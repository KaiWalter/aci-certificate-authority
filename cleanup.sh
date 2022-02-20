#!/bin/sh

find /root/ca -name '*.pem' -print0 | xargs -0 rm -f
find /root/ca -name '*.pfx' -print0 | xargs -0 rm -f
find /root/ca -name '*.srl' -print0 | xargs -0 rm -f
