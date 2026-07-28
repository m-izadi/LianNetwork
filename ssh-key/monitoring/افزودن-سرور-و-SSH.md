# افزودن سرور پایش + SSH

## دو سرور جدا

| | **سرور بات** | **سرور پایش** |
|---|-------------|----------------|
| کار | اجرای `monitoring_bot` | Docker + سرویس‌های شما |
| کلید خصوصی | اینجا می‌ماند | — |
| کلید عمومی | — | اینجا در `authorized_keys` |
| فایل تنظیم | `config.js` روی سرور بات | — |

```
سرور بات (لینوکس)  ──SSH──►  سرور پایش ۱
                 ──SSH──►  سرور پایش ۲
```

---

## ۱ — روی سرور بات: ساخت کلید

```bash
ssh user@IP-سرور-بات
```

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/monitoring_bot -N ""
chmod 600 ~/.ssh/monitoring_bot
```

```bash
cat ~/.ssh/monitoring_bot.pub
```

خروجی را کپی کنید (یک خط `ssh-ed25519 ...`).

> اگر بات با کاربر دیگری اجرا می‌شود (مثلاً `node`)، کلید را به همان کاربر بدهید:

```bash
sudo mkdir -p /home/node/.ssh
sudo cp ~/.ssh/monitoring_bot /home/node/.ssh/
sudo cp ~/.ssh/monitoring_bot.pub /home/node/.ssh/
sudo chown -R node:node /home/node/.ssh
sudo chmod 600 /home/node/.ssh/monitoring_bot
```

مسیر در `config.js` = `/home/node/.ssh/monitoring_bot`

---

## ۲ — روی سرور پایش: اجازه ورود

```bash
ssh root@IP-سرور-پایش
```

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
```

کلید `.pub` را paste کنید → `Ctrl+O` → Enter → `Ctrl+X`

```bash
chmod 600 ~/.ssh/authorized_keys
exit
```

**یا** از سرور بات:

```bash
ssh-copy-id -i ~/.ssh/monitoring_bot.pub -p 22 root@IP-سرور-پایش
```

---

## ۳ — تست از سرور بات

```bash
ssh -i ~/.ssh/monitoring_bot -p 22 root@IP-سرور-پایش
```

```bash
docker ps
exit
```

بدون رمز وارد شد + `docker ps` لیست داد = OK.

---

## ۴ — `config.js` روی سرور بات

```bash
cd /opt/monitoring_bot
cp config.example.js config.js
nano config.js
```

یک سرور جدید داخل `servers`:

```javascript
export default {
  servers: [
    {
      name: "سرور اصلی",
      ip: "178.239.151.33",
      sshPort: 22,
      sshUser: "root",
      sshPrivateKey: "/root/.ssh/monitoring_bot",
      endpoints: [],
    },
  ],
};
```

آستانه و فاصله چک در **`.env`** (نه config.js):

```bash
THRESHOLD_CPU=80
THRESHOLD_RAM=85
THRESHOLD_DISK=90
HTTP_CHECK_INTERVAL_MS=300000
MONITOR_REMINDER_INTERVAL_MS=1800000
```

چند سرور پایش:

```javascript
export default {
  servers: [
  {
    name: "بک‌اند",
    ip: "178.239.151.33",
    sshPort: 22,
    sshUser: "root",
    sshPrivateKey: "/root/.ssh/monitoring_bot",
    endpoints: [],
  },
  {
    name: "وب",
    ip: "130.185.75.96",
    sshPort: 2222,
    sshUser: "root",
    sshPrivateKey: "/root/.ssh/monitoring_bot",
    endpoints: [],
  },
  ],
};
```

| فیلد | مقدار |
|------|--------|
| `name` | اسم در تلگرام |
| `ip` | IP **سرور پایش** |
| `sshPort` | پورت SSH همان سرور |
| `sshUser` | کاربر SSH |
| `sshPrivateKey` | مسیر کلید روی **سرور بات** (بدون `.pub`) |
| `endpoints` | فقط container → `[]` |

> یک کلید کافی است — `.pub` را روی **هر** سرور پایش اضافه کنید.

---

## ۵ — اعمال و ریستارت (سرور بات)

```bash
cd ~/monitorbot
npm run validate
pm2 restart monitoring-bot
```

### Docker

`config.js` داخل image نیست — باید mount شود (در `docker-compose.yml` هست).

```bash
cd ~/monitorbot
cp config.example.js config.js
nano config.js
```

مسیر کلید داخل کانتینر:

```javascript
sshPrivateKey: "/app/ssh/monitoring_bot",
```

```bash
export SSH_PRIVATE_KEY_HOST=/home/user/.ssh/monitoring_bot
export DOCKER_UID=$(id -u)
export DOCKER_GID=$(id -g)
docker compose up -d --build
docker compose logs -f
```

---

## ۶ — تست تلگرام

```
/servers
/containers سرور اصلی
/status
```

`سرور اصلی` = همان `name` در config.

---

## ۷ — زمان‌بندی

| مورد | زمان |
|------|------|
| اولین چک | ۵ دقیقه baseline |
| بعد از آن | down شد → هشدار |
| یادآوری | هر ۳۰ دقیقه تا رفع |

---

## خطاها

```bash
# Permission denied
cat ~/.ssh/monitoring_bot.pub   # روی سرور پایش دوباره authorized_keys

# کلید باز است
chmod 600 ~/.ssh/monitoring_bot

# بات به کلید دسترسی ندارد
ls -la ~/.ssh/monitoring_bot
sudo chown node:node /home/node/.ssh/monitoring_bot

# timeout
ping IP-سرور-پایش
nc -zv IP-سرور-پایش 22

# docker
ssh -i ~/.ssh/monitoring_bot root@IP-سرور-پایش "docker ps"
```

---

## چک‌لیست

- [ ] کلید روی **سرور بات** ساخته شد
- [ ] `.pub` روی **سرور پایش** است
- [ ] `ssh -i` از بات به پایش بدون رمز
- [ ] `docker ps` روی سرور پایش OK
- [ ] `config.js` → `servers` به‌روز شد
- [ ] `npm run validate` → `ok: true`
- [ ] `pm2 restart monitoring-bot`
- [ ] `/containers` در تلگرام OK

---

**هرگز** فایل `monitoring_bot` (بدون `.pub`) را نفرستید.
