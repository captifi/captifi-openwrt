# CaptiFi OpenWRT Integration - PIN Registration System

This repository contains scripts to integrate OpenWRT devices with CaptiFi's captive portal system using Nodogsplash, featuring a self-service PIN registration workflow for customer deployments.

## Overview

This integration creates a customer-friendly deployment system where:

1. The WiFi network name is set to "CaptiFi Setup" during installation
2. The LAN IP address is changed to 192.168.2.1
3. Internet access is blocked for all clients until authenticated
4. Customers connect to the WiFi and automatically see a captive portal PIN page
5. They enter their CaptiFi PIN to activate the device
6. Upon successful activation, the customer's device gets internet access
7. The system fetches and displays their custom splash page to future guests
8. The activated device maintains communication with CaptiFi via heartbeats
9. Guest data is collected and sent to CaptiFi
10. The device receives and processes commands from CaptiFi

## Quick Installation

To install the CaptiFi integration with PIN registration on your OpenWRT device, run the following command:

```bash
wget -O - https://raw.githubusercontent.com/captifi/captifi-openwrt/main/install.sh | sh
```

Unlike the standard version, this script does NOT prompt for a PIN during installation. Instead, it sets up a self-service activation system where customers will enter their PIN through the captive portal.

Note: The installation script uses `wget` which is commonly available on OpenWRT devices.

## Requirements

- OpenWRT device with internet access
- CaptiFi account that can generate customer PINs
- Sufficient storage space (approximately 2MB)
- uhttpd with CGI support (installed automatically)

## Components

The integration consists of the following components:

- **install.sh** - Main installation script
- **pin-registry.html** - PIN entry splash page for device activation
- **scripts/activate.sh** - Device activation with PIN
- **scripts/pin-register.cgi** - CGI handler for processing PIN submissions
- **scripts/fetch-splash.sh** - Fetch splash page from CaptiFi
- **scripts/heartbeat.sh** - Send periodic heartbeats and process commands
- **scripts/auth-handler.sh** - Handle guest authentication
- **config/nodogsplash.config** - Nodogsplash configuration

## Key Features

- **Automatic Captive Portal Detection**: Compatible with Apple, Android, and Windows devices
- **Internet Blocking**: Prevents internet access until device is properly authenticated
- **Customer Self-Registration**: Simple PIN entry workflow with immediate internet access
- **Reliable Heartbeat System**: Enhanced logging and error recovery
- **Custom Branded Splash**: After activation, guests see your custom splash page

## How PIN Registration Works

1. **Initial Setup**:
   - When the device is first installed, it's configured with a generic PIN registration splash page
   - Both WiFi networks (2.4GHz and 5GHz) are renamed to "CaptiFi Setup"
   - LAN IP address is set to 192.168.2.1
   - All internet access is blocked by default
   - No activation PIN is required during installation

2. **Customer First Connection**:
   - When a customer connects to the "CaptiFi Setup" WiFi, a captive portal automatically appears
   - They see the PIN registration page without having to manually browse to any URL
   - They enter their CaptiFi PIN to activate the device
   - The PIN is submitted to a CGI script that processes the activation

3. **Activation Process**:
   - The PIN is validated and sent to the CaptiFi API along with device information
   - Upon successful activation, an API key is obtained
   - The customer's device is automatically authorized for internet access
   - The system fetches the customer's personalized splash page
   - The PIN registration page is replaced with the customer's splash page

4. **Subsequent Guest Connections**:
   - After activation, all guests connecting to the WiFi see the customer's splash page
   - Internet access is blocked until they authenticate via the splash page
   - Guest information is collected and sent to CaptiFi

## Manual Installation

If you prefer to install the components manually:

1. Create the necessary directories:
   ```bash
   mkdir -p /etc/captifi/scripts /etc/captifi/config /www /www/cgi-bin
   ```

2. Copy the scripts to the appropriate directories:
   ```bash
   cp scripts/*.sh /etc/captifi/scripts/
   cp scripts/pin-register.cgi /www/cgi-bin/pin-register
   cp config/* /etc/captifi/config/
   cp pin-registry.html /www/index.html
   ```

