#!/bin/bash
# Database Optimization Script
# Optimizes Nextcloud database tables and cleans up

# Load core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"

# Default database configuration
DB_TYPE="${DB_TYPE:-mysql}"
DB_HOST="${DB_HOST:-localhost}"
DB_NAME="${DB_NAME:-nextcloud}"
DB_USER="${DB_USER:-nextcloud}"
DB_PASS="${DB_PASS:-}"

# Optimize MySQL/MariaDB tables
optimize_mysql() {
    log_info "Optimizing MySQL/MariaDB tables"
    
    if ! command -v mysql &> /dev/null; then
        log_error "mysql command not found"
        return 1
    fi
    
    # Get list of tables
    local tables
    tables=$(MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" -N -e "SHOW TABLES;" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_error "Failed to get list of tables"
        return 1
    fi
    
    # Optimize each table
    local count=0
    for table in $tables; do
        log_debug "Optimizing table: $table"
        if MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" -e "OPTIMIZE TABLE \`$table\`;" &>/dev/null; then
            ((count++))
        else
            log_warning "Failed to optimize table: $table"
        fi
    done
    
    log_success "Optimized $count tables"
    return 0
}

# Optimize PostgreSQL database
optimize_postgresql() {
    log_info "Optimizing PostgreSQL database"
    
    if ! command -v psql &> /dev/null; then
        log_error "psql command not found"
        return 1
    }
    
    # Run VACUUM ANALYZE
    if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "VACUUM ANALYZE;" &>/dev/null; then
        log_success "Database optimization completed"
        return 0
    else
        log_error "Failed to optimize PostgreSQL database"
        return 1
    fi
}

# Main function
main() {
    log_section "Starting Database Optimization"
    
    case "$DB_TYPE" in
        mysql|mariadb)
            optimize_mysql
            ;;
        postgresql|postgres)
            optimize_postgresql
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
