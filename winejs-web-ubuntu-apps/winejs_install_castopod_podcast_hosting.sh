#!/bin/bash
# ============================================
# Castopod Podcast Hosting - WineJS Installer
# Adds Podcast Hosting Platform to WineJS
# ============================================
# App: Castopod
# Category: Media
# Features: Podcast Hosting, Fediverse Integration, Analytics
# ============================================

CASTOPOD_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/castopod-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🎙️ Installing WineJS Castopod Podcast Platform..."

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

# ============= ASK FOR CASTOPOD CONFIGURATION =============
echo ""
info "📝 Castopod Configuration"
echo "================================"
read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password (min 8 chars): " ADMIN_PASSWORD
echo ""
read -p "Admin username: " ADMIN_USERNAME
read -p "Podcast name [WineJS Podcast]: " PODCAST_NAME
PODCAST_NAME=${PODCAST_NAME:-"WineJS Podcast"}

# Generate secure salts and passwords
ANALYTICS_SALT=$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/' | head -c 24)
MYSQL_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/' | head -c 24)
REDIS_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/' | head -c 24)

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=8300  # Start after Cal.diy's range (8200+)
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

# Find available port for Castopod
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Castopod"
fi

log "Using port: Castopod=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="castopod"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/castopod"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{media,db,redis,logs}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/castopod"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # MariaDB Database
  mariadb:
    image: mariadb:12.1
    container_name: winejs-castopod-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: castopod
      MYSQL_USER: castopod
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    volumes:
      - ${DATA_DIR}/db:/var/lib/mysql
    networks:
      - castopod-db
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      start_period: 10s
      interval: 10s
      timeout: 5s
      retries: 3

  # Redis Cache
  redis:
    image: redis:8.4-alpine
    container_name: winejs-castopod-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - castopod-app

  # Castopod Application
  winejs-castopod:
    image: castopod/castopod:1
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    volumes:
      - ${DATA_DIR}/media:/app/public/media
    environment:
      # Database
      MYSQL_DATABASE: castopod
      MYSQL_USER: castopod
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      CP_DATABASE_HOSTNAME: mariadb
      # Base URL
      CP_BASEURL: "https://${DOMAIN_NAME}/castopod"
      # Analytics
      CP_ANALYTICS_SALT: ${ANALYTICS_SALT}
      # Cache
      CP_CACHE_HANDLER: redis
      CP_REDIS_HOST: redis
      CP_REDIS_PASSWORD: ${REDIS_PASSWORD}
      CP_REDIS_PORT: 6379
      # Email (using console for now)
      CP_EMAIL_FROM: noreply@${DOMAIN_NAME}
      CP_EMAIL_SMTP_HOST: localhost
      CP_EMAIL_SMTP_PORT: 25
      # Admin gateway
      CP_ADMIN_GATEWAY: cp-admin
      CP_AUTH_GATEWAY: cp-auth
      # Security
      CP_DISABLE_HTTPS: 0
      # PHP Settings
      PHP_MEMORY_LIMIT: 512M
      PHP_UPLOAD_MAX_FILE_SIZE: 512M
      PHP_POST_MAX_SIZE: 512M
      PHP_MAX_EXECUTION_TIME: 300
      PHP_OPCACHE_ENABLE: 1
    networks:
      - castopod-app
      - castopod-db
    ports:
      - "127.0.0.1:${APP_PORT}:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    depends_on:
      mariadb:
        condition: service_healthy
      redis:
        condition: service_started

networks:
  castopod-app:
    driver: bridge
  castopod-db:
    driver: bridge
    internal: true
DOCKER_EOF

# ============= RUN THE SETUP WIZARD =============
log "🚀 Starting Castopod containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Castopod to initialize (this may take 1-2 minutes)..."
sleep 60

# Run database migrations and setup via CLI
log "🔧 Configuring Castopod..."

# Create .env file in container
docker exec winejs-castopod bash -c "cat > /app/.env << 'EOF'
CI_ENVIRONMENT = production
app.baseURL = 'https://${DOMAIN_NAME}/castopod/'
database.default.hostname = mariadb
database.default.database = castopod
database.default.username = castopod
database.default.password = ${MYSQL_PASSWORD}
database.default.DBDriver = MySQLi
cache.handler = redis
cache.redis.host = redis
cache.redis.password = ${REDIS_PASSWORD}
cache.redis.port = 6379
EOF" 2>/dev/null

# Run spark commands to initialize
docker exec winejs-castopod php spark install:init-database 2>/dev/null || true
docker exec winejs-castopod php spark install:create-superadmin << EOF
${ADMIN_USERNAME}
${ADMIN_EMAIL}
${ADMIN_PASSWORD}
${ADMIN_PASSWORD}
Admin User
EOF

