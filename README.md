# Nextcloud Docker Setup with Azure Blob Storage

Complete Nextcloud deployment using Docker Compose with Caddy reverse proxy and Azure Blob Storage for user data.

## Features

- Nextcloud 30, MariaDB 11.4, Redis 8.2
- Optimized for 2GB RAM servers (scalable to 4GB)
- Azure Blob Storage integration via BlobFuse
- Works with existing Caddy setups
- Secure defaults and network isolation
- Automatic file upload handling for large files

## Prerequisites

1. **Docker and Docker Compose installed**
2. **Caddy web server running**
3. **Domain configured** - Point your domain to your server's IP
4. **Firewall ports open** - 80 (HTTP), 443 (HTTPS)
5. **Port 8080 available** - For Nextcloud container
6. **Azure Storage Account** - With container for user data

## Quick Setup

1. **Configure environment**: Create `.env` file with your Azure and Nextcloud settings
2. **Setup BlobFuse**: `docker-compose --profile setup up blobfuse-setup`
3. **Start services**: `docker-compose up -d` (Azure storage auto-configures)
4. **Configure Caddy**: Add configuration from `caddy-nextcloud-config.txt` to `/etc/caddy/Caddyfile`
5. **Restart Caddy**: `sudo systemctl restart caddy`
6. **Access**: Visit https://your-domain.com

## Environment Configuration

Create `.env` file with the following variables:

```bash
# Nextcloud Configuration
NEXTCLOUD_DOMAIN=your-domain.com
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=your-secure-password

# Database Configuration
MYSQL_ROOT_PASSWORD=your-root-password
MYSQL_PASSWORD=your-db-password

# Redis Configuration
REDIS_PASSWORD=your-redis-password

# Azure Blob Storage Configuration
AZURE_STORAGE_ACCOUNT=your-storage-account
AZURE_STORAGE_KEY=your-storage-key
AZURE_CONTAINER_NAME=your-container-name
```

## Architecture

### Services
- **nextcloud-app**: Main application (768MB RAM limit)
- **nextcloud-db**: MariaDB database (512MB RAM limit)
- **nextcloud-redis**: Redis cache (128MB RAM limit)
- **nextcloud-cron**: Background tasks (256MB RAM limit)

### Storage
- **Local storage**: System files, database, cache (VM disk)
- **Azure Blob Storage**: User data files (via BlobFuse mount)

## DNS Configuration

Create an A record pointing your domain to your server's IP:
```
Type: A
Name: next (or your subdomain)
Value: [Your server's public IP]
TTL: 300
```

## What the Setup Does

1. **BlobFuse setup profile**: Installs BlobFuse on host system with systemd service
2. **Main services**: Starts Nextcloud with optimized 2GB RAM configuration
3. **Configure profile**: Sets up Azure Blob Storage as external storage for user data
4. **Caddy integration**: Handles large file uploads properly

## Caddy Configuration

Add the configuration from `caddy-nextcloud-config.txt` to your `/etc/caddy/Caddyfile`:

```bash
# Test configuration
sudo caddy validate --config /etc/caddy/Caddyfile

# Reload Caddy
sudo systemctl reload caddy
```

The Caddy configuration includes:
- Proper file upload handling for large files
- Content-Length header preservation
- Extended timeouts for uploads
- Security headers

Caddy will automatically obtain SSL certificates from Let's Encrypt.

## Management Commands

```bash
# One-time setup (run in order)
docker-compose --profile setup up blobfuse-setup  # Install BlobFuse
docker-compose up -d                               # Start services (auto-configures Azure)

# Daily operations
docker-compose up -d                    # Start services
docker-compose down                     # Stop services
docker-compose logs -f nextcloud-app    # View logs
docker-compose pull && docker-compose up -d  # Update images

# BlobFuse management (after setup)
sudo systemctl start blobfuse           # Mount Azure storage
sudo systemctl stop blobfuse            # Unmount Azure storage
sudo systemctl status blobfuse          # Check mount status

# Caddy management
sudo systemctl status caddy             # Check Caddy status
sudo systemctl reload caddy             # Reload Caddy config
sudo caddy validate --config /etc/caddy/Caddyfile  # Test config
```

## File Storage Locations

- **Nextcloud system files**: Docker volumes (`nextcloud_app_data`)
- **Database**: Docker volume (`nextcloud_db_data`)
- **User uploaded files**: Azure Blob Storage via BlobFuse
- **Cache**: Docker volume (`nextcloud_redis_data`)

## Troubleshooting

**Check services:**
```bash
# All container status
docker-compose ps

# BlobFuse mount status
sudo systemctl status blobfuse
mountpoint /mnt/blobfuse

# Caddy status
sudo systemctl status caddy

# Container logs
docker-compose logs nextcloud-app
```

**Common issues:**

**BlobFuse not mounted:**
```bash
# Check if mounted
mountpoint /mnt/blobfuse

# Restart BlobFuse service
sudo systemctl restart blobfuse

# Check BlobFuse logs
journalctl -u blobfuse -f
```

**File upload errors:**
- Check Caddy configuration includes the updated config from `caddy-nextcloud-config.txt`
- Verify BlobFuse mount is accessible: `ls -la /mnt/blobfuse`
- Check container can access mount: `docker exec nextcloud-app ls -la /mnt/azure-blob`

**Memory issues:**
- Monitor usage: `docker stats`
- Current config optimized for 2GB RAM with ~300MB system overhead

**Network issues:**
- Port 8080 in use: `netstat -tuln | grep 8080`
- DNS not propagated: `nslookup your-domain.com`
- Caddy config errors: `sudo caddy validate --config /etc/caddy/Caddyfile`
