#!/bin/bash
# ============================================
# Huly Project Management Platform - WineJS Installer
# Adds All-in-One Project Management to WineJS
# ============================================
# App: Huly
# Category: Productivity
# Features: Project Management, Team Collaboration, AI Assistant
# ============================================

HULY_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/huly-project-management-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🎮 Installing WineJS Huly Project Management Platform..."

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

# ============= ASK FOR HULY CONFIGURATION =============
echo ""
info "📝 Huly Configuration"
echo "================================"
read -p "Admin email for SSL: " ADMIN_EMAIL
read -s -p "Admin password (for initial setup): " ADMIN_PASSWORD
echo ""
read -p "Huly version [v0.7.242]: " HULY_VERSION
HULY_VERSION=${HULY_VERSION:-"v0.7.242"}

# Generate secure credentials
generate_secure_random() {
    local type="$1"
    local length="$2"
    local result=""
    
    if command -v openssl &>/dev/null; then
        if [ "$type" = "hex" ]; then
            result=$(openssl rand -hex "$length" 2>/dev/null || true)
        else
            result=$(openssl rand -base64 "$length" 2>/dev/null | tr -d '\n+/=' | head -c "$length" || true)
        fi
    fi
    
    if [ -z "$result" ] && [ -f /dev/urandom ]; then
        if [ "$type" = "hex" ]; then
            result=$(head -c "$length" /dev/urandom | xxd -p -c "$length" 2>/dev/null || true)
        else
            result=$(head -c "$length" /dev/urandom | base64 | tr -d '\n+/=' | head -c "$length" 2>/dev/null || true)
        fi
    fi
    
    if [ -z "$result" ]; then
        error "Unable to generate random string"
    fi
    
    echo "$result"
}

HULY_SECRET=$(generate_secure_random hex 32)
COCKROACH_SECRET="cr_$(generate_secure_random hex 16)"
REDPANDA_SECRET="rp_$(generate_secure_random hex 16)"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="huly"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/huly"
HULY_DIR="$DATA_DIR/huly-selfhost"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$HULY_DIR" "$ICON_DIR"
chown -R 1000:1000 "$DATA_DIR" 2>/dev/null || true

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/huly"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE HULY CONFIGURATION =============
log "📝 Creating Huly configuration..."

cat > "$HULY_DIR/huly_v7.conf" << EOF
# Huly Configuration - WineJS Installer
HULY_VERSION=$HULY_VERSION
DESKTOP_CHANNEL=0.7.242
DOCKER_NAME=huly_v7

# Network Configuration
HOST_ADDRESS=$DOMAIN_NAME
SECURE=true
HTTP_PORT=80
HTTP_BIND=0.0.0.0

# Huly Specific
TITLE=WineJS Huly Project Management
DEFAULT_LANGUAGE=en
LAST_NAME_FIRST=true

# CockroachDB
CR_DATABASE=defaultdb
CR_USERNAME=selfhost
CR_USER_PASSWORD=$COCKROACH_SECRET
CR_DB_URL=postgres://selfhost:$COCKROACH_SECRET@cockroach:26257/defaultdb

# Redpanda
REDPANDA_ADMIN_USER=superadmin
REDPANDA_ADMIN_PWD=$REDPANDA_SECRET

# Auto-generated secrets
SECRET=$HULY_SECRET
EOF

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml for Huly microservices..."

