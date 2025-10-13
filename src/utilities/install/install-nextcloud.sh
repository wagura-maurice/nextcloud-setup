#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Installing Nextcloud"

# Default values
NEXTCLOUD_ROOT="/var/www/nextcloud"
NEXTCLOUD_DATA="/var/nextcloud/data"
NEXTCLOUD_USER="www-data"
NEXTCLOUD_GROUP="www-data"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Check if Apache is installed
if ! command -v apache2 >/dev/null 2>&1; then
    log_error "Apache web server not found. Please install Apache first."
    exit 1
fi

# Create necessary directories
log_info "Creating directories..."
mkdir -p "$NEXTCLOUD_ROOT" "$NEXTCLOUD_DATA"

# Get latest Nextcloud version
log_info "Fetching latest Nextcloud version..."
LATEST_VERSION=$(curl -s https://download.nextcloud.com/server/releases/latest-26.tar.bz2 | grep -oP 'nextcloud-\d+\.\d+\.\d+' | head -1 | cut -d'-' -f2)

if [ -z "$LATEST_VERSION" ]; then
    log_error "Could not determine the latest Nextcloud version"
    exit 1
fi

DOWNLOAD_URL="https://download.nextcloud.com/server/releases/nextcloud-${LATEST_VERSION}.tar.bz2"
DOWNLOAD_SHA256_URL="https://download.nextcloud.com/server/releases/nextcloud-${LATEST_VERSION}.tar.bz2.sha256"
DOWNLOAD_ASC_URL="https://download.nextcloud.com/server/releases/nextcloud-${LATEST_VERSION}.tar.bz2.asc"
DOWNLOAD_DIR="/tmp/nextcloud-download"
DOWNLOAD_FILE="${DOWNLOAD_DIR}/nextcloud-${LATEST_VERSION}.tar.bz2"

# Create download directory
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR" || exit 1

# Download Nextcloud
log_info "Downloading Nextcloud ${LATEST_VERSION}..."
if ! wget --show-progress -q "$DOWNLOAD_URL" -O "$DOWNLOAD_FILE"; then
    log_error "Failed to download Nextcloud"
    exit 1
fi

# Download checksum and signature
log_info "Downloading verification files..."
wget -q "$DOWNLOAD_SHA256_URL" -O "${DOWNLOAD_FILE}.sha256"
wget -q "$DOWNLOAD_ASC_URL" -O "${DOWNLOAD_FILE}.asc"

# Verify checksum
log_info "Verifying checksum..."
if ! sha256sum -c --status "${DOWNLOAD_FILE}.sha256"; then
    log_error "Checksum verification failed"
    exit 1
fi

# Verify signature (optional but recommended)
if command -v gpg >/dev/null 2>&1; then
    log_info "Verifying package signature..."
    wget -q https://nextcloud.com/nextcloud.asc -O- | gpg --import
    if ! gpg --verify "${DOWNLOAD_FILE}.asc" "$DOWNLOAD_FILE" 2>/dev/null; then
        log_warning "GPG signature verification failed (this is not critical but recommended)"
    fi
else
    log_warning "GPG not found, skipping signature verification"
fi

# Extract Nextcloud
log_info "Extracting Nextcloud to ${NEXTCLOUD_ROOT}..."
tar -xjf "$DOWNLOAD_FILE" -C /tmp

# Remove old installation if it exists
if [ -d "$NEXTCLOUD_ROOT" ] && [ "$(ls -A $NEXTCLOUD_ROOT)" ]; then
    log_warning "Existing Nextcloud installation found, creating backup..."
    BACKUP_DIR="/var/backups/nextcloud-$(date +%Y%m%d%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -a "$NEXTCLOUD_ROOT" "${BACKUP_DIR}/nextcloud"
    log_info "Backup created at ${BACKUP_DIR}"
    rm -rf "$NEXTCLOUD_ROOT"
fi

# Move files to web root
mv "/tmp/nextcloud" "$NEXTCLOUD_ROOT"

# Set permissions
log_info "Setting up permissions..."
chown -R ${NEXTCLOUD_USER}:${NEXTCLOUD_GROUP} "$NEXTCLOUD_ROOT"
chown -R ${NEXTCLOUD_USER}:${NEXTCLOUD_GROUP} "$NEXTCLOUD_DATA"
chmod -R 750 "$NEXTCLOUD_ROOT"
chmod -R 770 "$NEXTCLOUD_DATA"

# Enable necessary PHP modules
if command -v phpenmod >/dev/null 2>&1; then
    phpenmod -v ALL -s ALL \
        bcmath bz2 ctype curl dom fileinfo gd gmp iconv intl json mbstring \
        openssl pcntl pdo posix session simplexml tokenizer xml xmlreader \
        xmlwriter zip zlib
fi

# Clean up
download_cleanup() {
    log_info "Cleaning up..."
    rm -rf "$DOWNLOAD_DIR"
    log_success "Nextcloud ${LATEST_VERSION} has been installed to ${NEXTCLOUD_ROOT}"
    log_info "Data directory: ${NEXTCLOUD_DATA}"
    log_info "Please complete the setup using the web interface or occ command"
}

# Register cleanup on exit
trap download_cleanup EXIT

# Output next steps
cat << EOF

Nextcloud Installation Complete
==============================

Nextcloud has been installed to: ${NEXTCLOUD_ROOT}
Data directory: ${NEXTCLOUD_DATA}

Next steps:
1. Configure your web server (Apache) to serve Nextcloud
2. Set up the database (MariaDB)
3. Complete the installation via the web interface or occ command

For more information, visit:
https://docs.nextcloud.com/server/latest/admin_manual/installation/

EOF

exit 0
