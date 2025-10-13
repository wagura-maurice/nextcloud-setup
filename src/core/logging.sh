#!/bin/bash

# Logging Functions for Nextcloud Setup and Management
# This script provides consistent logging functionality across all scripts

# Set default log level if not set
: "${LOG_LEVEL:="INFO"}"
: "${PROJECT_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
: "${LOG_DIR:=${PROJECT_ROOT}/logs}"
: "${LOG_FILE:=${LOG_DIR}/nextcloud-setup-$(date +%Y%m%d%H%M%S).log}"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"
chmod 750 "${LOG_DIR}"

# Define log levels
# Using parameter expansion to set default values if not already set
: "${LOG_LEVEL_DEBUG:=0}"
: "${LOG_LEVEL_INFO:=1}"
: "${LOG_LEVEL_WARNING:=2}"
: "${LOG_LEVEL_ERROR:=3}"

# Map string log levels to numeric values
map_log_level() {
    local level="$1"
    case "${level^^}" in
        "DEBUG") echo 0 ;;
        "INFO") echo 1 ;;
        "WARNING") echo 2 ;;
        "ERROR") echo 3 ;;
        [0-9]*) echo "$level" ;;
        *) echo 1 ;; # Default to INFO
    esac
}

# Set log level from environment or default to INFO
: "${LOG_LEVEL_NUM:=$(map_log_level "${LOG_LEVEL}")}"
export LOG_LEVEL_DEBUG LOG_LEVEL_INFO LOG_LEVEL_WARNING LOG_LEVEL_ERROR LOG_LEVEL_NUM

# Ensure log directory exists
log_dir="$(dirname "$LOG_FILE")"
mkdir -p "$log_dir"
chmod 750 "$log_dir"

# Log a message with timestamp and log level
log() {
    # Initialize timestamp with a safe default
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'timestamp-error')"
    
    # Handle case when called with a single argument (message only)
    if [ $# -eq 1 ]; then
        local message="$1"
        echo "[${timestamp}] [INFO] ${message}" | tee -a "${LOG_FILE}" >&2
        return 0
    fi
    
    # Ensure we have at least a log level and message
    if [ $# -lt 2 ]; then
        echo "[${timestamp}] [ERROR] log() called with insufficient arguments" >&2
        echo "[${timestamp}] [DEBUG] Called from: ${BASH_SOURCE[1]:-unknown}:${BASH_LINENO[0]:-0} with args: $*" >&2
        echo "[${timestamp}] [DEBUG] Call stack:" >&2
        local i=0
        while caller $i; do
            ((i++))
        done >&2
        return 1
    fi
    
    local level="$1"
    local message="${2:-}"
    local exit_code="${3:-}"
    
    # Map level to numeric value
    local level_num
    case "${level^^}" in
        "DEBUG") level_num=${LOG_LEVEL_DEBUG:-0} ;;
        "INFO") level_num=${LOG_LEVEL_INFO:-1} ;;
        "WARNING") level_num=${LOG_LEVEL_WARNING:-2} ;;
        "ERROR") level_num=${LOG_LEVEL_ERROR:-3} ;;
        *) level_num=${LOG_LEVEL_INFO:-1} ;; # Default to INFO
    esac
    
    # Only log if level is at or above the current log level
    if [ ${level_num} -ge ${LOG_LEVEL_NUM:-${LOG_LEVEL_INFO:-1}} ]; then
        # Ensure we have a valid timestamp
        local log_timestamp="${timestamp}"
        if [ -z "${log_timestamp}" ] || [ "${log_timestamp}" = "timestamp-error" ]; then
            log_timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'unknown-time')"
        fi
        
        # Ensure message is not empty
        if [ -z "${message}" ]; then
            message="(empty message)"
        fi
        
        local log_entry="[${log_timestamp}] [${level^^}] ${message}"
        
        # Print to console with color
        case ${level_num} in
            ${LOG_LEVEL_DEBUG:-0}) echo -e "\033[0;36m${log_entry}\033[0m" ;;
            ${LOG_LEVEL_INFO:-1}) echo -e "\033[0;32m${log_entry}\033[0m" ;;
            ${LOG_LEVEL_WARNING:-2}) echo -e "\033[0;33m${log_entry}\033[0m" >&2 ;;
            ${LOG_LEVEL_ERROR:-3}) echo -e "\033[0;31m${log_entry}\033[0m" >&2 ;;
            *) echo "${log_entry}" ;;
        esac
        
        # Ensure LOG_FILE is set and writable
        if [ -z "${LOG_FILE:-}" ]; then
            local fallback_timestamp
            fallback_timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'timestamp-error')"
            LOG_FILE="/tmp/nextcloud-setup-$(date +%s).log"
            echo "[${fallback_timestamp}] [WARNING] LOG_FILE not set, using fallback: ${LOG_FILE}" >&2
        fi
        
        # Create log directory if it doesn't exist
        local log_dir
        local timestamp
        timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'timestamp-error')"
        log_dir="$(dirname "${LOG_FILE}" 2>/dev/null || echo '/tmp')"
        mkdir -p "${log_dir}" 2>/dev/null || {
            echo "[${timestamp}] [ERROR] Failed to create log directory: ${log_dir}" >&2
            return 1
        }
        
        # Write to log file
        if ! echo "${log_entry}" >> "${LOG_FILE}" 2>/dev/null; then
            # Use a new timestamp for the error message to ensure it's always set
            local err_timestamp
            err_timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'timestamp-error')"
            echo "[${err_timestamp}] [ERROR] Failed to write to log file: ${LOG_FILE}" >&2
            return 1
        fi
    fi
    
    # Exit if this was an error with an exit code
    if [ "${level^^}" = "ERROR" ] && [ -n "${exit_code}" ]; then
        exit ${exit_code}
    fi
    
    return 0
}

