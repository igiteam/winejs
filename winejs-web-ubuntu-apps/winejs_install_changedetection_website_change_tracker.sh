#!/bin/bash
# ============================================
# Changedetection.io Web Monitor - WineJS Installer
# Adds Website Change Detection to WineJS Platform
# ============================================
# App: Changedetection.io
# Category: Productivity
# Features: Website Monitoring, Change Detection, Price Tracking
# ============================================

CHANGEDETECTION_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/changedetection-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "👁️ Installing WineJS Changedetection.io Web Monitor..."

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

# ============= ASK FOR CHANGEDETECTION CONFIGURATION =============
echo ""
info "📝 Changedetection.io Configuration"
echo "================================"
read -p "Admin username: " ADMIN_USER
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

read -p "Enable Playwright/Javascript rendering? (true/false) [true]: " PLAYWRIGHT_ENABLED
PLAYWRIGHT_ENABLED=${PLAYWRIGHT_ENABLED:-true}

read -p "Base URL [https://${DOMAIN_NAME}/changedetection]: " BASE_URL
BASE_URL=${BASE_URL:-"https://${DOMAIN_NAME}/changedetection"}

read -p "Email notifications? (true/false) [false]: " EMAIL_ENABLED
EMAIL_ENABLED=${EMAIL_ENABLED:-false}

if [ "$EMAIL_ENABLED" = "true" ]; then
    read -p "SMTP Server: " SMTP_HOST
    read -p "SMTP Port [587]: " SMTP_PORT
    SMTP_PORT=${SMTP_PORT:-587}
    read -p "SMTP User: " SMTP_USER
    read -s -p "SMTP Password: " SMTP_PASSWORD
    echo ""
    read -p "From Email: " FROM_EMAIL
    read -p "To Email: " TO_EMAIL
fi

read -p "Enable AI summaries? (true/false) [false]: " AI_ENABLED
AI_ENABLED=${AI_ENABLED:-false}

if [ "$AI_ENABLED" = "true" ]; then
    echo ""
    echo "AI Provider Options:"
    echo "  1. OpenAI (GPT-4o-mini)"
    echo "  2. Google Gemini"
    echo "  3. Ollama (Local)"
    read -p "Select provider (1-3): " AI_PROVIDER
    
    case $AI_PROVIDER in
        1)
            read -p "OpenAI API Key: " OPENAI_API_KEY
            ;;
        2)
            read -p "Gemini API Key: " GEMINI_API_KEY
            ;;
        3)
            read -p "Ollama URL [http://localhost:11434]: " OLLAMA_URL
            OLLAMA_URL=${OLLAMA_URL:-"http://localhost:11434"}
            read -p "Ollama Model [llama2]: " OLLAMA_MODEL
            OLLAMA_MODEL=${OLLAMA_MODEL:-"llama2"}
            ;;
    esac
fi

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=8400  # Start after Castopod's range (8300+)
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

# Find available port for Changedetection
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Changedetection"
fi

log "Using port: Changedetection=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="changedetection"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/changedetection"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{datastore,playwright-data,chromium-cache}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/changedetection"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Playwright/Javascript fetcher (optional)
  playwright-chrome:
    image: browserless/chrome:latest
    container_name: winejs-changedetection-playwright
    restart: unless-stopped
    environment:
      - SCREEN_WIDTH=1920
      - SCREEN_HEIGHT=1024
      - MAX_CONCURRENT_SESSIONS=10
      - CONNECTION_TIMEOUT=300000
    volumes:
      - ${DATA_DIR}/playwright-data:/data
    networks:
      - winejs-net

  # Main Changedetection.io app
  winejs-changedetection:
    image: dgtlmoon/changedetection.io:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:5000"
    volumes:
      - ${DATA_DIR}/datastore:/datastore
      - ${DATA_DIR}/chromium-cache:/chromium-cache
    environment:
      - BASE_URL=${BASE_URL}
      - PLAYWRIGHT_DRIVER_URL=ws://playwright-chrome:3000
      - USE_X_SETTINGS=1
      - PUID=1000
      - PGID=1000
      - TZ=UTC
    networks:
      - winejs-net
    depends_on:
      - playwright-chrome

