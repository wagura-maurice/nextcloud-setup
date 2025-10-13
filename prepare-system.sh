#!/bin/bash
set -euo pipefail

# Get project root (resolves symlinks if any)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR" && pwd)"

# Ensure we're running from the project root
cd "$PROJECT_ROOT" || {
    echo "❌ ERROR: Failed to change to project root directory" >&2
    exit 1
}

# Verify this is the correct directory
if [ ! -f "prepare-system.sh" ] || [ ! -d "src" ]; then
    echo "❌ ERROR: This script must be run from the project root directory" >&2
    echo "Current directory: $PWD" >&2
    echo "Expected to find: prepare-system.sh and src/ directory" >&2
    exit 1
fi
LOG_DIR="${PROJECT_ROOT}/logs"
CONFIG_DIR="${PROJECT_ROOT}/config"
DATA_DIR="${PROJECT_ROOT}/data"

# Set up logging
mkdir -p "$LOG_DIR"
chmod 750 "$LOG_DIR"
LOG_FILE="${LOG_DIR}/prepare-$(date +%Y%m%d%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Starting System Preparation ==="
echo "Project Root: $PROJECT_ROOT"
echo "Log file: $LOG_FILE"

# Function to create directory with proper permissions
create_dir() {
    local dir="$1"
    local owner="${2:-www-data:www-data}"
    local perms="${3:-750}"
    
    echo "Creating directory: $dir"
    mkdir -p "$dir"
    chown "$owner" "$dir"
    chmod "$perms" "$dir"
}

# Create project directories
echo "Creating project directories..."
create_dir "$LOG_DIR" "$(whoami):www-data" "770"
create_dir "$CONFIG_DIR" "$(whoami):www-data" "770"
create_dir "$DATA_DIR" "www-data:www-data" "750"

# Create .env file from .env.example if it doesn't exist
if [ ! -f "${PROJECT_ROOT}/.env" ]; then
    if [ -f "${PROJECT_ROOT}/.env.example" ]; then
        echo "Creating .env file from .env.example..."
        cp "${PROJECT_ROOT}/.env.example" "${PROJECT_ROOT}/.env"
        chmod 640 "${PROJECT_ROOT}/.env"
        chown "$(whoami):www-data" "${PROJECT_ROOT}/.env"
    else
        echo "Warning: .env.example not found. Please create a .env file manually."
    fi
fi

# Create system directories (relative to project root by default)
echo "Creating system directories..."

# Create project-specific system directories under /var
create_dir "/var/www/nextcloud" "www-data:www-data" "750"
create_dir "/var/nextcloud" "www-data:www-data" "750"
create_dir "/var/backups/nextcloud" "root:root" "750"

# Set up Let's Encrypt directories if they don't exist
echo "Setting up Let's Encrypt directories..."
for dir in \
    "/etc/letsencrypt/live" \
    "/etc/letsencrypt/archive" \
    "/etc/letsencrypt/renewal" \
    "/var/lib/letsencrypt" \
    "/var/log/letsencrypt"
do
    if [ ! -d "$dir" ]; then
        echo "Creating Let's Encrypt directory: $dir"
        mkdir -p "$dir"
        chmod 750 "$dir"
        chown root:root "$dir"
    fi
done

# Create SSL certificate directory with proper permissions
SSL_CERT_DIR="/etc/ssl/cloud.e-granary.com"
if [ ! -d "$SSL_CERT_DIR" ]; then
    echo "Creating SSL certificate directory: $SSL_CERT_DIR"
    mkdir -p "$SSL_CERT_DIR"
    chmod 750 "$SSL_CERT_DIR"
    chown root:ssl-cert "$SSL_CERT_DIR" || {
        echo "⚠️  Warning: Could not set group to ssl-cert for $SSL_CERT_DIR"
        echo "   The ssl-cert group might not exist. Creating it..."
        if ! getent group ssl-cert >/dev/null; then
            groupadd ssl-cert || echo "⚠️  Could not create ssl-cert group"
        fi
        chown root:ssl-cert "$SSL_CERT_DIR" 2>/dev/null || true
    }
fi

