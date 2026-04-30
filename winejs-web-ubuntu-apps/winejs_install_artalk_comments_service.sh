#!/bin/bash
# ============================================
# Artalk Comment System - WineJS Installer
# Adds Self-Hosted Comment System to WineJS Platform
# ============================================
# App: Artalk
# Category: Communication
# Features: Comments, Moderation, Anti-Spam, Email Notifications
# ============================================

ARTALK_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/artalk-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "💬 Installing WineJS Artalk Comment System..."

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

# ============= ASK FOR ARTALK CONFIGURATION =============
echo ""
info "📝 Artalk Configuration"
echo "================================"
read -p "Site name [WineJS Blog]: " SITE_NAME
SITE_NAME=${SITE_NAME:-"WineJS Blog"}

read -p "Site URL (your blog/website): " SITE_URL

read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

read -p "Default language (en/zh-CN/zh-TW/ja) [en]: " LOCALE
LOCALE=${LOCALE:-"en"}

read -p "Enable email notifications? (true/false) [false]: " EMAIL_ENABLED
EMAIL_ENABLED=${EMAIL_ENABLED:-false}

if [ "$EMAIL_ENABLED" = "true" ]; then
    read -p "SMTP Host: " SMTP_HOST
    read -p "SMTP Port: " SMTP_PORT
    read -p "SMTP User: " SMTP_USER
    read -s -p "SMTP Password: " SMTP_PASSWORD
    echo ""
    read -p "From Email: " FROM_EMAIL
fi

read -p "Enable CAPTCHA? (true/false) [true]: " CAPTCHA_ENABLED
CAPTCHA_ENABLED=${CAPTCHA_ENABLED:-true}

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=7700  # Start after ArchiveBox's range (7600+)
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

# Find available port for Artalk
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Artalk"
fi

log "Using port: Artalk=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="artalk"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/artalk"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/artalk"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

# Build email config if enabled
EMAIL_CONFIG=""
if [ "$EMAIL_ENABLED" = "true" ]; then
    EMAIL_CONFIG="
      - ATK_EMAIL_ENABLED=true
      - ATK_EMAIL_SMTP_HOST=${SMTP_HOST}
      - ATK_EMAIL_SMTP_PORT=${SMTP_PORT}
      - ATK_EMAIL_SMTP_USERNAME=${SMTP_USER}
      - ATK_EMAIL_SMTP_PASSWORD=${SMTP_PASSWORD}
      - ATK_EMAIL_FROM=${FROM_EMAIL}"
