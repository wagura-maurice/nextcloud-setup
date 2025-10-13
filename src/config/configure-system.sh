#!/bin/bash

# configure-system.sh - System configuration script for Nextcloud
# This script configures system-wide settings for optimal Nextcloud performance

# Source core functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/common-functions.sh"
source "$SCRIPT_DIR/../core/logging.sh"
source "$SCRIPT_DIR/../core/config-manager.sh"

# Component details
COMPONENT="system"

# Default configuration values
declare -A DEFAULTS=(
    [SYSTEM_TIMEZONE]="UTC"
    [SYSTEM_LOCALE]="en_US.UTF-8"
    [SYSTEM_HOSTNAME]="nextcloud"
    [SYSTEM_SWAP_SIZE]="auto"  # auto, none, or size in MB
    [SYSTEM_SWAPPINESS]="10"
    [SYSTEM_VFS_CACHE_PRESSURE]="50"
    [SYSTEM_ULIMIT_NOFILE]="65535"
    [SYSTEM_ULIMIT_NPROC]="65535"
    [SYSTEM_ULIMIT_MEMLOCK]="unlimited"
)

# Main function
main() {
    print_header "Configuring System Settings"
    
    # Load environment
    load_config
    
    # Check root
    require_root
    
    # Configure system basics
    configure_hostname
    configure_locale
    configure_timezone
    
    # Configure system limits
    configure_ulimits
    configure_sysctl
    
    # Configure swap
    configure_swap
    
    # Configure system services
    configure_services
    
    print_success "System configuration completed"
}

# Configure system hostname
configure_hostname() {
    local hostname="${SYSTEM_HOSTNAME:-nextcloud}"
    
    if [ "$(hostname)" != "$hostname" ]; then
        print_status "Setting hostname to $hostname..."
        hostnamectl set-hostname "$hostname"
        
        # Update /etc/hosts if needed
        if ! grep -q "^127.0.1.1\s*$hostname" /etc/hosts; then
            sed -i "/^127.0.1.1/d" /etc/hosts
            echo "127.0.1.1\t$hostname" >> /etc/hosts
        fi
    fi
}

# Configure system locale
configure_locale() {
    local locale="${SYSTEM_LOCALE:-en_US.UTF-8}"
    
    # Generate locale if not present
    if ! locale -a | grep -q "^${locale//.utf8/}\\b"i; then
        print_status "Generating locale $locale..."
        sed -i "s/^#\s*\($locale\)/\1/" /etc/locale.gen
        locale-gen
    fi
    
    # Set system locale
    if [ "$(locale | grep -E '^LANG=' | cut -d= -f2)" != "$locale" ]; then
        print_status "Setting system locale to $locale..."
        update-locale LANG=$locale LC_ALL=$locale LANGUAGE=$locale
        export LANG=$locale
        export LC_ALL=$locale
        export LANGUAGE=$locale
    fi
}

# Configure timezone
configure_timezone() {
    local timezone="${SYSTEM_TIMEZONE:-UTC}"
    local current_tz="$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")"
    
    if [ "$current_tz" != "$timezone" ]; then
        if [ -f "/usr/share/zoneinfo/$timezone" ]; then
            print_status "Setting timezone to $timezone..."
            timedatectl set-timezone "$timezone"
        else
            print_error "Invalid timezone: $timezone"
        fi
    fi
}

