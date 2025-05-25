#!/bin/sh

# CaptiFi Device Activation Script
# This script handles the communication with the CaptiFi API for device activation
# Usage: device-activation-api.sh [PIN] [MAC_ADDRESS]

# Ensure script exits on any error
set -e

# Configuration
API_URL="https://api.captifi.io/api"  # Change this to your CaptiFi API URL
CONFIG_DIR="/etc/captifi"
LOGS_DIR="/tmp"
LOG_FILE="$LOGS_DIR/captifi_activation.log"

# Ensure directories exist
mkdir -p "$CONFIG_DIR/scripts" "$LOGS_DIR"

# Log function
log() {
    echo "$(date): $1" >> "$LOG_FILE"
    echo "$1"
}

log "Starting device activation process"

# Get PIN from argument or file
PIN="$1"
if [ -z "$PIN" ] && [ -f "$CONFIG_DIR/activation_pin" ]; then
    PIN=$(cat "$CONFIG_DIR/activation_pin")
fi

# Get MAC address from argument or file
MAC_ADDRESS="$2"
if [ -z "$MAC_ADDRESS" ] && [ -f "$CONFIG_DIR/activation_mac" ]; then
    MAC_ADDRESS=$(cat "$CONFIG_DIR/activation_mac")
fi

# If still not set, try to detect MAC address
if [ -z "$MAC_ADDRESS" ]; then
    MAC_ADDRESS=$(ifconfig br-lan 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
    if [ -z "$MAC_ADDRESS" ]; then
        MAC_ADDRESS=$(ifconfig eth0 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
    fi
fi

# Get device model and serial number
MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "OpenWRT")
SERIAL=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo "Unknown")

# Validate inputs
if [ -z "$PIN" ]; then
    log "Error: No PIN provided"
    exit 1
fi

if [ -z "$MAC_ADDRESS" ]; then
    log "Error: Could not determine device MAC address"
    exit 1
fi

log "Activating device with PIN: $PIN and MAC: $MAC_ADDRESS"

# Send activation request to CaptiFi API
log "Sending activation request to $API_URL/plug-and-play/activate"

# Use curl to make the API request
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"pin\":\"$PIN\",\"box_mac_address\":\"$MAC_ADDRESS\",\"device_model\":\"$MODEL\",\"serial\":\"$SERIAL\"}" \
    "$API_URL/plug-and-play/activate" 2>> "$LOG_FILE")

# Log the response
log "API Response: $RESPONSE"

