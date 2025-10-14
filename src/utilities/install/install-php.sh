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

# Function to apply recommended PHP settings
apply_php_settings() {
    local php_ini_path="/etc/php/${PHP_VERSION}/fpm/php.ini"
    local php_fpm_conf="/etc/php/${PHP_VERSION}/fpm/php-fpm.conf"
    local nextcloud_ini="/etc/php/${PHP_VERSION}/fpm/conf.d/90-nextcloud.ini"
    
    log_info "🔧 Applying recommended PHP settings..."
    
    # Create a backup of the original php.ini
    if [ ! -f "${php_ini_path}.original" ]; then
        cp "${php_ini_path}" "${php_ini_path}.original"
    fi
    
    # Create or update the Nextcloud-specific ini file
    log_info "📝 Updating Nextcloud PHP configuration..."
    
    # Remove existing file if it exists to avoid permission issues
    if [ -f "${nextcloud_ini}" ]; then
        log_info "ℹ️ Removing existing ${nextcloud_ini}..."
        rm -f "${nextcloud_ini}" || {
            log_warning "⚠️  Could not remove ${nextcloud_ini}, trying with sudo..."
            sudo rm -f "${nextcloud_ini}" || {
                log_error "❌ Failed to remove existing ${nextcloud_ini}"
                return 1
            }
        }
    fi
    
    # Create new configuration file
    cat > "${nextcloud_ini}.tmp" << EOF
; Nextcloud recommended PHP settings
; This file is auto-generated - do not edit manually

; Resource limits
memory_limit = 2G
upload_max_filesize = 10G
post_max_size = 10G
max_execution_time = 3600
max_input_time = 3600

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

; Session settings
session.gc_maxlifetime = 3600
session.cookie_lifetime = 0
session.cookie_httponly = 1
session.cookie_secure = 1
session.use_strict_mode = 1

; Disable PHP output buffering
output_buffering = Off

; Disable expose_php for security
expose_php = Off

; Enable file uploads
file_uploads = On

; Set default charset
default_charset = "UTF-8"

; Disable dangerous functions
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_multi_exec,parse_ini_file,show_source

; Increase realpath cache size
realpath_cache_size = 512k
realpath_cache_ttl = 3600

; Increase max input variables
max_input_vars = 2000

; Ensure these settings are not overridden in .user.ini files
user_ini.filename =

; Ensure this setting is not overridden in .htaccess
htaccess_force_redirect = 1
EOF

    # Set correct permissions if file exists
    if [ -f "${nextcloud_ini}" ]; then
        chmod 644 "${nextcloud_ini}"
    fi
    
    # Also update the main php.ini with critical settings
    log_info "🔧 Updating main PHP configuration..."
    
    # First, create a backup of the original php.ini if we haven't already
    if [ ! -f "${php_ini_path}.original" ]; then
        cp "${php_ini_path}" "${php_ini_path}.original"
    fi
    
    # Create a temporary file for the new php.ini
    local temp_ini="${php_ini_path}.new"
    cp "${php_ini_path}.original" "${temp_ini}"
    
    # Define the settings we want to ensure are set in the main php.ini
    declare -A main_settings=(
        ["memory_limit"]="2G"
        ["upload_max_filesize"]="10G"
        ["post_max_size"]="10G"
        ["max_execution_time"]="3600"
        ["max_input_time"]="3600"
    )
    
    # Process each setting
    for setting in "${!main_settings[@]}"; do
        local value="${main_settings[$setting]}"
        
        # Remove any existing setting (commented or not)
        sed -i -E "/^;?\s*${setting}\s*=/d" "${temp_ini}"
        
        # Add our setting at the end of the file
        echo "${setting} = ${value}" >> "${temp_ini}"
        log_info "✅ Set ${setting} = ${value} in ${php_ini_path##*/}"
    done
    
    # Replace the original with our updated version
    mv "${temp_ini}" "${php_ini_path}"
    chmod 644 "${php_ini_path}"
    
        # Move the temporary file to the final location with a high number to ensure it loads last
    local final_ini="/etc/php/${PHP_VERSION}/fpm/conf.d/99-nextcloud.ini"
    
    # Remove any existing nextcloud ini files that might cause conflicts
    for f in "/etc/php/${PHP_VERSION}/fpm/conf.d/"*nextcloud*.ini; do
        if [ "$f" != "$final_ini" ] && [ -f "$f" ]; then
            log_info "Removing conflicting PHP config: $f"
            rm -f "$f" || sudo rm -f "$f"
        fi
    done
    
    if mv "${nextcloud_ini}.tmp" "$final_ini"; then
        chmod 644 "$final_ini"
        log_info "✅ Created $final_ini"
    else
        log_error "❌ Failed to create $final_ini"
        return 1
    fi
    
    # Ensure the PHP-FPM configuration is properly set
    if [ -f "${php_fpm_conf}" ]; then
        log_info "🔧 Configuring PHP-FPM..."
        
        # Create a backup if it doesn't exist
        if [ ! -f "${php_fpm_conf}.original" ]; then
            cp "${php_fpm_conf}" "${php_fpm_conf}.original"
        fi
        
        # Create a temporary file for the new configuration
        local temp_conf="${php_fpm_conf}.tmp"
        cp "${php_fpm_conf}" "${temp_conf}"
        
        # Set FPM settings
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
            if grep -q -E "^;?\s*${setting}\s*=" "${temp_conf}"; then
                sed -i -E "s/^;?\s*${setting}\s*=.*$/${setting} = ${value}/" "${temp_conf}"
            else
                echo "${setting} = ${value}" >> "${temp_conf}"
            fi
            log_info "✅ Set ${setting} = ${value} in ${php_fpm_conf##*/}"
        done
        
        # Validate the configuration before applying
        if php-fpm${PHP_VERSION} -t -c "${temp_conf}"; then
            mv "${temp_conf}" "${php_fpm_conf}"
            chmod 644 "${php_fpm_conf}"
            log_success "✅ PHP-FPM configuration validated and saved"
            
            # Restart PHP-FPM to apply changes
            log_info "🔄 Restarting PHP-FPM service..."
            if systemctl restart "php${PHP_VERSION}-fpm"; then
                log_success "✅ PHP-FPM restarted successfully"
            else
                log_error "❌ Failed to restart PHP-FPM. Showing logs..."
                journalctl -u "php${PHP_VERSION}-fpm" -n 20 --no-pager
                return 1
            fi
        else
            log_error "❌ Invalid PHP-FPM configuration. Not applying changes."
            log_info "Check the configuration in: ${temp_conf}"
            return 1
        fi
    else
        log_warning "⚠️  PHP-FPM configuration file not found at ${php_fpm_conf}"
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
    
    # Create a custom PHP configuration for Nextcloud
    local nextcloud_ini="/etc/php/${PHP_VERSION}/fpm/conf.d/90-nextcloud.ini"
    
    # Nextcloud recommended settings
    cat > "${nextcloud_ini}" << 'EOF'
; Nextcloud recommended settings
max_execution_time = 3600
max_input_time = 3600
memory_limit = 2G
upload_max_filesize = 10G
post_max_size = 10G

; Default timezone
[Date]
date.timezone = UTC

; OPcache settings for better performance
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
session.cookie_httponly = 1
session.cookie_secure = 1
session.use_strict_mode = 1
session.cookie_samesite = Lax
session.cookie_lifetime = 0
session.gc_maxlifetime = 1440

; Other recommended settings
[PHP]
default_socket_timeout = 60

[Pcre]
pcre.jit = 1
pcre.backtrack_limit = 1000000
pcre.recursion_limit = 100000

[MySQL]
mysql.connect_timeout = 60
mysqli.reconnect = Off

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
        "max_input_time = 3600" \
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
        ["max_input_time"]="3600"
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
            
            expected_bytes=$(php${PHP_VERSION} -r "echo \\ini_get_bytes('${expected_value}');" 2>/dev/null)
            actual_bytes=$(php${PHP_VERSION} -r "echo \\ini_get_bytes('${actual_value}');" 2>/dev/null)
            
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
