FROM nginx:alpine

RUN apk update && \
    apk add --no-cache openssl sudo bash && \
    rm -rf "/var/cache/apk/*"

COPY *.sh /root/
RUN chmod u+x /root/*.sh

COPY openssl.cnf /etc/ssl1.1/openssl.cnf