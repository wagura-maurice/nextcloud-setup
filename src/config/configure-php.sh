#!/bin/bash

# configure-php.sh - PHP configuration script for Nextcloud
# This script configures PHP with optimal settings for Nextcloud

set -e

# Source core functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/common-functions.sh"
source "$SCRIPT_DIR/../core/logging.sh"
source "$SCRIPT_DIR/../core/config-manager.sh"

# Component details
COMPONENT="php"
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || echo "")
PHP_INI_DIR="/etc/php/$PHP_VERSION"
PHP_FPM_POOL_DIR="/etc/php/$PHP_VERSION/fpm/pool.d"
PHP_CLI_INI="$PHP_INI_DIR/cli/php.ini"
PHP_FPM_INI="$PHP_INI_DIR/fpm/php.ini"
PHP_APACHE_INI="$PHP_INI_DIR/apache2/php.ini"

# Default configuration values
declare -A DEFAULTS=(
    [PHP_MEMORY_LIMIT]="512M"
    [PHP_UPLOAD_MAX_FILESIZE]="10G"
    [PHP_POST_MAX_SIZE]="10G"
    [PHP_MAX_EXECUTION_TIME]="3600"
    [PHP_MAX_INPUT_TIME]="3600"
    [PHP_MAX_FILE_UPLOADS]="200"
    [PHP_DISPLAY_ERRORS]="Off"
    [PHP_LOG_ERRORS]="On"
    [PHP_ERROR_REPORTING]="E_ALL & ~E_DEPRECATED & ~E_STRICT"
    [PHP_OPCACHE_ENABLE]="1"
    [PHP_OPCACHE_MEMORY_CONSUMPTION]="256"
    [PHP_OPCACHE_INTERNED_STRINGS_BUFFER]="32"
    [PHP_OPCACHE_MAX_ACCELERATED_FILES]="10000"
    [PHP_OPCACHE_VALIDATE_TIMESTAMPS]="1"
    [PHP_OPCACHE_SAVE_COMMENTS]="1"
    [PHP_OPCACHE_ENABLE_CLI]="0"
    [PHP_OPCACHE_REVALIDATE_FREQ]="60"
    [PHP_SESSION_GC_MAXLIFETIME]="14400"
    [PHP_SESSION_SAVE_HANDLER]="redis"
    [PHP_SESSION_SAVE_PATH]="tcp://127.0.0.1:6379"
    [PHP_APC_ENABLED]="1"
    [PHP_APC_SHM_SIZE]="128M"
    [PHP_APC_TTL]="7200"
)

