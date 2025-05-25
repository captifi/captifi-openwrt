#!/bin/sh

# CaptiFi OpenWRT Integration - Installation Script
# This script installs and configures the CaptiFi integration with Nodogsplash

echo "========================================================"
echo "  CaptiFi OpenWRT Integration Installation"
echo "========================================================"
echo "  PIN-Based Registration Version"
echo "========================================================"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

# Base variables
GITHUB_REPO="https://raw.githubusercontent.com/captifi/captifi-openwrt/main"
INSTALL_DIR="/etc/captifi"
CONFIG_DIR="$INSTALL_DIR/config"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
WWW_DIR="/www"
CGI_DIR="/www/cgi-bin"

# Create necessary directories
echo "Creating directories..."
mkdir -p $INSTALL_DIR $CONFIG_DIR $SCRIPTS_DIR $WWW_DIR $CGI_DIR

# Install required packages
echo "Installing required packages..."
opkg update
opkg install wget nodogsplash bash uhttpd
# Note: uhttpd in OpenWrt 23.05+ already includes CGI support without a separate package

# Download scripts from GitHub
echo "Downloading scripts..."
download_file() {
  wget -q -O "$2" "$GITHUB_REPO/$1"
  chmod +x "$2"
  echo "Downloaded: $2"
}

download_file "scripts/activate.sh" "$SCRIPTS_DIR/activate.sh"
download_file "scripts/fetch-splash.sh" "$SCRIPTS_DIR/fetch-splash.sh"
download_file "scripts/heartbeat.sh" "$SCRIPTS_DIR/heartbeat.sh"
download_file "scripts/auth-handler.sh" "$SCRIPTS_DIR/auth-handler.sh"
download_file "scripts/pin-register.cgi" "$SCRIPTS_DIR/pin-register.cgi"
download_file "pin-registry.html" "$WWW_DIR/index.html"
download_file "config/nodogsplash.config" "$CONFIG_DIR/nodogsplash.config"

# Configure firewall for CaptiFi API access
echo "Configuring firewall..."
cat << 'EOF' > /tmp/captifi_firewall.rule
config rule
        option name 'Allow-Captifi-API'
        option src 'lan'
        option dest 'wan'
        option dest_ip '157.230.53.133'
        option proto 'tcp'
        option dest_port '443'
        option src_ip '157.230.53.133'
        option src_port '443'
        option target 'ACCEPT'
EOF

# Add the rule to the firewall config
cat /tmp/captifi_firewall.rule >> /etc/config/firewall
rm /tmp/captifi_firewall.rule

# Restart firewall
/etc/init.d/firewall restart

# Configure LAN IP address
echo "Setting LAN IP address to 192.168.2.1..."
if [ -f /etc/config/network ]; then
  # Set LAN IP address
  uci set network.lan.ipaddr='192.168.2.1'
  # Commit changes and restart network
  uci commit network
  /etc/init.d/network restart
  echo "LAN IP address updated to 192.168.2.1"
else
  echo "Warning: Network configuration not found."
fi

# Configure wireless networks
echo "Configuring wireless networks to 'CaptiFi Setup'..."
# Try to set both radio0 and radio1 if they exist
if [ -f /etc/config/wireless ]; then
  # Check for radio0 and set its SSID
  if uci show wireless | grep -q "wireless.radio0"; then
    echo "Setting radio0 SSID to 'CaptiFi Setup'..."
    uci set wireless.default_radio0.ssid='CaptiFi Setup'
    # Make sure the interface is enabled
    uci set wireless.default_radio0.disabled='0'
  fi
  
  # Check for radio1 and set its SSID
  if uci show wireless | grep -q "wireless.radio1"; then
    echo "Setting radio1 SSID to 'CaptiFi Setup'..."
    uci set wireless.default_radio1.ssid='CaptiFi Setup'
    # Make sure the interface is enabled
    uci set wireless.default_radio1.disabled='0'
  fi
  
  # Commit changes and restart wireless
  uci commit wireless
  wifi reload
  echo "Wireless configuration updated."
else
  echo "Warning: Wireless configuration not found."
fi

# Configure Nodogsplash
echo "Configuring Nodogsplash..."
cp $CONFIG_DIR/nodogsplash.config /etc/config/nodogsplash

# Set up heartbeat cron job
echo "Setting up heartbeat service..."
cat << 'EOF' > /etc/crontabs/root
# CaptiFi heartbeat - run every 5 minutes
*/5 * * * * $SCRIPTS_DIR/heartbeat.sh
EOF

# Create a default rule to block internet access for unauthenticated users
echo "Setting up firewall to block internet access until authenticated..."
cat << 'EOF' > /tmp/captifi_internet_block.rule
config rule
        option name 'CaptiFi-Block-Internet'
        option src 'lan'
        option dest 'wan'
        option proto 'all'
        option target 'REJECT'
EOF

# Add the internet blocking rule to the firewall config
cat /tmp/captifi_internet_block.rule >> /etc/config/firewall
rm /tmp/captifi_internet_block.rule

# Configure the web server 
echo "Configuring web server for CGI scripts..."
uci set uhttpd.main.interpreter='.cgi=/bin/sh'
uci set uhttpd.main.cgi_prefix='/cgi-bin'
uci commit uhttpd

# Copy PIN registration CGI script to cgi-bin directory
echo "Setting up PIN registration handler..."
cp "$SCRIPTS_DIR/pin-register.cgi" "$CGI_DIR/pin-register"
chmod +x "$CGI_DIR/pin-register"

# Set PIN registration page as the default splash
echo "Setting up initial PIN registration page..."
cp "$WWW_DIR/index.html" "$WWW_DIR/pin-registration.html"

# Configure the system for customer self-activation
echo "Setting up self-activation mode..."
touch "$INSTALL_DIR/self_activate_mode"

# All services and restarts happen at the end
echo "Enabling and starting services..."
/etc/init.d/nodogsplash enable
/etc/init.d/cron enable

# Restart all services at the end
echo "Applying all configurations..."
/etc/init.d/firewall restart
/etc/init.d/uhttpd restart
/etc/init.d/cron start

echo "Setting up captive portal detection..."
# Force captive portal detection by routing to CaptiFi site
route add -host captive.apple.com gw 192.168.2.1
route add -host connectivitycheck.gstatic.com gw 192.168.2.1

# Start Nodogsplash last
echo "Starting captive portal service..."
/etc/init.d/nodogsplash start


# Skip immediate activation - this will be done by customers using the splash page
echo "Device is now in self-activation mode."
echo "Customers will be prompted to enter their PIN when they connect."

# Final message
echo ""
echo "========================================================"
echo "  CaptiFi Integration Installation Complete!"
echo "========================================================"
echo ""
echo "Your device has been configured to work with CaptiFi."
echo "The captive portal is active and guests will be"
echo "redirected to your CaptiFi splash page."
echo ""
echo "For support, contact support@captifi.io"
echo "========================================================"
