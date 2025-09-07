#!/bin/bash

# Configure Azure Blob Storage as Primary Storage for Nextcloud
# Based on: https://docs.nextcloud.com/server/30/admin_manual/configuration_files/primary_storage.html

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}☁️  Configure Azure Blob as Primary Storage${NC}"
echo "=============================================="

# Warning about primary storage
echo -e "${RED}⚠️  IMPORTANT WARNING ⚠️${NC}"
echo -e "${YELLOW}Primary storage configuration should be done BEFORE first setup!${NC}"
echo -e "${YELLOW}If Nextcloud is already configured with data, this may cause issues.${NC}"
echo -e "${YELLOW}Consider backing up your data first.${NC}"
echo ""
read -p "Do you want to continue? [y/N]: " CONTINUE_WARNING
if [[ ! $CONTINUE_WARNING =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}❌ Configuration cancelled${NC}"
    exit 0
fi

# Check if Nextcloud is running
if ! docker ps | grep -q nextcloud-app; then
    echo -e "${RED}❌ Nextcloud container is not running${NC}"
    echo -e "${YELLOW}💡 Start Nextcloud first: docker-compose up -d${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Nextcloud container is running${NC}"

# Get Azure Blob Storage details from user
echo -e "${YELLOW}📋 Please provide your Azure Blob Storage details:${NC}"
echo ""

read -p "Enter your Azure Storage Account name: " STORAGE_ACCOUNT
if [ -z "$STORAGE_ACCOUNT" ]; then
    echo -e "${RED}❌ Storage account name is required${NC}"
    exit 1
fi

read -p "Enter your Azure Storage Account key: " STORAGE_KEY
if [ -z "$STORAGE_KEY" ]; then
    echo -e "${RED}❌ Storage account key is required${NC}"
    exit 1
fi

read -p "Enter your Azure Blob Container name: " CONTAINER_NAME
if [ -z "$CONTAINER_NAME" ]; then
    echo -e "${RED}❌ Container name is required${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}📋 Configuration Summary:${NC}"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Container: $CONTAINER_NAME"
echo ""
read -p "Continue with this configuration? [y/N]: " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}❌ Configuration cancelled${NC}"
    exit 0
fi

# Put Nextcloud in maintenance mode
echo -e "${YELLOW}🔧 Enabling maintenance mode...${NC}"
docker exec nextcloud-app php occ maintenance:mode --on

# Backup current config.php
echo -e "${YELLOW}💾 Backing up current config.php...${NC}"
docker exec nextcloud-app cp /var/www/html/config/config.php /var/www/html/config/config.php.backup.$(date +%Y%m%d_%H%M%S)

# Create the objectstore configuration
echo -e "${YELLOW}🔧 Configuring Azure Blob as primary storage...${NC}"

# Create PHP configuration snippet for Azure Blob Storage using PHP itself
echo -e "${YELLOW}📝 Generating Azure configuration...${NC}"

# Write the configuration using PHP to avoid sed issues with special characters
echo -e "${YELLOW}📝 Writing Azure configuration...${NC}"
docker exec nextcloud-app php -r "
\$config = '<?php
// Azure Blob Storage Primary Storage Configuration
\$CONFIG[\'objectstore\'] = [
    \'class\' => \'\\\\OC\\\\Files\\\\ObjectStore\\\\Azure\',
    \'arguments\' => [
        \'container\' => \'' . addslashes('$CONTAINER_NAME') . '\',
        \'account_name\' => \'' . addslashes('$STORAGE_ACCOUNT') . '\',
        \'account_key\' => \'' . addslashes('$STORAGE_KEY') . '\',
    ],
];
';
file_put_contents('/tmp/azure_config.php', \$config);
"

# Append the Azure configuration to config.php
echo -e "${YELLOW}🔧 Updating config.php...${NC}"
docker exec nextcloud-app bash -c '
# Remove the closing ?> tag if it exists
sed -i "/^?>/d" /var/www/html/config/config.php

# Add the Azure configuration
echo "" >> /var/www/html/config/config.php
cat /tmp/azure_config.php >> /var/www/html/config/config.php

# Clean up temporary file
rm /tmp/azure_config.php

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

# Test the objectstore connection
echo -e "${YELLOW}🔍 Testing Azure Blob Storage connection...${NC}"
if docker exec nextcloud-app php occ config:list system --private | grep -q "objectstore"; then
    echo -e "${GREEN}✅ Objectstore configuration detected${NC}"
else
    echo -e "${RED}❌ Objectstore configuration not found${NC}"
fi

# Disable maintenance mode
echo -e "${YELLOW}🔧 Disabling maintenance mode...${NC}"
docker exec nextcloud-app php occ maintenance:mode --off

# Save configuration for reference
cat > azure-primary-storage-config.txt << EOF
# Azure Blob Primary Storage Configuration
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
CONTAINER_NAME=$CONTAINER_NAME
STORAGE_KEY=$STORAGE_KEY
CONFIGURED_DATE=$(date)

# Configuration added to: /var/www/html/config/config.php
# Backup created: /var/www/html/config/config.php.backup.*
EOF

echo -e "${GREEN}✅ Azure Blob Primary Storage configuration completed!${NC}"
echo ""
echo -e "${BLUE}📋 What was configured:${NC}"
echo "- Azure Blob Storage set as primary object store"
echo "- All new files will be stored in Azure Blob Storage"
echo "- Configuration added to config.php"
echo "- Backup of original config.php created"
echo ""
echo -e "${YELLOW}💡 Important notes:${NC}"
echo "- All new files uploaded to Nextcloud will go to Azure Blob Storage"
echo "- Existing files remain in local storage (if any)"
echo "- This provides unlimited storage capacity"
echo "- Files are automatically distributed across Azure's global network"
echo ""
echo -e "${GREEN}💾 Configuration saved to: azure-primary-storage-config.txt${NC}"
echo ""
echo -e "${BLUE}🔧 To verify everything is working:${NC}"
echo "1. Access your Nextcloud web interface"
echo "2. Upload a test file"
echo "3. Check Azure Portal to see the file in your container"