#!/bin/bash
set -euo pipefail

# Set fixed paths based on the known repository structure
if [ -z "${PROJECT_ROOT:-}" ]; then
    # If not set by parent script, use default
    PROJECT_ROOT="/root/nextcloud-setup"
fi

# Define core directories relative to PROJECT_ROOT
CORE_DIR="${PROJECT_ROOT}/src/core"
SRC_DIR="${PROJECT_ROOT}/src"
UTILS_DIR="${SRC_DIR}/utilities"
LOG_DIR="${PROJECT_ROOT}/logs"
CONFIG_DIR="${PROJECT_ROOT}/config"
DATA_DIR="${PROJECT_ROOT}/data"
ENV_FILE="${PROJECT_ROOT}/.env"

# Export environment variables
export PROJECT_ROOT CORE_DIR SRC_DIR UTILS_DIR LOG_DIR CONFIG_DIR DATA_DIR ENV_FILE

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

# Function to install packages in batches
install_packages() {
    local packages=("$@")
    local batch_size=10
    local i=0
    
    while [ $i -lt ${#packages[@]} ]; do
        local batch=("${packages[@]:$i:$batch_size}")
        log_info "Installing package batch: ${batch[*]}"
        
        if ! DEBIAN_FRONTEND=noninteractive ${PACKAGE_MANAGER} install -y --no-install-recommends "${batch[@]}"; then
            log_warning "Failed to install a batch of packages. Retrying individually..."
            
            # Try installing packages one by one
            for pkg in "${batch[@]}"; do
                log_info "Attempting to install: $pkg"
                if ! DEBIAN_FRONTEND=noninteractive ${PACKAGE_MANAGER} install -y --no-install-recommends "$pkg"; then
                    log_error "Failed to install package: $pkg"
                    return 1
                fi
            done
        fi
        
        i=$((i + batch_size))
    done
    
    return 0
}

# Function to update package lists
{{ ... }}
    rm -rf /var/lib/apt/lists/*
}

# Main installation function
install_system_dependencies() {
    log_section "Installing system dependencies"
    
    # Update package lists
    if ! update_package_lists; then
        log_error "Failed to update package lists"
        return 1
    fi
    # Install packages in logical groups
    log_info "Installing system packages..."
    if ! install_packages "${SYSTEM_PACKAGES[@]}"; then
        log_error "Failed to install system packages"
        return 1
    fi
    
    log_info "Installing monitoring tools..."
    if ! install_packages "${MONITORING_TOOLS[@]}"; then
        log_warning "Some monitoring tools failed to install, but continuing..."
    fi
{{ ... }}
    log_info "Installing database packages..."
    if ! install_packages "${DATABASE_PACKAGES[@]}"; then
        log_error "Failed to install database packages"
        return 1
    fi
    
    log_info "Installing web server packages..."
    if ! install_packages "${WEB_SERVER_PACKAGES[@]}"; then
        log_error "Failed to install web server packages"
        return 1
    fi
    
    log_info "Installing PHP and extensions..."
    if ! install_packages "${PHP_PACKAGES[@]}"; then
        log_error "Failed to install PHP packages"
        return 1
    fi
    
    # Configure firewall
    if ! configure_firewall; then
        log_warning "Failed to configure firewall. Continuing..."
    fi
    
    log_success "System dependencies installed successfully"
    return 0
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
