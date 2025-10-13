#!/bin/bash

# configure-nextcloud.sh - Configuration script for Nextcloud
# This script handles the configuration of Nextcloud's config.php with optimal settings

# Source core functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/common-functions.sh"
source "$SCRIPT_DIR/../core/logging.sh"
source "$SCRIPT_DIR/../core/config-manager.sh"

# Component details
COMPONENT="nextcloud"
NEXTCLOUD_ROOT="/var/www/nextcloud"
NEXTCLOUD_CONFIG="${NEXTCLOUD_ROOT}/config/config.php"
NEXTCLOUD_DATA="/var/nextcloud/data"
OCC="${NEXTCLOUD_ROOT}/occ"

# Default configuration values
declare -A DEFAULTS=(
    [NEXTCLOUD_TRUSTED_DOMAINS]="localhost"
    [NEXTCLOUD_DB_TYPE]="mysql"
    [NEXTCLOUD_DB_NAME]="nextcloud"
    [NEXTCLOUD_DB_USER]="nextcloud"
    [NEXTCLOUD_DB_PASSWORD]="$(openssl rand -base64 32)"
    [NEXTCLOUD_DB_HOST]="localhost"
    [NEXTCLOUD_ADMIN_USER]="admin"
    [NEXTCLOUD_ADMIN_PASSWORD]=""
    [NEXTCLOUD_DATA_DIR]="${NEXTCLOUD_DATA}"
    [NEXTCLOUD_OVERWRITE_CLI_URL]="https://${NEXTCLOUD_TRUSTED_DOMAINS}"
    [NEXTCLOUD_HTACCESS_REWRITE_BASE]="/"
    [NEXTCLOUD_REDIS_HOST]="localhost"
    [NEXTCLOUD_REDIS_PORT]="6379"
    [NEXTCLOUD_REDIS_PASSWORD]=""
    [NEXTCLOUD_MEMCACHED_LOCAL]="\\\\OC\\\\Memcache\\\\APCu"
    [NEXTCLOUD_MEMCACHED_DISTRIBUTED]="\\\\OC\\\\Memcache\\\\Redis"
    [NEXTCLOUD_FILELOCKING_ENABLED]="true"
    [NEXTCLOUD_MAINTENANCE_MODE]="false"
    [NEXTCLOUD_CRONJOB]="cron"
)

# Main function
main() {
    print_header "Configuring Nextcloud"
    
    # Load environment
    load_config
    
    # Check root
    require_root
    
    # Check if Nextcloud is installed
    if [ ! -f "$NEXTCLOUD_CONFIG" ]; then
        print_error "Nextcloud is not installed or config file not found at $NEXTCLOUD_CONFIG"
        exit 1
    fi
    
    # Check if occ command exists
    if [ ! -f "$OCC" ]; then
        print_error "Nextcloud occ command not found at $OCC"
        exit 1
    fi
    
    # Set file permissions
    set_permissions
    
    # Configure Nextcloud
    configure_nextcloud
    
    # Configure database
    configure_database
    
    # Configure caching
    configure_caching
    
    # Configure background jobs
    configure_background_jobs
    
    # Configure file locking
    configure_file_locking
    
    # Configure HTTPS
    configure_https
    
    # Configure security
    configure_security
    
    # Configure performance
    configure_performance
    
    # Finalize configuration
    finalize_configuration
    
    print_success "Nextcloud configuration completed"
}

# Set file permissions
set_permissions() {
    print_status "Setting file permissions..."
    
    # Set ownership
    chown -R www-data:www-data "$NEXTCLOUD_ROOT"
    chown -R www-data:www-data "$NEXTCLOUD_DATA"
    
    # Set directory permissions
    find "$NEXTCLOUD_ROOT" -type d -exec chmod 750 {} \;
    find "$NEXTCLOUD_ROOT" -type f -exec chmod 640 {} \;
    
    # Set special permissions for certain directories
    chmod 750 "$NEXTCLOUD_ROOT/occ"
    chmod 770 "$NEXTCLOUD_ROOT/apps"
    chmod 770 "${NEXTCLOUD_ROOT}/config"
    
    print_status "File permissions set successfully"
}

