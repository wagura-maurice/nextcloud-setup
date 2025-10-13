#!/bin/bash
# Nextcloud Restore Script
# Main entry point for restoring Nextcloud from backup

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

# Default configuration (overridden by .env)
BACKUP_DIR="${BACKUP_DIR:-/var/backups/nextcloud}"
NEXTCLOUD_ROOT="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"
RESTORE_DIR="${RESTORE_DIR:-$BACKUP_DIR/latest}"
WEB_SERVER_USER="${WEB_SERVER_USER:-www-data}"

# Display usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -b, --backup-dir DIR    Directory containing backups (default: $BACKUP_DIR)"
    echo "  -t, --target-dir DIR    Directory to restore to (default: $NEXTCLOUD_ROOT)"
    echo "  -d, --date DATE         Date of backup to restore (YYYYMMDD_HHMMSS)"
    echo "  -l, --list              List available backups"
    echo "  -h, --help              Show this help message"
# List available backups
list_backups() {
    log_section "Available Backups"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "Backup directory not found: $BACKUP_DIR"
        return 1
    fi
    
    local count=0
    for dir in "$BACKUP_DIR"/*/; do
        if [ -d "$dir" ]; then
            local dir_name=$(basename "$dir")
            local date_str="${dir_name:0:8}"
            local time_str="${dir_name:9:2}:${dir_name:11:2}:${dir_name:13:2}"
            local size=$(du -sh "$dir" | cut -f1)
            
            # Check if this is a valid backup
            if [ -d "$dir/db" ] && [ -d "$dir/files" ]; then
                echo -e "${GREEN}$dir_name${NC} (${YELLOW}$size${NC}) - ${CYAN}$date_str $time_str${NC}"
                ((count++))
            fi
        fi
    done
    
    if [ $count -eq 0 ]; then
        log_warning "No valid backups found in $BACKUP_DIR"
        return 1
    fi
    
    return 0
}

# Validate backup directory
validate_backup() {
    local backup_path="$1"
    
    if [ ! -d "$backup_path" ]; then
        log_error "Backup directory not found: $backup_path"
        return 1
    fi
    
    # Check for required backup components
    local missing=()
    
    [ ! -d "$backup_path/db" ] && missing+=("database")
    [ ! -d "$backup_path/files" ] && missing+=("files")
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Backup is missing required components: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# Main restore function
restore() {
    local backup_path="$1"
    local target_dir="${2:-$NEXTCLOUD_ROOT}"
    
    log_section "Starting Nextcloud Restore"
    log_info "Source: $backup_path"
    log_info "Target: $target_dir"
    
    # Validate backup
    validate_backup "$backup_path" || return 1
    
    # Check if target directory exists
    if [ ! -d "$target_dir" ]; then
        log_info "Creating target directory: $target_dir"
        mkdir -p "$target_dir" || {
            log_error "Failed to create target directory"
            return 1
        }
    fi
    
    # Set proper permissions
    chown -R ${WEB_SERVER_USER}:${WEB_SERVER_USER} "$target_dir"
    chmod 750 "$target_dir"
    
    log_success "Target directory prepared: $target_dir"
    
    # Restore files
    log_info "Restoring files..."
    if [ -d "$backup_path/files" ]; then
        log_info "Restoring files to: $target_dir/data/"
        if ! rsync -a --delete "$backup_path/files/" "$target_dir/data/"; then
            log_error "Failed to restore files"
            return 1
        fi
        
        # Set proper ownership
        chown -R ${WEB_SERVER_USER}:${WEB_SERVER_USER} "$target_dir/data"
        chmod -R 750 "$target_dir/data"
        
        log_success "Files restored successfully"
    else
        log_error "Files backup not found in $backup_path/files/"
        return 1
    fi
    
    # Restore database
    log_info "Restoring database..."
    if [ -f "$backup_path/db/nextcloud.sql" ]; then
        log_info "Restoring database from: $backup_path/db/nextcloud.sql"
        if ! mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" "$DB_NAME" < "$backup_path/db/nextcloud.sql"; then
            log_error "Failed to restore database"
            return 1
        fi
        log_success "Database restored successfully"
    else
        log_error "Database backup not found in $backup_path/db/"
        return 1
    fi
    
    return 0
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--backup-dir)
                BACKUP_DIR="$2"
                RESTORE_DIR="$BACKUP_DIR/latest"
                shift 2
                ;;
            -t|--target-dir)
                NEXTCLOUD_ROOT="$2"
                shift 2
                ;;
            -d|--date)
                local date_str="$2"
                RESTORE_DIR="$BACKUP_DIR/$date_str"
                shift 2
                ;;
            -l|--list)
                list_backups
                exit $?
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    log_section "Nextcloud Restore Utility"
    
    # Verify running as root or with sudo
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        return 1
    fi
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # If no specific backup is specified, use the latest
    if [ "$RESTORE_DIR" = "$BACKUP_DIR/latest" ] && [ -L "$RESTORE_DIR" ]; then
        RESTORE_DIR=$(readlink -f "$RESTORE_DIR")
    fi
    
    log_info "Starting restore from: $RESTORE_DIR"
    log_info "Restoring to: $NEXTCLOUD_ROOT"
    
    # Run the restore
    if restore "$RESTORE_DIR" "$NEXTCLOUD_ROOT"; then
        log_success "Restore completed successfully"
        return 0
    else
        log_error "Restore failed"
        return 1
    fi
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
