#!/bin/bash
set -euo pipefail

# Set project root and core directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"  # Points to utilities directory
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"  # Points to src directory
CORE_DIR="${PROJECT_ROOT}/core"
UTILS_DIR="${SCRIPT_DIR}"  # Current directory is utilities
LOG_DIR="/root/nextcloud-setup/src/logs"  # Explicit log directory
CONFIG_DIR="${PROJECT_ROOT}/../config"
DATA_DIR="${PROJECT_ROOT}/../data"
ENV_FILE="${PROJECT_ROOT}/../.env"

# Ensure required directories exist before any logging or sourcing
for dir in "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/../tmp"; do
    mkdir -p "${dir}" || {
        echo "Failed to create directory: ${dir}" >&2
        exit 1
    }
    chmod 750 "${dir}"
done

export LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d).log"

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

# Function to apply recommended PHP settings
apply_php_settings() {
    local php_ini_path="/etc/php/${PHP_VERSION}/fpm/php.ini"
    local php_fpm_conf="/etc/php/${PHP_VERSION}/fpm/php-fpm.conf"
    local nextcloud_ini="/etc/php/${PHP_VERSION}/fpm/conf.d/99-nextcloud.ini"
    
    log_info "🔧 Applying recommended PHP settings..."
    
    # Create a backup of the original php.ini
    if [ ! -f "${php_ini_path}.original" ]; then
        cp "${php_ini_path}" "${php_ini_path}.original"
    fi
    
    # Ensure the configuration directory exists and has correct permissions
    mkdir -p "$(dirname "${nextcloud_ini}")"
    
    # Remove any existing nextcloud config files to prevent conflicts
    for f in "/etc/php/${PHP_VERSION}/fpm/conf.d/"*nextcloud*.ini; do
        if [ -f "$f" ]; then
            log_info "Removing existing PHP config: $f"
            rm -f "$f"
        fi
    done

    # Always remove before creating
    if [ -f "${nextcloud_ini}" ]; then
        rm -f "${nextcloud_ini}"
    fi

    # Create a new configuration file with all settings
    cat > "${nextcloud_ini}" << 'EOF'
; Nextcloud recommended PHP settings
; This file is auto-generated - do not edit manually

[PHP]
; Resource limits
memory_limit = 2G
upload_max_filesize = 10G
post_max_size = 10G
max_execution_time = 3600
max_input_time = 1000

; Timezone
date.timezone = UTC

; Security settings
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_multi_exec,parse_ini_file,show_source
expose_php = Off

; Performance settings
realpath_cache_size = 512k
realpath_cache_ttl = 3600
max_input_vars = 2000

; OPcache settings
[opcache]
opcache.enable = 1
opcache.enable_cli = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.validate_timestamps = 1
opcache.save_comments = 1
opcache.revalidate_freq = 1
opcache.fast_shutdown = 1

; Session settings
[session]
session.auto_start = 0
session.gc_maxlifetime = 3600
session.cookie_lifetime = 0
session.cookie_httponly = 1
session.cookie_secure = 1
session.use_strict_mode = 1
session.cookie_samesite = Lax

; Other settings
default_socket_timeout = 60

[Pcre]
pcre.jit = 1
pcre.backtrack_limit = 1000000
pcre.recursion_limit = 100000

; Database settings
[MySQL]
mysql.connect_timeout = 60
mysqli.reconnect = Off

; File handling
file_uploads = On
output_buffering = Off

default_charset = "UTF-8"
EOF

    # Set correct permissions
    chmod 644 "${nextcloud_ini}"
    log_info "✅ Created ${nextcloud_ini}"
    
    # Ensure CLI version has the same settings
    local cli_ini_path="/etc/php/${PHP_VERSION}/cli/php.ini"
    if [ -f "${cli_ini_path}" ]; then
        log_info "🔧 Updating CLI PHP configuration..."
        if [ ! -f "${cli_ini_path}.original" ]; then
            cp "${cli_ini_path}" "${cli_ini_path}.original"
        fi
        # Create CLI-specific config
        local cli_conf_dir="/etc/php/${PHP_VERSION}/cli/conf.d"
        mkdir -p "${cli_conf_dir}"
        cat >| "${cli_conf_dir}/99-nextcloud.ini" << 'EOF'
; Nextcloud recommended PHP settings for CLI
memory_limit = 2G
upload_max_filesize = 10G
post_max_size = 10G
max_execution_time = 3600
max_input_time = 1000
date.timezone = UTC
opcache.enable_cli = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.validate_timestamps = 1
opcache.save_comments = 1
max_input_vars = 2000
EOF
        chmod 644 "${cli_conf_dir}/99-nextcloud.ini"
    fi
    
    # Ensure PHP-FPM configuration is properly set
    if [ -f "${php_fpm_conf}" ]; then
        log_info "🔧 Configuring PHP-FPM..."
        
        if [ ! -f "${php_fpm_conf}.original" ]; then
            cp "${php_fpm_conf}" "${php_fpm_conf}.original"
        fi
        
        # Set FPM settings with proper sed patterns
        declare -A fpm_settings=(
            ["emergency_restart_threshold"]="10"
            ["emergency_restart_interval"]="1m"
            ["process_control_timeout"]="10s"
            ["log_level"]="notice"
            ["log_limit"]="4096"
            ["decorate_workers_output"]="no"
        )
        
        for setting in "${!fpm_settings[@]}"; do
            local value="${fpm_settings[$setting]}"
            
            # Use a more robust sed pattern
            if grep -q "^;*\s*${setting}\s*=" "${php_fpm_conf}"; then
                sed -i "s/^;*\s*${setting}\s*=.*$/${setting} = ${value}/" "${php_fpm_conf}"
            else
                echo "${setting} = ${value}" >> "${php_fpm_conf}"
            fi
            log_info "✅ Set ${setting} = ${value}"
        done
        
        # Validate the configuration before applying
        if php-fpm${PHP_VERSION} -t > /dev/null 2>&1; then
            log_success "✅ PHP-FPM configuration validated"
            
            # Restart PHP-FPM to apply changes
            log_info "🔄 Restarting PHP-FPM service..."
            if systemctl restart "php${PHP_VERSION}-fpm"; then
                log_success "✅ PHP-FPM restarted successfully"
                sleep 2  # Give FPM time to fully restart
            else
                log_error "❌ Failed to restart PHP-FPM"
                journalctl -u "php${PHP_VERSION}-fpm" -n 20 --no-pager
                return 1
            fi
        else
            log_error "❌ Invalid PHP-FPM configuration"
            php-fpm${PHP_VERSION} -t
            return 1
        fi
    else
        log_warning "⚠️ PHP-FPM configuration file not found at ${php_fpm_conf}"
    fi
    
    log_success "✅ PHP settings applied successfully"
    return 0
}

