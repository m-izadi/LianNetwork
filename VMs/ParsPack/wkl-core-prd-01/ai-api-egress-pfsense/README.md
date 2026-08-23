<div dir="rtl">

# AI APIها از اینترفیس دوم pfSense — `wkl-core-prd-01`

ماشین: **`wkl-core-prd-01` / `158.255.74.75` / LAN `192.168.77.3`**

هدف: بعد از انتقال کانتینرها از `weekilaw-com-back-ir` (`178.239.151.33`)، فقط ترافیک این APIها از **اینترفیس/WAN دوم pfSense** خارج شود؛ بقیه ترافیک (Mongo، Minio، Arvan، LAN و …) مثل قبل از gateway پیش‌فرض برود.

| دامنه | مسیر نمونه |
|--------|------------|
| `api.mistral.ai` | `/v1` |
| `api.openai.com` | `/v1` |
| `api.elevenlabs.io` | `/v1` |
| `api.anthropic.com` | — |
| `api.deepseek.com` | `/` |
| `api.x.ai` | `/v1/chat/completions` |

مسیر URL در روتینگ مهم نیست؛ فقط **IP مقصد hostname** مهم است.

```text
کانتینر روی wkl-core-prd-01
  └─ 192.168.77.x (یا NAT از host .3)
       └─ gateway 192.168.77.1 (pfSense LAN)
            ├─ مقصد = AI API IPs  → WAN2 / OPTx (اینترنت خارج)
            └─ بقیه مقصدها        → WAN1 / gateway پیش‌فرض
```

---

## چرا روی pfSense و نه WireGuard؟

`wkl-core-prd-01` پشت LAN pfSense است (`192.168.77.0/24`). برخلاف `back-ir` که از اینترنت با WireGuard به pfSense وصل می‌شود، اینجا **policy routing روی pfSense** ساده‌تر و پایدارتر است.

الگوی WireGuard + sync روی front/back برای hostهای دور از LAN است:
- [front wireguard-ai-apis](../../weekilaw-com-front-ir-151-53/wireguard-ai-apis/)
- [back wireguard-anthropic](../../weekilaw-com-back-ir-151.33/wireguard-anthropic/)

---

## ۱) pfSense — Gateway اینترفیس دوم

**System → Routing → Gateways**

1. Gateway برای WAN/OPT دوم بساز (مثلاً `GW_WAN2`).
2. **Monitor IP** بگذار (مثلاً `1.1.1.1` یا `8.8.8.8`) تا pfSense بداند لینک زنده است.
3. اگر failover می‌خواهی: **System → Routing → Gateway Groups** — برای AI API لازم نیست؛ فقط یک gateway ثابت کافی است.

---

## ۲) pfSense — Alias مقصدهای AI

**Firewall → Aliases**

| نام | نوع | محتوا |
|-----|-----|--------|
| `AI_API_HOSTS` | **URL Table (IPs)** یا Host(s) | لیست IP/CIDR |
| `WKL_CORE_SOURCES` | Network(s) | `192.168.77.3/32` و اگر کانتینر IP ثابت دارد همان‌ها (مثلاً `192.168.77.40/32`) |

### تولید لیست IP از دامنه‌ها

روی هر ماشینی که `getent`/`dig` دارد:

```bash
cd /path/to/repo/VMs/ParsPack/wkl-core-prd-01/ai-api-egress-pfsense
bash generate-alias-ips.sh > /tmp/ai-api-ips.txt
cat /tmp/ai-api-ips.txt
```

خروجی را در Alias بگذار، یا فایل را روی HTTP داخلی host کن و در pfSense **URL Table** با refresh هر ۳۰–۶۰ دقیقه تنظیم کن (CDNها IP عوض می‌کنند).

**CIDR ثابت Anthropic** (حتماً اضافه کن):

```text
160.79.104.0/23
```

