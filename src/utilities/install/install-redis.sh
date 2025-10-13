#!/bin/bash
set -euo pipefail

# Load core configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORE_DIR="${SCRIPT_DIR}/core"
source "${CORE_DIR}/env-loader.sh" 2>/dev/null || {
    echo "Error: Failed to load ${CORE_DIR}/env-loader.sh" >&2
    exit 1
}

# Initialize environment and logging
load_environment
init_logging

log_section "Redis Installation"

# Default configuration values
readonly REDIS_VERSION="7.0"
readonly PACKAGE_MANAGER="apt-get"
readonly INSTALL_OPTS="-y --no-install-recommends"

# Required packages
readonly REDIS_PACKAGES=(
    "redis-server"
    "redis-tools"
    "redis-sentinel"
)

# Function to add Redis repository
add_redis_repository() {
    log_info "Adding Redis repository..."
    
    # Check if already added
    if [ -f "/etc/apt/sources.list.d/redis.list" ]; then
        log_info "Redis repository already added"
        return 0
    fi
    
    # Install required packages
    if ! ${PACKAGE_MANAGER} install ${INSTALL_OPTS} \
        software-properties-common \
        curl \
        gnupg; then
        log_error "Failed to install required packages"
        return 1
    fi
    
    # Add Redis repository
    if ! curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg; then
        log_error "Failed to add Redis GPG key"
        return 1
    fi
    
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | \
        tee /etc/apt/sources.list.d/redis.list
    
    # Update package lists
    if ! ${PACKAGE_MANAGER} update; then
        log_error "Failed to update package lists"
        return 1
    fi
    
    log_success "Redis repository added successfully"
    return 0
}

# Function to install Redis packages
install_redis_packages() {
    log_info "Installing Redis packages..."
    
    if ! DEBIAN_FRONTEND=noninteractive ${PACKAGE_MANAGER} install ${INSTALL_OPTS} "${REDIS_PACKAGES[@]}"; then
        log_error "Failed to install Redis packages"
        return 1
    fi
    
    log_success "Redis packages installed successfully"
    return 0
}

