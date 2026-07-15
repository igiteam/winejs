#!/bin/bash
# ============================================
# WineJS Dagu Workflow Engine Installer
# Adds Workflow Automation & Scheduling to WineJS Platform
# ============================================
# App: Dagu
# Category: Automation
# Features: Workflow Automation, DAG Execution, Scheduling, HTTP Triggers, Monitoring
# ============================================

APP_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/dagu_logo_dark.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🚀 Installing WineJS Dagu Workflow Engine..."

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

# ============= ASK FOR ADMIN DETAILS =============
read -p "Enter admin email: " ADMIN_EMAIL
read -s -p "Enter admin password (min 8 chars): " ADMIN_PASSWORD
echo ""

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=7001
MAX_RETRIES=50
APP_PORT=""
PROMETHEUS_PORT=""
GRAFANA_PORT=""

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

# Find available port for Dagu web
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

# Find available port for Prometheus
for i in $(seq 1 $MAX_RETRIES); do
    TEST_PORT=$((APP_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        PROMETHEUS_PORT=$TEST_PORT
        break
    fi
done

# Find available port for Grafana
for i in $(seq 2 $MAX_RETRIES); do
    TEST_PORT=$((APP_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        GRAFANA_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ] || [ -z "$PROMETHEUS_PORT" ] || [ -z "$GRAFANA_PORT" ]; then
    error "Could not find available ports"
fi

log "Using ports: Dagu=$APP_PORT, Prometheus=$PROMETHEUS_PORT, Grafana=$GRAFANA_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="dagu"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/dagu"
CONFIG_DIR="/opt/winejs/config/dagu"
DAGS_DIR="/opt/winejs/data/dagu/dags"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$DAGS_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/dagu"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= GENERATE AUTHENTICATION CREDENTIALS =============
log "🔐 Generating authentication credentials..."

ADMIN_USERNAME="admin"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(openssl rand -base64 16 | tr -d '/+' | cut -c1-12)}"
API_TOKEN=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Dagu Workflow Engine
  winejs-dagu:
    image: ghcr.io/dagu-org/dagu:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:8080"
    environment:
      DAGU_HOST: 0.0.0.0
      DAGU_PORT: 8080
      DAGU_TZ: UTC
      DAGU_DEBUG: "false"
      DAGU_LOG_FORMAT: text
      DAGU_DAGS_DIR: /etc/dagu/dags
      DAGU_DATA_DIR: /var/lib/dagu/data
      DAGU_LOG_DIR: /var/lib/dagu/logs
      DAGU_UI_NAVBAR_TITLE: "WineJS Workflows"
      DAGU_SCHEDULER_PORT: 8090
      DAGU_QUEUE_ENABLED: "true"
    volumes:
      - ${DAGS_DIR}:/etc/dagu/dags
      - ${DATA_DIR}/data:/var/lib/dagu/data
      - ${DATA_DIR}/logs:/var/lib/dagu/logs
      - ${CONFIG_DIR}:/root/.config/dagu
    networks:
      - winejs-net

  # Prometheus Monitoring
  winejs-dagu-prometheus:
    image: prom/prometheus:latest
    container_name: winejs-${APP_NAME}-prometheus
    restart: unless-stopped
    ports:
      - "127.0.0.1:${PROMETHEUS_PORT}:9090"
    volumes:
      - ${DATA_DIR}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - ${DATA_DIR}/prometheus/data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    networks:
      - winejs-net

  # Grafana Dashboards
  winejs-dagu-grafana:
    image: grafana/grafana:latest
    container_name: winejs-${APP_NAME}-grafana
    restart: unless-stopped
    ports:
      - "127.0.0.1:${GRAFANA_PORT}:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: ${API_TOKEN:0:12}
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_INSTALL_PLUGINS: grafana-piechart-panel
    volumes:
      - ${DATA_DIR}/grafana/data:/var/lib/grafana
      - ${DATA_DIR}/grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ${DATA_DIR}/grafana/datasources:/etc/grafana/provisioning/datasources
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE PROMETHEUS CONFIG =============
log "📊 Creating Prometheus configuration..."

mkdir -p "$DATA_DIR/prometheus"
cat > "$DATA_DIR/prometheus/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'dagu'
    static_configs:
      - targets: ['winejs-dagu:8090']
    metrics_path: '/metrics'
    scrape_interval: 5s

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF

# ============= CREATE GRAFANA CONFIG =============
log "📈 Creating Grafana configuration..."

mkdir -p "$DATA_DIR/grafana/dashboards" "$DATA_DIR/grafana/datasources"

cat > "$DATA_DIR/grafana/datasources/prometheus.yml" << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://winejs-dagu-prometheus:9090
    isDefault: true
EOF

# Create a basic Dagu dashboard for Grafana
cat > "$DATA_DIR/grafana/dashboards/dagu-dashboard.yml" << 'EOF'
apiVersion: 1

providers:
  - name: 'Dagu'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

# ============= CREATE DAGU CONFIG FILE =============
log "⚙️ Creating Dagu configuration..."

mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/config.yaml" << AUTH_EOF
# Dagu Authentication Configuration
auth:
  basic:
    username: "$ADMIN_USERNAME"
    password: "$ADMIN_PASSWORD"
  token:
    value: "$API_TOKEN"

# Permissions
permissions:
  writeDAGs: true
  runDAGs: true

# Web UI Settings
web:
  title: "WineJS Workflow Engine"
  navbarTitle: "Dagu Workflows"

# Scheduler
scheduler:
  port: 8090
  queueEnabled: true
AUTH_EOF

chmod 600 "$CONFIG_DIR/config.yaml"

# ============= CREATE SAMPLE WORKFLOWS =============
log "📝 Creating sample workflows..."

# Simple hello world workflow
cat > "$DAGS_DIR/hello-world.yaml" << 'EOF'
name: hello-world
description: A simple sequential workflow
schedule: "0 9 * * *"  # Run daily at 9 AM

steps:
  - name: say-hello
    command: echo "Hello from Dagu on WineJS!"
    
  - name: show-date
    command: date
    
  - name: complete
    command: echo "Workflow completed successfully!"
EOF

# Parallel processing workflow
cat > "$DAGS_DIR/parallel-processing.yaml" << 'EOF'
name: parallel-processing
description: Execute multiple tasks in parallel

steps:
  - name: setup
    command: echo "Starting parallel execution"
  
  - name: task-a
    command: echo "Task A running"
    depends: setup
    
  - name: task-b
    command: echo "Task B running" 
    depends: setup
    
  - name: task-c
    command: echo "Task C running"
    depends: setup
    
  - name: final-step
    command: echo "All parallel tasks completed"
    depends: [task-a, task-b, task-c]
EOF

# HTTP health check workflow
cat > "$DAGS_DIR/http-check.yaml" << 'EOF'
name: http-health-check
description: Monitor website health with HTTP requests
schedule: "*/5 * * * *"  # Every 5 minutes

steps:
  - name: check-winejs
    executor:
      type: http
      config:
        url: https://__DOMAIN__
        method: GET
    timeout: 10s
    
  - name: check-api
    executor:
      type: http
      config:
        url: https://__DOMAIN__/api/health
        method: GET
    timeout: 5s
EOF

# Backup workflow example
cat > "$DAGS_DIR/backup-workflows.yaml" << 'EOF'
name: backup-dags
description: Backup DAG workflows to local archive
schedule: "0 2 * * *"  # Daily at 2 AM

steps:
  - name: create-backup-dir
    command: mkdir -p /var/lib/dagu/backups
    
  - name: tar-dags
    command: tar -czf /var/lib/dagu/backups/dags-$(date +%Y%m%d).tar.gz /etc/dagu/dags/
    
  - name: cleanup-old
    command: find /var/lib/dagu/backups -name "*.tar.gz" -mtime +7 -delete
EOF

# Replace domain placeholder in http-check workflow
sed -i "s/__DOMAIN__/${DOMAIN_NAME}/g" "$DAGS_DIR/http-check.yaml"

# ============= CREATE ADMIN SETUP SCRIPT =============
log "🔧 Creating admin setup script..."

cat > "$APP_DIR/setup-admin.sh" << 'ADMIN_EOF'
#!/bin/bash

APP_PORT="${APP_PORT}"
ADMIN_USERNAME="${ADMIN_USERNAME}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"
API_TOKEN="${API_TOKEN}"
DOMAIN_NAME="${DOMAIN_NAME}"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "Waiting for Dagu to start..."
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -s -f "http://localhost:${APP_PORT}/api/v1/health" > /dev/null 2>&1; then
        log "✅ Dagu is ready!"
        break
    fi
    log "Attempt $attempt/$max_attempts: Waiting for Dagu..."
    sleep 5
    attempt=$((attempt + 1))
done

# Test authentication
log "Testing authentication..."
AUTH_WORKING=false
for i in {1..10}; do
    if curl -f -s -u "$ADMIN_USERNAME:$ADMIN_PASSWORD" "http://localhost:${APP_PORT}/api/v2/dags" > /dev/null 2>&1; then
        AUTH_WORKING=true
        break
    fi
    sleep 3
done

if [ "$AUTH_WORKING" = true ]; then
    log "✅ Authentication is working"
else
    log "⚠️ Authentication may need manual verification"
fi

log "✅ Admin setup complete. Login at: https://${DOMAIN_NAME}/dagu"
ADMIN_EOF

chmod +x "$APP_DIR/setup-admin.sh"

# ============= CREATE CONFIG.JSON (CRITICAL FOR APP REGISTRATION) =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Dagu Workflow Engine",
    "version": "latest",
    "description": "Automate workflows, schedule tasks, and orchestrate processes with DAG-based execution",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/dagu.png",
    "category": "Automation",
    "features": [
        "DAG-based workflow automation",
        "Cron-style scheduling",
        "HTTP/webhook triggers",
        "Parallel task execution",
        "Prometheus metrics",
        "Grafana dashboards",
        "REST API for automation",
        "Queue management",
        "Container support",
        "Email notifications"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading Dagu icon..."
curl -L "$APP_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# Also create SVG version for better quality
cat > "$ICON_DIR/${APP_NAME}.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <rect width="100" height="100" rx="20" fill="#2D3748"/>
  <text x="50" y="68" font-size="45" text-anchor="middle" fill="#48BB78">⏵</text>
  <circle cx="25" cy="50" r="8" fill="#48BB78"/>
  <circle cx="50" cy="75" r="8" fill="#48BB78"/>
  <circle cx="75" cy="50" r="8" fill="#48BB78"/>
  <line x1="33" y1="50" x2="42" y2="50" stroke="#48BB78" stroke-width="3"/>
  <line x1="58" y1="65" x2="67" y2="60" stroke="#48BB78" stroke-width="3"/>
  <line x1="58" y1="35" x2="67" y2="40" stroke="#48BB78" stroke-width="3"/>
</svg>
SVG_EOF

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-dagu << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}
PROMETHEUS_PORT=${PROMETHEUS_PORT}
GRAFANA_PORT=${GRAFANA_PORT}

case "\$1" in
    status)
        docker ps | grep winejs-dagu
        ;;
    logs)
        docker logs winejs-dagu --tail 50
        ;;
    restart)
        docker restart winejs-dagu
        ;;
    workflows)
        echo "Available workflows:"
        ls -la /opt/winejs/data/dagu/dags/
        ;;
    run)
        shift
        if [ -z "\$1" ]; then
            echo "Usage: winejs-dagu run <workflow-name>"
            echo "Available: $(ls /opt/winejs/data/dagu/dags/ | sed 's/\.yaml$//' | tr '\n' ' ')"
        else
            curl -X POST -u "admin:${ADMIN_PASSWORD}" \\
                "http://localhost:\${APP_PORT}/api/v1/dags/\$1/start"
        fi
        ;;
    token)
        echo "API Token: ${API_TOKEN}"
        echo ""
        echo "Usage:"
        echo "  curl -H \"Authorization: Bearer ${API_TOKEN}\" https://\${DOMAIN_NAME}/dagu/api/v2/dags"
        ;;
    metrics)
        echo "Prometheus: http://localhost:\${PROMETHEUS_PORT}"
        echo "Grafana: http://localhost:\${GRAFANA_PORT} (admin/${API_TOKEN:0:12})"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/dagu/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/dagu/"
        fi
        ;;
    *)
        echo "Dagu Workflow Engine"
        echo ""
        echo "Commands:"
        echo "  winejs-dagu open        - Open Dagu UI in browser"
        echo "  winejs-dagu status      - Check service status"
        echo "  winejs-dagu logs        - View container logs"
        echo "  winejs-dagu restart     - Restart Dagu"
        echo "  winejs-dagu workflows   - List available workflows"
        echo "  winejs-dagu run <name>  - Run a workflow"
        echo "  winejs-dagu token       - Show API token"
        echo "  winejs-dagu metrics     - Show monitoring URLs"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-dagu

