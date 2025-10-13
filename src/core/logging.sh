#!/bin/bash

#!/bin/bash

# Logging Functions for Nextcloud Setup and Management
# This script provides consistent logging functionality across all scripts

# Set default log level if not set
: "${LOG_LEVEL:="INFO"}"
: "${LOG_FILE:="${LOG_DIR:-/var/log/nextcloud}/nextcloud-setup.log"}"

# Define log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARNING=2
readonly LOG_LEVEL_ERROR=3

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
LOG_LEVEL_NUM=$(map_log_level "${LOG_LEVEL}")
export LOG_LEVEL_NUM

# Ensure log directory exists
log_dir="$(dirname "$LOG_FILE")"
mkdir -p "$log_dir"
chmod 750 "$log_dir"

# Initialize logging
init_logging() {
    # Create log file if it doesn't exist
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    
    # Log script start
    log_info "=== Logging initialized ==="
    log_info "Log file: $LOG_FILE"
    log_info "Log level: ${LOG_LEVEL} (${LOG_LEVEL_NUM})"
}

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
