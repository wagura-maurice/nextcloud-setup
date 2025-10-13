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
        log_error "Apache is not installed. Please run the installation script first."
        return 1
    fi
    
    # Verify PHP-FPM is installed and running
    if ! systemctl is-active --quiet "${PHP_FPM_SERVICE}"; then
        log_error "${PHP_FPM_SERVICE} is not running. Please install and start it first."
        return 1
    fi
    
    # Verify Nextcloud directory exists
    if [ ! -d "${NEXTCLOUD_ROOT}" ]; then
        log_error "Nextcloud directory not found at ${NEXTCLOUD_ROOT}"
        return 1
    fi
    
    return 0
}

# Function to configure PHP-FPM pool
configure_php_fpm() {
    log_info "Configuring PHP-FPM pool for Nextcloud..."
    
    # Create backup of existing config if it exists
    if [ -f "${PHP_POOL_DIR}/nextcloud.conf" ]; then
        cp -f "${PHP_POOL_DIR}/nextcloud.conf" "${PHP_POOL_DIR}/nextcloud.conf.bak"
    fi
    
    # Create PHP-FPM pool configuration
    cat > "${PHP_POOL_DIR}/nextcloud.conf" <<EOF
; Nextcloud PHP-FPM Pool Configuration
; Managed by Nextcloud setup script - DO NOT EDIT MANUALLY

[nextcloud]
user = www-data
group = www-data
listen = /run/php/php${PHP_VERSION}-fpm-nextcloud.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

; Process manager configuration
pm = dynamic
pm.max_children = $(get_config "PHP_PM_MAX_CHILDREN" "50")
pm.start_servers = $(get_config "PHP_PM_START_SERVERS" "5")
pm.min_spare_servers = $(get_config "PHP_PM_MIN_SPARE_SERVERS" "5")
pm.max_spare_servers = $(get_config "PHP_PM_MAX_SPARE_SERVERS" "35")
pm.max_requests = $(get_config "PHP_PM_MAX_REQUESTS" "500")

; PHP settings
php_admin_value[memory_limit] = ${MEMORY_LIMIT}
php_admin_value[upload_max_filesize] = ${UPLOAD_MAX_SIZE}
php_admin_value[post_max_size] = ${UPLOAD_MAX_SIZE}
php_admin_value[max_execution_time] = $(get_config "PHP_MAX_EXECUTION_TIME" "3600")
php_admin_value[max_input_time] = $(get_config "PHP_MAX_INPUT_TIME" "3600")
php_admin_value[output_buffering] = 0

; OPcache settings
php_admin_value[opcache.enable] = 1
php_admin_value[opcache.interned_strings_buffer] = 8
php_admin_value[opcache.max_accelerated_files] = 10000
php_admin_value[opcache.memory_consumption] = 128
php_admin_value[opcache.save_comments] = 1
php_admin_value[opcache.revalidate_freq] = 1
php_admin_value[opcache.validate_timestamps] = 1

; File upload settings
php_admin_value[upload_tmp_dir] = ${NEXTCLOUD_ROOT}/tmp
php_admin_value[session.save_path] = ${NEXTCLOUD_ROOT}/data/sessions

; Error handling
php_admin_flag[log_errors] = on
php_admin_value[error_log] = /var/log/php${PHP_VERSION}-fpm-nextcloud-error.log
php_admin_value[error_reporting] = E_ALL & ~E_DEPRECATED & ~E_STRICT
php_admin_value[display_errors] = Off
php_admin_value[display_startup_errors] = Off
php_admin_value[log_errors_max_len] = 0

; Security
php_admin_value[expose_php] = Off
php_admin_flag[file_uploads] = On
php_admin_flag[allow_url_fopen] = Off
php_admin_flag[allow_url_include] = Off

; Session settings
php_admin_value[session.gc_maxlifetime] = 3600
php_admin_value[session.cookie_httponly] = 1
php_admin_value[session.cookie_secure] = 1
php_admin_value[session.use_strict_mode] = 1
php_admin_value[session.cookie_samesite] = Lax
EOF

    # Set correct permissions
    chmod 0644 "${PHP_POOL_DIR}/nextcloud.conf"
    
    log_info "PHP-FPM pool configuration created at ${PHP_POOL_DIR}/nextcloud.conf"
    return 0
}
# Function to configure Apache virtual host
configure_apache_vhost() {
    log_info "Configuring Apache virtual host for ${DOMAIN}..."
    
    local vhost_file="${APACHE_SITES_AVAILABLE}/nextcloud.conf"
    
    # Create backup of existing config if it exists
    if [ -f "${vhost_file}" ]; then
        cp -f "${vhost_file}" "${vhost_file}.bak"
    fi
    
    # Create Apache virtual host configuration
    cat > "${vhost_file}" <<EOF
# Nextcloud Apache Configuration
# Managed by Nextcloud setup script - DO NOT EDIT MANUALLY

<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAdmin webmaster@${DOMAIN}
    DocumentRoot ${NEXTCLOUD_ROOT}
    
    # Enable HTTP/2
    Protocols h2 http/1.1
    
    # Security headers
    Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains; preload"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set X-Robots-Tag "none"
    Header always set X-Download-Options "noopen"
    Header always set X-Permitted-Cross-Domain-Policies "none"
    Header always set Referrer-Policy "no-referrer"
    
    # Disable directory listing
    Options -Indexes
    
    # Basic settings
    <Directory "${NEXTCLOUD_ROOT}">
        Require all granted
        Options FollowSymLinks MultiViews
        AllowOverride All
        
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
        
        SetEnv HOME ${NEXTCLOUD_ROOT}
        SetEnv HTTP_HOME ${NEXTCLOUD_ROOT}
    </Directory>
    
    # Configure PHP-FPM
    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php${PHP_VERSION}-fpm-nextcloud.sock|fcgi://localhost"
    </FilesMatch>
    
    # Set upload limit
    LimitRequestBody 0
    
    # Logging
    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
    
    # Redirect to HTTPS if enabled
    RewriteEngine On
    RewriteCond %{HTTPS} off [OR]
    RewriteCond %{HTTP:X-Forwarded-Proto} =http
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
</VirtualHost>

# HTTPS configuration
<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerName ${DOMAIN}
        ServerAdmin webmaster@${DOMAIN}
        DocumentRoot ${NEXTCLOUD_ROOT}
        
        # SSL configuration
        SSLEngine on
        SSLCertificateFile      /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
        SSLCertificateKeyFile   /etc/letsencrypt/live/${DOMAIN}/privkey.pem
        
        # Enable HTTP/2
        Protocols h2 http/1.1
        
        # Security headers (same as HTTP)
        Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains; preload"
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-XSS-Protection "1; mode=block"
        Header always set X-Robots-Tag "none"
        Header always set X-Download-Options "noopen"
        Header always set X-Permitted-Cross-Domain-Policies "none"
        Header always set Referrer-Policy "no-referrer"
        
        # Basic settings (same as HTTP)
        <Directory "${NEXTCLOUD_ROOT}">
            Require all granted
            Options FollowSymLinks MultiViews
            AllowOverride All
            
            <IfModule mod_dav.c>
                Dav off
            </IfModule>
            
            SetEnv HOME ${NEXTCLOUD_ROOT}
            SetEnv HTTP_HOME ${NEXTCLOUD_ROOT}
        </Directory>
        
        # Configure PHP-FPM
        <FilesMatch \.php$>
            SetHandler "proxy:unix:/run/php/php${PHP_VERSION}-fpm-nextcloud.sock|fcgi://localhost"
        </FilesMatch>
        
        # Set upload limit
        LimitRequestBody 0
        
        # Logging
        ErrorLog \${APACHE_LOG_DIR}/nextcloud_ssl_error.log
        CustomLog \${APACHE_LOG_DIR}/nextcloud_ssl_access.log combined
    </VirtualHost>
</IfModule>
EOF

    # Enable required Apache modules
    local required_modules=(
        proxy_fcgi setenvif headers rewrite dir mime env
        ssl http2 deflate expires proxy proxy_http proxy_wstunnel
        remoteip reqtimeout
    )
    
    for module in "${required_modules[@]}"; do
        if ! a2enmod -q "${module}"; then
            log_warning "Failed to enable Apache module: ${module}"
        fi
    done
    
    # Enable the site
    if ! a2ensite -q nextcloud.conf; then
        log_error "Failed to enable Nextcloud site"
        return 1
    fi
    
    # Disable default site if it exists
    if [ -f "${APACHE_SITES_AVAILABLE}/000-default.conf" ]; then
        a2dissite -q 000-default.conf 2>/dev/null || true
    fi
    
    log_info "Apache virtual host configuration created at ${vhost_file}"
    return 0
}

