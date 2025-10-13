#!/bin/bash
# Security Utilities
# Provides security-related functions for Nextcloud

# Load core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"

# Default configuration
NEXTCLOUD_ROOT="${NEXTCLOUD_ROOT:-/var/www/nextcloud}"
SECURITY_SCAN_DIRS=(
    "$NEXTCLOUD_ROOT"
    "/etc/nginx"
    "/etc/apache2"
    "/etc/php"
    "/etc/mysql"
    "/etc/postgresql"
)

# Check file permissions
check_permissions() {
    log_section "Checking File Permissions"
    local issues_found=0
    
    # Check Nextcloud directory permissions
    local dirs_to_check=(
        "$NEXTCLOUD_ROOT"
        "$NEXTCLOUD_ROOT/config"
        "$NEXTCLOUD_ROOT/apps"
        "$NEXTCLOUD_ROOT/data"
    )
    
    for dir in "${dirs_to_check[@]}"; do
        if [ ! -d "$dir" ]; then
            log_warning "Directory not found: $dir"
            continue
        fi
        
        # Check directory permissions
        local perms=$(stat -c "%a" "$dir")
        local owner=$(stat -c "%U:%G" "$dir")
        
        if [ "$owner" != "www-data:www-data" ]; then
            log_warning "Incorrect ownership for $dir (should be www-data:www-data, found $owner)"
            ((issues_found++))
        fi
        
        # Check directory permissions (should be 750 for directories)
        if [ "$perms" != "750" ] && [ "$perms" != "755" ]; then
            log_warning "Insecure permissions for $dir (should be 750, found $perms)"
            ((issues_found++))
        fi
    done
    
    # Check file permissions in config directory
    if [ -d "$NEXTCLOUD_ROOT/config" ]; then
        while IFS= read -r -d '' file; do
            local perms=$(stat -c "%a" "$file")
            if [ "$perms" != "640" ] && [ "$perms" != "644" ]; then
                log_warning "Insecure permissions for $file (should be 640, found $perms)"
                ((issues_found++))
            fi
        done < <(find "$NEXTCLOUD_ROOT/config" -type f -print0)
    fi
    
    if [ $issues_found -eq 0 ]; then
        log_success "No permission issues found"
        return 0
    else
        log_warning "Found $issues_found permission issues"
        return 1
    fi
}

