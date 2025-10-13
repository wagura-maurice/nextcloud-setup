#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Installing PHP"

# Define required PHP version and extensions
PHP_VERSION="8.4"
PHP_PACKAGES="php${PHP_VERSION} php${PHP_VERSION}-fpm php${PHP_VERSION}-common \
    php${PHP_VERSION}-mysql php${PHP_VERSION}-gd php${PHP_VERSION}-json \
    php${PHP_VERSION}-curl php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-intl php${PHP_VERSION}-imagick \
    php${PHP_VERSION}-xml php${PHP_VERSION}-zip \
    php${PHP_VERSION}-bcmath php${PHP_VERSION}-gmp"

# Add PHP repository
log_info "Adding PHP repository..."
apt-get update
apt-get install -y software-properties-common
add-apt-repository -y ppa:ondrej/php
apt-get update

# Install PHP and extensions
log_info "Installing PHP ${PHP_VERSION} and extensions..."
DEBIAN_FRONTEND=noninteractive apt-get install -y $PHP_PACKAGES

# Configure PHP-FPM
log_info "Configuring PHP-FPM..."
sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" "/etc/php/${PHP_VERSION}/fpm/php.ini"
systemctl enable "php${PHP_VERSION}-fpm"
systemctl restart "php${PHP_VERSION}-fpm"

log_success "PHP ${PHP_VERSION} installation completed"