# Configure Nextcloud
configure_nextcloud() {
    print_status "Configuring Nextcloud..."
    
    # Check if Nextcloud is already installed
    if ! sudo -u www-data php "$OCC" status --no-warnings > /dev/null 2>&1; then
        print_status "Performing initial Nextcloud installation..."
        
        # Run the installation
        sudo -u www-data php "$OCC" maintenance:install \
            --database="${NEXTCLOUD_DB_TYPE:-mysql}" \
            --database-name="${NEXTCLOUD_DB_NAME}" \
            --database-user="${NEXTCLOUD_DB_USER}" \
            --database-pass="${NEXTCLOUD_DB_PASSWORD}" \
            --database-host="${NEXTCLOUD_DB_HOST}" \
            --admin-user="${NEXTCLOUD_ADMIN_USER}" \
            --admin-pass="${NEXTCLOUD_ADMIN_PASSWORD}" \
            --data-dir="${NEXTCLOUD_DATA_DIR}" \
            --no-interaction
            
        if [ $? -ne 0 ]; then
            print_error "Failed to install Nextcloud"
            exit 1
        fi
        
        print_status "Nextcloud installed successfully"
    else
        print_status "Nextcloud is already installed, updating configuration..."
    fi
    
    # Set trusted domains
    IFS=',' read -ra TRUSTED_DOMAINS <<< "${NEXTCLOUD_TRUSTED_DOMAINS}"
    for i in "${!TRUSTED_DOMAINS[@]}"; do
        sudo -u www-data php "$OCC" config:system:set trusted_domains "$i" --value="${TRUSTED_DOMAINS[$i]}" > /dev/null
    done
    
    # Set default phone region
    sudo -u www-data php "$OCC" config:system:set default_phone_region --value="${NEXTCLOUD_DEFAULT_PHONE_REGION:-US}" > /dev/null
    
    # Set default app disabled list
    sudo -u www-data php "$OCC" config:system:set appstoreenabled --value true --type boolean > /dev/null
    
    print_status "Nextcloud configuration applied successfully"
}

# Configure database
configure_database() {
    print_status "Configuring database..."
    
    # Set database type
    sudo -u www-data php "$OCC" config:system:set dbtype --value="${NEXTCLOUD_DB_TYPE}" > /dev/null
    
    # Set database host
    sudo -u www-data php "$OCC" config:system:set dbhost --value="${NEXTCLOUD_DB_HOST}" > /dev/null
    
    # Set database name
    sudo -u www-data php "$OCC" config:system:set dbname --value="${NEXTCLOUD_DB_NAME}" > /dev/null
    
    # Set database user
    sudo -u www-data php "$OCC" config:system:set dbuser --value="${NEXTCLOUD_DB_USER}" > /dev/null
    
    # Set database password
    sudo -u www-data php "$OCC" config:system:set dbpassword --value="${NEXTCLOUD_DB_PASSWORD}" > /dev/null
    
    # Optimize database
    sudo -u www-data php "$OCC" db:add-missing-indices > /dev/null
    sudo -u www-data php "$OCC" db:convert-filecache-bigint > /dev/null
    
    print_status "Database configuration applied successfully"
}

