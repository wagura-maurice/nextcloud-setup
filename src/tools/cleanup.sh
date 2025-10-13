#!/bin/bash
# Cleanup Script
# Handles cleanup of temporary files, logs, and old backups

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment
load_environment
init_logging

# Default configuration (overridden by .env)
NEXTCLOUD_ROOT="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/nextcloud}"
LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-30}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}

# Clean old log files
clean_logs() {
    log_section "Cleaning up old log files"
    
    local log_dirs=(
        "/var/log/nextcloud"
        "/var/log/apache2"
        "/var/log/nginx"
        "/var/log/mysql"
        "/var/log/redis"
    )
    
    for dir in "${log_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_info "Cleaning logs in $dir older than $LOG_RETENTION_DAYS days"
            find "$dir" -type f -name "*.log*" -mtime +$LOG_RETENTION_DAYS -delete
        fi
    done
    
    log_success "Log cleanup completed"
    return 0
}

# Clean old backups
clean_backups() {
    log_section "Cleaning up old backups"
    
    if [ -d "$BACKUP_DIR" ]; then
        log_info "Removing backups older than $BACKUP_RETENTION_DAYS days from $BACKUP_DIR"
        find "$BACKUP_DIR" -type d -mtime +$BACKUP_RETENTION_DAYS -exec rm -rf {} \;
    else
        log_warning "Backup directory not found: $BACKUP_DIR"
        return 1
    fi
    
    log_success "Backup cleanup completed"
    return 0
}

# Clean temporary files
clean_temp_files() {
    log_section "Cleaning temporary files"
    
    local temp_dirs=(
        "$NEXTCLOUD_ROOT/updater-*"
        "$NEXTCLOUD_ROOT/updater"
        "$NEXTCLOUD_ROOT/data/appdata_*/preview"
        "$NEXTCLOUD_ROOT/data/*/files_*/cache"
        "$NEXTCLOUD_ROOT/data/*/files_*/uploads"
        "$NEXTCLOUD_ROOT/data/*/files_*/transcode"
        "/tmp/nextcloud-*"
    )
    
    for pattern in "${temp_dirs[@]}"; do
        # Expand the pattern to handle wildcards
        for dir in $pattern; do
            if [ -d "$dir" ]; then
                log_info "Cleaning directory: $dir"
                rm -rf "$dir"/*
            fi
        done
    done
    
    log_success "Temporary files cleanup completed"
    return 0
}

# Main function
main() {
    log_section "Starting System Cleanup"
    local success=true
    
    if ! clean_logs; then
        log_warning "Log cleanup had issues"
        success=false
    fi
    
    if ! clean_backups; then
        log_warning "Backup cleanup had issues"
        success=false
    fi
    
    if ! clean_temp_files; then
        log_warning "Temporary files cleanup had issues"
        success=false
    fi
    
    if [ "$success" = true ]; then
        log_success "Cleanup completed successfully"
        return 0
    else
        log_warning "Cleanup completed with some issues"
        return 1
    fi
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
