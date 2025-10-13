#!/bin/bash

# Nextcloud Setup Script
# This script initializes the environment and runs the Nextcloud setup process in the correct order

# Set strict mode for better error handling
set -o errexit
set -o nounset
set -o pipefail

# Set script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CORE_DIR="${PROJECT_ROOT}/src/core"
UTILS_DIR="${PROJECT_ROOT}/src/utilities/install"

# Set up logging
LOG_DIR="${PROJECT_ROOT}/logs"
mkdir -p "${LOG_DIR}" 2>/dev/null
chmod 750 "${LOG_DIR}" 2>/dev/null || true

# Set log file with timestamp
LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d%H%M%S).log"
touch "${LOG_FILE}" 2>/dev/null || {
    LOG_FILE="/tmp/nextcloud-setup-$(date +%s).log"
    touch "${LOG_FILE}" || {
        echo "Failed to create log file" >&2
        exit 1
    }
}
chmod 640 "${LOG_FILE}" 2>/dev/null || true
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Define installation order
readonly INSTALL_ORDER=(
    "system"
    "php"
    "mariadb"
    "apache"
    "redis"
    "certbot"
    "nextcloud"
)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Export paths
export SCRIPT_DIR PROJECT_ROOT SCRIPT_NAME

# Set default environment variables
: "${SRC_DIR:=${PROJECT_ROOT}/src}"
: "${CORE_DIR:=${SRC_DIR}/core}"
: "${UTILS_DIR:=${SRC_DIR}/utilities}"
: "${LOG_DIR:=${PROJECT_ROOT}/logs}"
: "${CONFIG_DIR:=${PROJECT_ROOT}/config}"
: "${DATA_DIR:=${PROJECT_ROOT}/data}"
: "${LOG_LEVEL:="INFO"}"
: "${LOG_FILE:=${LOG_DIR}/nextcloud-setup-$(date +%Y%m%d%H%M%S).log}"

# Export all variables
export SRC_DIR CORE_DIR UTILS_DIR LOG_DIR CONFIG_DIR DATA_DIR LOG_LEVEL LOG_FILE

# Export file permission variables
export DIR_PERMS FILE_PERMS SECURE_DIR_PERMS SECURE_FILE_PERMS

# Export exit code variables
export E_SUCCESS E_ERROR E_INVALID_ARG E_MISSING_DEP E_PERMISSION E_CONFIG

# Create required directories with proper permissions
mkdir -p "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/tmp"
chmod 750 "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/tmp"

# Simple logging function if we can't load the proper one
log() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '[timestamp-error]')"
    
    if [ $# -ge 2 ]; then
        local level="$1"
        shift
        echo "[${timestamp}] [${level}] $*" | tee -a "${LOG_FILE}" >&2
    else
        echo "[${timestamp}] [INFO] $*" | tee -a "${LOG_FILE}" >&2
    fi
}

# Load environment and common functions
load_environment() {
    # Source environment loader if it exists
    if [ -f "${CORE_DIR}/env-loader.sh" ]; then
        echo -e "${GREEN}Loading environment from ${CORE_DIR}/env-loader.sh${NC}"
        if ! source "${CORE_DIR}/env-loader.sh"; then
            echo -e "${RED}Failed to load environment${NC}" >&2
            return 1
        fi
    else
        echo -e "${YELLOW}Warning: env-loader.sh not found in ${CORE_DIR}${NC}" >&2
    fi

    # Source common functions if they exist
    if [ -f "${CORE_DIR}/common-functions.sh" ]; then
        if ! source "${CORE_DIR}/common-functions.sh"; then
            echo -e "${YELLOW}Warning: Failed to load common functions${NC}" >&2
        fi
    fi
    
    return 0
}

# Log a message with timestamp
log() {
    local level="${1:-INFO}"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}" >&2
}

# Run a command with error handling
run_command() {
    local cmd="$*"
    log "EXEC" "Running: ${cmd}"
    
    if eval "${cmd}"; then
        log "SUCCESS" "Command completed successfully"
        return 0
    else
        local status=$?
        log "ERROR" "Command failed with status ${status}: ${cmd}"
        return $status
    fi
}

# Install a component
install_component() {
    local component="$1"
    local script_path="${UTILS_DIR}/install-${component}.sh"
    
    if [ ! -f "${script_path}" ]; then
        log "ERROR" "Installation script not found: ${script_path}"
        return 1
    fi
    
    log "INFO" "Installing ${component}..."
    
    # Make the script executable
    chmod +x "${script_path}"
    
    # Run the installation script
    if ! bash -x "${script_path}"; then
        log "ERROR" "Failed to install ${component}"
        return 1
    fi
    
    log "SUCCESS" "Successfully installed ${component}"
    return 0
}