منبع: [Anthropic IP addresses](https://platform.claude.com/docs/en/api/ip-addresses)

---

## ۳) pfSense — Policy routing (LAN)

**Firewall → Rules → LAN** (یا اینترفیسی که `192.168.77.0/24` روی آن است)

Rule **بالای** rule عمومی اینترنت:

| فیلد | مقدار |
|------|--------|
| Action | Pass |
| Interface | LAN (یا OPT مربوط به 77.x) |
| Protocol | TCP (یا any برای تست اولیه) |
| Source | Alias `WKL_CORE_SOURCES` |
| Destination | Alias `AI_API_HOSTS` |
| Destination Port | `443` (HTTPS) |
| Advanced → Gateway | **`GW_WAN2`** (اینترفیس دوم) |
| Description | `wkl-core AI APIs → WAN2` |

بقیه ruleهای LAN بدون Gateway override → مسیر پیش‌فرض.

---

## ۴) pfSense — Outbound NAT (خیلی مهم)

**Firewall → NAT → Outbound**

حالت: **Hybrid** یا **Manual**

Rule جدید **بالای** NAT عمومی:

| فیلد | مقدار |
|------|--------|
| Interface | **WAN2** (همان اینترفیس دوم) |
| Source | `WKL_CORE_SOURCES` |
| Destination | `AI_API_HOSTS` |
| Translation | Interface address |
| Description | `SNAT wkl-core AI → WAN2` |

بدون این rule، بسته از WAN2 خارج می‌شود ولی **SNAT اشتباه** می‌خورد و API جواب نمی‌دهد.

---

## ۵) pfSense — فایروال روی WAN2 (در صورت نیاز)

اگر WAN2 rule سخت‌گیرانه دارد، **Pass** برای ترافیک NAT‌شدهٔ outbound stateful معمولاً کافی است (reply traffic برمی‌گردد). اگر block می‌بینی، روی WAN2 rule موقت **Pass** برای تست بگذار.

---

## ۶) سمت `wkl-core-prd-01` — بدون تغییر routing host

اگر کانتینرها از subnet `192.168.77.0/24` با gateway `192.168.77.1` استفاده می‌کنند (مثل Mongo در [lian-server2](../../lian-server2/docker-compose.yaml))، **روی host چیزی عوض نکن** — pfSense policy را اعمال می‌کند.

### اگر کانتینر bridge دارد (مثلاً `172.x`)

منبع بسته روی pfSense `192.168.77.3` دیده می‌شود (MASQUERADE docker). در آن صورت کافی است `WKL_CORE_SOURCES = 192.168.77.3/32` باشد.

برای اطمینان بعد از بالا آوردن کانتینر:

```bash
# از داخل کانتینر backend
curl -4 -I --connect-timeout 10 https://api.openai.com/
curl -4 -I --connect-timeout 10 https://api.anthropic.com/
```

روی pfSense: **Diagnostics → States** — state به IPهای OpenAI/Anthropic باید از **WAN2** خارج شود.

---

## ۷) تست از host

```bash
# مسیر عادی — نباید از WAN2 برود (فقط default)
ip route get 1.1.1.1

# resolve و curl
dig +short A api.openai.com
curl -4 -I --connect-timeout 10 https://api.openai.com/v1
curl -4 -I --connect-timeout 10 https://api.mistral.ai/v1
curl -4 -I --connect-timeout 10 https://api.elevenlabs.io/v1
curl -4 -I --connect-timeout 10 https://api.anthropic.com/
curl -4 -I --connect-timeout 10 https://api.deepseek.com/
curl -4 -I --connect-timeout 10 https://api.x.ai/v1/chat/completions

bash verify-ai-egress.sh
```

اسکریپت `verify-ai-egress.sh` فقط connectivity را چک می‌کند؛ تأیید WAN2 از **Packet Capture روی pfSense** است.

---

## ۸) خاموش کردن `back-ir` (.33)

بعد از cutover موفق:

```bash
# روی 178.239.151.33
sudo systemctl disable --now wg-quick@wg-anthropic   # اگر فعال است
docker compose stop <backend> <test-backend>            # نام stack واقعی
# nginx / Arvan را به wkl-core یا front هدایت کن
```

روی pfSense Peer مربوط به `weekilaw-back-ir-33` را می‌توانی disable کنی.

---

## نکات

- **`AllowedIPs = 0.0.0.0/0` روی WG back-ir نگذار** — اگر هنوز WG روی .33 فعال است فقط Anthropic CIDR بماند.
- Alias `AI_API_HOSTS` را دوره‌ای refresh کن؛ OpenAI/Mistral/ElevenLabs CDN هستند.
- IPv6: اگر host AAAA resolve می‌کند و مسیر IPv6 از WAN1 می‌رود، در اپ **`curl -4`** یا disable IPv6 برای outbound API تا از مسیر IPv4/WAN2 برود.
- دو کانتینر را همزمان بالا نیاور روی back و core — اول core را تست، بعد back را stop.

---

## فایل‌های این پوشه

| فایل | کاربرد |
|------|--------|
| [domains.list](./domains.list) | دامنه‌های AI API |
| [generate-alias-ips.sh](./generate-alias-ips.sh) | خروجی IP برای Alias pfSense |
| [verify-ai-egress.sh](./verify-ai-egress.sh) | تست curl از host/کانتینر |

مهاجرت کامل کانتینر: [MIGRATE-FROM-BACK-IR.md](../MIGRATE-FROM-BACK-IR.md)

</div>
