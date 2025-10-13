#!/bin/bash

# Configuration Manager for Nextcloud Installation
# This script provides functions to load and apply configuration templates
# with proper error handling and logging

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common-functions.sh"

# Global configuration
readonly CONFIG_VALIDATION_PATTERNS=(
    "^[a-zA-Z0-9_]+=.*$"  # Basic key=value format
    "^#"                   # Comments
    "^[[:space:]]*$"       # Empty lines
)

# Default configuration values
readonly DEFAULT_CONFIG=(
    "INSTALL_DIR=/var/www/nextcloud"
    "DATA_DIR=/var/nextcloud/data"
    "BACKUP_DIR=/var/backups/nextcloud"
    "DB_TYPE=mysql"
    "DB_NAME=nextcloud"
    "DB_USER=nextcloud"
    "DB_PASS=$(openssl rand -hex 16)"
    "DB_HOST=localhost"
    "REDIS_HOST=localhost"
    "REDIS_PORT=6379"
    "WEB_SERVER=apache"
    "DOMAIN_NAME=localhost"
    "ADMIN_USER=admin"
    "ADMIN_PASS=$(openssl rand -base64 12)"
    "PHP_VERSION=8.4"
    "PHP_MEMORY_LIMIT=1G"
    "PHP_UPLOAD_MAX=10G"
    "PHP_POST_MAX_SIZE=10G"
)

# Validate configuration key-value pair
# Usage: _validate_config_line "key=value"
_validate_config_line() {
    local line="$1"
    
    # Skip empty lines and comments
    [[ -z "${line}" || "${line:0:1}" == "#" ]] && return 0
    
    # Check against validation patterns
    local pattern
    for pattern in "${CONFIG_VALIDATION_PATTERNS[@]}"; do
        if [[ "$line" =~ $pattern ]]; then
            return 0
        fi
    done
    
    # If we get here, the line didn't match any pattern
    print_warning "Invalid configuration line: ${line}"
    return 1
}

# Load configuration from a file with validation
# Usage: load_config "path/to/config/file" [default_value]
load_config() {
    local config_file="$1"
    local default_value="${2:-}"
    
    # Create directory if it doesn't exist
    local config_dir=$(dirname "${config_file}")
    if [ ! -d "${config_dir}" ]; then
        mkdir -p "${config_dir}" || {
            print_error "Failed to create config directory: ${config_dir}"
            return 1
        }
        chmod 750 "${config_dir}" || print_warning "Failed to set permissions for: ${config_dir}"
    fi
    
    # If config file exists, validate and load it
    if [ -f "${config_file}" ]; then
        print_status "Loading configuration from: ${config_file}"
        
        # Validate each line before sourcing
        local line
        while IFS= read -r line; do
            _validate_config_line "${line}" || {
                print_warning "Skipping invalid configuration in ${config_file}"
                continue
            }
        done < "${config_file}"
        
        # Source the config file
        . "${config_file}" || {
            print_error "Failed to load configuration from: ${config_file}"
            return 1
        }
    # If default value is provided, use it
    elif [ -n "${default_value}" ]; then
        print_status "Using default configuration for: ${config_file}"
        eval "${default_value}" || {
            print_error "Failed to set default configuration"
            return 1
        }
    else
        print_error "Configuration file not found and no default provided: ${config_file}"
        return 1
    fi
    
    # Export all variables for child processes
    set -a
    . "${config_file}" 2>/dev/null || true
    set +a
    
    print_success "Configuration loaded successfully from ${config_file}"
}

