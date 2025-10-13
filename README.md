# 🚀 Nextcloud Enterprise-Grade Deployment Kit

A comprehensive, production-ready Nextcloud deployment solution with enterprise-grade optimizations, security configurations, and automation scripts.

> **Developer**: Wagura Maurice  
> **Contact**: [wagura465@gmail.com](mailto:wagura465@gmail.com)  
> **GitHub**: [github.com/wagura-maurice/nextcloud-setup](https://github.com/wagura-maurice/nextcloud-setup)

## 📋 Table of Contents

### Getting Started
- [✨ Features](#-features)
- [🚀 Quick Start](#-quick-start)
- [📦 Installation](#-installation)

### Core Components
- [🏗️ Architecture](#-architecture)
- [⚙️ Configuration](#-configuration)
- [🔐 Security](#-security-features)

### Data Management
- [💾 Backup](#-backup)
- [🔄 Restore](#-restore)
- [⏰ Scheduled Backups](#-scheduled-backups)
- [☁️ Cloud Storage](#-cloudflare-r2-integration)

### Advanced
- [⚡ Performance Tuning](#-performance-optimization)
- [🔄 Background Tasks](#-background-tasks--cron-configuration)
- [📚 Additional Resources](#-additional-resources)

### Support
- [❓ FAQ](#-faq)
- [📜 License](#-license)
- [📞 Support](#-support)

## 🌟 Features

- **Automated Installation**: Single-command deployment of Nextcloud with all dependencies
- **Performance Optimized**: Pre-configured with PHP 8.4, OPcache, and Redis caching
- **Security Hardened**: Includes security headers, SSL configuration, and best practices
- **Production Ready**: Configured for high availability and reliability
- **Maintenance Tools**: Built-in scripts for backup, updates, and monitoring
- **Resource Efficient**: Optimized for minimal resource usage while maintaining performance
- **Scalable**: Configuration that grows with your needs from small to large deployments

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

## 🖥️ System Requirements

### Hardware Requirements

| Resource | Minimum | Recommended | Enterprise |
|----------|---------|-------------|------------|
| **OS** | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |
| **CPU** | 1 core (2.0 GHz) | 2-4 cores (2.4 GHz+) | 8+ cores (3.0 GHz+) |
| **RAM** | 2GB | 4-8GB | 16GB+ |
| **Storage** | 20GB SSD | 40GB+ SSD | 100GB+ NVMe |
| **Network** | 100 Mbps | 1 Gbps | 1 Gbps+ |
| **Swap** | = RAM (min 2GB) | = RAM (min 4GB) | 8GB+ |

### Software Requirements

- **Web Server**: Apache 2.4+ with mod_php or PHP-FPM
- **Database**: MySQL 8.0+ or MariaDB 10.5+
- **PHP**: 8.2+ with required extensions
- **Cache**: Redis 6.0+ recommended
- **SSL**: Let's Encrypt certificate (auto-configured)

### Additional Requirements

- **Domain Name**: Required for SSL certificates
- **Static IP**: Recommended for production environments
- **Backup Storage**: Cloud storage (R2, S3) or external storage for backups
- **Firewall**: Properly configured firewall (UFW recommended)
- **Monitoring**: Basic server monitoring tools

## 🚀 Quick Start

### Prerequisites

- Ubuntu 22.04 LTS server (minimal installation recommended)
- Root or sudo access
- Git
- Basic knowledge of Linux command line

### 1. Clone the Repository

```bash
git clone https://github.com/wagura-maurice/nextcloud-setup.git
cd nextcloud-setup
```

### 2. Configure Your Installation

Copy the example configuration file and edit it with your settings:

```bash
cp config/nextcloud.conf.example config/nextcloud.conf
nano config/nextcloud.conf
```

Update the following key settings at minimum:
- `NEXTCLOUD_URL`: Your domain name
- `ADMIN_EMAIL`: Your email address
- `DB_PASS` and `DB_ROOT_PASS`: Strong database passwords
- `NEXTCLOUD_ADMIN_PASS`: A strong admin password

### 3. Run the Installation

Make the setup script executable and start the installation:

```bash
chmod +x nextcloud-setup
./nextcloud-setup install all
```

This will install and configure all components in the correct order.

### 4. Access Your Nextcloud Instance

Once the installation is complete, open your web browser and navigate to:
```
https://your-domain.com
```

Log in with the admin credentials you set in the configuration file.

## 🛠️ Using the CLI Tool

The Nextcloud CLI tool provides a unified interface for all management tasks:

### Install Specific Components
```bash
# Install just the database
./nextcloud-setup install database

# Install web server and PHP
./nextcloud-setup install webserver php
```

### Configure Components
```bash
# Configure all components
./nextcloud-setup configure all

# Configure just PHP and Redis
./nextcloud-setup configure php redis
```

### Backup and Restore
```bash
# Create a backup
./nextcloud-setup backup

# Restore from backup
./nextcloud-setup restore /path/to/backup.tar.gz
```

### Maintenance Tasks
```bash
# Run maintenance tasks
./nextcloud-setup maintenance

# Update Nextcloud
./nextcloud-setup update

# Monitor Nextcloud
./nextcloud-setup monitor
```

### Help and Documentation
```bash
# Show help
./nextcloud-setup help
```
- Domain name with DNS properly configured
- SSH access to the server

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
   > sudo certbot delete --cert-name cloud.e-granary.com
   > sudo certbot --apache --non-interactive --agree-tos --email wagura465@gmail.com -d cloud.e-granary.com --redirect
   > ```

   The script will guide you through the installation process and automatically:

   - Install and configure all dependencies (Apache, MySQL/MariaDB, PHP 8.4, Redis)
   - Set up Apache with optimized settings for Nextcloud
   - Configure PHP 8.4 FPM with performance optimizations
   - Secure the installation with Let's Encrypt SSL
   - Set up Redis for caching and file locking
   - Configure automatic backups and maintenance tasks
   - Optimize system settings for Nextcloud performance

4. **Access Your Nextcloud**
   After installation, access your Nextcloud instance at:
   ```
   https://cloud.e-granary.com
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
   MAILTO=wagura465@gmail.com
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

## ☁️ Cloudflare R2 Integration

For backing up to Cloudflare R2 (S3-compatible storage), you'll need to install the AWS CLI tool and configure it with your R2 credentials.

### Prerequisites

1. **Install AWS CLI**
   ```bash
   # Install AWS CLI v2 (recommended)
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   
   # Verify installation
   aws --version
   ```

2. **Configure AWS CLI for R2**
   ```bash
   aws configure
   ```
   When prompted, enter:
   - **AWS Access Key ID**: Your R2 Access Key ID
   - **AWS Secret Access Key**: Your R2 Secret Access Key
   - **Default region name**: `auto` (or your preferred region)
   - **Default output format**: `json`

3. **Add R2 Endpoint to AWS Config**
   Edit `~/.aws/config` and add:
   ```ini
   [profile default]
   region = auto
   s3 =
     endpoint_url = https://<your-account-id>.r2.cloudflarestorage.com
   s3_use_path_style = true
   ```
   Replace `<your-account-id>` with your Cloudflare account ID.

### Configuration in Backup Script

Update your `backup-config.conf` with the following R2 settings:

```ini
# Cloudflare R2 Configuration
R2_ACCESS_KEY_ID="your-r2-access-key"
R2_SECRET_ACCESS_KEY="your-r2-secret-key"
R2_BUCKET="your-bucket-name"
R2_ENDPOINT="https://<your-account-id>.r2.cloudflarestorage.com"
R2_REGION="auto"
```

### Testing R2 Connection

Verify your R2 setup with:

```bash
# List buckets
aws s3 ls --endpoint-url https://<your-account-id>.r2.cloudflarestorage.com

# Test upload
echo "test" > test.txt
aws s3 cp test.txt s3://your-bucket-name/ --endpoint-url https://<your-account-id>.r2.cloudflarestorage.com
```

## 🏗️ Architecture

### PHP-FPM with Apache

This deployment kit uses PHP 8.4 FPM (FastCGI Process Manager) with Apache's `mod_proxy_fcgi` module, providing several advantages over traditional `mod_php`:

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
