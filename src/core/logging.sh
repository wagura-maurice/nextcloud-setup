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
    # Handle case when called with a single argument (message only)
    if [ $# -eq 1 ]; then
        local message="$1"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ${message}" | tee -a "${LOG_FILE}" >&2
        return 0
    fi
    
    # Ensure we have at least a log level and message
    if [ $# -lt 2 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] log() called with insufficient arguments" >&2
        echo "[DEBUG] Called from: ${BASH_SOURCE[1]}:${BASH_LINENO[0]} with args: $*" >&2
        echo "[DEBUG] Call stack:" >&2
        local i=0
        while caller $i; do
            ((i++))
        done >&2
        return 1
    fi
    
    local level="$1"
    local message="$2"
    local exit_code="${3:-}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')" || timestamp="[timestamp-error]"
    
    # Map level to numeric value
    local level_num
    case "${level^^}" in
        "DEBUG") level_num=0 ;;
        "INFO") level_num=1 ;;
        "WARNING") level_num=2 ;;
        "ERROR") level_num=3 ;;
        *) level_num=1 ;; # Default to INFO
    esac
    
    # Only log if level is at or above the current log level
    if [ "$level_num" -ge "${LOG_LEVEL_NUM:-1}" ]; then
        local log_entry="[${timestamp}] [${level^^}] ${message}"
        
        # Print to console with color
        case $level_num in
            0) echo -e "\033[0;36m${log_entry}\033[0m" ;;
            1) echo -e "\033[0;32m${log_entry}\033[0m" ;;
            2) echo -e "\033[0;33m${log_entry}\033[0m" >&2 ;;
            3) echo -e "\033[0;31m${log_entry}\033[0m" >&2 ;;
            *) echo "${log_entry}" ;;
        esac
    fi
    
    # Exit if this was an error with an exit code
    if [ "${level^^}" = "ERROR" ] && [ -n "$exit_code" ]; then
        exit "$exit_code"
    fi
}

# Log level functions
log_debug() { [ "${LOG_LEVEL_NUM:-1}" -le ${LOG_LEVEL_DEBUG} ] && log "DEBUG" "$@"; }
log_info() { [ "${LOG_LEVEL_NUM:-1}" -le ${LOG_LEVEL_INFO} ] && log "INFO" "$@"; }
log_warning() { [ "${LOG_LEVEL_NUM:-1}" -le ${LOG_LEVEL_WARNING} ] && log "WARNING" "$@"; }
log_error() { log "ERROR" "$@" 1; }

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
    
    # Create log directory if it doesn't exist
    local log_dir="$(dirname "$LOG_FILE")"
    mkdir -p "$log_dir" || {
        echo "Failed to create log directory: $log_dir" >&2
        return 1
    }
    
    # Create log file with appropriate permissions
    if ! touch "$LOG_FILE" 2>/dev/null; then
        echo "Failed to create log file: $LOG_FILE" >&2
        LOG_FILE="/tmp/nextcloud-setup-$(date +%s).log"
        touch "$LOG_FILE" || {
            echo "Failed to create fallback log file: $LOG_FILE" >&2
            return 1
        }
    fi
    
    chmod 640 "$LOG_FILE" 2>/dev/null || true
    
    # Log script start
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] === Logging initialized ===" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Project Root: ${PROJECT_ROOT:-Not set}" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Log file: ${LOG_FILE}" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Log level: ${LOG_LEVEL:-INFO} (${LOG_LEVEL_NUM:-1})" >> "$LOG_FILE"
    
    return 0
}

# Set log level from environment or default to INFO
LOG_LEVEL_NUM=$(log "${LOG_LEVEL}" | head -n1 | awk '{print $1}')

export -f init_logging log log_debug log_info log_warning log_error run_command

# Log a message with timestamp and log level
# Usage: log <level> <message> [exit_code]
log() {
    local level="$1"
    local message="$2"
    local exit_code="${3:-}"
    local timestamp
    
    # Map level to numeric value
    local level_num
    level_num=$(map_log_level "$level")
    
    # Create log entry
    local log_entry="[$timestamp] [${level^^}] $message"
    
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

export -f log_debug log_info log_warning log_error log_section log_success run_command init_logging