# Check for vulnerable PHP functions
check_php_functions() {
    log_section "Checking for Dangerous PHP Functions"
    local vulnerable_funcs=(
        "exec"
        "passthru"
        "shell_exec"
        "system"
        "proc_open"
        "popen"
        "show_source"
        "phpinfo"
    )
    
    local issues_found=0
    
    # Check PHP files for dangerous functions
    for dir in "${SECURITY_SCAN_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            continue
        fi
        
        for func in "${vulnerable_funcs[@]}"; do
            while IFS= read -r -d '' file; do
                # Skip vendor directories
                if [[ $file == */vendor/* ]]; then
                    continue
                fi
                
                # Check if the function is used with parentheses (function call)
                if grep -q "[^a-zA-Z0-9_]$func[[:space:]]*(" "$file"; then
                    log_warning "Potentially dangerous function '$func' found in: $file"
                    ((issues_found++))
                fi
            done < <(find "$dir" -type f -name "*.php" -print0)
        done
    done
    
    if [ $issues_found -eq 0 ]; then
        log_success "No dangerous PHP functions found"
        return 0
    else
        log_warning "Found $issues_found instances of potentially dangerous PHP functions"
        return 1
    fi
}

# Check for known vulnerabilities
check_known_vulnerabilities() {
    log_section "Checking for Known Vulnerabilities"
    local issues_found=0
    
    # Get Nextcloud version
    if [ ! -f "$NEXTCLOUD_ROOT/version.php" ]; then
        log_error "Could not determine Nextcloud version"
        return 1
    fi
    
    local version=$(grep -oP "[0-9]+\.[0-9]+\.[0-9]+" "$NEXTCLOUD_ROOT/version.php" 2>/dev/null || echo "unknown")
    
    if [ "$version" = "unknown" ]; then
        log_warning "Could not determine Nextcloud version"
        return 1
    fi
    
    log_info "Nextcloud version: $version"
    
    # Check for outdated version (this is a simplified example)
    local latest_stable=$(curl -s https://nextcloud.com/changelog/ | grep -oP 'Latest release: \K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    if [ -n "$latest_stable" ] && [ "$version" != "$latest_stable" ]; then
        log_warning "Outdated Nextcloud version. Latest stable is $latest_stable, you have $version"
        ((issues_found++))
    fi
    
    # Check for known vulnerable packages
    if command -v dpkg &> /dev/null; then
        local vulnerable_pkgs=(
            "libxml2"
            "openssl"
            "php*"
        )
        
        for pkg in "${vulnerable_pkgs[@]}"; do
            if dpkg -l | grep -q "^ii[[:space:]]\+$pkg"; then
                log_info "Checking for updates for $pkg..."
                apt-get update >/dev/null
                updates=$(apt-get -s upgrade | grep -i "^inst $pkg" | wc -l)
                if [ "$updates" -gt 0 ]; then
                    log_warning "Updates available for $pkg"
                    ((issues_found++))
                fi
            fi
        done
    fi
    
    if [ $issues_found -eq 0 ]; then
        log_success "No known vulnerabilities detected"
        return 0
    else
        log_warning "Found $issues_fund potential security issues"
        return 1
    fi
}

# Harden PHP configuration
harden_php() {
    log_section "Hardening PHP Configuration"
    local php_ini_paths=(
        "/etc/php/*/fpm/php.ini"
        "/etc/php/*/apache2/php.ini"
        "/etc/php/*/cli/php.ini"
    )
    
    local changes_made=0
    
    for php_ini in ${php_ini_paths[@]}; do
        # Expand the glob pattern
        for file in $php_ini; do
            [ -f "$file" ] || continue
            
            log_info "Hardening $file"
            
            # Create backup
            backup_file "$file"
            
            # Disable dangerous functions
            set_php_ini_setting "$file" "disable_functions" "exec,passthru,shell_exec,system,proc_open,popen,show_source,phpinfo"
            
            # Secure PHP settings
            set_php_ini_setting "$file" "expose_php" "Off"
            set_php_ini_setting "$file" "display_errors" "Off"
            set_php_ini_setting "$file" "log_errors" "On"
            set_php_ini_setting "$file" "allow_url_fopen" "Off"
            set_php_ini_setting "$file" "allow_url_include" "Off"
            set_php_ini_setting "$file" "session.cookie_httponly" "1"
            set_php_ini_setting "$file" "session.cookie_secure" "1"
            set_php_ini_setting "$file" "session.use_strict_mode" "1"
            
            ((changes_made++))
        done
    done
    
    if [ $changes_made -gt 0 ]; then
        log_success "PHP configuration hardened ($changes_made files updated)"
        return 0
    else
        log_warning "No PHP configuration files were modified"
        return 1
    fi
}

# Helper function to set PHP INI settings
set_php_ini_setting() {
    local file="$1"
    local setting="$2"
    local value="$3"
    
    if grep -q "^$setting[[:space:]]*=" "$file"; then
        # Update existing setting
        sed -i "s/^$setting[[:space:]]*=.*/$setting = $value/" "$file"
    else
        # Add new setting
        echo -e "\n; Added by security script\n$setting = $value" >> "$file"
    fi
}

# Run security scan
run_security_scan() {
    log_header "Running Security Scan"
    local issues_found=0
    
    check_permissions || ((issues_found++))
    check_php_functions || ((issues_found++))
    check_known_vulnerabilities || ((issues_found++))
    
    if [ $issues_found -gt 0 ]; then
        log_warning "Security scan completed with $issues_found issues"
        return 1
    else
        log_success "Security scan completed - No issues found"
        return 0
    fi
}

# Main function
main() {
    case "$1" in
        scan)
            run_security_scan
            ;;
        harden)
            harden_php
            ;;
        check-perms)
            check_permissions
            ;;
        check-php)
            check_php_functions
            ;;
        check-vulns)
            check_known_vulnerabilities
            ;;
        *)
            echo "Usage: $0 {scan|harden|check-perms|check-php|check-vulns}"
            exit 1
            ;;
    esac
    
    return $?
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
