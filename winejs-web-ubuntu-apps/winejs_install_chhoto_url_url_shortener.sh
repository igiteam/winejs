#!/bin/bash
# ============================================
# Chhoto URL Shortener - WineJS Installer
# Adds Lightweight URL Shortener to WineJS Platform
# ============================================
# App: Chhoto URL
# Category: Productivity
# Features: URL Shortening, QR Codes, Hit Counting, API Support
# ============================================

CHHOTO_URL_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/chhoto-url-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🔗 Installing WineJS Chhoto URL Shortener..."

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

# ============= ASK FOR CHHOTO URL CONFIGURATION =============
echo ""
info "📝 Chhoto URL Configuration"
echo "================================"
read -s -p "Admin password (min 8 chars): " ADMIN_PASSWORD
echo ""
read -p "Site URL [https://${DOMAIN_NAME}/short]: " SITE_URL
SITE_URL=${SITE_URL:-"https://${DOMAIN_NAME}/short"}

# Generate API key
API_KEY=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)

read -p "Enable public mode (anyone can add links)? (true/false) [false]: " PUBLIC_MODE
PUBLIC_MODE=${PUBLIC_MODE:-false}

read -p "Slug style (pair/uid) [pair]: " SLUG_STYLE
SLUG_STYLE=${SLUG_STYLE:-"pair"}

if [ "$SLUG_STYLE" = "uid" ]; then
    read -p "Slug length [6]: " SLUG_LENGTH
    SLUG_LENGTH=${SLUG_LENGTH:-6}
fi

read -p "Redirect method (TEMPORARY/PERMANENT) [PERMANENT]: " REDIRECT_METHOD
REDIRECT_METHOD=${REDIRECT_METHOD:-"PERMANENT"}

read -p "Allow capital letters in slugs? (true/false) [false]: " ALLOW_CAPITALS
ALLOW_CAPITALS=${ALLOW_CAPITALS:-false}

read -p "Enable WAL mode for better performance? (true/false) [true]: " WAL_MODE
WAL_MODE=${WAL_MODE:-true}

# Set expiry for public mode if enabled
if [ "$PUBLIC_MODE" = "true" ]; then
    read -p "Public link expiry delay (seconds, 0=never) [86400]: " PUBLIC_EXPIRY
    PUBLIC_EXPIRY=${PUBLIC_EXPIRY:-86400}
fi

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=8500  # Start after Changedetection's range (8400+)
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

# Find available port for Chhoto URL
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Chhoto URL"
fi

log "Using port: Chhoto URL=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="chhoto-url"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/chhoto-url"
DATA_DIR="/opt/winejs/data/chhoto-url"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/chhoto-url"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

# Build environment variables
ENV_VARS=""
ENV_VARS="$ENV_VARS\n      - CHHOTO_PASSWORD=${ADMIN_PASSWORD}"
ENV_VARS="$ENV_VARS\n      - CHHOTO_API_KEY=${API_KEY}"
ENV_VARS="$ENV_VARS\n      - CHHOTO_SITE_URL=${SITE_URL}"
ENV_VARS="$ENV_VARS\n      - CHHOTO_REDIRECT_METHOD=${REDIRECT_METHOD}"
ENV_VARS="$ENV_VARS\n      - CHHOTO_SLUG_STYLE=${SLUG_STYLE}"
if [ "$SLUG_STYLE" = "uid" ] && [ -n "$SLUG_LENGTH" ]; then
    ENV_VARS="$ENV_VARS\n      - CHHOTO_SLUG_LENGTH=${SLUG_LENGTH}"
fi
if [ "$ALLOW_CAPITALS" = "true" ]; then
    ENV_VARS="$ENV_VARS\n      - CHHOTO_ALLOW_CAPITAL_LETTERS=True"
fi
if [ "$PUBLIC_MODE" = "true" ]; then
    ENV_VARS="$ENV_VARS\n      - CHHOTO_PUBLIC_MODE=Enable"
    if [ -n "$PUBLIC_EXPIRY" ] && [ "$PUBLIC_EXPIRY" != "0" ]; then
        ENV_VARS="$ENV_VARS\n      - CHHOTO_PUBLIC_MODE_EXPIRY_DELAY=${PUBLIC_EXPIRY}"
    fi
fi
if [ "$WAL_MODE" = "true" ]; then
    ENV_VARS="$ENV_VARS\n      - CHHOTO_SQLITE_USE_WAL_MODE=True"
