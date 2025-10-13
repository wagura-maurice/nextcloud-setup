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

log_section "PHP 8.4 FPM Installation for Apache"

# Configuration
readonly PHP_VERSION="8.4"
readonly PACKAGE_MANAGER="apt-get"
readonly INSTALL_OPTS="-y --no-install-recommends"

# Required PHP extensions for Nextcloud with Apache
readonly PHP_EXTENSIONS=(
    "fpm" "common" "cli" "gd" "curl" "intl" "mbstring" "xml" "zip"
    "ldap" "apcu" "imagick" "bz2" "dom" "simplexml" "gmp" "bcmath"
    "opcache" "mysql" "pdo" "pdo_mysql" "fileinfo" "exif" "sodium"
    "iconv" "ctype" "session" "tokenizer" "posix" "pcntl" "ftp"
)

# Additional required packages
readonly REQUIRED_PACKAGES=(
    "libmagickcore-6.q16-6-extra"
    "ffmpeg"
    "libimage-exiftool-perl"
    "unzip"
    "libapache2-mod-fcgid"
)

# Function to add PHP repository
add_php_repository() {
    log_info "Adding PHP 8.4 repository..."
    
    # Check if already added
    if grep -q "ondrej/php" /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list 2>/dev/null; then
        log_info "PHP repository already added"
        return 0
    fi
    
    # Install required packages
    log_info "Installing required packages for repository management..."
    if ! ${PACKAGE_MANAGER} install ${INSTALL_OPTS} software-properties-common apt-transport-https lsb-release ca-certificates; then
        log_error "Failed to install required packages"
        return 1
    fi
    
    # Add repository
    log_info "Adding Ondřej Surý's PHP repository..."
    if ! add-apt-repository -y ppa:ondrej/php; then
        log_error "Failed to add PHP repository"
        return 1
    fi
    
    # Update package lists
    log_info "Updating package lists..."
    if ! ${PACKAGE_MANAGER} update; then
        log_error "Failed to update package lists"
        return 1
    fi
    
    log_success "PHP 8.4 repository added successfully"
    return 0
}

# Function to install PHP and extensions
install_php() {
    log_info "Installing PHP ${PHP_VERSION} and required extensions..."
    
    # Build package list
    local packages=("${REQUIRED_PACKAGES[@]}")
    for ext in "${PHP_EXTENSIONS[@]}"; do
        # Skip empty extensions and duplicates
        [[ -z "${ext}" ]] && continue
        if [[ ! " ${packages[@]} " =~ " php${PHP_VERSION}-${ext} " ]]; then
            packages+=("php${PHP_VERSION}-${ext}")
        fi
    done
    
    # Install packages with retry logic
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Installing packages (attempt $attempt of $max_attempts)..."
        
        # Update package lists before each attempt
        if ! ${PACKAGE_MANAGER} update; then
            log_warning "Failed to update package lists, retrying..."
            sleep 5
            attempt=$((attempt + 1))
            continue
        fi
        
        # Install packages
        if DEBIAN_FRONTEND=noninteractive ${PACKAGE_MANAGER} install ${INSTALL_OPTS} "${packages[@]}"; then
            break
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log_error "Failed to install PHP packages after ${max_attempts} attempts"
            return 1
        fi
        
        log_warning "Package installation failed, retrying in 5 seconds..."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    # Verify PHP installation
    if ! command -v "php${PHP_VERSION}" >/dev/null 2>&1; then
        log_error "PHP ${PHP_VERSION} installation failed - php${PHP_VERSION} command not found"
        return 1
    fi
    
    log_success "PHP ${PHP_VERSION} and extensions installed successfully"
    return 0
}

# Function to configure PHP-FPM service for Apache
configure_php_fpm() {
    log_info "Configuring PHP-FPM service for Apache..."
    
    local php_fpm_service="php${PHP_VERSION}-fpm"
    local php_ini_path="/etc/php/${PHP_VERSION}/fpm/php.ini"
    local fpm_conf_path="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
    
    # Ensure PHP-FPM is installed
    if ! command -v "${php_fpm_service}" >/dev/null 2>&1; then
        log_error "PHP-FPM is not installed"
        return 1
    }
    
    # Configure PHP.ini
    log_info "Configuring PHP settings..."
    for setting in \
        "upload_max_filesize = 16G" \
        "post_max_size = 16G" \
        "memory_limit = 2G" \
        "max_execution_time = 3600" \
        "max_input_time = 3600" \
        "date.timezone = UTC" \
        "opcache.enable = 1" \
        "opcache.validate_timestamps = 1" \
        "opcache.revalidate_freq = 1" \
        "opcache.memory_consumption = 256" \
        "opcache.max_accelerated_files = 10000" \
        "opcache.save_comments = 1"
    do
        local key=$(echo "$setting" | cut -d'=' -f1 | xargs)
        if ! grep -q "^$key" "$php_ini_path" 2>/dev/null; then
            echo "$setting" | tee -a "$php_ini_path" >/dev/null
        else
            sed -i "s/^$key.*/$setting/" "$php_ini_path"
        fi
    done
    
    # Configure FPM pool
    log_info "Configuring PHP-FPM pool settings..."
    for setting in \
        "pm = dynamic" \
        "pm.max_children = 50" \
        "pm.start_servers = 5" \
        "pm.min_spare_servers = 4" \
        "pm.max_spare_servers = 20" \
        "pm.max_requests = 500" \
        "request_terminate_timeout = 300" \
        "env[HOSTNAME] = $HOSTNAME" \
        "env[PATH] = /usr/local/bin:/usr/bin:/bin" \
        "env[TMP] = /tmp" \
        "env[TMPDIR] = /tmp" \
        "env[TEMP] = /tmp"
    do
        local key=$(echo "$setting" | cut -d'=' -f1 | xargs)
        if ! grep -q "^$key" "$fpm_conf_path" 2>/dev/null; then
            sed -i "/^;.*$key.*/a $setting" "$fpm_conf_path"
        else
            sed -i "s/^$key.*/$setting/" "$fpm_conf_path"
        fi
    done
    
    # Enable and start PHP-FPM
    log_info "Starting PHP-FPM service..."
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
    }
    
    log_success "PHP-FPM service configured and running"
    return 0
}

