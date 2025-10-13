#!/bin/bash

# Nextcloud CLI - Unified Interface for Nextcloud Setup and Maintenance
# This script provides a single entry point for all Nextcloud operations

# Set strict mode for better error handling
set -o errexit
set -o nounset
set -o pipefail

# Get the directory where this script is located
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$SCRIPT_DIR"
export SRC_DIR="$PROJECT_ROOT/src"
export CORE_DIR="$SRC_DIR/core"
export UTILS_DIR="$SRC_DIR/utilities"

# Set default log level if not set
export LOG_LEVEL=${LOG_LEVEL:-INFO}

# Source environment loader first (it will handle logging initialization)
if [ -f "$CORE_DIR/env-loader.sh" ]; then
    source "$CORE_DIR/env-loader.sh"
else
    echo "Error: env-loader.sh not found in $CORE_DIR" >&2
    exit 1
fi

# Now load the environment
load_environment

# Ensure logging is initialized
if ! type -t log_info >/dev/null 2>&1; then
    echo "Error: Failed to initialize logging" >&2
    exit 1
fi

# Log script start
log_info "=== Starting Nextcloud Setup ==="
log_info "Project Root: $PROJECT_ROOT"
log_info "Log Directory: $LOG_DIR"

# Source additional core scripts
source "$CORE_DIR/config-manager.sh"

# Load installation configuration
load_installation_config

# Ensure required directories exist
mkdir -p "$LOG_DIR"
chmod 750 "$LOG_DIR"
chmod 750 "$BACKUP_DIR"
chmod 750 "$(dirname "$NEXTCLOUD_DATA_DIR")"

# Define component installation and configuration order
INSTALL_ORDER=(
    "system"
    "webserver"
    "php"
    "database"
    "redis"
    "nextcloud"
)

# Let's Encrypt is optional and should be installed separately
LETSENCRYPT_COMPONENT="letsencrypt"

# Show usage information
show_usage() {
    echo "Nextcloud CLI - Unified Interface for Nextcloud Setup and Maintenance"
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  install [component]    Install Nextcloud components (all, ${INSTALL_ORDER[*]}, $LETSENCRYPT_COMPONENT)"
    echo "  configure [target]     Configure system components (all, ${INSTALL_ORDER[*]}, $LETSENCRYPT_COMPONENT)"
    echo "  update                 Update Nextcloud and its components"
    echo "  status                 Show status of all components"
    echo "  help                   Show this help message"
    echo ""
    echo "For backup, restore, and maintenance operations, use nextcloud-manager.sh"
    echo ""
    echo "Installation Order:"
    echo "  1. system"
    echo "  2. webserver (Apache/Nginx)"
    echo "  3. php"
    echo "  4. database (MySQL/MariaDB)"
    echo "  5. redis"
    echo "  6. nextcloud"
    echo "  7. $LETSENCRYPT (optional, run separately)"
    echo ""

# Update Nextcloud
    log_info "Starting Nextcloud update..."
    # Implementation here
    log_success "Update completed successfully"
}

# Check if a component is installed
is_component_installed() {
    local component=$1
    
    case $component in
        system)
            # Check for basic system utilities
            command -v apt-get >/dev/null 2>&1 && \
            command -v systemctl >/dev/null 2>&1
            ;;
        webserver)
            # Check for Apache
            systemctl is-active --quiet apache2 2>/dev/null
            ;;
        php)
            # Check for PHP-FPM
            systemctl is-active --quiet php*-fpm 2>/dev/null
            ;;
        database)
            # Check for MariaDB
            command -v mariadb >/dev/null 2>&1 && \
            systemctl is-active --quiet mariadb 2>/dev/null
            ;;
        nextcloud)
{{ ... }}
            systemctl is-active --quiet 'php*-fpm' 2>/dev/null
            ;;
        database)
            systemctl is-active --quiet mariadb 2>/dev/null
            ;;
        nextcloud)
            # Check if web server is running and can access Nextcloud
            local url="http://localhost/status.php"
            curl -s -f "$url" | grep -q 'installed.*true' 2>/dev/null
            ;;
            # Check if certbot is installed and has certificates
            (command -v certbot >/dev/null 2>&1 || command -v certbot-auto >/dev/null 2>&1) && \
            [[ -n $(find /etc/letsencrypt/live -name '*.pem' 2>/dev/null) ]]
            ;;
        *) return 1 ;;
    esac
    
    return $?
}

