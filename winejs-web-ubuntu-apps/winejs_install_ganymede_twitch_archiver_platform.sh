#!/bin/bash
# ============================================
# Ganymede Twitch Archiver - WineJS Installer
# Adds Twitch VOD & Live Stream Archiving to WineJS
# ============================================
# App: Ganymede
# Category: Media
# Features: Twitch VOD Archiving, Live Stream Recording, Chat Rendering
# ============================================

GANYMEDE_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/ganymede-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📺 Installing WineJS Ganymede Twitch Archiver..."

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

# ============= ASK FOR GANYMEDE CONFIGURATION =============
echo ""
info "📝 Ganymede Configuration"
echo "================================"
read -p "Admin password (default: ganymede - CHANGE THIS!): " ADMIN_PASSWORD
ADMIN_PASSWORD=${ADMIN_PASSWORD:-"ganymede"}

read -p "Twitch Client ID: " TWITCH_CLIENT_ID
read -s -p "Twitch Client Secret: " TWITCH_CLIENT_SECRET
echo ""

read -p "Enable OAuth/SSO? (true/false) [false]: " OAUTH_ENABLED
OAUTH_ENABLED=${OAUTH_ENABLED:-false}

if [ "$OAUTH_ENABLED" = "true" ]; then
    read -p "OAuth Provider URL: " OAUTH_PROVIDER_URL
    read -p "OAuth Client ID: " OAUTH_CLIENT_ID
    read -s -p "OAuth Client Secret: " OAUTH_CLIENT_SECRET
    echo ""
    read -p "OAuth Redirect URL (https://${DOMAIN_NAME}/archive/api/v1/auth/oauth/callback): " OAUTH_REDIRECT_URL
    OAUTH_REDIRECT_URL=${OAUTH_REDIRECT_URL:-"https://${DOMAIN_NAME}/archive/api/v1/auth/oauth/callback"}
fi

read -p "Require login to view videos? (true/false) [false]: " REQUIRE_LOGIN
REQUIRE_LOGIN=${REQUIRE_LOGIN:-false}

read -p "Videos directory (storage path) [/opt/winejs/data/ganymede/videos]: " VIDEOS_DIR
VIDEOS_DIR=${VIDEOS_DIR:-"/opt/winejs/data/ganymede/videos"}

# Generate database password
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/')

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=9200  # Start after Drop OSS's range (9100+)
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

# Find available port for Ganymede
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Ganymede"
fi

log "Using port: Ganymede=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="ganymede"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/ganymede"
DATA_DIR="/opt/winejs/data/ganymede"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{videos,logs,temp,config,db}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/ganymede"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # PostgreSQL Database
  postgres:
    image: postgres:14-alpine
    container_name: winejs-ganymede-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: ganymede
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: ganymede
    volumes:
      - ${DATA_DIR}/db:/var/lib/postgresql/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ganymede"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Ganymede API Server
  api:
    image: ghcr.io/zibbp/ganymede:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:4000"
    volumes:
      - ${DATA_DIR}/videos:/data/videos
      - ${DATA_DIR}/logs:/data/logs
      - ${DATA_DIR}/temp:/data/temp
      - ${DATA_DIR}/config:/data/config
    environment:
      # Debug
      - DEBUG=false
      # Database
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=ganymede
      - DB_PASS=${DB_PASSWORD}
      - DB_NAME=ganymede
      - DB_SSL=disable
      # Twitch
      - TWITCH_CLIENT_ID=${TWITCH_CLIENT_ID}
      - TWITCH_CLIENT_SECRET=${TWITCH_CLIENT_SECRET}
      # OAuth
      - OAUTH_ENABLED=${OAUTH_ENABLED}
      - REQUIRE_LOGIN=${REQUIRE_LOGIN}
      - SHOW_SSO_LOGIN_BUTTON=${OAUTH_ENABLED}
      - FORCE_SSO_AUTH=false
      # Directories
      - VIDEOS_DIR=/data/videos
      - TEMP_DIR=/data/temp
      - LOGS_DIR=/data/logs
      - CONFIG_DIR=/data/config
      # Timezone
      - TZ=UTC
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# Add OAuth config if enabled
if [ "$OAUTH_ENABLED" = "true" ]; then
    cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
      - OAUTH_PROVIDER_URL=${OAUTH_PROVIDER_URL}
      - OAUTH_CLIENT_ID=${OAUTH_CLIENT_ID}
      - OAUTH_CLIENT_SECRET=${OAUTH_CLIENT_SECRET}
      - OAUTH_REDIRECT_URL=${OAUTH_REDIRECT_URL}
