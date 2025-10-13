#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Configuring PHP"

PHP_VERSION="8.4"
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
PHP_POOL="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

if [ ! -f "$PHP_INI" ]; then
    log_error "PHP ${PHP_VERSION} is not installed. Run install-php.sh first."
    exit 1
fi

log_info "Optimizing PHP configuration..."

# Backup original php.ini
cp "$PHP_INI" "${PHP_INI}.bak"

# Configure PHP settings
for setting in \
    "memory_limit=512M" \
    "upload_max_filesize=2G" \
    "post_max_size=2G" \
    "max_execution_time=3600" \
    "max_input_time=3600" \
    "date.timezone=UTC" \
    "opcache.enable=1" \
    "opcache.interned_strings_buffer=8" \
    "opcache.max_accelerated_files=10000" \
    "opcache.memory_consumption=128" \
    "opcache.save_comments=1" \
    "opcache.revalidate_freq=1"; do
    
    key="${setting%=*}"
    value="${setting#*=}"
    
    if grep -q "^;*\s*${key}" "$PHP_INI"; then
        sed -i "s/^;*\s*${key}\s*=.*$/${key} = ${value}/" "$PHP_INI"
    else
        echo "${key} = ${value}" >> "$PHP_INI"
    fi
done

# Configure PHP-FPM pool
log_info "Configuring PHP-FPM pool..."
cp "$PHP_POOL" "${PHP_POOL}.bak"

for setting in \
    "pm = dynamic" \
    "pm.max_children = 50" \
    "pm.start_servers = 5" \
    "pm.min_spare_servers = 4" \
    "pm.max_spare_servers = 6" \
    "pm.max_requests = 500"; do
    
    key="${setting%=*}"
    value="${setting#*=}"
    
    if grep -q "^;*\s*${key}" "$PHP_POOL"; then
        sed -i "s/^;*\s*${key}\s*=.*$/${key} = ${value}/" "$PHP_POOL"
    else
        echo "${key} = ${value}" >> "$PHP_POOL"
    fi
done

# Restart PHP-FPM
log_info "Restarting PHP-FPM..."
systemctl restart "php${PHP_VERSION}-fpm"

log_success "PHP configuration completed"
