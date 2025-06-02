#!/bin/sh

# CaptiFi Splash Page Installation Script
# This script installs the necessary files for the CaptiFi splash page integration

echo "===== CaptiFi Splash Page Installation ====="
echo ""

# Ensure directories exist
mkdir -p /etc/captifi/scripts
mkdir -p /www/cgi-bin

# Copy scripts
echo "Copying scripts..."
cp captifi-openwrt/scripts/fetch-splash-page.sh /etc/captifi/scripts/
cp captifi-openwrt/scripts/handle-form-submission.sh /etc/captifi/scripts/
cp captifi-openwrt/www/cgi-bin/submit-form.cgi /www/cgi-bin/

# Make scripts executable
echo "Setting permissions..."
chmod +x /etc/captifi/scripts/fetch-splash-page.sh
chmod +x /etc/captifi/scripts/handle-form-submission.sh
chmod +x /www/cgi-bin/submit-form.cgi

# Create symlink for heartbeat to find fetch-splash-page.sh
echo "Creating symlink..."
ln -sf /etc/captifi/scripts/fetch-splash-page.sh /etc/captifi/fetch-splash-page.sh

# Fetch the splash page
echo "Fetching splash page..."
/etc/captifi/scripts/fetch-splash-page.sh

# Restart web server
echo "Restarting web server..."
if command -v uci &> /dev/null; then
    uci set uhttpd.main.index_page='index.html'
    uci commit uhttpd
    /etc/init.d/uhttpd restart
fi

echo ""
echo "===== Installation Complete ====="
echo "The CaptiFi splash page integration has been installed."
echo "The splash page should now be correctly displayed to users."
echo ""
echo "To test the integration, visit http://$(uci get network.lan.ipaddr || echo "192.168.1.1")"
echo "To manually update the splash page, run: /etc/captifi/scripts/fetch-splash-page.sh"
echo ""
