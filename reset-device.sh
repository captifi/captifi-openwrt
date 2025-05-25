#!/bin/sh

# CaptiFi Device Reset Script
# This script resets the device to its factory state, removing all CaptiFi configurations
# and preparing it for re-activation with a new PIN
# V2.0 - Enhanced with better PIN mode activation and multiple interface support

# Ensure script exits on any error
set -e

echo "Starting CaptiFi device reset process..."

# Configuration directories
CONFIG_DIR="/etc/captifi"
WEB_DIR="/www"

# Remove API key and configuration
if [ -d "$CONFIG_DIR" ]; then
    echo "Removing API key and configuration..."
    rm -f $CONFIG_DIR/api_key
    rm -f $CONFIG_DIR/config.json
    rm -f $CONFIG_DIR/last_response
    rm -f $CONFIG_DIR/last_heartbeat
    
    # Create self-activation mode flag file
    touch $CONFIG_DIR/self_activate_mode
    echo "Device set to PIN activation mode"
fi

# Reset splash page
if [ -d "$WEB_DIR" ]; then
    echo "Removing splash page..."
    rm -f $WEB_DIR/splash.html
    rm -f $WEB_DIR/captifi-setup.html
    
    # Create a basic redirect page
    cat > $WEB_DIR/splash.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>CaptiFi Setup Required</title>
    <meta http-equiv="refresh" content="5;url=http://captifi.io/setup" />
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #0066cc; }
    </style>
</head>
<body>
    <h1>CaptiFi Setup Required</h1>
    <p>This device needs to be set up with a new activation PIN.</p>
    <p>Please contact your administrator for a new PIN.</p>
    <p>Device MAC Address: <span id="mac"></span></p>
    <script>
        fetch('/cgi-bin/get-mac')
        .then(response => response.text())
        .then(data => {
            document.getElementById('mac').textContent = data.trim();
        });
    </script>
</body>
</html>
EOF

    # Create a simple CGI script to get MAC address
    if [ -d "$WEB_DIR/cgi-bin" ]; then
        cat > $WEB_DIR/cgi-bin/get-mac << EOF
#!/bin/sh
echo "Content-type: text/plain"
echo ""
ifconfig br-lan 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1 || \
ifconfig eth0 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1
EOF
        chmod +x $WEB_DIR/cgi-bin/get-mac
    fi
fi

# Reset iptables rules
echo "Resetting firewall rules..."
if command -v iptables &> /dev/null; then
    # Clean up any CaptiFi chains
    iptables -t nat -F CAPTIFI_PREROUTING 2>/dev/null || true
    iptables -t nat -X CAPTIFI_PREROUTING 2>/dev/null || true
    iptables -F CAPTIFI_FORWARD 2>/dev/null || true
    iptables -X CAPTIFI_FORWARD 2>/dev/null || true
    iptables -F CAPTIFI_AUTH 2>/dev/null || true
    iptables -X CAPTIFI_AUTH 2>/dev/null || true
fi

# Reset WiFi if available
echo "Resetting WiFi configuration..."
if command -v uci &> /dev/null; then
    # Count how many wifi-iface sections exist
    IFACE_COUNT=0
    while uci get wireless.@wifi-iface[$IFACE_COUNT] > /dev/null 2>&1; do
        # Set each interface to setup mode
        echo "Resetting WiFi interface $IFACE_COUNT"
        uci set wireless.@wifi-iface[$IFACE_COUNT].ssid='CaptiFi Setup'
        uci set wireless.@wifi-iface[$IFACE_COUNT].encryption='none'
        # Remove password if present
        uci delete wireless.@wifi-iface[$IFACE_COUNT].key 2>/dev/null || true
        
        IFACE_COUNT=$((IFACE_COUNT+1))
    done
    
    echo "Configured $IFACE_COUNT WiFi interfaces for setup mode"
    
    # Apply changes
    uci commit wireless
    
    # Restart network to apply changes
    if [ -x /etc/init.d/network ]; then
        echo "Restarting network..."
        /etc/init.d/network restart
    else
        echo "Reloading wireless settings..."
        wifi reload
    fi
fi

# Remove scheduled tasks from crontab
echo "Removing scheduled tasks..."
if [ -f /etc/crontabs/root ]; then
    sed -i '/captifi/d' /etc/crontabs/root
    if [ -x /etc/init.d/cron ]; then
        /etc/init.d/cron restart
    fi
fi

# Clean up any leftover files
echo "Cleaning up additional files..."
rm -f /tmp/captifi_*.log
rm -f /tmp/heartbeat_response.txt

# Add the heartbeat script back to crontab to enable self-activation
if [ -x "$CONFIG_DIR/scripts/heartbeat.sh" ] && [ -f /etc/crontabs/root ]; then
    echo "*/5 * * * * $CONFIG_DIR/scripts/heartbeat.sh" >> /etc/crontabs/root
    if [ -x /etc/init.d/cron ]; then
        /etc/init.d/cron restart
    fi
    echo "Heartbeat service enabled for PIN activation"
fi

echo "Device has been reset to factory settings."
echo "A new activation PIN will be required to reactivate this device."
echo "Reset completed successfully."

exit 0
