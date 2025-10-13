#!/bin/bash
set -euo pipefail

# Set project root and core directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"  # Points to utilities directory
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"  # Points to src directory
CORE_DIR="${PROJECT_ROOT}/core"
UTILS_DIR="${SCRIPT_DIR}"  # Current directory is utilities
LOG_DIR="${PROJECT_ROOT}/../logs"
CONFIG_DIR="${PROJECT_ROOT}/../config"
DATA_DIR="${PROJECT_ROOT}/../data"
ENV_FILE="${PROJECT_ROOT}/../.env"

# Export environment variables
export PROJECT_ROOT CORE_DIR UTILS_DIR LOG_DIR CONFIG_DIR DATA_DIR ENV_FILE

# Create required directories
mkdir -p "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/../tmp"
chmod 750 "${LOG_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${PROJECT_ROOT}/../tmp"

# Function to safely source core utilities
safe_source() {
    local file="$1"
    if [ -f "${file}" ]; then
        # shellcheck source=/dev/null
        source "${file}" || {
            echo "Error: Failed to load ${file}" >&2
            return 1
        }
    else
        echo "Error: Required file not found: ${file}" >&2
        return 1
    fi
}

# Source core utilities with error handling
if ! safe_source "${CORE_DIR}/config-manager.sh" || \
   ! safe_source "${CORE_DIR}/env-loader.sh" || \
   ! safe_source "${CORE_DIR}/logging.sh"; then
    exit 1
fi

# Initialize environment and logging
if ! load_environment || ! init_logging; then
    echo "Error: Failed to initialize environment and logging" >&2
    exit 1
fi

log_section "Nextcloud Installation"

# Default values
NEXTCLOUD_ROOT="/var/www/nextcloud"
NEXTCLOUD_DATA="${DATA_DIR}/nextcloud"
NEXTCLOUD_USER="www-data"
NEXTCLOUD_GROUP="www-data"
NEXTCLOUD_VERSION="latest"  # Can be 'latest' or specific version like '28.0.0'

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "❌ This script must be run as root"
    exit 1
fi

# Check if required services are installed and running
log_info "🔍 Checking system requirements..."

# Check Apache
if ! command -v apache2 >/dev/null 2>&1; then
    log_error "❌ Apache web server not found. Please install Apache first."
    exit 1
fi

# Check PHP
if ! command -v php8.4 >/dev/null 2>&1; then
    log_error "❌ PHP 8.4 not found. Please install PHP 8.4 first."
    exit 1
fi

# Check MariaDB
if ! command -v mariadb >/dev/null 2>&1; then
    log_warning "⚠️  MariaDB not found. Make sure to install and configure it before proceeding."
fi

# Create necessary directories
log_info "📁 Creating directories..."
mkdir -p "$NEXTCLOUD_ROOT" "$NEXTCLOUD_DATA"
chown -R ${NEXTCLOUD_USER}:${NEXTCLOUD_GROUP} "$NEXTCLOUD_ROOT" "$NEXTCLOUD_DATA"
chmod 750 "$NEXTCLOUD_ROOT" "$NEXTCLOUD_DATA"

# Function to get the latest Nextcloud version
get_latest_version() {
    log_info "🌐 Fetching latest Nextcloud version..."
    local version
    
    # Try to get the latest version from the latest.tar.bz2 file
    version=$(curl -s -L -I https://download.nextcloud.com/server/releases/latest.tar.bz2 | 
             grep -i '^location:' | grep -oP 'nextcloud-\d+\.\d+\.\d+' | head -1 | cut -d'-' -f2)
    
    if [ -z "$version" ]; then
        # Fallback: parse the releases page
        version=$(curl -s https://download.nextcloud.com/server/releases/ | 
                 grep -oP 'nextcloud-\d+\.\d+\.\d+\.tar\.bz2' | 
                 sort -V | tail -1 | cut -d'-' -f2 | cut -d'.' -f1-3)
    fi
    
    echo "$version"
}

# Determine Nextcloud version to install
if [ "$NEXTCLOUD_VERSION" = "latest" ]; then
    NEXTCLOUD_VERSION=$(get_latest_version)
    if [ -z "$NEXTCLOUD_VERSION" ]; then
        log_error "❌ Could not determine the latest Nextcloud version"
        exit 1
    fi
    log_info "✅ Latest version: ${NEXTCLOUD_VERSION}"
else
    log_info "ℹ️  Using specified version: ${NEXTCLOUD_VERSION}"
fi

