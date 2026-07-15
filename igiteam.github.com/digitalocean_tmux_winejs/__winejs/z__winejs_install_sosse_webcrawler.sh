#!/bin/bash
# ============================================
# Sosse Web Crawler & Search Engine - WineJS Installer
# Adds Web Crawling & Search to WineJS Platform
# ============================================
# App: Sosse
# Category: Productivity
# Features: Web Crawling, Search Engine, Document Indexing
# ============================================

APP_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/sosse-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🕷️ Installing WineJS Sosse Web Crawler..."

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

# ============= ASK FOR SOSSE CONFIGURATION =============
echo ""
info "📝 Sosse Configuration"
echo "================================"
read -p "Admin username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-"admin"}
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

read -p "Database password: " DB_PASSWORD
read -p "Secret key (generate with: openssl rand -base64 32): " SECRET_KEY

read -p "Enable anonymous search? (true/false) [false]: " ANON_SEARCH
ANON_SEARCH=${ANON_SEARCH:-false}

read -p "Crawler count (parallel crawlers) [2]: " CRAWLER_COUNT
CRAWLER_COUNT=${CRAWLER_COUNT:-2}

read -p "Default browser (chromium/firefox) [chromium]: " DEFAULT_BROWSER
DEFAULT_BROWSER=${DEFAULT_BROWSER:-"chromium"}

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=9900  # Start after Screego's range (9800+)
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

# Find available port for Sosse
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Sosse"
fi

log "Using port: Sosse=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="sosse"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/sosse"
DATA_DIR="/opt/winejs/data/sosse"
CONFIG_DIR="/opt/winejs/config/sosse"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{postgres,var,log,static,screenshots,html,downloads,browser_config}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/sosse"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE Sosse CONFIGURATION =============
log "📝 Creating Sosse configuration..."

cat > "$CONFIG_DIR/sosse.conf" << EOF
[common]
secret_key = ${SECRET_KEY}
debug = False
db_name = sosse
db_user = sosse
db_pass = ${DB_PASSWORD}
db_host = postgres
db_port = 5432

[webserver]
anonymous_search = ${ANON_SEARCH}
search_shortcut_char = !
default_search_redirect = 
online_search_redirect = 
online_check_url = https://google.com/
online_check_timeout = 1.0
online_check_cache = 10
allowed_host = ${DOMAIN_NAME}
static_url = /static/
static_root = /var/lib/sosse/static/
screenshots_url = /screenshots/
screenshots_dir = /var/lib/sosse/screenshots/
scripts_dir = /var/lib/sosse/scripts/
html_snapshot_url = /snap/
html_snapshot_dir = /var/lib/sosse/html/
use_i18n = True
use_l10n = True
language_code = en-us
datetime_format = N j, Y, P
use_tz = True
timezone = UTC
default_page_size = 20
max_page_size = 200
data_upload_max_memory_size = 2621440
data_upload_max_number_fields = 1000
atom_feed_size = 200
csv_export = True
csv_export_size = 200
exclude_not_indexed = True
exclude_redirect = True
archive_follows_redirect = True
admin_page_size = 100
crawl_status_autorefresh = 5
browsable_home = True
links_no_referrer = True
links_new_tab = False
home_search_history_size = 3

[crawler]
crawler_count = ${CRAWLER_COUNT}
proxy = 
user_agent = Sosse
fake_user_agent_browser = 
fake_user_agent_os = 
fake_user_agent_platform = 
requests_timeout = 10
fail_over_lang = english
hashing_algo = md5
screenshots_size = 1920x1080
default_browser = ${DEFAULT_BROWSER}
chromium_options = --enable-precise-memory-info --disable-default-apps --headless --no-sandbox --disable-dev-shm-usage
firefox_options = --headless
js_stable_time = 0.1
js_stable_retry = 100
tmp_dl_dir = /var/lib/sosse/downloads
browser_config_dir = /var/lib/sosse/browser_config
dl_check_time = 0.1
dl_check_retry = 2
max_file_size = 1000000
max_html_asset_size = 50000
max_redirects = 5
browser_idle_exit_time = 5
browser_crash_sleep = 1.0
browser_crash_retry = 1
css_parser = internal
worker_crash_retry = 1
EOF

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # PostgreSQL Database
  postgres:
    image: postgres:15
    container_name: winejs-sosse-db
    restart: unless-stopped
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: sosse
      POSTGRES_USER: sosse
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sosse"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Sosse Web Crawler & Search Engine
  winejs-sosse:
    image: biolds/sosse:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:80"
    volumes:
      - ${DATA_DIR}/var:/var/lib/sosse
      - ${DATA_DIR}/log:/var/log/sosse
      - ${CONFIG_DIR}:/etc/sosse:ro
    environment:
      - SOSSE_DB_HOST=postgres
      - SOSSE_DB_PASS=${DB_PASSWORD}
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= INITIALIZE DATABASE =============
log "🚀 Starting Sosse containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Sosse to initialize (this may take 1-2 minutes)..."
sleep 45

