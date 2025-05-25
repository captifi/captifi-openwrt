# CaptiFi OpenWRT Integration

This project provides a streamlined integration between OpenWRT devices and the CaptiFi captive portal system. It enables OpenWRT-based routers to offer guest WiFi with captive portal functionality, allowing guests to register with a PIN provided by CaptiFi.

## Features

- PIN-based device activation
- Direct API communication with CaptiFi servers
- Guest WiFi splash page with Terms of Service acceptance
- Automated heartbeat reporting to CaptiFi
- SSH-safe implementation (no SSH lockout issues)
- No dependency on nodogsplash or other captive portal packages

## Prerequisites

- OpenWRT device (v21.02 or newer recommended)
- Internet connection
- SSH access to the OpenWRT device
- CaptiFi account with a valid PIN

## Installation

### Option 1: Automated Installation

1. SSH into your OpenWRT device
2. Download the installation script:
```bash
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/no-nodogsplash-install.sh
```
3. Make it executable:
```bash
chmod +x no-nodogsplash-install.sh
```
4. Run the script:
```bash
./no-nodogsplash-install.sh
```
5. Follow the prompts to configure WiFi settings and IP address

### Option 2: Manual Installation

If you prefer to install the components manually, follow these steps:

1. Install required packages:
```bash
opkg update
opkg install curl uhttpd
```

2. Create required directories:
```bash
mkdir -p /etc/captifi/scripts /www/cgi-bin
```

3. Download scripts from this repository:
```bash
cd /etc/captifi/scripts
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/scripts/activate.sh
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/scripts/fetch-splash.sh
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/scripts/heartbeat.sh
chmod +x *.sh
```

4. Download CGI scripts and web files:
```bash
cd /www/cgi-bin
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/cgi-bin/pin-register
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/cgi-bin/auth
chmod +x *

cd /www
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/index.html
wget https://raw.githubusercontent.com/captifi/captifi-openwrt/main/splash.html
```

5. Configure web server:
```bash
uci set uhttpd.main.interpreter='.cgi=/bin/sh'
uci set uhttpd.main.cgi_prefix='/cgi-bin'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

6. Set up heartbeat service:
```bash
echo "*/5 * * * * /etc/captifi/scripts/heartbeat.sh" > /etc/crontabs/root
/etc/init.d/cron enable
/etc/init.d/cron restart
```

## Usage

### First-time Setup

1. After installation, connect to your OpenWRT device's WiFi network (default SSID: "OpenWRT")
2. Open a browser and navigate to your router's IP address (default: 192.168.1.1)
3. You should see the CaptiFi PIN registration page
4. Enter your 8-digit PIN provided by CaptiFi
5. Upon successful activation, you'll be redirected to the splash page

### Guest WiFi Usage

Once the device is activated:

1. Guests connect to your WiFi network
2. They are presented with the CaptiFi splash page
3. They click "Connect to Internet" to gain access
4. The system records the connection in the CaptiFi dashboard

### Admin Access

The router's admin interface remains accessible at:
```
http://<router-ip>/cgi-bin/luci/
```

## Troubleshooting

### API Connection Issues

If you see "Failed to connect to CaptiFi server" errors:

1. Verify internet connectivity:
```bash
ping google.com
```

2. Check DNS resolution:
```bash
nslookup app.captifi.io
```

3. Add a direct DNS entry:
```bash
echo "157.230.53.133 app.captifi.io" >> /etc/hosts
```

4. Check heartbeat logs:
```bash
cat /tmp/captifi_heartbeat.log
```

### Web Server Issues

If the web pages don't display correctly:

1. Restart the web server:
```bash
/etc/init.d/uhttpd restart
```

2. Check web server status:
```bash
ps | grep uhttpd
```

3. Verify file permissions:
```bash
chmod -R 644 /www/*.html
chmod -R 755 /www/cgi-bin
```

### Activation Issues

If PIN activation fails:

1. Test activation manually:
```bash
/etc/captifi/scripts/activate.sh YOUR_PIN_HERE
```

2. Check for API connectivity using curl:
```bash
curl -v -k https://app.captifi.io/
```

3. Verify the PIN is valid in your CaptiFi dashboard

## Uninstallation

To remove the CaptiFi integration:

```bash
rm -rf /etc/captifi
rm -f /www/cgi-bin/pin-register /www/cgi-bin/auth
sed -i '/captifi/d' /etc/crontabs/root
/etc/init.d/cron restart
/etc/init.d/uhttpd restart
```

## Support

For support, please contact:
- CaptiFi Support: support@captifi.io
- GitHub Issues: [Create a new issue](https://github.com/captifi/captifi-openwrt/issues)