fi
ENV_VARS="$ENV_VARS\n      - CHHOTO_DB_URL=/data/urls.sqlite"
ENV_VARS="$ENV_VARS\n      - CHHOTO_LISTEN_PORT=4567"
ENV_VARS="$ENV_VARS\n      - CHHOTO_FRONTEND_PAGE_SIZE=20"

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Chhoto URL Shortener
  winejs-chhoto-url:
    image: sayanarijit/chhoto-url:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:4567"
    volumes:
      - ${DATA_DIR}:/data
    environment:${ENV_VARS}
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:4567/health"]
      interval: 30s
      timeout: 5s
      retries: 3

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= INITIALIZE DATABASE =============
log "🚀 Starting Chhoto URL container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Chhoto URL to initialize..."
sleep 10

if docker ps | grep -q "winejs-${APP_NAME}"; then
    success "✅ Container started successfully"
else
    warn "⚠️ Container may not have started. Check: docker logs winejs-${APP_NAME}"
    docker logs winejs-${APP_NAME} --tail 20

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

# Build features list
FEATURES_LIST='[
        "🔗 URL Shortening",
        "📊 Hit Counting",
        "📱 QR Code Generation",
        "⏰ Automatic Link Expiry",
        "🔑 API Key Support",'
if [ "$PUBLIC_MODE" = "true" ]; then
    FEATURES_LIST="$FEATURES_LIST\n        \"🌍 Public Mode (Anonymous Link Creation)\","
fi
FEATURES_LIST="$FEATURES_LIST
        "✏️ Editable Short Links",
        "🎨 Custom Slug Support",
        "🌙 Dark Mode",
        "📱 Mobile Friendly",
        "⚡ Lightweight (<15MB RAM)",
        "🐳 Tiny Docker Image (<6MB)",
        "🔄 307/308 Redirects",
        "🔒 Password Protection"
    ]"

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Chhoto URL Shortener",
    "version": "latest",
    "description": "Lightning fast, lightweight URL shortener with QR codes and hit counting",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/chhoto-url.png",
    "category": "Productivity",
    "features": ${FEATURES_LIST}
}
CONF_EOF

# ============= CREATE USAGE GUIDE =============
log "📝 Creating usage guide..."

cat > "$APP_DIR/usage-guide.md" << GUIDE_EOF
# Chhoto URL Shortener - Usage Guide

## Access
- **Main Interface**: https://$DOMAIN_NAME/short/
- **Admin Management**: https://$DOMAIN_NAME/short/admin/manage

## Default Admin Password
- **Password**: [the password you set during installation]

## Creating Short Links

### Via Web Interface
1. Visit https://$DOMAIN_NAME/short/
2. Enter your long URL
3. (Optional) Enter a custom short link slug
4. (Optional) Set expiry time
5. Click "Shorten"
6. Copy your shortened URL!

