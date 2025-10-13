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

# Create required directories
mkdir -p "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/tmp"
chmod 750 "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/tmp"

# Load core utilities
source "${CORE_DIR}/env-loader.sh" 2>/dev/null || true
source "${CORE_DIR}/config-manager.sh" 2>/dev/null || true
source "${CORE_DIR}/logging.sh" 2>/dev/null || {
    # Basic logging function if logging.sh is not available
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warning() { echo "[WARN] $*" >&2; }
    log_success() { echo "[SUCCESS] $*"; }
}

# Initialize logging if available
command -v init_logging >/dev/null 2>&1 && init_logging || true

log_section "System Dependencies Installation"

# Function to install packages in batches
install_packages() {
    local packages=("$@")
    local batch_size=10
    local i=0
    
    while [ $i -lt ${#packages[@]} ]; do
        local batch=("${packages[@]:$i:$batch_size}")
        log_info "Installing package batch: ${batch[*]}"
        
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${batch[@]}"; then
            log_warning "Failed to install a batch of packages. Retrying individually..."
            
            # Try installing packages one by one
            for pkg in "${batch[@]}"; do
                log_info "Attempting to install: $pkg"
                if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$pkg"; then
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
update_package_lists() {
    log_info "Updating package lists..."
    
    # Update package lists
    if ! DEBIAN_FRONTEND=noninteractive apt-get update -y; then
        log_error "Failed to update package lists"
        return 1
    fi
    
    # Upgrade existing packages
    if ! DEBIAN_FRONTEND=noninteractive apt-get upgrade -y; then
        log_warning "Failed to upgrade all packages, but continuing..."
    fi
    
    # Clean up
    apt-get clean -y
    apt-get autoremove -y
    rm -rf /var/lib/apt/lists/*
    
    return 0
}

# Main installation function
install_system_dependencies() {
    log_info "Updating package lists and installing essential tools..."
    
    # Update package lists
    if ! update_package_lists; then
        log_error "Failed to update package lists"
        return 1
    fi
    
    # Install essential tools
    local essential_tools=(
        software-properties-common
        apt-transport-https
        ca-certificates
        gnupg
        curl
        wget
        git
        nano
        htop
        ufw
        unattended-upgrades
        fail2ban
        jq
        unzip
        bzip2
        lsof
        net-tools
        dnsutils
        telnet
        tcpdump
        traceroute
        iotop
        iftop
        ntp
        ntpdate
        ntpstat
        bash-completion
        hdparm
        iotop
        iperf
        iperf3
        lshw
        lsof
        lsscsi
        lvm2
        mtr-tiny
        pciutils
        strace
        sysstat
    )
    
    if ! install_packages "${essential_tools[@]}"; then
        log_error "Failed to install essential tools"
        return 1
    fi
    
    # Add universe repository
    if ! add-apt-repository universe; then
        log_warning "Failed to add universe repository"
    fi
    
    # Update package lists again after adding repositories
    if ! update_package_lists; then
        log_warning "Failed to update package lists after adding repositories"
    fi
    
    # Enable and start important services
    systemctl enable --now ufw
    systemctl enable --now fail2ban
    systemctl enable --now unattended-upgrades
    
    log_success "System tools and dependencies installed successfully"
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
