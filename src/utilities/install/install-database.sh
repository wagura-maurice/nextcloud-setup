#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Installing Database Server"

# Install MariaDB server
if ! command -v mariadb >/dev/null 2>&1; then
    log_info "Installing MariaDB server..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server
else
    log_info "MariaDB is already installed"
fi

# Generate secure passwords if not set
DB_ROOT_PASS="${DB_ROOT_PASS:-$(openssl rand -hex 32)}"

echo "DB_ROOT_PASS=$DB_ROOT_PASS" > "$SCRIPT_DIR/.db_credentials"
chmod 600 "$SCRIPT_DIR/.db_credentials"

# Secure the installation
log_info "Securing MariaDB installation..."
mysql_secure_installation <<EOF
y
${DB_ROOT_PASS}
${DB_ROOT_PASS}
y
y
y
y
y
EOF

log_success "Database server installation completed"
