#!/bin/bash
# Nextcloud Backup Script
# Handles complete backup of Nextcloud instance including database, files, and configuration

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
NEXTCLOUD_DATA="${NEXTCLOUD_DATA:-/var/nextcloud/data}"
MYSQL_USER="${MYSQL_USER:-nextcloud}"
MYSQL_PASSWORD="${MYSQL_PASSWORD}"
MYSQL_DATABASE="${MYSQL_DATABASE:-nextcloud}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CURRENT_BACKUP_DIR="$BACKUP_DIR/$TIMESTAMP"

# Initialize backup directory
init_backup_dir() {
    log_info "Creating backup directory: $CURRENT_BACKUP_DIR"
    mkdir -p "$CURRENT_BACKUP_DIR" || {
        log_error "Failed to create backup directory"
        return 1
    }
    
    # Create subdirectories
    mkdir -p "$CURRENT_BACKUP_DIR/database"
    mkdir -p "$CURRENT_BACKUP_DIR/files"
    mkdir -p "$CURRENT_BACKUP_DIR/config"
    
    # Set secure permissions
    chmod 700 "$CURRENT_BACKUP_DIR"
    chown -R root:root "$CURRENT_BACKUP_DIR"
}

# Backup database
backup_database() {
    log_info "Backing up database..."
    local db_backup="$CURRENT_BACKUP_DIR/database/nextcloud-db-$(date +%Y%m%d).sql"
    
    if ! mysqldump --single-transaction -h localhost -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" > "$db_backup"; then
        log_error "Database backup failed"
        return 1
    fi
    
    # Compress the backup
    gzip -f "$db_backup"
    log_success "Database backup completed: ${db_backup}.gz"
}

# Backup Nextcloud files
backup_files() {
    log_info "Backing up Nextcloud files..."
    
    # Backup Nextcloud installation
    if ! tar -czf "$CURRENT_BACKUP_DIR/files/nextcloud-files.tar.gz" -C "$(dirname "$NEXTCLOUD_ROOT")" "$(basename "$NEXTCLOUD_ROOT")"; then
        log_error "Failed to backup Nextcloud files"
        return 1
    fi
    
    # Backup data directory
    if ! tar -czf "$CURRENT_BACKUP_DIR/files/nextcloud-data.tar.gz" -C "$(dirname "$NEXTCLOUD_DATA")" "$(basename "$NEXTCLOUD_DATA")"; then
        log_error "Failed to backup Nextcloud data directory"
        return 1
    fi
    
    log_success "File backup completed"
}

# Backup Nextcloud configuration
backup_config() {
    log_info "Backing up Nextcloud configuration..."
    
    # Backup config directory
    if ! cp -a "$NEXTCLOUD_ROOT/config" "$CURRENT_BACKUP_DIR/config/"; then
        log_error "Failed to backup Nextcloud configuration"
        return 1
    }
    
    # Backup .htaccess and .user.ini files
    cp -a "$NEXTCLOUD_ROOT/.htaccess" "$CURRENT_BACKUP_DIR/config/" 2>/dev/null || true
    cp -a "$NEXTCLOUD_ROOT/.user.ini" "$CURRENT_BACKUP_DIR/config/" 2>/dev/null || true
    
    log_success "Configuration backup completed"
}

# Main backup function
main() {
    log_section "Starting Nextcloud Backup"
    
    # Initialize backup directory
    init_backup_dir || return 1
    
    log_info "Backing up from: $NEXTCLOUD_ROOT"
    log_info "Backup destination: $CURRENT_BACKUP_DIR"
    
    # Put Nextcloud in maintenance mode
    if ! sudo -u www-data php "$NEXTCLOUD_ROOT/occ" maintenance:mode --on; then
        log_warning "Failed to enable maintenance mode, continuing with backup..."
    fi
    
    # Run backup components
    local success=true
    
    log_info "Starting database backup..."
    if ! backup_database; then
        log_error "Database backup failed"
        success=false
    fi
    
    log_info "Starting file backup..."
    if ! backup_files; then
        log_error "File backup failed"
        success=false
    fi
    
    log_info "Starting configuration backup..."
    if ! backup_config; then
        log_error "Configuration backup failed"
        success=false
    fi
    
    # Turn off maintenance mode
    if ! sudo -u www-data php "$NEXTCLOUD_ROOT/occ" maintenance:mode --off; then
        log_warning "Failed to disable maintenance mode"
    fi
    
    if [ "$success" = true ]; then
        log_success "Backup completed successfully: $CURRENT_BACKUP_DIR"
        # Create a symlink to the latest backup
        ln -sfn "$CURRENT_BACKUP_DIR" "$BACKUP_DIR/latest"
        return 0
    else
        log_error "Backup completed with errors"
        return 1
    fi
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
