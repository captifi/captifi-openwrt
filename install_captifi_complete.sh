#!/bin/sh

# CaptiFi Complete Installation Script
# This script installs all components needed for the CaptiFi OpenWRT integration:
# - PIN-based activation
# - Captive portal functionality
# - API integration with CaptiFi backend
# - Reset functionality
# - WiFi management

# Ensure script exits on any error
set -e

echo "Starting CaptiFi OpenWRT Integration installation..."

# Configuration
CONFIG_DIR="/etc/captifi"
SCRIPTS_DIR="$CONFIG_DIR/scripts"
WEB_DIR="/www"
CGI_DIR="$WEB_DIR/cgi-bin"
LOGS_DIR="/tmp"
API_URL="https://app.captifi.io/api"  # Change this to your CaptiFi API URL

# Ensure directories exist
mkdir -p "$CONFIG_DIR" "$SCRIPTS_DIR" "$WEB_DIR" "$CGI_DIR" "$LOGS_DIR"

# Function to download a file
download_file() {
    local url="$1"
    local dest="$2"
    echo "Downloading $url to $dest"
    wget -q -O "$dest" "$url" || {
        echo "Error: Failed to download $url"
        return 1
    }
    chmod +x "$dest"
    return 0
}

# Function to create from scratch if download fails
create_file() {
    local dest="$1"
    local content="$2"
    echo "Creating $dest"
    echo "$content" > "$dest"
    chmod +x "$dest"
}

echo "Setting up device activation scripts..."

# Create device activation script
cat > "$SCRIPTS_DIR/device-activation.sh" << 'EOF'
#!/bin/sh

# CaptiFi Device Activation Script
# This script handles the communication with the CaptiFi API for device activation
# Usage: device-activation.sh [PIN] [MAC_ADDRESS]

# Ensure script exits on any error
set -e

# Configuration
API_URL="https://app.captifi.io/api"  # Change this to your CaptiFi API URL
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
        
        # Remove activation files
        log "Removing activation files"
        rm -f "$CONFIG_DIR/activation_pin" "$CONFIG_DIR/activation_mac" "$CONFIG_DIR/self_activate_mode"
        
        # Run first heartbeat immediately
        if [ -x "$CONFIG_DIR/scripts/heartbeat.sh" ]; then
            log "Running first heartbeat"
            "$CONFIG_DIR/scripts/heartbeat.sh"
        fi
        
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
EOF

chmod +x "$SCRIPTS_DIR/device-activation.sh"

# Create heartbeat script
cat > "$SCRIPTS_DIR/heartbeat.sh" << 'EOF'
#!/bin/sh

# CaptiFi Heartbeat Script
# This script sends periodic heartbeats to the CaptiFi server
# and processes any commands received in response

# Configuration
API_URL="https://app.captifi.io/api"  # Change this to your CaptiFi API URL
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
        if [ -x "$CONFIG_DIR/scripts/device-activation.sh" ]; then
            "$CONFIG_DIR/scripts/device-activation.sh"
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

chmod +x "$SCRIPTS_DIR/heartbeat.sh"

# Create reset device script
cat > "$CONFIG_DIR/reset-device.sh" << 'EOF'
#!/bin/sh

# CaptiFi Device Reset Script
# This script resets the device to its factory state, removing all CaptiFi configurations
# and preparing it for re-activation with a new PIN
# V2.0 - Enhanced with better PIN mode activation and multiple interface support

# Ensure script exits on any error
set -e

echo "Starting CaptiFi device reset process..."

# Configuration directories
CONFIG_DIR="/etc/captifi"
WEB_DIR="/www"

# Remove API key and configuration
if [ -d "$CONFIG_DIR" ]; then
    echo "Removing API key and configuration..."
    rm -f $CONFIG_DIR/api_key
    rm -f $CONFIG_DIR/config.json
    rm -f $CONFIG_DIR/last_response
    rm -f $CONFIG_DIR/last_heartbeat
    
    # Create self-activation mode flag file
    touch $CONFIG_DIR/self_activate_mode
    echo "Device set to PIN activation mode"
fi

# Reset splash page
if [ -d "$WEB_DIR" ]; then
    echo "Removing splash page..."
    rm -f $WEB_DIR/splash.html
    rm -f $WEB_DIR/captifi-setup.html
    
    # Create a basic redirect page
    cat > $WEB_DIR/splash.html << EOF2
<!DOCTYPE html>
<html>
<head>
    <title>CaptiFi Setup Required</title>
    <meta http-equiv="refresh" content="5;url=http://captifi.io/setup" />
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #0066cc; }
    </style>
