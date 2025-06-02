# CaptiFi Splash Page Integration

This integration allows OpenWrt devices to display CaptiFi's Blade template splash pages properly by fetching pre-rendered HTML from the CaptiFi server.

## How It Works

The integration follows these steps:

1. The OpenWrt device makes an API call to the CaptiFi server requesting the rendered splash page
2. The CaptiFi server renders the appropriate Blade template (e.g., daisys.blade.php) into HTML
3. The OpenWrt device serves this HTML to users who connect to the WiFi
4. When users submit the form, the data is sent to the CaptiFi server API
5. The CaptiFi server processes the form data, stores it in the database, and returns an authorization response
6. The OpenWrt device authorizes the user's MAC address to access the internet

## Installation

1. **On the OpenWrt Device:**

   ```bash
   # SSH into your OpenWrt device
   ssh root@192.168.2.1
   
   # Run the installation script
   /path/to/install-captifi-splash.sh
   ```

2. **On the CaptiFi Server:**

   - Ensure the DeviceController is properly placed in `app/Http/Controllers/Api/DeviceController.php`
   - Update the API routes in `routes/api.php`
   - Run `php artisan route:cache` to update the route cache

## File Structure

### OpenWrt Device Files

- **fetch-splash-page.sh**: Fetches rendered HTML from the CaptiFi server
- **handle-form-submission.sh**: Processes form submissions and authorizes users
- **submit-form.cgi**: CGI script to handle form submissions
- **install-captifi-splash.sh**: Installation script

### CaptiFi Server Files

- **DeviceController.php**: Controller to handle device API requests
- **routes/api.php**: API routes for the device interaction

## API Endpoints

1. **GET /api/device/get-rendered-splash**
   - Parameters:
     - mac_address: MAC address of the connecting device
     - device_id: ID of the OpenWrt device
     - splash_page: (optional) Name of the splash page to render
     - site_id: (optional) ID of the site
   - Returns: Rendered HTML of the splash page

2. **POST /api/device/submit-form**
   - Headers:
     - X-API-KEY: API key of the device
   - Parameters:
     - mac_address: MAC address of the connecting device
     - name, email, etc.: Form data submitted by the user
   - Returns: JSON response with authorization status

## Troubleshooting

If the splash page is not displaying correctly:

1. Check the logs on the OpenWrt device:
   ```
   cat /tmp/captifi_splash.log
   ```

2. Check the Laravel logs on the server:
   ```
   tail -f storage/logs/laravel.log
   ```

3. Make sure the API key is correctly set on the device:
   ```
   cat /etc/captifi/api_key
   ```

4. Verify the site_id is correctly associated with the server in the database

## Testing

To manually test the integration:

1. Connect to the OpenWrt device's WiFi network
2. You should be redirected to the captive portal
3. Fill out the form and submit
4. You should be authorized to access the internet

To manually fetch the splash page:

```
/etc/captifi/scripts/fetch-splash-page.sh
```
