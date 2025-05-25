#!/bin/sh

# CaptiFi OpenWRT Integration - Heartbeat Script
# This script sends periodic heartbeats to CaptiFi and processes commands

# Base variables
INSTALL_DIR="/etc/captifi"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
SERVER_URL="https://app.captifi.io"
API_ENDPOINT="/api/plug-and-play/heartbeat"
LOG_FILE="$INSTALL_DIR/heartbeat.log"

# Ensure log file exists
touch "$LOG_FILE"

# Rotate log if it gets too large (> 100KB)
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 102400 ]; then
  mv "$LOG_FILE" "$LOG_FILE.old"
  touch "$LOG_FILE"
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Starting heartbeat..."

# Check if API key exists
if [ ! -f "$INSTALL_DIR/api_key" ]; then
  log "Error: API key not found. Please activate your device first."
  exit 1
fi

# Get API key
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

# Get system uptime in seconds
UPTIME=$(cat /proc/uptime | awk '{print $1}')

# Send heartbeat
log "Sending heartbeat to CaptiFi (MAC: $MAC_ADDRESS, Uptime: $UPTIME)"
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"mac_address\":\"${MAC_ADDRESS}\",\"uptime\":${UPTIME},\"api_key\":\"${API_KEY}\"}" \
    ${SERVER_URL}${API_ENDPOINT})

# Check if curl command was successful
if [ $? -ne 0 ]; then
  log "Error: Failed to connect to CaptiFi server."
  exit 1
fi

# Update last heartbeat timestamp
echo "$(date +%s)" > "$INSTALL_DIR/last_heartbeat"

# Check for commands
if echo "$RESPONSE" | grep -q "\"command\":"; then
    COMMAND=$(echo "$RESPONSE" | grep -o '"command":"[^"]*"' | cut -d'"' -f4)
    log "Received command: $COMMAND"
    
    case "$COMMAND" in
        "fetch_splash")
            log "Executing command: fetch_splash"
            # Get splash page name if available
            SPLASH_PAGE=$(echo "$RESPONSE" | grep -o '"splash_page":"[^"]*"' | cut -d'"' -f4)
            if [ -n "$SPLASH_PAGE" ]; then
                log "Fetching splash page: $SPLASH_PAGE"
            fi
            # Run fetch splash script
            "$SCRIPTS_DIR/fetch-splash.sh"
            ;;
        "reboot")
            log "Executing command: reboot"
            # Schedule reboot after a short delay to allow response
            (sleep 10 && reboot) &
            ;;
        *)
            log "Unknown command: $COMMAND"
            ;;
    esac
else
    log "No commands received."
fi

# Update status with success
log "Heartbeat completed successfully."
exit 0
