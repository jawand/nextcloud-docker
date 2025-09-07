# Nextcloud Docker Setup

Production-ready Nextcloud deployment using Docker Compose, optimized for performance and designed to work with existing n8n/Nginx Proxy Manager setups.

## Features

- **Latest Images**: Nextcloud 29, MariaDB 11.4, Redis 7.4
- **Low Memory Optimized**: Configured for 1GB RAM servers
- **Security**: Proper network isolation, secure defaults
- **Domain Ready**: Pre-configured for next.example.com
- **Caddy Compatible**: Works seamlessly with your existing n8n Caddy setup
- **Azure Blob Integration**: Optional external storage for unlimited capacity

## Quick Start

### Prerequisites

1. **Verify n8n/Caddy is running:**

   ```bash
   sudo systemctl status caddy
   docker ps | grep n8n
   ```

2. **Check port 8080 is available:**
   ```bash
   netstat -tuln | grep 8080
   ```
   Port 8080 should be free for Nextcloud

3. **Configure DNS for your domain:**
   - Point your domain (e.g., `next.prismantis.com`) to your server's IP
   - Wait for DNS propagation (5-60 minutes)
   - Test with: `nslookup next.prismantis.com`

4. **Ensure firewall ports are open:**
   - Port 80 (HTTP) - Required for Let's Encrypt SSL validation
   - Port 443 (HTTPS) - For SSL traffic
   - Port 8080 should only be accessible locally

### Deployment

1. **Configure DNS first**: Point your domain to your server's IP address
2. **Deploy Nextcloud**: Run `./setup.sh` and follow the prompts
3. **Configure Caddy**: Add configuration from `caddy-nextcloud-config.txt` to `/etc/caddy/Caddyfile`
4. **Validate Caddy config**: `sudo caddy validate --config /etc/caddy/Caddyfile`
5. **Restart Caddy**: `sudo systemctl restart caddy`
6. **Wait for SSL**: Caddy will automatically obtain Let's Encrypt certificate
7. **Access**: Visit https://your-domain.com

## Architecture

```
Internet → Caddy (Port 443) → Nextcloud App (Port 8080)
                                      ↓
                              MariaDB + Redis
```

## Services

- **nextcloud-app**: Main Nextcloud application (Nextcloud 29)
- **nextcloud-db**: MariaDB 11.4 database with performance optimizations
- **nextcloud-redis**: Redis 7.4 cache with memory management
- **nextcloud-cron**: Background task processor

## Performance Optimizations (Low Memory Server)

- PHP memory limit: 256MB (optimized for 1GB RAM servers)
- Upload limit: 1GB (reduced for stability)
- OPcache enabled with conservative settings
- Redis memory management (64MB with LRU eviction)
- MariaDB tuned for low memory usage
- Container memory limits to prevent OOM kills

## DNS Configuration

### Option 1: A Record (Simple)
```
Type: A
Name: next (or your subdomain)
Value: [Your server's public IP]
TTL: 300
```

### Option 2: CNAME (Recommended for Azure)
If using Azure VM with dynamic IP:
```
Type: CNAME
Name: next
Value: [Your Azure VM DNS name like: vm-name.region.cloudapp.azure.com]
TTL: 300
```

## Caddy Configuration & SSL

### 1. Add Nextcloud Configuration
**Edit your existing `/etc/caddy/Caddyfile`:**

```caddy
# Your existing n8n configuration
your-n8n-domain.com {
    reverse_proxy localhost:5678
}

# Add this for Nextcloud
next.prismantis.com {
    # Security headers
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        Permissions-Policy "interest-cohort=()"
    }
    
    # Handle large file uploads
    request_body {
        max_size 1GB
    }
    
    # Proxy to Nextcloud container
    reverse_proxy localhost:8080 {
        header_up X-Forwarded-Proto "https"
        header_up X-Forwarded-For {remote_host}
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        
        transport http {
            read_timeout 3600s
            write_timeout 3600s
        }
    }
}
```

### 2. Validate and Restart Caddy
```bash
# Test configuration syntax
sudo caddy validate --config /etc/caddy/Caddyfile

# If valid, restart Caddy
sudo systemctl restart caddy

# Monitor SSL certificate generation
sudo journalctl -u caddy -f
```

### 3. SSL Certificate (Automatic)
Caddy automatically:
- ✅ Obtains Let's Encrypt SSL certificates
- ✅ Handles HTTP to HTTPS redirects  
- ✅ Renews certificates before expiry
- ✅ Serves traffic on port 443

