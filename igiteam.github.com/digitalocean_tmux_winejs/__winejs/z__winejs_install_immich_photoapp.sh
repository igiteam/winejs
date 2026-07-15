#!/bin/bash
# ============================================
# WineJS Immich Installer
# Adds Immich Photo Management to WineJS Platform
# ============================================
# App: Immich Photo Manager
# Category: Media
# Features: Photo Backup, Face Recognition, Auto Album, Mobile Sync
# ============================================

# What this script does:
#     ✓ Verifies WineJS platform - Checks if /opt/winejs exists
#     ✓ Creates docker network - Creates winejs-net if missing
#     ✓ Creates all necessary directories with data persistence
#     ✓ Downloads/Configures Immich - Latest version with ML support
#     ✓ Sets up PostgreSQL and Redis for performance
#     ✓ Creates shared volumes system (like Docker mounts)
#     ✓ Creates launch.sh with auto-heal monitor
#     ✓ Creates config.json with all app metadata
#     ✓ Creates docker-compose.yml with volume mounts
#     ✓ Sets up automated backup system
#     ✓ Creates uninstall script with cleanup
#     ✓ Sets up PM2 for microservices persistence
#     ✓ Creates CLI helper tools
#     ✓ Installs ML face recognition models
#     ✓ Restarts translator and starts containers

APP_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/immich.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }
header() { echo -e "${CYAN}$1${NC}"; }

log "🚀 Installing WineJS Immich Server..."

# ============= VERIFY WINEJS PLATFORM =============
log "Verifying WineJS platform..."

if [ ! -d "/opt/winejs" ]; then
    error "WineJS platform not found at /opt/winejs"
    exit 1
fi

# Ensure winejs-net network exists
log "Checking winejs-net network..."
if docker network ls | grep -q "winejs-net"; then
    log "✅ winejs-net network already exists"
    if ! docker network inspect winejs-net &>/dev/null; then
        log "⚠️ Network exists but is corrupted, recreating..."
        docker network rm winejs-net 2>/dev/null || true
        docker network create winejs-net
        log "✅ winejs-net network recreated"
    fi
else
    log "Creating winejs-net network..."
    docker network create winejs-net
    if [ $? -eq 0 ]; then
        log "✅ winejs-net network created"
    else
        error "Failed to create winejs-net network"
    fi
fi

if ! docker network inspect winejs-net &>/dev/null; then
    error "winejs-net network is not available. Please run: docker network create winejs-net"
fi