### Via API
\`\`\`bash
# Create a short link
curl -X POST https://$DOMAIN_NAME/short/api/shorten \\
  -H "Content-Type: application/json" \\
  -H "X-API-Key: ${API_KEY}" \\
  -d '{
    "url": "https://example.com/very/long/url",
    "slug": "custom-slug",
    "expiry": 86400
  }'

# Get link stats
curl https://$DOMAIN_NAME/short/api/stats/{slug}

# Delete a link
curl -X DELETE https://$DOMAIN_NAME/short/api/delete/{slug} \\
  -H "X-API-Key: ${API_KEY}"
\`\`\`

## Features

### QR Codes
Every short link automatically has a QR code at:
\`https://$DOMAIN_NAME/short/qr/{slug}\`

### Hit Counting
Each short link tracks:
- Total number of clicks
- No personal data collected (privacy first!)

### Custom Slugs
Instead of auto-generated slugs, you can specify your own:
\`https://$DOMAIN_NAME/short/my-custom-link\`

### Link Expiry
Set links to expire after:
- 1 hour
- 1 day
- 1 week
- 1 month
- Custom duration

## Public Mode
$([ "$PUBLIC_MODE" = "true" ] && echo "Public mode is ENABLED. Anyone can create short links without authentication." || echo "Public mode is DISABLED. Only authenticated users can create links.")

## Managing Links

1. Login at https://$DOMAIN_NAME/short/admin/manage
2. View all your shortened links
3. Edit slugs or expiry dates
4. Delete unwanted links
5. View click statistics

## Configuration

Current settings:
- **Slug Style**: $SLUG_STYLE
- **Redirect Type**: $REDIRECT_METHOD
- **WAL Mode**: $([ "$WAL_MODE" = "true" ] && echo "Enabled" || echo "Disabled")
- **API Key**: ${API_KEY}

## Integration Examples

### With n8n
Use the HTTP Request node with API key to create short links automatically.

### With Forgejo/Git
Create short links for commit URLs, PRs, or documentation.

### With Mumble
Share shortened meeting links or voice channel invites.

## Troubleshooting

### Link not working?
- Check if link has expired
- Verify the slug is correct
- Ensure you're using the correct domain

### API returning 401?
- Verify your API key is correct
- API key is: ${API_KEY}

### Need more help?
- GitHub: https://github.com/sayantarijit/Chhoto-URL
- Documentation: https://github.com/sayantarijit/Chhoto-URL#readme
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Chhoto URL icon..."

if curl -L "$CHHOTO_URL_LOGO_URL" -o "$ICON_DIR/chhoto-url.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    # Create a simple SVG icon as fallback
    cat > "$ICON_DIR/chhoto-url.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
  <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
</svg>
SVG_EOF
    # Try to convert SVG to PNG if ImageMagick is available
    if command -v convert &>/dev/null; then
        convert "$ICON_DIR/chhoto-url.svg" "$ICON_DIR/chhoto-url.png" 2>/dev/null || true
    else
        # Use a data URI base64 encoded 1x1 pixel as fallback, or copy default
        cp /opt/winejs/translator/public/icons/default-app.png "$ICON_DIR/chhoto-url.png" 2>/dev/null || true
    fi
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-chhoto-url << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
API_KEY="${API_KEY}"

case "\$1" in
    status)
        docker ps | grep winejs-chhoto-url
        ;;
    logs)
        docker logs winejs-chhoto-url --tail 50
        ;;
    restart)
        docker restart winejs-chhoto-url
        echo "Chhoto URL restarted"
        ;;
    stats)
        echo "📊 Chhoto URL Statistics:"
        echo "  API Key: ${API_KEY}"
        echo "  Port: ${APP_PORT}"
        echo "  Data Dir: /opt/winejs/data/chhoto-url"
        ;;
    create)
        shift
        if [ $# -lt 1 ]; then
            echo "Usage: winejs-chhoto-url create <URL> [slug]"
            echo "Example: winejs-chhoto-url create https://example.com/long/url mylink"
        else
            URL="\$1"
            SLUG="\$2"
            if [ -n "\$SLUG" ]; then
                curl -X POST "https://\${DOMAIN_NAME}/short/api/shorten" \
                    -H "Content-Type: application/json" \
                    -H "X-API-Key: ${API_KEY}" \
                    -d "{\"url\":\"\${URL}\",\"slug\":\"\${SLUG}\"}" | jq .
            else
                curl -X POST "https://\${DOMAIN_NAME}/short/api/shorten" \
                    -H "Content-Type: application/json" \
                    -H "X-API-Key: ${API_KEY}" \
                    -d "{\"url\":\"\${URL}\"}" | jq .
            fi
        fi
        ;;
    list)
        echo "📋 Listing all short links:"
        curl -s "https://\${DOMAIN_NAME}/short/api/list" -H "X-API-Key: ${API_KEY}" | jq .
        ;;
    delete)
        shift
        if [ $# -lt 1 ]; then
            echo "Usage: winejs-chhoto-url delete <slug>"
        else
            curl -X DELETE "https://\${DOMAIN_NAME}/short/api/delete/\$1" \
                -H "X-API-Key: ${API_KEY}"
            echo ""
        fi
        ;;
    qr)
        shift
        if [ $# -lt 1 ]; then
            echo "Usage: winejs-chhoto-url qr <slug>"
        else
            echo "QR Code URL: https://\${DOMAIN_NAME}/short/qr/\$1"
        fi
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/short/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/short/"
        fi
        ;;
    admin)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/short/admin/manage"
        else
            echo "Admin: https://\${DOMAIN_NAME}/short/admin/manage"
        fi
        ;;
    *)
        echo "Chhoto URL Shortener Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-chhoto-url open           - Open Chhoto URL"
        echo "  winejs-chhoto-url admin          - Open Admin Panel"
        echo "  winejs-chhoto-url status         - Check status"
        echo "  winejs-chhoto-url logs           - View logs"
        echo "  winejs-chhoto-url restart        - Restart service"
        echo "  winejs-chhoto-url stats          - Show configuration"
        echo "  winejs-chhoto-url create <url> [slug] - Create short link"
        echo "  winejs-chhoto-url list           - List all short links"
        echo "  winejs-chhoto-url delete <slug>  - Delete a short link"
        echo "  winejs-chhoto-url qr <slug>      - Show QR code URL"
        echo ""
        echo "Access URLs:"
        echo "  • Main: https://\${DOMAIN_NAME}/short/"
        echo "  • Admin: https://\${DOMAIN_NAME}/short/admin/manage"
        echo ""
        echo "API Key: ${API_KEY}"
        echo "Admin Password: [the password you set]"
        echo ""
        echo "Usage Guide: cat /opt/winejs/apps/chhoto-url/usage-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-chhoto-url

# ============= UPDATE NGINX FOR CHHOTO URL =============
log "📝 Setting up nginx reverse proxy for Chhoto URL..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /short" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Chhoto URL Shortener\n\
    location /short {\n\
        rewrite ^/short(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 30s;\n\
        proxy_buffering off;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Chhoto URL routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_chhoto-url.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Chhoto URL..."

docker stop winejs-chhoto-url 2>/dev/null
docker rm winejs-chhoto-url 2>/dev/null

rm -rf /opt/winejs/apps/chhoto-url
rm -rf /opt/winejs/kasmvnc-instances/chhoto-url
rm -rf /opt/winejs/data/chhoto-url

rm -f /usr/local/bin/winejs-chhoto-url

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Chhoto URL Shortener/,/location \/short/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/short {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Chhoto URL uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_chhoto-url.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              CHHOTO URL INSTALLED ON WINEJS!                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Chhoto URL Shortener installed!"
echo ""
info "🌐 Access URLs:"
info "   • Main Interface: https://$DOMAIN_NAME/short/"
info "   • Admin Panel: https://$DOMAIN_NAME/short/admin/manage"
echo ""
info "🔐 Authentication:"
info "   • Password: [the password you set]"
info "   • API Key: $API_KEY"
echo ""
info "🔗 Features:"
info "   • URL shortening with custom slugs"
info "   • Automatic QR code generation"
info "   • Hit counting & statistics"
info "   • Link expiry dates"
if [ "$PUBLIC_MODE" = "true" ]; then
    info "   • Public mode: Anyone can create links ✓"
fi
echo ""
info "📊 Configuration:"
info "   • Slug Style: $SLUG_STYLE"
if [ "$SLUG_STYLE" = "uid" ] && [ -n "$SLUG_LENGTH" ]; then
    info "   • Slug Length: $SLUG_LENGTH"
fi
info "   • Redirect Type: $REDIRECT_METHOD"
info "   • WAL Mode: $([ "$WAL_MODE" = "true" ] && echo "Enabled (faster)" || echo "Disabled")"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-chhoto-url open            # Open web interface"
info "   • winejs-chhoto-url admin           # Open admin panel"
info "   • winejs-chhoto-url create <url>    # Create short link"
info "   • winejs-chhoto-url list            # List all links"
info "   • winejs-chhoto-url delete <slug>   # Delete a link"
info "   • winejs-chhoto-url qr <slug>       # Show QR code URL"
info "   • winejs-chhoto-url stats           # Show configuration"
echo ""
info "📁 Data Directory:"
info "   • ${DATA_DIR}/urls.sqlite"
echo ""
info "📚 Usage Guide:"
info "   • cat /opt/winejs/apps/chhoto-url/usage-guide.md"
echo ""
info "💡 API Example:"
info "   curl -X POST https://$DOMAIN_NAME/short/api/shorten \\"
info "     -H 'X-API-Key: $API_KEY' \\"
info "     -d '{\"url\":\"https://example.com\"}'"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_chhoto-url.sh"
echo ""
success "✨ Chhoto URL is ready! Start shortening URLs at https://$DOMAIN_NAME/short/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Chhoto URL Does:

# Chhoto URL is an ultra-lightweight URL shortener written in Rust:
# Key Features:
#     URL Shortening - Turn long URLs into short, shareable links
#     Custom Slugs - Create your own short links (e.g., /my-link)
#     QR Codes - Automatically generated for every short link
#     Hit Counting - Track how many times a link is clicked (privacy-respecting)
#     Link Expiry - Links can auto-expire after a set time
#     API Support - REST API for programmatic link creation
#     Public Mode - Let anyone create short links (optional)
#     Ultra Lightweight - Uses <15MB RAM, Docker image <6MB

# Perfect For:
#     Social media - Shorten links for posts
#     Email signatures - Clean, professional links
#     QR codes - Generate QR codes for events
#     Internal tools - Shorten internal system links
#     WineJS apps - Create short links to any WineJS app!