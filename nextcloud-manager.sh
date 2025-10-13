#!/bin/bash

# Nextcloud Manager
# ================
# Main entry point for managing an existing Nextcloud installation.
# This script provides a menu-driven interface for common Nextcloud maintenance tasks.

# Set strict mode for better error handling
set -o errexit
set -o nounset
set -o pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
SRC_DIR="$PROJECT_ROOT/src"
CORE_DIR="$SRC_DIR/core"

# Source core functions and environment loader
source "$CORE_DIR/common-functions.sh"
source "$CORE_DIR/logging.sh"
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
    exit 1
fi

# Ensure required directories exist
mkdir -p "$LOG_DIR"
chmod 750 "$LOG_DIR"
chmod 750 "$BACKUP_DIR"
chmod 750 "$(dirname "$NEXTCLOUD_DATA_DIR")"

# Main menu
show_menu() {
    clear
    log_info "=== Nextcloud Manager ==="
    echo "1. Backup Nextcloud"
    echo "2. Restore Nextcloud"
    echo "3. Update Nextcloud"
    echo "4. Maintenance"
    echo "5. Monitoring"
    echo "6. Security"
    echo "7. Exit"
    echo ""
    read -p "Enter your choice [1-7]: " choice

    case $choice in
        1) backup_menu ;;
        2) restore_menu ;;
        3) update_menu ;;
        4) maintenance_menu ;;
        5) monitoring_menu ;;
        6) security_menu ;;
        7) exit 0 ;;
        *) 
            log_error "Invalid option"
            sleep 1
            show_menu
            ;;
    esac
}

# Backup menu
backup_menu() {
    clear
    log_info "=== Backup Menu ==="
    echo "1. Full Backup (Database + Files)"
    echo "2. Database Backup Only"
    echo "3. Files Backup Only"
    echo "4. List Available Backups"
    echo "5. Return to Main Menu"
    echo ""
    read -p "Enter your choice [1-5]: " choice

    case $choice in
        1) 
            log_info "Starting full backup..."
            "${SCRIPT_DIR}/src/lib/backup/backup-nextcloud.sh" --full
            ;;
        2) 
            log_info "Starting database backup..."
            "${SCRIPT_DIR}/src/lib/backup/backup-database.sh"
            ;;
        3) 
            log_info "Starting files backup..."
            "${SCRIPT_DIR}/src/lib/backup/backup-files.sh"
            ;;
        4) 
            log_info "Available backups:"
            ls -l "${BACKUP_DIR:-/var/backups/nextcloud}" 2>/dev/null || log_warning "No backups found"
            ;;
        5) return ;;
        *) 
            log_error "Invalid option"
            ;;
    esac
    
    read -p "Press [Enter] to continue..."
    backup_menu
}

# Restore menu
restore_menu() {
    clear
    log_info "=== Restore Menu ==="
    echo "1. Full Restore (Database + Files)"
    echo "2. Database Restore Only"
    echo "3. Files Restore Only"
    echo "4. List Available Backups"
    echo "5. Return to Main Menu"
    echo ""
    read -p "Enter your choice [1-5]: " choice

    case $choice in
        1) 
            log_info "Starting full restore..."
            "${SCRIPT_DIR}/src/lib/restore/restore-nextcloud.sh" --full
            ;;
        2) 
            log_info "Starting database restore..."
            "${SCRIPT_DIR}/src/lib/restore/restore-database.sh"
            ;;
        3) 
            log_info "Starting files restore..."
            "${SCRIPT_DIR}/src/lib/restore/restore-files.sh"
            ;;
        4) 
            log_info "Available backups:"
            ls -l "${BACKUP_DIR:-/var/backups/nextcloud}" 2>/dev/null || log_warning "No backups found"
            ;;
        5) return ;;
        *) 
            log_error "Invalid option"
            ;;
    esac
    
    read -p "Press [Enter] to continue..."
    restore_menu
}

# Update menu
update_menu() {
    clear
    log_info "=== Update Menu ==="
    echo "1. Update Nextcloud"
    echo "2. Update System Dependencies"
    echo "3. Check for Updates"
    echo "4. Return to Main Menu"
    echo ""
    read -p "Enter your choice [1-4]: " choice

    case $choice in
        1) 
            log_info "Updating Nextcloud..."
            "${SCRIPT_DIR}/src/lib/update/update-nextcloud.sh"
            ;;
        2) 
            log_info "Updating system dependencies..."
            "${SCRIPT_DIR}/src/lib/update/update-dependencies.sh"
            ;;
        3) 
            log_info "Checking for updates..."
            "${SCRIPT_DIR}/src/lib/update/update-nextcloud.sh" --check
            ;;
        4) return ;;
        *) 
            log_error "Invalid option"
            ;;
    esac
    
    read -p "Press [Enter] to continue..."
    update_menu
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
