#!/bin/bash

# Nextcloud Installation Script for Ubuntu 22.04 LTS
# This script automates the complete installation of Nextcloud with Apache, PHP-FPM, MySQL, Redis, and SSL

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$BASE_DIR/configs"

# Load configuration
source "$CONFIG_DIR/install-config.conf" 2>/dev/null || {
    echo "Error: Missing config file at $CONFIG_DIR/install-config.conf"
    exit 1
}

echo "Starting Nextcloud installation from $BASE_DIR..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print section headers
print_section() {
    echo -e "\n\033[1;34m==> $1\033[0m"
}

# Function to print status messages
print_status() {
    echo -e "\033[1;32m[+] $1\033[0m"
}

# Function to print error messages
print_error() {
    echo -e "\033[1;31m[!] ERROR: $1\033[0m"
    exit 1
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root. Use 'sudo $0'"
fi

# Step1: Install Required Packages
print_section "Step 1: Installing Required Packages"

# 1. Update and Upgrade the Ubuntu Packages
print_status "Updating and upgrading system packages..."
apt update -y && apt upgrade -y

# 2. Install Apache and MySQL Server
print_status "Installing Apache and MySQL Server..."
apt install -y apache2 mariadb-server

# 3. Add PHP 8.4 repository and update
print_status "Adding PHP 8.4 repository and updating..."
add-apt-repository -y ppa:ondrej/php
apt update -y

# 4. Install PHP 8.4 and other Dependencies
print_status "Installing PHP 8.4 and dependencies..."
apt install -y software-properties-common
add-apt-repository -y ppa:ondrej/php
apt update -y

# Install PHP 8.4 with all required extensions
apt install -y php8.4 php8.4-{bz2,gd,mysql,curl,zip,mbstring,imagick,bcmath,xml,intl,gmp,apcu,cli,common,fpm,redis,sqlite3} \
    libapache2-mod-php8.4 zip unzip wget

# 5. Configure PHP settings consistently across all interfaces
print_status "Configuring PHP 8.4 settings..."
if [ -f "scripts/configure-php.sh" ]; then
    bash scripts/configure-php.sh
else
    print_error "PHP configuration script not found at scripts/configure-php.sh"
fi

# 4. Enable required Apache modules and restart Apache
print_status "Enabling Apache modules..."
a2enmod rewrite dir mime env headers
systemctl restart apache2

# Step2. Configure MySQL Server
print_section "Step 2: Configuring MySQL Server"

# 1. Create MySQL Database and User for Nextcloud
print_status "Configuring MySQL database..."
mysql -e "CREATE USER IF NOT EXISTS 'nextcloud'@'localhost' IDENTIFIED BY 'passw@rd';"
mysql -e "CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Step3. Download and Install Nextcloud
print_section "Step 3: Downloading and Installing Nextcloud"

# 1. Download and unzip in the /var/www folder
print_status "Downloading and extracting Nextcloud..."
apt install -y wget unzip
cd /var/www/
wget -q https://download.nextcloud.com/server/releases/latest.zip
unzip -q latest.zip
rm -f latest.zip

# 2. Set proper permissions
print_status "Setting permissions..."
chown -R www-data:www-data /var/www/nextcloud/

# Step4. Install NextCloud From the Command Line
print_section "Step 4: Installing Nextcloud"

# 1. Run the CLI Command
print_status "Running Nextcloud installation..."
sudo -u www-data php /var/www/nextcloud/occ maintenance:install \
    --database "mysql" \
    --database-host "127.0.0.1" \
    --database-name "nextcloud" \
    --database-user "nextcloud" \
    --database-pass "passw@rd" \
    --admin-user "admin" \
    --admin-pass "admin123"

# 2. Configure trusted domains
print_status "Configuring trusted domains..."
mkdir -p /var/www/nextcloud/config
if ! grep -q "trusted_domains" /var/www/nextcloud/config/config.php 2>/dev/null; then
    echo -e "<?php\n\n\$CONFIG = array ();" > /var/www/nextcloud/config/config.php
fi

# Add trusted domain if not already present
if ! grep -q "'data.amarissolutions.com'" /var/www/nextcloud/config/config.php; then
    sed -i "/'trusted_domains' =>/{
    n
    a\    1 => 'data.amarissolutions.com',
    }" /var/www/nextcloud/config/config.php
fi

