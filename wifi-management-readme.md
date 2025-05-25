# CaptiFi OpenWRT WiFi Management

This document explains how to install and use the WiFi management features of the CaptiFi OpenWRT Integration.

## Installation

There are two ways to install the CaptiFi OpenWRT Integration with WiFi management:

### Option 1: Full Installation (Clean Install)

```bash
# Download the installer
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/captifi-install-with-wifi.sh -O captifi-install-with-wifi.sh

# Make it executable
chmod +x captifi-install-with-wifi.sh

# Run the installer
./captifi-install-with-wifi.sh
```

### Option 2: Update Existing Installation

If you already have the CaptiFi OpenWRT Integration installed, you can update to add WiFi management:

```bash
# Download the script files
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/scripts/heartbeat-with-wifi.sh -O /etc/captifi/scripts/heartbeat.sh
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/scripts/captifi-api.cgi -O /www/cgi-bin/captifi-api.cgi
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/scripts/test-wifi-update.sh -O /etc/captifi/test-wifi-update.sh

# Make them executable
chmod +x /etc/captifi/scripts/heartbeat.sh /www/cgi-bin/captifi-api.cgi /etc/captifi/test-wifi-update.sh

# Restart the heartbeat service
/etc/init.d/cron restart
```

## Using WiFi Management

### Remote Management via Dashboard

WiFi settings can be managed remotely from the CaptiFi dashboard:

1. Log in to your CaptiFi dashboard
2. Navigate to Device Management
3. Find your device and click "Manage WiFi"
4. Update the SSID, password, and encryption settings
5. Click "Save" to apply the changes

The settings will be applied the next time the device sends a heartbeat (within 5 minutes).

### Direct API Access

You can update WiFi settings directly through the API on the device:

```bash
# Example: Update WiFi with password
curl -X POST -H "Content-Type: application/json" -d '{
  "command": "update_wifi",
  "auth_token": "your-api-key-here",
  "ssid": "My Network",
  "password": "mypassword",
  "encryption": "psk2"
}' http://router-ip/cgi-bin/captifi-api.cgi

# Example: Set open network (no password)
curl -X POST -H "Content-Type: application/json" -d '{
  "command": "update_wifi", 
  "auth_token": "your-api-key-here",
  "ssid": "Open Network"
}' http://router-ip/cgi-bin/captifi-api.cgi
```

### Testing Script

The system includes a built-in testing script to help you test WiFi management:

```bash
# SSH into your OpenWRT device
ssh root@router-ip

# Run the test script
/etc/captifi/test-wifi-update.sh
```

This interactive script allows you to:
- View current WiFi settings
- Update WiFi SSID and password
- Create an open WiFi network
- Test the API connection

## WiFi Settings

The following settings can be configured:

| Setting | Description | Options |
|---------|-------------|---------|
| SSID | Network name | Any text string |
| Password | Network password | 8-63 characters (optional) |
| Encryption | Security type | psk2 (WPA2), psk (WPA), psk-mixed (WPA/WPA2), none (open) |

If no encryption is specified, the system defaults to "psk2" (WPA2-PSK).
If no password is provided, the network will be configured as an open network.

## How It Works

1. **Dashboard Integration**:
   - WiFi settings are sent as parameters in the `update_wifi` command
   - The command is delivered through the heartbeat response
   - The heartbeat script processes the command and applies the changes

2. **Direct API**:
   - The API handler in `/www/cgi-bin/captifi-api.cgi` processes requests
   - It authenticates with the API key and executes commands
   - WiFi settings are applied using UCI commands

3. **WiFi Configuration**:
   - Settings are applied to the first WiFi interface using UCI
   - The wireless interface is reloaded to apply changes
   - Changes take effect immediately

## Troubleshooting

### Common Issues

1. **WiFi settings not updating**:
   - Check if the heartbeat is working (`/tmp/captifi_heartbeat.log`)
   - Verify API key is correct
   - Ensure UCI commands are working on your device

2. **API errors**:
   - Check API logs (`/tmp/captifi_api.log`)
   - Verify authentication token
   - Ensure the CGI script is executable

3. **Invalid WiFi settings**:
   - Password must be 8-63 characters for secured networks
   - SSID cannot be empty
   - Encryption must be one of: psk2, psk, psk-mixed, none

### Testing Commands

Check WiFi status:
```bash
uci show wireless
```

View logs:
```bash
cat /tmp/captifi_heartbeat.log
cat /tmp/captifi_api.log
```

Test API connection:
```bash
API_KEY=$(cat /etc/captifi/api_key)
curl -X POST -H "Content-Type: application/json" -d "{\"command\":\"status\",\"auth_token\":\"$API_KEY\"}" http://localhost/cgi-bin/captifi-api.cgi
```

For further assistance, contact support@captifi.io