docker exec winejs-castopod php spark cache:clear 2>/dev/null || true

log "✅ Castopod configured"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Castopod Podcast Hosting",
    "version": "latest",
    "description": "Free & open-source podcast hosting platform with Fediverse integration",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/castopod.png",
    "category": "Media",
    "features": [
        "🎙️ Podcast Hosting & Management",
        "🌐 Fediverse Integration (ActivityPub)",
        "📊 Built-in Analytics (GDPR compliant)",
        "💬 Social Interaction (posts, comments, favorites)",
        "🎬 Video Clip Generation",
        "🔊 Soundbite Generation",
        "📱 Progressive Web App (PWA)",
        "🎨 Customizable Themes",
        "📡 Podcasting 2.0 Features",
        "💰 Monetization Tools",
        "👥 Multi-user & Roles",
        "🔗 RSS Feed Generation",
        "📥 Podcast Import/Export",
        "🔄 WebSub Broadcasting"
    ]
}
CONF_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Castopod icon..."

# Try to download the icon, fallback to a placeholder if it fails
if curl -L "$CASTOPOD_LOGO_URL" -o "$ICON_DIR/castopod.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon from $CASTOPOD_LOGO_URL"
    info "Creating a simple placeholder icon instead..."
    
    # Create a simple SVG icon as fallback
    cat > "$ICON_DIR/castopod.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"/>
  <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
  <line x1="12" y1="19" x2="12" y2="22"/>
</svg>
SVG_EOF
    
    # Convert SVG to PNG using convert if available
    if command -v convert &>/dev/null; then
        convert "$ICON_DIR/castopod.svg" "$ICON_DIR/castopod.png" 2>/dev/null || true
    else
        # Copy a default icon if SVG conversion fails
        cp /opt/winejs/translator/public/icons/default-app.png "$ICON_DIR/castopod.png" 2>/dev/null || true
    fi
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-castopod << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
ADMIN_USERNAME="${ADMIN_USERNAME}"
PODCAST_NAME="${PODCAST_NAME}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/castopod && docker compose ps
        ;;
    logs)
        docker logs winejs-castopod --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/castopod && docker compose restart
        echo "Castopod restarted"
        ;;
    cache-clear)
        echo "🗑️ Clearing cache..."
        docker exec winejs-castopod php spark cache:clear
        ;;
    db-migrate)
        echo "🔄 Running database migrations..."
        docker exec winejs-castopod php spark migrate
        ;;
    create-user)
        echo "👤 Creating new user..."
        docker exec -it winejs-castopod php spark install:create-superadmin
        ;;
    ffmpeg-check)
        echo "🎬 Checking FFmpeg availability:"
        docker exec winejs-castopod ffmpeg -version 2>/dev/null | head -n1 || echo "FFmpeg not available"
        ;;
    media)
        echo "📁 Media directory: /opt/winejs/data/castopod/media"
        echo "Size: \$(du -sh /opt/winejs/data/castopod/media 2>/dev/null | cut -f1 || echo '0')"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/castopod/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/castopod/"
        fi
        ;;
    admin)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/castopod/cp-admin/"
        else
            echo "Admin: https://\${DOMAIN_NAME}/castopod/cp-admin/"
        fi
        ;;
    *)
        echo "Castopod Podcast Hosting Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-castopod open           - Open Castopod"
        echo "  winejs-castopod admin          - Open Admin Panel"
        echo "  winejs-castopod status         - Check status"
        echo "  winejs-castopod logs           - View logs"
        echo "  winejs-castopod restart        - Restart services"
        echo "  winejs-castopod cache-clear    - Clear cache"
        echo "  winejs-castopod db-migrate     - Run migrations"
        echo "  winejs-castopod create-user    - Create superadmin"
        echo "  winejs-castopod ffmpeg-check   - Check FFmpeg"
        echo "  winejs-castopod media          - Show media info"
        echo ""
        echo "Access URLs:"
        echo "  • Main Site: https://\${DOMAIN_NAME}/castopod/"
        echo "  • Admin: https://\${DOMAIN_NAME}/castopod/cp-admin/"
        echo ""
        echo "Admin Login: $ADMIN_USERNAME / (password you set)"
        echo ""
        echo "Quick Start:"
        echo "  1. Login with admin credentials"
        echo "  2. Click 'Create a Podcast'"
        echo "  3. Fill in podcast details"
        echo "  4. Upload your first episode"
        echo "  5. Share your RSS feed!"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-castopod

