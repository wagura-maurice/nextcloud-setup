#!/bin/bash

# This script configures PHP settings consistently across all PHP interfaces
# It should be run as root during the Nextcloud installation

set -e

# Function to print status messages
print_status() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Path to the PHP configuration file
PHP_CONFIG="./configs/php-settings.ini"

# Check if the config file exists
if [ ! -f "$PHP_CONFIG" ]; then
    print_status "Error: PHP configuration file not found at $PHP_CONFIG"
    exit 1
fi

# Function to backup existing config
backup_config() {
    local config_file=$1
    if [ -f "$config_file" ]; then
        cp "$config_file" "${config_file}.bak.$(date +%Y%m%d%H%M%S)"
        print_status "Backed up $config_file"
    fi
}

# Configure PHP for Apache2
print_status "Configuring PHP for Apache2..."
APACHE_PHP_INI="/etc/php/8.4/apache2/php.ini"
if [ -f "$APACHE_PHP_INI" ]; then
    backup_config "$APACHE_PHP_INI"
    cp "$PHP_CONFIG" "$APACHE_PHP_INI"
    print_status "Applied PHP settings to Apache2 configuration"
else
    print_status "Warning: Apache2 PHP configuration not found at $APACHE_PHP_INI"
fi

# Configure PHP for CLI
print_status "Configuring PHP for CLI..."
CLI_PHP_INI="/etc/php/8.4/cli/php.ini"
if [ -f "$CLI_PHP_INI" ]; then
    backup_config "$CLI_PHP_INI"
    cp "$PHP_CONFIG" "$CLI_PHP_INI"
    
    # Some CLI-specific overrides
    sed -i 's/^memory_limit = .*/memory_limit = -1/' "$CLI_PHP_INI"
    sed -i 's/^max_execution_time = .*/max_execution_time = 0/' "$CLI_PHP_INI"
    
    print_status "Applied PHP settings to CLI configuration"
else
    print_status "Warning: CLI PHP configuration not found at $CLI_PHP_INI"
fi

# Configure PHP-FPM
print_status "Configuring PHP-FPM..."
FPM_PHP_INI="/etc/php/8.4/fpm/php.ini"
FPM_POOL_CONF="/etc/php/8.4/fpm/pool.d/www.conf"

if [ -f "$FPM_PHP_INI" ]; then
    backup_config "$FPM_PHP_INI"
    cp "$PHP_CONFIG" "$FPM_PHP_INI"
    print_status "Applied PHP settings to FPM configuration"
    
    # Configure FPM pool settings
    if [ -f "$FPM_POOL_CONF" ]; then
        backup_config "$FPM_POOL_CONF"
        
        # Apply FPM pool settings
        sed -i 's/^pm = .*/pm = dynamic/' "$FPM_POOL_CONF"
        sed -i 's/^pm.max_children = .*/pm.max_children = 64/' "$FPM_POOL_CONF"
        sed -i 's/^pm.start_servers = .*/pm.start_servers = 16/' "$FPM_POOL_CONF"
        sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 16/' "$FPM_POOL_CONF"
        sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 32/' "$FPM_POOL_CONF"
        sed -i 's/^pm.max_requests = .*/pm.max_requests = 500/' "$FPM_POOL_CONF"
        
        # Set error log
        sed -i 's|^;*error_log = .*|error_log = /var/log/php8.4-fpm/error.log|' "$FPM_POOL_CONF"
        
        # Ensure the log directory exists
        mkdir -p /var/log/php8.4-fpm
        chown www-data:www-data /var/log/php8.4-fpm
        
        print_status "Applied FPM pool settings"
    else
        print_status "Warning: FPM pool configuration not found at $FPM_POOL_CONF"
    fi
else
    print_status "Warning: FPM PHP configuration not found at $FPM_PHP_INI"
fi

# Create necessary directories
print_status "Creating necessary directories..."
mkdir -p /var/www/nextcloud/tmp
chown -R www-data:www-data /var/www/nextcloud/tmp
chmod 750 /var/www/nextcloud/tmp

# Create OPcache directory
mkdir -p /var/www/nextcloud/.opcache
chown -R www-data:www-data /var/www/nextcloud/.opcache
chmod 750 /var/www/nextcloud/.opcache

# Restart services
print_status "Restarting PHP and web services..."
systemctl restart php8.4-fpm
systemctl restart apache2

print_status "PHP configuration completed successfully!"

# Verify PHP configurations
echo -e "\nVerifying PHP configurations..."
for php_ini in "$APACHE_PHP_INI" "$CLI_PHP_INI" "$FPM_PHP_INI"; do
    if [ -f "$php_ini" ]; then
        echo -e "\n=== $php_ini ==="
        grep -E '^(memory_limit|max_execution_time|opcache\.|session\.|date\.timezone)' "$php_ini" | grep -v '^;'
    fi
done

echo -e "\nPHP configuration complete!"
