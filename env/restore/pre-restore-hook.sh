#!/bin/bash

# Nextcloud Pre-Restore Hook Script
# This script runs before the restoration process begins

# Exit on error
set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/restore.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    case $level in
        "INFO") color=$BLUE ;;
        "SUCCESS") color=$GREEN ;;
        "WARNING") color=$YELLOW ;;
        "ERROR") color=$RED ;;
        *) color=$NC ;;
    esac
    
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Function to load configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Configuration file not found at $CONFIG_FILE${NC}"
        exit 1
    fi
    
    # Source the config file
    source <(grep = "$CONFIG_FILE" | sed 's/ *= */=/g' | sed 's/^[^#]/export /' | sed 's/"//g' 2>/dev/null)
    
    # Set default values if not set in config
    LOG_FILE=${log_file:-"/var/log/nextcloud/pre-restore-$(date +%Y%m%d).log"}
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
}

# Function to check disk space
check_disk_space() {
    local required_space=$1
    local available_space=$(df -k --output=avail "$NEXTCLOUD_PATH" | tail -n1)
    
    if [ $available_space -lt $(($required_space * 1024)) ]; then
        log "ERROR" "Not enough disk space. Required: ${required_space}MB, Available: $(($available_space/1024))MB"
        return 1
    fi
    
    log "INFO" "Disk space check passed. Available: $(($available_space/1024))MB"
    return 0
}

# Function to stop services
stop_services() {
    log "INFO" "Stopping services..."
    
    # Stop web server
    if systemctl is-active --quiet apache2; then
        systemctl stop apache2
        log "INFO" "Stopped Apache"
    fi
    
    # Stop PHP-FPM
    if systemctl is-active --quiet php8.4-fpm; then
        systemctl stop php8.4-fpm
        log "INFO" "Stopped PHP-FPM"
    fi
    
    # Stop Redis if running
    if systemctl is-active --quiet redis-server; then
        systemctl stop redis-server
        log "INFO" "Stopped Redis"
    fi
    
    # Stop cron jobs
    if systemctl is-active --quiet cron; then
        systemctl stop cron
        log "INFO" "Stopped cron"
    fi
}

# Function to create backup of current state
create_pre_restore_backup() {
    if [ "$backup_before_restore" != "true" ]; then
        log "INFO" "Skipping pre-restore backup as per configuration"
        return 0
    fi
    
    local timestamp=$(date +%Y%m%d%H%M%S)
    local backup_dir="$backup_dir/pre_restore_$timestamp"
    
    log "INFO" "Creating backup of current state to $backup_dir..."
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Backup Nextcloud directory
    if [ -d "$NEXTCLOUD_PATH" ]; then
        log "INFO" "Backing up Nextcloud files..."
        cp -a "$NEXTCLOUD_PATH" "$backup_dir/"
    fi
    
    # Backup database if credentials are available
    if [ -n "$db_user" ] && [ -n "$db_password" ] && [ -n "$db_name" ]; then
        log "INFO" "Backing up database..."
        mysqldump -u "$db_user" -p"$db_password" "$db_name" > "$backup_dir/nextcloud-db-backup-${timestamp}.sql"
    fi
    
    log "SUCCESS" "Pre-restore backup created at $backup_dir"
}

# Function to verify system requirements
verify_requirements() {
    log "INFO" "Verifying system requirements..."
    
    # Check for required commands
    local required_commands=("tar" "gzip" "mysql" "mysqldump" "php")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR" "Required command not found: $cmd"
            return 1
        fi
    done
    
    # Check PHP version
    local php_version=$(php -r "echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;" 2>/dev/null)
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to get PHP version"
        return 1
    fi
    
    log "INFO" "PHP version: $php_version"
    
    # Check for required PHP extensions
    local required_extensions=("pdo" "pdo_mysql" "json" "xml" "zip" "gd" "curl" "mbstring" "intl")
    for ext in "${required_extensions[@]}"; do
        if ! php -m | grep -q "^$ext$"; then
            log "WARNING" "PHP extension not found: $ext"
        fi
    done
    
    log "SUCCESS" "System requirements check passed"
    return 0
}

# Main function
main() {
    # Load configuration
    load_config
    
    log "INFO" "=== Starting Pre-Restore Checks ==="
    
    # Verify system requirements
    if ! verify_requirements; then
        log "ERROR" "System requirements check failed"
        exit 1
    fi
    
    # Check disk space (estimate 1.5x the backup size)
    if [ -f "$1" ]; then
        local backup_size=$(($(stat -c%s "$1")/1024/1024))
        local required_space=$((backup_size * 15 / 10)) # 1.5x backup size
        
        if ! check_disk_space "$required_space"; then
            exit 1
        fi
    fi
    
    # Stop services
    stop_services
    
    # Create backup of current state
    create_pre_restore_backup
    
    log "SUCCESS" "=== Pre-Restore Checks Completed Successfully ==="
    exit 0
}

# Run main function
main "$@"
