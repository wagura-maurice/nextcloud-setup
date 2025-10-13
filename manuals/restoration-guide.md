# Nextcloud Restoration Guide

This guide provides step-by-step instructions for restoring a Nextcloud instance from backup using the `restore-nextcloud.sh` script. The script handles both local and Cloudflare R2 backups with integrity verification.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Restoration Methods](#restoration-methods)
3. [Restoring from Local Backup](#restoring-from-local-backup)
4. [Restoring from Cloudflare R2](#restoring-from-cloudflare-r2)
5. [Restoration Process](#restoration-process)
6. [Troubleshooting](#troubleshooting)
7. [Best Practices](#best-practices)

## Prerequisites

Before starting the restoration process:

1. **Required Files**
   - `restore-nextcloud.sh` script in your project's `scripts/` directory
   - Backup archive (`.tar.gz` file) and its checksum (`.sha256`)
   - Configuration files in `temp/` directory:
     - `.nextcloud_backup_config` or `.nextcloud_restore_config`
     - `.mysql_credentials`

2. **System Requirements**
   - Sufficient disk space (at least 2x the backup size)
   - Required dependencies:
     - `awscli` (for R2 backups)
     - `mysql-client`
     - `tar` and `gzip`
     - `sha256sum`

3. **Configuration**
   Ensure your `temp/.nextcloud_backup_config` contains:
   ```ini
   # Database Configuration
   DB_NAME="nextcloud"
   DB_USER="nextcloud"
   DB_PASS="your_secure_password"
   
   # R2 Configuration (if using Cloudflare R2)
   R2_ACCESS_KEY_ID=""
   R2_SECRET_ACCESS_KEY=""
   R2_BUCKET=""
   R2_ENDPOINT=""
   ```

## Restoration Methods

### 1. List Available Backups (R2 Only)

To list available backups in your Cloudflare R2 bucket:

```bash
chmod +x scripts/restore-nextcloud.sh
./scripts/restore-nextcloud.sh
```

This will display all available backup archives in your configured R2 bucket.

### 2. Restore from Local Backup

```bash
# Make script executable if needed
chmod +x scripts/restore-nextcloud.sh

# Run restore script with local backup file
sudo ./scripts/restore-nextcloud.sh /path/to/backup-file.tar.gz
```

The script will:
1. Verify the backup file integrity using the `.sha256` checksum
2. Extract the backup to a temporary directory
3. Restore the database
4. Restore Nextcloud files and configuration
5. Set proper permissions
6. Run Nextcloud maintenance commands

### 3. Restore from Cloudflare R2

```bash
# Make script executable if needed
chmod +x scripts/restore-nextcloud.sh

# Run restore script with R2 path
sudo ./scripts/restore-nextcloud.sh s3://your-bucket-name/nextcloud_backup_YYYYMMDD_HHMMSS.tar.gz
```

The script will:
1. Download the backup from R2
2. Verify the download integrity
3. Proceed with the restoration process

## Restoration Process

### What the Script Does

1. **Backup Verification**
   - Checks if the backup file exists
   - Verifies the backup integrity using SHA256 checksum
   - Validates the backup structure

2. **System Preparation**
   - Creates necessary temporary directories
   - Backs up current configuration
   - Puts Nextcloud in maintenance mode

3. **Database Restoration**
   - Creates a backup of the current database
   - Drops and recreates the database
   - Restores the database from the backup

4. **File Restoration**
   - Backs up current Nextcloud installation
   - Extracts the backup archive
   - Restores Nextcloud files with proper permissions

5. **Post-Restoration**
   - Updates file ownership and permissions
   - Runs Nextcloud maintenance commands
   - Disables maintenance mode
   - Cleans up temporary files

### Manual Restoration Steps (if needed)

If you need to perform a manual restoration, the script's temporary directory contains the extracted backup files at:

```
/tmp/tmp.XXXXXXXXXX/nextcloud_backup/
├── config/       # Configuration files
├── data/         # Data directory
├── database/     # Database dump
└── redis.conf    # Redis configuration (if present)
```

You can use these files to perform a manual restoration if needed.

## Restoring Specific Components

### Restore Only Database

```bash
# Extract the database from the backup
BACKUP_FILE="path/to/backup.tar.gz"
tar -xzf "$BACKUP_FILE" -C /tmp/nextcloud_restore nextcloud_backup/database/

# Restore the database
zcat /tmp/nextcloud_restore/nextcloud_backup/database/nextcloud-sqlbkp_*.sql.gz | mysql -u root -p nextcloud
```

### Restore Only Configuration

```bash
# Extract config files
BACKUP_FILE="path/to/backup.tar.gz"
tar -xzf "$BACKUP_FILE" -C /tmp/nextcloud_restore nextcloud_backup/config/

# Restore config
cp -r /tmp/nextcloud_restore/nextcloud_backup/config/* /var/www/nextcloud/config/
chown -R www-data:www-data /var/www/nextcloud/config/
```

### Restore Only Data Directory

```bash
# Extract data directory
BACKUP_FILE="path/to/backup.tar.gz"
tar -xzf "$BACKUP_FILE" -C /tmp/nextcloud_restore nextcloud_backup/data/

# Restore data
rsync -a --delete /tmp/nextcloud_restore/nextcloud_backup/data/ /var/nextcloud/data/
chown -R www-data:www-data /var/nextcloud/data/
```

## Support

For additional help, please refer to:
- [Nextcloud Documentation](https://docs.nextcloud.com/)
- [Nextcloud Forums](https://help.nextcloud.com/)
- [GitHub Issues](https://github.com/wagura-maurice/nextcloud-setup/issues)

---
*Last updated: $(date +%Y-%m-%d)*

## Post-Restoration Steps

The script handles most post-restoration tasks, but you should verify:

1. **Check Service Status**
   ```bash
   # Check web server
   sudo systemctl status apache2  # or nginx
   
   # Check PHP-FPM if used
   sudo systemctl status php8.1-fpm
   
   # Check Nextcloud status
   sudo -u www-data php /var/www/nextcloud/occ status
   ```

2. **Verify Data Integrity**
   ```bash
   # Check for file integrity
   sudo -u www-data php /var/www/nextcloud/occ files:scan --all
   
   # Check for any warnings
   sudo -u www-data php /var/www/nextcloud/occ check
   ```

3. **Test Functionality**
   - Log in to the web interface
   - Upload/download files
   - Test sharing functionality
   - Verify app functionality

## Troubleshooting

### Common Issues

1. **Backup Verification Failed**
   ```bash
   # Manually verify the checksum
   sha256sum -c backup-file.tar.gz.sha256
   
   # If the backup is corrupted, try downloading it again
   ```

2. **Database Connection Issues**
   ```bash
   # Check MySQL service status
   sudo systemctl status mysql
   
   # Verify credentials in config.php
   sudo grep -E 'db(user|password|name|host)' /var/www/nextcloud/config/config.php
   ```

3. **Permission Issues**
   ```bash
   # Fix ownership
   sudo chown -R www-data:www-data /var/www/nextcloud/
   sudo chown -R www-data:www-data /var/nextcloud/data/
   
   # Fix permissions
   sudo find /var/www/nextcloud/ -type d -exec chmod 750 {} \;
   sudo find /var/www/nextcloud/ -type f -exec chmod 640 {} \;
   ```

4. **R2 Download Issues**
   ```bash
   # Verify R2 credentials
   aws s3 ls s3://your-bucket-name/ --endpoint-url https://your-r2-endpoint
   
   # Check network connectivity
   curl -v https://your-r2-endpoint
   ```

## Best Practices

1. **Test Restorations**
   - Regularly test restoration process in a staging environment
   - Document any issues encountered during testing

2. **Documentation**
   - Keep detailed records of all restoration procedures
   - Document any custom configurations

3. **Verification**
   - Verify data integrity after restoration
   - Check application logs for errors
   - Test critical functionality

4. **Security**
   - Change all passwords after restoration
   - Verify file permissions
   - Update any API keys or tokens

## Next Steps

- [Backup Guide](./backup-guide.md)
- [Maintenance Guide](./maintenance-guide.md)

---
*Last updated: $(date +%Y-%m-%d)*