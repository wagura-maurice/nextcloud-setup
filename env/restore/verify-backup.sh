#!/bin/bash

# Nextcloud Backup Verification Script
# This script verifies the integrity of Nextcloud backup files

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
    LOG_FILE=${log_file:-"/var/log/nextcloud/verify-backup-$(date +%Y%m%d).log"}
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
}

# Function to verify backup file
verify_backup() {
    local backup_file=$1
    
    log "INFO" "Verifying backup file: $backup_file"
    
    # Check if file exists
    if [ ! -f "$backup_file" ]; then
        log "ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    # Check file size
    local file_size=$(stat -c%s "$backup_file" 2>/dev/null)
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to get file size for: $backup_file"
        return 1
    fi
    
    log "INFO" "Backup file size: $(($file_size/1024/1024)) MB"
    
    # Check if file is a valid tar.gz archive
    if ! tar -tzf "$backup_file" &>/dev/null; then
        log "ERROR" "Invalid or corrupted tar.gz archive: $backup_file"
        return 1
    fi
    
    # Extract file list to check contents
    local file_list=$(tar -tzf "$backup_file" 2>/dev/null)
    
    # Check for required directories
    local has_nextcloud=$(echo "$file_list" | grep -q "nextcloud/" && echo true || echo false)
    local has_database=$(echo "$file_list" | grep -q "database/" && echo true || echo false)
    local has_config=$(echo "$file_list" | grep -q "config/" && echo true || echo false)
    
    if [ "$has_nextcloud" = false ] || [ "$has_database" = false ] || [ "$has_config" = false ]; then
        log "WARNING" "Backup is missing some components:"
        [ "$has_nextcloud" = false ] && log "WARNING" "  - Missing nextcloud/ directory"
        [ "$has_database" = false ] && log "WARNING" "  - Missing database/ directory"
        [ "$has_config" = false ] && log "WARNING" "  - Missing config/ directory"
    fi
    
    # Check for SQL files in database directory
    if [ "$has_database" = true ]; then
        local sql_files=$(echo "$file_list" | grep -c "database/.*\.sql$")
        if [ $sql_files -eq 0 ]; then
            log "WARNING" "No SQL files found in database/ directory"
        else
            log "INFO" "Found $sql_files SQL file(s) in database/ directory"
        fi
    fi
    
    # Check for config.php
    if [ "$has_config" = true ]; then
        if ! echo "$file_list" | grep -q "config/config\.php"; then
            log "WARNING" "config.php not found in backup"
        fi
    fi
    
    log "SUCCESS" "Backup verification completed: $backup_file"
    return 0
}

# Function to verify database dump
verify_database_dump() {
    local backup_file=$1
    local temp_dir=$(mktemp -d)
    
    log "INFO" "Extracting database dump for verification..."
    
    # Extract database directory
    if ! tar -xzf "$backup_file" -C "$temp_dir" --wildcards "database/*" 2>/dev/null; then
        log "ERROR" "Failed to extract database from backup"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Find SQL file
    local sql_file=$(find "$temp_dir" -name "*.sql" | head -n 1)
    
    if [ -z "$sql_file" ]; then
        log "ERROR" "No SQL file found in backup"
        rm -rf "$temp_dir"
        return 1
    fi
    
    log "INFO" "Found SQL file: $(basename "$sql_file")"
    
    # Check SQL file header
    local header=$(head -n 10 "$sql_file")
    if ! echo "$header" | grep -q "MySQL dump"; then
        log "WARNING" "SQL file header doesn't look like a standard MySQL dump"
    fi
    
    # Check for common tables
    local table_check=$(grep -c -E 'CREATE TABLE.*(oc_|nextcloud_|*_table)' "$sql_file" || true)
    if [ $table_check -eq 0 ]; then
        log "WARNING" "No standard Nextcloud tables found in SQL dump"
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    
    log "SUCCESS" "Database dump verification completed"
    return 0
}

# Main function
main() {
    # Load configuration
    load_config
    
    log "INFO" "=== Starting Backup Verification ==="
    
    # Check if backup file is provided
    if [ $# -eq 0 ]; then
        log "ERROR" "No backup file specified"
        echo "Usage: $0 <backup-file.tar.gz>"
        exit 1
    fi
    
    local backup_file=$1
    
    # Verify backup file
    if ! verify_backup "$backup_file"; then
        log "ERROR" "Backup verification failed"
        exit 1
    fi
    
    # Verify database dump if requested
    if [ "$verify_database" = true ]; then
        if ! verify_database_dump "$backup_file"; then
            log "WARNING" "Database verification failed, but backup might still be valid"
        fi
    fi
    
    log "SUCCESS" "=== Backup Verification Completed Successfully ==="
    exit 0
}

# Run main function
main "$@"
