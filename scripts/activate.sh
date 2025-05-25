#!/bin/sh

# CaptiFi OpenWRT Integration - Device Activation Script
# This script activates the device with CaptiFi using a PIN
# Can be called directly or from the PIN registration page

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

# Check if we're in self-activation mode
SELF_ACTIVATE=0
if [ -f "$INSTALL_DIR/self_activate_mode" ]; then
  SELF_ACTIVATE=1
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

# First, allow all outbound traffic for the activation
echo "Temporarily allowing internet access for activation..."
CAPTIFI_RULE=$(uci show firewall | grep -o "@rule.*CaptiFi-Block-Internet.*" | cut -d'.' -f1 | head -n 1)
if [ -n "$CAPTIFI_RULE" ]; then
  # Temporarily disable the rule by setting enabled to 0
  uci set firewall.${CAPTIFI_RULE}.enabled='0'
  uci commit firewall
  /etc/init.d/firewall restart
  echo "Internet access temporarily enabled for activation"
else
  echo "No internet blocking rule found to disable"
fi

# Create a temporary file for the response
RESP_FILE="/tmp/captifi_activation_response.txt"

# Create payload file for better compatibility
echo "{\"pin\":\"${PIN}\",\"box_mac_address\":\"${MAC_ADDRESS}\",\"device_model\":\"${MODEL}\",\"serial\":\"${SERIAL}\"}" > /tmp/captifi_payload.json

# Call the activation API - using BusyBox compatible wget parameters
echo "Sending activation request to ${SERVER_URL}${API_ENDPOINT}..."
wget -q -O "$RESP_FILE" --post-file=/tmp/captifi_payload.json ${SERVER_URL}${API_ENDPOINT}
WGET_STATUS=$?

# Check if wget command was successful
if [ $WGET_STATUS -ne 0 ]; then
  echo "Error: Failed to connect to CaptiFi server (wget status: $WGET_STATUS)."
  # Display error information
  echo "Command used: wget -q -O $RESP_FILE --post-file=/tmp/captifi_payload.json ${SERVER_URL}${API_ENDPOINT}"
  echo "Testing basic connectivity..."
  
  # Test if we can reach google.com
  wget -q --spider https://www.google.com
  if [ $? -eq 0 ]; then
    echo "Internet connection is working (can reach google.com)"
    # Add DNS entry for CaptiFi
    echo "157.230.53.133 app.captifi.io" >> /etc/hosts
    echo "Added DNS entry for app.captifi.io"
    # Try again with the DNS entry
    wget -q -O "$RESP_FILE" --post-file=/tmp/captifi_payload.json ${SERVER_URL}${API_ENDPOINT}
    WGET_STATUS=$?
    if [ $WGET_STATUS -eq 0 ]; then
      echo "Connection successful after adding DNS entry!"
    else
      echo "Still cannot connect to CaptiFi server."
      echo "Please check your internet connection and try again."
      
      # Re-enable the firewall rule before exiting
      if [ -n "$CAPTIFI_RULE" ]; then
        uci set firewall.${CAPTIFI_RULE}.enabled='1'
        uci commit firewall
        /etc/init.d/firewall restart
        echo "Internet blocking re-enabled"
      fi
      
      exit 1
    fi
  else
    echo "No internet connectivity at all. Please check your network settings."
    
    # Re-enable the firewall rule before exiting
    if [ -n "$CAPTIFI_RULE" ]; then
      uci set firewall.${CAPTIFI_RULE}.enabled='1'
      uci commit firewall
      /etc/init.d/firewall restart
      echo "Internet blocking re-enabled"
    fi
    
    exit 1
  fi
fi

# Read response
RESPONSE=$(cat "$RESP_FILE" 2>/dev/null)
rm -f "$RESP_FILE" /tmp/captifi_payload.json

# Re-enable the firewall rule after activation
if [ -n "$CAPTIFI_RULE" ]; then
  uci set firewall.${CAPTIFI_RULE}.enabled='1'
  uci commit firewall
  /etc/init.d/firewall restart
  echo "Internet blocking re-enabled after activation"
fi

# Extract API key and other information from response
API_KEY=$(echo "$RESPONSE" | grep -o '"api_key":"[^"]*"' | cut -d'"' -f4)
SERVER_ID=$(echo "$RESPONSE" | grep -o '"server_id":[^,}]*' | cut -d':' -f2)
SITE_ID=$(echo "$RESPONSE" | grep -o '"site_id":[^,}]*' | cut -d':' -f2)
WIFI_SSID=$(echo "$RESPONSE" | grep -o '"wifi_ssid":"[^"]*"' | cut -d'"' -f4)
SUCCESS=$(echo "$RESPONSE" | grep -o '"success":[^,}]*' | cut -d':' -f2)

if [ "$SUCCESS" = "true" ] && [ -n "$API_KEY" ]; then
    # Save API key and configuration
    echo "$API_KEY" > "$INSTALL_DIR/api_key"
    chmod 600 "$INSTALL_DIR/api_key"
    
    # Save additional information
    cat << EOF > "$INSTALL_DIR/config.json"
{
  "server_id": $SERVER_ID,
  "site_id": $SITE_ID,
  "wifi_ssid": "$WIFI_SSID",
  "mac_address": "$MAC_ADDRESS",
  "last_heartbeat": "$(date +%s)"
}
EOF
    
    echo "Device activated successfully!"
    echo "API Key: ${API_KEY:0:6}...${API_KEY: -6}"
    
    # Fetch splash page
    /etc/captifi/scripts/fetch-splash.sh
    
    # If we were in self-activation mode, remove the marker
    if [ $SELF_ACTIVATE -eq 1 ]; then
        rm -f "$INSTALL_DIR/self_activate_mode"
        echo "Device removed from self-activation mode."
    fi
    
    exit 0
else
    ERROR_MSG=$(echo "$RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
    echo "Error: Activation failed."
    echo "Response: $ERROR_MSG"
    echo "Raw response: $RESPONSE"
    exit 1
fi
