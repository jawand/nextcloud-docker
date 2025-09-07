# Azure Blob Storage Integration with Nextcloud

This guide shows you how to integrate Azure Blob Storage with your Nextcloud installation for external file storage.

## Method 1: Automated Configuration (Recommended)

### Step 1: Use the Configuration Script

1. **Run the configuration script:**
   ```bash
   ./configure-azure-storage.sh
   ```
   
2. **Provide your existing Azure details:**
   - Storage Account Name
   - Storage Account Key  
   - Container Name
   - Mount folder name (optional)

The script will automatically configure everything for you!

## Method 2: Manual Web Interface Configuration

### Step 1: Enable External Storage in Nextcloud

1. **Login to Nextcloud** as admin
2. **Go to Settings** → Apps  
3. **Enable "External storage support"** app
4. **Go to Settings** → Administration → External Storage

### Step 2: Add Azure Blob Storage

1. **Click "Add storage"**
2. **Select "Amazon S3"** (works with Azure Blob via compatibility)
3. **Configure the mount:**
   ```
   Folder name: Azure Files
   Bucket: [your-container-name]
   Hostname: [storage-account].blob.core.windows.net
   Port: 443
   Region: (leave empty)
   Enable SSL: ✅
   Enable Path Style: ✅
   Access Key: [storage-account-name]
   Secret Key: [storage-account-key]
   ```

4. **Click the checkmark** to test the connection
5. **Set availability** to "All users" or specific groups

## Method 3: Manual Command Line Configuration

### Enable External Storage App
```bash
docker exec nextcloud-app php occ app:enable files_external
```

### Create External Storage Mount
```bash
# Replace values with your Azure details
STORAGE_ACCOUNT="yourstorageaccount"
STORAGE_KEY="your-storage-key"
CONTAINER_NAME="nextcloud-files"

# Create the mount
docker exec nextcloud-app php occ files_external:create \
    "Azure Storage" \
    "amazons3" \
    "password::password"

# Get mount ID (usually 1)
MOUNT_ID=1

# Configure Azure Blob as S3-compatible storage
docker exec nextcloud-app php occ files_external:option $MOUNT_ID bucket "$CONTAINER_NAME"
docker exec nextcloud-app php occ files_external:option $MOUNT_ID hostname "${STORAGE_ACCOUNT}.blob.core.windows.net"
docker exec nextcloud-app php occ files_external:option $MOUNT_ID port "443"
docker exec nextcloud-app php occ files_external:option $MOUNT_ID use_ssl "true"
docker exec nextcloud-app php occ files_external:option $MOUNT_ID use_path_style "true"
docker exec nextcloud-app php occ files_external:option $MOUNT_ID key "$STORAGE_ACCOUNT"
docker exec nextcloud-app php occ files_external:option $MOUNT_ID secret "$STORAGE_KEY"

# Enable for all users
docker exec nextcloud-app php occ files_external:applicable $MOUNT_ID --add-user --value="all"

# Verify the mount
docker exec nextcloud-app php occ files_external:verify $MOUNT_ID
```

## Method 4: Primary Storage (Fresh Installation Only)

If you want Azure Blob as primary storage (requires fresh Nextcloud installation):

### Update docker-compose.yml
Add these environment variables to nextcloud-app service:
```yaml
environment:
  # ... existing variables ...
  - OBJECTSTORE_S3_HOST=[storage-account].blob.core.windows.net
  - OBJECTSTORE_S3_BUCKET=[container-name]
  - OBJECTSTORE_S3_KEY=[storage-account-name]
  - OBJECTSTORE_S3_SECRET=[storage-account-key]
  - OBJECTSTORE_S3_PORT=443
  - OBJECTSTORE_S3_SSL=true
  - OBJECTSTORE_S3_USEPATH_STYLE=true
```

## Benefits of Azure Blob Integration

### For 1GB RAM Server:
- **Offload file storage** from local disk
- **Unlimited storage capacity** (pay per use)
- **Better performance** for large files
- **Automatic backups** and redundancy
- **Global CDN** capabilities

### Cost Optimization:
- **Hot tier**: ~$0.018/GB/month for frequently accessed files
- **Cool tier**: ~$0.01/GB/month for infrequently accessed files
- **Archive tier**: ~$0.002/GB/month for long-term storage

## Troubleshooting

### Connection Issues
1. **Verify Azure credentials** in azure-storage-config.txt
2. **Check container permissions** (should be private)
3. **Test connectivity:**
   ```bash
   docker exec nextcloud-app php occ files_external:list
   docker exec nextcloud-app php occ files_external:verify [mount-id]
   ```

### Performance Issues
1. **Use Hot tier** for frequently accessed files
2. **Enable CDN** for better global performance
3. **Monitor bandwidth** usage in Azure portal

### Security Best Practices
1. **Use SAS tokens** instead of storage keys (more secure)
2. **Enable firewall rules** to restrict access
3. **Regular key rotation** for storage accounts
4. **Monitor access logs** in Azure

## Usage After Setup

### For Users:
1. **Files app** → External Storage folder appears
2. **Upload/download** files normally
3. **Files stored** in Azure Blob automatically
4. **Sync clients** work transparently

### For Admins:
1. **Monitor usage** in Azure portal
2. **Set quotas** per user if needed
3. **Configure lifecycle policies** for cost optimization
4. **Regular backups** of Nextcloud database (files are in Azure)

## Cost Estimation

For typical usage:
- **10GB storage**: ~$0.18/month (Hot tier)
- **100GB storage**: ~$1.80/month (Hot tier)
- **1TB storage**: ~$18/month (Hot tier)

Plus minimal bandwidth costs for uploads/downloads.

Much cheaper than upgrading server storage!