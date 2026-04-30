#!/bin/bash
# ============================================
# n8n Workflow Automation - WineJS Installer
# Adds Workflow Automation Platform to WineJS
# ============================================
# App: n8n
# Category: Productivity
# Features: Workflow automation, API integration, Webhooks
# ============================================

N8N_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/n8n_logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🔄 Installing WineJS n8n Workflow Automation..."

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

# ============= ASK FOR N8N CONFIGURATION =============
echo ""
info "📝 n8n Configuration"
echo "================================"
read -p "Admin email for SSL: " ADMIN_EMAIL
read -s -p "Admin password (for n8n login): " ADMIN_PASSWORD
echo ""
read -p "Timezone [UTC]: " TIMEZONE
TIMEZONE=${TIMEZONE:-"UTC"}

# Generate encryption key for n8n
ENCRYPTION_KEY=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | head -c 32 | xxd -p)

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=7200  # Start after SearXNG's range (7100+)
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

# Find available port for n8n web interface
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for n8n"
fi

log "Using port: n8n=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="n8n"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/n8n"
LOCAL_FILES_DIR="$DATA_DIR/local-files"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$LOCAL_FILES_DIR" "$ICON_DIR"
chown -R 1000:1000 "$DATA_DIR" "$LOCAL_FILES_DIR" 2>/dev/null || true

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/n8n"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE ENVIRONMENT FILE =============
log "📝 Creating environment configuration..."

cat > "$INSTANCE_DIR/.env" << EOF
# Domain Configuration
DOMAIN_NAME=${DOMAIN_NAME}
SSL_EMAIL=${ADMIN_EMAIL}
GENERIC_TIMEZONE=${TIMEZONE}

# n8n Configuration
N8N_HOST=${DOMAIN_NAME}
N8N_PORT=5678
N8N_PROTOCOL=https
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
N8N_RUNNERS_ENABLED=true
N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
WEBHOOK_URL=https://${DOMAIN_NAME}/n8n/
NODE_ENV=production
TZ=${TIMEZONE}
GENERIC_TIMEZONE=${TIMEZONE}

# Initial admin credentials
N8N_USER_MANAGEMENT_DISABLED=false
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=${ADMIN_PASSWORD}
EOF

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # n8n Workflow Automation
  winejs-n8n:
    container_name: winejs-${APP_NAME}
    image: docker.n8n.io/n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:5678"
    environment:
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_HOST=${DOMAIN_NAME}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - N8N_RUNNERS_ENABLED=true
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN_NAME}/n8n/
      - GENERIC_TIMEZONE=${TIMEZONE}
      - TZ=${TIMEZONE}
      - N8N_USER_MANAGEMENT_DISABLED=false
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=${ADMIN_PASSWORD}
    volumes:
      - ${DATA_DIR}:/home/node/.n8n
      - ${LOCAL_FILES_DIR}:/files
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE CONFIG.JSON (CRITICAL FOR APP REGISTRATION) =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "n8n Workflow Automation",
    "version": "latest",
    "description": "Build powerful workflows and automate tasks with 400+ integrations",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/n8n.png",
    "category": "Productivity",
    "features": [
        "🔄 Visual workflow automation builder",
        "🔌 400+ integrations and nodes",
        "⚡ Real-time webhook triggers",
        "📅 Scheduled workflows (cron jobs)",
        "🔐 Encrypted credential storage",
        "🐳 Docker container support",
        "📊 Workflow execution history",
        "🎨 Drag-and-drop interface",
        "🧪 Built-in testing and debugging",
        "📦 Export/Import workflows",
        "🔄 REST API for programmatic access",
        "👥 User management (multi-user)"
    ]
}
CONF_EOF

# ============= CREATE INITIAL WORKFLOW SETUP SCRIPT =============
log "📝 Creating initial workflow setup script..."

cat > "$APP_DIR/setup-workflows.sh" << 'WORKFLOW_EOF'
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT="${APP_PORT}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "⏳ Waiting for n8n to be ready..."
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -s -f "http://localhost:${APP_PORT}/healthz" > /dev/null 2>&1; then
        log "✅ n8n is ready!"
        break
    fi
    log "Attempt $attempt/$max_attempts: Waiting for n8n..."
    sleep 5
    attempt=$((attempt + 1))
done

log "🎉 n8n is running!"
log "📍 Access URL: https://${DOMAIN_NAME}/n8n/"
log "🔑 Login: admin / ${ADMIN_PASSWORD}"
log ""
log "💡 Quick Start Tips:"
log "   1. Login with admin credentials"
log "   2. Click 'New Workflow' to create your first automation"
log "   3. Add nodes (HTTP, Webhook, Email, Databases, etc.)"
log "   4. Connect them to build your workflow"
log "   5. Activate to run on schedule or trigger via webhook"
log ""
log "📚 Example workflows available at:"
log "   https://n8n.io/workflows/"
WORKFLOW_EOF

chmod +x "$APP_DIR/setup-workflows.sh"

# ============= DOWNLOAD ICON =============
log "📥 Downloading n8n icon..."
curl -L "$N8N_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-n8n << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"
DATA_DIR="${DATA_DIR}"

