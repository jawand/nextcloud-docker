# Nextcloud Docker Setup

Production-ready Nextcloud deployment using Docker Compose, optimized for performance and designed to work with existing n8n/Nginx Proxy Manager setups.

## Features

- **Latest Images**: Nextcloud 29, MariaDB 11.4, Redis 7.4
- **High Performance**: Optimized PHP settings, Redis caching, dedicated cron service
- **Security**: Proper network isolation, secure defaults
- **Domain Ready**: Pre-configured for next.example.com
- **NPM Compatible**: Works seamlessly with existing Nginx Proxy Manager

## Quick Start

1. **Prerequisites**: Ensure your n8n/Nginx Proxy Manager is running with `npm_default` network
2. **Deploy**: Run `./setup.sh` and follow the prompts
3. **Configure NPM**: Add proxy host for next.example.com → nextcloud-app:80
4. **Access**: Visit https://next.example.com

## Architecture

```
Internet → Nginx Proxy Manager → Nextcloud App
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

## Nginx Proxy Manager Configuration

**Basic Settings:**
- Domain: `next.example.com`
- Forward to: `nextcloud-app:80`
- Block Common Exploits: ✅
- Websockets Support: ✅

**Advanced Tab:**
```nginx
client_max_body_size 1G;
proxy_request_buffering off;
proxy_buffering off;
proxy_read_timeout 3600;
proxy_connect_timeout 60;
proxy_send_timeout 600;
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

**Container conflicts**: The setup script checks for existing containers
**Network issues**: Ensure npm_default network exists from your n8n setup
**Performance**: Monitor with `docker stats` and adjust PHP/Redis limits as needed