#!/bin/bash

# Remove Azure Blob Storage Configuration from Nextcloud
# This script undoes what configure-azure-storage.sh did

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}🗑️  Remove Azure Blob Storage from Nextcloud${NC}"
echo "=============================================="

# Check if Nextcloud is running
if ! docker ps | grep -q nextcloud-app; then
    echo -e "${RED}❌ Nextcloud container is not running${NC}"
    echo -e "${YELLOW}💡 Start Nextcloud first: docker-compose up -d${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Nextcloud container is running${NC}"

# List current external storage mounts
echo -e "${YELLOW}📋 Current external storage mounts:${NC}"
docker exec nextcloud-app php occ files_external:list

echo ""
echo -e "${YELLOW}⚠️  This will remove ALL external storage mounts from Nextcloud${NC}"
echo -e "${YELLOW}⚠️  Files in Azure Blob Storage will NOT be deleted${NC}"
echo -e "${YELLOW}⚠️  Only the Nextcloud connection will be removed${NC}"
echo ""
read -p "Are you sure you want to continue? [y/N]: " CONFIRM

if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}❌ Operation cancelled${NC}"
    exit 0
fi

# Get all external storage mount IDs
echo -e "${YELLOW}🔍 Finding external storage mounts...${NC}"
MOUNT_IDS=$(docker exec nextcloud-app php occ files_external:list --output=json | grep -o '"mount_id":[0-9]*' | cut -d: -f2 || true)

if [ -z "$MOUNT_IDS" ]; then
    echo -e "${YELLOW}ℹ️  No external storage mounts found${NC}"
else
    echo -e "${BLUE}Found mount IDs: $MOUNT_IDS${NC}"
    
    # Remove each mount
    for MOUNT_ID in $MOUNT_IDS; do
        echo -e "${YELLOW}🗑️  Removing mount ID: $MOUNT_ID${NC}"
        if docker exec nextcloud-app php occ files_external:delete "$MOUNT_ID" --yes; then
            echo -e "${GREEN}✅ Successfully removed mount ID: $MOUNT_ID${NC}"
        else
            echo -e "${RED}❌ Failed to remove mount ID: $MOUNT_ID${NC}"
        fi
    done
fi

# Check if External Storage app should be disabled
echo ""
read -p "Do you want to disable the External Storage app entirely? [y/N]: " DISABLE_APP

if [[ $DISABLE_APP =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}📦 Disabling External Storage app...${NC}"
    if docker exec nextcloud-app php occ app:disable files_external; then
        echo -e "${GREEN}✅ External Storage app disabled${NC}"
    else
        echo -e "${RED}❌ Failed to disable External Storage app${NC}"
    fi
else
    echo -e "${BLUE}ℹ️  External Storage app remains enabled${NC}"
fi

# Clean up configuration files
echo -e "${YELLOW}🧹 Cleaning up configuration files...${NC}"
if [ -f "azure-storage-config.txt" ]; then
    read -p "Remove azure-storage-config.txt file? [y/N]: " REMOVE_CONFIG
    if [[ $REMOVE_CONFIG =~ ^[Yy]$ ]]; then
        rm -f azure-storage-config.txt
        echo -e "${GREEN}✅ Removed azure-storage-config.txt${NC}"
    else
        echo -e "${BLUE}ℹ️  Kept azure-storage-config.txt${NC}"
    fi
else
    echo -e "${BLUE}ℹ️  No azure-storage-config.txt file found${NC}"
fi

# Final status check
echo ""
echo -e "${YELLOW}📋 Final external storage status:${NC}"
docker exec nextcloud-app php occ files_external:list

echo ""
echo -e "${GREEN}✅ Azure Blob Storage removal completed!${NC}"
echo ""
echo -e "${BLUE}📋 What was done:${NC}"
echo "- Removed all external storage mounts from Nextcloud"
if [[ $DISABLE_APP =~ ^[Yy]$ ]]; then
    echo "- Disabled External Storage app"
fi
if [[ $REMOVE_CONFIG =~ ^[Yy]$ ]]; then
    echo "- Removed configuration files"
fi
echo ""
echo -e "${YELLOW}💡 Important notes:${NC}"
echo "- Files in Azure Blob Storage are NOT deleted"
echo "- You can still access them directly in Azure Portal"
echo "- To reconnect, run ./configure-azure-storage.sh again"
echo "- Users will no longer see the Azure folder in Files app"