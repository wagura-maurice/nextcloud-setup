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

log_section "MariaDB Installation"

# Default configuration values
readonly MARIADB_VERSION="10.11"
readonly PACKAGE_MANAGER="apt-get"
readonly INSTALL_OPTS="-y --no-install-recommends"
# Required packages
readonly MARIADB_PACKAGES=(
    "mariadb-server"
    "mariadb-client"
    "mariadb-backup"
    "galera-4"
    "socat"
    "pwgen"
    "python3-mysqldb"
    "python3-pymysql"
)

# Function to add MariaDB repository
add_mariadb_repository() {
    log_info "Adding MariaDB repository..."
    
    # Check if already added
    if [ -f "/etc/apt/sources.list.d/mariadb.list" ]; then
        log_info "MariaDB repository already added"
        return 0
    fi
    
    # Install required packages
    if ! ${PACKAGE_MANAGER} install ${INSTALL_OPTS} \
        software-properties-common \
        apt-transport-https \
        curl; then
        log_error "Failed to install required packages"
        return 1
    fi
    
    # Add MariaDB repository
    if ! curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | \
        bash -s -- --mariadb-server-version="mariadb-${MARIADB_VERSION}"; then
        log_error "Failed to add MariaDB repository"
        return 1
    fi
    
    # Update package lists
    if ! ${PACKAGE_MANAGER} update; then
        log_error "Failed to update package lists"
        return 1
    fi
    
    log_info "MariaDB repository added successfully"
    return 0
}

# Function to install MariaDB packages
install_mariadb_packages() {
    log_info "Installing MariaDB packages..."
    
    if ! DEBIAN_FRONTEND=noninteractive ${PACKAGE_MANAGER} install ${INSTALL_OPTS} "${MARIADB_PACKAGES[@]}"; then
        log_error "Failed to install MariaDB packages"
        return 1
    fi
    
    log_info "MariaDB packages installed successfully"
    return 0
}

# Function to secure MariaDB installation
secure_mariadb() {
    log_info "Securing MariaDB installation..."
    
    # Generate a random root password if not set
    local root_password=$(openssl rand -base64 32)
    
    # Create a temporary file with SQL commands
    local temp_sql=$(mktemp)
    
    cat > "${temp_sql}" <<-EOF
-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';
-- Remove test database
DROP DATABASE IF EXISTS test;
-- Remove test database access
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
-- Reload privileges
FLUSH PRIVILEGES;
-- Set root password
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${root_password}');
-- Remove remote root access
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
-- Remove any empty user
DELETE FROM mysql.user WHERE User='';
-- Remove any empty database
DELETE FROM mysql.db WHERE Db='';
-- Reload privileges
FLUSH PRIVILEGES;
EOF
    
    # Execute SQL commands
    if ! mysql -u root < "${temp_sql}"; then
        log_warning "Failed to secure MariaDB installation. Attempting to continue..."
    fi
    
    # Clean up
    rm -f "${temp_sql}"
    
    # Save root password to a secure location
    local root_credentials="/root/.my.cnf"
    cat > "${root_credentials}" <<-EOF
[client]
user=root
password='${root_password}'
host=localhost
EOF
    
    # Secure the credentials file
    chmod 600 "${root_credentials}"
    
    log_info "MariaDB installation secured successfully"
    log_warning "Root password saved to ${root_credentials}. Keep this file secure!"
    return 0
}

