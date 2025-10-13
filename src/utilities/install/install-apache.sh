#!/bin/bash
set -euo pipefail

# Load core configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/src/core/config-manager.sh"
source "${SCRIPT_DIR}/src/core/env-loader.sh"
source "${SCRIPT_DIR}/src/core/logging.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Apache Web Server Installation"

# Configuration
readonly PACKAGE_MANAGER="apt-get"
readonly INSTALL_OPTS="-y --no-install-recommends"
readonly REQUIRED_PACKAGES=(
    apache2
    apache2-utils
    libapache2-mod-fcgid
    ssl-cert
    libapache2-mod-http2
    libapache2-mod-security2
)

# Function to install required packages
install_apache_packages() {
    log_info "Installing Apache2 and required modules..."
    
    # Update package lists
    if ! ${PACKAGE_MANAGER} update; then
        log_error "Failed to update package lists"
        return 1
    fi
    
    # Install required packages
    if ! ${PACKAGE_MANAGER} install ${INSTALL_OPTS} "${REQUIRED_PACKAGES[@]}"; then
        log_error "Failed to install Apache packages"
        return 1
    fi
    
    return 0
}

# Function to configure Apache modules
configure_apache_modules() {
    log_info "Configuring Apache modules..."
    
    # Disable default modules
    local modules_to_disable=(
        mpm_prefork
        mpm_worker
        autoindex
        status
    )
    
    for module in "${modules_to_disable[@]}"; do
        if a2query -m "${module}" >/dev/null 2>&1; then
            if ! a2dismod -f "${module}"; then
                log_warning "Failed to disable module: ${module}"
            fi
        fi
    done
    
    # Enable required modules
    local modules_to_enable=(
        mpm_event
        proxy_fcgi
        setenvif
        headers
        rewrite
        dir
        mime
        env
        ssl
        http2
        deflate
        expires
        headers
        proxy
        proxy_http
        proxy_wstunnel
        remoteip
        reqtimeout
    )
    
    for module in "${modules_to_enable[@]}"; do
        if ! a2enmod -q "${module}"; then
            log_warning "Failed to enable module: ${module}"
        fi
    done
    
    return 0
}

# Function to verify Apache installation
verify_apache_installation() {
    log_info "Verifying Apache installation..."
    
    if ! command -v apache2 >/dev/null 2>&1; then
        log_error "Apache2 installation failed - binary not found"
        return 1
    fi
    
    # Test Apache configuration
    if ! apache2ctl -t >/dev/null 2>&1; then
        log_error "Apache configuration test failed"
        apache2ctl -t
        return 1
    fi
    
    # Check if Apache is running
    if ! systemctl is-active --quiet apache2; then
        log_warning "Apache is not running, attempting to start..."
        if ! systemctl start apache2; then
            log_error "Failed to start Apache service"
            journalctl -u apache2 -n 50 --no-pager
            return 1
        fi
    fi
    
    # Enable Apache to start on boot
    if ! systemctl is-enabled --quiet apache2; then
        if ! systemctl enable apache2 >/dev/null 2>&1; then
            log_warning "Failed to enable Apache to start on boot"
        fi
    fi
    
    return 0
}

# Main installation function
install_apache() {
    local success=true
    
    if ! command -v apache2 >/dev/null 2>&1; then
        if ! install_apache_packages; then
            success=false
        fi
        
        if ! configure_apache_modules; then
            success=false
        fi
    else
        log_info "Apache is already installed"
    fi
    
    # Always verify the installation
    if ! verify_apache_installation; then
        success=false
    fi
    
    # Final status
    if [ "${success}" = true ]; then
        log_success "Apache web server installation completed successfully"
        log_info "Run the configuration script to set up Apache for Nextcloud:"
        log_info "  ./src/utilities/configure/configure-apache.sh"
        return 0
    else
        log_error "Apache installation completed with errors"
        return 1
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    install_apache
    exit $?
fi
