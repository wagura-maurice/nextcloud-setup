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
EOL

# Make hooks executable
chmod +x /etc/letsencrypt/renewal-hooks/pre/stop-webserver
chmod +x /etc/letsencrypt/renewal-hooks/post/start-webserver

echo "=== System Preparation Complete ==="

# Check if running as root
if [ "$(id -u)" -eq 0 ]; then
    echo "\n=== Starting Nextcloud Setup ==="
    echo "Running nextcloud-setup.sh to configure and install all required components..."
    
    # Check if nextcloud-setup.sh exists and is executable
    if [ -x "${PROJECT_ROOT}/nextcloud-setup.sh" ]; then
        # Run the setup script with the same user who owns the project directory
        sudo -u "$(stat -c '%U' "${PROJECT_ROOT}")" "${PROJECT_ROOT}/nextcloud-setup.sh"
    else
        echo "Error: nextcloud-setup.sh not found or not executable in ${PROJECT_ROOT}/"
        echo "Please ensure the file exists and has execute permissions."
        exit 1
    fi
else
    echo "\n=== Next Steps ==="
    echo "1. Install certbot: sudo apt install certbot python3-certbot-apache"
    echo "2. Obtain SSL certificate:"
    echo "   sudo certbot --apache -d cloud.e-granary.com --non-interactive --agree-tos --email support@e-granary.com"
    echo "3. Test renewal: sudo certbot renew --dry-run"
    echo "4. Run the Nextcloud setup:"
    echo "   cd ${PROJECT_ROOT} && sudo -E ./nextcloud-setup.sh"
    echo "\nNote: The setup script requires root privileges to install system packages and configure services."
fi