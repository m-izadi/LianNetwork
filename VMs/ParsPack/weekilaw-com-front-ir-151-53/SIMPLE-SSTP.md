# weekilaw-com-front-ir (178.239.151.53) — SSTP ساده بعد از از دست رفتن KVM

همان مشکل back: بعد از ریستارت KVM نیست → VM `mikrotik` بالا نمی‌آید → `iran-routing` fail + mark خراب.

روی میکروTik: user **`ui5-ir3`** → IP تونل **`192.168.90.172`** → سرور `78.110.124.179:4443`

## همین الان روی سرور بزن

```bash
# ۱) توقف مسیر خراب
sudo systemctl disable --now iran-routing
sudo iptables -t mangle -F OUTPUT
sudo iptables -t mangle -F PREROUTING
sudo ip rule del fwmark 1 table iran-bypass 2>/dev/null || true
sudo pkill sstpc 2>/dev/null || true

# ۲) نصب sstpc اگر نبود
which sstpc || sudo apt-get install -y sstp-client ppp

# ۳) پسورد از میکروTik: /ppp secret print where name="ui5-ir3"
sudo mkdir -p /etc/sstp
sudo bash -c 'cat > /etc/sstp/ui5-ir3.env <<EOF
SSTP_USER=ui5-ir3
SSTP_PASSWORD=PUT_PASSWORD_HERE
EOF'
sudo chmod 600 /etc/sstp/ui5-ir3.env

# ۴) یک سرویس ساده
sudo tee /etc/systemd/system/sstp-ui5.service >/dev/null <<'EOF'
[Unit]
Description=SSTP ui5-ir3 (simple)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/sstp/ui5-ir3.env
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
sudo systemctl enable --now sstp-ui5
sleep 8
ip -br a | grep ppp
ping -c 2 192.168.90.1
ping -c 3 192.168.88.242
systemctl status sstp-ui5 --no-pager
```

## برگشت وقتی ParsPack دوباره KVM داد

```bash
ls -l /dev/kvm
sudo systemctl disable --now sstp-ui5
sudo virsh start mikrotik
ping -c 2 192.168.122.254
sudo systemctl enable --now iran-routing
ping -c 3 192.168.88.242
```
