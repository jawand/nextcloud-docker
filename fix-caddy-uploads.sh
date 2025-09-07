#!/bin/bash

# Fix Caddy configuration for Nextcloud file uploads
# Resolves "Content-Length HTTP header is missing" error

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}🔧 Fix Caddy Configuration for Nextcloud Uploads${NC}"
echo "================================================"

# Check if Caddy is running
if ! systemctl is-active --quiet caddy; then
    echo -e "${RED}❌ Caddy is not running${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Caddy is running${NC}"

# Backup current Caddyfile
echo -e "${YELLOW}💾 Backing up current Caddyfile...${NC}"
sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.backup.$(date +%Y%m%d_%H%M%S)

# Check if our domain configuration exists
DOMAIN="next.prismantis.com"
if ! sudo grep -q "$DOMAIN" /etc/caddy/Caddyfile; then
    echo -e "${RED}❌ Domain $DOMAIN not found in Caddyfile${NC}"
    echo -e "${YELLOW}💡 Please add the configuration from caddy-nextcloud-config.txt manually${NC}"
    exit 1
fi

echo -e "${YELLOW}🔍 Found $DOMAIN configuration in Caddyfile${NC}"

# Show current configuration
echo -e "${BLUE}📋 Current Nextcloud configuration:${NC}"
sudo sed -n "/$DOMAIN/,/^}/p" /etc/caddy/Caddyfile

echo ""
echo -e "${YELLOW}⚠️  This will update your Caddy configuration to fix upload issues${NC}"
echo -e "${YELLOW}⚠️  The current configuration will be backed up${NC}"
read -p "Continue with the fix? [y/N]: " CONFIRM

if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}❌ Operation cancelled${NC}"
    exit 0
fi

# Create the fixed configuration
echo -e "${YELLOW}🔧 Creating fixed Caddy configuration...${NC}"

# Read the current Caddyfile and replace the Nextcloud section
sudo bash -c "
# Create temporary file with the new configuration
cat > /tmp/nextcloud_fixed_config << 'CADDY_EOF'
$DOMAIN {
    # Add debug logging
    log {
        output stderr
        format console
        level INFO
    }
    
    # Add security headers
    header {
        # Enable HSTS
        Strict-Transport-Security \"max-age=31536000; includeSubDomains\"
        # Disable FLoC tracking
        Permissions-Policy \"interest-cohort=()\"
        # XSS protection
        X-XSS-Protection \"1; mode=block\"
        # Prevent clickjacking
        X-Frame-Options \"SAMEORIGIN\"
        # Disable MIME type sniffing
        X-Content-Type-Options \"nosniff\"
    }

    # Handle large file uploads - CRITICAL for Nextcloud
    request_body {
        max_size 1GB
    }

    # Special handling for Nextcloud uploads
    @uploads {
        path /remote.php/dav/files/*
        path /remote.php/webdav/*
        path /public.php/dav/files/*
        path /apps/files/*
    }

    # Handle uploads with specific configuration
    reverse_proxy @uploads localhost:8080 {
        # Essential headers for Nextcloud uploads
        header_up X-Forwarded-Proto \"https\"
        header_up X-Forwarded-For {remote_host}
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-Host {host}
        
        # Critical: Preserve Content-Length for uploads
        header_up Content-Length {http.request.header.Content-Length}
        
        # Handle chunked uploads
        flush_interval -1
        
        # Extended timeouts for large uploads
        transport http {
            read_timeout 3600s
            write_timeout 3600s
            dial_timeout 30s
            response_header_timeout 30s
            expect_continue_timeout 10s
        }
    }

    # Handle all other requests
    reverse_proxy localhost:8080 {
        # Standard headers
        header_up X-Forwarded-Proto \"https\"
        header_up X-Forwarded-For {remote_host}
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-Host {host}
        
        # Standard timeouts
        transport http {
            read_timeout 300s
            write_timeout 300s
        }
    }
}
CADDY_EOF

# Create new Caddyfile with the fixed configuration
awk -v domain=\"$DOMAIN\" -v config=\"\$(cat /tmp/nextcloud_fixed_config)\" '
BEGIN { in_block = 0; brace_count = 0 }
\$0 ~ domain \" {\" { 
    in_block = 1; 
    brace_count = 1;
    print config;
    next;
}
in_block && /^}/ { 
    brace_count--; 
    if (brace_count == 0) { 
        in_block = 0; 
    }
    next;
}
in_block && /{/ { brace_count++; next; }
in_block { next; }
!in_block { print }
' /etc/caddy/Caddyfile > /tmp/new_caddyfile

# Replace the original file
mv /tmp/new_caddyfile /etc/caddy/Caddyfile
rm /tmp/nextcloud_fixed_config
"

# Validate the new configuration
echo -e "${YELLOW}🔍 Validating new Caddy configuration...${NC}"
if sudo caddy validate --config /etc/caddy/Caddyfile; then
    echo -e "${GREEN}✅ Configuration is valid${NC}"
else
    echo -e "${RED}❌ Configuration validation failed${NC}"
    echo -e "${YELLOW}🔄 Restoring backup...${NC}"
    LATEST_BACKUP=$(sudo ls -t /etc/caddy/Caddyfile.backup.* | head -1)
    sudo cp "$LATEST_BACKUP" /etc/caddy/Caddyfile
    exit 1
fi

# Restart Caddy
echo -e "${YELLOW}🔄 Restarting Caddy...${NC}"
if sudo systemctl restart caddy; then
    echo -e "${GREEN}✅ Caddy restarted successfully${NC}"
else
    echo -e "${RED}❌ Caddy restart failed${NC}"
    echo -e "${YELLOW}🔄 Restoring backup...${NC}"
    LATEST_BACKUP=$(sudo ls -t /etc/caddy/Caddyfile.backup.* | head -1)
    sudo cp "$LATEST_BACKUP" /etc/caddy/Caddyfile
    sudo systemctl restart caddy
    exit 1
fi

# Test the configuration
echo -e "${YELLOW}🔍 Testing Nextcloud connectivity...${NC}"
sleep 3

if curl -s -I https://$DOMAIN | grep -q "200 OK\|302 Found"; then
    echo -e "${GREEN}✅ Nextcloud is accessible via HTTPS${NC}"
else
    echo -e "${YELLOW}⚠️  Nextcloud may not be fully ready yet${NC}"
    echo -e "${BLUE}💡 Try accessing https://$DOMAIN in your browser${NC}"
fi

echo ""
echo -e "${GREEN}✅ Caddy upload fix completed!${NC}"
echo ""
echo -e "${BLUE}📋 What was fixed:${NC}"
echo "- Added special handling for Nextcloud upload paths"
echo "- Preserved Content-Length headers for uploads"
echo "- Configured chunked upload support"
echo "- Extended timeouts for large file uploads"
echo "- Added proper headers for WebDAV operations"
echo ""
echo -e "${YELLOW}💡 Test file uploads:${NC}"
echo "1. Access your Nextcloud web interface"
echo "2. Try uploading a file"
echo "3. The Content-Length error should be resolved"
echo ""
echo -e "${BLUE}🔧 If issues persist:${NC}"
echo "- Check Caddy logs: sudo journalctl -u caddy -f"
echo "- Check Nextcloud logs in the web interface"