#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Configuring Apache Web Server"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Set default values
export DOMAIN="${DOMAIN:-localhost}"
export NEXTCLOUD_ROOT="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"
PHP_VERSION="8.4"

# Verify Apache is installed
if ! command -v apache2 >/dev/null 2>&1; then
    log_error "Apache is not installed. Please run the installation script first."
    exit 1
fi

# Configure Apache MPM Event
log_info "Configuring Apache MPM Event..."
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
log_info "Enabling required Apache modules..."
a2enmod rewrite headers env dir mime ssl http2 proxy_fcgi setenvif

# Disable default site
log_info "Disabling default site..."
a2dissite 000-default.conf 2>/dev/null || true

# Create Apache virtual host configuration
log_info "Configuring Apache virtual host..."
cat > /etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAdmin webmaster@${DOMAIN}
    DocumentRoot ${NEXTCLOUD_ROOT}
    
    # Redirect all HTTP to HTTPS
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
    
    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName ${DOMAIN}
    ServerAdmin webmaster@${DOMAIN}
    DocumentRoot ${NEXTCLOUD_ROOT}
    
    # SSL Configuration
    SSLEngine on
    SSLCertificateFile      /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
    SSLCertificateKeyFile   /etc/letsencrypt/live/${DOMAIN}/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf
    
    # Enable HTTP/2
    Protocols h2 http/1.1
    
    <Directory ${NEXTCLOUD_ROOT}/>
        Require all granted
        Options FollowSymlinks
        AllowOverride All
        
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
        
        <IfModule mod_headers.c>
            Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains; preload"
            Header always set X-Content-Type-Options "nosniff"
            Header always set X-Frame-Options "SAMEORIGIN"
            Header always set X-XSS-Protection "1; mode=block"
            Header always set X-Robots-Tag "none"
            Header always set Referrer-Policy "no-referrer"
            Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"
            Header unset ETag
        </IfModule>
        
        <FilesMatch \.php$>
            SetHandler "proxy:unix:/run/php/php${PHP_VERSION}-fpm-nextcloud.sock|fcgi://localhost/"
        </FilesMatch>
        
        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteRule .* - [env=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
        </IfModule>
    </Directory>
    
    # Performance optimizations
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/plain text/css application/json application/javascript text/xml application/xml text/x-component
    </IfModule>
    
    FileETag None
    
    ErrorLog \${APACHE_LOG_DIR}/nextcloud_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_ssl_access.log combined
</VirtualHost>