# Function to configure Apache security settings
configure_apache_security() {
    log_info "Configuring Apache security settings..."
    
    local security_conf="/etc/apache2/conf-available/security-headers.conf"
    
    # Create security headers configuration
    cat > "${security_conf}" << 'EOF'
# Security Headers
<IfModule mod_headers.c>
    # HSTS (mod_headers is required)
    Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains; preload"
    
    # XSS Protection
    Header always set X-XSS-Protection "1; mode=block"
    
    # MIME-type sniffing protection
    Header always set X-Content-Type-Options "nosniff"
    
    # Clickjacking protection
    Header always set X-Frame-Options "SAMEORIGIN"
    
    # Content Security Policy
    Header always set Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:;"
    
    # Prevent MIME type sniffing
    Header always set X-Content-Type-Options "nosniff"
    
    # Disable server signature
    ServerSignature Off
    ServerTokens Prod
</IfModule>

# Disable directory listing
<Directory "/var/www">
    Options -Indexes
</Directory>

# Disable TRACE and TRACK HTTP methods
TraceEnable off
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteCond %{REQUEST_METHOD} ^(TRACE|TRACK)
    RewriteRule .* - [F]
</IfModule>
EOF
    
    # Enable the security configuration
    if ! a2enconf security-headers >/dev/null 2>&1; then
        log_warning "Failed to enable security headers configuration"
    fi
    
    # Configure mod_evasive for DDoS protection
    if [ -f "${APACHE_MODS_AVAILABLE}/evasive.conf" ]; then
        cat > "${APACHE_MODS_AVAILABLE}/evasive.conf" << 'EOF'
<IfModule mod_evasive20.c>
    DOSHashTableSize 3097
    DOSPageCount 5
    DOSSiteCount 50
    DOSPageInterval 1
    DOSSiteInterval 1
    DOSBlockingPeriod 60
    DOSEmailNotify admin@${DOMAIN}
    DOSLogDir /var/log/apache2/evasive
</IfModule>
EOF
        
        if ! a2enmod evasive >/dev/null 2>&1; then
            log_warning "Failed to enable mod_evasive"
        else
            mkdir -p /var/log/apache2/evasive
            chown -R www-data:www-data /var/log/apache2/evasive
        fi
    fi
    
    return 0
}