# Log level functions with proper variable initialization
log_debug() { 
    local level_num="${LOG_LEVEL_NUM:-${LOG_LEVEL_INFO:-1}}"
    [ "${level_num}" -le "${LOG_LEVEL_DEBUG:-0}" ] && log "DEBUG" "$@" 
}

log_info() { 
    local level_num="${LOG_LEVEL_NUM:-${LOG_LEVEL_INFO:-1}}"
    [ "${level_num}" -le "${LOG_LEVEL_INFO:-1}" ] && log "INFO" "$@" 
}

log_warning() { 
    local level_num="${LOG_LEVEL_NUM:-${LOG_LEVEL_INFO:-1}}"
    [ "${level_num}" -le "${LOG_LEVEL_WARNING:-2}" ] && log "WARNING" "$@" 
}

log_error() { 
    log "ERROR" "$@" 1 
}

# Run a command and log the output
run_command() {
    local cmd="$*"
    log_info "Executing: ${cmd}"
    
    local output
    if output=$(eval "${cmd}" 2>&1); then
        log_info "Command succeeded"
        echo "${output}"
        return 0
    else
        local status=$?
        log_error "Command failed with status ${status}: ${output}"
        return $status
    fi
}

# Initialize logging
init_logging() {
    # Ensure LOG_FILE is set
    : "${LOG_FILE:=${LOG_DIR:-/tmp}/nextcloud-setup-$(date +%Y%m%d%H%M%S).log}"
    export LOG_FILE
    
    # Create log directory if it doesn't exist
    local log_dir="$(dirname "$LOG_FILE" 2>/dev/null || echo '/tmp')"
    mkdir -p "$log_dir" 2>/dev/null || {
        echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'timestamp-error')] [ERROR] Failed to create log directory: $log_dir" >&2
        return 1
    }
    
    # Create log file with appropriate permissions
    if ! touch "$LOG_FILE" 2>/dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'timestamp-error')] [WARNING] Failed to create log file: $LOG_FILE" >&2
        LOG_FILE="/tmp/nextcloud-setup-$(date +%s).log"
        export LOG_FILE
        if ! touch "$LOG_FILE" 2>/dev/null; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'timestamp-error')] [ERROR] Failed to create fallback log file: $LOG_FILE" >&2
            return 1
        fi
    fi
    
    chmod 640 "$LOG_FILE" 2>/dev/null || true
    
    # Get a timestamp for the log entries
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'timestamp-error')"
    
    # Log script start
    {
        echo "[${timestamp}] [INFO] === Logging initialized ==="
        echo "[${timestamp}] [INFO] Project Root: ${PROJECT_ROOT:-Not set}"
        echo "[${timestamp}] [INFO] Log file: ${LOG_FILE}"
        echo "[${timestamp}] [INFO] Log level: ${LOG_LEVEL:-INFO} (${LOG_LEVEL_NUM:-1})"
    } >> "$LOG_FILE" 2>/dev/null || {
        echo "[${timestamp}] [ERROR] Failed to write to log file: $LOG_FILE" >&2
        return 1
    }
    
    return 0
}

