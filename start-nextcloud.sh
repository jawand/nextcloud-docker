#!/bin/bash

# Nextcloud Startup Script with BlobFuse Check
# This ensures BlobFuse is mounted before starting containers

set -e

echo "🚀 Starting Nextcloud with BlobFuse verification..."

# Function to check if BlobFuse is properly mounted
check_blobfuse() {
    if ! mountpoint -q /mnt/blobfuse 2>/dev/null; then
        echo "❌ BlobFuse is not mounted"
        return 1
    fi
    
    # Test if we can list contents (this verifies Azure connection)
    if ! timeout 10 ls /mnt/blobfuse > /dev/null 2>&1; then
        echo "❌ BlobFuse mount is not responding"
        return 1
    fi
    
    echo "✅ BlobFuse is mounted and responding"
    return 0
}

# Stop containers if running
echo "🛑 Stopping existing containers..."
docker-compose down

# Check and start BlobFuse if needed
echo "🔍 Checking BlobFuse status..."
if ! check_blobfuse; then
    echo "🔧 Starting BlobFuse..."
    sudo systemctl restart blobfuse
    
    # Wait for BlobFuse to be ready
    echo "⏳ Waiting for BlobFuse to be ready..."
    for i in {1..30}; do
        if check_blobfuse; then
            break
        fi
        echo "   Attempt $i/30..."
        sleep 2
    done
    
    if ! check_blobfuse; then
        echo "❌ Failed to start BlobFuse after 60 seconds"
        exit 1
    fi
fi

# Start Nextcloud containers
echo "🐳 Starting Nextcloud containers..."
docker-compose up -d

# Wait for containers to be ready
echo "⏳ Waiting for containers to start..."
sleep 10

# Verify the mount is working in container
echo "🔍 Verifying container mount..."
if docker exec nextcloud-app ls /mnt/azure-blob > /dev/null 2>&1; then
    echo "✅ Container mount is working"
    
    # Show what both host and container see
    echo ""
    echo "📁 Host mount contents:"
    ls -la /mnt/blobfuse/ | head -5
    echo ""
    echo "📁 Container mount contents:"
    docker exec nextcloud-app ls -la /mnt/azure-blob/ | head -5
else
    echo "❌ Container mount verification failed"
    echo "Try running: docker-compose down && ./start-nextcloud.sh"
    exit 1
fi

echo ""
echo "🎉 Nextcloud started successfully!"
echo "🌐 Access your Nextcloud at: https://$(grep NEXTCLOUD_DOMAIN .env | cut -d'=' -f2)"