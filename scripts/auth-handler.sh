#!/bin/sh

# CaptiFi OpenWRT Integration - Guest Authentication Handler
# This script handles guest authentication with CaptiFi API

# Base variables
INSTALL_DIR="/etc/captifi"
SERVER_URL="https://app.captifi.io"
API_ENDPOINT="/api/plug-and-play/guest-connect"
LOG_FILE="$INSTALL_DIR/auth.log"

# Ensure log file exists
touch "$LOG_FILE"

# Rotate log if it gets too large (> 1MB)
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 1048576 ]; then
  mv "$LOG_FILE" "$LOG_FILE.old"
  touch "$LOG_FILE"
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Parse query string
parse_query_string() {
  local query_string="$1"
  local param_name="$2"
  echo "$query_string" | tr '&' '\n' | grep "^$param_name=" | cut -d'=' -f2- | sed 's/+/ /g;s/%/\\x/g' | xargs -0 printf "%b"
}

# Read API key
if [ ! -f "$INSTALL_DIR/api_key" ]; then
  log "Error: API key not found. Please activate your device first."
  echo "Status: 500 Internal Server Error"
  echo "Content-Type: text/plain"
  echo
  echo "Server Error: Device not activated"
  exit 1
fi

API_KEY=$(cat "$INSTALL_DIR/api_key")

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

# Read POST data
CONTENT_LENGTH=$(env | grep -o 'CONTENT_LENGTH=[0-9]*' | cut -d'=' -f2)
if [ -z "$CONTENT_LENGTH" ]; then
  CONTENT_LENGTH=0
fi

if [ "$CONTENT_LENGTH" -gt 0 ]; then
  POST_DATA=$(dd bs=1 count=$CONTENT_LENGTH 2>/dev/null)
else
  # Handle GET requests
  POST_DATA="$QUERY_STRING"
fi

# Extract guest information
GUEST_MAC=$(parse_query_string "$POST_DATA" "mac")
GUEST_NAME=$(parse_query_string "$POST_DATA" "name")
GUEST_EMAIL=$(parse_query_string "$POST_DATA" "email")
GUEST_PHONE=$(parse_query_string "$POST_DATA" "phone")
GUEST_OPT_IN=$(parse_query_string "$POST_DATA" "marketing_opt_in")

# Default opt_in to false if not specified
if [ -z "$GUEST_OPT_IN" ] || [ "$GUEST_OPT_IN" != "true" ]; then
  GUEST_OPT_IN="false"
fi

log "Processing auth request for guest MAC: $GUEST_MAC"
log "Guest details - Name: $GUEST_NAME, Email: $GUEST_EMAIL, Phone: $GUEST_PHONE, Opt-in: $GUEST_OPT_IN"

# Prepare JSON payload
JSON_PAYLOAD="{\"api_key\":\"${API_KEY}\",\"mac_address\":\"${MAC_ADDRESS}\",\"guest_data\":{\"name\":\"${GUEST_NAME}\",\"email\":\"${GUEST_EMAIL}\",\"phone\":\"${GUEST_PHONE}\",\"marketing_opt_in\":${GUEST_OPT_IN}}}"

# Temporarily disable internet blocking for API access
log "Temporarily allowing internet access for API communication..."
CAPTIFI_RULE=$(uci show firewall | grep -o "@rule.*CaptiFi-Block-Internet.*" | cut -d'.' -f1 | head -n 1)
if [ -n "$CAPTIFI_RULE" ]; then
  # Temporarily disable the rule by setting enabled to 0
  uci set firewall.${CAPTIFI_RULE}.enabled='0'
  uci commit firewall
  /etc/init.d/firewall restart
  log "Internet access temporarily enabled"
else
  log "No internet blocking rule found to disable"
fi

# Send data to CaptiFi API
log "Sending guest data to CaptiFi API"
# Create temporary file for response
RESP_FILE="/tmp/captifi_auth_response.txt"
wget -q -O "$RESP_FILE" --post-data="$JSON_PAYLOAD" \
  ${SERVER_URL}${API_ENDPOINT}
WGET_STATUS=$?

# Re-enable the firewall rule
if [ -n "$CAPTIFI_RULE" ]; then
  uci set firewall.${CAPTIFI_RULE}.enabled='1'
  uci commit firewall
  /etc/init.d/firewall restart
  log "Internet blocking re-enabled"
fi

RESPONSE=$(cat "$RESP_FILE" 2>/dev/null)
rm -f "$RESP_FILE"

# Check if wget command was successful
if [ $? -ne 0 ]; then
  log "Error: Failed to connect to CaptiFi server."
  echo "Status: 500 Internal Server Error"
  echo "Content-Type: text/plain"
  echo
  echo "Server Error: Failed to connect to authentication server"
  exit 1
fi

# Process response
SUCCESS=$(echo "$RESPONSE" | grep -o '"success":[^,}]*' | cut -d':' -f2)
REDIRECT_URL=$(echo "$RESPONSE" | grep -o '"redirect_url":"[^"]*"' | cut -d'"' -f4)

if [ "$SUCCESS" = "true" ]; then
  log "Authentication successful. Redirecting guest to: $REDIRECT_URL"
  
  # Allow guest through firewall (typically handled by Nodogsplash)
  # This is a fallback in case Nodogsplash doesn't handle it automatically
  if [ -n "$GUEST_MAC" ]; then
    # Authorize in Nodogsplash
    ndsctl auth "$GUEST_MAC"
    log "Guest MAC $GUEST_MAC authorized in Nodogsplash"
  fi
  
  # Return success with redirect
  echo "Status: 302 Found"
  echo "Location: $REDIRECT_URL"
  echo "Content-Type: text/plain"
  echo
  echo "Authentication successful. Redirecting..."
  
  # Log success
  log "Guest authentication completed successfully."
else
  ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
  log "Authentication failed. Error: $ERROR_MSG"
  
  echo "Status: 400 Bad Request"
  echo "Content-Type: text/plain"
  echo
  echo "Authentication Error: $ERROR_MSG"
fi
