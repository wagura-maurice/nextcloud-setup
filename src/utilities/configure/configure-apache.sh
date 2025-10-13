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
    
    # Verify PHP-FPM is installed and running
    if ! command -v "php-fpm${PHP_VERSION}" >/dev/null 2>&1; then
        log_error "PHP-FPM ${PHP_VERSION} is not installed. Please install it first using install-php.sh"
        return 1
    fi
    
    # Verify PHP-FPM is running
    if ! systemctl is-active --quiet "php${PHP_VERSION}-fpm"; then
        log_error "PHP-FPM ${PHP_VERSION} is not running. Please start it with: systemctl start php${PHP_VERSION}-fpm"
        return 1
    }
    
    log_success "All prerequisites are met"
    return 0
}

# Function to verify PHP-FPM is properly configured
verify_php_fpm() {
    log_info "Verifying PHP-FPM configuration..."
    
    if ! systemctl is-active --quiet "php${PHP_VERSION}-fpm"; then
        log_error "PHP-FPM ${PHP_VERSION} is not running"
        return 1
    fi
    
    if [ ! -S "/run/php/php${PHP_VERSION}-fpm.sock" ]; then
        log_error "PHP-FPM socket not found"
        return 1
    fi
    
    log_success "PHP-FPM is properly configured"
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
    
    # Enable HTTP/2 if available
    Protocols h2 h2c http/1.1
    
    # Enable HTTP/2 Server Push
    H2Push on
    
    # Directory configuration
    <Directory ${NEXTCLOUD_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
        
        # Set environment variables
        SetEnv HOME ${NEXTCLOUD_ROOT}
        SetEnv HTTP_HOME ${NEXTCLOUD_ROOT}
        
        # PHP-FPM configuration
        <FilesMatch \.php$>
            SetHandler "proxy:unix:/run/php/php${PHP_VERSION}-fpm.sock|fcgi://localhost"
        </FilesMatch>
        
        # Enable .htaccess overrides
        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteRule .* - [env=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
            RewriteRule ^\.well-known/carddav /remote.php/dav/ [R=301,L]
            RewriteRule ^\.well-known/caldav /remote.php/dav/ [R=301,L]
        </IfModule>
    </Directory>
    
    # Security headers
    <IfModule mod_headers.c>
        Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains; preload"
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-XSS-Protection "1; mode=block"
        Header always set X-Robots-Tag "none"
        Header always set X-Download-Options "noopen"
        Header always set X-Permitted-Cross-Domain-Policies "none"
        Header always set Referrer-Policy "no-referrer"
        Header always set Permissions-Policy "camera=(), geolocation=(), microphone=()"
        Header always set Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:;"
    </IfModule>
    
    # Performance optimizations
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript
    </IfModule>
    
    <IfModule mod_expires.c>
        ExpiresActive on
        ExpiresDefault "access plus 1 month"
        ExpiresByType image/x-icon "access plus 1 year"
        ExpiresByType image/jpg "access plus 1 month"
        ExpiresByType image/jpeg "access plus 1 month"
        ExpiresByType image/gif "access plus 1 month"
        ExpiresByType image/png "access plus 1 month"
        ExpiresByType image/svg+xml "access plus 1 month"
        ExpiresByType text/css "access plus 1 month"
        ExpiresByType application/javascript "access plus 1 month"
    </IfModule>
    
    # Logging
    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
    
    # PHP settings
    php_value upload_max_filesize ${UPLOAD_MAX_SIZE}
    php_value post_max_size ${UPLOAD_MAX_SIZE}
    php_value memory_limit ${MEMORY_LIMIT}
    php_value max_execution_time 3600
    php_value max_input_time 3600
    php_value date.timezone UTC
    
    # Disable directory listing
    Options -Indexes
    
    # Enable keep-alive
    <IfModule mod_headers.c>
        Header set Connection keep-alive
    </IfModule>
</VirtualHost>

# HTTPS configuration - uncomment after setting up SSL
#<VirtualHost *:443>
#    ServerName ${DOMAIN}
#    ServerAdmin webmaster@${DOMAIN}
#    DocumentRoot ${NEXTCLOUD_ROOT}
#    
#    # SSL Configuration
#    SSLEngine on
#    SSLCertificateFile      /etc/ssl/certs/ssl-cert-snakeoil.pem
#    SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key
#    
#    # Rest of the configuration is the same as for port 80
#    Include ${APACHE_SITES_AVAILABLE}/nextcloud.conf
#</VirtualHost>
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