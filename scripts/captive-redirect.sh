#!/bin/sh

# CaptiFi OpenWRT Integration - Captive Portal Redirect Script
# This script creates lightweight captive portal redirection without nodogsplash

INSTALL_DIR="/etc/captifi"
WWW_DIR="/www"
ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")
STATUS_FILE="$INSTALL_DIR/captive_portal_active"

# Usage information
usage() {
    echo "Usage: $0 [enable|disable|status]"
    echo ""
    echo "Commands:"
    echo "  enable   - Enable captive portal redirection"
    echo "  disable  - Disable captive portal redirection"
    echo "  status   - Check if captive portal redirection is active"
    echo ""
    exit 1
}

# Check if iptables is installed
check_dependencies() {
    which iptables >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: iptables not found. Please install it with:"
        echo "opkg update && opkg install iptables iptables-mod-nat-extra"
        exit 1
    fi
}

# Enable captive portal redirection
enable_captive_portal() {
    echo "Enabling captive portal redirection..."
    
    # Create a unique chain for CaptiFi redirects
    iptables -t nat -N captifi_redirect 2>/dev/null || iptables -t nat -F captifi_redirect
    
    # Add rules to redirect HTTP traffic
    iptables -t nat -A captifi_redirect -p tcp --dport 80 -j DNAT --to-destination $ROUTER_IP:80
    iptables -t nat -A captifi_redirect -p tcp --dport 443 -j DNAT --to-destination $ROUTER_IP:80
    
    # Jump to our chain from PREROUTING
    iptables -t nat -A PREROUTING -i br-lan -j captifi_redirect
    
    # Create captive portal detection files
    create_detection_files
    
    # Mark as active
    touch $STATUS_FILE
    
    echo "Captive portal redirection is now ACTIVE."
}

# Disable captive portal redirection
disable_captive_portal() {
    echo "Disabling captive portal redirection..."
    
    # Remove the jump to our chain
    iptables -t nat -D PREROUTING -i br-lan -j captifi_redirect 2>/dev/null
    
    # Flush and remove our chain
    iptables -t nat -F captifi_redirect 2>/dev/null
    iptables -t nat -X captifi_redirect 2>/dev/null
    
    # Remove the status file
    rm -f $STATUS_FILE
    
    echo "Captive portal redirection is now DISABLED."
}

# Check status
check_status() {
    if [ -f "$STATUS_FILE" ]; then
        echo "Captive portal redirection is ACTIVE."
        return 0
    else
        echo "Captive portal redirection is DISABLED."
        return 1
    fi
}

# Create detection files for various platforms
create_detection_files() {
    # Apple
    cat << EOF > "$WWW_DIR/hotspot-detect.html"
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="refresh" content="0;url=http://$ROUTER_IP/">
    <title>Captive Portal Detection</title>
</head>
<body>
    <p>Redirecting to captive portal...</p>
</body>
</html>
EOF

    # Android
    cp "$WWW_DIR/hotspot-detect.html" "$WWW_DIR/generate_204"
    
    # Microsoft
    echo "Microsoft NCSI" > "$WWW_DIR/ncsi.txt"
    
    # Generic
    echo "success" > "$WWW_DIR/success.txt"
    
    # Create symlinks for common detection paths
    ln -sf "$WWW_DIR/hotspot-detect.html" "$WWW_DIR/library/test/success.html" 2>/dev/null
    ln -sf "$WWW_DIR/hotspot-detect.html" "$WWW_DIR/connecttest.txt" 2>/dev/null
    
    echo "Created captive portal detection files."
}

# Main script logic
if [ $# -eq 0 ]; then
    usage
fi

check_dependencies

case "$1" in
    "enable")
        enable_captive_portal
        ;;
    "disable")
        disable_captive_portal
        ;;
    "status")
        check_status
        ;;
    *)
        usage
        ;;
esac

exit 0
