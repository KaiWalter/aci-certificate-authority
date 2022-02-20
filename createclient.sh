#!/bin/sh

cd /root/ca

openssl genrsa -out private/client1-key.pem 4096
openssl req -new -key private/client1-key.pem -out requests/client1-csr.pem -subj "/C=XX/ST=YY/L=ZZ/O=Acme Corp/OU=CA/CN=client1.dev.cloud.acmecorp.com"
openssl x509 -req -days 9999 -in requests/client1-csr.pem -CA cacert.pem -CAkey private/cakey.pem -CAcreateserial -out certs/client1-crt.pem
openssl verify -CAfile cacert.pem certs/client1-crt.pem
openssl pkcs12 -inkey private/client1-key.pem -in certs/client1-crt.pem -export -out client1.pfx
