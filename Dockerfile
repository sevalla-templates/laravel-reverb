# Stage 1: Install PHP dependencies
FROM composer:2 AS vendor
WORKDIR /app

COPY . .
RUN composer install

# Stage 2: Build frontend assets
FROM node:20-alpine AS assets
WORKDIR /app

COPY . .
RUN npm ci
COPY --from=vendor /app/vendor ./vendor

RUN npm run build

# Stage 3: Set up runtime environment
FROM php:8.3-fpm-alpine AS runtime

# Install system packages
RUN apk add --no-cache \
    nginx supervisor bash tzdata \
    icu-dev oniguruma-dev libzip-dev \
    libpng-dev libjpeg-turbo-dev freetype-dev \
    git curl shadow

# Install PHP extensions
ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN install-php-extensions @composer apcu bcmath calendar Core ctype curl date dom ev excimer exif \
    fileinfo filter ftp gd gettext gmp hash iconv igbinary imagick \
    imap intl json ldap libxml mbstring mongodb msgpack mysqli \
    mysqlnd openssl pcntl pcre PDO pdo_mysql pdo_pgsql pdo_sqlite pdo_sqlsrv \
    Phar posix pspell random readline redis Reflection session shmop \
    SimpleXML soap sockets sodium SPL sqlite3 sqlsrv standard tokenizer xml \
    xmlreader xmlwriter xsl OPcache zip zlib

# Config PHP-FPM
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
RUN cat > "$PHP_INI_DIR/conf.d/99-production.ini" <<'INI'
opcache.enable=1
opcache.enable_cli=0
opcache.jit_buffer_size=0
opcache.validate_timestamps=0
memory_limit=512M
expose_php=0
cgi.fix_pathinfo=0
INI

RUN touch /usr/local/etc/php-fpm.d/zz-log.conf
RUN cat /usr/local/etc/php-fpm.d/zz-log.conf <<'LOG'
[global]
error_log=/proc/self/fd/2
LOG

RUN touch /usr/local/etc/php-fpm.d/zz-pool-www.conf
RUN cat /usr/local/etc/php-fpm.d/zz-pool-www.conf <<'POOL'
listen=127.0.0.1:9000
pm=dynamic
pm.max_children=10
pm.start_servers=3
pm.min_spare_servers=2
pm.max_spare_servers=6
request_terminate_timeout=60s
request_slowlog_timeout=5s
slowlog=/proc/self/fd/2
pm.status_path=/fpm-status
ping.path=/fpm-ping
catch_workers_output=yes
clear_env=no
POOL

# Uncomment these lines to enable NGINX logging to STDOUT/STDERR
# RUN ln -sf /dev/stdout /var/log/nginx/access.log
# RUN ln -sf /dev/stderr /var/log/nginx/error.log

# Config Nginx
RUN mkdir -p /run/nginx /etc/nginx/conf.d /var/log/nginx; \
  cat > /etc/nginx/nginx.conf <<'NGINX'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events { worker_connections 1024; }

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

  access_log  /var/log/nginx/access.log  main;
  sendfile        on;
  keepalive_timeout  65;
  server_tokens off;
  gzip on;
  gzip_types text/plain text/css application/json application/javascript application/xml+rss application/xml text/javascript image/svg+xml;

  server {
    listen 8080 default_server;
    listen [::]:8080 default_server;
    client_max_body_size 50m;

    server_name _;
    root /var/www/html/public;
    index index.php;
    default_type application/octet-stream;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    charset utf-8;


    location / {
      try_files $uri $uri/ /index.php?$query_string;
    }
    error_page 404 /index.php;

    location /app {
      proxy_http_version 1.1;
      proxy_set_header Host $http_host;
      proxy_set_header Scheme $scheme;
      proxy_set_header SERVER_PORT $server_port;
      proxy_set_header REMOTE_ADDR $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "Upgrade";

      proxy_pass http://0.0.0.0:8000;
    }

    location ~ \.php$ {
      include fastcgi_params;
      fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
      fastcgi_param DOCUMENT_ROOT $realpath_root;
      fastcgi_index index.php;
      fastcgi_pass 127.0.0.1:9000;
      fastcgi_read_timeout 300;
    }

    location ~ /\.(?!well-known).* {
      deny all;
    }
  }
}
NGINX

# Config Supervisor
RUN cat > /etc/supervisord.conf <<'SUP'
[supervisord]
nodaemon=true

[program:php-fpm]
command=/usr/local/sbin/php-fpm -F
autostart=true
autorestart=true
priority=10
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
priority=20
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0

[program:reverb]
directory=/var/www/html
command=/usr/local/bin/php artisan reverb:start --host=0.0.0.0 --port=8000 --no-interaction
process_name=%(program_name)s_%(process_num)02d
autostart=true
autorestart=false
stopasgroup=true
killasgroup=true
user=root
numprocs=1
minfds=10000
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stopwaitsecs=3600
SUP

WORKDIR /var/www/html

COPY . ./
COPY --from=vendor /app/vendor ./vendor
COPY --from=vendor /app/composer.lock ./composer.lock
COPY --from=assets /app/public/build ./public/build

RUN mkdir -p storage bootstrap/cache; \
  chown -R www-data:www-data storage bootstrap/cache; \
  chmod -R ug+rwx storage bootstrap/cache

RUN usermod -u 1000 www-data || true

CMD ["supervisord", "-c", "/etc/supervisord.conf"]
