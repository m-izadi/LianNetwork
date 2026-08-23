# NAT برای کلاینت‌های WireGuard روی این egress

کلاینت‌ها (مثلاً `.33` = `10.20.1.2`، `.53` = `10.20.1.3`) بدون این دو مورد جواب API نمی‌گیرند:

```bash
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -s 10.20.1.0/24 -o enp0s7 -j MASQUERADE
iptables -A FORWARD -i wg0 -o enp0s7 -j ACCEPT
iptables -A FORWARD -i enp0s7 -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

Peer برای front: `AllowedIPs = 10.20.1.3/32`  
جزئیات کلاینت: `VMs/ParsPack/weekilaw-com-front-ir-151-53/wireguard-ai-apis/`
