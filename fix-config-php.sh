#!/bin/bash

# Fix corrupted config.php file in Nextcloud
# This script repairs syntax errors in config.php

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}🔧 Nextcloud Config.php Recovery Tool${NC}"
echo "===================================="

# Check if Nextcloud container is running
if ! docker ps | grep -q nextcloud-app; then
    echo -e "${RED}❌ Nextcloud container is not running${NC}"
    echo -e "${YELLOW}💡 Start Nextcloud first: docker-compose up -d${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Nextcloud container is running${NC}"

# Check if there are any backups
echo -e "${YELLOW}🔍 Looking for config.php backups...${NC}"
BACKUPS=$(docker exec nextcloud-app bash -c 'ls -la /var/www/html/config/config.php.backup.* 2>/dev/null || echo "none"')

if [ "$BACKUPS" = "none" ]; then
    echo -e "${RED}❌ No backups found${NC}"
    echo -e "${YELLOW}💡 We'll try to fix the current config.php${NC}"
else
    echo -e "${GREEN}✅ Found backups:${NC}"
    docker exec nextcloud-app bash -c 'ls -la /var/www/html/config/config.php.backup.*'
    echo ""
    read -p "Do you want to restore from the most recent backup? [Y/n]: " RESTORE_BACKUP
    
    if [[ ! $RESTORE_BACKUP =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}🔄 Restoring from most recent backup...${NC}"
        LATEST_BACKUP=$(docker exec nextcloud-app bash -c 'ls -t /var/www/html/config/config.php.backup.* | head -1')
        docker exec nextcloud-app cp "$LATEST_BACKUP" /var/www/html/config/config.php
        
        # Test the restored config
        if docker exec nextcloud-app php -l /var/www/html/config/config.php; then
            echo -e "${GREEN}✅ Config.php restored successfully!${NC}"
            echo -e "${YELLOW}💡 You can now run configure-azure-primary-storage.sh again${NC}"
            exit 0
        else
            echo -e "${RED}❌ Restored backup also has syntax errors${NC}"
            echo -e "${YELLOW}💡 Will try to fix manually...${NC}"
        fi
    fi
fi

# Show the problematic area around line 61
echo -e "${YELLOW}🔍 Showing config.php around line 61:${NC}"
docker exec nextcloud-app bash -c 'sed -n "55,65p" /var/www/html/config/config.php' || true

echo ""
echo -e "${YELLOW}🔧 Attempting to fix config.php...${NC}"

# Create a fixed version of config.php
docker exec nextcloud-app bash -c '
# Create a backup of the current (broken) file
cp /var/www/html/config/config.php /var/www/html/config/config.php.broken.$(date +%Y%m%d_%H%M%S)

# Try to fix common issues
sed -i "s/<?php<?php/<?php/g" /var/www/html/config/config.php  # Remove duplicate PHP tags
sed -i "/^$/d" /var/www/html/config/config.php                   # Remove empty lines
sed -i "s/^<.*>//g" /var/www/html/config/config.php             # Remove stray HTML tags

# Ensure the file starts with <?php
if ! head -1 /var/www/html/config/config.php | grep -q "<?php"; then
    echo "<?php" > /tmp/fixed_config.php
    cat /var/www/html/config/config.php >> /tmp/fixed_config.php
    mv /tmp/fixed_config.php /var/www/html/config/config.php
fi

# Remove any closing ?> tags that might be in the middle
sed -i "/^?>$/d" /var/www/html/config/config.php

# Ensure proper file permissions
chown www-data:www-data /var/www/html/config/config.php
chmod 660 /var/www/html/config/config.php
'

# Test the fixed config
echo -e "${YELLOW}🔍 Testing fixed config.php...${NC}"
if docker exec nextcloud-app php -l /var/www/html/config/config.php; then
    echo -e "${GREEN}✅ Config.php syntax is now valid!${NC}"
    
    # Test if Nextcloud can load
    echo -e "${YELLOW}🔍 Testing Nextcloud functionality...${NC}"
    if docker exec nextcloud-app php occ status; then
        echo -e "${GREEN}✅ Nextcloud is working properly!${NC}"
        echo ""
        echo -e "${BLUE}💡 Next steps:${NC}"
        echo "1. Your config.php has been fixed"
        echo "2. You can now run: ./configure-azure-primary-storage.sh"
        echo "3. A backup of the broken file was created with .broken timestamp"
    else
        echo -e "${YELLOW}⚠️  Config syntax is valid but Nextcloud has other issues${NC}"
        echo -e "${YELLOW}💡 Check the Nextcloud logs for more details${NC}"
    fi
else
    echo -e "${RED}❌ Config.php still has syntax errors${NC}"
    echo ""
    echo -e "${YELLOW}🔍 Current syntax errors:${NC}"
    docker exec nextcloud-app php -l /var/www/html/config/config.php || true
    echo ""
    echo -e "${YELLOW}💡 Manual intervention may be required${NC}"
    echo "You can:"
    echo "1. Access the container: docker exec -it nextcloud-app bash"
    echo "2. Edit the file: nano /var/www/html/config/config.php"
    echo "3. Or restore from a working backup if available"
fi