</head>
<body>
    <h1>CaptiFi Setup Required</h1>
    <p>This device needs to be set up with a new activation PIN.</p>
    <p>Please contact your administrator for a new PIN.</p>
    <p>Device MAC Address: <span id="mac"></span></p>
    <script>
        fetch('/cgi-bin/get-mac')
        .then(response => response.text())
        .then(data => {
            document.getElementById('mac').textContent = data.trim();
        });
    </script>
</body>
</html>
EOF2

    # Create a simple CGI script to get MAC address
    if [ -d "$WEB_DIR/cgi-bin" ]; then
        cat > $WEB_DIR/cgi-bin/get-mac << EOF2
#!/bin/sh
echo "Content-type: text/plain"
echo ""
ifconfig br-lan 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1 || \
ifconfig eth0 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1
EOF2
        chmod +x $WEB_DIR/cgi-bin/get-mac
    fi
fi

# Reset iptables rules
echo "Resetting firewall rules..."
if command -v iptables &> /dev/null; then
    # Clean up any CaptiFi chains
    iptables -t nat -F CAPTIFI_PREROUTING 2>/dev/null || true
    iptables -t nat -X CAPTIFI_PREROUTING 2>/dev/null || true
    iptables -F CAPTIFI_FORWARD 2>/dev/null || true
    iptables -X CAPTIFI_FORWARD 2>/dev/null || true
    iptables -F CAPTIFI_AUTH 2>/dev/null || true
    iptables -X CAPTIFI_AUTH 2>/dev/null || true
fi

# Reset WiFi if available
echo "Resetting WiFi configuration..."
if command -v uci &> /dev/null; then
    # Count how many wifi-iface sections exist
    IFACE_COUNT=0
    while uci get wireless.@wifi-iface[$IFACE_COUNT] > /dev/null 2>&1; do
        # Set each interface to setup mode
        echo "Resetting WiFi interface $IFACE_COUNT"
        uci set wireless.@wifi-iface[$IFACE_COUNT].ssid='CaptiFi Setup'
        uci set wireless.@wifi-iface[$IFACE_COUNT].encryption='none'
        # Remove password if present
        uci delete wireless.@wifi-iface[$IFACE_COUNT].key 2>/dev/null || true
        
        IFACE_COUNT=$((IFACE_COUNT+1))
    done
    
    echo "Configured $IFACE_COUNT WiFi interfaces for setup mode"
    
    # Apply changes
    uci commit wireless
    
    # Restart network to apply changes
    if [ -x /etc/init.d/network ]; then
        echo "Restarting network..."
        /etc/init.d/network restart
    else
        echo "Reloading wireless settings..."
        wifi reload
    fi
fi

# Remove scheduled tasks from crontab
echo "Removing scheduled tasks..."
if [ -f /etc/crontabs/root ]; then
    sed -i '/captifi/d' /etc/crontabs/root
    if [ -x /etc/init.d/cron ]; then
        /etc/init.d/cron restart
    fi
fi

# Clean up any leftover files
echo "Cleaning up additional files..."
rm -f /tmp/captifi_*.log
rm -f /tmp/heartbeat_response.txt

# Add the heartbeat script back to crontab to enable self-activation
if [ -x "$CONFIG_DIR/scripts/heartbeat.sh" ] && [ -f /etc/crontabs/root ]; then
    echo "*/5 * * * * $CONFIG_DIR/scripts/heartbeat.sh" >> /etc/crontabs/root
    if [ -x /etc/init.d/cron ]; then
        /etc/init.d/cron restart
    fi
    echo "Heartbeat service enabled for PIN activation"
fi

echo "Device has been reset to factory settings."
echo "A new activation PIN will be required to reactivate this device."
echo "Reset completed successfully."

exit 0
EOF

chmod +x "$CONFIG_DIR/reset-device.sh"

