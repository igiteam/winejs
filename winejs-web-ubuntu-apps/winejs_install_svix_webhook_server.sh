#!/bin/bash
# ============================================
# Svix Webhook Server - WineJS Installer
# Adds Webhook Delivery Platform to WineJS
# ============================================
# App: Svix
# Category: Development
# Features: Webhook Delivery, Webhook Logs, Retry Logic
# ============================================

SVIX_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/svix-live-webhook-server.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📨 Installing WineJS Svix Webhook Server..."

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

# ============= ASK FOR SVIX CONFIGURATION =============
echo ""
info "📝 Svix Configuration"
echo "================================"
read -p "Admin email for SSL: " ADMIN_EMAIL

# Generate JWT secret
SVIX_JWT_SECRET=$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)

read -p "Default signature type (symmetric/ed25519) [symmetric]: " SIGNATURE_TYPE
SIGNATURE_TYPE=${SIGNATURE_TYPE:-"symmetric"}

read -p "Webhook retry attempts [5]: " RETRY_ATTEMPTS
RETRY_ATTEMPTS=${RETRY_ATTEMPTS:-5}

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=7500  # Start after Mergeable's range (7400+)
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

# Find available port for Svix
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Svix"
fi

log "Using port: Svix=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="svix"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/svix"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR"/{postgres,redis} "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/svix"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml for Svix services..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # PostgreSQL Database
  postgres:
    image: postgres:13.4
    container_name: winejs-svix-postgres
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 1s
      timeout: 1s
      retries: 600
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: postgres
    networks:
      - winejs-net

  # PgBouncer Connection Pooler
  pgbouncer:
    image: edoburu/pgbouncer:1.15.0
    container_name: winejs-svix-pgbouncer
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h localhost"]
      interval: 30s
      timeout: 10s
      retries: 3
    environment:
      DB_HOST: postgres
      DB_USER: postgres
      DB_PASSWORD: postgres
      MAX_CLIENT_CONN: 500
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - winejs-net

  # Redis Cache & Queue
  redis:
    image: redis:7-alpine
    container_name: winejs-svix-redis
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 1s
      timeout: 1s
      retries: 600
    command: "--save 60 500 --appendonly yes --appendfsync everysec"
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - winejs-net

  # Svix Webhook Server
  svix-server:
    image: svix/svix-server
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "svix-server healthcheck http://localhost:8071"]
      interval: 1s
      timeout: 1s
      retries: 600
    environment:
      WAIT_FOR: "true"
      SVIX_REDIS_DSN: redis://redis:6379
      SVIX_DB_DSN: postgresql://postgres:postgres@pgbouncer/postgres
      SVIX_JWT_SECRET: ${SVIX_JWT_SECRET}
      SVIX_QUEUE_TYPE: redis
      SVIX_DEFAULT_SIGNATURE_TYPE: ${SIGNATURE_TYPE}
      SVIX_RETRY_SCHEDULE: [1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233]
      SVIX_MAX_ATTEMPTS: ${RETRY_ATTEMPTS}
      SVIX_CACHE_TYPE: redis
      SVIX_OPENTELEMETRY_ENABLED: false
      SVIX_LOG_LEVEL: info
    ports:
      - "127.0.0.1:${APP_PORT}:8071"
    depends_on:
      pgbouncer:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

FEATURES_LIST='[
        "📨 Webhook Delivery Platform",
        "🔄 Automatic Retries with Backoff",
        "📊 Webhook Logs & Analytics",
        "🔐 JWT Authentication",
        "⚡ Redis Queue & Cache",
        "🗄️ PostgreSQL Storage",'

if [ "$SIGNATURE_TYPE" = "ed25519" ]; then
    FEATURES_LIST="$FEATURES_LIST\n        \"🔏 ED25519 Asymmetric Signatures\","
else
    FEATURES_LIST="$FEATURES_LIST\n        \"🔑 Symmetric (HS256) Signatures\","
fi

FEATURES_LIST="$FEATURES_LIST
        \"📈 Operational Webhooks\",
        \"🛡️ SSRF Protection\",
        \"🎯 Webhook Filtering\",
        \"📦 SDK Support (Python, JS, Go, Rust, etc.)\"
    ]"

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Svix Webhook Server",
    "version": "latest",
    "description": "Reliable webhook delivery platform with retries, logs, and SDK support",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/svix.png",
    "category": "Development",
    "features": ${FEATURES_LIST}
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading Svix icon..."
curl -L "$SVIX_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= SETUP AUTHENTICATION =============
log "🔐 Setting up Svix authentication..."

# Generate a valid JWT token for the default organization
DEFAULT_ORG_ID="org_23rb8YdGqMT0qIzpgGwdXfHirMu"

# Use docker to generate JWT (or create our own)
if docker run --rm svix/svix-server svix-server jwt generate "$DEFAULT_ORG_ID" 2>/dev/null; then
    SVIX_JWT=$(docker run --rm svix/svix-server svix-server jwt generate "$DEFAULT_ORG_ID" 2>/dev/null)
else
    # Fallback: Create a simple JWT (for demo purposes - in production use proper JWT)
    SVIX_JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE2NTUxNDA2MzksImV4cCI6MTk3MDUwMDYzOSwibmJmIjoxNjU1MTQwNjM5LCJpc3MiOiJzdml4LXNlcnZlciIsInN1YiI6Im9yZ18yM3JiOFlkR3FNVDBxSXpwZ0d3ZFhmSGlyTXUifQ.USMuIPrqsZTSj3kyWupCzJO9eyQioBzh5alGlvRbrbA"
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-svix << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
SVIX_JWT_SECRET="${SVIX_JWT_SECRET}"
SVIX_JWT="${SVIX_JWT}"

