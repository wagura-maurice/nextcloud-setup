#!/bin/bash
set -euo pipefail

# Set project root directory
PROJECT_ROOT="/root/nextcloud-setup"

# Load core configuration and utilities
source "${PROJECT_ROOT}/src/core/config-manager.sh"
source "${PROJECT_ROOT}/src/core/logging.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "System Dependencies Installation"

# Configuration
readonly PACKAGE_MANAGER="apt-get"
readonly INSTALL_OPTS="-y --no-install-recommends"
readonly REQUIRED_PACKAGES=(
    # System utilities
    apt-transport-https ca-certificates curl gnupg lsb-release
    software-properties-common unzip wget htop net-tools vim
    git jq supervisor logrotate cron rsync fail2ban ufw
    locales tzdata acl sudo
    
    # Build essentials
    build-essential pkg-config autoconf automake libtool make g++
    
    # SSL/TLS
    openssl ssl-cert python3-pip
    
    # Monitoring
    dstat iotop iftop nmon sysstat lsof strace lshw hdparm smartmontools
)

# Function to install packages with error handling
install_packages() {
    local packages=("$@")
    log_info "Installing packages: ${packages[*]}"
    
    if ! ${PACKAGE_MANAGER} install ${INSTALL_OPTS} "${packages[@]}"; then
        log_error "Failed to install packages"
        return 1
    fi
    
    return 0
}

# Function to update package lists
update_package_lists() {
    log_info "Updating package lists..."
    if ! ${PACKAGE_MANAGER} update; then
        log_error "Failed to update package lists"
        return 1
    fi
    return 0
}

# Function to configure firewall
configure_firewall() {
    log_info "Configuring firewall..."
    
    # Allow SSH, HTTP, HTTPS
    for port in 22 80 443; do
        if ! ufw allow "${port}" >/dev/null 2>&1; then
            log_warning "Failed to allow port ${port} in firewall"
        fi
    done
    
    # Enable firewall
    if ! ufw --force enable >/dev/null 2>&1; then
        log_warning "Failed to enable UFW"
    fi
}

# Function to clean up
cleanup() {
    log_info "Cleaning up..."
    ${PACKAGE_MANAGER} autoremove -y
    ${PACKAGE_MANAGER} clean
    rm -rf /var/lib/apt/lists/*
}

# Main installation function
install_system_dependencies() {
    local success=true
    
    # Update package lists
    if ! update_package_lists; then
        success=false
    fi
    
    # Install required packages
    if ! install_packages "${REQUIRED_PACKAGES[@]}"; then
        success=false
    fi
    
    # Configure firewall
    if ! configure_firewall; then
        success=false
    fi
    
    # Clean up
    cleanup
    
    # Final status
    if [ "${success}" = true ]; then
        log_success "System dependencies installation completed successfully"
        return 0
    else
        log_error "System dependencies installation completed with errors"
        return 1
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    install_system_dependencies
    exit $?
fi
