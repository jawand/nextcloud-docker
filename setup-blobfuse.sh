#!/bin/bash

# BlobFuse2 Setup for Nextcloud External Storage
# Updated for BlobFuse2 using Microsoft's official documentation
# https://learn.microsoft.com/en-us/azure/storage/blobs/blobfuse2-how-to-deploy

set -e

echo "🔧 Setting up BlobFuse2 for Azure Blob Storage..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

# Try to load environment variables from .env file
if [ -f ".env" ]; then
    echo "📋 Loading configuration from .env file..."
    set -a  # Export all variables
    source .env
    set +a  # Stop exporting
elif [ -f "../.env" ]; then
    echo "📋 Loading configuration from ../.env file..."
    set -a  # Export all variables
    source ../.env
    set +a  # Stop exporting
fi

# Check if required environment variables are set
if [ -z "$AZURE_STORAGE_ACCOUNT" ] || [ -z "$AZURE_STORAGE_KEY" ] || [ -z "$AZURE_CONTAINER_NAME" ]; then
    echo "❌ Required environment variables not set!"
    echo ""
    echo "Please either:"
    echo "1. Create .env file in current directory with:"
    echo "   AZURE_STORAGE_ACCOUNT=your_storage_account_name"
    echo "   AZURE_STORAGE_KEY=your_storage_account_key"
    echo "   AZURE_CONTAINER_NAME=your_container_name"
    echo ""
    echo "2. Or export them manually:"
    echo "   export AZURE_STORAGE_ACCOUNT=your_storage_account_name"
    echo "   export AZURE_STORAGE_KEY=your_storage_account_key"
    echo "   export AZURE_CONTAINER_NAME=your_container_name"
    echo "   sudo -E ./setup-blobfuse.sh"
    echo ""
    echo "3. Or use the wrapper script:"
    echo "   sudo ./setup-azure-blobfuse.sh"
    exit 1
fi

echo "📋 Configuration:"
echo "Storage Account: $AZURE_STORAGE_ACCOUNT"
echo "Container: $AZURE_CONTAINER_NAME"

# Detect OS and install BlobFuse2
if [ -f /etc/debian_version ]; then
    echo "🐧 Detected Debian/Ubuntu - Installing BlobFuse2..."

    # Install dependencies
    apt-get update
    apt-get install -y wget apt-transport-https software-properties-common lsb-release

    # Add Microsoft repository for Ubuntu 20.04 (works for most Ubuntu versions)
    echo "Adding Microsoft repository..."
    wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb
    dpkg -i packages-microsoft-prod.deb
    apt-get update

    # Install FUSE3 dependencies and BlobFuse2
    echo "Installing FUSE3 and BlobFuse2..."
    apt-get install -y libfuse3-dev fuse3 blobfuse2
else
    echo "❌ Unsupported OS detected:"
    echo "   Supported: Ubuntu/Debian, RHEL/CentOS, SUSE Linux"
    echo "   Current OS info:"
    cat /etc/os-release 2>/dev/null || echo "   No /etc/os-release found"
    echo ""
    echo "   Please install BlobFuse2 manually or run on supported OS"
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

# Create BlobFuse2 configuration file
echo "📝 Creating BlobFuse2 configuration..."
cat > /opt/nextcloud/azure-config/config.yaml << EOF
# BlobFuse2 Configuration for Nextcloud

# Azure Storage configuration
azstorage:
  type: block
  account-name: $AZURE_STORAGE_ACCOUNT
  account-key: $AZURE_STORAGE_KEY
  container: $AZURE_CONTAINER_NAME
  mode: key

# Logging configuration
logging:
  type: syslog
  level: log_warning

# File cache configuration for better performance
file_cache:
  path: /mnt/blobfusetmp
  timeout-sec: 300
  max-size-mb: 2048

# Stream configuration for memory usage
stream:
  block-size-mb: 64
  max-buffers: 32
  buffer-size-mb: 64

