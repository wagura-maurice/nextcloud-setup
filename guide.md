# Nextcloud Setup Guide

## Initial Setup

```bash
# Update and install required tools
sudo apt update && sudo apt upgrade -y
sudo apt install -y software-properties-common git
sudo add-apt-repository universe
sudo apt update

# Clone the repository
cd ~
rm -rf nextcloud-setup
git clone https://github.com/wagura-maurice/nextcloud-setup.git
cd nextcloud-setup

cd .env src/

# Make scripts executable
sudo chmod +x prepare-system.sh
sudo chmod +x src/utilities/install/install-*.sh
sudo chmod +x src/utilities/configure/configure-*.sh

# Run system preparation
sudo ./prepare-system.sh
```

## Installation

```bash
# System setup
sudo ./src/utilities/install/install-system.sh
sudo ./src/utilities/configure/configure-system.sh

# Apache
sudo ./src/utilities/install/install-apache.sh
sudo ./src/utilities/configure/configure-apache.sh

# PHP
sudo ./src/utilities/install/install-php.sh
sudo ./src/utilities/configure/configure-php.sh
```

## Verification

```bash
# Check services
sudo systemctl status apache2
sudo systemctl status php8.4-fpm

# Check PHP version
php -v
```

## Post-Installation (Optional)

```bash
# Enable firewall
sudo ufw allow 'Apache Full'
sudo ufw allow 'OpenSSH'
sudo ufw enable

# Install SSL (Let's Encrypt)
sudo apt install -y certbot python3-certbot-apache
sudo certbot --apache
```
