# 🚀 Nextcloud Enterprise Deployment Guide

## 📝 Overview

This comprehensive guide provides step-by-step instructions for deploying a production-grade Nextcloud instance with enterprise-level optimizations. This solution has been developed and maintained by **Wagura Maurice** ([wagura465@gmail.com](mailto:wagura465@gmail.com)).

## 🛠 System Requirements

### Minimum Requirements
- **OS**: Ubuntu 22.04 LTS (64-bit)
- **CPU**: 2 cores (4+ recommended for production)
- **RAM**: 4GB (8GB+ recommended for production)
- **Storage**: 20GB free space (SSD strongly recommended)
- **Network**: Public IP with ports 80/443 open

### Prerequisites
- Domain name: `data.amarissolutions.com`
- Root or sudo access
- Basic Linux command line knowledge

## 🚀 Automated Installation

### 1. Download the Installation Package

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install Git if not already installed
sudo apt install -y git

# Clone the repository
git clone https://github.com/wagura-maurice/nextcloud-setup.git
cd nextcloud-setup
```

### 2. Review Configuration (Optional)

Before proceeding, you may want to review the default configuration:

```bash
# View available configuration options
cat configs/install-config.conf

# Edit configuration if needed
nano configs/install-config.conf
```

### 3. Run the Installation Script

Execute the automated installation script:

```bash
# Make the script executable
chmod +x scripts/install-nextcloud.sh

# Start the installation
sudo ./scripts/install-nextcloud.sh
```

The script will perform the following actions:

1. **System Preparation**
   - Update system packages
   - Configure system timezone and locale
   - Set up required repositories

2. **Service Installation**
   - Apache 2.4 with HTTP/2
   - PHP 8.4 with FPM and OPcache
   - MariaDB 10.6+ database server
   - Redis for caching and file locking
   - Let's Encrypt SSL certificate

3. **Nextcloud Configuration**
   - Secure database setup
   - Optimized PHP settings
   - Security headers and hardening
   - Performance tuning
   - Automated maintenance setup

4. **Finalization**
   - System cleanup
   - Backup of configuration
   - Service verification

### 4. Post-Installation

After successful installation, you'll receive a summary with:
- Nextcloud access URL
- Admin credentials
- Backup locations
- Important configuration details

## 🔧 Manual Configuration (Advanced)

### 2. Manual Installation (Alternative)

If you prefer to install Nextcloud manually, follow these steps:

#### 2.1 Update System Packages

```bash
sudo apt update -y && sudo apt upgrade -y
```

#### 2.2 Install Required Software

```bash
# Install Apache and MariaDB
sudo apt install -y apache2 mariadb-server

# Install PHP and required extensions
sudo apt install -y libapache2-mod-php8.4 php8.4-bz2 php8.4-gd php8.4-mysql php8.4-curl \
    php8.4-zip php8.4-mbstring php8.4-imagick php8.4-bcmath php8.4-xml php8.4-intl \
    php8.4-gmp php8.4-apcu php8.4-cli php8.4-common php8.4-fpm php8.4-redis

# Install additional tools
sudo apt install -y wget unzip redis-server
```

#### 2.3 Configure MySQL Database

```bash
# Secure MySQL installation
sudo mysql_secure_installation

# Create database and user
sudo mysql -e "CREATE USER IF NOT EXISTS 'nextcloud'@'localhost' IDENTIFIED BY 'passw@rd';"
sudo mysql -e "CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
sudo mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"
```

#### 2.4 Download and Install Nextcloud

```bash
# Download and extract Nextcloud
cd /var/www/
sudo wget https://download.nextcloud.com/server/releases/latest.zip
sudo unzip -q latest.zip
sudo rm -f latest.zip

# Set proper permissions
sudo chown -R www-data:www-data /var/www/nextcloud/
```

#### 2.5 Configure Apache

Copy the Apache configuration:

```bash
sudo cp configs/apache-nextcloud.conf /etc/apache2/sites-available/nextcloud.conf
sudo a2dissite 000-default
sudo a2ensite nextcloud

# Enable required modules
sudo a2enmod rewrite headers env dir mime setenvif ssl http2

