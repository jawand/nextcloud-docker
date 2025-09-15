#!/bin/bash

# Custom Nextcloud entrypoint script with Azure Blob Storage configuration

set -e

echo "🚀 Starting Nextcloud with Azure Blob Storage integration..."

# Run the original Nextcloud entrypoint in the background
/entrypoint.sh apache2-foreground &
NEXTCLOUD_PID=$!

# Function to configure Azure external storage
configure_azure_storage() {
    echo "⏳ Waiting for Nextcloud to be ready..."

    # Wait for Nextcloud to be fully installed and ready
    while ! php /var/www/html/occ status | grep -q "installed: true" 2>/dev/null; do
        echo "   Waiting for Nextcloud installation..."
        sleep 5
    done

    echo "✅ Nextcloud is ready!"

    # Check if Azure mount is available
    if [ ! -d "/mnt/azure-blob" ]; then
        echo "⚠️  Azure Blob mount not found at /mnt/azure-blob"
        echo "   Make sure BlobFuse is mounted on the host"
        return 1
    fi

    echo "📁 Azure Blob mount found"

    # Enable external storage app
    echo "🔌 Enabling External Storage app..."
    php /var/www/html/occ app:enable files_external

    # Check if Azure storage is already configured
    if php /var/www/html/occ files_external:list | grep -q "Azure Blob Storage"; then
        echo "✅ Azure Blob Storage already configured"
        return 0
    fi

    # Configure Azure Blob Storage as external storage
    echo "🏗️  Configuring Azure Blob Storage as external storage..."
    MOUNT_ID=$(php /var/www/html/occ files_external:create \
        "Azure Blob Storage" \
        "local" \
        "null::null" \
        -c datadir="/mnt/azure-blob" \
        --scope="personal" \
        --add-user="admin" \
        | grep -o '[0-9]\+' | tail -1)

    if [ -n "$MOUNT_ID" ]; then
        echo "✅ Azure Blob Storage configured with Mount ID: $MOUNT_ID"

        # Test the mount
        if php /var/www/html/occ files_external:verify "$MOUNT_ID"; then
            echo "✅ Azure Blob Storage mount verified successfully!"
        else
            echo "⚠️  Azure Blob Storage mount verification failed"
        fi
    else
        echo "❌ Failed to configure Azure Blob Storage"
        return 1
    fi

    echo "🎉 Azure Blob Storage configuration completed!"
}

# Run Azure storage configuration in background after a delay
(
    sleep 30  # Give Nextcloud time to fully start
    configure_azure_storage
) &

# Wait for the main Nextcloud process
wait $NEXTCLOUD_PID