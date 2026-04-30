#!/bin/bash
# ============================================
# Dittofeed Customer Engagement - WineJS Installer
# Adds Omni-channel Marketing Platform to WineJS
# ============================================
# App: Dittofeed
# Category: Marketing
# Features: Email, SMS, Push Notifications, User Journeys
# ============================================

DITTOFEED_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/dittofeed.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📧 Installing WineJS Dittofeed Customer Engagement..."

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

# ============= ASK FOR DITTOFEED CONFIGURATION =============
echo ""
info "📝 Dittofeed Configuration"
echo "================================"
read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

read -p "Auth mode (anonymous/single-tenant/multi-tenant) [single-tenant]: " AUTH_MODE
AUTH_MODE=${AUTH_MODE:-"single-tenant"}

if [ "$AUTH_MODE" = "single-tenant" ]; then
    read -p "Dashboard password (shared): " SHARED_PASSWORD
fi

if [ "$AUTH_MODE" = "multi-tenant" ]; then
    read -p "OIDC Provider URL: " OIDC_ISSUER
    read -p "OIDC Client ID: " OIDC_CLIENT_ID
    read -s -p "OIDC Client Secret: " OIDC_CLIENT_SECRET
    echo ""
    read -p "Auth Provider (auth0/cognito/keycloak): " AUTH_PROVIDER
fi

read -p "Enable blob storage (for attachments)? (true/false) [true]: " BLOB_STORAGE_ENABLED
BLOB_STORAGE_ENABLED=${BLOB_STORAGE_ENABLED:-true}

if [ "$BLOB_STORAGE_ENABLED" = "true" ]; then
    read -p "Blob storage endpoint [http://minio:9000]: " BLOB_ENDPOINT
    BLOB_ENDPOINT=${BLOB_ENDPOINT:-"http://minio:9000"}
    read -p "Blob storage access key: " BLOB_ACCESS_KEY
    read -s -p "Blob storage secret key: " BLOB_SECRET_KEY
    echo ""
    read -p "Blob storage bucket name [dittofeed]: " BLOB_BUCKET
    BLOB_BUCKET=${BLOB_BUCKET:-"dittofeed"}
fi

read -p "SMTP server (for email): " SMTP_HOST
read -p "SMTP port [587]: " SMTP_PORT
SMTP_PORT=${SMTP_PORT:-587}
read -p "SMTP user: " SMTP_USER
read -s -p "SMTP password: " SMTP_PASSWORD
echo ""
read -p "From email address: " FROM_EMAIL

# Generate secrets
SECRET_KEY=$(openssl rand -base64 32 | tr -d '\n=+/')
DATABASE_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/')
CLICKHOUSE_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/')

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=9100  # Start after Discount Bandit's range (9000+)
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

# Find available port for Dittofeed
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Dittofeed"
fi

log "Using port: Dittofeed=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="dittofeed"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/dittofeed"
DATA_DIR="/opt/winejs/data/dittofeed"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{postgres,clickhouse,minio,minio-bucket}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/dittofeed"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE .ENV FILE =============
log "📝 Creating environment configuration..."

cat > "$INSTANCE_DIR/.env" << EOF
# Database
DATABASE_USER=postgres
DATABASE_PASSWORD=${DATABASE_PASSWORD}
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}

# Auth
SECRET_KEY=${SECRET_KEY}
AUTH_MODE=${AUTH_MODE}
EOF

if [ "$AUTH_MODE" = "single-tenant" ]; then
    echo "PASSWORD=${SHARED_PASSWORD}" >> "$INSTANCE_DIR/.env"
fi

if [ "$AUTH_MODE" = "multi-tenant" ]; then
    cat >> "$INSTANCE_DIR/.env" << EOF
OPEN_ID_CLIENT_ID=${OIDC_CLIENT_ID}
OPEN_ID_CLIENT_SECRET=${OIDC_CLIENT_SECRET}
AUTH_PROVIDER=${AUTH_PROVIDER}
OPEN_ID_ISSUER=${OIDC_ISSUER}
SIGNOUT_URL=/dashboard/signout
EOF
fi

