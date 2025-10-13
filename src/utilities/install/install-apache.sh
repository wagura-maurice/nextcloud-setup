#!/bin/bash
set -euo pipefail

# Set project root and core directories
PROJECT_ROOT="/root/nextcloud-setup"
CORE_DIR="${PROJECT_ROOT}/src/core"

# Source core utilities
source "${CORE_DIR}/config-manager.sh" 2>/dev/null || { 
    echo "Error: Failed to load ${CORE_DIR}/config-manager.sh" >&2
    exit 1
}
source "${CORE_DIR}/env-loader.sh" 2>/dev/null || { 
    echo "Error: Failed to load ${CORE_DIR}/env-loader.sh" >&2
    exit 1
}
source "${CORE_DIR}/logging.sh" 2>/dev/null || { 
    echo "Error: Failed to load ${CORE_DIR}/logging.sh" >&2
    exit 1
}

# Initialize environment and logging
load_environment
init_logging

log_section "Apache Installation"

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

# Function to install packages with retries
install_packages() {
    local packages=("$@")
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        log_info "Installing packages (attempt $attempt of $MAX_RETRIES)..."
        if $PACKAGE_MANAGER install $INSTALL_OPTS "${packages[@]}"; then
            return 0
        fi
        log_warning "Package installation failed, retrying in $RETRY_DELAY seconds..."
        sleep $RETRY_DELAY
        ((attempt++))
    done
    
    log_error "Failed to install packages after $MAX_RETRIES attempts"
    return 1
}

# Function to configure Apache modules
configure_apache_modules() {
    log_info "Configuring Apache modules..."
    
    local required_modules=(
        rewrite
        headers
        env
        dir
        mime
        setenvif
        ssl
        proxy_fcgi
        http2
        alias
        authz_core
        deflate
        filter
        mpm_event
    )
    
    for module in "${required_modules[@]}"; do
        if ! a2enmod -q "$module"; then
            log_warning "Failed to enable Apache module: $module"
        fi
    done
    
    # Disable mpm_prefork if mpm_event is enabled
    if a2query -M | grep -q 'event'; then
        a2dismod -q mpm_prefork 2>/dev/null || true
    fi
    
    log_success "Apache modules configured"
    return 0
}

# Function to set up initial Apache configuration
setup_apache_config() {
    log_info "Setting up Apache configuration..."
    
    # Create backup of original config
    cp -f /etc/apache2/apache2.conf /etc/apache2/apache2.conf.bak
    
    # Update main Apache configuration
    cat > /etc/apache2/conf-available/nextcloud-optimized.conf << 'EOF'
# Security headers
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set X-Robots-Tag "none"
    Header always set X-Download-Options "noopen"
    Header always set X-Permitted-Cross-Domain-Policies "none"
    Header always set Referrer-Policy "no-referrer"
</IfModule>

# Disable server signature
ServerSignature Off
ServerTokens Prod

# Enable Keep-Alive
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5

# MPM Event configuration
<IfModule mpm_event_module>
    StartServers             2
    MinSpareThreads         25
    MaxSpareThreads         75
    ThreadLimit             64
    ThreadsPerChild         25
    MaxRequestWorkers      150
    MaxConnectionsPerChild   0
</IfModule>
EOF

    # Enable the configuration
    a2enconf nextcloud-optimized >/dev/null
    
    log_success "Apache configuration updated"
    return 0
}

# Function to install Apache
install_apache() {
    log_info "Starting Apache installation..."
    
    # Check for conflicting services
    if ! check_conflicting_services; then
        log_warning "Conflicting services found. Installation may not work correctly."
    fi
    
    # Check for port conflicts
    for port in 80 443; do
        if is_port_in_use "$port"; then
            log_warning "Port $port is already in use. This may cause issues with Apache."
        fi
    done
    
    # Add universe repository and update package lists
    log_info "Adding universe repository and updating package lists..."
    if ! add-apt-repository -y universe || ! $PACKAGE_MANAGER update; then
        log_error "Failed to update package lists"
        return 1
    fi
    
    # Install required packages
    if ! install_packages "${REQUIRED_PACKAGES[@]}"; then
        log_error "Failed to install required packages"
        return 1
    fi
    
    # Configure Apache modules
    if ! configure_apache_modules; then
        log_error "Failed to configure Apache modules"
        return 1
    fi
    
    # Set up initial configuration
    if ! setup_apache_config; then
        log_error "Failed to set up Apache configuration"
        return 1
    fi
    
    # Enable and start Apache
    log_info "Starting Apache service..."
    if ! systemctl enable --now apache2; then
        log_error "Failed to start Apache service"
        return 1
    fi
    
    log_success "Apache installation completed successfully"
    return 0
}

# Main function
main() {
    log_section "Starting Apache Installation"
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        return 1
    fi
    
    # Install Apache
    if ! install_apache; then
        log_error "Apache installation failed"
        return 1
    fi
    
    log_success "Apache installation and configuration completed successfully"
    log_info "Apache version: $(apache2 -v | head -n1)"
    return 0
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    exit $?
fi