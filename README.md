# 🚀 Nextcloud Enterprise-Grade Deployment Kit

A comprehensive, production-ready Nextcloud deployment solution with enterprise-grade optimizations, security configurations, and automation scripts. Developed by **Wagura Maurice** ([wagura465@gmail.com](mailto:wagura465@gmail.com)).

## 🌟 Features

- **Automated Installation**: Single-command deployment of Nextcloud with all dependencies
- **Performance Optimized**: Pre-configured with PHP 8.4, OPcache, and Redis caching
- **Security Hardened**: Includes security headers, SSL configuration, and best practices
- **Production Ready**: Configured for high availability and reliability
- **Maintenance Tools**: Built-in scripts for backup, updates, and monitoring

## 🏗️ Architecture

```
nextcloud-setup/
├── scripts/              # Deployment and maintenance scripts
│   └── install-nextcloud.sh  # Main installation script
├── configs/              # Configuration templates
│   ├── apache-nextcloud.conf  # Apache virtual host configuration
│   ├── php-settings.ini      # PHP-FPM performance tuning
│   └── install-config.conf   # Installation parameters
└── docs/                 # Documentation
    └── installation-guide.md  # Detailed setup instructions
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
   ```bash
   # Make the script executable and run it
   chmod +x scripts/install-nextcloud.sh
   sudo ./scripts/install-nextcloud.sh
   ```

   The script will guide you through the installation process and automatically:
   - Install and configure all dependencies
   - Set up Apache with optimized settings
   - Configure PHP 8.4 with FPM
   - Secure the installation with Let's Encrypt SSL
   - Optimize Nextcloud for production use

4. **Access Your Nextcloud**
   After installation, access your Nextcloud instance at:
   ```
   https://data.amarissolutions.com
   ```
   Use the admin credentials provided during installation.

## 🔧 Advanced Configuration

### Customizing the Installation

Edit the configuration file before running the installation:
```bash
nano configs/install-config.conf
```

### Available Configuration Options

- **Database Settings**: Configure MySQL/MariaDB credentials
- **Domain Configuration**: Set your domain name and SSL options
- **Performance Tuning**: Adjust PHP and Apache settings
- **Security Options**: Configure security headers and access controls

## 🛡️ Security Features

- Automatic SSL certificate provisioning with Let's Encrypt
- Security headers (HSTS, CSP, XSS Protection)
- PHP security optimizations
- Redis-based file locking and caching
- Regular security updates and maintenance scripts

## 📈 Performance Optimizations

- PHP 8.4 with OPcache and JIT compilation
- Redis caching for sessions and file operations
- HTTP/2 and Brotli compression
- Database optimization and maintenance

## 🤝 Support

For support, feature requests, or contributions, please contact:
- **Wagura Maurice**
- Email: [wagura465@gmail.com](mailto:wagura465@gmail.com)

## 📜 License

This project is open-source and available under the MIT License.