# Check if container is running
if ! docker ps | grep -q "winejs-${APP_NAME}"; then
    error "Sosse container failed to start. Check logs with: docker logs winejs-${APP_NAME}"
fi

# Initialize database - using the correct commands for Sosse
log "🔧 Initializing database..."

# Try different possible command locations
if docker exec winejs-${APP_NAME} which sosse-admin &>/dev/null; then
    # sosse-admin is in PATH
    docker exec winejs-${APP_NAME} sosse-admin migrate 2>/dev/null || true
    docker exec winejs-${APP_NAME} sosse-admin update_se 2>/dev/null || true
    docker exec winejs-${APP_NAME} sosse-admin update_mime 2>/dev/null || true
elif docker exec winejs-${APP_NAME} test -f /app/manage.py &>/dev/null; then
    # Using Django manage.py directly
    docker exec winejs-${APP_NAME} python3 /app/manage.py migrate 2>/dev/null || true
elif docker exec winejs-${APP_NAME} test -f /usr/local/bin/sosse-admin &>/dev/null; then
    # Using full path
    docker exec winejs-${APP_NAME} /usr/local/bin/sosse-admin migrate 2>/dev/null || true
    docker exec winejs-${APP_NAME} /usr/local/bin/sosse-admin update_se 2>/dev/null || true
    docker exec winejs-${APP_NAME} /usr/local/bin/sosse-admin update_mime 2>/dev/null || true
else
    warn "Could not find sosse-admin command. Trying Django directly..."
    # Try to find manage.py
    MANAGE_PATH=$(docker exec winejs-${APP_NAME} find / -name "manage.py" 2>/dev/null | head -1)
    if [ -n "$MANAGE_PATH" ]; then
        docker exec winejs-${APP_NAME} python3 "$MANAGE_PATH" migrate 2>/dev/null || true
    else
        warn "Could not initialize database automatically"
    fi
fi

# Create admin user - using Django shell which is more reliable
log "👤 Creating admin user..."

# Method 1: Try using createsuperuser command
if docker exec winejs-${APP_NAME} python3 /app/manage.py createsuperuser --noinput --username ${ADMIN_USER} --email admin@example.com 2>/dev/null; then
    # Set password using shell
    docker exec winejs-${APP_NAME} python3 /app/manage.py shell << PYTHON_EOF
from django.contrib.auth import get_user_model
User = get_user_model()
try:
    user = User.objects.get(username='${ADMIN_USER}')
    user.set_password('${ADMIN_PASSWORD}')
    user.is_superuser = True
    user.is_staff = True
    user.save()
    print(f"✅ Password set for user: ${ADMIN_USER}")
except Exception as e:
    print(f"Error: {e}")
PYTHON_EOF
else
    # Method 2: Direct shell approach
    docker exec winejs-${APP_NAME} python3 -c "
from django.contrib.auth import get_user_model
User = get_user_model()
try:
    user = User.objects.create_superuser('${ADMIN_USER}', 'admin@example.com', '${ADMIN_PASSWORD}')
    print(f'✅ Superuser created: ${ADMIN_USER}')
except Exception as e:
    print(f'User may already exist: {e}')
    try:
        user = User.objects.get(username='${ADMIN_USER}')
        user.set_password('${ADMIN_PASSWORD}')
        user.is_superuser = True
        user.is_staff = True
        user.save()
        print(f'✅ Password updated for: ${ADMIN_USER}')
    except:
        pass
" 2>/dev/null || true
fi

