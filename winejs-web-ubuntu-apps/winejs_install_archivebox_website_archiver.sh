#!/bin/bash
# ============================================
# ArchiveBox Internet Archiver - WineJS Installer
# Adds Web Archiving Tool to WineJS Platform
# ============================================
# App: ArchiveBox
# Category: Productivity
# Features: Web Archiving, URL Snapshots, Offline Browsing
# ============================================

ARCHIVEBOX_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/archivebox-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📦 Installing WineJS ArchiveBox Internet Archiver..."

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

# ============= ASK FOR ARCHIVEBOX CONFIGURATION =============
echo ""
info "📝 ArchiveBox Configuration"
echo "================================"
read -p "Admin username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-"admin"}
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""
read -p "Admin email: " ADMIN_EMAIL

read -p "Archive title [WineJS Archive]: " ARCHIVE_TITLE
ARCHIVE_TITLE=${ARCHIVE_TITLE:-"WineJS Archive"}

read -p "Enable public snapshot viewing? (true/false) [false]: " PUBLIC_SNAPSHOTS
PUBLIC_SNAPSHOTS=${PUBLIC_SNAPSHOTS:-false}

read -p "Archive methods (comma-separated: wget,chrome,singlefile,dom,media) [wget,chrome,singlefile]: " ARCHIVE_METHODS
ARCHIVE_METHODS=${ARCHIVE_METHODS:-"wget,chrome,singlefile"}

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=7600  # Start after Svix's range (7500+)
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

# Find available port for ArchiveBox
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for ArchiveBox"
fi

log "Using port: ArchiveBox=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="archivebox"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/archivebox"
ARCHIVE_DIR="$DATA_DIR/archive"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ARCHIVE_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/archivebox"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # ArchiveBox Web Archiver
  winejs-archivebox:
    image: archivebox/archivebox:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:8000"
    volumes:
      - ${ARCHIVE_DIR}:/data
    environment:
      - USE_COLOR=True
      - SHOW_PROGRESS=True
      - TIMEOUT=60
      - CHECK_SSL_VALIDITY=True
      - SAVE_WGET=True
      - SAVE_WARC=True
      - SAVE_PDF=True
      - SAVE_SCREENSHOT=True
      - SAVE_DOM=True
      - SAVE_SINGLEFILE=True
      - SAVE_MEDIA=True
      - SAVE_READABILITY=True
      - SAVE_MERCURY=True
      - WGET_AUTO_COMPRESSION=True
      - WGET_RESTRICT_FILE_NAMES=unix
      - SUBMIT_ARCHIVE_DOT_ORG=False
      - ARCHIVE_METHODS=${ARCHIVE_METHODS}
      - PUBLIC_SNAPSHOTS=${PUBLIC_SNAPSHOTS}
      - PUBLIC_INDEX=True
      - PUBLIC_ADD_VIEW=False
      - SEARCH_BACKEND_ENGINE=sonic
      - ONLY_NEW=False
      - RESOLUTION=1440,900
      - CHROME_HEADLESS=True
      - CHROME_DEFAULT_LAUNCH_ARGS=--window-size=1440,900,--disable-save-password-bubble,--disable-features=PasswordImport
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= INITIALIZE ARCHIVEBOX =============
log "📦 Initializing ArchiveBox..."

# Create admin user and initialize archive
docker run --rm -v "$ARCHIVE_DIR:/data" archivebox/archivebox init --setup 2>/dev/null || true

# Set admin credentials if provided
if [ -n "$ADMIN_PASSWORD" ]; then
    # Create admin user via Docker
    docker run --rm -v "$ARCHIVE_DIR:/data" archivebox/archivebox manage createsuperuser \
        --username "$ADMIN_USER" \
        --email "$ADMIN_EMAIL" \
        --noinput 2>/dev/null || true
    
    # Set password (using echoing into Django's command)
    echo "from django.contrib.auth import get_user_model; User = get_user_model(); user = User.objects.get(username='$ADMIN_USER'); user.set_password('$ADMIN_PASSWORD'); user.save()" | \
        docker run --rm -i -v "$ARCHIVE_DIR:/data" archivebox/archivebox manage shell 2>/dev/null || true
fi

