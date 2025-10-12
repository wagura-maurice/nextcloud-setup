# install-nextcloud-on-ubuntu-22-04-lts.sh

# Step1: Install Required Packages

    # 1. Update and Upgrade the Ubuntu Packages

    sudo apt update -y && sudo apt upgrade -y

    # 2. install Apache and MySQL Server

    sudo apt install apache2 mariadb-server -y

    # 3. Install PHP and other Dependencies and Restart Apache

    sudo apt install -y libapache2-mod-php8.4 php8.4 php8.4-bz2 php8.4-gd php8.4-mysql php8.4-curl php8.4-zip php8.4-mbstring php8.4-imagick php8.4-bcmath php8.4-xml php8.4-intl php8.4-gmp zip unzip wget
    sudo apt install php8.4 php8.4-apcu php8.4-bcmath php8.4-cli php8.4-common php8.4-curl php8.4-gd php8.4-gmp php8.4-imagick php8.4-intl php8.4-mbstring php8.4-mysql php8.4-zip php8.4-xml -y

    # 4. Enable required Apache modules and restart Apache:

    sudo a2enmod rewrite dir mime env headers
    sudo systemctl restart apache2

    # sudo phpenmod bcmath gmp imagick intl

# Step2. Configure MySQL Server

    # 1. Login to MySQL Prompt, Just type mysql

    sudo mysql

    # 2. Create MySQL Database and User for Nextcloud and Provide Permissions.

    CREATE USER ‘nextcloud’@’localhost’ IDENTIFIED BY ‘passw@rd’;
    CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
    GRANT ALL PRIVILEGES ON nextcloud.* TO ‘nextcloud’@’localhost’;
    FLUSH PRIVILEGES;
    quit;

# Step3. Download, Extract, and Apply Permissions.

    # 1. Download and unzip in the /var/www folder
    sudo apt install wget unzip -y

    cd /var/www/
    wget https://download.nextcloud.com/server/releases/latest.zip
    unzip latest.zip

    # 2. Remove the zip file, which is not necessary now.

    rm -rf latest.zip

    # 3. Change the ownership of the nextcloud content directory to the HTTP user.

    sudo chown -R www-data:www-data /var/www/nextcloud/

# Step4. Install NextCloud From the Command Line

    # 1. Run the CLI Command

    sudo -u www-data php occ maintenance:install --database "mysql" --database-host "127.0.0.1" --database-name "nextcloud" --database-user "nextcloud" --database-pass "passw@rd" --admin-user "admin" --admin-pass "admin123"

    # 2. nextcloud allows access only from localhost, it could through error “Access through untrusted domain”. we need to allow accessing nextcloud by using ip or domain name.

    sudo mkdir -p /var/www/nextcloud/config && \
    sudo bash -c 'grep -q "trusted_domains" /var/www/nextcloud/config/config.php 2>/dev/null || echo -e "<?php\n\n\$CONFIG = array ();" > /var/www/nextcloud/config/config.php && \
    sed -i "/'trusted_domains' =>/{
    n
    a\    1 => 'data.amarissolutions.com',
    }" /var/www/nextcloud/config/config.php'

    # 3. Configure Apache to load Nextcloud from the /var/www/nextcloud folder.
    
    sudo bash -c 'cat > /etc/apache2/sites-enabled/000-default.conf <<EOF
    <VirtualHost *:80>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/nextcloud
        ErrorLog \${APACHE_LOG_DIR}/error.log
        CustomLog \${APACHE_LOG_DIR}/access.log combined
    </VirtualHost>
    EOF'

    # Now, Restart Apache Server

    sudo systemctl restart apache2

# Step5. Install and Configure PHP-FPM with Apache

    # 1. Install php-fpm

    sudo apt install php8.4-fpm
    sudo service php8.4-fpm status

    # 2. Check the php-fpm version and Socket.

    php-fpm8.4 -v
    ls -la /var/run/php/php8.4-fpm.sock

    # 3. Disable Apache prefork module

    sudo a2dismod php8.4
    sudo a2dismod mpm_prefork

    # 4. Enable php-fpm

    sudo a2enmod mpm_event proxy_fcgi setenvif
    sudo a2enconf php8.4-fpm

    # 5. set required php.ini variables

    sudo tee -a /etc/php/8.4/fpm/php.ini > /dev/null <<'EOF'
    upload_max_filesize = 64M
    post_max_size = 96M
    memory_limit = 512M
    max_execution_time = 600
    max_input_vars = 3000
    max_input_time = 1000
    EOF

    # 6. php-fpm pool Configurations

    sudo sed -i \
    -e 's/^pm.max_children.*/pm.max_children = 64/' \
    -e 's/^pm.start_servers.*/pm.start_servers = 16/' \
    -e 's/^pm.min_spare_servers.*/pm.min_spare_servers = 16/' \
    -e 's/^pm.max_spare_servers.*/pm.max_spare_servers = 32/' \
    /etc/php/8.4/fpm/pool.d/www.conf && \
    sudo systemctl restart php8.4-fpm

    # 7. Apache directives for php files processing by PHP-FPM

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

    # Now, Restart php-fpm and Apache Server

    sudo service php8.4-fpm restart
    sudo systemctl restart apache2

