<div dir="rtl">

# iran-8-100 — راهنمای درک شبکه ویکیلا

این سند نقطهٔ شروع برای فهم **کل معماری شبکه** است؛ نه فقط همین سرور.  
اطلاعات از ترکیب `1.backup` (میکروتیک)، اسکرین‌شات اینترفیس‌ها، دیاگرام Draw.io و READMEهای دیگر استخراج شده.

---

## ۱. خلاصهٔ خیلی کوتاه

| مورد | مقدار |
|------|--------|
| **نام داخلی** | `iran-8-100` / `weegram` |
| **IP عمومی** | `185.239.3.93` |
| **ارائه‌دهنده** | ParsPack (VPS — خارج از دیتاسنتر فیزیکی) |
| **SSH** | پورت `50022` — کاربر `root` |
| **نقش در میکروتیک** | `ui6-ir4` — IP مجاز برای دسترسی مدیریتی (Winbox) |
| **وضعیت کلی** | بخش زیادی از سرویس‌های production به VPS منتقل شده؛ دیتاسنتر محلی هنوز زیرساخت، چند VM و لینک‌های اینترنت را نگه می‌دارد |

---

## ۲. تصویر کلی: دو دنیأ جدا

```
                    ┌─────────────────────────────────────┐
                    │         اینترنت / کاربران           │
                    └─────────────────┬───────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
              ▼                       ▼                       ▼
     ┌────────────────┐    ┌─────────────────┐    ┌──────────────────┐
     │  CDN اروان     │    │  VPSهای ParsPack │    │  VPS خارج / VPN  │
     │  (پروکسی)      │    │  (production اصلی)│    │  (weekilaw.app)  │
     └───────┬────────┘    └────────┬─────────┘    └────────┬─────────┘
             │                      │                       │
             │         ┌────────────┴────────────┐          │
             │         │ 130.185.75.96  web      │          │
             │         │ 178.239.151.33 backend  │          │
             │         │ 178.239.151.53 front    │          │
             │         │ 185.239.3.93   weegram  │ ◄── شما اینجا
             │         └─────────────────────────┘          │
             │                                              │
             └──────────────────┬───────────────────────────┘
                                │
                    ┌───────────▼───────────┐
                    │   دیتاسنتر فیزیکی     │
                    │   میکروتیک + سرورها   │
                    │   78.110.124.0/24     │
                    └───────────────────────┘
```

**نکتهٔ مهم:** VPSهای ParsPack **پشت NAT میکروتیک نیستند** (IP عمومی مستقل دارند)، ولی با **VPN** به subnetهای private دیتاسنتر (`192.168.88.0/24` و …) route دارند و ping/بکاپ مستقیم ممکن است.  
جزئیات: [ParsPack-Datacenter-Connectivity.md](./ParsPack-Datacenter-Connectivity.md)

میکروتیک IP آن‌ها را در `ui3-ir1` … `ui6-ir4` هم برای **Winbox** whitelist کرده.

---

## ۳. دیتاسنتر محلی (پشت میکروTik)

### ۳.۱. سخت‌افزار

| پورت میکروتیک | نام | نقش |
|---------------|-----|-----|
| `ether1-radio` | رادیو | لینک اینترنت ۱ (فعال، ترافیک بالا) |
| `ether2-fiber` | فیبر | لینک اینترنت ۲ (فعال، ترافیک کم) |
| `ether3-starlink` | استارلینک | لینک ۳ (فعلاً down) |
| `ether6-tplink_sw` | سوئیچ TP-Link | شبکهٔ داخلی / trunk |
| `ether9-hp` | سرور HP | میزبان VMها (slave روی bridge) |
| `ether10-supermicro` | سرور SuperMicro | سرور دوم |
| `sfp-sfpplus1` | SFP+ | غیرفعال |

### ۳.۲. Bridge چیست و چرا این‌قدر زیاد داریم؟

**Bridge** در میکروتیک مثل **سوئیچ مجازی** است: چند پورت/ VLAN را در یک broadcast domain قرار می‌دهد.