case "\$1" in
    status)
        docker ps | grep winejs-svix
        ;;
    logs)
        docker logs winejs-svix --tail 50
        ;;
    restart)
        docker restart winejs-svix
        echo "Svix restarted"
        ;;
    token)
        echo "📋 Svix JWT Token:"
        echo "\$SVIX_JWT"
        echo ""
        echo "Use this token for API calls:"
        echo "curl -H 'Authorization: Bearer \$SVIX_JWT' https://\$DOMAIN_NAME/svix/api/v1/health/"
        ;;
    health)
        echo "🏥 Checking Svix health..."
        curl -s "https://\$DOMAIN_NAME/svix/api/v1/health/" | jq .
        ;;
    apps)
        echo "📱 Listing applications..."
        curl -s -H "Authorization: Bearer \$SVIX_JWT" "https://\$DOMAIN_NAME/svix/api/v1/app/" | jq .
        ;;
    install-cli)
        echo "📦 Installing Svix CLI..."
        npm install -g svix-cli
        echo "✅ Svix CLI installed"
        echo "Configure with: svix-cli auth --token \$SVIX_JWT --server https://\$DOMAIN_NAME/svix"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/svix/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/svix/"
        fi
        ;;
    *)
        echo "Svix Webhook Server Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-svix open           - Open Svix API"
        echo "  winejs-svix status         - Check status"
        echo "  winejs-svix logs           - View logs"
        echo "  winejs-svix restart        - Restart server"
        echo "  winejs-svix token          - Show JWT token"
        echo "  winejs-svix health         - Check health endpoint"
        echo "  winejs-svix apps           - List applications"
        echo "  winejs-svix install-cli    - Install Svix CLI"
        echo ""
        echo "API Base URL: https://\${DOMAIN_NAME}/svix/api/v1/"
        echo "JWT Secret: \$SVIX_JWT_SECRET"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-svix

# ============= START CONTAINERS =============
log "🚀 Starting Svix services (PostgreSQL, Redis, PgBouncer, Svix)..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for services to initialize (this may take 1-2 minutes)..."
sleep 45

if docker ps | grep -q "winejs-${APP_NAME}"; then
    success "✅ Container started successfully"
else
    warn "⚠️ Container may not have started. Check: docker logs winejs-${APP_NAME}"
    docker logs winejs-${APP_NAME} --tail 20
fi

# ============= UPDATE NGINX FOR SVIX =============
log "📝 Setting up nginx reverse proxy for Svix..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /svix" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Svix Webhook Server\n\
    location /svix {\n\
        rewrite ^/svix(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 86400;\n\
        proxy_buffering off;\n\
        client_max_body_size 10M;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Svix routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_svix.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Svix..."

cd /opt/winejs/kasmvnc-instances/svix
docker compose down -v 2>/dev/null

rm -rf /opt/winejs/apps/svix
rm -rf /opt/winejs/kasmvnc-instances/svix
rm -rf /opt/winejs/data/svix

rm -f /usr/local/bin/winejs-svix

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Svix Webhook Server/,/location \/svix/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/svix {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Svix uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_svix.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              SVIX INSTALLED ON WINEJS!                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Svix Webhook Server installed!"
echo ""
info "🌐 API Base URL:"
info "   • https://$DOMAIN_NAME/svix/api/v1/"
echo ""
info "🔐 Authentication:"
info "   • JWT Secret: $SVIX_JWT_SECRET"
info "   • Example JWT: $SVIX_JWT"
echo ""
info "🔧 Configuration:"
info "   • Signature Type: $SIGNATURE_TYPE"
info "   • Max Retry Attempts: $RETRY_ATTEMPTS"
info "   • Retry Schedule: Exponential backoff"
echo ""
info "📦 Quick Start:"
info "   1. Get JWT token: winejs-svix token"
info "   2. Check health: winejs-svix health"
info "   3. Install CLI: winejs-svix install-cli"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-svix open        # Open API"
info "   • winejs-svix status      # Check status"
info "   • winejs-svix logs        # View logs"
info "   • winejs-svix token       # Show JWT"
info "   • winejs-svix health      # Health check"
info "   • winejs-svix apps        # List apps"
echo ""
info "📚 SDK Support:"
info "   • Python, JavaScript, TypeScript"
info "   • Go, Rust, Java, Kotlin"
info "   • C#, PHP, Ruby"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_svix.sh"
echo ""
success "✨ Svix is ready! Send webhooks via https://$DOMAIN_NAME/svix/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Svix Does:

# Svix is a webhook delivery platform that makes sending webhooks reliable and easy:
# Key Features:
#     Reliable Delivery - Automatic retries with exponential backoff
#     Webhook Logs - See every attempt, response, and failure
#     Message Signing - Verify webhooks are authentic (HS256 or ED25519)
#     Rate Limiting - Protect your endpoints
#     Multiple SDKs - Python, JS, Go, Rust, Java, C#, PHP, Ruby

# Perfect For:
#     Building a SaaS - Let customers configure webhooks
#     Event-driven architecture - Connect services
#     Forgejo/Gitea webhooks - Automate CI/CD
#     n8n workflows - Trigger from external events

# Integration with Your WineJS Stack:

# Forgejo (Git) → Webhook → Svix → n8n → Huly
#                     ↓
#               VS Code (notifications)
#               Mumble (voice alerts)