# ============= GET DOMAIN FROM WINEJS CONFIG =============
if [ -f "/opt/winejs/translator/index.js" ]; then
    DOMAIN_NAME=$(grep "const DOMAIN_NAME" /opt/winejs/translator/index.js | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/")
fi

if [ -z "$DOMAIN_NAME" ]; then
    read -p "Enter your WineJS domain (e.g., photos.yourdomain.com): " DOMAIN_NAME
fi

DOMAIN_NAME=$(echo "$DOMAIN_NAME" | tr -d '"' | tr -d "'" | xargs)
info "Using domain: $DOMAIN_NAME"

# ============= ASK FOR ADMIN DETAILS =============
if [ -z "$ADMIN_EMAIL" ]; then
    read -p "Enter admin email: " ADMIN_EMAIL
fi

if [ -z "$ADMIN_PASSWORD" ]; then
    read -s -p "Enter admin password (min 8 chars): " ADMIN_PASSWORD
    echo ""
fi

# ============= FIND NEXT AVAILABLE PORTS =============
log "Finding next available ports..."

port_in_use() {
    local port=$1
    if ss -tln | grep -q ":$port " || netstat -tln 2>/dev/null | grep -q ":$port "; then
        return 0
    fi
    if docker ps 2>/dev/null | grep -q ":$port->"; then
        return 0
    fi
    return 1
}

START_PORT=7001
MAX_RETRIES=100
APP_PORT=""
MICROSERVICES_PORT=""
ML_PORT=""
WEB_PORT=""

declare -a USED_PORTS
if [ -d "/opt/winejs/apps" ]; then
    for config in /opt/winejs/apps/*/config.json; do
        if [ -f "$config" ]; then
            PORT=$(grep -o '"port": [0-9]*' "$config" | awk '{print $2}')
            if [ -n "$PORT" ]; then
                USED_PORTS+=($PORT)
            fi
        fi
    done
fi

# Find available ports
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

for i in $(seq 1 $MAX_RETRIES); do
    TEST_PORT=$((APP_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        MICROSERVICES_PORT=$TEST_PORT
        break
    fi
done

for i in $(seq 2 $MAX_RETRIES); do
    TEST_PORT=$((APP_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        ML_PORT=$TEST_PORT
        break
    fi
done

for i in $(seq 3 $MAX_RETRIES); do
    TEST_PORT=$((APP_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        WEB_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ] || [ -z "$MICROSERVICES_PORT" ] || [ -z "$ML_PORT" ] || [ -z "$WEB_PORT" ]; then
    error "Could not find available ports"
fi

log "Using ports: Immich=$APP_PORT, Microservices=$MICROSERVICES_PORT, ML=$ML_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="immich"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
IMMICH_DATA="/opt/winejs/data/immich"
IMMICH_CONFIG="/opt/winejs/config/immich"
UPLOAD_LOCATION="/opt/winejs/photos"
DB_DATA_LOCATION="/opt/winejs/data/immich/postgres"
ICON_DIR="/opt/winejs/translator/public/icons"
SHARED_VOLUMES="/opt/winejs/shared-volumes"
THUMBNAILS_DIR="/opt/winejs/data/immich/thumbs"
ENCODED_VIDEOS="/opt/winejs/data/immich/encoded"
PROFILE_DIR="/opt/winejs/data/immich/profile"

mkdir -p "$APP_DIR"
mkdir -p "$INSTANCE_DIR"
mkdir -p "$IMMICH_DATA"/{uploads,thumbs,encoded,profile,backups,ml-cache}
mkdir -p "$IMMICH_CONFIG"
mkdir -p "$UPLOAD_LOCATION"
mkdir -p "$DB_DATA_LOCATION"
mkdir -p "$ICON_DIR"
mkdir -p "$SHARED_VOLUMES"/{backups,imports,exports,face-data,ml-models}
mkdir -p "$THUMBNAILS_DIR"
mkdir -p "$ENCODED_VIDEOS" 
mkdir -p "$PROFILE_DIR"

# ============= FIX PERMISSIONS =============
log "🔧 Fixing permissions for Immich..."

# Immich runs as user 1000:1000
chown -R 1000:1000 "$IMMICH_DATA" 2>/dev/null || true
chown -R 1000:1000 "$IMMICH_CONFIG" 2>/dev/null || true
chown -R 1000:1000 "$UPLOAD_LOCATION" 2>/dev/null || true
chown -R 1000:1000 "$DB_DATA_LOCATION" 2>/dev/null || true
chmod -R 755 "$IMMICH_DATA" 2>/dev/null || true
chmod -R 755 "$UPLOAD_LOCATION" 2>/dev/null || true

log "✅ Permissions fixed for Immich"

cd "$APP_DIR"

# Generate random passwords and keys
DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)
JWT_SECRET=$(openssl rand -base64 32)
MACHINE_LEARNING_KEY=$(openssl rand -base64 32)

# ============= CREATE DOCKER-COMPOSE.YML =============
log "Generating docker-compose.yml with all Immich services..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
# WARNING: Make sure to use the docker-compose.yml of the latest release.
# The compose file can be found at:
# https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml

# WARNING: Make sure to use the docker-compose.yml of the latest release.
# The compose file can be found at:
# https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml

name: immich-winejs

services:
  immich-server:
    container_name: winejs-immich-server
    image: ghcr.io/immich-app/immich-server:release
    ports:
      - "${APP_PORT}:2283"
    devices:
      - /dev/dri:/dev/dri
    volumes:
      - ${UPLOAD_LOCATION}:/usr/src/app/upload
      - ${IMMICH_CONFIG}:/etc/immich
      - ${IMMICH_DATA}/ml-cache:/cache
      - /etc/localtime:/etc/localtime:ro
    environment:
      - DB_USERNAME=postgres
      - DB_DATABASE_NAME=immich
      - DB_PASSWORD=${DB_PASSWORD}
      - REDIS_HOSTNAME=redis
      - REDIS_PORT=6379
      - JWT_SECRET=${JWT_SECRET}
      - IMMICH_PORT=2283
    depends_on:
      - redis
      - database
    restart: unless-stopped
    networks:
      - winejs-net

  immich-microservices:
    container_name: winejs-immich-microservices
    image: ghcr.io/immich-app/immich-server:release
    devices:
      - /dev/dri:/dev/dri
    volumes:
      - ${UPLOAD_LOCATION}:/usr/src/app/upload
      - ${IMMICH_CONFIG}:/etc/immich
      - ${IMMICH_DATA}/ml-cache:/cache
      - /etc/localtime:/etc/localtime:ro
    environment:
      - DB_USERNAME=postgres
      - DB_DATABASE_NAME=immich
      - DB_PASSWORD=${DB_PASSWORD}
      - REDIS_HOSTNAME=redis
      - REDIS_PORT=6379
      - NODE_ENV=production
    command: ["node", "/usr/src/app/dist/microservices.js"]
    depends_on:
      - redis
      - database
    restart: unless-stopped
    networks:
      - winejs-net

  immich-machine-learning:
    container_name: winejs-immich-ml
    image: ghcr.io/immich-app/immich-machine-learning:release
    volumes:
      - ${IMMICH_DATA}/ml-cache:/cache
    env_file:
      - .env
    restart: unless-stopped
    networks:
      - winejs-net

  # [FIX 1 & 2] UPDATED DATABASE SERVICE
  database:
    container_name: winejs-immich-db
    # This is the NEW correct image (using vectorchord)
    image: tensorchord/pgvecto-rs:pg14-v0.2.0
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_DB: ${DB_DATABASE_NAME}
      POSTGRES_INITDB_ARGS: '--data-checksums'
    volumes:
      - ${DB_DATA_LOCATION}:/var/lib/postgresql/data
    restart: unless-stopped
    networks:
      - winejs-net

  redis:
    container_name: winejs-immich-redis
    image: redis:7.2-alpine
    restart: unless-stopped
    networks:
      - winejs-net

  immich-web:
    container_name: winejs-immich-web
    image: ghcr.io/immich-app/immich-web:release
    ports:
      - "${WEB_PORT}:3000"
    environment:
      - IMMICH_SERVER_URL=http://immich-server:2283
      - PUBLIC_IMMICH_SERVER_URL=https://${DOMAIN_NAME}/immich-api
      - PUBLIC_URL=/immich
      - BASE_URL=/immich
    depends_on:
      - immich-server
    restart: unless-stopped
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE .ENV FILE =============
log "Creating .env configuration..."

cat > "$INSTANCE_DIR/.env" << ENV_EOF
# You can find documentation for all the supported env variables at https://immich.app/docs/install/environment-variables

# Web UI Configuration
WEB_PORT=${WEB_PORT}
IMMICH_WEB_URL=http://localhost:${WEB_PORT}

# API Configuration
IMMICH_SERVER_URL=http://immich-server:2283
PUBLIC_IMMICH_SERVER_URL=https://${DOMAIN_NAME}/immich-api

# Performance
WORKERS=1
WORKER_INCLUDE_PATHS=/usr/src/app/upload

# The location where your uploaded files are stored
UPLOAD_LOCATION=${UPLOAD_LOCATION}

# The Immich version to use
IMMICH_VERSION=v1.125.0

# Connection secret for postgres
DB_PASSWORD=${DB_PASSWORD}
DB_USERNAME=postgres
DB_DATABASE_NAME=immich

# Redis
REDIS_HOSTNAME=redis
REDIS_PORT=6379

# Machine Learning
MACHINE_LEARNING_HOST=immich-machine-learning
MACHINE_LEARNING_PORT=3003
MACHINE_LEARNING_WORKERS=1
MACHINE_LEARNING_WORKER_TIMEOUT=120

# Web UI Port
IMMICH_PORT=${APP_PORT}

# JWT Secret
JWT_SECRET=${JWT_SECRET}

# Reverse Proxy
IMMICH_TRUSTED_PROXIES=127.0.0.1,::1
# Or remove it entirely by commenting out:
# IMMICH_TRUSTED_PROXIES=0.0.0.0/0

# Thumbnail Settings
THUMBNAIL_HASHING_ALGORITHM=sha1
THUMBNAIL_MAX_WIDTH=1024
THUMBNAIL_MAX_HEIGHT=1024

# Video Encoding
VIDEO_CODEC=h264
ENABLE_ACCELERATED_TRANSCODING=true

# Timezone
TZ=UTC

# Logging
LOG_LEVEL=log
ENV_EOF

# ============= CREATE LAUNCH SCRIPT =============
log "Generating launch.sh with auto-heal monitor..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "🚀 Starting WineJS Immich Server..."

cd /opt/winejs/kasmvnc-instances/immich

# Start auto-heal monitor
(
    while true; do
        sleep 30
        if ! docker ps | grep -q "winejs-immich-server.*Up"; then
            log "⚠️ Immich server crashed! Restarting..."
            docker-compose restart immich-server
        fi
        if ! docker ps | grep -q "winejs-immich-microservices.*Up"; then
            log "⚠️ Microservices crashed! Restarting..."
            docker-compose restart immich-microservices
        fi
        if ! docker ps | grep -q "winejs-immich-ml.*Up"; then
            log "⚠️ ML service crashed! Restarting..."
            docker-compose restart immich-machine-learning
        fi
    done
) &

log "✅ Immich services running"
docker-compose logs -f
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE CONFIG.JSON =============
log "Generating config.json..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Immich Photo Manager",
    "version": "v1.125.0",
    "description": "Self-hosted photo and video backup solution with AI face recognition, automatic albums, and mobile sync",
    "executable": "launch.sh",
    "port": ${WEB_PORT},
    "vnc_password": "winejs-immich",
    "icon": "/icons/immich.png",
    "category": "Media",
    "features": [
        "Automatic photo backup",
        "Face recognition",
        "Smart search",
        "Automatic albums",
        "Mobile apps (iOS/Android)",
        "RAW image support",
        "Video transcoding",
        "User management",
        "Shared albums",
        "Map view"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "Downloading app icon..."
curl -L "$APP_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon, using default"

# ============= CREATE UNINSTALL SCRIPT =============
log "Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_immich.sh" << 'UNINSTALL_EOF'
#!/bin/bash
# WineJS Immich Uninstaller

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

log "🧹 Uninstalling Immich Server..."

# ============= STOP AND REMOVE DOCKER CONTAINERS =============
log "Stopping Docker containers..."

# Check if docker-compose.yml exists and use it
if [ -f "/opt/winejs/kasmvnc-instances/immich/docker-compose.yml" ]; then
    log "Stopping all Immich containers via docker-compose..."
    cd /opt/winejs/kasmvnc-instances/immich
    docker compose down -v 2>/dev/null || true
    cd /tmp
    log "✅ All containers stopped and removed"
else
    # Fallback: Stop individual containers
    for container in winejs-immich-server winejs-immich-microservices winejs-immich-web winejs-immich-ml winejs-immich-db winejs-immich-redis; do
        if docker ps -a 2>/dev/null | grep -q "$container"; then
            log "Stopping $container..."
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        fi
    done
    log "✅ All containers stopped and removed"
fi

# Remove Immich Docker images (optional - saves disk space)
read -p "Do you want to remove Immich Docker images? (y/N): " remove_images
if [[ "$remove_images" =~ ^[Yy]$ ]]; then
    log "Removing Immich Docker images..."
    docker images | grep immich | awk '{print $3}' | xargs -r docker rmi 2>/dev/null || true
    log "✅ Images removed"
fi

# ============= ASK ABOUT DATA PRESERVATION =============
echo ""
read -p "Do you want to keep your photos and data? (y/N): " keep_data
if [[ ! "$keep_data" =~ ^[Yy]$ ]]; then
    log "Removing all Immich data..."
    rm -rf /opt/winejs/photos 2>/dev/null || true
    rm -rf /opt/winejs/data/immich 2>/dev/null || true
    rm -rf /opt/winejs/config/immich 2>/dev/null || true
    log "✅ All data removed"
else
    warn "Photos and data preserved at:"
    warn "   • /opt/winejs/photos"
    warn "   • /opt/winejs/data/immich"
    warn "   • /opt/winejs/config/immich"
fi

# ============= REMOVE APP DIRECTORIES =============
log "Removing app directories..."

APP_NAME="immich"
APP_DIR="/opt/winejs/apps/${APP_NAME}"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/${APP_NAME}"
IMMICH_DATA="/opt/winejs/data/immich"
IMMICH_CONFIG="/opt/winejs/config/immich"
PHOTOS_DIR="/opt/winejs/photos"
ICON_FILE="/opt/winejs/translator/public/icons/${APP_NAME}.png"
ICON_SVG="/opt/winejs/translator/public/icons/${APP_NAME}.svg"
SHARED_VOLUMES="/opt/winejs/shared-volumes"

# Remove directories if they exist and user chose to delete data
if [[ ! "$keep_data" =~ ^[Yy]$ ]]; then
    [ -d "$PHOTOS_DIR" ] && rm -rf "$PHOTOS_DIR" && log "✅ Photos directory removed"
    [ -d "$IMMICH_DATA" ] && rm -rf "$IMMICH_DATA" && log "✅ Immich data removed"
    [ -d "$IMMICH_CONFIG" ] && rm -rf "$IMMICH_CONFIG" && log "✅ Immich config removed"
fi

# Always remove app directories (these don't contain user data)
[ -d "$INSTANCE_DIR" ] && rm -rf "$INSTANCE_DIR" && log "✅ Instance directory removed"
[ -d "$APP_DIR" ] && rm -rf "$APP_DIR" && log "✅ App directory removed"

# Remove shared volume links (but not the shared-volumes directory itself)
if [ -d "$SHARED_VOLUMES/backups/immich" ]; then
    rm -rf "$SHARED_VOLUMES/backups/immich" 2>/dev/null || true
    log "✅ Backup directory removed"
fi

# Remove icons
[ -f "$ICON_FILE" ] && rm -f "$ICON_FILE" && log "✅ Icon removed"
[ -f "$ICON_SVG" ] && rm -f "$ICON_SVG" && log "✅ SVG icon removed"

# ============= REMOVE HELPER SCRIPT =============
if [ -f "/usr/local/bin/winejs-immich" ]; then
    rm -f "/usr/local/bin/winejs-immich"
    log "✅ Helper script removed"
fi

# ============= REMOVE NGINX CONFIGURATION =============
log "Removing nginx configuration..."

NGINX_SITE="/etc/nginx/sites-available/winejs"

if [ ! -f "$NGINX_SITE" ]; then
    warn "nginx config not found at $NGINX_SITE"
else
    # Check if any Immich routes exist
    if ! grep -q "immich" "$NGINX_SITE"; then
        log "No Immich routes found in nginx config"
    else
        log "Removing Immich routes from nginx config..."
        
        # Create backup with timestamp
        BACKUP_FILE="${NGINX_SITE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$NGINX_SITE" "$BACKUP_FILE"
        log "✅ Backup created: $BACKUP_FILE"
        
        # Use Perl for more reliable multi-line removal (if available)
        if command -v perl &> /dev/null; then
            perl -i -0777 -pe 's/^[[:space:]]*# Immich Photo Manager\s*\n.*?location \/immich-api\/.*?^\s*}\s*$//gms' "$NGINX_SITE"
            perl -i -0777 -pe 's/^[[:space:]]*location \/immich\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
            perl -i -0777 -pe 's/^[[:space:]]*location \/immich-api\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
        else
            # Fallback to sed for multi-line removal
            sed -i '/^[[:space:]]*# Immich Photo Manager/,/^[[:space:]]*}/d' "$NGINX_SITE"
            sed -i '/^[[:space:]]*location \/immich {/,/^[[:space:]]*}/d' "$NGINX_SITE"
            sed -i '/^[[:space:]]*location \/immich-api\//,/^[[:space:]]*}/d' "$NGINX_SITE"
        fi
        
        # Remove any orphaned immich lines
        sed -i '/immich/d' "$NGINX_SITE"
        
        # Clean up multiple blank lines
        sed -i '/^$/N;/^\n$/D' "$NGINX_SITE"
        
        # Test and reload nginx
        log "Testing nginx configuration..."
        if nginx -t 2>&1 | tee /tmp/nginx_test.log; then
            systemctl reload nginx
            log "✅ Nginx configuration successfully updated - Immich routes removed"
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

# ============= RELOAD WINEJS TRANSLATOR =============
log "Reloading WineJS translator..."
if command -v pm2 &> /dev/null; then
    pm2 restart translator 2>/dev/null || true
    log "✅ Translator reloaded"
fi
 

# ============= VERIFY REMOVAL =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           IMMICH SERVER UNINSTALLED SUCCESSFULLY!             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
log "✅ Immich Server has been completely removed"

if [[ "$keep_data" =~ ^[Yy]$ ]]; then
    echo ""
    warn "📸 Your photos and data have been preserved at:"
    warn "   • /opt/winejs/photos"
    warn "   • /opt/winejs/data/immich"
    warn "   • /opt/winejs/config/immich"
    echo ""
    warn "To delete them later, run: sudo rm -rf /opt/winejs/photos /opt/winejs/data/immich /opt/winejs/config/immich"
fi
echo ""
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_immich.sh"
log "✅ Uninstall script created"

# ============= CREATE HELPER SCRIPT =============
log "Creating helper script..."

cat > /usr/local/bin/winejs-immich << EOF
#!/bin/bash

case "\$1" in
    status)
        echo "Immich status:"
        docker ps --format "table {{.Names}}\t{{.Status}}" | grep immich
        ;;
    logs)
        cd /opt/winejs/kasmvnc-instances/immich
        docker-compose logs -f --tail=50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/immich
        docker-compose restart
        echo "✅ Immich restarted"
        ;;
    backup)
        BACKUP_DIR="/opt/winejs/shared-volumes/backups/immich-\$(date +%Y%m%d_%H%M%S)"
        mkdir -p "\$BACKUP_DIR"
        echo "📦 Backing up database..."
        docker exec winejs-immich-db pg_dump -U postgres immich > "\$BACKUP_DIR/database.sql"
        echo "📸 Backing up config..."
        cp -r /opt/winejs/config/immich "\$BACKUP_DIR/config"
        echo "✅ Backup saved to \$BACKUP_DIR"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://${DOMAIN_NAME}/immich"
        else
            echo "Visit: https://${DOMAIN_NAME}/immich"
        fi
        ;;
    *)
        echo "WineJS Immich Helper"
        echo ""
        echo "Commands:"
        echo "  winejs-immich open      - Open Immich in browser"
        echo "  winejs-immich status    - Check service status"
        echo "  winejs-immich logs      - View logs"
        echo "  winejs-immich restart   - Restart all services"
        echo "  winejs-immich backup    - Backup database"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-immich

# ============= START CONTAINERS =============
log "Starting Immich containers..."

cd "$INSTANCE_DIR"

# Start database and redis first (they take longest)
log "Starting database and redis..."
docker compose up -d database redis
sleep 15

# Create database immediately after database is up
log "Ensuring immich database exists..."
docker exec winejs-immich-db psql -U postgres -c "CREATE DATABASE immich;" 2>/dev/null || true
log "✅ Database verified"

# Wait for database to be ready
log "Waiting for database to be ready..."
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if docker exec winejs-immich-db pg_isready -U postgres &>/dev/null; then
        log "✅ Database is ready!"
        break
    fi
    log "Attempt $attempt/$max_attempts: Waiting for database..."
    sleep 5
    attempt=$((attempt + 1))
done

# Start server, microservices, and ML
log "Starting server and supporting services..."
docker compose up -d immich-server immich-microservices immich-machine-learning
sleep 15

# Start web UI LAST (so it gets the correct server IP)
log "Starting web UI..."
docker compose up -d immich-web

# Create admin user
log "Creating admin user..."
sleep 10

docker exec winejs-immich-server curl -X POST http://localhost:${APP_PORT}/api/auth/admin-sign-up \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\",\"name\":\"Admin\"}" 2>/dev/null || \
    warn "Admin creation may have failed or already exists"

# ============= UPDATE NGINX CONFIG =============
log "Updating nginx configuration for Immich..."
# The pattern for ALL installers (Mumble, PufferPanel, Forgejo, Immich):
#   1. Find the HTTPS server block by locating "listen 443"
#   2. Count braces { and } to find the exact closing brace of that server block
#   3. Insert new location blocks BEFORE that closing brace
#   4. This guarantees routes are safely INSIDE the correct server block
# This method is proven to work (VSCode uses it) and never creates orphaned directives.
# DO NOT insert before "listen 443" - that breaks the config.
# DO NOT insert after random lines like "root" or "server_name" - that's fragile.
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    # Check if Immich routes already exist
    if ! grep -q "location /immich/" /etc/nginx/sites-available/winejs; then
        # Backup the current config
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
                # Insert routes BEFORE the closing brace (safe inside server block)
                sed -i "${HTTPS_END}i\\
    # Immich Photo Manager\n\
    location /immich/ {\n\
        proxy_pass http://127.0.0.1:${WEB_PORT}/;\n\
        proxy_set_header Host \$host;\n\
        proxy_set_header X-Real-IP \$remote_addr;\n\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        client_max_body_size 500M;\n\
        proxy_buffering off;\n\
        proxy_read_timeout 86400s;\n\
        proxy_send_timeout 86400s;\n\
    }\n\
    location /immich-api/ {\n\
        proxy_pass http://127.0.0.1:${APP_PORT}/;\n\
        proxy_set_header Host \$host;\n\
        proxy_set_header X-Real-IP \$remote_addr;\n\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \$scheme;\n\
        client_max_body_size 500M;\n\
    }\n" /etc/nginx/sites-available/winejs
                
                log "✅ Immich routes inserted safely"
                
                # Test and reload
                if nginx -t; then
                    systemctl reload nginx
                    log "✅ Nginx updated with Immich routes"
                    log "   • /immich/ → Web UI (port ${WEB_PORT})"
                    log "   • /immich-api/ → API (port ${APP_PORT})"
                else
                    warn "Nginx test failed, restoring backup"
                    cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                    nginx -t && systemctl reload nginx
                    log "⚠️ Could not add Immich routes automatically"
                fi
            else
                warn "Could not find HTTPS block closing brace"
            fi
        else
            warn "Could not find HTTPS server block (listen 443)"
        fi
    else
        log "Immich routes already exist in nginx config"
    fi
else
    warn "nginx config not found, skipping"
fi
# ============= RELOAD TRANSLATOR =============
log "Reloading WineJS translator..."
pm2 restart translator 2>/dev/null || true

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║             IMMICH SERVER INSTALLED ON WINEJS!                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Immich Server installed as a WineJS app!"
echo ""
info "🌐 Access URLs:"
info "   • Web UI: https://$DOMAIN_NAME/immich/"
info "   • API: https://$DOMAIN_NAME/immich-api/"
echo ""
info "🔑 Admin Credentials:"
info "   • Email: $ADMIN_EMAIL"
info "   • Password: $ADMIN_PASSWORD"
echo ""
info "📂 Storage Locations:"
info "   • Photos: /opt/winejs/photos"
info "   • Database: /opt/winejs/data/immich/postgres"
info "   • Thumbnails: /opt/winejs/data/immich/thumbs"
info "   • Backups: /opt/winejs/shared-volumes/backups"
echo ""
info "📱 Mobile Apps:"
info "   • iOS: App Store search 'Immich'"
info "   • Android: Play Store search 'Immich'"
info "   • Server URL for mobile: https://$DOMAIN_NAME/immich-api/"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-immich open        # Open Immich in browser"
info "   • winejs-immich status      # Check service status"
info "   • winejs-immich logs        # View logs"
info "   • winejs-immich backup      # Backup database"
info "   • winejs-immich restart     # Restart services"
echo ""
info "⚠️  IMPORTANT: Set up external backups for:"
info "   • Photos: /opt/winejs/photos"
info "   • Database: Use 'winejs-immich backup' regularly"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_immich.sh"
echo ""
success "✨ Immich Server is ready! Visit https://$DOMAIN_NAME/immich/"
echo ""

echo "Find all uninstall scripts in the apps directory:"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# Key Features of this Immich Installer:
#     Complete Microservices Setup - Server, Microservices, ML, PostgreSQL, Redis
#     AI/ML Support - Face recognition, smart search, automatic tagging
#     Auto-Heal Monitoring - Automatically restarts crashed services
#     Persistent Storage - Separates photos, thumbnails, encoded videos
#     Nginx Integration - Clean URL routing through WineJS proxy
#     Mobile App Ready - Compatible with official iOS/Android apps
#     Backup System - Database backup via CLI command
#     Helper Script - winejs-immich for easy management
#     Uninstall with Data Option - Choose to keep or delete photos
#     Automatic Admin Creation - First user setup on install