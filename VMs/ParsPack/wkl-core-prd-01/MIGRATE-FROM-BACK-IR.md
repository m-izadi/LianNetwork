<div dir="rtl">

# انتقال دو کانتینر از `back-ir` به `wkl-core-prd-01`

| | back (قدیم) | core (جدید) |
|---|-------------|-------------|
| Host | `weekilaw-com-back-ir` | `wkl-core-prd-01` |
| IP عمومی | `178.239.151.33` | `158.255.74.75` |
| LAN pfSense | — | `192.168.77.3` |
| سرویس‌های هدف | `api.weekilaw.com` + `test.weekilaw.com` (یا stack docker همان دو کانتینر) | همان |

ترافیک AI API از **اینترفیس دوم pfSense** → [ai-api-egress-pfsense/README.md](./ai-api-egress-pfsense/README.md)

---

## پیش‌نیاز

- [ ] pfSense: Gateway WAN2 + Alias + Policy rule + Outbound NAT (طبق README بالا)
- [ ] دسترسی SSH به `158.255.74.75` (پورت طبق convention — معمولاً `5566` برای core)
- [ ] Mongo / Redis / Minio و وابستگی‌ها روی core یا reachable از `192.168.77.x`
- [ ] backup از `.env` و volumeهای docker روی back

---

## فاز ۱ — آماده‌سازی روی `wkl-core-prd-01`

```bash
ssh -p5566 izadi@158.255.74.75   # یا user مناسب

# ساختار docker (مسیر واقعی روی سرور)
ls /srv/docker-compose/   # یا مسیر deploy شما

# کپی env از back (مثال)
scp -P2222 root@178.239.151.33:/path/to/backend/.env ./backend.env
scp -P2222 root@178.239.151.33:/path/to/test_backend/.env ./test.env
```

1. Image / compose را روی core deploy کن (همان tag که روی back بود).
2. پورت‌ها را با nginx داخلی یا reverse proxy هماهنگ کن:
   - `3000` → api اصلی
   - `5000` → test
3. **قبل از cutover** کانتینرها را با `docker compose up -d` بالا بیاور و healthcheck بزن.
4. از **داخل کانتینر** curl به AI API بزن (بعد از تنظیم pfSense).

---

## فاز ۲ — تست بدون قطع back

```bash
# روی core — از host
bash /path/to/ai-api-egress-pfsense/verify-ai-egress.sh

# health اپ
curl -sS http://127.0.0.1:3000/health   # endpoint واقعی
curl -sS http://127.0.0.1:5000/health
```

- [ ] pfSense States نشان می‌دهد HTTPS AI از WAN2 می‌رود
- [ ] login / یک flow واقعی با LLM روی core کار می‌کند
- [ ] Mongo و سرویس‌های داخلی از core OK

---

## فاز ۳ — Cutover ترافیک کاربر

ترتیب پیشنهادی (کم‌ریسک):

1. **DNS / Arvan / nginx**: upstream را موقتاً به IP core (`158.255.74.75`) یا LAN در صورت proxy داخلی بده — یا فقط test را اول switch کن.
2. `test.weekilaw.com` → core؛ smoke test.
3. `api.weekilaw.com` → core.
4. مانیتور error rate و latency ۱۵–۳۰ دقیقه.

اگر Arvan روی back (`151.33`) است، origin را به core تغییر بده یا traffic را از back بردار.

---

## فاز ۴ — خاموش کردن back (.33)

```bash
ssh -p2222 root@178.239.151.33

# کانتینرهای منتقل‌شده
cd /path/to/docker-compose
docker compose stop backend test_backend   # نام سرویس واقعی

# WireGuard Anthropic — دیگر لازم نیست
sudo systemctl disable --now wg-quick@wg-anthropic 2>/dev/null || true

# تأیید چیزی روی 3000/5000 listen نمی‌کند
ss -tlnp | grep -E ':3000|:5000'
```

روی back اگر فقط admin / weeshion مانده، nginx را برای hostهای منتقل‌شده disable کن.

---

## فاز ۵ — rollback

اگر مشکل بود:

1. DNS/Arvan را به `178.239.151.33` برگردان.
2. `docker compose start` روی back.
3. core را stop کن تا دوبل نشود.

---

## چک‌لیست نهایی

- [ ] دو کانتینر فقط روی core در حال اجرا
- [ ] ترافیک AI از WAN2 pfSense (نه اینترنت مستقیم ایران)
- [ ] back: WG anthropic off؛ پورت‌های 3000/5000 بسته یا فقط سرویس‌های باقی‌مانده
- [ ] مستندات env/secret در جای امن (نه در git)

</div>
