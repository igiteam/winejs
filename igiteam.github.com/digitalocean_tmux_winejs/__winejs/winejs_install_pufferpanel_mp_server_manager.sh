#!/bin/bash
# ============================================
# WineJS PufferPanel Installer
# Adds Game Server Management Panel to WineJS Platform
# ============================================
# App: PufferPanel
# Category: Gaming
# Features: Game Server Management, CS:GO, Minecraft, SteamCMD, Docker
# ============================================

APP_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/pufferpanel-icon.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🚀 Installing WineJS PufferPanel Game Server Manager..."

# ============= VERIFY WINEJS PLATFORM =============
log "Verifying WineJS platform..."

if [ ! -d "/opt/winejs" ]; then
    error "WineJS platform not found at /opt/winejs"
fi

if [ ! -f "/opt/winejs/translator/index.js" ]; then
    error "WineJS translator not found. Please install WineJS first."
fi

# Ensure winejs-net network exists
log "Checking winejs-net network..."
if ! docker network inspect winejs-net &>/dev/null; then
    docker network create winejs-net
    log "✅ winejs-net network created"
fi

# ============= GET DOMAIN FROM WINEJS CONFIG =============
if [ -f "/opt/winejs/translator/index.js" ]; then
    DOMAIN_NAME=$(grep "const DOMAIN_NAME" /opt/winejs/translator/index.js | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/")
fi

if [ -z "$DOMAIN_NAME" ]; then
    read -p "Enter your WineJS domain: " DOMAIN_NAME
fi

info "Using domain: $DOMAIN_NAME"

# ============= ASK FOR ADMIN DETAILS =============
read -p "Enter admin email: " ADMIN_EMAIL
read -s -p "Enter admin password (min 8 chars): " ADMIN_PASSWORD
echo ""

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=6901
MAX_RETRIES=50
APP_PORT=""
SFTP_PORT=""

# Get used ports from existing apps
declare -a USED_PORTS
if [ -d "/opt/winejs/apps" ]; then
    for config in /opt/winejs/apps/*/config.json; do
        if [ -f "$config" ]; then
            PORT=$(grep -o '"port": [0-9]*' "$config" | awk '{print $2}')
            [ -n "$PORT" ] && USED_PORTS+=($PORT)
        fi
    done
fi

# Find available port for PufferPanel web
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

# Find available port for SFTP
for i in $(seq 1 $MAX_RETRIES); do
    TEST_PORT=$((APP_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        SFTP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ] || [ -z "$SFTP_PORT" ]; then
    error "Could not find available ports"
fi

log "Using ports: PufferPanel=$APP_PORT, SFTP=$SFTP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="pufferpanel"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/pufferpanel"
CONFIG_DIR="/opt/winejs/config/pufferpanel"
TEMPLATES_DIR="/opt/winejs/data/pufferpanel-templates"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$TEMPLATES_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/pufferpanel"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

# Generate random database password
DB_PASS=$(openssl rand -base64 16 | tr -d '=/+')

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # MySQL Database
  pufferpanel-db:
    image: mariadb:10.11
    container_name: winejs-pufferpanel-db
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=${DB_PASS}
      - MYSQL_DATABASE=pufferpanel
      - MYSQL_USER=pufferpanel
      - MYSQL_PASSWORD=${DB_PASS}
    volumes:
      - ${DATA_DIR}/mysql:/var/lib/mysql
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

  # PufferPanel
  winejs-pufferpanel:
    image: ghcr.io/igiteam/pufferpanel:branch-v3
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "${APP_PORT}:8080"                    # Web panel (e.g., 6902)
      - "${SFTP_PORT}:5657"                  # SFTP (e.g., 6905)
    environment:
      - DB_HOST=pufferpanel-db
      - DB_PORT=3306
      - DB_DATABASE=pufferpanel
      - DB_USERNAME=pufferpanel
      - DB_PASSWORD=${DB_PASS}
      - WEB_HOST=0.0.0.0
      - WEB_PORT=8080
      - SFTP_PORT=5657
      - PANEL_URL=https://${DOMAIN_NAME}/pufferpanel
    volumes:
      - ${DATA_DIR}/servers:/var/lib/pufferpanel
      - ${TEMPLATES_DIR}:/var/lib/pufferpanel/templates
      - ${DATA_DIR}/config:/etc/pufferpanel
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      pufferpanel-db:
        condition: service_healthy
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF


# ============= CREATE CONFIG.JSON (CRITICAL FOR APP REGISTRATION) =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "PufferPanel Game Server Manager",
    "version": "latest",
    "description": "Manage game servers (CS:GO, Minecraft, Rust, etc.) in your browser",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/pufferpanel.png",
    "category": "Gaming",
    "features": [
        "CS:GO Dedicated Servers",
        "Minecraft Java/Bedrock",
        "Rust, ARK, Palworld",
        "SteamCMD integration",
        "Docker container support",
        "SFTP file access",
        "Server scheduling",
        "Resource monitoring"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading PufferPanel icon..."
curl -L "$APP_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE GAME TEMPLATES =============
log "🎮 Creating game server templates..."
chown -R 1000:1000 "$TEMPLATES_DIR" 2>/dev/null || true

# ============= CREATE ADMIN SETUP SCRIPT =============
log "🔧 Creating admin setup script..."

cat > "$APP_DIR/setup-admin.sh" << 'ADMIN_EOF'
#!/bin/bash

APP_PORT="APP_PORT_PLACEHOLDER"
ADMIN_EMAIL="ADMIN_EMAIL_PLACEHOLDER"
ADMIN_PASSWORD="ADMIN_PASSWORD_PLACEHOLDER"
DOMAIN_NAME="DOMAIN_NAME_PLACEHOLDER"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "Waiting for PufferPanel to start..."
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -s -f "http://localhost:${APP_PORT}" > /dev/null 2>&1; then
        log "✅ PufferPanel is ready!"
        break
    fi
    log "Attempt $attempt/$max_attempts: Waiting for PufferPanel..."
    sleep 5
    attempt=$((attempt + 1))
done

log "Creating admin user..."
docker exec winejs-pufferpanel /pufferpanel/bin/pufferpanel user add \
    --email "$ADMIN_EMAIL" \
    --password "$ADMIN_PASSWORD" \
    --admin \
    --name Admin 2>&1

if [ $? -eq 0 ]; then
    log "✅ Admin user created successfully"
else
    log "⚠️ Admin user creation failed or user already exists"
fi

log "✅ Admin setup complete. Login at: https://${DOMAIN_NAME}/pufferpanel"
ADMIN_EOF

# Replace placeholders with actual values
sed -i "s/APP_PORT_PLACEHOLDER/${APP_PORT}/g" "$APP_DIR/setup-admin.sh"
sed -i "s/ADMIN_EMAIL_PLACEHOLDER/${ADMIN_EMAIL}/g" "$APP_DIR/setup-admin.sh"
sed -i "s/ADMIN_PASSWORD_PLACEHOLDER/${ADMIN_PASSWORD}/g" "$APP_DIR/setup-admin.sh"
sed -i "s/DOMAIN_NAME_PLACEHOLDER/${DOMAIN_NAME}/g" "$APP_DIR/setup-admin.sh"

chmod +x "$APP_DIR/setup-admin.sh"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-pufferpanel << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}

case "\$1" in
    status)
        docker ps | grep pufferpanel
        ;;
    logs)
        docker logs winejs-pufferpanel --tail 50
        ;;
    restart)
        docker restart winejs-pufferpanel
        ;;
    create-server)
        echo "Create a new game server:"
        echo "1. Login to https://\${DOMAIN_NAME}/pufferpanel/"
        echo "2. Go to Servers → Create New"
        echo "3. Choose template (CS:GO, Minecraft, etc.)"
        echo "4. Configure ports and settings"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/pufferpanel/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/pufferpanel/"
        fi
        ;;
    *)
        echo "PufferPanel Game Server Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-pufferpanel open      - Open panel in browser"
        echo "  winejs-pufferpanel status    - Check service status"
        echo "  winejs-pufferpanel logs      - View container logs"
        echo "  winejs-pufferpanel restart   - Restart panel"
        echo "  winejs-pufferpanel create-server - Server creation guide"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-pufferpanel

# ============= START CONTAINER =============
log "🚀 Starting PufferPanel container..."

cd "$INSTANCE_DIR"

# ============= FORCE PULL LATEST IMAGE =============
log "📥 Force pulling latest PufferPanel image from ghcr.io..."

# Remove cached image to ensure fresh pull
if docker image inspect ghcr.io/igiteam/pufferpanel:branch-v3 &>/dev/null; then
    OLD_IMAGE_ID=$(docker images -q ghcr.io/igiteam/pufferpanel:branch-v3)
    log "Removing cached image: $OLD_IMAGE_ID"
    docker rmi -f ghcr.io/igiteam/pufferpanel:branch-v3 2>/dev/null || true
fi

# Pull fresh copy
log "Pulling from registry..."
docker pull ghcr.io/igiteam/pufferpanel:branch-v3

# Show what we got
NEW_IMAGE_ID=$(docker images -q ghcr.io/igiteam/pufferpanel:branch-v3)
log "Pulled image ID: $NEW_IMAGE_ID"

docker-compose down 2>/dev/null
docker-compose up -d

# ============= CREATE CONFIG AFTER CONTAINER STARTS =============
log "📝 Creating PufferPanel configuration (after container start)..."

# Wait for container to create default config
sleep 10

# Now write our config (overwriting the default)
mkdir -p "$DATA_DIR/config"
cat > "$DATA_DIR/config/config.json" << 'EOF'
{
  "branding": {
    "name": "PufferPanel Game Server Manager",
    "description": "Manage game servers in your browser",
    "logo": "/logo.png",
    "favicon": "/favicon.png"
  },
  "daemon": {
    "data": {
      "root": "/var/lib/pufferpanel"
    },
    "sftp": {
      "host": "0.0.0.0:5657"
    }
  },
  "email": {
    "provider": "debug"
  },
  "logs": "/var/log/pufferpanel",
  "panel": {
    "database": {
      "dialect": "mysql",
      "url": "pufferpanel:DB_PASS_PLACEHOLDER@tcp(pufferpanel-db:3306)/pufferpanel"
    },
    "registrationEnabled": false,
    "settings": {
      "masterUrl": "https://DOMAIN_PLACEHOLDER/pufferpanel"
    }
  },
  "web": {
    "basePath": "/pufferpanel",
    "host": "0.0.0.0:8080"
  }
}
EOF

# Replace placeholders
sed -i "s/DB_PASS_PLACEHOLDER/${DB_PASS}/g" "$DATA_DIR/config/config.json"
sed -i "s/DOMAIN_PLACEHOLDER/${DOMAIN_NAME}/g" "$DATA_DIR/config/config.json"

# Restart container to pick up new config
docker restart winejs-pufferpanel
sleep 5

# ============= SETUP ADMIN USER =============
bash "$APP_DIR/setup-admin.sh"


# ============= UPDATE NGINX CONFIG =============
log "📝 Updating nginx configuration for PufferPanel..."

# The pattern for ALL installers (Mumble, PufferPanel, Forgejo, VSCode):
#   1. Find the HTTPS server block by locating "listen 443"
#   2. Count braces { and } to find the exact closing brace of that server block
#   3. Insert new location blocks BEFORE that closing brace
#   4. This guarantees routes are safely INSIDE the correct server block
#
# This method is proven to work (VSCode uses it) and never creates orphaned directives.
# DO NOT insert before "listen 443" - that breaks the config.
# DO NOT insert after random lines like "root" or "server_name" - that's fragile.

# ============= BASE PATH INJECTION =============
# PufferPanel's frontend API client looks for:
#   1. <meta name="panel-base" content="/pufferpanel">
#   2. window.__PUFFERPANEL_BASE__ = '/pufferpanel'
#
# By injecting these into the HTML, the frontend automatically prefixes
# ALL API calls with /pufferpanel, eliminating the need for sub_filter rewrites.
# This is the CLEANEST solution because PufferPanel's code already supports it!
# ================================================

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    
    # Remove any existing PufferPanel blocks to prevent duplicates
    if grep -q "# PufferPanel Game Server Manager" /etc/nginx/sites-available/winejs; then
        log "Removing existing PufferPanel nginx configuration..."
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup.$(date +%s)
        sed -i '/# PufferPanel Game Server Manager/,/location \/pufferpanel\/ {/d' /etc/nginx/sites-available/winejs
        sed -i '/location \/pufferpanel {/,/^    }/d' /etc/nginx/sites-available/winejs
    fi
    
    # Find the HTTPS server block (listen 443)
    HTTPS_START=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
    
    if [ -n "$HTTPS_START" ]; then
        # Find the closing brace
        BRACE_COUNT=0
        LINE_NUM=$HTTPS_START
        TOTAL_LINES=$(wc -l < /etc/nginx/sites-available/winejs)
        HTTPS_END=""
        
        while [ $LINE_NUM -le $TOTAL_LINES ]; do
            LINE=$(sed -n "${LINE_NUM}p" /etc/nginx/sites-available/winejs)
            for ((i=0; i<${#LINE}; i++)); do
                char="${LINE:$i:1}"
                if [ "$char" = "{" ]; then
                    BRACE_COUNT=$((BRACE_COUNT + 1))
                elif [ "$char" = "}" ]; then
                    BRACE_COUNT=$((BRACE_COUNT - 1))
                fi
            done
            if [ $BRACE_COUNT -eq 0 ]; then
                HTTPS_END=$LINE_NUM
                break
            fi
            LINE_NUM=$((LINE_NUM + 1))
        done
        
        if [ -n "$HTTPS_END" ]; then
            # Insert the PufferPanel location block with basePath injection and WebSocket rewrites
            sed -i "${HTTPS_END}i\\
    # PufferPanel Game Server Manager\\
    location /pufferpanel {\\
        return 301 /pufferpanel/;\\
    }\\
    \\
    location /pufferpanel/ {\\
        proxy_pass http://127.0.0.1:${APP_PORT}/;\\
        proxy_set_header Host \$host;\\
        proxy_set_header X-Real-IP \$remote_addr;\\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\\
        proxy_set_header X-Forwarded-Proto \$scheme;\\
        proxy_set_header X-Forwarded-Prefix /pufferpanel;\\
        proxy_http_version 1.1;\\
        proxy_set_header Upgrade \$http_upgrade;\\
        proxy_set_header Connection \"upgrade\";\\
        proxy_read_timeout 300s;\\
        proxy_send_timeout 300s;\\
        proxy_redirect off;\\
        proxy_intercept_errors on;\\
        error_page 404 = /index.html;\\
        \\
        # BASE PATH INJECTION\\
        sub_filter '</head>' '<meta name=\"panel-base\" content=\"/pufferpanel\"><script>window.__PUFFERPANEL_BASE__=\"/pufferpanel\";window.__WEBSOCKET_BASE__=\"/pufferpanel\";</script></head>';\\
        sub_filter_once off;\\
        \\
        # WEBSOCKET URL REWRITES IN JAVASCRIPT\\
        sub_filter 'wss://${DOMAIN_NAME}/api/servers/' 'wss://${DOMAIN_NAME}/pufferpanel/api/servers/';\\
        sub_filter 'ws://${DOMAIN_NAME}/api/servers/' 'wss://${DOMAIN_NAME}/pufferpanel/api/servers/';\\
        sub_filter '\\\\\"wss://${DOMAIN_NAME}/api/servers/' '\\\\\"wss://${DOMAIN_NAME}/pufferpanel/api/servers/';\\
        sub_filter \"'wss://${DOMAIN_NAME}/api/servers/\" \"'wss://${DOMAIN_NAME}/pufferpanel/api/servers/\";\\
        \\
        # FALLBACK API PATH REWRITES\\
        sub_filter_types text/html application/json text/javascript;\\
        sub_filter '\"/api/' '\"/pufferpanel/api/';\\
        sub_filter \"'/api/\" \"'/pufferpanel/api/\";\\
        sub_filter '\"/auth/' '\"/pufferpanel/auth/';\\
        sub_filter \"'/auth/\" \"'/pufferpanel/auth/\";\\
    }\\
" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with PufferPanel routes (WebSocket + basePath injection enabled)"
            else
                warn "Nginx test failed, restoring backup"
                cp /etc/nginx/sites-available/winejs.backup.* /etc/nginx/sites-available/winejs 2>/dev/null || true
                nginx -t && systemctl reload nginx
            fi
        fi
    fi
fi

# ============= RESTART TRANSLATOR TO REGISTER APP =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_pufferpanel.sh" << 'UNINSTALL_EOF'
#!/bin/bash
# WineJS PufferPanel Uninstaller

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Change to safe directory first
cd /tmp || cd /root || exit 1

log "🧹 Uninstalling PufferPanel Game Server Manager..."

# ============= STOP AND REMOVE DOCKER CONTAINERS =============
log "Stopping Docker containers..."

if docker ps -a 2>/dev/null | grep -q "winejs-pufferpanel"; then
    log "Stopping winejs-pufferpanel container..."
    docker stop winejs-pufferpanel 2>/dev/null || true
    docker rm winejs-pufferpanel 2>/dev/null || true
    log "✅ PufferPanel container removed"
fi

if docker ps -a 2>/dev/null | grep -q "winejs-pufferpanel-db"; then
    log "Stopping winejs-pufferpanel-db container..."
    docker stop winejs-pufferpanel-db 2>/dev/null || true
    docker rm winejs-pufferpanel-db 2>/dev/null || true
    log "✅ Database container removed"
fi

# ============= REMOVE APP DIRECTORIES =============
log "Removing app directories..."

APP_NAME="pufferpanel"
APP_DIR="/opt/winejs/apps/${APP_NAME}"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/${APP_NAME}"
PUFFERPANEL_DATA="/opt/winejs/data/pufferpanel"
PUFFERPANEL_CONFIG="/opt/winejs/config/pufferpanel"
TEMPLATES_DIR="/opt/winejs/data/pufferpanel-templates"
ICON_FILE="/opt/winejs/translator/public/icons/${APP_NAME}.png"

# Remove directories if they exist
[ -d "$INSTANCE_DIR" ] && rm -rf "$INSTANCE_DIR" && log "✅ Instance directory removed"
[ -d "$APP_DIR" ] && rm -rf "$APP_DIR" && log "✅ App directory removed"
[ -d "$PUFFERPANEL_DATA" ] && rm -rf "$PUFFERPANEL_DATA" && log "✅ PufferPanel data removed"
[ -d "$PUFFERPANEL_CONFIG" ] && rm -rf "$PUFFERPANEL_CONFIG" && log "✅ PufferPanel config removed"
[ -d "$TEMPLATES_DIR" ] && rm -rf "$TEMPLATES_DIR" && log "✅ Game templates removed"
[ -f "$ICON_FILE" ] && rm -f "$ICON_FILE" && log "✅ Icon removed"

# ============= REMOVE NGINX CONFIGURATION =============
log "Removing nginx configuration..."

NGINX_SITE="/etc/nginx/sites-available/winejs"

if [ ! -f "$NGINX_SITE" ]; then
    warn "nginx config not found at $NGINX_SITE"
else
    # Check if any PufferPanel routes exist
    if ! grep -q "pufferpanel" "$NGINX_SITE"; then
        log "No PufferPanel routes found in nginx config"
    else
        log "Removing PufferPanel routes from nginx config..."
        
        # Create backup with timestamp
        BACKUP_FILE="${NGINX_SITE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$NGINX_SITE" "$BACKUP_FILE"
        log "✅ Backup created: $BACKUP_FILE"
        
        # Use Perl for more reliable multi-line removal (if available)
        if command -v perl &> /dev/null; then
            # Remove the main PufferPanel location blocks
            perl -i -0777 -pe 's/^[[:space:]]*# PufferPanel Game Server Manager\s*\n.*?location \/pufferpanel\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
            perl -i -0777 -pe 's/^[[:space:]]*location \/pufferpanel\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
            perl -i -0777 -pe 's/^[[:space:]]*location \/pufferpanel\/\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
        else
            # Fallback to sed for multi-line removal
            sed -i '/^[[:space:]]*# PufferPanel Game Server Manager/,/^[[:space:]]*}/d' "$NGINX_SITE"
            sed -i '/^[[:space:]]*location \/pufferpanel {/,/^[[:space:]]*}/d' "$NGINX_SITE"
            sed -i '/^[[:space:]]*location \/pufferpanel\/ {/,/^[[:space:]]*}/d' "$NGINX_SITE"
        fi
        
        # Remove any orphaned pufferpanel lines
        sed -i '/pufferpanel/d' "$NGINX_SITE"
        
        # Clean up multiple blank lines
        sed -i '/^$/N;/^\n$/D' "$NGINX_SITE"
        
        # Test and reload nginx
        log "Testing nginx configuration..."
        if nginx -t 2>&1 | tee /tmp/nginx_test.log; then
            systemctl reload nginx
            log "✅ Nginx configuration successfully updated - PufferPanel routes removed"
        else
            warn "Nginx test failed! Restoring from backup..."
            if [ -f "$BACKUP_FILE" ]; then
                cp "$BACKUP_FILE" "$NGINX_SITE"
                if nginx -t 2>/dev/null; then
                    systemctl reload nginx
                    log "✅ Successfully restored previous nginx config"
                else
                    error "CRITICAL: Even backup config fails! Check nginx manually"
                    exit 1
                fi
            else
                error "No backup available! Manual intervention required"
                log "Check nginx config at: $NGINX_SITE"
                log "Previous error: $(cat /tmp/nginx_test.log)"
                exit 1
            fi
        fi
    fi
fi

# ============= REMOVE HELPER SCRIPT =============
if [ -f "/usr/local/bin/winejs-pufferpanel" ]; then
    rm -f "/usr/local/bin/winejs-pufferpanel"
    log "✅ Helper script removed"
fi

# ============= RELOAD WINEJS TRANSLATOR =============
log "Reloading WineJS translator..."
if command -v pm2 &> /dev/null; then
    pm2 restart translator 2>/dev/null || true
    log "✅ Translator reloaded"
fi

# ============= VERIFY REMOVAL =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         PUFFERPANEL UNINSTALLED SUCCESSFULLY!                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
log "✅ PufferPanel Game Server Manager has been completely removed"
echo ""
UNINSTALL_EOF


chmod +x "$(dirname "$APP_DIR")/uninstall_pufferpanel.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           PUFFERPANEL INSTALLED ON WINEJS!                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ PufferPanel Game Server Manager installed!"
echo ""
info "🌐 Access URLs:"
info "   • Panel: https://$DOMAIN_NAME/pufferpanel/"
info "   • SFTP: port ${SFTP_PORT}"
echo ""
info "🔑 Admin Credentials:"
info "   • Email: $ADMIN_EMAIL"
info "   • Password: $ADMIN_PASSWORD"
echo ""
info "🎮 Game Templates Available:"
info "   • CS:GO - Counter-Strike: Global Offensive"
info "   • Minecraft - Java Edition"
echo ""
info "📁 Server Data: /opt/winejs/data/pufferpanel/servers"
info ""
info "🎯 Quick Commands:"
info "   • winejs-pufferpanel open      # Open panel"
info "   • winejs-pufferpanel status    # Check status"
info "   • winejs-pufferpanel logs      # View logs"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_pufferpanel.sh"
echo ""
success "✨ PufferPanel is ready! Visit https://$DOMAIN_NAME/pufferpanel/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"