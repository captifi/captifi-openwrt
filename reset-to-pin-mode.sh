#!/bin/sh

# CaptiFi OpenWRT Integration - Reset to PIN Registration Mode
# This script resets a device to PIN registration mode for redeployment

echo "========================================================"
echo "  CaptiFi Reset to PIN Registration Mode"
echo "========================================================"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

# Base variables
INSTALL_DIR="/etc/captifi"
WWW_DIR="/www"

# Check if CaptiFi is installed
if [ ! -d "$INSTALL_DIR" ]; then
  echo "Error: CaptiFi integration does not appear to be installed."
  exit 1
fi

# Confirm with user
echo "WARNING: This will reset the device to PIN registration mode."
echo "Any existing activation will be removed, and customers will"
echo "need to enter a PIN again to activate this device."
echo ""
echo "Press ENTER to continue or CTRL+C to cancel..."
read CONFIRM

# Remove API key if it exists
if [ -f "$INSTALL_DIR/api_key" ]; then
  echo "Removing API key..."
  rm -f "$INSTALL_DIR/api_key"
  rm -f "$INSTALL_DIR/config.json"
  rm -f "$INSTALL_DIR/splash_updated"
else
  echo "No API key found - device may already be in PIN registration mode."
fi

# Enable self-activation mode
echo "Enabling self-activation mode..."
touch "$INSTALL_DIR/self_activate_mode"

# Restore PIN registration page
if [ -f "$WWW_DIR/pin-registration.html" ]; then
  echo "Restoring PIN registration page..."
  cp "$WWW_DIR/pin-registration.html" "$WWW_DIR/index.html"
else
  echo "Warning: PIN registration page backup not found."
  echo "The device may still be using the default splash page."
fi

# Update Nodogsplash configuration
if [ -f /etc/config/nodogsplash ]; then
  echo "Updating Nodogsplash configuration..."
  uci set nodogsplash.@nodogsplash[0].splashpage="$WWW_DIR/index.html"
  uci commit nodogsplash
fi

# Restart services
echo "Restarting services..."
/etc/init.d/nodogsplash restart
/etc/init.d/uhttpd restart

echo ""
echo "========================================================"
echo "  Reset Complete!"
echo "========================================================"
echo ""
echo "This device has been reset to PIN registration mode."
echo "When customers connect, they will be prompted to"
echo "enter their CaptiFi PIN to activate the device."
echo ""
echo "For support, contact support@captifi.io"
echo "========================================================"
