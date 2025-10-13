#!/bin/bash

# configure-webserver.sh - Comprehensive web server configuration script
# This script configures Apache, PHP-FPM, and related components for Nextcloud

set -e

# Source core functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/common-functions.sh"
source "$SCRIPT_DIR/../core/logging.sh"
source "$SCRIPT_DIR/../core/config-manager.sh"

# Component details
COMPONENT="webserver"
APACHE_CONF_DIR="/etc/apache2"
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || echo "")
PHP_FPM_POOL_DIR="/etc/php/$PHP_VERSION/fpm/pool.d"
NEXTCLOUD_DIR="${NEXTCLOUD_INSTALL_DIR:-/var/www/nextcloud}"
NEXTCLOUD_DATA_DIR="${NEXTCLOUD_DATA_DIR:-/var/nextcloud/data}"

# Default configuration values
declare -A DEFAULTS=(
    [WEBSERVER_USER]="www-data"
    [WEBSERVER_GROUP]="www-data"
    [SERVER_ADMIN_EMAIL]="admin@${NEXTCLOUD_DOMAIN:-localhost}"
    [MAX_UPLOAD_SIZE]="10G"
    [MAX_EXECUTION_TIME]="3600"
    [MEMORY_LIMIT]="512M"
    [OPCACHE_MEMORY_CONSUMPTION]="256"
    [APACHE_MPM]="event"
    [APACHE_MAX_REQUEST_WORKERS]="150"
    [APACHE_THREADS_PER_CHILD]="25"
    [PHP_FPM_PM]="ondemand"
    [PHP_FPM_MAX_CHILDREN]="50"
    [PHP_FPM_START_SERVERS]="5"
    [PHP_FPM_MIN_SPARE_SERVERS]="5"
    [PHP_FPM_MAX_SPARE_SERVERS]="35"
    [PHP_FPM_MAX_REQUESTS]="500"
)

# Main function
main() {
    print_header "Configuring Web Server Stack"
    load_config
    require_root
    check_requirements
    configure_apache_mpm
    configure_apache
    configure_php_fpm
    configure_php_opcache
    apply_security_settings
    configure_virtual_hosts
    test_configuration
    restart_services
    print_success "Web server configuration completed"
}

# Check system requirements
check_requirements() {
    if ! command -v apache2 >/dev/null 2>&1; then
        print_error "Apache is not installed. Please run 'install-webserver.sh' first."
        exit 1
    fi
    
    if [ -z "$PHP_VERSION" ] || ! command -v php-fpm$PHP_VERSION >/dev/null 2>&1; then
        print_error "PHP-FPM is not installed. Please install PHP-FPM first."
        exit 1
    fi
    
    mkdir -p "$APACHE_CONF_DIR/sites-available" \
             "$APACHE_CONF_DIR/sites-enabled" \
             "$PHP_FPM_POOL_DIR"
    
    chown -R ${WEBSERVER_USER}:${WEBSERVER_GROUP} "$NEXTCLOUD_DIR" "$NEXTCLOUD_DATA_DIR"
    chmod -R 750 "$NEXTCLOUD_DIR"
    chmod -R 770 "$NEXTCLOUD_DATA_DIR"
}

# Configure Apache MPM
configure_apache_mpm() {
    local mpm=${APACHE_MPM,,}
    a2dismod mpm_prefork mpm_worker mpm_event 2>/dev/null || true
    
    if ! a2enmod "mpm_$mpm"; then
        print_error "Failed to enable MPM $mpm. Falling back to event MPM."
        a2enmod mpm_event
        mpm="event"
    fi
    
    local mpm_conf="$APACHE_CONF_DIR/mods-available/mpm_${mpm}.conf"
    if [ -f "$mpm_conf" ]; then
        case $mpm in
            "prefork")
                sed -i -e "s/^StartServers.*/StartServers             ${PHP_FPM_START_SERVERS:-5}/" \
                      -e "s/^MaxRequestWorkers.*/MaxRequestWorkers          ${APACHE_MAX_REQUEST_WORKERS:-150}/" \
                      "$mpm_conf"
                ;;
            "event" | "worker")
                sed -i -e "s/^ThreadsPerChild.*/ThreadsPerChild           ${APACHE_THREADS_PER_CHILD:-25}/" \
                      -e "s/^MaxRequestWorkers.*/MaxRequestWorkers          ${APACHE_MAX_REQUEST_WORKERS:-150}/" \
                      "$mpm_conf"
                ;;
        esac
    fi
}

# Configure Apache
configure_apache() {
    print_status "Configuring Apache web server..."
    
    local required_modules=(
        "headers" "rewrite" "ssl" "http2" "proxy_fcgi" "setenvif" "env" "dir" "mime"
        "authz_core" "authz_host" "deflate" "filter" "alias" "socache_shmcb"
    )
    
    for module in "${required_modules[@]}"; do
        a2enmod -q "$module" 2>/dev/null || print_warning "Failed to enable module: $module"
    done
    
    a2dissite 000-default.conf 2>/dev/null || true
}