# Configure caching
configure_caching() {
    print_status "Configuring caching..."
    
    # Configure local caching
    if [ -n "${NEXTCLOUD_MEMCACHED_LOCAL}" ]; then
        sudo -u www-data php "$OCC" config:system:set memcache.local --value="${NEXTCLOUD_MEMCACHED_LOCAL}" > /dev/null
    fi
    
    # Configure distributed caching
    if [ -n "${NEXTCLOUD_MEMCACHED_DISTRIBUTED}" ]; then
        sudo -u www-data php "$OCC" config:system:set memcache.distributed --value="${NEXTCLOUD_MEMCACHED_DISTRIBUTED}" > /dev/null
    fi
    
    # Configure Redis caching if enabled
    if [ -n "${NEXTCLOUD_REDIS_HOST}" ]; then
        sudo -u www-data php "$OCC" config:system:set redis host --value="${NEXTCLOUD_REDIS_HOST}" > /dev/null
        
        if [ -n "${NEXTCLOUD_REDIS_PORT}" ]; then
            sudo -u www-data php "$OCC" config:system:set redis port --value="${NEXTCLOUD_REDIS_PORT}" --type=integer > /dev/null
        fi
        
        if [ -n "${NEXTCLOUD_REDIS_PASSWORD}" ]; then
            sudo -u www-data php "$OCC" config:system:set redis password --value="${NEXTCLOUD_REDIS_PASSWORD}" > /dev/null
        fi
        
        # Enable Redis for file locking if configured
        if [ "${NEXTCLOUD_FILELOCKING_ENABLED}" = "true" ]; then
            sudo -u www-data php "$OCC" config:system:set memcache.locking --value="\\\\OC\\\\Memcache\\\\Redis" > /dev/null
        fi
    fi
    
    # Configure APCu caching if available
    if php -m | grep -q apcu; then
        sudo -u www-data php "$OCC" config:system:set memcache.local --value="\\\\OC\\\\Memcache\\\\APCu" > /dev/null
    fi
    
    print_status "Caching configuration applied successfully"
}

# Configure background jobs
configure_background_jobs() {
    print_status "Configuring background jobs..."
    
    # Set background job mode
    if [ -n "${NEXTCLOUD_CRONJOB}" ]; then
        sudo -u www-data php "$OCC" background:job --mode="${NEXTCLOUD_CRONJOB}" > /dev/null
    fi
    
    # Set cron job if not set
    if ! crontab -u www-data -l 2>/dev/null | grep -q "$OCC"; then
        (crontab -u www-data -l 2>/dev/null; echo "*/5  *  *  *  * php -f ${NEXTCLOUD_ROOT}/cron.php" ) | crontab -u www-data -
    fi
    
    print_status "Background jobs configured successfully"
}

# Configure file locking
configure_file_locking() {
    print_status "Configuring file locking..."
    
    if [ "${NEXTCLOUD_FILELOCKING_ENABLED}" = "true" ]; then
        sudo -u www-data php "$OCC" config:app:set core enable_previews --value="true" > /dev/null
        sudo -u www-data php "$OCC" config:system:set filelocking.enabled --value="true" --type=boolean > /dev/null
        
        if [ -n "${NEXTCLOUD_REDIS_HOST}" ]; then
            sudo -u www-data php "$OCC" config:system:set memcache.locking --value="\\\\OC\\\\Memcache\\\\Redis" > /dev/null
        fi
    else
        sudo -u www-data php "$OCC" config:system:delete memcache.locking > /dev/null
        sudo -u www-data php "$OCC" config:system:set filelocking.enabled --value="false" --type=boolean > /dev/null
    fi
    
    print_status "File locking configuration applied successfully"
}

# Configure HTTPS
configure_https() {
    print_status "Configuring HTTPS..."
    
    # Set default protocol to https
    sudo -u www-data php "$OCC" config:system:set overwriteprotocol --value="https" > /dev/null
    
    # Enable HSTS
    sudo -u www-data php "$OCC" config:system:set hsts_header --value="true" --type=boolean > /dev/null
    
    # Enable HSTS preload
    sudo -u www-data php "$OCC" config:system:set hsts_preload --value="true" --type=boolean > /dev/null
    
    # Set trusted proxies if provided
    if [ -n "${NEXTCLOUD_TRUSTED_PROXIES}" ]; then
        IFS=',' read -ra PROXIES <<< "${NEXTCLOUD_TRUSTED_PROXIES}"
        for i in "${!PROXIES[@]}"; do
            sudo -u www-data php "$OCC" config:system:set trusted_proxies "$i" --value="${PROXIES[$i]}" > /dev/null
        done
    fi
    
    print_status "HTTPS configuration applied successfully"
}

