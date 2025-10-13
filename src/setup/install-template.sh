#!/bin/bash
# Template for installation scripts
# Usage: Copy and rename this file, then implement the required functions

# Source core functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/common-functions.sh"
source "$SCRIPT_DIR/../core/logging.sh"
source "$SCRIPT_DIR/../core/config-manager.sh"

# Component details (override these in your script)
COMPONENT="template"
DEPENDENCIES=()

# Main function
main() {
    print_header "Installing $COMPONENT"
    
    # Load environment
    load_config
    
    # Check root
    require_root
    
    # Install dependencies
    install_dependencies
    
    # Install component
    install_component
    
    # Save version to .env
    save_version
    
    print_success "$COMPONENT installation completed"
    echo -e "\nRun '${YELLOW}./nextcloud-setup configure $COMPONENT${NC}' to configure $COMPONENT\n"
}

# Install system dependencies
install_dependencies() {
    if [ ${#DEPENDENCIES[@]} -gt 0 ]; then
        print_status "Installing dependencies..."
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${DEPENDENCIES[@]}"
    fi
}

# Install the component (override this in your script)
install_component() {
    print_status "Installing $COMPONENT..."
    # Implementation goes here
}

# Save installed version to .env (override if needed)
save_version() {
    # Example: set_env "${COMPONENT^^}_VERSION" "1.0.0"
    return 0
}

# Helper function to check if running as root
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Run main function
main "$@"
