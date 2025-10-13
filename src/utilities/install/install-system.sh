#!/bin/bash
set -euo pipefail

# Set fixed paths based on the known repository structure
PROJECT_ROOT="/root/nextcloud-setup"
CORE_DIR="${PROJECT_ROOT}/src/core"

# Export environment variables
export PROJECT_ROOT CORE_DIR

# Set other default environment variables
: "${SRC_DIR:=${PROJECT_ROOT}/src}"
: "${UTILS_DIR:=${SRC_DIR}/utilities}"
: "${LOG_DIR:=${PROJECT_ROOT}/logs}"
: "${CONFIG_DIR:=${PROJECT_ROOT}/config}"
: "${DATA_DIR:=${PROJECT_ROOT}/data}"
: "${ENV_FILE:=${PROJECT_ROOT}/.env}"

export SRC_DIR CORE_DIR UTILS_DIR LOG_DIR CONFIG_DIR DATA_DIR ENV_FILE

# Create required directories
mkdir -p "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/tmp"
chmod 750 "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/tmp"

# Load core utilities
source "${CORE_DIR}/env-loader.sh"
source "${CORE_DIR}/config-manager.sh"
source "${CORE_DIR}/logging.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "System Dependencies Installation"

# Load configuration
if ! load_installation_config; then
    log_error "Failed to load installation configuration"
    exit 1
fi

# Configuration
readonly PACKAGE_MANAGER="apt-get"
readonly INSTALL_OPTS="-y --no-install-recommends"

# Define required packages based on configuration
REQUIRED_PACKAGES=(
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

# Add database packages based on configuration
if [ "${DB_TYPE:-mysql}" = "mysql" ]; then
    REQUIRED_PACKAGES+=(
        mysql-server
        mysql-client
        libmysqlclient-dev
    )
else
    REQUIRED_PACKAGES+=(
        postgresql
        postgresql-contrib
        postgresql-client
        libpq-dev
    )
fi

# Add web server packages
if [ "${WEB_SERVER:-apache}" = "apache" ]; then
    REQUIRED_PACKAGES+=(
        apache2
        libapache2-mod-php${PHP_VERSION}
        libapache2-mod-security2
    )
else
    REQUIRED_PACKAGES+=(
        nginx
        php${PHP_VERSION}-fpm
    )
fi

# Add PHP packages
REQUIRED_PACKAGES+=(
    php${PHP_VERSION}
    php${PHP_VERSION}-common
    php${PHP_VERSION}-mysql
    php${PHP_VERSION}-gd
    php${PHP_VERSION}-xml
    php${PHP_VERSION}-curl
    php${PHP_VERSION}-mbstring
    php${PHP_VERSION}-intl
    php${PHP_VERSION}-zip
    php${PHP_VERSION}-bcmath
    php${PHP_VERSION}-imagick
    php${PHP_VERSION}-gmp
    php${PHP_VERSION}-apcu
    php${PHP_VERSION}-redis
    php${PHP_VERSION}-opcache
    php${PHP_VERSION}-cli
    php${PHP_VERSION}-bz2
    php${PHP_VERSION}-soap
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
