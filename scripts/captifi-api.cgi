#!/bin/sh

# CaptiFi OpenWRT Integration - API Handler
# This script processes direct API requests for WiFi management and other commands
# V1.1 - Updated with multi-interface support

# Required headers for CGI script
echo "Content-type: application/json"
echo ""

# Configuration
INSTALL_DIR="/etc/captifi"
LOG_FILE="/tmp/captifi_api.log"

# Log function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
  # Keep log file size reasonable
  if [ -f "$LOG_FILE" ] && [ $(wc -l < "$LOG_FILE") -gt 100 ]; then
    tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
  fi
}

# Parse query string if GET request
if [ "$REQUEST_METHOD" = "GET" ]; then
    QUERY_STRING_POST="$QUERY_STRING"
fi

# Parse POST data if POST request
if [ "$REQUEST_METHOD" = "POST" ]; then
    # Read POST data
    if [ -n "$CONTENT_LENGTH" ]; then
        read -n $CONTENT_LENGTH QUERY_STRING_POST
    fi
fi

# Function to extract value from JSON
get_json_value() {
    local json="$1"
    local key="$2"
    echo "$json" | grep -o "\"$key\":\"[^\"]*\"" | cut -d'"' -f4
}

# Extract command and auth token
COMMAND=$(get_json_value "$QUERY_STRING_POST" "command")
AUTH_TOKEN=$(get_json_value "$QUERY_STRING_POST" "auth_token")

log "Received request: command=$COMMAND"

# Check if API key exists and matches
API_KEY_FILE="$INSTALL_DIR/api_key"
if [ -f "$API_KEY_FILE" ]; then
    STORED_API_KEY=$(cat "$API_KEY_FILE")
else
    # No API key found
    echo '{"success":false,"message":"Device not activated"}'
    log "Error: Device not activated"
    exit 0
fi

# Validate authentication
if [ "$AUTH_TOKEN" != "$STORED_API_KEY" ]; then
    echo '{"success":false,"message":"Invalid authentication"}'
    log "Error: Invalid authentication"
    exit 0
fi

# Process commands
if [ -z "$COMMAND" ]; then
    echo '{"success":false,"message":"No command specified"}'
    log "Error: No command specified"
    exit 0
fi

# Execute command
case "$COMMAND" in
    "update_wifi")
        # Extract WiFi parameters
        WIFI_SSID=$(get_json_value "$QUERY_STRING_POST" "ssid")
        WIFI_PASSWORD=$(get_json_value "$QUERY_STRING_POST" "password")
        WIFI_ENCRYPTION=$(get_json_value "$QUERY_STRING_POST" "encryption")
        
        # Set defaults
        [ -z "$WIFI_ENCRYPTION" ] && WIFI_ENCRYPTION="psk2"
        
        # Validate SSID
        if [ -z "$WIFI_SSID" ]; then
            echo '{"success":false,"message":"SSID is required"}'
            log "Error: SSID is required"
            exit 0
        fi
        
        log "Updating WiFi: SSID=$WIFI_SSID, Encryption=$WIFI_ENCRYPTION"
        
        # Update WiFi settings
        if command -v uci &> /dev/null; then
            # Updated to support multiple WiFi interfaces
            IFACE_COUNT=0
            INTERFACES_UPDATED=0
            
            # Loop through all WiFi interfaces
            while uci get wireless.@wifi-iface[$IFACE_COUNT] > /dev/null 2>&1; do
                # Set SSID for each interface
                uci set wireless.@wifi-iface[$IFACE_COUNT].ssid="$WIFI_SSID"
                
                # Set encryption and password if provided
                if [ -n "$WIFI_PASSWORD" ]; then
                    log "Setting interface $IFACE_COUNT with password and encryption type: $WIFI_ENCRYPTION"
                    uci set wireless.@wifi-iface[$IFACE_COUNT].encryption="$WIFI_ENCRYPTION"
                    uci set wireless.@wifi-iface[$IFACE_COUNT].key="$WIFI_PASSWORD"
                else
                    # No password = open network
                    log "Setting interface $IFACE_COUNT as open network (no password)"
                    uci set wireless.@wifi-iface[$IFACE_COUNT].encryption="none"
                    uci delete wireless.@wifi-iface[$IFACE_COUNT].key 2>/dev/null || true
                fi
                
                INTERFACES_UPDATED=$((INTERFACES_UPDATED+1))
                IFACE_COUNT=$((IFACE_COUNT+1))
            done
            
            # Apply changes
            uci commit wireless
            
            # Response with success message
            echo '{"success":true,"message":"WiFi settings updated","ssid":"'$WIFI_SSID'","interfaces_updated":'$INTERFACES_UPDATED'}'
            
            # Use background process to restart wireless after sending response
            (sleep 2 && wifi reload) &
            log "WiFi settings updated on $INTERFACES_UPDATED interfaces"
        else
            echo '{"success":false,"message":"UCI command not available"}'
            log "Error: UCI command not available"
        fi
        ;;
        
    "reboot")
        log "Executing reboot command"
        echo '{"success":true,"message":"Device will reboot shortly"}'
        # Delay reboot to allow response to be sent
        (sleep 2 && /sbin/reboot) &
        ;;
        
    "reset")
        log "Executing reset command"
        echo '{"success":true,"message":"Device will reset to PIN mode"}'
        # Delay reset to allow response to be sent
        (sleep 2 && rm -f "$INSTALL_DIR/api_key" "$INSTALL_DIR/config.json" && touch "$INSTALL_DIR/self_activate_mode") &
        ;;
        
    "fetch_splash")
        log "Executing fetch splash command"
        if [ -f "$INSTALL_DIR/scripts/fetch-splash.sh" ]; then
            # Execute the fetch splash script
            RESULT=$("$INSTALL_DIR/scripts/fetch-splash.sh" 2>&1)
            echo "{\"success\":true,\"message\":\"Fetched splash page\",\"result\":\"$RESULT\"}"
            log "Fetch splash executed successfully"
        else
            echo '{"success":false,"message":"Fetch splash script not found"}'
            log "Error: Fetch splash script not found"
        fi
        ;;
        
    "status")
        # Get device status
        UPTIME=$(cat /proc/uptime | awk '{print $1}')
        MAC_ADDRESS=$(ifconfig br-lan | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1 || echo "Unknown")
        HOSTNAME=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo "Unknown")
        MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "OpenWRT")
        WIFI_SSID=$(uci get wireless.@wifi-iface[0].ssid 2>/dev/null || echo "Unknown")
        
        # Count WiFi interfaces
        WIFI_INTERFACES=0
        while uci get wireless.@wifi-iface[$WIFI_INTERFACES] > /dev/null 2>&1; do
            WIFI_INTERFACES=$((WIFI_INTERFACES+1))
        done
        
        echo "{\"success\":true,\"message\":\"Device status\",\"uptime\":$UPTIME,\"mac_address\":\"$MAC_ADDRESS\",\"hostname\":\"$HOSTNAME\",\"model\":\"$MODEL\",\"wifi_ssid\":\"$WIFI_SSID\",\"wifi_interfaces\":$WIFI_INTERFACES}"
        log "Status requested and returned"
        ;;
        
    *)
        echo "{\"success\":false,\"message\":\"Unknown command: $COMMAND\"}"
        log "Error: Unknown command: $COMMAND"
        ;;
esac

exit 0