# Set archive title
echo "from core.models import Snapshot; from django.conf import settings; settings.ARCHIVEBOX_TITLE = '$ARCHIVE_TITLE'" | \
    docker run --rm -i -v "$ARCHIVE_DIR:/data" archivebox/archivebox manage shell 2>/dev/null || true

log "✅ ArchiveBox initialized"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

# Build methods list for features
METHODS_LIST=""
if [[ "$ARCHIVE_METHODS" == *"wget"* ]]; then
    METHODS_LIST="$METHODS_LIST\n        \"📥 WGET HTML & WARC\","
fi
if [[ "$ARCHIVE_METHODS" == *"chrome"* ]]; then
    METHODS_LIST="$METHODS_LIST\n        \"🌐 Chrome PDF & Screenshot\","
fi
if [[ "$ARCHIVE_METHODS" == *"singlefile"* ]]; then
    METHODS_LIST="$METHODS_LIST\n        \"📄 SingleFile HTML\","
fi
if [[ "$ARCHIVE_METHODS" == *"dom"* ]]; then
    METHODS_LIST="$METHODS_LIST\n        \"🏠 DOM Snapshot\","
fi
if [[ "$ARCHIVE_METHODS" == *"media"* ]]; then
    METHODS_LIST="$METHODS_LIST\n        \"🎬 Media Downloader\","
fi

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "ArchiveBox Internet Archiver",
    "version": "latest",
    "description": "Self-hosted internet archiving tool - save webpages, links, and content for offline access",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/archivebox.png",
    "category": "Productivity",
    "features": [
        "📦 Web Page Archiving",
        "🔍 Full-Text Search",${METHODS_LIST}
        "📚 Multi-Format Snapshots",
        "🏷️ Tag Organization",
        "📊 Archive Statistics",
        "🔒 Password Protection",
        "📱 Mobile Interface",
        "📥 Import from Pocket, Pinboard, Reddit",
        "🔄 Scheduled Archiving",
        "💾 WARC Format Support"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading ArchiveBox icon..."
curl -L "$ARCHIVEBOX_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-archivebox << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
ARCHIVE_DIR="${ARCHIVE_DIR}"
ADMIN_USER="${ADMIN_USER}"

case "\$1" in
    status)
        docker ps | grep winejs-archivebox
        ;;
    logs)
        docker logs winejs-archivebox --tail 50
        ;;
    restart)
        docker restart winejs-archivebox
        echo "ArchiveBox restarted"
        ;;
    add)
        shift
        if [ $# -eq 0 ]; then
            echo "Usage: winejs-archivebox add <url>"
            echo "Example: winejs-archivebox add https://example.com"
        else
            docker exec winejs-archivebox archivebox add "\$@"
        fi
        ;;
    add-file)
        echo "📄 Add URLs from file (one URL per line):"
        echo "  docker exec -i winejs-archivebox archivebox add < urls.txt"
        ;;
    list)
        docker exec winejs-archivebox archivebox list
        ;;
    stats)
        docker exec winejs-archivebox archivebox status
        ;;
    update)
        docker exec winejs-archivebox archivebox update
        ;;
    schedule)
        echo "⏰ To set up scheduled archiving, add to crontab:"
        echo "  0 2 * * * docker exec winejs-archivebox archivebox update"
        ;;
    export)
        echo "📦 Export formats:"
        echo "  HTML: docker exec winejs-archivebox archivebox list --html > archive.html"
        echo "  JSON: docker exec winejs-archivebox archivebox list --json > archive.json"
        echo "  CSV:  docker exec winejs-archivebox archivebox list --csv > archive.csv"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/archivebox/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/archivebox/"
        fi
        ;;
    *)
        echo "ArchiveBox Internet Archiver Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-archivebox open           - Open ArchiveBox UI"
        echo "  winejs-archivebox status         - Check status"
        echo "  winejs-archivebox logs           - View logs"
        echo "  winejs-archivebox restart        - Restart"
        echo "  winejs-archivebox add <url>      - Archive a URL"
        echo "  winejs-archivebox add-file       - Add URLs from file"
        echo "  winejs-archivebox list           - List archived URLs"
        echo "  winejs-archivebox stats          - Show archive statistics"
        echo "  winejs-archivebox update         - Update archives"
        echo "  winejs-archivebox schedule       - Setup auto-archiving"
        echo "  winejs-archivebox export         - Export archive data"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/archivebox/"
        echo "Login: ${ADMIN_USER} / (password you set)"
        echo ""
        echo "Archive Directory: $ARCHIVE_DIR"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-archivebox

