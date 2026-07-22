<div dir="rtl">

# راهنمای عملی — مسیریابی، تونل، virbr0

سند جدا برای **فهم کانفیگ واقعی** و **دستورات inspect**.  
برای دیاگرام کلی → [weekilaw-network.drawio](./weekilaw-network.drawio)

---

## ۱. مسیر ترافیک (خلاصه)

```
ماشین (ParsPack یا دیتاسنتر)
    │
    ├─ مقصد ایرانی ──────────────────► اینترنت ایران (مستقیم)
    │
    └─ مقصد خارجی ──► [لایه host] ──► میکروTik (192.168.122.254)
                           │              │
                           │              ├─ SSTP (hs)
                           │              └─ L2TP (tun2-L2)
                           │                      │
                           └──────────────────────┘
                                      │
                                      ▼
                            VPS فرانسه 202.133.88.39
                                      │
                                      ▼
                            اینترنت (curl ipconfig.io)
```

**سه لایه کانفیگ:**

| لایه | کجا | کار |
|------|-----|-----|
| **A. host** | Linux روی سرور | تشخیص ایران/خارج (`ipset`) + فرستادن خارجی به GW میکروTik |
| **B. میکروTik** | RouterOS | تونل SSTP/L2TP به فرانسه + OpenVPN برای LAN داخلی |
| **C. فرانسه** | VPS | NAT egress → IP عمومی `202.133.88.39` |

---

## ۲. virbr0 چیست؟

**virbr0** = bridge پیش‌فرض **libvirt/KVM** روی همان سرور Linux.

| مورد | توضیح |
|------|--------|
| **چیست** | سوئیچ مجازی برای VMهای libvirt |
| **IP معمول** | `192.168.122.1/24` روی host |
| **Gateway مهم** | **`192.168.122.254`** = میکروTik داخل VM (`vm-mik`) — **فقط روی hypervisor دیتاسنتر** |
| **روی ParsPack** | همان نام و subnet ولی **جدا** — به دیتاسنتر وصل نیست مگر route VPN بدهد |
| **Docker** | `docker0` و `br-*` جدا از virbr0 هستند |

**در دیتاسنتر:** اسکریپت `iran-routing.sh` ترافیک خارجی را به `192.168.122.254` (میکروTik VM) می‌فرستد.

---

## ۳. لایه A — split routing روی Linux (دیتاسنتر)

### فایل‌های شناخته‌شده در repo

| فایل | نقش |
|------|-----|
| `/usr/local/bin/ipset-iran.sh` | بارگذاری لیست IP ایران |
| `/usr/local/bin/iran-routing.sh` | mark + route table `iran-bypass` |
| `/etc/systemd/system/ipset-iran.service` | سرویس ipset |
| `/etc/systemd/system/iran-routing.service` | سرویس routing |
| `/etc/ipset.ir.conf` | داده ipset |
| `/etc/iproute2/rt_tables` | خط `200 iran-bypass` |

### منطق (از اسکریپت repo)

1. مقصد در ipset `iran` → مسیر عادی (اینترنت ایران)
2. مقصد **خارج** از ipset → `mark 1` → table `iran-bypass` → `default via 192.168.122.254 dev virbr0`
3. ترافیک Docker/forward هم با iptables mangle mark می‌شود

### دستورات — روی hypervisor دیتاسنتر (مثلاً `178.239.151.53` یا host فیزیکی)

```bash
# وضعیت سرویس‌ها
systemctl status ipset-iran iran-routing libvirtd

# virbr0 و gateway
ip -br a show virbr0
ip route show table iran-bypass
ip rule list

# مسیر یک IP خارجی / ایرانی
ip route get 8.8.8.8
ip route get 217.218.61.230

# mark و iptables
iptables -t mangle -L OUTPUT -n -v | head -25
iptables -t mangle -L PREROUTING -n -v | head -25
ipset list iran | head -20
ipset list iran | wc -l

# libvirt — شبکه default
virsh net-list --all
virsh net-dumpxml default

# VM میکروTik
virsh list --all
virsh domifaddr <name-mikrotik-vm> 2>/dev/null

# تست egress
curl -4 ipconfig.io ; echo
```

