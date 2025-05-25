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
  
  # Use our default splash page template
  cat << 'HTML' > "${OUTPUT_FILE}"
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
    
    # Use our default splash page template
    cat << 'HTML' > "${OUTPUT_FILE}"
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