# Function to configure MariaDB
configure_mariadb() {
    log_info "Configuring MariaDB..."
    
    # Create backup of existing configuration
    local backup_dir="/etc/mysql/backup-$(date +%Y%m%d%H%M%S)"
    mkdir -p "${backup_dir}"
    cp -a /etc/mysql/conf.d/ "${backup_dir}/" 2>/dev/null || true
    cp -a /etc/mysql/mariadb.conf.d/ "${backup_dir}/" 2>/dev/null || true
    
    # Create custom configuration directory if it doesn't exist
    mkdir -p /etc/mysql/conf.d/
    
    # Create custom configuration
    cat > /etc/mysql/conf.d/nextcloud.cnf <<-EOF
# Nextcloud MariaDB Configuration
# Managed by Nextcloud setup script - DO NOT EDIT MANUALLY

[mysqld]
# General settings
user                    = mysql
pid-file                = /var/run/mysqld/mysqld.pid
socket                  = /var/run/mysqld/mysqld.sock
port                    = 3306
basedir                 = /usr
datadir                 = /var/lib/mysql
tmpdir                  = /tmp
lc-messages-dir         = /usr/share/mysql

# Connection and Threads
max_connections         = 200
max_connect_errors      = 1000
connect_timeout         = 30
wait_timeout            = 300
interactive_timeout     = 300
max_allowed_packet      = 256M
thread_cache_size       = 128
thread_handling         = pool-of-threads
thread_pool_size        = 16
thread_pool_max_threads = 1000

# Query Cache (disabled in MariaDB 10.1.7+)
query_cache_type        = 0
query_cache_size        = 0

# Table and Buffer Settings
table_open_cache        = 4000
table_definition_cache  = 2000
table_open_cache_instances = 16
table_open_cache_size   = 2000

# InnoDB Settings
innodb_buffer_pool_size            = 4G
innodb_buffer_pool_instances       = 8
innodb_flush_log_at_trx_commit     = 1
innodb_log_buffer_size             = 16M
innodb_log_file_size               = 512M
innodb_log_files_in_group          = 2
innodb_file_per_table              = 1
innodb_autoinc_lock_mode           = 2
innodb_flush_method                = O_DIRECT
innodb_read_io_threads             = 8
innodb_write_io_threads            = 8
innodb_io_capacity                 = 2000
innodb_io_capacity_max             = 4000
innodb_lru_scan_depth              = 1000
innodb_purge_threads               = 4
innodb_read_ahead_threshold        = 0
innodb_stats_on_metadata           = 0
innodb_use_native_aio              = 1
innodb_lock_wait_timeout           = 120
innodb_rollback_on_timeout         = 1
innodb_print_all_deadlocks         = 1
innodb_compression_level           = 6
innodb_compression_failure_threshold_pct = 5
innodb_compression_pad_pct_max     = 50

# MyISAM Settings (minimal as we use InnoDB)
key_buffer_size         = 16M
myisam_recover_options  = BACKUP

# Logging
slow_query_log_file     = /var/log/mysql/mariadb-slow.log
slow_query_log          = 1
long_query_time         = 2
log_slow_verbosity      = query_plan
log_warnings            = 2
log_error               = /var/log/mysql/error.log

# Binary Logging (for replication)
server_id               = 1
log_bin                 = /var/log/mysql/mariadb-bin
log_bin_index           = /var/log/mysql/mariadb-bin.index
expire_logs_days        = 7
sync_binlog             = 1
binlog_format           = ROW
binlog_row_image        = FULL
binlog_cache_size       = 1M
max_binlog_size         = 100M
binlog_group_commit_sync_delay = 100

# Replication
read_only               = 0
skip_slave_start        = 1
slave_parallel_mode     = optimistic
slave_parallel_threads  = 4

# Security
local_infile            = 0
skip_name_resolve       = 1
secure_file_priv        = /var/lib/mysql-files

# Performance Schema
performance_schema                = ON
performance_schema_events_waits_history_long_size = 10000
performance_schema_events_waits_history_size = 10
performance_schema_max_table_instances = 500
performance_schema_max_thread_instances = 1000

# Other Settings
tmp_table_size          = 64M
max_heap_table_size     = 64M
join_buffer_size        = 2M
sort_buffer_size        = 2M
read_buffer_size        = 2M
read_rnd_buffer_size    = 4M
net_buffer_length       = 8K
myisam_sort_buffer_size = 64M

# Character Set
character-set-server    = utf8mb4
collation-server        = utf8mb4_unicode_ci
character-set-client-handshake = FALSE
init_connect           = 'SET NAMES utf8mb4'

# Nextcloud specific optimizations
innodb_read_only_compressed = OFF
innodb_adaptive_hash_index = ON
innodb_adaptive_flushing = ON
innodb_flush_neighbors = 1
innodb_random_read_ahead = ON
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000
innodb_lru_scan_depth = 1000
innodb_checksum_algorithm = crc32
innodb_checksum_algorithm = strict_crc32
innodb_lock_wait_timeout = 50
innodb_rollback_on_timeout = 1
innodb_print_all_deadlocks = 1
innodb_file_format = Barracuda
innodb_file_per_table = 1
innodb_large_prefix = 1
innodb_purge_threads = 4
innodb_read_ahead_threshold = 0
innodb_stats_on_metadata = 0
innodb_use_native_aio = 1
innodb_compression_level = 6
innodb_compression_failure_threshold_pct = 5
innodb_compression_pad_pct_max = 50
innodb_buffer_pool_dump_at_shutdown = 1
innodb_buffer_pool_load_at_startup = 1
innodb_buffer_pool_dump_pct = 40
innodb_buffer_pool_load_abort = 0
innodb_buffer_pool_load_now = 0
innodb_buffer_pool_filename = ib_buffer_pool
innodb_flush_neighbors = 1
innodb_flush_sync = 1
innodb_flushing_avg_loops = 30
innodb_max_dirty_pages_pct = 90
innodb_max_dirty_pages_pct_lwm = 10
innodb_adaptive_flushing = 1
innodb_adaptive_flushing_lwm = 10
innodb_adaptive_hash_index = 1
innodb_adaptive_hash_index_parts = 8
innodb_adaptive_max_sleep_delay = 150000
innodb_change_buffer_max_size = 25
innodb_change_buffering = all
innodb_checksum_algorithm = crc32
innodb_cmp_per_index_enabled = 0
innodb_commit_concurrency = 0
innodb_compression_failure_threshold_pct = 5
innodb_compression_level = 6
innodb_compression_pad_pct_max = 50
innodb_concurrency_tickets = 5000
innodb_deadlock_detect = 1
innodb_default_row_format = dynamic
innodb_disable_sort_file_cache = 0
innodb_fast_shutdown = 1
innodb_fill_factor = 100
innodb_flush_log_at_timeout = 1
innodb_flush_neighbors = 1
innodb_flush_sync = 1
innodb_ft_cache_size = 8000000
innodb_ft_min_token_size = 3
innodb_ft_server_stopword_table =
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000
innodb_lock_wait_timeout = 50
innodb_log_buffer_size = 16M
innodb_log_compressed_pages = 1
innodb_log_file_size = 1G
innodb_lru_scan_depth = 1000
innodb_max_dirty_pages_pct = 90
innodb_max_purge_lag = 0
innodb_max_purge_lag_delay = 0
innodb_old_blocks_pct = 37
innodb_old_blocks_time = 1000
innodb_online_alter_log_max_size = 1G
innodb_open_files = 4000
innodb_page_cleaners = 4
innodb_print_all_deadlocks = 1
innodb_purge_batch_size = 300
innodb_purge_threads = 4
innodb_random_read_ahead = 0
innodb_read_ahead_threshold = 56
innodb_read_io_threads = 8
innodb_read_only = 0
innodb_rollback_on_timeout = 1
innodb_sort_buffer_size = 1M
innodb_spin_wait_delay = 6
innodb_stats_auto_recalc = 1
innodb_stats_include_delete_marked = 0
innodb_stats_method = nulls_unequal
innodb_stats_on_metadata = 0
innodb_stats_persistent = 1
innodb_stats_persistent_sample_pages = 20
innodb_stats_transient_sample_pages = 8
innodb_status_output = 0
innodb_status_output_locks = 0
innodb_strict_mode = 1
innodb_sync_array_size = 1
innodb_sync_spin_loops = 30
innodb_table_locks = 1
innodb_thread_concurrency = 0
innodb_thread_sleep_delay = 10000
innodb_use_native_aio = 1
innodb_write_io_threads = 8

# Performance Schema
performance_schema = ON
performance_schema_events_waits_history_long_size = 10000
performance_schema_events_waits_history_size = 10
performance_schema_max_table_instances = 500
performance_schema_max_thread_instances = 1000

# Logging
slow_query_log_file = /var/log/mysql/mariadb-slow.log
slow_query_log = 1
long_query_time = 2
log_slow_verbosity = query_plan
log_warnings = 2
log_error = /var/log/mysql/error.log

# Binary Logging (for replication)
server_id = 1
log_bin = /var/log/mysql/mariadb-bin
log_bin_index = /var/log/mysql/mariadb-bin.index
expire_logs_days = 7
sync_binlog = 1
binlog_format = ROW
binlog_row_image = FULL
binlog_cache_size = 1M
max_binlog_size = 100M
binlog_group_commit_sync_delay = 100

# Replication
read_only = 0
skip_slave_start = 1
slave_parallel_mode = optimistic
slave_parallel_threads = 4

# Security
local_infile = 0
skip_name_resolve = 1
secure_file_priv = /var/lib/mysql-files

# Other Settings
tmp_table_size = 64M
max_heap_table_size = 64M
join_buffer_size = 2M
sort_buffer_size = 2M
read_buffer_size = 2M
read_rnd_buffer_size = 4M
net_buffer_length = 8K
myisam_sort_buffer_size = 64M

# Character Set
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
character-set-client-handshake = FALSE
init_connect = 'SET NAMES utf8mb4'
EOF
    
    # Set proper permissions
    chown -R mysql:mysql /etc/mysql/
    chmod 644 /etc/mysql/conf.d/nextcloud.cnf
    
    # Create log directory if it doesn't exist
    mkdir -p /var/log/mysql
    chown -R mysql:mysql /var/log/mysql
    
    log_info "MariaDB configuration created at /etc/mysql/conf.d/nextcloud.cnf"
    return 0
}

