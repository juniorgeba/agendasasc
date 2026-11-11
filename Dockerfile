# ============================================================
# STAGE 1 — Dependências PHP (Composer)
# ============================================================
FROM php:8.4-fpm-alpine AS vendor

RUN apk add --no-cache git unzip libzip-dev icu-dev \
    autoconf g++ make

RUN docker-php-ext-install pdo_mysql bcmath intl zip pcntl

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

# Copia só os manifests primeiro — cache do Composer só invalida se eles mudarem
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

# Agora o código, e finaliza o autoloader otimizado
COPY . .
RUN composer dump-autoload --no-dev --optimize --classmap-authoritative --no-scripts

# ============================================================
# STAGE 2 — Build de assets (Node)
# ============================================================
FROM node:22-alpine AS assets

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

# O projeto inteiro é copiado porque o Tailwind 4 escaneia todo o código-fonte
# (resources/, app/, config/…) para descobrir as classes usadas.
# O .dockerignore mantém node_modules/vendor/.git fora daqui.
COPY . .

# O CSS importa o tema e escaneia as views do TallStackUI em vendor/ (resources/css/app.css),
# então o vendor do stage anterior precisa estar presente no build.
COPY --from=vendor /var/www/vendor ./vendor
RUN npm run build

# ============================================================
# STAGE 3 — Imagem final de runtime
# ============================================================
FROM php:8.4-fpm-alpine AS runtime

# Dependências de runtime (sem toolchain de build)
RUN apk add --no-cache \
    nginx \
    supervisor \
    libpng \
    libjpeg-turbo \
    freetype \
    libzip \
    oniguruma \
    icu-libs \
    imagemagick \
    imagemagick-svg \
    rsvg-convert \
    imagemagick-libs \
    libgomp \
    curl

# Extensões PHP: compila numa camada com toolchain e remove o toolchain no mesmo RUN
RUN apk add --no-cache --virtual .build-deps \
        autoconf g++ make libpng-dev libjpeg-turbo-dev freetype-dev libzip-dev oniguruma-dev icu-dev imagemagick-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install \
        pdo_mysql mbstring exif pcntl bcmath gd zip intl opcache \
    && git_redis_ver="6.1.0" \
    && curl -fsSL "https://github.com/phpredis/phpredis/archive/refs/tags/${git_redis_ver}.tar.gz" \
        | tar xz -C /tmp \
    && cd "/tmp/phpredis-${git_redis_ver}" \
    && phpize && ./configure && make -j"$(nproc)" && make install \
    && docker-php-ext-enable redis \
    && cd / && rm -rf /tmp/phpredis-* \
    && pecl install imagick \
    && docker-php-ext-enable imagick \
    && rm -rf /tmp/pear \
    && apk del .build-deps

WORKDIR /var/www

# Código + vendor + assets já prontos dos stages anteriores
COPY --chown=www-data:www-data . .
COPY --from=vendor --chown=www-data:www-data /var/www/vendor ./vendor
COPY --from=assets --chown=www-data:www-data /app/public/build ./public/build

# Permissões corretas de storage/cache
RUN chown -R www-data:www-data /var/www \
    && chmod -R 775 /var/www/storage /var/www/bootstrap/cache

# Configs
COPY docker/nginx/default.conf /etc/nginx/http.d/default.conf
COPY docker/php/custom.ini /usr/local/etc/php/conf.d/custom.ini
COPY docker/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/start.sh /start.sh
RUN chmod +x /start.sh && mkdir -p /var/log/supervisor

EXPOSE 80

CMD ["/start.sh"]
