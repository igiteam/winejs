#!/bin/bash
# ============================================
# SearXNG Privacy Search Engine - WineJS Installer
# Adds Privacy-Respecting Metasearch Engine to WineJS Platform
# ============================================
# App: SearXNG
# Category: Productivity
# Features: Privacy-focused search, Meta-search engine, No tracking
# ============================================

SEARXNG_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/searxng_logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🔍 Installing WineJS SearXNG Privacy Search Engine..."

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

# ============= ASK FOR SEARXNG CONFIGURATION =============
echo ""
info "📝 SearXNG Configuration"
echo "================================"
read -p "Instance name [WineJS Search]: " INSTANCE_NAME
INSTANCE_NAME=${INSTANCE_NAME:-"WineJS Search"}

read -p "Admin email for SSL: " ADMIN_EMAIL

read -p "Enable safe search? (0=off, 1=moderate, 2=strict) [2]: " SAFE_SEARCH
SAFE_SEARCH=${SAFE_SEARCH:-2}

read -p "Enable image proxy? (true/false) [true]: " IMAGE_PROXY
IMAGE_PROXY=${IMAGE_PROXY:-true}

read -p "Enable rate limiting? (true/false) [true]: " LIMITER
LIMITER=${LIMITER:-true}

# Generate random secret key
SECRET_KEY=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | head -c 32 | xxd -p)

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=7100  # Start after Mumble's range (7000+)
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

# Find available port for SearXNG web interface
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for SearXNG"
fi

log "Using port: SearXNG=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="searxng"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/searxng"
CONFIG_DIR="/opt/winejs/config/searxng"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR"/{config,data} "$CONFIG_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/searxng"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE SEARXNG CONFIGURATION =============
log "📝 Creating SearXNG configuration..."

cat > "$DATA_DIR/config/settings.yml" << EOF
# SearXNG configuration - WineJS installer
use_default_settings: true

general:
  debug: false
  instance_name: "$INSTANCE_NAME"
  private_instances: false

search:
  safe_search: $SAFE_SEARCH
  autocomplete: 'duckduckgo'
  formats:
    - html
  default_lang: 'en'

server:
  secret_key: "$SECRET_KEY"
  limiter: $LIMITER
  image_proxy: $IMAGE_PROXY
  public_instance: false
  base_url: https://$DOMAIN_NAME/searxng

ui:
  default_locale: 'en'
  default_theme: 'simple'
  theme_args:
    simple_style: 'auto'

redis:
  url: redis://searxng-redis:6379/0

outgoing:
  request_timeout: 5.0
  max_request_timeout: 15.0
  useragent_suffix: "WineJS"
EOF

log "✅ Configuration created"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Redis cache for SearXNG
  searxng-redis:
    image: valkey/valkey:7.2.5-alpine
    container_name: winejs-searxng-redis
    restart: unless-stopped
    command: valkey-server --appendonly yes
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "valkey-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # SearXNG Search Engine
  winejs-searxng:
    image: docker.io/searxng/searxng:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:8080"
    volumes:
      - ${DATA_DIR}/config:/etc/searxng:ro
      - ${DATA_DIR}/data:/var/cache/searxng
    environment:
      - SEARXNG_SECRET_KEY=${SECRET_KEY}
      - SEARXNG_BASE_URL=https://${DOMAIN_NAME}/searxng
    depends_on:
      searxng-redis:
        condition: service_healthy
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE CONFIG.JSON (CRITICAL FOR APP REGISTRATION) =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "SearXNG Privacy Search",
    "version": "latest",
    "description": "Privacy-respecting metasearch engine - No tracking, no profiling",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/searxng.png",
    "category": "Productivity",
    "features": [
        "🔍 Privacy-focused metasearch engine",
        "🚫 No user tracking or profiling",
        "🌐 Searches multiple engines simultaneously",
        "⚡ Fast results with caching",
        "🎨 Customizable themes and UI",
        "🔒 HTTPS with automatic SSL",
        "🛡️ Safe search filtering",
        "🖼️ Image proxy for privacy",
        "📱 Responsive mobile design",
        "🔧 Self-hosted, full control"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading SearXNG icon..."
curl -L "$SEARXNG_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-searxng << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
SECRET_KEY="${SECRET_KEY}"

case "\$1" in
    status)
        docker ps | grep winejs-searxng
        ;;
    logs)
        docker logs winejs-searxng --tail 50
        ;;
    restart)
        docker restart winejs-searxng
        echo "SearXNG restarted"
        ;;
    redis)
        docker exec -it winejs-searxng-redis valkey-cli
        ;;
    search)
        echo "Search interface: https://\${DOMAIN_NAME}/searxng/"
        ;;
    stats)
        echo "Cache stats:"
        docker exec winejs-searxng-redis valkey-cli INFO stats | grep -E "total_commands_processed|instantaneous_ops_per_sec"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/searxng/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/searxng/"
        fi
        ;;
    *)
        echo "SearXNG Privacy Search Engine Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-searxng open        - Open search interface"
        echo "  winejs-searxng status      - Check server status"
        echo "  winejs-searxng logs        - View server logs"
        echo "  winejs-searxng restart     - Restart server"
        echo "  winejs-searxng stats       - Show cache statistics"
        echo "  winejs-searxng redis       - Connect to Redis CLI"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/searxng/"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-searxng

