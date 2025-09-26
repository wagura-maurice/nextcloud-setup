#!/bin/bash

# Nextcloud Installation Script for Ubuntu 22.04 LTS
# This script automates the complete installation of Nextcloud with Apache, PHP-FPM, MySQL, Redis, and SSL

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$BASE_DIR/configs"

# Load configuration
source "$CONFIG_DIR/install-config.conf" 2>/dev/null || {
    echo "Error: Missing config file at $CONFIG_DIR/install-config.conf"
    exit 1
}

echo "Starting Nextcloud installation from $BASE_DIR..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print section headers
print_section() {
    echo -e "\n\033[1;34m==> $1\033[0m"
}

# Function to print status messages
print_status() {
    echo -e "\033[1;32m[+] $1\033[0m"
}

# Function to print error messages
print_error() {
    echo -e "\e[31m[!] $1\e[0m"
}

# Function to check if a package is installed
is_package_installed() {
    dpkg -l "$1" &> /dev/null
    return $?
}

# Function to check if a service is running
is_service_running() {
    systemctl is-active --quiet "$1"
    return $?
}

# Function to check if a module is enabled in Apache
is_apache_module_enabled() {
    a2query -q -m "$1"
    return $?
}

# Function to check if a site is enabled in Apache
is_apache_site_enabled() {
    a2query -q -s "$1"
    return $?
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root. Use 'sudo $0'"
fi

# Step1: Install Required Packages
print_section "Step 1: Installing Required Packages"

# 1. Update package lists
print_status "Updating package lists..."
apt update -y

# 2. Install required packages if not already installed
print_status "Checking and installing required packages..."

# First, add PHP repository if not already added
if ! apt-cache policy | grep -q 'ondrej/php'; then
    print_status "Adding PHP repository..."
    apt install -y software-properties-common
    add-apt-repository -y ppa:ondrej/php
    apt update -y
fi

# List of required packages
REQUIRED_PACKAGES=(
    apache2 
    mariadb-server 
    unzip 
    wget 
    curl 
    git 
    redis-server 
    python3-certbot-apache
)

# PHP 8.4 specific packages
PHP_PACKAGES=(
    php8.4
    php8.4-cli
    php8.4-gd
    php8.4-common
    php8.4-mysql
    php8.4-curl
    php8.4-mbstring
    php8.4-xml
    php8.4-zip
    php8.4-intl
    php8.4-ldap
    php8.4-imagick
    php8.4-gmp
    php8.4-bcmath
    php8.4-opcache
    php8.4-redis
    php8.4-apcu
    libapache2-mod-php8.4
    php8.4-fpm
)

# Note: php8.4-json is included in the core php8.4 package

# Install base packages that are not already installed
TO_INSTALL=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! is_package_installed "$pkg"; then
        TO_INSTALL+=("$pkg")
    else
        print_status "Package already installed: $pkg"
    fi
done

if [ ${#TO_INSTALL[@]} -gt 0 ]; then
    print_status "Installing missing base packages: ${TO_INSTALL[*]}"
    apt install -y "${TO_INSTALL[@]}" || {
        print_error "Failed to install base packages. Please check your internet connection and try again."
        exit 1
    }
else
    print_status "All required base packages are already installed."
fi

# Install PHP 8.4 packages
print_status "Installing PHP 8.4 and extensions..."
apt install -y "${PHP_PACKAGES[@]}" || {
    print_error "Failed to install PHP 8.4 packages. Please check the error messages above."
    exit 1
}

# Verify PHP installation
if ! php8.4 -v &>/dev/null; then
    print_error "PHP 8.4 installation failed. Please check the error messages above."
    exit 1
else
    print_status "PHP 8.4 and extensions installed successfully."
fi

apt update -y

# 4. Configure PHP-FPM
print_status "Configuring PHP-FPM..."
PHP_FPM_SERVICE="php8.4-fpm"

# Enable and start PHP-FPM if not already running
if ! systemctl is-active --quiet $PHP_FPM_SERVICE; then
    systemctl enable $PHP_FPM_SERVICE
    systemctl start $PHP_FPM_SERVICE
    print_status "PHP-FPM service started."
else
    print_status "PHP-FPM service is already running."
fi

# Configure PHP settings
print_status "Configuring PHP 8.4 settings..."

# Create PHP configuration directory if it doesn't exist
PHP_CONF_DIR="/etc/php/8.4/fpm/conf.d"
mkdir -p "$PHP_CONF_DIR"

# Configure PHP settings
cat > "$PHP_CONF_DIR/nextcloud.ini" << 'EOL'
; File Uploads
upload_max_filesize = 64M
post_max_size = 96M

; Resource Limits
memory_limit = 512M
max_execution_time = 600
max_input_vars = 3000
max_input_time = 1000

; OPcache Settings
opcache.enable=1
opcache.enable_cli=1
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=60

; APCu configuration
apc.enable_cli=1
EOL

print_status "PHP 8.4 configuration completed."

# 4. Enable required Apache modules and restart Apache
print_status "Configuring Apache..."

# List of required Apache modules
APACHE_MODULES=(
    rewrite
    dir
    mime
    env
    headers
    ssl
    http2
)

# Enable required modules if not already enabled
MODULES_TO_ENABLE=()
for mod in "${APACHE_MODULES[@]}"; do
    if ! is_apache_module_enabled "$mod"; then
        MODULES_TO_ENABLE+=("$mod")
    else
        print_status "Apache module already enabled: $mod"
    fi
done

if [ ${#MODULES_TO_ENABLE[@]} -gt 0 ]; then
    print_status "Enabling Apache modules: ${MODULES_TO_ENABLE[*]}"
    a2enmod "${MODULES_TO_ENABLE[@]}"
    systemctl restart apache2
else
    print_status "All required Apache modules are already enabled."
fi

# Step# 2. Setup MySQL
print_status "Checking MySQL installation..."

# Default credentials
MYSQL_ROOT_PASS="Qwerty123!"
DB_PASSWORD="passw@rd"
DB_NAME="nextcloud"
DB_USER="nextcloud"

# Check if MySQL/MariaDB is already installed
if ! command -v mysql &> /dev/null; then
    print_status "MySQL/MariaDB not found. Installing..."
    
    # Set debconf selections for unattended installation
    echo "mariadb-server mysql-server/root_password password $MYSQL_ROOT_PASS" | debconf-set-selections
    echo "mariadb-server mysql-server/root_password_again password $MYSQL_ROOT_PASS" | debconf-set-selections
    
    # Install MariaDB Server
    apt-get install -y mariadb-server
    
    # Start and enable MariaDB service
    systemctl start mariadb
    systemctl enable mariadb
    
    # Wait for MariaDB to be fully up
    sleep 5
    
    # Run mysql_secure_installation
    print_status "Securing MySQL installation..."
    mysql -u root -p"$MYSQL_ROOT_PASS" <<-EOF
        DELETE FROM mysql.user WHERE User='';
        DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
        DROP DATABASE IF EXISTS test;
        DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
        FLUSH PRIVILEGES;
EOF
else
    print_status "MySQL/MariaDB is already installed."
    
    # Check if we can connect with default root password
    if ! mysql -u root -p"$MYSQL_ROOT_PASS" -e "SELECT 1" &>/dev/null; then
        print_status "Could not connect with default root password. Please enter MySQL root password:"
        read -s MYSQL_ROOT_PASS
        
        # Test the provided password
        if ! mysql -u root -p"$MYSQL_ROOT_PASS" -e "SELECT 1" &>/dev/null; then
            print_error "Failed to connect to MySQL. Please check your root password and try again."
            exit 1
        fi
    fi
fi

# Check if database exists
if ! mysql -u root -p"$MYSQL_ROOT_PASS" -e "USE $DB_NAME" &>/dev/null; then
    print_status "Creating database $DB_NAME..."
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
else
    print_status "Database $DB_NAME already exists."
fi

# Check if user exists
if ! mysql -u root -p"$MYSQL_ROOT_PASS" -e "SELECT 1 FROM mysql.user WHERE user = '$DB_USER'" | grep -q 1; then
    print_status "Creating MySQL user $DB_USER..."
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "FLUSH PRIVILEGES;"
else
    print_status "MySQL user $DB_USER already exists. Updating password..."
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "FLUSH PRIVILEGES;"
fi

# Store MySQL credentials securely
print_status "Storing MySQL credentials securely..."
cat > /root/.nextcloud_db_credentials << EOL
# MySQL Root Credentials
MYSQL_ROOT_USER=root
MYSQL_ROOT_PASS=$MYSQL_ROOT_PASS

# Nextcloud Database Credentials
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASSWORD
EOL
chmod 600 /root/.nextcloud_db_credentials

# Function to check MySQL connection
check_mysql_connection() {
    mysql -u "$1" -p"$2" -e "SELECT 1" &>/dev/null
    return $?
}

# Function to execute MySQL command with proper credentials
execute_mysql() {
    if [ "$1" == "root" ]; then
        mysql -u root -p"$MYSQL_ROOT_PASS" -e "$2"
    else
        mysql -u "$DB_USER" -p"$DB_PASSWORD" -e "$2"
    fi
}

# Check if MySQL is installed
if ! command -v mysql &> /dev/null; then
    print_status "MySQL not found. Installing MySQL..."
    
    # Set debconf selections for unattended installation
    echo "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASS" | debconf-set-selections
    echo "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASS" | debconf-set-selections
    
    # Install MySQL Server
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y mysql-server
    
    # Start and enable MySQL service
    systemctl start mysql
    systemctl enable mysql
    
    # Wait for MySQL to be fully up
    sleep 5
    
    # Basic security setup
    print_status "Performing initial MySQL security setup..."
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "
        DELETE FROM mysql.user WHERE User='';
        DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
        DROP DATABASE IF EXISTS test;
        DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
        FLUSH PRIVILEGES;"
else
    print_status "MySQL is already installed."
    
    # Check if we can connect with default root password
    if ! check_mysql_connection "root" "$MYSQL_ROOT_PASS"; then
        print_status "Could not connect with default root password. Please enter MySQL root password:"
        read -s MYSQL_ROOT_PASS
        
        # Test the provided password
        if ! check_mysql_connection "root" "$MYSQL_ROOT_PASS"; then
            print_error "Failed to connect to MySQL. Please check your root password and try again."
            exit 1
        fi
    fi
fi

# Ensure the nextcloud database exists
print_status "Setting up Nextcloud database..."
mysql -u root -p"$MYSQL_ROOT_PASS" -e "
    CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"

# Check if nextcloud user exists and update or create it
print_status "Configuring Nextcloud database user..."
USER_EXISTS=$(mysql -u root -p"$MYSQL_ROOT_PASS" -sN -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE User = '$DB_USER' AND Host = 'localhost');")

if [ "$USER_EXISTS" -eq 1 ]; then
    print_status "Updating existing Nextcloud user password..."
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "
        ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
        FLUSH PRIVILEGES;"
else
    print_status "Creating Nextcloud database user..."
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "
        CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
        FLUSH PRIVILEGES;"
fi

# Grant necessary privileges (not all privileges)
print_status "Setting up database permissions..."
mysql -u root -p"$MYSQL_ROOT_PASS" -e "
    GRANT CREATE, ALTER, DROP, INSERT, UPDATE, DELETE, SELECT, INDEX, REFERENCES 
    ON $DB_NAME.* TO '$DB_USER'@'localhost';
    FLUSH PRIVILEGES;"

# Store MySQL root password securely
cat > /root/.mysql_credentials << EOL
# MySQL Root Credentials
MYSQL_ROOT_USER=root
MYSQL_ROOT_PASS=$MYSQL_ROOT_PASS

# Nextcloud Database Credentials
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASSWORD
EOL
chmod 600 /root/.mysql_credentials

# Create database and user with secure password
print_status "Creating database and user..."

# Function to check if database exists
database_exists() {
    local dbname=$1
    local result=$(mysql -u root -p"${MYSQL_ROOT_PASS}" -sN -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${dbname}';")
    if [ "$result" == "$dbname" ]; then
        return 0 # exists
    else
        return 1 # doesn't exist
    fi
}

# Create database if it doesn't exist
if ! database_exists "nextcloud"; then
    print_status "Creating database 'nextcloud'..."
    mysql -u root -p"${MYSQL_ROOT_PASS}" -e "CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    if [ $? -ne 0 ]; then
        print_error "Failed to create database 'nextcloud'"
        exit 1
    fi
    print_status "Database 'nextcloud' created successfully."
else
    print_status "Database 'nextcloud' already exists."
fi

# Create user and grant privileges
print_status "Creating database user and setting permissions..."
mysql -u root -p"${MYSQL_ROOT_PASS}" -e "
    CREATE USER IF NOT EXISTS 'nextcloud'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
    GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';
    FLUSH PRIVILEGES;"

if [ $? -ne 0 ]; then
    print_error "Failed to create database user or set permissions"
    exit 1
fi

# Store the database credentials securely
print_status "Storing database credentials..."
cat > /root/.nextcloud_db_credentials << EOL
# Nextcloud Database Credentials
DB_NAME=nextcloud
DB_USER=nextcloud
DB_PASS=${DB_PASSWORD}
EOL
chmod 600 /root/.nextcloud_db_credentials

# Step3. Download and Install Nextcloud
print_section "Step 3: Downloading and Installing Nextcloud"

# 1. Check if Nextcloud is already installed, if not download and extract
print_status "Checking Nextcloud installation..."
cd /var/www/
if [ ! -d "nextcloud" ]; then
    if [ ! -f "latest.zip" ]; then
        print_status "Downloading Nextcloud..."
        wget -q https://download.nextcloud.com/server/releases/latest.zip
    fi
    print_status "Extracting Nextcloud..."
    unzip -q latest.zip
    rm -f latest.zip
else
    print_status "Nextcloud is already installed at /var/www/nextcloud"
fi

# 2. Set proper permissions
print_status "Setting permissions..."
chown -R www-data:www-data /var/www/nextcloud/

# Step4. Install NextCloud From the Command Line
print_section "Step 4: Installing Nextcloud"

# 1. Run the CLI Command
print_status "Preparing Nextcloud installation..."

# Check if Nextcloud is already installed
if [ ! -f "/var/www/nextcloud/config/config.php" ]; then
    print_status "Running Nextcloud installation..."
    
    # Source the database credentials
    if [ -f "/root/.nextcloud_db_credentials" ]; then
        source /root/.nextcloud_db_credentials
    else
        print_error "Database credentials file not found. Cannot proceed with installation."
        exit 1
    fi
    
    # Run the install command with all required parameters
    if ! sudo -u www-data php /var/www/nextcloud/occ maintenance:install \
        --database "mysql" \
        --database-host "127.0.0.1" \
        --database-name "${DB_NAME}" \
        --database-user "${DB_USER}" \
        --database-pass "${DB_PASS}" \
        --admin-user "admin" \
        --admin-pass "admin123"; then
        print_error "Failed to install Nextcloud. Please check the error messages above."
        exit 1
    fi
    
    print_status "Nextcloud installed successfully!"
    
    # Additional security hardening
    print_status "Applying security settings..."
    sudo -u www-data php /var/www/nextcloud/occ config:system:set trusted_domains 1 --value="$(hostname -f)"
    sudo -u www-data php /var/www/nextcloud/occ config:system:set trusted_domains 2 --value="data.amarissolutions.com"
    sudo -u www-data php /var/www/nextcloud/occ config:system:set default_phone_region --value="KE"
    sudo -u www-data php /var/www/nextcloud/occ config:system:set default_timezone --value="Africa/Nairobi"
    
    # Enable APCu if available
    print_status "Configuring APCu..."
    if php -m | grep -q apcu; then
        sudo -u www-data php /var/www/nextcloud/occ config:system:set memcache.local --value="\\OC\\Memcache\\APCu"
        print_status "APCu enabled and configured for local caching."
    else
        print_status "APCu extension not found. Local caching will use file-based cache."
    fi
    
    print_status "Security settings applied successfully!"
else
    print_status "Nextcloud is already installed. Skipping installation."
fi

print_status "Trusted domains configuration complete."

# Step5. Install and Configure PHP-FPM with Apache
print_section "Step 5: Configuring PHP-FPM"

# 1. Install php-fpm
print_status "Installing PHP 8.4 FPM..."
apt install -y php8.4-fpm

# 2. Configure Apache to use PHP-FPM
print_status "Configuring Apache to use PHP 8.4 FPM..."
a2dismod php8.4 mpm_prefork
a2enmod mpm_event proxy_fcgi setenvif
a2enconf php8.4-fpm

# 3. Set required php.ini variables
print_status "Configuring PHP 8.4 settings..."
cat > /etc/php/8.4/fpm/conf.d/nextcloud.ini << 'EOL'
; File Uploads
upload_max_filesize = 64M
post_max_size = 96M

; Resource Limits
memory_limit = 512M
max_execution_time = 600
max_input_vars = 3000
max_input_time = 1000

; OPcache Settings
opcache.enable=1
opcache.enable_cli=1
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=60

; Disable deprecated mbstring functions
; These are now handled in the main php.ini file

; APCu configuration
apc.enable_cli=1

; SQLite3 configuration
; Check if SQLite3 is already loaded before loading it again
; This prevents the 'Module already loaded' warning
; extension=sqlite3.so
EOL

# 4. php-fpm pool Configurations
echo "Configuring PHP-FPM pools..."
sudo sed -i \
-e 's/^pm.max_children.*/pm.max_children = 64/' \
-e 's/^pm.start_servers.*/pm.start_servers = 16/' \
-e 's/^pm.min_spare_servers.*/pm.min_spare_servers = 16/' \
-e 's/^pm.max_spare_servers.*/pm.max_spare_servers = 32/' \
/etc/php/8.4/fpm/pool.d/www.conf && \
sudo systemctl restart php8.4-fpm

# 5. Apache directives for php files processing by PHP-FPM
echo "Configuring Apache for PHP-FPM..."
sudo tee /etc/apache2/sites-enabled/000-default.conf > /dev/null <<'EOF'
<VirtualHost *:80>

    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/nextcloud

    <Directory /var/www/nextcloud>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch "\.php$">
        SetHandler "proxy:unix:/var/run/php/php8.4-fpm.sock|fcgi://localhost/"
    </FilesMatch>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined

</VirtualHost>
EOF

# Restart php-fpm and Apache Server
echo "Restarting services..."
sudo service php8.4-fpm restart
sudo systemctl restart apache2

# Step6. Configure Redis for Caching
print_section "Step 6: Configuring Redis"

# 1. Install Redis Server and PHP extension
print_status "Installing Redis server and PHP extension..."
apt install -y redis-server php-redis

# 2. Configure Redis
print_status "Configuring Redis..."
cat > /etc/redis/redis.conf << 'EOL'
daemonize yes
pidfile /var/run/redis/redis-server.pid
port 0
unixsocket /var/run/redis/redis.sock
unixsocketperm 770
timeout 0
tcp-keepalive 300
databases 16
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis
maxmemory 256mb
maxmemory-policy allkeys-lru
appendonly yes
appendfilename "appendonly.aof"
no-appendfsync-on-rewrite no
EOL

# Set proper permissions
usermod -a -G redis www-data
chown -R redis:redis /var/lib/redis
chmod 755 /var/lib/redis

# Restart Redis
systemctl restart redis-server

# 3. Configure SSL with Let's Encrypt
print_section "Configuring SSL"

# Function to check if certificate is valid (not expired and matches domain)
check_ssl_certificate() {
    local domain=$1
    local cert_file="/etc/letsencrypt/live/${domain}/fullchain.pem"
    
    # Check if certificate exists
    if [ ! -f "$cert_file" ]; then
        return 1
    fi
    
    # Check if certificate is valid for at least 30 more days
    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry_date" "+%s" 2>/dev/null)
    local now_epoch=$(date +%s)
    
    # If we couldn't parse the date, assume the certificate is invalid
    if [ -z "$expiry_epoch" ]; then
        return 1
    fi
    
    local days_until_expiry=$(( (expiry_epoch - now_epoch) / 86400 ))
    
    if [ $days_until_expiry -lt 30 ]; then
        print_status "SSL certificate expires in $days_until_expiry days. Will renew."
        return 1
    fi
    
    # Check if certificate is for the correct domain
    local cert_domains=$(openssl x509 -in "$cert_file" -text -noout | grep -o 'DNS:[^, ]*' | sed 's/DNS://g' | tr '\n' ' ')
    if [[ " $cert_domains " != *" $domain "* ]]; then
        print_status "Existing SSL certificate is not for domain: $domain"
        return 1
    fi
    
    print_status "Valid SSL certificate found for $domain (expires in $days_until_expiry days)"
    return 0
}

# Check for existing valid certificate
if check_ssl_certificate "$DOMAIN_NAME"; then
    print_status "Using existing valid SSL certificate for $DOMAIN_NAME"
else
    # Install Certbot if not already installed
    if ! command -v certbot &> /dev/null; then
        print_status "Installing Certbot..."
        apt install -y python3-certbot-apache
    fi
    
    # Obtain new SSL certificate
    print_status "Obtaining new SSL certificate for $DOMAIN_NAME..."
    if certbot --apache --non-interactive --agree-tos --email "$SSL_EMAIL" -d "$DOMAIN_NAME" --redirect; then
        print_status "Successfully obtained new SSL certificate"
    else
        print_error "Failed to obtain SSL certificate. Generating self-signed certificate..."
        
        # Create directory for self-signed certificate if it doesn't exist
        mkdir -p /etc/ssl/private /etc/ssl/certs
        
        # Generate self-signed certificate
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/ssl/private/nextcloud-selfsigned.key \
            -out /etc/ssl/certs/nextcloud-selfsigned.crt \
            -subj "/CN=$DOMAIN_NAME"
        
        # Configure Apache to use self-signed certificate
        cat > /etc/apache2/sites-available/nextcloud-ssl.conf << EOL
<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerName $DOMAIN_NAME
        DocumentRoot /var/www/nextcloud/
        
        SSLEngine on
        SSLCertificateFile /etc/ssl/certs/nextcloud-selfsigned.crt
        SSLCertificateKeyFile /etc/ssl/private/nextcloud-selfsigned.key
        
        # Enable HTTP/2
        Protocols h2 h2c http/1.1
        
        # Security headers
        Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains; preload"
        
        # Other SSL settings
        SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
        SSLProtocol -all +TLSv1.2 +TLSv1.3
        SSLHonorCipherOrder off
        SSLCompression off
        
        # Rest of your Apache configuration
        <Directory /var/www/nextcloud/>
            Options Indexes FollowSymLinks
            AllowOverride All
            Require all granted
        </Directory>
        
        <FilesMatch "\\.php$\">
            SetHandler "proxy:unix:/var/run/php/php8.4-fpm.sock|fcgi://localhost/"
        </FilesMatch>
        
        ErrorLog \${APACHE_LOG_DIR}/error.log
        CustomLog \${APACHE_LOG_DIR}/access.log combined
    </VirtualHost>
</IfModule>
EOL
        
        # Enable required modules and the new site
        a2enmod ssl
        a2ensite nextcloud-ssl
    fi
fi

# Enable HTTP/2
print_status "Enabling HTTP/2..."
a2enmod http2 headers

# Update the SSL configuration file that was created by Certbot
SSL_CONF_FILE="/etc/apache2/sites-available/000-default-le-ssl.conf"
if [ -f "$SSL_CONF_FILE" ]; then
    print_status "Updating SSL configuration..."
    # Enable HTTP/2
    sed -i 's/Protocols h2 http\/1.1/Protocols h2 h2c http\/1.1/' "$SSL_CONF_FILE"
    
    # Add HSTS header if not present
    if ! grep -q "Strict-Transport-Security" "$SSL_CONF_FILE"; then
        sed -i '/^<\/VirtualHost>/i \    Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains; preload"' "$SSL_CONF_FILE"
    fi
    
    # Restart Apache to apply changes
    systemctl restart apache2
fi

# 4. Configure Redis for Nextcloud
print_status "Configuring Redis for Nextcloud..."
if [ -f "/var/www/nextcloud/config/config.php" ]; then
    if ! grep -q "'memcache.local'" /var/www/nextcloud/config/config.php; then
        # Create a temporary file for the Redis configuration
        REDIS_CONFIG="$(mktemp)"
        cat > "$REDIS_CONFIG" << 'REDIS_EOF'
  'memcache.local' => '\OC\Memcache\Redis',
  'memcache.distributed' => '\OC\Memcache\Redis',
  'redis' => [
    'host' => '/var/run/redis/redis.sock',
    'port' => 0,
    'dbindex' => 0,
    'password' => '',
    'timeout' => 1.5,
  ],
REDIS_EOF
        
        # Insert the Redis configuration before the closing );
        sed -i "/);/ {
            x
            r $REDIS_CONFIG
            x
        }" /var/www/nextcloud/config/config.php
        
        # Clean up the temporary file
        rm -f "$REDIS_CONFIG"
    fi
else
    print_error "Nextcloud config.php not found at /var/www/nextcloud/config/config.php"
fi

# 4. Enable Redis session locking
print_status "Enabling Redis session locking..."
cat > /etc/php/8.4/fpm/conf.d/20-redis-session.ini << 'EOL'
session.save_handler = redis
session.save_path = "unix:///var/run/redis/redis.sock?persistent=1&weight=1&database=0"
redis.session.locking_enabled = 1
redis.session.lock_retries = -1
redis.session.lock_wait_time = 10000
EOL

print_status "Configuring SSL parameters..."
cat > /etc/apache2/conf-available/ssl-params.conf << 'EOL'
SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
SSLProtocol -all +TLSv1.2 +TLSv1.3
SSLHonorCipherOrder off
SSLSessionTickets off

# OCSP Stapling
SSLUseStapling on
SSLStaplingCache "shmcb:logs/ssl_stapling(32768)"

# HSTS (mod_headers is required) (15768000 seconds = 6 months)
Header always set Strict-Transport-Security "max-age=15768000; includeSubDomains; preload"
EOL

a2enconf ssl-params

# Restart Apache
print_status "Restarting Apache..."
systemctl restart apache2

# Step8. Configure Nextcloud Settings
print_status "Configuring Nextcloud settings..."

# Check database schema
print_status "Checking database schema..."
fi

# Set trusted domains
print_status "Setting trusted domains..."
CURRENT_DOMAIN=$(hostname -f)
sudo -u www-data php /var/www/nextcloud/occ config:system:set trusted_domains 1 --value="${CURRENT_DOMAIN}"
sudo -u www-data php /var/www/nextcloud/occ config:system:set trusted_domains 2 --value="data.amarissolutions.com"

# Enable pretty URLs
print_status "Enabling pretty URLs..."
sudo -u www-data php /var/www/nextcloud/occ config:system:set htaccess.RewriteBase --value="/"

# Update .htaccess file
print_status "Updating .htaccess file..."
sudo -u www-data php /var/www/nextcloud/occ maintenance:update:htaccess

# Set proper permissions
print_status "Setting proper permissions..."
chown -R www-data:www-data /var/www/nextcloud/
chmod -R 755 /var/www/nextcloud/

sudo apt-get install -y php8.4-sqlite3
sudo systemctl restart apache2

# Run database maintenance
print_status "Running database maintenance..."
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-columns
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-primary-keys
sudo -u www-data php /var/www/nextcloud/occ db:convert-filecache-bigint
sudo -u www-data php /var/www/nextcloud/occ db:convert-filecache-bigint
sudo -u www-data php /var/www/nextcloud/occ maintenance:repair --include-expensive
sudo -u www-data php /var/www/nextcloud/occ status

sudo -u www-data php /var/www/nextcloud/occ integrity:check-core
sudo -u www-data php /var/www/nextcloud/occ maintenance:data-fingerprint

cp -r /var/www/nextcloud/config /root/nextcloud-config-backup
cp -r /var/www/nextcloud/data /root/nextcloud-data-backup

sudo -u www-data php /var/www/nextcloud/occ upgrade
sudo -u www-data php /var/www/nextcloud/occ maintenance:data-fingerprint

sudo apt update
sudo apt install -y libmagickcore-6.q16-6-extra librsvg2-bin
sudo apt install -y php8.4-imagick
sudo systemctl restart php8.4-fpm
sudo systemctl restart apache2

sudo -u www-data php /var/www/nextcloud/occ maintenance:repair