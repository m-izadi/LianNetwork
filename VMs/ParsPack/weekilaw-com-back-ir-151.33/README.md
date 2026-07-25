178.239.151.33

lo               UNKNOWN        127.0.0.1/8 ::1/128 
eth0             UP             178.239.151.33/24 fe80::be24:11ff:fe00:a0e1/64 
br-205a39a8c223  DOWN           172.20.0.1/16 
br-27d3b8e59e9b  DOWN           172.18.0.1/16 
docker0          UP             172.17.0.1/16 fe80::b0e0:f4ff:fe2f:235/64 
br-ff70f60ca889  DOWN           172.19.0.1/16 
virbr0           UP             192.168.122.1/24 
vnet0            UNKNOWN        fe80::fc54:ff:fee0:bbe9/64 
veth14b3377@if2  UP             fe80::1017:5eff:fe49:b0b6/64 



1 - کانتینر سرور تست ویکیلا
test.weekilaw.com

2 - کانتینر اصلی بک اند ویکیلا
api.weekilaw.com

3 - پنل ادمین ویکیلا
admin.weekilaw.com

4 - بک اند اپ چت بات
api.weeshion.ir






سرور بک اند

PORT :
3000 => بک اند اصلی
5000 => بک اند تست
4000 => پنل ادمین
6000 => بک اند اپلیکیشن چت بات لیان ( پروژه قدیمی )
80,8080,443 => اروان کلاد و nginx

---

## شبکه / VPN داخلی

بعد از ریستارت جولای ۲۰۲۶: بدون KVM، VM میکروTik بالا نمی‌آید.
وضعیت فعلی و ماندگاری SSTP + برگشت به حالت قبل:

→ [NETWORK-WORKAROUND.md](./NETWORK-WORKAROUND.md)
→ فایل‌های systemd: [sstp-host/](./sstp-host/)
