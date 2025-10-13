#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Installing PHP-FPM"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Define PHP version and required extensions
PHP_VERSION="8.4"
PHP_PACKAGES=(
    "php${PHP_VERSION}-fpm"
    "php${PHP_VERSION}-common"
    "php${PHP_VERSION}-cli"
    "php${PHP_VERSION}-gd"
    "php${PHP_VERSION}-curl"
    "php${PHP_VERSION}-intl"
    "php${PHP_VERSION}-mbstring"
    "php${PHP_VERSION}-xml"
    "php${PHP_VERSION}-zip"
    "php${PHP_VERSION}-json"
    "php${PHP_VERSION}-ldap"
    "php${PHP_VERSION}-apcu"
    "php${PHP_VERSION}-redis"
    "php${PHP_VERSION}-imagick"
    "php${PHP_VERSION}-bz2"
    "php${PHP_VERSION}-dom"
    "php${PHP_VERSION}-simplexml"
    "php${PHP_VERSION}-gmp"
    "php${PHP_VERSION}-bcmath"
    "libapache2-mod-fcgid"
)

# Add PHP repository if not already added
if ! grep -q "ondrej/php" /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list 2>/dev/null; then
    log_info "Adding PHP repository..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
    add-apt-repository -y ppa:ondrej/php
    apt-get update
fi

# Install PHP-FPM and extensions
log_info "Installing PHP-FPM ${PHP_VERSION} and extensions..."
DEBIAN_FRONTEND=noninteractive apt-get install -y "${PHP_PACKAGES[@]}"

# Verify installation
if ! command -v "php${PHP_VERSION}" >/dev/null 2>&1; then
    log_error "PHP ${PHP_VERSION} installation failed"
    exit 1
fi

# Create PHP-FPM pool directory if it doesn't exist
PHP_POOL_DIR="/etc/php/${PHP_VERSION}/fpm/pool.d"
if [ ! -d "$PHP_POOL_DIR" ]; then
    mkdir -p "$PHP_POOL_DIR"
fi

# Create a basic PHP-FPM pool configuration
log_info "Creating PHP-FPM pool configuration..."
cat > "${PHP_POOL_DIR}/nextcloud.conf" <<EOF
[nextcloud]
user = www-data
group = www-data
listen = /run/php/php${PHP_VERSION}-fpm-nextcloud.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.max_requests = 500
EOF

# Enable and start PHP-FPM
log_info "Starting PHP-FPM service..."
systemctl enable "php${PHP_VERSION}-fpm"
systemctl start "php${PHP_VERSION}-fpm"

# Verify PHP-FPM is running
if ! systemctl is-active --quiet "php${PHP_VERSION}-fpm"; then
    log_error "PHP-FPM ${PHP_VERSION} failed to start"
    journalctl -u "php${PHP_VERSION}-fpm" -n 50 --no-pager
    exit 1
fi

log_success "PHP-FPM ${PHP_VERSION} installation completed"
log_info "Run the configuration script to optimize PHP settings:"
log_info "  ./src/utilities/configure/configure-php.sh"
