#!/bin/bash
set -euo pipefail

# Set project root and core directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
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
    
    # Ensure the timezone is properly set
    if [ "$(cat /etc/timezone)" != "${timezone}" ]; then
        echo "${timezone}" > /etc/timezone
        ln -sf "/usr/share/zoneinfo/${timezone}" /etc/localtime
        dpkg-reconfigure -f noninteractive tzdata
    fi
    
    log_info "Timezone set to ${timezone}"
    return 0
}

# Function to configure system limits
configure_limits() {
    log_info "Configuring system limits..."
    
    # Configure file limits
    cat > /etc/security/limits.d/nextcloud.conf << 'EOL'
*               soft    nofile          65535
*               hard    nofile          65535
www-data        soft    nofile          65535
www-data        hard    nofile          65535
mysql           soft    nofile          65535
mysql           hard    nofile          65535
EOL

    # Configure sysctl settings
    cat > "${SYSCTL_FILE}" << 'EOL'
# Increase system file descriptor limit
fs.file-max = 100000

# Increase the maximum number of open files
fs.nr_open = 100000

# Increase the maximum amount of memory for TCP
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 4096
net.core.netdev_max_backlog = 4096
vm.overcommit_memory = 1
vm.swappiness = 10
EOL

    # Apply sysctl settings
    if ! sysctl -p "${SYSCTL_FILE}" > /dev/null; then
        log_warning "Failed to apply sysctl settings"
        return 1
    fi
    
    log_info "System limits configured"
    return 0
}

# Function to set system hostname
set_hostname() {
    local hostname="${1:-$(hostname -s)}"  # Use current hostname if not provided
    
    # Remove all instances of "nextcloud-" from the beginning of the string
    while [[ "$hostname" =~ ^nextcloud-* ]]; do
        hostname="${hostname#nextcloud-}"
    done
    
    # Add a single "nextcloud-" prefix
    hostname="nextcloud-${hostname}"
    
    # Ensure hostname is not too long (max 63 chars as per RFC 1123)
    if [ ${#hostname} -gt 63 ]; then
        log_warning "Hostname is too long, truncating to 63 characters"
        hostname="${hostname:0:63}"
    fi
    
    log_info "Setting system hostname to ${hostname}..."
    
    # Set hostname using hostnamectl
    if ! hostnamectl set-hostname "${hostname}"; then
        log_warning "Failed to set hostname using hostnamectl, trying alternative method..."
        echo "${hostname}" > /etc/hostname
        hostname "${hostname}"
    fi
    
    # Update /etc/hosts - first remove any existing entries
    sed -i "/${hostname}/d" /etc/hosts 2>/dev/null || true
    
    # Create a clean /etc/hosts file
    cat > /etc/hosts << EOL
127.0.0.1 localhost
127.0.1.1 ${hostname}

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOL
    
    log_info "Hostname set to ${hostname}"
    return 0
}

# Helper function to install and configure NTP
install_ntp() {
    log_info "Installing and configuring NTP..."
    
    # Stop and disable systemd-timesyncd if it's causing issues
    if systemctl is-active systemd-timesyncd &> /dev/null; then
        systemctl stop systemd-timesyncd
        systemctl disable systemd-timesyncd
    fi
    
    # Install NTP if not already installed
    if ! command -v ntpq &> /dev/null; then
        log_info "Installing NTP package..."
        if ! apt-get update || ! apt-get install -y ntp; then
            log_error "Failed to install NTP package"
            return 1
        fi
    fi
    
    # Backup existing config
    if [ -f /etc/ntp.conf ]; then
        cp /etc/ntp.conf /etc/ntp.conf.bak
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
    else
        log_warning "ntpq command not found, NTP installation may have failed"
        return 1
    fi
    
    return 0
}

# Function to configure time synchronization
configure_time_sync() {
    log_info "Configuring time synchronization..."
    
    # Try to use systemd-timesyncd first
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
        if ! install_ntp; then
            log_error "Failed to configure time synchronization"
            return 1
        fi
    fi
    
    # Verify time synchronization status
    if command -v timedatectl &> /dev/null; then
        timedatectl status
    fi
    
    log_info "Time synchronization configured"
    return 0
}

# Function to configure swap
configure_swap() {
    log_info "Configuring swap..."
    
    # Check if swap is already configured
    if [ -n "$(swapon --show)" ]; then
        log_info "Swap is already configured"
        return 0
    fi
    
    local swap_size="2G"
    local swap_file="/swapfile"
    
    # Create swap file
    fallocate -l "${swap_size}" "${swap_file}" || {
        log_warning "fallocate failed, trying dd..."
        dd if=/dev/zero of="${swap_file}" bs=1M count=$((2*1024))
    }
    
    # Set correct permissions
    chmod 600 "${swap_file}"
    
    # Set up swap area
    mkswap "${swap_file}"
    swapon "${swap_file}"
    
    # Make swap permanent
    echo "${swap_file} none swap sw 0 0" >> /etc/fstab
    
    # Configure swappiness
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
    sysctl -p
    
    log_info "Swap configured successfully"
    return 0
}

# Main configuration function
main() {
    log_info "Starting system configuration..."
    
    # Set timezone
    set_timezone "${TIMEZONE:-UTC}" || {
        log_error "Failed to set timezone"
        return 1
    }
    
    # Set hostname
    set_hostname "${HOSTNAME:-}" || {
        log_error "Failed to set hostname"
        return 1
    }
    
    # Configure system limits
    configure_limits || {
        log_warning "Failed to configure system limits, continuing..."
    }
    
    # Configure time synchronization
    configure_time_sync || {
        log_warning "Failed to configure time synchronization, continuing..."
    }
    
    # Configure swap if needed
    configure_swap || {
        log_warning "Failed to configure swap, continuing..."
    }
    
    log_success "✓ System configuration completed successfully"
    return 0
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    main
    exit $?
fi