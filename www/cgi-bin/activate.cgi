#!/bin/sh

# Print HTTP headers
echo "Content-type: text/html"
echo ""

# Get the query string
QUERY_STRING="${QUERY_STRING:-$(echo "$REQUEST_URI" | cut -d'?' -f2)}"

# Get the PIN from query string
PIN=$(echo "$QUERY_STRING" | grep -o 'pin=[0-9]\{8\}' | cut -d'=' -f2)

# Validate PIN
if [ -z "$PIN" ] || [ ${#PIN} -ne 8 ]; then
    # Return error page for invalid PIN
    cat << EOF
<html>
<head>
    <title>Activation Error</title>
    <meta http-equiv="refresh" content="5;url=/splash.html">
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #cc0000; }
    </style>
</head>
<body>
    <h1>Activation Error</h1>
    <p>Invalid PIN format. Please enter an 8-digit PIN.</p>
    <p>Redirecting back to activation page...</p>
</body>
</html>
EOF
    exit 0
fi

# Get device MAC address
MAC_ADDRESS=$(ifconfig br-lan 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
if [ -z "$MAC_ADDRESS" ]; then
    MAC_ADDRESS=$(ifconfig eth0 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)
fi

# Store PIN and MAC for activation
mkdir -p /etc/captifi
echo "$PIN" > /etc/captifi/activation_pin
echo "$MAC_ADDRESS" > /etc/captifi/activation_mac

# Call the device activation script
if [ -x "/etc/captifi/scripts/device-activation.sh" ]; then
    # Run activation script in the background
    (/etc/captifi/scripts/device-activation.sh "$PIN" "$MAC_ADDRESS" > /tmp/activation_log.txt 2>&1) &
    
    # Display success page immediately while activation happens in background
    cat << EOF
<html>
<head>
    <title>Device Activation</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #0066cc; }
        .spinner {
            border: 4px solid rgba(0, 0, 0, 0.1);
            width: 36px;
            height: 36px;
            border-radius: 50%;
            border-left-color: #0066cc;
            margin: 20px auto;
            animation: spin 1s linear infinite;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <h1>Activating Device</h1>
    <p>Your device is being activated with PIN: $PIN</p>
    <p>Device MAC Address: $MAC_ADDRESS</p>
    <div class="spinner"></div>
    <p>Please wait while the device connects to the CaptiFi network. This may take a few minutes.</p>
    <p>The device will reboot automatically once activation is complete.</p>
</body>
</html>
EOF
else
    # Return error if activation script not found
    cat << EOF
<html>
<head>
    <title>Activation Error</title>
    <meta http-equiv="refresh" content="5;url=/splash.html">
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #cc0000; }
    </style>
</head>
<body>
    <h1>Activation Error</h1>
    <p>Activation script not found. Please contact support.</p>
    <p>Redirecting back to activation page...</p>
</body>
</html>
EOF
fi

exit 0
