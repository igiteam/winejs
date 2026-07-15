#!/bin/bash
# ============================================
# OpenSpy Core v2 - WineJS Installer
# Adds Game Server Browser & Statistics to WineJS Platform
# ============================================
# App: OpenSpy
# Category: Gaming
# Features: Game Server Browser, Player Statistics, Match History, Server Query API
# ============================================
#
# Domain Structure:
# =================
# ofpigi.com (Main website - HTML/landing page)
# ├── Shows all OFP servers (from OpenSpy API)
# ├── Player leaderboards
# └── Server browser with real-time data
#     ↓
# wine.ofpigi.com (WineJS platform)
#     ├── /pufferpanel (Manage game servers - CS:GO, Minecraft)
#     ├── /openspy (GameSpy API replacement - OFP, BF, CoD)
#     └── /mumble (Voice chat)
#

# How it works:
# =============
# 1. PufferPanel manages game servers (CS:GO, Minecraft, etc.)
# 2. PufferPanel reports server status to OpenSpy (via reportingIP config)
# 3. OpenSpy API aggregates all game server data
# 4. Main website (ofpigi.com) calls OpenSpy API to display:
#    - Active servers
#    - Player counts
#    - Map names
#    - Connect buttons
# ============================================

# OpenSpy Compatibility for Your Games
# =====================================
# ✅ OpenMoHAA (Medal of Honor: Allied Assault)
#     Listed in the official OpenSpy supported games as "Playable"
#     OpenMoHAA client should work with OpenSpy's master server
#
# ✅ Dark Messiah of Might & Magic
#     Uses GameSpy multiplayer backend
#     Should be compatible with OpenSpy's server browser
#
# ✅ OpenJKDF2 (Jedi Knight: Dark Forces II)
#     Open source engine for a GameSpy-era game
#     Community patches often include OpenSpy support

# How It Works
# ============
# OpenSpy is designed to be a drop-in replacement for GameSpy. Any game that originally used GameSpy for:
#     - Server browsing
#     - Master server queries
#     - Player presence
#     - Matchmaking
# ...can work with OpenSpy, either natively or with simple DNS redirects.

# For Your Operation Flashpoint Project
# =====================================
# If you're reviving multiple classic games under ofpigi.com,
# OpenSpy can be the central server browser for all of them. 
# The same OpenSpy instance would handle:
#
# Game                      | OpenSpy Status
# --------------------------|-----------------
# Operation Flashpoint      | Full support
# OpenMoHAA                 | Playable
# Dark Messiah              | Should work
# OpenJKDF2                 | Community support available
#
# Your website at ofpigi.com would query wine.ofpigi.com/openspy/api/servers 
# and display server lists for ALL these games from one API.

APP_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/openspy-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🎮 Installing WineJS OpenSpy Core v2..."

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

# ============= ASK FOR OPENSPY CONFIGURATION =============
echo ""
info "📝 OpenSpy Configuration"
echo "================================"

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=7300
MAX_RETRIES=50
APP_PORT=""

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

# Find available port for OpenSpy web interface
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for OpenSpy"
fi

