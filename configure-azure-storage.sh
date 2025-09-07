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

# Test Azure Blob Storage connectivity
echo -e "${YELLOW}🔍 Testing Azure Blob Storage connectivity...${NC}"
AZURE_ENDPOINT="https://$STORAGE_ACCOUNT.blob.core.windows.net"
if curl -s --head "$AZURE_ENDPOINT" | head -n 1 | grep -q "200 OK\|400 Bad Request"; then
    echo -e "${GREEN}✅ Azure Storage endpoint is reachable${NC}"
else
    echo -e "${RED}❌ Cannot reach Azure Storage endpoint: $AZURE_ENDPOINT${NC}"
    echo -e "${YELLOW}💡 Please check your storage account name and network connectivity${NC}"
    exit 1
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
    echo -e "${RED}❌ Mount verification failed. Please check your credentials.${NC}"
    echo -e "${YELLOW}💡 Common issues:${NC}"
    echo "- Incorrect storage account name or key"
    echo "- Container doesn't exist or is not accessible"
    echo "- Network connectivity issues"
    echo ""
    echo -e "${YELLOW}🔧 To troubleshoot:${NC}"
    echo "1. Verify credentials in Azure Portal"
    echo "2. Check container exists and has proper permissions"
    echo "3. Test connectivity: curl -I https://$STORAGE_ACCOUNT.blob.core.windows.net"
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