# Apply configuration template to a target file with validation
# Usage: apply_config_template "template_file" "target_file" [variables...]
apply_config_template() {
    [ $# -lt 2 ] && { print_error "Usage: ${FUNCNAME[0]} template_file target_file [var=value...]"; return 1; }
    
    local template_file="$1"
    local target_file="$2"
    shift 2
    
    # Validate template file
    if [ ! -f "${template_file}" ]; then
        print_error "Template file not found: ${template_file}"
        return 1
    fi
    
    # Create target directory if it doesn't exist
    local target_dir=$(dirname "${target_file}")
    if [ ! -d "${target_dir}" ]; then
        mkdir -p "${target_dir}" || {
            print_error "Failed to create target directory: ${target_dir}"
            return 1
        }
        chmod 755 "${target_dir}" || print_warning "Failed to set permissions for: ${target_dir}"
    fi
    
    # Create a secure temporary file
    local temp_file
    temp_file=$(mktemp) || {
        print_error "Failed to create temporary file"
        return 1
    }
    
    # Set secure permissions on temp file
    chmod 600 "${temp_file}" || print_warning "Failed to secure temporary file"
    
    # Copy template to temp file
    if ! cp "${template_file}" "${temp_file}"; then
        rm -f "${temp_file}"
        print_error "Failed to copy template to temporary file"
        return 1
    fi
    
    # Process variables
    local var_name var_value safe_value
    for var in "$@"; do
        # Split on first '=' only
        var_name="${var%%=*}"
        var_value="${var#*=}"
        
        # Basic validation of variable name
        if [[ ! "${var_name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            print_warning "Skipping invalid variable name: ${var_name}"
            continue
        fi
        
        # Escape special characters for sed
        safe_value=$(printf '%s\n' "${var_value}" | sed 's/[&/\]/\\&/g')
        
        # Replace all occurrences of __VAR_NAME__ with the value
        if ! sed -i "s|__${var_name}__|${safe_value}|g" "${temp_file}"; then
            rm -f "${temp_file}"
            print_error "Failed to process variable: ${var_name}"
            return 1
        fi
    done
    
    # Backup existing file if it exists
    if [ -f "${target_file}" ]; then
        backup_file "${target_file}" || {
            rm -f "${temp_file}"
            return 1
        }
    fi
    
    # Move the processed file to target location
    if ! mv "${temp_file}" "${target_file}"; then
        rm -f "${temp_file}"
        print_error "Failed to move temporary file to: ${target_file}"
        return 1
    fi
    
    # Set secure permissions on target file
    chmod 640 "${target_file}" || print_warning "Failed to set permissions for: ${target_file}"
    
    print_success "Applied configuration: ${target_file}"
    return 0
}

# Load and validate installation configuration
load_installation_config() {
    local config_dir="${1:-$CONFIG_DIR}"
    
    # Default configuration values
    local default_config="
        # System Configuration
        INSTALL_DIR="/var/www/nextcloud"
        DATA_DIR="${INSTALL_DIR}/data"
        BACKUP_DIR="/var/backups/nextcloud"
        
        # Database Configuration
        DB_TYPE="mysql"
        DB_NAME="nextcloud"
        DB_USER="nextcloud"
        DB_PASS=$(openssl rand -hex 16)
        DB_HOST="localhost"
        
        # Redis Configuration
        REDIS_HOST="localhost"
        REDIS_PORT=6379
        
        # Web Server Configuration
        WEB_SERVER="apache"
        DOMAIN_NAME="localhost"
        ADMIN_USER="admin"
        ADMIN_PASS=$(openssl rand -base64 12)
        
        # PHP Configuration
        PHP_VERSION="8.4"
        PHP_MEMORY_LIMIT="1G"
        PHP_UPLOAD_MAX="10G"
        PHP_POST_MAX_SIZE="10G"
        
        # SSL Configuration
        SSL_ENABLED=true
        SSL_EMAIL="admin@example.com"
        SSL_COUNTRY="US"
        SSL_STATE="California"
        SSL_LOCALITY="San Francisco"
        SSL_ORG="Example Org"
        SSL_OU="IT Department"
    "
    
    # Create config directory if it doesn't exist
    mkdir -p "$config_dir"
    
    # Create default config if it doesn't exist
    local main_config="$config_dir/install-config.conf"
    if [ ! -f "$main_config" ]; then
        echo "$default_config" > "$main_config"
        echo "Created default configuration file: $main_config"
    fi
    
    # Load the configuration
    source "$main_config"
    
    # Export all variables for use in other scripts
    export INSTALL_DIR DATA_DIR BACKUP_DIR \
           DB_TYPE DB_NAME DB_USER DB_PASS DB_HOST \
           REDIS_HOST REDIS_PORT \
           WEB_SERVER DOMAIN_NAME ADMIN_USER ADMIN_PASS \
           PHP_VERSION PHP_MEMORY_LIMIT PHP_UPLOAD_MAX PHP_POST_MAX_SIZE \
           SSL_ENABLED SSL_EMAIL SSL_COUNTRY SSL_STATE SSL_LOCALITY SSL_ORG SSL_OU
}

# Generate configuration files from templates
generate_configs() {
    local template_dir="${1:-$CONFIG_DIR/templates}"
    local output_dir="${2:-/etc}"
    
    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"
    
    # Process each template in the directory
    if [ -d "$template_dir" ]; then
        find "$template_dir" -type f | while read -r template; do
            # Get relative path from template directory
            local rel_path="${template#$template_dir/}"
            local target_file="$output_dir/$rel_path"
            
            # Create target directory if it doesn't exist
            mkdir -p "$(dirname "$target_file")"
            
            # Apply template with current environment variables
            envsubst < "$template" > "$target_file"
            
            echo "Generated: $target_file"
        done
    fi
}

# Backup existing configuration files
backup_configs() {
    local backup_dir="${1:-$BACKUP_DIR/config-backups/$(date +%Y%m%d_%H%M%S)}"
    local config_files=(
        "/etc/apache2/sites-available/nextcloud.conf"
        "/etc/php/$PHP_VERSION/fpm/pool.d/nextcloud.conf"
        "/etc/php/$PHP_VERSION/fpm/php.ini"
        "/etc/php/$PHP_VERSION/mods-available/nextcloud.ini"
        "/etc/php/$PHP_VERSION/cli/php.ini"
        "/etc/redis/redis.conf"
    )
    
    mkdir -p "$backup_dir"
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            cp -v "$file" "$backup_dir/"
        fi
    done
    
    echo "Configuration backed up to: $backup_dir"
}

# Restore configuration from backup
restore_configs() {
    local backup_dir="${1:-$(ls -d $BACKUP_DIR/config-backups/*/ | sort -r | head -n 1)}"
    
    if [ ! -d "$backup_dir" ]; then
        echo "Error: Backup directory not found: $backup_dir" >&2
        return 1
    fi
    
    echo "Restoring configurations from: $backup_dir"
    
    # Restore each file that exists in the backup
    find "$backup_dir" -type f | while read -r backup_file; do
        local target_file="/${backup_file#$backup_dir/}"
        if [ -f "$backup_file" ]; then
            mkdir -p "$(dirname "$target_file")"
            cp -v "$backup_file" "$target_file"
        fi
    done
    
    echo "Configuration restored from: $backup_dir"
}