# ============= START CONTAINER =============
log "🚀 Starting ArchiveBox container..."

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

# ============= ADD EXAMPLE URLs =============
log "📝 Adding example URLs to archive..."

cat > /tmp/example_urls.txt << EOF
https://news.ycombinator.com
https://en.wikipedia.org/wiki/Web_archiving
https://archive.org
EOF

cat /tmp/example_urls.txt | docker exec -i winejs-archivebox archivebox add 2>/dev/null || true
rm /tmp/example_urls.txt

log "✅ Example URLs added"

# ============= UPDATE NGINX FOR ARCHIVEBOX =============
log "📝 Setting up nginx reverse proxy for ArchiveBox..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /archivebox" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # ArchiveBox Internet Archiver\n\
    location /archivebox {\n\
        rewrite ^/archivebox(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 86400;\n\
        client_max_body_size 100M;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with ArchiveBox routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_archivebox.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling ArchiveBox..."

docker stop winejs-archivebox 2>/dev/null
docker rm winejs-archivebox 2>/dev/null

rm -rf /opt/winejs/apps/archivebox
rm -rf /opt/winejs/kasmvnc-instances/archivebox
rm -rf /opt/winejs/data/archivebox

rm -f /usr/local/bin/winejs-archivebox

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# ArchiveBox Internet Archiver/,/location \/archivebox/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/archivebox {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ ArchiveBox uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_archivebox.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ARCHIVEBOX INSTALLED ON WINEJS!                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ ArchiveBox Internet Archiver installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/archivebox/"
echo ""
info "🔐 Login:"
info "   • Username: $ADMIN_USER"
info "   • Password: [the password you set]"
echo ""
info "📦 Archive Methods:"
IFS=',' read -ra METHODS <<< "$ARCHIVE_METHODS"
for method in "${METHODS[@]}"; do
    case "$method" in
        "wget") info "   • WGET: HTML + WARC format" ;;
        "chrome") info "   • Chrome: PDF + Screenshot" ;;
        "singlefile") info "   • SingleFile: Single HTML file" ;;
        "dom") info "   • DOM: DOM snapshot" ;;
        "media") info "   • Media: Download videos/audio" ;;
    esac
done
echo ""
info "📊 Current Archive:"
info "   • $(docker exec winejs-archivebox archivebox status 2>/dev/null | grep -o '[0-9]\+ snapshots' || echo '0 snapshots')"
info "   • Archive Directory: $ARCHIVE_DIR"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-archivebox open        # Open ArchiveBox"
info "   • winejs-archivebox add <url>   # Archive a URL"
info "   • winejs-archivebox list        # List archived URLs"
info "   • winejs-archivebox stats       # Show statistics"
info "   • winejs-archivebox update      # Update archives"
info "   • winejs-archivebox schedule    # Setup auto-archiving"
info "   • winejs-archivebox export      # Export archive data"
echo ""
info "📥 Import from Services:"
info "   • Pocket: https://getpocket.com/export"
info "   • Pinboard: https://pinboard.in/export/"
info "   • Reddit: https://www.reddit.com/saved/"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_archivebox.sh"
echo ""
success "✨ ArchiveBox is ready! Start saving webpages at https://$DOMAIN_NAME/archivebox/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What ArchiveBox Does:

# ArchiveBox saves webpages and content for offline access - like a personal Wayback Machine:
# Key Features:

#     Multiple Archive Methods - WGET, Chrome PDF, Screenshot, SingleFile, DOM, Media
#     Import from Services - Pocket, Pinboard, Reddit, Bookmarks, History
#     Full-Text Search - Find content in archived pages
#     Tag Organization - Categorize and filter archives
#     Scheduled Archiving - Auto-update archived pages
#     Export Formats - HTML, JSON, CSV, WARC

# Perfect For:
#     Saving important articles before they disappear
#     Research documentation - Keep copies of sources
#     Legal/compliance - Archive communications
#     Personal knowledge base - Collect and search content