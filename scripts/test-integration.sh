#!/bin/sh

# CaptiFi OpenWRT Integration - Testing Script
# This script tests various components of the CaptiFi integration

echo "========================================================"
echo "  CaptiFi OpenWRT Integration - Testing Utility"
echo "========================================================"
echo ""

# Base variables
INSTALL_DIR="/etc/captifi"
WWW_DIR="/www"
CGI_DIR="/www/cgi-bin"
ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check functions
check_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

check_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
}

check_warn() {
    echo -e "${YELLOW}! WARN${NC}: $1"
}

# Test directory structure
echo "Testing directory structure..."
if [ -d "$INSTALL_DIR" ]; then
    check_pass "CaptiFi installation directory exists"
    
    if [ -d "$SCRIPTS_DIR" ]; then
        check_pass "Scripts directory exists"
    else
        check_fail "Scripts directory is missing"
    fi
else
    check_fail "CaptiFi installation directory is missing"
fi

# Test scripts existence
echo ""
echo "Testing scripts..."
for script in activate.sh fetch-splash.sh heartbeat.sh captive-redirect.sh; do
    if [ -f "$INSTALL_DIR/scripts/$script" ]; then
        if [ -x "$INSTALL_DIR/scripts/$script" ]; then
            check_pass "Script $script exists and is executable"
        else
            check_warn "Script $script exists but is not executable"
            chmod +x "$INSTALL_DIR/scripts/$script"
            check_pass "Fixed permissions for $script"
        fi
    else
        check_fail "Script $script is missing"
    fi
done

# Test web files
echo ""
echo "Testing web files..."
if [ -f "$WWW_DIR/index.html" ]; then
    check_pass "Index page exists"
else
    check_fail "Index page is missing"
fi

if [ -f "$WWW_DIR/splash.html" ]; then
    check_pass "Splash page exists"
else
    check_fail "Splash page is missing"
fi

# Test CGI scripts
echo ""
echo "Testing CGI scripts..."
for script in pin-register auth get-mac; do
    if [ -f "$CGI_DIR/$script" ]; then
        if [ -x "$CGI_DIR/$script" ]; then
            check_pass "CGI script $script exists and is executable"
        else
            check_warn "CGI script $script exists but is not executable"
            chmod +x "$CGI_DIR/$script"
            check_pass "Fixed permissions for $script"
        fi
    else
        check_fail "CGI script $script is missing"
    fi
done

# Test web server configuration
echo ""
echo "Testing web server configuration..."
if [ -f "/etc/config/uhttpd" ]; then
    if grep -q "cgi_prefix='/cgi-bin'" /etc/config/uhttpd || grep -q 'cgi_prefix="/cgi-bin"' /etc/config/uhttpd; then
        check_pass "Web server CGI configuration is correct"
    else
        check_fail "Web server CGI configuration is incorrect"
    fi
else
    check_fail "Web server configuration file is missing"
fi

# Test if uhttpd is running
if ps | grep [u]httpd >/dev/null; then
    check_pass "Web server is running"
else
    check_fail "Web server is not running"
    echo "Attempting to start web server..."
    /etc/init.d/uhttpd start
    if ps | grep [u]httpd >/dev/null; then
        check_pass "Web server started successfully"
    else
        check_fail "Failed to start web server"
    fi
fi

# Test API connectivity
echo ""
echo "Testing API connectivity..."
echo "Testing API server reachability..."
if ping -c 1 app.captifi.io >/dev/null 2>&1; then
    check_pass "API server is reachable via ping"
else
    check_warn "API server is not reachable via ping (may be firewalled)"
fi

# Test curl connectivity
if which curl >/dev/null 2>&1; then
    echo "Testing curl connectivity to API server..."
    if curl -s -k -I https://app.captifi.io >/dev/null 2>&1; then
        check_pass "API server is reachable via HTTPS"
    else
        check_fail "API server is not reachable via HTTPS"
        echo ""
        echo "Attempting DNS resolution test..."
        if nslookup app.captifi.io >/dev/null 2>&1; then
            check_pass "DNS resolution works for API server"
        else
            check_fail "DNS resolution fails for API server"
            check_warn "Adding DNS entry to hosts file..."
            echo "157.230.53.133 app.captifi.io" >> /etc/hosts
        fi
    fi