# Initialize log level from environment or default to INFO
: "${LOG_LEVEL:=INFO}"
case "${LOG_LEVEL^^}" in
    "DEBUG") LOG_LEVEL_NUM=0 ;;
    "INFO")  LOG_LEVEL_NUM=1 ;;
    "WARNING") LOG_LEVEL_NUM=2 ;;
    "ERROR") LOG_LEVEL_NUM=3 ;;
    *) LOG_LEVEL_NUM=1 ;; # Default to INFO
esac
export LOG_LEVEL LOG_LEVEL_NUM

# Export all logging functions
export -f log log_debug log_info log_warning log_error run_command init_logging

# Log a message with timestamp and log level
# Usage: log <level> <message> [exit_code]
log() {
    local level="$1"
    local message="${2:-}"
    local exit_code="${3:-}"
    
    # Ensure we have a valid timestamp
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'timestamp-error')"
    
    # Ensure message is not empty
    if [ -z "$message" ]; then
        message="(empty message)"
    fi
    
    # Map level to numeric value
    local level_num
    level_num=$(map_log_level "$level" 2>/dev/null || echo 1)  # Default to INFO level if mapping fails
    
    # Create log entry with timestamp
    local log_entry="[${timestamp}] [${level^^}] ${message}"
    
    # Only process if level is at or above the current log level
    if [[ $level_num -ge $LOG_LEVEL_NUM ]]; then
        # Print to console with appropriate color
        case $level_num in
            $LOG_LEVEL_DEBUG) echo -e "\033[0;36m$log_entry\033[0m" ;;
            $LOG_LEVEL_INFO) echo -e "\033[0;32m$log_entry\033[0m" ;;
            $LOG_LEVEL_WARNING) echo -e "\033[0;33m$log_entry\033[0m" >&2 ;;
            $LOG_LEVEL_ERROR) echo -e "\033[0;31m$log_entry\033[0m" >&2 ;;
            *) echo "$log_entry" ;;
        esac
        
        # Append to log file
        echo "$log_entry" >> "$LOG_FILE"
    fi
    
    # Always log errors to stderr and exit if exit code provided
    if [[ $level_num -ge $LOG_LEVEL_ERROR ]]; then
        if [[ -n "$exit_code" ]]; then
            exit "$exit_code"
        fi
    fi
}
log_info() { log "$LOG_LEVEL_INFO" "$@"; }
log_warning() { log "$LOG_LEVEL_WARNING" "$@"; }
log_error() { 
    log "$LOG_LEVEL_ERROR" "$@" 
    exit 1
}
# Log command execution
run_command() {
    local cmd="$*"
    log_info "Executing: $cmd"
    if ! output=$($cmd 2>&1); then
        log_error "Command failed: $cmd\n$output"
    fi
    log_debug "Command output: $output"
    echo "$output"
}

# Log section header
log_section() {
    local message="=== $* ==="
    log_info "$message"
}

# Success message
log_success() {
    local message="✓ $*"
    log_info "$message"
}

# Export the log function and its variants
export -f log log_debug log_info log_warning log_error run_command
