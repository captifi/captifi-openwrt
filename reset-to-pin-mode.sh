#!/bin/sh

# CaptiFi OpenWRT Integration - PIN Reset Script
# This script resets a device to PIN registration mode without full uninstallation

echo "========================================================"
echo "  CaptiFi OpenWRT Integration - Reset to PIN Mode"
echo "========================================================"
echo ""
# Check for auto mode
AUTO_MODE=0
if [ "$1" = "--auto" ]; then
    AUTO_MODE=1
fi

if [ $AUTO_MODE -eq 0 ]; then
    echo "This script will reset this device to PIN registration mode."
    echo "All current CaptiFi activation data will be removed."
    echo "Would you like to proceed? (y/n)"
    read CONFIRM

    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "Reset cancelled."
        exit 0
    fi
else
    echo "Automated reset mode: resetting device to PIN registration mode..."
fi

# Base variables
INSTALL_DIR="/etc/captifi"
WWW_DIR="/www"

# Check if CaptiFi is installed
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Error: CaptiFi is not installed on this device."
    exit 1
fi

# Remove API key and configuration
echo "Removing activation data..."
rm -f "$INSTALL_DIR/api_key"
rm -f "$INSTALL_DIR/config.json"
touch "$INSTALL_DIR/self_activate_mode"
echo "✓ Removed API key and configuration"

# Reset web interface to registration page
echo "Resetting web interface to PIN registration..."
cat << 'EOF' > "$WWW_DIR/index.html"
<!DOCTYPE html>
<html>
<head>
    <title>CaptiFi Setup</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        .button { background-color: #4CAF50; border: none; color: white;
                 padding: 15px 32px; text-align: center; font-size: 16px;
                 margin: 4px 2px; cursor: pointer; border-radius: 8px; }
        input { padding: 10px; font-size: 16px; border-radius: 4px; 
               border: 1px solid #ccc; width: 200px; }
        .links { margin-top: 50px; font-size: 12px; }
    </style>
</head>
<body>
    <h1>CaptiFi Device Setup</h1>
    <p>Enter your PIN to activate this device:</p>
    <form action="/cgi-bin/pin-register" method="post">
        <input type="text" name="pin" placeholder="Enter 8-digit PIN" pattern="[0-9]{8}" required>
        <br><br>
        <button type="submit" class="button">Activate Device</button>
    </form>
    
    <div class="links">
        <p>
            <a href="/cgi-bin/luci/">Router Admin</a>
        </p>
    </div>
</body>
</html>
EOF
echo "✓ Reset to PIN registration page"

# Restart web server
echo "Restarting web server..."
/etc/init.d/uhttpd restart
echo "✓ Web server restarted"

echo ""
echo "========================================================"
echo "  Reset to PIN Mode Complete!"
echo "========================================================"
echo ""
echo "This device is now ready for activation with a new PIN."
echo "Navigate to http://$(uci get network.lan.ipaddr || echo "192.168.1.1") to register."
echo ""
echo "For support, contact support@captifi.io"
echo "========================================================"

exit 0
