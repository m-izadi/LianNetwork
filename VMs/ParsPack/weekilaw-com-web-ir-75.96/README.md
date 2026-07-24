130.185.75.96

lo               UNKNOWN        127.0.0.1/8 ::1/128 
eth0             UP             130.185.75.96/24 fe80::b05c:b9ff:feba:6c28/64 
virbr0           UP             192.168.122.1/24 
br-1a25f09ff411  UP             172.18.0.1/16 fe80::90fa:53ff:fe9e:d4a6/64 
docker0          UP             172.17.0.1/16 fe80::1cb8:c5ff:fe77:988/64 
br-2c9c9c86b7bc  UP             172.21.0.1/16 fe80::8074:e9ff:fe41:b36a/64 
br-68910d06ed30  UP             172.19.0.1/16 fe80::a8af:e2ff:fe60:6211/64 
br-7a17c198f663  DOWN           172.20.0.1/16 fe80::6424:79ff:fe13:909b/64 
br-aff2196a6397  UP             172.25.0.1/16 fe80::fc65:20ff:fec7:42d7/64 
vnet0            UNKNOWN        fe80::fc54:ff:fe1d:ed91/64 
vethf9c2de2@if2  UP             fe80::74f1:18ff:fe61:802e/64 
vethbd5cf9f@if2  UP             fe80::1c8a:90ff:fe08:7ff/64 
veth2dc4bde@if2  UP             fe80::1c3b:9ff:fe38:4075/64 
veth23acc7f@if2  UP             fe80::4cf3:2aff:fe08:1ceb/64 
veth7b89207@if2  UP             fe80::58d2:bbff:fe1b:6c04/64 
vethf76b0b7@if2  UP             fe80::ec79:11ff:fe72:1d5f/64 
veth3bfa3c4@if2  UP             fe80::94f2:ddff:fe0e:1728/64 


 1- کانتینر وب اپ ویکیلا
app.weekilaw.com

2 - سرویس پرداخت ورژن 2 ( مخصوص پرداخت اعتباری ویکیلا )
payment2.weekilaw.com

3 - اسکریپت بکاپ خودکار ( از سرویس minio و mongo ویکیلا بکاپ میگیره و فایلش رو برای سرور شرکت ارسال میکنه )

4 - سرویس پرداخت ورژن 1 ( نسخه های قدیمی ویکیلا و یکسری پرداخت ها از این ورژن یک استفاده میشه پس نباید غیرفعال بشه )
payment.weekilaw.com


5 - سرویس وب اپ مربوط به فیچر های دفترمجازی
مثل درخواست مشاوره و منش مجازی و سرویس قدیمی ویدیو کال
service.weekilaw.com

6 - دیتابیس اصلی ویکیلا

7 - دیتابیس اصلی ویکیلا ( media )
data.weekilaw.com

——————-
دفاتر مجازی در این قسمت سرور هستن
cd /var/www/weekilaw5





--------------------------

سرور وب اپ

PORT :
8080,80 => وب اپ ویکیلا
4000 => فیچر های دفترمجازی
3001,3002 => سرویس های پرداخت
27017 => دیتابیس ( Mongodb )
9000.9001 => دیتابیس ( MiniO )
8080,80,443 => اروان کلاد و nginx


# Containers

