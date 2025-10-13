#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Installing Redis Server"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Install Redis server and tools
if ! command -v redis-server >/dev/null 2>&1; then
    log_info "Adding Redis repository..."
    
    # Add Redis repository for the latest stable version
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    
    log_info "Updating package lists and installing Redis..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        redis-server \
        redis-tools \
        redis-sentinel \
        redis-benchmark
    
    # Verify installation
    if ! command -v redis-server >/dev/null 2>&1; then
        log_error "Redis installation failed"
        exit 1
    fi
    
    log_success "Redis installed successfully"
else
    log_info "Redis is already installed"
fi

# Create backup of current configuration
BACKUP_DIR="/etc/redis/backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -a /etc/redis/redis.conf "$BACKUP_DIR/" 2>/dev/null || true
cp -a /etc/redis/sentinel.conf "$BACKUP_DIR/" 2>/dev/null || true
log_info "Current configuration backed up to $BACKUP_DIR"

# Create Redis system user and group if they don't exist
if ! id -u redis >/dev/null 2>&1; then
    useradd -r -s /bin/false -d /var/lib/redis redis
fi

# Create necessary directories with correct permissions
for dir in /var/lib/redis /var/log/redis /run/redis; do
    mkdir -p "$dir"
    chown -R redis:redis "$dir"
    chmod 750 "$dir"
done

# Install PHP Redis extension if PHP is installed
for php_version in 8.4 8.3 8.2 8.1 8.0 7.4; do
    if command -v "php${php_version}" >/dev/null 2>&1; then
        log_info "Installing PHP ${php_version} Redis extension..."
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "php${php_version}-redis"; then
            log_warning "Failed to install PHP ${php_version} Redis extension"
        else
            # Enable the extension
            if [ -f "/etc/php/${php_version}/mods-available/redis.ini" ]; then
                phpenmod -v "${php_version}" redis
            fi
            
            # Restart PHP-FPM if it's installed
            if systemctl is-active --quiet "php${php_version}-fpm"; then
                systemctl restart "php${php_version}-fpm"
            fi
        fi
    fi
done

# Enable and start Redis service
log_info "Starting Redis service..."
systemctl enable redis-server
if ! systemctl restart redis-server; then
    log_error "Failed to start Redis server"
    journalctl -u redis-server --no-pager -n 50
    exit 1
fi

# Verify Redis is running
if ! systemctl is-active --quiet redis-server; then
    log_error "Redis server failed to start"
    journalctl -u redis-server --no-pager -n 50
    exit 1
fi

# Basic connectivity test
if ! redis-cli ping >/dev/null 2>&1; then
    log_error "Redis server is not responding to connections"
    exit 1
fi

# Save Redis info to a file for the configuration script
REDIS_INFO_FILE="$SCRIPT_DIR/.redis_info"
cat > "$REDIS_INFO_FILE" <<EOF
# Redis Server Information
REDIS_VERSION=$(redis-server --version | awk '{print $3}' | cut -d= -f2)
REDIS_CONFIG="/etc/redis/redis.conf"
REDIS_DATA_DIR="/var/lib/redis"
REDIS_LOG_DIR="/var/log/redis"
REDIS_RUN_DIR="/run/redis"
REDIS_USER="redis"
REDIS_GROUP="redis"

# Connection Details
REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
# Password will be set by configure-redis.sh

# Performance Metrics
REDIS_MAXMEMORY="256mb"
REDIS_MAXMEMORY_POLICY="allkeys-lru"

# Persistence Settings
REDIS_APPENDONLY="yes"
REDIS_APPENDFSYNC="everysec"

# Security Settings
REDIS_PROTECTED_MODE="yes"
REDIS_REQUIREPASS=""  # Will be set by configure-redis.sh

# How to connect to Redis:
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_PASSWORD

# How to monitor Redis:
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_PASSWORD monitor

# How to get Redis info:
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_PASSWORD info

# How to flush all data (use with caution):
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_PASSWORD flushall
EOF

chmod 600 "$REDIS_INFO_FILE"

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
log_info "   - Setting up Redis authentication"
log_info "   - Configuring Redis persistence"
log_info "   - Setting up Redis Sentinel for high availability"
log_info "   - Configuring proper firewall rules"
log_info "   - Setting up monitoring and alerting"
