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