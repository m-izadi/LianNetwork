<div dir="rtl">

# اتصال ParsPack به شبکهٔ داخلی دیتاسنتر

این سند توضیح می‌دهد **چطور VPSهای ParsPack به IPهای private دیتاسنتر دسترسی دارند** و **چرا اینترنت بین‌الملل «بدون فیلتر» به نظر می‌رسد**.

> وضعیت: بر اساس READMEهای interface، backup میکروTik، History سرور `178.239.151.53`، پوشهٔ `vpn` روی web، و WireGuard روی Cloudz — **بخشی تأیید شده، بخشی فرضیه** تا وقتی دستورات پایین را بزنید.

---

## ۱. خلاصهٔ یک خط

VPSهای ParsPack روی **اینترنت عمومی** هستند، ولی با **تونل VPN (site-to-site یا client-to-site)** به LAN دیتاسنتر وصل شده‌اند.  
میکروTik مسیر subnetهای داخلی (`192.168.88.0/24` و …) را به کلاینت‌های VPN می‌دهد و فایروال rule «Allow VPN to rest of LAN» اجازهٔ forward می‌دهد.

**اینترنت بین‌الملل** یا مستقیم از ParsPack (پلن ترافیک بین‌الملل) می‌آید، یا از VPN به **gateway خروجی** (مثلاً Cloudz `144.172.117.7` با `wg0` / `10.200.0.1`).

---

## ۲. چرا فکر می‌کردیم جدا هستند؟

| لایه | واقعیت |
|------|--------|
| **IP عمومی** | هر VPS ParsPack IP مستقل روی اینترنت دارد (`130.185.…`, `178.239.…`) |
| **لایهٔ L3 داخلی** | با VPN به subnetهای `192.168.x.x` دیتاسenتر route دارد |
| **کاربران وب** | `app.weekilaw.com` از CDN اروان → VPS می‌آید؛ **نه** از LAN داخلی |
| **ادمین / بکاپ / sync** | از همان VPN به IP private دیتاسنتر می‌رود |

پس: **production عمومی جدا است، مدیریت و sync از طریق VPN وصل است.**

---

## ۳. معماری (بر اساس شواهد موجود)

```
                         ┌──────────────────────────────────────┐
                         │           دیتاسنتر فیزیکی             │
                         │                                      │
                         │  میکروTik (78.110.124.179)           │
                         │    ├─ ovpn-server / br-ovpn          │
                         │    ├─ SSTP client (hs) ───────┐      │
                         │    ├─ L2TP client (tun2-L2) ──┤      │
                         │    └─ vlan11-vpn / br-vpn     │      │
                         │                               │      │
                         │  192.168.90.0/24  مدیریت      │      │
                         │  192.168.88.0/24  VM/LAN      │      │
                         │  192.168.122.254  GW میکروTik │      │
                         │       (روی virbr0 hypervisor) │      │
                         └───────────────┬───────────────┘      │
                                         │                      │
                            تونل VPN ◄───┴───► (OpenVPN / WG / L2TP)
                                         │
         ┌───────────────────────────────┼───────────────────────────────┐
         │                               │                               │
         ▼                               ▼                               ▼
  130.185.75.96                   178.239.151.33                  178.239.151.53
  weekilaw-com-web-ir             weekilaw-com-back-ir            weekilaw-com-front-ir
  ~/vpn/  (احتمال OVPN client)    virbr0 + vnet0                  wg0? + iran-routing
  sync_tool → بکاپ به سرور شرکت
         │                               │                               │
         └───────────────────────────────┴───────────────────────────────┘
                                         │
                          اینترنت بین‌الملل (مستقیم ParsPack یا via VPN)
                                         │
                                         ▼
                         ┌───────────────────────────────┐
                         │ Cloudz weekilaw-egress-gw-01  │
                         │ 144.172.117.7                 │
                         │ wg0 → 10.200.0.1/32           │
                         └───────────────────────────────┘
```

---

## ۴. مکانیزم‌های محتمل (اولویت‌بندی)

### ۴.۱. OpenVPN — محتمل‌ترین برای ParsPack → دیتاسنتر

**شواهد:**

- میکروTik: `ovpn-server`, `br-ovpn`, `ovpn-ca`, address-list `vpn-clients`
- فایروall: `Allow VPN to rest of LAN` (forward از VPN به LAN)
- VPS web (`130.185.75.96`): پوشهٔ **`~/vpn`** در لیست فایل‌ها
- README web: «اسکریپت بکاپ … فایلش را **برای سرور شرکت** ارسال می‌کند» → نیاز به مسیر private به دیتاسنتر

**نحوهٔ کار (معمول):**

1. میکروTik OpenVPN Server روی پورت UDP/TCP (مثلاً 1194)
2. هر VPS ParsPack فایل `.ovpn` + certificate دارد (`~/vpn/`)
3. بعد از connect، interface `tun0` (یا مشابه) بالا می‌آید
4. میکروTik با **push route** subnet `192.168.88.0/24` (و شاید `192.168.90.0/24`) را به client می‌دهد
5. ping به `192.168.88.242` (که در History سرور `178.239.151.53` دیده شده) از همین مسیر است

### ۴.۲. WireGuard — برای خروجی بین‌الملل

**شواهد:**

- Cloudz `144.172.117.7`: `wg0` با `10.200.0.1/32`
- History `178.239.151.53`: نصب و تنظیم `/etc/wireguard/wg0.conf`، v`exclude-iran-routes.sh`
- تست `curl api.openai.com`، `traceroute` از طریق `wg0`

**نحوهٔ کار (معمول):**

- peerهای ParsPack/دیتاسنتر به hub Cloudz وصل می‌شوند
- `AllowedIPs` شامل `0.0.0.0/0` یا فقط prefixهای خارج → ترافیک غیرایرانی از تونل
- یا split: ایران مستقیم، خارج از WG

### ۴.۳. SSTP / L2TP — میکروTik به عنوان client

**شواهد (از backup + interface):**

- `hs` = SSTP Client **فعال**
- `tun2-L2` = L2TP Client **فعال**
- VPS فرانسه: `202.133.88.239`, `202.133.88.39` (README: France for vpn)

**نقش احتمالی:** میکروTik برای **خروج بین‌الملل دیتاسنتر** به VPN خارج وصل می‌شود (نه لزوماً ParsPack → دیتاسenتر).  
اما ممکن است hub مشترک باشد.

### ۴.۴. EoIP — فعلاً غیرفعال

- `eoip-hassaniRouter`, `eoip-hassaniIDC` در interface list **disabled (X)**
- اگر فعال بود L2 bridge مستقیم می‌داد؛ **الان نقش ندارد**

### ۴.۵. `192.168.122.0/24` روی ParsPack ≠ دیتاسنتر

روی **هر** VPS ParsPack:

```
virbr0    192.168.122.1/24
vnet0     (VM محلی libvirt)
```

این **شبکهٔ محلی libvirt همان ماشین** است.  
`192.168.122.254` فقط روی hypervisor دیتاسنتر gateway میکروTik VM است — **مگر** route VPN صریح بدهد، از ParsPack به `.254` نمی‌رسید.

---

## ۵. subnetهای داخلی شناخته‌شده

| Subnet | نقش | کجا دیده شده |
|--------|-----|--------------|
| `192.168.90.0/24` | مدیریت میکروTik (Winbox از `.2`, `.3`, `.200`) | backup میکروTik |
| `192.168.88.0/24` | LAN/VM دیتاسنتر | History: `ping 192.168.88.242`؛ `ipset-iran` exclude |
| `192.168.122.0/24` | libvirt default؛ GW `.254` = میکروTik VM | `iran-routing.sh` |
| `10.200.0.0/…` | WireGuard mesh (Cloudz hub) | `weekilaw-egress-gw-01` |
| `172.17–25.0.0/16` | Docker bridge (محلی هر VPS) | README web |

---

## ۶. اینترنت «بدون فیلتر» ParsPack — چرا؟

چند سناریو **همزمان** ممکن است:

| سناریو | علامت | توضیح |
|--------|-------|-------|
| **A. پلن ParsPack** | `curl ifconfig.me` = IP ParsPack | ترافیک بین‌الملل روی VPS بدون فیلتر ISP ایران |
| **B. WireGuard به Cloudz** | `curl ifconfig.me` = `144.172.x.x` | default یا route selective از WG |
| **C. VPN به میکروTik + multi-WAN** | traceroute از radio/fiber | خروج از لینک دیتاسنتر |
| **D. split routing (`ir.zone`)** | `ip rule` / `ip route table` | ایران مستقیم، خارج از تونل |

روی `iran-8-100` فایل **`ir.zone`** دیده شده → احتمال split routing شبیه دیتاسenتر.

---

## ۷. interfaceهای ParsPack (از READMEها)

### `130.185.75.96` — web

| Interface | IP | نقش |
|-----------|-----|-----|
| `eth0` | `130.185.75.96/24` | اینترنت عمومی |
| `virbr0` | `192.168.122.1/24` | libvirt محلی |
| `docker0`, `br-*` | `172.x.0.1/16` | Docker |
| `vnet0` | link-local | VM libvirt |

### `178.239.151.33` — backend

| Interface | IP |
|-----------|-----|
| `eth0` | `178.239.151.33/24` |
| `virbr0` | `192.168.122.1/24` |
| `docker0` | `172.17.0.1/16` |

### `178.239.151.53` — front / hypervisor

| Interface | IP |
|-----------|-----|
| `eth0` | `178.239.151.53/24` |
| `virbr0` | `192.168.122.1/24` |

### `144.172.117.7` — Cloudz egress

| Interface | IP |
|-----------|-----|
| `enp0s7` | چند IP روی یک NIC |
| `wg0` | `10.200.0.1/32` |

---

## ۸. دستورات تشخیصی — لطفاً روی ماشین‌ها بزنید

خروجی را در repo بگذارید تا این سند از «فرضیه» به «مستند» تبدیل شود.

### ۸.۱. روی هر VPS ParsPack (web, backend, front, iran-8-100)

```bash
# کدام interface برای کجا استفاده می‌شود
ip -br a
ip route show
ip rule list

# اگر private دیتاسنتر را ping می‌کنید — مسیر دقیق
ip route get 192.168.88.242
ip route get 192.168.90.1
traceroute -n 192.168.88.242

# اینترنت بین‌الملل از کجا خارج می‌شود
curl -4 --max-time 10 ifconfig.me ; echo
traceroute -n 8.8.8.8
traceroute -n 1.1.1.1

# VPN clientها
systemctl list-units --type=service | grep -iE 'wg|openvpn|vpn|strongswan|xl2tp'
wg show 2>/dev/null
ls -la /etc/wireguard/ 2>/dev/null
ls -la ~/vpn/ 2>/dev/null
ip -br a show type tun
ip -br a show type wg

# Docker — جدا از VPN host است
docker network ls
```

**روی web (`130.185.75.96`) additionally:**

```bash
ls -la ~/vpn/
ls -la ~/sync_tool/
# اگر فایل .ovpn دارید (secret را mask کنید):
# grep -E '^(remote|dev|route|redirect-gateway)' ~/vpn/*.ovpn
```

**روی front (`178.239.151.53`) additionally:**

```bash
systemctl status wg-quick@wg0 2>/dev/null
systemctl status iran-routing ipset-iran 2>/dev/null
cat /usr/local/bin/iran-routing.sh 2>/dev/null | head -40
iptables -t mangle -L -n -v 2>/dev/null | head -30
```

### ۸.۲. روی میکروTik (Winbox Terminal یا SSH)

```routeros
/interface print
/interface ovpn-server server print
/interface ovpn-server print
/ppp secret print
/ppp active print
/interface wireguard print
/interface wireguard peers print
/ip pool print
/routing table print
/ip route print detail
/routing rule print
/ip firewall filter print where comment~"VPN"
/ip firewall nat print
```

### ۸.۳. روی hypervisor دیتاسنتر (اگر SSH دارید)

```bash
ip route
ip rule
ping -c 3 130.185.75.96
ping -c 3 192.168.88.242
virsh list --all
virsh domifaddr --source agent <vm-name> 2>/dev/null
iptables -t mangle -L -n -v | head -20
```

### ۸.۴. روی Cloudz egress (`144.172.117.7`)

```bash
wg show
ip route
iptables -t nat -L -n -v | head -20
```

---

## ۹. چک‌لیست تأیید فرضیه

بعد از اجرای دستورات، این جدول را پر کنید:

| تست | نتیجهٔ مورد انتظار اگر OVPN است | نتیجهٔ مورد انتظار اگر WG است |
|-----|----------------------------------|-------------------------------|
| `ip a` | interface `tun0` یا `tap0` | interface `wg0` |
| `ip route get 192.168.88.x` | dev `tun0` via VPN | dev `wg0` |
| `curl ifconfig.me` | IP ParsPack یا egress | IP Cloudz (`144.172.x`) |
| میکروTik `/ppp active` | session برای IP ParsPack | — |
| `wg show` روی Cloudz | — | peer با IP ParsPack |

---

## ۱۰. سناریوی محتمل end-to-end (بکاپ web → دیتاسنتر)

```
cron روی 130.185.75.96 (sync_tool)
    → مقصد: IP private دیتاسنتر (مثلاً 192.168.88.x)
    → ip route: 192.168.88.0/24 dev tun0 (OpenVPN)
    → تونل رمزنگاری‌شده تا میکروTik
    → میکروTik forward از br-ovpn به br-servers / vlan15-servers
    → VM/سرور مقصد
```

---

## ۱۱. نکات امنیتی

- فایل‌های `.ovpn`, `wg0.conf`, private key را **commit نکنید**
- VPN دسترسی به LAN داخلی می‌دهد — address-list `vpn-clients` و firewall میکروTik critical است
- `ui3-ir1` … `ui6-ir4` فقط برای **Winbox** است، نه جایگزین VPN

---

## ۱۲. فایل‌های مرتبط

| مسیر | محتوا |
|------|--------|
| [Docs/README.md](./README.md) | معماری کلی (نیاز به به‌روزرسانی بخش «دو دنیا») |
| [VMs/ParsPack/weekilaw-com-web-ir/README.md](../VMs/ParsPack/weekilaw-com-web-ir/README.md) | web + `~/vpn` |
| [VMs/Cloudz/weekilaw-egress-gw-01/README.md](../VMs/Cloudz/weekilaw-egress-gw-01/README.md) | WireGuard hub |
| [libvirtd/iran-routing/iran-routing.sh](../libvirtd/iran-routing/iran-routing.sh) | split routing دیتاسenتر |
| `ParsPack/178.239.151.53/History` | wg0, ping 192.168.88.242 |

---

## ۱۳. TODO بعد از دریافت خروجی دستورات

- [ ] نوع VPN دقیق (OpenVPN / WireGuard / هر دو)
- [ ] subnetهای push شده از میکروTik
- [ ] IP private دقیق مقصد بکاپ sync_tool
- [ ] مسیر خروج بین‌الملل (ParsPack مستقیم vs Cloudz)
- [ ] به‌روزرسانی دیاگرام Draw.io با لینک VPN

</div>
