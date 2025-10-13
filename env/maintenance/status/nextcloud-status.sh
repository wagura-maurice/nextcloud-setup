#!/bin/bash

# Nextcloud Status Script
# This script checks the status of Nextcloud and its dependencies

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NEXTCLOUD_PATH="/var/www/nextcloud"
PHP_PATH="/usr/bin/php"
OCC="$PHP_PATH $NEXTCLOUD_PATH/occ"

# Function to print section header
print_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} $2"
    else
        echo -e "${RED}[FAILED]${NC} $2"
    fi
}

# Function to check service status
check_service() {
    local service=$1
    if systemctl is-active --quiet $service; then
        print_status 0 "Service $service is running"
    else
        print_status 1 "Service $service is NOT running"
    fi
}

# Function to check disk space
check_disk_space() {
    local usage=$(df -h /var/www | awk 'NR==2 {print $5}' | tr -d '%')
    if [ $usage -gt 90 ]; then
        print_status 1 "Disk space usage: ${usage}% (Critical)"
    elif [ $usage -gt 75 ]; then
        print_status 1 "Disk space usage: ${usage}% (Warning)"
    else
        print_status 0 "Disk space usage: ${usage}%"
    fi
}

# Function to check Nextcloud status
check_nextcloud_status() {
    local status=$($OCC status 2>&1)
    if [ $? -eq 0 ]; then
        echo "$status" | while read -r line; do
            print_status 0 "$line"
        done
    else
        print_status 1 "Failed to get Nextcloud status"
    fi
}

# Function to check PHP version
check_php_version() {
    local required_php="8.0"
    local current_php=$($PHP_PATH -v | grep -oP '\d+\.\d+' | head -1)
    
    if [ "$(printf '%s\n' "$required_php" "$current_php" | sort -V | head -n1)" = "$required_php" ]; then 
        print_status 0 "PHP version: $current_php"
    else
        print_status 1 "PHP version: $current_php (Required: $required_php+)"
    fi
}

# Function to check database status
check_database_status() {
    local db_status=$($OCC db:table-status 2>&1)
    if [ $? -eq 0 ]; then
        print_status 0 "Database connection: OK"
        local table_count=$(echo "$db_status" | wc -l)
        print_status 0 "Tables found: $((table_count - 1))"
    else
        print_status 1 "Database connection: FAILED"
    fi
}

# Function to check for updates
check_updates() {
    local update_info=$($OCC update:check 2>&1)
    if [[ $update_info == *"up to date"* ]]; then
        print_status 0 "Nextcloud is up to date"
    else
        print_status 1 "Update available: $update_info"
    fi
}

# Main function
main() {
    echo -e "\n${BLUE}===== Nextcloud System Status =====${NC}\n"
    
    # System status
    print_section "System Status"
    check_disk_space
    check_service apache2
    check_service mysql
    check_service redis-server
    check_service php8.4-fpm
    
    # PHP status
    print_section "PHP Status"
    check_php_version
    
    # Nextcloud status
    print_section "Nextcloud Status"
    check_nextcloud_status
    check_database_status
    check_updates
    
    # Maintenance mode
    if [ -f "$NEXTCLOUD_PATH/data/update_in_progress.lock" ]; then
        print_status 1 "Update in progress"
    fi
    
    if [ -f "$NEXTCLOUD_PATH/data/.maintenance" ]; then
        print_status 1 "Maintenance mode is ENABLED"
    fi
    
    echo -e "\n${BLUE}=================================${NC}\n"
}

# Run main function
main "$@"