cat > "$INSTANCE_DIR/docker-compose.yml" << 'DOCKER_EOF'
name: huly_v7
services:
  cockroach:
    image: cockroachdb/cockroach:latest-v24.2
    container_name: winejs-huly-cockroach
    command: start-single-node --accept-sql-without-tls
    environment:
      - COCKROACH_DATABASE=defaultdb
      - COCKROACH_USER=selfhost
      - COCKROACH_PASSWORD=${COCKROACH_SECRET}
    volumes:
      - huly_cr_data:/cockroach/cockroach-data
      - huly_cr_certs:/cockroach/certs
    restart: unless-stopped
    networks:
      - winejs-net

  redpanda:
    image: docker.redpanda.com/redpandadata/redpanda:v24.3.6
    container_name: winejs-huly-redpanda
    command:
      - redpanda
      - start
      - --kafka-addr internal://0.0.0.0:9092,external://0.0.0.0:19092
      - --advertise-kafka-addr internal://redpanda:9092,external://localhost:19092
      - --pandaproxy-addr internal://0.0.0.0:8082,external://0.0.0.0:18082
      - --advertise-pandaproxy-addr internal://redpanda:8082,external://localhost:18082
      - --schema-registry-addr internal://0.0.0.0:8081,external://0.0.0.0:18081
      - --rpc-addr redpanda:33145
      - --advertise-rpc-addr redpanda:33145
      - --mode dev-container
      - --smp 1
      - --default-log-level=info
    volumes:
      - huly_redpanda:/var/lib/redpanda/data
    environment:
      - REDPANDA_SUPERUSER_USERNAME=superadmin
      - REDPANDA_SUPERUSER_PASSWORD=${REDPANDA_SECRET}
    healthcheck:
      test: ['CMD', 'rpk', 'cluster', 'info', '-X', 'user=superadmin', '-X', 'pass=${REDPANDA_SECRET}']
      interval: 10s
      timeout: 5s
      retries: 10
    networks:
      - winejs-net

  minio:
    image: minio/minio
    container_name: winejs-huly-minio
    command: server /data --address ":9000" --console-address ":9001"
    volumes:
      - huly_files:/data
    healthcheck:
      test: ['CMD', 'mc', 'ready', 'local']
      interval: 5s
      retries: 10
    restart: unless-stopped
    networks:
      - winejs-net

  elastic:
    image: elasticsearch:7.14.2
    container_name: winejs-huly-elastic
    command: |
      /bin/sh -c "./bin/elasticsearch-plugin list | grep -q ingest-attachment || yes | ./bin/elasticsearch-plugin install --silent ingest-attachment;
      /usr/local/bin/docker-entrypoint.sh eswrapper"
    volumes:
      - huly_elastic:/usr/share/elasticsearch/data
    environment:
      - ELASTICSEARCH_PORT_NUMBER=9200
      - BITNAMI_DEBUG=true
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms1024m -Xmx1024m
      - http.cors.enabled=true
      - http.cors.allow-origin=http://localhost:8082
    healthcheck:
      interval: 20s
      retries: 10
      test: curl -s http://localhost:9200/_cluster/health | grep -vq '"status":"red"'
    restart: unless-stopped
    networks:
      - winejs-net

  rekoni:
    image: hardcoreeng/rekoni-service:${HULY_VERSION}
    container_name: winejs-huly-rekoni
    environment:
      - SECRET=${SECRET}
    deploy:
      resources:
        limits:
          memory: 500M
    restart: unless-stopped
    networks:
      - winejs-net

  transactor:
    image: hardcoreeng/transactor:${HULY_VERSION}
    container_name: winejs-huly-transactor
    environment:
      - SERVER_PORT=3333
      - SERVER_SECRET=${SECRET}
      - DB_URL=${CR_DB_URL}
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - FRONT_URL=http://localhost:8087
      - ACCOUNTS_URL=http://account:3000
      - FULLTEXT_URL=http://fulltext:4700
      - STATS_URL=http://stats:4900
      - LAST_NAME_FIRST=true
      - QUEUE_CONFIG=redpanda:9092
    restart: unless-stopped
    networks:
      - winejs-net

  collaborator:
    image: hardcoreeng/collaborator:${HULY_VERSION}
    container_name: winejs-huly-collaborator
    environment:
      - COLLABORATOR_PORT=3078
      - SECRET=${SECRET}
      - ACCOUNTS_URL=http://account:3000
      - STATS_URL=http://stats:4900
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
    restart: unless-stopped
    networks:
      - winejs-net

  account:
    image: hardcoreeng/account:${HULY_VERSION}
    container_name: winejs-huly-account
    environment:
      - SERVER_PORT=3000
      - SERVER_SECRET=${SECRET}
      - DB_URL=${CR_DB_URL}
      - TRANSACTOR_URL=ws://transactor:3333;wss://${HOST_ADDRESS}/_transactor
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - FRONT_URL=https://${HOST_ADDRESS}
      - STATS_URL=https://${HOST_ADDRESS}/stats
      - MODEL_ENABLED=*
      - ACCOUNTS_URL=https://${HOST_ADDRESS}/_accounts
      - ACCOUNT_PORT=3000
      - QUEUE_CONFIG=redpanda:9092
    restart: unless-stopped
    networks:
      - winejs-net

  workspace:
    image: hardcoreeng/workspace:${HULY_VERSION}
    container_name: winejs-huly-workspace
    environment:
      - SERVER_SECRET=${SECRET}
      - DB_URL=${CR_DB_URL}
      - TRANSACTOR_URL=ws://transactor:3333;wss://${HOST_ADDRESS}/_transactor
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - MODEL_ENABLED=*
      - ACCOUNTS_URL=http://account:3000
      - STATS_URL=http://stats:4900
      - QUEUE_CONFIG=redpanda:9092
      - ACCOUNTS_DB_URL=${CR_DB_URL}
    restart: unless-stopped
    networks:
      - winejs-net

  front:
    image: hardcoreeng/front:${HULY_VERSION}
    container_name: winejs-huly-front
    ports:
      - "127.0.0.1:8080:8080"
    environment:
      - SERVER_PORT=8080
      - SERVER_SECRET=${SECRET}
      - LOVE_ENDPOINT=https://${HOST_ADDRESS}/_love
      - ACCOUNTS_URL=https://${HOST_ADDRESS}/_accounts
      - ACCOUNTS_URL_INTERNAL=http://account:3000
      - REKONI_URL=https://${HOST_ADDRESS}/_rekoni
      - CALENDAR_URL=https://${HOST_ADDRESS}/_calendar
      - GMAIL_URL=https://${HOST_ADDRESS}/_gmail
      - TELEGRAM_URL=https://${HOST_ADDRESS}/_telegram
      - STATS_URL=https://${HOST_ADDRESS}/_stats
      - UPLOAD_URL=/files
      - ELASTIC_URL=http://elastic:9200
      - COLLABORATOR_URL=wss://${HOST_ADDRESS}/_collaborator
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - TITLE=WineJS Huly Project Management
      - DEFAULT_LANGUAGE=en
      - LAST_NAME_FIRST=true
    restart: unless-stopped
    networks:
      - winejs-net

  fulltext:
    image: hardcoreeng/fulltext:${HULY_VERSION}
    container_name: winejs-huly-fulltext
    environment:
      - SERVER_SECRET=${SECRET}
      - DB_URL=${CR_DB_URL}
      - FULLTEXT_DB_URL=http://elastic:9200
      - ELASTIC_INDEX_NAME=huly_storage_index
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - REKONI_URL=http://rekoni:4004
      - ACCOUNTS_URL=http://account:3000
      - STATS_URL=http://stats:4900
      - QUEUE_CONFIG=redpanda:9092
    restart: unless-stopped
    networks:
      - winejs-net

  stats:
    image: hardcoreeng/stats:${HULY_VERSION}
    container_name: winejs-huly-stats
    environment:
      - PORT=4900
      - SERVER_SECRET=${SECRET}
    restart: unless-stopped
    networks:
      - winejs-net

  kvs:
    image: hardcoreeng/hulykvs:${HULY_VERSION}
    container_name: winejs-huly-kvs
    depends_on:
      cockroach:
        condition: service_started
    ports:
      - "127.0.0.1:8094:8094"
    environment:
      - HULY_DB_CONNECTION=${CR_DB_URL}
      - HULY_TOKEN_SECRET=${SECRET}
    restart: unless-stopped
    networks:
      - winejs-net

  love:
    image: hardcoreeng/love:${HULY_VERSION}
    container_name: winejs-huly-love
    environment:
      - PORT=8096
      - SECRET=${SECRET}
      - ACCOUNTS_URL=http://account:3000
      - DB_URL=${CR_DB_URL}
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - STORAGE_PROVIDER_NAME=minio
    restart: unless-stopped
    networks:
      - winejs-net

  print:
    image: hardcoreeng/print:${HULY_VERSION}
    container_name: winejs-huly-print
    environment:
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - STATS_URL=http://stats:4900
      - SECRET=${SECRET}
    restart: unless-stopped
    networks:
      - winejs-net

  aibot:
    image: hardcoreeng/ai-bot:${HULY_VERSION}
    container_name: winejs-huly-aibot
    environment:
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - SERVER_SECRET=${SECRET}
      - ACCOUNTS_URL=http://account:3000
      - DB_URL=${CR_DB_URL}
      - STATS_URL=http://stats:4900
      - FIRST_NAME=Bot
      - LAST_NAME=Huly AI
      - PASSWORD=${SECRET}
    restart: unless-stopped
    networks:
      - winejs-net

  calendar:
    image: hardcoreeng/calendar:${HULY_VERSION}
    container_name: winejs-huly-calendar
    environment:
      - ACCOUNTS_URL=http://account:3000
      - STATS_URL=http://stats:4900
      - SECRET=${SECRET}
      - KVS_URL=http://kvs:8094
    restart: unless-stopped
    networks:
      - winejs-net

  github:
    image: hardcoreeng/github:${HULY_VERSION}
    container_name: winejs-huly-github
    environment:
      - PORT=3500
      - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
      - SERVER_SECRET=${SECRET}
      - ACCOUNTS_URL=http://account:3000
      - STATS_URL=http://stats:4900
      - COLLABORATOR_URL=wss://${HOST_ADDRESS}/_collaborator
      - FRONT_URL=https://${HOST_ADDRESS}
      - BOT_NAME=Huly[bot]
    restart: unless-stopped
    networks:
      - winejs-net

