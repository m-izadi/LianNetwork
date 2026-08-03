# مستند استقرار سرویس ویدیوکال (LiveKit) روی سرور جدید

**تاریخ:** ۱۴۰۵ / ۲۰۲۶  
**مخاطب:** تیم DevOps / سرور  
**هدف:** نصب از صفر یا انتقال سرویس ویدیوکال Weekilaw روی سرور جدا، بدون وابستگی به CDN برای ترافیک WebRTC/TURN

---

## ۱. خلاصه معماری

ویدیوکال فعلی روی **LiveKit** است (نه Matrix و نه Agora برای تماس جدید).

| لایه | نقش | روی کدام سرور؟ |
|------|-----|----------------|
| **Flutter / App** | اتصال WebSocket + WebRTC به LiveKit | کلاینت |
| **weekila_nodejs (API)** | ساخت اتاق، صدور JWT توکن LiveKit | می‌تواند روی سرور فعلی بماند |
| **LiveKit Server** | SFU، signaling، TURN داخلی | **سرور ویدیو (هدف این مستند)** |
| **Redis** | state برای LiveKit | کنار LiveKit |
| **Nginx + TLS** | `wss://` روی پورت ۴۴۳ | روی سرور ویدیو |
| **DNS** | دامنه signaling + دامنه TURN | پنل DNS / Arvan |

```
App ──WSS 443──► videocall.DOMAIN (CDN OK برای HTTPS فقط)
App ──UDP TURN──► turn.DOMAIN  →  IP مستقیم سرور (بدون CDN)
API (Node) ──mint JWT──► با LIVEKIT_API_KEY/SECRET مشترک با livekit.yaml
```

**نکته حیاتی:** CDN (مثل Arvan روی `185.143.x`) فقط TCP/HTTPS را خوب پراکسی می‌کند.  
**UDP و WebRTC/TURN باید مستقیم به IP عمومی سرور ویدیو برسند.** اگر DNS ویدیو فقط روی CDN باشد، تماس بدون VPN شکست می‌خورد.

---

## ۲. آنچه روی سرور فعلی (مرجع) داریم

| مورد | مقدار / توضیح |
|------|----------------|
| دسترسی SSH رایج | `78.110.124.181` |
| IP سرویس/رسانه (node_ip) | `78.110.124.181` (طبق تایید ادمین؛ نه IP خروجی STUN مثل `91.107.185.17`) |
| مسیر LiveKit | `/opt/livekit` |
| کانتینرها | `livekit` (`livekit/livekit-server`) + `livekit-redis` (`redis:7-alpine`) |
| Signaling URL | `wss://videocall.weekilaw.com` |
| TURN hostname | `turn.weekilaw.com` → A → `78.110.124.181` (بدون CDN) |
| TURN داخلی LiveKit | UDP `3479` (نه کانتینر coturn) |
| coturn جدا | برای Matrix است؛ LiveKit از TURN توکار خودش استفاده می‌کند مگر عمداً خاموش شود |
| گواهی SSL nginx | اغلب از مسیر `api.weekilaw.com` / wildcard `*.weekilaw.com` |
| کلیدها در Node `.env` | `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_URL` |

---

## ۳. پیش‌نیازهای سرور جدید

### ۳.۱ سخت‌افزار / سیستم‌عامل

- Ubuntu 22.04 LTS (یا مشابه)
- حداقل ۲ vCPU، ۴ GB RAM (برای ترافیک متوسط؛ برای بار بیشتر افزایش دهید)
- فضای دیسک کافی برای لاگ‌ها
- Docker + Docker Compose
- Nginx
- دسترسی root/sudo

### ۳.۲ شبکه و فایروال (روی IP عمومی سرور جدید)

| پروتکل | پورت | کاربرد |
|--------|------|--------|
| TCP | `80` | ACME / redirect |
| TCP | `443` | HTTPS / WSS (nginx → LiveKit `7880`) |
| TCP | `7880` | فقط localhost (از بیرون لازم نیست اگر nginx جلوی آن است) |
| TCP | `7881` | RTC TCP fallback |
| UDP | `3479` | TURN داخلی LiveKit |
| TCP | `5349` | TURN TLS (اختیاری، بعد از پایدار شدن UDP) |
| UDP | `30000–40000` | TURN relay |
| UDP | `50000–50100` | ICE / media |

**در پنل کلود / فایروال ارائه‌دهنده همین پورت‌ها را باز کنید.**  
`ufw` روی هاست اگر خاموش است، باز هم قوانین کلود مهم‌اند.

