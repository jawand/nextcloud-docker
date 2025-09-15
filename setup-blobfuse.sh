#!/bin/bash

# BlobFuse Setup for Nextcloud External Storage
# Following: https://github.com/nextcloud/server/issues/2027#issuecomment-1077183842

set -e

echo "🔧 Setting up BlobFuse for Azure Blob Storage..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

# Check if required environment variables are set
if [ -z "$AZURE_STORAGE_ACCOUNT" ] || [ -z "$AZURE_STORAGE_KEY" ] || [ -z "$AZURE_CONTAINER_NAME" ]; then
    echo "❌ Required environment variables not set!"
    echo "Please set the following:"
    echo "export AZURE_STORAGE_ACCOUNT=your_storage_account_name"
    echo "export AZURE_STORAGE_KEY=your_storage_account_key"
    echo "export AZURE_CONTAINER_NAME=your_container_name"
    exit 1
fi

echo "📋 Configuration:"
echo "Storage Account: $AZURE_STORAGE_ACCOUNT"
echo "Container: $AZURE_CONTAINER_NAME"

# Detect OS and install BlobFuse
if [ -f /etc/debian_version ]; then
    echo "🐧 Detected Debian/Ubuntu - Installing BlobFuse..."

    # Install dependencies
    apt-get update
    apt-get install -y wget apt-transport-https software-properties-common

    # Add Microsoft repository
    wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
    dpkg -i packages-microsoft-prod.deb
    apt-get update

    # Install BlobFuse
    apt-get install -y blobfuse fuse

elif [ -f /etc/redhat-release ]; then
    echo "🎩 Detected RHEL/CentOS - Installing BlobFuse..."

    # Add Microsoft repository
    rpm -Uvh https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm

    # Install BlobFuse
    yum install -y blobfuse fuse

else
    echo "❌ Unsupported OS. Please install BlobFuse manually."
    exit 1
fi

# Create directories
echo "📁 Creating directories..."
mkdir -p /mnt/blobfuse
mkdir -p /mnt/blobfusetmp
mkdir -p /opt/nextcloud/azure-config

# Set permissions
chmod 755 /mnt/blobfuse
chmod 700 /mnt/blobfusetmp

# Create BlobFuse configuration file
echo "📝 Creating BlobFuse configuration..."
cat > /opt/nextcloud/azure-config/connection.cfg << EOF
accountName $AZURE_STORAGE_ACCOUNT
accountKey $AZURE_STORAGE_KEY
containerName $AZURE_CONTAINER_NAME
EOF

# Secure the config file
chmod 600 /opt/nextcloud/azure-config/connection.cfg

# Create mount script
echo "📜 Creating mount script..."
cat > /opt/nextcloud/azure-config/mount-blobfuse.sh << 'EOF'
#!/bin/bash

# Mount BlobFuse
blobfuse /mnt/blobfuse \
    --tmp-path=/mnt/blobfusetmp \
    --config-file=/opt/nextcloud/azure-config/connection.cfg \
    --log-level=LOG_WARNING \
    --file-cache-timeout-in-seconds=120 \
    --use-https=true \
    -o attr_timeout=240 \
    -o entry_timeout=240 \
    -o negative_timeout=120 \
    -o allow_other

echo "✅ BlobFuse mounted at /mnt/blobfuse"
EOF

chmod +x /opt/nextcloud/azure-config/mount-blobfuse.sh

# Create unmount script
cat > /opt/nextcloud/azure-config/unmount-blobfuse.sh << 'EOF'
#!/bin/bash

# Unmount BlobFuse
fusermount -u /mnt/blobfuse
echo "✅ BlobFuse unmounted"
EOF

chmod +x /opt/nextcloud/azure-config/unmount-blobfuse.sh

# Create systemd service for automatic mounting
echo "🔧 Creating systemd service..."
cat > /etc/systemd/system/blobfuse.service << EOF
[Unit]
Description=Azure BlobFuse Mount
After=network.target

[Service]
Type=forking
ExecStart=/opt/nextcloud/azure-config/mount-blobfuse.sh
ExecStop=/opt/nextcloud/azure-config/unmount-blobfuse.sh
RemainAfterExit=yes
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable blobfuse.service

# Test mount
echo "🧪 Testing BlobFuse mount..."
/opt/nextcloud/azure-config/mount-blobfuse.sh

# Verify mount
if mountpoint -q /mnt/blobfuse; then
    echo "✅ BlobFuse mounted successfully!"

    # Test write access
    echo "test" > /mnt/blobfuse/test-file.txt
    if [ -f /mnt/blobfuse/test-file.txt ]; then
        echo "✅ Write test successful!"
        rm /mnt/blobfuse/test-file.txt
    else
        echo "❌ Write test failed!"
    fi
else
    echo "❌ BlobFuse mount failed!"
    exit 1
fi

echo ""
echo "🎉 BlobFuse setup completed!"
echo ""
echo "📋 Next steps:"
echo "1. Update docker-compose.yml to mount /mnt/blobfuse"
echo "2. Configure Nextcloud external storage to use the mounted directory"
echo "3. Start/restart your Nextcloud containers"
echo ""
echo "🔧 Management commands:"
echo "sudo systemctl start blobfuse    # Mount BlobFuse"
echo "sudo systemctl stop blobfuse     # Unmount BlobFuse"
echo "sudo systemctl status blobfuse   # Check status"