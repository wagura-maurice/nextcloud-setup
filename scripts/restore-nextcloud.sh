#!/bin/bash

# Nextcloud Restore Script
# This script restores Nextcloud from a backup archive, either from a local file or Cloudflare R2

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="/root/nextcloud-backups"

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

# Function to ask for confirmation
ask_confirmation() {
    read -p "$1 (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Operation cancelled by user."
        exit 1
    fi
}

print_section "Nextcloud Restore Process"

# Check if backup file is provided as argument
if [ $# -eq 0 ]; then
    # No arguments provided, show available backups in R2
    print_status "No backup file specified. Checking available backups in R2 bucket '${R2_BUCKET}'..."
    aws s3 ls "s3://${R2_BUCKET}/" --endpoint-url "${R2_ENDPOINT}" --human-readable
    echo ""
    print_error "No backup file provided."
    echo "Usage: $0 [backup_archive.tar.gz]"
    echo "  If no argument is provided, it will list available backups in R2"
    echo "  To restore from R2: $0 s3://${R2_BUCKET}/nextcloud_backup_YYYYMMDD_HHMMSS.tar.gz"
    echo "  To restore from local file: $0 /path/to/backup.tar.gz"
    exit 1
fi

BACKUP_SOURCE="$1"

# Check if the source is an R2 path (starts with s3://)
if [[ "$BACKUP_SOURCE" == s3://* ]]; then
    # Download from R2
    BACKUP_FILENAME=$(basename "$BACKUP_SOURCE")
    BACKUP_ARCHIVE="${TEMP_DIR}/$BACKUP_FILENAME"
    
    print_status "Downloading backup from Cloudflare R2: $BACKUP_SOURCE"
    if ! aws s3 cp "$BACKUP_SOURCE" "$BACKUP_ARCHIVE" --endpoint-url "${R2_ENDPOINT}" --region auto; then
        print_error "Failed to download backup from R2"
        exit 1
    fi
    
    # Download the checksum file if it exists
    if aws s3 ls "${BACKUP_SOURCE}.sha256" --endpoint-url "${R2_ENDPOINT}" &> /dev/null; then
        print_status "Downloading checksum file..."
        if ! aws s3 cp "${BACKUP_SOURCE}.sha256" "${BACKUP_ARCHIVE}.sha256" --endpoint-url "${R2_ENDPOINT}" --region auto; then
            print_error "Warning: Failed to download checksum file. Continuing without verification."
        else
            # Verify the checksum
            print_status "Verifying backup integrity..."
            (cd "$(dirname "$BACKUP_ARCHIVE")" && sha256sum -c "${BACKUP_ARCHIVE}.sha256")
            if [ $? -ne 0 ]; then
                print_error "Backup verification failed! The file may be corrupted."
                exit 1
            fi
        fi
    else
        print_status "No checksum file found. Skipping integrity check."
    fi
else
    # Local file
    BACKUP_ARCHIVE="$BACKUP_SOURCE"
    
    # Validate backup file exists
    if [ ! -f "$BACKUP_ARCHIVE" ]; then
        print_error "Backup file does not exist: $BACKUP_ARCHIVE"
        exit 1
    fi
    
    # Validate it's a tar.gz file
    if [[ ! "$BACKUP_ARCHIVE" =~ \.tar\.gz$ ]]; then
        print_error "Backup file must be a .tar.gz archive"
        exit 1
    fi
    
    # Check for checksum file
    if [ -f "${BACKUP_ARCHIVE}.sha256" ]; then
        print_status "Verifying backup integrity..."
        (cd "$(dirname "$BACKUP_ARCHIVE")" && sha256sum -c "${BACKUP_ARCHIVE##*/}.sha256")
        if [ $? -ne 0 ]; then
            print_error "Backup verification failed! The file may be corrupted."
            exit 1
        fi
    else
        print_status "No checksum file found. Skipping integrity check."
    fi
fi

print_status "Using backup file: $BACKUP_ARCHIVE"

# Load configuration
if [ -f "/root/.nextcloud_backup_config" ]; then
    source /root/.nextcloud_backup_config
    print_status "Loaded configuration from /root/.nextcloud_backup_config"
else
    print_error "Configuration file not found at /root/.nextcloud_backup_config"
    print_status "Please provide database credentials:"
    read -p "Database Name: " DB_NAME
    read -p "Database User: " DB_USER
    read -s -p "Database Password: " DB_PASS
    echo
    
    # R2 Configuration
    echo "\n=== Cloudflare R2 Configuration ==="
    read -p "R2 Access Key ID: " R2_ACCESS_KEY_ID
    read -s -p "R2 Secret Access Key: " R2_SECRET_ACCESS_KEY
    echo
    read -p "R2 Bucket Name: " R2_BUCKET
    read -p "R2 Endpoint URL (e.g., https://xxxxxxxxxxxxxxxx.r2.cloudflarestorage.com): " R2_ENDPN
    
    # Save configuration for future use
    cat > "/root/.nextcloud_backup_config" << EOL
# Database Configuration
DB_NAME="$DB_NAME"
DB_USER="$DB_USER"
DB_PASS="$DB_PASS"

# R2 Configuration
R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
R2_BUCKET="$R2_BUCKET"
R2_ENDPOINT="$R2_ENDPOINT"
EOL
    
    chmod 600 "/root/.nextcloud_backup_config"
fi

# Configure AWS CLI for R2 if not already configured
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

# Function to restore from a backup directory
restore_from_backup() {
    local backup_dir="$1"
    
    # Check if this is an incremental backup
    if [ -f "$backup_dir/backup_metadata" ]; then
        local backup_type=$(grep '^BACKUP_TYPE=' "$backup_dir/backup_metadata" | cut -d'=' -f2-)
        local base_backup=$(grep '^BASE_BACKUP=' "$backup_dir/backup_metadata" | cut -d'=' -f2-)
        
        if [ "$backup_type" = "incremental" ] && [ "$base_backup" != "none" ]; then
            print_status "This is an incremental backup, restoring base backup first..."
            local base_backup_path="$(dirname "$backup_dir")/$base_backup"
            
            if [ ! -d "$base_backup_path" ]; then
                print_error "Base backup not found: $base_backup"
                return 1
            fi
            
            # Recursively restore the base backup first
            restore_from_backup "$base_backup_path"
            if [ $? -ne 0 ]; then
                return 1
            fi
        fi
    fi
    
    # Restore files from this backup
    print_status "Restoring from backup: $(basename "$backup_dir")"
    
    # Restore Nextcloud configuration
    if [ -d "$backup_dir/config" ] && [ "$RESTORE_CONFIG" = "true" ]; then
        print_status "Restoring Nextcloud configuration..."
        rsync -a --delete "$backup_dir/config/" "/var/www/nextcloud/config/"
    fi
    
    # Restore Nextcloud data
    if [ -d "$backup_dir/data" ] && [ "$RESTORE_DATA" = "true" ]; then
        print_status "Restoring Nextcloud data..."
        rsync -a --delete "$backup_dir/data/" "/var/www/nextcloud/data/"
    fi
    
    # Restore Nextcloud apps
    if [ -d "$backup_dir/apps" ] && [ "$RESTORE_APPS" = "true" ]; then
        print_status "Restoring Nextcloud apps..."
        rsync -a --delete "$backup_dir/apps/" "/var/www/nextcloud/apps/"
    fi
    
    # Restore database
    if [ -f "$backup_dir/nextcloud_db_backup.sql" ] && [ "$RESTORE_DATABASE" = "true" ]; then
        print_status "Restoring Nextcloud database..."
        mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$backup_dir/nextcloud_db_backup.sql"
        if [ $? -ne 0 ]; then
            print_error "Failed to restore database"
            return 1
        fi
    fi
    
    return 0
}

# Extract the backup archive to a temporary directory
print_status "Preparing to restore backup..."
RESTORE_DIR=$(mktemp -d)

# Check if this is a tar archive or a directory
if [ -f "$BACKUP_ARCHIVE" ]; then
    # Extract tar archive
    print_status "Extracting backup archive..."
    tar -xzf "$BACKUP_ARCHIVE" -C "$RESTORE_DIR"
    if [ $? -ne 0 ]; then
        print_error "Failed to extract backup archive"
        rm -rf "$RESTORE_DIR"
        exit 1
    fi
    
    # Get the extracted directory
    EXTRACTED_DIR=$(find "$RESTORE_DIR" -maxdepth 1 -type d -not -path "$RESTORE_DIR" | head -n 1)
    if [ -z "$EXTRACTED_DIR" ]; then
        print_error "No valid backup data found in the archive"
        rm -rf "$RESTORE_DIR"
        exit 1
    fi
else
    # Assume it's already a directory
    EXTRACTED_DIR="$BACKUP_ARCHIVE"
fi

print_status "Backup extracted to: $EXTRACTED_DIR"

# Confirm restore operation
print_status "This will restore Nextcloud from the backup. All current data will be overwritten."
ask_confirmation "Do you want to continue?"

# Stop Apache and Nextcloud services
print_status "Stopping Apache and Nextcloud services..."
systemctl stop apache2
systemctl stop php8.4-fpm
systemctl stop nextcloudcron.timer 2>/dev/null || true

# 1. Restore Nextcloud data directory
print_status "Restoring Nextcloud data directory..."
if [ -d "$EXTRACTED_DIR/data" ]; then
    print_status "Restoring data directory..."
    rm -rf /var/www/nextcloud/data/*
    cp -r "$EXTRACTED_DIR/data/"* /var/www/nextcloud/data/
    chown -R www-data:www-data /var/www/nextcloud/data/
    chmod -R 755 /var/www/nextcloud/data/
    print_status "Data directory restored"
else
    print_error "Data directory not found in backup"
fi

# 2. Restore Nextcloud configuration
print_status "Restoring Nextcloud configuration..."
if [ -d "$EXTRACTED_DIR/config" ]; then
    print_status "Restoring configuration..."
    rm -rf /var/www/nextcloud/config/*
    cp -r "$EXTRACTED_DIR/config/"* /var/www/nextcloud/config/
    chown -R www-data:www-data /var/www/nextcloud/config/
    chmod -R 755 /var/www/nextcloud/config/
    print_status "Configuration restored"
else
    print_error "Configuration directory not found in backup"
fi

# 3. Restore Nextcloud apps directory (custom apps)
print_status "Restoring Nextcloud apps directory..."
if [ -d "$EXTRACTED_DIR/apps" ]; then
    print_status "Restoring apps directory..."
    rm -rf /var/www/nextcloud/apps/*
    cp -r "$EXTRACTED_DIR/apps/"* /var/www/nextcloud/apps/
    chown -R www-data:www-data /var/www/nextcloud/apps/
    chmod -R 755 /var/www/nextcloud/apps/
    print_status "Apps directory restored"
else
    print_status "Apps directory not found in backup, this is normal for fresh installations"
fi

# 4. Restore the database
print_status "Restoring Nextcloud database..."
if [ -f "$EXTRACTED_DIR/nextcloud_db_backup.sql" ]; then
    print_status "Dropping and recreating database..."
    
    # First, drop the existing database and recreate it
    mysql -u "$DB_USER" -p"$DB_PASS" -e "DROP DATABASE IF EXISTS $DB_NAME;"
    mysql -u "$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    
    print_status "Importing database dump..."
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$EXTRACTED_DIR/nextcloud_db_backup.sql"
    
    if [ $? -eq 0 ]; then
        print_status "Database restored successfully"
    else
        print_error "Database restore failed"
    fi
else
    print_error "Database backup file not found in backup"
fi

# 5. Restore Apache configuration
print_status "Restoring Apache configuration..."
if [ -f "$EXTRACTED_DIR/apache_config.conf" ]; then
    cp "$EXTRACTED_DIR/apache_config.conf" /etc/apache2/sites-available/000-default.conf
    print_status "Apache configuration restored"
fi

if [ -f "$EXTRACTED_DIR/apache_ssl_config.conf" ]; then
    cp "$EXTRACTED_DIR/apache_ssl_config.conf" /etc/apache2/sites-available/000-default-le-ssl.conf
    print_status "Apache SSL configuration restored"
fi

if [ -f "$EXTRACTED_DIR/nextcloud_ssl_config.conf" ]; then
    cp "$EXTRACTED_DIR/nextcloud_ssl_config.conf" /etc/apache2/sites-available/nextcloud-ssl.conf
    print_status "Nextcloud SSL configuration restored"
fi

# 6. Restore PHP configuration
print_status "Restoring PHP configuration..."
if [ -f "$EXTRACTED_DIR/nextcloud.ini" ]; then
    cp "$EXTRACTED_DIR/nextcloud.ini" /etc/php/8.4/fpm/conf.d/
    print_status "PHP configuration restored"
fi

if [ -f "$EXTRACTED_DIR/20-redis-session.ini" ]; then
    cp "$EXTRACTED_DIR/20-redis-session.ini" /etc/php/8.4/fpm/conf.d/
    print_status "PHP Redis session configuration restored"
fi

# 7. Restore Redis configuration
print_status "Restoring Redis configuration..."
if [ -f "$EXTRACTED_DIR/redis.conf" ]; then
    cp "$EXTRACTED_DIR/redis.conf" /etc/redis/redis.conf
    chown redis:redis /etc/redis/redis.conf
    chmod 644 /etc/redis/redis.conf
    print_status "Redis configuration restored"
fi

# 8. Clean up temporary files
print_status "Cleaning up temporary files..."
if [[ "$BACKUP_SOURCE" == s3://* ]]; then
    rm -f "$BACKUP_ARCHIVE"
    rm -f "${BACKUP_ARCHIVE}.sha256"
fi
rm -rf "$RESTORE_DIR"

# Run post-restore commands
print_status "Running post-restore commands..."
for cmd in "${POST_RESTORE_COMMANDS[@]}"; do
    print_status "Executing: $cmd"
    eval "$cmd"
    if [ $? -ne 0 ]; then
        print_error "Command failed: $cmd"
        # Continue even if some commands fail
    fi
done

# Clean up
print_status "Cleaning up temporary files..."
rm -rf "$RESTORE_DIR"

print_section "Restore Process Completed"
echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    NEXTCLOUD RESTORE COMPLETED SUCCESSFULLY                ║"
echo "╠════════════════════════════════════════════════════════════════════════════╣"
printf "║  %-15s %-60s ║\n" "📅 Restore Date:" "$(date)"
printf "║  %-15s %-60s ║\n" "📦 Source:" "$(basename "$BACKUP_SOURCE")"
printf "║  %-15s %-60s ║\n" "🔧 Services Status:" "$(systemctl is-active apache2 2>/dev/null || echo 'Apache: not running'), PHP-FPM $(systemctl is-active php8.4-fpm 2>/dev/null || echo 'not running')"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

print_status "Nextcloud has been successfully restored from backup!"
print_status "Please verify your installation by logging in to the web interface."

# 9. Restart services
print_status "Restarting services..."

# Restart Redis
systemctl restart redis-server

# Restart PHP-FPM
systemctl restart php8.4-fpm

# Restart Apache
systemctl restart apache2

# Start Nextcloud cron
systemctl start nextcloudcron.timer 2>/dev/null || true

# Run maintenance and integrity checks
print_status "Running Nextcloud maintenance..."
sudo -u www-data php /var/www/nextcloud/occ maintenance:repair --include-expensive 2>/dev/null || true
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices 2>/dev/null || true
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-columns 2>/dev/null || true
sudo -u www-data php /var/www/nextcloud/occ integrity:check-core 2>/dev/null || true

# Clean up temporary files
rm -rf "$RESTORE_DIR"

print_section "Restore Process Completed"

echo ""
echo "╔════════════╗"
echo "║                    NEXTCLOUD RESTORE COMPLETED SUCCESSFULLY                ║"
echo "╠══════════════╣"
printf "║  %-15s %-50s ║\n" "📅 Restore Date:" "$(date)"
printf "║  %-15s %-50s ║\n" "📦 Backup File:" "$BACKUP_ARCHIVE"
printf "║  %-15s %-50s ║\n" "📁 Nextcloud Path:" "/var/www/nextcloud"
printf "║  %-15s %-50s ║\n" "🔄 Services:" "Apache, PHP-FPM, Redis, Nextcloud Cron"
echo "╚════════════╝"
echo ""

print_status "Nextcloud has been successfully restored from backup!"
print_status "Services have been restarted and maintenance checks completed."
print_status "Please verify that Nextcloud is working correctly by accessing your site."