### ۳.۳ DNS (بدون CDN برای TURN)

فرض: دامنه همان `weekilaw.com` یا دامنه جدید.

| رکورد | نوع | مقدار | CDN |
|-------|-----|-------|-----|
| `videocall.NEWDOMAIN` | A یا CNAME | سرور ویدیو / یا پشت CDN فقط برای HTTPS | CDN برای HTTPS مجاز است |
| `turn.NEWDOMAIN` | **A** | **IP عمومی مستقیم سرور ویدیو** | **حتماً خاموش (DNS only)** |

چک:

```bash
dig +short turn.NEWDOMAIN
# باید فقط IP سرور ویدیو باشد — نه 185.143.x (CDN)
```

---

## ۴. نصب کامل LiveKit از صفر (سرور جدید)

این بخش نصب **از صفر** است: سیستم‌عامل → Docker → Redis → LiveKit → چک سلامت.  
قبل از شروع از ادمین بگیرید: **IP عمومی inbound** سرور، دامنه‌های `videocall` و `turn`.

جایگزین‌ها در دستورات زیر:

| متغیر | معنی |
|--------|------|
| `NEW_PUBLIC_IP` | IP عمومی inbound (همان که در DNS `turn` می‌گذارید) |
| `turn.NEWDOMAIN` | مثلاً `turn.weekilaw.com` |
| `videocall.NEWDOMAIN` | مثلاً `videocall.weekilaw.com` |
| `YOUR_API_KEY` / `YOUR_API_SECRET` | کلید مشترک با Node |

---

### ۴.۱ آماده‌سازی سیستم‌عامل (Ubuntu)

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release \
  nginx dnsutils openssl ufw

# تشخیص IP (ممکن است egress با inbound فرق کند — از ادمین تایید بگیرید)
curl -4 ifconfig.me
echo
hostname -I
ip -4 addr show
```

اگر `ufw` را روشن می‌کنید:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 7881/tcp
sudo ufw allow 3479/udp
sudo ufw allow 5349/tcp
sudo ufw allow 30000:40000/udp
sudo ufw allow 50000:50100/udp
sudo ufw enable
sudo ufw status verbose
```

> قوانین **پنل کلود** (Arvan/Hetzner/…) را جدا باز کنید؛ فقط ufw کافی نیست.

---

### ۴.۲ نصب Docker Engine + Compose plugin

```bash
# اگر Docker از قبل نصب است، این بلوک را رد کنید:
# docker --version && docker compose version

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
# یک‌بار logout/login یا: newgrp docker

docker --version
docker compose version
```

Pull ایمیج‌ها (اختیاری ولی مفید برای سرعت استارت):

```bash
docker pull livekit/livekit-server:latest
docker pull redis:7-alpine
```

---

### ۴.۳ ساخت کلید API

```bash
# نام کلید (می‌تواند رشته ساده هم باشد؛ در Weekilaw فعلی گاهی devkey بوده)
openssl rand -hex 16
# → این را YOUR_API_KEY بگیرید

openssl rand -hex 32
# → این را YOUR_API_SECRET بگیرید
```

این دو مقدار را:

1. داخل `livekit.yaml` → بخش `keys:`
2. داخل `.env` بک‌اند → `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET`

**دقیقاً یکی** نگه دارید. عدم تطابق = توکن نامعتبر / join fail.

---

### ۴.۴ دایرکتوری پروژه LiveKit

```bash
sudo mkdir -p /opt/livekit/certs
sudo chown -R "$USER":"$USER" /opt/livekit
cd /opt/livekit
```

ساختار نهایی:

```text
/opt/livekit/
├── docker-compose.yml
├── livekit.yaml
└── certs/          # برای TURN TLS اختیاری
    ├── fullchain.pem
    └── privkey.pem
```

---

### ۴.۵ فایل `docker-compose.yml`

```bash
cd /opt/livekit
cat > docker-compose.yml <<'EOF'
services:
  livekit-redis:
    image: redis:7-alpine
    container_name: livekit-redis
    restart: unless-stopped
    network_mode: host
    command: ["redis-server", "--bind", "127.0.0.1", "--port", "6379"]

  livekit:
    image: livekit/livekit-server:latest
    container_name: livekit
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./livekit.yaml:/etc/livekit.yaml:ro
      - ./certs:/certs:ro
    command: ["--config", "/etc/livekit.yaml"]
    depends_on:
      - livekit-redis
EOF
```

**چرا `network_mode: host`؟**  
WebRTC/TURN به بازه بزرگ UDP نیاز دارد. Host network ساده‌ترین و پایدارترین حالت برای SFU روی یک نود است.