# Check if a component is properly configured
is_component_configured() {
    local component=$1
    
    case $component in
        system) return 0 ;;  # System is always considered configured
        webserver)
            # Check for valid web server configuration
            if systemctl is-active --quiet apache2 2>/dev/null; then
                apache2ctl -t >/dev/null 2>&1
            else
                return 1
            fi
            ;;
        php)
            # Check for required PHP extensions
            local required_extensions=("mysqli" "pdo_mysql" "gd" "xml" "curl" "mbstring" "intl" "zip" "imagick")
            local missing_extensions=()
            
            for ext in "${required_extensions[@]}"; do
                if ! php -m | grep -q -i "^${ext}$"; then
                    missing_extensions+=("$ext")
                fi
            done
            
            [[ ${#missing_extensions[@]} -eq 0 ]]
            ;;
        database)
            # Check if Nextcloud database exists and is accessible
            if [[ -f "$PROJECT_ROOT/.db_credentials" ]]; then
                source "$PROJECT_ROOT/.db_credentials"
                mariadb -u "$db_user" -p"$db_pass" -e "USE ${db_name};" >/dev/null 2>&1
            else
                return 1
            fi
            ;;
        redis)
            # Check if Redis is configured in Nextcloud
            if [[ -f "$NEXTCLOUD_ROOT/config/config.php" ]]; then
                grep -q "'memcache.local' => '\\OC\\\\Memcache\\\\Redis'" "$NEXTCLOUD_ROOT/config/config.php" && \
                grep -q "'redis' => " "$NEXTCLOUD_ROOT/config/config.php"
            else
                return 1
            fi
            ;;
        nextcloud)
            # Check if Nextcloud is installed and configured
            if [[ -f "$NEXTCLOUD_ROOT/occ" ]]; then
                sudo -u "$HTTP_USER" php "$NEXTCLOUD_ROOT/occ" status --no-ansi 2>&1 | grep -q 'installed: true'
            else
                return 1
            fi
            ;;
        letsencrypt)
            # Check if Let's Encrypt is properly configured
            if [[ -f "/etc/letsencrypt/options-ssl-apache.conf" || -f "/etc/letsencrypt/options-ssl-nginx.conf" ]]; then
                return 0
            else
                return 1
            fi
            ;;
        *) return 1 ;;
    esac
    
    return $?
}Handle Let's Encrypt separately as it's optional
    if [[ "$component" == "$LETSENCRYPT_COMPONENT" ]]; then
        run_component_script "install" "letsencrypt"
        return $?
    fi
    
{{ ... }}
            ;;
        update)
            update_nextcloud
            ;;
        status)
        # Show detailed status of all components
        log_section "Nextcloud Setup - Component Status"
        echo -e "\n\033[1mComponent          Installed  Configured  Status\033[0m"
        echo "------------------------------------------------"
        
        # Check each component
        for comp in "${INSTALL_ORDER[@]}" "$LETSENCRYPT_COMPONENT"; do
            local installed=false
            local configured=false
            local status="Not Running"
            
            # Check if component is installed
            if is_component_installed "$comp"; then
                installed=true
                
                # Check if component is running
                if is_component_running "$comp"; then
                    status="Running"
                fi
                
                # Check if component is configured
                if is_component_configured "$comp"; then
                    configured=true
                fi
            fi
            
            # Format output with colors
            local installed_icon=$([[ "$installed" == true ]] && echo -e "\033[0;32m✓\033[0m" || echo -e "\033[0;31m✗\033[0m")
            local configured_icon=$([[ "$configured" == true ]] && echo -e "\033[0;32m✓\033[0m" || echo -e "\033[0;33m✗\033[0m")
            
            # Color status based on state
            if [[ "$status" == "Running" ]]; then
                status="\033[0;32m$status\033[0m"
            else
                status="\033[0;31m$status\033[0m"
            fi
            
            # Print component status
            printf "%-18s %-10s %-11s %-20s\n" "$comp" "$installed_icon" "$configured_icon" "$status"
        done
            show_usage
            exit 1
            ;;
    esac
    
    log_info "Operation completed successfully"
}
