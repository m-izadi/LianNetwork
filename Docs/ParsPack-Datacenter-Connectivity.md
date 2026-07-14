<div dir="rtl">

# اتصال ParsPack به شبکهٔ داخلی دیتاسنتر

این سند توضیح می‌دهد **چطور VPSهای ParsPack به IPهای private دیتاسنتر دسترسی دارند** و **چرا اینترنت بین‌الملل «بدون فیلتر» به نظر می‌رسد**.

> **به‌روزرسانی (تأیید عملی):** `curl ipconfig.io` روی همهٔ ماشین‌ها → **`202.133.88.39`** (France 2).  
> Cloudz `144.172.117.7` **هنوز در production نیست** — ساخته شده ولی ترافیکی رویش نیست.

---

## ۱. خلاصهٔ یک خط

VPSهای ParsPack روی **اینترنت عمومی** هستند، ولی با **تونل VPN (site-to-site یا client-to-site)** به LAN دیتاسنتر وصل شده‌اند.  
میکروTik مسیر subnetهای داخلی (`192.168.88.0/24` و …) را به کلاینت‌های VPN می‌دهد و فایروال rule «Allow VPN to rest of LAN» اجازهٔ forward می‌دهد.

**اینترنت بین‌الملل** از تونل VPN به **VPS فرانسه `202.133.88.39`** می‌رود — `curl ipconfig.io` روی همهٔ ماشین‌ها همین IP را نشان می‌دهد. Cloudz `144.172.117.7` فعلاً استفاده نمی‌شود.

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

## ۳. معماری تأییدشده (خروج بین‌الملل)

