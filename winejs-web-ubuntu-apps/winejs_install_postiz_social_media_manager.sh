#!/bin/bash
# ============================================
# Postiz Social Media Manager - WineJS Installer
# Adds Social Media Management to WineJS Platform
# ============================================
# App: Postiz
# Category: Marketing
# Features: Social Media Scheduling, AI Posts, Analytics
# ============================================

POSTIZ_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/postiz-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📱 Installing WineJS Postiz Social Media Manager..."

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

# ============= ASK FOR POSTIZ CONFIGURATION =============
echo ""
info "📝 Postiz Configuration"
echo "================================"
read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

# Generate secrets
JWT_SECRET=$(openssl rand -base64 32 | tr -d '\n=+/')
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/')
TEMPORAL_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/')

read -p "Enable OpenAI integration? (true/false) [false]: " OPENAI_ENABLED
if [ "$OPENAI_ENABLED" = "true" ]; then
    read -p "OpenAI API Key: " OPENAI_API_KEY
fi

read -p "Enable email notifications? (true/false) [false]: " EMAIL_ENABLED
if [ "$EMAIL_ENABLED" = "true" ]; then
    read -p "Email provider (resend/nodemailer) [nodemailer]: " EMAIL_PROVIDER
    EMAIL_PROVIDER=${EMAIL_PROVIDER:-"nodemailer"}
    if [ "$EMAIL_PROVIDER" = "resend" ]; then
        read -p "Resend API Key: " RESEND_API_KEY
    else
        read -p "SMTP Host: " SMTP_HOST
        read -p "SMTP Port [587]: " SMTP_PORT
        SMTP_PORT=${SMTP_PORT:-587}
        read -p "SMTP User: " SMTP_USER
        read -s -p "SMTP Password: " SMTP_PASSWORD
        echo ""
    fi
fi

read -p "Storage provider (local/cloudflare) [local]: " STORAGE_PROVIDER
STORAGE_PROVIDER=${STORAGE_PROVIDER:-"local"}

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=10300  # Start after Sympa's range (10200+)
MAX_RETRIES=50
APP_PORT=""
TEMPORAL_UI_PORT=8081

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

# Find available port for Postiz
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Postiz"
fi

log "Using ports: Postiz=$APP_PORT, Temporal UI=$TEMPORAL_UI_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="postiz"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/postiz"
DATA_DIR="/opt/winejs/data/postiz"
CONFIG_DIR="/opt/winejs/config/postiz"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{postgres,redis,uploads,config,temporal-elasticsearch,temporal-postgresql}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/postiz"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE .ENV FILE =============
log "📝 Creating configuration file..."

cat > "$CONFIG_DIR/postiz.env" << EOF
# === Required Settings
DATABASE_URL="postgresql://postiz-user:${DB_PASSWORD}@postiz-postgres:5432/postiz-db-local"
REDIS_URL="redis://postiz-redis:6379"
JWT_SECRET="${JWT_SECRET}"
FRONTEND_URL="https://${DOMAIN_NAME}/social"
NEXT_PUBLIC_BACKEND_URL="https://${DOMAIN_NAME}/social/api"
BACKEND_INTERNAL_URL="http://localhost:3000"
TEMPORAL_ADDRESS="temporal:7233"
IS_GENERAL="true"
DISABLE_REGISTRATION="false"

# === Storage Settings
STORAGE_PROVIDER="${STORAGE_PROVIDER}"
UPLOAD_DIRECTORY="/uploads"
NEXT_PUBLIC_UPLOAD_DIRECTORY="/uploads"

# === AI Settings
${OPENAI_API_KEY:+OPENAI_API_KEY="${OPENAI_API_KEY}"}

# === Email Settings
EOF

if [ "$EMAIL_ENABLED" = "true" ]; then
    cat >> "$CONFIG_DIR/postiz.env" << EOF
EMAIL_PROVIDER="${EMAIL_PROVIDER}"
EMAIL_FROM_ADDRESS="noreply@${DOMAIN_NAME}"
EMAIL_FROM_NAME="Postiz Social Manager"
EOF
    if [ "$EMAIL_PROVIDER" = "resend" ]; then
        echo "RESEND_API_KEY=\"${RESEND_API_KEY}\"" >> "$CONFIG_DIR/postiz.env"
    else
        cat >> "$CONFIG_DIR/postiz.env" << EOF