networks:
  winejs-net:
    external: true
DOCKER_EOF

# Add email configuration if enabled
if [ "$EMAIL_ENABLED" = "true" ]; then
    cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF

  # Mailhog for email testing (optional, remove in production)
  mailhog:
    image: mailhog/mailhog:latest
    container_name: winejs-changedetection-mailhog
    restart: unless-stopped
    ports:
      - "127.0.0.1:${SMTP_PORT:-1025}:1025"
      - "127.0.0.1:8025:8025"
    networks:
      - winejs-net
DOCKER_EOF
fi

# ============= CREATE ENVIRONMENT FILE =============
log "📝 Creating environment configuration..."

cat > "$INSTANCE_DIR/.env" << EOF
# Changedetection.io Configuration
BASE_URL=${BASE_URL}
USE_X_SETTINGS=1

# Authentication (set via UI after first run)
# First user to register becomes admin

# Email settings
EOF

if [ "$EMAIL_ENABLED" = "true" ]; then
    cat >> "$INSTANCE_DIR/.env" << EOF
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_USER=${SMTP_USER}
SMTP_PASSWORD=${SMTP_PASSWORD}
FROM_EMAIL=${FROM_EMAIL}
TO_EMAIL=${TO_EMAIL}
EOF
fi

if [ "$AI_ENABLED" = "true" ]; then
    cat >> "$INSTANCE_DIR/.env" << EOF
# AI Settings
AI_ENABLED=true
EOF
    if [ -n "$OPENAI_API_KEY" ]; then
        echo "OPENAI_API_KEY=${OPENAI_API_KEY}" >> "$INSTANCE_DIR/.env"
    fi
    if [ -n "$GEMINI_API_KEY" ]; then
        echo "GEMINI_API_KEY=${GEMINI_API_KEY}" >> "$INSTANCE_DIR/.env"
    fi
    if [ -n "$OLLAMA_URL" ]; then
        echo "OLLAMA_URL=${OLLAMA_URL}" >> "$INSTANCE_DIR/.env"
        echo "OLLAMA_MODEL=${OLLAMA_MODEL}" >> "$INSTANCE_DIR/.env"
    fi
fi

# ============= START CONTAINERS =============
log "🚀 Starting Changedetection containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Changedetection to initialize..."
sleep 15

# Create admin user via API or UI prompt
log "🔐 Setting up admin user..."

# Wait for service to be ready
MAX_ATTEMPTS=30
for i in $(seq 1 $MAX_ATTEMPTS); do
    if curl -s -f "http://127.0.0.1:${APP_PORT}/" >/dev/null 2>&1; then
        log "✅ Changedetection is ready"
        break
    fi
    if [ $i -eq $MAX_ATTEMPTS ]; then
        warn "Changedetection may not be fully ready, continuing..."
    fi
    sleep 2
done

log "✅ Changedetection initialized"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

# Build features list
FEATURES_LIST='[
        "👁️ Website Change Detection",
        "📧 Discord/Email/Slack/Telegram Notifications",'
if [ "$PLAYWRIGHT_ENABLED" = "true" ]; then
    FEATURES_LIST="$FEATURES_LIST\n        \"🌐 Javascript Rendering (Playwright)\","
fi
if [ "$AI_ENABLED" = "true" ]; then
    FEATURES_LIST="$FEATURES_LIST\n        \"🤖 AI-Powered Change Summaries\","