# Configure system limits
configure_ulimits() {
    local limits_conf="/etc/security/limits.conf"
    local limits_d_dir="/etc/security/limits.d"
    local nextcloud_limits="$limits_d_dir/nextcloud.conf"
    
    # Create limits.d directory if it doesn't exist
    mkdir -p "$limits_d_dir"
    
    # Configure system-wide limits for web server and PHP
    cat > "$nextcloud_limits" << EOF
# Nextcloud system limits configuration
# Managed by Nextcloud Setup Script

# Web server limits
www-data          soft    nofile          ${SYSTEM_ULIMIT_NOFILE:-65535}
www-data          hard    nofile          ${SYSTEM_ULIMIT_NOFILE:-65535}
www-data          soft    nproc           ${SYSTEM_ULIMIT_NPROC:-65535}
www-data          hard    nproc           ${SYSTEM_ULIMIT_NPROC:-65535}
www-data          soft    memlock         ${SYSTEM_ULIMIT_MEMLOCK:-unlimited}
www-data          hard    memlock         ${SYSTEM_ULIMIT_MEMLOCK:-unlimited}

# PHP-FPM limits
$(ls /etc/php/*/fpm/pool.d/www.conf 2>/dev/null | xargs -I{} basename {} | cut -d. -f1 | xargs -I{} echo "{}" | while read -r user; do
    echo "$user          soft    nofile          ${SYSTEM_ULIMIT_NOFILE:-65535}"
    echo "$user          hard    nofile          ${SYSTEM_ULIMIT_NOFILE:-65535}"
    echo "$user          soft    nproc           ${SYSTEM_ULIMIT_NPROC:-65535}"
    echo "$user          hard    nproc           ${SYSTEM_ULIMIT_NPROC:-65535}"
    echo "$user          soft    memlock         ${SYSTEM_ULIMIT_MEMLOCK:-unlimited}"
    echo "$user          hard    memlock         ${SYSTEM_ULIMIT_MEMLOCK:-unlimited}"
done)
EOF
    
    # Set proper permissions
    chmod 644 "$nextcloud_limits"
    
    # Configure session limits
    if [ -d "/etc/systemd/system" ]; then
        mkdir -p /etc/systemd/system/php*-fpm.service.d
        for fpm_service in $(ls /lib/systemd/system/php*-fpm.service 2>/dev/null); do
            local service_name=$(basename "$fpm_service")
            local override_dir="/etc/systemd/system/${service_name}.d"
            
            mkdir -p "$override_dir"
            cat > "${override_dir}/limits.conf" << EOF
[Service]
LimitNOFILE=${SYSTEM_ULIMIT_NOFILE:-65535}
LimitNPROC=${SYSTEM_ULIMIT_NPROC:-65535}
LimitMEMLOCK=${SYSTEM_ULIMIT_MEMLOCK:-infinity}
EOF
        done
        
        # Reload systemd
        systemctl daemon-reload
    fi
    
    # Configure PAM limits
    if [ -f "/etc/pam.d/common-session" ] && ! grep -q "pam_limits.so" /etc/pam.d/common-session; then
        echo "session required pam_limits.so" >> /etc/pam.d/common-session
    fi
}

# Configure sysctl settings
configure_sysctl() {
    local sysctl_conf="/etc/sysctl.d/99-nextcloud.conf"
    
    # Configure system-wide kernel parameters
    cat > "$sysctl_conf" << EOF
# Nextcloud system tuning
# Managed by Nextcloud Setup Script

# Increase system file descriptor limits
fs.file-max = 2097152
fs.nr_open = 2097152

# Network tuning
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# Memory management
vm.swappiness = ${SYSTEM_SWAPPINESS:-10}
vm.vfs_cache_pressure = ${SYSTEM_VFS_CACHE_PRESSURE:-50}
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1
vm.overcommit_ratio = 50

# Increase system limits
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1024
fs.inotify.max_queued_events = 32768

# Increase TCP buffer sizes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_mem = 65536 131072 262144

# Security settings
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.default.log_martians = 1
EOF
    
    # Apply sysctl settings
    sysctl -p "$sysctl_conf"
}

# Configure swap
configure_swap() {
    local swap_size="${SYSTEM_SWAP_SIZE:-auto}"
    
    # Skip if swap is already configured
    if swapon --show | grep -q "/"; then
        print_status "Swap is already configured"
        return
    fi
    
    # Calculate swap size if set to auto
    if [ "$swap_size" = "auto" ] || [ -z "$swap_size" ]; then
        local total_ram=$(free -m | awk '/^Mem:/{print $2}')
        swap_size=$(($total_ram * 2))  # 2x RAM size
    elif [ "$swap_size" = "none" ]; then
        print_status "Swap configuration is set to 'none', skipping..."
        return
    fi
    
    # Create swap file
    print_status "Configuring swap space (${swap_size}MB)..."
    fallocate -l ${swap_size}M /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    # Make swap permanent
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    
    # Configure swappiness
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness=${SYSTEM_SWAPPINESS:-10}" >> /etc/sysctl.conf
        sysctl -p
    fi
}

# Configure system services
configure_services() {
    print_status "Configuring system services..."
    
    # Enable and start essential services
    local services=(
        "cron"
        "rsyslog"
        "apparmor"
        "ufw"
        "fail2ban"
    )
    
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "$service\.service"; then
            systemctl enable --now "$service" 2>/dev/null || true
        fi
    done
    
    # Enable and restart PHP-FPM if installed
    if command -v php-fpm &>/dev/null; then
        local php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || echo "")
        if [ -n "$php_version" ] && systemctl list-unit-files | grep -q "php$php_version-fpm\.service"; then
            systemctl enable "php$php_version-fpm"
            systemctl restart "php$php_version-fpm"
        fi
    fi
}

# Run main function
main "@"

# things like configures the limits, swap, timezone etc
