#!/bin/bash

# Configure Nextcloud External Storage for Azure Blob
# Run this after setting up Azure Blob Storage

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}☁️  Configuring Nextcloud Azure Blob Storage${NC}"
echo "=============================================="

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
echo -e "${BLUE}💡 Mount name is the folder name users will see in Nextcloud Files app${NC}"
echo -e "${BLUE}   Examples: 'Azure Storage', 'Company Files', 'Cloud Backup'${NC}"
read -p "Enter mount folder name [Azure Storage]: " MOUNT_NAME
MOUNT_NAME=${MOUNT_NAME:-"Azure Storage"}

echo ""
echo -e "${BLUE}📋 Configuration Summary:${NC}"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Container: $CONTAINER_NAME"
echo "Mount Name: $MOUNT_NAME"
echo ""
read -p "Continue with this configuration? [y/N]: " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}❌ Configuration cancelled${NC}"
    exit 0
fi

# Check if Nextcloud is running
if ! docker ps | grep -q nextcloud-app; then
    echo -e "${RED}❌ Nextcloud container is not running${NC}"
    echo -e "${YELLOW}💡 Start Nextcloud first: docker-compose up -d${NC}"
    exit 1
fi

echo -e "${YELLOW}📦 Installing External Storage app...${NC}"

# Enable External Storage app
docker exec nextcloud-app php occ app:enable files_external

# Install Azure Blob Storage support
echo -e "${YELLOW}� Confilguring Azure Blob Storage as S3-compatible storage...${NC}"

# Create S3-compatible external storage mount for Azure Blob
docker exec nextcloud-app php occ files_external:create \
    "$MOUNT_NAME" \
    "amazons3" \
    "password::password"

# Get the mount ID (usually 1 for first external storage)
MOUNT_ID=$(docker exec nextcloud-app php occ files_external:list | grep "$MOUNT_NAME" | awk '{print $2}' | tr -d '|' | xargs)

if [ -z "$MOUNT_ID" ]; then
    echo -e "${RED}❌ Failed to create external storage mount${NC}"
    exit 1
fi

echo -e "${BLUE}Mount ID: $MOUNT_ID${NC}"

# Configure the mount with Azure credentials using S3 API
docker exec nextcloud-app php occ files_external:option "$MOUNT_ID" bucket "$CONTAINER_NAME"
docker exec nextcloud-app php occ files_external:option "$MOUNT_ID" hostname "${STORAGE_ACCOUNT}.blob.core.windows.net"
docker exec nextcloud-app php occ files_external:option "$MOUNT_ID" port "443"
docker exec nextcloud-app php occ files_external:option "$MOUNT_ID" use_ssl "true"
docker exec nextcloud-app php occ files_external:option "$MOUNT_ID" region "us-east-1"
docker exec nextcloud-app php occ files_external:option "$MOUNT_ID" use_path_style "true"
docker exec nextcloud-app php occ files_external:option "$MOUNT_ID" key "$STORAGE_ACCOUNT"
docker exec nextcloud-app php occ files_external:option "$MOUNT_ID" secret "$STORAGE_KEY"

# Enable for all users
docker exec nextcloud-app php occ files_external:applicable "$MOUNT_ID" --add-user --value="all"

# Verify the mount
echo -e "${YELLOW}🔍 Verifying Azure Blob Storage mount...${NC}"
if docker exec nextcloud-app php occ files_external:verify "$MOUNT_ID"; then
    echo -e "${GREEN}✅ Azure Blob Storage mount verified successfully!${NC}"
else
    echo -e "${RED}❌ Mount verification failed. Please check your configuration.${NC}"
    echo ""
    echo -e "${YELLOW}🔧 Troubleshooting Steps:${NC}"
    echo ""
    echo -e "${BLUE}1. Verify Azure Storage Account Details:${NC}"
    echo "   - Storage Account: $STORAGE_ACCOUNT"
    echo "   - Container: $CONTAINER_NAME"
    echo "   - Check these exist in Azure Portal"
    echo ""
    echo -e "${BLUE}2. Verify Access Key:${NC}"
    echo "   - Go to Azure Portal → Storage Account → Access Keys"
    echo "   - Copy key1 or key2 (not connection string)"
    echo "   - Ensure no extra spaces or characters"
    echo ""
    echo -e "${BLUE}3. Check Container Permissions:${NC}"
    echo "   - Container should be 'Private' (not public)"
    echo "   - Ensure container exists and is accessible"
    echo ""
    echo -e "${BLUE}4. Test Manual Connection:${NC}"
    echo "   curl -I https://$STORAGE_ACCOUNT.blob.core.windows.net"
    echo ""
    echo -e "${BLUE}5. Check Network/Firewall:${NC}"
    echo "   - Azure Storage firewall settings"
    echo "   - Server outbound connectivity on port 443"
    echo ""
    read -p "Would you like to try manual web configuration instead? [y/N]: " TRY_MANUAL
    if [[ $TRY_MANUAL =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}📋 Manual Configuration Instructions:${NC}"
        echo "1. Login to Nextcloud as admin"
        echo "2. Go to Settings → Apps → Enable 'External storage support'"
        echo "3. Go to Settings → Administration → External Storage"
        echo "4. Add new storage with these settings:"
        echo "   - Type: Amazon S3"
        echo "   - Folder name: $MOUNT_NAME"
        echo "   - Bucket: $CONTAINER_NAME"
        echo "   - Hostname: $STORAGE_ACCOUNT.blob.core.windows.net"
        echo "   - Port: 443"
        echo "   - Enable SSL: Yes"
        echo "   - Enable Path Style: Yes"
        echo "   - Access Key: $STORAGE_ACCOUNT"
        echo "   - Secret Key: [your storage key]"
        echo "5. Click the checkmark to test connection"
    fi
    exit 1
fi

# Save configuration for future reference
cat > azure-storage-config.txt << EOF
# Azure Blob Storage Configuration for Nextcloud
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
CONTAINER_NAME=$CONTAINER_NAME
STORAGE_KEY=$STORAGE_KEY
MOUNT_NAME=$MOUNT_NAME
MOUNT_ID=$MOUNT_ID
EOF

echo -e "${GREEN}✅ Azure Blob Storage configuration completed!${NC}"
echo ""
echo -e "${BLUE}📋 What's configured:${NC}"
echo "- External Storage app enabled"
echo "- Azure Blob Storage mounted as: $MOUNT_NAME"
echo "- Available to all users"
echo "- Storage Account: $STORAGE_ACCOUNT"
echo "- Container: $CONTAINER_NAME"
echo "- Mount ID: $MOUNT_ID"
echo ""
echo -e "${YELLOW}💡 Next steps:${NC}"
echo "1. Login to Nextcloud web interface"
echo "2. Go to Settings → Administration → External Storage"
echo "3. Verify the Azure mount is listed and working (green checkmark)"
echo "4. Users can now access Azure storage under '$MOUNT_NAME' in Files app"
echo ""
echo -e "${GREEN}💾 Configuration saved to: azure-storage-config.txt${NC}"