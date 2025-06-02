#!/bin/sh

# CaptiFi Form Submission Handler
# This script processes form submissions from the splash page
# and communicates with the CaptiFi server for authorization

# Configuration
API_KEY=$(cat /etc/captifi/api_key 2>/dev/null)
SERVER_URL="https://app.captifi.io"
CONFIG_DIR="/etc/captifi"
LOGFILE="/tmp/captifi_submission.log"

# Log function
log() {
    echo "$(date): $1" >> "$LOGFILE"
    echo "Content-type: text/plain"
    echo ""
    echo "$1"
}

# Get query string
QUERY_STRING="${QUERY_STRING:-$(echo "$REQUEST_URI" | cut -d'?' -f2)}"

# Get MAC address
MAC_ADDRESS=$(echo "$QUERY_STRING" | grep -o 'mac=[^&]*' | cut -d'=' -f2)
if [ -z "$MAC_ADDRESS" ]; then
    MAC_ADDRESS=$(ifconfig br-lan 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1 || \
                 ifconfig eth0 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
fi

# Forward the form submission to the CaptiFi server
FORM_DATA="$QUERY_STRING&mac_address=$MAC_ADDRESS"
log "Forwarding form submission: $FORM_DATA"

RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "X-API-KEY: $API_KEY" \
    --data "$FORM_DATA" \
    "$SERVER_URL/api/device/submit-form" 2>> "$LOGFILE")

# Check the response
if echo "$RESPONSE" | grep -q "\"success\":true"; then
    log "Form submission successful"
    
    # Extract the authorization status
    AUTH_STATUS=$(echo "$RESPONSE" | grep -o '"authorized":true' | cut -d':' -f2)
    
    if [ "$AUTH_STATUS" = "true" ]; then
        # Authorize the MAC address
        if [ -n "$MAC_ADDRESS" ]; then
            log "Authorizing MAC address: $MAC_ADDRESS"
            
            # Add to authorized MACs list
            echo "$MAC_ADDRESS" >> "$CONFIG_DIR/authorized_macs"
            
            # Allow this MAC in firewall
            if command -v iptables &> /dev/null; then
                iptables -t nat -I CAPTIFI_PREROUTING 1 -m mac --mac-source "$MAC_ADDRESS" -j ACCEPT
                log "Added MAC to firewall accept rules"
            fi
            
            # Return success response
            echo "Content-type: text/html"
            echo ""
            echo "<!DOCTYPE html><html><head><title>Success</title>"
            echo "<meta http-equiv=\"refresh\" content=\"2;url=http://captifi.io\">"
            echo "</head><body><h1>Success!</h1>"
            echo "<p>You are now authorized to use the internet.</p>"
            echo "<p>Redirecting you to the internet...</p></body></html>"
        else
            log "Error: No MAC address to authorize"
            echo "Content-type: text/html"
            echo ""
            echo "<!DOCTYPE html><html><head><title>Error</title></head>"
            echo "<body><h1>Error</h1><p>No MAC address found to authorize.</p></body></html>"
        fi
    else
        # Return the response from the server
        log "Authorization not granted by server"
        echo "Content-type: text/html"
        echo ""
        echo "$RESPONSE"
    fi
else
    # Error in submission
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$ERROR_MSG" ]; then
        log "Error in form submission: $ERROR_MSG"
    else
        log "Error: Invalid response format"
        log "Response: $RESPONSE"
    fi
    
    echo "Content-type: text/html"
    echo ""
    echo "<!DOCTYPE html><html><head><title>Error</title></head>"
    echo "<body><h1>Error</h1><p>There was an error processing your submission.</p>"
    echo "<p>Please try again or contact support.</p></body></html>"
fi