EMAIL_HOST="${SMTP_HOST}"
EMAIL_PORT="${SMTP_PORT}"
EMAIL_SECURE="true"
EMAIL_USER="${SMTP_USER}"
EMAIL_PASS="${SMTP_PASSWORD}"
EOF
    fi
fi

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml (this may take a moment)..."

cat > "$INSTANCE_DIR/docker-compose.yml" << 'DOCKER_EOF'
services:
  # PostgreSQL Database
  postiz-postgres:
    image: postgres:17-alpine
    container_name: winejs-postiz-db
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: DB_PASSWORD_PLACEHOLDER
      POSTGRES_USER: postiz-user
      POSTGRES_DB: postiz-db-local
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postiz-user -d postiz-db-local"]
      interval: 10s
      timeout: 3s
      retries: 5

  # Redis Cache
  postiz-redis:
    image: redis:7.2
    container_name: winejs-postiz-redis
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - winejs-net

  # Temporal Elasticsearch
  temporal-elasticsearch:
    image: elasticsearch:7.17.27
    container_name: winejs-postiz-elasticsearch
    restart: unless-stopped
    environment:
      - cluster.routing.allocation.disk.threshold_enabled=true
      - cluster.routing.allocation.disk.watermark.low=512mb
      - cluster.routing.allocation.disk.watermark.high=256mb
      - cluster.routing.allocation.disk.watermark.flood_stage=128mb
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms256m -Xmx256m
      - xpack.security.enabled=false
    networks:
      - winejs-net
    volumes:
      - ${DATA_DIR}/temporal-elasticsearch:/usr/share/elasticsearch/data

  # Temporal PostgreSQL
  temporal-postgresql:
    image: postgres:16
    container_name: winejs-postiz-temporal-db
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: TEMPORAL_PASSWORD_PLACEHOLDER
      POSTGRES_USER: temporal
    networks:
      - winejs-net
    volumes:
      - ${DATA_DIR}/temporal-postgresql:/var/lib/postgresql/data

  # Temporal Server
  temporal:
    image: temporalio/auto-setup:1.28.1
    container_name: winejs-postiz-temporal
    restart: unless-stopped
    ports:
      - "127.0.0.1:7233:7233"
    depends_on:
      - temporal-postgresql
      - temporal-elasticsearch
    environment:
      - DB=postgres12
      - DB_PORT=5432
      - POSTGRES_USER=temporal
      - POSTGRES_PWD=TEMPORAL_PASSWORD_PLACEHOLDER
      - POSTGRES_SEEDS=temporal-postgresql
      - DYNAMIC_CONFIG_FILE_PATH=config/dynamicconfig/development-sql.yaml
      - ENABLE_ES=true
      - ES_SEEDS=temporal-elasticsearch
      - ES_VERSION=v7
      - TEMPORAL_NAMESPACE=default
    networks:
      - winejs-net

  # Temporal UI
  temporal-ui:
    image: temporalio/ui:2.34.0
    container_name: winejs-postiz-temporal-ui
    restart: unless-stopped
    environment:
      - TEMPORAL_ADDRESS=temporal:7233
      - TEMPORAL_CORS_ORIGINS=https://${DOMAIN_NAME}
    networks:
      - winejs-net
    ports:
      - "127.0.0.1:${TEMPORAL_UI_PORT}:8080"

  # Postiz Main Application
  postiz:
    image: ghcr.io/gitroomhq/postiz-app:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:5000"
    volumes:
      - ${DATA_DIR}/uploads:/uploads/
      - ${CONFIG_DIR}:/config/
    env_file:
      - ${CONFIG_DIR}/postiz.env
    environment:
      - DATABASE_URL=postgresql://postiz-user:DB_PASSWORD_PLACEHOLDER@postiz-postgres:5432/postiz-db-local
      - REDIS_URL=redis://postiz-redis:6379
      - JWT_SECRET=JWT_SECRET_PLACEHOLDER
      - FRONTEND_URL=https://${DOMAIN_NAME}/social
      - NEXT_PUBLIC_BACKEND_URL=https://${DOMAIN_NAME}/social/api
      - BACKEND_INTERNAL_URL=http://localhost:3000
      - TEMPORAL_ADDRESS=temporal:7233
      - IS_GENERAL=true
    depends_on:
      postiz-postgres:
        condition: service_healthy
      postiz-redis:
        condition: service_healthy
      temporal:
        condition: service_started
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# Replace placeholders in docker-compose
sed -i "s/DB_PASSWORD_PLACEHOLDER/${DB_PASSWORD}/g" "$INSTANCE_DIR/docker-compose.yml"
sed -i "s/TEMPORAL_PASSWORD_PLACEHOLDER/${TEMPORAL_PASSWORD}/g" "$INSTANCE_DIR/docker-compose.yml"
sed -i "s/JWT_SECRET_PLACEHOLDER/${JWT_SECRET}/g" "$INSTANCE_DIR/docker-compose.yml"
sed -i "s|\${DATA_DIR}|${DATA_DIR}|g" "$INSTANCE_DIR/docker-compose.yml"
sed -i "s|\${DOMAIN_NAME}|${DOMAIN_NAME}|g" "$INSTANCE_DIR/docker-compose.yml"
sed -i "s|\${APP_PORT}|${APP_PORT}|g" "$INSTANCE_DIR/docker-compose.yml"
sed -i "s|\${TEMPORAL_UI_PORT}|${TEMPORAL_UI_PORT}|g" "$INSTANCE_DIR/docker-compose.yml"

