#!/bin/bash

for i in $(seq 1 20); do
    ip link show virbr0 >/dev/null 2>&1 && break
    sleep 1
done

/sbin/ipset restore -exist < /etc/ipset.ir.conf || true

/sbin/ipset del iran 192.168.88.0/24 2>/dev/null || true

exit 0
