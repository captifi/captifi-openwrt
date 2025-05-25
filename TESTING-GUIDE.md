# CaptiFi OpenWRT Integration Testing Guide

This guide provides instructions for testing the CaptiFi OpenWRT integration on a physical OpenWRT device.

## Prerequisites

- An OpenWRT device (router, access point, etc.)
- SSH access to the device
- Internet connectivity for the device
- A valid 8-digit activation PIN from the CaptiFi dashboard

## Upload and Installation

### Method 1: Direct Installation from GitHub

SSH into your OpenWRT device and run:

```bash
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/install_captifi_complete.sh -O install_captifi.sh && chmod +x install_captifi.sh && ./install_captifi.sh
```

### Method 2: Manual Upload and Installation

1. Connect to your OpenWRT device via SSH:
   ```bash
   ssh root@192.168.1.1  # Replace with your device's IP
   ```

2. Create the necessary directories:
   ```bash
   mkdir -p /etc/captifi/scripts /www/cgi-bin
   ```

3. Upload the files from your local machine to the OpenWRT device:
   ```bash
   # From your local machine:
   scp captifi-installer-package/scripts/device-activation-api.sh root@192.168.1.1:/etc/captifi/scripts/device-activation.sh
   scp captifi-installer-package/scripts/heartbeat-with-wifi.sh root@192.168.1.1:/etc/captifi/scripts/heartbeat.sh
   scp captifi-installer-package/reset-device.sh root@192.168.1.1:/etc/captifi/reset-device.sh
   scp captifi-installer-package/www/splash.html root@192.168.1.1:/www/splash.html
   scp captifi-installer-package/www/cgi-bin/activate.cgi root@192.168.1.1:/www/cgi-bin/activate.cgi
   ```

4. Set execute permissions:
   ```bash
   # On the OpenWRT device:
   chmod +x /etc/captifi/scripts/device-activation.sh
   chmod +x /etc/captifi/scripts/heartbeat.sh
   chmod +x /etc/captifi/reset-device.sh
   chmod +x /www/cgi-bin/activate.cgi
   ```

5. Create the get-mac CGI script:
   ```bash
   cat > /www/cgi-bin/get-mac << 'EOF'
   #!/bin/sh
   echo "Content-type: text/plain"
   echo ""
   ifconfig br-lan 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1 || \
   ifconfig eth0 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1
   EOF
   
   chmod +x /www/cgi-bin/get-mac
   ```

6. Set up activation mode:
   ```bash
   mkdir -p /etc/captifi
   touch /etc/captifi/self_activate_mode
   ```

7. Configure the web server:
   ```bash
   uci set uhttpd.main.index_page='splash.html'
   uci commit uhttpd
   /etc/init.d/uhttpd restart
   ```

8. Configure iptables for captive portal redirection:
   ```bash
   iptables -t nat -F PREROUTING
   iptables -t nat -A PREROUTING -i br-lan -p tcp --dport 80 -j DNAT --to-destination 192.168.2.1:80
   iptables -t nat -A PREROUTING -i br-lan -p tcp --dport 443 -j DNAT --to-destination 192.168.2.1:80
   iptables -t nat -A PREROUTING -i br-lan -p udp --dport 53 -j DNAT --to-destination 192.168.2.1:53
   ```

9. Set up heartbeat cron job:
   ```bash
   echo "*/5 * * * * /etc/captifi/scripts/heartbeat.sh" >> /etc/crontabs/root
   /etc/init.d/cron restart
   ```

## Testing PIN Activation

1. Configure your WiFi interface to use "CaptiFi Setup" as the SSID:
   ```bash
   # Find your wireless interface:
   uci show wireless
   
   # Set SSID and disable encryption:
   uci set wireless.@wifi-iface[0].ssid='CaptiFi Setup'
   uci set wireless.@wifi-iface[0].encryption='none'
   uci delete wireless.@wifi-iface[0].key 2>/dev/null || true
   uci commit wireless
   wifi reload
   ```

2. Connect to the "CaptiFi Setup" WiFi network from a mobile device or laptop

3. You should be automatically redirected to the activation page. If not, open a browser and navigate to any website.

4. Enter a valid 8-digit PIN from your CaptiFi dashboard

5. The activation process should begin. The device will restart automatically when activation is complete.

## Verifying API Communication

To verify that your device is properly communicating with the CaptiFi backend:

1. Check activation logs:
   ```bash
   cat /tmp/captifi_activation.log
   ```

2. Check heartbeat logs:
   ```bash
   cat /tmp/captifi_heartbeat.log
   ```

3. Verify that an API key was generated:
   ```bash
   cat /etc/captifi/api_key
   ```

4. Check the last heartbeat response:
   ```bash
   cat /etc/captifi/last_response
   ```

5. In the CaptiFi dashboard, verify that the device appears as online.

## Testing Remote Management

Once the device is activated and registered with the CaptiFi backend, you can test remote management features:

1. **Reboot Test**: Use the CaptiFi dashboard to send a reboot command to the device
   - The device should reboot and reconnect to the CaptiFi backend
   - Check `/tmp/captifi_heartbeat.log` to verify the command was received

2. **WiFi Update Test**: Use the CaptiFi dashboard to send a WiFi update command
   - Set a new SSID and password
   - The device should update its WiFi configuration and reconnect
   - Verify with `uci show wireless`

3. **Reset Test**: Use the CaptiFi dashboard to send a reset command
   - The device should reset to factory settings and return to PIN activation mode
   - WiFi should change back to "CaptiFi Setup"

## Troubleshooting

### Device Not Redirecting to Captive Portal

1. Check web server status:
   ```bash
   /etc/init.d/uhttpd status
   ```

2. Verify that splash.html exists:
   ```bash
   ls -la /www/splash.html
   ```

3. Check iptables rules:
   ```bash
   iptables -t nat -L PREROUTING -n
   ```

4. Manually navigate to the device's IP address (usually 192.168.1.1 or 192.168.2.1)

### API Connection Issues

1. Verify internet connectivity:
   ```bash
   ping -c 4 google.com
   ```

2. Check DNS resolution:
   ```bash
   nslookup app.captifi.io
   ```

3. Test API endpoint reachability:
   ```bash
   wget -O- --timeout=10 https://app.captifi.io/api/ping
   ```

4. Make sure the correct API URL is configured in the scripts.

### Activation Fails

1. Verify the PIN format (must be exactly 8 digits)

2. Check that the PIN is valid in the CaptiFi dashboard

3. Examine the activation logs:
   ```bash
   cat /tmp/captifi_activation.log
   ```

4. Try running the activation script manually:
   ```bash
   /etc/captifi/scripts/device-activation.sh YOUR_PIN_HERE
   ```

## Factory Reset

If you need to start over, you can reset the device to factory settings:

```bash
/etc/captifi/reset-device.sh
```

This will remove all CaptiFi configuration and put the device back into PIN activation mode.
