#!/bin/bash
# Redis Server Configuration
# This script configures Redis server with secure and optimized settings

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Configuring Redis Server"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Default Redis configuration
REDIS_CONF="/etc/redis/redis.conf"
REDIS_SENTINEL_CONF="/etc/redis/sentinel.conf"
REDIS_PASSWORD=$(openssl rand -base64 48 | tr -d '\n' | tr -d '\' | tr -d '=' | tr -d '+' | cut -c1-32)
REDIS_ADMIN_USER="admin"
REDIS_ADMIN_PASS=$(openssl rand -base64 48 | tr -d '\n' | tr -d '\' | tr -d '=' | tr -d '+' | cut -c1-32)
REDIS_READONLY_PASS=$(openssl rand -base64 48 | tr -d '\n' | tr -d '\' | tr -d '=' | tr -d '+' | cut -c1-32)

# Verify Redis is installed
if ! command -v redis-server >/dev/null 2>&1; then
    log_error "Redis is not installed. Please run install-redis.sh first."
    exit 1
fi

# Function to set Redis configuration
set_redis_config() {
    local key="$1"
    local value="$2"
    local conf_file="${3:-$REDIS_CONF}"
    
    # Escape special characters in the value
    value=$(echo "$value" | sed 's/[&/\]/\&/g')
    
    # Check if the key exists in the config
    if grep -q "^$key " "$conf_file" 2>/dev/null; then
        # Key exists, replace the line
        sed -i "s|^$key .*|$key $value|" "$conf_file"
    elif grep -q "^#$key " "$conf_file" 2>/dev/null; then
        # Commented key exists, uncomment and set
        sed -i "s|^#$key .*|$key $value|" "$conf_file"
    else
        # Key doesn't exist, append to the end of the file
        echo "$key $value" >> "$conf_file"
    fi
}

# Function to configure Redis server
configure_redis() {
    log_info "Configuring Redis server..."
    
    # Create backup of current config
    BACKUP_DIR="/etc/redis/backup-$(date +%Y%m%d%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp "$REDIS_CONF" "${BACKUP_DIR}/redis.conf.bak" 2>/dev/null || true
    cp "$REDIS_SENTINEL_CONF" "${BACKUP_DIR}/sentinel.conf.bak" 2>/dev/null || true
    log_info "Configuration backed up to $BACKUP_DIR"
    
    # Create ACL file for users
    REDIS_ACL_FILE="/etc/redis/users.acl"
    echo "# Redis ACL file" > "$REDIS_ACL_FILE"
    echo "user default off" >> "$REDIS_ACL_FILE"
    echo "user ${REDIS_ADMIN_USER} on >${REDIS_ADMIN_PASS} ~* &* +@all" >> "$REDIS_ACL_FILE"
    echo "user readonly on >${REDIS_READONLY_PASS} ~* &* +@read +@pubsub +subscribe +psubscribe -@dangerous" >> "$REDIS_ACL_FILE"
    chown redis:redis "$REDIS_ACL_FILE"
    chmod 600 "$REDIS_ACL_FILE"
    
    # Configure Redis
    log_info "Updating Redis configuration..."
    
    # Basic Settings
    set_redis_config "daemonize" "yes"
    set_redis_config "pidfile" "/var/run/redis/redis-server.pid"
    set_redis_config "port" "6379"
    set_redis_config "tcp-backlog" "511"
    set_redis_config "bind" "127.0.0.1"
    set_redis_config "unixsocket" "/var/run/redis/redis.sock"
    set_redis_config "unixsocketperm" "770"
    set_redis_config "timeout" "300"
    set_redis_config "tcp-keepalive" "300"
    
    # Security
    set_redis_config "protected-mode" "yes"
    set_redis_config "aclfile" "$REDIS_ACL_FILE"
    set_redis_config "rename-command" "FLUSHDB" ""
    set_redis_config "rename-command" "FLUSHALL" ""
    set_redis_config "rename-command" "CONFIG" ""
    set_redis_config "rename-command" "SHUTDOWN" ""
    
    # Memory Management
    set_redis_config "maxmemory" "1gb"
    set_redis_config "maxmemory-policy" "allkeys-lru"
    set_redis_config "maxmemory-samples" "5"
    set_redis_config "maxclients" "10000"
    set_redis_config "lazyfree-lazy-eviction" "yes"
    set_redis_config "lazyfree-lazy-expire" "yes"
    set_redis_config "lazyfree-lazy-server-del" "yes"
    
    # Persistence
    set_redis_config "appendonly" "yes"
    set_redis_config "appendfilename" "appendonly.aof"
    set_redis_config "appendfsync" "everysec"
    set_redis_config "no-appendfsync-on-rewrite" "no"
    set_redis_config "auto-aof-rewrite-percentage" "100"
    set_redis_config "auto-aof-rewrite-min-size" "64mb"
    set_redis_config "aof-load-truncated" "yes"
    set_redis_config "aof-rewrite-incremental-fsync" "yes"
    
    # Disable RDB snapshots since we're using AOF
    set_redis_config "save" ""
    
    # Performance
    set_redis_config "lua-time-limit" "5000"
    set_redis_config "slowlog-log-slower-than" "10000"
    set_redis_config "slowlog-max-len" "128"
    set_redis_config "latency-monitor-threshold" "0"
    set_redis_config "hash-max-ziplist-entries" "512"
    set_redis_config "hash-max-ziplist-value" "64"
    set_redis_config "list-max-ziplist-size" "-2"
    set_redis_config "list-compress-depth" "0"
    set_redis_config "set-max-intset-entries" "512"
    set_redis_config "zset-max-ziplist-entries" "128"
    set_redis_config "zset-max-ziplist-value" "64"
    set_redis_config "hll-sparse-max-bytes" "3000"
    set_redis_config "stream-node-max-bytes" "4096"
    set_redis_config "stream-node-max-entries" "100"
    
    # Logging
    set_redis_config "loglevel" "notice"
    set_redis_config "logfile" "/var/log/redis/redis-server.log"
    set_redis_config "syslog-enabled" "no"
    
    # Replication (disabled by default, can be enabled for master/slave setup)
    set_redis_config "replica-serve-stale-data" "yes"
    set_redis_config "replica-read-only" "yes"
    set_redis_config "repl-diskless-sync" "no"
    set_redis_config "repl-diskless-sync-delay" "5"
    set_redis_config "repl-disable-tcp-nodelay" "no"
    set_redis_config "replica-priority" "100"
    
    # Security - disable dangerous commands
    set_redis_config "rename-command" "DEBUG" ""
    set_redis_config "rename-command" "BGREWRITEAOF" ""
    set_redis_config "rename-command" "BGSAVE" ""
    set_redis_config "rename-command" "SAVE" ""
    
    # Set proper permissions
    chown -R redis:redis /etc/redis
    chmod 750 /etc/redis
    chmod 640 "$REDIS_CONF"
    
    # Configure systemd service
    if [ -f "/etc/systemd/system/redis.service" ]; then
        cat > /etc/systemd/system/redis.service <<EOF
[Unit]
Description=Redis In-Memory Data Store
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=redis
Group=redis
ExecStart=/usr/bin/redis-server /etc/redis/redis.conf --supervised systemd
ExecStop=/bin/redis-cli shutdown
Restart=always
RestartSec=10s
LimitNOFILE=10032

# Security options
NoNewPrivileges=yes
PrivateTmp=yes
ProtectHome=yes
ProtectSystem=full
ReadWritePaths=/var/lib/redis /var/log/redis /run/redis

# Sandboxing
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictNamespaces=yes
RestrictRealtime=yes
MemoryDenyWriteExecute=yes
SystemCallFilter=@system-service
SystemCallArchitectures=native
LockPersonality=yes
PrivateDevices=yes
ProtectHostname=yes
ProtectClock=yes
ProtectKernelLogs=yes
ProtectKernelModules=yes
ProtectProc=invisible
RestrictSUIDSGID=yes
CapabilityBoundingSet=
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF
        
        # Reload systemd
        systemctl daemon-reload
    fi
    
    # Create log directory if it doesn't exist
    mkdir -p /var/log/redis
    chown -R redis:adm /var/log/redis
    chmod 750 /var/log/redis
    
    # Set OOM score adjustment to prevent Redis from being killed under memory pressure
    echo 'vm.overcommit_memory = 1' > /etc/sysctl.d/99-redis.conf
    sysctl -p /etc/sysctl.d/99-redis.conf
    
    # Configure ulimits for Redis user
    echo 'redis soft nofile 65536' > /etc/security/limits.d/redis.conf
    echo 'redis hard nofile 65536' >> /etc/security/limits.d/redis.conf
    echo 'redis soft nproc 4096' >> /etc/security/limits.d/redis.conf
    echo 'redis hard nproc 16384' >> /etc/security/limits.d/redis.conf
    
    # Apply configuration
    log_info "Restarting Redis server..."
    if ! systemctl restart redis-server; then
        log_error "Failed to restart Redis server"
        journalctl -u redis-server --no-pager -n 50
        return 1
    fi
    
    # Verify Redis is running
    if ! systemctl is-active --quiet redis-server; then
        log_error "Redis server failed to start after configuration"
        journalctl -u redis-server --no-pager -n 50
        return 1
    fi
    
    # Test Redis connection
    if ! redis-cli -a "$REDIS_ADMIN_PASS" --no-auth-warning ping >/dev/null 2>&1; then
        log_error "Failed to connect to Redis with the new configuration"
        return 1
    fi
    
    # Save Redis info to a file
    REDIS_INFO_FILE="$SCRIPT_DIR/.redis_info"
    cat > "$REDIS_INFO_FILE" <<EOF
# Redis Server Information
REDIS_VERSION=$(redis-server --version | awk '{print $3}' | cut -d= -f2)
REDIS_CONFIG="$REDIS_CONF"
REDIS_ACL_FILE="$REDIS_ACL_FILE"
REDIS_DATA_DIR="/var/lib/redis"
REDIS_LOG_DIR="/var/log/redis"
REDIS_RUN_DIR="/run/redis"

# Connection Details (for local connections only)
REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
REDIS_SOCKET="/var/run/redis/redis.sock"

# Admin User (full access)
REDIS_ADMIN_USER="$REDIS_ADMIN_USER"
REDIS_ADMIN_PASS="$REDIS_ADMIN_PASS"

# Readonly User (for applications)
REDIS_READONLY_PASS="$REDIS_READONLY_PASS"

# Security Settings
REDIS_PROTECTED_MODE="yes"

# Performance Settings
REDIS_MAXMEMORY="1gb"
REDIS_MAXMEMORY_POLICY="allkeys-lru"
REDIS_MAXCLIENTS="10000"

# Persistence Settings
REDIS_APPENDONLY="yes"
REDIS_APPENDFSYNC="everysec"

# How to connect as admin:
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_ADMIN_PASS

# How to connect as readonly user:
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_READONLY_PASS

# How to monitor Redis:
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_ADMIN_PASS monitor

# How to get Redis info:
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_ADMIN_PASS info

# How to get memory usage:
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_ADMIN_PASS info memory

# How to get client list:
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_ADMIN_PASS client list

# How to flush all data (use with caution):
# redis-cli -h 127.0.0.1 -p 6379 -a \$REDIS_ADMIN_PASS flushall

# How to create a backup:
# sudo -u redis cp /var/lib/redis/dump.rdb /var/backups/redis-dump-\$(date +%Y%m%d).rdb
# sudo -u redis cp /var/lib/redis/appendonly.aof /var/backups/redis-aof-\$(date +%Y%m%d).aof

# For Nextcloud configuration, use these settings in config.php:
# 'redis' => [
#     'host'     => '/var/run/redis/redis.sock',
#     'port'     => 0,
#     'dbindex'  => 0,
#     'password' => '${REDIS_READONLY_PASS}',
#     'timeout'  => 1.5,
# ],
# 'memcache.local' => '\\OC\\Memcache\\Redis',
# 'memcache.distributed' => '\\OC\\Memcache\\Redis',
# 'memcache.locking' => '\\OC\\Memcache\\Redis',
# 'filelocking.enabled' => true,
# 'redis.cluster' => [
#     'seeds' => ['tls://127.0.0.1:7000', 'tls://127.0.0.1:7001'],
#     'timeout' => 0.0,
#     'read_timeout' => 0.0,
#     'persistent' => true,
#     'auth' => ['${REDIS_READONLY_PASS}'],
# ],
EOF
    
    chmod 600 "$REDIS_INFO_FILE"
    
    log_success "Redis server configured successfully"
    log_info "Redis configuration file: $REDIS_CONF"
    log_info "Redis ACL file: $REDIS_ACL_FILE"
    log_info "Redis data directory: /var/lib/redis"
    log_info "Redis log file: /var/log/redis/redis-server.log"
    log_info ""
    log_info "🔐 Redis credentials saved to: $REDIS_INFO_FILE"
    log_info "  - Admin user: $REDIS_ADMIN_USER"
    log_info "  - Admin password: $REDIS_ADMIN_PASS"
    log_info "  - Readonly password (for applications): $REDIS_READONLY_PASS"
    log_info ""
    log_info "🔍 Test Redis connection:"
    log_info "  redis-cli -h 127.0.0.1 -p 6379 -a $REDIS_READONLY_PASS ping"
    log_info ""
    log_info "For Nextcloud, use the readonly password in your config.php"
    
    return 0
}

# Main execution
main() {
    log_info "Starting Redis server configuration"
    
    if configure_redis; then
        log_success "Redis server configuration completed successfully"
        log_info ""
        log_info "Next steps:"
        log_info "1. Update your Nextcloud config.php with the Redis configuration"
        log_info "2. Consider setting up Redis Sentinel for high availability"
        log_info "3. Set up monitoring for Redis (e.g., RedisInsight, Prometheus)"
        log_info "4. Configure log rotation for Redis logs"
        log_info "5. Set up regular backups of Redis data"
        return 0
    else
        log_error "Redis configuration failed"
        return 1
    fi
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi