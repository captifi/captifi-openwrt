#!/bin/sh

# CaptiFi OpenWRT Integration - Fetch Splash Page Script
# This script fetches the splash page from CaptiFi API
# After activation, it replaces the PIN registration page with the actual splash page

# Base variables
INSTALL_DIR="/etc/captifi"
SERVER_URL="https://app.captifi.io"
API_ENDPOINT="/api/splash-page"
OUTPUT_DIR="/www"
OUTPUT_FILE="$OUTPUT_DIR/splash.html"

# Check if API key exists
if [ ! -f "$INSTALL_DIR/api_key" ]; then
  echo "Error: API key not found. Please activate your device first."
  exit 1
fi

# Get API key
API_KEY=$(cat "$INSTALL_DIR/api_key")

echo "Fetching splash page from CaptiFi..."

# Fetch the splash page - BusyBox compatible wget
# Note: Without header support, we need to ensure the API accepts the key in the URL
# Create URL with API key as query parameter
FETCH_URL="${SERVER_URL}${API_ENDPOINT}?api_key=${API_KEY}"
wget -q -O ${OUTPUT_FILE} "${FETCH_URL}"

# Check if wget command was successful
if [ $? -ne 0 ]; then
  echo "Error: Failed to fetch splash page from CaptiFi server."
  exit 1
fi

# Verify the splash page was downloaded
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
  # Check if the file contains HTML
  if grep -q "<!DOCTYPE html>" "$OUTPUT_FILE" || grep -q "<html" "$OUTPUT_FILE"; then
    echo "Splash page downloaded successfully to $OUTPUT_FILE"
    
    # Check if we were in self-activation mode
    if [ -f "$INSTALL_DIR/self_activate_mode" ]; then
      echo "Switching from PIN registration to customer splash page..."
      
      # Copy the splash page to index.html to replace the PIN registration page
      cp "$OUTPUT_FILE" "$OUTPUT_DIR/index.html"
      
      # Keep a backup of the PIN registration page in case we need it again
      if [ ! -f "$OUTPUT_DIR/pin-registration.html" ]; then
        cp "$OUTPUT_DIR/index.html" "$OUTPUT_DIR/pin-registration.html"
      fi
    fi
    
    # Update Nodogsplash configuration to use this splash page
    if [ -f /etc/config/nodogsplash ]; then
      # In self-activation mode, we use index.html as the splash
      # After activation, we continue using index.html but with the customer's content
      uci set nodogsplash.@nodogsplash[0].splashpage="$OUTPUT_DIR/index.html"
      uci commit nodogsplash
      
      # Restart Nodogsplash to apply changes
      /etc/init.d/nodogsplash restart
      
      echo "Nodogsplash configuration updated and service restarted."
    else
      echo "Warning: Nodogsplash configuration not found."
    fi
    
    # Create success marker
    touch "$INSTALL_DIR/splash_updated"
    
    exit 0
  else
    echo "Error: Downloaded file is not a valid HTML splash page."
    # Save the response for debugging
    mv "$OUTPUT_FILE" "$OUTPUT_FILE.error"
    echo "Response saved to $OUTPUT_FILE.error for debugging."
    exit 1
  fi
else
  echo "Error: Failed to download splash page or file is empty."
  exit 1
fi
