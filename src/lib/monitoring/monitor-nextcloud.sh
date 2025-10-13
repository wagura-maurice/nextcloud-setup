#!/bin/bash

# Nextcloud Monitoring Script
# This script monitors the health and performance of Nextcloud

# Source core functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/core/common-functions.sh"
source "${SCRIPT_DIR}/core/logging.sh"
source "${SCRIPT_DIR}/core/config-manager.sh"

# Load configuration
load_config

# Configuration
# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")/.."

# Ensure logs directory exists
LOG_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"

# Load configuration from .env if exists
if [ -f "${PROJECT_ROOT}/.env" ]; then
    source "${PROJECT_ROOT}/.env"
fi

# Default values
NEXTCLOUD_PATH="${NEXTCLOUD_INSTALL_DIR:-/var/www/nextcloud}"
WEB_SERVER_USER="${WEB_SERVER_USER:-www-data}"
LOG_FILE="${LOG_DIR}/monitor-$(date +%Y%m%d).log"
STATUS_FILE="${LOG_DIR}/status.json"
PHP_PATH="$(which php8.4 || which php8.2 || which php8.1 || which php8.0 || which php7.4 || which php)"
OCC="${PHP_PATH} ${NEXTCLOUD_PATH}/occ"

# Function to get system metrics
get_system_metrics() {
    local metrics=()
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    metrics+=("\"cpu_usage\": $cpu_usage")
    
    # Memory usage
    local mem_total=$(free -m | awk '/Mem:/ {print $2}')
    local mem_used=$(free -m | awk '/Mem:/ {print $3}')
    local mem_usage=$(echo "scale=2; ($mem_used / $mem_total) * 100" | bc)
    metrics+=("\"memory_usage\": $mem_usage")
    
    # Disk usage
    local disk_usage=$(df -h /var/www | awk 'NR==2 {print $5}' | tr -d '%')
    metrics+=("\"disk_usage\": $disk_usage")
    
    # Load average
    local load_avg=$(cat /proc/loadavg | awk '{print $1}')
    metrics+=("\"load_avg\": $load_avg")
    
    echo "{$(IFS=,; echo "${metrics[*]}")}"
}

# Function to get Nextcloud status
get_nextcloud_status() {
    local status=()
    
    # Check if OCC exists and is executable
    if [ ! -f "${NEXTCLOUD_PATH}/occ" ]; then
        log_error "Nextcloud OCC not found at ${NEXTCLOUD_PATH}/occ"
        echo "{}"
        return 1
    fi
    
    # Run as web server user
    if [ -z "$WEB_SERVER_USER" ]; then
        log_error "WEB_SERVER_USER is not set. Please check your .env file."
        return 1
    fi
    local run_as="sudo -u $WEB_SERVER_USER"
    
    # Get Nextcloud version
    local version=$(${run_as} ${OCC} status 2>/dev/null | grep "version" | awk '{print $3}')
    [ -n "$version" ] && status+=("\"version\": \"$version\"")
    
    # Check if in maintenance mode
    local maintenance_mode=$(${run_as} ${OCC} maintenance:mode 2>/dev/null | grep -q "enabled" && echo "true" || echo "false")
    status+=("\"maintenance_mode\": $maintenance_mode")
    
    # Get number of users
    local user_count=$(${run_as} ${OCC} user:list 2>/dev/null | wc -l)
    status+=("\"user_count\": $((user_count-1))")
    
    # Get number of active users in the last hour
    local active_users=$(${run_as} ${OCC} user:list 2>/dev/null | xargs -I {} ${run_as} ${OCC} user:info {} 2>/dev/null | \
        grep 'Last Login:' | grep -v 'Never' | \
        awk -v d1="$(date -d '1 hour ago' +%s)" -F': ' '
        {
            if ($2 != "Never") {
                cmd="date -d \""$2"\" +%s"; 
                cmd | getline d2; 
                close(cmd); 
                if (d2 > d1) print $0
            }
        }' | wc -l)
    status+=("\"active_users_1h\": $active_users")
    
    # Check background jobs
    local background_jobs=$(${run_as} ${OCC} background:job:list 2>/dev/null | wc -l)
    status+=("\"background_jobs\": $((background_jobs-2))")
    
    # Check for updates
    local update_available=$(${run_as} ${OCC} update:check 2>/dev/null | grep -c 'available' || echo 0)
    status+=("\"update_available\": $update_available")
    
    echo "{$(IFS=,; echo "${status[*]}")}"
}

# Function to check services
check_services() {
    local services=()
    
    # Define services to check
    local service_list=(
        "${WEB_SERVER:-apache2}"
        "${DB_SERVICE:-mysql}"
        "${CACHE_SERVICE:-redis-server}"
        "${PHP_FPM_SERVICE:-php8.4-fpm}"
        "cron"
    )
    
    for service in "${service_list[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            services+=("\"$service\": \"running\"")
        else
            services+=("\"$service\": \"stopped\"")
            log_warning "Service $service is not running"
        fi
    done
    
    echo "{$(IFS=,; echo "${services[*]}")}"
}

