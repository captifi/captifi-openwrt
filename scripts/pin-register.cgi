#!/bin/sh

# CaptiFi OpenWRT Integration - PIN Registration CGI Handler
# This script processes PIN submissions from the splash page

# Print HTTP headers
echo "Content-type: text/html"
echo ""

# Base variables
INSTALL_DIR="/etc/captifi"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
WWW_DIR="/www"

# Function to parse query parameters
get_post_data() {
    # Check if this is a POST request
    if [ "$REQUEST_METHOD" = "POST" ]; then
        # Get Content-Type
        CT=$(echo "$CONTENT_TYPE" | cut -d';' -f1)
        if [ "$CT" = "application/x-www-form-urlencoded" ]; then
            # Read POST data from stdin
            read -n $CONTENT_LENGTH POST_DATA
            echo "$POST_DATA"
        else
            echo ""
        fi
    else
        echo ""
    fi
}

# Function to extract parameters from query string
get_param() {
    echo "$1" | tr '&' '\n' | grep "^$2=" | cut -d'=' -f2- | sed 's/+/ /g;s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\\\\\x\1/g' | xargs -0 echo -e
}

# Get POST data
POST_DATA=$(get_post_data)
PIN=$(get_param "$POST_DATA" "pin")

# Validate PIN format (8 digits)
if ! echo "$PIN" | grep -qE '^[0-9]{8}$'; then
    # Show error page
    cat << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Invalid PIN</title>
    <meta http-equiv="refresh" content="5;url=/">
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        .error { color: red; }
    </style>
</head>
<body>
    <h1 class="error">Invalid PIN Format</h1>
    <p>The PIN must be 8 digits. Please try again.</p>
    <p>You will be redirected back to the registration page in 5 seconds...</p>
</body>
</html>
EOF
    exit 0
fi

# Try to activate the device with this PIN
ACTIVATION_RESULT=$("$SCRIPTS_DIR/activate.sh" "$PIN" 2>&1)
ACTIVATION_SUCCESS=$?

# Check if activation was successful
if [ $ACTIVATION_SUCCESS -eq 0 ]; then
    # Success - show confirmation and redirect to splash page
    cat << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Device Activated</title>
    <meta http-equiv="refresh" content="5;url=/">
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        .success { color: green; }
    </style>
</head>
<body>
    <h1 class="success">Device Activated Successfully!</h1>
    <p>Your device has been successfully registered with CaptiFi.</p>
    <p>You will be redirected to the guest WiFi page in 5 seconds...</p>
</body>
</html>
EOF

    # Copy the newly downloaded splash page to the default index
    if [ -f "$WWW_DIR/splash.html" ]; then
        cp "$WWW_DIR/splash.html" "$WWW_DIR/index.html"
    fi
    
    # Update Nodogsplash to use the proper splash page
    if [ -f /etc/config/nodogsplash ]; then
        uci set nodogsplash.@nodogsplash[0].splashpage="$WWW_DIR/index.html"
        uci commit nodogsplash
        /etc/init.d/nodogsplash restart
    fi
else
    # Activation failed - show error
    cat << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Activation Failed</title>
    <meta http-equiv="refresh" content="10;url=/">
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; text-align: center; }
        .error { color: red; }
        .details { background-color: #f8f8f8; padding: 20px; text-align: left; font-family: monospace; }
    </style>
</head>
<body>
    <h1 class="error">Device Activation Failed</h1>
    <p>Unable to activate the device with the provided PIN. Please check your PIN and try again.</p>
    <div class="details">
        <h3>Error Details:</h3>
        <pre>${ACTIVATION_RESULT}</pre>
    </div>
    <p>You will be redirected back to the registration page in 10 seconds...</p>
</body>
</html>
EOF
fi

exit 0
