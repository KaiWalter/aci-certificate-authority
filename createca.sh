#!/bin/sh

cd /root/ca

openssl req -new -x509 -days 9999 -keyout private/cakey.pem -out cacert.pem -subj "/C=XX/ST=YY/L=ZZ/O=Acme Corp/OU=CA/CN=dev.cloud.acmecorp.com"
