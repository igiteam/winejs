#!/bin/bash
# ============================================
# CommaFeed RSS Reader - WineJS Installer
# Adds Self-Hosted RSS Reader to WineJS Platform
# ============================================
# App: CommaFeed
# Category: Productivity
# Features: RSS Aggregator, Feed Reader, News Aggregation
# ============================================

COMMAFEED_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/commafeed-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📰 Installing WineJS CommaFeed RSS Reader..."

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

# ============= ASK FOR COMMAFEED CONFIGURATION =============
echo ""
info "📝 CommaFeed Configuration"
echo "================================"
read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

read -p "Database type (h2/postgresql/mysql/mariadb) [h2]: " DB_TYPE
DB_TYPE=${DB_TYPE:-"h2"}

if [ "$DB_TYPE" != "h2" ]; then
    read -p "Database host: " DB_HOST
    read -p "Database port: " DB_PORT
    read -p "Database name: " DB_NAME
    read -p "Database user: " DB_USER
    read -s -p "Database password: " DB_PASS
    echo ""
fi

read -p "Enable push notifications? (true/false) [false]: " PUSH_ENABLED
PUSH_ENABLED=${PUSH_ENABLED:-false}

# Generate session encryption key
ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=8700  # Start after ChiefOnboarding's range (8600+)
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

# Find available port for CommaFeed
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for CommaFeed"
fi

log "Using port: CommaFeed=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="commafeed"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/commafeed"
DATA_DIR="/opt/winejs/data/commafeed"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{data,config}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/commafeed"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= BUILD DOCKER-COMPOSE BASED ON DB TYPE =============
log "📝 Creating docker-compose.yml..."

# Start with base services
cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # CommaFeed Application
  winejs-commafeed:
    image: athou/commafeed:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:8082"
    volumes:
      - ${DATA_DIR}/data:/app/data
      - ${DATA_DIR}/config:/app/config
    environment:
      - QUARKUS_HTTP_AUTH_SESSION_ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - QUARKUS_DATASOURCE_JDBC_URL=jdbc:${DB_TYPE}://${DB_HOST:-localhost}:${DB_PORT:-5432}/${DB_NAME:-commafeed}
      - QUARKUS_DATASOURCE_USERNAME=${DB_USER:-sa}
      - QUARKUS_DATASOURCE_PASSWORD=${DB_PASS:-}
      - COMMAFEED_ADMIN_EMAIL=${ADMIN_EMAIL}
DOCKER_EOF

# Add database service if not using H2
if [ "$DB_TYPE" = "postgresql" ]; then
    cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF

  # PostgreSQL Database
  postgres:
    image: postgres:15
    container_name: winejs-commafeed-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${DB_NAME:-commafeed}
      POSTGRES_USER: ${DB_USER:-postgres}
      POSTGRES_PASSWORD: ${DB_PASS:-postgres}
    volumes:
      - ${DATA_DIR}/db:/var/lib/postgresql/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-postgres}"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  winejs-net:
    external: true
DOCKER_EOF
elif [ "$DB_TYPE" = "mysql" ] || [ "$DB_TYPE" = "mariadb" ]; then
    cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF

  # MariaDB/MySQL Database
  db:
    image: mariadb:11
    container_name: winejs-commafeed-db
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: ${DB_NAME:-commafeed}
      MYSQL_USER: ${DB_USER:-commafeed}
      MYSQL_PASSWORD: ${DB_PASS:-commafeed}
      MYSQL_ROOT_PASSWORD: ${DB_PASS:-rootpassword}
    volumes:
      - ${DATA_DIR}/db:/var/lib/mysql
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  winejs-net:
    external: true
DOCKER_EOF
else
    # H2 - add just the network
    cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF

networks:
  winejs-net:
    external: true
DOCKER_EOF
fi

# Add push notification support if enabled
if [ "$PUSH_ENABLED" = "true" ]; then
    cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF

  # Redis for push notifications
  redis:
    image: redis:7-alpine
    container_name: winejs-commafeed-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - winejs-net
DOCKER_EOF
    
    # Add Redis env to CommaFeed
    sed -i '/environment:/a\      - QUARKUS_REDIS_HOSTS=redis://redis:6379' "$INSTANCE_DIR/docker-compose.yml"
