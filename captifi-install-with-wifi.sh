#!/bin/sh

# CaptiFi OpenWRT Integration - Installation Script with WiFi Management
# This script installs CaptiFi with WiFi management capabilities

echo "========================================================"
echo "  CaptiFi OpenWRT Integration - WiFi Management Edition"
echo "========================================================"
echo "  PIN-Based Registration with WiFi Management Support"
echo "========================================================"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

# Base variables
INSTALL_DIR="/etc/captifi"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
WWW_DIR="/www"
CGI_DIR="/www/cgi-bin"

# Create necessary directories
echo "Creating directories..."
mkdir -p $INSTALL_DIR $SCRIPTS_DIR $WWW_DIR $CGI_DIR

# Install required packages
echo "Installing required packages..."
opkg update
opkg install curl uhttpd iptables iptables-mod-nat-extra

# Copy the script files from current directory to installation directory
echo "Copying WiFi-enabled script files..."
cp scripts/heartbeat-with-wifi.sh $SCRIPTS_DIR/heartbeat.sh
cp scripts/captifi-api.cgi $CGI_DIR/
cp scripts/test-wifi-update.sh $INSTALL_DIR/
chmod +x $SCRIPTS_DIR/heartbeat.sh $CGI_DIR/captifi-api.cgi $INSTALL_DIR/test-wifi-update.sh

# Create activation script
echo "Creating activation script..."
cat << 'EOF' > "$SCRIPTS_DIR/activate.sh"
#!/bin/sh

# CaptiFi OpenWRT Integration - Device Activation Script
# This script activates the device with CaptiFi using a PIN with curl

# Base variables
INSTALL_DIR="/etc/captifi"
SERVER_URL="https://app.captifi.io"
API_ENDPOINT="/api/plug-and-play/activate"

# Get PIN from command line or prompt if not provided
if [ -n "$1" ]; then
  PIN="$1"
else
  echo "Please enter your CaptiFi PIN:"
  read PIN
fi

