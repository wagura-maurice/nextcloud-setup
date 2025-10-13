#!/bin/bash
set -euo pipefail

# Load core configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/core/config-manager.sh"
source "${SCRIPT_DIR}/core/env-loader.sh"
source "${SCRIPT_DIR}/core/logging.sh"

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
    if ! grep -q "^127.0.1.1\s*${hostname}" /etc/hosts; then
        sed -i "/^127.0.1.1/c\127.0.1.1\t${hostname}" /etc/hosts || {
            log_warning "Failed to update /etc/hosts with new hostname"
        }
    fi
    
    log_info "Hostname set to ${hostname}"
    return 0
}

# Function to configure system limits
configure_limits() {
    log_info "Configuring system limits..."
    
    # Create backup of limits file
    cp -f "${LIMITS_FILE}" "${LIMITS_FILE}.bak" 2>/dev/null || true
    
    # Configure limits for www-data user
    if ! grep -q "^# Nextcloud" "${LIMITS_FILE}"; then
        cat >> "${LIMITS_FILE}" << EOL

# Nextcloud optimizations
www-data  soft  nofile   8192
www-data  hard  nofile   16384
www-data  soft  nproc    4096
www-data  hard  nproc    8192
EOL
    fi
    
    log_info "System limits configured"
    return 0
}

# Function to configure kernel parameters
configure_kernel() {
    log_info "Configuring kernel parameters..."
    
    # Create sysctl configuration
    cat > "${SYSCTL_FILE}" << 'EOL'
# System limits
fs.file-max = 1000000
fs.nr_open = 1000000

# Network stack optimization
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_window_scaling = 1
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_tw_reuse = 1

# Swap and memory management
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.overcommit_memory = 1
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5

# File system optimization
fs.inotify.max_user_watches = 1048576
EOL
    
    # Apply settings
    if ! sysctl -p "${SYSCTL_FILE}" >/dev/null 2>&1; then
        log_error "Failed to apply sysctl settings"
        return 1
    fi
    
    log_info "Kernel parameters configured"
    return 0
}

# Function to configure time synchronization
configure_time_sync() {
    log_info "Configuring time synchronization..."
    
    if ! systemctl is-enabled --quiet systemd-timesyncd 2>/dev/null; then
        if ! systemctl enable --now systemd-timesyncd; then
            log_warning "Failed to enable systemd-timesyncd"
            return 1
        fi
    fi
    
    # Ensure NTP is synchronized
    if ! timedatectl show | grep -q '^NTPSynchronized=yes'; then
        if ! timedatectl set-ntp true; then
            log_warning "Failed to enable NTP synchronization"
            return 1
        fi
    fi
    
    log_info "Time synchronization configured"
    return 0
}

# Main configuration function
configure_system() {
    local success=true
    local timezone=$(get_config "timezone" "${DEFAULT_TIMEZONE}")
    local hostname=$(get_config "hostname" "${DEFAULT_HOSTNAME}")
    
    log_info "Starting system configuration..."
    
    # Apply system configurations
    set_timezone "${timezone}" || success=false
    set_hostname "${hostname}" || success=false
    configure_limits || success=false
    configure_kernel || success=false
    configure_time_sync || success=false
    
    # Final status
    if [ "${success}" = true ]; then
        log_success "System configuration completed successfully"
        return 0
    else
        log_error "System configuration completed with errors"
        return 1
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    configure_system
    exit $?
fi