# Check if activation was successful
if echo "$RESPONSE" | grep -q "\"success\":true"; then
    log "Activation successful!"
    
    # Extract API key from response
    API_KEY=$(echo "$RESPONSE" | grep -o '"api_key":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$API_KEY" ]; then
        log "API key received, storing for future use"
        echo "$API_KEY" > "$CONFIG_DIR/api_key"
        chmod 600 "$CONFIG_DIR/api_key"
        
        # Extract server_id and site_id for future reference
        SERVER_ID=$(echo "$RESPONSE" | grep -o '"server_id":[0-9]*' | cut -d':' -f2)
        SITE_ID=$(echo "$RESPONSE" | grep -o '"site_id":[0-9]*' | cut -d':' -f2)
        
        if [ -n "$SERVER_ID" ]; then
            echo "$SERVER_ID" > "$CONFIG_DIR/server_id"
        fi
        
        if [ -n "$SITE_ID" ]; then
            echo "$SITE_ID" > "$CONFIG_DIR/site_id"
        fi
        
        # Extract WiFi SSID if provided
        WIFI_SSID=$(echo "$RESPONSE" | grep -o '"wifi_ssid":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$WIFI_SSID" ]; then
            log "Setting WiFi SSID to: $WIFI_SSID"
            
            # Configure WiFi
            if command -v uci &> /dev/null; then
                # Count how many wifi-iface sections exist
                IFACE_COUNT=0
                while uci get wireless.@wifi-iface[$IFACE_COUNT] > /dev/null 2>&1; do
                    # Set each interface to the provided SSID
                    uci set wireless.@wifi-iface[$IFACE_COUNT].ssid="$WIFI_SSID"
                    
                    # If password provided, set encryption and key
                    WIFI_PASSWORD=$(echo "$RESPONSE" | grep -o '"wifi_password":"[^"]*"' | cut -d'"' -f4)
                    if [ -n "$WIFI_PASSWORD" ] && [ "$WIFI_PASSWORD" != "null" ]; then
                        uci set wireless.@wifi-iface[$IFACE_COUNT].encryption="psk2"
                        uci set wireless.@wifi-iface[$IFACE_COUNT].key="$WIFI_PASSWORD"
                    else
                        # No password means open network
                        uci set wireless.@wifi-iface[$IFACE_COUNT].encryption="none"
                        uci delete wireless.@wifi-iface[$IFACE_COUNT].key 2>/dev/null || true
                    fi
                    
                    IFACE_COUNT=$((IFACE_COUNT+1))
                done
                
                log "Configured $IFACE_COUNT WiFi interfaces"
                
                # Apply changes
                uci commit wireless
            fi
        fi
        
        # Setup heartbeat script
        log "Setting up heartbeat script"
        
        cat > "$CONFIG_DIR/scripts/heartbeat.sh" << 'EOF'
#!/bin/sh

# CaptiFi Heartbeat Script
# This script sends periodic heartbeats to the CaptiFi server
# and processes any commands received in response

# Configuration
API_URL="https://api.captifi.io/api"  # Change this to your CaptiFi API URL
CONFIG_DIR="/etc/captifi"
LOGS_DIR="/tmp"
LOG_FILE="$LOGS_DIR/captifi_heartbeat.log"
LAST_RESPONSE_FILE="$CONFIG_DIR/last_response"

# Ensure directories exist
mkdir -p "$CONFIG_DIR" "$LOGS_DIR"

# Log function (only if verbose)
log() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Get device information
MAC_ADDRESS=$(ifconfig br-lan 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
if [ -z "$MAC_ADDRESS" ]; then
    MAC_ADDRESS=$(ifconfig eth0 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
fi

UPTIME=$(cat /proc/uptime | awk '{print $1}')
MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "OpenWRT")
SERIAL=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo "Unknown")

# Get WiFi SSID
WIFI_SSID=""
if command -v uci &> /dev/null; then
    WIFI_SSID=$(uci get wireless.@wifi-iface[0].ssid 2>/dev/null || echo "")
fi

# Check if in activation mode
if [ -f "$CONFIG_DIR/self_activate_mode" ]; then
    log "Device is in self-activation mode"
    
    # Check if activation PIN exists
    if [ -f "$CONFIG_DIR/activation_pin" ] && [ -f "$CONFIG_DIR/activation_mac" ]; then
        log "Activation PIN found, starting activation process"
        
        # Call the activation script
        if [ -x "$CONFIG_DIR/scripts/device-activation-api.sh" ]; then
            "$CONFIG_DIR/scripts/device-activation-api.sh"
        fi
    fi
    
    # Exit early - don't send heartbeat in activation mode
    exit 0
fi

# Check if device is activated
if [ ! -f "$CONFIG_DIR/api_key" ]; then
    log "Device not activated yet"
    exit 0
fi

# Get API key
API_KEY=$(cat "$CONFIG_DIR/api_key")
if [ -z "$API_KEY" ]; then
    log "API key empty, device not properly activated"
    exit 1
fi

log "Sending heartbeat to $API_URL/plug-and-play/heartbeat"

# Send heartbeat to server
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"mac_address\":\"$MAC_ADDRESS\",\"api_key\":\"$API_KEY\",\"uptime\":$UPTIME,\"device_model\":\"$MODEL\",\"serial\":\"$SERIAL\",\"wifi_ssid\":\"$WIFI_SSID\"}" \
    "$API_URL/plug-and-play/heartbeat" 2>> "$LOG_FILE")

# Save response for debugging
echo "$RESPONSE" > "$LAST_RESPONSE_FILE"

# Process any commands in the response
if echo "$RESPONSE" | grep -q "\"command\":"; then
    COMMAND=$(echo "$RESPONSE" | grep -o '"command":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$COMMAND" ] && [ "$COMMAND" != "null" ]; then
        log "Received command: $COMMAND"
        
        case "$COMMAND" in
            "reboot")
                log "Rebooting device as requested"
                reboot
                ;;
                
            "reset")
                log "Resetting device as requested"
                if [ -x "$CONFIG_DIR/reset-device.sh" ]; then
                    "$CONFIG_DIR/reset-device.sh"
                else
                    log "Reset script not found"
                fi
                ;;
                
            "fetch_splash")
                log "Fetching splash page as requested"
                if [ -x "$CONFIG_DIR/fetch-splash-page.sh" ]; then
                    "$CONFIG_DIR/fetch-splash-page.sh" "$API_KEY" "$API_URL"
                else
                    log "Fetch splash script not found"
                fi
                ;;
                
            "update_wifi")
                log "Updating WiFi settings as requested"
                
                # Extract WiFi parameters
                SSID=$(echo "$RESPONSE" | grep -o '"ssid":"[^"]*"' | cut -d'"' -f4)
                PASSWORD=$(echo "$RESPONSE" | grep -o '"password":"[^"]*"' | cut -d'"' -f4)
                ENCRYPTION=$(echo "$RESPONSE" | grep -o '"encryption":"[^"]*"' | cut -d'"' -f4)
                
                if [ -n "$SSID" ]; then
                    log "Setting WiFi SSID to: $SSID"
                    
                    # Configure WiFi
                    if command -v uci &> /dev/null; then
                        # Count how many wifi-iface sections exist
                        IFACE_COUNT=0
                        while uci get wireless.@wifi-iface[$IFACE_COUNT] > /dev/null 2>&1; do
                            # Set each interface to the provided SSID
                            uci set wireless.@wifi-iface[$IFACE_COUNT].ssid="$SSID"
                            
                            # If password provided, set encryption and key
                            if [ -n "$PASSWORD" ] && [ "$PASSWORD" != "null" ]; then
                                ENCRYPTION=${ENCRYPTION:-"psk2"}
                                uci set wireless.@wifi-iface[$IFACE_COUNT].encryption="$ENCRYPTION"
                                uci set wireless.@wifi-iface[$IFACE_COUNT].key="$PASSWORD"
                            else
                                # No password means open network
                                uci set wireless.@wifi-iface[$IFACE_COUNT].encryption="none"
                                uci delete wireless.@wifi-iface[$IFACE_COUNT].key 2>/dev/null || true
                            fi
                            
                            IFACE_COUNT=$((IFACE_COUNT+1))
                        done
                        
                        log "Configured $IFACE_COUNT WiFi interfaces"
                        
                        # Apply changes
                        uci commit wireless
                        
                        # Restart network to apply changes
                        if [ -x /etc/init.d/network ]; then
                            log "Restarting network to apply WiFi changes"
                            /etc/init.d/network restart
                        else
                            log "Reloading wireless settings"
                            wifi reload
                        fi
                    else
                        log "UCI command not found, cannot configure WiFi"
                    fi
                else
                    log "No SSID provided in WiFi update command"
                fi
                ;;
                
            *)
                log "Unknown command: $COMMAND"
                ;;
        esac
    fi
