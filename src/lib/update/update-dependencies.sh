#!/bin/bash
# System Dependencies Update Script
# Updates system packages and dependencies for Nextcloud

# Load core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"

# Default configuration
PHP_VERSION="${PHP_VERSION:-8.2}"
NEXTCLOUD_ROOT="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"

# Update package lists
update_package_lists() {
    log_info "Updating package lists..."
    
    if ! apt-get update; then
        log_error "Failed to update package lists"
        return 1
    fi
    
    log_success "Package lists updated"
    return 0
}

# Upgrade installed packages
upgrade_packages() {
    log_info "Upgrading installed packages..."
    
    if ! DEBIAN_FRONTEND=noninteractive apt-get -y upgrade; then
        log_error "Failed to upgrade packages"
        return 1
    fi
    
    log_success "Packages upgraded"
    return 0
}

# Update PHP and extensions
update_php() {
    log_section "Updating PHP $PHP_VERSION"
    
    # Install PHP repository if not already present
    if ! apt-cache policy | grep -q "ondrej/php"; then
        log_info "Adding PHP repository..."
        apt-get install -y software-properties-common
        add-apt-repository -y ppa:ondrej/php
        update_package_lists || return 1
    fi
    
    # Install/update PHP and required extensions
    local php_packages=(
        "php${PHP_VERSION}"
        "php${PHP_VERSION}-fpm"
        "php${PHP_VERSION}-common"
        "php${PHP_VERSION}-mysql"
        "php${PHP_VERSION}-gd"
        "php${PHP_VERSION}-json"
        "php${PHP_VERSION}-curl"
        "php${PHP_VERSION}-mbstring"
        "php${PHP_VERSION}-intl"
        "php${PHP_VERSION}-imagick"
        "php${PHP_VERSION}-xml"
        "php${PHP_VERSION}-zip"
        "php${PHP_VERSION}-bcmath"
        "php${PHP_VERSION}-opcache"
        "php${PHP_VERSION}-apcu"
        "php${PHP_VERSION}-redis"
    )
    
    log_info "Installing/updating PHP packages..."
    if ! apt-get install -y "${php_packages[@]}"; then
        log_error "Failed to install/update PHP packages"
        return 1
    fi
    
    # Restart PHP-FPM
    if systemctl is-active --quiet "php${PHP_VERSION}-fpm"; then
        log_info "Restarting PHP-FPM..."
        systemctl restart "php${PHP_VERSION}-fpm"
    fi
    
    log_success "PHP updated successfully"
    return 0
}

# Update database server
update_database() {
    log_section "Updating Database Server"
    
    local db_type="${DB_TYPE:-mysql}"
    
    case "$db_type" in
        mysql|mariadb)
            update_mysql
            ;;
        postgresql|postgres)
            update_postgresql
            ;;
        *)
            log_warning "Unsupported database type: $db_type"
            return 1
            ;;
    esac
    
    return $?
}

# Update MySQL/MariaDB
update_mysql() {
    log_info "Updating MySQL/MariaDB..."
    
    if command -v mysql &> /dev/null; then
        log_info "MySQL/MariaDB is already installed"
        return 0
    fi
    
    # Install MySQL server
    if ! apt-get install -y mariadb-server; then
        log_error "Failed to install MariaDB"
        return 1
    fi
    
    # Run secure installation
    log_info "Running MySQL secure installation..."
    mysql_secure_installation <<EOF

y
y
${DB_ROOT_PASSWORD:-}
${DB_ROOT_PASSWORD:-}
y
y
y
y
EOF
    
    log_success "MySQL/MariaDB updated successfully"
    return 0
}

# Update PostgreSQL
update_postgresql() {
    log_info "Updating PostgreSQL..."
    
    if ! apt-get install -y postgresql postgresql-contrib; then
        log_error "Failed to update PostgreSQL"
        return 1
    fi
    
    log_success "PostgreSQL updated successfully"
    return 0
}

# Update web server
update_webserver() {
    log_section "Updating Web Server"
    
    if systemctl is-active --quiet apache2; then
        update_apache
    elif systemctl is-active --quiet nginx; then
        update_nginx
    else
        log_warning "No web server detected"
        return 1
    fi
    
    return $?
}

# Update Apache
update_apache() {
    log_info "Updating Apache..."
    
    if ! apt-get install -y apache2 libapache2-mod-php${PHP_VERSION}; then
        log_error "Failed to update Apache"
        return 1
    fi
    
    # Enable required modules
    a2enmod rewrite headers env dir mime setenvif ssl
    
    # Restart Apache
    systemctl restart apache2
    
    log_success "Apache updated successfully"
    return 0
}

# Update Nginx
update_nginx() {
    log_info "Updating Nginx..."
    
    if ! apt-get install -y nginx php${PHP_VERSION}-fpm; then
        log_error "Failed to update Nginx"
        return 1
    fi
    
    # Restart Nginx and PHP-FPM
    systemctl restart nginx
    systemctl restart "php${PHP_VERSION}-fpm"
    
    log_success "Nginx updated successfully"
    return 0
}

# Update Redis
update_redis() {
    log_section "Updating Redis"
    
    if ! apt-get install -y redis-server; then
        log_warning "Failed to update Redis"
        return 1
    fi
    
    # Enable and start Redis
    systemctl enable --now redis-server
    
    log_success "Redis updated successfully"
    return 0
}

# Main function
main() {
    log_section "System Dependencies Update"
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Update package lists
    if ! update_package_lists; then
        return 1
    fi
    
    # Upgrade packages
    if ! upgrade_packages; then
        log_warning "Package upgrades had issues"
    fi
    
    # Update components
    local components=(
        "update_php"
        "update_database"
        "update_webserver"
        "update_redis"
    )
    
    for component in "${components[@]}"; do
        if ! $component; then
            log_warning "$component had issues"
        fi
    done
    
    log_success "System dependencies updated successfully"
    return 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