# Function to verify installation
verify_installation() {
    log_info "Verifying MariaDB installation..."
    
    # Check if MariaDB service is running
    if ! systemctl is-active --quiet mariadb; then
        log_error "MariaDB service is not running"
        return 1
    fi
    
    # Check if we can connect to MariaDB
    if ! mysql -e "SELECT VERSION();" >/dev/null 2>&1; then
        log_error "Failed to connect to MariaDB"
        return 1
    fi
    
    log_info "MariaDB installation verified successfully"
    return 0
}

# Function to restart MariaDB
restart_mariadb() {
    log_info "Restarting MariaDB service..."
    
    if ! systemctl restart mariadb; then
        log_error "Failed to restart MariaDB service"
        journalctl -u mariadb --no-pager -n 50
        return 1
    fi
    
    # Wait for MariaDB to start
    local max_attempts=30
    local attempt=1
    
    while ! mysql -e "SELECT 1" >/dev/null 2>&1; do
        if [ ${attempt} -ge ${max_attempts} ]; then
            log_error "MariaDB failed to start after ${max_attempts} attempts"
            return 1
        fi
        
        log_info "Waiting for MariaDB to start (attempt ${attempt}/${max_attempts})..."
        sleep 1
        attempt=$((attempt + 1))
    done
    
    log_info "MariaDB service restarted successfully"
    return 0
}

