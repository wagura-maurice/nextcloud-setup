#!/bin/bash

# install-webserver.sh - Installation script for webserver
# This script handles ONLY the installation of Apache web server
# Configuration is handled by the configure-webserver.sh script

set -e

# Source core functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/common-functions.sh"
source "$SCRIPT_DIR/../core/logging.sh"
source "$SCRIPT_DIR/../core/config-manager.sh"

# Component details
COMPONENT="webserver"
DEPENDENCIES=(
    "apache2"
    "apache2-utils"
    "libapache2-mod-fcgid"
    "ssl-cert"
    "apache2-suexec-pristine"
    "libapache2-mod-http2"
    "libapache2-mod-security2"
)

# Main function
main() {
    print_header "Installing Apache Web Server"
    
    # Load environment
    load_config
    
    # Check root
    require_root
    
    # Install dependencies
    install_dependencies
    
    # Install Apache
    install_apache
    
    # Enable required modules
    a2enmod rewrite headers env dir mime ssl proxy_fcgi setenvif alias deflate filter expires
    
    # Enable HTTP/2
    a2enmod http2
    
    # Enable mpm_event
    a2enmod mpm_event
    
    # Enable proxy modules
    a2enmod proxy proxy_http proxy_fcgi setenvif
    
    # Enable security module (will be configured later)
    a2enmod security2
    
    print_status "Apache installation completed"
}

# Save installed version to .env
save_version() {
    local version
    version=$(apache2 -v | grep 'Server version' | awk '{print $3}' | cut -d'/' -f2)
    set_env "APACHE_VERSION" "$version"
}

# Helper function to check if running as root
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Run main function
main "@"