3. Make the scripts executable:
   ```bash
   chmod +x /etc/captifi/scripts/*.sh
   chmod +x /www/cgi-bin/pin-register
   ```

4. Configure uhttpd for CGI:
   ```bash
   uci set uhttpd.main.interpreter='.cgi=/bin/sh'
   uci set uhttpd.main.cgi_prefix='/cgi-bin'
   uci commit uhttpd
   /etc/init.d/uhttpd restart
   ```

5. Configure Nodogsplash:
   ```bash
   cp /etc/captifi/config/nodogsplash.config /etc/config/nodogsplash
   ```

6. Configure the firewall:
   ```bash
   # Add CaptiFi API access to firewall
   uci add firewall rule
   uci set firewall.@rule[-1].name='Allow-Captifi-API'
   uci set firewall.@rule[-1].src='lan'
   uci set firewall.@rule[-1].dest='wan'
   uci set firewall.@rule[-1].dest_ip='157.230.53.133'
   uci set firewall.@rule[-1].proto='tcp'
   uci set firewall.@rule[-1].dest_port='443'
   uci set firewall.@rule[-1].target='ACCEPT'
   uci commit firewall
   /etc/init.d/firewall restart
   ```

7. Set up the heartbeat cron job:
   ```bash
   echo "*/5 * * * * /etc/captifi/scripts/heartbeat.sh" >> /etc/crontabs/root
   /etc/init.d/cron restart
   ```

8. Enable self-activation mode:
   ```bash
   touch /etc/captifi/self_activate_mode
   ```

## Customization

You can customize the following aspects of the integration:

- **PIN registration page**: Edit `/www/pin-registration.html` to change the appearance of the PIN entry page
- **Splash page timeout**: Edit `/etc/config/nodogsplash` and change the `authidletimeout` value
- **Heartbeat frequency**: Modify the cron job timing in `/etc/crontabs/root`
- **Walled garden**: Add domains to the `walledgarden_fqdn_list` in `/etc/config/nodogsplash`

## Troubleshooting

Check the following log files for debugging information:

- **Activation log**: Use `cat /etc/captifi/api_key` to verify the device is activated
- **Heartbeat log**: Check `/etc/captifi/heartbeat.log` for communication issues
- **Auth log**: Check `/etc/captifi/auth.log` for guest authentication issues
- **Nodogsplash log**: Run `logread | grep nodogsplash` to see Nodogsplash-related messages
- **uhttpd log**: Run `logread | grep uhttpd` for CGI script errors

Common issues and solutions:

1. **PIN registration page not appearing**: 
   - Check if `/www/index.html` exists
   - Restart uhttpd (`/etc/init.d/uhttpd restart`)
   - Restart Nodogsplash (`/etc/init.d/nodogsplash restart`)

2. **PIN submission not working**:
   - Check if the CGI script is executable (`chmod +x /www/cgi-bin/pin-register`)
   - Verify uhttpd CGI configuration (`uci show uhttpd.main.interpreter`)
   - Check uhttpd logs for CGI errors

3. **Device not activating with PIN**:
   - Verify internet connectivity
   - Ensure the PIN is valid and not expired
   - Check the activation script for errors (`/etc/captifi/scripts/activate.sh`)

4. **Splash page not appearing after activation**:
   - Check if the device has been activated (`cat /etc/captifi/api_key`)
   - Verify the splash page was downloaded (`ls -la /www/splash.html`)
   - Restart Nodogsplash (`/etc/init.d/nodogsplash restart`)

5. **API connection issues**: 
   - Verify the firewall rule is correctly configured
   - Test connectivity to the CaptiFi API server

## Reset to PIN Registration Mode

If you need to reset a device to PIN registration mode (e.g., for redeployment to a new customer):

```bash
# Remove the API key
rm -f /etc/captifi/api_key

# Enable self-activation mode
touch /etc/captifi/self_activate_mode

# Restore the PIN registration page
cp /www/pin-registration.html /www/index.html

# Restart services
/etc/init.d/nodogsplash restart
```

## Support

For support, contact CaptiFi support at support@captifi.io.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