# Create the splash page
cat > "$WEB_DIR/splash.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>CaptiFi Device Activation</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 0; 
            padding: 20px; 
            text-align: center;
            background-color: #f5f7fa;
        }
        .container { 
            max-width: 500px; 
            margin: 20px auto; 
            background: #ffffff; 
            padding: 30px; 
            border-radius: 8px; 
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .logo {
            max-width: 200px;
            margin-bottom: 20px;
        }
        h1 { 
            color: #0066cc; 
            margin-top: 0;
        }
        input { 
            width: 100%; 
            padding: 12px; 
            margin: 10px 0; 
            box-sizing: border-box; 
            border: 1px solid #ddd; 
            border-radius: 4px;
            font-size: 16px;
        }
        button { 
            background: #0066cc; 
            color: white; 
            border: none; 
            padding: 12px 20px; 
            border-radius: 4px; 
            cursor: pointer; 
            font-size: 16px;
            width: 100%;
            margin-top: 10px;
        }
        button:hover { 
            background: #0055bb; 
        }
        .mac { 
            background: #eee; 
            padding: 8px; 
            border-radius: 4px; 
            font-family: monospace;
            display: inline-block;
            min-width: 150px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>CaptiFi Device Activation</h1>
        <p>This device needs to be activated with a PIN before it can be used.</p>
        
        <p>Device MAC Address: <span id="mac" class="mac">Loading...</span></p>
        
        <form action="/cgi-bin/activate.cgi" method="get">
            <input type="text" name="pin" placeholder="Enter 8-digit activation PIN" pattern="[0-9]{8}" required>
            <button type="submit">Activate Device</button>
        </form>
        
        <p>Please contact your administrator if you don't have an activation PIN.</p>
    </div>
    
    <script>
        // Get MAC address
        fetch('/cgi-bin/get-mac')
        .then(response => response.text())
        .then(data => {
            document.getElementById('mac').textContent = data.trim();
        })
        .catch(error => {
            document.getElementById('mac').textContent = 'Error fetching MAC';
        });
    </script>
</body>
</html>
EOF

# Create the CGI scripts
cat > "$CGI_DIR/get-mac" << 'EOF'
#!/bin/sh
echo "Content-type: text/plain"
echo ""
ifconfig br-lan 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1 || \
ifconfig eth0 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1
EOF

chmod +x "$CGI_DIR/get-mac"

cat > "$CGI_DIR/activate.cgi" << 'EOF'
#!/bin/sh

# Print HTTP headers
echo "Content-type: text/html"
echo ""

# Get the query string
QUERY_STRING="${QUERY_STRING:-$(echo "$REQUEST_URI" | cut -d'?' -f2)}"

# Get the PIN from query string
PIN=$(echo "$QUERY_STRING" | grep -o 'pin=[0-9]\{8\}' | cut -d'=' -f2)

# Validate PIN
if [ -z "$PIN" ] || [ ${#PIN} -ne 8 ]; then
    # Return error page for invalid PIN
    cat << EOF2
<html>
<head>
    <title>Activation Error</title>
    <meta http-equiv="refresh" content="5;url=/splash.html">
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #cc0000; }
    </style>
</head>
<body>
    <h1>Activation Error</h1>
    <p>Invalid PIN format. Please enter an 8-digit PIN.</p>
    <p>Redirecting back to activation page...</p>
</body>
</html>
EOF2
    exit 0
fi

# Get device MAC address
MAC_ADDRESS=$(ifconfig br-lan 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
if [ -z "$MAC_ADDRESS" ]; then
    MAC_ADDRESS=$(ifconfig eth0 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
fi

# Store PIN and MAC for activation
mkdir -p /etc/captifi
echo "$PIN" > /etc/captifi/activation_pin
echo "$MAC_ADDRESS" > /etc/captifi/activation_mac

# Call the device activation script
if [ -x "/etc/captifi/scripts/device-activation.sh" ]; then
    # Run activation script in the background
    (/etc/captifi/scripts/device-activation.sh "$PIN" "$MAC_ADDRESS" > /tmp/activation_log.txt 2>&1) &
    
    # Display success page immediately while activation happens in background
    cat << EOF2
<html>
<head>
    <title>Device Activation</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #0066cc; }
        .spinner {
            border: 4px solid rgba(0, 0, 0, 0.1);
            width: 36px;
            height: 36px;
            border-radius: 50%;
            border-left-color: #0066cc;
            margin: 20px auto;
            animation: spin 1s linear infinite;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <h1>Activating Device</h1>
    <p>Your device is being activated with PIN: $PIN</p>
    <p>Device MAC Address: $MAC_ADDRESS</p>
    <div class="spinner"></div>
    <p>Please wait while the device connects to the CaptiFi network. This may take a few minutes.</p>
    <p>The device will reboot automatically once activation is complete.</p>
</body>
</html>
EOF2
else
    # Return error if activation script not found
    cat << EOF2
<html>
<head>
    <title>Activation Error</title>
    <meta http-equiv="refresh" content="5;url=/splash.html">
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #cc0000; }