---

## ۴. لایه B — میکروTik

**مهم:** سه نوع VPN روی میکروTik **جدا** هستند — قاطی نکن:

| نوع | اینترفیس | جهت | نقش | egress |
|-----|----------|-----|-----|--------|
| **L2TP Client** | `tun2-L2` | میکروTik → France | خروج بین‌الملل | `202.133.88.39` |
| **SSTP Client** | `hs` | میکروTik → France | خروج بین‌الملل (پشتیبان/موازی) | `202.133.88.39` |
| **OpenVPN Server** | `ovpn-server` | ParsPack → میکروTik | دسترسی LAN / بکاپ | ❌ نه egress |
| **OpenVPN Client** | `ovpn-client` | میکروTik → بیرون | احتمالاً USA — **جدا از France** | ممکن است آمریکا |

ترافیک `curl ipconfig.io` از **L2TP/SSTP به France** می‌رود، نه از OpenVPN.

---

### ۴.۱. کانفیگ France — کجای Winbox؟

**مسیر منو (RouterOS):**

| تنظیم | Winbox | Terminal |
|-------|--------|----------|
| L2TP به France | PPP → L2TP Client → **`tun2-L2`** | `/interface l2tp-client print detail` |
| SSTP به France | PPP → SSTP Client → **`hs`** | `/interface sstp-client print detail` |
| user/password تونل | PPP → Secrets | `/ppp secret print` |
| مسیریابی France | IP → Routes (table **`route2fr`**) | `/routing table print` |
| قوانین routing | Routing → Rules | `/routing rule print` |
| NAT بعد از تونل | IP → Firewall → NAT | `/ip firewall nat print` |
| OpenVPN ورودی (ParsPack) | PPP → OVPN Server | `/interface ovpn-server server print` |
| OpenVPN خروجی (USA?) | PPP → OVPN Client | `/interface ovpn-client print` |

**IP سرور France (از credentials پروژه):**

| سرور | IP | user | pass |
|------|-----|------|------|
| France 2 (فعال) | `202.133.88.39` | root | `WklWkl@link2` |
| France 1 (پشتیبان) | `202.133.88.239` | root | `WklWkl@link1` |

> رمزها را در chat/email عمومی نفرست — فقط برای inspect داخلی.

**چک سریع — آیا L2TP به France وصل است:**

```routeros
/interface l2tp-client print detail
/interface sstp-client print detail
/ppp active print
/ping 8.8.8.8 routing-table=route2fr
```

---

### ۴.۲. چرا OpenVPN «به آمریکا» به نظر می‌رسد؟

احتمالاً **دو کانال موازی** داری:

```
ParsPack ──OpenVPN──► میکروTik (ovpn-server)     → فقط LAN / 192.168.88.x
                              │
ماشین‌ها ──L2TP/SSTP──► (از میکروTik) ──► France → curl ipconfig.io
                              │
میکروTik ──ovpn-client──► USA (144.172.x.x)?     → مسیر جدا — شاید سرویس خاص
```

- **OpenVPN Server** روی میکروTik: برای **ورود** VPSها به شبکهٔ داخلی — معمولاً route فقط subnet داخلی push می‌شود، نه default به France.
- **OpenVPN Client** روی میکروTik (`ovpn-client` در backup): ممکن است تونل **خروجی به USA** باشد — جدا از L2TP France.
- در README پروژه VPS USA: `144.172.91.114` با برچسب «USA for vpn».

**تأیید روی میکروTik:**

```routeros
/interface ovpn-client print detail
/ip route print where gateway~"ovpn"
```

**تأیید روی VPS ParsPack:**

```bash
# OpenVPN فقط LAN است یا default route هم می‌دهد؟
grep -E 'redirect-gateway|route|pull' ~/vpn/*.ovpn 2>/dev/null
ip route get 192.168.88.242
ip route get 8.8.8.8
```