# ============= UPDATE NGINX FOR CASTOPOD =============
log "📝 Setting up nginx reverse proxy for Castopod..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /castopod" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Castopod Podcast Hosting\n\
    location /castopod {\n\
        rewrite ^/castopod(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 86400;\n\
        client_max_body_size 512M;\n\
        proxy_buffering off;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Castopod routes"
            else
                warn "Nginx test failed, restoring backup"
                cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                nginx -t && systemctl reload nginx
            fi
        fi
    fi
fi

# ============= SETUP CRONJOBS =============
log "⏰ Setting up cron jobs for background tasks..."

# Add cron job for Castopod background tasks
(crontab -l 2>/dev/null | grep -v "castopod tasks:run" || true; 
 echo "* * * * * /usr/bin/docker exec winejs-castopod php spark tasks:run >> /var/log/castopod-cron.log 2>&1") | crontab -

# ============= RESTART TRANSLATOR =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_castopod.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Castopod..."

cd /opt/winejs/kasmvnc-instances/castopod
docker compose down -v 2>/dev/null

rm -rf /opt/winejs/apps/castopod
rm -rf /opt/winejs/kasmvnc-instances/castopod
rm -rf /opt/winejs/data/castopod

rm -f /usr/local/bin/winejs-castopod

# Remove cronjobs
crontab -l 2>/dev/null | grep -v "castopod tasks:run" | crontab - 2>/dev/null || true

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Castopod Podcast Hosting/,/location \/castopod/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/castopod {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Castopod uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_castopod.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              CASTOPOD INSTALLED ON WINEJS!                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Castopod Podcast Hosting installed!"
echo ""
info "🌐 Access URLs:"
info "   • Main Site: https://$DOMAIN_NAME/castopod/"
info "   • Admin Panel: https://$DOMAIN_NAME/castopod/cp-admin/"
echo ""
info "🔐 Admin Login:"
info "   • Username: $ADMIN_USERNAME"
info "   • Password: [the password you set]"
info "   • Email: $ADMIN_EMAIL"
echo ""
info "🎙️ Podcast Features:"
info "   • Podcast hosting with RSS feed"
info "   • Fediverse integration (ActivityPub)"
info "   • Built-in analytics"
info "   • Video clip & soundbite generation"
info "   • Podcasting 2.0 ready"
echo ""
info "🔑 Generated Credentials (Save these):"
info "   • Analytics Salt: $ANALYTICS_SALT"
info "   • MySQL Root Password: $MYSQL_ROOT_PASSWORD"
info "   • Redis Password: $REDIS_PASSWORD"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-castopod open        # Open Castopod"
info "   • winejs-castopod admin       # Open Admin Panel"
info "   • winejs-castopod status      # Check status"
info "   • winejs-castopod logs        # View logs"
info "   • winejs-castopod cache-clear # Clear cache"
info "   • winejs-castopod media       # Show media directory"
info "   • winejs-castopod create-user # Add new admin"
echo ""
info "📁 Data Directories:"
info "   • Media: ${DATA_DIR}/media"
info "   • Database: ${DATA_DIR}/db"
info "   • Cache: ${DATA_DIR}/redis"
echo ""
info "📚 Quick Start:"
info "   1. Login to admin panel"
info "   2. Click 'Create a Podcast'"
info "   3. Fill in your podcast details"
info "   4. Upload your first episode"
info "   5. Share your RSS feed with directories!"
echo ""
info "📡 RSS Feed URL:"
info "   • https://$DOMAIN_NAME/castopod/podcast/[podcast-slug]/feed"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_castopod.sh"
echo ""
success "✨ Castopod is ready! Start podcasting at https://$DOMAIN_NAME/castopod/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Castopod Does:

# Castopod is a free & open-source podcast hosting platform with Fediverse integration:
# Key Features:
#     Podcast Hosting - Host unlimited podcasts on one instance
#     Fediverse Integration - Built-in social network (ActivityPub)
#     Analytics - GDPR-compliant, on-premises analytics (no third parties)
#     Podcasting 2.0 - Transcripts, chapters, funding, transcripts, locations
#     Video Clips - Generate shareable video clips from episodes
#     Soundbites - Create audio snippets for promotion
#     RSS Feed - Automatic RSS generation for all directories
#     Monetization - Funding links, value4value, premium episodes
#     Multi-user - Add contributors with different roles
#     PWA - Install as a standalone app

# Perfect For:
#     Podcasters - Host your own podcast without third parties
#     Media Companies - Multi-podcast support
#     Fans - Interact with favorite podcasts via Fediverse
#     WineJS itself - Launch your own podcast!