# Function to install and configure PHP-FPM
configure_php_fpm() {
    log_info "Configuring PHP-FPM service for Apache..."
    
    local php_fpm_service="php${PHP_VERSION}-fpm"
    local php_ini_path="/etc/php/${PHP_VERSION}/fpm/php.ini"
    local fpm_conf_path="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
    local log_dir="/var/log/php${PHP_VERSION}-fpm"
    
    # Create and set permissions for log directory
    if ! mkdir -p "$log_dir"; then
        log_error "Failed to create log directory: $log_dir"
        return 1
    fi
    
    if ! chown -R www-data:www-data "$log_dir"; then
        log_warning "Failed to change ownership of $log_dir to www-data"
    fi
    
    if ! chmod 755 "$log_dir"; then
        log_warning "Failed to set permissions for $log_dir"
    fi
    
    # Create log files with proper permissions
    for logfile in "error.log" "www-error.log" "slow.log" "access.log"; do
        log_path="$log_dir/$logfile"
        if ! touch "$log_path"; then
            log_error "Failed to create log file: $log_path"
            return 1
        fi
        
        if ! chown www-data:www-data "$log_path"; then
            log_warning "Failed to change ownership of $log_path to www-data"
        fi
        
        if ! chmod 644 "$log_path"; then
            log_warning "Failed to set permissions for $log_path"
        fi
    done
    
    # Check if PHP-FPM package is installed, if not install it
    if ! dpkg -l | grep -q "php${PHP_VERSION}-fpm"; then
        log_info "PHP-FPM package not found, installing..."
        if ! apt-get update; then
            log_error "Failed to update package lists"
            return 1
        fi
        
        if ! apt-get install -y --no-install-recommends "${php_fpm_service}"; then
            log_error "Failed to install ${php_fpm_service}"
            log_info "Trying to fix broken packages..."
            apt-get -f install -y || {
                log_error "Failed to fix broken packages"
                return 1
            }
            
            if ! apt-get install -y --no-install-recommends "${php_fpm_service}"; then
                log_error "Still failed to install ${php_fpm_service} after fixing packages"
                return 1
            fi
        fi
        
        log_success "Successfully installed ${php_fpm_service}"
    else
        log_info "${php_fpm_service} is already installed"
    fi
    
    # Verify the service file exists
    local service_file="/lib/systemd/system/${php_fpm_service}.service"
    if [ ! -f "$service_file" ]; then
        log_error "PHP-FPM service file not found: $service_file"
        log_info "Trying to find the service file in other locations..."
        
        # Try alternative locations
        service_file=$(find /etc -name "${php_fpm_service}.service" 2>/dev/null | head -1)
        
        if [ -z "$service_file" ]; then
            log_error "Could not find ${php_fpm_service}.service in any standard location"
            log_info "Attempting to reinstall the package..."
            
            if ! apt-get install --reinstall -y "${php_fpm_service}"; then
                log_error "Failed to reinstall ${php_fpm_service}"
                return 1
            fi
            
            if [ ! -f "/lib/systemd/system/${php_fpm_service}.service" ]; then
                log_error "Service file still not found after reinstallation"
                return 1
            fi
            service_file="/lib/systemd/system/${php_fpm_service}.service"
        fi
    fi
    
    log_info "Using service file: $service_file"
    
    # Ensure the service is enabled and started
    log_info "Managing ${php_fpm_service} service..."
    
    # Reload systemd to ensure it knows about the service
    if ! systemctl daemon-reload; then
        log_warning "Failed to reload systemd daemon, but continuing..."
    fi
    
    # Enable the service if not already enabled
    if ! systemctl is-enabled "${php_fpm_service}" >/dev/null 2>&1; then
        log_info "Enabling ${php_fpm_service} service..."
        if ! systemctl enable "${php_fpm_service}" --now; then
            log_error "Failed to enable ${php_fpm_service} service"
            log_info "Attempting to start the service anyway..."
        fi
    else
        log_info "${php_fpm_service} service is already enabled"
    fi
    
    # Check service status and start if not running
    if systemctl is-active "${php_fpm_service}" >/dev/null 2>&1; then
        log_info "${php_fpm_service} is already running"
    else
        log_info "Starting ${php_fpm_service} service..."
        if ! systemctl start "${php_fpm_service}"; then
            log_error "Failed to start ${php_fpm_service} service"
            log_info "Checking for configuration errors..."
            
            # Test the PHP-FPM configuration
            if command -v "php-fpm${PHP_VERSION}" >/dev/null 2>&1; then
                if ! "php-fpm${PHP_VERSION}" -t; then
                    log_error "PHP-FPM configuration test failed"
                fi
            fi
            
            # Show the last few lines of the error log
            log_info "Last 20 lines of PHP-FPM error log:"
            tail -n 20 "${log_dir}/error.log" 2>/dev/null || echo "No error log available"
            
            # Show the last few lines of the systemd journal
            log_info "Last 20 lines of systemd journal for ${php_fpm_service}:"
            journalctl -u "${php_fpm_service}" -n 20 --no-pager 2>/dev/null || echo "Could not retrieve journal entries"
            
            return 1
        fi
    fi
    
    # Configure PHP.ini
    log_info "Configuring PHP settings..."
    
    # Remove any existing nextcloud config files to prevent conflicts
    for f in "/etc/php/${PHP_VERSION}/fpm/conf.d/"*nextcloud*.ini; do
        if [ -f "$f" ]; then
            log_info "Removing existing PHP config: $f"
            rm -f "$f"
        fi
    done
    
    # Always remove before creating
    local nextcloud_ini="/etc/php/${PHP_VERSION}/fpm/conf.d/99-nextcloud.ini"
    if [ -f "${nextcloud_ini}" ]; then
        rm -f "${nextcloud_ini}"
    fi

    log_info "📝 Creating consolidated Nextcloud PHP configuration..."
    
    # Create new configuration file with proper permissions
    touch -f "${nextcloud_ini}"
    chmod 644 "${nextcloud_ini}"
    
    # Write the consolidated configuration
    cat > "${nextcloud_ini}" << 'EOF'
; Nextcloud recommended PHP settings
; This file is auto-generated - do not edit manually

; Resource limits
memory_limit = 2G
upload_max_filesize = 10G
post_max_size = 10G
max_execution_time = 3600
max_input_time = 1000

; Timezone
date.timezone = UTC

; OPcache settings
opcache.enable = 1
opcache.enable_cli = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.validate_timestamps = 1
opcache.save_comments = 1
opcache.revalidate_freq = 1
opcache.fast_shutdown = 1

; Session settings
session.auto_start = 0
session.gc_maxlifetime = 3600
session.cookie_lifetime = 0
session.cookie_httponly = 1
session.cookie_secure = 1
session.use_strict_mode = 1
session.cookie_samesite = Lax

; Other settings
default_socket_timeout = 60
pcre.jit = 1
pcre.backtrack_limit = 1000000
pcre.recursion_limit = 100000

; Database settings
mysql.connect_timeout = 60
mysqli.reconnect = Off

; Disable PHP output buffering
output_buffering = Off

; Disable expose_php for security
expose_php = Off

; Enable file uploads
file_uploads = On

; Set default charset
default_charset = "UTF-8"

[Zend]
zend.assertions = -1

[Core]
expose_php = Off
file_uploads = On
allow_url_fopen = On
allow_url_include = Off
default_charset = UTF-8

[mbstring]
mbstring.func_overload = 0
mbstring.internal_encoding = UTF-8
mbstring.encoding_translation = Off

[PHP]
output_buffering = 4096
short_open_tag = Off
variables_order = GPCS
request_order = GP
register_argc_argv = Off
auto_globals_jit = On
EOF

    # Set proper permissions
    chmod 644 "${nextcloud_ini}"
    
    # Also update the main php.ini with critical settings
    for setting in \
        "upload_max_filesize = 10G" \
        "post_max_size = 10G" \
        "memory_limit = 2G" \
        "max_execution_time = 3600" \
        "max_input_time = 1000" \
        "date.timezone = UTC"; do
        local key=${setting%%=*}
        key=${key// /}
        
        # Remove any existing setting
        sed -i "/^${key}/d" "${php_ini_path}"
        # Add the new setting
        echo "${setting}" | tee -a "${php_ini_path}" >/dev/null
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
    local php_ini_path="/etc/php/${PHP_VERSION}/fpm/php.ini"
    local nextcloud_ini="/etc/php/${PHP_VERSION}/fpm/conf.d/99-nextcloud.ini"
    
    # Check PHP command exists
    if ! command -v "php${PHP_VERSION}" >/dev/null 2>&1; then
        log_error "❌ PHP ${PHP_VERSION} is not properly installed (php${PHP_VERSION} command not found)"
        return 1
    fi
    
    # Check PHP version
    local php_version
    php_version=$(php${PHP_VERSION} -r 'echo PHP_VERSION;' 2>/dev/null)
    if [ $? -ne 0 ]; then
        log_error "❌ Failed to get PHP version"
        success=false
    else
        log_info "✅ PHP version: ${php_version}"
    fi
    
    # Check PHP-FPM service
    local php_fpm_service="php${PHP_VERSION}-fpm"
    if ! systemctl is-active --quiet "${php_fpm_service}"; then
        log_warning "⚠️  ${php_fpm_service} service is not running. Attempting to start..."
        if ! systemctl start "${php_fpm_service}"; then
            log_error "❌ Failed to start ${php_fpm_service} service"
            systemctl status "${php_fpm_service}" --no-pager || true
            success=false
        else
            log_info "✅ Successfully started ${php_fpm_service} service"
        fi
    else
        log_info "✅ PHP-FPM service is running"
    fi
    
    # Check configuration files
    log_info "\n🔍 Checking configuration files..."
    for config_file in "${php_ini_path}" "${nextcloud_ini}"; do
        if [ ! -f "${config_file}" ]; then
            log_error "❌ Configuration file not found: ${config_file}"
            success=false
        else
            log_info "✅ Found config file: ${config_file}"
        fi
    done
    
    # Check PHP settings
    log_info "\n🔧 Checking PHP settings..."
    declare -A required_settings=(
        ["memory_limit"]="2G"
        ["upload_max_filesize"]="10G"
        ["post_max_size"]="10G"
        ["max_execution_time"]="3600"
        ["max_input_time"]="1000"
        ["date.timezone"]="UTC"
        ["opcache.enable"]="1"
        ["opcache.enable_cli"]="1"
        ["opcache.memory_consumption"]="256"
        ["opcache.interned_strings_buffer"]="16"
        ["opcache.max_accelerated_files"]="10000"
        ["opcache.validate_timestamps"]="1"
        [opcache.save_comments]="1"
    )
    
    for setting in "${!required_settings[@]}"; do
        local expected_value="${required_settings[$setting]}"
        local actual_value
        
        # First try to get the value from PHP
        actual_value=$(php${PHP_VERSION} -r "echo ini_get('${setting}');" 2>/dev/null || echo "(error)")
        
        if [ "${actual_value}" = "(error)" ]; then
            log_warning "⚠️  Could not read setting: ${setting}"
            continue
        fi
        
        # Special handling for memory values (convert to bytes for comparison)
        if [[ "${setting}" =~ _size$|^memory_limit$ ]] && [ "${expected_value}" != "0" ] && [ "${expected_value}" != "-1" ]; then
            local expected_bytes
            local actual_bytes
            
            # Manual conversion of expected value
            local expected_upper=$(echo "${expected_value}" | tr '[:lower:]' '[:upper:]')
            case "${expected_upper}" in
                *G) expected_bytes=$(( ${expected_upper%G} * 1024 * 1024 * 1024 )) ;;
                *M) expected_bytes=$(( ${expected_upper%M} * 1024 * 1024 )) ;;
                *K) expected_bytes=$(( ${expected_upper%K} * 1024 )) ;;
                *) expected_bytes="${expected_upper}" ;;
            esac
            
            # Manual conversion of actual value
            local actual_upper=$(echo "${actual_value}" | tr '[:lower:]' '[:upper:]')
            case "${actual_upper}" in
                *G) actual_bytes=$(( ${actual_upper%G} * 1024 * 1024 * 1024 )) ;;
                *M) actual_bytes=$(( ${actual_upper%M} * 1024 * 1024 )) ;;
                *K) actual_bytes=$(( ${actual_upper%K} * 1024 )) ;;
                *) actual_bytes="${actual_upper}" ;;
            esac
            
            if [ -z "${expected_bytes}" ] || [ -z "${actual_bytes}" ]; then
                log_warning "⚠️  Could not compare values for ${setting}: expected=${expected_value}, actual=${actual_value}"
                continue
            fi
            
            if [ "${actual_bytes}" -lt "${expected_bytes}" ]; then
                log_error "❌ ${setting} is too low: ${actual_value} (should be at least ${expected_value})"
                success=false
            else
                log_info "✅ ${setting} = ${actual_value} (>= ${expected_value})"
            fi
        # Special handling for numeric time values (like max_execution_time, max_input_time)
        elif [[ "${setting}" == "max_execution_time" || "${setting}" == "max_input_time" ]]; then
            # Remove any non-numeric characters and compare as integers
            local actual_num=$(echo "${actual_value}" | tr -cd '0-9')
            local expected_num=$(echo "${expected_value}" | tr -cd '0-9')
            
            if [ -z "${actual_num}" ] || [ -z "${expected_num}" ]; then
                log_warning "⚠️  Could not compare numeric values for ${setting}: expected=${expected_value}, actual=${actual_value}"
                continue
            fi
            
            if [ "${actual_num}" -lt "${expected_num}" ]; then
                log_error "❌ ${setting} is too low: ${actual_value} (should be at least ${expected_value})"
                success=false
            else
                log_info "✅ ${setting} = ${actual_value} (>= ${expected_value})"
            fi
        else
            # Simple string comparison for non-size settings
            if [ "${actual_value}" != "${expected_value}" ]; then
                log_error "❌ ${setting} is incorrect: ${actual_value} (should be ${expected_value})"
                success=false
            else
                log_info "✅ ${setting} = ${actual_value}"
            fi
        fi
    done
    
    # Check required PHP extensions
    log_info "\n🔌 Checking PHP extensions..."
    local missing_extensions=()
    local loaded_extensions
    loaded_extensions=$(php${PHP_VERSION} -m 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_error "❌ Failed to get list of loaded PHP extensions"
        success=false
    else
        for ext in "${PHP_EXTENSIONS[@]}"; do
            # Special handling for extensions that might have different names
            case "${ext}" in
                "pdo_mysql")
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
            log_error "❌ Missing PHP extensions: ${missing_extensions[*]}"
            success=false
            
            # Try to install missing extensions
            log_info "\n🔄 Attempting to install missing extensions..."
            local pkgs_to_install=()
            
            for ext in "${missing_extensions[@]}"; do
                case "${ext}" in
                    "pdo_mysql") pkgs_to_install+=("php${PHP_VERSION}-mysql") ;;
                    "mysqli") pkgs_to_install+=("php${PHP_VERSION}-mysql") ;;
                    *) pkgs_to_install+=("php${PHP_VERSION}-${ext}") ;;
                esac
            done
            
            # Remove duplicates
            readarray -t pkgs_to_install < <(printf "%s\n" "${pkgs_to_install[@]}" | sort -u)
            
            if [ ${#pkgs_to_install[@]} -gt 0 ]; then
                log_info "📦 Installing packages: ${pkgs_to_install[*]}"
                if DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs_to_install[@]}"; then
                    log_info "✅ Successfully installed packages"
                    systemctl restart "${php_fpm_service}" || true
                    
                    # Re-check extensions after installation
                    local still_missing=()
                    for ext in "${missing_extensions[@]}"; do
                        if ! php${PHP_VERSION} -m | grep -q -E "^${ext}$"; then
                            still_missing+=("${ext}")
                        fi
                    done
                    
                    if [ ${#still_missing[@]} -gt 0 ]; then
                        log_error "❌ Still missing extensions: ${still_missing[*]}"
                        success=false
                    else
                        log_info "✅ All extensions successfully loaded"
                    fi
                else
                    log_error "❌ Failed to install packages"
                    success=false
                fi
            fi
        else
            log_info "✅ All required PHP extensions are installed"
        fi
    fi
    
    # Check PHP-FPM configuration
    log_info "\n🔧 Checking PHP-FPM configuration..."
    if ! php-fpm${PHP_VERSION} -t; then
        log_error "❌ PHP-FPM configuration test failed"
        success=false
    else
        log_info "✅ PHP-FPM configuration test passed"
    fi
    
    # Final status
    if [ "${success}" = true ]; then
        log_success "\n🎉 PHP installation verified successfully!"
        return 0
    else
        log_error "\n❌ PHP installation verification failed"
        log_info "\n💡 Check the following:"
        log_info "1. PHP-FPM service status: systemctl status ${php_fpm_service}"
        log_info "2. PHP-FPM error log: journalctl -u ${php_fpm_service} -n 50"
        log_info "3. PHP configuration files in /etc/php/${PHP_VERSION}/fpm/"
        log_info "4. Install missing extensions manually if needed"
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

        # Apply recommended PHP settings
        log_section "3.1. Applying Recommended PHP Settings"
        if ! apply_php_settings; then
            log_error "Failed to apply recommended PHP settings"
            success=false
        fi

        # Fix critical PHP settings before verification
        if [ "$success" = true ]; then
            log_section "3.2. Fixing Critical PHP Settings"
            fix_max_input_time
        fi

        # Only restart PHP-FPM if config is valid
        if [ "$success" = true ]; then
            log_info "🔄 Performing final restart of PHP-FPM to apply all configurations..."
            if php-fpm${PHP_VERSION} -t; then
                if systemctl restart "php${PHP_VERSION}-fpm"; then
                    log_success "✅ PHP-FPM restarted successfully after applying all settings"
                else
                    log_error "❌ Failed to restart PHP-FPM after applying settings. Showing logs..."
                    journalctl -u "php${PHP_VERSION}-fpm" -n 20 --no-pager
                    systemctl status "php${PHP_VERSION}-fpm" --no-pager
                    success=false
                fi
            else
                log_error "❌ PHP-FPM configuration test failed. Not restarting service."
                php-fpm${PHP_VERSION} -t
                success=false
            fi
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
    
    # Set max_input_time to at least 1000 in all relevant php.ini files (FPM, CLI, Apache2)
    local changed=0
    for ini in /etc/php/*/fpm/php.ini /etc/php/*/cli/php.ini /etc/php/*/apache2/php.ini; do
        if [ -f "$ini" ]; then
            # If set to -1 or missing, set to 1000
            if grep -q '^max_input_time\s*=' "$ini"; then
                if grep -q '^max_input_time\s*=\s*-1' "$ini"; then
                    sed -i 's/^max_input_time\s*=.*/max_input_time = 1000/' "$ini"
                    changed=1
                fi
            else
                echo "max_input_time = 1000" >> "$ini"
                changed=1
            fi
        fi
    done
    # Reload PHP-FPM if any changes were made
    if [ "$changed" -eq 1 ]; then
        systemctl reload "php${PHP_VERSION}-fpm" 2>/dev/null || true
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

# Function to ensure max_input_time is properly set
fix_max_input_time() {
    local php_ini_path="/etc/php/${PHP_VERSION}/fpm/php.ini"
    local cli_ini_path="/etc/php/${PHP_VERSION}/cli/php.ini"
    local fpm_conf="/etc/php/${PHP_VERSION}/fpm/php-fpm.conf"
    local pool_conf="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
    local nextcloud_ini="/etc/php/${PHP_VERSION}/fpm/conf.d/99-nextcloud.ini"
    
    # Fix FPM configuration
    if [ -f "${php_ini_path}" ]; then
        if grep -q '^;*\s*max_input_time\s*=' "${php_ini_path}"; then
            if ! sed -i 's/^;*\s*max_input_time\s*=.*/max_input_time = 1000/' "${php_ini_path}"; then
                log_error "Failed to set max_input_time in ${php_ini_path}"
                return 1
            fi
        else
            if ! echo -e "\n; Set max_input_time for long-running requests\nmax_input_time = 1000" >> "${php_ini_path}"; then
                log_error "Failed to append max_input_time to ${php_ini_path}"
                return 1
            fi
        fi
        log_info "✅ Set max_input_time = 1000 in ${php_ini_path}"
    fi
    
    # Fix CLI configuration
    if [ -f "${cli_ini_path}" ]; then
        if grep -q '^;*\s*max_input_time\s*=' "${cli_ini_path}"; then
            if ! sed -i 's/^;*\s*max_input_time\s*=.*/max_input_time = 1000/' "${cli_ini_path}"; then
                log_error "Failed to set max_input_time in ${cli_ini_path}"
                return 1
            fi
        else
            if ! echo -e "\n; Set max_input_time for long-running requests\nmax_input_time = 1000" >> "${cli_ini_path}"; then
                log_error "Failed to append max_input_time to ${cli_ini_path}"
                return 1
            fi
        fi
        log_info "✅ Set max_input_time = 1000 in ${cli_ini_path}"
    fi
    
    # Ensure it's set in the PHP-FPM main config
    if [ -f "${fpm_conf}" ]; then
        if grep -q '^;*\s*max_input_time\s*=' "${fpm_conf}"; then
            if ! sed -i 's/^;*\s*max_input_time\s*=.*/max_input_time = 1000/' "${fpm_conf}"; then
                log_error "Failed to set max_input_time in ${fpm_conf}"
                return 1
            fi
        else
            if ! echo -e "\n; Set max_input_time for long-running requests\nmax_input_time = 1000" >> "${fpm_conf}"; then
                log_error "Failed to append max_input_time to ${fpm_conf}"
                return 1
            fi
        fi
        log_info "✅ Set max_input_time = 1000 in ${fpm_conf}"
    fi
    
    # Ensure it's set in the pool configuration
    if [ -f "${pool_conf}" ]; then
        if grep -q '^;*\s*php_admin_value\[max_input_time\]' "${pool_conf}"; then
            if ! sed -i 's/^;*\s*php_admin_value\[max_input_time\].*/php_admin_value[max_input_time] = 1000/' "${pool_conf}"; then
                log_error "Failed to set php_admin_value[max_input_time] in ${pool_conf}"
                return 1
            fi
        else
            if ! echo -e "\n; Set max_input_time for long-running requests\nphp_admin_value[max_input_time] = 1000" >> "${pool_conf}"; then
                log_error "Failed to append php_admin_value[max_input_time] to ${pool_conf}"
                return 1
            fi
        fi
        log_info "✅ Set php_admin_value[max_input_time] = 1000 in ${pool_conf}"
    fi
    
    # Also ensure it's set in the custom config
    if [ -f "${nextcloud_ini}" ]; then
        if grep -q '^;*\s*max_input_time\s*=' "${nextcloud_ini}"; then
            if ! sed -i 's/^;*\s*max_input_time\s*=.*/max_input_time = 1000/' "${nextcloud_ini}"; then
                log_error "Failed to set max_input_time in ${nextcloud_ini}"
                return 1
            fi
        else
            if ! echo -e "\n; Set max_input_time for long-running requests\nmax_input_time = 1000" >> "${nextcloud_ini}"; then
                log_error "Failed to append max_input_time to ${nextcloud_ini}"
                return 1
            fi
        fi
        log_info "✅ Set max_input_time = 1000 in ${nextcloud_ini}"
    fi
    
    # Force reload PHP-FPM to apply changes
    if systemctl is-active --quiet "php${PHP_VERSION}-fpm"; then
        log_info "🔄 Reloading PHP-FPM to apply max_input_time changes..."
        if ! systemctl reload "php${PHP_VERSION}-fpm" 2>/dev/null; then
            log_warning "⚠️  Failed to reload PHP-FPM, trying full restart..."
            if ! systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null; then
                log_error "❌ Failed to restart PHP-FPM"
                return 1
            fi
        fi
        log_success "✅ PHP-FPM reloaded successfully"
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_php_stack
    exit $?
fi
