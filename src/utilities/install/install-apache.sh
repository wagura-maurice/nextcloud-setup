#!/bin/bash
set -euo pipefail

# Hardcode the project root and core directories
PROJECT_ROOT="/root/nextcloud-setup"
CORE_DIR="${PROJECT_ROOT}/src/core"

# Source core utilities
source "${CORE_DIR}/config-manager.sh" 2>/dev/null || { 
    echo "Error: Failed to load ${CORE_DIR}/config-manager.sh" >&2
    exit 1
}
source "${CORE_DIR}/env-loader.sh" 2>/dev/null || { 
    echo "Error: Failed to load ${CORE_DIR}/env-loader.sh" >&2
    exit 1
}
source "${CORE_DIR}/logging.sh" 2>/dev/null || { 
    echo "Error: Failed to load ${CORE_DIR}/logging.sh" >&2
    exit 1
}

# Initialize environment and logging
load_environment
init_logging

log_section "Apache Installation"

# Function to install packages with retries
install_packages() {
    local packages=("$@")
    local max_attempts=3
    local delay=5
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log_info "Installing packages (attempt $attempt of $max_attempts)..."
        
        # First update package lists
        if ! apt-get update; then
            log_warning "Failed to update package lists, retrying in ${delay} seconds..."
            sleep $delay
            attempt=$((attempt + 1))
            continue
        fi
        
        # Try to install packages
        if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"; then
            log_info "Successfully installed packages"
            return 0
        fi
        
        log_warning "Package installation failed, retrying in ${delay} seconds..."
        sleep $delay
        attempt=$((attempt + 1))
    done
    
    log_error "Failed to install packages after $max_attempts attempts"
    return 1
}

# Function to install Apache
install_apache() {
    log_info "Starting Apache installation..."
    
    # Check for conflicting services
    log_info "Checking for conflicting services..."
    local conflicting_services=("nginx" "lighttpd" "httpd")
    for service in "${conflicting_services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_warning "Stopping conflicting service: $service"
            systemctl stop "$service"
            systemctl disable "$service" 2>/dev/null || true
        fi
    done
    
    # Add PHP 8.4 repository
    log_info "Adding PHP 8.4 repository..."
    if ! add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1; then
        apt-get install -y software-properties-common
        add-apt-repository -y ppa:ondrej/php
    fi
    apt-get update

    # Required packages for PHP 8.4
    local required_packages=(
        "apache2"
        "apache2-utils"
        "libapache2-mod-fcgid"
        "php8.4"
        "php8.4-cli"
        "php8.4-common"
        "php8.4-curl"
        "php8.4-gd"
        "php8.4-json"
        "php8.4-mbstring"
        "php8.4-mysql"
        "php8.4-xml"
        "php8.4-zip"
        "php8.4-intl"
        "php8.4-bcmath"
        "php8.4-gmp"
        "php8.4-imagick"
        "php8.4-fpm"
        "libapache2-mod-php8.4"
    )
    
    # Install required packages
    if ! install_packages "${required_packages[@]}"; then
        log_error "Failed to install required packages"
        return 1
    fi
    
    # Enable required Apache modules
    log_info "Enabling required Apache modules..."
    local apache_modules=(
        "rewrite"
        "headers"
        "env"
        "dir"
        "mime"
        "setenvif"
        "socache_shmcb"
        "ssl"
        "proxy_fcgi"
        "proxy"
        "proxy_http"
        "proxy_wstunnel"
    )
    
    for module in "${apache_modules[@]}"; do
        if ! a2enmod -q "$module"; then
            log_warning "Failed to enable Apache module: $module"
        fi
    done
    
    # Enable HTTP/2 if available
    if a2enmod -q "http2" 2>/dev/null; then
        echo "Protocols h2 h2c http/1.1" > /etc/apache2/conf-available/http2.conf
        a2enconf http2 > /dev/null
    else
        log_warning "HTTP/2 module not available, continuing without it"
    fi
    
    # Enable PHP 8.4 FPM configuration
    a2enconf php8.4-fpm > /dev/null 2>&1 || true
    a2enmod proxy_fcgi setenvif > /dev/null
    
    # Disable any other PHP versions
    for phpver in 5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3; do
        if [ -f "/etc/php/${phpver}/fpm/php-fpm.conf" ]; then
            systemctl stop "php${phpver}-fpm" 2>/dev/null || true
            systemctl disable "php${phpver}-fpm" 2>/dev/null || true
        fi
    done
    
    # Restart services
    log_info "Restarting services..."
    systemctl enable php8.4-fpm > /dev/null 2>&1 || true
    systemctl restart php8.4-fpm || log_warning "Failed to restart PHP 8.4 FPM"
    
    if ! systemctl restart apache2; then
        log_error "Failed to restart Apache"
        return 1
    fi
    
    # Enable services to start on boot
    systemctl enable apache2 > /dev/null 2>&1 || true
    
    # Verify PHP version
    local php_version=$(php -v | grep -oP '^PHP \K[0-9]+\.[0-9]+' || echo "")
    if [[ "$php_version" != "8.4" ]]; then
        log_warning "PHP version is ${php_version}, but expected 8.4. Please check the installation."
    else
        log_success "PHP 8.4 is now the active version"
    fi
    
    log_success "Apache installation completed successfully"
    return 0
}

# Main function
main() {
    log_info "=== Starting Apache Installation ==="
    
    if ! install_apache; then
        log_error "Apache installation failed"
        return 1
    fi
    
    return 0
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    main
    exit $?
fi