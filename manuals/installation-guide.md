# Nextcloud Installation Guide

This guide provides step-by-step instructions for installing Nextcloud on Ubuntu 22.04 LTS using the automated installation script. The installation includes Apache, PHP 8.4, MySQL, Redis, and SSL configuration.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Installation Steps](#installation-steps)
3. [Post-Installation](#post-installation)
4. [Backup and Recovery](#backup-and-recovery)
5. [Troubleshooting](#troubleshooting)

## Prerequisites

- Ubuntu 22.04 LTS server
- Root or sudo access
- Minimum 2GB RAM (4GB+ recommended)
- At least 10GB free disk space
- Domain name pointing to your server (recommended)
- Ports 80 and 443 open in your firewall

## Installation Steps

### 1. Clone the Repository

```bash
git clone https://github.com/wagura-maurice/nextcloud-setup.git
cd nextcloud-setup
```

### 2. Configure Installation

Create a configuration file with your settings:

```bash
mkdir -p temp
cat > temp/install-config.conf << 'EOL'
# System Configuration
TIMEZONE="Africa/Nairobi"
LANGUAGE="en_US.UTF-8"

# MySQL Configuration
MYSQL_ROOT_PASS="your_secure_root_password"
MYSQL_NC_USER="nextcloud"
MYSQL_NC_PASS="your_secure_nc_password"

# Nextcloud Configuration
NEXTCLOUD_DOMAIN="your-domain.com"
NEXTCLOUD_ADMIN_USER="admin"
NEXTCLOUD_ADMIN_PASS="your_secure_admin_password"

# SSL Configuration
SSL_EMAIL="admin@your-domain.com"
SSL_MODE="production"  # or "staging" for testing
EOL

# Set secure permissions
chmod 600 temp/install-config.conf
```

### 3. Run the Installation Script

Make the script executable and run it:

```bash
chmod +x scripts/install-nextcloud.sh
sudo ./scripts/install-nextcloud.sh
```

### 4. Follow the Prompts

The script will guide you through the installation process. It will:

1. Install required system packages
2. Configure Apache and PHP-FPM
3. Set up MySQL database
4. Install and configure Nextcloud
5. Set up SSL certificates (Let's Encrypt)
6. Configure Redis for caching
7. Optimize system settings

## Post-Installation

### Accessing Nextcloud

After installation, you can access your Nextcloud instance at:
- `https://your-domain.com`

### Initial Setup

1. Log in with the admin credentials you provided
2. Go to Settings > Administration for additional configuration
3. Set up your user accounts and groups
4. Configure any additional apps you need

### Recommended Post-Installation Steps

1. **Enable Two-Factor Authentication**
   - Go to Settings > Security
   - Set up TOTP or U2F for additional security

2. **Configure Email**
   - Go to Settings > Administration > Basic settings
   - Set up SMTP for email notifications

3. **Set Up Background Jobs**
   - Recommended: Set up cron for background jobs
   - Run `sudo -u www-data php /var/www/nextcloud/occ background:job:list` to verify

## Backup and Recovery

### Creating Backups

```bash
# Create a manual backup
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on
sudo rsync -Aavx /var/www/nextcloud/ /path/to/backup/
sudo mysqldump --single-transaction -u root -p nextcloud > nextcloud-sqlbkp_`date +"%Y%m%d"`.bak
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off
```

### Restoring from Backup

1. Stop the web server:
   ```bash
   sudo systemctl stop apache2
   ```

2. Restore files and database:
   ```bash
   sudo rsync -Aavx /path/to/backup/ /var/www/nextcloud/
   sudo mysql -u root -p nextcloud < nextcloud-sqlbkp_YYYYMMDD.bak
   ```

3. Fix permissions:
   ```bash
   sudo chown -R www-data:www-data /var/www/nextcloud/
   sudo chmod -R 750 /var/www/nextcloud/
   ```

4. Restart services:
   ```bash
   sudo systemctl start apache2
   ```

## Troubleshooting

### Common Issues

1. **502 Bad Gateway Error**
   - Check if PHP-FPM is running: `sudo systemctl status php8.4-fpm`
   - Verify socket permissions in `/etc/php/8.4/fpm/pool.d/www.conf`

2. **Database Connection Issues**
   - Check MySQL service status: `sudo systemctl status mysql`
   - Verify credentials in `/var/www/nextcloud/config/config.php`

3. **File Permissions**
   - Reset permissions:
     ```bash
     sudo chown -R www-data:www-data /var/www/nextcloud/
     sudo find /var/www/nextcloud/ -type d -exec chmod 750 {} \;
     sudo find /var/www/nextcloud/ -type f -exec chmod 640 {} \;
     ```

4. **SSL Certificate Issues**
   - Check certificate status: `sudo certbot certificates`
   - Renew certificates: `sudo certbot renew --dry-run`

### Checking Logs

- Nextcloud log: `tail -f /var/www/nextcloud/data/nextcloud.log`
- Apache error log: `tail -f /var/log/apache2/error.log`
- PHP-FPM log: `tail -f /var/log/php8.4-fpm.log`

## Maintenance

### Updating Nextcloud

1. Put Nextcloud in maintenance mode:
   ```bash
   sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on
   ```

2. Backup your installation:
   ```bash
   sudo rsync -Aavx /var/www/nextcloud/ /path/to/backup/
   ```

3. Run the update:
   ```bash
   cd /var/www/nextcloud
   sudo -u www-data php updater/updater.phar
   ```

4. Update the database:
   ```bash
   sudo -u www-data php occ upgrade
   ```

5. Disable maintenance mode:
   ```bash
   sudo -u www-data php occ maintenance:mode --off
   ```

### System Maintenance

- **Clean up old backups**:
  ```bash
  find /path/to/backups -type f -mtime +30 -delete
  ```

- **Update system packages**:
  ```bash
  sudo apt update && sudo apt upgrade -y
  sudo apt autoremove -y
  ```

## Support

For additional help, please refer to:
- [Nextcloud Documentation](https://docs.nextcloud.com/)
- [Nextcloud Forums](https://help.nextcloud.com/)
- [GitHub Issues](https://github.com/wagura-maurice/nextcloud-setup/issues)

---
*Last updated: $(date +%Y-%m-%d)*