# Disable unnecessary modules
sudo a2dismod mpm_prefork
sudo a2enmod mpm_event proxy_fcgi setenvif

# Enable PHP-FPM
sudo a2enconf php8.4-fpm
```

#### 2.6 Configure PHP-FPM

Copy the PHP-FPM configuration:

```bash
sudo cp configs/php-fpm-optimizations.conf /etc/php/8.4/fpm/pool.d/nextcloud.conf
```

#### 2.7 Install and Configure Redis

```bash
# Enable Redis session handling
sudo sed -i 's/^port .*/port 0/' /etc/redis/redis.conf
echo 'unixsocket /var/run/redis/redis.sock' | sudo tee -a /etc/redis/redis.conf
echo 'unixsocketperm 770' | sudo tee -a /etc/redis/redis.conf

# Add www-data to redis group
sudo usermod -a -G redis www-data

# Restart Redis
sudo systemctl restart redis-server
```

#### 2.8 Install Let's Encrypt SSL Certificate

```bash
# Install Certbot
sudo apt install -y python3-certbot-apache

# Obtain SSL certificate
sudo certbot --apache --non-interactive --agree-tos --email admin@amarissolutions.com \
    -d data.amarissolutions.com --redirect
```

#### 2.9 Final Configuration

```bash
# Restart services
sudo systemctl restart apache2
sudo systemctl restart php8.4-fpm

# Run Nextcloud installation
cd /var/www/nextcloud
sudo -u www-data php occ maintenance:install \
    --database "mysql" \
    --database-host "127.0.0.1" \
    --database-name "nextcloud" \
    --database-user "nextcloud" \
    --database-pass "passw@rd" \
    --admin-user "admin" \
    --admin-pass "admin123"

# Configure trusted domains
sudo -u www-data php occ config:system:set trusted_domains 1 --value=data.amarissolutions.com

# Enable Redis for file locking and caching
sudo -u www-data php occ config:system:set memcache.local --value=\\OC\\Memcache\\APCu
sudo -u www-data php occ config:system:set memcache.distributed --value=\\OC\\Memcache\\Redis
sudo -u www-data php occ config:system:set redis host --value="/var/run/redis/redis.sock"
sudo -u www-data php occ config:system:set redis port --value=0 --type=integer

# Set up background jobs
sudo -u www-data php occ background:cron

# Update the database
sudo -u www-data php occ db:add-missing-indices
sudo -u www-data php occ db:convert-filecache-bigint
```
sudo -u www-data php occ maintenance:install --database "mysql" --database-host "127.0.0.1" --database-name "nextcloud" --database-user "nextcloud" --database-pass "passw@rd" --admin-user "admin" --admin-pass "admin123"
```

### 6. Configure Apache

1. Configure Apache virtual host:
   ```bash
   sudo bash -c 'cat > /etc/apache2/sites-enabled/000-default.conf <<EOF
   <VirtualHost *:80>
       ServerAdmin webmaster@localhost
       DocumentRoot /var/www/nextcloud
       ErrorLog \${APACHE_LOG_DIR}/error.log
       CustomLog \${APACHE_LOG_DIR}/access.log combined
   </VirtualHost>
   EOF'
   ```

2. Enable required Apache modules:
   ```bash
   sudo a2enmod rewrite dir mime env headers
   sudo systemctl restart apache2
   ```

### 7. Configure PHP-FPM

1. Install PHP-FPM:
   ```bash
   sudo apt install php8.4-fpm
   ```

2. Configure PHP-FPM:
   ```bash
   sudo a2dismod php8.4
   sudo a2dismod mpm_prefork
   sudo a2enmod mpm_event proxy_fcgi setenvif
   sudo a2enconf php8.4-fpm
   ```

3. Set PHP settings:
   ```bash
   sudo tee -a /etc/php/8.4/fpm/php.ini > /dev/null <<'EOF'
   upload_max_filesize = 64M
   post_max_size = 96M
   memory_limit = 512M
   max_execution_time = 600
   max_input_vars = 3000
   max_input_time = 1000
   EOF
   ```