**Requirements for automatic SSL:**
- Domain must resolve to your server
- Ports 80 and 443 must be open
- DNS propagation must be complete

## Management Commands

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker-compose logs -f

# Update to latest images
docker-compose pull && docker-compose up -d

# Backup data
docker-compose exec nextcloud-app php occ maintenance:mode --on
# Backup volumes: nextcloud_app_data, nextcloud_data, nextcloud_db_data
docker-compose exec nextcloud-app php occ maintenance:mode --off
```

## Security Notes

- All passwords are auto-generated during setup
- Database and Redis are isolated in internal network
- Only HTTP port 8080 exposed locally (HTTPS handled by Caddy)
- Trusted proxies configured for proper IP forwarding

## Troubleshooting

### Container Conflicts

The setup script checks for existing containers and offers to remove them.

### Network Issues

**Check if Caddy is running:**

```bash
sudo systemctl status caddy
```

**Check Caddy configuration:**

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
```

**If Caddy fails to start:**

```bash
# Check Caddy logs
sudo journalctl -u caddy -f

# Test configuration
sudo caddy fmt --overwrite /etc/caddy/Caddyfile
```

**Test Nextcloud connectivity:**

```bash
# Test local connection
curl -I http://localhost:8080

# Test through Caddy
curl -I https://your-domain.com

# Check SSL certificate
openssl s_client -connect your-domain.com:443 -servername your-domain.com
```

### SSL Issues

**If SSL certificate fails:**

1. **Check DNS resolution:**
   ```bash
   nslookup your-domain.com
   dig your-domain.com @8.8.8.8
   ```

2. **Verify firewall ports:**
   ```bash
   # Check if ports are open
   sudo netstat -tuln | grep -E ':80|:443'
   ```

3. **Monitor Caddy SSL process:**
   ```bash
   sudo journalctl -u caddy -f
   # Look for "obtaining certificate" messages
   ```

4. **Test HTTP challenge:**
   ```bash
   # Caddy needs port 80 for Let's Encrypt validation
   curl -I http://your-domain.com/.well-known/acme-challenge/test
   ```

### Azure Firewall Configuration

**Ensure these ports are open in your Network Security Group:**

1. **Go to Azure Portal** → Virtual Machines → Your VM → Networking
2. **Check inbound security rules** for:
   - **Port 22** (SSH) - For management
   - **Port 80** (HTTP) - Required for Let's Encrypt validation
   - **Port 443** (HTTPS) - For SSL traffic
   - **Port 8080** should NOT be exposed externally

3. **Add rules if missing:**
   ```
   Priority: 1000
   Name: Allow-HTTPS
   Port: 443
   Protocol: TCP
   Source: Any
   Action: Allow
   ```

### Performance Issues

**Monitor resource usage:**

```bash
docker stats --no-stream
free -h
```

**Check container logs:**

```bash
docker-compose logs nextcloud-app
docker-compose logs nextcloud-db
```

**Low memory warnings:**

- Add swap space (see `low-memory-setup.md`)
- Disable unused Nextcloud apps
- Consider upgrading RAM

### Common Error Solutions

**"Port 8080 already in use":**

1. Check what's using port 8080: `netstat -tuln | grep 8080`
2. Stop the conflicting service or change Nextcloud port in docker-compose.yml
3. Restart Nextcloud services

**"Container keeps restarting":**

1. Check memory usage: `docker stats`
2. Review logs: `docker-compose logs [service-name]`
3. Verify .env file configuration

**"Database connection failed":**

1. Wait 60 seconds for MariaDB to fully start
2. Check database logs: `docker-compose logs nextcloud-db`
3. Verify MYSQL_PASSWORD in .env file

## Azure Blob Storage Integration

For unlimited storage capacity and better performance on your 1GB server:

### Quick Setup
1. **Create Azure Storage:**
   ```bash
   ./azure-storage-setup.sh
   ```

2. **Configure in Nextcloud:**
   - Login as admin → Settings → Apps
   - Enable "External storage support"
   - Go to Administration → External Storage
   - Add "Amazon S3" storage type
   - Use Azure Blob credentials (see `azure-blob-integration-guide.md`)

### Benefits
- **Unlimited storage** without server disk limits
- **Cost-effective** (~$0.018/GB/month)
- **Better performance** for large files
- **Automatic backups** and redundancy

**See `azure-blob-integration-guide.md` for detailed setup instructions.**
