#!/bin/bash
set -euo pipefail

# Set project root and core directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CORE_DIR="${PROJECT_ROOT}/core"
SRC_DIR="${PROJECT_ROOT}"
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
source "${CORE_DIR}/config-manager.sh" 2>/dev/null || {
    echo "Error: Failed to load ${CORE_DIR}/config-manager.sh" >&2
    exit 1
}
source "${CORE_DIR}/env-loader.sh" 2>/dev/null || {
    echo "Error: Failed to load ${CORE_DIR}/env-loader.sh" >&2
    exit 1
}
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

# Function to setup repositories
setup_repositories() {
    log_info "Setting up required repositories..."
    
    # Add universe repository if not already present
    if ! grep -q "^deb.*universe" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
        log_info "Adding universe repository..."
        add-apt-repository -y universe || {
            log_warning "Failed to add universe repository, trying alternative method..."
            echo "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) universe" | tee -a /etc/apt/sources.list
        }
    fi
    
    # Add multiverse repository if not already present
    if ! grep -q "^deb.*multiverse" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
        log_info "Adding multiverse repository..."
        add-apt-repository -y multiverse || {
            log_warning "Failed to add multiverse repository, trying alternative method..."
            echo "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) multiverse" | tee -a /etc/apt/sources.list
        }
    fi
    
    # Update package lists after adding repositories
    if ! DEBIAN_FRONTEND=noninteractive apt-get update -y; then
        log_error "Failed to update package lists after adding repositories"
        return 1
    fi
    
    return 0
}

# Function to update package lists
update_package_lists() {
    log_info "Updating package lists..."
    
    # First, ensure we have the latest package information
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
    apt-get autoremove -y --purge
    rm -rf /var/lib/apt/lists/*
    
    return 0
}

# Function to install essential packages
install_essential_packages() {
    log_info "Installing essential system packages..."
    
    # First, install the most critical packages that are needed for the rest
    local critical_packages=(
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
    )
    
    # These packages might be in different repositories, we'll handle them separately
    local additional_critical_packages=(
        bzip2
        unzip
        net-tools
        bind9-dnsutils  # Alternative to dnsutils
    )
    
    # Install critical packages
    if ! install_packages "${critical_packages[@]}"; then
        log_error "Failed to install critical packages"
        return 1
    fi
    
    # Add universe and multiverse repositories if not already present
    log_info "Ensuring universe and multiverse repositories are enabled..."
    for repo in universe multiverse; do
        if ! grep -q "^deb.*$repo" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
            log_info "Adding $repo repository..."
            add-apt-repository -y $repo || {
                log_warning "Failed to add $repo repository, trying alternative method..."
                echo "deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) $repo" | tee -a /etc/apt/sources.list
                echo "deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates $repo" | tee -a /etc/apt/sources.list
                echo "deb http://security.ubuntu.com/ubuntu/ $(lsb_release -sc)-security $repo" | tee -a /etc/apt/sources.list
            }
        fi
    done
    
    # Update package lists after adding repositories
    if ! DEBIAN_FRONTEND=noninteractive apt-get update -y; then
        log_warning "Failed to update package lists after adding repositories, continuing anyway..."
    fi
    
    # Now install additional critical packages that might need the repositories we just added
    log_info "Installing additional critical packages..."
    for pkg in "${additional_critical_packages[@]}"; do
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$pkg"; then
            log_warning "Failed to install critical package: $pkg"
        fi
    done
    
    # Now install additional useful packages that might be in universe/multiverse
    local additional_packages=(
        jq
        fail2ban
        lsof
        telnet
        tcpdump
        traceroute
        iotop
        iftop
        ntp
        ntpdate
        bash-completion
        hdparm
        iperf3
        lshw
        lsscsi
        lvm2
        mtr-tiny
        pciutils
        strace
        sysstat
    )
    
    # Try to install additional packages, but don't fail the whole script if they don't install
    for pkg in "${additional_packages[@]}"; do
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$pkg"; then
            log_warning "Failed to install optional package: $pkg"
        fi
    done
    
    return 0
}

# Main installation function
install_system_dependencies() {
    log_info "Starting system dependencies installation..."
    
    # Setup required repositories first
    if ! setup_repositories; then
        log_warning "Failed to setup all repositories, some packages might not be available"
    fi
    
    # Update package lists
    if ! update_package_lists; then
        log_error "Failed to update package lists"
        return 1
    fi
    
    # Install essential packages
    if ! install_essential_packages; then
        log_error "Failed to install essential packages"
        return 1
    fi
    
    # Enable and start important services if they were installed
    if command -v ufw &> /dev/null; then
        systemctl enable --now ufw
    else
        log_warning "ufw not installed, skipping service setup"
    fi
    
    if command -v fail2ban-server &> /dev/null; then
        systemctl enable --now fail2ban
    else
        log_warning "fail2ban not installed, skipping service setup"
    fi
    
    if systemctl list-unit-files | grep -q unattended-upgrades; then
        systemctl enable --now unattended-upgrades
    else
        log_warning "unattended-upgrades not available, skipping"
    fi
    
    log_success "System tools and dependencies installation completed"
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