fi

# Process any splash page updates
if echo "$RESPONSE" | grep -q "\"splash_page\":"; then
    SPLASH_PAGE=$(echo "$RESPONSE" | grep -o '"splash_page":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$SPLASH_PAGE" ] && [ "$SPLASH_PAGE" != "null" ]; then
        log "Splash page update requested: $SPLASH_PAGE"
        
        if [ -x "$CONFIG_DIR/fetch-splash-page.sh" ]; then
            "$CONFIG_DIR/fetch-splash-page.sh" "$API_KEY" "$API_URL"
        else
            log "Fetch splash script not found"
        fi
    fi
fi

log "Heartbeat completed successfully"
exit 0
EOF

        chmod +x "$CONFIG_DIR/scripts/heartbeat.sh"
        
        # Set up cron job
        log "Setting up heartbeat cron job"
        
        # Check if there's already a cron entry for heartbeat
        if ! grep -q "$CONFIG_DIR/scripts/heartbeat.sh" /etc/crontabs/root 2>/dev/null; then
            echo "*/5 * * * * $CONFIG_DIR/scripts/heartbeat.sh" >> /etc/crontabs/root
            if [ -x /etc/init.d/cron ]; then
                /etc/init.d/cron restart
            fi
        fi
        
        # Remove activation files
        log "Removing activation files"
        rm -f "$CONFIG_DIR/activation_pin" "$CONFIG_DIR/activation_mac" "$CONFIG_DIR/self_activate_mode"
        
        # Run first heartbeat immediately
        log "Running first heartbeat"
        "$CONFIG_DIR/scripts/heartbeat.sh"
        
        # Schedule reboot to apply all changes
        log "Scheduling reboot in 30 seconds"
        ( sleep 30 && reboot ) &
        
        exit 0
    else
        log "Error: No API key found in response"
        log "Response: $RESPONSE"
        exit 1
    fi
else
    # Extract error message
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$ERROR_MSG" ]; then
        log "Activation failed: $ERROR_MSG"
    else
        log "Activation failed with unknown error"
        log "Response: $RESPONSE"
    fi
    
    exit 1
fi