# Dashboard URLs
cat >> "$INSTANCE_DIR/.env" << EOF
DASHBOARD_URL=https://${DOMAIN_NAME}/engage
DASHBOARD_API_BASE=https://${DOMAIN_NAME}/engage

# SMTP
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_USER=${SMTP_USER}
SMTP_PASSWORD=${SMTP_PASSWORD}
FROM_EMAIL=${FROM_EMAIL}
EOF

if [ "$BLOB_STORAGE_ENABLED" = "true" ]; then
    cat >> "$INSTANCE_DIR/.env" << EOF
ENABLE_BLOB_STORAGE=true
BLOB_STORAGE_ENDPOINT=${BLOB_ENDPOINT}
BLOB_STORAGE_ACCESS_KEY_ID=${BLOB_ACCESS_KEY}
BLOB_STORAGE_SECRET_ACCESS_KEY=${BLOB_SECRET_KEY}
BLOB_STORAGE_BUCKET=${BLOB_BUCKET}
BLOB_STORAGE_REGION=us-east-1
EOF
fi

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << 'DOCKER_EOF'
services:
  # PostgreSQL Database
  postgres:
    image: postgres:15
    container_name: winejs-dittofeed-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${DATABASE_PASSWORD}
      POSTGRES_DB: dittofeed
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ClickHouse Analytics Database
  clickhouse-server:
    image: clickhouse/clickhouse-server:latest
    container_name: winejs-dittofeed-clickhouse
    restart: unless-stopped
    environment:
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: ${CLICKHOUSE_PASSWORD}
    volumes:
      - ${DATA_DIR}/clickhouse:/var/lib/clickhouse
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8123/ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # MinIO Blob Storage (if enabled)
  minio:
    image: minio/minio
    container_name: winejs-dittofeed-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${BLOB_STORAGE_ACCESS_KEY_ID:-minioadmin}
      MINIO_ROOT_PASSWORD: ${BLOB_STORAGE_SECRET_ACCESS_KEY:-minioadmin}
    volumes:
      - ${DATA_DIR}/minio:/data
      - ${DATA_DIR}/minio-bucket:/bucket
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

  # Create MinIO bucket
  create-bucket:
    image: minio/mc
    container_name: winejs-dittofeed-mc
    depends_on:
      - minio
    entrypoint: >
      /bin/sh -c "
      until mc config host add myminio http://minio:9000 ${BLOB_STORAGE_ACCESS_KEY_ID:-minioadmin} ${BLOB_STORAGE_SECRET_ACCESS_KEY:-minioadmin} 2>/dev/null; do
        echo 'Waiting for MinIO...';
        sleep 2;
      done;
      mc mb myminio/${BLOB_STORAGE_BUCKET:-dittofeed} --ignore-existing;
      echo 'Bucket created';
      exit 0;
      "
    networks:
      - winejs-net

  # Dittofeed Lite Service
  lite:
    image: dittofeed/dittofeed-lite:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:3000"
    environment:
      DATABASE_USER: postgres
      DATABASE_PASSWORD: ${DATABASE_PASSWORD}
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: ${CLICKHOUSE_PASSWORD}
      SECRET_KEY: ${SECRET_KEY}
      AUTH_MODE: ${AUTH_MODE}
      DASHBOARD_URL: https://${DOMAIN_NAME}/engage
      DASHBOARD_API_BASE: https://${DOMAIN_NAME}/engage
      SMTP_HOST: ${SMTP_HOST}
      SMTP_PORT: ${SMTP_PORT}
      SMTP_USER: ${SMTP_USER}
      SMTP_PASSWORD: ${SMTP_PASSWORD}
      FROM_EMAIL: ${FROM_EMAIL}
      ENABLE_BLOB_STORAGE: ${ENABLE_BLOB_STORAGE:-false}
      BLOB_STORAGE_ENDPOINT: ${BLOB_STORAGE_ENDPOINT}
      BLOB_STORAGE_ACCESS_KEY_ID: ${BLOB_STORAGE_ACCESS_KEY_ID}
      BLOB_STORAGE_SECRET_ACCESS_KEY: ${BLOB_STORAGE_SECRET_ACCESS_KEY}
      BLOB_STORAGE_BUCKET: ${BLOB_STORAGE_BUCKET}
      BLOB_STORAGE_REGION: us-east-1
    env_file:
      - .env
    depends_on:
      postgres:
        condition: service_healthy
      clickhouse-server:
        condition: service_healthy
      create-bucket:
        condition: service_completed_successfully
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= START CONTAINERS =============
log "🚀 Starting Dittofeed containers (this may take 2-3 minutes)..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Dittofeed to initialize..."
sleep 60

