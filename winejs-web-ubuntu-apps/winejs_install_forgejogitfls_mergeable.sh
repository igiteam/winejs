#!/bin/bash
# ============================================
# Mergeable PR Management - WineJS Installer
# Adds Pull Request Management Tool to WineJS
# ============================================
# App: Mergeable
# Category: Development
# Features: PR Management, GitHub/Gitea/Forgejo Integration, PR Sizing
# ============================================

MERGEABLE_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/mergeable-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🔀 Installing WineJS Mergeable PR Management..."

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

# ============= ASK FOR MERGEABLE CONFIGURATION =============
echo ""
info "📝 Mergeable Configuration"
echo "================================"
echo "Configure GitHub/Gitea/Forgejo API endpoints:"
echo "  Example 1: https://api.github.com (GitHub.com)"
echo "  Example 2: https://git.yourdomain.com/api/v3 (Forgejo/Gitea)"
echo "  Example 3: Multiple: https://api.github.com,https://git.yourdomain.com/api/v3"
read -p "GitHub API URLs (comma-separated): " GITHUB_URLS

if [ -z "$GITHUB_URLS" ]; then
    GITHUB_URLS="https://api.github.com"
    info "Using default: $GITHUB_URLS"
fi

read -p "PR Size thresholds (comma-separated: XS,S,M,L,XL) [10,30,100,500,1000]: " PR_SIZES
PR_SIZES=${PR_SIZES:-"10,30,100,500,1000"}

read -p "Disable telemetry? (true/false) [true]: " NO_TELEMETRY
NO_TELEMETRY=${NO_TELEMETRY:-true}

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=7400  # Start after OpenSpy's range (7300+)
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

# Find available port for Mergeable
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Mergeable"
fi

log "Using port: Mergeable=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="mergeable"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/mergeable"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/mergeable"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

# Build environment variables string
ENV_VARS=""
if [ -n "$GITHUB_URLS" ]; then
    ENV_VARS="$ENV_VARS\n      - MERGEABLE_GITHUB_URLS=${GITHUB_URLS}"
fi
if [ -n "$PR_SIZES" ]; then
    ENV_VARS="$ENV_VARS\n      - MERGEABLE_PR_SIZES=${PR_SIZES}"
fi
if [ "$NO_TELEMETRY" = "true" ]; then
    ENV_VARS="$ENV_VARS\n      - MERGEABLE_NO_TELEMETRY=1"
fi

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Mergeable PR Management
  winejs-mergeable:
    image: ghcr.io/pvcnt/mergeable:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:80"
    environment:${ENV_VARS}
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:80/"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

# Build features list based on config
FEATURES_LIST='[
        "🔀 Pull Request Management",
        "📊 PR Size Labels (XS-XXL)",
        "🏢 Multi-GitHub Instance Support",
        "🔗 GitLab/Gitea/Forgejo Compatible",
        "📈 PR Analytics & Insights",'

if [ -n "$GITHUB_URLS" ] && [[ "$GITHUB_URLS" == *","* ]]; then
    FEATURES_LIST="$FEATURES_LIST\n        \"🔄 Multiple Git Providers\","
fi
if [ "$NO_TELEMETRY" = "true" ]; then
    FEATURES_LIST="$FEATURES_LIST\n        \"🔒 Privacy-Focused (No Telemetry)\","
fi

FEATURES_LIST="$FEATURES_LIST
        \"⚡ Lightweight & Fast\",
        \"🎨 Clean Modern UI\",
        \"🔐 No External Dependencies\"
    ]"

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Mergeable PR Management",
    "version": "latest",
    "description": "Manage pull requests across GitHub, Gitea, and Forgejo with smart sizing and analytics",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/mergeable.png",
    "category": "Development",
    "features": ${FEATURES_LIST}
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading Mergeable icon..."
curl -L "$MERGEABLE_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-mergeable << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
GITHUB_URLS="${GITHUB_URLS}"

