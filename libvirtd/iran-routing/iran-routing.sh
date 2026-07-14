#!/bin/bash

# ---------- Start default KVM network if not running ----------
if ! virsh net-info default >/dev/null 2>&1; then
    echo "Default network does not exist!"
    exit 1
fi

if ! virsh net-list --active | grep -q '^default'; then
    echo "Starting default KVM network..."
    virsh net-start default
fi

# ---------- Wait for virbr0 ----------
for i in $(seq 1 60); do
    ip link show virbr0 >/dev/null 2>&1 && break
    echo "Waiting for virbr0..."
    sleep 1
done

ip rule del fwmark 1 table iran-bypass 2>/dev/null || true
ip route flush table iran-bypass 2>/dev/null || true

for net in 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 172.17.0.0/16 172.18.0.0/16 172.19.0.0/16 172.25.0.0/16; do
    iptables -t mangle -C OUTPUT -d $net -j RETURN 2>/dev/null || \
    iptables -t mangle -I OUTPUT 1 -d $net -j RETURN
done

grep -q '^200 iran-bypass' /etc/iproute2/rt_tables || echo "200 iran-bypass" >> /etc/iproute2/rt_tables

ip route add default via 192.168.122.254 dev virbr0 src 192.168.122.1 table iran-bypass

iptables -t mangle -C OUTPUT -m set ! --match-set iran dst -j MARK --set-mark 1 2>/dev/null || \
iptables -t mangle -A OUTPUT -m set ! --match-set iran dst -j MARK --set-mark 1

# ---------- FORWARDED traffic (containers, bridges, etc) ----------
# 1) restore mark
iptables -t mangle -C PREROUTING \
  ! -i virbr0 \
  -j CONNMARK --restore-mark 2>/dev/null || \
iptables -t mangle -A PREROUTING \
  ! -i virbr0 \
  -j CONNMARK --restore-mark

# 2) mark non-IR
iptables -t mangle -C PREROUTING \
  ! -i virbr0 \
  -m set ! --match-set iran dst \
  -j MARK --set-mark 1 2>/dev/null || \
iptables -t mangle -A PREROUTING \
  ! -i virbr0 \
  -m set ! --match-set iran dst \
  -j MARK --set-mark 1

# 3) save mark
iptables -t mangle -C PREROUTING \
  ! -i virbr0 \
  -m mark --mark 1 \
  -j CONNMARK --save-mark 2>/dev/null || \
iptables -t mangle -A PREROUTING \
  ! -i virbr0 \
  -m mark --mark 1 \
  -j CONNMARK --save-mark

ip rule add fwmark 1 table iran-bypass prio 100

# ---------- Start all defined VMs ----------
for vm in $(virsh list --all --name); do
    if ! virsh domstate "$vm" | grep -q running; then
        echo "Starting VM: $vm"
        virsh start "$vm"
    fi
done