# Function to restart services
restart_services() {
    log_info "Restarting services..."
    
    # Reload systemd to pick up new service files
    systemctl daemon-reload
    
    # Restart PHP-FPM
    if ! systemctl restart "${PHP_FPM_SERVICE}"; then
        log_error "Failed to restart ${PHP_FPM_SERVICE}"
        journalctl -u "${PHP_FPM_SERVICE}" -n 50 --no-pager
        return 1
    fi
    
    # Test Apache configuration
    if ! apache2ctl -t; then
        log_error "Apache configuration test failed"
        return 1
    fi
    
    # Restart Apache
    if ! systemctl restart apache2; then
        log_error "Failed to restart Apache"
        journalctl -u apache2 -n 50 --no-pager
        return 1
    fi
    
    return 0
}

# Main configuration function
configure_apache() {
    local success=true
    
    if ! verify_prerequisites; then
        success=false
    fi
    
    if ! configure_php_fpm; then
        success=false
    fi
    
    if ! configure_apache_vhost; then
        success=false
    fi
    
    if ! configure_apache_security; then
        success=false
    fi
    
    if ! restart_services; then
        success=false
    fi
    
    # Final status
    if [ "${success}" = true ]; then
        log_success "Apache and PHP-FPM configuration completed successfully"
        log_info "Nextcloud should now be accessible at: https://${DOMAIN}"
        return 0
    else
        log_error "Apache and PHP-FPM configuration completed with errors"
        return 1
    fi
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
    DocumentRoot ${NEXTCLOUD_ROOT}
    
    <Directory ${NEXTCLOUD_ROOT}/>
        Require all granted
        Options FollowSymlinks
        AllowOverride All
        
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
        
        <IfModule mod_headers.c>
            Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains; preload"
        </IfModule>
        
        <FilesMatch \.php$>
            SetHandler "proxy:unix:/run/php/php${PHP_VERSION}-fpm-nextcloud.sock|fcgi://localhost/"
        </FilesMatch>
        
        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteRule .* - [env=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
        </IfModule>
    </Directory>

    # Security headers
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set X-Robots-Tag "none"
    
    # Performance optimizations
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/plain text/css application/json application/javascript text/xml application/xml text/x-component
    </IfModule>
    
    <IfModule mod_headers.c>
        Header unset ETag
    </IfModule>
    
    FileETag None
    
    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF

# Configure Apache MPM Event
log_info "Optimizing Apache MPM Event configuration..."
cat > /etc/apache2/mods-available/mpm_event.conf <<EOF
<IfModule mpm_event_module>
    StartServers             2
    MinSpareThreads         25
    MaxSpareThreads         75
    ThreadLimit             64
    ThreadsPerChild         25
    MaxRequestWorkers      150
    MaxConnectionsPerChild   0
</IfModule>
EOF

# Enable required Apache modules
log_info "Configuring Apache modules..."
a2enmod proxy_fcgi setenvif headers env rewrite mime dir mpm_event

# Enable site and disable default
log_info "Enabling Nextcloud site..."
a2dissite 000-default.conf 2>/dev/null || true
a2ensite nextcloud.conf

# Set proper permissions
log_info "Setting file permissions..."
chown -R www-data:www-data "$NEXTCLOUD_ROOT"
find "$NEXTCLOUD_ROOT" -type d -exec chmod 750 {} \;
find "$NEXTCLOUD_ROOT" -type f -exec chmod 640 {} \;

# Set PHP upload limits
log_info "Configuring PHP upload limits..."
cat > "${PHP_INI_DIR}/conf.d/30-nextcloud.ini" <<EOF
upload_max_filesize = 2G
post_max_size = 2G
memory_limit = 512M
max_execution_time = 3600
max_input_time = 3600
opcache.enable = 1
opcache.validate_timestamps = 1
opcache.revalidate_freq = 1
opcache.memory_consumption = 128
opcache.max_accelerated_files = 10000
opcache.jit = 1255
opcache.jit_buffer_size = 50M
EOF

# Restart services
log_info "Restarting services..."
systemctl restart "php${PHP_VERSION}-fpm" apache2

# Verify configuration
if ! systemctl is-active --quiet "php${PHP_VERSION}-fpm"; then
    log_error "PHP-FPM ${PHP_VERSION} failed to start"
    journalctl -u "php${PHP_VERSION}-fpm" -n 50 --no-pager
    exit 1
fi

if ! systemctl is-active --quiet apache2; then
    log_error "Apache failed to start"
    journalctl -u apache2 -n 50 --no-pager
    exit 1
fi

log_success "Web server and PHP-FPM configuration completed"
log_info "PHP-FPM socket: /run/php/php${PHP_VERSION}-fpm-nextcloud.sock"
log_info "PHP Version: $(php${PHP_VERSION} -r 'echo phpversion();')"
