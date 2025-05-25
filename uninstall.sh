#!/bin/sh

# CaptiFi OpenWRT Integration - Uninstallation Script
# This script removes the CaptiFi integration from an OpenWRT device

echo "========================================================"
echo "  CaptiFi OpenWRT Integration Uninstallation"
echo "========================================================"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

# Stop services
echo "Stopping services..."
/etc/init.d/nodogsplash stop
/etc/init.d/nodogsplash disable

# Remove cron job
echo "Removing cron job..."
sed -i '/captifi\/scripts\/heartbeat.sh/d' /etc/crontabs/root
/etc/init.d/cron restart

# Remove firewall rule
echo "Removing firewall rule..."
# Find and remove the CaptiFi API firewall rule
rule_index=$(uci show firewall | grep "Allow-Captifi-API" | cut -d'.' -f2 | cut -d'=' -f1)
if [ -n "$rule_index" ]; then
  uci delete firewall.${rule_index}
  uci commit firewall
  /etc/init.d/firewall restart
  echo "Firewall rule removed."
else
  echo "Firewall rule not found."
fi

# Restore original wireless configuration
echo "Restoring wireless configuration..."
if [ -f /etc/config/wireless ]; then
  # Ask if the user wants to reset the SSID
  echo ""
  echo "Do you want to reset the 'CaptiFi Setup' WiFi name?"
  echo "Enter 'y' to reset or any other key to leave as is:"
  read RESET_WIFI
  
  if [ "$RESET_WIFI" = "y" ] || [ "$RESET_WIFI" = "Y" ]; then
    echo "Resetting WiFi names..."
    
    # Reset radio0 if it has CaptiFi Setup name
    if uci show wireless | grep -q "wireless.default_radio0.ssid='CaptiFi Setup'"; then
      echo "Resetting radio0 SSID to default..."
      uci set wireless.default_radio0.ssid='OpenWrt'
    fi
    
    # Reset radio1 if it has CaptiFi Setup name
    if uci show wireless | grep -q "wireless.default_radio1.ssid='CaptiFi Setup'"; then
      echo "Resetting radio1 SSID to default..."
      uci set wireless.default_radio1.ssid='OpenWrt'
    fi
    
    # Commit changes and restart wireless
    uci commit wireless
    wifi reload
    echo "Wireless configuration reset to default."
  else
    echo "Wireless configuration left unchanged."
  fi
else
  echo "Wireless configuration not found."
fi

# Remove files
echo "Removing files..."
rm -rf /etc/captifi
rm -f /www/splash.html
rm -f /www/splash.html.error
rm -f /www/index.html
rm -f /www/pin-registration.html
rm -f /www/cgi-bin/pin-register
rm -f /etc/config/nodogsplash

# Restore uhttpd configuration
echo "Restoring web server configuration..."
uci delete uhttpd.main.interpreter
uci delete uhttpd.main.cgi_prefix
uci commit uhttpd
/etc/init.d/uhttpd restart

echo ""
echo "========================================================"
echo "  CaptiFi Integration Uninstallation Complete!"
echo "========================================================"
echo ""
echo "The CaptiFi integration has been removed from your device."
echo ""
echo "Note: The following packages were not removed:"
echo "- nodogsplash"
echo "- curl"
echo "- bash"
echo "- uhttpd"
echo ""
echo "If you wish to remove these packages, use:"
echo "opkg remove nodogsplash curl bash uhttpd"
echo "========================================================"