else
    check_fail "curl is not installed"
    echo "Please install curl: opkg update && opkg install curl"
fi

# Test activation status
echo ""
echo "Testing activation status..."
if [ -f "$INSTALL_DIR/api_key" ]; then
    check_pass "Device is activated with API key"
    API_KEY=$(cat "$INSTALL_DIR/api_key")
    echo "API Key: ${API_KEY:0:6}...${API_KEY: -6}"
    
    # Test heartbeat
    echo ""
    echo "Testing heartbeat functionality..."
    if [ -f "$INSTALL_DIR/scripts/heartbeat.sh" ]; then
        echo "Sending test heartbeat..."
        "$INSTALL_DIR/scripts/heartbeat.sh" >/dev/null 2>&1
        if [ -f "/tmp/captifi_heartbeat.log" ]; then
            LAST_LOG=$(tail -1 /tmp/captifi_heartbeat.log)
            if echo "$LAST_LOG" | grep -q "Heartbeat completed"; then
                check_pass "Heartbeat test successful"
            else
                check_warn "Heartbeat test results unclear. Check log:"
                tail -5 /tmp/captifi_heartbeat.log
            fi
        else
            check_fail "Heartbeat log file not found"
        fi
    else
        check_fail "Heartbeat script not found"
    fi
else
    check_warn "Device is not yet activated. Use PIN registration to activate."
fi

# Test cron configuration
echo ""
echo "Testing cron configuration..."
if grep -q "captifi" /etc/crontabs/root; then
    check_pass "Cron job is configured"
else
    check_fail "Cron job is not configured"
    echo "Adding heartbeat cron job..."
    echo "*/5 * * * * /etc/captifi/scripts/heartbeat.sh" >> /etc/crontabs/root
    /etc/init.d/cron restart
    check_pass "Added heartbeat cron job"
fi

if ps | grep [c]rond >/dev/null; then
    check_pass "Cron service is running"
else
    check_fail "Cron service is not running"
    echo "Starting cron service..."
    /etc/init.d/cron start
    check_pass "Started cron service"
fi

# Test captive portal redirection
echo ""
echo "Testing captive portal redirection..."
if [ -f "$INSTALL_DIR/scripts/captive-redirect.sh" ]; then
    echo "Checking captive portal status..."
    STATUS=$("$INSTALL_DIR/scripts/captive-redirect.sh" status)
    if echo "$STATUS" | grep -q "ACTIVE"; then
        check_pass "Captive portal redirection is active"
    else
        check_warn "Captive portal redirection is not active"
        echo "Enabling captive portal redirection..."
        "$INSTALL_DIR/scripts/captive-redirect.sh" enable
        check_pass "Enabled captive portal redirection"
    fi
else
    check_fail "Captive portal redirection script not found"
fi

# Test captive portal detection files
echo ""
echo "Testing captive portal detection files..."
for file in hotspot-detect.html generate_204 success.txt ncsi.txt; do
    if [ -f "$WWW_DIR/$file" ]; then
        check_pass "Captive portal detection file $file exists"
    else
        check_warn "Captive portal detection file $file is missing"
    fi
done

# Summary
echo ""
echo "========================================================"
echo "  CaptiFi Integration Test Summary"
echo "========================================================"
echo ""
echo "Router IP: $ROUTER_IP"
echo "PIN Registration URL: http://$ROUTER_IP/"
echo "Admin Interface URL: http://$ROUTER_IP/cgi-bin/luci/"
echo ""

if [ -f "$INSTALL_DIR/api_key" ]; then
    echo "Status: ACTIVATED"
    echo "You can now direct guests to connect to your WiFi network."
else
    echo "Status: NOT ACTIVATED"
    echo "Please complete the PIN registration process to activate this device."
fi

echo ""
echo "For support, contact support@captifi.io"
echo "========================================================"
exit 0
