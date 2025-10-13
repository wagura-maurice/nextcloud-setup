#!/bin/bash

# Nextcloud Restore Script
# This script handles the restore process for Nextcloud from a backup

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NEXTCLOUD_PATH="/var/www/nextcloud"
BACKUP_ROOT="/var/backups/nextcloud"
LOG_FILE="/var/log/nextcloud/restore-$(date +%Y%m%d).log"
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

# Check if backup file is provided
if [ $# -eq 0 ]; then
    log "ERROR" "No backup file specified"
    echo "Usage: $0 <backup-file.tar.gz>"
    exit 1
fi

BACKUP_FILE="$1"
RESTORE_DIR="/tmp/nextcloud-restore-$(date +%s)"

# Function to validate backup file
validate_backup() {
    log "INFO" "Validating backup file: $BACKUP_FILE"
    
    if [ ! -f "$BACKUP_FILE" ]; then
        log "ERROR" "Backup file not found: $BACKUP_FILE"
        exit 1
    fi
    
    # Check if tar.gz is valid
    if ! tar -tzf "$BACKUP_FILE" &>/dev/null; then
        log "ERROR" "Invalid backup file: $BACKUP_FILE"
        exit 1
    fi
    
    log "SUCCESS" "Backup file is valid"
}

# Function to extract backup
extract_backup() {
    log "INFO" "Extracting backup to $RESTORE_DIR..."
    mkdir -p "$RESTORE_DIR"
    
    if ! tar -xzf "$BACKUP_FILE" -C "$RESTORE_DIR" --strip-components=1; then
        log "ERROR" "Failed to extract backup"
        exit 1
    fi
    
    # Verify extracted files
    if [ ! -d "$RESTORE_DIR/nextcloud" ] || [ ! -d "$RESTORE_DIR/database" ]; then
        log "ERROR" "Invalid backup structure"
        exit 1
    fi
    
    log "SUCCESS" "Backup extracted successfully"
}

# Function to restore files
restore_files() {
    log "INFO" "Restoring Nextcloud files..."
    
    # Stop web server
    systemctl stop apache2
    
    # Backup current installation
    log "INFO" "Creating backup of current installation..."
    mv "$NEXTCLOUD_PATH" "${NEXTCLOUD_PATH}_backup_$(date +%Y%m%d%H%M%S)"
    
    # Restore files
    log "INFO" "Restoring files..."
    cp -a "$RESTORE_DIR/nextcloud" "$(dirname "$NEXTCLOUD_PATH")/"
    
    # Restore configuration
    if [ -f "$RESTORE_DIR/config/config.php" ]; then
        cp "$RESTORE_DIR/config/config.php" "$NEXTCLOUD_PATH/config/"
    fi
    
    # Set proper permissions
    chown -R www-data:www-data "$NEXTCLOUD_PATH"
    chmod -R 750 "$NEXTCLOUD_PATH"
    
    log "SUCCESS" "Files restored successfully"
}

# Function to restore database
restore_database() {
    log "INFO" "Restoring database..."
    
    # Get database credentials from restored config
    DB_NAME=$(grep "dbname" "$NEXTCLOUD_PATH/config/config.php" | awk -F"'" '{print $4}')
    DB_USER=$(grep "dbuser" "$NEXTCLOUD_PATH/config/config.php" | awk -F"'" '{print $4}')
    DB_PASS=$(grep "dbpassword" "$NEXTCLOUD_PATH/config/config.php" | awk -F"'" '{print $4}')
    
    # Find SQL file
    SQL_FILE=$(find "$RESTORE_DIR/database" -name "*.sql" | head -n 1)
    
    if [ -z "$SQL_FILE" ]; then
        log "ERROR" "No SQL file found in backup"
        exit 1
    fi
    
    # Drop and recreate database
    mysql -u "$DB_USER" -p"$DB_PASS" -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\`;"
    
    # Restore database
    if ! mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL_FILE"; then
        log "ERROR" "Failed to restore database"
        exit 1
    fi
    
    log "SUCCESS" "Database restored successfully"
}

# Function to clean up
cleanup() {
    log "INFO" "Cleaning up..."
    
    # Start services
    systemctl start apache2
    
    # Run Nextcloud maintenance
    log "INFO" "Running Nextcloud maintenance..."
    sudo -u www-data $OCC maintenance:mode --off
    sudo -u www-data $OCC maintenance:repair
    sudo -u www-data $OCC maintenance:data-fingerprint
    
    # Clean up temporary files
    if [ -d "$RESTORE_DIR" ]; then
        rm -rf "$RESTORE_DIR"
    fi
    
    log "SUCCESS" "Cleanup completed"
}

# Main function
main() {
    log "INFO" "=== Starting Nextcloud Restore Process ==="
    
    # Validate backup
    validate_backup
    
    # Extract backup
    extract_backup
    
    # Put Nextcloud in maintenance mode
    log "INFO" "Enabling maintenance mode..."
    sudo -u www-data $OCC maintenance:mode --on
    
    # Restore files and database
    restore_files
    restore_database
    
    # Clean up and finalize
    cleanup
    
    log "SUCCESS" "=== Restore completed successfully ==="
    log "INFO" "Nextcloud is now running from the restored backup"
}

# Run main function
main "$@"
