#!/bin/bash
# Files Restore Script
# Restores Nextcloud files and data from backup

# Load core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"

# Check if source and target directories are provided
if [ -z "$1" ] || [ ! -d "$1" ]; then
    log_error "Source backup directory not specified or invalid"
    exit 1
fi

if [ -z "$2" ]; then
    log_error "Target directory not specified"
    exit 1
fi

SRC_DIR="$1"
TARGET_DIR="${2%/}"  # Remove trailing slash if present

# Default configuration
NEXTCLOUD_ROOT="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"
NEXTCLOUD_DATA="${NEXTCLOUD_DATA:-$NEXTCLOUD_ROOT/data}"

# Run command as www-data user
run_as_www_data() {
    sudo -u www-data bash -c "$1"
    return $?
}

# Check if Nextcloud is in maintenance mode
is_maintenance_mode() {
    local status
    status=$(run_as_www_data "php $NEXTCLOUD_ROOT/occ maintenance:mode" 2>/dev/null)
    if [[ $status == *"enabled"* ]]; then
        return 0
    else
        return 1
    fi
}

# Enable maintenance mode
enable_maintenance_mode() {
    log_info "Enabling maintenance mode"
    if ! run_as_www_data "php $NEXTCLOUD_ROOT/occ maintenance:mode --on"; then
        log_warning "Failed to enable maintenance mode"
        return 1
    fi
    return 0
}

# Disable maintenance mode
disable_maintenance_mode() {
    log_info "Disabling maintenance mode"
    if ! run_as_www_data "php $NEXTCLOUD_ROOT/occ maintenance:mode --off"; then
        log_warning "Failed to disable maintenance mode"
    fi
    return 0
}

# Restore Nextcloud files
restore_nextcloud_files() {
    local backup_file
    
    # Find the latest files backup
    backup_file=$(find "$SRC_DIR" -name "nextcloud-files-*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -z "$backup_file" ]; then
        log_error "No files backup found in $SRC_DIR"
        return 1
    fi
    
    log_info "Found files backup: $backup_file"
    
    # Create target directory if it doesn't exist
    mkdir -p "$TARGET_DIR" || {
        log_error "Failed to create target directory: $TARGET_DIR"
        return 1
    }
    
    # Extract files
    log_info "Restoring files to: $TARGET_DIR"
    if ! tar -xzf "$backup_file" -C "$(dirname "$TARGET_DIR")"; then
        log_error "Failed to extract files"
        return 1
    fi
    
    # Set proper ownership
    chown -R www-data:www-data "$TARGET_DIR" || {
        log_warning "Failed to set ownership on $TARGET_DIR"
    }
    
    log_success "Files restored successfully"
    return 0
}

# Restore Nextcloud data directory
restore_data_directory() {
    local backup_file
    local data_dir="$TARGET_DIR/data"
    
    # Find the latest data backup
    backup_file=$(find "$SRC_DIR" -name "nextcloud-data-*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -z "$backup_file" ]; then
        log_warning "No data directory backup found in $SRC_DIR"
        return 0  # This is not a critical error
    fi
    
    log_info "Found data directory backup: $backup_file"
    
    # Create data directory if it doesn't exist
    mkdir -p "$data_dir" || {
        log_error "Failed to create data directory: $data_dir"
        return 1
    }
    
    # Extract data
    log_info "Restoring data to: $data_dir"
    if ! tar -xzf "$backup_file" -C "$TARGET_DIR"; then
        log_error "Failed to extract data directory"
        return 1
    fi
    
    # Set proper ownership
    chown -R www-data:www-data "$data_dir" || {
        log_warning "Failed to set ownership on $data_dir"
    }
    
    log_success "Data directory restored successfully"
    return 0
}

# Main function
main() {
    log_section "Starting Files Restore"
    
    # Check if target is a Nextcloud installation
    local is_nextcloud=false
    if [ -f "$TARGET_DIR/occ" ]; then
        is_nextcloud=true
    fi
    
    # Enable maintenance mode if Nextcloud is installed
    if [ "$is_nextcloud" = true ] && ! is_maintenance_mode; then
        enable_maintenance_mode || {
            log_warning "Continuing with restore without maintenance mode"
        }
    fi
    
    local success=true
    
    # Restore files
    if ! restore_nextcloud_files; then
        log_error "Failed to restore Nextcloud files"
        success=false
    fi
    
    # Restore data directory
    if ! restore_data_directory; then
        log_error "Failed to restore data directory"
        success=false
    fi
    
    # Disable maintenance mode if we enabled it
    if [ "$is_nextcloud" = true ] && is_maintenance_mode; then
        disable_maintenance_mode
    fi
    
    if [ "$success" = true ]; then
        log_success "Files restore completed successfully"
        return 0
    else
        log_error "Files restore completed with errors"
        return 1
    fi
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
