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

log_section "Nextcloud Configuration"

# Configuration
readonly NEXTCLOUD_ROOT="/var/www/nextcloud"
readonly NEXTCLOUD_USER="www-data"
readonly NEXTCLOUD_GROUP="www-data"
readonly DB_HOST="localhost"
readonly DB_NAME="nextcloud"
readonly DB_USER="nextcloud"
readonly DB_PASS=$(openssl rand -base64 32)
readonly ADMIN_USER="admin"
readonly ADMIN_PASS=$(openssl rand -base64 16)

# Function to configure database
configure_database() {
    log_info "Configuring database..."
    
    # Create database and user
    mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    log_success "Database configured"
    return 0
}

# Function to install Nextcloud
install_nextcloud() {
    log_info "Running Nextcloud installation..."
    
    # Run the installation
    sudo -u "$NEXTCLOUD_USER" php "${NEXTCLOUD_ROOT}/occ" maintenance:install \
        --database="mysql" \
        --database-name="$DB_NAME" \
        --database-user="$DB_USER" \
        --database-pass="$DB_PASS" \
        --database-host="$DB_HOST" \
        --admin-user="$ADMIN_USER" \
        --admin-pass="$ADMIN_PASS" \
        --data-dir="$NEXTCLOUD_DATA" || { log_error "Installation failed"; return 1; }
    
    log_success "Nextcloud installed successfully"
    return 0
}

# Function to configure Nextcloud
configure_nextcloud() {
    log_info "Configuring Nextcloud..."
    
    # Set trusted domains
    local domain=$(hostname -f)
    sudo -u "$NEXTCLOUD_USER" php "${NEXTCLOUD_ROOT}/occ" config:system:set trusted_domains 1 --value="$domain"
    
    # Configure caching
    sudo -u "$NEXTCLOUD_USER" php "${NEXTCLOUD_ROOT}/occ" config:system:set memcache.local --value="\\OC\\Memcache\\APCu"
    sudo -u "$NEXTCLOUD_USER" php "${NEXTCLOUD_ROOT}/occ" config:system:set memcache.distributed --value="\\OC\\Memcache\\Redis"
    sudo -u "$NEXTCLOUD_USER" php "${NEXTCLOUD_ROOT}/occ" config:system:set redis host --value="localhost"
    sudo -u "$NEXTCLOUD_USER" php "${NEXTCLOUD_ROOT}/occ" config:system:set redis port --value=6379
    
    # Enable default apps
    sudo -u "$NEXTCLOUD_USER" php "${NEXTCLOUD_ROOT}/occ" app:enable admin_audit
    sudo -u "$NEXTCLOUD_USER" php "${NEXTCLOUD_ROOT}/occ" app:enable files_external
    
    # Set secure permissions
    find "${NEXTCLOUD_ROOT}" -type d -exec chmod 750 {} \\;
    find "${NEXTCLOUD_ROOT}" -type f -exec chmod 640 {} \\;
    chmod 750 "${NEXTCLOUD_ROOT}/occ"
    
    log_success "Nextcloud configuration complete"
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    configure_database || exit 1
    install_nextcloud || exit 1
    configure_nextcloud || exit 1
    
    log_info "============================================"
    log_info "Nextcloud has been successfully configured!"
    log_info "Admin username: $ADMIN_USER"
    log_info "Admin password: $ADMIN_PASS"
    log_info "Database name: $DB_NAME"
    log_info "Database user: $DB_USER"
    log_info "Database password: $DB_PASS"
    log_info "============================================"
    
    exit 0
fi