# ============= START CONTAINER =============
log "🚀 Starting SearXNG container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

sleep 15

if docker ps | grep -q "winejs-${APP_NAME}"; then
    success "✅ Container started successfully"
else
    warn "⚠️ Container may not have started. Check: docker logs winejs-${APP_NAME}"
    docker logs winejs-${APP_NAME} --tail 20
fi

# ============= WAIT FOR SEARXNG TO INITIALIZE =============
log "⏳ Waiting for SearXNG to initialize..."
sleep 10

# ============= UPDATE NGINX FOR SEARXNG =============
log "📝 Setting up nginx reverse proxy for SearXNG..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    # Check if SearXNG routes already exist
    if ! grep -q "location /searxng" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        # Find the line with "listen 443" and insert BEFORE it
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # SearXNG Privacy Search Engine\n\
    location /searxng {\n\
        rewrite ^/searxng(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_set_header X-Forwarded-Host \\\$host;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_connect_timeout 30s;\n\
        proxy_send_timeout 30s;\n\
        proxy_read_timeout 30s;\n\
        proxy_buffering off;\n\
    }\n\
    \n\
    # SearXNG static files cache\n\
    location ~ ^/searxng/static/ {\n\
        rewrite ^/searxng/static/(.*)$ /static/\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        expires 1y;\n\
        add_header Cache-Control \"public, immutable\";\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with SearXNG routes"
            else
                warn "Nginx test failed, restoring backup"
                cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                nginx -t && systemctl reload nginx
            fi
        fi
    else
        log "SearXNG routes already exist"
    fi
fi

# ============= RESTART TRANSLATOR TO REGISTER APP =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_searxng.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling SearXNG..."

docker stop winejs-searxng winejs-searxng-redis 2>/dev/null
docker rm winejs-searxng winejs-searxng-redis 2>/dev/null

rm -rf /opt/winejs/apps/searxng
rm -rf /opt/winejs/kasmvnc-instances/searxng
rm -rf /opt/winejs/data/searxng
rm -rf /opt/winejs/config/searxng

rm -f /usr/local/bin/winejs-searxng

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# SearXNG Privacy Search Engine/,/location ~ \^\/searxng\/static\//d' /etc/nginx/sites-available/winejs
    sed -i '/location \/searxng {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ SearXNG uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_searxng.sh"

# ============= FINAL HEALTH CHECK =============
log "🔍 Performing final health check..."
sleep 5

if curl -s -f "http://127.0.0.1:${APP_PORT}/healthz" > /dev/null 2>&1; then
    success "✅ SearXNG health check passed!"
else
    warn "⚠️ Health check may take a moment. Check: docker logs winejs-searxng"
fi

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           SEARXNG INSTALLED ON WINEJS!                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ SearXNG Privacy Search Engine installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/searxng/"
echo ""
info "🔍 Instance Details:"
info "   • Name: $INSTANCE_NAME"
info "   • Safe Search: $([ $SAFE_SEARCH -eq 0 ] && echo "Off" || ([ $SAFE_SEARCH -eq 1 ] && echo "Moderate" || echo "Strict"))"
info "   • Image Proxy: $IMAGE_PROXY"
info "   • Rate Limiting: $LIMITER"
echo ""
info "🔑 Security:"
info "   • Secret Key: $SECRET_KEY"
info "   • SSL: Automatic via Let's Encrypt"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-searxng open        # Open search interface"
info "   • winejs-searxng status      # Check server status"
info "   • winejs-searxng logs        # View logs"
info "   • winejs-searxng stats       # Show cache stats"
echo ""
info "📁 Data Directories:"
info "   • Config: $DATA_DIR/config"
info "   • Cache: $DATA_DIR/data"
info "   • Redis: $DATA_DIR/redis"
echo ""
info "🔧 Configuration File:"
info "   • $DATA_DIR/config/settings.yml"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_searxng.sh"
echo ""
success "✨ SearXNG is ready! Start searching privately at https://$DOMAIN_NAME/searxng/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"