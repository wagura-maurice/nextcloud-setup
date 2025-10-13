#!/bin/bash

# Common functions for Nextcloud setup scripts
# This file provides utility functions for system configuration, file operations,
# and logging with proper error handling and security considerations.

# Source logging functions if not already sourced
if [ -z "${LOG_INITIALIZED:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/logging.sh" 2>/dev/null || {
        echo "Error: Failed to load logging module" >&2
        exit 1
    }
    # Initialize logging
    init_logging
    export LOG_INITIALIZED=1
fi

# Set strict mode for better error handling and security
set -o errexit    # Exit on error
set -o nounset    # Exit on undefined variables
set -o pipefail   # Ensure pipeline commands are checked for failures
set -o noclobber  # Prevent overwriting existing files with >
# Global configuration
# Only set SCRIPT_NAME if not already set
: "${SCRIPT_NAME:=$(basename "${0}")}"
: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
: "${PROJECT_ROOT:=$(dirname "$SCRIPT_DIR")}"

export SCRIPT_DIR PROJECT_ROOT

# File permissions
: "${DIR_PERMS:=750}"
: "${FILE_PERMS:=640}"
: "${SECURE_DIR_PERMS:=700}"
: "${SECURE_FILE_PERMS:=600}"

# Exit codes
: "${E_SUCCESS:=0}"      # Success
: "${E_ERROR:=1}"        # General error
: "${E_INVALID_ARG:=2}"  # Invalid argument
: "${E_MISSING_DEP:=3}"  # Missing dependency
: "${E_PERMISSION:=4}"   # Permission denied
: "${E_CONFIG:=5}"       # Configuration error

export E_SUCCESS E_ERROR E_INVALID_ARG E_MISSING_DEP E_PERMISSION E_CONFIG

# Load environment if not already loaded
if [ -z "${PROJECT_ROOT:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "${SCRIPT_DIR}/env-loader.sh" ]; then
        source "${SCRIPT_DIR}/env-loader.sh"
    else
        echo "Error: env-loader.sh not found in ${SCRIPT_DIR}" >&2
        exit 1
    fi
fi

# Check if running as root
# Exits with E_PERMISSION
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root" ${E_PERMISSION}
    fi
}

# Ensure required directories exist
ensure_directories() {
    local dirs=(
        "${LOG_DIR}"
        "${CONFIG_DIR}"
        "${DATA_DIR}"
        "${PROJECT_ROOT}/backups"
        "${PROJECT_ROOT}/tmp"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            chmod 750 "$dir"
        fi
    done
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install required packages
install_packages() {
    local packages=("$@")
    local pkg_manager=""
    
    # Detect package manager
    if command_exists apt-get; then
        pkg_manager="apt-get -y install"
    elif command_exists yum; then
        pkg_manager="yum -y install"
    elif command_exists dnf; then
        pkg_manager="dnf -y install"
    else
        log_error "Could not find a supported package manager" ${E_MISSING_DEP}
    fi
    
    log_info "Installing required packages: ${packages[*]}"
    if ! $pkg_manager "${packages[@]}"; then
        log_error "Failed to install required packages" ${E_ERROR}
    fi
}

# Check if a command exists in the system PATH
# Usage: command_exists <command>
# Returns: 0 if command exists, 1 otherwise
command_exists() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        log_warning "Command not found: ${cmd}"
        return ${E_MISSING_DEP}
    fi
    return ${E_SUCCESS}
}

# Ensure required commands are available
# Usage: require_commands <command1> [command2] ...
require_commands() {
    local missing=0
    for cmd in "$@"; do
        if ! command_exists "${cmd}"; then
            log_error "Required command not found: ${cmd}" ${E_MISSING_DEP}
            missing=$((missing + 1))
        fi
    done
    [ ${missing} -eq 0 ] || exit ${E_MISSING_DEP}
}

# Print section header
print_header() {
    log_section "$1"
}

# Backup a file with timestamp
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
        log_info "Creating backup of $file to $backup"
        if ! cp "$file" "$backup"; then
            log_error "Failed to create backup of $file" ${E_ERROR}
        fi
        chmod ${SECURE_FILE_PERMS} "$backup" || log_warning "Failed to set permissions on backup file"
        log_success "Backup created: $backup"
    else
        log_warning "File not found for backup: $file"
    fi
}


# Check if a process is running
# Usage: is_process_running <process_name>
is_process_running() {
    local process_name="$1"
    if pgrep -x "${process_name}" >/dev/null; then
        return ${E_SUCCESS}
    fi
    return ${E_ERROR}
}

# Check if a port is in use
# Usage: is_port_in_use <port_number>
is_port_in_use() {
    local port="$1"
    if command -v ss >/dev/null; then
        ss -tuln | grep -q ":${port} "
    else
        netstat -tuln 2>/dev/null | grep -q ":${port} "
    fi
    return $?
}

# Get the current Linux distribution
# Sets DISTRO and DISTRO_VERSION variables
get_linux_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO="${ID:-unknown}"
        DISTRO_VERSION="${VERSION_ID:-unknown}"
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
        DISTRO_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
        DISTRO_VERSION=$(cat /etc/debian_version)
    else
        DISTRO="unknown"
        DISTRO_VERSION="unknown"
    fi
    
    DISTRO=$(echo "${DISTRO}" | tr '[:upper:]' '[:lower:]')
    export DISTRO DISTRO_VERSION
}