case "\$1" in
    status)
        docker ps | grep winejs-mergeable
        ;;
    logs)
        docker logs winejs-mergeable --tail 50
        ;;
    restart)
        docker restart winejs-mergeable
        echo "Mergeable restarted"
        ;;
    config)
        echo "📋 Mergeable Configuration:"
        echo "  • GitHub URLs: ${GITHUB_URLS}"
        echo "  • PR Sizes: ${PR_SIZES}"
        echo "  • Telemetry: $([ "$NO_TELEMETRY" = "true" ] && echo "Disabled" || echo "Enabled")"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/mergeable/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/mergeable/"
        fi
        ;;
    *)
        echo "Mergeable PR Management Tool"
        echo ""
        echo "Commands:"
        echo "  winejs-mergeable open        - Open Mergeable"
        echo "  winejs-mergeable status      - Check status"
        echo "  winejs-mergeable logs        - View logs"
        echo "  winejs-mergeable restart     - Restart"
        echo "  winejs-mergeable config      - Show configuration"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/mergeable/"
        echo ""
        echo "Configured GitHub URLs:"
        echo "$GITHUB_URLS" | tr ',' '\n' | sed 's/^/  • /'
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-mergeable

# ============= START CONTAINER =============
log "🚀 Starting Mergeable container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

sleep 10

if docker ps | grep -q "winejs-${APP_NAME}"; then
    success "✅ Container started successfully"
else
    warn "⚠️ Container may not have started. Check: docker logs winejs-${APP_NAME}"
    docker logs winejs-${APP_NAME} --tail 20
fi

# ============= UPDATE NGINX FOR MERGEABLE =============
log "📝 Setting up nginx reverse proxy for Mergeable..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /mergeable" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Mergeable PR Management\n\
    location /mergeable {\n\
        rewrite ^/mergeable(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_buffering off;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Mergeable routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_mergeable.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Mergeable..."

docker stop winejs-mergeable 2>/dev/null
docker rm winejs-mergeable 2>/dev/null

rm -rf /opt/winejs/apps/mergeable
rm -rf /opt/winejs/kasmvnc-instances/mergeable
rm -rf /opt/winejs/data/mergeable

rm -f /usr/local/bin/winejs-mergeable

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Mergeable PR Management/,/location \/mergeable/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/mergeable {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Mergeable uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_mergeable.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              MERGEABLE INSTALLED ON WINEJS!                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Mergeable PR Management installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/mergeable/"
echo ""
info "🔧 Configuration:"
info "   • GitHub URLs: $GITHUB_URLS"
info "   • PR Size Thresholds: $PR_SIZES"
info "   • Telemetry: $([ "$NO_TELEMETRY" = "true" ] && echo "Disabled ✓" || echo "Enabled")"
echo ""
info "📊 PR Size Categories:"
echo "   • XS: 0-${PR_SIZES%,*} lines"
echo "   • S: ${PR_SIZES%,*}-$(echo $PR_SIZES | cut -d',' -f2) lines"
echo "   • M: $(echo $PR_SIZES | cut -d',' -f2)-$(echo $PR_SIZES | cut -d',' -f3) lines"
echo "   • L: $(echo $PR_SIZES | cut -d',' -f3)-$(echo $PR_SIZES | cut -d',' -f4) lines"
echo "   • XL: $(echo $PR_SIZES | cut -d',' -f4)-$(echo $PR_SIZES | cut -d',' -f5) lines"
echo "   • XXL: $(echo $PR_SIZES | cut -d',' -f5)+ lines"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-mergeable open        # Open Mergeable"
info "   • winejs-mergeable status      # Check status"
info "   • winejs-mergeable logs        # View logs"
info "   • winejs-mergeable config      # Show config"
echo ""
info "🔗 Integration Tips:"
if [[ "$GITHUB_URLS" == *"api.github.com"* ]]; then
    info "   • GitHub.com: Create a Personal Access Token"
fi
if [[ "$GITHUB_URLS" == *"/api/v3"* ]]; then
    info "   • Forgejo/Gitea: Use API v3 endpoint"
    info "   • Example: https://your-forgejo.com/api/v3"
fi
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_mergeable.sh"
echo ""
success "✨ Mergeable is ready! Manage PRs at https://$DOMAIN_NAME/mergeable/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"