# Performance optimizations for large files (ALL NEW)
libfuse:
  attribute-expiration-sec: 300
  entry-expiration-sec: 300
  negative-entry-expiration-sec: 10
  allow-other: true
  default-permission: 0755
  direct-io: false
  kernel-cache: true
EOF

# Secure the config file
chmod 600 /opt/nextcloud/azure-config/config.yaml

# Create mount script
echo "📜 Creating mount script..."
cat > /opt/nextcloud/azure-config/mount-blobfuse.sh << 'EOF'
#!/bin/bash

# BlobFuse2 Mount Script
set -e

echo "Starting BlobFuse2 mount process..."

# Check if already mounted
if mountpoint -q /mnt/blobfuse 2>/dev/null; then
    echo "✅ /mnt/blobfuse is already mounted"
    exit 0
fi

# Check if config file exists
if [ ! -f /opt/nextcloud/azure-config/config.yaml ]; then
    echo "❌ Config file not found: /opt/nextcloud/azure-config/config.yaml"
    exit 1
fi

# Check if mount point exists
if [ ! -d /mnt/blobfuse ]; then
    echo "❌ Mount point does not exist: /mnt/blobfuse"
    exit 1
fi

# Mount BlobFuse2
echo "Executing: blobfuse2 mount /mnt/blobfuse --config-file=/opt/nextcloud/azure-config/config.yaml"
blobfuse2 mount /mnt/blobfuse --config-file=/opt/nextcloud/azure-config/config.yaml --allow-other

# Verify mount
if mountpoint -q /mnt/blobfuse; then
    echo "✅ BlobFuse2 mounted successfully at /mnt/blobfuse"
else
    echo "❌ BlobFuse2 mount command completed but mount verification failed"
    exit 1
fi
EOF

chmod +x /opt/nextcloud/azure-config/mount-blobfuse.sh

# Create unmount script
cat > /opt/nextcloud/azure-config/unmount-blobfuse.sh << 'EOF'
#!/bin/bash

# BlobFuse2 Unmount Script
set -e

echo "Starting BlobFuse2 unmount process..."

# Check if mounted
if ! mountpoint -q /mnt/blobfuse 2>/dev/null; then
    echo "✅ /mnt/blobfuse is not mounted"
    exit 0
fi

# Unmount BlobFuse2
echo "Executing: blobfuse2 unmount /mnt/blobfuse"
blobfuse2 unmount /mnt/blobfuse

# Verify unmount
if ! mountpoint -q /mnt/blobfuse 2>/dev/null; then
    echo "✅ BlobFuse2 unmounted successfully"
else
    echo "❌ BlobFuse2 unmount command completed but verification failed"
    exit 1
fi
EOF

chmod +x /opt/nextcloud/azure-config/unmount-blobfuse.sh

# Create systemd service for automatic mounting
echo "🔧 Creating systemd service..."
cat > /etc/systemd/system/blobfuse.service << EOF
[Unit]
Description=Azure BlobFuse2 Mount
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/nextcloud/azure-config/mount-blobfuse.sh
ExecStop=/opt/nextcloud/azure-config/unmount-blobfuse.sh
RemainAfterExit=yes
TimeoutStartSec=30
Restart=no

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
echo "🎉 BlobFuse2 setup completed!"
echo ""
echo "📋 Next steps:"
echo "1. Update docker-compose.yml to mount /mnt/blobfuse"
echo "2. Configure Nextcloud external storage to use the mounted directory"
echo "3. Start/restart your Nextcloud containers"
echo ""
echo "🔧 Management commands:"
echo "sudo systemctl start blobfuse    # Mount BlobFuse2"
echo "sudo systemctl stop blobfuse     # Unmount BlobFuse2"
echo "sudo systemctl status blobfuse   # Check status"
echo "sudo journalctl -u blobfuse -f   # View logs"