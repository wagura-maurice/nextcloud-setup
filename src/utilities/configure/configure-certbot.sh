#!/bin/bash

# Source the configuration and logging utilities
source "${BASH_SOURCE%/*}/../../core/config-manager.sh"
source "${BASH_SOURCE%/*}/../../core/logging.sh"

# Set up logging
LOG_FILE="${LOG_DIR}/configure-certbot-$(date +%Y%m%d%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

log_message "INFO" "Starting Certbot configuration..."

# Function to configure certbot and obtain SSL certificate
configure_certbot() {
    local domain=$(get_config "domain" "cloud.e-granary.com")
    local email=$(get_config "email" "support@e-granary.com")
    
    # Ensure certbot is installed
    if ! command -v certbot &> /dev/null; then
        log_message "ERROR" "Certbot is not installed. Please run install-certbot.sh first."
        return 1
    fi
    
    # Stop Apache to free port 80 if it's running
    if systemctl is-active --quiet apache2; then
        log_message "INFO" "Stopping Apache to free port 80..."
        systemctl stop apache2 || {
            log_message "WARNING" "Failed to stop Apache. Continuing anyway..."
        }
    fi
    
    # Obtain SSL certificate
    log_message "INFO" "Obtaining SSL certificate for ${domain}..."
    certbot certonly --standalone --non-interactive --agree-tos \
        --email "${email}" \
        -d "${domain}" \
        --preferred-challenges http-01 || {
        log_message "ERROR" "Failed to obtain SSL certificate"
        return 1
    }
    
    # Set up automatic renewal
    log_message "INFO" "Setting up automatic certificate renewal..."
    
    # Create renewal hooks directory if it doesn't exist
    local hooks_dir="/etc/letsencrypt/renewal-hooks"
    mkdir -p "${hooks_dir}/pre"
    mkdir -p "${hooks_dir}/post"
    
    # Create pre-renewal hook to stop Apache
    cat > "${hooks_dir}/pre/stop-apache" << 'EOL'
#!/bin/sh
systemctl stop apache2
EOL
    
    # Create post-renewal hook to start Apache
    cat > "${hooks_dir}/post/start-apache" << 'EOL'
#!/bin/sh
systemctl start apache2
EOL
    
    # Make hooks executable
    chmod +x "${hooks_dir}/pre/stop-apache"
    chmod +x "${hooks_dir}/post/start-apache"
    
    # Test renewal (dry run)
    log_message "INFO" "Testing certificate renewal..."
    certbot renew --dry-run || {
        log_message "WARNING" "Certificate renewal dry run failed. Please check your configuration."
    }
    
    log_message "SUCCESS" "Certbot configuration completed successfully"
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root"
        exit 1
    fi
    
    configure_certbot
    exit $?
fi