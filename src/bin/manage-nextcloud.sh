#!/bin/bash

# Nextcloud Manager
# ================
# A comprehensive tool for managing Nextcloud operations including:
# - Backup and restore
# - System maintenance
# - Performance optimization
# - Security checks
# - Monitoring

# Set strict mode for better error handling
set -o errexit
set -o nounset
set -o pipefail

# Set default values for exit codes
EXIT_SUCCESS=0
EXIT_FAILURE=1

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
SRC_DIR="${PROJECT_ROOT}/src"
CORE_DIR="${SRC_DIR}/core"
UTILS_DIR="${SRC_DIR}/utilities"

# Set up logging
LOG_DIR="${PROJECT_ROOT}/logs"
mkdir -p "${LOG_DIR}" 2>/dev/null
chmod 750 "${LOG_DIR}" 2>/dev/null || true

# Set log file with timestamp
LOG_FILE="${LOG_DIR}/manager-$(date +%Y%m%d%H%M%S).log"
touch "${LOG_FILE}" 2>/dev/null || {
    LOG_FILE="/tmp/nextcloud-manager-$(date +%s).log"
    touch "${LOG_FILE}" || {
        echo "Failed to create log file" >&2
        exit 1
    }
}
chmod 640 "${LOG_FILE}" 2>/dev/null || true

# Export environment variables
export PROJECT_ROOT SRC_DIR CORE_DIR UTILS_DIR LOG_DIR LOG_FILE

# Source core functions and environment loader
source "${CORE_DIR}/common-functions.sh"
source "${CORE_DIR}/logging.sh"

# Initialize logging
init_logging || {
    echo "Failed to initialize logging" >&2
    exit 1
}
source "$CORE_DIR/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

# Log script start
log_info "=== Starting Nextcloud Manager ==="
log_info "Project Root: $PROJECT_ROOT"

# Source additional core scripts
source "$CORE_DIR/config-manager.sh"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit $EXIT_FAILURE
fi

# Ensure required directories exist
for dir in "$LOG_DIR" "$BACKUP_DIR" "$(dirname "$NEXTCLOUD_DATA_DIR")"; do
    if [ ! -d "$dir" ]; then
        log_info "Creating directory: $dir"
        mkdir -p "$dir"
        chmod 750 "$dir"
    fi
done

# Check if Nextcloud is installed
if [ ! -f "$NEXTCLOUD_ROOT/occ" ]; then
    log_error "Nextcloud is not installed at $NEXTCLOUD_ROOT"
    log_info "Please run nextcloud-setup.sh first"
    exit $EXIT_FAILURE
fi

# Include component scripts
source "$UTILS_DIR/backup/backup-functions.sh"
source "$UTILS_DIR/restore/restore-functions.sh"
source "$UTILS_DIR/maintenance/maintenance-functions.sh"
source "$UTILS_DIR/monitoring/monitoring-functions.sh"

# Display header
show_header() {
    clear
    echo -e "\033[1;34m=== Nextcloud Manager ===\033[0m"
    echo -e "\033[1mVersion: 2.0.0\033[0m"
    echo -e "Nextcloud Path: $NEXTCLOUD_ROOT"
    echo -e "Data Directory: $NEXTCLOUD_DATA_DIR"
    echo -e "Backup Directory: $BACKUP_DIR\n"
}

# Main menu
show_menu() {
    while true; do
        show_header
        echo -e "\033[1mMain Menu\033[0m"
        echo "1. 🔄  Backup Operations"
        echo "2. ⏮️  Restore Operations"
        echo "3. 🛠️  Maintenance Tasks"
        echo "4. 📊 System Monitoring"
        echo "5. 🔒 Security Checks"
        echo "6. ⚙️  Configuration"
        echo "0. 🚪 Exit"
        echo ""
        read -p "Enter your choice [0-6]: " choice

    case $choice in
        1) backup_menu ;;
        2) restore_menu ;;
        3) maintenance_menu ;;
        4) monitoring_menu ;;
        5) security_menu ;;
        6) config_menu ;;
        0) 
            log_info "Exiting Nextcloud Manager"
            exit $EXIT_SUCCESS
            ;;
        *)
            log_error "Invalid option"
            sleep 1
            ;;
    esac
}

# Backup menu
backup_menu() {
    while true; do
        show_header
        echo -e "\033[1m🔧 Backup Operations\033[0m"
        echo "1. 🔄  Create Full Backup (Database + Files)"
        echo "2. 💾  Database Backup Only"
        echo "3. 📁  Files Backup Only"
        echo "4. 📋  List Available Backups"
        echo "5. 🕒  Configure Backup Schedule"
        echo "0. ↩️  Return to Main Menu"
        echo ""
        read -p "Enter your choice [0-5]: " choice

        case $choice in
            1) 
                log_info "Starting full backup..."
                backup_full
                ;;
            2) 
                log_info "Starting database backup..."
                backup_database
                ;;
            3) 
                log_info "Starting files backup..."
                backup_files
                ;;
            4) 
                log_info "Available backups:"
                list_backups
                ;;
            5)
                configure_backup_schedule
                ;;
            0) return ;;
            *) 
                log_error "Invalid option"
                ;;
        esac
        
        if [ "$choice" != "0" ]; then
            read -p "Press [Enter] to continue..."
        fi
    done
}

# Restore menu
restore_menu() {
    while true; do
        show_header
        echo -e "\033[1m⏮️  Restore Operations\033[0m"
        echo "1. 🔄  Full Restore (Database + Files)"
        echo "2. 💾  Restore Database Only"
        echo "3. 📁  Restore Files Only"
        echo "4. 📋  List Available Backups"
        echo "0. ↩️  Return to Main Menu"
        echo ""
        read -p "Enter your choice [0-4]: " choice

        case $choice in
            1) 
                log_info "Starting full restore..."
                restore_full
                ;;
            2) 
                log_info "Starting database restore..."
                restore_database
                ;;
            3) 
                log_info "Starting files restore..."
                restore_files
                ;;
            4) 
                log_info "Available backups:"
                list_backups
                ;;
            0) return ;;
            *) 
                log_error "Invalid option"
                ;;
        esac
        
        if [ "$choice" != "0" ]; then
            read -p "Press [Enter] to continue..."
        fi
    done
}

# Maintenance menu
maintenance_menu() {
    while true; do
        show_header
        echo -e "\033[1m🛠️  Maintenance Tasks\033[0m"
        echo "1. 🔄  Run Database Optimization"
        echo "2. 🧹  Cleanup Temporary Files"
        echo "3. 🔍  Check System Health"
        echo "4. 🔄  Update Nextcloud"
        echo "5. 📦  Update System Dependencies"
        echo "0. ↩️  Return to Main Menu"
        echo ""
        read -p "Enter your choice [0-5]: " choice

        case $choice in
            1) 
                log_info "Running database optimization..."
                optimize_database
                ;;
            2) 
                log_info "Cleaning up temporary files..."
                cleanup_temp_files
                ;;
            3) 
                log_info "Checking system health..."
                check_system_health
                ;;
            4)
                log_info "Updating Nextcloud..."
                update_nextcloud
                ;;
            5)
                log_info "Updating system dependencies..."
                update_dependencies
                ;;
            0) return ;;
            *) 
                log_error "Invalid option"
                ;;
        esac
        
        if [ "$choice" != "0" ]; then
            read -p "Press [Enter] to continue..."
        fi
    done
}

# Maintenance menu
maintenance_menu() {
    clear
    log_info "=== Maintenance Menu ==="
    echo "1. Optimize Database"
    echo "2. Cleanup Old Backups"
    echo "3. Run Nextcloud Repair"
    echo "4. Check System Health"
    echo "5. Return to Main Menu"
    echo ""
    read -p "Enter your choice [1-5]: " choice

    case $choice in
        1) 
            log_info "Optimizing database..."
            "${SCRIPT_DIR}/src/lib/maintenance/optimize-database.sh"
            ;;
        2) 
            log_info "Cleaning up old backups..."
            "${SCRIPT_DIR}/src/lib/maintenance/cleanup.sh"
            ;;
        3) 
            log_info "Running Nextcloud repair..."
            "${SCRIPT_DIR}/src/lib/maintenance/repair.sh"
            ;;
        4) 
            log_info "Checking system health..."
            "${SCRIPT_DIR}/src/lib/maintenance/check-health.sh"
            ;;
        5) return ;;
        *) 
            log_error "Invalid option"
            ;;
    esac
    
    read -p "Press [Enter] to continue..."
    maintenance_menu
}

