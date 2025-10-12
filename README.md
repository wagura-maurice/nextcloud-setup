# 🚀 Nextcloud Enterprise-Grade Deployment Kit

A comprehensive, production-ready Nextcloud deployment solution with enterprise-grade optimizations, security configurations, and automation scripts. Developed by **Wagura Maurice** ([wagura465@gmail.com](mailto:wagura465@gmail.com)).

## 📋 Table of Contents
- [Features](#-features)
- [Quick Start](#-quick-start)
- [Installation](#-installation)
- [Backup](#-backup)
- [Restore](#-restore)
- [Scheduled Backups](#-scheduled-backups)
- [Advanced Configuration](#-advanced-configuration)
- [Security Features](#-security-features)
- [Architecture](#-architecture-php-fpm-with-apache)
- [Background Tasks](#-background-tasks--cron-configuration)
- [License](#-license)
- [Support](#-support)

## 🌟 Features

- **Automated Installation**: Single-command deployment of Nextcloud with all dependencies
- **Performance Optimized**: Pre-configured with PHP 8.4, OPcache, and Redis caching
- **Security Hardened**: Includes security headers, SSL configuration, and best practices
- **Production Ready**: Configured for high availability and reliability
- **Maintenance Tools**: Built-in scripts for backup, updates, and monitoring

## 🏗️ Architecture

```
nextcloud-setup/
├── scripts/                  # Deployment and maintenance scripts
│   ├── install-nextcloud.sh  # Main installation script
│   ├── backup-nextcloud.sh   # Backup script with incremental support
│   ├── restore-nextcloud.sh  # Restore script for full/incremental backups
│   └── configure-php.sh      # PHP configuration helper
├── configs/                  # Configuration files
│   ├── apache-nextcloud.conf # Apache virtual host configuration
│   ├── php-settings.ini      # PHP-FPM performance tuning
│   ├── install-config.conf   # Installation parameters
│   ├── backup-config.conf    # Backup configuration
│   └── restore-config.conf   # Restore configuration
└── docs/                     # Documentation
    └── installation-guide.md # Detailed setup instructions
```

## 🚀 Quick Start

### Prerequisites

- Ubuntu 22.04 LTS server
- Minimum 2GB RAM (4GB+ recommended for production)
- Root or sudo access
- Minimum 20GB free disk space (SSD recommended)
- Domain name pointed to your server's IP

### Installation

1. **Prepare Your System**

   ```bash
   # Update system and install Git
   sudo apt update && sudo apt upgrade -y
   sudo apt install -y git
   ```

2. **Clone the Repository**

   ```bash
   git clone https://github.com/wagura-maurice/nextcloud-setup.git
   cd nextcloud-setup
   ```

3. **Run the Installation**

   For a production environment with a valid SSL certificate:
   ```bash
   # Make the script executable and run it
   chmod +x scripts/install-nextcloud.sh
   sudo ./scripts/install-nextcloud.sh # will trigger ssl staging by default
   sudo ./scripts/install-nextcloud.sh --ssl=production # will trigger ssl production explicityly 
   ```

   For testing/development with a staging SSL certificate (avoids rate limits):
   ```bash
   sudo ./scripts/install-nextcloud.sh --ssl=staging # will trigger ssl staging explicityly 
   ```

   > **Note**: The staging certificate will trigger browser security warnings. 
   > To switch to production later, run:
   > ```bash
   > sudo certbot delete --cert-name cloud.amarissolutions.com
   > sudo certbot --apache --non-interactive --agree-tos --email wagura465@gmail.com -d cloud.amarissolutions.com --redirect
   > ```

   The script will guide you through the installation process and automatically:

   - Install and configure all dependencies
   - Set up Apache with optimized settings
   - Configure PHP 8.4 with FPM
   - Secure the installation with Let's Encrypt SSL
   - Optimize Nextcloud for production use

4. **Access Your Nextcloud**
   After installation, access your Nextcloud instance at:
   ```
   https://cloud.amarissolutions.com
   ```
   Use the admin credentials provided during installation.

## 💾 Backup

### Backup Script (`backup-nextcloud.sh`)

#### Features
- Full and incremental backup support
- Database backup with transaction support
- Cloudflare R2 storage integration
- Configurable retention policy
- Detailed logging and error handling

#### Usage

```bash
# Run a full backup
sudo ./scripts/backup-nextcloud.sh

# Force a full backup (ignore incremental)
sudo ./scripts/backup-nextcloud.sh --full

# Run with custom config file
sudo ./scripts/backup-nextcloud.sh --config /path/to/backup-config.conf
```

#### Configuration (`configs/backup-config.conf`)
```ini
# Backup Configuration
BACKUP_DIR="/var/nextcloud_backups"
RETAIN_DAYS=30

# Database Configuration
DB_NAME="nextcloud"
DB_USER="nextcloud"
DB_PASS="your_db_password"

# Cloudflare R2 Configuration (optional)
R2_ACCESS_KEY_ID=""
R2_SECRET_ACCESS_KEY=""
R2_BUCKET=""
R2_ENDPOINT=""

# What to backup (true/false)
BACKUP_DATA=true
BACKUP_CONFIG=true
BACKUP_APPS=true
BACKUP_DATABASE=true

# Email notifications (optional)
NOTIFICATION_EMAIL=""
```

## 🔄 Restore

### Restore Script (`restore-nextcloud.sh`)

#### Features
- Restores both full and incremental backups
- Handles database restoration
- Maintains file permissions
- Pre/Post restore hooks
- Detailed logging

#### Usage

```bash
# Restore from a local backup
sudo ./scripts/restore-nextcloud.sh /path/to/backup.tar.gz

# Restore from R2 storage
sudo ./scripts/restore-nextcloud.sh s3://bucket-name/backup.tar.gz

# Run with custom config file
sudo ./scripts/restore-nextcloud.sh --config /path/to/restore-config.conf /path/to/backup
```

#### Configuration (`configs/restore-config.conf`)
```ini
# Database Configuration
DB_NAME="nextcloud"
DB_USER="nextcloud"
DB_PASS="your_db_password"

# Paths
NEXTCLOUD_ROOT="/var/www/nextcloud"
NEXTCLOUD_DATA="${NEXTCLOUD_ROOT}/data"

# What to restore (true/false)
RESTORE_DATA=true
RESTORE_CONFIG=true
RESTORE_APPS=true
RESTORE_DATABASE=true

# Service Control
RESTART_SERVICES=true

# Logging
LOG_FILE="/var/log/nextcloud/restore.log"
LOG_LEVEL="INFO"  # DEBUG, INFO, WARNING, ERROR
```

## ⏰ Scheduled Backups

To set up automatic daily backups:

1. Edit the crontab:
   ```bash
   sudo crontab -e
   ```

2. Add the following line to run daily at 2 AM:
   ```
   0 2 * * * /path/to/nextcloud-setup/scripts/backup-nextcloud.sh
   ```

3. To receive email notifications, add your email:
   ```
   MAILTO=your-email@example.com
   0 2 * * * /path/to/nextcloud-setup/scripts/backup-nextcloud.sh
   ```

## 🔧 Advanced Configuration

### Customizing the Installation

Edit the configuration files before running the scripts:

```bash
# Installation configuration
nano configs/install-config.conf

# Backup configuration
nano configs/backup-config.conf

# Restore configuration
nano configs/restore-config.conf
```

### Available Configuration Options

- **Installation**: Database settings, domain configuration, SSL options
- **Backup**: Retention policy, cloud storage, notification settings
- **Restore**: Selective restoration, service control, logging options
- **Performance**: PHP and Apache tuning, caching configuration
- **Security**: Access controls, file permissions, encryption

## 🛡️ Security Features

- Automatic SSL certificate provisioning with Let's Encrypt
- Security headers (HSTS, CSP, XSS Protection)
- PHP security optimizations
- Redis-based file locking and caching
- Regular security updates and maintenance scripts

## 🏗️ Architecture: PHP-FPM with Apache

This deployment kit uses PHP 8.4 FPM (FastCGI Process Manager) with Apache's `mod_proxy_fcgi` module, which provides several advantages over traditional `mod_php`:

### Key Components

1. **Apache with `mod_proxy_fcgi`**

   - Handles HTTP/HTTPS requests
   - Serves static files directly
   - Proxies PHP requests to PHP-FPM via FastCGI

2. **PHP 8.4 FPM**

   - Runs as a separate service with its own process manager
   - Uses Unix domain sockets for communication
   - Configurable process management (pm = dynamic/ondemand)

3. **Performance Optimizations**
   - OPcache with JIT compilation
   - Realpath caching
   - Optimized PHP-FPM process manager settings
   - Redis for session and file locking

### Benefits Over Traditional mod_php

1. **Better Resource Management**

   - PHP processes run independently of Apache threads
   - Memory is not tied to Apache processes
   - More efficient handling of concurrent requests

2. **Improved Security**

   - PHP runs as a separate user (www-data)
   - Better isolation between web server and PHP processes
   - Reduced attack surface compared to mod_php

3. **Enhanced Performance**

   - Lower memory usage per request
   - Better handling of high traffic loads
   - More stable under heavy load

4. **Flexibility**
   - Easier to scale PHP processes independently
   - Can run PHP on a different server if needed
   - Better support for modern PHP features

### Configuration Highlights

- PHP-FPM pool configuration optimized for Nextcloud
- Apache MPM Event with optimized settings
- Proper file permissions and security hardening
- Redis-based session and file locking

## 🔄 Background Tasks & Cron Configuration

Nextcloud requires regular background tasks for maintenance and optimal performance. This setup implements a robust solution using both systemd timers and traditional cron jobs.

### 1. Systemd Timer (Recommended)

- **Service**: `nextcloudcron.service`
- **Timer**: `nextcloudcron.timer`
- **Schedule**: Runs every 5 minutes
- **User**: Runs as root with proper permissions

Key Features:

- Automatic startup on system boot
- Proper process isolation
- Logging and monitoring via journald
- Automatic retry on failure

### 2. Traditional Cron Job

- **User**: www-data
- **Schedule**: `*/5 * * * *` (Every 5 minutes)
- **Command**: `php -f /var/www/nextcloud/cron.php`

### Verification

After installation, verify the cron setup with:

```bash
# Check systemd timer status
systemctl status nextcloudcron.timer

# Check when the timer will trigger next
systemctl list-timers | grep nextcloud

# View cron jobs for www-data
sudo -u www-data crontab -l
```

## 🚀 Performance Optimizations

- **PHP 8.4 with OPcache and JIT**

  - OPcache with 256MB memory
  - Optimized realpath cache settings
  - JIT compilation for better performance

- **Caching Layers**

  - Redis for session handling
  - File locking via Redis
  - APCu for local caching (if available)

- **Web Server Optimizations**

  - HTTP/2 support
  - Brotli and Gzip compression
  - Proper cache headers for static assets

- **Database Optimizations**
  - InnoDB buffer pool configuration
  - Query cache settings
  - Connection pooling

## 🤝 Support

For support, feature requests, or contributions, please contact:

- **Wagura Maurice**
- Email: [wagura465@gmail.com](mailto:wagura465@gmail.com)

## 📜 License

This project is open-source and available under the MIT License.
