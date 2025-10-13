#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Configuring Database"

# Load database credentials
if [ -f "$SCRIPT_DIR/.db_credentials" ]; then
    source "$SCRIPT_DIR/.db_credentials"
else
    log_error "Database credentials not found. Run install-database.sh first."
    exit 1
fi

# Set default values if not provided
DB_NAME="${DB_NAME:-nextcloud}"
DB_USER="${DB_USER:-nextcloud}"
DB_PASS="${DB_PASS:-$(openssl rand -hex 16)}"

# Create database and user
log_info "Creating database and user..."
mysql -u root -p"${DB_ROOT_PASS}" <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# Save database credentials
echo "DB_NAME=$DB_NAME" >> "$SCRIPT_DIR/.db_credentials"
echo "DB_USER=$DB_USER" >> "$SCRIPT_DIR/.db_credentials"
echo "DB_PASS=$DB_PASS" >> "$SCRIPT_DIR/.db_credentials"
chmod 600 "$SCRIPT_DIR/.db_credentials"

log_success "Database configuration completed"