fi
FEATURES_LIST="$FEATURES_LIST
        "💰 Price Change Tracking",
        "📦 Stock/Inventory Monitoring",
        "🎯 Visual Selector Tool",
        "🔍 XPath/CSS/JSONPath Filters",
        "📊 REST API Access",
        "🔄 Browser Steps (Login/Click)",
        "📎 PDF File Monitoring",
        "⏰ Custom Schedules",
        "🌐 Proxy Support",
        "📱 Mobile Viewport Testing",
        "🔔 Webhook Integrations"
    ]"

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Changedetection.io Web Monitor",
    "version": "latest",
    "description": "Monitor websites for changes, get alerts for price drops, restocks, and content updates",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/changedetection.png",
    "category": "Productivity",
    "features": ${FEATURES_LIST}
}
CONF_EOF

# ============= CREATE EXAMPLE WATCHES =============
log "📝 Creating example watch configurations..."

cat > "$APP_DIR/example-watches.md" << EXAMPLE_EOF
# Example Website Watches

## Price Monitoring
- **Amazon product**: Watch for price drops
- **Best Buy**: Restock alerts
- **eBay**: Auction ending soon

## Content Monitoring  
- **Government pages**: Policy changes
- **Job boards**: New positions
- **News sites**: Breaking stories

## API Monitoring
- **JSON endpoints**: Track API changes
- **Weather APIs**: Condition changes

## Setting Up a Watch

1. Click "Add Watch" in the dashboard
2. Enter the URL to monitor
3. Configure check interval (e.g., every 6 hours)
4. Set filters to target specific elements
5. Choose notification method
6. Save and start monitoring!

## Example: Price Drop Alert

