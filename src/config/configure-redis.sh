#!/bin/bash

# configure-redis.sh - Configuration script for Redis
# This script configures Redis for optimal performance with Nextcloud

set -e

# Source core functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/common-functions.sh"
source "$SCRIPT_DIR/../core/logging.sh"
source "$SCRIPT_DIR/../core/config-manager.sh"

# Component details
COMPONENT="redis"

# Main function
main() {
    print_header "Configuring Redis"
    
    # Load environment
    load_config
    
    # Check root
    require_root
    
    # Check if Redis is installed
    if ! command -v redis-server &> /dev/null; then
        print_error "Redis is not installed. Please run 'install-redis.sh' first."
        exit 1
    fi
    
    # Configure Redis
    configure_redis
    
    # Apply security settings
    apply_security_settings
    
    # Test configuration
    if ! redis-cli ping &> /dev/null; then
        print_error "Redis configuration test failed. Please check the configuration."
        exit 1
    fi
    
    # Restart Redis
    systemctl restart redis-server
    
    print_success "Redis configuration completed"
}

# Configure Redis
configure_redis() {
    print_status "Configuring Redis..."
    
    # Create Redis configuration directory if it doesn't exist
    mkdir -p /etc/redis/redis.conf.d/
    
    # Create Redis configuration for Nextcloud
    cat > /etc/redis/redis.conf.d/nextcloud.conf << 'EOF'
# Redis configuration for Nextcloud
# Managed by Nextcloud Setup Script - Do not edit manually

# Basic settings
daemonize yes
pidfile /var/run/redis/redis-server.pid
port 6379
bind 127.0.0.1 ::1

# Unix socket
unixsocket /var/run/redis/redis-server.sock
unixsocketperm 770

# Security
protected-mode yes

# Memory management
maxmemory 512MB
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Snapshots
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis

# AOF (Append Only File)
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-rewrite-incremental-fsync yes

# Performance
tcp-keepalive 300
timeout 0
tcp-backlog 511

# Logging
loglevel notice
logfile /var/log/redis/redis-server.log

# Client settings
maxclients 10000
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60

# Slow log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Event notification
notify-keyspace-events ""

# Advanced configuration
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
aof-rewrite-incremental-fsync yes
EOF

    # Include our configuration in the main redis.conf
    if ! grep -q "^include /etc/redis/redis.conf.d/" /etc/redis/redis.conf; then
        echo -e "\n# Include additional configuration files\ninclude /etc/redis/redis.conf.d/*.conf" >> /etc/redis/redis.conf
    fi
    
    # Set proper permissions
    chown -R redis:redis /etc/redis/
    chmod -R 750 /etc/redis/
    
    # Create log directory if it doesn't exist
    mkdir -p /var/log/redis/
    chown redis:redis /var/log/redis/
    
    print_status "Redis configuration applied"
}

# Apply security settings
apply_security_settings() {
    print_status "Applying security settings..."
    
    # Disable dangerous commands
    if ! grep -q "^rename-command" /etc/redis/redis.conf; then
        echo -e "\n# Disable dangerous commands\nrename-command FLUSHDB \"\"\nrename-command FLUSHALL \"\"\nrename-command CONFIG \"\"\nrename-command DEBUG \"\"\n" >> /etc/redis/redis.conf
    fi
    
    # Set Redis password if not already set
    if ! grep -q "^requirepass" /etc/redis/redis.conf; then
        local redis_password=$(openssl rand -base64 32)
        echo "requirepass $redis_password" >> /etc/redis/redis.conf
        set_env "REDIS_PASSWORD" "$redis_password"
        print_status "Redis password set and saved to .env"
    fi
    
    # Set proper permissions
    chown redis:redis /etc/redis/redis.conf
    chmod 640 /etc/redis/redis.conf
    
    print_status "Security settings applied"
}

# Run main function
main "@"