```
  ┌──────────────── ParsPack VPS ────────────────┐     ┌─── دیتاسنتر ───────────────┐
  │ 130.185.75.96  web                           │     │ 78.110.124.181  app-back    │
  │ 178.239.151.33 backend                      │     │ 78.110.124.178  …           │
  │ 178.239.151.53 front (+ iran-routing)       │     │ 192.168.88.0/24  VM LAN     │
  │ 91.228.186.133 app-back-tu                   │     │ 192.168.122.254  GW میکروTik│
  │ 185.239.3.93   weegram                       │     └──────────────┬─────────────┘
  └──────────────────────┬───────────────────────┘                    │
                         │                                            │
            VPN داخلی (OVPN?)              iran-routing / ipset-iran   │
            برای 192.168.x.x               mark ترافیک غیرایرانی ──────┤
                         │                                            │
                         └────────────────────┬───────────────────────┘
                                              │
                                              ▼
                         ┌────────────────────────────────────────────┐
                         │  میکروTik (78.110.124.179)                 │
                         │    ovpn-server  ←→  ParsPack (LAN access)  │
                         │    SSTP client (hs)      ──┐                 │
                         │    L2TP client (tun2-L2) ──┤  route2fr       │
                         └──────────────────────────┼─────────────────┘
                                                    │
                                                    ▼
                         ┌────────────────────────────────────────────┐
                         │  🇫🇷 VPS France 2  —  egress فعلی         │
                         │  202.133.88.39  (curl ipconfig.io)         │
                         │  France 1: 202.133.88.239 (پشتیبان/link1)  │
                         └────────────────────┬───────────────────────┘
                                              │
                                              ▼
                                    اینترنت بدون فیلتر

  ┌─ آینده (غیرفعال) ────────────────────────────────────────────────┐
  │  Cloudz weekilaw-egress-gw-01  144.172.117.7  —  ترافیک ندارد    │
  └──────────────────────────────────────────────────────────────────┘
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

### ۴.۲. VPS فرانسه — **خروج بین‌الملل فعال (تأیید شده)**

| سرور | IP | نقش |
|------|-----|-----|
| **France 2** | `202.133.88.39` | **egress فعلی** — `curl ipconfig.io` روی همهٔ ماشین‌ها |
| France 1 | `202.133.88.239` | لینک پشتیبان (`link1`) |

**تست تأیید:** `curl ipconfig.io` → `202.133.88.39`

**نحوهٔ کار (محتمل):**

1. ترافیک **غیرایرانی** mark/route می‌شود (`iran-routing` + `ipset-iran` یا policy میکروTik)
2. از میکروTik از تونل **SSTP (`hs`)** یا **L2TP (`tun2-L2`)** به VPS فرانسه می‌رود
3. VPS فرانسه NAT → اینترنت با IP `202.133.88.39`

### ۴.۳. Cloudz / WireGuard — **برنامهٔ آینده، فعلاً خاموش**

| مورد | وضعیت |
|------|--------|
| `144.172.117.7` | ساخته شده، **ترافیک production ندارد** |
| `wg0` = `10.200.0.1/32` | پیکربندی اولیه — جایگزین egress فعلی **نشده** |

### ۴.۴. SSTP / L2TP — لینک میکروTik → France

- `hs` (SSTP) و `tun2-L2` (L2TP) روی میکروTik **فعال**
- routing table: `route2fr`
- egress تأییدشده = `202.133.88.39` = France 2 — همهٔ ماشین‌ها (ParsPack + دیتاسenتر) همین را در `curl ipconfig.io` می‌بینند

### ۴.۵. EoIP — فعلاً غیرفعال

- `eoip-hassaniRouter`, `eoip-hassaniIDC` در interface list **disabled (X)**
- اگر فعال بود L2 bridge مستقیم می‌داد؛ **الان نقش ندارد**

### ۴.۶. `192.168.122.0/24` روی ParsPack ≠ دیتاسنتر

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
| `10.200.0.0/…` | WireGuard (Cloudz — **غیرفعال**) | `weekilaw-egress-gw-01` |
| `202.133.88.39` | NAT egress بین‌الملل فعلی | `curl ipconfig.io` |
| `172.17–25.0.0/16` | Docker bridge (محلی هر VPS) | README web |

---

## ۶. اینترنت «بدون فیلتر» — چرا `202.133.88.39`؟

**تأیید شده:** همهٔ ماشین‌ها (ParsPack + دیتاسenتر) با `curl ipconfig.io` IP فرانسه را می‌بینند.

| لایه | رفتار |
|------|--------|
| **مقصد ایرانی** | مستقیم از اینترنت ایران (ParsPack یا radio/fiber دیتاسenتر) |
| **مقصد خارجی** | از تونل VPN → VPS France 2 → NAT → اینترنت آزاد |
| **Cloudz** | هنوز در این مسیر **نیست** |

**split routing** (روی hostهای libvirt):

- `ipset-iran` — لیست IPهای ایران
- `iran-routing` — ترافیک `!iran` → mark → table `iran-bypass` → gateway `192.168.122.254` (میکروTik VM) → France

روی ParsPack احتمالاً همان منطق (یا VPN مستقیم به France / via میکروTik) اعمال شده — با دستور `ip route get 8.8.8.8` روی هر VPS دقیق می‌شود.

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

### `144.172.117.7` — Cloudz egress (**غیرفعال در production**)

| Interface | IP | وضعیت |
|-----------|-----|--------|
| `enp0s7` | چند IP روی یک NIC | آماده |
| `wg0` | `10.200.0.1/32` | پیکربندی اولیه — **ترافیک ندارد** |

### `202.133.88.39` — France 2 egress (**فعال**)

| مورد | مقدار |
|------|--------|
| IP egress | `202.133.88.39` |
| تست | `curl ipconfig.io` روی همهٔ ماشین‌ها |
| نقش | NAT خروجی بین‌الملل کل زیرساخت |

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

# اینترنت بین‌الملل از کجا خارج می‌شود (انتظار: 202.133.88.39)
curl -4 --max-time 10 ipconfig.io ; echo
ip route get 8.8.8.8
traceroute -n 8.8.8.8

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

### ۸.۴. روی VPS France 2 (`202.133.88.39`) — **اولویت بالا**

```bash
# سرویس VPN (SSTP/L2TP/OpenVPN server?)
ss -tulnp
ip a
iptables -t nat -L -n -v | head -30
# sessionهای فعال
cat /var/log/syslog | tail -50
```

### ۸.۵. روی Cloudz (`144.172.117.7`) — فقط برای آینده

```bash
wg show
# انتظار: peer فعال ندارد یا ترافیک صفر
```

---

## ۹. چک‌لیست — وضعیت فعلی

| تست | نتیجهٔ تأییدشده | هنوز باز |
|-----|-----------------|----------|
| `curl ipconfig.io` | **`202.133.88.39`** (France) | — |
| Cloudz egress | **غیرفعال** | — |
| ParsPack → private LAN | ping کار می‌کند | نوع VPN (OVPN?) |
| `ip route get 8.8.8.8` روی ParsPack | — | dev/interface دقیق |
| میکروTik `/ppp active` | — | کدام tunnel به France |
| France VPS | NAT egress | SSTP vs L2TP vs OVPN |

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

## ۱۳. TODO

- [x] مسیر egress بین‌الملل → **`202.133.88.39`** (France 2)
- [x] Cloudz `144.172.117.7` → **غیرفعال**
- [ ] نوع تونل میکروTik → France (SSTP `hs` vs L2TP `tun2-L2`)
- [ ] نوع VPN ParsPack → دیتاسenتر (OpenVPN?)
- [ ] `ip route get 8.8.8.8` و `ip route get 192.168.88.242` روی یک VPS ParsPack
- [ ] `/ppp active print` روی میکروTik
- [ ] به‌روزرسانی دیاگرام Draw.io

</div>
