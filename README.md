# Nextcloud Docker Setup

Simple Nextcloud deployment using Docker Compose with Caddy reverse proxy.

## Features

- Nextcloud 30, MariaDB 11.4, Redis 8.2
- Optimized for low memory servers
- Works with existing Caddy setups
- Secure defaults and network isolation

## Prerequisites

1. **Docker and Docker Compose installed**
2. **Caddy web server running**
3. **Domain configured** - Point your domain to your server's IP
4. **Firewall ports open** - 80 (HTTP), 443 (HTTPS)
5. **Port 8080 available** - For Nextcloud container

## Deployment

1. **Run setup script**: `./setup.sh`
2. **Configure Caddy**: Add configuration from `caddy-nextcloud-config.txt` to `/etc/caddy/Caddyfile`
3. **Restart Caddy**: `sudo systemctl restart caddy`
4. **Access**: Visit https://your-domain.com

## Services

- **nextcloud-app**: Main application
- **nextcloud-db**: MariaDB database  
- **nextcloud-redis**: Redis cache
- **nextcloud-cron**: Background tasks

## DNS Configuration

Create an A record pointing your domain to your server's IP:
```
Type: A
Name: next (or your subdomain)
Value: [Your server's public IP]
TTL: 300
```

## Caddy Configuration

Add the configuration from `caddy-nextcloud-config.txt` to your `/etc/caddy/Caddyfile`:

```bash
# Test configuration
sudo caddy validate --config /etc/caddy/Caddyfile

# Restart Caddy
sudo systemctl restart caddy
```

Caddy will automatically obtain SSL certificates from Let's Encrypt.

## Management Commands

```bash
# Start services
cd ~/nextcloud && docker-compose up -d

# Stop services
cd ~/nextcloud && docker-compose down

# View logs
cd ~/nextcloud && docker-compose logs -f

# Update images
cd ~/nextcloud && docker-compose pull && docker-compose up -d
```

## Troubleshooting

**Check services:**
```bash
# Caddy status
sudo systemctl status caddy

# Container status
cd ~/nextcloud && docker-compose ps

# Container logs
cd ~/nextcloud && docker-compose logs [service-name]
```

**Common issues:**
- Port 8080 in use: `netstat -tuln | grep 8080`
- DNS not propagated: `nslookup your-domain.com`
- Caddy config errors: `sudo caddy validate --config /etc/caddy/Caddyfile`
