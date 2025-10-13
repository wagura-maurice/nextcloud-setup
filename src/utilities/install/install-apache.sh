#!/bin/bash
set -euo pipefail

# Set project root and core directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CORE_DIR="${PROJECT_ROOT}/core"
SRC_DIR="${PROJECT_ROOT}"
UTILS_DIR="${SRC_DIR}/utilities"
LOG_DIR="${PROJECT_ROOT}/logs"
CONFIG_DIR="${PROJECT_ROOT}/config"
DATA_DIR="${PROJECT_ROOT}/data"
ENV_FILE="${PROJECT_ROOT}/.env"

# Export environment variables
export PROJECT_ROOT CORE_DIR SRC_DIR UTILS_DIR LOG_DIR CONFIG_DIR DATA_DIR ENV_FILE

# Create required directories
mkdir -p "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/tmp"
chmod 750 "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/tmp"

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

# Function to install PHP using the dedicated script
install_php() {
    log_info "Installing PHP using the dedicated script..."
    
    local php_script="${UTILS_DIR}/install/install-php.sh"
    
    if [ -f "$php_script" ]; then
        if ! bash "$php_script"; then
            log_error "Failed to install PHP"
            return 1
        fi
    else
        log_error "PHP installation script not found at $php_script"
        return 1
    fi
    
    return 0
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
    
    # Install PHP first
    if ! install_php; then
        log_error "Failed to install PHP"
        return 1
    fi
    
    # Required Apache packages
    local required_packages=(
        "apache2"
        "apache2-utils"
        "libapache2-mod-fcgid"
    )
    
    # Install required Apache packages
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${required_packages[@]}"; then
        log_error "Failed to install required Apache packages"
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
    
    # Restart Apache
    log_info "Restarting Apache..."
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