| Bridge | کاربرد |
|--------|--------|
| `BR-TRUNK` | trunk اصلی — VLANها روی آن سوارند |
| `br-radio` / `br-fiber` / `br-starlink` | جدا کردن هر WAN برای policy routing (`route2radio`, `route2fiber`, `route2starlink`) |
| `br-servers` | ترافیک سرورها (HP + SuperMicro) |
| `br-vpn` / `br-ovpn` | ترافیک VPN (OpenVPN و …) |

**چرا bridge به‌جای routing ساده؟**  
تا بتوان برای هر لینک اینترنت مسیر، NAT و فایروال جدا تعریف کرد — مثلاً ترافیک radio از fiber جدا برود یا failover راحت‌تر شود.

### ۳.۳. VLANها (روی `BR-TRUNK`)

| VLAN | نام | احتمال نقش |
|------|-----|------------|
| `vlan10-radio` | radio | ترافیک مرتبط با uplink رادیو |
| `vlan11-vpn` | vpn | شبکهٔ VPN داخلی |
| `vlan12-fiber` | fiber | uplink فیبر |
| `vlan13-starlink` | starlink | uplink استارلینک |
| `vlan15-servers` | servers | شبکهٔ VMها/سرورها (ترافیک `ether9-hp` اینجا دیده می‌شود) |
| `vlan16-IPMI` | IPMI | مدیریت out-of-band سرورها |
| `vlan17` | — | VLAN اضافی (نقش دقیق نیاز به export متنی دارد) |

### ۳.۴. VMهای محلی (libvirt/KVM)

از backup میکروتیک و تاریخچهٔ سرور `178.239.151.53`:

| VM | توضیح احتمالی |
|----|--------------|
| `vm00` | اصلی‌ترین — چندین قانون **NAT to vm00** |
| `vm01` … `vm05` | VMهای دیگر |
| `vm - test` | محیط تست |
| `vm - mik` | احتمالاً خود RouterOS به‌صورت VM (`mikrotik-routeros-kvm-disk.qcow2`) |
| `vm - win10-hassani` | ویندوز ادمین |

**شبکهٔ مدیریت میکروتیک:** `192.168.90.0/24`  
(ادمین‌ها از `.2`, `.3`, `.200` Winbox می‌زنند)

**شبکهٔ libvirt پیش‌فرض:** `192.168.122.0/24` — gateway برای bypass ترافیک غیرایرانی: `192.168.122.254`

### ۳.۵. IPهای عمومی دیتاسنتر (`78.110.124.x`)

| IP | سرویس (طبق مستندات پروژه) |
|----|---------------------------|
| `78.110.124.179` | IP/router — گواهی SSL میکروتیک |
| `78.110.124.181` | `weekilaw.app` بین‌المللی، ویدیو کال، API، Redis، Planka |
| `78.110.124.182` | (در README دیتاسنتر — جزئیات کم) |
| `78.110.124.178` | (SSH پورت 50022) |
| `185.143.234.235` | front مرتبط (`weekilaw.app-front-ir`) |

### ۳.۶. Split routing روی host (چرا گاهی اینترنت «عجیب» است)

روی hypervisor (مثلاً `178.239.151.53`) دو سرویس systemd نصب شده:

- **`ipset-iran`** — لیست IP/-CIDR ایران
- **`iran-routing`** — ترافیک **غیرایرانی** را mark می‌کند و از table `iran-bypass` از gateway میکروTik VM (`192.168.122.254`) رد می‌کند

یعنی: مقصد ایرانی → اینترنت مستقیم / مقصد خارجی → از تونل/میکروتیک.  
اگر ipset یا VM میکروتیک down باشد، دسترسی به سرویس‌های خارجی (Claude، OpenAI، …) قطع می‌شود — در History همین سرور traceهای زیادی از این مشکل دیده می‌شود.

---

## ۴. VPSهای ParsPack (production فعلی `weekilaw.com`)

این‌ها **خارج از LAN داخلی** هستند و مستقیم روی ParsPack:

