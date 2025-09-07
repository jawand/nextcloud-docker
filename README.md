# Nextcloud Docker Setup

Production-ready Nextcloud deployment using Docker Compose, optimized for performance and designed to work with existing n8n/Nginx Proxy Manager setups.

## Features

- **Latest Images**: Nextcloud 29, MariaDB 11.4, Redis 7.4
- **Low Memory Optimized**: Configured for 1GB RAM servers
- **Security**: Proper network isolation, secure defaults
- **Domain Ready**: Pre-configured for next.example.com
- **Caddy Compatible**: Works seamlessly with your existing n8n Caddy setup

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

### Deployment

1. **Deploy**: Run `./setup.sh` and follow the prompts
2. **Configure Caddy**: Add configuration from `caddy-nextcloud-config.txt` to `/etc/caddy/Caddyfile`
3. **Restart Caddy**: `sudo systemctl restart caddy`
4. **Access**: Visit https://next.example.com

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

## Caddy Configuration

**Add to your existing `/etc/caddy/Caddyfile`:**

```caddy
next.example.com {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
    }
    
    request_body {
        max_size 1GB
    }
    
    reverse_proxy localhost:8080 {
        header_up X-Forwarded-Proto "https"
        header_up X-Forwarded-For {remote_host}
        header_up Host {host}
        
        transport http {
            read_timeout 3600s
            write_timeout 3600s
        }
    }
}
```

**Then restart Caddy:**
```bash
sudo systemctl restart caddy
```

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
- Only HTTP port 80 exposed internally (HTTPS handled by NPM)
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
curl -I https://next.example.com
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
