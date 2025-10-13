#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Configuring MariaDB Database for Nextcloud"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Load database credentials
if [ -f "$SCRIPT_DIR/.db_credentials" ]; then
    # Create a backup of the credentials file
    cp "$SCRIPT_DIR/.db_credentials" "$SCRIPT_DIR/.db_credentials.bak"
    
    # Source the credentials
    source "$SCRIPT_DIR/.db_credentials"
else
    log_error "Database credentials not found. Run install-mysql.sh first."
    exit 1
fi

# Verify root access to MySQL
if ! mysql -u root -p"${DB_ROOT_PASS}" -e "SELECT 1" >/dev/null 2>&1; then
    log_error "Failed to connect to MySQL as root. Please check your root password."
    exit 1
fi

# Set database configuration
DB_NAME="${DB_NAME:-nextcloud}"
DB_USER="${DB_USER:-nextcloud}"
DB_PASS="${DB_PASS:-$(openssl rand -base64 24)}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"

# Validate database name and username
if ! [[ "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
    log_error "Invalid database name. Only alphanumeric and underscore characters are allowed."
    exit 1
fi

if ! [[ "$DB_USER" =~ ^[a-zA-Z0-9_]+$ ]]; then
    log_error "Invalid database username. Only alphanumeric and underscore characters are allowed."
    exit 1
fi

log_info "Configuring database '${DB_NAME}' for user '${DB_USER}'..."

# Create a temporary file for SQL commands
SQL_FILE="$(mktemp)"
cat > "$SQL_FILE" <<EOF
-- Create the database if it doesn't exist
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` 
    CHARACTER SET utf8mb4 
    COLLATE utf8mb4_unicode_ci;

-- Create the user if it doesn't exist
CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}' 
    IDENTIFIED BY '${DB_PASS}'
    WITH 
        MAX_QUERIES_PER_HOUR 0
        MAX_UPDATES_PER_HOUR 0
        MAX_CONNECTIONS_PER_HOUR 0
        MAX_USER_CONNECTIONS 0;

-- Grant all privileges on the database to the user
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* 
    TO '${DB_USER}'@'${DB_HOST}' 
    WITH GRANT OPTION;

-- Apply the privilege changes
FLUSH PRIVILEGES;

-- Set password expiration to never
ALTER USER '${DB_USER}'@'${DB_HOST}' PASSWORD EXPIRE NEVER;

-- Set resource limits
ALTER USER '${DB_USER}'@'${DB_HOST}'
WITH 
    MAX_QUERIES_PER_HOUR 0
    MAX_UPDATES_PER_HOUR 0
    MAX_CONNECTIONS_PER_HOUR 0
    MAX_USER_CONNECTIONS 50;

-- Show the grants for the user
SHOW GRANTS FOR '${DB_USER}'@'${DB_HOST}';

-- Show database character set and collation
SELECT SCHEMA_NAME 'Database', 
       DEFAULT_CHARACTER_SET_NAME 'Charset', 
       DEFAULT_COLLATION_NAME 'Collation' 
FROM information_schema.SCHEMATA 
WHERE SCHEMA_NAME = '${DB_NAME}';
EOF

# Execute the SQL commands
log_info "Creating database and user..."
if ! mysql -u root -p"${DB_ROOT_PASS}" < "$SQL_FILE"; then
    log_error "Failed to configure the database"
    rm -f "$SQL_FILE"
    exit 1
fi

# Clean up the temporary file
rm -f "$SQL_FILE"

# Update the credentials file with the new database and user
cat > "$SCRIPT_DIR/.db_credentials" <<EOF
# MariaDB root credentials
DB_ROOT_PASS='${DB_ROOT_PASS}'

# Database connection details
DB_HOST='${DB_HOST}'
DB_PORT='${DB_PORT}'
DB_SOCKET='${DB_SOCKET:-/var/run/mysqld/mysqld.sock}'

# Nextcloud database credentials
DB_NAME='${DB_NAME}'
DB_USER='${DB_USER}'
DB_PASS='${DB_PASS}'

# Connection strings
MYSQL_CMD="mysql -u ${DB_USER} -p'${DB_PASS}' -h ${DB_HOST} -P ${DB_PORT} ${DB_NAME}"
MYSQL_DUMP_CMD="mysqldump -u ${DB_USER} -p'${DB_PASS}' -h ${DB_HOST} -P ${DB_PORT} ${DB_NAME}"

# How to connect as root:
# mysql -u root -p\$DB_ROOT_PASS
# or
# mysql --defaults-file=/root/.my.cnf

# How to connect as the Nextcloud user:
# mysql -u ${DB_USER} -p'${DB_PASS}' -h ${DB_HOST} -P ${DB_PORT} ${DB_NAME}

# How to backup the database:
# mysqldump -u ${DB_USER} -p'${DB_PASS}' -h ${DB_HOST} -P ${DB_PORT} --single-transaction --quick --lock-tables=false ${DB_NAME} | gzip > nextcloud_db_\$(date +%Y%m%d).sql.gz

# How to restore the database:
# gunzip < nextcloud_db_YYYYMMDD.sql.gz | mysql -u ${DB_USER} -p'${DB_PASS}' -h ${DB_HOST} -P ${DB_PORT} ${DB_NAME}
EOF

# Set proper permissions
chmod 600 "$SCRIPT_DIR/.db_credentials"

# Create a read-only credentials file for non-root users
cat > "$SCRIPT_DIR/.db_credentials.readonly" <<EOF
# Nextcloud database connection details
DB_HOST='${DB_HOST}'
DB_PORT='${DB_PORT}'
DB_NAME='${DB_NAME}'
DB_USER='${DB_USER}'
DB_PASS='${DB_PASS}'

# Example connection command:
# mysql -u ${DB_USER} -p'${DB_PASS}' -h ${DB_HOST} -P ${DB_PORT} ${DB_NAME}
EOF
chmod 640 "$SCRIPT_DIR/.db_credentials.readonly"
chown root:www-data "$SCRIPT_DIR/.db_credentials.readonly"

# Create a test connection script
cat > "$SCRIPT_DIR/test-db-connection.sh" <<'EOF'
#!/bin/bash
# Test database connection

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.db_credentials" ]; then
    source "$SCRIPT_DIR/.db_credentials"
else
    echo "Error: Database credentials not found"
    exit 1
fi

# Test connection
echo "Testing database connection..."
if mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -P "$DB_PORT" -e "SELECT 1" "$DB_NAME" 2>/dev/null; then
    echo "✅ Database connection successful!"
    echo "  - Database: $DB_NAME"
    echo "  - User: $DB_USER"
    echo "  - Host: $DB_HOST"
    echo "  - Port: $DB_PORT"
    
    # Show database size
    echo -e "\n📊 Database size:"
    mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -P "$DB_PORT" -e "
        SELECT 
            table_schema as 'Database', 
            ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as 'Size (MB)' 
        FROM information_schema.tables 
        WHERE table_schema = '$DB_NAME' 
        GROUP BY table_schema;"
    
    # Show tables and their row counts
    echo -e "\n📋 Tables and row counts:"
    mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -P "$DB_PORT" "$DB_NAME" -e "
        SELECT 
            table_name as 'Table', 
            table_rows as 'Rows',
            ROUND(((data_length + index_length) / 1024 / 1024), 2) as 'Size (MB)'
        FROM information_schema.TABLES 
        WHERE table_schema = '$DB_NAME' 
        ORDER BY (data_length + index_length) DESC;"
else
    echo "❌ Database connection failed"
    exit 1
fi
EOF

chmod +x "$SCRIPT_DIR/test-db-connection.sh"

log_success "Database configuration completed successfully"
log_info "Database Name: ${DB_NAME}"
log_info "Database User: ${DB_USER}"
log_info "Database Host: ${DB_HOST}"
log_info "Database Port: ${DB_PORT}"
log_info ""
log_info "🔐 Database credentials saved to:"
log_info "  - $SCRIPT_DIR/.db_credentials (root access)"
log_info "  - $SCRIPT_DIR/.db_credentials.readonly (read-only for www-data)"
log_info ""
log_info "🔍 Test the database connection with:"
log_info "  $SCRIPT_DIR/test-db-connection.sh"
log_info ""
log_info "Next steps:"
log_info "1. Update your Nextcloud config.php with these database credentials"
log_info "2. Run the Nextcloud installation script"
log_info "3. Consider setting up automated backups"