# Function to check disk space
check_disk_space() {
    local disks=()
    
    # Check main disk
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    disks+=("\"root\": $disk_usage")
    
    # Check Nextcloud data directory if it's on a different partition
    local data_dir="${NEXTCLOUD_DATA_DIR:-$(${run_as} ${OCC} config:system:get datadirectory 2>/dev/null)}"
    if [ -n "$data_dir" ] && [ -d "$data_dir" ] && [ "$data_dir" != "/var/www/nextcloud/data" ]; then
        local data_usage=$(df -h "$data_dir" | awk 'NR==2 {print $5}' | tr -d '%')
        disks+=("\"data\": $data_usage")
    fi
    
    # Check backup directory if it exists
    if [ -d "${BACKUP_DIR:-/var/backups/nextcloud}" ]; then
        local backup_usage=$(df -h "${BACKUP_DIR:-/var/backups/nextcloud}" | awk 'NR==2 {print $5}' | tr -d '%')
        disks+=("\"backups\": $backup_usage")
    fi
    
    echo "{$(IFS=,; echo "${disks[*]}")}"
}

# Function to generate status JSON
generate_status() {
    log_info "Generating system status..."
    
    # Get all metrics
    local system_metrics=$(get_system_metrics)
    local nextcloud_status=$(get_nextcloud_status)
    local services_status=$(check_services)
    local disk_status=$(check_disk_space)
    
    # Ensure the logs directory exists
    mkdir -p "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    
    # Generate status JSON
    cat > "$STATUS_FILE" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "system": $system_metrics,
    "nextcloud": $nextcloud_status,
    "services": $services_status,
    "disks": $disk_status
}
EOF
    
    # Set proper permissions
    chmod 644 "$STATUS_FILE"
    
    # Log to both console and log file
    local status_summary=$(jq -c '{
        timestamp: .timestamp,
        system: {cpu_usage, memory_usage, disk_usage, load_avg},
        nextcloud: {version, maintenance_mode, user_count, active_users_1h, background_jobs, update_available},
        services: .services,
        disks: .disks
    }' "$STATUS_FILE" 2>/dev/null || echo '{"error":"Failed to parse status"}')
    
    log_info "Status updated: $status_summary"
}

# Function to check for issues and alert if needed
check_for_issues() {
    local issues=0
    local warnings=0
    
    # Check disk space
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$disk_usage" -gt 90 ]; then
        log_error "Disk usage is critical: ${disk_usage}%"
        ((issues++))
    elif [ "$disk_usage" -gt 80 ]; then
        log_warning "Disk usage is high: ${disk_usage}%"
        ((warnings++))
    fi
    
    # Check Nextcloud data directory space if different from root
    local data_dir="${NEXTCLOUD_DATA_DIR:-$(${run_as} ${OCC} config:system:get datadirectory 2>/dev/null)}"
    if [ -n "$data_dir" ] && [ -d "$data_dir" ] && [ "$data_dir" != "/var/www/nextcloud/data" ]; then
        local data_usage=$(df -h "$data_dir" | awk 'NR==2 {print $5}' | tr -d '%')
        if [ "$data_usage" -gt 90 ]; then
            log_error "Data directory disk usage is critical: ${data_usage}%"
            ((issues++))
        elif [ "$data_usage" -gt 80 ]; then
            log_warning "Data directory disk usage is high: ${data_usage}%"
            ((warnings++))
        fi
    fi
    
    # Check services
    local service_list=(
        "${WEB_SERVER:-apache2}"
        "${DB_SERVICE:-mysql}"
        "${CACHE_SERVICE:-redis-server}"
        "${PHP_FPM_SERVICE:-php8.4-fpm}"
    )
    
    for service in "${service_list[@]}"; do
        if ! systemctl is-active --quiet "$service" 2>/dev/null; then
            log_error "Service $service is not running"
            ((issues++))
        fi
    done
    
    # Check Nextcloud maintenance mode
    if [ -f "${NEXTCLOUD_PATH}/occ" ]; then
        local run_as="sudo -u ${WEB_SERVER_USER:-www-data}"
        if ${run_as} ${OCC} maintenance:mode 2>/dev/null | grep -q "enabled"; then
            log_warning "Nextcloud is in maintenance mode"
            ((warnings++))
        fi
        
        # Check for failed background jobs
        local failed_jobs=$(${run_as} ${OCC} background:job:list 2>/dev/null | grep -c 'failed' || echo 0)
        if [ "$failed_jobs" -gt 0 ]; then
            log_warning "$failed_jobs background jobs have failed"
            ((warnings++))
        fi
    else
        log_error "Nextcloud OCC not found at ${NEXTCLOUD_PATH}/occ"
        ((issues++))
    fi
    
    # Log summary
    if [ $issues -gt 0 ]; then
        log_error "Detected $issues critical issue(s) and $warnings warning(s)"
        return 1
    elif [ $warnings -gt 0 ]; then
        log_warning "Detected $warnings warning(s)"
        return 2
    else
        log_info "No issues detected"
        return 0
    fi
}

# Main function
main() {
    log_info "=== Starting Nextcloud Monitoring ==="
    
    # Generate status
    generate_status
    
    # Check for issues
    if check_for_issues; then
        log_info "=== Monitoring Completed Successfully ==="
        return 0
    else
        local status=$?
        if [ $status -eq 1 ]; then
            log_error "=== Monitoring Completed with Critical Issues ==="
        else
            log_warning "=== Monitoring Completed with Warnings ==="
        fi
        return $status
    fi
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
