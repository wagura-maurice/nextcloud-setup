#!/bin/bash

# install-redis.sh - Installation script for Redis
# This script handles ONLY the installation of Redis server
# Configuration is handled by configure-redis.sh

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
    print_header "Installing Redis"
    
    # Load environment
    load_config
    
    # Check root
    require_root
    
    # Install Redis
    install_redis
    
    # Save version to .env
    save_version
    
    print_success "Redis installation completed"
    echo -e "\nRun '${YELLOW}./nextcloud-setup configure redis${NC}' to configure Redis\n"
}

# Install Redis
install_redis() {
    print_status "Installing Redis..."
    
    # Install Redis server
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server
    
    # Create necessary directories
    mkdir -p /etc/redis/redis.conf.d/
    
    # Set proper permissions
    chown -R redis:redis /etc/redis/
    chmod -R 750 /etc/redis/
    
    # Enable and start Redis
    systemctl enable redis-server
    systemctl restart redis-server
    
    print_status "Redis installation completed"
}

# Save installed version to .env
save_version() {
    local version
    version=$(redis-server --version | awk '{print $3}' | cut -d'=' -f2)
    set_env "REDIS_VERSION" "$version"
    set_env "REDIS_SOCKET" "/var/run/redis/redis-server.sock"
    set_env "REDIS_CONF" "/etc/redis/redis.conf"
    set_env "REDIS_DATA_DIR" "/var/lib/redis"
}

# Run main function
main "@"

# means install redis etc