# Configure PHP-FPM
configure_php_fpm() {
    print_status "Configuring PHP-FPM..."
    
    local pool_conf="$PHP_FPM_POOL_DIR/nextcloud.conf"
    
    cat > "$pool_conf" << EOF
[nextcloud]
user = ${WEBSERVER_USER}
group = ${WEBSERVER_GROUP}
listen = /run/php/php${PHP_VERSION}-fpm-nextcloud.sock
listen.owner = ${WEBSERVER_USER}
listen.group = ${WEBSERVER_GROUP}
listen.mode = 0660

; Process manager
pm = ${PHP_FPM_PM}
pm.max_children = ${PHP_FPM_MAX_CHILDREN}
pm.start_servers = ${PHP_FPM_START_SERVERS}
pm.min_spare_servers = ${PHP_FPM_MIN_SPARE_SERVERS}
pm.max_spare_servers = ${PHP_FPM_MAX_SPARE_SERVERS}
pm.max_requests = ${PHP_FPM_MAX_REQUESTS}

; Resource limits
rlimit_files = 131072
rlimit_core = unlimited

; PHP settings
php_admin_value[upload_max_filesize] = ${MAX_UPLOAD_SIZE}
php_admin_value[post_max_size] = ${MAX_UPLOAD_SIZE}
php_admin_value[memory_limit] = ${MEMORY_LIMIT}
php_admin_value[max_execution_time] = ${MAX_EXECUTION_TIME}
php_admin_value[date.timezone] = ${SYSTEM_TIMEZONE:-UTC}

; OPcache
php_admin_flag[opcache.enable] = 1
php_admin_flag[opcache.validate_timestamps] = 0
php_admin_value[opcache.memory_consumption] = ${OPCACHE_MEMORY_CONSUMPTION}
php_admin_value[opcache.interned_strings_buffer] = 16
php_admin_value[opcache.max_accelerated_files] = 10000
EOF
}

# Apply security settings
apply_security_settings() {
    local security_conf="$APACHE_CONF_DIR/conf-available/security-headers.conf"
    
    cat > "$security_conf" << EOF
# Security headers
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Download-Options "noopen"
Header always set X-Permitted-Cross-Domain-Policies "none"
Header always set Referrer-Policy "no-referrer"
Header always set Permissions-Policy "camera=(), microphone=(), geolocation=()"

# Disable server signature
ServerSignature Off
ServerTokens Prod

# Disable directory listing
<DirectoryMatch "^/.*/\\.git/|/vendor/|/node_modules/|/\\.">
    Require all denied
</DirectoryMatch>

# Protect sensitive files
<FilesMatch "^\\.|^composer\\.json|^composer\\.lock|^package\\.json|^package-lock\\.json|^web\\.config|^Dockerfile|^docker-compose\\.ya?ml|^README\\.md$">
    Require all denied
</FilesMatch>

# Disable TRACE and TRACK methods
TraceEnable off
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteCond %{REQUEST_METHOD} ^(TRACE|TRACK|OPTIONS)
    RewriteRule .* - [F]
</IfModule>
EOF

    a2enconf security-headers
}

# Configure virtual hosts
configure_virtual_hosts() {
    local vhost_conf="$APACHE_CONF_DIR/sites-available/nextcloud.conf"
    local server_name="${NEXTCLOUD_DOMAIN:-localhost}"
    
    cat > "$vhost_conf" << EOF
<VirtualHost *:80>
    ServerAdmin ${SERVER_ADMIN_EMAIL}
    ServerName ${server_name}
    DocumentRoot ${NEXTCLOUD_DIR}
    
    <Directory ${NEXTCLOUD_DIR}>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
        SetEnv HOME ${NEXTCLOUD_DIR}
        SetEnv HTTP_HOME ${NEXTCLOUD_DIR}
    </Directory>
    
    <FilesMatch \\.php$>
        SetHandler "proxy:unix:/run/php/php${PHP_VERSION}-fpm-nextcloud.sock|fcgi://localhost"
    </FilesMatch>
    
    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF

    a2ensite nextcloud.conf
}

# Test configuration
test_configuration() {
    if ! apache2ctl -t; then
        print_error "Apache configuration test failed. Please check the configuration."
        exit 1
    fi
    
    if ! php-fpm${PHP_VERSION} -t; then
        print_error "PHP-FPM configuration test failed. Please check the configuration."
        exit 1
    fi
}

# Restart services
restart_services() {
    systemctl restart apache2
    systemctl restart php${PHP_VERSION}-fpm
}

# Run main function
main "@"