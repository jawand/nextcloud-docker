#!/bin/bash

# Nextcloud Docker Compose Deployment Script
# For use with existing Nginx Proxy Manager setup

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Nextcloud Docker Deployment Script${NC}"
echo -e "${BLUE}   (Compatible with existing Nginx Proxy Manager)${NC}"
echo "=================================================="

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}❌ This script should not be run as root${NC}"
   exit 1
fi

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Check dependencies
echo -e "${YELLOW}📋 Checking dependencies...${NC}"
command -v docker >/dev/null 2>&1 || { echo -e "${RED}❌ Docker is required but not installed.${NC}" >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo -e "${RED}❌ Docker Compose is required but not installed.${NC}" >&2; exit 1; }

# Check if npm_default network exists (from n8n setup)
if ! docker network ls | grep -q npm_default; then
    echo -e "${RED}❌ npm_default network not found. Is your n8n/Nginx Proxy Manager running?${NC}"
    echo -e "${YELLOW}💡 Make sure your n8n setup is running first.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Found existing npm_default network${NC}"

# Create project directory
PROJECT_DIR="$HOME/nextcloud"
echo -e "${YELLOW}📁 Creating project directory: $PROJECT_DIR${NC}"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Create subdirectories
mkdir -p data/nextcloud

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo -e "${YELLOW}⚙️  Creating environment configuration...${NC}"
    
    # Get user inputs
    read -p "Enter your Nextcloud domain (e.g., next.example.com): " DOMAIN
    read -p "Enter Nextcloud admin username [admin]: " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}
    
    while true; do
        read -s -p "Enter Nextcloud admin password: " ADMIN_PASSWORD
        echo
        read -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
        echo
        [ "$ADMIN_PASSWORD" = "$ADMIN_PASSWORD_CONFIRM" ] && break
        echo -e "${RED}❌ Passwords don't match. Please try again.${NC}"
    done
    
    # Generate random passwords
    MYSQL_ROOT_PASSWORD=$(generate_password)
    MYSQL_PASSWORD=$(generate_password)
    REDIS_PASSWORD=$(generate_password)
    
    cat > .env << EOF
# Database Configuration
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_PASSWORD=$MYSQL_PASSWORD

# Redis Configuration  
REDIS_PASSWORD=$REDIS_PASSWORD

# Nextcloud Admin Configuration
NEXTCLOUD_ADMIN_USER=$ADMIN_USER
NEXTCLOUD_ADMIN_PASSWORD=$ADMIN_PASSWORD

# Domain Configuration
NEXTCLOUD_DOMAIN=$DOMAIN
NEXTCLOUD_TRUSTED_DOMAINS=$DOMAIN,localhost

# Timezone
TZ=UTC
EOF
    echo -e "${GREEN}✅ Environment file created${NC}"
else
    echo -e "${GREEN}✅ Environment file already exists${NC}"
    source .env
fi

# Set proper permissions
chmod 600 .env

# Check for container name conflicts
echo -e "${YELLOW}🔍 Checking for container name conflicts...${NC}"
CONFLICTING_CONTAINERS=$(docker ps -a --format "table {{.Names}}" | grep -E "nextcloud-(db|redis|app|cron)" || true)
if [ ! -z "$CONFLICTING_CONTAINERS" ]; then
    echo -e "${YELLOW}⚠️  Found existing containers with nextcloud names:${NC}"
    echo "$CONFLICTING_CONTAINERS"
    read -p "Do you want to remove these containers? [y/N]: " REMOVE_CONTAINERS
    if [[ $REMOVE_CONTAINERS =~ ^[Yy]$ ]]; then
        echo "$CONFLICTING_CONTAINERS" | tail -n +2 | xargs -r docker rm -f
        echo -e "${GREEN}✅ Removed conflicting containers${NC}"
    fi
fi

# Start services
echo -e "${YELLOW}🚀 Starting Nextcloud services...${NC}"
docker-compose pull
docker-compose up -d

# Wait for services to be ready
echo -e "${YELLOW}⏳ Waiting for services to start...${NC}"
sleep 45

# Check if services are running
if docker-compose ps | grep -q "Up"; then
    echo -e "${GREEN}🎉 Nextcloud deployment completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}📋 Next Steps:${NC}"
    echo "1. 🌐 Add a new proxy host in your Nginx Proxy Manager:"
    echo "   - Domain: $NEXTCLOUD_DOMAIN"
    echo "   - Forward to: nextcloud-app:80"
    echo "   - Enable 'Block Common Exploits'"
    echo "   - Enable 'Websockets Support'"
    echo "   - Get SSL certificate (Let's Encrypt)"
    echo ""
    echo "2. 🔧 Advanced settings in Nginx Proxy Manager:"
    echo "   Add this to the 'Advanced' tab:"
    echo ""
    echo "   client_max_body_size 10G;"
    echo "   proxy_request_buffering off;"
    echo "   proxy_buffering off;"
    echo ""
    echo "3. 🌟 Once configured, access via:"
    echo "   https://$NEXTCLOUD_DOMAIN"
    echo ""
    echo "👤 Admin credentials:"
    echo "   Username: $ADMIN_USER"
    echo "   Password: [as entered during setup]"
    echo ""
    echo "🔧 Management commands:"
    echo "   Start:   cd $PROJECT_DIR && docker-compose up -d"
    echo "   Stop:    cd $PROJECT_DIR && docker-compose down"  
    echo "   Logs:    cd $PROJECT_DIR && docker-compose logs -f"
    echo "   Update:  cd $PROJECT_DIR && docker-compose pull && docker-compose up -d"
else
    echo -e "${RED}❌ Some services failed to start. Check logs with: docker-compose logs${NC}"
    docker-compose ps
    exit 1
fi

# Show all containers (including n8n)
echo -e "${YELLOW}📊 All running containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"