| IP | پوشهٔ مستندات | دامنه / نقش |
|----|--------------|-------------|
| `130.185.75.96` | [weekilaw-com-web-ir](../weekilaw-com-web-ir/) | `app.weekilaw.com`, `payment.weekilaw.com`, MongoDB, MinIO |
| `178.239.151.33` | [weekilaw-com-back-ir](../weekilaw-com-back-ir/) | `api.weekilaw.com`, `admin.weekilaw.com`, `test.weekilaw.com` |
| `178.239.151.53` | [weekilaw-com-front-ir](../weekilaw-com-front-ir/) | front / lian site / hypervisor |
| **`185.239.3.93`** | **همین فایل** | **weegram** |

**جریان typical کاربر `app.weekilaw.com`:**

```
کاربر → DNS → CDN اروان → nginx روی VPS web (130.185.75.96)
                              ↓
                         API روی VPS backend (178.239.151.33)
```

---

## ۵. این سرور: `iran-8-100` / `185.239.3.93`

### مشخصات

```
Host:     iran-8-100 (ParsPack)
IP:       185.239.3.93
SSH:      50022
User:     root
Service:  weegram (طبق README ریشهٔ پروژه)
```

### ارتباط با بقیه

- در میکروTik با برچسب **`ui6-ir4`** و **`for IR`** ثبت شده → یعنی از این IP اجازهٔ دسترسی به UI میکروTik داده شده.
- **جدا از** سه VPS اصلی weekilaw.com است؛ احتمالاً سرویس جانبی (مثلاً Telegram/weegram) روی ParsPack جدا deploy شده.
- در دیاگرام Draw.io شما ممکن است با nodeهای ParsPack قاطی شده باشد — IP `185.239.3.93` را با `185.143.235.153` (CDN/سرویس دیگر) اشتباه نگیرید.

---

## ۶. VPN و تونل‌ها (از backup + دیاگرام)

| اینترفیس | نوع | وضعیت |
|----------|-----|--------|
| `hs` | SSTP Client | فعال |
| `tun2-L2` | L2TP Client | فعال |
| `tun1`, `tun3`, `tun4` | SSTP/L2TP | غیرفعال |
| `eoip-hassaniRouter`, `eoip-hassaniIDC` | EoIP | غیرفعال (پل L2 به datacenter دیگر) |
| `ipip-tunnel1` | IPIP | غیرفعال |
| OpenVPN (`ovpn-server`, `ovpn-client`) | OpenVPN | پیکربندی شده |

**VPS VPN خارجی (README پروژه):**

| محل | IP | وضعیت |
|-----|-----|--------|
| **France 2** | `202.133.88.39` | **egress فعال** — `curl ipconfig.io` روی همهٔ ماشین‌ها |
| France 1 | `202.133.88.239` | لینک پشتیبان |
| Cloudz egress | `144.172.117.7` | ساخته شده، **ترافیک ندارد** |
| USA Utah | `144.172.91.114` | VPN |
| Germany (ui2) | `185.215.244.112` | Winbox whitelist |

جزئیات: [ParsPack-Datacenter-Connectivity.md](./ParsPack-Datacenter-Connectivity.md)

---

## ۷. دیاگرام Draw.io — چه چیزهایی درست است / چه چیزهایی را چک کن

### به‌نظر درست

- میکروTik جلوی سرور فیزیکی با **چند لینک اینترنت**
- **NAT** هر IP public به یک ماشین در دیتاسنتر
- سرویس‌های `weekilaw.com` روی **ParsPack** و **CDN اروان**
- `weekilaw.app` بین‌المللی روی VPS/دیتاسنتر جدا
- چند node VPN در خارج

### موارد مشکوک / نیاز به تأیید

| موضوع | توضیح |
|-------|--------|
| IPهای تکراری | بعضی IPها در چند جای دیاگرام تکرار شده (`185.143.235.153` و …) — باید با DNS واقعی تطبیق داده شود |
| `weekilaw.app` vs `weekilaw.com` | دو اکوسیستم جدا — `.app` بیشتر بین‌المللی/دیتاسنتر، `.com` بیشتر ایران/ParsPack |
| جهت فلش «Backend Forward» | احتمالاً منظور reverse proxy یا API gateway است — باید با nginx config روی هر VPS چک شود |
| nodeهای VPS generic | IPهایی مثل `144.172.93.184` / `46.223.111.1` — در backup میکروTik نیستند؛ یا VPS مستقل‌اند یا دیاگرام قدیمی است |