volumes:
  huly_elastic:
  huly_files:
  huly_cr_data:
  huly_cr_certs:
  huly_redpanda:

networks:
  winejs-net:
    external: true
DOCKER_EOF

# Substitute environment variables in docker-compose
sed -i "s/\${COCKROACH_SECRET}/$COCKROACH_SECRET/g" "$INSTANCE_DIR/docker-compose.yml"
sed -i "s/\${REDPANDA_SECRET}/$REDPANDA_SECRET/g" "$INSTANCE_DIR/docker-compose.yml"
sed -i "s/\${SECRET}/$HULY_SECRET/g" "$INSTANCE_DIR/docker-compose.yml"
sed -i "s/\${HOST_ADDRESS}/$DOMAIN_NAME/g" "$INSTANCE_DIR/docker-compose.yml"
sed -i "s/\${CR_DB_URL}/postgres:\/\/selfhost:$COCKROACH_SECRET@cockroach:26257\/defaultdb/g" "$INSTANCE_DIR/docker-compose.yml"
sed -i "s/\${HULY_VERSION}/$HULY_VERSION/g" "$INSTANCE_DIR/docker-compose.yml"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Huly Project Management",
    "version": "${HULY_VERSION}",
    "description": "All-in-one project management platform with AI assistant, team collaboration, and workflow automation",
    "executable": "launch.sh",
    "port": 8080,
    "vnc_password": "",
    "icon": "/icons/huly.png",
    "category": "Productivity",
    "features": [
        "📊 Project Management",
        "🤖 AI-Powered Assistant",
        "👥 Team Collaboration",
        "📅 Calendar Integration",
        "📝 Document Management",
        "🔗 GitHub Integration",
        "💬 Real-time Chat",
        "📎 File Storage (MinIO)",
        "🔍 Full-text Search",
        "📧 Email Integration",
        "🎨 Custom Workflows",
        "📈 Analytics & Stats",
        "🔐 Enterprise Security",
        "🌍 Multi-language Support",
        "📱 Mobile Responsive"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading Huly icon..."
curl -L "$HULY_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-huly << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
HULY_DIR="${HULY_DIR}"
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
        echo "Huly restarted"
        ;;
    stop)
        cd "\$INSTANCE_DIR" && docker compose down
        echo "Huly stopped"
        ;;
    start)
        cd "\$INSTANCE_DIR" && docker compose up -d
        echo "Huly started"
        ;;
    update)
        cd "\$INSTANCE_DIR"
        docker compose pull
        docker compose up -d
        echo "Huly updated"
        ;;
    services)
        echo "📊 Huly Microservices Status:"
        cd "\$INSTANCE_DIR" && docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/huly/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/huly/"
        fi
        ;;
    *)
        echo "Huly Project Management Platform"
        echo ""
        echo "Commands:"
        echo "  winejs-huly open        - Open Huly interface"
        echo "  winejs-huly status      - Check all services status"
        echo "  winejs-huly logs        - View all logs"
        echo "  winejs-huly restart     - Restart all services"
        echo "  winejs-huly stop        - Stop all services"
        echo "  winejs-huly start       - Start all services"
        echo "  winejs-huly update      - Update to latest version"
        echo "  winejs-huly services    - Show microservices status"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/huly/"
        echo "⚠️  Note: First startup takes 3-5 minutes for all 18 services"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-huly