log "✅ Sosse initialization complete"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Sosse Web Crawler & Search",
    "version": "latest",
    "description": "Self-hosted web crawler and search engine for indexing and searching websites",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/sosse.png",
    "category": "Productivity",
    "features": [
        "🕷️ Web Crawling",
        "🔍 Full-Text Search",
        "📸 Page Screenshots",
        "📄 HTML Snapshots",
        "⏱️ Adaptive Recrawling",
        "🔐 Authenticated Crawling",
        "🏷️ Document Tagging",
        "📊 Search Analytics",
        "⚡ Collections & Rules",
        "🌐 Multi-Browser Support",
        "📱 Mobile Responsive",
        "🔌 Atom/RSS Feeds"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << GUIDE_EOF
# Sosse Web Crawler & Search Engine - User Guide

## Access
- **Web Interface**: https://$DOMAIN_NAME/search/
- **Admin Interface**: https://$DOMAIN_NAME/search/admin

## Admin Login
- **Username**: $ADMIN_USER
- **Password**: [the password you set]

## Getting Started

### 1. Configure a Collection

Collections define crawling rules:

1. Login to admin interface
2. Click **⚡ Collections**
3. Create new collection or modify default
4. Set URL patterns to crawl
5. Configure crawl frequency

**URL Patterns Explained**:
- **Unlimited depth regex**: Crawled without depth limits
- **Limited depth regex**: Crawled with depth limits
- **Excluded URL regex**: Never crawled

### 2. Add URLs to Crawl

**Method 1 - Manual Add**:
1. Go to **🌐 Crawl a new URL**
2. Enter URL
3. Select collection
4. Click "Add and Crawl"

**Method 2 - Import**:
1. Import URLs from file
2. One URL per line
3. Bulk add to collection

### 3. Monitor Crawling

**Crawl Queue**:
- View pending URLs
- Monitor progress
- Check for errors

**Crawlers Status**:
- Active crawler count: $CRAWLER_COUNT
- Current tasks
- Success/failure rates

### 4. Search Your Index

**Basic Search**:
- Enter search terms
- Filter by tag
- Sort by relevance/date

**Advanced Search**:
- Use quotes for exact phrase
- AND/OR operators
- Site: restrict to domain
- Tag: filter by tag

## Collection Configuration

### Crawl Settings

**Recrawl Frequency**:
- **Once**: No automatic recrawling
- **Constant**: Recrawl every X minutes
- **Adaptive**: Adjust based on change frequency

**Change Detection**:
- Raw content comparison
- Normalize numbers (ignore counters)
- Screenshot comparison

### Browser Settings

**Default Browse Mode**:
- **Detect**: Auto-detect dynamic vs static
- **Chromium**: Use Chrome/Chromium
- **Firefox**: Use Firefox
- **Requests**: Fast, no JavaScript

**Script Execution**:
Run JavaScript before indexing:
\`\`\`javascript
// Handle authentication
const button = document.evaluate(
  "//button[contains(text(), 'Accept')]",
  document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null
).singleNodeValue;
if (button) button.click();
\`\`\`

### Archive Settings

**Archive Content**:
- Save HTML snapshots
- Download assets (CSS, images)
- Take screenshots

**Asset Filters**:
- Exclude by URL regex
- Exclude by mime type
- Skip large files

### Authentication

Configure form-based authentication:
1. Set **Login URL regex**
2. Specify **Form selector**
3. Define authentication fields
4. Crawler will auto-login

## Search Features

### Search Shortcuts

**Default shortcut character**: !
- Use in search box for quick searching
- Example: \`!query\` searches with shortcut

**Online Fallback**:
- When internet available, fallback to external search
- Configurable online check URL

### Atom Feeds

Subscribe to search results:
\`\`\`
https://$DOMAIN_NAME/search/feed/?q=search+terms
\`\`\`

**Options**:
- Format: Atom
- Size: configurable (default 200)
- Token authentication available

### CSV Export

Export search results:
- CSV format
- Up to 200 results
- All metadata included

## Document Management

### Tags

**Auto-tagging**:
- Define tags in collection
- Automatically applied
- Filter search by tag

**Manual Tagging**:
- Edit document settings
- Add/remove tags
- Bulk tag operations

**Hidden Documents**:
- Hide from search results
- Still tracked in database
- Can be re-enabled

### Document Details

**Metadata**:
- Title, description
- Last crawl time
- Change history
- Screenshots

**URL Management**:
- Canonical URLs
- Redirect handling
- Parameter indexing

## Crawler Optimization

### Performance Tips

**Crawler Count** ($CRAWLER_COUNT):
- Higher = faster but more resource intensive
- Lower = gentler on target servers

**Recrawl Strategy**:
- Adaptive for dynamic sites
- Constant for stable content
- Once for archived content

**Robots.txt Respect**:
- Sosse respects robots.txt
- Configurable crawl delays
- Rate limiting

### Resource Usage

**Storage**:
- Database: Metadata
- Snapshots: HTML, images
- Screenshots: PNG/JPG

**Memory**:
- Browser instances
- Cache settings
- Queue size

## Integration with WineJS Apps

### With Changedetection
- Use Sosse to crawl, Changedetection to monitor
- Schedule regular crawls

### With ArchiveBox
- Sosse finds content, ArchiveBox archives it
- Complementary tools

### With Paperless-ngx
- Crawl document repositories
- Index searchable content

### With n8n
- Trigger workflows on new documents
- Process crawled data
- Send notifications

## Troubleshooting

### Crawling Issues

**Pages not indexing**:
- Check robots.txt
- Verify collection regex
- Check browser console

**Authentication fails**:
- Verify login URL regex
- Check form selectors
- Enable debug logging

**High resource usage**:
- Reduce crawler count
- Increase crawl delays
- Limit concurrent browsers

### Search Issues

**Results not appearing**:
- Wait for indexing
- Check excluded status
- Verify tags

**Outdated results**:
- Adjust recrawl frequency
- Force manual recrawl
- Check change detection

## Commands

\`\`\`bash
# View logs
winejs-sosse logs

# Restart services
winejs-sosse restart

# Check status
winejs-sosse status

# Manual crawl
docker exec winejs-sosse sosse-admin crawl

# Update search index
docker exec winejs-sosse sosse-admin update_se

# Run migrations
docker exec winejs-sosse sosse-admin migrate

# Open interface
winejs-sosse open
\`\`\`

## Performance Monitoring

**Metrics to Watch**:
- Queue size (should stay low)
- Crawler success rate (>90%)
- Database size growth
- Snapshot storage

**Log Locations**:
- Crawler: \`/var/log/sosse/crawler.log\`
- Web server: \`/var/log/sosse/webserver.log\`
- Debug: \`/var/log/sosse/debug.log\`

## Security

**Authentication**:
$([ "$ANON_SEARCH" = "true" ] && echo "- Anonymous search enabled" || echo "- Login required for search")

**Best Practices**:
- Use strong passwords
- Regular backups
- Monitor crawl targets
- Respect website terms

## Support

- **GitHub**: https://github.com/biolds/sosse
- **Documentation**: https://sosse.readthedocs.io
- **Discord**: Join community
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Sosse icon..."
curl -L "$APP_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-sosse << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
ADMIN_USER="${ADMIN_USER}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/sosse && docker compose ps
        ;;
    logs)
        docker logs winejs-sosse --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/sosse && docker compose restart
        echo "Sosse restarted"
        ;;
    crawl)
        echo "🕷️ Starting manual crawl..."
        docker exec winejs-sosse sosse-admin crawl
        ;;
    queue)
        echo "📋 Crawl queue status:"
        docker exec winejs-sosse python3 manage.py shell -c "from sosse.models import Page; print(f'Pending: {Page.objects.filter(crawl__gt=0).count()}')"
        ;;
    migrate)
        echo "🔄 Running migrations..."
        docker exec winejs-sosse sosse-admin migrate
        docker exec winejs-sosse sosse-admin update_se
        docker exec winejs-sosse sosse-admin update_mime
        ;;
    stats)
        echo "📊 Index statistics:"
        docker exec winejs-sosse python3 manage.py shell -c "from sosse.models import Page; print(f'Total pages: {Page.objects.count()}')"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/search/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/search/"
        fi
        ;;
    admin)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/search/admin"
        else
            echo "Admin: https://\${DOMAIN_NAME}/search/admin"
        fi
        ;;
    *)
        echo "Sosse Web Crawler & Search Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-sosse open           # Open search"
        echo "  winejs-sosse admin          # Open admin"
        echo "  winejs-sosse status         # Check status"
        echo "  winejs-sosse logs           # View logs"
        echo "  winejs-sosse restart        # Restart"
        echo "  winejs-sosse crawl          # Manual crawl"
        echo "  winejs-sosse queue          # View queue"
        echo "  winejs-sosse migrate        # Run migrations"
        echo "  winejs-sosse stats          # Index statistics"
        echo ""
        echo "Access URLs:"
        echo "  • Search: https://\${DOMAIN_NAME}/search/"
        echo "  • Admin: https://\${DOMAIN_NAME}/search/admin"
        echo ""
        echo "Admin Login: $ADMIN_USER / (password you set)"
        echo ""
        echo "Crawler Count: $CRAWLER_COUNT"
        echo "Default Browser: $DEFAULT_BROWSER"
        echo "Anonymous Search: $ANON_SEARCH"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/sosse/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-sosse

# ============= UPDATE NGINX FOR SOSSE =============
log "📝 Setting up nginx reverse proxy for Sosse..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /search" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Sosse Web Crawler & Search\n\
    location /search {\n\
        rewrite ^/search(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 300s;\n\
        proxy_buffering off;\n\
        client_max_body_size 100M;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Sosse routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_sosse.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Sosse..."

cd /opt/winejs/kasmvnc-instances/sosse
docker compose down -v 2>/dev/null

# Ask about removing data
read -p "Remove all crawled data and indexes? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /opt/winejs/apps/sosse
    rm -rf /opt/winejs/kasmvnc-instances/sosse
    rm -rf /opt/winejs/data/sosse
    rm -rf /opt/winejs/config/sosse
    log "✅ All data removed"
else
    rm -rf /opt/winejs/apps/sosse
    rm -rf /opt/winejs/kasmvnc-instances/sosse
    rm -rf /opt/winejs/config/sosse
fi

rm -f /usr/local/bin/winejs-sosse

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Sosse Web Crawler & Search/,/location \/search/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/search {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Sosse uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_sosse.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                SOSSE INSTALLED ON WINEJS!                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Sosse Web Crawler & Search Engine installed!"
echo ""
info "🌐 Access URLs:"
info "   • Search: https://$DOMAIN_NAME/search/"
info "   • Admin: https://$DOMAIN_NAME/search/admin"
echo ""
info "🔐 Admin Login:"
info "   • Username: $ADMIN_USER"
info "   • Password: [the password you set]"
echo ""
info "⚙️ Configuration:"
info "   • Crawler Count: $CRAWLER_COUNT"
info "   • Default Browser: $DEFAULT_BROWSER"
info "   • Anonymous Search: $ANON_SEARCH"
echo ""
info "🕷️ Features:"
info "   • Web crawling with browser support"
info "   • Full-text search across crawled content"
info "   • Page screenshots and HTML snapshots"
info "   • Adaptive recrawling based on changes"
info "   • Tag-based document organization"
info "   • Atom/RSS feeds for search results"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-sosse open           # Open search"
info "   • winejs-sosse admin          # Open admin"
info "   • winejs-sosse status         # Check status"
info "   • winejs-sosse logs           # View logs"
info "   • winejs-sosse crawl          # Manual crawl"
info "   • winejs-sosse queue          # View queue"
info "   • winejs-sosse stats          # Index statistics"
info "   • winejs-sosse migrate        # Run migrations"
echo ""
info "📁 Data Directories:"
info "   • Database: ${DATA_DIR}/postgres"
info "   • Snapshots: ${DATA_DIR}/var/html"
info "   • Screenshots: ${DATA_DIR}/var/screenshots"
info "   • Logs: ${DATA_DIR}/log"
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/sosse/user-guide.md"
echo ""
info "🔍 Getting Started:"
info "   1. Login to admin panel"
info "   2. Configure a collection with URL patterns"
info "   3. Add URLs to crawl"
info "   4. Wait for crawling to complete"
info "   5. Search your indexed content!"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_sosse.sh"
echo ""
success "✨ Sosse is ready! Start crawling and searching at https://$DOMAIN_NAME/search/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Sosse Does:

# Sosse is a self-hosted web crawler and search engine - index and search websites:
# Key Features:
#     Web Crawling - Crawl websites with browser or HTTP requests
#     Full-Text Search - Search indexed content
#     Page Screenshots - Visual snapshots of pages
#     HTML Snapshots - Offline page archives
#     Adaptive Recrawling - Adjust frequency based on changes
#     Tag Management - Organize documents by tags
#     Collections - Define crawling rules per site
#     Authentication - Crawl behind login forms
#     Atom Feeds - Subscribe to search results
#     CSV Export - Export search results

# Crawling Modes:
# Mode	Speed	JS Support	Use Case
# Requests	Fast	No	Static sites
# Chromium	Slower	Yes	Dynamic sites, Single-page apps
# Firefox	Slower	Yes	Dynamic sites
# Detect	Adaptive	Auto	Mixed content

# Perfect For:
#     Personal Search - Index bookmarked sites
#     Intranets - Company document search
#     Documentation - Index technical docs
#     Research - Crawl and search academic sites
#     Monitoring - Track content changes