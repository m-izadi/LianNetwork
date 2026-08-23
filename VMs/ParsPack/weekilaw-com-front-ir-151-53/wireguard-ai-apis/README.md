<div dir="rtl">

# AI APIها از VPN خارج — روی `weekilaw-com-front-ir` (`178.239.151.53`)

وقتی اینترنت `back-ir` (`151.33`) خراب است و سرویس را به **front** منتقل می‌کنی، این دامنه‌ها باید از egress خارج (WireGuard) بروند؛ بقیه ترافیک مثل قبل بماند (`eth0` / SSTP / `ens23`).

| دامنه | کاربرد |
|--------|--------|
| `api.mistral.ai` | Mistral |
| `api.openai.com` | OpenAI |
| `api.elevenlabs.io` | ElevenLabs |
| `api.anthropic.com` | Anthropic (`160.79.104.0/23`) |
| `api.deepseek.com` | DeepSeek |
| `api.x.ai` | xAI |

مسیر URL مثل `/v1` در روتینگ مهم نیست؛ فقط **hostname → IP** مهم است.

```text
سرویس روی .53
  ├─ eth0 178.239.151.53     → اینترنت عادی ایران / مثل قبل
  ├─ ens23 192.168.183.2     → دست نزن (شبکهٔ جدا)
  ├─ SSTP / virbr0           → LAN شرکت اگر لازم است
  └─ wg-ai → فقط IPهای لیست بالا → سرور خارج (NAT) → APIها
```

---

## پیش‌نیاز روی سرور خارج (egress)

همان ماشینی که Endpoint WireGuard است (مثلاً `185.208.175.224` یا Cloudz `144.172.117.7`):

1. Peer جدید برای front با `AllowedIPs = 10.20.1.3/32` (back قبلاً `.2` بود)
2. `ip_forward=1` + **MASQUERADE** برای `10.20.1.0/24` روی WAN  
   بدون NAT جواب API برنمی‌گردد.

---

## نصب روی front (`.53`)

```bash
sudo apt-get install -y wireguard wireguard-tools

# کلید
umask 077
wg genkey | sudo tee /etc/wireguard/ai.client.key | wg pubkey | sudo tee /etc/wireguard/ai.client.pub
sudo cat /etc/wireguard/ai.client.pub   # → Peer روی egress

# کانفیگ
sudo cp wg-ai.conf.example /etc/wireguard/wg-ai.conf
sudo nano /etc/wireguard/wg-ai.conf
# PrivateKey / Address=10.20.1.3/24 / Peer PublicKey / Endpoint

sudo cp domains.list /etc/wireguard/ai-apis-domains.list
sudo cp sync-ai-routes.sh /usr/local/bin/sync-ai-routes.sh
sudo chmod 755 /usr/local/bin/sync-ai-routes.sh
sudo cp ai-api-routes.service ai-api-routes.timer /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now wg-quick@wg-ai
sudo systemctl enable --now ai-api-routes.timer
sudo systemctl start ai-api-routes.service
```

`Table = off` عمدی است: default route عوض نمی‌شود؛ فقط اسکریپت `/32` برای IPهای resolve‌شده می‌گذارد. هر ۵ دقیقه DNS را دوباره می‌گیرد (CDNها IP عوض می‌کنند).

---

## تست

```bash
wg show
systemctl status ai-api-routes.timer --no-pager
cat /var/lib/ai-api-routes/ips.cur

# باید از wg-ai برود
ip route get "$(getent ahostsv4 api.openai.com | awk '{print $1; exit}')"
ip route get 160.79.104.10

# نباید از wg-ai برود
ip route get 1.1.1.1
ip route get 192.168.183.1

curl -4 -I --connect-timeout 10 https://api.openai.com/
curl -4 -I --connect-timeout 10 https://api.anthropic.com/
curl -4 -I --connect-timeout 10 https://api.mistral.ai/
```

---

## انتقال سرویس از back به front (چک‌لیست)

1. روی front: WG + timer بالا (بالا)
2. کانتینر/سرویس را روی `.53` بالا بیاور (env همان API keyها)
3. nginx / DNS / Arvan را به IP یا هاست front بده اگر از بیرون می‌آید
4. روی back سرویس را stop کن تا دوبل نشود
5. SSTP/`iran-routing` را برای LAN جدا نگه دار؛ با WG قاطی نکن

---

## دامنه اضافه کردن

```bash
sudo nano /etc/wireguard/ai-apis-domains.list
sudo systemctl start ai-api-routes.service
```

---

## نکات

- **`AllowedIPs = 0.0.0.0/0` بدون `Table=off` نگذار** — کل اینترنت از VPN می‌رود.
- `ens23` (`192.168.183.2`) را دست نزن مگر بدانی چیست.
- اگر بعد از ریستارت تانل LAN قطع شد: [AFTER-REBOOT.md](../AFTER-REBOOT.md)
- اگر فقط Anthropic لازم بود روی back: الگوی قدیمی در `weekilaw-com-back-ir-151.33/wireguard-anthropic/`

</div>