# Main installation function
run_installation() {
    log "INFO" "Starting Nextcloud installation process"
    
    # Create required directories
    mkdir -p "${LOG_DIR}" "${PROJECT_ROOT}/config"
    
    # Load environment
    if ! load_environment; then
        log "ERROR" "Failed to load environment"
        return 1
    fi
    
    # Run installations in order
    for component in "${INSTALL_ORDER[@]}"; do
        if ! install_component "${component}"; then
            log "ERROR" "Installation failed at component: ${component}"
            return 1
        fi
    done
    
    log "SUCCESS" "Nextcloud installation completed successfully"
    return 0
}

# Set up project directory structure
: "${SRC_DIR:=${PROJECT_ROOT}/src}"
: "${CORE_DIR:=${SRC_DIR}/core}"
: "${UTILS_DIR:=${SRC_DIR}/utilities}"
: "${LOG_DIR:=${PROJECT_ROOT}/logs}"
: "${CONFIG_DIR:=${PROJECT_ROOT}/config}"
: "${DATA_DIR:=${PROJECT_ROOT}/data}"

export SRC_DIR CORE_DIR UTILS_DIR LOG_DIR CONFIG_DIR DATA_DIR

# Create required directories with proper permissions
mkdir -p "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/tmp"
chmod 750 "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/tmp"

# Set default environment variables
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
export LOG_FILE="${LOG_DIR}/nextcloud-setup-$(date +%Y%m%d%H%M%S).log"

# Add project utilities to PATH
export PATH="${UTILS_DIR}:${PATH}"

# Ensure we have a clean environment
unset CDPATH

# Initialize logging first
if [ -f "${CORE_DIR}/logging.sh" ]; then
    source "${CORE_DIR}/logging.sh"
    init_logging
    log_info "=== Starting Nextcloud Setup ==="
    log_info "Project Root: ${PROJECT_ROOT}"
    log_info "Log File: ${LOG_FILE}"
else
    echo "Error: Failed to load logging module" >&2
    exit 1
fi

# Load environment
if [ -f "${CORE_DIR}/env-loader.sh" ]; then
    source "${CORE_DIR}/env-loader.sh"
else
    log_error "env-loader.sh not found in ${CORE_DIR}" 1
fi

# Set default log level if not set
export LOG_LEVEL=${LOG_LEVEL:-INFO}

# Source core functions first
if [ -f "$CORE_DIR/common-functions.sh" ]; then
    source "$CORE_DIR/common-functions.sh"
else
    echo "Error: common-functions.sh not found in $CORE_DIR" >&2
    exit 1
fi

# Source logging
if [ -f "$CORE_DIR/logging.sh" ]; then
    source "$CORE_DIR/logging.sh"
else
    echo "Error: logging.sh not found in $CORE_DIR" >&2
    exit 1
fi

# Initialize logging
init_logging

# Source environment loader
if [ -f "$CORE_DIR/env-loader.sh" ]; then
    source "$CORE_DIR/env-loader.sh"
else
    log_error "env-loader.sh not found in $CORE_DIR"
    exit 1
fi

# Now load the environment
load_environment

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
    "apache"
    "php"
    "mariadb"
    "redis"
    "nextcloud"
    "certbot"
)

# Configuration order (includes cron at the end)
CONFIG_ORDER=(
    "system"
    "apache"
    "php"
    "mariadb"
    "redis"
    "nextcloud"
    "certbot"
    "cron"
)
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
    echo "  2. apache"
    echo "  3. php"
    echo "  4. mariadb"
    echo "  5. redis"
    echo "  6. nextcloud"
    echo "  7. certbot"
    echo ""
    echo "Configuration Order:"
    echo "  1. system"
    echo "  2. apache"
    echo "  3. php"
    echo "  4. mariadb"
    echo "  5. redis"
    echo "  6. nextcloud"
    echo "  7. certbot"
    echo "  8. cron"
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
            # Check for essential system utilities and services
            command -v apt-get >/dev/null 2>&1 && \
            command -v systemctl >/dev/null 2>&1 && \
            systemctl is-active --quiet cron && \
            systemctl is-active --quiet fail2ban && \
            systemctl is-active --quiet ufw
            ;;
        apache)
            # Check for Apache installation and service
            command -v apache2 >/dev/null 2>&1 && \
            systemctl is-active --quiet apache2 2>/dev/null
            ;;
        php)
            # Check for PHP and PHP-FPM
            local php_version=$(php -v 2>/dev/null | grep -oP '^PHP \K[0-9]+\.[0-9]+')
            [ -n "$php_version" ] && \
            systemctl is-active --quiet "php${php_version}-fpm" 2>/dev/null
            ;;
        mariadb)
            # Check for MariaDB/MySQL
            (command -v mariadb >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1) && \
            systemctl is-active --quiet mariadb 2>/dev/null
            ;;
        redis)
            # Check for Redis
            command -v redis-cli >/dev/null 2>&1 && \
            systemctl is-active --quiet redis-server 2>/dev/null
            ;;
        nextcloud)
            # Check for Nextcloud installation
            local nc_root="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"
            [ -f "${nc_root}/occ" ] && [ -d "${nc_root}/apps" ]
            ;;
        certbot)
            # Check for certbot installation
            (command -v certbot >/dev/null 2>&1 || command -v certbot-auto >/dev/null 2>&1)
            ;;
        cron)
            # Check for cron service
            systemctl is-active --quiet cron 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
    
    return $?
}

