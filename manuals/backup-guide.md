# Nextcloud Backup Guide

This guide covers the backup procedures for the Nextcloud instance using the `backup-nextcloud.sh` script, which supports both local and Cloudflare R2 storage.

## Table of Contents
1. [Backup Process Overview](#backup-process-overview)
2. [Configuration](#configuration)
3. [Running Backups](#running-backups)
4. [Backup Contents](#backup-contents)
5. [Cloudflare R2 Integration](#cloudflare-r2-integration)
6. [Troubleshooting](#troubleshooting)
7. [Restoration](#restoration)

## Backup Process Overview

The backup script performs the following operations:

1. **Initialization**
   - Loads configuration
   - Sets up logging
   - Validates dependencies
   - Creates necessary directories

2. **Backup Execution**
   - Puts Nextcloud in maintenance mode
   - Backs up configuration files
   - Backs up data directory (with exclusions)
   - Backs up custom apps
   - Creates a database dump
   - Backs up Apache configuration
   - Creates a compressed archive
   - Verifies backup integrity with SHA256 checksum
   - Uploads to Cloudflare R2 (if configured)

3. **Cleanup**
   - Applies retention policy
   - Removes old backups
   - Disables maintenance mode
   - Logs completion status

## Configuration

### Configuration File

The main configuration file is located at `configs/backup-config.conf`. A sample configuration is created automatically if it doesn't exist.

### Key Configuration Options

```ini
# Database Configuration
DB_NAME="nextcloud"
DB_USER="nextcloud"
DB_PASS="your_secure_db_password"

# Cloudflare R2 Configuration
R2_ACCESS_KEY_ID="your_r2_access_key_id"
R2_SECRET_ACCESS_KEY="your_r2_secret_access_key"
R2_BUCKET="your-r2-bucket-name"
R2_ENDPOINT="https://your-account-id.r2.cloudflarestorage.com"

# Local Backup Settings
BACKUP_DIR="/path/to/backups"

# Retention Policy (in days)
RETAIN_DAYS=30

# What to back up (set to "true" to include, "false" to exclude)
BACKUP_DATA=true
BACKUP_CONFIG=true
BACKUP_APPS=true
BACKUP_DATABASE=true
BACKUP_REDIS=false

# Compression level (1-9, where 1 is fastest, 9 is best compression)
COMPRESSION_LEVEL=6

# Maintenance Mode (true/false)
MAINTENANCE_MODE="true"

# Logging
LOG_LEVEL="INFO"  # DEBUG, INFO, WARNING, ERROR
```

## Running Backups

### Prerequisites

```bash
# Install required dependencies
sudo apt-get update
sudo apt-get install -y rsync mysql-client awscli
```

### Manual Backup

```bash
# Make the script executable
chmod +x scripts/backup-nextcloud.sh

# Run the backup script
sudo ./scripts/backup-nextcloud.sh
```

### Scheduled Backups (Cron)

Add to crontab (as root):

```bash
# Edit crontab
sudo crontab -e

# Add this line to run daily at 2 AM
0 2 * * * /path/to/nextcloud-setup/scripts/backup-nextcloud.sh

# For verbose logging (optional)
0 2 * * * /path/to/nextcloud-setup/scripts/backup-nextcloud.sh >> /var/log/nextcloud-backup.log 2>&1
```

### Command Line Options

- `--force-full`: Force a full backup instead of incremental
- `--no-upload`: Skip R2 upload
- `--dry-run`: Show what would be done without making changes

## Backup Contents

Each backup includes:

```
backup_YYYYMMDD_HHMMSS/
├── backup_metadata       # Backup metadata and type
├── config/               # Nextcloud configuration
│   └── config.php        # Main configuration file
├── data/                 # User data (excludes cache and temp files)
├── apps/                 # Custom apps (if any)
├── nextcloud_db_backup.sql  # Database dump
└── apache_config.conf    # Apache configuration (if found)
```

## Cloudflare R2 Integration

The script can automatically upload backups to Cloudflare R2. To enable:

1. Create an R2 bucket in your Cloudflare dashboard
2. Generate API credentials with read/write permissions
3. Update the R2 configuration in `backup-config.conf`

### R2 Configuration

```ini
# Required R2 Settings
R2_ACCESS_KEY_ID="your_access_key_id"
R2_SECRET_ACCESS_KEY="your_secret_access_key"
R2_BUCKET="your-bucket-name"
R2_ENDPOINT="https://your-account-id.r2.cloudflarestorage.com"
```

### Verifying R2 Access

```bash
# List objects in the bucket
aws s3 ls s3://your-bucket-name/ --endpoint-url https://your-account-id.r2.cloudflarestorage.com
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   # Ensure the backup script is executable
   chmod +x scripts/backup-nextcloud.sh
   
   # Run with sudo if needed
   sudo ./scripts/backup-nextcloud.sh
   ```

2. **Database Connection Issues**
   - Verify database credentials in `config.php`
   - Check if MySQL/MariaDB is running
   - Ensure the database user has proper permissions

3. **R2 Upload Failures**
   ```bash
   # Check AWS credentials
   aws configure list
   
   # Test R2 connectivity
   aws s3 ls s3://your-bucket-name/ --endpoint-url https://your-account-id.r2.cloudflarestorage.com
   ```

### Checking Logs

Logs are stored in the `logs/` directory:

```bash
# View the latest log
tail -f logs/nextcloud-backup-*.log

# Search for errors
grep -i error logs/nextcloud-backup-*.log
```

## Restoration

See the [Restoration Guide](./restoration-guide.md) for detailed instructions on restoring from backups.

### Quick Restoration

```bash
# Restore from local backup
./scripts/restore-nextcloud.sh /path/to/backup.tar.gz

# Restore from R2
./scripts/restore-nextcloud.sh s3://your-bucket-name/backup_YYYYMMDD_HHMMSS.tar.gz
```

## Support

For additional help, please refer to:
- [Nextcloud Documentation](https://docs.nextcloud.com/)
- [Nextcloud Forums](https://help.nextcloud.com/)
- [GitHub Issues](https://github.com/wagura-maurice/nextcloud-setup/issues)

---
*Last updated: $(date +%Y-%m-%d)*

   Add to crontab (as root):
   ```
   # Daily full backup at 2 AM
   0 2 * * * /path/to/nextcloud-setup/scripts/backup-nextcloud.sh
   ```

## Manual Backups

### Database Backup
```bash
# Create a database dump
mysqldump --single-transaction -h [host] -u [user] -p[password] [database] > backup-$(date +%Y%m%d).sql
```

### File System Backup
```bash
# Backup Nextcloud directory
rsync -Aavx /var/www/nextcloud/ /backup/nextcloud-$(date +%Y%m%d)/

# Backup data directory
rsync -Aavx /var/nextcloud/data/ /backup/nextcloud-data-$(date +%Y%m%d)/
```

## Backup Contents

### Configuration Files
- `config/config.php`
- `.htaccess`
- All other files in the Nextcloud directory

### Database
- Complete SQL dump of the Nextcloud database
- Includes all user data, app data, and system settings

### Data Directory
- User files
- Application data
- File versions
- Previews
- Encryption keys (if encryption is enabled)

## Restoring from Backup

1. Stop the web server:
   ```bash
   sudo systemctl stop apache2
   ```

2. Restore the database:
   ```bash
   mysql -u [user] -p[password] [database] < backup-file.sql
   ```

3. Restore files:
   ```bash
   rsync -Aavx /backup/nextcloud/ /var/www/nextcloud/
   rsync -Aavx /backup/nextcloud-data/ /var/nextcloud/data/
   ```

4. Fix permissions:
   ```bash
   chown -R www-data:www-data /var/www/nextcloud/
   chown -R www-data:www-data /var/nextcloud/data/
   ```

5. Run maintenance mode:
   ```bash
   sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on
   ```

6. Run the restore script:
   ```bash
   sudo ./scripts/restore-nextcloud.sh /path/to/backup-file.tar.gz
   ```

7. Disable maintenance mode:
   ```bash
   sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off
   ```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   - Ensure the backup script has execute permissions:
     ```bash
     chmod +x scripts/*.sh
     ```
   - Run the script with sudo if needed

2. **Database Connection Issues**
   - Verify database credentials in `.env`
   - Check if MySQL/MariaDB is running

3. **Insufficient Disk Space**
   - Check available space: `df -h`
   - Clean up old backups if needed

### Checking Logs

Logs are stored in the `logs/` directory:
- `nextcloud-backup-*.log`: Backup process logs
- `restore-*.log`: Restore process logs

View the latest log:
```bash
tail -f logs/nextcloud-backup-*.log
```

## Best Practices

1. **Regular Testing**: Periodically test restores to ensure backups are working
2. **Offsite Storage**: Use R2 or another cloud storage for offsite backups
3. **Monitoring**: Set up alerts for backup failures
4. **Retention Policy**: Adjust `BACKUP_RETENTION_DAYS` based on your needs
5. **Security**: Keep backup files secure with proper permissions (600 for config files)

## Next Steps

- [Restoration Guide](./restore-guide.md)
- [Maintenance Guide](./maintenance-guide.md)

---
*Last updated: $(date +%Y-%m-%d)*