# ============= START CONTAINERS =============
log "🚀 Starting Huly microservices (this may take 3-5 minutes)..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null

# Start infrastructure first
log "Starting infrastructure services..."
docker-compose up -d cockroach redpanda minio elastic

sleep 30

# Start core services
log "Starting core services..."
docker-compose up -d account transactor workspace front fulltext

sleep 20

# Start remaining services
log "Starting all remaining services..."
docker-compose up -d

sleep 30

# ============= SETUP MINIO BUCKET =============
log "📦 Setting up MinIO storage..."

# Wait for MinIO to be ready
MAX_ATTEMPTS=30
for i in $(seq 1 $MAX_ATTEMPTS); do
    if docker exec winejs-huly-minio curl -s http://localhost:9000/minio/health/live >/dev/null 2>&1; then
        log "✅ MinIO is ready"
        break
    fi
    if [ $i -eq $MAX_ATTEMPTS ]; then
        warn "MinIO may not be ready, but continuing..."
    fi
    sleep 2
done

# Create bucket
docker exec winejs-huly-minio mc alias set local http://localhost:9000 minioadmin minioadmin 2>/dev/null || true
docker exec winejs-huly-minio mc mb local/uploads --ignore-existing 2>/dev/null || true
docker exec winejs-huly-minio mc anonymous set public local/uploads 2>/dev/null || true