# Function to configure PHP settings
configure_php_ini() {
    local ini_file="$1"
    local is_fpm=false
    
    if [[ "$ini_file" == *"fpm"* ]]; then
        is_fpm=true
    fi
    
    print_status "Configuring $ini_file"
    
    # Backup existing config
    backup_file "$ini_file"
    
    # Set PHP settings
    set_ini_setting "$ini_file" "memory_limit" "${PHP_MEMORY_LIMIT}"
    set_ini_setting "$ini_file" "upload_max_filesize" "${PHP_UPLOAD_MAX_FILESIZE}"
    set_ini_setting "$ini_file" "post_max_size" "${PHP_POST_MAX_SIZE}"
    set_ini_setting "$ini_file" "max_execution_time" "${PHP_MAX_EXECUTION_TIME}"
    set_ini_setting "$ini_file" "max_input_time" "${PHP_MAX_INPUT_TIME}"
    set_ini_setting "$ini_file" "max_file_uploads" "${PHP_MAX_FILE_UPLOADS}"
    set_ini_setting "$ini_file" "display_errors" "${PHP_DISPLAY_ERRORS}"
    set_ini_setting "$ini_file" "log_errors" "${PHP_LOG_ERRORS}"
    set_ini_setting "$ini_file" "error_reporting" "${PHP_ERROR_REPORTING}"
    
    # Session settings
    set_ini_setting "$ini_file" "session.save_handler" "${PHP_SESSION_SAVE_HANDLER}"
    set_ini_setting "$ini_file" "session.save_path" "${PHP_SESSION_SAVE_PATH}"
    set_ini_setting "$ini_file" "session.gc_maxlifetime" "${PHP_SESSION_GC_MAXLIFETIME}"
    
    # OPcache settings
    set_ini_setting "$ini_file" "opcache.enable" "${PHP_OPCACHE_ENABLE}"
    set_ini_setting "$ini_file" "opcache.memory_consumption" "${PHP_OPCACHE_MEMORY_CONSUMPTION}"
    set_ini_setting "$ini_file" "opcache.interned_strings_buffer" "${PHP_OPCACHE_INTERNED_STRINGS_BUFFER}"
    set_ini_setting "$ini_file" "opcache.max_accelerated_files" "${PHP_OPCACHE_MAX_ACCELERATED_FILES}"
    set_ini_setting "$ini_file" "opcache.validate_timestamps" "${PHP_OPCACHE_VALIDATE_TIMESTAMPS}"
    set_ini_setting "$ini_file" "opcache.save_comments" "${PHP_OPCACHE_SAVE_COMMENTS}"
    set_ini_setting "$ini_file" "opcache.enable_cli" "${PHP_OPCACHE_ENABLE_CLI}"
    set_ini_setting "$ini_file" "opcache.revalidate_freq" "${PHP_OPCACHE_REVALIDATE_FREQ}"
    
    # APC settings (if enabled)
    if [ "$PHP_APC_ENABLED" = "1" ]; then
        set_ini_setting "$ini_file" "apc.enabled" "1"
        set_ini_setting "$ini_file" "apc.shm_size" "${PHP_APC_SHM_SIZE}"
        set_ini_setting "$ini_file" "apc.ttl" "${PHP_APC_TTL}"
    fi
    
    # Additional FPM-specific settings
    if [ "$is_fpm" = true ]; then
        set_ini_setting "$ini_file" "request_terminate_timeout" "${PHP_MAX_EXECUTION_TIME}"
        set_ini_setting "$ini_file" "pm.max_children" "50"
        set_ini_setting "$ini_file" "pm.start_servers" "5"
        set_ini_setting "$ini_file" "pm.min_spare_servers" "5"
        set_ini_setting "$ini_file" "pm.max_spare_servers" "35"
    fi
    
    # Additional CLI-specific settings
    if [[ "$ini_file" == *"cli"* ]]; then
        set_ini_setting "$ini_file" "memory_limit" "-1"
        set_ini_setting "$ini_file" "max_execution_time" "0"
    fi
}

