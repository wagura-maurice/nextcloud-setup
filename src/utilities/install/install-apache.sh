#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Installing Apache Web Server"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Install Apache2
if ! command -v apache2 >/dev/null 2>&1; then
    log_info "Installing Apache2 and required modules..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        apache2 \
        libapache2-mod-fcgid \
        ssl-cert
    
    # Enable required modules
    a2enmod proxy_fcgi setenvif
    
    # Enable MPM Event
    a2dismod mpm_prefork -f 2>/dev/null || true
    a2dismod mpm_worker -f 2>/dev/null || true
    a2enmod mpm_event
    
    log_success "Apache2 installed successfully"
else
    log_info "Apache2 is already installed"
fi

# Verify installation
if ! command -v apache2 >/dev/null 2>&1; then
    log_error "Apache2 installation failed"
    exit 1
fi

log_success "Apache web server installation completed"
log_info "Run the configuration script to set up Apache for Nextcloud:"
log_info "  ./src/utilities/configure/configure-apache.sh"
