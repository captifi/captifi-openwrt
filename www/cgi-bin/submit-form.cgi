#!/bin/sh

# Print HTTP headers
echo "Content-type: text/html"
echo ""

# Call the form submission handler script
/etc/captifi/scripts/handle-form-submission.sh
