#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Configuring Web Server"

# Set default values
DOMAIN="${DOMAIN:-localhost}"
NEXTCLOUD_ROOT="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"

# Create Apache configuration
log_info "Creating Apache site configuration..."
cat > /etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    DocumentRoot ${NEXTCLOUD_ROOT}
    
    <Directory ${NEXTCLOUD_ROOT}/>
        Require all granted
        Options FollowSymlinks
        AllowOverride All
        
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF

# Enable site and disable default
log_info "Enabling Nextcloud site..."
a2dissite 000-default.conf 2>/dev/null || true
a2ensite nextcloud.conf

# Set proper permissions
log_info "Setting file permissions..."
chown -R www-data:www-data "$NEXTCLOUD_ROOT"
find "$NEXTCLOUD_ROOT" -type d -exec chmod 750 {} \;
find "$NEXTCLOUD_ROOT" -type f -exec chmod 640 {} \;

# Restart Apache
log_info "Restarting Apache..."
systemctl restart apache2

log_success "Web server configuration completed"
