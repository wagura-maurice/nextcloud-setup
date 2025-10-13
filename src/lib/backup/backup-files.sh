#!/bin/bash
# Nextcloud Files Backup Script
# Handles backup of Nextcloud files and data directory

# Load core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"

# Check if backup directory is provided
if [ -z "$1" ]; then
    log_error "Backup directory not specified"
    exit 1
fi

BACKUP_DIR="$1/files"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Default paths
NEXTCLOUD_ROOT="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"
NEXTCLOUD_DATA="${NEXTCLOUD_DATA:-$NEXTCLOUD_ROOT/data}"

# Create backup directory
mkdir -p "$BACKUP_DIR" || {
    log_error "Failed to create files backup directory"
    exit 1
}

# Put Nextcloud in maintenance mode
enable_maintenance_mode() {
    log_info "Enabling maintenance mode"
    if ! run_as_www_data "$NEXTCLOUD_ROOT/occ maintenance:mode --on"; then
        log_warning "Failed to enable maintenance mode"
        return 1
    fi
    return 0
}

# Disable maintenance mode
disable_maintenance_mode() {
    log_info "Disabling maintenance mode"
    if ! run_as_www_data "$NEXTCLOUD_ROOT/occ maintenance:mode --off"; then
        log_warning "Failed to disable maintenance mode"
    fi
    return 0
}

# Run command as www-data user
run_as_www_data() {
    sudo -u www-data bash -c "$1"
    return $?
}

# Backup Nextcloud files
backup_nextcloud_files() {
    local backup_file="$BACKUP_DIR/nextcloud-files-$TIMESTAMP.tar.gz"
    
    log_info "Backing up Nextcloud files from: $NEXTCLOUD_ROOT"
    
    # Exclude data directory and other unnecessary files
    if ! tar -czf "$backup_file" -C "$(dirname "$NEXTCLOUD_ROOT")" \
        --exclude="$(basename "$NEXTCLOUD_ROOT")/data" \
        --exclude="$(basename "$NEXTCLOUD_ROOT")/updater-*" \
        --exclude="$(basename "$NEXTCLOUD_ROOT")/updater" \
        --exclude="$(basename "$NEXTCLOUD_ROOT")/updater" \
        --exclude="$(basename "$NEXTCLOUD_ROOT")/updater" \
        --exclude="$(basename "$NEXTCLOUD_ROOT")/updater" \
        --exclude="$(basename "$NEXTCLOUD_ROOT")/updater" \
        "$(basename "$NEXTCLOUD_ROOT")"; then
        log_error "Failed to create files backup"
        return 1
    fi
    
    log_success "Files backup created: $backup_file"
    return 0
}

# Backup Nextcloud data directory
backup_data_directory() {
    local backup_file="$BACKUP_DIR/nextcloud-data-$TIMESTAMP.tar.gz"
    
    log_info "Backing up Nextcloud data from: $NEXTCLOUD_DATA"
    
    if [ ! -d "$NEXTCLOUD_DATA" ]; then
        log_warning "Data directory not found: $NEXTCLOUD_DATA"
        return 1
    fi
    
    # Exclude cache and other temporary files
    if ! tar -czf "$backup_file" -C "$(dirname "$NEXTCLOUD_DATA")" \
        --exclude="$(basename "$NEXTCLOUD_DATA")/appdata_*/preview" \
        --exclude="$(basename "$NEXTCLOUD_DATA")/*/files_*/cache" \
        --exclude="$(basename "$NEXTCLOUD_DATA")/*/files_*/uploads" \
        --exclude="$(basename "$NEXTCLOUD_DATA")/*/files_*/transcode" \
        --exclude="$(basename "$NEXTCLOUD_DATA")/*/files_*/files_trashbin" \
        --exclude="$(basename "$NEXTCLOUD_DATA")/*/files_*/files_versions" \
        --exclude="$(basename "$NEXTCLOUD_DATA")/.trash-*" \
        "$(basename "$NEXTCLOUD_DATA")"; then
        log_error "Failed to create data directory backup"
        return 1
    fi
    
    log_success "Data directory backup created: $backup_file"
    return 0
}

# Main function
main() {
    log_section "Starting Files Backup"
    local success=true
    
    # Enable maintenance mode
    if ! enable_maintenance_mode; then
        log_warning "Continuing with backup without maintenance mode"
    fi
    
    # Run backup operations
    if ! backup_nextcloud_files; then
        success=false
    fi
    
    if ! backup_data_directory; then
        success=false
    fi
    
    # Disable maintenance mode
    disable_maintenance_mode
    
    if [ "$success" = false ]; then
        log_error "Files backup completed with errors"
        return 1
    fi
    
    log_success "Files backup completed successfully"
    return 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
