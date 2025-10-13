#!/bin/bash
set -euo pipefail

# Set project root and core directories
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

log_section "Apache and PHP-FPM Configuration"

# Default configuration values
readonly DEFAULT_DOMAIN="localhost"
readonly DEFAULT_NEXTCLOUD_ROOT="/var/www/nextcloud"
readonly DEFAULT_PHP_VERSION="8.4"
readonly DEFAULT_UPLOAD_MAX_SIZE="2G"
readonly DEFAULT_MEMORY_LIMIT="512M"

# Load configuration
export DOMAIN=$(get_config "DOMAIN" "${DEFAULT_DOMAIN}")
export NEXTCLOUD_ROOT=$(get_config "NEXTCLOUD_ROOT" "${DEFAULT_NEXTCLOUD_ROOT}")
readonly PHP_VERSION=$(get_config "PHP_VERSION" "${DEFAULT_PHP_VERSION}")
readonly UPLOAD_MAX_SIZE=$(get_config "UPLOAD_MAX_SIZE" "${DEFAULT_UPLOAD_MAX_SIZE}")
readonly MEMORY_LIMIT=$(get_config "MEMORY_LIMIT" "${DEFAULT_MEMORY_LIMIT}")

# Derived paths
readonly PHP_INI_DIR="/etc/php/${PHP_VERSION}/fpm"
readonly PHP_POOL_DIR="${PHP_INI_DIR}/pool.d"
readonly PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
readonly APACHE_SITES_AVAILABLE="/etc/apache2/sites-available"
readonly APACHE_MODS_AVAILABLE="/etc/apache2/mods-available"

# Function to verify prerequisites
verify_prerequisites() {
    log_info "Verifying prerequisites..."
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        return 1
    fi
    
    # Verify Apache is installed
    if ! command -v apache2 >/dev/null 2>&1; then
        log_error "Apache2 is not installed. Please install it first."
        return 1
    fi
    
    # Verify PHP-FPM is installed
    if [ ! -d "${PHP_INI_DIR}" ]; then
        log_error "PHP-FPM ${PHP_VERSION} is not installed. Please install it first."
        return 1
    fi
    
    log_success "All prerequisites are met"
    return 0
}

# Function to configure PHP-FPM pool
configure_php_fpm() {
    log_info "Configuring PHP-FPM pool..."
    
    local pool_file="${PHP_POOL_DIR}/nextcloud.conf"
    
    # Create backup if file exists
    if [ -f "${pool_file}" ]; then
        cp "${pool_file}" "${pool_file}.bak"
    fi
    
    cat > "${pool_file}" << EOF
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
php_admin_value[memory_limit] = ${MEMORY_LIMIT}
php_admin_value[upload_max_filesize] = ${UPLOAD_MAX_SIZE}
php_admin_value[post_max_size] = ${UPLOAD_MAX_SIZE}
php_admin_value[max_execution_time] = 3600
php_admin_value[max_input_time] = 3600
php_admin_value[max_input_vars] = 10000
php_admin_value[date.timezone] = UTC
php_admin_flag[opcache.enable] = on
php_admin_value[opcache.memory_consumption] = 128
php_admin_value[opcache.interned_strings_buffer] = 8
php_admin_value[opcache.max_accelerated_files] = 10000
php_admin_value[opcache.validate_timestamps] = 0
php_admin_value[opcache.save_comments] = 1
php_admin_value[opcache.fast_shutdown] = 1
EOF
    
    # Set correct permissions
    chmod 0644 "${pool_file}"
    chown root:root "${pool_file}"
    
    log_success "PHP-FPM pool configured"
    return 0
}

# Function to configure Apache virtual host
configure_apache_vhost() {
    log_info "Configuring Apache virtual host..."
    
    local vhost_file="${APACHE_SITES_AVAILABLE}/nextcloud.conf"
    
    # Create backup if file exists
    if [ -f "${vhost_file}" ]; then
        cp "${vhost_file}" "${vhost_file}.bak"
    fi
    
    cat > "${vhost_file}" << EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAdmin webmaster@${DOMAIN}
    DocumentRoot ${NEXTCLOUD_ROOT}
    
    <Directory ${NEXTCLOUD_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
        
        SetEnv HOME ${NEXTCLOUD_ROOT}
        SetEnv HTTP_HOME ${NEXTCLOUD_ROOT}
    </Directory>
    
    <IfModule mod_headers.c>
        Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains; preload"
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-XSS-Protection "1; mode=block"
        Header always set X-Robots-Tag "none"
        Header always set X-Download-Options "noopen"
        Header always set X-Permitted-Cross-Domain-Policies "none"
        Header always set Referrer-Policy "no-referrer"
    </IfModule>
    
    <IfModule mod_rewrite.c>
        RewriteEngine On
        RewriteRule .* - [env=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
    </IfModule>
    
    <IfModule mod_headers.c>
        Header always set Referrer-Policy "no-referrer"
    </IfModule>
    
    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF
    
    # Enable the site
    a2ensite "$(basename "${vhost_file}")" >/dev/null
    
    log_success "Apache virtual host configured"
    return 0
}

# Function to configure Apache security settings
configure_apache_security() {
    log_info "Configuring Apache security settings..."
    
    # Enable required modules
    a2enmod rewrite headers env dir mime setenvif ssl >/dev/null
    a2enmod proxy_fcgi >/dev/null
    a2enmod proxy >/dev/null
    a2enmod http2 >/dev/null
    
    # Configure MPM Event
    if [ -f "/etc/apache2/mods-available/mpm_event.conf" ]; then
        sed -i 's/^#\(.*\)$/\1/' /etc/apache2/mods-available/mpm_event.conf
    fi
    
    # Configure security headers
    if [ ! -f "/etc/apache2/conf-available/security-headers.conf" ]; then
        cat > /etc/apache2/conf-available/security-headers.conf << 'EOF'
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set X-Robots-Tag "none"
    Header always set X-Download-Options "noopen"
    Header always set X-Permitted-Cross-Domain-Policies "none"
    Header always set Referrer-Policy "no-referrer"
    Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"
</IfModule>
EOF
        a2enconf security-headers >/dev/null
    fi
    
    log_success "Apache security settings configured"
    return 0
}

# Function to restart services
restart_services() {
    log_info "Restarting services..."
    
    # Restart PHP-FPM
    if ! systemctl restart "${PHP_FPM_SERVICE}"; then
        log_warning "Failed to restart PHP-FPM service"
        return 1
    fi
    
    # Restart Apache
    if ! systemctl restart apache2; then
        log_error "Failed to restart Apache"
        return 1
    fi
    
    log_success "Services restarted successfully"
    return 0
}

# Main configuration function
configure_apache() {
    log_info "Starting Apache and PHP-FPM configuration..."
    
    # Verify prerequisites
    if ! verify_prerequisites; then
        log_error "Prerequisites check failed"
        return 1
    fi
    
    # Configure PHP-FPM pool
    if ! configure_php_fpm; then
        log_error "Failed to configure PHP-FPM pool"
        return 1
    fi
    
    # Configure Apache virtual host
    if ! configure_apache_vhost; then
        log_error "Failed to configure Apache virtual host"
        return 1
    fi
    
    # Configure Apache security settings
    if ! configure_apache_security; then
        log_warning "Failed to configure all security settings, continuing..."
    fi
    
    # Restart services
    if ! restart_services; then
        log_error "Failed to restart services"
        return 1
    fi
    
    log_success "Apache and PHP-FPM configuration completed successfully"
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    configure_apache
    exit $?
fi