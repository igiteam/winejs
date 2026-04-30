#!/bin/bash
# ============================================
# OpenSpy Gaming Server Platform - WineJS Installer
# Adds Game Server Browser & Statistics to WineJS
# ============================================
# App: OpenSpy
# Category: Gaming
# Features: Game Server Browser, Player Statistics, Match History
# ============================================

OPENSPY_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/openspy-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🎮 Installing WineJS OpenSpy Gaming Platform..."

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
read -p "Admin email for SSL: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""
read -p "Max upload size (MB) [256]: " UPLOAD_SIZE_MB
UPLOAD_SIZE_MB=${UPLOAD_SIZE_MB:-256}

# Generate JWT secret
if [ -z "${OPENSPY_JWT_SECRET:-}" ]; then
    OPENSPY_JWT_SECRET=$(head -c 64 /dev/urandom | xxd -p -c 64 | head -1)
fi

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=7300  # Start after Huly's range (7200+)
MAX_RETRIES=50
APP_PORT=""
NGINX_PORT=""

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

# Find available port for OpenSpy backend
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

# Find available port for nginx (internal)
for i in $(seq 1 $MAX_RETRIES); do
    TEST_PORT=$((APP_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        NGINX_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for OpenSpy"
fi

log "Using ports: OpenSpy=$APP_PORT, Nginx=$NGINX_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="openspy"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/openspy"
CONFIG_DIR="/opt/winejs/config/openspy"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{data,geoip,nginx-conf}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/openspy"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE NGINX CONFIGURATION =============
log "📝 Creating nginx configuration..."

cat > "$DATA_DIR/nginx-conf/default.conf" << EOF
server {
    listen 80;
    server_name _;
    
    client_max_body_size ${UPLOAD_SIZE_MB}M;
    
    location / {
        proxy_pass http://openspy-web:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /api/ {
        proxy_pass http://authservices:3000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml for OpenSpy services..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
version: "3.8"

services:
  # RabbitMQ message broker
  rabbit:
    image: rabbitmq:3-management-alpine
    container_name: winejs-openspy-rabbit
    restart: unless-stopped
    environment:
      RABBITMQ_DEFAULT_USER: rabbitmq
      RABBITMQ_DEFAULT_PASS: rabbitmq
    volumes:
      - ${DATA_DIR}/rabbitmq:/var/lib/rabbitmq
    networks:
      - winejs-net

  # Redis cache
  redis:
    image: redis:7-alpine
    container_name: winejs-openspy-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - winejs-net

  # MongoDB database
  mongo:
    image: mongo:6
    container_name: winejs-openspy-mongo
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: OpenSpy
      MONGO_INITDB_ROOT_PASSWORD: OpenSpy123
    volumes:
      - ${DATA_DIR}/mongo:/data/db
    networks:
      - winejs-net

  # OpenSpy Core Services
  authservices:
    image: chcniz/openspy-auth-services:latest
    container_name: winejs-openspy-auth
    restart: unless-stopped
    depends_on:
      - rabbit
      - mongo
    environment:
      RABBITMQ_URL: amqp://rabbitmq:rabbitmq@rabbit
      MONGODB_URI: mongodb://OpenSpy:OpenSpy123@mongo:27017
      JWT_SECRET: ${OPENSPY_JWT_SECRET}
    networks:
      - winejs-net

  commerceservice:
    image: chcniz/openspy-commerce-service:latest
    container_name: winejs-openspy-commerce
    restart: unless-stopped
    depends_on:
      - rabbit
      - mongo
    environment:
      RABBITMQ_URL: amqp://rabbitmq:rabbitmq@rabbit
      MONGODB_URI: mongodb://OpenSpy:OpenSpy123@mongo:27017
    networks:
      - winejs-net

  competitionservice:
    image: chcniz/openspy-competition-service:latest
    container_name: winejs-openspy-competition
    restart: unless-stopped
    depends_on:
      - rabbit
      - mongo
    environment:
      RABBITMQ_URL: amqp://rabbitmq:rabbitmq@rabbit
      MONGODB_URI: mongodb://OpenSpy:OpenSpy123@mongo:27017
    networks:
      - winejs-net

  storageservice:
    image: chcniz/openspy-storage-service:latest
    container_name: winejs-openspy-storage
    restart: unless-stopped
    depends_on:
      - rabbit
      - mongo
    environment:
      RABBITMQ_URL: amqp://rabbitmq:rabbitmq@rabbit
      MONGODB_URI: mongodb://OpenSpy:OpenSpy123@mongo:27017
    networks:
      - winejs-net

  # NAT Negotiation Helper
  natneg-helper:
    image: chcniz/openspy-natneg-helper:latest
    container_name: winejs-openspy-natneg
    restart: unless-stopped
    depends_on:
      - rabbit
    environment:
      RABBITMQ_URL: amqp://rabbitmq:rabbitmq@rabbit
      UNSOLICITED_PORT_PROBE_DRIVER: 0.0.0.0:30695
      UNSOLICITED_IP_PROBE_DRIVER: unset
      UNSOLICITED_IPPORT_PROBE_DRIVER: unset
      SKIP_ERTL: 1
    networks:
      - winejs-net

  # QR Service
  qr-service:
    image: chcniz/openspy-qr-service:latest
    container_name: winejs-openspy-qr
    restart: unless-stopped
    depends_on:
      - rabbit
      - redis
    environment:
      RABBITMQ_URL: amqp://rabbitmq:rabbitmq@rabbit
      REDIS_URL: redis://redis:6379
      GEOIP_DB_PATH: /GeoLite2-City.mmdb
    volumes:
      - ${DATA_DIR}/geoip:/geoip
    networks:
      - winejs-net

  # Game Stats Web
  gamestats-web:
    image: chcniz/openspy-gamestats-web:latest
    container_name: winejs-openspy-gamestats
    restart: unless-stopped
    environment:
      GAMESTATS_MONGODB_URI: mongodb://OpenSpy:OpenSpy123@mongo:27017
      PORT: 4000
    networks:
      - winejs-net

  # BF2142 Stella Web
  stella-web:
    image: chcniz/openspy-bf2142-stella-web:latest
    container_name: winejs-openspy-stella
    restart: unless-stopped
    environment:
      API_KEY: ELGAoKHyFPfsWhmWF5F/8uNz2YcdTrojCZbRfvlFwBKJIhDUdvMwM4bmljSsEBq57riyXRij8FoqmxWR8C2BQIEaGG68uFJKcQmJlLY2ntAFOYUloccRCr/eBW8sJZsTIGaIdVdsDeDOrRJR487tfFGNHW2Ezp+oVrZVsd3C9e0VobSE1fXdSFz3R5MIqH3bLprfcDLJL/U8gtvUBegOQI22Vviha24W0/76SQSo72Z7i6GrpU/OnrsjcHQSwyC6VeCTv5JjCP/BSsaCK0Zxw3OlzQsPAprQug9Pwm5MrH/pkkxhqLKcCxjsU25Zj+ipkKOzsO+rmqaIMsK6ILke6w==
      API_ENDPOINT: http://core-web:8080
      MONGODB_URI: mongodb://OpenSpy:OpenSpy123@mongo:27017
      PORT: 4000
    networks:
      - winejs-net

  # Web Frontend
  openspy-web:
    image: chcniz/openspy-web:latest
    container_name: winejs-openspy-web
    restart: unless-stopped
    depends_on:
      - authservices
      - commerceservice
      - competitionservice
      - storageservice
    ports:
      - "127.0.0.1:${APP_PORT}:8080"
    networks:
      - winejs-net

  # Internal Nginx
  nginx:
    image: nginx:1-alpine
    container_name: winejs-openspy-nginx
    restart: unless-stopped
    depends_on:
      - authservices
      - commerceservice
      - competitionservice
      - storageservice
      - openspy-web
    ports:
      - "127.0.0.1:${NGINX_PORT}:80"
    volumes:
      - ${DATA_DIR}/nginx-conf:/etc/nginx/conf.d
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "OpenSpy Gaming Platform",
    "version": "latest",
    "description": "Game server browser, player statistics, and match history platform",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/openspy.png",
    "category": "Gaming",
    "features": [
        "🎮 Game Server Browser",
        "📊 Player Statistics Tracking",
        "🏆 Match History & Rankings",
        "🔍 Server Discovery",
        "👥 Player Profiles",
        "📈 Real-time Stats",
        "🌍 Global Leaderboards",
        "🎯 Game-specific Stats",
        "🔐 User Authentication",
        "📱 Mobile-responsive Interface",
        "🔄 Auto-updating Server List",
        "📝 Match Reports"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading OpenSpy icon..."
curl -L "$OPENSPY_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= DOWNLOAD GEOIP DATABASE =============
log "📥 Downloading GeoIP database..."
curl -L "https://github.com/maxmind/geoipupdate/raw/main/GeoLite2-City.mmdb" -o "$DATA_DIR/geoip/GeoLite2-City.mmdb" 2>/dev/null || \
warn "Failed to download GeoIP database"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-openspy << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}
INSTANCE_DIR="${INSTANCE_DIR}"

case "\$1" in
    status)
        cd "\$INSTANCE_DIR" && docker compose ps
        ;;
    logs)
        cd "\$INSTANCE_DIR" && docker compose logs -f --tail=50
        ;;
    restart)
        cd "\$INSTANCE_DIR" && docker compose restart
        echo "OpenSpy restarted"
        ;;
    stop)
        cd "\$INSTANCE_DIR" && docker compose down
        echo "OpenSpy stopped"
        ;;
    start)
        cd "\$INSTANCE_DIR" && docker compose up -d
        echo "OpenSpy started"
        ;;
    servers)
        echo "🌐 Game Server Browser: https://\${DOMAIN_NAME}/openspy/"
        echo ""
        echo "Supported Games:"
        echo "  • Battlefield 1942"
        echo "  • Battlefield 2"
        echo "  • Battlefield 2142"
        echo "  • Call of Duty"
        echo "  • Medal of Honor"
        echo "  • And more..."
        ;;
    stats)
        echo "📊 Check player stats at: https://\${DOMAIN_NAME}/openspy/stats"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/openspy/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/openspy/"
        fi
        ;;
    *)
        echo "OpenSpy Gaming Platform Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-openspy open        - Open OpenSpy interface"
        echo "  winejs-openspy status      - Check all services status"
        echo "  winejs-openspy logs        - View all logs"
        echo "  winejs-openspy restart     - Restart all services"
        echo "  winejs-openspy stop        - Stop all services"
        echo "  winejs-openspy start       - Start all services"
        echo "  winejs-openspy servers     - Show supported games"
        echo "  winejs-openspy stats       - Open stats page"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/openspy/"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-openspy

