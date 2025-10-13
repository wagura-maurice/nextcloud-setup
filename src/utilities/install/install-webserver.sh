#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Installing Web Server"

# Install Apache2
if ! command -v apache2 >/dev/null 2>&1; then
    log_info "Installing Apache2..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y apache2
else
    log_info "Apache2 is already installed"
fi

# Enable required modules
log_info "Enabling required Apache modules..."
a2enmod rewrite headers env dir mime ssl

log_success "Web server installation completed"