اگر `8.8.8.8` از `tun0` نمی‌رود ولی `192.168.88.x` می‌رود → OpenVPN فقط LAN است و egress از L2TP/SSTP است ✅

---

### ۴.۳. درخواست «کانفیگ VPN L2TP شرکت» — یعنی چی؟

معمولاً یکی از این دو معنی را دارد:

| معنی | چه کسی می‌خواهد | چه چیزی بفرست |
|------|-----------------|---------------|
| **A. اتصال به VPN شرکت** | کارمند / سرور جدید / پیمانکار | تنظیمات **L2TP Server** میکروTik (یا Windows/Android L2TP) |
| **B. مستندسازی egress** | تیم فنی / جایگزین تو | تنظیمات **L2TP Client** میکروTik به France (`tun2-L2`) |

**قبل از ارسال — از درخواست‌کننده بپرس:**

> «منظورتون L2TP برای **اتصال به شبکهٔ شرکت** است یا کانفیگ **خروج به France** روی میکروTik؟»

---

#### اگر معنی A — کاربر جدید به VPN شرکت

روی میکروTik جمع کن:

```routeros
/interface l2tp-server server print
/interface l2tp-server print
/ppp profile print
/ppp secret print where service=l2tp
/ip ipsec peer print
/ip ipsec proposal print
/ip firewall filter print where dst-port=1701,500,4500
/ip address print
```

**چیزهایی که معمولاً لازم است (بدون رمز در email ناامن):**

- IP عمومی میکروTik: `78.110.124.179`
- نوع: L2TP over IPsec
- IPsec PSK (pre-shared key)
- username / password (یا بگو جدا بفرستند)
- subnet داخلی بعد از connect (مثلاً `192.168.90.x`)

**روی Windows/macOS/Android:** راهنمای L2TP/IPsec با همان PSK و user.

---

#### اگر معنی B — مستند egress France

```routeros
/interface l2tp-client print detail
/ppp secret print where name~"tun2"
/routing rule print where table=route2fr
/ip route print where routing-table=route2fr
```

خروجی export (بدون password):

```routeros
/export file=l2tp-france-doc
```

---

### ۴.۴. چک‌لیست کاری برای تو (DevOps جدید)

1. Winbox → `/interface l2tp-client print detail` → IP France را یادداشت کن
2. `/ppp active print` → session فعال L2TP/SSTP
3. `/interface ovpn-client print` → آیا USA جداست؟
4. از درخواست‌کننده L2TP بپرس: **A** (ورود به شرکت) یا **B** (France egress)
5. تا تأیید admin — **password/PSK در تلگرام/email عمومی نفرست**
6. export بگیر: `/export file=handover-$(date).rsc`

### دستورات — Winbox Terminal یا SSH

```routeros
# تونل‌های فعال
/interface print stats
/ppp active print detail
/ppp secret print

# SSTP / L2TP — آدرس سرور فرانسه اینجاست
/interface sstp-client print detail
/interface l2tp-client print detail

# مسیری که ترافیک خارجی می‌رود
/routing table print
/ip route print detail where dst-address=0.0.0.0/0
/routing rule print

# OpenVPN (دسترسی LAN — جدا از egress)
/interface ovpn-server server print
/interface ovpn-server print
/ppp secret print where service=ovpn

# NAT و firewall مرتبط VPN
/ip firewall nat print
/ip firewall filter print where comment~"VPN"
/ip firewall mangle print

# export کامل (بهترین راه برای دیدن همه چیز)
/export file=inspect-config
```

فایل export در **Files** میکروTik ظاهر می‌شود — دانلود کن و در repo بگذار (بدون password).

---

## ۵. لایه C — VPS فرانسه (`202.133.88.39`)

NAT egress — `curl ipconfig.io` همه جا این IP را نشان می‌دهد.

### دستورات