case "\$1" in
    status)
        docker ps | grep winejs-n8n
        ;;
    logs)
        docker logs winejs-n8n --tail 50
        ;;
    restart)
        docker restart winejs-n8n
        echo "n8n restarted"
        ;;
    stop)
        docker stop winejs-n8n
        echo "n8n stopped"
        ;;
    start)
        docker start winejs-n8n
        echo "n8n started"
        ;;
    workflows)
        echo "📁 Workflows directory: \$DATA_DIR"
        echo "🔧 To export workflows: docker exec winejs-n8n n8n export:workflow --all"
        ;;
    password)
        echo "Admin password: \$ADMIN_PASSWORD"
        ;;
    webhook)
        echo "🌐 Webhook URL: https://\${DOMAIN_NAME}/n8n/webhook/"
        echo "💡 Use this for incoming webhook triggers in your workflows"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/n8n/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/n8n/"
        fi
        ;;
    *)
        echo "n8n Workflow Automation Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-n8n open        - Open n8n interface"
        echo "  winejs-n8n status      - Check server status"
        echo "  winejs-n8n logs        - View server logs"
        echo "  winejs-n8n restart     - Restart server"
        echo "  winejs-n8n stop        - Stop server"
        echo "  winejs-n8n start       - Start server"
        echo "  winejs-n8n password    - Show admin password"
        echo "  winejs-n8n webhook     - Show webhook URL"
        echo "  winejs-n8n workflows   - Show workflows location"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/n8n/"
        echo "Login: admin / \$ADMIN_PASSWORD"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-n8n

# ============= START CONTAINER =============
log "🚀 Starting n8n container..."

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

# ============= WAIT FOR N8N TO INITIALIZE =============
log "⏳ Waiting for n8n to initialize..."
sleep 10

# ============= UPDATE NGINX FOR N8N =============
log "📝 Setting up nginx reverse proxy for n8n..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    # Check if n8n routes already exist
    if ! grep -q "location /n8n" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        # Find the line with "listen 443" and insert BEFORE it
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # n8n Workflow Automation\n\
    location /n8n {\n\
        rewrite ^/n8n(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_set_header X-Forwarded-Host \\\$host;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 86400;\n\
        proxy_buffering off;\n\
        proxy_request_buffering off;\n\
        client_max_body_size 100M;\n\
    }\n\
    \n\
    # n8n webhook endpoint\n\
    location /n8n/webhook {\n\
        rewrite ^/n8n/webhook(/.*)?$ /webhook/\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_read_timeout 86400;\n\
        proxy_buffering off;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with n8n routes"
            else
                warn "Nginx test failed, restoring backup"
                cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                nginx -t && systemctl reload nginx
            fi
        fi
    else
        log "n8n routes already exist"
    fi
fi

# ============= RUN SETUP WORKFLOWS SCRIPT =============
bash "$APP_DIR/setup-workflows.sh"

# ============= RESTART TRANSLATOR TO REGISTER APP =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_n8n.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling n8n..."

docker stop winejs-n8n 2>/dev/null
docker rm winejs-n8n 2>/dev/null

rm -rf /opt/winejs/apps/n8n
rm -rf /opt/winejs/kasmvnc-instances/n8n
rm -rf /opt/winejs/data/n8n

rm -f /usr/local/bin/winejs-n8n

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# n8n Workflow Automation/,/location \/n8n\/webhook/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/n8n {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ n8n uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_n8n.sh"

# ============= FINAL HEALTH CHECK =============
log "🔍 Performing final health check..."
sleep 10

if curl -s -f "http://127.0.0.1:${APP_PORT}/healthz" > /dev/null 2>&1; then
    success "✅ n8n health check passed!"
else
    warn "⚠️ Health check may take a moment. Check: docker logs winejs-n8n"
fi

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              N8N INSTALLED ON WINEJS!                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ n8n Workflow Automation installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/n8n/"
echo ""
info "🔑 Login Credentials:"
info "   • Username: admin"
info "   • Password: $ADMIN_PASSWORD"
echo ""
info "🌐 Webhook URL:"
info "   • https://$DOMAIN_NAME/n8n/webhook/"
info "   • Use this for incoming webhook triggers"
echo ""
info "⚙️ Configuration:"
info "   • Timezone: $TIMEZONE"
info "   • Encryption Key: $ENCRYPTION_KEY"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-n8n open        # Open n8n interface"
info "   • winejs-n8n status      # Check server status"
info "   • winejs-n8n logs        # View logs"
info "   • winejs-n8n webhook     # Show webhook URL"
info "   • winejs-n8n workflows   # Show workflows location"
echo ""
info "📁 Data Directories:"
info "   • Workflows: $DATA_DIR"
info "   • Local files: $LOCAL_FILES_DIR"
info "   • Config: $DATA_DIR/.n8n.json"
echo ""
info "💡 Getting Started:"
info "   1. Login with admin credentials"
info "   2. Browse example workflows: https://n8n.io/workflows/"
info "   3. Import a workflow and customize it"
info "   4. Set up webhooks or schedule triggers"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_n8n.sh"
echo ""
success "✨ n8n is ready! Start automating at https://$DOMAIN_NAME/n8n/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"