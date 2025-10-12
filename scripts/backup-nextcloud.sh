#!/bin/bash

# Nextcloud Backup Script
# This script creates a complete backup of Nextcloud data, configuration, and database
# and uploads it to Cloudflare R2 storage

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Ensure logs directory exists
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"
chmod 750 "$LOG_DIR"

# Set up logging
LOG_FILE="$LOG_DIR/nextcloud-backup-$(date +%Y%m%d_%H%M%S).log"

# Function to log messages
log() {
    local level="$1"
    local message="${*:2}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to log and print status messages
print_status() {
    local message="$1"
    log "INFO" "$message"
    echo -e "\033[1;32m[+] $message\033[0m"
}

# Function to log and print error messages
print_error() {
    local message="$1"
    log "ERROR" "$message"
    echo -e "\e[31m[!] $message\e[0m"
}

# Function to log and print section headers
print_section() {
    local message="$1"
    log "SECTION" "$message"
    echo -e "\n=== $message ===\n"
}

# Log script start
log "INFO" "Starting Nextcloud backup process"
log "INFO" "Project root: $PROJECT_ROOT"
log "INFO" "Log file: $LOG_FILE"

# Configuration
CONFIG_DIR="$PROJECT_ROOT/temporary"
BACKUP_DIR="$PROJECT_ROOT/backups"
NEXTCLOUD_DIR="/var/www/nextcloud"
DATE=$(date +%Y%m%d_%H%M%S)

# Create necessary directories
mkdir -p "$CONFIG_DIR"
mkdir -p "$BACKUP_DIR"

# Log configuration
log "CONFIG" "Backup directory: $BACKUP_DIR"
log "CONFIG" "Nextcloud directory: $NEXTCLOUD_DIR"
log "CONFIG" "Configuration directory: $CONFIG_DIR"

# Load configurations
source "$CONFIG_DIR/.nextcloud_backup_config" 2>/dev/null || {
    echo "Error: Missing backup config at $CONFIG_DIR/.nextcloud_backup_config"
    exit 1
}

# Function to print status messages
print_status() {
    echo -e "\033[1;32m[+] $1\033[0m"
}

# Function to print error messages
print_error() {
    echo -e "\e[31m[!] $1\e[0m"
}

# Function to print section headers
print_section() {
    echo -e "\n\033[1;34m==> $1\033[0m"
}

# Load configuration
CONFIG_FILE="$(dirname "$0")/../configs/backup-config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Configuration file not found at $CONFIG_FILE"
    print_status "A template has been created at $CONFIG_FILE. Please edit it with your settings and try again."
    
    # Create a sample config file
    mkdir -p "$(dirname "$0")/../configs"
    cat > "$CONFIG_FILE" << 'EOL'
# Backup Configuration File
# This file contains sensitive information - keep it secure!

# Database Configuration
DB_NAME="nextcloud"
DB_USER="nextcloud"
DB_PASS="your_secure_db_password"

# Cloudflare R2 Configuration
R2_ACCESS_KEY_ID="your_r2_access_key_id"
R2_SECRET_ACCESS_KEY="your_r2_secret_access_key"
R2_BUCKET="your-r2-bucket-name"
R2_ENDPOINT="https://your-account-id.r2.cloudflarestorage.com"

# Local Backup Settings
BACKUP_DIR="/root/nextcloud-backups"

# Retention Policy (in days)
RETAIN_DAYS=30

# Notification Settings (optional)
# EMAIL_NOTIFY="admin@example.com"
# SLACK_WEBHOOK_URL=""

# Logging
LOG_FILE="/var/log/nextcloud/backup.log"
LOG_LEVEL="INFO"  # DEBUG, INFO, WARNING, ERROR

# Maintenance Mode
MAINTENANCE_MODE="true"

# What to back up (set to "true" to include, "false" to exclude)
BACKUP_DATA=true
BACKUP_CONFIG=true
BACKUP_APPS=true
BACKUP_DATABASE=true
BACKUP_REDIS=false

# Compression level (1-9, where 1 is fastest, 9 is best compression)
COMPRESSION_LEVEL=6
EOL
    
    chmod 600 "$CONFIG_FILE"
    print_status "Sample configuration file created at $CONFIG_FILE"
    exit 1
fi

# Source the configuration file
source "$CONFIG_FILE"
print_status "Loaded configuration from $CONFIG_FILE"

# Validate required variables
if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "DB_PASS" ]; then
    print_error "Database credentials are not properly set in $CONFIG_FILE"
    exit 1