# Function to configure PHP-FPM pool
configure_php_fpm_pool() {
    local pool_file="$PHP_FPM_POOL_DIR/nextcloud.conf"
    
    print_status "Configuring PHP-FPM pool for Nextcloud"
    
    # Create PHP-FPM pool configuration
    cat > "$pool_file" << EOF
[nextcloud]
user = www-data
group = www-data
listen = /run/php/php${PHP_VERSION}-fpm-nextcloud.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

; Process manager configuration
pm = dynamic
pm.max_children = ${PHP_FPM_MAX_CHILDREN:-50}
pm.start_servers = ${PHP_FPM_START_SERVERS:-5}
pm.min_spare_servers = ${PHP_FPM_MIN_SPARE_SERVERS:-5}
pm.max_spare_servers = ${PHP_FPM_MAX_SPARE_SERVERS:-35}
pm.max_requests = ${PHP_FPM_MAX_REQUESTS:-500}

; Resource limits
request_terminate_timeout = ${PHP_MAX_EXECUTION_TIME:-3600}s
request_slowlog_timeout = 60s
slowlog = /var/log/php-fpm/nextcloud-slow.log

; Security
php_admin_flag[log_errors] = on
php_admin_flag[expose_php] = off
php_admin_flag[display_errors] = off
php_admin_flag[html_errors] = off

; Environment variables
env[HOSTNAME] = \$HOSTNAME
env[PATH] = /usr/local/bin:/usr/bin:/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp

; Performance tuning
php_admin_value[memory_limit] = ${PHP_MEMORY_LIMIT}
php_admin_value[upload_max_filesize] = ${PHP_UPLOAD_MAX_FILESIZE}
php_admin_value[post_max_size] = ${PHP_POST_MAX_SIZE}
php_admin_value[max_execution_time] = ${PHP_MAX_EXECUTION_TIME}
php_admin_value[max_input_time] = ${PHP_MAX_INPUT_TIME}
php_admin_value[max_file_uploads] = ${PHP_MAX_FILE_UPLOADS}

; Session handling
php_admin_value[session.save_handler] = ${PHP_SESSION_SAVE_HANDLER}
php_admin_value[session.save_path] = "${PHP_SESSION_SAVE_PATH}"
php_admin_value[session.gc_maxlifetime] = ${PHP_SESSION_GC_MAXLIFETIME}

; OPcache settings
php_admin_flag[opcache.enable] = ${PHP_OPCACHE_ENABLE}
php_admin_value[opcache.memory_consumption] = ${PHP_OPCACHE_MEMORY_CONSUMPTION}
php_admin_value[opcache.interned_strings_buffer] = ${PHP_OPCACHE_INTERNED_STRINGS_BUFFER}
php_admin_value[opcache.max_accelerated_files] = ${PHP_OPCACHE_MAX_ACCELERATED_FILES}
php_admin_flag[opcache.validate_timestamps] = ${PHP_OPCACHE_VALIDATE_TIMESTAMPS}
php_admin_flag[opcache.save_comments] = ${PHP_OPCACHE_SAVE_COMMENTS}
php_admin_flag[opcache.enable_cli] = ${PHP_OPCACHE_ENABLE_CLI}
php_admin_value[opcache.revalidate_freq] = ${PHP_OPCACHE_REVALIDATE_FREQ}
EOF
    
    # Set proper permissions
    chmod 644 "$pool_file"
    
    # Create log directory if it doesn't exist
    mkdir -p /var/log/php-fpm
    chown www-data:www-data /var/log/php-fpm
}

# Function to restart PHP services
restart_php_services() {
    print_status "Restarting PHP services"
    
    # Restart PHP-FPM if installed
    if [ -f "/etc/init.d/php${PHP_VERSION}-fpm" ]; then
        systemctl restart "php${PHP_VERSION}-fpm"
        print_success "Restarted PHP-FPM"
    fi
    
    # Restart web server if needed
    if systemctl is-active --quiet apache2; then
        systemctl restart apache2
        print_success "Restarted Apache"
    elif systemctl is-active --quiet nginx; then
        systemctl restart nginx
        print_success "Restarted Nginx"
    fi
}

# Main function
main() {
    print_header "Configuring PHP for Nextcloud"
    
    # Load environment and check requirements
    load_config
    require_root
    
    # Check if PHP is installed
    if [ -z "$PHP_VERSION" ]; then
        print_error "PHP is not installed or not found"
        exit 1
    fi
    
    print_status "Configuring PHP $PHP_VERSION"
    
    # Create PHP configuration directories if they don't exist
    mkdir -p "$PHP_INI_DIR/conf.d"
    mkdir -p "$PHP_FPM_POOL_DIR"
    
    # Configure PHP for different SAPIs
    if [ -f "$PHP_CLI_INI" ]; then
        configure_php_ini "$PHP_CLI_INI"
    fi
    
    if [ -f "$PHP_FPM_INI" ]; then
        configure_php_ini "$PHP_FPM_INI"
        configure_php_fpm_pool
    fi
    
    if [ -f "$PHP_APACHE_INI" ]; then
        configure_php_ini "$PHP_APACHE_INI"
    fi
    
    # Restart services
    restart_php_services
    
    print_success "PHP configuration completed successfully"
}

# Execute main function
main "$@"

# this is the scrip that will configure the php.ini in the apache, an the php instalion i.e the cli and fpm on all