log "✅ MinIO bucket configured"

# ============= UPDATE NGINX FOR HULY =============
log "📝 Setting up nginx reverse proxy for Huly..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /huly" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Huly Project Management\n\
    location /huly {\n\
        rewrite ^/huly(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:8080;\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 86400;\n\
        proxy_buffering off;\n\
    }\n\
    \n\
    location /huly/_accounts/ {\n\
        rewrite ^/huly/_accounts/(.*)$ /_accounts/\\\$1 break;\n\
        proxy_pass http://127.0.0.1:3000/;\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
    }\n\
    \n\
    location /huly/_transactor {\n\
        rewrite ^/huly/_transactor(.*)$ /_transactor\\\$1 break;\n\
        proxy_pass http://127.0.0.1:3333;\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Huly routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_huly.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Huly..."

cd /opt/winejs/kasmvnc-instances/huly
docker compose down -v 2>/dev/null

rm -rf /opt/winejs/apps/huly
rm -rf /opt/winejs/kasmvnc-instances/huly
rm -rf /opt/winejs/data/huly

rm -f /usr/local/bin/winejs-huly

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Huly Project Management/,/location \/huly\/_transactor/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/huly {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Huly uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_huly.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              HULY INSTALLED ON WINEJS!                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Huly Project Management Platform installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/huly/"
echo ""
info "🔐 Credentials:"
info "   • Admin Email: $ADMIN_EMAIL"
info "   • Admin Password: $ADMIN_PASSWORD"
info "   • First login: Create your organization and account"
echo ""
info "🔑 System Secrets (save these):"
info "   • Huly Secret: $HULY_SECRET"
info "   • CockroachDB: $COCKROACH_SECRET"
info "   • Redpanda: $REDPANDA_SECRET"
echo ""
info "📊 Microservices: 18 containers total"
info "   • Database: CockroachDB"
info "   • Queue: Redpanda (Kafka-compatible)"
info "   • Storage: MinIO"
info "   • Search: Elasticsearch"
info "   • AI: AI Bot Assistant"
info "   • Integrations: GitHub, Calendar, Love, Print"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-huly open        # Open Huly"
info "   • winejs-huly status      # Check all services"
info "   • winejs-huly logs        # View logs"
info "   • winejs-huly services    # Show microservices"
info "   • winejs-huly update      # Update to latest"
echo ""
info "📁 Data Directory: $DATA_DIR"
echo ""
info "⚠️  Important Notes:"
info "   • First startup takes 3-5 minutes for all services"
info "   • Requires 4GB+ RAM minimum"
info "   • All 18 microservices auto-start with WineJS"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_huly.sh"
echo ""
success "✨ Huly is ready! Access your project management suite at https://$DOMAIN_NAME/huly/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"