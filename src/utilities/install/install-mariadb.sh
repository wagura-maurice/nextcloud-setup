#!/bin/bash

# Load core functions and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"
source "$SCRIPT_DIR/core/env-loader.sh"

# Initialize environment and logging
load_environment
init_logging

log_section "Installing MariaDB Server"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Install MariaDB server and client
if ! command -v mariadb >/dev/null 2>&1; then
    log_info "Adding MariaDB repository and updating package lists..."
    apt-get update
    apt-get install -y software-properties-common apt-transport-https
    
    # Add MariaDB repository for the latest stable version
    curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash -s -- --mariadb-server-version="mariadb-10.11"
    
    log_info "Installing MariaDB server and client..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        mariadb-server \
        mariadb-client \
        mariadb-backup \
        mariadb-plugin-tokudb \
        galera-4 \
        socat \
        pwgen
    
    # Verify installation
    if ! systemctl is-active --quiet mariadb; then
        log_error "MariaDB service failed to start"
        systemctl status mariadb --no-pager
        exit 1
    fi
    
    log_success "MariaDB installed successfully"
else
    log_info "MariaDB is already installed"
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