# Step6. Enable Opcache and APCu in php

    # 1. Enable opcache extension in php.ini file

    sudo sed -i \
    -e 's/^opcache.enable\s*=.*/opcache.enable=1/' \
    -e 's/^opcache.enable_cli\s*=.*/opcache.enable_cli=1/' \
    -e 's/^opcache.interned_strings_buffer\s*=.*/opcache.interned_strings_buffer=16/' \
    -e 's/^opcache.max_accelerated_files\s*=.*/opcache.max_accelerated_files=10000/' \
    -e 's/^opcache.memory_consumption\s*=.*/opcache.memory_consumption=128/' \
    -e 's/^opcache.save_comments\s*=.*/opcache.save_comments=1/' \
    -e 's/^opcache.revalidate_freq\s*=.*/opcache.revalidate_freq=60/' \
    /etc/php/8.4/fpm/php.ini && \
    sudo systemctl restart php8.4-fpm

    # 2. Install APCu
    
    sudo apt install php8.4-apcu

    # 3. Configure Nextcloud to use APCu for memory caching.

    sudo grep -q "'memcache.local'" /var/www/nextcloud/config/config.php || \
    sudo sed -i "/'trusted_domains' =>/a\  'memcache.local' => '\\\OC\\\Memcache\\\APCu'," /var/www/nextcloud/config/config.php

    # Now, Restart php-fpm and Apache Server

    sudo service php8.4-fpm restart
    sudo systemctl restart apache2

# Step7. Install and Configure Redis

    # 1. Install Redis Server and Redis php extension

    sudo apt-get install redis-server php-redis

    # 2. Start and Enable Redis

    sudo systemctl start redis-server
    sudo systemctl enable redis-server

    # 3. Configure Redis to use Unix Socket than ports

    sudo sed -i \
    -e 's/^port .*/port 0/' \
    -e '/^unixsocket /d' \
    -e '/^unixsocketperm /d' \
    /etc/redis/redis.conf && \
    echo -e "unixsocket /var/run/redis/redis.sock\nunixsocketperm 770" | sudo tee -a /etc/redis/redis.conf > /dev/null && \
    sudo systemctl restart redis-server

    # 4. Add Apache user to the Redis group

    sudo usermod -a -G redis www-data

    # 5. Configure Nextcloud for using Redis for File Locking

    sudo sed -i "/);/i\  'filelocking.enabled' => true,\n  'memcache.locking' => '\\\OC\\\Memcache\\\Redis',\n  'redis' => [\n    'host' => '/var/run/redis/redis.sock',\n    'port' => 0,\n    'dbindex' => 0,\n    'password' => '',\n    'timeout' => 1.5,\n  ]," /var/www/nextcloud/config/config.php

    # 6. Enable Redis session locking in PHP

    sudo sed -i \
    -e '/^redis.session.locking_enabled/d' \
    -e '/^redis.session.lock_retries/d' \
    -e '/^redis.session.lock_wait_time/d' \
    /etc/php/8.4/fpm/php.ini && \
    echo -e "redis.session.locking_enabled=1\nredis.session.lock_retries=-1\nredis.session.lock_wait_time=10000" | sudo tee -a /etc/php/8.4/fpm/php.ini > /dev/null && \
    sudo systemctl restart php8.4-fpm

    # Now, Restart php-fpm and Apache Server

    sudo service php8.4-fpm restart
    sudo systemctl restart apache2

# Step8. Install SSL and Enable HTTP2

    # 1. We will install the LetsEncrypt certificate, so, first, we need the Certbot tools.

    sudo apt-get install python3-certbot-apache -y

    # 2. with the Certbot tool, let’s request a Certificate for our domain.

    sudo certbot --apache -d data.amarissolutions.com

    # 3. Enable apache HTTP2 module and configure site for the http2 protocols

    sudo a2enmod http2
    # sudo sed -i 's/^Protocols .*/Protocols h2 h2c http/1.1/' /etc/apache2/sites-enabled/000-default-le-ssl.conf
    sudo sed -i '/<VirtualHost \*:443>/a\        Protocols h2 h2c http/1.1' /etc/apache2/sites-enabled/000-default-le-ssl.conf
    
    # Now, Restart Apache Server
    
    sudo systemctl restart apache2

    # 4. HTTP Strict Transport Security, which instructs browsers not to allow any connection to the Nextcloud instance using HTTP, prevents man-in-the-middle attacks.

    sudo sed -i '/<\/VirtualHost>/i\
    <IfModule mod_headers.c>\n        Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains"\n    </IfModule>\n' /etc/apache2/sites-enabled/000-default-le-ssl.conf

# Step9. Pretty URL’s

    # 1. Pretty URLs remove the "index.php“ part in all Nextcloud URLs. It will make URLs shorter and prettier.
    
    sudo sed -i "/);/i\ \ \ \ 'htaccess.RewriteBase' => '/', " /var/www/nextcloud/config/config.php
    
    # 2. This command will update the .htaccess file for the redirection
    
    sudo -u www-data php -define apc.enable_cli=1 /var/www/nextcloud/occ maintenance:update:htaccess

# Step10. Final Nextcloud Tweaks

    sudo -u www-data php /var/www/nextcloud/occ background:cron

    sudo -u www-data php /var/www/nextcloud/occ config:system:set timezone --value="Africa/Nairobi"

    sudo -u www-data php /var/www/nextcloud/occ config:system:set maintenance_window_start --type=integer --value=1
    sudo -u www-data php -f /var/www/nextcloud/cron.php
    sudo -u www-data php /var/www/nextcloud/occ background:job:list

    sudo apt-get install -y php8.4-sqlite3
    sudo systemctl restart apache2

sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices
sudo -u www-data php /var/www/nextcloud/occ db:check
sudo -u www-data php /var/www/nextcloud/occ db:schema:expected
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-columns
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-primary-keys
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
sudo apt install -y php-imagick
sudo systemctl restart php8.4-fpm
sudo systemctl restart apache2

sudo -u www-data php /var/www/nextcloud/occ maintenance:repair

