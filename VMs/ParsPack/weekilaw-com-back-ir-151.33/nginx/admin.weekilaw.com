# Redirect HTTP → HTTPS (canonical host — never echo $host)
server {
    listen 80;
    server_name admin.weekilaw.com;
    return 301 https://admin.weekilaw.com$request_uri;
}

server {
    listen 443 ssl http2;
    server_name admin.weekilaw.com;

    ssl_certificate     /etc/nginx/ssl/team.weekilaw.com/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/team.weekilaw.com/private.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers off;

    location / {
        proxy_pass http://127.0.0.1:4000;

        proxy_set_header Host admin.weekilaw.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
