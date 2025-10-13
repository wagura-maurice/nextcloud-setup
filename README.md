# 🚀 Nextcloud Enterprise-Grade Deployment Kit

## 📋 Table of Contents

- [System Requirements](#-system-requirements)
- [Prerequisites](#-prerequisites)
- [Installation Steps](#-installation-steps)
  - [1. System Preparation](#1-system-preparation)
  - [2. Install and Configure System Dependencies](#2-install-and-configure-system-dependencies)
  - [3. Install and Configure Apache](#3-install-and-configure-apache)
  - [4. Install and Configure MariaDB](#4-install-and-configure-mariadb)
  - [5. Install and Configure PHP](#5-install-and-configure-php)
  - [6. Install and Configure Redis](#6-install-and-configure-redis)
  - [7. Install and Configure Certbot](#7-install-and-configure-certbot)
  - [8. Install and Configure Nextcloud](#8-install-and-configure-nextcloud)
  - [9. Final Configuration](#9-final-configuration)
- [Post-Installation](#-post-installation)
- [Troubleshooting](#-troubleshooting)

## 🖥️ System Requirements

### Hardware Requirements

- **CPU**: 2 cores (4+ recommended)
- **RAM**: 2GB minimum (4GB+ recommended)
- **Storage**: 20GB minimum (SSD recommended)
- **Network**: 100 Mbps minimum (1 Gbps recommended)

### Software Requirements

- **OS**: Ubuntu 22.04 LTS (recommended)
- **Web Server**: Apache 2.4+
- **Database**: MariaDB 10.5+ or MySQL 8.0+
- **PHP**: 8.2+
- **Cache**: Redis 6.0+

## 📋 Prerequisites

1. Fresh Ubuntu 22.04 LTS installation
2. Root or sudo privileges
3. Domain name pointing to your server
4. Minimum 2GB RAM (4GB+ recommended for production)
5. Basic Linux command line knowledge

## 🚀 Installation Steps

### 1. System Preparation

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install required tools
sudo apt install -y software-properties-common
sudo add-apt-repository universe
sudo apt update
sudo apt install -y git curl wget nano

# Clone the repository
cd ~
rm -rf nextcloud-setup
git clone https://github.com/wagura-maurice/nextcloud-setup.git
cd nextcloud-setup

# Make all scripts executable
sudo chmod +x ./prepare-system.sh
sudo chmod +x src/utilities/install/*.sh
sudo chmod +x src/utilities/configure/*.sh

# Run system preparation script
sudo ./prepare-system.sh
```

### 2. Install and Configure System Dependencies

```bash
# Install system dependencies
sudo ./src/utilities/install/install-system.sh

# Configure system dependencies
sudo ./src/utilities/configure/configure-system.sh
```

### 3. Install and Configure Apache

```bash
# Install Apache
sudo ./src/utilities/install/install-apache.sh

# Configure Apache for Nextcloud
sudo ./src/utilities/configure/configure-apache.sh
```

### 4. Install and Configure MariaDB

```bash
# Install MariaDB
sudo ./src/utilities/install/install-mariadb.sh

# Secure MariaDB installation
sudo ./src/utilities/configure/configure-mariadb.sh
```

### 5. Install and Configure PHP

```bash
# Install PHP and required extensions
sudo ./src/utilities/install/install-php.sh

# Configure PHP for Nextcloud
sudo ./src/utilities/configure/configure-php.sh
```

### 6. Install and Configure Redis

```bash
# Install Redis
sudo ./src/utilities/install/install-redis.sh

# Configure Redis for Nextcloud
sudo ./src/utilities/configure/configure-redis.sh
```

### 7. Install and Configure Certbot

```bash
# Install Certbot for SSL certificates
sudo ./src/utilities/install/install-certbot.sh

# Configure SSL certificates
sudo ./src/utilities/configure/configure-certbot.sh
```

### 8. Install and Configure Nextcloud

```bash
# Install Nextcloud
sudo ./src/utilities/install/install-nextcloud.sh

# Configure Nextcloud
sudo ./src/utilities/configure/configure-nextcloud.sh
```

### 9. Final Configuration

```bash
# Set up scheduled tasks
sudo ./src/utilities/configure/configure-cron.sh
```

## 🎉 Post-Installation

1. Access your Nextcloud instance at: `https://your-domain.com`
2. Log in with the admin credentials you set during installation
3. Complete the setup wizard
4. Install recommended apps from the app store
5. Set up your users and groups

## 🔍 Troubleshooting

### Common Issues

1. **Permission Issues**

   ```bash
   sudo chown -R www-data:www-data /var/www/nextcloud/
   sudo chmod -R 755 /var/www/nextcloud/
   ```

2. **Check Service Status**

   ```bash
   sudo systemctl status apache2
   sudo systemctl status mariadb
   sudo systemctl status redis-server
   ```

3. **View Logs**

   ```bash
   # Apache error log
   sudo tail -f /var/log/apache2/error.log

   # Nextcloud log
   sudo tail -f /var/www/nextcloud/data/nextcloud.log
   ```

4. **Check Firewall**
   ```bash
   sudo ufw status
   sudo ufw allow 'Apache Full'
   sudo ufw allow OpenSSH
   ```

### Getting Help

If you encounter any issues, please check the following:

- Verify all services are running
- Check file permissions
- Review the logs mentioned above
- Ensure your domain's DNS is properly configured

### Troubleshooting

- **Firewall Warning**: The firewall configuration warning during system installation is non-critical and can be ignored.
- **Path Issues**: If you encounter path-related errors, make sure to run the path fix command in step 4.
- **Logs**: Check logs in the `logs/` directory for detailed error information.

---

## 🚀 Nextcloud Enterprise-Grade Deployment Kit

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

| Resource    | Minimum          | Recommended          | Enterprise          |
| ----------- | ---------------- | -------------------- | ------------------- |
| **OS**      | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS     | Ubuntu 22.04 LTS    |
| **CPU**     | 1 core (2.0 GHz) | 2-4 cores (2.4 GHz+) | 8+ cores (3.0 GHz+) |
| **RAM**     | 2GB              | 4-8GB                | 16GB+               |
| **Storage** | 20GB SSD         | 40GB+ SSD            | 100GB+ NVMe         |
| **Network** | 100 Mbps         | 1 Gbps               | 1 Gbps+             |
| **Swap**    | = RAM (min 2GB)  | = RAM (min 4GB)      | 8GB+                |

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

## 🛠️ System Preparation

Before running the main setup, you'll need to prepare your system by running the `prepare-system.sh` script. This script sets up the required directory structure and permissions.

### Prerequisites

- Linux-based system (Ubuntu/Debian recommended)
- Sudo privileges
- Basic system utilities (git, curl, etc.)

### Running the Preparation Script

1. **Make the script executable** (if not already):

   ```bash
   chmod +x prepare-system.sh
   ```

2. **Run the script with sudo** (requires root privileges):
   ```bash
   sudo ./prepare-system.sh
   ```

### What the Script Does

1. **Creates Required Directories**:

   - `logs/`: For storing system and application logs
   - `config/`: For configuration files
   - `data/`: For application data

2. **Sets Up Permissions**:

   - Ensures proper ownership and permissions for web server access
   - Creates necessary system directories
   - Sets up log rotation

3. **Environment Setup**:
   - Creates a `.env` file from `.env.example` if it doesn't exist
   - Sets up proper permissions for sensitive files

### Troubleshooting

- **Permission Denied Errors**: Ensure you're running the script with `sudo`
- **Missing Dependencies**: The script will attempt to install required packages automatically
- **Logs**: Check the log file in `logs/prepare-*.log` for detailed output

## 🚀 Quick Start

### Prerequisites

- Ubuntu 22.04 LTS server (minimal installation recommended)
- Root or sudo access
- Git
- Domain name pointing to your server (for SSL certificates)
- Minimum 2GB RAM (4GB+ recommended for production)

### 1. Clone and Prepare

```bash
# Clone the repository
git clone https://github.com/wagura-maurice/nextcloud-setup.git
cd nextcloud-setup

# Make the preparation script executable and run it
chmod +x prepare-system.sh
sudo ./prepare-system.sh
```

### 2. Configure Your Installation

Edit the `.env` file to set your preferences:

```bash
# Copy the example config if it doesn't exist
cp .env.example .env

# Edit the configuration
nano .env  # or use your preferred text editor
```

Key settings to configure:

- `NEXTCLOUD_DOMAIN`: Your domain name (e.g., cloud.yourdomain.com)
- `NEXTCLOUD_ADMIN_USER`: Desired admin username
- `NEXTCLOUD_ADMIN_PASSWORD`: Strong admin password
- `MYSQL_ROOT_PASSWORD`: Secure MySQL root password
- `NEXTCLOUD_DB_PASSWORD`: Secure database password for Nextcloud

### 3. Run the Installation

```bash
# Start the installation process
./setup-nextcloud
```

The installer will:

1. Install all required dependencies
2. Configure the web server and database
3. Set up SSL certificates (Let's Encrypt)
4. Install and configure Nextcloud
5. Optimize system settings for performance

### 4. Access Your Nextcloud Instance

Once installation completes, access your Nextcloud at:

```
https://cloud.yourdomain.com
```

### 5. Post-Installation

1. **Verify Installation**:

   ```bash
   # Check system status
   ./manage-nextcloud status
   ```

2. **Regular Maintenance**:

   ```bash
   # Perform system updates and maintenance
   ./manage-nextcloud maintenance
   ```

3. **Backup Your Data**:
   ```bash
   # Create a complete backup
   ./manage-nextcloud backup
   ```

### 6. Getting Help

- View available commands:
  ```bash
  ./manage-nextcloud help
  ```
- Check logs:
  ```bash
  sudo tail -f /var/log/nextcloud/nextcloud.log
  ```

## 📋 Project Structure

```
/
├── src/                    # Source code
│   ├── bin/               # Main executable scripts
│   │   ├── setup-nextcloud.sh
│   │   └── manage-nextcloud.sh
│   └── utilities/         # Supporting scripts
│       ├── install/       # Installation scripts
│       └── configure/     # Configuration scripts
├── setup-nextcloud        # Launcher for setup
├── manage-nextcloud       # Launcher for management
└── prepare-system.sh      # System preparation script
```

### Main Commands:

- `./prepare-system.sh` - Initial system preparation (run once)
- `./setup-nextcloud` - Install and configure Nextcloud
- `./manage-nextcloud` - Manage and maintain your installation

## 🛠️ Script Details

### Setup Nextcloud (`./setup-nextcloud`)

Launcher for the main setup script (`src/bin/setup-nextcloud.sh`). Handles the complete installation and configuration of:

- System dependencies
- Web server (Apache/Nginx)
- PHP and extensions
- Database (MariaDB/PostgreSQL)
- Redis caching
- SSL certificates (Let's Encrypt)
- Nextcloud core installation

### Nextcloud Manager (`./manage-nextcloud`)

Launcher for the management script (`src/bin/manage-nextcloud.sh`). Provides tools for:

- Backup and restore operations
- System maintenance
- Performance optimization
- Security checks
- Monitoring and logging

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

````

The Nextcloud CLI tool provides a unified interface for all management tasks:

### Install Specific Components
```bash
{{ ... }}
# Install just the database
./nextcloud-setup install mariadb

# Install Apache and PHP
./nextcloud-setup install apache php
````

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

1. **Clone and Prepare**

   ```bash
   # Clone the repository
   git clone https://github.com/wagura-maurice/nextcloud-setup.git
   cd nextcloud-setup

   # Run the system preparation script
   sudo ./prepare-system.sh
   ```

2. **Run System Installation**

   ```bash
   # Make all installation scripts executable
   sudo chmod +x src/utilities/install/*.sh

   # Install system dependencies and core components
   sudo ./src/utilities/install/install-system.sh

   # Install and configure Apache
   sudo ./src/utilities/install/install-apache.sh

   # Install and configure MariaDB
   sudo ./src/utilities/install/install-mariadb.sh

   # Install and configure PHP
   sudo ./src/utilities/install/install-php.sh

   # Install and configure Redis
   sudo ./src/utilities/install/install-redis.sh

   # Install and configure Certbot for SSL
   sudo ./src/utilities/install/install-certbot.sh

   # Install Nextcloud
   sudo ./src/utilities/install/install-nextcloud.sh
   ```

3. **Run Configuration Scripts**
   After installation completes, configure all components:

   ```bash
   # Make all configuration scripts executable
   sudo chmod +x src/utilities/configure/*.sh

   # Configure system settings
   sudo ./src/utilities/configure/configure-system.sh

   # Configure Apache web server
   sudo ./src/utilities/configure/configure-apache.sh

   # Configure MariaDB database
   sudo ./src/utilities/configure/configure-mariadb.sh

   # Configure PHP settings
   sudo ./src/utilities/configure/configure-php.sh

   # Configure Redis caching
   sudo ./src/utilities/configure/configure-redis.sh

   # Configure SSL certificates with Certbot
   sudo ./src/utilities/configure/configure-certbot.sh

   # Configure scheduled tasks
   sudo ./src/utilities/configure/configure-cron.sh

   # Finalize Nextcloud configuration
   sudo ./src/utilities/configure/configure-nextcloud.sh
   ```

4. **Complete the Setup**
   Follow the on-screen prompts to complete your Nextcloud installation. The scripts will automatically:

   - Configure all installed components
   - Set up security certificates
   - Optimize the server for Nextcloud
   - Set up Redis for caching
   - Configure scheduled maintenance tasks
   - Provide you with login details

5. **Access Your Nextcloud**
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