fi

# ============= START CONTAINERS =============
log "🚀 Starting CommaFeed containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for CommaFeed to initialize..."
sleep 20

# Create admin user via API or database
log "🔐 Setting up admin user..."

# For H2, we need to wait for the database to initialize
sleep 10

# Create admin user using curl (if API is available)
MAX_ATTEMPTS=30
for i in $(seq 1 $MAX_ATTEMPTS); do
    if curl -s -f "http://127.0.0.1:${APP_PORT}/rest/health" >/dev/null 2>&1; then
        log "✅ CommaFeed is ready"
        
        # Try to register admin user
        curl -X POST "http://127.0.0.1:${APP_PORT}/rest/user/register" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\",\"admin\":true}" 2>/dev/null || true
        break
    fi
    if [ $i -eq $MAX_ATTEMPTS ]; then
        warn "Could not create admin user automatically. Please create manually."
    fi
    sleep 2
done

log "✅ CommaFeed initialized"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "CommaFeed RSS Reader",
    "version": "latest",
    "description": "Google Reader inspired self-hosted RSS feed reader with modern features",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/commafeed.png",
    "category": "Productivity",
    "features": [
        "📰 RSS/Atom Feed Reader",
        "🎨 4 Different Layouts",
        "🌙 Light/Dark Theme",
        "📱 Fully Responsive",
        "⌨️ Keyboard Shortcuts",
        "🌍 Right-to-Left Support",
        "🗣️ 25+ Languages",
        "📥 OPML Import/Export",
        "🔔 Push Notifications",
        "📊 Auto-mark Rules",
        "🎨 Custom CSS/JS",
        "🔌 Fever-compatible API",
        "🚀 Fast & Lightweight"
    ]
}
CONF_EOF

# ============= CREATE FEED GUIDE =============
log "📝 Creating feed guide..."

cat > "$APP_DIR/feed-guide.md" << GUIDE_EOF
# CommaFeed RSS Reader - Feed Guide

## Access
- **Main Reader**: https://$DOMAIN_NAME/rss/
- **Login**: Use the email and password you set during installation

## Adding Your First Feed

1. Login to CommaFeed
2. Click "Add Feed" in the sidebar
3. Enter the RSS/Atom feed URL
4. Click "Subscribe"
5. New articles will appear in your feed!

## Popular RSS Feeds to Add

### Tech News
- **Hacker News**: https://news.ycombinator.com/rss
- **TechCrunch**: https://feeds.feedburner.com/TechCrunch
- **The Verge**: https://www.theverge.com/rss/index.xml
- **Ars Technica**: https://feeds.arstechnica.com/arstechnica/index

### Open Source
- **GitHub Blog**: https://github.blog/feed/
- **GitLab Blog**: https://about.gitlab.com/atom.xml
- **Docker Blog**: https://www.docker.com/blog/feed/
- **Kubernetes Blog**: https://kubernetes.io/feed.xml

### Self-Hosting
- **Self-Hosted Show**: https://selfhosted.show/feed
- **LinuxServer.io**: https://blog.linuxserver.io/rss/
- **Awesome Self-Hosted**: https://github.com/awesome-selfhosted/awesome-selfhosted/commits/master.atom

### Your Own WineJS Apps
- **Forgejo**: https://$DOMAIN_NAME/git/username/project/feeds/rss
- **Artalk**: https://$DOMAIN_NAME/artalk/feed
- **Castopod**: https://$DOMAIN_NAME/castopod/feed

## OPML Import

Import feeds from other readers:
1. Export OPML from your current reader
2. In CommaFeed, go to Settings → Import
3. Upload the OPML file
4. All your feeds will be imported!

## Organizing Feeds

### Categories
- Create folders for different topics
- Drag and drop feeds into categories
- Collapse categories you don't need

### Keyboard Shortcuts
- `n` - Next article
- `p` - Previous article
- `v` - Open original article
- `s` - Star article
- `m` - Mark as read
- `r` - Refresh feed
- `?` - Show all shortcuts

## Filters & Auto-Mark

