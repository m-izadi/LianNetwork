<div dir="rtl">

# WireGuard به pfSense — فقط `api.anthropic.com`

ماشین: **`weekilaw-com-back-ir` / `178.239.151.33`**

هدف: ترافیک **`api.anthropic.com`** از تانل WireGuard به pfSense برود؛ SSTP / LAN (`192.168.88.0/24`) و بقیه اینترنت مثل قبل بمانند.

## چرا CIDR به‌جای فقط دامنه؟

Anthropic برای inbound API بازهٔ ثابت اعلام کرده:

| جهت | IPv4 |
|-----|------|
| inbound (همین API) | **`160.79.104.0/23`** |

منبع: [Anthropic IP addresses](https://platform.claude.com/docs/en/api/ip-addresses)

`api.anthropic.com` الان به همین بازه resolve می‌شود (مثلاً `160.79.104.10`).  
در WireGuard با `AllowedIPs = 160.79.104.0/23` فقط همین مسیر اضافه می‌شود؛ **default route عوض نمی‌شود**.

```text
host (.33)
  ├─ eth0          → اینترنت عادی (مثل قبل)
  ├─ ppp0 / SSTP   → 192.168.88.0/24 (مثل قبل)
  └─ wg-anthropic  → فقط 160.79.104.0/23 → pfSense → اینترنت خارج
```

---

## ۱) سمت pfSense

1. **VPN → WireGuard → Tunnels**  
   - یک تانل بساز (یا از تانل موجود استفاده کن).  
   - Listen Port مثلاً `51820`.  
   - Interface Assign اگر لازم است (مثلاً `OPT_WG`).

2. **Peers** روی همان تانل:
   - Peer Name: `weekilaw-back-ir-33`
   - Public Key: کلید عمومی کلاینت روی `.33` (پایین می‌سازی)
   - Allowed IPs: آدرس تانل کلاینت، مثلاً `10.66.66.2/32`
   - (اختیاری) Preshared Key مشترک

3. **Firewall → Rules** روی اینترفیس WireGuard:
   - Allow از `10.66.66.2` به `160.79.104.0/23` (TCP 443 کافی است اگر سخت‌گیرانه می‌خواهی)
   - یا موقتاً Allow any برای تست

4. **Outbound NAT** (خیلی مهم):
   - ترافیک از شبکه WG باید با WAN pfSense خارج شود (Hybrid/Manual outbound NAT با rule برای اینترفیس WG → WAN address).
   - بدون NAT، Anthropic جواب نمی‌دهد.

5. فایروال/کلود جلوی pfSense: UDP `51820` از اینترنت (حداقل از `178.239.151.33`) باز باشد.

---

## ۲) سمت سرور `.33`

```bash
sudo apt-get update
sudo apt-get install -y wireguard wireguard-tools

# کلید کلاینت
umask 077
wg genkey | sudo tee /etc/wireguard/anthropic.client.key | wg pubkey | sudo tee /etc/wireguard/anthropic.client.pub
sudo chmod 600 /etc/wireguard/anthropic.client.key /etc/wireguard/anthropic.client.pub
sudo cat /etc/wireguard/anthropic.client.pub   # این را در Peer pfSense بگذار
```

کانفیگ:

```bash
sudo cp /path/to/repo/.../wg-anthropic.conf.example /etc/wireguard/wg-anthropic.conf
sudo chmod 600 /etc/wireguard/wg-anthropic.conf
sudo nano /etc/wireguard/wg-anthropic.conf
```

پر کن:

| فیلد | مقدار |
|------|--------|
| `PrivateKey` | محتوای `anthropic.client.key` |
| `Address` | مثلاً `10.66.66.2/32` (همان Allowed IPs روی pfSense) |
| `PublicKey` (Peer) | Public Key تانل/سرور pfSense |
| `Endpoint` | IP یا hostname عمومی pfSense + پورت |

روشن کردن:

```bash
sudo systemctl enable --now wg-quick@wg-anthropic
sudo wg show
ip route | grep 160.79.104
```

باید چیزی شبیه این باشد:

```text
160.79.104.0/23 dev wg-anthropic scope link
```

و **نباید** default از `wg-anthropic` باشد.

---

## ۳) تست

```bash
# مسیر Anthropic از WG
ip route get 160.79.104.10
# انتظار: via wg-anthropic  (یا dev wg-anthropic)

# بقیه مثل قبل
ip route get 1.1.1.1
ip route get 192.168.88.242

dig +short A api.anthropic.com
curl -4 -I --connect-timeout 10 https://api.anthropic.com/

# اسکریپت همین پوشه
sudo bash verify-anthropic-route.sh
```

روی pfSense در Diagnostics → States / Packet Capture روی اینترفیس WG باید ترافیک به `160.79.104.x:443` دیده شود.

---

## ۴) خاموش کردن / برگشت

```bash
sudo systemctl disable --now wg-quick@wg-anthropic
# route مخصوص Anthropic خودش پاک می‌شود؛ SSTP دست نخورده می‌ماند
```

---

## نکات

- **`AllowedIPs` را `0.0.0.0/0` نگذار** — کل ترافیک می‌رود سمت pfSense.
- **`DNS=` در `[Interface]` نگذار** مگر فقط resolver خاص بخواهی؛ روی این host خطر تداخل با بقیه سرویس‌ها دارد.
- SSTP (`sstp-ui4`) و مسیر `192.168.88.0/24` را دست نزن.
- اگر بعداً Anthropic بازه را عوض کرد، فقط `AllowedIPs` و NAT/فایروال pfSense را به‌روز کن.
- IPv6: اگر host IPv6 دارد و AAAA برای Anthropic resolve می‌شود، یا IPv6 را برای آن مسیر هم از WG بفرست (`2607:6bc0::/48`) یا موقتاً `curl -4` / disable IPv6 برای آن فرایند تا از مسیر IPv4 WG برود.

</div>