log "Using port: OpenSpy=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="openspy"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/openspy"
CONFIG_DIR="/opt/winejs/config/openspy"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{redis,rabbitmq,mongo}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/openspy"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
# FIXES APPLIED:
# 1. Removed volume mount from openspy-core (let container use its internal defaults)
# 2. Added healthcheck for Redis to ensure it's ready before web starts
# 3. Changed REDIS_CONNECTION format to include host:port
# 4. Added container_name consistency with service names for DNS resolution
# 5. Added network aliases for reliable service discovery
# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Redis cache - GameSpy services use Redis for session data
  redis:
    image: redis:7-alpine
    container_name: winejs-openspy-redis
    restart: unless-stopped
    command: redis-server --appendonly yes --bind 0.0.0.0
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  # RabbitMQ message broker - Handles async communication between services
  rabbitmq:
    image: rabbitmq:3-management-alpine
    container_name: winejs-openspy-rabbitmq
    restart: unless-stopped
    environment:
      RABBITMQ_DEFAULT_USER: openspy
      RABBITMQ_DEFAULT_PASS: openspy
    volumes:
      - ${DATA_DIR}/rabbitmq:/var/lib/rabbitmq
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  # MongoDB - Stores player stats, match history, and user data
  mongo:
    image: mongo:6
    container_name: winejs-openspy-mongo
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: openspy
      MONGO_INITDB_ROOT_PASSWORD: openspy
    volumes:
      - ${DATA_DIR}/mongo:/data/db
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.runCommand('ping').ok", "--quiet"]
      interval: 5s
      timeout: 3s
      retries: 5

  # OpenSpy Core Services - The actual GameSpy protocol servers
  openspy-core:
    image: chcniz/openspy-core:latest
    container_name: winejs-openspy-core
    restart: unless-stopped
    depends_on:
      redis:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    environment:
      REDIS_HOST: winejs-openspy-redis
      REDIS_PORT: 6379
      RABBITMQ_HOST: winejs-openspy-rabbitmq
      RABBITMQ_PORT: 5672
      RABBITMQ_USER: openspy
      RABBITMQ_PASS: openspy
    ports:
      - "28900:28900"
      - "28910:28910"
      - "29900:29900"
      - "29901:29901"
      - "29920:29920"
      - "6667:6667"
    networks:
      - winejs-net

  # Web Frontend - REST API for websites to query server data
  openspy-web:
    image: chcniz/openspy-web-backend:latest
    container_name: winejs-openspy-web
    restart: unless-stopped
    depends_on:
      redis:
        condition: service_healthy
      mongo:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - ASPNETCORE_URLS=http://0.0.0.0:8080
      # FIXED: Use correct container names for all connections
      - CONNECTIONSTRINGS__REDISCACHE=winejs-openspy-redis:6379,allowAdmin=true
      - CONNECTIONSTRINGS__SNAPSHOTDB=mongodb://openspy:openspy@winejs-openspy-mongo:27017/gamestats
      - CONNECTIONSTRINGS__RMQCONNECTION=amqp://openspy:openspy@winejs-openspy-rabbitmq:5672/
      # MySQL connections (disabled - not used)
      - CONNECTIONSTRINGS__GAMEMASTERDB=
      - CONNECTIONSTRINGS__GAMETRACKERDB=
      - CONNECTIONSTRINGS__KEYMASTERDB=
      - CONNECTIONSTRINGS__PEERCHATDB=
    ports:
      - "127.0.0.1:${APP_PORT}:8080"
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
    name: winejs-net
DOCKER_EOF

# ============= CREATE CONFIG.JSON (CRITICAL FOR APP REGISTRATION) =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "OpenSpy Gaming Platform",
    "version": "v2",
    "description": "Game server browser, player statistics, and match history platform - Core v2",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/openspy.png",
    "category": "Gaming",
    "features": [
        "🎮 Game Server Browser (Query & Reporting)",
        "📊 Player Statistics Tracking (GStats)",
        "🏆 Match History & Rankings",
        "🔍 Server Discovery",
        "👥 Buddy Lists & Messaging (GP)",
        "📈 Real-time Stats",
        "🌍 Global Leaderboards",
        "💬 Peerchat (Game Lobby Chat)",
        "🔐 User Authentication",
        "📱 Mobile-responsive Interface",
        "🔄 Auto-updating Server List"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading OpenSpy icon..."
curl -L "$APP_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-openspy << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}

case "\$1" in
    status)
        docker ps | grep openspy
        ;;
    logs)
        docker logs winejs-openspy-core --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/openspy && docker-compose restart
        ;;
    services)
        echo "🔧 OpenSpy Core Services:"
        echo "  • Server Browsing (V1): port 28900 - Legacy GameSpy clients"
        echo "  • Server Browsing (V2): port 28910 - Modern protocol"
        echo "  • GameSpy Presence: port 29900 - Buddy lists & messaging"
        echo "  • Search: port 29901 - Account lookups"
        echo "  • GStats: port 29920 - Player stats & leaderboards"
        echo "  • Peerchat: port 6667 - Game lobby chat"
        echo ""
        echo "🌐 Web API: http://localhost:${APP_PORT}"
        ;;
    servers)
        echo "🌐 Game Server Browser: https://\${DOMAIN_NAME}/openspy/"
        echo ""
        echo "Supported Games:"
        echo "  • Operation Flashpoint (Full support)"
        echo "  • Battlefield 1942 / 2 / 2142"
        echo "  • Call of Duty series"
        echo "  • Medal of Honor: Allied Assault (OpenMoHAA)"
        echo "  • Dark Messiah of Might & Magic"
        echo "  • Jedi Knight: Dark Forces II (OpenJKDF2)"
        echo "  • UT2003 / UT2004"
        echo "  • And many more classic shooters"
        echo ""
        echo "API Endpoints:"
        echo "  • GET /api/servers - List all active game servers"
        echo "  • GET /api/servers/{game} - Filter by game"
        echo "  • GET /api/players - Online players"
        echo "  • GET /api/stats/{player} - Player statistics"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/openspy/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/openspy/"
        fi
        ;;
    *)
        echo "OpenSpy Core v2 Gaming Platform Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-openspy open        - Open OpenSpy interface"
        echo "  winejs-openspy status      - Check service status"
        echo "  winejs-openspy logs        - View core logs"
        echo "  winejs-openspy restart     - Restart services"
        echo "  winejs-openspy services    - Show service ports"
        echo "  winejs-openspy servers     - Show supported games & API endpoints"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-openspy