---

## ۸. جدول IP → نقش (مرجع سریع)

### ParsPack / ایران

| IP | نقش |
|----|-----|
| `130.185.75.96` | Web + Payment + Mongo + MinIO |
| `178.239.151.33` | API + Admin + Test |
| `178.239.151.53` | Front / Lian / Hypervisor |
| `185.239.3.93` | weegram (**iran-8-100**) |

### دیتاسنتر محلی

| IP | نقش |
|----|-----|
| `78.110.124.179` | Router/MikroTik |
| `78.110.124.181` | weekilaw.app backend بین‌المللی |
| `78.110.124.178` | سرور/VM دیگر |
| `78.110.124.182` | (نامشخص — تکمیل شود) |

### مدیریت میکروTik (address-list «for IR/DE»)

| Label | IP |
|-------|-----|
| ui2 (DE) | `185.215.244.112` |
| ui3-ir1 | `130.185.75.96` |
| ui4-ir2 | `178.239.151.33` |
| ui5-ir3 | `178.239.151.53` |
| ui6-ir4 | `185.239.3.93` |

---

## ۹. چرا سرویس‌ها به VPS رفت؟

از شواهد پروژه:

1. **Multi-WAN ناپایدار** — radio/fiber/starlink؛ policy routing پیچیده
2. **Split routing** — وابستگی به VM میکروTik برای ترافیک خارجی
3. **تمرکز ریسک** — یک قطعی برق/لینک کل production را می‌انداخت
4. **CDN اروان** — برای `weekilaw.com` لایهٔ cache/proxy جلوی VPS

نتیجه: **production اصلی `.com` روی ParsPack**؛ دیتاسنتر محلی بیشتر برای `.app` بین‌المللی، VPN، مانیتورینگ، AI/dev workload (History سرور 178.239.151.53) و زیرساخت.

---

## ۱۰. قدم‌های بعدی برای مسلط شدن

1. **Export متنی میکروTik** — در Winbox: `Files → Backup` یا `/export file=network` → فایل `.rsc` خوانا می‌دهد (backup فعلی binary است).
2. **DNS واقعی** — `dig app.weekilaw.com`, `dig api.weekilaw.com` و مقایسه با دیاگرام.
3. **SSH به هر VPS** — `docker ps`, `nginx -T`, `ss -tlnp` برای نقشهٔ پورت‌ها (READMEهای sibling همین کار را شروع کرده‌اند).
4. **تست مسیر** — از داخل دیتاسنتر: `traceroute 8.8.8.8` vs `traceroute api.weekilaw.com`.
5. **مستند کردن iran-8-100** — بعد از SSH: سرویس‌های running، دامنه، و ارتباط با weegram.

---

## ۱۱. فایل‌های مرتبط در این repo

| مسیر | محتوا |
|------|--------|
| [Docs/interface.jpg](../../../Docs/interface.jpg) | اسکرین‌شات لیست interface میکروTik |
| [Docs/Untitled Diagram.jpg](../../../Docs/Untitled Diagram.jpg) | دیاگرام معماری Draw.io |
| [VMs/Datacenter/README.md](../../Datacenter/README.md) | IPها و سرویس‌های دیتاسنتر |
| [libvirtd/iran-routing/iran-routing.sh](../../../libvirtd/iran-routing/iran-routing.sh) | split routing |
| `1.backup` | backup binary میکروTik (نیاز به export `.rsc` برای جزئیات NAT) |
| [ParsPack-Datacenter-Connectivity.md](./ParsPack-Datacenter-Connectivity.md) | VPN ParsPack ↔ دیتاسنتر + اینترنت بین‌الملل |

---

## ۱۲. TODO — تکمیل بعد از دسترسی SSH

- [ ] `docker ps` / `systemctl list-units` روی `185.239.3.93`
- [ ] دامنه و nginx config مربوط به weegram
- [ ] آیا ترافیکی به دیتاسنتر/میکروTik برمی‌گردد یا کاملاً standalone است
- [ ] تطبیق نهایی دیاگرام Draw.io با DNS و export میکروTik

</div>
