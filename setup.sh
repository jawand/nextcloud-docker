#!/bin/bash

# Nextcloud Docker Compose Deployment Script
# For use with existing Caddy reverse proxy setup

set -e  # Exit on any error

echo "Nextcloud Docker Deployment Script"
echo "Compatible with Caddy reverse proxy"
echo "=================================="

# Check if required files exist in current directory
REQUIRED_FILES=("docker-compose.yml" "nextcloud-custom.ini" "caddy-nextcloud-config.txt")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "ERROR: Required file '$file' not found in current directory"
        echo "Please run this script from the nextcloud-docker directory"
        exit 1
    fi
done

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "ERROR: This script should not be run as root"
   exit 1
fi

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Check dependencies
echo "Checking dependencies..."
command -v docker >/dev/null 2>&1 || { echo "ERROR: Docker is required but not installed." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "ERROR: Docker Compose is required but not installed." >&2; exit 1; }

# Check available memory
TOTAL_MEM=$(free -m | awk 'NR==2{printf "%.0f", $2}')
echo "Available memory: ${TOTAL_MEM}MB"
if [ "$TOTAL_MEM" -lt 900 ]; then
    echo "WARNING: Less than 1GB RAM detected. Performance may be limited."
    echo "Consider adding swap space or upgrading RAM."
    read -p "Continue anyway? [y/N]: " CONTINUE_LOW_MEM
    if [[ ! $CONTINUE_LOW_MEM =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if Caddy is running
if ! systemctl is-active --quiet caddy; then
    echo "ERROR: Caddy is not running. Make sure Caddy is configured first."
    exit 1
fi

echo "Caddy is running"

# Check if port 8080 is available
if netstat -tuln | grep -q ":8080 "; then
    echo "ERROR: Port 8080 is already in use"
    echo "Please free up port 8080 or modify docker-compose.yml"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create project directory
PROJECT_DIR="$HOME/nextcloud"
echo "Creating project directory: $PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Copy necessary files to project directory
echo "Copying configuration files..."
cp "$SCRIPT_DIR/docker-compose.yml" "$PROJECT_DIR/" || { echo "ERROR: docker-compose.yml not found in script directory"; exit 1; }
cp "$SCRIPT_DIR/nextcloud-custom.ini" "$PROJECT_DIR/" || { echo "ERROR: nextcloud-custom.ini not found in script directory"; exit 1; }
cp "$SCRIPT_DIR/caddy-nextcloud-config.txt" "$PROJECT_DIR/" || { echo "ERROR: caddy-nextcloud-config.txt not found in script directory"; exit 1; }

cd "$PROJECT_DIR"

# Create subdirectories
mkdir -p data/nextcloud

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "Creating environment configuration..."
    
    # Get user inputs
    read -p "Enter your Nextcloud domain [next.example.com]: " DOMAIN
    DOMAIN=${DOMAIN:-next.example.com}
    read -p "Enter Nextcloud admin username [admin]: " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}
    
    while true; do
        read -s -p "Enter Nextcloud admin password: " ADMIN_PASSWORD
        echo
        read -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
        echo
        [ "$ADMIN_PASSWORD" = "$ADMIN_PASSWORD_CONFIRM" ] && break
        echo "ERROR: Passwords don't match. Please try again."
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
    echo "Environment file created"
else
    echo "Environment file already exists"
    source .env
fi

# Set proper permissions
chmod 600 .env

# Check for container name conflicts
echo "Checking for container name conflicts..."
CONFLICTING_CONTAINERS=$(docker ps -a --format "table {{.Names}}" | grep -E "nextcloud-(db|redis|app|cron)" || true)
if [ ! -z "$CONFLICTING_CONTAINERS" ]; then
    echo "Found existing containers with nextcloud names:"
    echo "$CONFLICTING_CONTAINERS"
    read -p "Do you want to remove these containers? [y/N]: " REMOVE_CONTAINERS
    if [[ $REMOVE_CONTAINERS =~ ^[Yy]$ ]]; then
        echo "$CONFLICTING_CONTAINERS" | tail -n +2 | xargs -r docker rm -f
        echo "Removed conflicting containers"
    fi
fi

# Start services
echo "Starting Nextcloud services..."
docker-compose pull
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 45

# Check if services are running
if docker-compose ps | grep -q "Up"; then
    echo "Nextcloud deployment completed successfully!"
    echo ""
    echo "Next Steps:"
    echo "1. Configure Caddy for Nextcloud:"
    echo "   - Copy configuration from 'caddy-nextcloud-config.txt'"
    echo "   - Add it to your /etc/caddy/Caddyfile"
    echo "   - Update domain name to: $NEXTCLOUD_DOMAIN"
    echo "   - Restart Caddy: sudo systemctl restart caddy"
    echo ""
    echo "2. Access Nextcloud:"
    echo "   https://$NEXTCLOUD_DOMAIN"
    echo ""
    echo "Admin credentials:"
    echo "   Username: $ADMIN_USER"
    echo "   Password: [as entered during setup]"
    echo ""
    echo "Management commands:"
    echo "   Start:   cd $PROJECT_DIR && docker-compose up -d"
    echo "   Stop:    cd $PROJECT_DIR && docker-compose down"  
    echo "   Logs:    cd $PROJECT_DIR && docker-compose logs -f"
    echo "   Update:  cd $PROJECT_DIR && docker-compose pull && docker-compose up -d"
else
    echo "ERROR: Some services failed to start. Check logs with: docker-compose logs"
    docker-compose ps
    exit 1
fi

# Show all containers
echo "All running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"