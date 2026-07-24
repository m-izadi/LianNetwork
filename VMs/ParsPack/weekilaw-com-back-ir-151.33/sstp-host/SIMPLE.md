# روی سرور فقط این را بزن (یک‌بار)

```bash
# توقف چیزهای مزاحم
sudo systemctl disable --now iran-routing 2>/dev/null || true
sudo systemctl stop sstp-ui4 sstp-lan-routes 2>/dev/null || true
sudo pkill sstpc 2>/dev/null || true

# پاک کردن mark خراب
sudo iptables -t mangle -F OUTPUT
sudo iptables -t mangle -F PREROUTING
sudo ip rule del fwmark 1 table iran-bypass 2>/dev/null || true

# پسورد
sudo mkdir -p /etc/sstp
echo 'SSTP_USER=ui4-ir2' | sudo tee /etc/sstp/ui4-ir2.env
echo 'SSTP_PASSWORD=YOUR_PASS' | sudo tee -a /etc/sstp/ui4-ir2.env
sudo chmod 600 /etc/sstp/ui4-ir2.env

# یک سرویس ساده
sudo tee /etc/systemd/system/sstp-ui4.service >/dev/null <<'EOF'
[Unit]
Description=SSTP ui4-ir2 (simple)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/sstp/ui4-ir2.env
ExecStartPre=-/sbin/ip rule del fwmark 1 table iran-bypass
ExecStartPre=-/sbin/iptables -t mangle -F OUTPUT
ExecStartPre=-/sbin/iptables -t mangle -F PREROUTING
ExecStart=/usr/sbin/sstpc --log-stderr --cert-warn --user ${SSTP_USER} --password ${SSTP_PASSWORD} 78.110.124.179:4443 usepeerdns require-mschap-v2 noauth
ExecStartPost=/bin/sleep 5
ExecStartPost=/sbin/ip route replace 192.168.88.0/24 via 192.168.90.1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl reset-failed sstp-ui4
sudo systemctl disable sstp-lan-routes 2>/dev/null || true
sudo systemctl enable --now sstp-ui4

sleep 8
ip -br a | grep ppp
ping -c 3 192.168.88.242
```

`YOUR_PASS` را با پسورد واقعی عوض کن.

تست:
```bash
systemctl status sstp-ui4 --no-pager
ping -c 2 192.168.90.1
ping -c 3 192.168.88.242
```