# Monitoring menu
monitoring_menu() {
    clear
    log_info "=== Monitoring Menu ==="
    echo "1. View Current Status"
    echo "2. Run System Check"
    echo "3. View Logs"
    echo "4. Configure Monitoring"
    echo "5. Return to Main Menu"
    echo ""
    read -p "Enter your choice [1-5]: " choice

    case $choice in
        1) 
            log_info "Current system status:"
            "${SCRIPT_DIR}/src/lib/monitoring/monitor-nextcloud.sh" --status
            ;;
        2) 
            log_info "Running system check..."
            "${SCRIPT_DIR}/src/lib/monitoring/monitor-nextcloud.sh" --check
            ;;
        3) 
            log_info "Viewing logs..."
            less "${LOG_DIR:-/var/log/nextcloud}/monitor-$(date +%Y%m%d).log" 2>/dev/null || log_error "No logs found"
            ;;
        4) 
            log_info "Configuring monitoring..."
            "${SCRIPT_DIR}/src/lib/monitoring/configure-monitoring.sh"
            ;;
        5) return ;;
        *) 
            log_error "Invalid option"
            ;;
    esac
    
    read -p "Press [Enter] to continue..."
    monitoring_menu
}

# Security menu
security_menu() {
    clear
    log_info "=== Security Menu ==="
    echo "1. Run Security Scan"
    echo "2. Check File Permissions"
    echo "3. Check for Vulnerabilities"
    echo "4. Harden PHP Configuration"
    echo "5. Return to Main Menu"
    echo ""
    read -p "Enter your choice [1-5]: " choice

    case $choice in
        1) 
            log_info "Running security scan..."
            "${SCRIPT_DIR}/src/lib/utils/security.sh" --scan
            ;;
        2) 
            log_info "Checking file permissions..."
            "${SCRIPT_DIR}/src/lib/utils/security.sh" --check-permissions
            ;;
        3) 
            log_info "Checking for vulnerabilities..."
            "${SCRIPT_DIR}/src/lib/utils/security.sh" --check-vulnerabilities
            ;;
        4) 
            log_info "Hardening PHP configuration..."
            "${SCRIPT_DIR}/src/lib/utils/security.sh" --harden-php
            ;;
        5) return ;;
        *) 
            log_error "Invalid option"
            ;;
    esac
    
    read -p "Press [Enter] to continue..."
    security_menu
}

# Help message
show_help() {
    echo "Nextcloud Manager - Manage your Nextcloud installation"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --backup [full|db|files]  Run backup (full, database only, or files only)"
    echo "  --restore [backup_dir]    Restore from backup"
    echo "  --update                  Update Nextcloud and dependencies"
    echo "  --maintenance             Run maintenance tasks"
    echo "  --monitor                 Show system status"
    echo "  --security                Run security checks"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --backup full         # Create a full backup"
    echo "  $0 --restore /path/to/backup  # Restore from backup"
    echo "  $0 --update              # Update Nextcloud"
}

# Handle command line arguments
if [ $# -gt 0 ]; then
    case $1 in
        --backup)
            case $2 in
                full)
                    "${SCRIPT_DIR}/src/lib/backup/backup-nextcloud.sh" --full
                    ;;
                db)
                    "${SCRIPT_DIR}/src/lib/backup/backup-database.sh"
                    ;;
                files)
                    "${SCRIPT_DIR}/src/lib/backup/backup-files.sh"
                    ;;
                *)
                    log_error "Please specify backup type: full, db, or files"
                    exit 1
                    ;;
            esac
            ;;
        --restore)
            if [ -z "$2" ]; then
                log_error "Please specify backup directory"
                exit 1
            fi
            "${SCRIPT_DIR}/src/lib/restore/restore-nextcloud.sh" "$2"
            ;;
        --update)
            "${SCRIPT_DIR}/src/lib/update/update-nextcloud.sh"
            "${SCRIPT_DIR}/src/lib/update/update-dependencies.sh"
            ;;
        --maintenance)
            "${SCRIPT_DIR}/src/lib/maintenance/repair.sh"
            "${SCRIPT_DIR}/src/lib/maintenance/optimize-database.sh"
            "${SCRIPT_DIR}/src/lib/maintenance/cleanup.sh"
            ;;
        --monitor)
            "${SCRIPT_DIR}/src/lib/monitoring/monitor-nextcloud.sh"
            ;;
        --security)
            "${SCRIPT_DIR}/src/lib/utils/security.sh" --scan
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
else
    # Show interactive menu if no arguments provided
    show_menu
fi

exit 0
