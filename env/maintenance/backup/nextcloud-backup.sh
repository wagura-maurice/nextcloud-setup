#!/bin/bash

# Nextcloud Backup Script
# This script handles the backup process for Nextcloud

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NEXTCLOUD_PATH="/var/www/nextcloud"
BACKUP_ROOT="/var/backups/nextcloud"
LOG_FILE="/var/log/nextcloud/backup-$(date +%Y%m%d).log"
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

# Create backup directory with timestamp
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/nextcloud-backup-$TIMESTAMP"

# Function to create directory structure
create_backup_structure() {
    log "INFO" "Creating backup directory structure..."
    mkdir -p "$BACKUP_DIR/nextcloud"
    mkdir -p "$BACKUP_DIR/database"
    mkdir -p "$BACKUP_DIR/config"
}

# Function to backup Nextcloud files
backup_nextcloud() {
    log "INFO" "Backing up Nextcloud files..."
    rsync -Aavx "$NEXTCLOUD_DIR/" "$BACKUP_DIR/nextcloud/"
    
    # Backup configuration
    cp -a "$NEXTCLOUD_DIR/config/config.php" "$BACKUP_DIR/config/"
    cp -a "/etc/apache2/sites-available/nextcloud.conf" "$BACKUP_DIR/config/" 2>/dev/null || true
    cp -a "/etc/php/8.4/fpm/pool.d/www.conf" "$BACKUP_DIR/config/" 2>/dev/null || true
}

# Function to backup database
backup_database() {
    log "INFO" "Backing up database..."
    # Get database credentials from Nextcloud config
    DB_NAME=$(grep "dbname" "$NEXTCLOUD_DIR/config/config.php" | awk -F"'" '{print $4}')
    DB_USER=$(grep "dbuser" "$NEXTCLOUD_DIR/config/config.php" | awk -F"'" '{print $4}')
    DB_PASS=$(grep "dbpassword" "$NEXTCLOUD_DIR/config/config.php" | awk -F"'" '{print $4}')
    
    # Perform the backup
    mysqldump --single-transaction -h localhost -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_DIR/database/nextcloud-sqlbkp_$(date +"%Y%m%d").sql"
    
    # Verify the backup
    if [ -s "$BACKUP_DIR/database/nextcloud-sqlbkp_$(date +"%Y%m%d").sql" ]; then
        log "SUCCESS" "Database backup completed successfully"
    else
        log "ERROR" "Database backup failed"
        exit 1
    fi
}

# Function to create archive
create_archive() {
    log "INFO" "Creating backup archive..."
    cd "$BACKUP_ROOT"
    tar -czf "nextcloud-backup-$TIMESTAMP.tar.gz" "nextcloud-backup-$TIMESTAMP"
    
    # Remove the uncompressed backup
    rm -rf "$BACKUP_DIR"
    
    log "SUCCESS" "Backup created: $BACKUP_ROOT/nextcloud-backup-$TIMESTAMP.tar.gz"
}

# Main function
main() {
    log "INFO" "=== Starting Nextcloud Backup Process ==="
    
    # Put Nextcloud in maintenance mode
    log "INFO" "Enabling maintenance mode..."
    sudo -u www-data $OCC maintenance:mode --on
    
    # Create backup structure
    create_backup_structure
    
    # Perform backups
    backup_nextcloud
    backup_database
    
    # Create final archive
    create_archive
    
    # Disable maintenance mode
    log "INFO" "Disabling maintenance mode..."
    sudo -u www-data $OCC maintenance:mode --off
    
    log "SUCCESS" "=== Backup completed successfully ==="
}

# Run main function
main "$@"
