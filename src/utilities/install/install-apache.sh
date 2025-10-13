#!/bin/bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Set project root and core directories
PROJECT_ROOT="${SCRIPT_DIR}"
SRC_DIR="${PROJECT_ROOT}/src"
CORE_DIR="${SRC_DIR}/core"
UTILS_DIR="${SRC_DIR}/utilities"

# Export environment variables
export PROJECT_ROOT SRC_DIR CORE_DIR UTILS_DIR

# Add core directory to PATH
export PATH="${CORE_DIR}:${PATH}"

# Load core configuration and utilities
for file in "${CORE_DIR}/config-manager.sh" "${CORE_DIR}/env-loader.sh" "${CORE_DIR}/logging.sh"; do
    if [[ ! -f "${file}" ]]; then
        echo "[ERROR] Required file not found: ${file}" >&2
        exit 1
    fi
    source "${file}" || {
        echo "[ERROR] Failed to load ${file}" >&2
        exit 1
    }
done

# Initialize environment and logging
load_environment
init_logging

log_section "Apache Web Server Installation"

# Configuration
readonly PACKAGE_MANAGER="apt-get"
readonly INSTALL_OPTS="-y --no-install-recommends"
readonly MAX_RETRIES=3
readonly RETRY_DELAY=5
readonly REQUIRED_PACKAGES=(
    apache2
    apache2-utils
    libapache2-mod-fcgid
    ssl-cert
    libapache2-mod-http2
    libapache2-mod-security2
)

# Function to check for running services that might conflict with Apache
check_conflicting_services() {
    local conflicts=("nginx" "lighttpd" "httpd")
    local conflict_found=0
    
    log_info "Checking for conflicting services..."
    
    for service in "${conflicts[@]}"; do
        if systemctl is-active --quiet "${service}" 2>/dev/null; then
            log_warning "Conflicting service found: ${service}. It's recommended to stop it before continuing."
            conflict_found=1
        fi
    done
    
    if [ $conflict_found -eq 1 ]; then
        log_warning "Conflicting services detected. You may need to stop them before proceeding."
        return 1
    fi
    
    return 0
}

# Function to check if a port is in use
is_port_in_use() {
    local port=$1
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i ":${port}" >/dev/null 2>&1; then
            return 0
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":${port} "; then
            return 0
        fi
    fi
    return 1
}

# Function to check system requirements
check_system_requirements() {
    log_info "Checking system requirements..."
    
    # Check for root privileges
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root. Please use 'sudo' or run as root user."
        return 1
    fi
    
    # Check for package manager
    if ! command -v ${PACKAGE_MANAGER} >/dev/null 2>&1; then
        log_error "Package manager '${PACKAGE_MANAGER}' not found. This script requires a Debian-based system."
        return 1
    fi
    
    # Check for systemd
    if ! command -v systemctl >/dev/null 2>&1; then
        log_error "systemd is not available. This script requires a systemd-based system."
        return 1
    fi
    
    # Check for required ports
    for port in 80 443; do
        if is_port_in_use "${port}"; then
            log_warning "Port ${port} is already in use. This may cause issues with Apache."
        fi
    done
    
    return 0
}

# Function to install a single package with retries
install_package() {
    local package=$1
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        log_info "Installing ${package} (attempt ${attempt}/${MAX_RETRIES})..."
        
        if ${PACKAGE_MANAGER} install ${INSTALL_OPTS} "${package}" 2>&1; then
            log_success "Successfully installed ${package}"
            return 0
        fi
        
        log_warning "Failed to install ${package} on attempt ${attempt}"
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            log_info "Retrying in ${RETRY_DELAY} seconds..."
            sleep $RETRY_DELAY
        fi
        
        ((attempt++))
    done
    
    log_error "Failed to install ${package} after ${MAX_RETRIES} attempts"
    return 1
}

# Function to install required packages
install_apache_packages() {
    log_info "Updating package lists..."
    
    # Update package lists with retries
    local update_attempt=1
    while [ $update_attempt -le $MAX_RETRIES ]; do
        if ${PACKAGE_MANAGER} update; then
            break
        fi
        
        log_warning "Failed to update package lists (attempt ${update_attempt}/${MAX_RETRIES})"
        if [ $update_attempt -eq $MAX_RETRIES ]; then
            log_error "Failed to update package lists after ${MAX_RETRIES} attempts"
            return 1
        fi
        
        sleep $RETRY_DELAY
        ((update_attempt++))
    done
    
    log_info "Installing Apache2 and required modules..."
    
    # Install each package individually with retries
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! install_package "${package}"; then
            log_error "Failed to install required package: ${package}"
            return 1
        fi
    done
    
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
    
    if [ "$success" = true ]; then
        log_success "Apache installation verification completed successfully"
        return 0
    else
        log_error "Apache installation verification failed"
        return 1
    fi
}

# Main installation function
install_apache() {
    local success=true
    
    log_section "Starting Apache installation"
    
    # Check system requirements
    if ! check_system_requirements; then
        log_error "System requirements check failed"
        return 1
    fi
    
    # Check for conflicting services
    check_conflicting_services || {
        log_warning "Conflicting services check failed. Continuing, but issues may occur."
    }
    
    # Install Apache if not already installed
    if ! command -v apache2 >/dev/null 2>&1; then
        log_info "Apache not found. Starting installation..."
        
        if ! install_apache_packages; then
            log_error "Failed to install Apache packages"
            success=false
        elif ! configure_apache_modules; then
            log_error "Failed to configure Apache modules"
            success=false
        fi
    else
        log_info "Apache is already installed"
    fi
    
    # Verify the installation
    if [ "$success" = true ]; then
        if ! verify_apache_installation; then
            success=false
            log_error "Apache installation verification failed"
        fi
    fi
    
    # Final status
    if [ "$success" = true ]; then
        log_success "Apache web server installation completed successfully"
        log_info "Run the configuration script to set up Apache for Nextcloud:"
        log_info "  ./src/utilities/configure/configure-apache.sh"
        return 0
    else
        log_error "Apache installation completed with errors"
        log_info "Troubleshooting tips:"
        log_info "1. Check for conflicting services: systemctl list-units --type=service | grep -E 'apache2|nginx|httpd'"
        log_info "2. Check Apache error logs: journalctl -u apache2 -n 50 --no-pager"
        log_info "3. Verify port availability: ss -tulpn | grep -E ':80|:443'"
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
