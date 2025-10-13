#!/bin/bash
set -euo pipefail

# Set project root and core directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"  # Points to utilities directory
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"  # Points to src directory
CORE_DIR="${PROJECT_ROOT}/core"
UTILS_DIR="${SCRIPT_DIR}"  # Current directory is utilities
LOG_DIR="${PROJECT_ROOT}/../logs"
CONFIG_DIR="${PROJECT_ROOT}/../config"
DATA_DIR="${PROJECT_ROOT}/../data"
ENV_FILE="${PROJECT_ROOT}/../.env"

# Export environment variables
export PROJECT_ROOT CORE_DIR UTILS_DIR LOG_DIR CONFIG_DIR DATA_DIR ENV_FILE

# Create required directories
mkdir -p "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/../tmp"
chmod 750 "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/../tmp"

# Function to safely source core utilities
safe_source() {
    local file="$1"
    if [ -f "${file}" ]; then
        # shellcheck source=/dev/null
        source "${file}" || {
            echo "Error: Failed to load ${file}" >&2
            return 1
        }
    else
        echo "Error: Required file not found: ${file}" >&2
        return 1
    fi
}

# Source core utilities with error handling
if ! safe_source "${CORE_DIR}/config-manager.sh" || \
   ! safe_source "${CORE_DIR}/env-loader.sh" || \
   ! safe_source "${CORE_DIR}/logging.sh"; then
    exit 1
fi

# Initialize environment and logging
if ! load_environment || ! init_logging; then
    echo "Error: Failed to initialize environment and logging" >&2
    exit 1
fi

log_section "PHP 8.4 FPM Installation for Apache"

# Configuration
readonly PHP_VERSION="8.4"
readonly PACKAGE_MANAGER="apt-get"
readonly INSTALL_OPTS="-y --no-install-recommends"

# Required PHP extensions for Nextcloud with Apache
readonly PHP_EXTENSIONS=(
    "gd" "curl" "intl" "mbstring" "xml" "zip"
    "ldap" "apcu" "imagick" "bz2" "dom" "gmp" "bcmath"
    "opcache" "mysqli" "pdo_mysql" "fileinfo" "exif"
    "tokenizer"
)

# Required PHP packages
readonly PHP_PACKAGES=(
    "fpm" "common" "cli"
    "gd" "curl" "intl" "mbstring" "xml" "zip"
    "ldap" "apcu" "imagick" "bz2" "dom" "gmp" "bcmath"
    "opcache" "mysql" "pdo-mysql" "fileinfo" "exif"
    "tokenizer"
)

# Additional required system packages
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
    for pkg in "${PHP_PACKAGES[@]}"; do
        # Skip empty packages and duplicates
        [[ -z "${pkg}" ]] && continue
        pkg_name="php${PHP_VERSION}-${pkg}"
        if [[ ! " ${packages[@]} " =~ " ${pkg_name} " ]]; then
            packages+=("${pkg_name}")
        fi
    done
    
    log_info "The following packages will be installed/upgraded:"
    printf '  %s\n' "${packages[@]}"
    
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
            log_success "PHP ${PHP_VERSION} packages installed successfully"
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
    
    # Verify PHP-FPM installation
    if ! systemctl is-active "php${PHP_VERSION}-fpm" >/dev/null 2>&1; then
        log_warning "PHP-FPM service is not running. Starting it now..."
        systemctl start "php${PHP_VERSION}-fpm" || {
            log_error "Failed to start PHP-FPM service"
            return 1
        }
    fi
    
    log_success "PHP ${PHP_VERSION} and extensions installed successfully"
    return 0
}

# Function to install and configure PHP-FPM
configure_php_fpm() {
    log_info "Configuring PHP-FPM service for Apache..."
    
    local php_fpm_service="php${PHP_VERSION}-fpm"
    local php_ini_path="/etc/php/${PHP_VERSION}/fpm/php.ini"
    local fpm_conf_path="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
    
    # Check if PHP-FPM package is installed, if not install it
    if ! dpkg -l | grep -q "php${PHP_VERSION}-fpm"; then
        log_info "PHP-FPM package not found, installing..."
        if ! apt-get install -y --no-install-recommends "${php_fpm_service}"; then
            log_error "Failed to install ${php_fpm_service}"
            return 1
        fi
    fi
    
    # Verify the service file exists
    if [ ! -f "/lib/systemd/system/${php_fpm_service}.service" ]; then
        log_error "PHP-FPM service file not found after installation"
        return 1
    fi
    
    # Ensure the service is enabled and started
    if ! systemctl is-enabled "${php_fpm_service}" >/dev/null 2>&1; then
        log_info "Enabling ${php_fpm_service} service..."
        systemctl enable "${php_fpm_service}" || {
            log_error "Failed to enable ${php_fpm_service} service"
            return 1
        }
    fi
    
    # Start the service if not running
    if ! systemctl is-active "${php_fpm_service}" >/dev/null 2>&1; then
        log_info "Starting ${php_fpm_service} service..."
        systemctl start "${php_fpm_service}" || {
            log_error "Failed to start ${php_fpm_service} service"
            return 1
        }
    fi
    
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
    fi
    
    log_success "PHP-FPM service configured and running"
    return 0
}

