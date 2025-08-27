# Low Memory Server Setup (1GB RAM)

This configuration is specifically optimized for servers with 1GB RAM and 1 CPU core.

## Memory Allocation

Total available: ~1GB

- System + n8n: ~400MB
- Nextcloud containers: ~600MB
  - nextcloud-app: 400MB (limit)
  - nextcloud-db: 200MB (limit)
  - nextcloud-redis: 80MB (limit)
  - nextcloud-cron: 150MB (limit)

## Performance Expectations

- **Slower response times** compared to higher-spec servers
- **Limited concurrent users** (2-5 users recommended)
- **Smaller file uploads** (1GB max instead of 10GB)
- **Reduced caching** (64MB Redis vs 512MB)

## Monitoring Commands

```bash
# Check memory usage
docker stats --no-stream

# Check system memory
free -h

# Monitor Nextcloud performance
docker-compose exec nextcloud-app php occ status
```

## Optimization Tips

1. **Disable unnecessary apps** in Nextcloud admin panel
2. **Use external storage** for large files when possible
3. **Regular cleanup** of logs and temporary files
4. **Monitor swap usage** - add swap if needed

## Swap Configuration (Recommended)

```bash
# Create 1GB swap file
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## Warning Signs

If you see these, your server is overloaded:

- Containers frequently restarting
- Very slow web interface
- Database connection errors
- Out of memory errors in logs

Consider upgrading to 2GB RAM if possible.
