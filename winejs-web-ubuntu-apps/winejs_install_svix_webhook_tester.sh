#!/bin/bash
# ============================================
# Webhook Tester - WineJS Installer
# Adds Webhook Testing & Debugging to WineJS
# ============================================
# App: Webhook Tester
# Category: Development
# Features: Webhook Testing, HTTP Request Inspection, Real-time Debugging
# ============================================

WEBHOOK_TESTER_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/webhook-tester-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🔌 Installing WineJS Webhook Tester..."

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

# ============= ASK FOR WEBHOOK TESTER CONFIGURATION =============
echo ""
info "📝 Webhook Tester Configuration"
echo "================================"
read -p "Admin email: " ADMIN_EMAIL

read -p "Maximum requests per session [128]: " MAX_REQUESTS
MAX_REQUESTS=${MAX_REQUESTS:-128}

read -p "Session TTL (days) [7]: " SESSION_TTL_DAYS
SESSION_TTL_DAYS=${SESSION_TTL_DAYS:-7}
SESSION_TTL="${SESSION_TTL_DAYS}d"

read -p "Storage driver (memory/redis/fs) [memory]: " STORAGE_DRIVER
STORAGE_DRIVER=${STORAGE_DRIVER:-"memory"}

read -p "Enable auto-create sessions? (true/false) [true]: " AUTO_CREATE
AUTO_CREATE=${AUTO_CREATE:-true}

read -p "Enable ngrok tunneling? (true/false) [false]: " TUNNEL_ENABLED
TUNNEL_ENABLED=${TUNNEL_ENABLED:-false}

if [ "$TUNNEL_ENABLED" = "true" ]; then
    read -p "Ngrok auth token: " NGROK_TOKEN
fi

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=10100  # Start after SolidInvoice's range (10000+)
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

# Find available port for Webhook Tester
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Webhook Tester"
fi

log "Using port: Webhook Tester=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="webhook-tester"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/webhook-tester"
DATA_DIR="/opt/winejs/data/webhook-tester"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/webhook-tester"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

# Build command args
CMD_ARGS="start"
CMD_ARGS="$CMD_ARGS --port=8080"
CMD_ARGS="$CMD_ARGS --max-requests=$MAX_REQUESTS"
CMD_ARGS="$CMD_ARGS --session-ttl=$SESSION_TTL"
CMD_ARGS="$CMD_ARGS --storage-driver=$STORAGE_DRIVER"
if [ "$AUTO_CREATE" = "true" ]; then
    CMD_ARGS="$CMD_ARGS --auto-create-sessions"
fi

if [ "$STORAGE_DRIVER" = "fs" ]; then
    CMD_ARGS="$CMD_ARGS --fs-storage-dir=/data"
fi

if [ "$TUNNEL_ENABLED" = "true" ] && [ -n "$NGROK_TOKEN" ]; then
    CMD_ARGS="$CMD_ARGS --tunnel-driver=ngrok --ngrok-auth-token=$NGROK_TOKEN"
fi

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Webhook Tester
  winejs-webhook-tester:
    image: ghcr.io/tarampampam/webhook-tester:2
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:8080"
    volumes:
      - ${DATA_DIR}:/data
    command: ${CMD_ARGS}
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "/bin/app", "start", "healthcheck", "--port=8080"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= START CONTAINER =============
log "🚀 Starting Webhook Tester container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Webhook Tester to initialize..."
sleep 10

if docker ps | grep -q "winejs-${APP_NAME}"; then
    success "✅ Container started successfully"
else
    warn "⚠️ Container may not have started. Check: docker logs winejs-${APP_NAME}"
    docker logs winejs-${APP_NAME} --tail 20