# Step5. Install and Configure PHP-FPM with Apache
print_section "Step 5: Configuring PHP-FPM"

# 1. Install php-fpm
print_status "Installing PHP 8.4 FPM..."
apt install -y php8.4-fpm

# 2. Configure Apache to use PHP-FPM
print_status "Configuring Apache to use PHP 8.4 FPM..."
a2dismod php8.4 mpm_prefork
a2enmod mpm_event proxy_fcgi setenvif
a2enconf php8.4-fpm

# 3. Set required php.ini variables
print_status "Configuring PHP 8.4 settings..."
cat > /etc/php/8.4/fpm/conf.d/nextcloud.ini << 'EOL'
upload_max_filesize = 64M
post_max_size = 96M
memory_limit = 512M
max_execution_time = 600
max_input_vars = 3000
max_input_time = 1000
opcache.enable=1
opcache.enable_cli=1
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=60

; Remove deprecated mbstring settings
mbstring.http_input =
mbstring.http_output =
mbstring.internal_encoding =
EOL

# 4. php-fpm pool Configurations
echo "Configuring PHP-FPM pools..."
sudo sed -i \
-e 's/^pm.max_children.*/pm.max_children = 64/' \
-e 's/^pm.start_servers.*/pm.start_servers = 16/' \
-e 's/^pm.min_spare_servers.*/pm.min_spare_servers = 16/' \
-e 's/^pm.max_spare_servers.*/pm.max_spare_servers = 32/' \
/etc/php/8.4/fpm/pool.d/www.conf && \
sudo systemctl restart php8.4-fpm

# 5. Apache directives for php files processing by PHP-FPM
echo "Configuring Apache for PHP-FPM..."
sudo tee /etc/apache2/sites-enabled/000-default.conf > /dev/null <<'EOF'
<VirtualHost *:80>

    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/nextcloud

    <Directory /var/www/nextcloud>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch "\.php$">
        SetHandler "proxy:unix:/var/run/php/php8.4-fpm.sock|fcgi://localhost/"
    </FilesMatch>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined

</VirtualHost>
EOF

# Restart php-fpm and Apache Server
echo "Restarting services..."
sudo service php8.4-fpm restart
sudo systemctl restart apache2

# Step6. Configure Redis for Caching
print_section "Step 6: Configuring Redis"

# 1. Install Redis Server and PHP extension
print_status "Installing Redis server and PHP extension..."
apt install -y redis-server php-redis

# 2. Configure Redis
print_status "Configuring Redis..."
cat > /etc/redis/redis.conf << 'EOL'
daemonize yes
pidfile /var/run/redis/redis-server.pid
port 0
unixsocket /var/run/redis/redis.sock
unixsocketperm 770
timeout 0
tcp-keepalive 300
databases 16
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis
maxmemory 256mb
maxmemory-policy allkeys-lru
appendonly yes
appendfilename "appendonly.aof"
no-appendfsync-on-rewrite no
EOL

# Set proper permissions
usermod -a -G redis www-data
chown -R redis:redis /var/lib/redis
chmod 755 /var/lib/redis

# Restart Redis
systemctl restart redis-server

# 3. Configure Nextcloud to use Redis
print_status "Configuring Nextcloud to use Redis..."
if [ -f "/var/www/nextcloud/config/config.php" ]; then
    if ! grep -q "'memcache.local'" /var/www/nextcloud/config/config.php; then
        # Create a temporary file for the Redis configuration
        REDIS_CONFIG="$(mktemp)"
        cat > "$REDIS_CONFIG" << 'REDIS_EOF'
  'memcache.local' => '\OC\Memcache\Redis',
  'memcache.distributed' => '\OC\Memcache\Redis',
  'redis' => [
    'host' => '/var/run/redis/redis.sock',
    'port' => 0,
    'dbindex' => 0,
    'password' => '',
    'timeout' => 1.5,
  ],
REDIS_EOF
        
        # Insert the Redis configuration before the closing );
        sed -i "/);/ {
            x
            r $REDIS_CONFIG
            x
        }" /var/www/nextcloud/config/config.php
        
        # Clean up the temporary file
        rm -f "$REDIS_CONFIG"
    fi
else
    print_error "Nextcloud config.php not found at /var/www/nextcloud/config/config.php"
fi

