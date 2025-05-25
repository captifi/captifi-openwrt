#!/bin/sh

# CaptiFi OpenWRT Integration - Heartbeat Script
# This script sends heartbeat to CaptiFi API using curl
# V2.0 - Enhanced error handling and retry logic

INSTALL_DIR="/etc/captifi"
SERVER_URL="https://app.captifi.io"
API_ENDPOINT="/api/plug-and-play/heartbeat"
LOG_FILE="/tmp/captifi_heartbeat.log"
MAX_RETRIES=3
RETRY_DELAY=5

# Log function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
  # Keep log file size reasonable - only keep last 100 lines
  if [ -f "$LOG_FILE" ] && [ $(wc -l < "$LOG_FILE") -gt 100 ]; then
    tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
  fi
}

log "Starting heartbeat..."

# Check for API key
if [ ! -f "$INSTALL_DIR/api_key" ]; then
  log "API key not found. Please activate device first."
  exit 1
fi

# Get device information
API_KEY=$(cat "$INSTALL_DIR/api_key")
MAC_ADDRESS=$(ifconfig br-lan 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)

# If br-lan interface doesn't exist, try other common interfaces
if [ -z "$MAC_ADDRESS" ]; then
  for iface in eth0 eth1 wlan0 wlan1; do
    MAC_ADDRESS=$(ifconfig $iface 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
    if [ -n "$MAC_ADDRESS" ]; then
      break
    fi
  done
  
  # Last resort: get any MAC address from any interface
  if [ -z "$MAC_ADDRESS" ]; then
    MAC_ADDRESS=$(ifconfig | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
    if [ -z "$MAC_ADDRESS" ]; then
      log "Error: Could not find a valid MAC address"
      MAC_ADDRESS="00:00:00:00:00:00"  # Fallback default
    fi
  fi
fi

UPTIME=$(cat /proc/uptime | cut -d' ' -f1)
HOSTNAME=$(cat /proc/sys/kernel/hostname)
CONNECTIONS=$(cat /proc/net/nf_conntrack 2>/dev/null | wc -l || echo "0")
MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "OpenWRT")

# Enhanced payload with additional system information
JSON="{\"mac_address\":\"${MAC_ADDRESS}\",\"uptime\":${UPTIME},\"api_key\":\"${API_KEY}\",\"hostname\":\"${HOSTNAME}\",\"connections\":${CONNECTIONS},\"model\":\"${MODEL}\"}"

log "Sending heartbeat with payload: $JSON"

# DNS resolution check
if ! nslookup app.captifi.io > /dev/null 2>&1; then
  log "DNS resolution failing, adding static host entry"
  grep -q "app.captifi.io" /etc/hosts || echo "157.230.53.133 app.captifi.io" >> /etc/hosts
fi

# Send heartbeat with retries
RETRY=0
SUCCESS=false
while [ $RETRY -lt $MAX_RETRIES ] && [ "$SUCCESS" != "true" ]; do
  RESP_FILE="/tmp/heartbeat_response.txt"
  
  # Verbose logging for debugging
  log "Attempt $((RETRY+1)) of $MAX_RETRIES connecting to $SERVER_URL$API_ENDPOINT"
  
  # Using -k to ignore SSL verification issues that might occur on OpenWRT
  curl -s -k -X POST \
       -H "Content-Type: application/json" \
       -H "Connection: close" \
       -d "$JSON" \
       --connect-timeout 10 \
       --max-time 20 \
       ${SERVER_URL}${API_ENDPOINT} > "$RESP_FILE" 2>> "$LOG_FILE"
  
  CURL_STATUS=$?
  
  if [ $CURL_STATUS -eq 0 ] && [ -s "$RESP_FILE" ]; then
    RESPONSE=$(cat "$RESP_FILE")
    log "Heartbeat response: $RESPONSE"
    
    # Validate response format - look for valid JSON response
    if echo "$RESPONSE" | grep -q -E '^\{.*\}$'; then
      SUCCESS=true
      
      # Check for commands in response
      if echo "$RESPONSE" | grep -q '"command":'; then
        COMMAND=$(echo "$RESPONSE" | grep -o '"command":"[^"]*"' | cut -d'"' -f4)
        log "Received command: $COMMAND"
        
        case "$COMMAND" in
          "fetch_splash")
            log "Executing command: fetch_splash"
            $SCRIPTS_DIR/fetch-splash.sh
            ;;
          "reboot")
            log "Executing command: reboot"
            reboot
            ;;
          "reset")
            log "Executing command: reset device to PIN mode"
            if [ -f "$INSTALL_DIR/scripts/reset-to-pin-mode.sh" ]; then
              $INSTALL_DIR/scripts/reset-to-pin-mode.sh --auto
            else
              log "Error: Reset script not found"
              # Fall back to manual reset if script not found
              rm -f "$INSTALL_DIR/api_key" "$INSTALL_DIR/config.json"
              touch "$INSTALL_DIR/self_activate_mode"
              log "Removed API key and reset to self-activation mode"
            fi
            ;;
          *)
            log "Unknown command: $COMMAND"
            ;;
        esac
      fi
      
      # Record last successful heartbeat time
      date +%s > "$INSTALL_DIR/last_heartbeat"
      echo "$RESPONSE" > "$INSTALL_DIR/last_response"
    else
      log "Error: Received malformed response"
      RETRY=$((RETRY+1))
    fi
  else
    log "Error: Heartbeat failed with curl status $CURL_STATUS"
    RETRY=$((RETRY+1))
    
    if [ $RETRY -lt $MAX_RETRIES ]; then
      log "Retrying in $RETRY_DELAY seconds..."
      sleep $RETRY_DELAY
    fi
  fi
  
  rm -f "$RESP_FILE"
done

if [ "$SUCCESS" = "true" ]; then
  log "Heartbeat completed successfully"
else
  log "All heartbeat attempts failed"
fi

exit 0
