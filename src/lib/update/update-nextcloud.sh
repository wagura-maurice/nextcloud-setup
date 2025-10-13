#!/bin/bash
# Nextcloud Update Script
# Main entry point for updating Nextcloud and its components

# Load core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"

# Default configuration
NEXTCLOUD_ROOT="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/nextcloud}"
PHP_BIN="${PHP_BIN:-php}"

# Run command as www-data user
run_as_www_data() {
    sudo -u www-data bash -c "$1"
    return $?
}

# Check if Nextcloud is in maintenance mode
is_maintenance_mode() {
    local status
    status=$(run_as_www_data "$PHP_BIN $NEXTCLOUD_ROOT/occ maintenance:mode" 2>/dev/null)
    if [[ $status == *"enabled"* ]]; then
        return 0
    else
        return 1
    fi
}

# Enable maintenance mode
enable_maintenance_mode() {
    log_info "Enabling maintenance mode"
    if ! run_as_www_data "$PHP_BIN $NEXTCLOUD_ROOT/occ maintenance:mode --on"; then
        log_error "Failed to enable maintenance mode"
        return 1
    fi
    return 0
}

# Disable maintenance mode
disable_maintenance_mode() {
    log_info "Disabling maintenance mode"
    if ! run_as_www_data "$PHP_BIN $NEXTCLOUD_ROOT/occ maintenance:mode --off"; then
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
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed. Please install jq first."
        return 1
    fi
    
    local current_version
    current_version=$(get_current_version)
    
    if [ "$current_version" = "unknown" ]; then
        log_error "Could not determine current Nextcloud version"
        return 1
    fi
    
    log_info "Current version: $current_version"
    
    # Get latest version from Nextcloud's update server
    local update_info
    update_info=$(curl -s https://updates.nextcloud.com/server/)
    
    if [ -z "$update_info" ]; then
        log_error "Failed to fetch update information"
        return 1
    fi
    
    local latest_version
    latest_version=$(echo "$update_info" | jq -r '.stable25' 2>/dev/null)
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        log_error "Failed to determine latest version"
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
    
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR" || {
            log_error "Failed to create backup directory"
            return 1
        }
    fi
    
    if ! "$SCRIPT_DIR/backup/backup-nextcloud.sh"; then
        log_error "Backup failed. Aborting update."
        return 1
    fi
    
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
    if ! run_as_www_data "cd $NEXTCLOUD_ROOT && $PHP_BIN updater/updater.phar --no-interaction"; then
        log_error "Nextcloud update failed"
        return 1
    fi
    
    # Run database migrations
    log_info "Running database migrations..."
    if ! run_as_www_data "cd $NEXTCLOUD_ROOT && $PHP_BIN occ upgrade"; then
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
    
    if ! run_as_www_data "cd $NEXTCLOUD_ROOT && $PHP_BIN occ app:update --all"; then
        log_error "Failed to update apps"
        return 1
    fi
    
    log_success "Apps updated successfully"
    return 0
}

# Main function
main() {
    log_section "Nextcloud Update"
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Check for updates
    check_for_updates
    local update_available=$?
    
    if [ $update_available -eq 0 ]; then
        # No updates available
        return 0
    elif [ $update_available -ne 2 ]; then
        # Error checking for updates
        return 1
    fi
    
    # Create backup
    if ! create_backup; then
        return 1
    fi
    
    # Update Nextcloud
    if ! update_nextcloud; then
        log_error "Nextcloud update failed. Check the logs for details."
        return 1
    fi
    
    # Update apps
    if ! update_apps; then
        log_warning "App updates had issues"
    fi
    
    log_success "Update completed successfully"
    return 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