# Set download URLs
DOWNLOAD_BASE_URL="https://download.nextcloud.com/server/releases"
DOWNLOAD_FILE="nextcloud-${NEXTCLOUD_VERSION}.tar.bz2"
DOWNLOAD_URL="${DOWNLOAD_BASE_URL}/${DOWNLOAD_FILE}"
DOWNLOAD_SHA256_URL="${DOWNLOAD_BASE_URL}/${DOWNLOAD_FILE}.sha256"
DOWNLOAD_ASC_URL="${DOWNLOAD_BASE_URL}/${DOWNLOAD_FILE}.asc"
DOWNLOAD_DIR="/tmp/nextcloud-download"
DOWNLOAD_PATH="${DOWNLOAD_DIR}/${DOWNLOAD_FILE}"

# Create download directory
mkdir -p "$DOWNLOAD_DIR"
chmod 700 "$DOWNLOAD_DIR"

# Create download directory
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR" || exit 1

# Function to download and verify Nextcloud
download_nextcloud() {
    log_info "📥 Downloading Nextcloud ${NEXTCLOUD_VERSION}..."
    
    # Download the file
    if ! wget --show-progress -q "$DOWNLOAD_URL" -O "$DOWNLOAD_PATH"; then
        log_error "❌ Failed to download Nextcloud"
        return 1
    fi
    
    # Verify checksum
    log_info "🔍 Verifying checksum..."
    local expected_checksum
    expected_checksum=$(curl -s "$DOWNLOAD_SHA256_URL" | cut -d' ' -f1)
    
    if [ -z "$expected_checksum" ]; then
        log_warning "⚠️  Could not verify checksum (file not found or empty)"
    else
        local actual_checksum
        actual_checksum=$(sha256sum "$DOWNLOAD_PATH" | cut -d' ' -f1)
        
        if [ "$expected_checksum" != "$actual_checksum" ]; then
            log_error "❌ Checksum verification failed"
            log_error "Expected: $expected_checksum"
            log_error "Actual:   $actual_checksum"
            return 1
        fi
        log_info "✅ Checksum verified"
    fi
    
    # Verify signature (optional but recommended)
    log_info "🔑 Verifying signature..."
    if ! wget -q "$DOWNLOAD_ASC_URL" -O "${DOWNLOAD_PATH}.asc"; then
        log_warning "⚠️  Failed to download signature file (this is not critical)"
    else
        # Import Nextcloud's public key if not already imported
        if ! gpg --list-keys "Nextcloud Security Team" &>/dev/null; then
            log_info "🔑 Importing Nextcloud's public key..."
            curl -s https://nextcloud.com/nextcloud.asc | gpg --import - || \
                log_warning "⚠️  Failed to import Nextcloud's public key"
        fi
        
        if gpg --verify "${DOWNLOAD_PATH}.asc" "$DOWNLOAD_PATH" 2>/dev/null; then
            log_info "✅ Signature verified"
        else
            log_warning "⚠️  Signature verification failed (this is not critical but recommended to check)"
        fi
    fi
    
    return 0
}

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

# Move files
# Function to install Nextcloud
install_nextcloud() {
    log_info "Extracting Nextcloud..."
    
    # Clean up any existing installation
    if [ -d "$NEXTCLOUD_ROOT" ] && [ "$(ls -A "$NEXTCLOUD_ROOT")" ]; then
        log_warning "Target directory $NEXTCLOUD_ROOT is not empty. Creating backup..."
        local backup_dir="/var/backups/nextcloud-$(date +%Y%m%d%H%M%S)"
        mkdir -p "$backup_dir"
        cp -a "$NEXTCLOUD_ROOT" "$backup_dir/"
        log_info "Backup created at $backup_dir"
        rm -rf "$NEXTCLOUD_ROOT"
    fi
    
    # Extract Nextcloud
    if ! tar -xjf "$DOWNLOAD_PATH" -C "$(dirname "$NEXTCLOUD_ROOT")"; then
        log_error "Failed to extract Nextcloud"
        return 1
    fi
    
    # Fix permissions
    log_info "Setting permissions..."
    chown -R ${NEXTCLOUD_USER}:${NEXTCLOUD_GROUP} "$NEXTCLOUD_ROOT"
    chmod -R 750 "$NEXTCLOUD_ROOT"
    chmod 750 "$NEXTCLOUD_ROOT/config"
    chmod 750 "$NEXTCLOUD_ROOT/apps"
    
    # Create data directory if it doesn't exist
    if [ ! -d "$NEXTCLOUD_DATA" ]; then
        mkdir -p "$NEXTCLOUD_DATA"
        chown -R ${NEXTCLOUD_USER}:${NEXTCLOUD_GROUP} "$NEXTCLOUD_DATA"
        chmod 750 "$NEXTCLOUD_DATA"
    fi
    
    return 0
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
