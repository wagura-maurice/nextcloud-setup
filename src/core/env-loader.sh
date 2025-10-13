#!/bin/bash

# Environment Loader for Nextcloud Setup and Management
# This script provides a unified way to load environment variables and configurations
# for both setup and management scripts.

# Ensure we're not being sourced multiple times
[ -n "${ENV_LOADED:-}" ] && return

# Set script directory if not already set
if [ -z "${SCRIPT_DIR:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Set project root relative to script directory
if [ -z "${PROJECT_ROOT:-}" ]; then
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"
fi
: "${SRC_DIR:=${PROJECT_ROOT}/src}"
: "${CORE_DIR:=${SRC_DIR}/core}"
: "${UTILS_DIR:=${SRC_DIR}/utilities}"
: "${LOG_DIR:=${PROJECT_ROOT}/logs}"
: "${CONFIG_DIR:=${PROJECT_ROOT}/config}"
: "${DATA_DIR:=${PROJECT_ROOT}/data}"

# Export all paths
export PROJECT_ROOT SRC_DIR CORE_DIR UTILS_DIR LOG_DIR CONFIG_DIR DATA_DIR

# Ensure required directories exist
mkdir -p "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}"
chmod 750 "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}"

# Set default environment file
ENV_FILE="${PROJECT_ROOT}/.env"

# Set default environment variables
: "${LOG_LEVEL:="INFO"}"
: "${PROJECT_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
: "${LOG_DIR:=${PROJECT_ROOT}/logs}"
: "${LOG_FILE:=${LOG_DIR}/nextcloud-setup-$(date +%Y%m%d%H%M%S).log}"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"
chmod 750 "${LOG_DIR}"

# Source logging functions
if [ -f "${CORE_DIR}/logging.sh" ]; then
    source "${CORE_DIR}/logging.sh"
else
    # Fallback logging if logging.sh fails to load
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] ${*:2}" | tee -a "${LOG_FILE}"
    }
    log_info() { log "INFO" "$@"; }
    log_warning() { log "WARNING" "$@"; }
    log_error() { log "ERROR" "$@"; exit 1; }
    log_debug() { [ "${LOG_LEVEL}" = "DEBUG" ] && log "DEBUG" "$@"; }
    
    log_warning "Using fallback logging - logging.sh not found in ${CORE_DIR}"
fi

# Initialize logging
init_logging 2>/dev/null || {
    log_warning "Failed to initialize logging, using fallback"
}

# Load common functions
if [ -f "${CORE_DIR}/common-functions.sh" ]; then
    source "${CORE_DIR}/common-functions.sh"
else
    log_error "common-functions.sh not found in ${CORE_DIR}" 1
fi

# Main environment file
ENV_FILE="${PROJECT_ROOT}/.env"

# Ensure required directories exist
mkdir -p "$LOG_DIR"
chmod 750 "$LOG_DIR"

# Set default values
declare -A DEFAULTS=(
    [PROJECT_ROOT]="$PROJECT_ROOT"
    [SRC_DIR]="$SRC_DIR"
    [CORE_DIR]="$CORE_DIR"
    [LOG_DIR]="$LOG_DIR"
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
    
    log_info "Loading environment from $env_file"
    
    # Create default .env if it doesn't exist
    if [ ! -f "$env_file" ]; then
        log_warning "No .env file found at $env_file, creating with default values"
        cp -n "${PROJECT_ROOT}/.env.example" "$env_file" || {
            log_error "Failed to create default .env file"
            return 1
        }
        chmod 600 "$env_file"
    fi
    
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