DOCKER_EOF
fi

# ============= START CONTAINERS =============
log "🚀 Starting Ganymede containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Ganymede to initialize (this may take 1-2 minutes)..."
sleep 40

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Ganymede Twitch Archiver",
    "version": "latest",
    "description": "Twitch VOD and live stream archiving platform with real-time chat playback",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/ganymede.png",
    "category": "Media",
    "features": [
        "📺 Twitch VOD Archiving",
        "🔴 Live Stream Recording",
        "💬 Real-time Chat Playback",
        "🎨 Rendered Chat Export",
        "👀 Watched Channels",
        "🔍 Advanced Filtering",
        "📦 Simple File Structure",
        "🔔 Webhook Notifications",
        "📊 Playback Progress",
        "🎬 Playlist Support",
        "🌙 Light/Dark Mode",
        "🔐 SSO/OAuth Support"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << GUIDE_EOF
# Ganymede Twitch Archiver - User Guide

## Access
- **Web Interface**: https://$DOMAIN_NAME/archive/
- **Default Login**: username: admin, password: ganymede

## ⚠️ IMPORTANT: First Steps

1. **CHANGE ADMIN PASSWORD IMMEDIATELY**:
   - Login with admin / ganymede
   - Go to Admin → Users
   - Change password or create new admin user
   - Delete default admin user

2. **Configure Settings**:
   - Go to Admin → Settings
   - Adjust video quality, chat render options
   - Configure webhook notifications

## Adding Channels to Watch

1. Go to **Watched Channels** → **Add Channel**
2. Enter Twitch channel name
3. Configure archiving options:
   - Archive VODs (past broadcasts)
   - Archive live streams
   - Chat download/render settings
4. Save - archiving starts automatically

## Managing Archives

### Viewing Archived Content
- Browse videos in main dashboard
- Filter by channel, date, status
- Click video to watch with synced chat

### Playback Features
- Watch video with real-time chat
- Jump to specific timestamps
- Save playback progress
- Create playlists

### File Structure
\`\`\`
/data/videos/
  [channel_name]/
    [vod_id]/
      video.mp4
      chat.json
      chat_render.html
      thumbnail.jpg
\`\`\`

## Live Stream Recording

Ganymede can record live streams in real-time:
1. Add channel to watched list
2. Enable "Archive Live Streams"
3. Recording starts automatically when channel goes live
4. Chat is captured in real-time

## Chat Features

### Rendered Chat
- HTML file generated for each VOD
- Can be viewed independently
- Styled like Twitch chat

### Chat Download
- Raw chat data in JSON
- Includes emotes, badges, etc.
- Usable for analysis/moderation

## Advanced Configuration

### FFmpeg Parameters
Customize video processing:
\`\`\`
Admin → Settings → Video
- Video codec: libx264
- Audio codec: aac
- Resolution: 1920x1080
\`\`\`

### Chat Render Parameters
\`\`\`
Admin → Settings → Chat
- Message limit
- Emote size
- Badge display
\`\`\`

## Webhook Notifications

Configure webhooks for events:
- Archive completed
- Live stream started/ended
- Errors/warnings

Use with n8n for automation:
\`\`\`bash
# Example webhook payload
{
  "event": "vod_archive_complete",
  "channel": "channel_name",
  "vod_id": "123456789",
  "duration": 3600
}
\`\`\`

## Storage Management

### Storage Requirements
- 1 hour of 1080p ≈ 2-4GB
- With chat JSON ≈ +50MB
- Plan accordingly for multiple channels

### Archival Strategy
\`\`\`bash
# Move old VODs to cold storage
mv /data/videos/old_channel /mnt/archive/

# Symlink back if needed
ln -s /mnt/archive/old_channel /data/videos/old_channel
\`\`\`

## Integration with WineJS Apps

### With ArchiveBox
Archive VOD metadata and chat logs

### With Directory Lister
Share archived VODs with others

### With ConvertX
Convert videos to different formats

### With n8n
- Auto-post new VODs to Discord/Slack
- Extract clips from streams
- Generate transcripts

## API Usage

Base URL: \`https://$DOMAIN_NAME/archive/api/v1\`

### Get Channels
\`\`\`bash
curl https://$DOMAIN_NAME/archive/api/v1/channel
\`\`\`

### Get VODs
\`\`\`bash
curl https://$DOMAIN_NAME/archive/api/v1/vod
\`\`\`

### Trigger Archive
\`\`\`bash
curl -X POST https://$DOMAIN_NAME/archive/api/v1/archive \\
  -H "Authorization: Bearer YOUR_TOKEN" \\
  -d '{"channel_id": "123456", "vod_id": "987654"}'
\`\`\`

## Troubleshooting

### Archive Fails
- Check Twitch API credentials
- Verify storage space
- Check logs: \`docker logs winejs-ganymede\`

### Chat Not Rendering
- Check FFmpeg installation
- Verify chat JSON exists
- Re-run chat render task

### Live Recording Issues
- Verify channel is online
- Check network connectivity
- Increase timeout settings

## Commands

\`\`\`bash
# View logs
winejs-ganymede logs

# Restart services
winejs-ganymede restart

# Check status
winejs-ganymede status

# Show storage usage
winejs-ganymede storage

# Open dashboard
winejs-ganymede open
\`\`\`

## Legal & Ethics

⚠️ **Important Considerations**:
- Respect streamers' wishes regarding VOD archiving
- Some streams may have VODs disabled
- Be mindful of storage usage
- Consider streamer revenue (ads, subs)

## Support

- **GitHub**: https://github.com/Zibbp/ganymede
- **Wiki**: https://github.com/Zibbp/ganymede/wiki
- **Discord**: Available via GitHub
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Ganymede icon..."

if curl -L "$GANYMEDE_LOGO_URL" -o "$ICON_DIR/ganymede.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/ganymede.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M3 8h18"/>
  <path d="M5 8v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8"/>
  <rect x="8" y="4" width="8" height="4" rx="1"/>
  <circle cx="12" cy="13" r="3"/>
  <path d="M12 16v3"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-ganymede << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
DATA_DIR="${DATA_DIR}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/ganymede && docker compose ps
        ;;
    logs)
        docker logs winejs-ganymede --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/ganymede && docker compose restart
        echo "Ganymede restarted"
        ;;
    storage)
        echo "💾 Storage Usage:"
        echo "  Videos: \$(du -sh ${DATA_DIR}/videos 2>/dev/null | cut -f1 || echo '0')"
        echo "  Logs: \$(du -sh ${DATA_DIR}/logs 2>/dev/null | cut -f1 || echo '0')"
        echo "  Temp: \$(du -sh ${DATA_DIR}/temp 2>/dev/null | cut -f1 || echo '0')"
        echo "  DB: \$(du -sh ${DATA_DIR}/db 2>/dev/null | cut -f1 || echo '0')"
        ;;
    channels)
        echo "📺 Watched channels (via API):"
        curl -s "https://\${DOMAIN_NAME}/archive/api/v1/channel" | jq -r '.data[] | "  • \(.channel_name) - \(.archive_vod)"' 2>/dev/null || echo "  No channels configured yet"
        ;;
    tasks)
        echo "⏰ Active tasks:"
        echo "  Check admin dashboard for task status"
        echo "  URL: https://\${DOMAIN_NAME}/archive/admin/tasks"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/archive/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/archive/"
        fi
        ;;
    admin)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/archive/admin"
        else
            echo "Admin: https://\${DOMAIN_NAME}/archive/admin"
        fi
        ;;
    *)
        echo "Ganymede Twitch Archiver Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-ganymede open           - Open dashboard"
        echo "  winejs-ganymede admin          - Open admin panel"
        echo "  winejs-ganymede status         - Check status"
        echo "  winejs-ganymede logs           - View logs"
        echo "  winejs-ganymede restart        - Restart"
        echo "  winejs-ganymede storage        - Show storage usage"
        echo "  winejs-ganymede channels       - List watched channels"
        echo "  winejs-ganymede tasks          - Show active tasks"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/archive/"
        echo ""
        echo "Default Login: admin / ganymede"
        echo "⚠️  CHANGE THE DEFAULT PASSWORD IMMEDIATELY!"
        echo ""
        echo "Data Directory: $DATA_DIR"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/ganymede/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-ganymede

# ============= UPDATE NGINX FOR GANYMEDE =============
log "📝 Setting up nginx reverse proxy for Ganymede..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /archive" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Ganymede Twitch Archiver\n\
    location /archive {\n\
        rewrite ^/archive(/.*)?$ /\\\$1 break;\n\
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
        client_max_body_size 0;\n\
    }\n\
    \n\
    # Ganymede API\n\
    location /archive/api/ {\n\
        rewrite ^/archive/api/(.*)$ /api/\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Ganymede routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_ganymede.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Ganymede..."

cd /opt/winejs/kasmvnc-instances/ganymede
docker compose down -v 2>/dev/null

# Ask about removing video storage
read -p "Remove video archive directory (${DATA_DIR}/videos)? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "${DATA_DIR}/videos"
    log "✅ Video archive removed"
fi

read -p "Remove all Ganymede data? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /opt/winejs/apps/ganymede
    rm -rf /opt/winejs/kasmvnc-instances/ganymede
    rm -rf /opt/winejs/data/ganymede
    log "✅ All data removed"
else
    rm -rf /opt/winejs/apps/ganymede
    rm -rf /opt/winejs/kasmvnc-instances/ganymede
    rm -rf "${DATA_DIR}"/{logs,temp,config,db}
fi

rm -f /usr/local/bin/winejs-ganymede

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Ganymede Twitch Archiver/,/location \/archive\/api\//d' /etc/nginx/sites-available/winejs
    sed -i '/location \/archive {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Ganymede uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_ganymede.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              GANYMEDE INSTALLED ON WINEJS!                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Ganymede Twitch Archiver installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/archive/"
echo ""
info "🔐 Default Login:"
info "   • Username: admin"
info "   • Password: ganymede"
echo "⚠️  CHANGE THIS PASSWORD IMMEDIATELY AFTER FIRST LOGIN!"
echo ""
info "📺 Twitch Configuration:"
info "   • Client ID: ${TWITCH_CLIENT_ID:0:10}..."
info "   • Client Secret: [configured]"
if [ "$OAUTH_ENABLED" = "true" ]; then
    info "   • SSO/OAuth: Enabled"
fi
echo ""
info "💾 Storage:"
info "   • Videos: ${DATA_DIR}/videos"
info "   • Logs: ${DATA_DIR}/logs"
info "   • Temp: ${DATA_DIR}/temp"
echo ""
info "🎯 Key Features:"
info "   • Archive Twitch VODs"
info "   • Record live streams"
info "   • Real-time chat playback"
info "   • Rendered chat HTML"
info "   • Webhook notifications"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-ganymede open        # Open dashboard"
info "   • winejs-ganymede admin       # Open admin panel"
info "   • winejs-ganymede status      # Check status"
info "   • winejs-ganymede storage     # Show storage usage"
info "   • winejs-ganymede channels    # List watched channels"
info "   • winejs-ganymede tasks       # Show active tasks"
echo ""
info "📁 Data Directory:"
info "   • ${DATA_DIR}"
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/ganymede/user-guide.md"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_ganymede.sh"
echo ""
success "✨ Ganymede is ready! Start archiving Twitch streams at https://$DOMAIN_NAME/archive/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Ganymede Does:

# Ganymede is a Twitch VOD and live stream archiving platform:
# Key Features:
#     VOD Archiving - Download and save past Twitch broadcasts
#     Live Stream Recording - Record streams in real-time as they happen
#     Chat Playback - Watch video with synchronized chat replay
#     Rendered Chat - Export chat as standalone HTML files
#     Watched Channels - Auto-archive content from followed channels
#     Webhook Notifications - Get alerts when archives complete
#     Playlist Support - Organize videos into playlists
#     Progress Tracking - Save playback position
#     File Structure - Simple, portable format usable without Ganymede

# Perfect For:
#     Content Archivists - Save streams before they're deleted
#     VOD Review - Watch with chat context for research
#     Clip Creation - Download source footage for editing
#     Community Archives - Preserve community history
#     Study/Research - Analyze streamer content