# Create symlinks for SSL certificates
for cert in privkey.pem fullchain.pem; do
    if [ ! -e "$SSL_CERT_DIR/$cert" ]; then
        ln -sf "/etc/letsencrypt/live/cloud.e-granary.com/$cert" "$SSL_CERT_DIR/$cert" || \
            echo "⚠️  Could not create symlink for $cert"
    fi
done

# Ensure the web server user is in the ssl-cert group
if ! getent group ssl-cert >/dev/null; then
    echo "Creating ssl-cert group..."
    groupadd ssl-cert 2>/dev/null || echo "⚠️  Could not create ssl-cert group"
fi

if ! id -nG www-data 2>/dev/null | grep -qw ssl-cert; then
    echo "Adding www-data to ssl-cert group..."
    usermod -aG ssl-cert www-data 2>/dev/null || \
        echo "⚠️  Warning: Failed to add www-data to ssl-cert group"
fi

# Set up certbot auto-renewal
echo "Setting up certbot renewal..."
create_dir "/etc/letsencrypt/renewal-hooks" "root:root" "755"
create_dir "/etc/letsencrypt/renewal-hooks/deploy" "root:root" "755"
create_dir "/etc/letsencrypt/renewal-hooks/post" "root:root" "755"
create_dir "/etc/letsencrypt/renewal-hooks/pre" "root:root" "755"

# Create a pre-hook to stop web server before renewal
cat > /etc/letsencrypt/renewal-hooks/pre/stop-webserver << 'EOL'
#!/bin/sh
systemctl stop apache2
EOL

# Create a post-hook to restart web server after renewal
cat > /etc/letsencrypt/renewal-hooks/post/start-webserver << 'EOL'
#!/bin/sh
systemctl start apache2
EOL

# Make hooks executable
chmod +x /etc/letsencrypt/renewal-hooks/pre/stop-webserver
chmod +x /etc/letsencrypt/renewal-hooks/post/start-webserver

# Ensure setup-nextcloud.sh is executable when cloned
echo "Setting up Nextcloud setup script..."
if [ -f "${PROJECT_ROOT}/src/bin/setup-nextcloud.sh" ]; then
    # Make the script executable
    chmod +x "${PROJECT_ROOT}/src/bin/setup-nextcloud.sh"
    
    # Create a launcher script in the project root for setup
    cat > "${PROJECT_ROOT}/setup-nextcloud" << 'EOL'
#!/bin/bash
# Launcher script for nextcloud-setup
# This file is auto-generated - do not edit directly

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Execute the main setup script with the correct working directory
(cd "$SCRIPT_DIR" && ./src/bin/setup-nextcloud.sh "$@")
EOL
    
    # Make the setup launcher executable
    chmod +x "${PROJECT_ROOT}/setup-nextcloud"
    
    # Ensure manage-nextcloud.sh is executable
    chmod +x "${PROJECT_ROOT}/src/bin/manage-nextcloud.sh"
    
    # Create a launcher script for management
    cat > "${PROJECT_ROOT}/manage-nextcloud" << 'EOL'
#!/bin/bash
# Launcher script for nextcloud-management
# This file is auto-generated - do not edit directly

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Execute the management script with the correct working directory
(cd "$SCRIPT_DIR" && ./src/bin/manage-nextcloud.sh "$@")
EOL
    
    # Make the management launcher executable
    chmod +x "${PROJECT_ROOT}/manage-nextcloud"
    
    echo "Nextcloud setup is ready to use. Run the following commands:"
    echo "  ./setup-nextcloud        # Run the setup"
    echo "  ./manage-nextcloud       # Manage your installation"
else
    echo "Warning: setup-nextcloud.sh not found in ${PROJECT_ROOT}/src/bin/"
fi

echo "=== System Preparation Complete ==="
# Final message
echo "\n✅ System preparation completed successfully!"
echo "\nNext steps:"
echo "1. Configure your domain in the .env file"
echo "2. Run the setup script:"
echo "   sudo -E ./setup-nextcloud"
echo "\nFor production use, ensure you have:"
echo "- A domain name pointing to this server"
echo "- Sufficient system resources (2GB+ RAM recommended)"
echo "- Backups of any existing data"

exit 0