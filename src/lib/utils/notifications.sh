#!/bin/bash
# Notification Utilities
# Provides functions for sending notifications

# Load core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/common-functions.sh"

# Default configuration
NOTIFICATION_METHOD="${NOTIFICATION_METHOD:-log}"  # log, email, webhook
EMAIL_FROM="${EMAIL_FROM:-nextcloud@$(hostname --fqdn)}"
EMAIL_TO="${EMAIL_TO:-admin@example.com}"
WEBHOOK_URL="${WEBHOOK_URL:-}"

# Send notification
# Usage: send_notification "Subject" "Message" [LEVEL]
send_notification() {
    local subject="$1"
    local message="$2"
    local level="${3:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Format the message
    local formatted_message="[$timestamp] [$level] $subject\n$message"
    
    case "$NOTIFICATION_METHOD" in
        email)
            send_email "$subject" "$formatted_message"
            ;;
        webhook)
            send_webhook "$subject" "$message" "$level"
            ;;
        log|*)
            # Default to logging
            case "$level" in
                ERROR)
                    log_error "$subject\n$message"
                    ;;
                WARNING)
                    log_warning "$subject\n$message"
                    ;;
                *)
                    log_info "$subject\n$message"
                    ;;
            esac
            ;;
    esac
    
    return 0
}

# Send email notification
# Usage: send_email "Subject" "Message"
send_email() {
    local subject="$1"
    local message="$2"
    
    if ! command -v mail &> /dev/null; then
        log_warning "mail command not found. Falling back to log notification."
        log_info "Email notification:\nSubject: $subject\n$message"
        return 1
    fi
    
    echo -e "$message" | mail -s "$subject" -a "From: $EMAIL_FROM" "$EMAIL_TO"
    return $?
}

# Send webhook notification
# Usage: send_webhook "Subject" "Message" [LEVEL]
send_webhook() {
    local subject="$1"
    local message="$2"
    local level="${3:-INFO}"
    
    if [ -z "$WEBHOOK_URL" ]; then
        log_warning "WEBHOOK_URL not set. Falling back to log notification."
        log_info "Webhook notification:\n$subject\n$message"
        return 1
    fi
    
    # Format the payload (adjust according to your webhook API)
    local payload=$(cat <<EOF
{
    "text": "*$subject*\n$message",
    "level": "$level",
    "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
}
EOF
)
    
    # Send the request
    if ! curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$WEBHOOK_URL" >/dev/null; then
        log_warning "Failed to send webhook notification"
        return 1
    fi
    
    return 0
}

# Send success notification
# Usage: notify_success "Subject" "Message"
notify_success() {
    send_notification "✅ $1" "$2" "SUCCESS"
}

# Send warning notification
# Usage: notify_warning "Subject" "Message"
notify_warning() {
    send_notification "⚠️ $1" "$2" "WARNING"
}

# Send error notification
# Usage: notify_error "Subject" "Message"
notify_error() {
    send_notification "❌ $1" "$2" "ERROR"
}

# Send info notification
# Usage: notify_info "Subject" "Message"
notify_info() {
    send_notification "ℹ️ $1" "$2" "INFO"
}

# Test notification system
# Usage: test_notifications
test_notifications() {
    log_section "Testing Notification System"
    
    notify_info "Test Notification" "This is a test info notification."
    notify_success "Test Success" "This is a test success notification."
    notify_warning "Test Warning" "This is a test warning notification."
    notify_error "Test Error" "This is a test error notification."
    
    log_success "Notification test completed"
}

# Export functions
export -f send_notification send_email send_webhook \
         notify_success notify_warning notify_error notify_info \
         test_notifications

# Run test if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_notifications
fi