# ============= START CONTAINER =============
log "🚀 Starting Dagu container..."

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

# ============= SETUP ADMIN USER =============
bash "$APP_DIR/setup-admin.sh"

# ============= UPDATE NGINX CONFIG =============
log "📝 Updating nginx configuration for Dagu..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    # Check if Dagu routes already exist
    if ! grep -q "location /dagu" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        # Find the line with "listen 443" and insert BEFORE it
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Dagu Workflow Engine\n\
    location /dagu {\n\
        rewrite ^/dagu(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 86400s;\n\
        proxy_buffering off;\n\
        proxy_request_buffering off;\n\
    }\n\
\n\
    # Dagu API endpoints\n\
    location /dagu/api/ {\n\
        rewrite ^/dagu/api(/.*)?$ /api\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Dagu routes"
            else
                warn "Nginx test failed, restoring backup"
                cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                nginx -t && systemctl reload nginx
            fi
        fi
    else
        log "Dagu routes already exist"
    fi
fi

# ============= RESTART TRANSLATOR TO REGISTER APP =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_dagu.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Dagu..."

docker stop winejs-dagu winejs-dagu-prometheus winejs-dagu-grafana 2>/dev/null
docker rm winejs-dagu winejs-dagu-prometheus winejs-dagu-grafana 2>/dev/null

rm -rf /opt/winejs/apps/dagu
rm -rf /opt/winejs/kasmvnc-instances/dagu
rm -rf /opt/winejs/data/dagu
rm -rf /opt/winejs/config/dagu

rm -f /usr/local/bin/winejs-dagu

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Dagu Workflow Engine/,/location \/dagu\/api/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/dagu {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Dagu uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_dagu.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           DAGU WORKFLOW ENGINE INSTALLED ON WINEJS!            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Dagu Workflow Engine installed!"
echo ""
info "🌐 Access URLs:"
info "   • Dagu UI: https://$DOMAIN_NAME/dagu/"
info "   • Prometheus: http://localhost:${PROMETHEUS_PORT}"
info "   • Grafana: http://localhost:${GRAFANA_PORT}"
echo ""
info "🔑 Authentication Credentials:"
info "   • Username: $ADMIN_USERNAME"
info "   • Password: $ADMIN_PASSWORD"
info "   • API Token: $API_TOKEN"
echo ""
info "📁 Directory Structure:"
info "   • Workflows: /opt/winejs/data/dagu/dags/"
info "   • Data: /opt/winejs/data/dagu/data/"
info "   • Logs: /opt/winejs/data/dagu/logs/"
echo ""
info "📝 Sample Workflows (ready to use):"
info "   • hello-world.yaml - Simple task sequence"
info "   • parallel-processing.yaml - Parallel execution"
info "   • http-check.yaml - Website monitoring"
info "   • backup-dags.yaml - Automated backups"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-dagu open        # Open Dagu UI"
info "   • winejs-dagu status      # Check status"
info "   • winejs-dagu workflows   # List workflows"
info "   • winejs-dagu run <name>  # Run a workflow"
info "   • winejs-dagu token       # Show API token"
info "   • winejs-dagu metrics     # Show monitoring URLs"
echo ""
info "🔗 API Usage Examples:"
echo ""
echo "   # List workflows using API token"
echo "   curl -H \"Authorization: Bearer $API_TOKEN\" \\"
echo "        https://$DOMAIN_NAME/dagu/api/v2/dags"
echo ""
echo "   # Run a workflow"
echo "   curl -X POST -H \"Authorization: Bearer $API_TOKEN\" \\"
echo "        https://$DOMAIN_NAME/dagu/api/v2/dags/hello-world/start"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_dagu.sh"
echo ""
success "✨ Dagu is ready! Visit https://$DOMAIN_NAME/dagu/"
echo ""

echo "Find all uninstall scripts in the apps directory:"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"