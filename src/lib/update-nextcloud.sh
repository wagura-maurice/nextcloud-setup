#!/bin/bash
# Nextcloud Update Script
# Main entry point for updating Nextcloud and its components

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

# Default configuration (overridden by .env)
NEXTCLOUD_ROOT="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/nextcloud}"
# Require PHP 8.4
PHP_BIN="${PHP_BIN:-$(which php8.4)}"
if [ -z "$PHP_BIN" ]; then
    log_error "PHP 8.4 is required but not found. Please install PHP 8.4."
    exit 1
fi
WEB_SERVER_USER="${WEB_SERVER_USER:-www-data}"

# Run command as web server user
run_as_web_user() {
    sudo -u "$WEB_SERVER_USER" bash -c "$1"
    return $?
}

# Check if Nextcloud is in maintenance mode
is_maintenance_mode() {
    local status
    status=$(run_as_web_user "$PHP_BIN $NEXTCLOUD_ROOT/occ maintenance:mode" 2>/dev/null)
    if [[ $status == *"enabled"* ]]; then
        return 0
    else
        return 1
    fi
}

# Enable maintenance mode
enable_maintenance_mode() {
    log_info "Enabling maintenance mode"
    if ! run_as_web_user "$PHP_BIN $NEXTCLOUD_ROOT/occ maintenance:mode --on"; then
        log_error "Failed to enable maintenance mode"
        return 1
    fi
    return 0
}

# Disable maintenance mode
disable_maintenance_mode() {
    log_info "Disabling maintenance mode"
    if ! run_as_web_user "$PHP_BIN $NEXTCLOUD_ROOT/occ maintenance:mode --off"; then
        log_error "Failed to disable maintenance mode"
        return 1
    fi
    return 0
}

# Get current Nextcloud version
get_current_version() {
    if [ -f "$NEXTCLOUD_ROOT/version.php" ]; then
        grep -oP "[0-9]+\.[0-9]+\.[0-9]+" "$NEXTCLOUD_ROOT/version.php"
    else
        echo "unknown"
    fi
}

# Check for available updates
check_for_updates() {
    log_info "Checking for Nextcloud updates..."
    
    local current_version
    current_version=$(get_current_version)
    
    if [ "$current_version" = "unknown" ]; then
        log_error "Could not determine current Nextcloud version"
        return 1
    fi
    
    log_info "Current version: $current_version"
    
    # Get latest version from download URL
    log_info "Fetching latest version information..."
    local latest_version
    if ! latest_version=$(curl -s -I https://download.nextcloud.com/server/releases/latest.zip 2>/dev/null | 
                    grep -i '^location:' | 
                    grep -oP 'nextcloud-\K[0-9.]+(?=.zip)' | 
                    head -1); then
        log_error "Failed to fetch version information"
        return 1
    fi
    
    if [ -z "$latest_version" ]; then
        log_error "Failed to determine latest version from download URL"
        return 1
    fi
    
    log_info "Latest stable version: $latest_version"
    
    if [ "$current_version" = "$latest_version" ]; then
        log_success "Nextcloud is up to date"
        return 0
    else
        log_info "Update available: $current_version -> $latest_version"
        return 2  # Special return code for update available
    fi
}

# Create backup before update
create_backup() {
    log_section "Creating backup before update"
    
    # Ensure backup directory exists
    mkdir -p "$BACKUP_DIR" || {
        log_error "Failed to create backup directory: $BACKUP_DIR"
        return 1
    }
    
    # Set proper permissions
    chown -R "$WEB_SERVER_USER":"$WEB_SERVER_USER" "$BACKUP_DIR"
    chmod 750 "$BACKUP_DIR"
    
    log_info "Starting backup to: $BACKUP_DIR"
    
    # Run the backup script
    if ! "$SCRIPT_DIR/backup-nextcloud.sh"; then
        log_error "Backup failed. Aborting update."
        return 1
    fi
    
    log_success "Backup completed successfully"
    return 0
}

# Update Nextcloud core
update_nextcloud() {
    log_section "Updating Nextcloud"
    
    # Enable maintenance mode
    if ! is_maintenance_mode; then
        enable_maintenance_mode || return 1
    fi
    
    # Run the updater
    log_info "Running Nextcloud updater..."
    if ! run_as_web_user "cd $NEXTCLOUD_ROOT && $PHP_BIN updater/updater.phar --no-interaction"; then
        log_error "Nextcloud update failed"
        return 1
    fi
    
    # Run database migrations
    log_info "Running database migrations..."
    if ! run_as_web_user "cd $NEXTCLOUD_ROOT && $PHP_BIN occ upgrade"; then
        log_error "Database migration failed"
        return 1
    fi
    
    # Disable maintenance mode
    if is_maintenance_mode; then
        disable_maintenance_mode || return 1
    fi
    
    log_success "Nextcloud updated successfully"
    return 0
}

# Update Nextcloud apps
update_apps() {
    log_section "Updating Nextcloud apps"
    
    if ! run_as_web_user "cd $NEXTCLOUD_ROOT && $PHP_BIN occ app:update --all"; then
        log_error "Failed to update apps"
        return 1
    
    log_success "Apps updated successfully"
    return 0
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-backup)
                SKIP_BACKUP=true
                shift
                ;;
            --force)
                FORCE_UPDATE=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --skip-backup    Skip creating a backup before update"
                echo "  --force          Force update even if no new version is available"
                echo "  -h, --help       Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    log_section "Nextcloud Update"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        return 1
    fi
    
    # Ensure required commands are available
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed"
        return 1
    fi
    
    # Check for updates
    log_info "Checking for available updates..."
    check_for_updates
    
    if [ "$FORCE_UPDATE" != "true" ] && [ $update_available -eq 0 ]; then
        # No updates available and not forced
        return 0
    elif [ $update_available -eq 1 ] && [ "$FORCE_UPDATE" != "true" ]; then
        # Error checking for updates and not forced
        return 1
    fi
    
    # Create backup unless skipped
    if [ "$SKIP_BACKUP" != "true" ]; then
        if ! create_backup; then
            log_error "Backup failed. Use --skip-backup to skip backup."
            return 1
        fi
    else
        log_warning "Skipping backup as requested"
    fi
    
    # Update Nextcloud
    log_info "Starting Nextcloud update..."
    if ! update_nextcloud; then
        log_error "Nextcloud update failed. Check the logs for details."
        return 1
    fi
    
    # Update apps
    log_info "Updating Nextcloud apps..."
    if ! update_apps; then
        log_warning "Some apps failed to update. Check the logs for details."
    fi
    
    log_success "Nextcloud update completed successfully"
    return 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