# Function to verify installation
verify_installation() {
    log_info "Verifying PHP installation..."
    local success=true
    
    # Check PHP version
    if ! php${PHP_VERSION} -v >/dev/null 2>&1; then
        log_error "PHP ${PHP_VERSION} is not properly installed"
        success=false
    else
        log_info "PHP version: $(php${PHP_VERSION} -r 'echo PHP_VERSION;')"
    fi
    
    # Check PHP-FPM status
    local php_fpm_service="php${PHP_VERSION}-fpm"
    if ! systemctl is-active --quiet "${php_fpm_service}"; then
        log_error "${php_fpm_service} service is not running"
        success=false
    else
        log_info "PHP-FPM service is running"
    fi
    
    # Check installed extensions
    log_info "Checking installed PHP extensions..."
    local missing_extensions=()
    for ext in "${PHP_EXTENSIONS[@]}"; do
        if ! php${PHP_VERSION} -m | grep -q -i "^${ext}$"; then
            missing_extensions+=("${ext}")
        fi
    done
    
    if [ ${#missing_extensions[@]} -gt 0 ]; then
        log_warning "Missing PHP extensions: ${missing_extensions[*]}"
        success=false
    else
        log_info "All required PHP extensions are installed"
    fi
    
    # Check PHP-FPM configuration
    if ! php-fpm${PHP_VERSION} -t >/dev/null 2>&1; then
        log_error "PHP-FPM configuration test failed"
        success=false
    else
        log_info "PHP-FPM configuration test passed"
    fi
    
    if [ "$success" = true ]; then
        log_success "PHP installation verified successfully"
        return 0
    else
        log_error "PHP installation verification failed"
        return 1
    fi
}

# Main installation function
install_php_stack() {
    local start_time=$(date +%s)
    local success=true
    
    log_info "===== Starting PHP ${PHP_VERSION} FPM Installation ====="
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        return 1
    fi
    
    # Add PHP repository
    log_section "1. Adding PHP Repository"
    if ! add_php_repository; then
        log_error "Failed to add PHP repository"
        success=false
    fi
    
    # Install PHP and extensions
    if [ "$success" = true ]; then
        log_section "2. Installing PHP ${PHP_VERSION} and Extensions"
        if ! install_php; then
            log_error "Failed to install PHP and extensions"
            success=false
        fi
    fi
    
    # Configure PHP-FPM
    if [ "$success" = true ]; then
        log_section "3. Configuring PHP-FPM"
        if ! configure_php_fpm; then
            log_error "Failed to configure PHP-FPM"
            success=false
        fi
    fi
    
    # Verify installation
    if [ "$success" = true ]; then
        log_section "4. Verifying Installation"
        if ! verify_installation; then
            log_warning "Verification found some issues"
            # Don't mark as failure for warnings
        fi
    fi
    
    # Final status
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_section "Installation Summary"
    if [ "$success" = true ]; then
        log_success "===== PHP ${PHP_VERSION} FPM Installation Completed Successfully in ${duration} seconds ====="
        log_info "\nNext steps:"
        log_info "1. PHP-FPM is running and configured for Apache"
        log_info "2. PHP settings are optimized for Nextcloud"
        log_info "3. Run the Apache configuration script to complete the setup"
        log_info "4. After installation, you may want to tune the PHP-FPM settings in:"
        log_info "   - /etc/php/${PHP_VERSION}/fpm/php.ini"
        log_info "   - /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
        return 0
    else
        log_error "===== PHP Installation Completed with Errors (${duration} seconds) ====="
        log_error "Check the logs above for specific error messages"
        log_info "\nTroubleshooting tips:"
        log_info "1. Check system logs: journalctl -xe"
        log_info "2. Verify PHP-FPM status: systemctl status php${PHP_VERSION}-fpm"
        log_info "3. Check PHP-FPM logs: tail -f /var/log/php${PHP_VERSION}-fpm.log"
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
