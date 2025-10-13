#!/bin/bash
# Database Optimization Script
# Optimizes Nextcloud database tables and cleans up

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment
load_environment
init_logging

# Default database configuration (overridden by .env)
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

# Main function
main() {
    log_section "Starting Database Optimization"
    
    if [ "$DB_TYPE" != "mysql" ] && [ "$DB_TYPE" != "mariadb" ]; then
        log_error "Unsupported database type: $DB_TYPE. Only MySQL/MariaDB is supported."
        return 1
    fi
    
    optimize_mysql
    return $?
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