# Check if containers are running
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
    "name": "Dittofeed Customer Engagement",
    "version": "latest",
    "description": "Omni-channel customer engagement platform - Email, SMS, Push, and Journeys",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/dittofeed.png",
    "category": "Marketing",
    "features": [
        "📧 Email Campaigns",
        "📱 Push Notifications",
        "💬 SMS Messaging",
        "🤖 Automated User Journeys",
        "🎯 Audience Segmentation",
        "📊 Performance Analytics",
        "🎨 Drag-and-drop Templates",
        "🔌 Webhook Integrations",
        "👥 Multi-tenant Support",
        "🔐 SSO/OIDC Auth",
        "📎 File Attachments",
        "🔄 Real-time Events"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << GUIDE_EOF
# Dittofeed Customer Engagement - User Guide

## Access
- **Dashboard**: https://$DOMAIN_NAME/engage/
- **API**: https://$DOMAIN_NAME/engage/api

## Authentication Mode: $AUTH_MODE

$([ "$AUTH_MODE" = "single-tenant" ] && echo "🔐 Login with shared password: [the password you set]")
$([ "$AUTH_MODE" = "multi-tenant" ] && echo "🔐 Login via OIDC provider (Auth0/Cognito/Keycloak)")
$([ "$AUTH_MODE" = "anonymous" ] && echo "⚠️ Anonymous mode - no login required")

## Quick Start Guide

### 1. Connect User Data

**Via Segment:**
\`\`\`javascript
analytics.identify('user_id', {
  email: 'user@example.com',
  name: 'John Doe'
});
\`\`\`

**Via Dittofeed API:**
\`\`\`bash
curl -X POST https://$DOMAIN_NAME/engage/api/users \\
  -H "Content-Type: application/json" \\
  -d '{"external_id":"user123","email":"user@example.com"}'
\`\`\`

### 2. Create User Segments

1. Go to **Segments** → **Create Segment**
2. Define conditions:
   - User properties (e.g., "country = US")
   - Behavior (e.g., "purchased in last 30 days")
   - Custom attributes
3. Save and activate

### 3. Design Message Templates

**Email Templates:**
- Use built-in MJML editor
- Drag-and-drop components
- Responsive design
- Custom HTML support

**Push/SMS Templates:**
- Personalization variables
- Emoji support
- Link tracking

### 4. Create Campaigns

**Broadcasts:**
1. Go to **Broadcasts** → **Create**
2. Select segment
3. Choose template
4. Set schedule
5. Launch!

**Automated Journeys:**
1. Go to **Journeys** → **Create**
2. Drag triggers (e.g., "User Signed Up")
3. Add actions (e.g., "Send Welcome Email")
4. Set conditions (e.g., "Wait 3 days")
5. Publish journey

### 5. Integrate Channels

**Email (SMTP):**
- Configured with: $SMTP_HOST:$SMTP_PORT
- From: $FROM_EMAIL

**Push Notifications:**
- Web Push (works in browser)
- Mobile Push (iOS/Android)

**SMS (Coming Soon)**
- Twilio integration

**WhatsApp (Coming Soon)**
- Business API

## Blob Storage

$([ "$BLOB_STORAGE_ENABLED" = "true" ] && echo "✅ Blob storage ENABLED - File attachments and email images are stored in MinIO")
$([ "$BLOB_STORAGE_ENABLED" = "false" ] && echo "❌ Blob storage DISABLED")

## API Reference

### Authentication
\`\`\`bash
# Get API token from dashboard: Settings → API Keys

# Use token in requests
curl -H "Authorization: Bearer YOUR_TOKEN" \\
  https://$DOMAIN_NAME/engage/api/users
\`\`\`

### Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| /api/users | POST | Create/update user |
| /api/track | POST | Track user event |
| /api/segments | GET | List segments |
| /api/campaigns | POST | Create campaign |
| /api/broadcasts | POST | Send broadcast |

## Journey Builder Examples

### Welcome Series
\`\`\`
Trigger: User Signs Up
  ↓
Wait: 1 hour
  ↓
Condition: Has email confirmed?
  ↓ (Yes)                ↓ (No)
Send: Welcome Email   Wait: 24 hours
  ↓                    ↓
End: Journey         Send: Reminder Email
                      ↓
                    End: Journey
\`\`\`

### Abandoned Cart
\`\`\`
Trigger: Cart Abandoned
  ↓
Wait: 1 hour
  ↓
Send: "Did you forget something?"
  ↓
Wait: 24 hours
  ↓
Condition: Purchased?
  ↓ (No)
Send: "10% off coupon"
\`\`\`

## Analytics & Reporting

### Metrics Tracked
- Opens, clicks, deliveries
- Conversion rates
- Revenue attribution
- Engagement scores

### Export Data
- CSV exports
- API access
- Webhook deliveries

## Integrations

### With Changedetection
Monitor competitor campaigns and trigger journeys

### With n8n
- Create webhook triggers
- Automate audience sync
- Connect to 400+ apps

### With Huly
- Track campaign tasks
- Manage marketing calendar
- Approve content

## Webhook Events

Subscribe to:
- user.created
- campaign.sent
- email.opened
- link.clicked
- journey.entered

## Security

### Data Protection
- All PII encrypted at rest
- HTTPS required
- Audit logging

### Compliance
- GDPR ready
- CAN-SPAM compliant
- Unsubscribe management

## Troubleshooting

**Emails not sending?**
- Check SMTP credentials
- Verify from address
- Check spam folder

**Segments empty?**
- Verify user data is synced
- Check segment conditions
- Wait for data processing

**Journeys not triggering?**
- Check event names match
- Verify user exists
- Check journey status

## Commands

\`\`\`bash
# View logs
winejs-dittofeed logs

# Restart services
winejs-dittofeed restart

# Check status
winejs-dittofeed status

# Open dashboard
winejs-dittofeed open
\`\`\$

## Support

- **Docs**: https://dittofeed.com/docs
- **Discord**: Join community
- **GitHub**: Report issues
- **Email**: support@dittofeed.com
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Dittofeed icon..."

if curl -L "$DITTOFEED_LOGO_URL" -o "$ICON_DIR/dittofeed.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/dittofeed.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-dittofeed << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
AUTH_MODE="${AUTH_MODE}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/dittofeed && docker compose ps
        ;;
    logs)
        docker logs winejs-dittofeed --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/dittofeed && docker compose restart
        echo "Dittofeed restarted"
        ;;
    users)
        echo "👥 User sync status:"
        curl -s "https://\${DOMAIN_NAME}/engage/api/users/count" | jq .
        ;;
    campaigns)
        echo "📊 Campaign stats:"
        curl -s "https://\${DOMAIN_NAME}/engage/api/campaigns/stats" | jq .
        ;;
    segments)
        echo "🎯 Active segments:"
        curl -s "https://\${DOMAIN_NAME}/engage/api/segments" | jq '.data | length'
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/engage/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/engage/"
        fi
        ;;
    *)
        echo "Dittofeed Customer Engagement Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-dittofeed open        - Open dashboard"
        echo "  winejs-dittofeed status      - Check status"
        echo "  winejs-dittofeed logs        - View logs"
        echo "  winejs-dittofeed restart     - Restart"
        echo "  winejs-dittofeed users       - User stats"
        echo "  winejs-dittofeed campaigns   - Campaign stats"
        echo "  winejs-dittofeed segments    - Segment count"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/engage/"
        echo ""
        echo "Auth Mode: $AUTH_MODE"
        if [ "$AUTH_MODE" = "single-tenant" ]; then
            echo "Login: Use shared password"
        elif [ "$AUTH_MODE" = "multi-tenant" ]; then
            echo "Login: Via OIDC provider"
        else
            echo "Login: No authentication (anonymous)"
        fi
        echo ""
        echo "Blob Storage: $([ "$BLOB_STORAGE_ENABLED" = "true" ] && echo "Enabled" || echo "Disabled")"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/dittofeed/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-dittofeed

# ============= UPDATE NGINX FOR DITTOFEED =============
log "📝 Setting up nginx reverse proxy for Dittofeed..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /engage" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Dittofeed Customer Engagement\n\
    location /engage {\n\
        rewrite ^/engage(/.*)?$ /\\\$1 break;\n\
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
    }\n\
    \n\
    # Dittofeed API\n\
    location /engage/api/ {\n\
        rewrite ^/engage/api/(.*)$ /api/\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Dittofeed routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_dittofeed.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Dittofeed..."

cd /opt/winejs/kasmvnc-instances/dittofeed
docker compose down -v 2>/dev/null

rm -rf /opt/winejs/apps/dittofeed
rm -rf /opt/winejs/kasmvnc-instances/dittofeed
rm -rf /opt/winejs/data/dittofeed

rm -f /usr/local/bin/winejs-dittofeed

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Dittofeed Customer Engagement/,/location \/engage\/api\//d' /etc/nginx/sites-available/winejs
    sed -i '/location \/engage {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Dittofeed uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_dittofeed.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              DITTOFEED INSTALLED ON WINEJS!                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Dittofeed Customer Engagement Platform installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/engage/"
echo ""
info "🔐 Authentication Mode: $AUTH_MODE"
if [ "$AUTH_MODE" = "single-tenant" ]; then
    info "   • Login with shared password"
elif [ "$AUTH_MODE" = "multi-tenant" ]; then
    info "   • Login via OIDC provider"
    info "   • Provider: $AUTH_PROVIDER"
else
    info "   • No authentication (anonymous mode)"
fi
echo ""
info "📧 Email Configuration:"
info "   • SMTP: $SMTP_HOST:$SMTP_PORT"
info "   • From: $FROM_EMAIL"
echo ""
info "💾 Blob Storage:"
if [ "$BLOB_STORAGE_ENABLED" = "true" ]; then
    info "   • Enabled - MinIO at $BLOB_ENDPOINT"
    info "   • Bucket: ${BLOB_BUCKET:-dittofeed}"
else
    info "   • Disabled"
fi
echo ""
info "🎯 Key Features:"
info "   • Email campaigns"
info "   • Automated user journeys"
info "   • Audience segmentation"
info "   • Real-time analytics"
info "   • Drag-drop templates"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-dittofeed open        # Open dashboard"
info "   • winejs-dittofeed status      # Check status"
info "   • winejs-dittofeed logs        # View logs"
info "   • winejs-dittofeed users       # User stats"
info "   • winejs-dittofeed campaigns   # Campaign stats"
echo ""
info "📁 Data Directories:"
info "   • PostgreSQL: ${DATA_DIR}/postgres"
info "   • ClickHouse: ${DATA_DIR}/clickhouse"
if [ "$BLOB_STORAGE_ENABLED" = "true" ]; then
    info "   • MinIO: ${DATA_DIR}/minio"
fi
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/dittofeed/user-guide.md"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_dittofeed.sh"
echo ""
success "✨ Dittofeed is ready! Engage customers at https://$DOMAIN_NAME/engage/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Dittofeed Does:

# Dittofeed is an omni-channel customer engagement platform (alternative to OneSignal, Customer.io):
# Key Features:
#     Email Campaigns - Send broadcast or triggered emails
#     Push Notifications - Web and mobile push alerts
#     User Journeys - Automated multi-step workflows
#     Audience Segmentation - Create custom user segments
#     Template Editor - Drag-and-drop email builder (MJML)
#     Analytics Dashboard - Track opens, clicks, conversions
#     Webhook Integrations - Connect to any external service
#     Multi-tenant Support - Multiple workspaces
#     Blob Storage - File attachments with MinIO
#     API-First - REST API for everything

# Perfect For:
#     Marketing Teams - Send campaigns to users
#     Product Teams - Onboarding and retention journeys
#     E-commerce - Abandoned cart recovery
#     SaaS Companies - User activation emails
#     Newsletters - Automated content delivery