# ============= START CONTAINER =============
log "🚀 Starting OpenSpy containers..."

cd "$INSTANCE_DIR"

docker-compose down 2>/dev/null
docker-compose up -d

sleep 15

# Check if containers are running
if docker ps | grep -q "winejs-openspy-core"; then
    success "✅ OpenSpy containers started successfully"
else
    warn "⚠️ Core container may not have started. Check: docker logs winejs-openspy-core"
fi

# Check web container separately
if docker ps | grep -q "winejs-openspy-web"; then
    success "✅ Web backend is running"
else
    warn "⚠️ Web container may not have started. Check: docker logs winejs-openspy-web"
fi

# ============= UPDATE NGINX CONFIG =============
log "📝 Updating nginx configuration for OpenSpy..."
# The pattern for ALL installers (Mumble, PufferPanel, Forgejo, VSCode):
#   1. Find the HTTPS server block by locating "listen 443"
#   2. Count braces { and } to find the exact closing brace of that server block
#   3. Insert new location blocks BEFORE that closing brace
#   4. This guarantees routes are safely INSIDE the correct server block
# This method is proven to work (VSCode uses it) and never creates orphaned directives.
# DO NOT insert before "listen 443" - that breaks the config.
# DO NOT insert after random lines like "root" or "server_name" - that's fragile.
# The pattern from PufferPanel - proven to work with proper SPA support
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    # Check if OpenSpy routes already exist
    if ! grep -q "location /openspy" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        # Find the HTTPS server block (listen 443)
        HTTPS_START=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$HTTPS_START" ]; then
            # Find the closing brace of the HTTPS block by counting braces
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
                # Insert routes BEFORE the closing brace
                sed -i "${HTTPS_END}i\\
    # OpenSpy Core v2 - Game Server Browser API\\
    # This provides REST API endpoints for ofpigi.com to display game servers\\
    location /openspy {\\
        return 301 /openspy/;\\
    }\\
    \\
    location /openspy/ {\\
        proxy_pass http://127.0.0.1:${APP_PORT}/;\\
        proxy_set_header Host \$host;\\
        proxy_set_header X-Real-IP \$remote_addr;\\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\\
        proxy_set_header X-Forwarded-Proto \$scheme;\\
        proxy_http_version 1.1;\\
        proxy_set_header Upgrade \$http_upgrade;\\
        proxy_set_header Connection \"upgrade\";\\
        proxy_read_timeout 300s;\\
        proxy_send_timeout 300s;\\
        proxy_redirect off;\\
    }\\
" /etc/nginx/sites-available/winejs
                
                if nginx -t; then
                    systemctl reload nginx
                    log "✅ Nginx updated with OpenSpy routes"
                else
                    warn "Nginx test failed, restoring backup"
                    cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                    nginx -t && systemctl reload nginx
                fi
            else
                warn "Could not find HTTPS block closing brace"
            fi
        else
            warn "Could not find HTTPS server block (listen 443)"
        fi
    else
        log "OpenSpy routes already exist"
    fi
fi

# ============= RESTART TRANSLATOR TO REGISTER APP =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_openspy.sh" << 'UNINSTALL_EOF'
#!/bin/bash
# WineJS OpenSpy Uninstaller

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

log "🧹 Uninstalling OpenSpy Gaming Platform..."

# ============= STOP AND REMOVE DOCKER CONTAINERS =============
log "Stopping Docker containers..."

for container in winejs-openspy-core winejs-openspy-web winejs-openspy-redis winejs-openspy-rabbitmq winejs-openspy-mongo; do
    if docker ps -a 2>/dev/null | grep -q "$container"; then
        log "Stopping $container..."
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
    fi
done

# ============= REMOVE APP DIRECTORIES =============
log "Removing app directories..."

APP_NAME="openspy"
APP_DIR="/opt/winejs/apps/${APP_NAME}"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/${APP_NAME}"
OPENSPY_DATA="/opt/winejs/data/openspy"
ICON_FILE="/opt/winejs/translator/public/icons/${APP_NAME}.png"

