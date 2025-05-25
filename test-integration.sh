#!/bin/sh

# CaptiFi OpenWRT Integration - Test Script
# This script tests the integration with CaptiFi

echo "========================================================"
echo "  CaptiFi OpenWRT Integration Test"
echo "========================================================"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

# Base variables
INSTALL_DIR="/etc/captifi"
TEST_RESULTS="/tmp/captifi-test-results.txt"

# Clear previous test results
rm -f $TEST_RESULTS
touch $TEST_RESULTS

log_test() {
  echo "$1: $2" | tee -a $TEST_RESULTS
}

# Test 1: Check if directories exist
echo "Testing directory structure..."
if [ -d "$INSTALL_DIR" ] && [ -d "$INSTALL_DIR/scripts" ] && [ -d "$INSTALL_DIR/config" ]; then
  log_test "Directory Structure" "PASS"
else
  log_test "Directory Structure" "FAIL - Required directories missing"
fi

# Test 2: Check if scripts exist
echo "Testing scripts..."
if [ -f "$INSTALL_DIR/scripts/activate.sh" ] && 
   [ -f "$INSTALL_DIR/scripts/fetch-splash.sh" ] && 
   [ -f "$INSTALL_DIR/scripts/heartbeat.sh" ] && 
   [ -f "$INSTALL_DIR/scripts/auth-handler.sh" ]; then
  log_test "Script Files" "PASS"
else
  log_test "Script Files" "FAIL - Required scripts missing"
fi

# Test 3: Check if scripts are executable
echo "Testing script permissions..."
if [ -x "$INSTALL_DIR/scripts/activate.sh" ] && 
   [ -x "$INSTALL_DIR/scripts/fetch-splash.sh" ] && 
   [ -x "$INSTALL_DIR/scripts/heartbeat.sh" ] && 
   [ -x "$INSTALL_DIR/scripts/auth-handler.sh" ]; then
  log_test "Script Permissions" "PASS"
else
  log_test "Script Permissions" "FAIL - Scripts not executable"
fi

# Test 4: Check if API key exists
echo "Testing API key..."
if [ -f "$INSTALL_DIR/api_key" ]; then
  log_test "API Key" "PASS - Device is activated"
else
  log_test "API Key" "FAIL - Device not activated"
fi

# Test 5: Check Nodogsplash configuration
echo "Testing Nodogsplash configuration..."
if [ -f "/etc/config/nodogsplash" ]; then
  if grep -q "CaptiFi" /etc/config/nodogsplash; then
    log_test "Nodogsplash Config" "PASS"
  else
    log_test "Nodogsplash Config" "WARN - Configuration exists but may not be from CaptiFi"
  fi
else
  log_test "Nodogsplash Config" "FAIL - Configuration missing"
fi

# Test 6: Check if Nodogsplash is running
echo "Testing Nodogsplash service..."
if /etc/init.d/nodogsplash status | grep -q "running"; then
  log_test "Nodogsplash Service" "PASS - Service is running"
else
  log_test "Nodogsplash Service" "FAIL - Service not running"
fi

# Test 7: Check firewall rule
echo "Testing firewall rule..."
if uci show firewall | grep -q "Allow-Captifi-API"; then
  log_test "Firewall Rule" "PASS - CaptiFi API rule exists"
else
  log_test "Firewall Rule" "FAIL - CaptiFi API rule missing"
fi

# Test 8: Check cron job
echo "Testing cron job..."
if grep -q "captifi/scripts/heartbeat.sh" /etc/crontabs/root; then
  log_test "Cron Job" "PASS - Heartbeat cron job found"
else
  log_test "Cron Job" "FAIL - Heartbeat cron job missing"
fi

# Test 9: Test API connectivity
echo "Testing API connectivity..."
if [ -f "$INSTALL_DIR/api_key" ]; then
  API_KEY=$(cat "$INSTALL_DIR/api_key")
  if curl -s -I -H "Authorization: ${API_KEY}" "https://app.captifi.io/api/splash-page" | grep -q "200 OK"; then
    log_test "API Connectivity" "PASS - Successfully connected to CaptiFi API"
  else
    log_test "API Connectivity" "FAIL - Could not connect to CaptiFi API"
  fi
else
  log_test "API Connectivity" "SKIP - No API key to test with"
fi

# Test 10: Check splash page
echo "Testing splash page..."
if [ -f "/www/splash.html" ]; then
  if grep -q "html" /www/splash.html; then
    log_test "Splash Page" "PASS - Splash page exists and contains HTML"
  else
    log_test "Splash Page" "WARN - Splash page exists but may not be valid HTML"
  fi
else
  log_test "Splash Page" "FAIL - Splash page missing"
fi

# Summary
echo ""
echo "========================================================"
echo "  Test Summary"
echo "========================================================"
echo ""
echo "Tests completed. Results saved to $TEST_RESULTS"
echo ""
echo "Passed tests: $(grep -c "PASS" $TEST_RESULTS)"
echo "Failed tests: $(grep -c "FAIL" $TEST_RESULTS)"
echo "Warning tests: $(grep -c "WARN" $TEST_RESULTS)"
echo "Skipped tests: $(grep -c "SKIP" $TEST_RESULTS)"
echo ""
echo "See detailed results in $TEST_RESULTS"
echo "========================================================"