**تداخل پورت:** اگر روی همین سرور Redis دیگری روی `6379` دارید، یا پورت Redis LiveKit را عوض کنید (مثلاً `6380`) و همان را در `livekit.yaml` بنویسید، یا Redis جدا نگه دارید و فقط `127.0.0.1:6379` را برای LiveKit bind کنید (مثل بالا).

---

### ۴.۶ فایل `livekit.yaml`

```bash
cd /opt/livekit

# مقادیر را جایگزین کنید، بعد فایل را ذخیره کنید:
cat > livekit.yaml <<'EOF'
port: 7880
bind_addresses:
  - ""

redis:
  address: 127.0.0.1:6379

rtc:
  tcp_port: 7881
  port_range_start: 50000
  port_range_end: 50100
  # مهم: IP ثابت inbound — اجازه ندهید STUN IP اشتباه ست کند
  use_external_ip: false
  node_ip: NEW_PUBLIC_IP

keys:
  YOUR_API_KEY: YOUR_API_SECRET

turn:
  enabled: true
  domain: turn.NEWDOMAIN
  udp_port: 3479
  # فاز اول: بدون TLS. بعد از کار کردن UDP، اختیاری:
  # tls_port: 5349
  # cert_file: /certs/fullchain.pem
  # key_file: /certs/privkey.pem
logging:
  level: info
EOF
```

سپس با ادیتور واقعی `NEW_PUBLIC_IP` و کلیدها و دامنه را جایگزین کنید:

```bash
nano /opt/livekit/livekit.yaml
# یا: vim /opt/livekit/livekit.yaml
```

**قوانین کانفیگ:**

| تنظیم | مقدار درست |
|--------|------------|
| `node_ip` | IP inbound تایید ادمین (نه لزوماً خروجی `curl ifconfig.me`) |
| `use_external_ip` | `false` وقتی IP ثابت می‌دهید |
| `turn.domain` | hostname که **فقط** به همان IP resolve می‌شود (بدون CDN) |
| `turn.udp_port` | `3479` (Matrix coturn معمولاً `3478` — قاطی نکنید) |
| `keys` | همان جفت کلید Node |

---

### ۴.۷ DNS قبل از تست واقعی

حداقل برای TURN:

```text
turn.NEWDOMAIN   A   NEW_PUBLIC_IP    (CDN/proxy OFF)
```

برای signaling:

```text
videocall.NEWDOMAIN   A   NEW_PUBLIC_IP
# یا پشت CDN فقط برای TCP 443 — UDP هرگز از CDN برای TURN نرود
```

چک:

```bash
dig +short turn.NEWDOMAIN
# فقط NEW_PUBLIC_IP
```

---

### ۴.۸ استارت سرویس

```bash
cd /opt/livekit
docker compose up -d
sleep 5

docker ps --filter name=livekit
docker logs livekit --tail 40
docker logs livekit-redis --tail 10
```

لاگ سالم تقریباً:

```text
connecting to redis ... addr=127.0.0.1:6379
Starting TURN server ... turn.portUDP=3479
starting LiveKit server ... portHttp=7880 nodeIP=NEW_PUBLIC_IP ... rtc.portTCP=7881
```

اگر crash روی cert دیدید (`TURN tls cert required` / `no such file`):

```yaml
# در livekit.yaml خطوط tls_port / cert_file / key_file را کامنت کنید
```

بعد:

```bash
cd /opt/livekit && docker compose up -d
```

---

### ۴.۹ تایید نصب (بدون اپ)

```bash
# پورت signaling
ss -tlnp | grep 7880
# پورت TURN
ss -ulnp | grep 3479

# health محلی
curl -sS -o /dev/null -w "local:%{http_code}\n" http://127.0.0.1:7880/
curl -sS http://127.0.0.1:7880/ | head -c 80
echo

# Redis
redis-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null || \
  docker exec livekit-redis redis-cli ping
```

انتظار:

- `7880` LISTEN
- `3479` UDP
- HTTP محلی ≈ `200` و بدنه شبیه `OK`
- Redis: `PONG`

دستورهای روزمره:

```bash
cd /opt/livekit
docker compose ps
docker compose restart
docker compose logs -f livekit
docker compose down          # توقف کامل
docker compose up -d         # روشن مجدد
```

به‌روزرسانی ایمیج:

```bash
cd /opt/livekit
docker compose pull
docker compose up -d
docker image prune -f
```

---

### ۴.۱۰ (اختیاری) TURN TLS بعد از پایدار شدن UDP