```bash
# سرویس VPN (SSTP/L2TP/strongSwan/xl2tp)
ss -tulnp
systemctl list-units | grep -iE 'sstp|l2tp|xl2tp|strongswan|pppd|accel'

# NAT
iptables -t nat -L -n -v
iptables -t nat -S

# interface و route
ip -br a
ip route

# لاگ اتصال
journalctl -u xl2tpd -n 50 2>/dev/null
journalctl -u strongswan -n 50 2>/dev/null
grep -i vpn /var/log/syslog 2>/dev/null | tail -30
```

---

## ۶. ParsPack — تونل و مسیریابی

روی VPSها **دو موضوع جدا** است:

| موضوع | احتمال | کجا ببین |
|--------|--------|----------|
| دسترسی به LAN دیتاسنتر | OpenVPN client | `~/vpn/`, `tun0` |
| egress بین‌الملل | via میکروTik یا مستقیم | `ip route get 8.8.8.8` |

### دستورات — روی هر VPS ParsPack

```bash
hostname ; curl -4 ipconfig.io ; echo

ip -br a
ip route show
ip rule list

# مسیر دقیق
ip route get 8.8.8.8
ip route get 192.168.88.242

# تونل‌ها
ip -br a show type tun
ip -br a show type wg
systemctl list-units --type=service | grep -iE 'openvpn|wg|vpn|xl2tp|strongswan'

# OpenVPN (web احتمالاً دارد)
ls -la ~/vpn/ /etc/openvpn/ 2>/dev/null
grep -E '^(remote|dev|route|redirect-gateway|pull)' ~/vpn/*.ovpn 2>/dev/null

# WireGuard
wg show 2>/dev/null
ls -la /etc/wireguard/ 2>/dev/null

# split routing مشابه دیتاسنتر؟
systemctl status ipset-iran iran-routing 2>/dev/null
ls -la /usr/local/bin/iran-routing.sh /usr/local/bin/ipset-iran.sh 2>/dev/null
iptables -t mangle -L -n -v 2>/dev/null | head -20

# virbr0 محلی (معمولاً فقط libvirt)
virsh net-list --all 2>/dev/null
ip addr show virbr0

# Docker (جدا از تونل egress)
docker network ls
```

### web (`130.185.75.96`) — اضافه

```bash
ls -la ~/sync_tool/
crontab -l | grep -i sync
```

---

## ۷. چطوری بفهمم ترافیک از کجا می‌رود؟

این جدول را بعد از دستورات پر کن:

| دستور | خروجی مورد انتظار | معنی |
|--------|-------------------|------|
| `curl ipconfig.io` | `202.133.88.39` | egress از فرانسه |
| `ip route get 8.8.8.8` | `via 192.168.122.254 dev virbr0` | host → میکروTik VM |
| `ip route get 8.8.8.8` | `dev tun0` | مستقیم OpenVPN (کمتر محتمل برای egress) |
| `ip -br a show type tun` | `tun0 UP` | کلاینت VPN فعال |
| میکروTik `/ppp active` | session به `202.133.88.39` | تونل France فعال |

---

## ۸. عوض کردن سرور فرانسه — checklist

### مرحله ۱ — VPS جدید

1. VPS جدید (مثلاً آلمان/فرانسه) با IP ثابت
2. نصب همان پروتکل فعلی (**SSTP و/یا L2TP** — از `/interface sstp-client print` و `/interface l2tp-client print` بفهم کدام استفاده می‌شود)
3. NAT masquerade برای clientهای VPN
4. user/password مثل `ppp secret` فعلی

### مرحله ۲ — میکروTik (اصلی‌ترین تغییر)

```routeros
# قبل از تغییر — backup
/system backup save name=before-france-change

# SSTP — آدرس سرور را عوض کن
/interface sstp-client set hs connect-to=NEW.IP.ADDRESS

# L2TP — همین‌طور
/interface l2tp-client set tun2-L2 connect-to=NEW.IP.ADDRESS

# اگر user/pass عوض شد
/ppp secret set [find name=...] password=...

# تست
/ping 8.8.8.8
/ppp active print
```

