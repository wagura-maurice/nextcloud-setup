#!/bin/bash
set -euo pipefail

# Hardcode the project root and core directories
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

log_section "System Configuration"

# Default configuration values
readonly DEFAULT_TIMEZONE="UTC"
readonly DEFAULT_HOSTNAME="nextcloud-$(hostname -s)"
readonly SYSCTL_FILE="/etc/sysctl.d/99-nextcloud.conf"
readonly LIMITS_FILE="/etc/security/limits.conf"

# Function to set system timezone
set_timezone() {
    local timezone="${1:-${DEFAULT_TIMEZONE}}"
    log_info "Setting system timezone to ${timezone}..."
    
    if ! timedatectl set-timezone "${timezone}"; then
        log_error "Failed to set timezone to ${timezone}"
        return 1
    fi
    
    log_info "Timezone set to ${timezone}"
    return 0
}

# Function to set system hostname
set_hostname() {
    local hostname="${1:-${DEFAULT_HOSTNAME}}"
    log_info "Setting system hostname to ${hostname}..."
    
    if ! hostnamectl set-hostname "${hostname}"; then
        log_error "Failed to set hostname to ${hostname}"
        return 1
    fi
    
    # Update /etc/hosts if needed
    if ! grep -q "${hostname}" /etc/hosts; then
        echo "127.0.1.1 ${hostname}" >> /etc/hosts
    fi
    
    log_info "Hostname set to ${hostname}"
    return 0
}

# Function to configure system limits
configure_limits() {
    log_info "Configuring system limits..."
    
    # Add or update limits in limits.conf
    if ! grep -q "nextcloud" "${LIMITS_FILE}"; then
        cat << EOF | tee -a "${LIMITS_FILE}" > /dev/null
# Nextcloud optimizations
*               soft    nofile          65536
*               hard    nofile          65536
www-data        soft    nofile          131072
www-data        hard    nofile          262144
www-data        soft    nproc           4096
www-data        hard    nproc           8192
EOF
    fi
    
    # Create sysctl.d file if it doesn't exist
    if [ ! -f "${SYSCTL_FILE}" ]; then
        cat << EOF | tee "${SYSCTL_FILE}" > /dev/null
# Nextcloud system optimizations
fs.file-max = 100000
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 4096
net.core.netdev_max_backlog = 4096
vm.overcommit_memory = 1
vm.swappiness = 10
EOF
        sysctl -p "${SYSCTL_FILE}" > /dev/null
    fi
    
    log_info "System limits configured"
    return 0
}

# Function to configure time synchronization
configure_time_sync() {
    log_info "Configuring time synchronization..."
    
    # Check if systemd-timesyncd is masked and unmask it
    if systemctl is-enabled systemd-timesyncd 2>&1 | grep -q "masked"; then
        log_info "Unmasking systemd-timesyncd service..."
        systemctl unmask systemd-timesyncd || {
            log_warning "Failed to unmask systemd-timesyncd, will try alternative approach"
        }
    fi

    # Check if we should use systemd-timesyncd or install NTP
    if systemctl is-enabled systemd-timesyncd &> /dev/null; then
        log_info "Using systemd-timesyncd for time synchronization"
        if ! timedatectl set-ntp true; then
            log_warning "Failed to enable NTP via timedatectl"
        fi
        if ! systemctl enable --now systemd-timesyncd 2>/dev/null; then
            log_warning "Failed to start systemd-timesyncd, will try installing NTP instead"
            install_ntp
        fi
    else
        log_info "systemd-timesyncd not available, installing NTP..."
        install_ntp
    fi
    
    # Verify time synchronization status
    if command -v timedatectl &> /dev/null; then
        timedatectl status
    fi
    
    log_info "Time synchronization configured"
    return 0
}

# Helper function to install and configure NTP
install_ntp() {
    log_info "Installing and configuring NTP..."
    
    if ! command -v ntpq &> /dev/null; then
        log_info "Installing NTP package..."
        apt-get update && apt-get install -y ntp
    fi
    
    # Configure NTP servers
    cat > /etc/ntp.conf << 'EOL'
# NTP Configuration for Nextcloud
driftfile /var/lib/ntp/ntp.drift
leapfile /usr/share/zoneinfo/leap-seconds.list

# Pool of NTP servers
pool 0.ubuntu.pool.ntp.org iburst
pool 1.ubuntu.pool.ntp.org iburst
pool 2.ubuntu.pool.ntp.org iburst
pool 3.ubuntu.pool.ntp.org iburst
pool ntp.ubuntu.com

# Allow local network clients to sync time
restrict -4 default kod notrap nomodify nopeer noquery limited
restrict -6 default kod notrap nomodify nopeer noquery limited

# Allow localhost
restrict 127.0.0.1
restrict ::1
EOL

    # Restart NTP service
    if systemctl is-active ntp &> /dev/null; then
        systemctl restart ntp
    else
        systemctl enable --now ntp
    fi
    
    # Verify NTP sync
    if command -v ntpq &> /dev/null; then
        log_info "NTP peers:"
        ntpq -p
    fi
}

# Main configuration function
main() {
    log_info "Starting system configuration..."
    
    # Set timezone
    if ! set_timezone; then
        log_warning "Failed to set timezone, using default"
    fi
    
    # Set hostname
    if ! set_hostname; then
        log_warning "Failed to set hostname, using default"
    fi
    
    # Configure system limits
    if ! configure_limits; then
        log_error "Failed to configure system limits"
        return 1
    fi
    
    # Configure time synchronization
    if ! configure_time_sync; then
        log_warning "Failed to configure time synchronization"
    fi
    
    log_success "System configuration completed successfully"
    return 0
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    main "$@"
    exit $?
fi