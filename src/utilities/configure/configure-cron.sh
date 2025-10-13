#!/bin/bash

# Source the configuration and logging utilities
source "${BASH_SOURCE%/*}/../../core/config-manager.sh"
source "${BASH_SOURCE%/*}/../../core/logging.sh"

# Set up logging
LOG_FILE="${LOG_DIR}/configure-cron-$(date +%Y%m%d%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

log_message "INFO" "Starting cron job configuration..."

# Function to configure Nextcloud cron jobs
configure_nextcloud_cron() {
    local webroot=$(get_config "webroot" "/var/www/nextcloud")
    local php_path=$(command -v php)
    local cron_user=$(get_config "cron_user" "www-data")
    
    if [ ! -d "${webroot}" ]; then
        log_message "ERROR" "Nextcloud webroot not found at ${webroot}"
        return 1
    }
    
    if [ -z "${php_path}" ]; then
        log_message "ERROR" "PHP not found. Please install PHP first."
        return 1
    fi
    
    log_message "INFO" "Configuring Nextcloud cron jobs..."
    
    # Create the systemd service for Nextcloud cron
    local service_file="/etc/systemd/system/nextcloud-cron.service"
    cat > "${service_file}" << EOL
[Unit]
Description=Nextcloud cron.php job

[Service]
User=${cron_user}
ExecStart=${php_path} ${webroot}/cron.php
every 5 minutes

[Install]
WantedBy=basic.target
EOL

    # Create the systemd timer for Nextcloud cron
    local timer_file="/etc/systemd/system/nextcloud-cron.timer"
    cat > "${timer_file}" << 'EOL'
[Unit]
Description=Run Nextcloud cron.php every 5 minutes

[Timer]
OnBootSec=5m
OnUnitActiveSec=5m
Unit=nextcloud-cron.service

[Install]
WantedBy=timers.target
EOL

    # Set proper permissions
    chmod 644 "${service_file}" "${timer_file}"
    
    # Reload systemd and enable the timer
    systemctl daemon-reload
    systemctl enable --now nextcloud-cron.timer
    
    # Verify the timer is active
    if systemctl is-active --quiet nextcloud-cron.timer; then
        log_message "SUCCESS" "Nextcloud cron timer is now active"
    else
        log_message "WARNING" "Nextcloud cron timer is not active. Please check the configuration."
        return 1
    fi
    
    # Also set up the traditional cron job as a fallback
    local cron_job="*/5  *  *  *  * ${cron_user} ${php_path} ${webroot}/cron.php"
    local cron_file="/etc/cron.d/nextcloud"
    
    echo "# Nextcloud cron job" > "${cron_file}"
    echo "${cron_job}" >> "${cron_file}"
    chmod 644 "${cron_file}"
    
    log_message "INFO" "Configured Nextcloud cron job to run every 5 minutes"
    return 0
}

# Function to set up system maintenance tasks
configure_system_maintenance() {
    log_message "INFO" "Configuring system maintenance tasks..."
    
    # Daily log rotation for Nextcloud
    local logrotate_file="/etc/logrotate.d/nextcloud"
    cat > "${logrotate_file}" << 'EOL'
/var/www/nextcloud/data/nextcloud.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 www-data www-data
    sharedscripts
    postrotate
        /usr/bin/find /var/www/nextcloud/data -name "*.log*" -mtime +30 -delete
    endscript
}
EOL
    
    # Weekly maintenance script
    local maintenance_script="/usr/local/bin/nextcloud-maintenance"
    cat > "${maintenance_script}" << 'EOL'
#!/bin/bash
# Nextcloud maintenance script

# Run Nextcloud maintenance mode
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on

# Run Nextcloud maintenance tasks
sudo -u www-data php /var/www/nextcloud/occ maintenance:repair
sudo -u www-data php /var/www/nextcloud/occ maintenance:data-fingerprint
sudo -u www-data php /var/www/nextcloud/occ files:scan --all
sudo -u www-data php /var/www/nextcloud/occ files:scan-app-data

# Update Nextcloud apps
sudo -u www-data php /var/www/nextcloud/occ app:update --all

# Disable maintenance mode
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off

echo "Nextcloud maintenance completed at $(date)"
EOL

    chmod +x "${maintenance_script}"
    
    # Add weekly cron job for maintenance
    echo "0 3 * * 0 root ${maintenance_script} >> /var/log/nextcloud/maintenance.log 2>&1" > /etc/cron.d/nextcloud-maintenance
    
    log_message "SUCCESS" "System maintenance tasks configured"
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root"
        exit 1
    fi
    
    configure_nextcloud_cron
    configure_system_maintenance
    exit $?
fi