[ -d "$INSTANCE_DIR" ] && rm -rf "$INSTANCE_DIR" && log "✅ Instance directory removed"
[ -d "$APP_DIR" ] && rm -rf "$APP_DIR" && log "✅ App directory removed"
[ -d "$OPENSPY_DATA" ] && rm -rf "$OPENSPY_DATA" && log "✅ OpenSpy data removed"
[ -f "$ICON_FILE" ] && rm -f "$ICON_FILE" && log "✅ Icon removed"

# ============= REMOVE NGINX CONFIGURATION =============
log "Removing nginx configuration..."

NGINX_SITE="/etc/nginx/sites-available/winejs"

if [ -f "$NGINX_SITE" ]; then
    if grep -q "openspy" "$NGINX_SITE"; then
        cp "$NGINX_SITE" "${NGINX_SITE}.backup.$(date +%Y%m%d_%H%M%S)"
        
        if command -v perl &> /dev/null; then
            perl -i -0777 -pe 's/^[[:space:]]*# OpenSpy Core v2.*?location \/openspy\/\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
        else
            sed -i '/# OpenSpy Core v2/,/location \/openspy\/ {/d' "$NGINX_SITE"
            sed -i '/location \/openspy {/,/^    }/d' "$NGINX_SITE"
        fi
        
        sed -i '/openspy/d' "$NGINX_SITE"
        
        if nginx -t 2>/dev/null; then
            systemctl reload nginx
            log "✅ Nginx configuration updated"
        else
            warn "Nginx test failed, manual intervention may be needed"
        fi
    fi
fi

# ============= REMOVE HELPER SCRIPT =============
[ -f "/usr/local/bin/winejs-openspy" ] && rm -f "/usr/local/bin/winejs-openspy" && log "✅ Helper script removed"

# ============= RELOAD WINEJS TRANSLATOR =============
log "Reloading WineJS translator..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           OPENSPY UNINSTALLED SUCCESSFULLY!                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
log "✅ OpenSpy Gaming Platform has been completely removed"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_openspy.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              OPENSPY CORE V2 INSTALLED ON WINEJS!              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ OpenSpy Core v2 Gaming Platform installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/openspy/"
echo ""
info "🎮 Features:"
info "   • Game Server Browser (V1 & V2 protocols)"
info "   • Player Statistics (GStats)"
info "   • Match History"
info "   • Buddy Lists & Messaging"
info "   • Peerchat (Game Lobby Chat)"
info "   • Global Leaderboards"
echo ""
info "🎯 Supported Games (Your Project):"
info "   • Operation Flashpoint - Full support"
info "   • OpenMoHAA (Medal of Honor) - Playable"
info "   • Dark Messiah of Might & Magic - Compatible"
info "   • OpenJKDF2 (Jedi Knight) - Community supported"
info "   • Battlefield 1942 / 2 / 2142"
info "   • Call of Duty series"
info "   • UT2003 / UT2004"
echo ""
info "🔧 Quick Commands:"
info "   • winejs-openspy open        # Open OpenSpy"
info "   • winejs-openspy status      # Check services"
info "   • winejs-openspy logs        # View core logs"
info "   • winejs-openspy services    # Show service ports"
info "   • winejs-openspy servers     # Show API endpoints"
echo ""
info "🔌 Service Ports:"
info "   • Server Browsing V1: 28900 - Legacy GameSpy clients"
info "   • Server Browsing V2: 28910 - Modern protocol"
info "   • GameSpy Presence: 29900 - Buddy lists"
info "   • Search: 29901 - Account lookups"
info "   • GStats: 29920 - Player stats"
info "   • Peerchat: 6667 - Lobby chat"
echo ""
info "📁 Data Directory: $DATA_DIR"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_openspy.sh"
echo ""
success "✨ OpenSpy Core v2 is ready!"
echo ""
info "📌 API Endpoints for ofpigi.com:"
echo "   • GET https://$DOMAIN_NAME/openspy/api/servers"
echo "   • GET https://$DOMAIN_NAME/openspy/api/servers/{game}"
echo "   • GET https://$DOMAIN_NAME/openspy/api/players"
echo ""
info "📌 For PufferPanel integration, add to PufferPanel config:"
echo '   {'
echo '     "panel": {'
echo '       "settings": {'
echo '         "masterUrl": "https://'$DOMAIN_NAME'/pufferpanel",'
echo '         "reportingIP": "'$DOMAIN_NAME'",'
echo '         "reportingPort": 27015'
echo '       }'
echo '     }'
echo '   }'
echo ""
echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"