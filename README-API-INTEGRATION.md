# CaptiFi OpenWRT Integration

This package provides all the necessary components for integrating OpenWRT-based routers with the CaptiFi platform, enabling PIN-based activation, captive portal functionality, and remote management.

## Features

- **PIN-based Device Activation**: Allows users to activate devices using 8-digit PINs
- **Captive Portal**: Redirects users to the activation page when connecting to the WiFi
- **API Integration**: Communicates with the CaptiFi backend through a secure API
- **Heartbeat Reporting**: Sends device status to the CaptiFi dashboard every 5 minutes
- **Remote Commands**: Supports remote management (reboot, reset, WiFi configuration)
- **Automatic Updates**: Fetches new splash pages when needed

## Installation

To install the CaptiFi OpenWRT integration on your device, you can use the one-line installation command:

```bash
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/install_captifi_complete.sh -O install_captifi.sh && chmod +x install_captifi.sh && ./install_captifi.sh
```

## Device Activation

After installation, the device will:

1. Set up a WiFi network called "CaptiFi Setup" (open network, no password)
2. When users connect to this network, they will be redirected to the activation page
3. Users can enter their 8-digit PIN to activate the device
4. Upon successful activation, the device will:
   - Connect to the CaptiFi backend
   - Retrieve WiFi settings (SSID, password)
   - Apply the new WiFi configuration
   - Reboot to complete the setup

## Troubleshooting

### PIN Activation Issues

If the device isn't accepting a PIN:

1. Verify the PIN is exactly 8 digits
2. Check the device's connection to the internet
3. Look for activation logs in `/tmp/captifi_activation.log`

### API Connection Problems

If the device can't connect to the CaptiFi backend:

1. Check internet connectivity (ping google.com)
2. Verify DNS resolution is working
3. Check for any firewall rules blocking outbound HTTPS connections
4. Look at heartbeat logs in `/tmp/captifi_heartbeat.log`

### Captive Portal Not Working

If users aren't being redirected to the activation page:

1. Restart the uhttpd service: `/etc/init.d/uhttpd restart`
2. Verify iptables rules: `iptables -t nat -L`
3. Check that `/www/splash.html` exists and is accessible

## Factory Reset

To reset the device to factory settings and re-enable PIN activation:

```bash
/etc/captifi/reset-device.sh
```

This will:
- Remove the API key and configuration
- Reset WiFi to "CaptiFi Setup" mode
- Put the device back into PIN activation mode

## Files and Directories

- `/etc/captifi/`: Configuration directory
  - `/etc/captifi/api_key`: API key for authentication with CaptiFi backend
  - `/etc/captifi/scripts/`: Script directory
    - `/etc/captifi/scripts/device-activation.sh`: Handles PIN activation
    - `/etc/captifi/scripts/heartbeat.sh`: Sends periodic updates to CaptiFi
  - `/etc/captifi/reset-device.sh`: Factory reset script

- `/www/`: Web directory
  - `/www/splash.html`: Activation page
  - `/www/cgi-bin/activate.cgi`: Processes PIN submission
  - `/www/cgi-bin/get-mac`: Helper script to get device MAC address

## Advanced Configuration

The CaptiFi integration uses the following configuration options:

- API URL: The URL of the CaptiFi API server (default: https://app.captifi.io/api)
- Heartbeat interval: How often the device reports its status (default: 5 minutes)
- WiFi settings: SSID and password for the device's WiFi network