# ============= START CONTAINERS =============
log "🚀 Starting OpenSpy services..."

cd "$INSTANCE_DIR"

# Export JWT secret
export OPENSPY_JWT_SECRET

# Start all services
docker-compose up -d

sleep 30

# Check if containers are running
if docker ps | grep -q "winejs-openspy"; then
    success "✅ OpenSpy containers started successfully"
else
    warn "⚠️ Some containers may not have started. Check: docker compose ps"
fi

# ============= UPDATE NGINX FOR OPENSPY =============
log "📝 Setting up nginx reverse proxy for OpenSpy..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /openspy" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # OpenSpy Gaming Platform\n\
    location /openspy {\n\
        rewrite ^/openspy(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${NGINX_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        client_max_body_size ${UPLOAD_SIZE_MB}M;\n\
        proxy_read_timeout 86400;\n\
        proxy_buffering off;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with OpenSpy routes"
            else
                warn "Nginx test failed, restoring backup"
                cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                nginx -t && systemctl reload nginx
            fi
        fi
    fi
fi

# ============= RESTART TRANSLATOR =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_openspy.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling OpenSpy..."

cd /opt/winejs/kasmvnc-instances/openspy
docker compose down -v 2>/dev/null

rm -rf /opt/winejs/apps/openspy
rm -rf /opt/winejs/kasmvnc-instances/openspy
rm -rf /opt/winejs/data/openspy

rm -f /usr/local/bin/winejs-openspy

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# OpenSpy Gaming Platform/,/location \/openspy/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/openspy {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ OpenSpy uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_openspy.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              OPENSPY INSTALLED ON WINEJS!                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ OpenSpy Gaming Platform installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/openspy/"
echo ""
info "🎮 Features:"
info "   • Game Server Browser"
info "   • Player Statistics"
info "   • Match History"
info "   • Global Leaderboards"
echo ""
info "🎯 Supported Games:"
info "   • Battlefield 1942 / 2 / 2142"
info "   • Call of Duty series"
info "   • Medal of Honor series"
info "   • And many more classic shooters"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-openspy open        # Open OpenSpy"
info "   • winejs-openspy status      # Check services"
info "   • winejs-openspy logs        # View logs"
info "   • winejs-openspy servers     # Show supported games"
info "   • winejs-openspy stats       # Open stats page"
echo ""
info "📁 Data Directory: $DATA_DIR"
echo ""
info "🔐 JWT Secret: $OPENSPY_JWT_SECRET"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_openspy.sh"
echo ""
success "✨ OpenSpy is ready! Browse game servers at https://$DOMAIN_NAME/openspy/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"