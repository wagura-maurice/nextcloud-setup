#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Installing System Dependencies"

# Update package lists
log_info "Updating package lists..."
apt-get update

# Install essential system utilities
log_info "Installing essential system utilities..."
apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    unzip \
    wget \
    htop \
    net-tools \
    vim \
    git \
    jq \
    supervisor \
    logrotate \
    cron \
    rsync \
    fail2ban \
    ufw \
    locales \
    tzdata \
    acl \
    sudo

# Install build essentials for compiling packages
log_info "Installing build essentials..."
apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    autoconf \
    automake \
    libtool \
    make \
    g++

# Install SSL/TLS and Let's Encrypt (Certbot)
log_info "Installing SSL/TLS and Let's Encrypt (Certbot)..."
apt-get install -y --no-install-recommends \
    openssl \
    ssl-cert \
    certbot \
    python3-certbot-apache \
    python3-certbot-doc \
    python3-certbot-nginx \
    python3-pip

# Install Certbot DNS plugins (for DNS challenges)
pip3 install --upgrade pip
pip3 install certbot-dns-cloudflare \
             certbot-dns-digitalocean \
             certbot-dns-route53 \
             certbot-dns-google \
             certbot-dns-cloudxns \
             certbot-dns-luadns \
             certbot-dns-nsone \
             certbot-dns-rfc2136 \
             certbot-dns-ovh \
             certbot-dns-linode

# Create directories for Let's Encrypt
mkdir -p /etc/letsencrypt/{live,renewal,archive}
chmod 0755 /etc/letsencrypt/{live,renewal,archive}

# Create a pre and post renewal hooks directory
mkdir -p /etc/letsencrypt/renewal-hooks/{pre,deploy,post}

# Create a script to test certificate renewal (dry run)
cat > /usr/local/bin/test-cert-renewal << 'EOF'
#!/bin/bash
/usr/bin/certbot renew --dry-run
EOF
chmod +x /usr/local/bin/test-cert-renewal

# Install monitoring and debugging tools
log_info "Installing monitoring tools..."
apt-get install -y --no-install-recommends \
    dstat \
    iotop \
    iftop \
    nmon \
    sysstat \
    lsof \
    strace \
    lshw \
    hdparm \
    smartmontools

# Clean up
log_info "Cleaning up..."
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

# Set up basic firewall rules
log_info "Configuring firewall..."
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable

# Test Let's Encrypt installation
log_info "Testing Let's Encrypt client..."
if command -v certbot >/dev/null 2>&1; then
    certbot --version
    log_success "Let's Encrypt (Certbot) is installed and working"
else
    log_warning "Let's Encrypt (Certbot) installation might have issues"
fi

# Create a renewal hook for Apache
cat > /etc/letsencrypt/renewal-hooks/deploy/01-reload-apache << 'EOF'
#!/bin/bash
# This script will be called by certbot when a certificate is renewed
# Reload Apache to pick up the new certificate
if command -v apache2ctl >/dev/null 2>&1; then
    if systemctl is-active --quiet apache2; then
        systemctl reload apache2
        echo "[$(date)] Apache reloaded after certificate renewal" >> /var/log/letsencrypt/renewal-hooks.log
    else
        echo "[$(date)] Warning: Apache is not running, could not reload" >> /var/log/letsencrypt/renewal-hooks.log
    fi
else
    echo "[$(date)] Error: Apache not found" >> /var/log/letsencrypt/renewal-hooks.log
fi
EOF
chmod +x /etc/letsencrypt/renewal-hooks/deploy/01-reload-apache

# Create log directory for renewal hooks
mkdir -p /var/log/letsencrypt/
touch /var/log/letsencrypt/renewal-hooks.log
chmod 644 /var/log/letsencrypt/renewal-hooks.log

log_success "System dependencies installation completed"
log_info "Basic system utilities and dependencies have been installed"
log_info "Let's Encrypt (Certbot) is ready to use"
