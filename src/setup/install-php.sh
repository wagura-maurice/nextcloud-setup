#!/bin/bash

# install-php.sh - Installation script for PHP and required extensions
# This script handles ONLY the installation of PHP and its extensions
# Configuration is handled by configure-php.sh

set -e

# Source core functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/common-functions.sh"
source "$SCRIPT_DIR/../core/logging.sh"
source "$SCRIPT_DIR/../core/config-manager.sh"

# Component details
COMPONENT="php"

# PHP version to install (can be overridden in .env)
PHP_VERSION="${PHP_VERSION:-8.2}"

# Required PHP extensions for Nextcloud
# Note: Some extensions are included in the PHP core but listed here for completeness
PHP_EXTENSIONS=(
    "php${PHP_VERSION}"
    "php${PHP_VERSION}-fpm"
    "php${PHP_VERSION}-common"
    "php${PHP_VERSION}-mysql"
    "php${PHP_VERSION}-gd"
    "php${PHP_VERSION}-json"
    "php${PHP_VERSION}-curl"
    "php${PHP_VERSION}-mbstring"
    "php${PHP_VERSION}-intl"
    "php${PHP_VERSION}-bcmath"
    "php${PHP_VERSION}-xml"
    "php${PHP_VERSION}-zip"
    "php${PHP_VERSION}-apcu"
    "php${PHP_VERSION}-redis"
    "php${PHP_VERSION}-imagick"
    "php${PHP_VERSION}-bz2"
    "php${PHP_VERSION}-gmp"
    "php${PHP_VERSION}-imap"
    "php${PHP_VERSION}-ldap"
    "php-phpseclib3"
    "php${PHP_VERSION}-sodium"
    "php${PHP_VERSION}-ftp"
    "php${PHP_VERSION}-ssh2"
    "php${PHP_VERSION}-sockets"
    "php${PHP_VERSION}-simplexml"
    "php${PHP_VERSION}-xmlwriter"
    "php${PHP_VERSION}-fileinfo"
    "php${PHP_VERSION}-exif"
    "php${PHP_VERSION}-iconv"
    "php${PHP_VERSION}-ctype"
    "php${PHP_VERSION}-dom"
    "php${PHP_VERSION}-tokenizer"
)

# Main function
main() {
    print_header "Installing PHP ${PHP_VERSION}"
    
    # Load environment
    load_config
    
    # Check root
    require_root
    
    # Add PHP repository
    add_php_repository
    
    # Install PHP and extensions
    install_php
    
    # Save version to .env
    save_version
    
    print_success "PHP ${PHP_VERSION} installation completed"
    echo -e "\nRun '${YELLOW}./nextcloud-setup configure php${NC}' to configure PHP\n"
}

# Add PHP repository
add_php_repository() {
    print_status "Adding PHP repository..."
    
    # Install required packages
    apt-get update
    apt-get install -y software-properties-common apt-transport-https lsb-release ca-certificates curl
    
    # Add PHP repository
    if ! apt-cache policy | grep -q "ondrej/php"; then
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
        apt-get update
    fi
}

# Install PHP and extensions
install_php() {
    print_status "Installing PHP ${PHP_VERSION} and extensions..."
    
    # Install PHP and extensions
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${PHP_EXTENSIONS[@]}"
    
    # Create PHP version symlink (e.g., /usr/bin/php -> /usr/bin/php8.2)
    update-alternatives --set php "/usr/bin/php${PHP_VERSION}" || \
        ln -sf "/usr/bin/php${PHP_VERSION}" /usr/bin/php
    
    # Enable PHP-FPM
    systemctl enable "php${PHP_VERSION}-fpm"
    systemctl start "php${PHP_VERSION}-fpm"
    
    # Install Composer
    if ! command -v composer &> /dev/null; then
        print_status "Installing Composer..."
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi
    
    print_status "PHP ${PHP_VERSION} installation completed"
}

# Save installed version to .env
save_version() {
    local version
    version=$(php -v | grep -oP '(?<=PHP )([0-9]+\.[0-9]+\.[0-9]+)' | head -1)
    set_env "PHP_VERSION" "$version"
    
    # Save PHP-FPM socket path
    set_env "PHP_FPM_SOCKET" "/var/run/php/php${PHP_VERSION}-fpm.sock"
    
    # Save PHP INI paths
    set_env "PHP_INI_DIR" "/etc/php/${PHP_VERSION}"
    set_env "PHP_FPM_CONF" "/etc/php/${PHP_VERSION}/fpm/php-fpm.conf"
    set_env "PHP_INI" "/etc/php/${PHP_VERSION}/fpm/php.ini"
    set_env "PHP_POOL_DIR" "/etc/php/${PHP_VERSION}/fpm/pool.d"
}

# Run main function
main "@"