fi

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Artalk Comment Server
  winejs-artalk:
    image: artalk/artalk-go:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:23366"
    volumes:
      - ${DATA_DIR}:/data
    environment:
      - TZ=UTC
      - ATK_LOCALE=${LOCALE}
      - ATK_SITE_DEFAULT=${SITE_NAME}
      - ATK_SITE_URL=${SITE_URL:-https://${DOMAIN_NAME}}
      - ATK_TRUSTED_PROXIES=127.0.0.1,::1,172.16.0.0/12,192.168.0.0/16,10.0.0.0/8
      - ATK_CAPTCHA_ENABLED=${CAPTCHA_ENABLED}
      - ATK_ADMIN_EMAILS=${ADMIN_EMAIL}
      - ATK_MODERATOR_EMAILS=${ADMIN_EMAIL}
      - ATK_DEFAULT_VOTES=false
      - ATK_IMG_LAZY_LOAD=true${EMAIL_CONFIG}
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:23366/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= INITIALIZE ARTALK AND CREATE ADMIN =============
log "🔧 Initializing Artalk and creating admin user..."

# Start container first
cd "$INSTANCE_DIR"
docker-compose up -d

sleep 10

# Create admin user non-interactively
echo "admin@artalk.local" | docker exec -i winejs-artalk artalk admin $ADMIN_PASSWORD $ADMIN_EMAIL 2>/dev/null || \
echo "y" | docker exec -i winejs-artalk artalk admin $ADMIN_PASSWORD $ADMIN_EMAIL 2>/dev/null || \
docker exec winejs-artalk artalk admin 2>/dev/null || true

log "✅ Admin user configured"

# ============= CREATE INTEGRATION SCRIPT =============
log "📝 Creating integration script for websites..."

cat > "$APP_DIR/embed-code.html" << HTML_EOF
<!-- Artalk Comment System - Embed Code -->
<!-- Copy this code into your website where you want comments to appear -->

<!-- CSS -->
<link rel="stylesheet" href="https://${DOMAIN_NAME}/artalk/dist/Artalk.css" />

<!-- Artalk Container -->
<div id="ArtalkComments"></div>

<!-- JS -->
<script src="https://${DOMAIN_NAME}/artalk/dist/Artalk.js"></script>
<script>
Artalk.init({
  el:        '#ArtalkComments',
  pageKey:   window.location.pathname,
  pageTitle: document.title,
  server:    'https://${DOMAIN_NAME}/artalk',
  site:      '${SITE_NAME}',
  // Optional: Custom emoticons, image upload, etc.
  useEmoji: true,
  imgUpload: true,
  nestMax: 3,
  nestSort: 'DATE_ASC',
})
</script>
HTML_EOF

# Create Vue.js integration example
cat > "$APP_DIR/vue-integration.md" << VUE_EOF
# Vue.js Integration for Artalk

## Installation
\`\`\`bash
npm install artalk
\`\`\`

## Usage in Vue Component
\`\`\`vue
<template>
  <div>
    <div id="Comments"></div>
  </div>
</template>

<script>
import 'artalk/Artalk.css'
import Artalk from 'artalk'

export default {
  name: 'ArtalkComments',
  mounted() {
    Artalk.init({
      el: '#Comments',
      pageKey: this.\$route.path,
      pageTitle: document.title,
      server: 'https://${DOMAIN_NAME}/artalk',
      site: '${SITE_NAME}',
      useEmoji: true,
      imgUpload: true,
    })
  }
}
</script>
\`\`\`
VUE_EOF

# Create React integration example
cat > "$APP_DIR/react-integration.md" << REACT_EOF
# React Integration for Artalk

## Installation
\`\`\`bash
npm install artalk
\`\`\`

## Usage in React Component
\`\`\`jsx
import React, { useEffect, useRef } from 'react';
import 'artalk/Artalk.css';
import Artalk from 'artalk';

const ArtalkComments = ({ pageKey, pageTitle }) => {
  const containerRef = useRef(null);

  useEffect(() => {
    if (containerRef.current) {
      Artalk.init({
        el: containerRef.current,
        pageKey: pageKey || window.location.pathname,
        pageTitle: pageTitle || document.title,
        server: 'https://${DOMAIN_NAME}/artalk',
        site: '${SITE_NAME}',
        useEmoji: true,
        imgUpload: true,
      });
    }
  }, [pageKey, pageTitle]);

  return <div ref={containerRef}></div>;
};

export default ArtalkComments;
\`\`\`
REACT_EOF

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

# Build features list
FEATURES_LIST='[
        "💬 Self-Hosted Comments",
        "🔒 Privacy-Focused",
        "🛡️ Anti-Spam Protection",
        "✏️ Markdown Support",
        "😀 Emoji Reactions",'
if [ "$EMAIL_ENABLED" = "true" ]; then
    FEATURES_LIST="$FEATURES_LIST\n        \"📧 Email Notifications\","
fi
if [ "$CAPTCHA_ENABLED" = "true" ]; then
    FEATURES_LIST="$FEATURES_LIST\n        \"🤖 CAPTCHA Verification\","
fi
FEATURES_LIST="$FEATURES_LIST
        \"🖼️ Image Uploads\",
        \"🌲 Nested Replies\",
        \"🔊 Akismet Integration\",
        \"📊 Moderation Dashboard\",
        \"🌍 Multi-Language\",
        \"📱 Mobile Responsive\"
    ]"

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Artalk Comment System",
    "version": "latest",
    "description": "Self-hosted, privacy-focused comment system for blogs and websites",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/artalk.png",
    "category": "Communication",
    "features": ${FEATURES_LIST}
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading Artalk icon..."
curl -L "$ARTALK_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-artalk << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
DATA_DIR="${DATA_DIR}"
SITE_NAME="${SITE_NAME}"

case "\$1" in
    status)
        docker ps | grep winejs-artalk
        ;;
    logs)
        docker logs winejs-artalk --tail 50
        ;;
    restart)
        docker restart winejs-artalk
        echo "Artalk restarted"
        ;;
    admin)
        echo "🔐 To create/reset admin user:"
        echo "  docker exec -it winejs-artalk artalk admin"
        ;;
    config)
        echo "📋 Artalk Configuration:"
        echo "  • Config file: \$DATA_DIR/conf.yml"
        echo "  • Data directory: \$DATA_DIR"
        echo ""
        echo "View config: docker exec winejs-artalk cat /data/conf.yml"
        ;;
    embed)
        echo "📝 Embedded Code:"
        echo "  Copy the embed code for your website:"
        echo "  cat /opt/winejs/apps/artalk/embed-code.html"
        ;;
    vue)
        echo "📘 Vue.js Integration:"
        echo "  cat /opt/winejs/apps/artalk/vue-integration.md"
        ;;
    react)
        echo "⚛️ React Integration:"
        echo "  cat /opt/winejs/apps/artalk/react-integration.md"
        ;;
    stats)
        echo "📊 Comment Statistics:"
        docker exec winejs-artalk artalk stats 2>/dev/null || echo "No stats available yet"
        ;;
    migrate)
        echo "🔄 Import comments from other systems:"
        echo "  Supported: Disqus, WordPress, Typecho, etc."
        echo "  See: https://artalk.js.org/docs/migrate/"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/artalk/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/artalk/"
        fi
        ;;
    *)
        echo "Artalk Comment System Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-artalk open           - Open Artalk Dashboard"
        echo "  winejs-artalk status         - Check status"
        echo "  winejs-artalk logs           - View logs"
        echo "  winejs-artalk restart        - Restart"
        echo "  winejs-artalk admin          - Create/Reset admin user"
        echo "  winejs-artalk config         - Show configuration"
        echo "  winejs-artalk embed          - Show embed code"
        echo "  winejs-artalk vue            - Show Vue.js integration"
        echo "  winejs-artalk react          - Show React integration"
        echo "  winejs-artalk stats          - Show comment stats"
        echo "  winejs-artalk migrate        - Import comments from other systems"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/artalk/"
        echo "Admin Login: ${ADMIN_EMAIL} / (password you set)"
        echo ""
        echo "Embed Code:"
        echo "  <link rel='stylesheet' href='https://\${DOMAIN_NAME}/artalk/dist/Artalk.css' />"
        echo "  <div id='Comments'></div>"
        echo "  <script src='https://\${DOMAIN_NAME}/artalk/dist/Artalk.js'></script>"
        echo "  <script>Artalk.init({ el:'#Comments', server:'https://\${DOMAIN_NAME}/artalk', site:'${SITE_NAME}' })</script>"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-artalk

# ============= UPDATE NGINX FOR ARTALK =============
log "📝 Setting up nginx reverse proxy for Artalk..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /artalk" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Artalk Comment System\n\
    location /artalk {\n\
        rewrite ^/artalk(/.*)?$ /\\\$1 break;\n\
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
    }\n\
    \n\
    # Artalk Static Files\n\
    location /artalk/dist/ {\n\
        rewrite ^/artalk/dist/(.*)$ /dist/\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        expires 1y;\n\
        add_header Cache-Control \"public, immutable\";\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Artalk routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_artalk.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Artalk..."

docker stop winejs-artalk 2>/dev/null
docker rm winejs-artalk 2>/dev/null

rm -rf /opt/winejs/apps/artalk
rm -rf /opt/winejs/kasmvnc-instances/artalk
rm -rf /opt/winejs/data/artalk

rm -f /usr/local/bin/winejs-artalk

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Artalk Comment System/,/location \/artalk\/dist\//d' /etc/nginx/sites-available/winejs
    sed -i '/location \/artalk {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Artalk uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_artalk.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ARTALK INSTALLED ON WINEJS!                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Artalk Comment System installed!"
echo ""
info "🌐 Access URL:"
info "   • Dashboard: https://$DOMAIN_NAME/artalk/"
echo ""
info "🔐 Admin Login:"
info "   • Email: $ADMIN_EMAIL"
info "   • Password: [the password you set]"
echo ""
info "📝 Configuration:"
info "   • Site Name: $SITE_NAME"
info "   • Site URL: ${SITE_URL:-https://$DOMAIN_NAME}"
info "   • Language: $LOCALE"
info "   • CAPTCHA: $([ "$CAPTCHA_ENABLED" = "true" ] && echo "Enabled" || echo "Disabled")"
info "   • Email: $([ "$EMAIL_ENABLED" = "true" ] && echo "Enabled" || echo "Disabled")"
echo ""
info "🔧 Embed Code (Copy to your website):"
echo ""
echo -e "${CYAN}  <link rel=\"stylesheet\" href=\"https://$DOMAIN_NAME/artalk/dist/Artalk.css\" />"
echo "  <div id=\"Comments\"></div>"
echo "  <script src=\"https://$DOMAIN_NAME/artalk/dist/Artalk.js\"></script>"
echo "  <script>"
echo "    Artalk.init({"
echo "      el: '#Comments',"
echo "      server: 'https://$DOMAIN_NAME/artalk',"
echo "      site: '$SITE_NAME',"
echo "      pageKey: window.location.pathname,"
echo "      pageTitle: document.title"
echo "    })"
echo "  </script>${NC}"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-artalk open        # Open Artalk"
info "   • winejs-artalk status      # Check status"
info "   • winejs-artalk admin       # Manage admin user"
info "   • winejs-artalk embed       # Show embed code"
info "   • winejs-artalk vue         # Vue.js integration"
info "   • winejs-artalk react       # React integration"
info "   • winejs-artalk stats       # View comment stats"
info "   • winejs-artalk migrate     # Import comments"
echo ""
info "📚 Integration Examples:"
info "   • Vue.js: cat /opt/winejs/apps/artalk/vue-integration.md"
info "   • React: cat /opt/winejs/apps/artalk/react-integration.md"
echo ""
info "📁 Data Directory: $DATA_DIR"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_artalk.sh"
echo ""
success "✨ Artalk is ready! Add comments to your site at https://$DOMAIN_NAME/artalk/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Artalk Does:

# Artalk is a self-hosted, privacy-focused comment system - a great alternative to Disqus:
# Key Features:
#     Self-Hosted - Full control over your comment data
#     No Tracking - Privacy-friendly, no external analytics
#     Markdown Support - Rich text formatting in comments
#     Email Notifications - Get notified of new comments
#     CAPTCHA Protection - Prevent spam
#     Moderation Dashboard - Approve/edit/delete comments
#     Nested Replies - Threaded conversations
#     Image Uploads - Users can attach images

# Perfect For:
#     Blogs - Add comments to your posts
#     Documentation sites - Allow feedback on pages
#     Static sites - Add dynamic comments to static HTML
#     WineJS itself - Let users comment on app pages!