# Check if a component is properly configured
is_component_configured() {
    local component=$1
    
    case $component in
        system)
            # Check for essential system services and configurations
            systemctl is-active --quiet cron && \
            systemctl is-active --quiet fail2ban && \
            systemctl is-active --quiet ufw && \
            [ "$(cat /proc/sys/vm/swappiness)" -le 10 ] 2>/dev/null
            ;;
        apache)
            # Check for valid Apache configuration and modules
            if systemctl is-active --quiet apache2 2>/dev/null; then
                local apache_status=0
                apache2ctl -t >/dev/null 2>&1 || apache_status=$?
                [ $apache_status -eq 0 ] && \
                apache2ctl -M 2>/dev/null | grep -q 'rewrite_module' && \
                apache2ctl -M 2>/dev/null | grep -q 'headers_module'
            else
                return 1
            fi
            ;;
        php)
            # Check for required PHP extensions and settings
            local required_extensions=(
                "mysqli" "pdo_mysql" "gd" "xml" "curl" 
                "mbstring" "intl" "zip" "imagick" "redis"
                "apcu" "bcmath" "exif" "ftp" "bz2" "opcache"
            )
            local missing_extensions=()
            
            # Check PHP extensions
            for ext in "${required_extensions[@]}"; do
                if ! php -m | grep -q -i "^${ext}$"; then
                    missing_extensions+=("$ext")
                fi
            done
            
            # Check PHP settings
            local php_ini=$(php --ini | grep 'Loaded Configuration File' | awk '{print $4}')
            local upload_max=$(php -r "echo ini_get('upload_max_filesize');")
            local post_max=$(php -r "echo ini_get('post_max_size');")
            local memory_limit=$(php -r "echo ini_get('memory_limit');")
            
            [[ ${#missing_extensions[@]} -eq 0 && 
               -n "$php_ini" && 
               -n "$upload_max" && 
               -n "$post_max" && 
               -n "$memory_limit" ]]
            ;;
        mariadb)
            # Check if MariaDB is properly configured
            if systemctl is-active --quiet mariadb; then
                # Check for InnoDB and other important settings
                local mysql_output
                mysql_output=$(mariadb -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null)
                
                # Check if database and user exist
                if [[ -f "$PROJECT_ROOT/.db_credentials" ]]; then
                    source "$PROJECT_ROOT/.db_credentials"
                    mariadb -u "$db_user" -p"$db_pass" -e "USE ${db_name};" >/dev/null 2>&1 && \
                    [[ -n "$mysql_output" ]]
                else
                    return 1
                fi
            else
                return 1
            fi
            ;;
        redis)
            # Check Redis configuration and connection
            if systemctl is-active --quiet redis-server; then
                local redis_ping
                redis_ping=$(redis-cli ping 2>/dev/null)
                [[ "$redis_ping" == "PONG" ]] && \
                [[ -f "/etc/redis/redis.conf" ]] && \
                grep -q '^maxmemory-policy allkeys-lru' /etc/redis/redis.conf
            else
                return 1
            fi
            ;;
        nextcloud)
            # Check Nextcloud configuration and status
            local nc_root="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"
            local nc_occ="${nc_root}/occ"
            local nc_status=0
            
            if [[ -f "$nc_occ" ]]; then
                # Check if Nextcloud is installed and maintenance mode is off
                sudo -u www-data php "$nc_occ" status --output=json 2>/dev/null | \
                    grep -q '"installed":true' || nc_status=1
                
                # Check if maintenance mode is off
                if [[ $nc_status -eq 0 ]]; then
                    sudo -u www-data php "$nc_occ" maintenance:mode --off 2>&1 | \
                        grep -q 'Maintenance mode disabled' || nc_status=1
                fi
                
                # Check for required PHP modules in Nextcloud
                if [[ $nc_status -eq 0 ]]; then
                    sudo -u www-data php "$nc_occ" check &>/dev/null || nc_status=1
                fi
                
                return $nc_status
            else
                return 1
            fi
            ;;
        certbot)
            # Check certbot configuration and certificates
            if (command -v certbot >/dev/null 2>&1 || command -v certbot-auto >/dev/null 2>&1); then
                # Check for valid certificates
                local cert_count=$(find /etc/letsencrypt/live -name 'fullchain.pem' 2>/dev/null | wc -l)
                [ "$cert_count" -gt 0 ] && \
                [ -f "/etc/letsencrypt/options-ssl-apache.conf" ] && \
                systemctl is-active --quiet certbot.timer 2>/dev/null
            else
                return 1
            fi
            ;;
        cron)
            # Check cron configuration for Nextcloud
            local has_cron_job=0
            local cron_active=0
            
            # Check for Nextcloud cron job
            if crontab -u www-data -l 2>/dev/null | grep -q "nextcloud.*cron.php"; then
                has_cron_job=1
            fi
            
            # Check if cron service is active
            if systemctl is-active --quiet cron 2>/dev/null; then
                cron_active=1
            fi
            
            [ $has_cron_job -eq 1 ] && [ $cron_active -eq 1 ]
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if a component is running
is_component_running() {
    local component=$1
    
    case $component in
        system)
            systemctl is-active --quiet cron && \
            systemctl is-active --quiet fail2ban && \
            systemctl is-active --quiet ufw
            ;;
        apache)
            systemctl is-active --quiet apache2 2>/dev/null
            ;;
        php)
            local php_version=$(php -v 2>/dev/null | grep -oP '^PHP \K[0-9]+\.[0-9]+')
            [ -n "$php_version" ] && \
            systemctl is-active --quiet "php${php_version}-fpm" 2>/dev/null
            ;;
        mariadb)
            systemctl is-active --quiet mariadb 2>/dev/null
            ;;
        redis)
            systemctl is-active --quiet redis-server 2>/dev/null && \
            redis-cli ping >/dev/null 2>&1
            ;;
        nextcloud)
            local nc_root="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"
            local nc_occ="${nc_root}/occ"
            [ -f "$nc_occ" ] && \
            sudo -u www-data php "$nc_occ" status --output=json 2>/dev/null | grep -q '"installed":true'
            ;;
        certbot)
            systemctl is-active --quiet certbot.timer 2>/dev/null
            ;;
        cron)
            systemctl is-active --quiet cron 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Update Nextcloud