fi

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Webhook Tester",
    "version": "latest",
    "description": "Test and debug webhooks with unique URLs and real-time notifications",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/webhook-tester.png",
    "category": "Development",
    "features": [
        "🔌 Webhook Testing",
        "📡 Real-time WebSocket Updates",
        "🎨 Customizable Responses",
        "📊 Request History",
        "🔗 Unique URLs per Session",
        "⚡ Zero Dependencies Option",
        "🐳 Multi-arch Docker Support",
        "📦 Binary Request View",
        "🔄 Tunneling Support (ngrok)",
        "💾 Multiple Storage Backends",
        "🔍 Request Inspection",
        "📝 JSON/Human-readable Logs"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << GUIDE_EOF
# Webhook Tester - User Guide

## Access
- **Web Interface**: https://$DOMAIN_NAME/webhooks/

## Getting Started

### 1. Create a Test URL

When you visit Webhook Tester, a unique URL is automatically generated for you:
\`\`\`
https://$DOMAIN_NAME/webhooks/uuid-here/
\`\`\`

### 2. Send a Webhook

Use this URL as your webhook endpoint in any service:

\`\`\`bash
# Example: Send a test webhook
curl -X POST https://$DOMAIN_NAME/webhooks/your-uuid/ \\
  -H "Content-Type: application/json" \\
  -d '{"event":"test","data":{"message":"Hello World"}}'
\`\`\`

### 3. Inspect Requests

Any requests sent to your URL appear instantly in the UI via WebSocket - no refresh needed!

You'll see:
- HTTP method (GET, POST, PUT, etc.)
- Headers
- Body content
- Query parameters
- Timestamp

### 4. Customize Responses

**Set Status Code**:
Add status code to URL:
\`\`\`
https://$DOMAIN_NAME/webhooks/uuid/404
\`\`\`

**Custom Response Body**:
\`\`\`bash
curl -X POST https://$DOMAIN_NAME/webhooks/uuid/ \\
  -H "X-Response-Status: 201" \\
  -H "X-Response-Content-Type: application/json" \\
  -H "X-Response-Body: {\"status\":\"ok\"}"
\`\`\`

## Configuration

### Current Settings
- **Max Requests per Session**: $MAX_REQUESTS
- **Session TTL**: $SESSION_TTL_DAYS days
- **Storage Driver**: $STORAGE_DRIVER
- **Auto-create Sessions**: $AUTO_CREATE
- **Tunneling**: $([ "$TUNNEL_ENABLED" = "true" ] && echo "Enabled" || echo "Disabled")

### Storage Options

**Memory** (default):
- Fastest, no persistence
- Data lost on restart
- Best for testing

**File System**:
- Persistent across restarts
- Data saved in ${DATA_DIR}
- Good for long-term testing

**Redis**:
- For multi-instance setups
- Persistent
- Requires Redis server

## Advanced Features

### Custom Response Headers

Add custom response headers to your webhook:
\`\`\`bash
curl -X POST https://$DOMAIN_NAME/webhooks/uuid/ \\
  -H "X-Response-Header-X-Custom: my-value" \\
  -H "X-Response-Status: 202"
\`\`\`

### Response Delay

Simulate slow responses:
\`\`\`bash
curl -X POST https://$DOMAIN_NAME/webhooks/uuid/ \\
  -H "X-Response-Delay: 5s"  # 5 second delay
\`\`\`

### Binary Data

View binary requests in the UI - great for file upload testing.

### Request History

Each session stores up to $MAX_REQUESTS requests. Oldest requests are dropped when limit reached.

## Integration Examples

### GitHub Webhooks
1. Create a test URL in Webhook Tester
2. In GitHub repo → Settings → Webhooks
3. Add your URL: \`https://$DOMAIN_NAME/webhooks/your-uuid/\`
4. Send test payload
5. Inspect in Webhook Tester UI

### Stripe Webhooks
1. Get your Webhook Tester URL
2. In Stripe Dashboard → Webhooks → Add endpoint
3. Paste your URL
4. Select events to listen for
5. Send test webhook

### n8n Workflows
Use Webhook Tester to debug webhook nodes:
1. Add Webhook node in n8n
2. Get test URL from Webhook Tester
3. Configure n8n to send to that URL
4. Inspect payload format

### Svix
Test webhook deliveries:
1. Create endpoint in Svix
2. Point to Webhook Tester URL
3. Trigger message
4. See exactly what was sent

## Tunneling

$([ "$TUNNEL_ENABLED" = "true" ] && echo "Tunneling is ENABLED - your local instance is exposed via ngrok. You'll receive a public URL when the container starts." || echo "Tunneling is DISABLED - only accessible within your network.")

## Use Cases

### Development
- Debug webhook integrations locally
- Test payload formats
- Verify retry logic

### QA Testing
- Automated webhook testing
- Load testing webhooks
- Error handling verification

### Production Monitoring
- Webhook health checks
- Request inspection
- Audit logging

### Troubleshooting
- See exactly what's being sent
- Compare expected vs actual payloads
- Debug authentication issues

## Integration with WineJS Apps

### With n8n
- Test webhook triggers
- Debug HTTP request nodes
- Inspect webhook payloads

### With Svix
- Test webhook deliveries
- Debug message formatting
- Verify signatures

### With Forgejo/Gitea
- Test repo webhooks
- Debug CI/CD triggers
- Verify payload structure

### With Changedetection
- Monitor webhook notifications
- Verify price drop alerts
- Test notification formats

## Security

### URL Privacy
- URLs are UUID-based (unpredictable)
- No authentication by default
- Keep URLs secret for sensitive data

### HTTPS
- Always use HTTPS in production
- Webhook Tester supports HTTPS via reverse proxy

### Data Retention
- Sessions expire after $SESSION_TTL_DAYS days of inactivity
- Maximum $MAX_REQUESTS requests per session
- Data automatically cleaned up

## Commands

\`\`\`bash
# View logs
winejs-webhook-tester logs

# Restart services
winejs-webhook-tester restart

# Check status
winejs-webhook-tester status

# Open interface
winejs-webhook-tester open
\`\`\`

## Troubleshooting

**Requests not appearing?**
- Check WebSocket connection (browser console)
- Verify correct URL
- Check network connectivity

**Response not customizing?**
- Check header names (X-Response-*)
- Verify header values
- Check container logs

**Session expired?**
- Sessions expire after $SESSION_TTL_DAYS days of no activity
- Create new session by refreshing page

## Support

- **GitHub**: https://github.com/tarampampam/webhook-tester
- **Demo**: https://wh.tarampamp.am

## Pro Tips

1. **Bookmark your session URLs** - they're unique and reusable
2. **Use descriptive UUIDs** if auto-create is enabled
3. **Export request data** for documentation
4. **Test edge cases** - slow responses, 5xx errors
5. **Combine with ngrok** for external testing
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Webhook Tester icon..."

# Try to download the icon
if curl -L "$WEBHOOK_TESTER_LOGO_URL" -o "$ICON_DIR/webhook-tester.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/webhook-tester.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M3 12h3l3-9 3 18 3-9h3"/>
  <path d="M18 8l3 4-3 4"/>
  <path d="M6 8l-3 4 3 4"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-webhook-tester << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/webhook-tester && docker compose ps
        ;;
    logs)
        docker logs winejs-webhook-tester --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/webhook-tester && docker compose restart
        echo "Webhook Tester restarted"
        ;;
    url)
        echo "🔗 Your test URL format:"
        echo "  https://\${DOMAIN_NAME}/webhooks/[uuid]/"
        echo ""
        echo "Visit the web interface to get your unique URL"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/webhooks/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/webhooks/"
        fi
        ;;
    *)
        echo "Webhook Tester Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-webhook-tester open        # Open web interface"
        echo "  winejs-webhook-tester status      # Check status"
        echo "  winejs-webhook-tester logs        # View logs"
        echo "  winejs-webhook-tester restart     # Restart"
        echo "  winejs-webhook-tester url         # Show URL format"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/webhooks/"
        echo ""
        echo "Settings:"
        echo "  • Max Requests: $MAX_REQUESTS"
        echo "  • Session TTL: $SESSION_TTL_DAYS days"
        echo "  • Storage Driver: $STORAGE_DRIVER"
        echo "  • Auto-create: $AUTO_CREATE"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/webhook-tester/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-webhook-tester

# ============= UPDATE NGINX FOR WEBHOOK TESTER =============
log "📝 Setting up nginx reverse proxy for Webhook Tester..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /webhooks" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Webhook Tester\n\
    location /webhooks {\n\
        rewrite ^/webhooks(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 60s;\n\
        proxy_buffering off;\n\
        client_max_body_size 10M;\n\
    }\n\
    \n\
    # Webhook Tester WebSocket\n\
    location /webhooks/ws {\n\
        rewrite ^/webhooks/ws(.*)$ /ws\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_read_timeout 86400s;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Webhook Tester routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_webhook-tester.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Webhook Tester..."

cd /opt/winejs/kasmvnc-instances/webhook-tester
docker compose down -v 2>/dev/null

# Ask about removing data
read -p "Remove all stored webhook data? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /opt/winejs/apps/webhook-tester
    rm -rf /opt/winejs/kasmvnc-instances/webhook-tester
    rm -rf /opt/winejs/data/webhook-tester
    log "✅ All data removed"
else
    rm -rf /opt/winejs/apps/webhook-tester
    rm -rf /opt/winejs/kasmvnc-instances/webhook-tester
fi

rm -f /usr/local/bin/winejs-webhook-tester

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Webhook Tester/,/location \/webhooks\/ws/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/webhooks {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Webhook Tester uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_webhook-tester.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           WEBHOOK TESTER INSTALLED ON WINEJS!                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Webhook Tester installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/webhooks/"
echo ""
info "🔧 Configuration:"
info "   • Max Requests: $MAX_REQUESTS"
info "   • Session TTL: $SESSION_TTL_DAYS days"
info "   • Storage Driver: $STORAGE_DRIVER"
info "   • Auto-create Sessions: $AUTO_CREATE"
if [ "$TUNNEL_ENABLED" = "true" ]; then
    info "   • Ngrok Tunneling: Enabled"
fi
echo ""
info "🔌 Features:"
info "   • Real-time WebSocket updates"
info "   • Customizable responses (status, headers, body)"
info "   • Request inspection (headers, body, params)"
info "   • Binary request viewing"
info "   • Session persistence"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-webhook-tester open        # Open interface"
info "   • winejs-webhook-tester status      # Check status"
info "   • winejs-webhook-tester logs        # View logs"
info "   • winejs-webhook-tester url         # Show URL format"
echo ""
info "📁 Data Directory:"
info "   • ${DATA_DIR}"
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/webhook-tester/user-guide.md"
echo ""
info "💡 Getting Started:"
info "   1. Visit the URL above"
info "   2. Copy your unique test URL"
info "   3. Configure webhook in your app/service"
info "   4. Send test webhook"
info "   5. Watch requests appear in real-time!"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_webhook-tester.sh"
echo ""
success "✨ Webhook Tester is ready! Start testing webhooks at https://$DOMAIN_NAME/webhooks/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Webhook Tester Does:

# Webhook Tester is a tool for testing and debugging webhooks - perfect for developers:
# Key Features:
#     Unique URLs - Generate random URLs for each test session
#     Real-time Updates - WebSocket connections show requests instantly
#     Request Inspection - View headers, body, query parameters
#     Customizable Responses - Set status codes, headers, response body
#     Binary Viewing - Inspect binary request data
#     Tunneling Support - Expose local instance via ngrok
#     Multiple Storage - Memory, Redis, or filesystem backends
#     Zero Dependencies - Can run standalone without Redis

# Perfect For:
#     Developers - Debug webhook integrations
#     QA Teams - Test webhook payloads
#     Integration Testing - Verify webhook formats
#     Troubleshooting - See exactly what's being sent
#     Education - Learn how webhooks work