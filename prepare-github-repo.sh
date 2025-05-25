#!/bin/sh

# Script to prepare CaptiFi OpenWRT Integration GitHub repository
# This script removes non-working files and organizes the repository structure

echo "========================================================"
echo "  Preparing CaptiFi OpenWRT Integration GitHub Repo"
echo "========================================================"

# Create required directories
mkdir -p scripts/
mkdir -p templates/

# Copy main files to the root directory
cp no-nodogsplash-install.sh captifi-install.sh
cp captive-redirect.sh scripts/
cp test-integration.sh scripts/
cp uninstall.sh scripts/
cp reset-to-pin-mode.sh scripts/

# Copy HTML templates
cp sample-splash.html templates/
cp pin-registry.html templates/

# Copy documentation files
# Keep these in the root

echo "Cleaning up non-working files..."
rm -f install.sh manual-install.sh fix-activate.sh fix-nodogsplash.sh
rm -rf config/

echo "Repository structure prepared successfully"
echo ""
echo "Files ready for GitHub:"
ls -la

echo ""
echo "To push to GitHub, you need to:"
echo "1. Create a new GitHub repository"
echo "2. Initialize Git in this directory:"
echo "   git init"
echo "3. Add all files:"
echo "   git add ."
echo "4. Commit the files:"
echo "   git commit -m \"Initial commit of CaptiFi OpenWRT Integration\""
echo "5. Add your GitHub repo as remote:"
echo "   git remote add origin https://github.com/YOURUSERNAME/YOURREPO.git"
echo "6. Push to GitHub:"
echo "   git push -u origin master"
echo ""
echo "========================================================"