4. Configure PHP-FPM pool:
   ```bash
   sudo sed -i \
   -e 's/^pm.max_children.*/pm.max_children = 64/' \
   -e 's/^pm.start_servers.*/pm.start_servers = 16/' \
   -e 's/^pm.min_spare_servers.*/pm.min_spare_servers = 16/' \
   -e 's/^pm.max_spare_servers.*/pm.max_spare_servers = 32/' \
   /etc/php/8.4/fpm/pool.d/www.conf && \
   sudo systemctl restart php8.4-fpm
   ```

5. Configure Apache for PHP-FPM:
   ```bash
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
   sudo systemctl restart apache2
   ```

### 8. Enable OPcache and APCu

1. Enable OPcache:
   ```bash
   sudo sed -i \
   -e 's/^opcache.enable\s*=.*/opcache.enable=1/' \
   -e 's/^opcache.enable_cli\s*=.*/opcache.enable_cli=1/' \
   -e 's/^opcache.interned_strings_buffer\s*=.*/opcache.interned_strings_buffer=16/' \
   -e 's/^opcache.max_accelerated_files\s*=.*/opcache.max_accelerated_files=10000/' \
   -e 's/^opcache.memory_consumption\s*=.*/opcache.memory_consumption=128/' \
   -e 's/^opcache.save_comments\s*=.*/opcache.save_comments=1/' \
   -e 's/^opcache.revalidate_freq\s*=.*/opcache.revalidate_freq=60/' \
   /etc/php/8.4/fpm/php.ini && \
   sudo systemctl restart php8.4-fpm
   ```

2. Install APCu:
   ```bash
   sudo apt install php8.4-apcu
   ```

### 9. Install and Configure Redis

1. Install Redis:
   ```bash
   sudo apt-get install redis-server php-redis
   sudo systemctl start redis-server
   sudo systemctl enable redis-server
   ```

2. Configure Redis for Unix socket:
   ```bash
   # Edit Redis configuration
   sudo nano /etc/redis/redis.conf
   
   # Make these changes:
   port 0
   unixsocket /var/run/redis/redis.sock
   unixsocketperm 770
   
   # Set proper permissions
   sudo usermod -a -G redis www-data
   sudo chown -R redis:redis /var/lib/redis
   sudo chmod 755 /var/lib/redis
   
   # Restart Redis
   sudo systemctl restart redis-server
   ```

3. Configure Nextcloud for Redis:
   ```bash
   sudo usermod -a -G redis www-data
   sudo sed -i "/);/i\  'filelocking.enabled' => true,\n  'memcache.local' => '\\OC\\Memcache\\APCu',\n  'memcache.distributed' => '\\OC\\Memcache\\Redis',\n  'memcache.locking' => '\\OC\\Memcache\\Redis',\n  'redis' => [\n    'host' => '/var/run/redis/redis.sock',\n    'port' => 0,\n    'dbindex' => 0,\n    'password' => '',\n    'timeout' => 1.5,\n  ]," /var/www/nextcloud/config/config.php
   ```

### 10. Install SSL and Enable HTTP/2

1. Install Certbot and Apache plugin:
   ```bash
   sudo apt-get install -y python3-certbot-apache
   ```

2. Obtain SSL certificate (replace with your email):
   ```bash
   sudo certbot --apache --non-interactive --agree-tos --email admin@example.com -d data.amarissolutions.com --redirect
   ```

3. Enable HTTP/2 and optimize SSL configuration:
   ```bash
   sudo a2enmod http2
   sudo sed -i '/<VirtualHost \*:443>/a\        Protocols h2 http/1.1' /etc/apache2/sites-available/nextcloud-ssl.conf
   
   # Configure SSL parameters
   sudo tee /etc/apache2/conf-available/ssl-params.conf > /dev/null << 'EOL'
   SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
   SSLProtocol -all +TLSv1.2 +TLSv1.3
   SSLHonorCipherOrder off
   SSLCompression off
   SSLSessionTickets off
   
   # OCSP Stapling
   SSLUseStapling on
   SSLStaplingCache "shmcb:logs/ssl_stapling(32768)"
   EOL
   
   sudo a2enconf ssl-params
   sudo systemctl restart apache2
   ```