# Restart a service using systemd
# Usage: restart_service <service_name>
restart_service() {
    local service="$1"
    
    if ! systemctl list-unit-files "${service}.service" &>/dev/null; then
        log_warning "Service not found: ${service}.service"
        return ${E_ERROR}
    fi
    
    log_info "Restarting ${service} service..."
    
    if ! systemctl is-active "${service}" &>/dev/null; then
        log_info "Service ${service} is not running, starting it..."
        if ! systemctl start "${service}"; then
            log_error "Failed to start ${service} service" ${E_ERROR}
        fi
    else
        if ! systemctl restart "${service}"; then
            log_error "Failed to restart ${service} service" ${E_ERROR}
        fi
    fi
    
    # Verify service is running
    if ! systemctl is-active --quiet "${service}"; then
        log_error "Service ${service} failed to start" ${E_ERROR}
    fi
    
    log_success "Service ${service} restarted successfully"
    return ${E_SUCCESS}
}

# Reload a service configuration
# Usage: reload_service <service_name>
reload_service() {
    local service="$1"
    
    if ! systemctl list-unit-files "${service}.service" &>/dev/null; then
        log_warning "Service not found: ${service}.service"
        return ${E_ERROR}
    fi
    
    log_info "Reloading ${service} service configuration..."
    
    if ! systemctl reload "${service}"; then
        log_error "Failed to reload ${service} service" ${E_ERROR}
    fi
    
    log_success "Service ${service} configuration reloaded successfully"
    return ${E_SUCCESS}
}

# Enable and start a service
# Usage: enable_service <service_name>
enable_service() {
    local service="$1"
    
    if ! systemctl list-unit-files "${service}.service" &>/dev/null; then
        print_warning "Service not found: ${service}.service"
        return ${E_ERROR}
    fi
    
    # Enable the service to start on boot
    if ! systemctl is-enabled "${service}" &>/dev/null; then
        print_status "Enabling ${service} service to start on boot..."
        if ! systemctl enable "${service}"; then
            print_error "Failed to enable ${service} service" ${E_ERROR}
        fi
    fi
    
    # Start the service if not already running
    if ! systemctl is-active "${service}" &>/dev/null; then
        print_status "Starting ${service} service..."
        if ! systemctl start "${service}"; then
            print_error "Failed to start ${service} service" ${E_ERROR}
        fi
    fi
    
    print_success "Service ${service} is enabled and running"
    return ${E_SUCCESS}
}

# Disable and stop a service
# Usage: disable_service <service_name>
disable_service() {
    local service="$1"
    
    if ! systemctl list-unit-files "${service}.service" &>/dev/null; then
        print_warning "Service not found: ${service}.service"
        return ${E_ERROR}
    fi
    
    # Stop the service if running
    if systemctl is-active "${service}" &>/dev/null; then
        print_status "Stopping ${service} service..."
        if ! systemctl stop "${service}"; then
            print_warning "Failed to stop ${service} service"
        fi
    fi
    
    # Disable the service
    if systemctl is-enabled "${service}" &>/dev/null; then
        print_status "Disabling ${service} service..."
        if ! systemctl disable "${service}"; then
            print_warning "Failed to disable ${service} service"
        fi
    fi
    
    print_success "Service ${service} is disabled and stopped"
    return ${E_SUCCESS}
}


# Check if a file contains a specific string
file_contains() {
    local file="$1"
    local string="$2"
    grep -q "$string" "$file" 2>/dev/null
}

# Add a line to a file if it doesn't exist
add_line_to_file() {
    local file="$1"
    local line="$2"
    local file_dir=$(dirname "${file}")
    
    # Create directory if it doesn't exist
    if [ ! -d "${file_dir}" ]; then
        mkdir -p "${file_dir}" || print_error "Failed to create directory: ${file_dir}"
        chmod 755 "${file_dir}" || print_warning "Failed to set permissions for: ${file_dir}"
    fi
    
    # Create file if it doesn't exist
    if [ ! -f "${file}" ]; then
        echo "${line}" > "${file}" || print_error "Failed to create file: ${file}"
        chmod 644 "${file}" || print_warning "Failed to set permissions for: ${file}"
        print_success "Created file: ${file}"
    # Add line if it doesn't exist
    elif ! file_contains "${file}" "${line}"; then
        echo "${line}" >> "${file}" || print_error "Failed to append to file: ${file}"
        print_success "Updated file: ${file}"
    else
        print_status "Line already exists in ${file}"
    fi
}

# Replace a string in a file
replace_in_file() {
    local file="$1"
    local search="$2"
    local replace="$3"
    
    if [ -f "$file" ]; then
        sed -i "s|${search}|${replace}|g" "$file"
    fi
}

# Get a configuration value from a file
get_config_value() {
    local file="$1"
    local key="$2"
    
    if [ -f "$file" ]; then
        grep -oP "^\s*${key}\s*=\s*\K.*" "$file" | tr -d '"''\'''
    fi
}