# Get device information
MAC_ADDRESS=$(ifconfig br-lan | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
if [ -z "$MAC_ADDRESS" ]; then
  # Try alternative interfaces if br-lan doesn't exist
  MAC_ADDRESS=$(ifconfig eth0 | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
  if [ -z "$MAC_ADDRESS" ]; then
    # Try to get any MAC address
    MAC_ADDRESS=$(ifconfig | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
  fi
fi

MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "OpenWRT")
SERIAL=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo "Unknown")

echo "Activating device with CaptiFi..."
echo "MAC Address: $MAC_ADDRESS"
echo "Device Model: $MODEL"
echo "Serial: $SERIAL"
echo "PIN: ${PIN:0:4}****"
echo ""

# Create JSON payload
JSON="{\"pin\":\"${PIN}\",\"box_mac_address\":\"${MAC_ADDRESS}\",\"device_model\":\"${MODEL}\",\"serial\":\"${SERIAL}\"}"

# Create response file
RESP_FILE="/tmp/captifi_activation_response.txt"

# Send request using curl
echo "Sending activation request to ${SERVER_URL}${API_ENDPOINT}..."
curl -s -k -X POST -H "Content-Type: application/json" -d "$JSON" ${SERVER_URL}${API_ENDPOINT} > "$RESP_FILE"
CURL_STATUS=$?

# Check if curl command was successful
if [ $CURL_STATUS -ne 0 ]; then
  echo "Error: Failed to connect to CaptiFi server (curl status: $CURL_STATUS)."
  rm -f "$RESP_FILE"
  exit 1
fi

# Read response
RESPONSE=$(cat "$RESP_FILE" 2>/dev/null)
rm -f "$RESP_FILE"

# Extract API key and other information from response
API_KEY=$(echo "$RESPONSE" | grep -o '"api_key":"[^"]*"' | cut -d'"' -f4)
SERVER_ID=$(echo "$RESPONSE" | grep -o '"server_id":[^,}]*' | cut -d':' -f2)
SITE_ID=$(echo "$RESPONSE" | grep -o '"site_id":[^,}]*' | cut -d':' -f2)
SUCCESS=$(echo "$RESPONSE" | grep -o '"success":[^,}]*' | cut -d':' -f2)

if [ "$SUCCESS" = "true" ] && [ -n "$API_KEY" ]; then
    # Save API key and configuration
    echo "$API_KEY" > "$INSTALL_DIR/api_key"
    chmod 600 "$INSTALL_DIR/api_key"
    
    # Save additional information
    cat << CONFIG > "$INSTALL_DIR/config.json"
{
  "server_id": $SERVER_ID,
  "site_id": $SITE_ID,
  "mac_address": "$MAC_ADDRESS",
  "activation_date": "$(date +%s)"
}
CONFIG
    
    echo "Device activated successfully!"
    echo "API Key: ${API_KEY:0:6}...${API_KEY: -6}"
    
    # Copy the splash page to index.html
    cp $WWW_DIR/splash.html $WWW_DIR/index.html
    
    exit 0
else
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
    if [ -z "$ERROR_MSG" ]; then
        ERROR_MSG="Unknown error occurred"
    fi
    echo "Error: Activation failed."
    echo "Response: $ERROR_MSG"
    echo "Raw response: $RESPONSE"
    exit 1
fi
EOF
chmod +x "$SCRIPTS_DIR/activate.sh"
echo "✓ Created activation script"

# Create fetch-splash script
echo "Creating fetch-splash script..."
cat << 'EOF' > "$SCRIPTS_DIR/fetch-splash.sh"
#!/bin/sh

# CaptiFi OpenWRT Integration - Fetch Splash Page Script
# This script fetches the splash page from CaptiFi API using curl

INSTALL_DIR="/etc/captifi"
SERVER_URL="https://app.captifi.io"
API_ENDPOINT="/api/splash-page"
OUTPUT_FILE="/www/splash.html"
BACKUP_FILE="/www/splash-backup.html"
LOG_FILE="/tmp/captifi_fetch.log"

# Log function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Starting splash page fetch..."

# Check for API key
if [ ! -f "$INSTALL_DIR/api_key" ]; then
  log "API key not found. Please activate device first."
  exit 1
fi

API_KEY=$(cat "$INSTALL_DIR/api_key")
log "Using API Key: ${API_KEY:0:6}...${API_KEY: -6}"

# First, backup current splash page if it exists
if [ -f "${OUTPUT_FILE}" ]; then
  cp "${OUTPUT_FILE}" "${BACKUP_FILE}"
  log "Backed up current splash page"
fi

# Fetch splash page with curl
log "Fetching splash page from ${SERVER_URL}${API_ENDPOINT}..."
RESP_FILE="/tmp/captifi_splash_response.txt"
curl -s -k -X GET -H "Authorization: ${API_KEY}" ${SERVER_URL}${API_ENDPOINT} -o ${RESP_FILE}
CURL_STATUS=$?

if [ $CURL_STATUS -ne 0 ]; then
  log "Error: Failed to fetch splash page (status: $CURL_STATUS)."
  # Restore from backup if it exists
  if [ -f "${BACKUP_FILE}" ]; then
    cp "${BACKUP_FILE}" "${OUTPUT_FILE}"
    log "Restored splash page from backup"
  fi
  exit 1
fi

# Check if response is a JSON error message
if grep -q '"success":false' "${RESP_FILE}"; then
  ERROR_MSG=$(grep -o '"message":"[^"]*"' "${RESP_FILE}" | cut -d'"' -f4)
  log "Error: Server returned error: $ERROR_MSG"
  log "Using default splash page instead"
  
  # Use default splash page template
  cat << HTML > "${OUTPUT_FILE}"
<!DOCTYPE html>
<html>
<head>
    <title>CaptiFi Guest WiFi</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        .header { color: #4285f4; }
        .button { background-color: #4CAF50; border: none; color: white;
                 padding: 15px 32px; text-align: center; font-size: 16px;
                 margin: 20px 0; cursor: pointer; border-radius: 8px;
                 text-decoration: none; display: inline-block; }
        .footer { margin-top: 50px; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <h1 class="header">Welcome to Guest WiFi</h1>
    
    <p>Thank you for visiting.</p>
    <p>Click the button below to connect to the internet.</p>
    
    <form action="/cgi-bin/auth" method="post">
        <input type="hidden" name="accept" value="true">
        <button type="submit" class="button">Connect to Internet</button>
    </form>
    
    <div class="footer">
        <p>Powered by CaptiFi - WiFi Marketing Solution</p>
        <p>Device ID: <span id="mac-address">Loading...</span></p>
        <script>
            fetch('/cgi-bin/get-mac')
              .then(response => response.text())
              .then(mac => {
                document.getElementById('mac-address').textContent = mac;
              });
        </script>
    </div>
</body>
</html>
HTML
else
  # It's not a JSON error response, so hopefully it's HTML content
  mv "${RESP_FILE}" "${OUTPUT_FILE}"
  
  # Verify it's a valid HTML file
  if ! grep -q "<html" "${OUTPUT_FILE}"; then
    log "Error: Downloaded content doesn't appear to be valid HTML."
    log "Response content: $(cat ${OUTPUT_FILE})"
    log "Using default splash page instead"
    
    # Use default splash page template
    cat << HTML > "${OUTPUT_FILE}"
<!DOCTYPE html>
<html>
<head>
    <title>CaptiFi Guest WiFi</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        .header { color: #4285f4; }
        .button { background-color: #4CAF50; border: none; color: white;
                 padding: 15px 32px; text-align: center; font-size: 16px;
                 margin: 20px 0; cursor: pointer; border-radius: 8px;
                 text-decoration: none; display: inline-block; }
        .footer { margin-top: 50px; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <h1 class="header">Welcome to Guest WiFi</h1>
    
    <p>Thank you for visiting.</p>
    <p>Click the button below to connect to the internet.</p>
    
    <form action="/cgi-bin/auth" method="post">
        <input type="hidden" name="accept" value="true">
        <button type="submit" class="button">Connect to Internet</button>
    </form>
    
    <div class="footer">
        <p>Powered by CaptiFi - WiFi Marketing Solution</p>
        <p>Device ID: <span id="mac-address">Loading...</span></p>
        <script>
            fetch('/cgi-bin/get-mac')
              .then(response => response.text())
              .then(mac => {
                document.getElementById('mac-address').textContent = mac;
              });
        </script>
    </div>
</body>
</html>
HTML
  else
    log "Valid HTML content received."
  fi
fi

# Copy to index.html
cp ${OUTPUT_FILE} /www/index.html
log "Splash page updated successfully."
exit 0
EOF
chmod +x "$SCRIPTS_DIR/fetch-splash.sh"
echo "✓ Created fetch-splash script"

# Create auth handler script
echo "Creating authentication handler..."
cat << 'EOF' > "$CGI_DIR/auth"
#!/bin/sh

echo "Content-type: text/html"
echo ""

cat << HTML
<!DOCTYPE html>
<html>
<head>
    <title>Connected</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        .success { color: green; }
        .links { margin-top: 30px; font-size: 12px; }
    </style>
</head>
<body>
    <h1 class="success">Successfully Connected!</h1>
    <p>You now have access to the internet.</p>
    <p>Enjoy your browsing experience!</p>
    
    <div class="links">
        <p>
            <a href="/index.html">Back to Main Page</a>
        </p>
    </div>
</body>
</html>
HTML

exit 0
EOF
chmod +x "$CGI_DIR/auth"
echo "✓ Created authentication handler"

# Create PIN register script
echo "Creating PIN registration handler..."
cat << 'EOF' > "$CGI_DIR/pin-register"
#!/bin/sh

echo "Content-type: text/html"
echo ""

# Get POST data
if [ "$REQUEST_METHOD" = "POST" ]; then
  read -n "$CONTENT_LENGTH" POST_DATA
  PIN=$(echo "$POST_DATA" | grep -o 'pin=[0-9]*' | cut -d= -f2)
else
  PIN=""
fi

# Validate PIN format
if ! echo "$PIN" | grep -qE '^[0-9]{8}$'; then
  # Invalid PIN - show error
  cat << HTML
<!DOCTYPE html>
<html>
<head>
    <title>Invalid PIN</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        .error { color: red; }
        .button { background-color: #4CAF50; border: none; color: white;
                 padding: 15px 32px; text-align: center; font-size: 16px;
                 margin: 20px 0; cursor: pointer; border-radius: 8px;
                 text-decoration: none; display: inline-block; }
    </style>
</head>
<body>
    <h1 class="error">Invalid PIN Format</h1>
    <p>The PIN must be 8 digits. Please try again.</p>
    <a href="/index.html" class="button">Go Back</a>
</body>
</html>
HTML
  exit 0
fi

# Process the PIN with the actual activation script
/etc/captifi/scripts/activate.sh "$PIN" > /tmp/activation_result.log 2>&1
ACTIVATION_SUCCESS=$?

if [ $ACTIVATION_SUCCESS -eq 0 ]; then
  # Success - show button to splash page
  cat << HTML
<!DOCTYPE html>
<html>
<head>
    <title>Device Activated</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        .success { color: green; }
        .button { background-color: #4CAF50; border: none; color: white;
                 padding: 15px 32px; text-align: center; font-size: 16px;
                 margin: 20px 0; cursor: pointer; border-radius: 8px;
                 text-decoration: none; display: inline-block; }
    </style>
</head>
<body>
    <h1 class="success">Device Activated Successfully!</h1>
    <p>Your device has been successfully registered with CaptiFi.</p>
    <p>The captive portal is now configured with your custom settings.</p>
    <a href="/splash.html" class="button">Continue to Guest WiFi</a>
</body>
</html>
HTML

  # Fetch the actual splash page
  /etc/captifi/scripts/fetch-splash.sh
else
  # Activation failed
  ACTIVATION_RESULT=$(cat /tmp/activation_result.log)
  
  cat << HTML
<!DOCTYPE html>
<html>
<head>
    <title>Activation Failed</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        .error { color: red; }
        .details { background-color: #f8f8f8; padding: 20px; text-align: left; font-family: monospace; }
        .button { background-color: #4CAF50; border: none; color: white;
                 padding: 15px 32px; text-align: center; font-size: 16px;
                 margin: 20px 0; cursor: pointer; border-radius: 8px;
                 text-decoration: none; display: inline-block; }
    </style>
</head>
<body>
    <h1 class="error">Device Activation Failed</h1>
    <p>Unable to activate the device with the provided PIN. Please check your PIN and try again.</p>
    <div class="details">
        <h3>Error Details:</h3>
        <pre>${ACTIVATION_RESULT}</pre>
    </div>
    <a href="/index.html" class="button">Try Again</a>
</body>
</html>
HTML
fi

exit 0
EOF
chmod +x "$CGI_DIR/pin-register"
echo "✓ Created PIN registration handler"

# Create PIN registration page
echo "Creating PIN registration page..."
cat << 'EOF' > "$WWW_DIR/index.html"
<!DOCTYPE html>
<html>
<head>
    <title>CaptiFi Setup</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        .button { background-color: #4CAF50; border: none; color: white;
                 padding: 15px 32px; text-align: center; font-size: 16px;
                 margin: 4px 2px; cursor: pointer; border-radius: 8px; }
        input { padding: 10px; font-size: 16px; border-radius: 4px; 
               border: 1px solid #ccc; width: 200px; }
        .links { margin-top: 50px; font-size: 12px; }
    </style>
</head>
<body>
    <h1>CaptiFi Device Setup</h1>
    <p>Enter your PIN to activate this device:</p>
    <form action="/cgi-bin/pin-register" method="post">
        <input type="text" name="pin" placeholder="Enter 8-digit PIN" pattern="[0-9]{8}" required>
        <br><br>
        <button type="submit" class="button">Activate Device</button>
    </form>
    
    <div class="links">
        <p>
            <a href="/cgi-bin/luci/">Router Admin</a>
        </p>
    </div>
</body>
</html>
EOF
echo "✓ Created PIN registration page"

# Create default splash page
echo "Creating default splash page..."
cat << 'EOF' > "$WWW_DIR/splash.html"
<!DOCTYPE html>
<html>
<head>
    <title>CaptiFi Guest WiFi</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        .header { color: #4285f4; }
        .button { background-color: #4CAF50; border: none; color: white;
                 padding: 15px 32px; text-align: center; font-size: 16px;
                 margin: 20px 0; cursor: pointer; border-radius: 8px;
                 text-decoration: none; display: inline-block; }
        .footer { margin-top: 50px; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <h1 class="header">Welcome to CaptiFi Guest WiFi</h1>
    
    <p>This network is provided by CaptiFi.</p>
    <p>Click the button below to connect to the internet.</p>
    
    <form action="/cgi-bin/auth" method="post">
        <input type="hidden" name="accept" value="true">
        <button type="submit" class="button">Connect to Internet</button>
    </form>
    
    <div class="footer">
        <p>Powered by CaptiFi - WiFi Marketing Solution</p>
        <p>Device ID: <span id="mac-address">Loading...</span></p>
        <script>
            fetch('/cgi-bin/get-mac')
              .then(response => response.text())
              .then(mac => {
                document.getElementById('mac-address').textContent = mac;
              });
        </script>
    </div>
</body>
</html>
EOF
echo "✓ Created default splash page"

# Create MAC address script
echo "Creating MAC address script..."
cat << 'EOF' > "$CGI_DIR/get-mac"
#!/bin/sh

echo "Content-type: text/plain"
echo ""

# Get MAC address
ifconfig br-lan | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1
EOF
chmod +x "$CGI_DIR/get-mac"
echo "✓ Created MAC address script"

# Configure uhttpd
echo "Configuring web server..."
uci set uhttpd.main.interpreter='.cgi=/bin/sh'
uci set uhttpd.main.cgi_prefix='/cgi-bin'
uci commit uhttpd
/etc/init.d/uhttpd restart
echo "✓ Configured web server for CGI scripts"

# Add firewall rule for API access
echo "Configuring firewall for API access..."
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-Captifi-API'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].dest='wan'
uci set firewall.@rule[-1].dest_ip='157.230.53.133'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='443'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall restart
echo "✓ Added firewall rule for CaptiFi API access"

# Set up heartbeat cron job
echo "Setting up heartbeat service..."
echo "*/5 * * * * /etc/captifi/scripts/heartbeat.sh" > /etc/crontabs/root
/etc/init.d/cron enable
/etc/init.d/cron restart
echo "✓ Scheduled heartbeat service every 5 minutes"

# Create captive portal redirection script
echo "Creating captive portal redirection script..."
cat << 'EOF' > "$SCRIPTS_DIR/captive-redirect.sh"
#!/bin/sh

# CaptiFi OpenWRT Integration - Captive Portal Redirect Script
INSTALL_DIR="/etc/captifi"
WWW_DIR="/www"
ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")
STATUS_FILE="$INSTALL_DIR/captive_portal_active"

# Enable captive portal redirection
enable_captive_portal() {
    echo "Enabling captive portal redirection..."
    
    # Check if iptables is installed
    which iptables >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: iptables not found. Please install it first."
        return 1
    fi
    
    # Create a unique chain for CaptiFi redirects
    iptables -t nat -N captifi_redirect 2>/dev/null || iptables -t nat -F captifi_redirect
    
    # Add rules to redirect HTTP traffic
    iptables -t nat -A captifi_redirect -p tcp --dport 80 -j DNAT --to-destination $ROUTER_IP:80
    iptables -t nat -A captifi_redirect -p tcp --dport 443 -j DNAT --to-destination $ROUTER_IP:80
    
    # Jump to our chain from PREROUTING
    iptables -t nat -A PREROUTING -i br-lan -j captifi_redirect
    
    # Create captive portal detection files
    create_detection_files
    
    # Mark as active
    touch $STATUS_FILE
    
    echo "Captive portal redirection is now ACTIVE."
}

# Create detection files for various platforms
create_detection_files() {
    # Apple
    cat << DETECT > "$WWW_DIR/hotspot-detect.html"
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="refresh" content="0;url=http://$ROUTER_IP/">
    <title>Captive Portal Detection</title>
</head>
<body>
    <p>Redirecting to captive portal...</p>
</body>
</html>
DETECT

    # Android
    cp "$WWW_DIR/hotspot-detect.html" "$WWW_DIR/generate_204"
    
    # Microsoft
    echo "Microsoft NCSI" > "$WWW_DIR/ncsi.txt"
    
    # Generic
    echo "success" > "$WWW_DIR/success.txt"
    
    # Create symlinks for common detection paths
    mkdir -p "$WWW_DIR/library/test" 2>/dev/null
    ln -sf "$WWW_DIR/hotspot-detect.html" "$WWW_DIR/library/test/success.html" 2>/dev/null
    ln -sf "$WWW_DIR/hotspot-detect.html" "$WWW_DIR/connecttest.txt" 2>/dev/null
}

# Check arguments
if [ "$1" = "disable" ]; then
    # Remove the jump to our chain
    iptables -t nat -D PREROUTING -i br-lan -j captifi_redirect 2>/dev/null
    
    # Flush and remove our chain
    iptables -t nat -F captifi_redirect 2>/dev/null
    iptables -t nat -X captifi_redirect 2>/dev/null
    
    # Remove the status file
    rm -f $STATUS_FILE
    
    echo "Captive portal redirection is now DISABLED."
elif [ "$1" = "status" ]; then
    if [ -f "$STATUS_FILE" ]; then
        echo "Captive portal redirection is ACTIVE."
    else
        echo "Captive portal redirection is DISABLED."
    fi
else
    # Default to enable
    enable_captive_portal
fi

exit 0
EOF
chmod +x "$SCRIPTS_DIR/captive-redirect.sh"
echo "✓ Created captive portal redirection script"

# Create captive portal detection files
echo "Creating captive portal detection files..."
"$SCRIPTS_DIR/captive-redirect.sh" enable

# Set up self-activation mode marker
echo "Setting up self-activation mode..."
touch "$INSTALL_DIR/self_activate_mode"
echo "✓ Enabled self-activation mode"

# Set up auto-start for captive portal
echo "Setting up auto-start for captive portal..."
cat << 'EOF' > /etc/rc.local
#!/bin/sh
# Auto-start script for CaptiFi

# Enable captive portal redirection
if [ -f "/etc/captifi/scripts/captive-redirect.sh" ]; then
  /etc/captifi/scripts/captive-redirect.sh enable
fi

exit 0
EOF
chmod +x /etc/rc.local
echo "✓ Configured auto-start for captive portal"

# Optional: Configure WiFi
echo ""
echo "Would you like to configure WiFi settings? (y/n)"
read CONFIGURE_WIFI
if [ "$CONFIGURE_WIFI" = "y" ] || [ "$CONFIGURE_WIFI" = "Y" ]; then
  echo "Setting WiFi SSID to 'CaptiFi Setup'..."
  
  if [ -f /etc/config/wireless ]; then
    # Try to set both radio0 and radio1 if they exist
    if uci show wireless | grep -q "wireless.default_radio0"; then
      uci set wireless.default_radio0.ssid='CaptiFi Setup'
      uci set wireless.default_radio0.disabled='0'
      echo "✓ Configured 2.4GHz radio"
    fi
    
    if uci show wireless | grep -q "wireless.default_radio1"; then
      uci set wireless.default_radio1.ssid='CaptiFi Setup'
      uci set wireless.default_radio1.disabled='0'
      echo "✓ Configured 5GHz radio"
    fi
    
    # Apply changes
    uci commit wireless
    wifi reload
    echo "✓ WiFi settings applied"
  else
    echo "× Wireless configuration not found."
  fi
fi

echo ""
echo "========================================================"
echo "  CaptiFi Integration with WiFi Management Complete!"
echo "========================================================"
echo ""
echo "Your device has been configured to work with CaptiFi."
echo "Customers can now enter their PIN at http://$(uci get network.lan.ipaddr || echo "192.168.1.1")"
echo ""
echo "WiFi management is available through:"
echo "1. The CaptiFi dashboard (remote management)"
echo "2. Direct API access via /cgi-bin/captifi-api.cgi"
echo "3. Testing script at /etc/captifi/test-wifi-update.sh"
echo ""
echo "For support, contact support@captifi.io"
echo "========================================================"

exit 0
