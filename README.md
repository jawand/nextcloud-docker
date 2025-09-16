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
2. **Setup Azure BlobFuse**: `sudo ./setup-azure-blobfuse.sh` (installs BlobFuse on HOST machine)
3. **Start Nextcloud**: `./setup.sh` (starts Docker services, auto-configures Azure storage)
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

### Azure BlobFuse Setup (`setup-azure-blobfuse.sh`):
⚠️ **Installs directly on HOST machine (not in Docker)**
1. Installs BlobFuse package and dependencies
2. Creates mount point at `/mnt/blobfuse` on HOST
3. Creates systemd service for automatic mounting
4. Mounts Azure Blob Storage as a filesystem on HOST

### Nextcloud Setup (`setup.sh`):
1. Starts Nextcloud services with optimized 2GB RAM configuration
2. Uses custom entrypoint (`nextcloud-entrypoint.sh`) that automatically:
   - Starts Nextcloud web server
   - Detects Azure Blob mount at `/mnt/azure-blob`
   - Enables External Storage app
   - Configures Azure Blob Storage for user files
3. Sets up database, Redis cache, and cron services

**Note:** `nextcloud-entrypoint.sh` runs automatically inside the container - no manual execution needed.

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
sudo ./setup-azure-blobfuse.sh          # Install BlobFuse on HOST
./setup.sh                              # Start Nextcloud services

# Daily operations
docker-compose up -d                    # Start services
docker-compose down                     # Stop services
docker-compose logs -f nextcloud-app    # View logs
docker-compose pull && docker-compose up -d  # Update images

# BlobFuse management (HOST machine)
sudo systemctl start blobfuse           # Mount Azure storage
sudo systemctl stop blobfuse            # Unmount Azure storage
sudo systemctl status blobfuse          # Check mount status
mountpoint /mnt/blobfuse                 # Verify mount

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
