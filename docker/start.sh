#!/bin/sh
set -e

echo "🚀 Iniciando Agenda SASC..."

cd /var/www

# ─── Garante estrutura de pastas de storage ───────────────────────────────────
# Precisa vir antes de qualquer `artisan`: o .dockerignore deixa storage/framework/views
# e storage/logs fora da imagem, e sem elas o Laravel nem inicializa ("valid cache path").
# O volume externo também começa vazio, e os uploads precisam das subpastas.
echo "📁 Criando estrutura de storage..."
mkdir -p /var/www/storage/app/public
mkdir -p /var/www/storage/framework/sessions
mkdir -p /var/www/storage/framework/views
mkdir -p /var/www/storage/framework/cache/data
mkdir -p /var/www/storage/logs
echo "✅ Storage pronto!"

# Aguarda o banco de dados ficar disponível
echo "⏳ Aguardando banco de dados..."
until php /var/www/artisan db:monitor --databases=mariadb 2>/dev/null; do
    echo "   Banco não disponível, aguardando 3s..."
    sleep 3
done
echo "✅ Banco de dados disponível!"

# Descoberta de pacotes. O build usa `composer install --no-scripts`, e `dump-autoload` não
# dispara o discovery — sem esta linha o bootstrap/cache/packages.php só seria montado na
# primeira requisição, por www-data, fora do controle deste script.
echo "📦 Descobrindo pacotes..."
php artisan package:discover --ansi

# Cache de configurações para produção
echo "⚙️  Otimizando aplicação..."
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan event:cache

# Roda migrations
echo "🗄️  Rodando migrations..."
php artisan migrate --force


# Cria link simbólico do storage
php artisan storage:link 2>/dev/null || true

# Workers da fila de um deploy anterior recarregam o código novo
php artisan queue:restart 2>/dev/null || true

# ─── Permissões, por último ───────────────────────────────────────────────────
# Tudo acima roda como root e deixa arquivos root:root em storage/framework/views e
# bootstrap/cache. O ajuste vem depois da escrita, senão o php-fpm (www-data) não
# conseguiria recompilar uma view que ficou de fora do view:cache.
echo "🔒 Ajustando permissões..."
chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache
chmod -R 775 /var/www/storage /var/www/bootstrap/cache

echo "✅ Aplicação pronta!"

# Inicia Supervisor (Nginx + PHP-FPM + Queue Worker + Scheduler)
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