فقط وقتی تماس با UDP 3479 بدون VPN کار می‌کند:

```bash
# کپی گواهی wildcard یا گواهی turn.NEWDOMAIN
sudo cp /etc/letsencrypt/live/SOME_CERT/fullchain.pem /opt/livekit/certs/
sudo cp /etc/letsencrypt/live/SOME_CERT/privkey.pem /opt/livekit/certs/
sudo chmod 644 /opt/livekit/certs/fullchain.pem
sudo chmod 600 /opt/livekit/certs/privkey.pem
```

در `livekit.yaml` زیر `turn:`:

```yaml
  tls_port: 5349
  cert_file: /certs/fullchain.pem
  key_file: /certs/privkey.pem
```

```bash
cd /opt/livekit && docker compose up -d
docker logs livekit --tail 20
```

اگر دوباره crash کرد → TLS را بردارید؛ UDP کافی است برای شروع.

---

### ۴.۱۱ نصب با باینری رسمی LiveKit (جایگزین Docker — اختیاری)

اگر سیاست سازمان Docker نمی‌خواهد:

```bash
# مثال — نسخه را از GitHub Releases LiveKit چک کنید
curl -sSL https://get.livekit.io | bash
# یا دانلود باینری livekit-server

# Redis جدا نصب کنید:
sudo apt install -y redis-server
sudo systemctl enable --now redis-server

# سپس:
livekit-server --config /opt/livekit/livekit.yaml
```

برای production ترجیح Weekilaw: **همان Docker Compose بخش ۴.۵** (مثل سرور فعلی `/opt/livekit`).

---

## ۵. Nginx + TLS برای WSS

### ۵.۱ گواهی

گزینه‌ها:

1. کپی wildcard موجود `*.weekilaw.com` (اگر دامنه همان است)
2. یا صدور جدید با certbot (webroot / DNS challenge)

مسیر نمونه (مثل سرور فعلی):

```text
ssl_certificate     /etc/letsencrypt/live/api.weekilaw.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/api.weekilaw.com/privkey.pem;
```

### ۵.۲ نمونه vhost `videocall`

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name videocall.NEWDOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name videocall.NEWDOMAIN;

    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://127.0.0.1:7880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -sI https://videocall.NEWDOMAIN/ | head -5
# 502 = LiveKit پایین؛ 200/OK یا پاسخ LiveKit = خوب
# برای /rtc با HEAD ممکن است 401/404 بیاید — مهم این است 502 نباشد
```

### ۵.۳ (اختیاری) vhost سبک برای `turn.NEWDOMAIN`

UDP TURN نیاز به nginx ندارد. فقط اگر می‌خواهید HTTPS روی همان hostname داشته باشید، SSL را مثل بقیه دامنه‌ها کپی کنید.

---

## ۶. اتصال بک‌اند (weekila_nodejs)

بک‌اند اتاق می‌سازد و JWT می‌دهد؛ لازم نیست LiveKit روی همان ماشین Node باشد.

در `.env` سرور API:

```env
LIVEKIT_API_KEY=YOUR_API_KEY
LIVEKIT_API_SECRET=YOUR_API_SECRET
LIVEKIT_URL=wss://videocall.NEWDOMAIN
# اختیاری:
# LIVEKIT_TOKEN_TTL_SECONDS=21600
```

سپس Node را ریستارت کنید و در استارت‌لاگ ببینید:

```text
[LiveKit] configured — url=wss://videocall.NEWDOMAIN
```

APIهای مرتبط:

- `POST /api/appointments/:id/create-room`
- `POST /api/appointments/:id/join-room`
- `POST /api/appointments/join-by-code`
- مسیرهای مشابه برای legal-expert و LawView live

پاسخ join شامل تقریباً:

```json
{
  "liveKitUrl": "wss://videocall.NEWDOMAIN",
  "roomName": "...",
  "token": "eyJ..."
}
```

---

## ۷. اپ Flutter

fallback در کد:

```dart
ApiConstants.liveKitUrl // پیش‌فرض: wss://videocall.weekilaw.com
```

اگر API فیلد `liveKitUrl` را برگرداند، کلاینت همان را ترجیح می‌دهد.  
برای دامنه جدید:

1. یا فقط `.env` بک‌اند را عوض کنید (ترجیحی)، یا  
2. ثابت `ApiConstants.liveKitUrl` را در بیلد جدید به‌روز کنید.

---

## ۸. چک‌لیست تست (قبل از Go-Live)

### ۸.۱ زیرساخت

- [ ] `dig +short turn.NEWDOMAIN` → فقط IP سرور ویدیو
- [ ] `docker ps` → `livekit` و `livekit-redis` Up
- [ ] لاگ: `nodeIP` = IP تاییدشده ادمین
- [ ] `https://videocall.NEWDOMAIN` بدون 502
- [ ] UDP 3479 / 30000–40000 / 50000–50100 از اینترنت باز

