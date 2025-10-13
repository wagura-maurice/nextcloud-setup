#!/bin/bash
# Database Restore Script
# Restores Nextcloud database from backup

# Load core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"

# Check if backup directory is provided
if [ -z "$1" ] || [ ! -d "$1" ]; then
    log_error "Backup directory not specified or invalid"
    exit 1
fi

BACKUP_DIR="$1"

# Default database configuration
DB_TYPE="${DB_TYPE:-mysql}"
DB_HOST="${DB_HOST:-localhost}"
DB_NAME="${DB_NAME:-nextcloud}"
DB_USER="${DB_USER:-nextcloud}"
DB_PASS="${DB_PASS:-}"

# Restore MySQL/MariaDB database
restore_mysql() {
    local sql_file
    
    # Find the latest SQL dump
    sql_file=$(find "$BACKUP_DIR" -name "*.sql.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -z "$sql_file" ]; then
        log_error "No SQL dump found in $BACKUP_DIR"
        return 1
    fi
    
    log_info "Found database dump: $sql_file"
    
    # Drop and recreate the database
    log_info "Recreating database: $DB_NAME"
    if ! MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -u "$DB_USER" -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\`;" 2>/dev/null; then
        log_error "Failed to recreate database"
        return 1
    fi
    
    # Restore the database
    log_info "Restoring database from backup..."
    if ! gunzip -c "$sql_file" | MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME"; then
        log_error "Failed to restore database"
        return 1
    fi
    
    log_success "Database restored successfully"
    return 0
}

# Restore PostgreSQL database
restore_postgresql() {
    local dump_file
    
    # Find the latest PostgreSQL dump
    dump_file=$(find "$BACKUP_DIR" -name "*.pgsql" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -z "$dump_file" ]; then
        log_error "No PostgreSQL dump found in $BACKUP_DIR"
        return 1
    fi
    
    log_info "Found database dump: $dump_file"
    
    # Drop and recreate the database
    log_info "Recreating database: $DB_NAME"
    if ! PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$DB_NAME\";" ||
       ! PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$DB_NAME\" WITH OWNER \"$DB_USER\" ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' TEMPLATE=template0;" 2>/dev/null; then
        log_error "Failed to recreate database"
        return 1
    fi
    
    # Restore the database
    log_info "Restoring database from backup..."
    if ! PGPASSWORD="$DB_PASS" pg_restore -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" "$dump_file"; then
        log_error "Failed to restore database"
        return 1
    fi
    
    log_success "Database restored successfully"
    return 0
}

# Main function
main() {
    log_section "Starting Database Restore"
    
    # Check if we have database credentials
    if [ -z "$DB_PASS" ]; then
        log_error "Database password not set. Please set DB_PASS environment variable."
        return 1
    fi
    
    case "$DB_TYPE" in
        mysql|mariadb)
            restore_mysql
            ;;
        postgresql|postgres)
            restore_postgresql
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