### 11. Final Configuration

1. Enable pretty URLs:
   ```bash
   sudo -u www-data php /var/www/nextcloud/occ config:system:set htaccess.RewriteBase --value="/"
   sudo -u www-data php /var/www/nextcloud/occ maintenance:update:htaccess
   ```

2. Set up background jobs:
   ```bash
   sudo -u www-data php /var/www/nextcloud/occ background:job:list
   sudo -u www-data php /var/www/nextcloud/occ background:cron
   ```

3. Configure maintenance window:
   ```bash
   sudo -u www-data php /var/www/nextcloud/occ config:system:set maintenance_window_start --type=integer --value=1
   ```

4. Set up database optimizations:
   ```bash
   sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices
   sudo -u www-data php /var/www/nextcloud/occ db:convert-filecache-bigint
   ```

## Post-Installation

1. Access Nextcloud via web browser at `https://data.amarissolutions.com`
2. Log in with the admin credentials you set during installation
3. Complete the setup wizard and configure:
   - Storage locations
   - Background jobs
   - Email server settings
   - Two-factor authentication
   - Any additional apps you need

## Configuration Management

All configuration is managed through files in the `configs/` directory:

- `install-config.conf`: Main configuration file with all settings
- `php-settings.ini`: PHP configuration applied to all PHP interfaces
- `apache-nextcloud.conf`: Apache virtual host configuration

To modify any settings:
1. Update the relevant configuration file
2. Run the appropriate setup script
3. Restart the affected services

## Maintenance

### Regular Maintenance Tasks

1. Update Nextcloud:
   ```bash
   sudo -u www-data php /var/www/nextcloud/updater/updater.phar
   sudo -u www-data php /var/www/nextcloud/occ upgrade
   sudo -u www-data php /var/www/nextcloud/occ maintenance:repair
   ```

2. Check system health:
   ```bash
   sudo -u www-data php /var/www/nextcloud/occ status
   sudo -u www-data php /var/www/nextcloud/occ check
   ```

## Troubleshooting

### Common Issues

- **Permission Errors**:
  ```bash
  sudo chown -R www-data:www-data /var/www/nextcloud/
  sudo chmod -R 750 /var/www/nextcloud/
  sudo chmod 640 /var/www/nextcloud/config/config.php
  ```

- **PHP Errors**: Check PHP error logs:
  ```bash
  sudo tail -f /var/log/php8.4-fpm/error.log
  ```

- **Apache Errors**:
  ```bash
  sudo tail -f /var/log/apache2/error.log
  sudo apache2ctl configtest
  ```

- **Redis Connection Issues**:
  ```bash
  sudo systemctl status redis-server
  sudo redis-cli ping
  ```

- **Nextcloud Logs**:
  ```bash
  sudo -u www-data php /var/www/nextcloud/occ log:tail
  ```

## Backup and Recovery

### Backup Nextcloud

1. Database backup:
   ```bash
   mysqldump --single-transaction -h localhost -u nextcloud -p nextcloud > nextcloud-sqlbkp_`date +"%Y%m%d"`.bak
   ```

2. File backup:
   ```bash
   tar -cpzf nextcloud-backup_`date +"%Y%m%d"`.tar.gz /var/www/nextcloud/
   ```

3. Configuration backup:
   ```bash
   cp -a /var/www/nextcloud/config/ /path/to/backup/nextcloud-config-`date +"%Y%m%d"`
   ```

### Restore from Backup

1. Restore database:
   ```bash
   mysql -u nextcloud -p nextcloud < nextcloud-sqlbkp.bak
   ```

2. Restore files:
   ```bash
   tar -xzpvf nextcloud-backup.tar.gz -C /
   ```

3. Update configuration if needed and set permissions:
   ```bash
   sudo chown -R www-data:www-data /var/www/nextcloud/
   sudo -u www-data php /var/www/nextcloud/occ maintenance:repair
   ```
- **PHP-FPM Not Responding**: Verify PHP-FPM service status with `sudo systemctl status php8.4-fpm`