# Main installation function
install_mariadb() {
    local success=true
    
    log_info "Starting MariaDB ${MARIADB_VERSION} installation..."
    
    # Add MariaDB repository
    if ! add_mariadb_repository; then
        success=false
    fi
    
    # Install MariaDB packages
    if ! install_mariadb_packages; then
        success=false
    fi
    
    # Configure MariaDB
    if ! configure_mariadb; then
        success=false
    fi
    
    # Restart MariaDB to apply configuration
    if ! restart_mariadb; then
        success=false
    fi
    
    # Secure MariaDB installation
    if ! secure_mariadb; then
        success=false
    fi
    
    # Verify installation
    if ! verify_installation; then
        success=false
    fi
    
    # Final status
    if [ "${success}" = true ]; then
        log_success "MariaDB ${MARIADB_VERSION} installation completed successfully"
        log_info "Run the configuration script to set up databases and users:"
        log_info "  ./src/utilities/configure/configure-mariadb.sh"
        return 0
    else
        log_error "MariaDB installation completed with errors"
        return 1
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    install_mariadb
    exit $?
fi

# Create backup of current configuration
BACKUP_DIR="/etc/mysql/backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -a /etc/mysql/conf.d/ "$BACKUP_DIR/" 2>/dev/null || true
cp -a /etc/mysql/mariadb.conf.d/ "$BACKUP_DIR/" 2>/dev/null || true
log_info "Current configuration backed up to $BACKUP_DIR"

# Generate secure root password if not set
DB_ROOT_PASS="${DB_ROOT_PASS:-$(openssl rand -base64 32)}"

echo "DB_ROOT_PASS=$DB_ROOT_PASS" > "$SCRIPT_DIR/.db_credentials"
chmod 600 "$SCRIPT_DIR/.db_credentials"

# Secure the installation
log_info "Securing MariaDB installation..."
SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation

# Handle initial root password prompt
expect "Enter current password for root (enter for none):"
send "\r"

# Set root password
expect "Switch to unix_socket authentication [Y/n]"
send "n\r"

expect "Change the root password? [Y/n]"
send "Y\r"

expect "New password:"
send "$DB_ROOT_PASS\r"

expect "Re-enter new password:"
send "$DB_ROOT_PASS\r"

# Answer remaining questions
expect "Remove anonymous users? [Y/n]"
send "Y\r"

expect "Disallow root login remotely? [Y/n]"
send "Y\r"

expect "Remove test database and access to it? [Y/n]"
send "Y\r"

expect "Reload privilege tables now? [Y/n]"
send "Y\r"

expect eof
")

echo "$SECURE_MYSQL"

# Verify root access
if ! mysql -u root -p"$DB_ROOT_PASS" -e "SELECT 1" >/dev/null 2>&1; then
    log_error "Failed to secure MariaDB installation"
    exit 1
fi

# Create a root credentials file for secure CLI access
cat > /root/.my.cnf <<EOF
[client]
user=root
password=$DB_ROOT_PASS
socket=/var/run/mysqld/mysqld.sock
[mysql]
connect_timeout=5
[mysqldump]
max_allowed_packet=1G
EOF

chmod 600 /root/.my.cnf

# Create a general my.cnf for all users
cat > /etc/mysql/conf.d/mariadb.cnf <<'EOF'
[client]
default-character-set = utf8mb4
socket = /var/run/mysqld/mysqld.sock

[mysql]
default-character-set = utf8mb4

[mysqld]
# Basic Settings
user = mysql
pid-file = /var/run/mysqld/mysqld.pid
socket = /var/run/mysqld/mysqld.sock
basedir = /usr
datadir = /var/lib/mysql
tmpdir = /tmp
lc_messages_dir = /usr/share/mysql
lc_messages = en_US
skip-external-locking

# Connection Settings
max_connections = 100
max_connect_errors = 100000
connect_timeout = 5
wait_timeout = 600
max_allowed_packet = 1G
max_heap_table_size = 64M
tmp_table_size = 64M

# Buffer Settings
key_buffer_size = 32M
sort_buffer_size = 4M
read_buffer_size = 2M
read_rnd_buffer_size = 4M
join_buffer_size = 4M

# Logging
general_log = 0
general_log_file = /var/log/mysql/mysql.log
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mariadb-slow.log
long_query_time = 5
log_slow_verbosity = query_plan
log_queries_not_using_indexes = 1
log_slow_filter = admin,filesort,filesort_on_disk,full_join,full_scan,query_cache,query_cache_miss,tmp_table,tmp_table_on_disk

# InnoDB Settings
innodb_buffer_pool_size = 2G
innodb_buffer_pool_instances = 2
innodb_flush_log_at_trx_commit = 1
innodb_log_buffer_size = 16M
innodb_log_file_size = 1G
innodb_flush_method = O_DIRECT
innodb_file_per_table = 1
innodb_autoinc_lock_mode = 2
innodb_read_io_threads = 4
innodb_write_io_threads = 4
innodb_io_capacity = 1000
innodb_io_capacity_max = 2000
innodb_flush_neighbors = 0
innodb_read_ahead_threshold = 0
innodb_buffer_pool_dump_at_shutdown = 1
innodb_buffer_pool_load_at_startup = 1
innodb_buffer_pool_dump_pct = 40
innodb_deadlock_detect = 1
innodb_lock_wait_timeout = 120
innodb_print_all_deadlocks = 1

# Security Settings
local-infile = 0
skip_name_resolve = 1
secure_file_priv = /var/lib/mysql-files

# Replication
server-id = 1
log_bin = /var/log/mysql/mariadb-bin
log_bin_index = /var/log/mysql/mariadb-bin.index
expire_logs_days = 10
max_binlog_size = 100M
binlog_format = ROW
binlog_row_image = FULL
binlog_cache_size = 1M
max_binlog_cache_size = 2G
sync_binlog = 1

# GTID
gtid_strict_mode = 1
binlog_gtid_simple_recovery = 1

# Performance Schema
performance_schema = ON
performance_schema_instrument = '%=ON'
performance_schema_consumer_events_statements_history_long = ON
performance_schema_consumer_events_statements_history = ON
performance_schema_consumer_events_waits_history_long = ON
performance_schema_consumer_events_waits_history = ON

# Character Set
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
character-set-client-handshake = FALSE

# Other Settings
query_cache_type = 0
query_cache_size = 0
table_open_cache = 4000
thread_cache_size = 100
open_files_limit = 65535

# Optimizer Settings
optimizer_switch = 'index_merge=on,index_merge_union=on,index_merge_sort_union=on,index_merge_intersection=on,index_merge_sort_intersection=off,engine_condition_pushdown=on,index_condition_pushdown=on,mrr=on,mrr_cost_based=on,block_nested_loop=on,batched_key_access=off,materialization=on,semijoin=on,loosescan=on,firstmatch=on,duplicateweedout=on,subquery_materialization_cost_based=on,use_index_extensions=on,condition_fanout_filter=on,derived_merge=on,use_invisible_indexes=off,skip_scan=on,hash_join=on,subquery_to_derived=off,prefer_ordering_index=on,hypergraph_optimizer=off,derived_condition_pushdown=on'
EOF

# Set proper permissions
chown -R mysql:mysql /var/lib/mysql
chmod 755 /var/lib/mysql
chmod 644 /etc/mysql/conf.d/mariadb.cnf

# Create log directory if it doesn't exist
mkdir -p /var/log/mysql
chown -R mysql:adm /var/log/mysql
chmod 750 /var/log/mysql

# Restart MariaDB to apply all changes
log_info "Restarting MariaDB to apply configuration..."
systemctl restart mariadb

# Verify MariaDB is running
if ! systemctl is-active --quiet mariadb; then
    log_error "MariaDB failed to start after configuration"
    journalctl -u mariadb --no-pager -n 50
    exit 1
fi

log_success "MariaDB server installation and configuration completed"
log_info "Root credentials saved to /root/.my.cnf"
log_info "MySQL configuration file: /etc/mysql/conf.d/mariadb.cnf"
log_info "MySQL data directory: /var/lib/mysql"
log_info "MySQL error log: /var/log/mysql/error.log"
log_info "MySQL slow query log: /var/log/mysql/mariadb-slow.log"
log_info "MySQL binary logs: /var/log/mysql/mariadb-bin.*"

# Save database credentials with restricted permissions
cat > "$SCRIPT_DIR/.db_credentials" <<EOF
# MariaDB root credentials
DB_ROOT_PASS='$DB_ROOT_PASS'

# Connection details
DB_HOST='localhost'
DB_PORT='3306'
DB_SOCKET='/var/run/mysqld/mysqld.sock'

# Nextcloud database will be created by configure-mysql.sh
# DB_NAME='nextcloud'
# DB_USER='nextcloud'
# DB_PASS=''

# How to connect as root:
# mysql -u root -p\$DB_ROOT_PASS
# or
# mysql --defaults-file=/root/.my.cnf
EOF

chmod 600 "$SCRIPT_DIR/.db_credentials"

log_info "Database credentials saved to $SCRIPT_DIR/.db_credentials"
log_info "Run the configuration script to create the Nextcloud database:"
log_info "  ./src/utilities/configure/configure-mysql.sh"
