#!/bin/sh

# CaptiFi OpenWRT Integration - WiFi Management Test Script
# This script allows testing the WiFi management functionality

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "${BLUE}CaptiFi WiFi Management Test Script${NC}"
echo "This script helps you test the WiFi management functionality."
echo ""

# Check if API key exists
INSTALL_DIR="/etc/captifi"
API_KEY_FILE="$INSTALL_DIR/api_key"

if [ ! -f "$API_KEY_FILE" ]; then
  echo "${RED}Error: API key not found. Please activate the device first.${NC}"
  exit 1
fi

API_KEY=$(cat "$API_KEY_FILE")
echo "${GREEN}Using API key: $API_KEY${NC}"

# Menu function
show_menu() {
  echo ""
  echo "${YELLOW}===== WiFi Update Test Menu =====${NC}"
  echo "1) Show current WiFi settings"
  echo "2) Update WiFi SSID (secured with password)"
  echo "3) Set open WiFi network (no password)"
  echo "4) Test API connection"
  echo "5) Exit"
  echo ""
  echo -n "Enter your choice [1-5]: "
}

# Show current WiFi settings
show_current_wifi() {
  echo "${BLUE}Current WiFi Settings:${NC}"
  
  if command -v uci &> /dev/null; then
    SSID=$(uci get wireless.@wifi-iface[0].ssid 2>/dev/null || echo "Not set")
    ENCRYPTION=$(uci get wireless.@wifi-iface[0].encryption 2>/dev/null || echo "Not set")
    
    if [ "$ENCRYPTION" = "none" ]; then
      PASSWORD="Open network (no password)"
    else
      PASSWORD=$(uci get wireless.@wifi-iface[0].key 2>/dev/null || echo "Not set")
      PASSWORD="********" # Mask the actual password for security
    fi
    
    echo "SSID: $SSID"
    echo "Encryption: $ENCRYPTION"
    echo "Password: $PASSWORD"
  else
    echo "${RED}UCI command not available. Cannot read WiFi settings.${NC}"
  fi
}

# Update WiFi settings
update_wifi() {
  local ssid="$1"
  local password="$2"
  local encryption="$3"
  
  # Prepare JSON data
  if [ -n "$password" ]; then
    JSON="{\"command\":\"update_wifi\",\"auth_token\":\"$API_KEY\",\"ssid\":\"$ssid\",\"password\":\"$password\",\"encryption\":\"$encryption\"}"
  else
    JSON="{\"command\":\"update_wifi\",\"auth_token\":\"$API_KEY\",\"ssid\":\"$ssid\"}"
  fi
  
  echo "${YELLOW}Sending request to update WiFi settings...${NC}"
  echo "Request: $JSON"
  
  # Send request to the API endpoint
  RESPONSE=$(echo "$JSON" | curl -s -X POST -H "Content-Type: application/json" --data-binary @- http://localhost/cgi-bin/captifi-api.cgi)
  
  if [ $? -eq 0 ]; then
    echo "${GREEN}Response: $RESPONSE${NC}"
    echo ""
    echo "${GREEN}WiFi update requested. Changes should take effect within 30 seconds.${NC}"
  else
    echo "${RED}Error communicating with API endpoint.${NC}"
  fi
}

# Test API connection
test_api() {
  echo "${YELLOW}Testing API connection...${NC}"
  
  # Prepare JSON data for status request
  JSON="{\"command\":\"status\",\"auth_token\":\"$API_KEY\"}"
  
  # Send request to the API endpoint
  RESPONSE=$(echo "$JSON" | curl -s -X POST -H "Content-Type: application/json" --data-binary @- http://localhost/cgi-bin/captifi-api.cgi)
  
  if [ $? -eq 0 ]; then
    echo "${GREEN}API is responsive!${NC}"
    echo "Response: $RESPONSE"
  else
    echo "${RED}Error: API endpoint is not responding.${NC}"
    echo "Make sure the CGI script is properly installed and executable."
    echo "Check if the web server is running and CGI is enabled."
  fi
}

# Main loop
while true; do
  show_menu
  read choice
  
  case "$choice" in
    1)
      show_current_wifi
      ;;
    2)
      echo ""
      echo "${BLUE}Update WiFi with Password${NC}"
      echo -n "Enter new SSID: "
      read new_ssid
      echo -n "Enter password (8-63 characters): "
      read new_password
      echo -n "Enter encryption type (psk2, psk, psk-mixed) [default: psk2]: "
      read encryption
      
      # Set default encryption if not provided
      [ -z "$encryption" ] && encryption="psk2"
      
      # Validate inputs
      if [ -z "$new_ssid" ]; then
        echo "${RED}Error: SSID cannot be empty.${NC}"
      elif [ -z "$new_password" ]; then
        echo "${RED}Error: Password cannot be empty.${NC}"
      elif [ ${#new_password} -lt 8 ]; then
        echo "${RED}Error: Password must be at least 8 characters.${NC}"
      else
        update_wifi "$new_ssid" "$new_password" "$encryption"
      fi
      ;;
    3)
      echo ""
      echo "${BLUE}Set Open WiFi Network (No Password)${NC}"
      echo -n "Enter new SSID: "
      read new_ssid
      
      # Validate input
      if [ -z "$new_ssid" ]; then
        echo "${RED}Error: SSID cannot be empty.${NC}"
      else
        update_wifi "$new_ssid" "" "none"
      fi
      ;;
    4)
      test_api
      ;;
    5)
      echo "${GREEN}Exiting test script.${NC}"
      exit 0
      ;;
    *)
      echo "${RED}Invalid choice. Please enter a number between 1 and 5.${NC}"
      ;;
  esac
  
  echo ""
  echo "${YELLOW}Press Enter to continue...${NC}"
  read dummy
done