update_nextcloud() {
    log_section "Updating Nextcloud"
    
    if ! is_component_installed "nextcloud"; then
        log_error "Nextcloud is not installed. Please install it first."
        return 1
    fi
    
    local nc_root="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"
    local nc_occ="${nc_occ:-$nc_root/occ}"
    
    log_info "Putting Nextcloud in maintenance mode..."
    sudo -u www-data php "$nc_occ" maintenance:mode --on
    
    log_info "Updating Nextcloud..."
    sudo -u www-data php "$nc_occ" upgrade
    
    log_info "Updating database..."
    sudo -u www-data php "$nc_occ" db:add-missing-indices
    sudo -u www-data php "$nc_occ" db:convert-filecache-bigint --no-interaction
    
    log_info "Updating system files..."
    sudo -u www-data php "$nc_occ" maintenance:repair
    
    log_info "Disabling maintenance mode..."
    sudo -u www-data php "$nc_occ" maintenance:mode --off
    
    log_success "Nextcloud update completed successfully"
}

# Main function
main() {
    # Ensure we're running as root
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root${NC}" >&2
        echo -e "Please run with: ${YELLOW}sudo $0${NC}" >&2
        exit 1
    fi
    
    # Parse command line arguments
    local command="${1:-install}"
    
    case "${command}" in
        install)
            echo -e "${GREEN}Starting Nextcloud installation...${NC}"
            if ! run_installation; then
                echo -e "${RED}Installation failed. Check ${LOG_FILE} for details.${NC}" >&2
                exit 1
            fi
            ;;
            
        status)
            echo -e "\n${GREEN}Nextcloud Installation Status${NC}"
            echo "=============================="
            
            for component in "${INSTALL_ORDER[@]}"; do
                local status_file="/tmp/nc_${component}_installed"
                if [ -f "${status_file}" ]; then
                    echo -e "${GREEN}✓${NC} ${component} is installed"
                else
                    echo -e "${YELLOW}✗${NC} ${component} is not installed"
                fi
            done
            
            echo -e "\nCheck ${LOG_FILE} for detailed logs."
            ;;
            
        help|--help|-h)
            echo -e "${GREEN}Nextcloud Setup Script${NC}"
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  install    Run the full installation (default)"
            echo "  status     Show installation status"
            echo "  help       Show this help message"
            ;;
            
        *)
            echo -e "${RED}Unknown command: ${command}${NC}" >&2
            echo "Use '$0 help' for usage information." >&2
            exit 1
            ;;
    esac
}

# Run the main function
main "$@"
}