# 4. Enable Redis session locking
print_status "Enabling Redis session locking..."
cat > /etc/php/8.4/fpm/conf.d/20-redis-session.ini << 'EOL'
session.save_handler = redis
session.save_path = "unix:///var/run/redis/redis.sock?persistent=1&weight=1&database=0"
redis.session.locking_enabled = 1
redis.session.lock_retries = -1
redis.session.lock_wait_time = 10000
EOL

# Restart services
print_status "Restarting services..."
systemctl restart php8.4-fpm
systemctl restart apache2

# Step7. Install and Configure SSL with Let's Encrypt
print_section "Step 7: Configuring SSL with Let's Encrypt"

# 1. Install Certbot
print_status "Installing Certbot..."
apt install -y python3-certbot-apache

# 2. Obtain SSL certificate
print_status "Obtaining SSL certificate..."
certbot --apache --non-interactive --agree-tos --email wagur465@gmail.com \
    -d data.amarissolutions.com --redirect

# 3. Configure HTTP/2
print_status "Enabling HTTP/2..."
a2enmod http2
sed -i '/<VirtualHost \*:443>/a\        Protocols h2 http/1.1' \
    /etc/apache2/sites-available/nextcloud-le-ssl.conf

# 4. Configure HSTS
print_status "Configuring HSTS..."
grep -q "Strict-Transport-Security" /etc/apache2/sites-available/nextcloud-le-ssl.conf || \
sed -i '/<\/VirtualHost>/i \
    <IfModule mod_headers.c>\n        Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains; preload"\n    </IfModule>' /etc/apache2/sites-available/nextcloud-le-ssl.conf

# 5. Configure SSL parameters
print_status "Configuring SSL parameters..."
cat > /etc/apache2/conf-available/ssl-params.conf << 'EOL'
SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
SSLProtocol -all +TLSv1.2 +TLSv1.3
SSLHonorCipherOrder off
SSLSessionTickets off

# OCSP Stapling
SSLUseStapling on
SSLStaplingCache "shmcb:logs/ssl_stapling(32768)"

# HSTS (mod_headers is required) (15768000 seconds = 6 months)
Header always set Strict-Transport-Security "max-age=15768000; includeSubDomains; preload"
EOL

a2enconf ssl-params

# Restart Apache
print_status "Restarting Apache..."
systemctl restart apache2

# Step8. Configure Nextcloud Settings
print_section "Step 8: Configuring Nextcloud Settings"

# 1. Set timezone
print_status "Setting timezone..."

# 2. Update .htaccess file
echo "Updating .htaccess file..."
sudo -u www-data php -define apc.enable_cli=1 /var/www/nextcloud/occ maintenance:update:htaccess

# Step10. Final Nextcloud Tweaks

echo "Applying final tweaks..."
sudo -u www-data php /var/www/nextcloud/occ background:cron
sudo -u www-data php /var/www/nextcloud/occ config:system:set timezone --value="Africa/Nairobi"
sudo -u www-data php /var/www/nextcloud/occ config:system:set maintenance_window_start --type=integer --value=1
sudo -u www-data php -f /var/www/nextcloud/cron.php
sudo -u www-data php /var/www/nextcloud/occ background:job:list

sudo apt-get install -y php8.4-sqlite3
sudo systemctl restart apache2

sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices
sudo -u www-data php /var/www/nextcloud/occ db:check
sudo -u www-data php /var/www/nextcloud/occ db:schema:expected
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-columns
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-primary-keys
sudo -u www-data php /var/www/nextcloud/occ db:convert-filecache-bigint
sudo -u www-data php /var/www/nextcloud/occ maintenance:repair --include-expensive
sudo -u www-data php /var/www/nextcloud/occ status

sudo -u www-data php /var/www/nextcloud/occ integrity:check-core
sudo -u www-data php /var/www/nextcloud/occ maintenance:data-fingerprint

cp -r /var/www/nextcloud/config /root/nextcloud-config-backup
cp -r /var/www/nextcloud/data /root/nextcloud-data-backup

sudo -u www-data php /var/www/nextcloud/occ upgrade
sudo -u www-data php /var/www/nextcloud/occ maintenance:data-fingerprint

sudo apt update
sudo apt install -y libmagickcore-6.q16-6-extra librsvg2-bin
sudo apt install -y php8.4-imagick
sudo systemctl restart php8.4-fpm
sudo systemctl restart apache2

sudo -u www-data php /var/www/nextcloud/occ maintenance:repair