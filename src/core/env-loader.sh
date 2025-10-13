#!/bin/bash

# Environment Loader for Nextcloud Setup and Management
# This script provides a unified way to load environment variables and configurations
# for both setup and management scripts.

# Get the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env"

# Source core functions
source "${SCRIPT_DIR}/common-functions.sh"
source "${SCRIPT_DIR}/logging.sh"

# Default environment variables
declare -A DEFAULTS=(
    [PROJECT_ROOT]="$PROJECT_ROOT"
    [LOG_DIR]="${PROJECT_ROOT}/logs"
    [CONFIG_DIR]="${PROJECT_ROOT}/config"
    [BACKUP_DIR]="/var/backups/nextcloud"
    [NEXTCLOUD_DATA_DIR]="/var/www/nextcloud/data"
    [DB_TYPE]="mariadb"
    [DB_HOST]="localhost"
    [DB_PORT]="3306"
    [DB_NAME]="nextcloud"
    [DB_USER]="nextcloud"
    [PHP_MEMORY_LIMIT]="512M"
    [PHP_UPLOAD_LIMIT]="10G"
    [PHP_MAX_EXECUTION_TIME]="3600"
)

# Load environment from .env file
load_environment() {
    local env_file="${1:-$ENV_FILE}"
    
    # Create default .env if it doesn't exist
    if [[ ! -f "$env_file" ]]; then
        log_warning "No .env file found at $env_file, creating with default values"
        cp "${PROJECT_ROOT}/.env.example" "$env_file"
        chmod 600 "$env_file"
    fi

    # Load environment variables
    if [[ -f "$env_file" ]]; then
        # Export all variables from .env
        set -o allexport
        # shellcheck source=/dev/null
        source "$env_file"
        set +o allexport
        log_info "Loaded environment from $env_file"
    else
        log_error "Failed to create .env file at $env_file"
        exit 1
    fi

    # Set default values for any unset variables
    for key in "${!DEFAULTS[@]}"; do
        if [[ -z "${!key:-}" ]]; then
            declare -gx "$key"="${DEFAULTS[$key]}"
        fi
    done

    # Ensure required directories exist
    mkdir -p "$LOG_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Set permissions
    chmod 750 "$LOG_DIR"
    chmod 750 "$BACKUP_DIR"
}

# Export the load_environment function
export -f load_environment

# If this script is sourced directly, load the environment
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    load_environment "$1"
fi
