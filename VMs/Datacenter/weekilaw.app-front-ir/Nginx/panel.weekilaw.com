server {
    listen 443 ssl;
    server_name panel.weekilaw.com;

    ssl_certificate /etc/letsencrypt/live/panel.weekilaw.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/panel.weekilaw.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Backend Laravel application - main panel/dashboard
    location / {
        root /var/www/weekilaw-backend/public;
        index index.php index.html;

        try_files $uri $uri/ /index.php?$query_string;

        location ~ \.php$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        }
    }

    # Backend API routes
    location /api/ {
        root /var/www/weekilaw-backend/public;
        index index.php;

        try_files $uri $uri/ /index.php?$query_string;

        location ~ \.php$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        }
    }

    # Backend auth routes
    location /auth/ {
        root /var/www/weekilaw-backend/public;
        index index.php;

        try_files $uri $uri/ /index.php?$query_string;

        location ~ \.php$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        }
    }

    # Well-known for SSL
    location ~ /\.well-known/acme-challenge/ {
        allow all;
    }

    # Hide dot files
    location ~ /\.(?!well-known) {
        deny all;
    }

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}

server {
    listen 8080;
    server_name 78.110.124.182;

    root /var/www/weekilaw-backend/public;
    index index.php index.html;

    client_max_body_size 50m;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
    }

    location ~ /\.well-known/acme-challenge/ {
        allow all;
    }

    location ~ /\.(?!well-known) {
        deny all;
    }
}
server {
    if ($host = panel.weekilaw.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot


    listen 80;
    server_name panel.weekilaw.com;
    return 404; # managed by Certbot


}
