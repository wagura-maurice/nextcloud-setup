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
    
    # Required packages
    local required_packages=(
        "apache2"
        "apache2-utils"
        "libapache2-mod-php"
        "php"
        "php-cli"
        "php-common"
        "php-curl"
        "php-gd"
        "php-json"
        "php-mbstring"
        "php-mysql"
        "php-xml"
        "php-zip"
        "php-intl"
        "php-bcmath"
        "php-gmp"
        "php-imagick"
        "libapache2-mod-fcgid"
        "php-fpm"
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
    
    # Enable required configurations
    a2enconf php*-fpm > /dev/null 2>&1 || true
    a2enmod proxy_fcgi setenvif > /dev/null
    
    # Restart Apache
    log_info "Restarting Apache service..."
    if ! systemctl restart apache2; then
        log_error "Failed to restart Apache"
        return 1
    fi
    
    # Enable Apache to start on boot
    systemctl enable apache2 > /dev/null 2>&1 || true
    
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