# Configure security
configure_security() {
    print_status "Configuring security settings..."
    
    # Enable brute force protection
    sudo -u www-data php "$OCC" config:system:set auth.bruteforce.protection.enabled --value="true" --type=boolean > /dev/null
    
    # Set password policy
    sudo -u www-data php "$OCC" config:app:set passwords minLength --value="12" > /dev/null
    sudo -u www-data php "$OCC" config:app:set passwords requireNumeric --value="true" --type=boolean > /dev/null
    sudo -u www-data php "$OCC" config:app:set passwords requireLowerAndUpperCase --value="true" --type=boolean > /dev/null
    sudo -u www-data php "$OCC" config:app:set passwords specialChars --value="!@#%^&*_+\-=\\`~(){}[]|:;\"'<>,.?/" > /dev/null
    
    # Enable two-factor authentication
    sudo -u www-data php "$OCC" app:enable twofactor_totp > /dev/null
    
    # Disable password reset for admins
    sudo -u www-data php "$OCC" config:system:set lost_password_link --value="disabled" > /dev/null
    
    # Set minimum password length
    sudo -u www-data php "$OCC" config:system:set minimum.supported.desktopVersion --value="3.0.0" > /dev/null
    
    print_status "Security configuration applied successfully"
}

# Configure performance
configure_performance() {
    print_status "Configuring performance settings..."
    
    # Enable file caching
    sudo -u www-data php "$OCC" config:system:set filelocking.enabled --value="true" --type=boolean > /dev/null
    
    # Configure preview settings
    sudo -u www-data php "$OCC" config:system:set preview_max_x --value="2048" --type=integer > /dev/null
    sudo -u www-data php "$OCC" config:system:set preview_max_y --value="2048" --type=integer > /dev/null
    sudo -u www-data php "$OCC" config:system:set jpeg_quality --value="60" --type=integer > /dev/null
    
    # Enable opcache if available
    if php -m | grep -q opcache; then
        sudo -u www-data php "$OCC" config:system:set opcache.enable --value="1" --type=integer > /dev/null
        sudo -u www-data php "$OCC" config:system:set opcache.enable_cli --value="1" --type=integer > /dev/null
        sudo -u www-data php "$OCC" config:system:set opcache.interned_strings_buffer --value="8" --type=integer > /dev/null
        sudo -u www-data php "$OCC" config:system:set opcache.max_accelerated_files --value="10000" --type=integer > /dev/null
        sudo -u www-data php "$OCC" config:system:set opcache.memory_consumption --value="128" --type=integer > /dev/null
        sudo -u www-data php "$OCC" config:system:set opcache.revalidate_freq --value="1" --type=integer > /dev/null
        sudo -u www-data php "$OCC" config:system:set opcache.save_comments --value="1" --type=integer > /dev/null
    fi
    
    # Configure PHP memory limit
    sudo -u www-data php "$OCC" config:system:set memory_limit --value="512M" > /dev/null
    
    # Configure PHP upload limits
    sudo -u www-data php "$OCC" config:system:set upload_max_filesize --value="10G" > /dev/null
    sudo -u www-data php "$OCC" config:system:set post_max_size --value="10G" > /dev/null
    
    print_status "Performance configuration applied successfully"
}

# Finalize configuration
finalize_configuration() {
    print_status "Finalizing configuration..."
    
    # Set maintenance mode if needed
    if [ "${NEXTCLOUD_MAINTENANCE_MODE}" = "true" ]; then
        sudo -u www-data php "$OCC" maintenance:mode --on > /dev/null
    else
        sudo -u www-data php "$OCC" maintenance:mode --off > /dev/null
    fi
    
    # Update the system
    sudo -u www-data php "$OCC" upgrade --no-interaction > /dev/null
    
    # Update the database schema
    sudo -u www-data php "$OCC" db:add-missing-indices > /dev/null
    
    # Clean up the cache
    sudo -u www-data php "$OCC" cache:clear > /dev/null
    
    # Update the theme
    sudo -u www-data php "$OCC" maintenance:theme:update > /dev/null
    
    # Update the search index
    sudo -u www-data php "$OCC" files:scan --all > /dev/null
    
    # Update the previews
    sudo -u www-data php "$OCC" preview:generate-all -n -v > /dev/null
    
    print_status "Configuration finalized successfully"
}

# Run main function
main "@"
