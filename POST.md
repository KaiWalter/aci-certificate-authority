---
title: Creating a Certificate Authority for testing with Azure Container Instances
published: false
description: This post shows how to create and spin up a temporary container with openssl to create certificates for various non-production scenarios.
tags: #azure #containers #certificate #security
cover_image: https://dev-to-uploads.s3.amazonaws.com/uploads/articles/7u9d418mr2lutrhcktm8.png
---

## Motivation

To test mutual TLS for a scenario with [Application Gateway](https://docs.microsoft.com/en-us/azure/application-gateway/mutual-authentication-overview) I required a disposable environment which easily allows me to create a CA chain as well as client certificates

- to figure out the right certificate request with our corporate CA and with that saving needless iterations - a common error shown when not requesting the right kind of (client) certificate:  `FAILED:unhandled critical extension`
- without Application Gateway telling me `FAILED:self signed certificate` - that is does not accept self-signed certificates for mutual TLS

## Setup

The idea is to create an on demand temporary container with [Azure Container Instances](https://azure.microsoft.com/en-us/services/container-instances/#overview) with [**openssl**](https://www.openssl.org/) under the hood but persisting issued certificates and keys on Azure File Storage so that these can be downloaded into the target environment or re-used for another time when running the aforementioned container.

### Dockerfile

It starts with a `Dockerfile` which installs `openssl` as well as `sudo` and `bash` for good measure. I chose [**nginx**](https://nginx.org/en/) because I might need to process HTTP(s) requests later with the same container. I add the desired **openssl configuration** and some **shell scripts** which help with repetitive tasks on the container.

```Dockerfile
FROM nginx:alpine

RUN apk update && \
  apk add --no-cache openssl sudo bash && \
  rm -rf "/var/cache/apk/*"

COPY *.sh /root/
RUN chmod u+x /root/*.sh

COPY openssl.cnf /etc/ssl1.1/openssl.cnf
```

### openssl.cnf

The configuration I use is based on [the default](https://github.com/openssl/openssl/blob/master/apps/openssl.cnf) - only with `dir` adjusted to the folder where I will operate the **CA** later:

```text
...
dir      = /root/ca       # Where everything is kept
certs    = $dir/certs     # Where the issued certs are kept
crl_dir  = $dir/crl       # Where the issued crl are kept
database = $dir/index.txt # database index file.
#unique_subject = no   # Set to 'no' to allow creation of
                       # several certs with same subject.
new_certs_dir = $dir/newcerts  # default place for new certs.

certificate = $dir/cacert.pem # The CA certificate
serial      = $dir/serial     # The current serial number
crlnumber   = $dir/crlnumber  # the current crl number
                              # must be commented out to leave a V1 CRL
crl  = $dir/crl.pem           # The current CRL
private_key = $dir/private/cakey.pem# The private key
...
```

> for later signing settings like `certificate = $dir/cacert.pem` and `private_key = $dir/private/cakey.pem` are crucial, as openssl expects those file exactly at the configured location

### prepare.sh

This script is used to initially setup the `/root/ca` folder when the container is started and when this folder is mounted to Azure File Storage.

```shell
#!/bin/sh

cd /root/ca

chmod 600 -R /root/ca

mkdir -p /root/ca/certs
mkdir -p /root/ca/crl
mkdir -p /root/ca/newcerts
mkdir -p /root/ca/private
mkdir -p /root/ca/requests

touch index.txt

if [ ! -f "serial" ]
then
    echo '01' > serial
fi

ls -lh
```

### cleanup.sh

Remove already created certificate files from `/root/ca` to start over again:

```shell
#!/bin/sh

find /root/ca -name '*.pem' -print0 | xargs -0 rm -f
find /root/ca -name '*.pfx' -print0 | xargs -0 rm -f
find /root/ca -name '*.srl' -print0 | xargs -0 rm -f
```

### createca.sh

Create the Certificate Authority certificate with the corresponding private key:

> for `/C=XX/ST=YY/L=ZZ/O=Acme Corp/OU=CA/CN=dev.cloud.acmecorp.com` a sensible subject specification needs to be provided

```shell
#!/bin/sh

cd /root/ca

openssl req -new -x509 -days 9999 -keyout private/cakey.pem -out cacert.pem -subj "/C=XX/ST=YY/L=ZZ/O=Acme Corp/OU=CA/CN=dev.cloud.acmecorp.com"
```

### createclient.sh

Create a sample client certificate with a private key, sign and verify this certificate:

```shell
#!/bin/sh

cd /root/ca

openssl genrsa -out private/client1-key.pem 4096
openssl req -new -key private/client1-key.pem -out requests/client1-csr.pem -subj "/C=XX/ST=YY/L=ZZ/O=Acme Corp/OU=CA/CN=client1.dev.cloud.acmecorp.com"
openssl x509 -req -days 9999 -in requests/client1-csr.pem -CA cacert.pem -CAkey private/cakey.pem -CAcreateserial -out certs/client1-crt.pem
openssl verify -CAfile cacert.pem certs/client1-crt.pem
openssl pkcs12 -inkey private/client1-key.pem -in certs/client1-crt.pem -export -out client1.pfx
```

### setup.ps1 - create storage and share

The environment with Container Registry and Storage account is created with `setup.ps1`:

```Powershell
$resourceGroupName = "myrg"
$location = "westeurope"

$registryName = "mycaserveracr"
$storageAccountName = "mycastorage"
$storageAccountShareName = "cashare"

$resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if (!$resourceGroup) {
    New-AzResourceGroup -Name $resourceGroupName -Location $location
}

$registry = Get-AzContainerRegistry -Name $registryName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (!$registry) {
    New-AzContainerRegistry -Name $registryName -ResourceGroupName $resourceGroupName -EnableAdminUser -Sku Standard
}

$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (!$storageAccount) {
    New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName -Location $location -SkuName Standard_GRS
    $storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName -ErrorAction Stop
}

$storageAccountKey = (Get-AzStorageAccountKey -Name $storageAccountName -ResourceGroupName $resourceGroupName)[0].Value
$stoCtx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

$stoShare = Get-AzStorageShare -Name $storageAccountShareName -Context $stoCtx -ErrorAction SilentlyContinue
if (!$stoShare) {
    New-AzStorageShare -Name $storageAccountShareName -Context $stoCtx
    $stoShare = Get-AzStorageShare -Name $storageAccountShareName -Context $stoCtx -ErrorAction Stop
}
```

### build.ps1 - build and push the container

With this **Powershell** script the container is build directly on a **Azure Container Registry** (with Admin account enabled):

```Powershell
$resourceGroupName = "myrg"
$registryName = "mycaserveracr"

$registry = Get-AzContainerRegistry -Name $registryName -ResourceGroupName $resourceGroupName
$tag = Get-Date -AsUTC -Format yyMMdd_HHmmss
$imagePrefix = "ca-server"
$image = "$($registry.LoginServer)/$($imagePrefix):$tag"

az acr build -t $image -r $registryName $PSScriptRoot
```

> I use Azure CLI for the container build here as a similar command seems not available for Azure PowerShell

### run.ps1 - execute container

When all resources are in place, one script can be used to start the container, mount it to the file share and shell into the container to do the actual certificate operations:

```Powershell
$resourceGroupName = "myrg"
$registryName = "mycaserveracr"

$registry = Get-AzContainerRegistry -Name $registryName -ResourceGroupName $resourceGroupName
$tag = Get-Date -AsUTC -Format yyMMdd_HHmmss
$imagePrefix = "ca-server"
$image = "$($registry.LoginServer)/$($imagePrefix):$tag"

az acr build -t $image -r $registryName $PSScriptRoot
```

> replacing ACI location `germanywestcentral` with `westeurope` : issue is a **failed exec command** that only occurs when the deployment is **on Atlas**, it works in other regions on k8s; `germanywestcentral` is an Atlas-only region

----

## Execution

To make the basic environment available adjust resource names in above mentioned scripts and execute:

```Powershell
./setup.ps1
./build.ps1
```

Then - or whenever required - start the environment with:

```Powershell
./run.ps1
```

When the container is started and shell apperas, switch to **su**, change to root home and prepare the folders:

```shell
bash-5.1# su
/ # cd ~
~ # ./prepare.sh
total 1K
drwxrwxrwx    2 root     root           0 Feb 20 18:31 certs
drwxrwxrwx    2 root     root           0 Feb 20 18:31 crl
-rwxrwxrwx    1 root     root           0 Feb 20 18:31 index.txt
drwxrwxrwx    2 root     root           0 Feb 20 18:31 newcerts
drwxrwxrwx    2 root     root           0 Feb 20 18:31 private
drwxrwxrwx    2 root     root           0 Feb 20 18:31 requests
-rwxrwxrwx    1 root     root           3 Feb 20 18:31 serial
```

Now CA certificate and key can be created:

```shell
~ # ./createca.sh
Generating a RSA private key
.......................................................+++++
..............+++++
writing new private key to 'private/cakey.pem'
Enter PEM pass phrase:
Verifying - Enter PEM pass phrase:
-----
```

From that client certificate can be created:

```shell
~ # ./createclient.sh
Generating RSA private key, 4096 bit long modulus (2 primes)
.....................................................................................................................++++
.....................................................................................................................................................................................................++++
e is 65537 (0x010001)
Signature ok
subject=C = XX, ST = YY, L = ZZ, O = Acme Corp, OU = CA, CN = client1.dev.cloud.acmecorp.com
Getting CA Private Key
Enter pass phrase for private/cakey.pem:
certs/client1-crt.pem: OK
Enter Export Password:
Verifying - Enter Export Password:
```

Files created:

```shell
~ # find /root/ca -name '*.pem'
/root/ca/cacert.pem
/root/ca/certs/client1-crt.pem
/root/ca/private/cakey.pem
/root/ca/private/client1-key.pem
/root/ca/requests/client1-csr.pem
~ # find /root/ca -name '*.pfx'
/root/ca/client1.pfx
~ # find /root/ca -name '*.srl'
/root/ca/cacert.srl
```