### Create Rules
1. Go to Settings → Auto-mark Rules
2. Add conditions (title contains, feed equals)
3. Choose action (mark as read, star, delete)
4. Great for newsletters or noisy feeds

## Push Notifications

$([ "$PUSH_ENABLED" = "true" ] && echo "Push notifications are ENABLED. You'll receive browser notifications when new articles arrive in your feeds." || echo "Push notifications are DISABLED. To enable, reconfigure with Redis support.")

## Fever API

Use your favorite RSS mobile app:
- **API Endpoint**: https://$DOMAIN_NAME/rss/fever
- **Username**: Your email
- **Password**: Your password

Supported apps:
- Reeder
- Unread
- Fiery Feeds
- Many more...

## Customization

### Themes
- Light mode (default)
- Dark mode (for night reading)
- Auto-switch based on system settings

### Layouts
1. **Classic** - Google Reader style
2. **Magazine** - Card-based layout
3. **Article List** - Compact view
4. **Full Width** - Article-focused

### Custom CSS
Add your own CSS in Settings → Custom CSS
\`\`\`css
/* Example: larger fonts */
.article-content {
    font-size: 18px;
    line-height: 1.6;
}
\`\`\`

## Keyboard Ninja Mode

Master CommaFeed without touching your mouse:
- `g h` - Go to Home
- `g a` - Go to All feeds
- `g s` - Go to Starred
- `shift + a` - Mark all as read
- `shift + n` - Next feed

## Integrations

### With Changedetection
Monitor websites without RSS feeds:
1. Set up a watch in Changedetection
2. Get RSS feed output
3. Add to CommaFeed

### With n8n
Automate your reading:
1. Trigger on new articles
2. Send to Slack/Discord
3. Archive important articles
4. Create summaries with AI

## Database

Current database: **$DB_TYPE**

$([ "$DB_TYPE" = "h2" ] && echo "Using embedded H2 database - fine for personal use up to a few hundred feeds. For larger deployments, consider PostgreSQL.")
$([ "$DB_TYPE" = "postgresql" ] && echo "Using PostgreSQL - great for large deployments with thousands of feeds and multiple users.")
$([ "$DB_TYPE" = "mysql" ] || [ "$DB_TYPE" = "mariadb" ] && echo "Using MySQL/MariaDB - good performance for medium to large deployments.")

## Mobile Apps

Use Fever-compatible apps:
- **iOS**: Reeder, Unread, Fiery Feeds
- **Android**: News+ (add RSS Fever plugin)
- **Web**: PWA - install to home screen

## Backup & Restore

### Export OPML
Settings → Export → Download OPML

### Backup Database
\`\`\`bash
cd /opt/winejs/data/commafeed
zip -r backup_$(date +%Y%m%d).zip data/ db/
\`\`\`

## Commands

\`\`\`bash
# View logs
winejs-commafeed logs

# Restart services
winejs-commafeed restart

# Check status
winejs-commafeed status

# Open reader
winejs-commafeed open
\`\`\`
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up CommaFeed icon..."

if curl -L "$COMMAFEED_LOGO_URL" -o "$ICON_DIR/commafeed.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/commafeed.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M4 11a9 9 0 0 1 9 9"/>
  <path d="M4 4a16 16 0 0 1 16 16"/>
  <circle cx="5" cy="19" r="1"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-commafeed << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/commafeed && docker compose ps
        ;;
    logs)
        docker logs winejs-commafeed --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/commafeed && docker compose restart
        echo "CommaFeed restarted"
        ;;
    feeds)
        echo "📰 Your feeds are available at:"
        echo "  https://\${DOMAIN_NAME}/rss/"
        ;;
    import)
        echo "📥 To import feeds from OPML:"
        echo "  1. Login to CommaFeed"
        echo "  2. Go to Settings → Import"
        echo "  3. Upload your OPML file"
        ;;
    export)
        echo "📤 To export feeds as OPML:"
        echo "  1. Login to CommaFeed"
        echo "  2. Go to Settings → Export"
        echo "  3. Download the OPML file"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/rss/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/rss/"
        fi
        ;;
    *)
        echo "CommaFeed RSS Reader Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-commafeed open           - Open RSS Reader"
        echo "  winejs-commafeed status         - Check status"
        echo "  winejs-commafeed logs           - View logs"
        echo "  winejs-commafeed restart        - Restart services"
        echo "  winejs-commafeed feeds          - Show feeds info"
        echo "  winejs-commafeed import         - Import OPML guide"
        echo "  winejs-commafeed export         - Export OPML guide"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/rss/"
        echo ""
        echo "Login: $ADMIN_EMAIL / (password you set)"
        echo ""
        echo "Database Type: $DB_TYPE"
        echo ""
        echo "Feed Guide: cat /opt/winejs/apps/commafeed/feed-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-commafeed

# ============= UPDATE NGINX FOR COMMAFEED =============
log "📝 Setting up nginx reverse proxy for CommaFeed..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /rss" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # CommaFeed RSS Reader\n\
    location /rss {\n\
        rewrite ^/rss(/.*)?$ /\\\$1 break;\n\
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
    }\n\
    \n\
    # CommaFeed REST API\n\
    location /rss/rest/ {\n\
        rewrite ^/rss/rest/(.*)$ /rest/\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with CommaFeed routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_commafeed.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling CommaFeed..."

cd /opt/winejs/kasmvnc-instances/commafeed
docker compose down -v 2>/dev/null

rm -rf /opt/winejs/apps/commafeed
rm -rf /opt/winejs/kasmvnc-instances/commafeed
rm -rf /opt/winejs/data/commafeed

rm -f /usr/local/bin/winejs-commafeed

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# CommaFeed RSS Reader/,/location \/rss\/rest\//d' /etc/nginx/sites-available/winejs
    sed -i '/location \/rss {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ CommaFeed uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_commafeed.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              COMMAFEED INSTALLED ON WINEJS!                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ CommaFeed RSS Reader installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/rss/"
echo ""
info "🔐 Login:"
info "   • Email: $ADMIN_EMAIL"
info "   • Password: [the password you set]"
echo ""
info "📰 Key Features:"
info "   • RSS/Atom feed aggregation"
info "   • 4 different layouts"
info "   • Light/Dark themes"
info "   • Keyboard shortcuts"
info "   • OPML import/export"
info "   • Auto-mark rules"
if [ "$PUSH_ENABLED" = "true" ]; then
    info "   • Push notifications ✓"
fi
echo ""
info "🗄️ Database:"
info "   • Type: $DB_TYPE"
info "   • Location: ${DATA_DIR}"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-commafeed open        # Open RSS reader"
info "   • winejs-commafeed status      # Check status"
info "   • winejs-commafeed logs        # View logs"
info "   • winejs-commafeed import      # OPML import guide"
info "   • winejs-commafeed export      # OPML export guide"
echo ""
info "📁 Data Directory:"
info "   • ${DATA_DIR}"
echo ""
info "📚 Feed Guide:"
info "   • cat /opt/winejs/apps/commafeed/feed-guide.md"
echo ""
info "📱 Mobile Apps:"
info "   • iOS: Reeder, Unread (Fever API compatible)"
info "   • Android: News+ with RSS Fever plugin"
info "   • PWA: Install to home screen"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_commafeed.sh"
echo ""
success "✨ CommaFeed is ready! Start reading RSS feeds at https://$DOMAIN_NAME/rss/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What CommaFeed Does:

# CommaFeed is a Google Reader-inspired RSS feed reader:
# Key Features:
#     RSS/Atom Aggregation - Subscribe to any RSS/Atom feed
#     4 Layouts - Classic, Magazine, Article List, Full Width
#     Dark/Light Themes - Easy on the eyes day or night
#     Keyboard Shortcuts - Browse feeds without a mouse
#     OPML Import/Export - Move feeds in/out easily
#     Auto-mark Rules - Automatically mark articles as read
#     Push Notifications - Get alerts for new articles
#     Fever API - Use with mobile RSS apps
#     25+ Languages - International support
#     Custom CSS/JS - Personalize the experience

# Perfect For:
#     News Junkies - Follow all your news sources in one place
#     Researchers - Track academic journals and blogs
#     Content Curators - Monitor industry trends
#     WineJS Users - Add RSS feeds from all your WineJS apps!