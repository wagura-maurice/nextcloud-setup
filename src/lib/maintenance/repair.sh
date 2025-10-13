#!/bin/bash
# Nextcloud Repair Script
# Handles repair and maintenance of Nextcloud instance

# Load core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"

# Default configuration
NEXTCLOUD_ROOT="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"
PHP_BIN="${PHP_BIN:-php}"

# Run command as www-data user
run_as_www_data() {
    sudo -u www-data bash -c "$1"
    return $?
}

# Check if Nextcloud is in maintenance mode
is_maintenance_mode() {
    local status
    status=$(run_as_www_data "$PHP_BIN $NEXTCLOUD_ROOT/occ maintenance:mode")
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

# Repair Nextcloud installation
repair_nextcloud() {
    log_section "Repairing Nextcloud installation"
    
    # Check if Nextcloud is installed
    if [ ! -f "$NEXTCLOUD_ROOT/occ" ]; then
        log_error "Nextcloud occ command not found. Is Nextcloud installed?"
        return 1
    fi
    
    # Check if maintenance mode is already enabled
    local was_in_maintenance=false
    if is_maintenance_mode; then
        was_in_maintenance=true
    else
        enable_maintenance_mode || return 1
    fi
    
    # Run repair commands
    local success=true
    
    log_info "Running database repair"
    if ! run_as_www_data "$PHP_BIN $NEXTCLOUD_ROOT/occ maintenance:repair"; then
        log_error "Database repair failed"
        success=false
    fi
    
    log_info "Checking database schema"
    if ! run_as_www_data "$PHP_BIN $NEXTCLOUD_ROOT/occ db:add-missing-indices"; then
        log_warning "Failed to add missing indices"
        success=false
    fi
    
    log_info "Checking file cache"
    if ! run_as_www_data "$PHP_BIN $NEXTCLOUD_ROOT/occ files:scan --all"; then
        log_error "File scan failed"
        success=false
    fi
    
    log_info "Checking previews"
    if ! run_as_www_data "$PHP_BIN $NEXTCLOUD_ROOT/occ preview:repair"; then
        log_warning "Preview repair had issues"
        success=false
    fi
    
    # Disable maintenance mode if it wasn't enabled before
    if [ "$was_in_maintenance" = false ]; then
        disable_maintenance_mode || success=false
    fi
    
    if [ "$success" = true ]; then
        log_success "Repair completed successfully"
        return 0
    else
        log_error "Repair completed with errors"
        return 1
    fi
}

# Main function
main() {
    log_section "Starting Nextcloud Repair"
    repair_nextcloud
    return $?
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
