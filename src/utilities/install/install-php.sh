#!/bin/bash
set -euo pipefail

# Load core configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/core/config-manager.sh"
source "${SCRIPT_DIR}/core/env-loader.sh"
source "${SCRIPT_DIR}/core/logging.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "PHP Installation"

# Default configuration values
readonly DEFAULT_PHP_VERSION="8.4"
readonly PACKAGE_MANAGER="apt-get"
readonly INSTALL_OPTS="-y --no-install-recommends"

# Load configuration
readonly PHP_VERSION=$(get_config "PHP_VERSION" "${DEFAULT_PHP_VERSION}")

# Required PHP extensions
readonly PHP_EXTENSIONS=(
    "fpm" "common" "cli" "gd" "curl" "intl" "mbstring" "xml" "zip"
    "json" "ldap" "apcu" "redis" "imagick" "bz2" "dom" "simplexml"
    "gmp" "bcmath" "opcache" "mysql" "pgsql" "sqlite3" "pdo" "pdo_mysql"
    "pdo_pgsql" "pdo_sqlite" "fileinfo" "exif" "sodium" "zip" "iconv"
)

# Additional required packages
readonly REQUIRED_PACKAGES=(
    "libapache2-mod-fcgid"
    "libmagickcore-6.q16-6-extra"
    "ffmpeg"
    "libimage-exiftool-perl"
    "unzip"
)

# Function to add PHP repository
add_php_repository() {
    log_info "Adding PHP repository..."
    
    # Check if already added
    if grep -q "ondrej/php" /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list 2>/dev/null; then
        log_info "PHP repository already added"
        return 0
    fi
    
    # Install required packages
    if ! ${PACKAGE_MANAGER} install ${INSTALL_OPTS} software-properties-common; then
        log_error "Failed to install required packages"
        return 1
    fi
    
    # Add repository
    if ! add-apt-repository -y ppa:ondrej/php; then
        log_error "Failed to add PHP repository"
        return 1
    fi
    
    # Update package lists
    if ! ${PACKAGE_MANAGER} update; then
        log_error "Failed to update package lists"
        return 1
    fi
    
    log_info "PHP repository added successfully"
    return 0
}

# Function to install PHP and extensions
install_php() {
    log_info "Installing PHP ${PHP_VERSION} and extensions..."
    
    # Build package list
    local packages=("${REQUIRED_PACKAGES[@]}")
    for ext in "${PHP_EXTENSIONS[@]}"; do
        packages+=("php${PHP_VERSION}-${ext}")
    done
    
    # Install packages
    if ! ${PACKAGE_MANAGER} install ${INSTALL_OPTS} "${packages[@]}"; then
        log_error "Failed to install PHP packages"
        return 1
    fi
    
    # Verify PHP installation
    if ! command -v "php${PHP_VERSION}" >/dev/null 2>&1; then
        log_error "PHP ${PHP_VERSION} installation failed"
        return 1
    fi
    
    log_info "PHP ${PHP_VERSION} and extensions installed successfully"
    return 0
}

# Function to configure PHP-FPM service
configure_php_fpm() {
    log_info "Configuring PHP-FPM service..."
    
    local php_fpm_service="php${PHP_VERSION}-fpm"
    
    # Enable and start PHP-FPM
    if ! systemctl is-active --quiet "${php_fpm_service}"; then
        if ! systemctl enable --now "${php_fpm_service}"; then
            log_error "Failed to enable ${php_fpm_service} service"
            return 1
        fi
    fi
    
    # Verify service status
    if ! systemctl is-active --quiet "${php_fpm_service}"; then
        log_error "${php_fpm_service} service is not running"
        return 1
    fi
    
    log_info "PHP-FPM service configured successfully"
    return 0
}

# Function to verify installation
verify_installation() {
    log_info "Verifying PHP installation..."
    
    # Check PHP version
    if ! php${PHP_VERSION} -v >/dev/null 2>&1; then
        log_error "PHP ${PHP_VERSION} is not properly installed"
        return 1
    fi
    
    # Check PHP-FPM status
    local php_fpm_service="php${PHP_VERSION}-fpm"
    if ! systemctl is-active --quiet "${php_fpm_service}"; then
        log_error "${php_fpm_service} service is not running"
        return 1
    fi
    
    # Check installed extensions
    local missing_extensions=()
    for ext in "${PHP_EXTENSIONS[@]}"; do
        if ! php${PHP_VERSION} -m | grep -q -i "^${ext}$"; then
            missing_extensions+=("${ext}")
        fi
    done
    
    if [ ${#missing_extensions[@]} -gt 0 ]; then
        log_warning "Missing PHP extensions: ${missing_extensions[*]}"
        return 1
    fi
    
    log_info "PHP installation verified successfully"
    return 0
}

# Main installation function
install_php_stack() {
    local success=true
    
    log_info "Starting PHP ${PHP_VERSION} installation..."
    
    # Add PHP repository
    if ! add_php_repository; then
        success=false
    fi
    
    # Install PHP and extensions
    if ! install_php; then
        success=false
    fi
    
    # Configure PHP-FPM
    if ! configure_php_fpm; then
        success=false
    fi
    
    # Verify installation
    if ! verify_installation; then
        success=false
    fi
    
    # Final status
    if [ "${success}" = true ]; then
        log_success "PHP ${PHP_VERSION} installation completed successfully"
        log_info "Run the configuration script to optimize PHP for Nextcloud:"
        log_info "  ./src/utilities/configure/configure-php.sh"
        return 0
    else
        log_error "PHP installation completed with errors"
        return 1
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    install_php_stack
    exit $?
fi
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
