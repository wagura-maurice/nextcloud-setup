#!/bin/bash
set -euo pipefail

# Set project root and core directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CORE_DIR="${PROJECT_ROOT}/core"
SRC_DIR="${PROJECT_ROOT}/src"
UTILS_DIR="${SRC_DIR}/utilities"
LOG_DIR="${PROJECT_ROOT}/logs"
CONFIG_DIR="${PROJECT_ROOT}/config"
DATA_DIR="${PROJECT_ROOT}/data"
ENV_FILE="${PROJECT_ROOT}/.env"

# Export environment variables
export PROJECT_ROOT CORE_DIR SRC_DIR UTILS_DIR LOG_DIR CONFIG_DIR DATA_DIR ENV_FILE

# Create required directories
mkdir -p "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/tmp"
chmod 750 "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/tmp"

# Function to safely source core utilities
safe_source() {
    local file="$1"
    if [ -f "${file}" ]; then
        # shellcheck source=/dev/null
        source "${file}" || {
            echo "Error: Failed to load ${file}" >&2
            return 1
        }
    else
        echo "Error: Required file not found: ${file}" >&2
        return 1
    fi
}

# Source core utilities with error handling
if ! safe_source "${CORE_DIR}/config-manager.sh" || \
   ! safe_source "${CORE_DIR}/env-loader.sh" || \
   ! safe_source "${CORE_DIR}/logging.sh"; then
    exit 1
fi

# Initialize environment and logging
if ! load_environment || ! init_logging; then
    echo "Error: Failed to initialize environment and logging" >&2
    exit 1
fi

log_section "Certbot Installation"

# Default configuration values
readonly PACKAGE_MANAGER="apt-get"
readonly INSTALL_OPTS="-y --no-install-recommends"

# Required packages
readonly CERTBOT_PACKAGES=(
    "certbot"
    "python3-certbot-apache"
    "python3-certbot-dns-cloudflare"  # For CloudFlare DNS validation
    "python3-certbot-dns-route53"     # For AWS Route 53 DNS validation
    "python3-certbot-nginx"           # For Nginx plugin (if needed in the future)
    "python3-pip"
)

# Function to install required system packages
install_system_packages() {
    log_info "Installing required system packages..."
    
    # Update package lists
    if ! ${PACKAGE_MANAGER} update; then
        log_error "Failed to update package lists"
        return 1
    fi
    
    # Install required packages
    if ! DEBIAN_FRONTEND=noninteractive ${PACKAGE_MANAGER} install ${INSTALL_OPTS} "${CERTBOT_PACKAGES[@]}"; then
        log_error "Failed to install required packages"
        return 1
    fi
    
    # Install additional Python packages
    if ! pip3 install --upgrade pip certbot-dns-cloudflare certbot-dns-route53; then
        log_warning "Failed to install additional Python packages"
    fi
    
    log_success "System packages installed successfully"
    return 0
}

# Function to verify Certbot installation
verify_certbot_installation() {
    log_info "Verifying Certbot installation..."
    
    if ! command -v certbot &> /dev/null; then
        log_error "Certbot installation verification failed"
        return 1
    fi
    
    local certbot_version
    certbot_version=$(certbot --version 2>&1 | awk '{print $2}')
    
    if [[ -z "${certbot_version}" ]]; then
        log_error "Could not determine Certbot version"
        return 1
    fi
    
    log_success "Certbot ${certbot_version} is installed and working"
    return 0
}

# Function to set up Certbot directories and permissions
setup_certbot_directories() {
    log_info "Setting up Certbot directories and permissions..."
    
    local certbot_dirs=(
        "/etc/letsencrypt"
        "/var/log/letsencrypt"
        "/var/lib/letsencrypt"
        "/etc/letsencrypt/renewal-hooks/pre"
        "/etc/letsencrypt/renewal-hooks/post"
        "/etc/letsencrypt/renewal-hooks/deploy"
    )
    
    for dir in "${certbot_dirs[@]}"; do
        mkdir -p "${dir}"
        chmod 750 "${dir}"
    done
    
    # Set ownership for webroot directory if it exists
    if [ -d "/var/www/html" ]; then
        chown -R www-data:www-data "/var/www/html"
    fi
    
    log_success "Certbot directories and permissions set up successfully"
    return 0
}

# Function to create a test certificate (optional)
create_test_certificate() {
    local domain
    domain=$(get_config "domain" "")
    
    if [ -z "${domain}" ]; then
        log_warning "No domain configured. Skipping test certificate creation."
        return 0
    fi
    
    log_info "Creating a test certificate for ${domain}..."
    
    if certbot certonly --test-cert --webroot -w /var/www/html \
        -d "${domain}" --email "$(get_config "admin_email" "admin@${domain}")" \
        --agree-tos --no-eff-email --keep-until-expiring; then
        log_success "Test certificate created successfully"
        return 0
    else
        log_warning "Failed to create test certificate"
        return 1
    fi
}

# Function to set up automatic renewal
setup_automatic_renewal() {
    log_info "Setting up automatic certificate renewal..."
    
    # Create a systemd timer for certbot renewal
    cat > /etc/systemd/system/certbot-renew.timer <<- 'EOF'
[Unit]
Description=Certbot renewal timer

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Create a systemd service for certbot renewal
    cat > /etc/systemd/system/certbot-renew.service <<- 'EOF'
[Unit]
Description=Certbot renewal service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --deploy-hook "systemctl reload apache2"
EOF

    # Enable and start the timer
    systemctl daemon-reload
    systemctl enable certbot-renew.timer
    systemctl start certbot-renew.timer
    
    # Test the renewal process (dry run)
    if certbot renew --dry-run; then
        log_success "Automatic renewal set up successfully"
        return 0
    else
        log_warning "Automatic renewal dry run failed"
        return 1
    fi
}

# Main function
main() {
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        return 1
    fi
    
    # Install required packages
    if ! install_system_packages; then
        log_error "Failed to install required packages"
        return 1
    fi
    
    # Verify installation
    if ! verify_certbot_installation; then
        log_error "Certbot installation verification failed"
        return 1
    fi
    
    # Set up directories and permissions
    if ! setup_certbot_directories; then
        log_error "Failed to set up Certbot directories"
        return 1
    fi
    
    # Set up automatic renewal
    if ! setup_automatic_renewal; then
        log_warning "Failed to set up automatic renewal"
    fi
    
    # Optionally create a test certificate
    if ! create_test_certificate; then
        log_warning "Failed to create test certificate"
    fi
    
    log_success "Certbot installation and setup completed successfully"
    log_info ""
    log_info "Next steps:"
    log_info "1. Run the configuration script to obtain production certificates:"
    log_info "   ./src/utilities/configure/configure-certbot.sh"
    log_info ""
    log_info "2. For production use, consider:"
    log_info "   - Configuring DNS validation if using a DNS provider"
    log_info "   - Setting up proper web server configuration"
    log_info "   - Monitoring certificate expiration"
    log_info "   - Setting up proper logging and alerting"
    
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi