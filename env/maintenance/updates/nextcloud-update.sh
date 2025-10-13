#!/bin/bash

# Nextcloud Update Script
# This script handles the update process for Nextcloud

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NEXTCLOUD_PATH="/var/www/nextcloud"
BACKUP_DIR="/var/backups/nextcloud"
LOG_FILE="/var/log/nextcloud/update-$(date +%Y%m%d).log"
PHP_PATH="/usr/bin/php"
OCC="$PHP_PATH $NEXTCLOUD_PATH/occ"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log messages
log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR" "This script must be run as root"
    exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Function to create backup
create_backup() {
    log "INFO" "Creating backup of Nextcloud..."
    
    # Backup Nextcloud directory
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/nextcloud-backup-$TIMESTAMP.tar.gz"
    
    # Put Nextcloud in maintenance mode
    sudo -u www-data $OCC maintenance:mode --on
    
    # Create backup
    tar -czf "$BACKUP_FILE" -C "$(dirname "$NEXTCLOUD_PATH")" "$(basename "$NEXTCLOUD_PATH")" \
        /etc/apache2/sites-available/nextcloud*.conf \
        /etc/php/8.4/fpm/pool.d/www.conf \
        /etc/php/8.4/mods-available/opcache.ini
    
    # Check if backup was successful
    if [ $? -eq 0 ]; then
        log "SUCCESS" "Backup created: $BACKUP_FILE"
    else
        log "ERROR" "Failed to create backup"
        exit 1
    fi
}

# Function to update Nextcloud
update_nextcloud() {
    log "INFO" "Starting Nextcloud update..."
    
    # Enable maintenance mode
    sudo -u www-data $OCC maintenance:mode --on
    
    # Update Nextcloud
    log "INFO" "Updating Nextcloud files..."
    cd "$NEXTCLOUD_PATH" || exit 1
    
    # Backup current version
    sudo -u www-data cp config/config.php "$BACKUP_DIR/config.php.bak"
    
    # Update files (assuming using git or tar)
    # For git:
    # git fetch --all
    # git checkout $(git describe --tags `git rev-list --tags --max-count=1`)
    
    # For tar:
    # wget https://download.nextcloud.com/server/releases/latest.tar.bz2
    # tar -xjf latest.tar.bz2 --strip-components=1 -C "$NEXTCLOUD_PATH"
    
    # Update database
    log "INFO" "Updating database..."
    sudo -u www-data $OCC upgrade
    
    # Update file cache
    log "INFO" "Updating file cache..."
    sudo -u www-data $OCC files:scan --all
    
    # Update themes and apps
    log "INFO" "Updating themes and apps..."
    sudo -u www-data $OCC app:update --all
    
    # Disable maintenance mode
    sudo -u www-data $OCC maintenance:mode --off
    
    log "SUCCESS" "Nextcloud update completed successfully"
}

# Function to check for updates
check_updates() {
    log "INFO" "Checking for Nextcloud updates..."
    
    # Get current version
    CURRENT_VERSION=$(sudo -u www-data $OCC status | grep "version" | awk '{print $3}')
    
    # Get latest version (this is a simplified example)
    # In a real scenario, you might want to use the Nextcloud API
    LATEST_VERSION=$(curl -s https://nextcloud.com/changelog/ | grep -oP 'Nextcloud \K[0-9.]+' | head -1)
    
    if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ] && [ -n "$LATEST_VERSION" ]; then
        log "INFO" "Update available: $CURRENT_VERSION -> $LATEST_VERSION"
        return 0
    else
        log "INFO" "Nextcloud is up to date ($CURRENT_VERSION)"
        return 1
    fi
}

# Function to update system packages
update_system() {
    log "INFO" "Updating system packages..."
    
    # Update package lists
    apt-get update -qq
    
    # Upgrade packages
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" upgrade
    
    # Clean up
    apt-get -y autoremove
    apt-get -y autoclean
    
    log "SUCCESS" "System packages updated"
}

# Main function
main() {
    log "INFO" "=== Starting Nextcloud Update Process ==="
    
    # Check for updates
    if check_updates; then
        log "WARNING" "Updates are available. Starting update process..."
        
        # Create backup before updating
        create_backup
        
        # Update system packages
        update_system
        
        # Update Nextcloud
        update_nextcloud
        
        # Restart services
        log "INFO" "Restarting services..."
        systemctl restart apache2
        systemctl restart php8.4-fpm
        systemctl restart redis-server
        
        log "SUCCESS" "=== Update completed successfully ==="
    else
        log "INFO" "No updates available. Exiting..."
    fi
    
    # Rotate logs
    logrotate -f /etc/logrotate.d/nextcloud
}

# Run main function
main "$@"
