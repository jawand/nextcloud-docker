#!/bin/bash

# Nextcloud Health Check Script
# Verifies all services are running properly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🏥 Nextcloud Health Check${NC}"
echo "=========================="

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}❌ docker-compose.yml not found${NC}"
    exit 1
fi

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found${NC}"
    exit 1
fi

source .env

# Check npm_default network
echo -e "${YELLOW}🌐 Checking npm_default network...${NC}"
if docker network ls | grep -q npm_default; then
    echo -e "${GREEN}✅ npm_default network exists${NC}"
else
    echo -e "${RED}❌ npm_default network not found${NC}"
    exit 1
fi

# Check container status
echo -e "${YELLOW}📦 Checking container status...${NC}"
CONTAINERS=("nextcloud-db" "nextcloud-redis" "nextcloud-app" "nextcloud-cron")
ALL_RUNNING=true

for container in "${CONTAINERS[@]}"; do
    if docker ps | grep -q "$container"; then
        STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")
        echo -e "${GREEN}✅ $container: Running${NC}"
    else
        echo -e "${RED}❌ $container: Not running${NC}"
        ALL_RUNNING=false
    fi
done

if [ "$ALL_RUNNING" = false ]; then
    echo -e "${RED}❌ Some containers are not running${NC}"
    echo -e "${YELLOW}💡 Try: docker-compose up -d${NC}"
    exit 1
fi

# Check database connection
echo -e "${YELLOW}🗄️  Testing database connection...${NC}"
if docker-compose exec -T nextcloud-db mysql -u nextcloud -p"$MYSQL_PASSWORD" -e "SELECT 1;" nextcloud >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Database connection successful${NC}"
else
    echo -e "${RED}❌ Database connection failed${NC}"
fi

# Check Redis connection
echo -e "${YELLOW}🔴 Testing Redis connection...${NC}"
if docker-compose exec -T nextcloud-redis redis-cli -a "$REDIS_PASSWORD" ping >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Redis connection successful${NC}"
else
    echo -e "${RED}❌ Redis connection failed${NC}"
fi

# Check Nextcloud status
echo -e "${YELLOW}☁️  Testing Nextcloud application...${NC}"
if docker-compose exec -T nextcloud-app php occ status --no-warnings 2>/dev/null | grep -q "installed: true"; then
    echo -e "${GREEN}✅ Nextcloud is installed and running${NC}"
    
    # Get version info
    VERSION=$(docker-compose exec -T nextcloud-app php occ status --no-warnings 2>/dev/null | grep "version:" | cut -d' ' -f4)
    echo -e "${BLUE}📋 Nextcloud version: $VERSION${NC}"
else
    echo -e "${YELLOW}⚠️  Nextcloud may not be fully configured yet${NC}"
fi

# Check disk usage
echo -e "${YELLOW}💾 Checking disk usage...${NC}"
docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}\t{{.Reclaimable}}"

# Show resource usage
echo -e "${YELLOW}📊 Current resource usage:${NC}"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" $(docker-compose ps -q)

echo ""
echo -e "${GREEN}🎉 Health check completed!${NC}"
echo -e "${BLUE}💡 Access your Nextcloud at: https://$NEXTCLOUD_DOMAIN${NC}"