### ۸.۲ تماس واقعی

- [ ] دو دستگاه (ترجیحاً موبایل LTE، **بدون VPN**)
- [ ] رزرو تایید + پرداخت شده → «ورود به جلسه»
- [ ] صدا/تصویر دو طرفه
- [ ] حین تماس روی سرور:

```bash
sudo tcpdump -ni any udp port 3479 -c 20
```

باید بسته **ورودی** از IP کلاینت دیده شود.

### ۸.۳ Smoke با LiveKit Meet (اختیاری)

```bash
# روی سرور ویدیو — توکن تست با lk یا SDK
# سپس https://meet.livekit.io → Custom → wss://videocall.NEWDOMAIN
```

---

## ۹. مراحل مهاجرت از سرور قدیم به جدید (ترتیب پیشنهادی)

1. سرور جدید: Docker + LiveKit + Redis + nginx + TLS  
2. DNS موقت تست (مثلاً `videocall-new` / `turn-new`) → تست کامل  
3. هم‌تراز کردن کلیدها با Node (یا کلید جدید مشترک)  
4. سوییچ `LIVEKIT_URL` در `.env` API به دامنه جدید  
5. سوییچ DNS اصلی `videocall` / `turn` به سرور جدید (TURN بدون CDN)  
6. مانیتور ۲۴–۴۸ ساعت؛ سپس خاموش کردن LiveKit روی سرور قدیم  
7. Matrix/coturn روی سرور قدیم اگر هنوز لازم است، جدا بماند (وابسته به LiveKit نیست)

---

## ۱۰. اشتباهات رایج (از تجربه سرور فعلی)

| مشکل | علت | درمان |
|------|-----|--------|
| تماس فقط با VPN کار می‌کند | TURN پشت CDN یا IP اشتباه در ICE | `turn` → A مستقیم؛ `node_ip` = IP inbound |
| `nodeIP` در لاگ با DNS یکی نیست | STUN IP egress (مثل `91.107…`) | `use_external_ip: false` + `node_ip` ثابت |
| 502 روی `/rtc` | LiveKit down / crash روی cert TURN TLS | اول بدون `tls_port` بالا بیاورید |
| Missing / invalid token | کلید Node ≠ کلید `livekit.yaml` | یکسان‌سازی KEY/SECRET |
| فقط signaling وصل، بدون تصویر | UDP بسته در فایروال کلود | باز کردن پورت‌های جدول بخش ۳ |

---

## ۱۱. تفکیک LiveKit و coturn

روی سرور فعلی هر دو دیده می‌شوند:

- `livekit` → TURN **توکار** (پورت ۳۴۷۹ در کانفیگ LiveKit)
- `coturn` → معمولاً برای **Matrix**

برای سرور ویدیو **جدید** نیازی به نصب coturn نیست مگر بخواهید Matrix را هم منتقل کنید یا عمداً LiveKit را به TURN خارجی وصل کنید.

---

## ۱۲. حداقل اطلاعات لازم از ادمین سرور جدید

لطفاً قبل از استقرار این‌ها را تایید کنید:

1. IP عمومی **inbound** برای سرویس (برای DNS `turn` و `node_ip`)  
2. آیا SSH IP با IP سرویس یکی است یا جدا؟  
3. دامنه نهایی: `videocall…` و `turn…`  
4. امکان باز کردن پورت‌های UDP ذکرشده در فایروال کلود  
5. مسیر یا صدور گواهی TLS برای `videocall`

---

## ۱۳. خلاصه یک‌خطی برای لید

> سرویس ویدیو = کانتینر LiveKit + Redis روی سرور جدید، nginx با WSS، دامنه `turn` مستقیم به IP سرور بدون CDN، کلیدهای API مشترک با Node، و باز بودن UDP برای TURN/مدیا. بک‌اند و اپ فقط URL و کلید را عوض می‌کنند؛ منطق اتاق همان `create-room` / `join-room` می‌ماند.

---

**تهیه‌کننده:** تیم توسعه Weekilaw  
**مرجع عملیاتی فعلی:** `/opt/livekit` روی `78.110.124.181` با `turn.weekilaw.com` و `wss://videocall.weekilaw.com`
