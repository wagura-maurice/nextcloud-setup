#!/bin/bash

# install-mysql.sh - Installation script for MariaDB/MySQL
# This script handles ONLY the installation of MariaDB/MySQL
# Configuration is handled by configure-mysql.sh

# Source core functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/common-functions.sh"
source "$SCRIPT_DIR/../core/logging.sh"
source "$SCRIPT_DIR/../core/config-manager.sh"

# Component details
COMPONENT="mysql"
DEPENDENCIES=(
    "mariadb-server"
    "mariadb-client"
    "python3-mysqldb"
)

# Main function
main() {
    print_header "Installing MariaDB/MySQL"
    
    # Load environment
    load_config
    
    # Check root
    require_root
    
    # Generate random root password if not set
    if [ -z "${MYSQL_ROOT_PASSWORD:-}" ]; then
        MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
        set_env "MYSQL_ROOT_PASSWORD" "$MYSQL_ROOT_PASSWORD"
    fi
    
    # Install dependencies
    install_dependencies
    
    # Install MySQL
    install_mysql
    
    # Save version to .env
    save_version
    
    print_success "MariaDB/MySQL installation completed"
    echo -e "\nRun '${YELLOW}./nextcloud-setup configure mysql${NC}' to configure MySQL\n"
}

# Install MySQL
install_mysql() {
    print_status "Installing MariaDB/MySQL..."
    
    # Set up non-interactive installation
    export DEBIAN_FRONTEND=noninteractive
    
    # Configure debconf for non-interactive installation
    echo "mariadb-server-10.6 mysql-server/root_password password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
    echo "mariadb-server-10.6 mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
    
    # Install MySQL server and client
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${DEPENDENCIES[@]}" || {
        print_error "Failed to install MariaDB/MySQL packages"
        exit 1
    }
    
    # Secure the installation
    secure_installation
    
    print_status "MariaDB/MySQL installed successfully"
}

# Secure MySQL installation
secure_installation() {
    print_status "Securing MySQL installation..."
    
    # Create a temporary file for the SQL commands
    local SQL_FILE
    SQL_FILE=$(mktemp)
    
    # Write SQL commands to the file
    cat > "$SQL_FILE" << EOF
-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Remove remote root login
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Remove test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Reload privilege tables
FLUSH PRIVILEGES;
EOF
    
    # Execute the SQL commands
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" < "$SQL_FILE"
    rm -f "$SQL_FILE"
    
    # Configure MySQL to start on boot
    systemctl enable mariadb
    systemctl restart mariadb
    
    print_status "MySQL security configuration completed"
}

# Save installed version to .env
save_version() {
    local version
    version=$(mysql --version | awk '{print $5}' | tr -d ',')
    set_env "MYSQL_VERSION" "$version"
    
    # Mark as installed
    touch "/etc/nextcloud/.mysql_installed"
    chmod 600 "/etc/nextcloud/.mysql_installed"
}

# Run main function
main "@"
    fi
}

# Execute main function
main "$@"