5. routing table `route2fr` — route default را چک کن
6. firewall NAT — مطمئن شو ترافیک VPN out می‌شود

### مرحله ۳ — hostهای Linux (دیتاسنتر)

اگر فقط GW `192.168.122.254` است → **معمولاً نیازی به تغییر نیست** (میکروTik وسط است).

اگر روی ParsPack route مستقیم به France بود → route/OpenVPN remote را عوض کن.

### مرحله ۴ — تست

```bash
# روی هر ماشین
curl -4 ipconfig.io
traceroute -n 8.8.8.8
ping -c 3 8.8.8.8
```

### مرحله ۵ — France قدیمی

بعد از تأیید همه ماشین‌ها → سرویس VPN روی `202.133.88.39` را خاموش یا نگه دار برای rollback.

---

## ۹. فایل‌ها و مسیرهای مهم (چک‌لیست)

| محل | مسیرهای رایج |
|-----|--------------|
| Linux routing | `/usr/local/bin/iran-routing.sh`, `/etc/systemd/system/iran-routing.service` |
| ipset | `/etc/ipset.ir.conf`, `/usr/local/bin/ipset-iran.sh` |
| OpenVPN client | `~/vpn/*.ovpn`, `/etc/openvpn/client/` |
| WireGuard | `/etc/wireguard/wg0.conf` |
| libvirt | `virsh net-dumpxml default`, `/etc/libvirt/qemu/networks/` |
| netplan | `/etc/netplan/*.yaml` |
| cron/sync | `crontab -l`, `~/sync_tool/` |
| MikroTik | `/export file=...` |
| France | `/etc/xl2tpd/`, `/etc/ipsec.conf`, `iptables-save` |

---

## ۱۰. یک اسکریپت جمع‌آوری (اختیاری)

روی هر Linux سرور بزن — خروجی را save کن:

```bash
OUT=~/network-inspect-$(hostname)-$(date +%F).txt
{
  echo "=== $(hostname) $(date) ==="
  echo "--- ipconfig.io ---"
  curl -4 -s --max-time 10 ipconfig.io ; echo
  echo "--- ip -br a ---"
  ip -br a
  echo "--- ip route ---"
  ip route show
  echo "--- ip rule ---"
  ip rule list
  echo "--- route get 8.8.8.8 ---"
  ip route get 8.8.8.8
  echo "--- route get 192.168.88.242 ---"
  ip route get 192.168.88.242 2>&1
  echo "--- tun/wg ---"
  ip -br a show type tun 2>/dev/null
  wg show 2>/dev/null
  echo "--- systemd vpn/routing ---"
  systemctl is-active ipset-iran iran-routing openvpn wg-quick@wg0 2>/dev/null
  echo "--- mangle (head) ---"
  iptables -t mangle -L -n -v 2>/dev/null | head -30
  echo "--- virbr0 ---"
  ip addr show virbr0 2>/dev/null
  virsh net-list --all 2>/dev/null
  echo "--- openvpn files ---"
  ls -la ~/vpn/ /etc/openvpn/ 2>/dev/null
} | tee "$OUT"
echo "Saved: $OUT"
```

---

## ۱۱. لینک‌های مرتبط (سبک)

| سند | محتوا |
|-----|--------|
| [weekilaw-network.drawio](./weekilaw-network.drawio) | دیاگرام |
| [ParsPack-Datacenter-Connectivity.md](./ParsPack-Datacenter-Connectivity.md) | VPN ParsPack ↔ دیتاسنتر |
| [libvirtd/iran-routing/iran-routing.sh](../libvirtd/iran-routing/iran-routing.sh) | سورس split routing |

---

## ۱۲. TODO — بعد از inspect

- [ ] خروجی `ip route get 8.8.8.8` از یک VPS ParsPack
- [ ] `/interface sstp-client print` + `/interface l2tp-client print` از میکروTik
- [ ] نوع VPN server روی `202.133.88.39`
- [ ] آیا ParsPack egress مستقیم است یا فقط via میکروTik

</div>
