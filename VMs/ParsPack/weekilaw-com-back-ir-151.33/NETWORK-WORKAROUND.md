<div dir="rtl">

# weekilaw-com-back-ir (`178.239.151.33`) — وضعیت شبکه و ماندگاری

## چه اتفاقی افتاد؟

بعد از ریستارت (حدود ۲۲ جولای ۲۰۲۶):

1. **KVM / nested virtualization** روی این VPS از کار افتاد (`/dev/kvm` نیست).
2. VM محلی **`mikrotik`** دیگر بالا نمی‌آید.
3. سرویس **`iran-routing`** fail می‌شود ولی قبلش قوانین `fwmark → table iran-bypass → 192.168.122.254` را می‌گذارد.
4. با `virbr0` مرده، ترافیک به `192.168.88.x` Unreachable می‌شود.
5. با `systemctl disable --now iran-routing` و حذف `fwmark`، مسیر **SSTP مستقیم روی host** (`ppp0` / `ui4-ir2`) کار کرد.

### حالت قبلی (هدف نهایی — وقتی ParsPack KVM بدهد)

```text
host → iran-routing → 192.168.122.254 (VM mikrotik) → SSTP → شرکت → 192.168.88.242
```

### حالت موقت فعلی (workaround)

```text
host → sstpc (ppp0, 192.168.90.171) → 78.110.124.179:4443 → 192.168.88.242
iran-routing = DISABLED
```

---

## ماندگار کردن وضعیت فعلی (روی سرور بزن)

فایل‌های نمونه در پوشهٔ [`sstp-host/`](./sstp-host/) هستند. روی سرور کپی و enable کن.

### ۱) iran-routing خاموش بماند

```bash
sudo systemctl disable --now iran-routing
systemctl is-enabled iran-routing   # باید disabled باشد
```

اگر قبلاً mark مانده:

```bash
sudo ip rule del fwmark 1 table iran-bypass 2>/dev/null || true
sudo iptables -t mangle -F OUTPUT
sudo iptables -t mangle -F PREROUTING
# اگر iptables-persistent دارید و mark ذخیره شده، بعد از پاک کردن:
sudo netfilter-persistent save 2>/dev/null || sudo iptables-save > /etc/iptables/rules.v4
```

### ۲) اعتبار SSTP (روی سرور — در git نگذار)

```bash
sudo mkdir -p /etc/sstp
sudo tee /etc/sstp/ui4-ir2.secrets >/dev/null <<'EOF'
ui4-ir2
PASSWORD_FROM_MIKROTIK
EOF
sudo chmod 600 /etc/sstp/ui4-ir2.secrets
```

User میکروTik: **`ui4-ir2`** — سرور: **`78.110.124.179:4443`** — IP تونل: **`192.168.90.171`**.

### ۳) نصب واحدها از این repo

**مهم:** روی Ubuntu باینری `sstpc` در **`/usr/sbin/sstpc`** است (نه `/usr/bin`). اگر در لاگ دیدی `No such file or directory` برای `/usr/bin/sstpc`، unit قدیمی است — فایل زیر را دوباره کپی کن.

فایل env:

```bash
sudo tee /etc/sstp/ui4-ir2.env >/dev/null <<'EOF'
SSTP_USER=ui4-ir2
SSTP_PASSWORD=CHANGE_ME
EOF
sudo chmod 600 /etc/sstp/ui4-ir2.env
```

```bash
# روی سرور، بعد از کپی فایل‌های sstp-host/
sudo cp sstp-ui4.service /etc/systemd/system/
sudo cp sstp-lan-routes.service /etc/systemd/system/
sudo cp sstp-lan-routes.sh /usr/local/bin/
sudo chmod 755 /usr/local/bin/sstp-lan-routes.sh

# پاک کردن markهای باقی‌مانده از iran-routing
sudo iptables -t mangle -F OUTPUT
sudo iptables -t mangle -F PREROUTING
sudo ip rule del fwmark 1 table iran-bypass 2>/dev/null || true

sudo systemctl daemon-reload
sudo systemctl reset-failed sstp-ui4
sudo systemctl enable --now sstp-ui4.service
sudo systemctl restart sstp-lan-routes.service
```
### ۴) تست بعد از reboot آزمایشی

```bash
sudo reboot
# بعد از بالا آمدن:
ip -br a | grep ppp
ping -c 2 192.168.90.1
ping -c 3 192.168.88.242
systemctl is-enabled iran-routing   # disabled
```

### ۵) OpenVPN host را استفاده نکن

`openvpn-client@office` را disable نگه دار (قبلاً default route را خراب کرد). فایل `office.conf.old` را دست نزن مگر برای آرشیو.

---

## برگشت به حالت قبل (بعد از فعال شدن KVM توسط ParsPack)

### ۱) تأیید KVM

```bash
ls -l /dev/kvm
egrep -c 'vmx|svm' /proc/cpuinfo
lsmod | grep kvm
```

اگر `/dev/kvm` نبود → هنوز به ParsPack تیکت بزن؛ برنگردان.

### ۲) خاموش کردن workaround SSTP روی host

```bash
sudo systemctl disable --now sstp-lan-routes.service
sudo systemctl disable --now sstp-ui4.service
sudo ip route del 192.168.88.0/24 2>/dev/null || true
# اگر ppp0 مانده:
sudo poff -a 2>/dev/null || true
sudo pkill sstpc 2>/dev/null || true
```

روی میکروTik اصلی نباید هم‌زمان دو session گیج‌کننده بماند؛ بعد از قطع host-SSTP، session داخل VM با `ui4-ir2` می‌آید.

### ۳) روشن کردن مسیر قدیمی

```bash
sudo ip link set virbr0 up
sudo virsh net-start default 2>/dev/null || true
sudo virsh start mikrotik
ping -c 2 192.168.122.254

sudo systemctl enable --now iran-routing
sudo systemctl status iran-routing --no-pager

ip route get 192.168.88.242
traceroute -n -m 5 192.168.88.242
ping -c 3 192.168.88.242
```

انتظار شبیه `178.239.151.53`:

```text
1  192.168.122.254
2  192.168.90.1
3  192.168.88.242
```

### ۴) اگر `iran-routing` باز به خاطر `virsh net-list --active` گیر کرد

نسخهٔ virsh این سرور گزینهٔ `--active` را ندارد. موقتاً:

```bash
sudo sed -i 's/virsh net-list --active/virsh net-list --name/' /usr/local/bin/iran-routing.sh
# یا اسکریپت را با نسخهٔ اصلاح‌شدهٔ repo عوض کن (بدون --active)
```

و حلقهٔ start VM را طوری نگذار که بدون KVM کل سرویس fail شود — وقتی KVM برگشت دیگر لازم نیست.

---

## چک‌لیست سریع

| وضعیت | iran-routing | sstp-ui4 | VM mikrotik |
|--------|--------------|----------|-------------|
| **الان (بدون KVM)** | disabled | enabled | shut off |
| **بعد از KVM** | enabled | disabled | running |

</div>
