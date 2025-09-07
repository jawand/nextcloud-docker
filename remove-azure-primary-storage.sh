#!/bin/bash

# Remove Azure Blob Primary Storage Configuration from Nextcloud
# This restores Nextcloud to use local storage

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}🗑️  Remove Azure Blob Primary Storage Configuration${NC}"
echo "=================================================="

# Warning about removing primary storage
echo -e "${RED}⚠️  IMPORTANT WARNING ⚠️${NC}"
echo -e "${YELLOW}Removing primary storage configuration may cause data access issues!${NC}"
echo -e "${YELLOW}Files stored in Azure Blob will become inaccessible through Nextcloud.${NC}"
echo -e "${YELLOW}Make sure you have backups before proceeding.${NC}"
echo ""
read -p "Do you want to continue? [y/N]: " CONTINUE_WARNING
if [[ ! $CONTINUE_WARNING =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}❌ Operation cancelled${NC}"
    exit 0
fi

# Check if Nextcloud is running
if ! docker ps | grep -q nextcloud-app; then
    echo -e "${RED}❌ Nextcloud container is not running${NC}"
    echo -e "${YELLOW}💡 Start Nextcloud first: docker-compose up -d${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Nextcloud container is running${NC}"

# Check if objectstore configuration exists
echo -e "${YELLOW}🔍 Checking for objectstore configuration...${NC}"
if docker exec nextcloud-app php occ config:list system --private | grep -q "objectstore"; then
    echo -e "${YELLOW}⚠️  Objectstore configuration found${NC}"
else
    echo -e "${BLUE}ℹ️  No objectstore configuration found${NC}"
    echo -e "${YELLOW}💡 Nextcloud may already be using local storage${NC}"
    exit 0
fi

# Show current configuration
echo -e "${YELLOW}📋 Current objectstore configuration:${NC}"
docker exec nextcloud-app php occ config:list system --private | grep -A 10 "objectstore" || true

echo ""
read -p "Proceed with removing Azure Blob primary storage? [y/N]: " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}❌ Operation cancelled${NC}"
    exit 0
fi

# Put Nextcloud in maintenance mode
echo -e "${YELLOW}🔧 Enabling maintenance mode...${NC}"
docker exec nextcloud-app php occ maintenance:mode --on

# Create a new backup
echo -e "${YELLOW}💾 Creating backup of current config.php...${NC}"
docker exec nextcloud-app cp /var/www/html/config/config.php /var/www/html/config/config.php.backup.$(date +%Y%m%d_%H%M%S)

# Remove objectstore configuration from config.php
echo -e "${YELLOW}🗑️  Removing objectstore configuration...${NC}"
docker exec nextcloud-app bash -c '
# Create a temporary file without the objectstore configuration
php -r "
\$config = file_get_contents(\"/var/www/html/config/config.php\");

// Remove the objectstore configuration block
\$config = preg_replace(\"/\\\$CONFIG\[.objectstore.\].*?];/s\", \"\", \$config);

// Remove any Azure-related comments
\$config = preg_replace(\"/\/\/.*Azure.*\\n/\", \"\", \$config);
\$config = preg_replace(\"/\/\*.*Azure.*?\*\//s\", \"\", \$config);

// Clean up extra newlines
\$config = preg_replace(\"/\\n\\s*\\n\\s*\\n/\", \"\\n\\n\", \$config);

file_put_contents(\"/var/www/html/config/config.php\", \$config);
"

# Ensure proper file permissions
chown www-data:www-data /var/www/html/config/config.php
chmod 660 /var/www/html/config/config.php
'

# Verify the configuration
echo -e "${YELLOW}🔍 Verifying configuration...${NC}"
if docker exec nextcloud-app php -l /var/www/html/config/config.php; then
    echo -e "${GREEN}✅ Configuration syntax is valid${NC}"
else
    echo -e "${RED}❌ Configuration syntax error detected${NC}"
    echo -e "${YELLOW}🔄 Restoring backup...${NC}"
    docker exec nextcloud-app bash -c 'cp /var/www/html/config/config.php.backup.* /var/www/html/config/config.php'
    docker exec nextcloud-app php occ maintenance:mode --off
    exit 1
fi

# Verify objectstore is removed
echo -e "${YELLOW}🔍 Verifying objectstore removal...${NC}"
if docker exec nextcloud-app php occ config:list system --private | grep -q "objectstore"; then
    echo -e "${RED}❌ Objectstore configuration still present${NC}"
    echo -e "${YELLOW}🔄 Restoring backup...${NC}"
    docker exec nextcloud-app bash -c 'cp /var/www/html/config/config.php.backup.* /var/www/html/config/config.php'
    docker exec nextcloud-app php occ maintenance:mode --off
    exit 1
else
    echo -e "${GREEN}✅ Objectstore configuration successfully removed${NC}"
fi

# Disable maintenance mode
echo -e "${YELLOW}🔧 Disabling maintenance mode...${NC}"
docker exec nextcloud-app php occ maintenance:mode --off

# Clean up configuration files
if [ -f "azure-primary-storage-config.txt" ]; then
    read -p "Remove azure-primary-storage-config.txt file? [y/N]: " REMOVE_CONFIG
    if [[ $REMOVE_CONFIG =~ ^[Yy]$ ]]; then
        rm -f azure-primary-storage-config.txt
        echo -e "${GREEN}✅ Removed azure-primary-storage-config.txt${NC}"
    else
        echo -e "${BLUE}ℹ️  Kept azure-primary-storage-config.txt${NC}"
    fi
fi

echo -e "${GREEN}✅ Azure Blob Primary Storage removal completed!${NC}"
echo ""
echo -e "${BLUE}📋 What was done:${NC}"
echo "- Removed objectstore configuration from config.php"
echo "- Nextcloud now uses local storage for new files"
echo "- Created backup of previous configuration"
echo ""
echo -e "${RED}⚠️  IMPORTANT NOTES:${NC}"
echo "- Files previously stored in Azure Blob are no longer accessible via Nextcloud"
echo "- They still exist in your Azure Storage Account"
echo "- New files will be stored locally in the container"
echo "- You can restore Azure configuration by running configure-azure-primary-storage.sh"
echo ""
echo -e "${YELLOW}💡 To access files stored in Azure Blob:${NC}"
echo "- Use Azure Portal or Azure Storage Explorer"
echo "- Or reconfigure primary storage to restore access"