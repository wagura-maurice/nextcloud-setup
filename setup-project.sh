#!/bin/bash

# Nextcloud Project Setup Script
# This script helps set up the project structure and configuration files

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
TEMPLATE_DIR="$PROJECT_ROOT/config-templates"
TEMP_DIR="$PROJECT_ROOT/temp"
BACKUP_DIR="$PROJECT_ROOT/backups"

# Function to print status messages
print_status() {
    echo -e "${GREEN}[+]${NC} $1"
}

# Function to print warnings
print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Create necessary directories
print_status "Creating project directories..."
mkdir -p "$TEMP_DIR"
mkdir -p "$BACKUP_DIR"
mkdir -p "$TEMPLATE_DIR"
mkdir -p "$PROJECT_ROOT/logs"

# Set secure permissions
chmod 750 "$TEMP_DIR"
chmod 750 "$BACKUP_DIR"
chmod 750 "$PROJECT_ROOT/logs"
chown -R root:root "$TEMP_DIR" "$BACKUP_DIR" "$PROJECT_ROOT/logs"

# Copy template files if they don't exist
if [ ! -f "$TEMP_DIR/.nextcloud_backup_config" ] && [ -f "$TEMPLATE_DIR/backup-config.template" ]; then
    cp "$TEMPLATE_DIR/backup-config.template" "$TEMP_DIR/.nextcloud_backup_config"
    print_status "Created .nextcloud_backup_config template in $TEMP_DIR/"
    print_warning "Please edit $TEMP_DIR/.nextcloud_backup_config with your settings"
fi

if [ ! -f "$TEMP_DIR/.mysql_credentials" ] && [ -f "$TEMPLATE_DIR/mysql-credentials.template" ]; then
    cp "$TEMPLATE_DIR/mysql-credentials.template" "$TEMP_DIR/.mysql_credentials"
    print_status "Created .mysql_credentials template in $TEMP_DIR/"
    print_warning "Please edit $TEMP_DIR/.mysql_credentials with your database credentials"
fi

# Set secure permissions for config files
chmod 600 "$TEMP_DIR/"* 2>/dev/null || true

print_status "Project setup complete!"
echo -e "\nNext steps:"
echo "1. Edit the configuration files in $TEMP_DIR/"
echo "2. Make the scripts executable: chmod +x scripts/*.sh"
echo "3. Run the installation script: sudo ./scripts/install-nextcloud.sh"