# ============= START CONTAINERS =============
log "🚀 Starting Postiz containers (this may take 3-5 minutes)..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for services to initialize..."
sleep 90

# Create admin user
log "👤 Setting up admin user..."

# Wait for API to be ready
MAX_ATTEMPTS=60
for i in $(seq 1 $MAX_ATTEMPTS); do
    if curl -s -f "http://127.0.0.1:${APP_PORT}/api/health" >/dev/null 2>&1; then
        log "✅ Postiz API is ready"
        break
    fi
    if [ $i -eq $MAX_ATTEMPTS ]; then
        warn "Postiz API may not be ready. Please register manually."
    fi
    sleep 2
done

# Register admin user
curl -X POST "http://127.0.0.1:${APP_PORT}/api/auth/register" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\",\"name\":\"Admin\"}" 2>/dev/null || true

log "✅ Postiz initialized"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Postiz Social Media Manager",
    "version": "latest",
    "description": "Schedule social media posts, generate content with AI, and track analytics across all platforms",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/postiz.png",
    "category": "Marketing",
    "features": [
        "📱 Multi-Platform Scheduling",
        "🤖 AI Post Generation",
        "📊 Analytics Dashboard",
        "🔄 Auto-Posting",
        "🎨 Image & Video Support",
        "📅 Content Calendar",
        "👥 Team Collaboration",
        "🔗 Link Shortening",
        "📧 Email Notifications",
        "📈 Performance Tracking",
        "🎯 Hashtag Suggestions",
        "📱 Mobile Responsive",
        "🔌 Webhook Integrations",
        "🌍 Multi-language"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << 'GUIDE_EOF'
# Postiz Social Media Manager - User Guide

## Access
- **Main Dashboard**: https://DOMAIN_NAME/social/
- **Temporal UI** (Workflow Monitoring): http://localhost:8081

## Admin Login
- **Email**: ADMIN_EMAIL
- **Password**: [the password you set]

## Supported Platforms

Postiz supports all major social media platforms:

| Platform | Features |
|----------|----------|
| **X (Twitter)** | Tweets, threads, media |
| **LinkedIn** | Posts, articles, company pages |
| **Facebook** | Posts, pages, groups |
| **Instagram** | Feed posts, stories, reels |
| **TikTok** | Videos, captions |
| **YouTube** | Videos, shorts |
| **Pinterest** | Pins, boards |
| **Reddit** | Posts, comments |
| **Discord** | Webhooks, channels |
| **Slack** | Messages, channels |
| **Telegram** | Channel posts |
| **Mastodon** | Toots |
| **Bluesky** | Posts |
| **Threads** | Thread posts |
| **Google My Business** | Posts, updates |
| **WordPress** | Blog posts |
| **Medium** | Articles |
| **Dev.to** | Blog posts |
| **Hashnode** | Articles |

## Getting Started

### 1. Connect Social Accounts

1. Click **Integrations** in sidebar
2. Select platform (e.g., X/Twitter)
3. Click **Connect**
4. Authorize Postiz
5. Account appears in dashboard

### 2. Create Your First Post

1. Go to **Posts** → **Create Post**
2. Select platforms (multiple allowed)
3. Write content:
   - **Text**: Main message
   - **Media**: Images, videos, GIFs
   - **Link**: URL to share
4. Add hashtags (#socialmedia)
5. Schedule date/time
6. Click **Schedule** or **Post Now**

### 3. Content Calendar

View all scheduled posts:
- **Month View**: Overview of all posts
- **Week View**: Detailed daily schedule
- **List View**: Sortable post list

### 4. Analytics Dashboard

Track performance:
- **Overview**: Engagement, reach, impressions
- **Per Platform**: Platform-specific metrics
- **Post Performance**: Individual post stats
- **Audience Growth**: Follower trends

## AI Features

### Generate Post Content

1. Click **AI Generate** in post composer
2. Enter topic/keywords
3. Choose tone (professional, casual, funny)
4. AI generates multiple options
5. Select and edit as needed

### Hashtag Suggestions

1. Enter main keywords
2. AI suggests relevant hashtags
3. Click to add to post

### Content Repurposing

1. Import existing content (blog, video)
2. AI rewrites for each platform
3. Optimizes length and format

## Scheduling

### Best Times to Post

Postiz analyzes your audience to suggest optimal posting times:
- Highest engagement periods
- Best performing days
- Timezone-aware scheduling

### Recurring Posts

Set up recurring content:
- Daily tips
- Weekly roundups
- Monthly newsletters

### Queue System

Create a content queue:
1. Add posts to queue
2. Set posting frequency
3. System automatically posts at intervals

## Analytics

### Key Metrics

**Engagement**:
- Likes, reactions
- Comments
- Shares, retweets
- Saves, bookmarks

**Reach**:
- Impressions
- Unique viewers
- Follower growth

**Conversions**:
- Link clicks
- Website visits
- Sign-ups (with UTM)

### Reports

Export analytics:
- CSV format
- Custom date ranges
- Platform comparison

## Team Collaboration

### Roles & Permissions

- **Admin**: Full access
- **Manager**: Create, schedule, edit
- **Contributor**: Create content only
- **Analyst**: View analytics only

### Approval Workflow

1. Contributor creates post
2. Sent for approval
3. Manager reviews
4. Approves or requests changes
5. Scheduled after approval

## Integrations

### With n8n
- Trigger workflows on new posts
- Auto-schedule based on events
- Send analytics to databases

### With Changedetection
- Monitor competitor posts
- Alert on trends
- Auto-respond to mentions

### With Chhoto URL
- Shorten links automatically
- Track click analytics
- Custom domains

### With OpenAI
- Generate post content
- Hashtag suggestions
- Image descriptions

## Chrome Extension

For cookie-based platforms (Skool, etc.):
1. Install Postiz extension
2. Set EXTENSION_ID in config
3. Extension automatically refreshes sessions

## Webhooks

Postiz can send webhooks for:
- New scheduled posts
- Post published
- Failed posting
- Analytics updates

## Troubleshooting

**Post failed to publish?**
- Check account connection
- Verify API rate limits
- Check media format/size
- Review platform-specific requirements

**Analytics not showing?**
- Wait 24-48 hours for data
- Reconnect account
- Check platform API status

**Images not uploading?**
- Verify storage provider config
- Check file size limits
- Supported formats: JPG, PNG, GIF, MP4

## Commands

```bash
# View logs
winejs-postiz logs

# Restart services
winejs-postiz restart

# Check status
winejs-postiz status

# Monitor Temporal workflows
# Open http://localhost:8081

# Open dashboard
winejs-postiz open

Best Practices
Content Strategy

    Post consistently (use scheduling)

    Mix content types

    Engage with comments

    Track what performs best

Platform Optimization

    Customize per platform

    Use platform-specific features

    Respect character limits

    Optimize media sizes

Team Efficiency

    Use approval workflows

    Batch content creation

    Reuse high-performers

    Plan monthly calendars

Support

    GitHub: https://github.com/gitroomhq/postiz-app

    Discord: https://discord.postiz.com

    YouTube: https://youtube.com/@postizofficial

    Documentation: https://docs.postiz.com

Quick Tips

    First post: Start with a test post to verify connection

    Media: Keep images under 5MB for best performance

    Hashtags: Use 3-5 relevant tags per post

    Timing: Schedule posts for peak audience times

    Analytics: Check weekly to optimize strategy
GUIDE_EOF


sed -i "s/DOMAIN_NAME/DOMAINNAME/g""DOMAINN​AME/g""APP_DIR/user-guide.md"
sed -i "s/ADMIN_EMAIL/ADMINEMAIL/g""ADMINE​MAIL/g""APP_DIR/user-guide.md"

#============= DOWNLOAD AND SETUP ICON =============

log "📥 Setting up Postiz icon..."

if curl -L "POSTIZLOGOURL"−o"POSTIZL​OGOU​RL"−o"ICON_DIR/postiz.png" 2>/dev/null; then
success "✅ Icon downloaded successfully"
else
warn "Failed to download icon, creating placeholder..."
cat > "$ICON_DIR/postiz.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
<path d="M22 4s-.7 2.1-2 3.4c1.6 10-9.4 17.3-18 11.6 2.2.1 4.4-.6 6-2C3 15.5.5 9.6 3 5c2.2 2.6 5.6 4.3 9 4-1-2.2.5-4.9 3-5 2.5-.1 4.5 1.5 5 4 1.5-.5 3-1.5 4-3z"/>
</svg>
SVG_EOF
fi

#============= CREATE HELPER SCRIPT =============

log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-postiz << EOF
#!/bin/bash
DOMAIN_NAME="DOMAINNAME"APPPORT=DOMAINN​AME"APPP​ORT={APP_PORT}"
TEMPORAL_UI_PORT="${TEMPORAL_UI_PORT}"

case "$1" in
status)
cd /opt/winejs/kasmvnc-instances/postiz && docker compose ps
;;
logs)
docker logs winejs-postiz --tail 50
;;
restart)
cd /opt/winejs/kasmvnc-instances/postiz && docker compose restart
echo "Postiz restarted"
;;
workflows)
echo "📊 Temporal Workflow Monitor:"
echo " Open http://localhost:${TEMPORAL_UI_PORT}"
;;
integrations)
echo "🔌 Connected integrations:"
curl -s "https://${DOMAIN_NAME}/social/api/integrations" | jq '.'
;;
posts)
echo "📅 Recent posts:"
curl -s "https://${DOMAIN_NAME}/social/api/posts?limit=10" | jq '.[] | {id, content, status}'
;;
open)
if command -v xdg-open &> /dev/null; then
xdg-open "https://${DOMAIN_NAME}/social/"
else
echo "Visit: https://${DOMAIN_NAME}/social/"
fi
;;
*)
echo "Postiz Social Media Manager"
echo ""
echo "Commands:"
echo " winejs-postiz open # Open dashboard"
echo " winejs-postiz status # Check services"
echo " winejs-postiz logs # View logs"
echo " winejs-postiz restart # Restart"
echo " winejs-postiz workflows # Open Temporal UI"
echo " winejs-postiz integrations # List integrations"
echo " winejs-postiz posts # Recent posts"
echo ""
echo "Access URL: https://${DOMAIN_NAME}/social/"
echo "Temporal UI: http://localhost:${TEMPORAL_UI_PORT}"
echo ""
echo "Admin Login: $ADMIN_EMAIL / (password you set)"
echo ""
echo "User Guide: cat /opt/winejs/apps/postiz/user-guide.md"
;;
esac
EOF

chmod +x /usr/local/bin/winejs-postiz
============= UPDATE NGINX FOR POSTIZ =============

log "📝 Setting up nginx reverse proxy for Postiz..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
if ! grep -q "location /social" /etc/nginx/sites-available/winejs; then
cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup

LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)

if [ -n "LISTEN443LINE"];thensed−i"LISTEN4​43L​INE"];thensed−i"{LISTEN_443_LINE}i\
Postiz Social Media Manager\n\

location /social {\n
rewrite ^/social(/.*)? /\\\1 break;\n
proxy_pass http://127.0.0.1:${APP_PORT};\n\
proxy_set_header Host \$host;\n
proxy_set_header X-Real-IP \$remote_addr;\n
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n
proxy_set_header X-Forwarded-Proto \$scheme;\n
proxy_http_version 1.1;\n
proxy_set_header Upgrade \$http_upgrade;\n
proxy_set_header Connection "upgrade";\n
proxy_read_timeout 300s;\n
proxy_buffering off;\n
client_max_body_size 100M;\n
}\n
\n\
Postiz API\n\

location /social/api/ {\n
rewrite ^/social/api/(.*) /api/\\\1 break;\n
proxy_pass http://127.0.0.1:${APP_PORT};\n\
proxy_set_header Host \$host;\n
proxy_set_header X-Real-IP \$remote_addr;\n
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n
proxy_set_header X-Forwarded-Proto \$scheme;\n
proxy_read_timeout 300s;\n
}\n" /etc/nginx/sites-available/winejs

if nginx -t; then
systemctl reload nginx
log "✅ Nginx updated with Postiz routes"
else
warn "Nginx test failed, restoring backup"
cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
nginx -t && systemctl reload nginx
fi
fi
fi
fi
============= RESTART TRANSLATOR =============

log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3
============= CREATE UNINSTALL SCRIPT =============

log "🗑️ Creating uninstall script..."

cat > "(dirname"(dirname"APP_DIR")/uninstall_postiz.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[(date′+(date′+1"; }

log "🧹 Uninstalling Postiz..."

cd /opt/winejs/kasmvnc-instances/postiz
docker compose down -v 2>/dev/null
Ask about removing data

read -p "Remove all social media data and scheduled posts? (y/N): " -n 1 -r
echo
if [[ REPLY= [Yy]REPLY= [Yy] ]]; then
rm -rf /opt/winejs/apps/postiz
rm -rf /opt/winejs/kasmvnc-instances/postiz
rm -rf /opt/winejs/data/postiz
rm -rf /opt/winejs/config/postiz
log "✅ All data removed"
else
rm -rf /opt/winejs/apps/postiz
rm -rf /opt/winejs/kasmvnc-instances/postiz
rm -rf /opt/winejs/config/postiz
fi

rm -f /usr/local/bin/winejs-postiz
Remove nginx routes

if [ -f "/etc/nginx/sites-available/winejs" ]; then
sed -i '/# Postiz Social Media Manager/,/location /social/api//d' /etc/nginx/sites-available/winejs
sed -i '/location /social {/,/^ }/d' /etc/nginx/sites-available/winejs
nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Postiz uninstalled"
UNINSTALL_EOF

chmod +x "(dirname"(dirname"APP_DIR")/uninstall_postiz.sh"
============= FINAL OUTPUT =============

echo ""
echo -e "GREEN╔════════════════════════════════════════════════════════════════╗GREEN╔════════════════════════════════════════════════════════════════╗{NC}"
echo -e "GREEN║POSTIZINSTALLEDONWINEJS!║GREEN║POSTIZINSTALLEDONWINEJS!║{NC}"
echo -e "GREEN╚════════════════════════════════════════════════════════════════╝GREEN╚════════════════════════════════════════════════════════════════╝{NC}"
echo ""
success "✅ Postiz Social Media Manager installed!"
echo ""
info "🌐 Access URLs:"
info " • Dashboard: https://DOMAINNAME/social/"info"•TemporalUI:http://DOMAINN​AME/social/"info"•TemporalUI:http://DOMAIN_NAME:TEMPORALUIPORT(workflowmonitoring)"echo""info"🔐AdminLogin:"info"•Email:TEMPORALU​IP​ORT(workflowmonitoring)"echo""info"🔐AdminLogin:"info"•Email:ADMIN_EMAIL"
info " • Password: [the password you set]"
echo ""
info "📱 Supported Platforms (25+):"
info " • X/Twitter, LinkedIn, Facebook, Instagram"
info " • TikTok, YouTube, Pinterest, Reddit"
info " • Discord, Slack, Telegram, Mastodon"
info " • Bluesky, Threads, Google My Business"
info " • WordPress, Medium, Dev.to, Hashnode"
echo ""
info "🤖 AI Features:"
if [ "OPENAIENABLED"="true"];theninfo"•OpenAI:Enabled✓"info"•AIcontentgeneration"info"•Hashtagsuggestions"elseinfo"•OpenAI:Disabled(addAPIkeytoenable)"fiecho""info"📧EmailSettings:"if["OPENAIE​NABLED"="true"];theninfo"•OpenAI:Enabled✓"info"•AIcontentgeneration"info"•Hashtagsuggestions"elseinfo"•OpenAI:Disabled(addAPIkeytoenable)"fiecho""info"📧EmailSettings:"if["EMAIL_ENABLED" = "true" ]; then
info " • Provider: EMAILPROVIDER"info"•Notifications:Enabled"elseinfo"•Notifications:Disabled"fiecho""info"💾Storage:"info"•Provider:EMAILP​ROVIDER"info"•Notifications:Enabled"elseinfo"•Notifications:Disabled"fiecho""info"💾Storage:"info"•Provider:STORAGE_PROVIDER"
info " • Uploads directory: {DATA_DIR}/uploads" echo "" info "🎯 Quick Commands:" info " • winejs-postiz open # Open dashboard" info " • winejs-postiz status # Check services" info " • winejs-postiz logs # View logs" info " • winejs-postiz workflows # Monitor workflows" info " • winejs-postiz integrations # List connections" echo "" info "📁 Data Directories:" info " • Database: {DATA_DIR}/postgres"
info " • Redis: DATADIR/redis"info"•Uploads:DATAD​IR/redis"info"•Uploads:{DATA_DIR}/uploads"
info " • Temporal DB: DATADIR/temporal−postgresql"echo""info"📚UserGuide:"info"•cat/opt/winejs/apps/postiz/user−guide.md"echo""info"💡QuickStart:"info"1.Logintodashboard"info"2.Connectyoursocialaccounts"info"3.Createyourfirstpost"info"4.Scheduleorpublishnow"info"5.Trackanalytics"echo""info"📝Touninstall:sudobashDATAD​IR/temporal−postgresql"echo""info"📚UserGuide:"info"•cat/opt/winejs/apps/postiz/user−guide.md"echo""info"💡QuickStart:"info"1.Logintodashboard"info"2.Connectyoursocialaccounts"info"3.Createyourfirstpost"info"4.Scheduleorpublishnow"info"5.Trackanalytics"echo""info"📝Touninstall:sudobash(dirname "APPDIR")/uninstallpostiz.sh"echo""success"✨Postizisready!Startmanagingsocialmediaathttps://APPD​IR")/uninstallp​ostiz.sh"echo""success"✨Postizisready!Startmanagingsocialmediaathttps://DOMAIN_NAME/social/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name "uninstall_*" -type f"
text


## What Postiz Does:

**Postiz is a comprehensive social media management platform**:

### Key Features:

1. **Multi-Platform Scheduling** - Schedule posts across 25+ social networks
2. **AI Content Generation** - Generate posts with OpenAI
3. **Analytics Dashboard** - Track engagement, reach, and growth
4. **Content Calendar** - Visual scheduling interface
5. **Team Collaboration** - Roles, permissions, approval workflows
6. **Link Shortening** - Built-in URL shortener integration
7. **Media Library** - Store and reuse images/videos
8. **Hashtag Suggestions** - AI-powered hashtag recommendations
9. **Webhook Support** - Trigger automations on events
10. **Temporal Workflows** - Reliable scheduling engine

### Supported Platforms (25+):

| Category | Platforms |
|----------|-----------|
| **Microblogging** | X/Twitter, Bluesky, Threads, Mastodon |
| **Professional** | LinkedIn (profile & pages) |
| **Social** | Facebook (profile, pages, groups), Instagram (feed, stories, reels) |
| **Video** | YouTube (videos, shorts), TikTok |
| **Visual** | Pinterest, Dribbble |
| **Community** | Reddit, Discord, Slack, Telegram |
| **Blogging** | WordPress, Medium, Dev.to, Hashnode |
| **Business** | Google My Business |
| **Other** | Whop, Skool (via extension) |

### Perfect For:

- **Social Media Managers** - Manage multiple brands/clients
- **Marketing Teams** - Collaborate on content
- **Small Businesses** - Schedule posts efficiently
- **Influencers** - Cross-post to all platforms
- **Agencies** - Scale content production