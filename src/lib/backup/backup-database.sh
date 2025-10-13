#!/bin/bash
# Database Backup Script
# Handles backup of Nextcloud database

# Load core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"

# Check if backup directory is provided
if [ -z "$1" ]; then
    log_error "Backup directory not specified"
    exit 1
fi

BACKUP_DIR="$1/db"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Default database configuration
DB_TYPE="${DB_TYPE:-mysql}"
DB_HOST="${DB_HOST:-localhost}"
DB_NAME="${DB_NAME:-nextcloud}"
DB_USER="${DB_USER:-nextcloud}"
DB_PASS="${DB_PASS:-}"

# Create backup directory
mkdir -p "$BACKUP_DIR" || {
    log_error "Failed to create database backup directory"
    exit 1
}

# Backup MySQL/MariaDB
backup_mysql() {
    local dump_file="$BACKUP_DIR/nextcloud-db-$TIMESTAMP.sql"
    
    log_info "Backing up MySQL database: $DB_NAME"
    
    if ! command -v mysqldump &> /dev/null; then
        log_error "mysqldump command not found. Please install MySQL client tools."
        return 1
    fi
    
    # Run mysqldump with credentials
    if ! MYSQL_PWD="$DB_PASS" mysqldump --single-transaction --quick \
        -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" > "$dump_file"; then
        log_error "Failed to create database dump"
        return 1
    fi
    
    # Compress the dump
    if ! gzip -f "$dump_file"; then
        log_error "Failed to compress database dump"
        return 1
    fi
    
    log_success "Database backup created: ${dump_file}.gz"
    return 0
}

# Backup PostgreSQL
backup_postgresql() {
    local dump_file="$BACKUP_DIR/nextcloud-db-$TIMESTAMP.pgsql"
    
    log_info "Backing up PostgreSQL database: $DB_NAME"
    
    if ! command -v pg_dump &> /dev/null; then
        log_error "pg_dump command not found. Please install PostgreSQL client tools."
        return 1
    fi
    
    # Run pg_dump with credentials
    if ! PGPASSWORD="$DB_PASS" pg_dump -h "$DB_HOST" -U "$DB_USER" -F c -b -v -f "$dump_file" "$DB_NAME"; then
        log_error "Failed to create database dump"
        return 1
    fi
    
    log_success "Database backup created: $dump_file"
    return 0
}

# Main function
main() {
    log_section "Starting Database Backup"
    
    case "$DB_TYPE" in
        mysql|mariadb)
            backup_mysql
            ;;
        postgresql|postgres)
            backup_postgresql
            ;;
        *)
            log_error "Unsupported database type: $DB_TYPE"
            return 1
            ;;
    esac
    
    return $?
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
