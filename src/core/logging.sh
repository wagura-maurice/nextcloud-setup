#!/bin/bash

#!/bin/bash

# Logging configuration
LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/logs"
mkdir -p "$LOG_DIR"
chmod 750 "$LOG_DIR"

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
LOG_LEVEL_NUM=$(map_log_level "${LOG_LEVEL:-INFO}")
export LOG_LEVEL_NUM

# Get current timestamp
get_timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# Initialize logging for a script
init_logging() {
    local script_name=$(basename "${BASH_SOURCE[1]}" .sh)
    local timestamp=$(date +%Y%m%d_%H%M%S)
    LOG_FILE="$LOG_DIR/${script_name}_${timestamp}.log"
    
    # Create log file with secure permissions
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    
    # Log script start
    log "INFO" "=== Starting $script_name ==="
}

# Log a message
log() {
    local level="$1"
    local message="${*:2}"
    local timestamp=$(get_timestamp)
    local level_str
    
    # Map numeric levels to strings
    case "$level" in
        "$LOG_LEVEL_DEBUG") level_str="DEBUG" ;;
        "$LOG_LEVEL_INFO") level_str="INFO" ;;
        "$LOG_LEVEL_WARNING") level_str="WARNING" ;;
        "$LOG_LEVEL_ERROR") level_str="ERROR" ;;
        *) level_str="UNKNOWN" ;;
    esac
    
    # Format log entry
    local log_entry="[$timestamp] [$level_str] $message"
    
    # Write to log file
    echo "$log_entry" >> "$LOG_FILE"
    
    # Print to console based on log level
    if [ "$level" -le "$LOG_LEVEL_NUM" ]; then
        case "$level" in
            "$LOG_LEVEL_DEBUG") echo -e "\033[0;36m$log_entry\033[0m" ;;
            "$LOG_LEVEL_INFO") echo -e "\033[0;32m$log_entry\033[0m" ;;
            "$LOG_LEVEL_WARNING") echo -e "\033[0;33m$log_entry\033[0m" >&2 ;;
            "$LOG_LEVEL_ERROR") echo -e "\033[0;31m$log_entry\033[0m" >&2 ;;
            *) echo "$log_entry" ;;
        esac
    fi
}

# Helper functions for different log levels
log_debug() { log "$LOG_LEVEL_DEBUG" "$@"; }
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
