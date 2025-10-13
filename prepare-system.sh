#!/bin/bash
set -euo pipefail

# Get project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Create system directories
echo "Creating system directories..."
create_dir "/var/www/nextcloud" "www-data:www-data" "750"
create_dir "/var/nextcloud" "www-data:www-data" "750"
create_dir "/var/backups/nextcloud" "root:root" "750"

# Create Let's Encrypt directories (standard locations)
echo "Setting up Let's Encrypt directories..."
create_dir "/etc/letsencrypt/live" "root:root" "755"
create_dir "/etc/letsencrypt/archive" "root:root" "750"
create_dir "/etc/letsencrypt/renewal" "root:root" "750"
create_dir "/var/lib/letsencrypt" "root:root" "755"
create_dir "/var/log/letsencrypt" "root:root" "750"

# Create symlink for SSL certificates (compatible with Apache/nginx)
create_dir "/etc/ssl/cloud.e-granary.com" "root:ssl-cert" "750"
ln -sf /etc/letsencrypt/live/cloud.e-granary.com/privkey.pem /etc/ssl/cloud.e-granary.com/privkey.pem
ln -sf /etc/letsencrypt/live/cloud.e-granary.com/fullchain.pem /etc/ssl/cloud.e-granary.com/fullchain.pem

# Ensure the web server user is in the ssl-cert group
if ! id -nG www-data | grep -qw ssl-cert; then
    echo "Adding www-data to ssl-cert group..."
    usermod -aG ssl-cert www-data || echo "Warning: Failed to add www-data to ssl-cert group"
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
# Check if running as root
if [ "$(id -u)" -eq 0 ]; then
    echo "\n=== Starting Nextcloud Setup ==="
    echo "Running nextcloud-setup.sh to configure and install all required components..."
    
    # Check if the launcher exists and is executable
    if [ -x "${PROJECT_ROOT}/setup-nextcloud" ]; then
        # Run the launcher with the same user who owns the project directory
        sudo -u "$(stat -c '%U' "${PROJECT_ROOT}")" "${PROJECT_ROOT}/setup-nextcloud"
    else
        echo "Error: setup-nextcloud launcher not found or not executable in ${PROJECT_ROOT}/"
        echo "Please ensure the preparation completed successfully."
        exit 1
    fi
else
    echo "\n❌ ERROR: This script must be run as root (or with sudo)" >&2
    echo "\nThe Nextcloud installation requires root privileges to perform the following actions:"
    echo "- Install system packages and dependencies"
    echo "- Configure system services (Apache, MySQL, etc.)"
    echo "- Set up SSL certificates"
    echo "- Create and configure system users and directories"
    echo "- Apply security settings"
    echo "\nPlease run the script again with root privileges:"
    echo "  sudo ./prepare-system.sh"
    echo "\nIf you're setting up a production environment, ensure you have:"
    echo "1. A domain name pointing to this server"
    echo "2. Sufficient system resources (2GB+ RAM recommended)"
    echo "3. Backups of any existing data"
    exit 1
fi