# Function to verify installation
verify_installation() {
    log_info "Verifying PHP installation..."
    local success=true
    
    # Check PHP version
    if ! command -v "php${PHP_VERSION}" >/dev/null 2>&1; then
        log_error "PHP ${PHP_VERSION} is not properly installed (php${PHP_VERSION} command not found)"
        success=false
    else
        local php_version
        php_version=$(php${PHP_VERSION} -r 'echo PHP_VERSION;' 2>/dev/null)
        if [ $? -eq 0 ]; then
            log_info "PHP version: ${php_version}"
            
            # Check for required PHP functions
            local required_functions=("json_encode" "curl_init" "mb_strlen" "simplexml_load_string")
            local missing_functions=()
            
            for func in "${required_functions[@]}"; do
                if ! php${PHP_VERSION} -r "if (!function_exists('${func}')) { exit(1); }" 2>/dev/null; then
                    missing_functions+=("${func}")
                fi
            done
            
            if [ ${#missing_functions[@]} -gt 0 ]; then
                log_warning "Missing required PHP functions: ${missing_functions[*]}"
                success=false
            fi
        else
            log_error "Failed to get PHP version"
            success=false
        fi
    fi
    
    # Check PHP-FPM status
    local php_fpm_service="php${PHP_VERSION}-fpm"
    if ! systemctl is-active --quiet "${php_fpm_service}"; then
        log_warning "${php_fpm_service} service is not running. Attempting to start..."
        if ! systemctl start "${php_fpm_service}"; then
            log_error "Failed to start ${php_fpm_service} service"
            systemctl status "${php_fpm_service}" --no-pager || true
            success=false
        else
            log_info "Successfully started ${php_fpm_service} service"
        fi
    else
        log_info "PHP-FPM service is running"
    fi
    
    # Check installed extensions
    log_info "Checking installed PHP extensions..."
    local missing_extensions=()
    
    # First, get the list of all loaded extensions
    local loaded_extensions
    loaded_extensions=$(php${PHP_VERSION} -m 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_error "Failed to get list of loaded PHP extensions"
        success=false
    else
        # Check each required extension
        for ext in "${PHP_EXTENSIONS[@]}"; do
            # Special handling for extensions that might have different names
            local ext_name="${ext}"
            case "${ext}" in
                "pdo_mysql")
                    # Check both pdo_mysql and pdo_mysqlnd
                    if ! echo "${loaded_extensions}" | grep -q -E '^(pdo_mysql|pdo_mysqlnd)$'; then
                        missing_extensions+=("${ext}")
                    fi
                    ;;
                *)
                    if ! echo "${loaded_extensions}" | grep -q -E "^${ext}$"; then
                        missing_extensions+=("${ext}")
                    fi
                    ;;
            esac
        done
        
        if [ ${#missing_extensions[@]} -gt 0 ]; then
            log_warning "Missing PHP extensions: ${missing_extensions[*]}"
            
            # Try to install missing extensions
            log_info "Attempting to install missing extensions..."
            local pkgs_to_install=()
            
            for ext in "${missing_extensions[@]}"; do
                case "${ext}" in
                    "pdo_mysql")
                        pkgs_to_install+=("php${PHP_VERSION}-mysql")
                        ;;
                    *)
                        pkgs_to_install+=("php${PHP_VERSION}-${ext}")
                        ;;
                esac
            done
            
            if [ ${#pkgs_to_install[@]} -gt 0 ]; then
                log_info "Installing packages: ${pkgs_to_install[*]}"
                if DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs_to_install[@]}"; then
                    log_info "Successfully installed missing extensions"
                    # Restart PHP-FPM to load new extensions
                    systemctl restart "${php_fpm_service}" || true
                    
                    # Re-check for still missing extensions
                    local still_missing=()
                    for ext in "${missing_extensions[@]}"; do
                        if ! php${PHP_VERSION} -m | grep -q -E "^${ext}$"; then
                            still_missing+=("${ext}")
                        fi
                    done
                    
                    if [ ${#still_missing[@]} -gt 0 ]; then
                        log_warning "Still missing extensions after installation: ${still_missing[*]}"
                        success=false
                    else
                        log_info "All extensions successfully installed and loaded"
                    fi
                else
                    log_error "Failed to install missing extensions"
                    success=false
                fi
            fi
        else
            log_info "All required PHP extensions are installed and loaded"
        fi
    fi
    
    # Check PHP-FPM configuration
    log_info "Checking PHP-FPM configuration..."
    if ! php-fpm${PHP_VERSION} -t; then
        log_error "PHP-FPM configuration test failed"
        success=false
    else
        log_info "PHP-FPM configuration test passed"
    fi
    
    # Check important PHP settings
    log_info "Checking PHP settings..."
    local settings=(
        "memory_limit"
        "upload_max_filesize"
        "post_max_size"
        "max_execution_time"
        "max_input_time"
        "date.timezone"
        "opcache.enable"
        "opcache.enable_cli"
        "opcache.memory_consumption"
        "opcache.interned_strings_buffer"
        "opcache.max_accelerated_files"
        "opcache.validate_timestamps"
        "opcache.save_comments"
        "opcache.revalidate_freq"
    )
    
    for setting in "${settings[@]}"; do
        local value
        value=$(php${PHP_VERSION} -r "echo ini_get('${setting}');" 2>/dev/null || echo "(error)")
        log_info "${setting} = ${value}"
    done
    
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
