#!/bin/sh

# CaptiFi Splash Page Fetcher - API Integration
# This script fetches rendered HTML splash pages from the CaptiFi server
# Usage: fetch-splash-page.sh [API_KEY] [SERVER_URL]

# Ensure script exits on any error
set -e

# Configuration
API_KEY=${1:-$(cat /etc/captifi/api_key 2>/dev/null)}
SERVER_URL=${2:-"https://app.captifi.io"}
MAC_ADDRESS=$(ifconfig br-lan 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1 || \
             ifconfig eth0 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
DEVICE_ID=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo "CaptiFi-OpenWrt")
OUTPUT_DIR="/www"
CONFIG_DIR="/etc/captifi"
LOGFILE="/tmp/captifi_splash.log"

# Log function
log() {
    echo "$(date): $1" >> "$LOGFILE"
    echo "$1"
}

# Validate inputs
if [ -z "$API_KEY" ]; then
    log "Error: No API key provided"
    exit 1
fi

if [ -z "$MAC_ADDRESS" ]; then
    log "Error: Could not determine device MAC address"
    exit 1
fi

log "Fetching splash page for device $DEVICE_ID with MAC $MAC_ADDRESS"

# Get site ID from config if available
SITE_ID=""
if [ -f "$CONFIG_DIR/site_id" ]; then
    SITE_ID=$(cat "$CONFIG_DIR/site_id")
fi

# Try to get splash page name from last heartbeat response
SPLASH_PAGE=""
if [ -f "$CONFIG_DIR/last_response" ]; then
    RESPONSE=$(cat "$CONFIG_DIR/last_response")
    if echo "$RESPONSE" | grep -q "\"splash_page\":"; then
        SPLASH_PAGE=$(echo "$RESPONSE" | grep -o '"splash_page":"[^"]*"' | cut -d'"' -f4)
    fi
fi

# API endpoint to fetch rendered HTML
FETCH_URL="$SERVER_URL/api/device/get-rendered-splash"

log "Requesting rendered splash page from $FETCH_URL"

# Make API request to get rendered HTML
RESPONSE=$(curl -s -X GET \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: $API_KEY" \
    "$FETCH_URL?mac_address=$MAC_ADDRESS&device_id=$DEVICE_ID&splash_page=$SPLASH_PAGE&site_id=$SITE_ID" 2>> "$LOGFILE")

# Check if response contains HTML content
if echo "$RESPONSE" | grep -q "<!DOCTYPE html>"; then
    log "Received HTML content, saving to $OUTPUT_DIR/index.html"
    
    # Create a directory for assets if it doesn't exist
    mkdir -p "$OUTPUT_DIR/assets"
    
    # Save the main HTML file
    echo "$RESPONSE" > "$OUTPUT_DIR/index.html"
    
    # Set it as the index page for the web server
    if command -v uci &> /dev/null; then
        uci set uhttpd.main.index_page='index.html'
        uci commit uhttpd
        /etc/init.d/uhttpd restart
        log "Set index.html as the default page"
    fi
    
    log "Splash page updated successfully"
    exit 0
elif echo "$RESPONSE" | grep -q "\"html\":"; then
    # If response is JSON with html field
    HTML_CONTENT=$(echo "$RESPONSE" | grep -o '"html":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$HTML_CONTENT" ] && [ "$HTML_CONTENT" != "null" ]; then
        log "Received JSON content with HTML, saving to $OUTPUT_DIR/index.html"
        echo "$HTML_CONTENT" | sed 's/\\n/\n/g; s/\\"/"/g; s/\\\\/\\/g' > "$OUTPUT_DIR/index.html"
        
        # Set it as the index page for the web server
        if command -v uci &> /dev/null; then
            uci set uhttpd.main.index_page='index.html'
            uci commit uhttpd
            /etc/init.d/uhttpd restart
            log "Set index.html as the default page"
        fi
        
        log "Splash page updated successfully"
        exit 0
    else
        log "Error: HTML content field is empty"
    fi
else
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$ERROR_MSG" ]; then
        log "Error fetching splash page: $ERROR_MSG"
    else
        log "Error: Invalid response format"
        log "Response: $RESPONSE"
    fi
    
    # Create a fallback page if fetch fails
    cat > "$OUTPUT_DIR/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>WiFi Access</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { 
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f7fa;
            text-align: center;
        }
        .container {
            max-width: 500px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #0066cc;
        }
        .button {
            display: inline-block;
            background: #0066cc;
            color: white;
            border: none;
            padding: 12px 30px;
            font-size: 16px;
            border-radius: 4px;
            cursor: pointer;
            text-decoration: none;
            margin-top: 20px;
        }
        .button:hover {
            background: #0055bb;
        }
        .mac {
            font-family: monospace;
            background: #eee;
            padding: 5px 10px;
            border-radius: 4px;
            display: inline-block;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to WiFi</h1>
        <p>You are now connected to our WiFi network.</p>
        <p>Device: <span class="mac">$MAC_ADDRESS</span></p>
        
        <p>By using this network, you agree to our terms and conditions.</p>
        
        <a href="$SERVER_URL/site/connect?mac=$MAC_ADDRESS&device_id=$DEVICE_ID" class="button">Continue to Internet</a>
    </div>
</body>
</html>
EOF
    
    # Set it as the index page for the web server
    if command -v uci &> /dev/null; then
        uci set uhttpd.main.index_page='index.html'
        uci commit uhttpd
        /etc/init.d/uhttpd restart
    fi
    
    log "Created fallback splash page"
    exit 1
fi