# Function to create Redis directories and set permissions
setup_redis_directories() {
    log_info "Setting up Redis directories and permissions..."
    
    # Create Redis user if it doesn't exist
    if ! id -u redis >/dev/null 2>&1; then
        useradd -r -s /bin/false -d /var/lib/redis redis
    fi
    
    # Create necessary directories
    local dirs=(
        "/var/lib/redis"
        "/var/log/redis"
        "/run/redis"
        "/etc/redis/conf.d"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "${dir}"
        chown -R redis:redis "${dir}"
        chmod 750 "${dir}"
    done
    
    log_success "Redis directories and permissions set up successfully"
    return 0
}

# Function to install PHP Redis extension
install_php_redis_extension() {
    log_info "Checking for PHP installations to add Redis extension..."
    
    for php_version in 8.4 8.3 8.2 8.1 8.0 7.4; do
        if command -v "php${php_version}" >/dev/null 2>&1; then
            log_info "Installing PHP ${php_version} Redis extension..."
            if ! DEBIAN_FRONTEND=noninteractive ${PACKAGE_MANAGER} install ${INSTALL_OPTS} "php${php_version}-redis"; then
                log_warning "Failed to install PHP ${php_version} Redis extension"
                continue
            fi
            
            # Enable the extension
            if [ -f "/etc/php/${php_version}/mods-available/redis.ini" ]; then
                phpenmod -v "${php_version}" redis
            fi
            
            # Restart PHP-FPM if it's installed
            if systemctl is-active --quiet "php${php_version}-fpm"; then
                systemctl restart "php${php_version}-fpm"
            fi
            
            log_success "PHP ${php_version} Redis extension installed and enabled"
        fi
    done
    
    return 0
}

# Function to start and enable Redis service
start_redis_service() {
    log_info "Starting Redis service..."
    
    # Reload systemd to ensure new unit files are loaded
    systemctl daemon-reload
    
    # Enable and start Redis
    if ! systemctl enable --now redis-server; then
        log_error "Failed to enable Redis service"
        return 1
    fi
    
    # Verify Redis is running
    if ! systemctl is-active --quiet redis-server; then
        log_error "Redis server failed to start"
        journalctl -u redis-server --no-pager -n 50
        return 1
    fi
    
    # Basic connectivity test
    if ! redis-cli ping >/dev/null 2>&1; then
        log_error "Redis server is not responding to connections"
        return 1
    fi
    
    log_success "Redis service is running"
    return 0
}

# Function to save Redis information
save_redis_info() {
    local redis_info_file="${SCRIPT_DIR}/.redis_info"
    
    # Get Redis version
    local redis_version="$(redis-server --version | awk '{print $3}' | cut -d= -f2)"
    
    # Generate a secure password for Redis
    local redis_password=$(openssl rand -base64 32 | tr -d '\n' | tr -d '\' | tr -d '=' | tr -d '+' | cut -c1-32)
    
    # Save Redis info to file
    cat > "${redis_info_file}" <<-EOF
# Redis Server Information
REDIS_VERSION="${redis_version}"
REDIS_CONFIG="/etc/redis/redis.conf"
REDIS_DATA_DIR="/var/lib/redis"
REDIS_LOG_DIR="/var/log/redis"
REDIS_RUN_DIR="/run/redis"
REDIS_USER="redis"
REDIS_GROUP="redis"

# Connection Details
REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
REDIS_PASSWORD="${redis_password}"
REDIS_SOCKET="/run/redis/redis.sock"

# Performance Settings
REDIS_MAXMEMORY="1gb"
REDIS_MAXMEMORY_POLICY="allkeys-lru"
REDIS_MAXMEMORY_SAMPLES="5"
REDIS_MAXCLIENTS="10000"

# Persistence Settings
REDIS_APPENDONLY="yes"
REDIS_APPENDFSYNC="everysec"
REDIS_AOF_REWRITE_PERCENTAGE="100"
REDIS_AOF_REWRITE_MIN_SIZE="64mb"

# Security Settings
REDIS_PROTECTED_MODE="yes"
REDIS_REQUIREPASS="${redis_password}"
REDIS_ADMIN_USER="admin"
REDIS_ADMIN_PASS="$(openssl rand -base64 32 | tr -d '\n' | tr -d '\' | tr -d '=' | tr -d '+' | cut -c1-32)"
REDIS_READONLY_USER="readonly"
REDIS_READONLY_PASS="$(openssl rand -base64 32 | tr -d '\n' | tr -d '\' | tr -d '=' | tr -d '+' | cut -c1-32)"

# How to connect to Redis:
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_PASSWORD

# How to connect with admin user:
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_ADMIN_PASS --user \$REDIS_ADMIN_USER

# How to monitor Redis:
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_PASSWORD monitor

# How to get Redis info:
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_PASSWORD info

# How to flush all data (use with caution):
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_PASSWORD flushall
EOF

    # Set secure permissions
    chmod 600 "${redis_info_file}"
    log_success "Redis information saved to ${redis_info_file}"
    return 0
}

# Main function
main() {
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Add Redis repository
    if ! add_redis_repository; then
        log_error "Failed to add Redis repository"
        exit 1
    fi
    
    # Install Redis packages
    if ! install_redis_packages; then
        log_error "Failed to install Redis packages"
        exit 1
    fi
    
    # Set up Redis directories and permissions
    if ! setup_redis_directories; then
        log_error "Failed to set up Redis directories"
        exit 1
    fi
    
    # Install PHP Redis extension if PHP is installed
    install_php_redis_extension
    
    # Start and enable Redis service
    if ! start_redis_service; then
        log_error "Failed to start Redis service"
        exit 1
    fi
    
    # Save Redis information
    if ! save_redis_info; then
        log_warning "Failed to save Redis information"
    fi

    log_success "Redis installation completed successfully"
    log_info "Redis version: $(redis-server --version | awk '{print $3}' | cut -d= -f2)"
    log_info "Redis configuration file: /etc/redis/redis.conf"
    log_info "Redis data directory: /var/lib/redis"
    log_info "Redis log file: /var/log/redis/redis-server.log"
    log_info ""
    log_info "Next steps:"
    log_info "1. Run the configuration script to secure Redis:"
    log_info "   ./src/utilities/configure/configure-redis.sh"
    log_info ""
    log_info "2. For production use, consider:"
    log_info "   - Reviewing the Redis configuration in /etc/redis/redis.conf"
    log_info "   - Setting up Redis Sentinel for high availability"
    log_info "   - Configuring proper firewall rules"
    log_info "   - Setting up monitoring and alerting"
    log_info "   - Configuring proper backup solutions"
    log_info "   - Reviewing security settings in the configuration file"
    
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi
