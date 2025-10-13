#!/bin/bash
# Nextcloud Backup Script
# Handles complete backup of Nextcloud instance

# Load core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"

# Default configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/nextcloud}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CURRENT_BACKUP_DIR="$BACKUP_DIR/$TIMESTAMP"

# Load configuration
load_config() {
    local config_file="$SCRIPT_DIR/../../.env"
    if [ -f "$config_file" ]; then
        source "$config_file"
    else
        log_warning "No .env configuration file found. Using default values."
    fi
}

# Initialize backup directory
init_backup_dir() {
    log_info "Creating backup directory: $CURRENT_BACKUP_DIR"
    mkdir -p "$CURRENT_BACKUP_DIR" || {
        log_error "Failed to create backup directory"
        return 1
    }
    
    # Set secure permissions
    chmod 700 "$CURRENT_BACKUP_DIR"
    chown root:root "$CURRENT_BACKUP_DIR"
}

# Main backup function
main() {
    log_section "Starting Nextcloud Backup"
    
    # Load configuration
    load_config
    
    # Initialize backup directory
    init_backup_dir || return 1
    
    # Run backup components
    local components=(
        "database"
        "files"
        "config"
    )
    
    for component in "${components[@]}"; do
        local script_path="$SCRIPT_DIR/backup/backup-${component}.sh"
        if [ -f "$script_path" ]; then
            log_info "Running $component backup..."
            if ! bash "$script_path" "$CURRENT_BACKUP_DIR"; then
                log_error "$component backup failed"
                return 1
            fi
        else
            log_warning "Backup script not found: $script_path"
        fi
    done
    
    log_success "Backup completed successfully: $CURRENT_BACKUP_DIR"
    return 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
