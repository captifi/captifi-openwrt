#!/bin/sh

# CaptiFi OpenWRT Integration - Uninstallation Script
# This script removes the CaptiFi integration from an OpenWRT device

echo "========================================================"
echo "  CaptiFi OpenWRT Integration - Uninstallation"
echo "========================================================"
echo ""
echo "This script will remove all CaptiFi components from your device."
echo "Would you like to proceed? (y/n)"
read CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Uninstallation cancelled."
    exit 0
fi

# Base variables
INSTALL_DIR="/etc/captifi"
WWW_DIR="/www"
CGI_DIR="/www/cgi-bin"

# Remove CaptiFi directories and files
echo "Removing CaptiFi files..."
rm -rf $INSTALL_DIR
rm -f $CGI_DIR/pin-register $CGI_DIR/auth $CGI_DIR/get-mac
rm -f $WWW_DIR/splash.html $WWW_DIR/splash-working.html

# Restore default index.html
cat << 'EOF' > "$WWW_DIR/index.html"
<!DOCTYPE html>
<html>
<head>
    <title>OpenWRT Device</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        .button { background-color: #0066cc; border: none; color: white;
                 padding: 10px 20px; text-align: center; font-size: 16px;
                 margin: 10px; cursor: pointer; border-radius: 4px;
                 text-decoration: none; display: inline-block; }
    </style>
</head>
<body>
    <h1>OpenWRT Device</h1>
    <p>This device is running OpenWRT.</p>
    <p>To configure this device, visit the admin interface.</p>
    <a href="/cgi-bin/luci/" class="button">Admin Interface</a>
</body>
</html>
EOF
echo "✓ Restored default index.html"

# Remove captive portal detection files
rm -f $WWW_DIR/hotspot-detect.html $WWW_DIR/generate_204 $WWW_DIR/success.txt

# Remove cron job
echo "Removing scheduled tasks..."
sed -i '/captifi/d' /etc/crontabs/root
/etc/init.d/cron restart
echo "✓ Removed scheduled tasks"

# Remove firewall rule
echo "Removing firewall rules..."
RULE_PATH=$(uci show firewall | grep 'Allow-Captifi-API' | cut -d'.' -f1-2)
if [ -n "$RULE_PATH" ]; then
    uci delete $RULE_PATH
    uci commit firewall
    /etc/init.d/firewall restart
    echo "✓ Removed firewall rules"
else
    echo "× No CaptiFi firewall rules found."
fi

# Reset WiFi (optional)
echo ""
echo "Would you like to reset WiFi settings to default? (y/n)"
read RESET_WIFI

if [ "$RESET_WIFI" = "y" ] || [ "$RESET_WIFI" = "Y" ]; then
    if [ -f /etc/config/wireless ]; then
        # Reset SSIDs to OpenWrt
        if uci show wireless | grep -q "wireless.default_radio0"; then
            uci set wireless.default_radio0.ssid='OpenWrt'
            echo "✓ Reset 2.4GHz SSID"
        fi
        
        if uci show wireless | grep -q "wireless.default_radio1"; then
            uci set wireless.default_radio1.ssid='OpenWrt'
            echo "✓ Reset 5GHz SSID"
        fi
        
        # Apply changes
        uci commit wireless
        wifi reload
        echo "✓ WiFi settings reset to default"
    else
        echo "× Wireless configuration not found."
    fi
fi

# Restart web server
echo "Restarting web server..."
/etc/init.d/uhttpd restart
echo "✓ Web server restarted"

echo ""
echo "========================================================"
echo "  CaptiFi Integration Uninstallation Complete!"
echo "========================================================"
echo ""
echo "All CaptiFi components have been removed from your device."
echo ""
echo "Your router's admin interface is accessible at:"
echo "http://$(uci get network.lan.ipaddr || echo "192.168.1.1")/cgi-bin/luci/"
echo "========================================================"

exit 0
