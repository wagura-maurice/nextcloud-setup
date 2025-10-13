#!/bin/bash

# install-system.sh - Installation script for system packages
# This script handles ONLY the installation of system packages
# Configuration is handled by configure-system.sh

# Source core functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/common-functions.sh"
source "$SCRIPT_DIR/../core/logging.sh"
source "$SCRIPT_DIR/../core/config-manager.sh"

# Component details
COMPONENT="system"
DEPENDENCIES=(
    "apt-transport-https"
    "ca-certificates"
    "curl"
    "gnupg"
    "lsb-release"
    "software-properties-common"
    "wget"
    "htop"
    "iftop"
    "iotop"
    "net-tools"
    "dnsutils"
    "ufw"
    "fail2ban"
    "unattended-upgrades"
    "apt-listchanges"
)

# Main function
main() {
    print_header "Installing System Packages"
    
    # Load environment
    load_config
    
    # Check root
    require_root
    
    # Install dependencies
    install_dependencies
    
    # Install system packages
    install_system_packages
    
    # Save version to .env
    save_version
    
    print_success "System packages installation completed"
    echo -e "\nRun '${YELLOW}./nextcloud-setup configure system${NC}' to configure system settings\n"
}

# Install system packages
install_system_packages() {
    print_status "Installing system packages..."
    
    # Update package lists
    apt-get update
    
    # Install all dependencies
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${DEPENDENCIES[@]}"
    
    # Create required directories
    mkdir -p "/etc/nextcloud"
    chmod 750 "/etc/nextcloud"
    
    print_status "System packages installed successfully"
}

# Save installed version to .env
save_version() {
    local os_info
    os_info=$(lsb_release -ds 2>/dev/null || echo "Unknown")
    set_env "SYSTEM_OS" "$os_info"
    
    # Mark as installed
    touch "/etc/nextcloud/.system_installed"
    chmod 600 "/etc/nextcloud/.system_installed"
}

# Run main function
main "$@"