fi

if [ -z "$R2_ACCESS_KEY_ID" ] || [ -z "$R2_SECRET_ACCESS_KEY" ] || [ -z "$R2_BUCKET" ] || [ -z "$R2_ENDPOINT" ]; then
    print_error "Cloudflare R2 configuration is not properly set in $CONFIG_FILE"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_status "Installing AWS CLI..."
    apt-get update
    apt-get install -y awscli
    if [ $? -ne 0 ]; then
        print_error "Failed to install AWS CLI. Please install it manually and try again."
        exit 1
    fi
fi

# Configure AWS CLI for R2
if [ ! -f "/root/.aws/credentials" ]; then
    mkdir -p /root/.aws
    cat > "/root/.aws/credentials" << EOL
[default]
aws_access_key_id = ${R2_ACCESS_KEY_ID}
aws_secret_access_key = ${R2_SECRET_ACCESS_KEY}
EOL
    
    cat > "/root/.aws/config" << EOL
[default]
region = auto
EOL
    
    chmod 600 /root/.aws/credentials
    chmod 600 /root/.aws/config
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Find the latest backup for incremental backup
LATEST_BACKUP=$(ls -td "$BACKUP_DIR"/nextcloud_backup_* 2>/dev/null | head -1)

# Create backup directory for this specific backup
if [ -z "$LATEST_BACKUP" ] || [ "$FORCE_FULL_BACKUP" = "true" ]; then
    # Full backup
    BACKUP_NAME="nextcloud_backup_${DATE}_full"
    BACKUP_TYPE="full"
    print_status "Creating new full backup: $BACKUP_NAME"
else
    # Incremental backup
    BACKUP_NAME="nextcloud_backup_${DATE}_incr"
    BACKUP_TYPE="incremental"
    print_status "Creating incremental backup from: $(basename "$LATEST_BACKUP")"
fi

BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
mkdir -p "$BACKUP_PATH"

# Create a file to store backup metadata
cat > "$BACKUP_PATH/backup_metadata" << EOL
BACKUP_DATE=$(date +%Y-%m-%dT%H:%M:%S%z)
BACKUP_TYPE=$BACKUP_TYPE
BASE_BACKUP=$(basename "$LATEST_BACKUP" 2>/dev/null || echo "none")
EOL

print_section "Starting Nextcloud Backup Process"

# 1. Stop Nextcloud cron jobs to ensure data consistency
print_status "Stopping Nextcloud cron jobs..."
systemctl stop nextcloudcron.timer 2>/dev/null || true
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on 2>/dev/null || true

# 2. Backup Nextcloud configuration
print_status "Backing up Nextcloud configuration..."
if [ -d "/var/www/nextcloud/config" ]; then
    if [ "$BACKUP_TYPE" = "full" ]; then
        # Full copy for full backup
        cp -a "/var/www/nextcloud/config" "$BACKUP_PATH/"
    else
        # Rsync for incremental backup
        rsync -a --delete --link-dest="$LATEST_BACKUP/config" \
            "/var/www/nextcloud/config/" "$BACKUP_PATH/config/"
    fi
    print_status "Configuration backed up successfully"
else
    print_error "Nextcloud config directory not found"
fi

# 3. Backup Nextcloud data directory (exclude cache and temporary files)
print_status "Backing up Nextcloud data directory..."
if [ -d "/var/www/nextcloud/data" ]; then
    if [ "$BACKUP_TYPE" = "full" ]; then
        # Full copy for full backup
        rsync -a --exclude='*/cache/*' --exclude='*/appdata_*/preview/*' \
            --exclude='*/files_*/cache/*' --exclude='*/updater*' \
            "/var/www/nextcloud/data/" "$BACKUP_PATH/data/"
    else
        # Rsync with hard links for incremental backup
        rsync -a --delete --link-dest="$LATEST_BACKUP/data" \
            --exclude='*/cache/*' --exclude='*/appdata_*/preview/*' \
            --exclude='*/files_*/cache/*' --exclude='*/updater*' \
            "/var/www/nextcloud/data/" "$BACKUP_PATH/data/"
    fi
    print_status "Data directory backed up successfully"
else
    print_error "Nextcloud data directory not found"
fi

