#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Installing Redis"

# Install Redis server
if ! command -v redis-server >/dev/null 2>&1; then
    log_info "Installing Redis server..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server
else
    log_info "Redis is already installed"
fi

# Enable and start Redis service
systemctl enable redis-server
systemctl restart redis-server

# Install PHP Redis extension if PHP is installed
if command -v php8.4 >/dev/null 2>&1; then
    log_info "Installing PHP Redis extension..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y php8.4-redis
    systemctl restart "php8.4-fpm"
fi

log_success "Redis installation completed"