\`\`\`
URL: https://example.com/product
Check Interval: 1 hour
Filters: CSS Selector ".price"
Trigger: when text value changes below $50
Notification: Email/Slack/Discord
\`\`\`

## Example: Restock Alert

\`\`\`
URL: https://example.com/product
Check Interval: 30 minutes
Filters: Text matching "Out of Stock"
Trigger: when text does NOT contain "Out of Stock"
Notification: Webhook to n8n workflow
\`\`\`
EXAMPLE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Changedetection icon..."

if curl -L "$CHANGEDETECTION_LOGO_URL" -o "$ICON_DIR/changedetection.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/changedetection.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <circle cx="12" cy="12" r="10"/>
  <path d="M12 8v4l3 3"/>
  <path d="M12 2a15 15 0 0 1 0 20"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-changedetection << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
ADMIN_USER="${ADMIN_USER}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/changedetection && docker compose ps
        ;;
    logs)
        docker logs winejs-changedetection --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/changedetection && docker compose restart
        echo "Changedetection restarted"
        ;;
    playwright)
        echo "🎭 Playwright container status:"
        docker logs winejs-changedetection-playwright --tail 20
        ;;
    watches)
        echo "📋 Active watches:"
        echo "  Visit the UI to see all watches"
        echo "  URL: https://\${DOMAIN_NAME}/changedetection/"
        ;;
    import)
        echo "📥 Import watches from file:"
        echo "  docker exec -i winejs-changedetection changedetection.io import < watches.json"
        ;;
    export)
        echo "📤 Export watches to file:"
        echo "  docker exec winejs-changedetection changedetection.io export > watches.json"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/changedetection/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/changedetection/"
        fi
        ;;
    *)
        echo "Changedetection.io Web Monitor Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-changedetection open        - Open Changedetection"
        echo "  winejs-changedetection status      - Check status"
        echo "  winejs-changedetection logs        - View logs"
        echo "  winejs-changedetection restart     - Restart services"
        echo "  winejs-changedetection playwright  - Check Playwright status"
        echo "  winejs-changedetection watches     - Show watch info"
        echo "  winejs-changedetection import      - Import watches"
        echo "  winejs-changedetection export      - Export watches"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/changedetection/"
        echo ""
        echo "First Run:"
        echo "  1. Visit the URL above"
        echo "  2. Click 'Register' to create admin account"
        echo "  3. Login with your credentials"
        echo "  4. Click 'Add Watch' to start monitoring"
        echo ""
        echo "Example Watches: cat /opt/winejs/apps/changedetection/example-watches.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-changedetection

# ============= UPDATE NGINX FOR CHANGEDETECTION =============
log "📝 Setting up nginx reverse proxy for Changedetection..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /changedetection" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Changedetection.io Web Monitor\n\
    location /changedetection {\n\
        rewrite ^/changedetection(/.*)?$ /\\\$1 break;\n\
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
                log "✅ Nginx updated with Changedetection routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_changedetection.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Changedetection..."

cd /opt/winejs/kasmvnc-instances/changedetection
docker compose down -v 2>/dev/null

rm -rf /opt/winejs/apps/changedetection
rm -rf /opt/winejs/kasmvnc-instances/changedetection
rm -rf /opt/winejs/data/changedetection

rm -f /usr/local/bin/winejs-changedetection

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Changedetection.io Web Monitor/,/location \/changedetection/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/changedetection {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Changedetection uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_changedetection.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         CHANGEDETECTION.IO INSTALLED ON WINEJS!                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Changedetection.io Web Monitor installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/changedetection/"
echo ""
info "🔐 First Time Setup:"
info "   • Visit the URL above"
info "   • Click 'Register' to create admin account"
info "   • Use username: $ADMIN_USER (or choose your own)"
info "   • Password: [the password you set]"
echo ""
info "👁️ Key Features:"
info "   • Monitor any website for changes"
info "   • Price drop & restock alerts"
info "   • Email/Discord/Slack/Telegram notifications"
if [ "$PLAYWRIGHT_ENABLED" = "true" ]; then
    info "   • JavaScript rendering (Playwright) ✓"
fi
if [ "$AI_ENABLED" = "true" ]; then
    info "   • AI-powered change summaries ✓"
fi
echo ""
info "🎯 Quick Commands:"
info "   • winejs-changedetection open        # Open dashboard"
info "   • winejs-changedetection status      # Check status"
info "   • winejs-changedetection logs        # View logs"
info "   • winejs-changedetection playwright  # Check Playwright"
info "   • winejs-changedetection import      # Import watches"
info "   • winejs-changedetection export      # Export watches"
echo ""
info "📁 Data Directories:"
info "   • Database: ${DATA_DIR}/datastore"
info "   • Playwright: ${DATA_DIR}/playwright-data"
info "   • Chromium: ${DATA_DIR}/chromium-cache"
echo ""
info "📚 Example Use Cases:"
info "   • Price monitoring: Track product prices"
info "   • Job alerts: Monitor career pages"
info "   • Restock alerts: Get notified when items return"
info "   • Content changes: Track policy updates"
echo ""
info "📝 Example Config:"
info "   • cat /opt/winejs/apps/changedetection/example-watches.md"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_changedetection.sh"
echo ""
success "✨ Changedetection is ready! Start monitoring at https://$DOMAIN_NAME/changedetection/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Changedetection.io Does:

# Changedetection.io monitors websites for changes and sends notifications:
# Key Features:
#     Website Change Detection - Monitor any webpage for changes
#     Price Tracking - Get alerts when prices drop
#     Restock Alerts - Know when items are back in stock
#     JavaScript Rendering - Monitor dynamic sites with Playwright
#     Visual Selector - Click to select elements to monitor
#     XPath/CSS Filters - Target specific page elements
#     Browser Steps - Login, click buttons, fill forms before checking
#     Multiple Notifications - Discord, Email, Slack, Telegram, Webhook
#     JSON/API Monitoring - Track API responses
#     PDF Monitoring - Detect changes in PDF files

# Perfect For:
#     Price watching - Get notified when products drop in price
#     Job hunting - Monitor company career pages
#     Restock alerts - Know when sold-out items return
#     Competitor tracking - Watch competitor websites
#     Compliance monitoring - Track policy changes
#     WineJS itself - Monitor app releases!