# 4. Backup Nextcloud apps directory (custom apps)
print_status "Backing up Nextcloud apps directory..."
if [ -d "/var/www/nextcloud/apps" ]; then
    if [ "$BACKUP_TYPE" = "full" ]; then
        # Full copy for full backup
        cp -a "/var/www/nextcloud/apps" "$BACKUP_PATH/"
    else
        # Rsync with hard links for incremental backup
        rsync -a --delete --link-dest="$LATEST_BACKUP/apps" \
            "/var/www/nextcloud/apps/" "$BACKUP_PATH/apps/"
    fi
    print_status "Apps directory backed up successfully"
else
    print_status "Nextcloud apps directory not found, skipping..."
fi

# 5. Backup the database
print_status "Backing up Nextcloud database..."
if command -v mysqldump &> /dev/null; then
    # Always do a full database dump
    mysqldump --single-transaction --quick -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_PATH/nextcloud_db_backup.sql"
    if [ $? -eq 0 ]; then
        print_status "Database backed up successfully"
    else
        print_error "Database backup failed"
    fi
else
    print_error "mysqldump command not found"
fi

# 6. Backup Apache configuration
print_status "Backing up Apache configuration..."
if [ -f "/etc/apache2/sites-available/000-default.conf" ]; then
    cp /etc/apache2/sites-available/000-default.conf "$BACKUP_PATH/apache_config.conf"
fi

if [ -f "/etc/apache2/sites-available/000-default-le-ssl.conf" ]; then
    cp /etc/apache2/sites-available/000-default-le-ssl.conf "$BACKUP_PATH/apache_ssl_config.conf"
fi

if [ -f "/etc/apache2/sites-available/nextcloud-ssl.conf" ]; then
    cp /etc/apache2/sites-available/nextcloud-ssl.conf "$BACKUP_PATH/nextcloud_ssl_config.conf"
fi

print_status "Apache configuration backed up"

# 7. Backup PHP configuration
print_status "Backing up PHP configuration..."
if [ -d "/etc/php/8.4/fpm/conf.d/" ]; then
    cp -r /etc/php/8.4/fpm/conf.d/nextcloud.ini "$BACKUP_PATH/" 2>/dev/null || true
    cp -r /etc/php/8.4/fpm/conf.d/20-redis-session.ini "$BACKUP_PATH/" 2>/dev/null || true
fi

print_status "PHP configuration backed up"

# 8. Backup Redis configuration
print_status "Backing up Redis configuration..."
if [ -f "/etc/redis/redis.conf" ]; then
    cp /etc/redis/redis.conf "$BACKUP_PATH/redis.conf"
    print_status "Redis configuration backed up"
fi

# 9. Create a backup info file
print_status "Creating backup information file..."
cat > "$BACKUP_PATH/backup_info.txt" << EOL
Nextcloud Backup Information
===========================
Backup Date: $(date)
Backup Directory: $BACKUP_PATH
Database Name: $DB_NAME
Database User: $DB_USER
Nextcloud Version: $(sudo -u www-data php /var/www/nextcloud/occ status 2>/dev/null | grep "version" | awk '{print $3}' || echo "Unknown")
EOL

# 10. Create a tar.gz archive of the backup
print_status "Creating compressed backup archive..."
cd "$BACKUP_DIR"
tar -czf "nextcloud_backup_$DATE.tar.gz" --exclude="*/appdata_*/preview/*" --exclude="*/updater*" --exclude="*/files_*/cache/*" --exclude="*/files_*/files_trashbin/*" --exclude="*/files_*/files_versions/*" --exclude="*/files_*/upload/*" --exclude="*/cache/*" --exclude="*/tmp/*" --exclude="*/thumbnails/*" "$BACKUP_NAME"
BACKUP_ARCHIVE="$BACKUP_DIR/nextcloud_backup_$DATE.tar.gz"

# 11. Calculate backup size and verify integrity
BACKUP_SIZE=$(du -h "$BACKUP_ARCHIVE" | cut -f1)
print_status "Backup size: $BACKUP_SIZE"

# Verify the backup archive
print_status "Verifying backup integrity..."
if ! gzip -t "$BACKUP_ARCHIVE"; then
    print_error "Backup archive is corrupted!"
    exit 1
fi

# 12. Clean up temporary backup directory
rm -rf "$BACKUP_PATH"

# 13. Upload backup to Cloudflare R2
print_status "Uploading backup to Cloudflare R2..."
UPLOAD_START=$(date +%s)

# Create a checksum file
BACKUP_CHECKSUM=$(sha256sum "$BACKUP_ARCHIVE" | awk '{print $1}')
echo "$BACKUP_CHECKSUM $(basename "$BACKUP_ARCHIVE")" > "${BACKUP_ARCHIVE}.sha256"

# Upload the backup file to R2
print_status "Uploading backup file..."
if ! aws s3 cp "$BACKUP_ARCHIVE" "s3://${R2_BUCKET}/" \
    --endpoint-url "${R2_ENDPOINT}" \
    --region auto; then
    print_error "Failed to upload backup to R2"
    exit 1
fi

# Upload the checksum file
print_status "Uploading checksum file..."
if ! aws s3 cp "${BACKUP_ARCHIVE}.sha256" "s3://${R2_BUCKET}/" \
    --endpoint-url "${R2_ENDPOINT}" \
    --region auto; then
    print_error "Failed to upload checksum file to R2"
    # Continue even if checksum upload fails
fi

if [ $? -eq 0 ]; then
    UPLOAD_END=$(date +%s)
    UPLOAD_TIME=$((UPLOAD_END - UPLOAD_START))
    print_status "Backup uploaded to Cloudflare R2 in ${UPLOAD_TIME} seconds"
    
    # Clean up local backup if upload was successful
    print_status "Cleaning up local backup file..."
    rm -f "$BACKUP_ARCHIVE"
    print_status "Local backup file removed"
else
    print_error "Failed to upload backup to Cloudflare R2"
    print_status "Local backup file kept at: $BACKUP_ARCHIVE"
fi

# 14. Clean up old backups using a rotation scheme
if [ -n "$RETAIN_DAYS" ] && [ "$RETAIN_DAYS" -gt 0 ]; then
    print_status "Cleaning up old backups (keeping last $RETAIN_DAYS days)..."
    
    # Keep all backups from the last 7 days
    find "$BACKUP_DIR" -maxdepth 1 -type d -name "nextcloud_backup_*" -mtime +7 -exec ls -td {} + | tail -n +$((RETAIN_DAYS + 1)) | xargs -r rm -rf
    
    # Keep only full backups older than 7 days
    find "$BACKUP_DIR" -maxdepth 1 -type d -name "nextcloud_backup_*_full" -mtime +7 | sort -r | tail -n +2 | xargs -r rm -rf
    
    # Remove any incremental backups that don't have a corresponding full backup
    for backup in "$BACKUP_DIR"/nextcloud_backup_*_incr; do
        if [ -d "$backup" ]; then
            base_backup=$(grep '^BASE_BACKUP=' "$backup/backup_metadata" | cut -d'=' -f2-)
            if [ ! -d "$BACKUP_DIR/$base_backup" ]; then
                print_status "Removing orphaned incremental backup: $(basename "$backup")"
                rm -rf "$backup"
            fi
        fi
    done
fi

# 15. Restart Nextcloud services
if [ "$MAINTENANCE_MODE" = "true" ]; then
    print_status "Taking Nextcloud out of maintenance mode..."
    sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off 2>/dev/null || true
fi

print_status "Restarting Nextcloud services..."
systemctl start nextcloudcron.timer 2>/dev/null || true
systemctl restart apache2 2>/dev/null || true
systemctl restart php8.4-fpm 2>/dev/null || true

# 16. Send notification if configured
if [ -n "$EMAIL_NOTIFY" ]; then
    echo "Nextcloud backup completed successfully at $(date)" | mail -s "Nextcloud Backup Status - Success" "$EMAIL_NOTIFY"
elif [ -n "$SLACK_WEBHOOK_URL" ]; then
    curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"✅ Nextcloud backup completed successfully at $(date)\"}" "$SLACK_WEBHOOK_URL"
fi

print_section "Backup Process Completed"

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    NEXTCLOUD BACKUP COMPLETED SUCCESSFULLY                 ║"
echo "╠════════════════════════════════════════════════════════════════════════════╣"
printf "║  %-15s %-60s ║\n" "📅 Backup Date:" "$(date)"
printf "║  %-15s %-60s ║\n" "📦 Archive:" "$(basename "$BACKUP_ARCHIVE")"
printf "║  %-15s %-60s ║\n" "💾 Size:" "$BACKUP_SIZE"
printf "║  %-15s %-60s ║\n" "🌐 R2 Bucket:" "${R2_BUCKET}"
printf "║  %-15s %-60s ║\n" "📁 Local Dir:" "$BACKUP_DIR"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

print_status "Backup completed and uploaded to Cloudflare R2: s3://${R2_BUCKET}/$(basename "$BACKUP_ARCHIVE")"
print_status "To restore this backup, use the restore script with the backup filename."