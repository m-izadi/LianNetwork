<div dir="rtl">

# بعد از ریستارت — `weekilaw-com-front-ir` (`178.239.151.53`)

تانل داخلی (مسیر به `192.168.88.0/24`) بعد از ریستارت معمولاً به‌خاطر یکی از این‌ها قطع است:

1. سرویس **`sstp-ui5`** بالا نیامده / fail شده  
2. یا **`iran-routing`** دوباره mark خراب گذاشته (بدون KVM / بدون VM میکروTik)  
3. یا مسیر LAN روی `ppp` ست نشده

---

## تشخیص سریع (اول این را بزن)

```bash
# KVM هست؟
ls -l /dev/kvm

# سرویس‌ها
systemctl is-enabled iran-routing sstp-ui5 wg-quick@wg0 2>/dev/null
systemctl --no-pager --failed
systemctl status sstp-ui5 --no-pager
systemctl status iran-routing --no-pager

# اینترفیس و مسیر
ip -br a | grep -E 'ppp|wg|virbr|eth0'
ip route | grep -E '192\.168\.88|default|ppp|wg'
ping -c 2 192.168.90.1
ping -c 3 192.168.88.242
```

| نتیجه | معنی |
|--------|------|
| `/dev/kvm` نیست + `mikrotik` down | مسیر درست = **SSTP روی host** (`sstp-ui5`) |
| `ppp` نیست / ping به `.90.1` fail | تانل SSTP قطع → پایین را بزن |
| `iran-routing` failed ولی mark مانده | ترافیک خراب → بخش ۲ |

---

## مسیر A — حالت فعلی (بدون KVM): بالا آوردن SSTP

### ۱) قطع مسیر خراب

```bash
sudo systemctl disable --now iran-routing 2>/dev/null || true
sudo iptables -t mangle -F OUTPUT
sudo iptables -t mangle -F PREROUTING
sudo ip rule del fwmark 1 table iran-bypass 2>/dev/null || true
sudo pkill sstpc 2>/dev/null || true
```

### ۲) اگر سرویس از قبل نصب بود

```bash
# env و پسورد باید باشد
sudo test -f /etc/sstp/ui5-ir3.env && sudo cat /etc/sstp/ui5-ir3.env | sed 's/PASSWORD=.*/PASSWORD=***/'
ls -l /etc/systemd/system/sstp-ui5.service

sudo systemctl daemon-reload
sudo systemctl reset-failed sstp-ui5
sudo systemctl enable --now sstp-ui5
sleep 8
systemctl status sstp-ui5 --no-pager
ip -br a | grep ppp
ping -c 2 192.168.90.1
ping -c 3 192.168.88.242
```

اگر مسیر LAN نبود:

```bash
sudo ip route replace 192.168.88.0/24 via 192.168.90.1
ping -c 3 192.168.88.242
```

### ۳) اگر سرویس اصلاً نبود / خراب بود

از اول بساز — جزئیات کامل در [SIMPLE-SSTP.md](./SIMPLE-SSTP.md)

خلاصه:

- User میکروTik: **`ui5-ir3`**
- سرور: **`78.110.124.179:4443`**
- IP تونل کلاینت: **`192.168.90.172`**
- باینری: **`/usr/sbin/sstpc`** (نه `/usr/bin`)

```bash
which sstpc || sudo apt-get install -y sstp-client ppp
# سپس مراحل SIMPLE-SSTP.md (env + unit + enable --now)
```

### ۴) اگر `sstp-ui5` fail شد

```bash
journalctl -u sstp-ui5 -n 50 --no-pager
# رایج: پسورد غلط / AUTH_FAILED / مسیر اشتباه sstpc / پورت 4443 بسته
```

روی میکروTik چک کن session برای `ui5-ir3` برقرار باشد.

---

## مسیر B — اگر `/dev/kvm` برگشته (مسیر قدیمی)

```bash
ls -l /dev/kvm
sudo systemctl disable --now sstp-ui5 2>/dev/null || true
sudo ip route del 192.168.88.0/24 2>/dev/null || true
sudo pkill sstpc 2>/dev/null || true

sudo virsh net-start default 2>/dev/null || true
sudo virsh start mikrotik
ping -c 2 192.168.122.254

sudo systemctl enable --now iran-routing
ping -c 3 192.168.88.242
ip route get 192.168.88.242
```

انتظار: مسیر از `192.168.122.254` (VM میکروTik).

---

## WireGuard جدا (اگر برای Anthropic/egress استفاده می‌کردی)

این جدا از تانل LAN است. اگر لازم بود:

```bash
systemctl status wg-quick@wg0 --no-pager
sudo systemctl enable --now wg-quick@wg0
wg show
```

برای LAN شرکت (`192.168.88.x`) معمولاً **SSTP / iran-routing** لازم است، نه WG.

---

## چک‌لیست نهایی

```bash
systemctl is-active sstp-ui5          # active (بدون KVM)
systemctl is-enabled iran-routing     # disabled (بدون KVM)
ip -br a | grep ppp                   # ppp0 با IP
ping -c 3 192.168.88.242              # OK
```

| بدون KVM (الان) | با KVM |
|------------------|--------|
| `sstp-ui5` = enabled/active | `sstp-ui5` = disabled |
| `iran-routing` = disabled | `iran-routing` = enabled + VM `mikrotik` running |

</div>
