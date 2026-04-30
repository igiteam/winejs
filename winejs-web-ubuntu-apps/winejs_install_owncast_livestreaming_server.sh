#!/bin/bash
# ============================================
# Owncast Live Streaming - WineJS Installer
# Adds Self-Hosted Live Streaming Platform to WineJS
# ============================================
# App: Owncast
# Category: Media
# Features: Live Streaming, Chat, RTMP Ingest
# ============================================

OWNCAST_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/owncast-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📺 Installing WineJS Owncast Live Streaming..."

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

# ============= ASK FOR OWNCAST CONFIGURATION =============
echo ""
info "📝 Owncast Configuration"
echo "================================"
read -p "Admin username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-"admin"}
read -s -p "Admin password (default: abc123 - CHANGE THIS!): " ADMIN_PASSWORD
ADMIN_PASSWORD=${ADMIN_PASSWORD:-"abc123"}
echo ""

read -p "Stream title [WineJS Live Stream]: " STREAM_TITLE
STREAM_TITLE=${STREAM_TITLE:-"WineJS Live Stream"}

read -p "Server name [WineJS Streaming]: " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-"WineJS Streaming"}

read -p "Enable chat? (true/false) [true]: " CHAT_ENABLED
CHAT_ENABLED=${CHAT_ENABLED:-true}

read -p "Enable social sharing? (true/false) [true]: " SOCIAL_ENABLED
SOCIAL_ENABLED=${SOCIAL_ENABLED:-true}

read -p "Enable external actions (donations, etc.)? (true/false) [false]: " EXTERNAL_ACTIONS
EXTERNAL_ACTIONS=${EXTERNAL_ACTIONS:-false}

read -p "Logo URL (optional): " LOGO_URL

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=9500  # Start after Neko's range (9400+)
MAX_RETRIES=50
APP_PORT=""
RTMP_PORT=""

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

# Find available port for Owncast web interface
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

# Find available port for RTMP ingest
for i in $(seq 1 $MAX_RETRIES); do
    TEST_PORT=$((APP_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        RTMP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ] || [ -z "$RTMP_PORT" ]; then
    error "Could not find available ports for Owncast"
fi

log "Using ports: Web=$APP_PORT, RTMP=$RTMP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="owncast"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/owncast"
DATA_DIR="/opt/winejs/data/owncast"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{data,logo}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/owncast"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Owncast Live Streaming Server
  winejs-owncast:
    image: owncast/owncast:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:8080"
      - "127.0.0.1:${RTMP_PORT}:1935"
    volumes:
      - ${DATA_DIR}/data:/app/data
    environment:
      - OWNCAST_ADMIN_USER=${ADMIN_USER}
      - OWNCAST_ADMIN_PASS=${ADMIN_PASSWORD}
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/status"]
      interval: 30s
      timeout: 10s
      retries: 5

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= INITIALIZE CONFIGURATION =============
log "🚀 Starting Owncast container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Owncast to initialize..."
sleep 20

# Create admin user and configure settings
log "🔧 Configuring Owncast..."

# Wait for API to be ready
MAX_ATTEMPTS=30
for i in $(seq 1 $MAX_ATTEMPTS); do
    if curl -s -f "http://127.0.0.1:${APP_PORT}/api/status" >/dev/null 2>&1; then
        log "✅ Owncast API is ready"
        break
    fi
    if [ $i -eq $MAX_ATTEMPTS ]; then
        warn "Owncast API may not be ready. Please configure manually."
    fi
    sleep 2
done

# Configure stream settings via API
if [ -n "$STREAM_TITLE" ]; then
    curl -X PUT "http://127.0.0.1:${APP_PORT}/api/admin/config" \
        -H "Content-Type: application/json" \
        -u "${ADMIN_USER}:${ADMIN_PASSWORD}" \
        -d "{\"name\":\"${STREAM_TITLE}\",\"summary\":\"${SERVER_NAME} live stream\"}" 2>/dev/null || true
fi

# Set logo if provided
if [ -n "$LOGO_URL" ]; then
    curl -X PUT "http://127.0.0.1:${APP_PORT}/api/admin/config" \
        -H "Content-Type: application/json" \
        -u "${ADMIN_USER}:${ADMIN_PASSWORD}" \
        -d "{\"logo\":\"${LOGO_URL}\"}" 2>/dev/null || true
fi

log "✅ Owncast configured"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Owncast Live Streaming",
    "version": "latest",
    "description": "Self-hosted live video streaming platform - Twitch alternative",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/owncast.png",
    "category": "Media",
    "features": [
        "📺 Live Video Streaming",
        "💬 Real-time Chat",
        "🎨 Customizable Interface",
        "🔌 RTMP Ingest",
        "👥 Viewer Analytics",
        "🔗 Social Sharing",
        "💾 Stream Recording",
        "🚫 Ad-free & Privacy-focused",
        "🌐 Federation Support",
        "🎭 Emoji Reactions",
        "📱 Mobile Responsive",
        "🔐 Admin Dashboard"
    ]
}
CONF_EOF

# ============= CREATE STREAMER GUIDE =============
log "📝 Creating streamer guide..."

cat > "$APP_DIR/streamer-guide.md" << GUIDE_EOF
# Owncast Live Streaming - Streamer Guide

## Access
- **Viewer Page**: https://$DOMAIN_NAME/watch/
- **Admin Dashboard**: https://$DOMAIN_NAME/watch/admin

## Admin Login
- **Username**: $ADMIN_USER
- **Password**: $ADMIN_PASSWORD

## Getting Started

### 1. Configure Your Stream

1. Login to admin dashboard
2. Go to **Configuration** → **Stream Details**
3. Set your stream title and description
4. Upload your logo
5. Configure social links

### 2. Set Up Streaming Software

Use OBS Studio, Streamlabs, or any RTMP encoder:

**OBS Studio Settings**:
- **Server**: `rtmp://$DOMAIN_NAME/live`
- **Stream Key**: Create in admin dashboard (Settings → Stream Keys)
- **Video Settings**:
  - Encoder: x264 or hardware encoder
  - Bitrate: 2500-6000 Kbps
  - Resolution: 720p or 1080p
  - FPS: 30 or 60

**Stream Key Management**:
1. Go to **Settings** → **Stream Keys**
2. Create a new key for each encoder
3. Name keys to identify them
4. Revoke keys if compromised

### 3. Go Live!

1. Start streaming in OBS
2. Stream appears on viewer page
3. Chat becomes active
4. Viewers can watch instantly

## Admin Features

### Dashboard Overview
- Current viewer count
- Stream status (live/offline)
- Chat moderation tools
- Recent viewers

### Configuration Options

**General Settings**:
- Stream title and description
- Server name
- Logo and branding
- Social media links

**Chat Settings**:
- $([ "$CHAT_ENABLED" = "true" ] && echo "✅ Chat is ENABLED" || echo "❌ Chat is DISABLED")
- Message length limits
- Slow mode
- Word filters

**External Actions**:
$([ "$EXTERNAL_ACTIONS" = "true" ] && echo "- Add donation buttons\n- Custom action links\n- Sponsor integrations" || echo "- External actions are disabled\n- Enable in settings to add donation buttons")

### Moderation Tools

**Chat Moderation**:
- Time out users
- Ban/unban
- Clear chat
- Enable slow mode

**Viewer Management**:
- View connected viewers
- See chat history
- Export chat logs

## Customization

### Branding
- Custom logo (upload via admin)
- Accent colors (change CSS in admin)
- Page title and description

### Custom Actions
Add buttons for:
- Donation links (Patreon, Ko-fi, etc.)
- Social media (Twitter, Discord, etc.)
- Merchandise store
- Affiliate links

### CSS Customization
Advanced users can inject custom CSS:
1. Enable custom CSS in settings
2. Add your styles
3. Changes apply immediately

## Streaming Tips

### Optimal Settings

**For 720p**:
- Bitrate: 2500-4000 Kbps
- Encoder Preset: veryfast
- Keyframe Interval: 2s
- Audio: 160 Kbps

**For 1080p**:
- Bitrate: 4500-6000 Kbps
- Encoder Preset: faster
- Keyframe Interval: 2s
- Audio: 192 Kbps

**Hardware Encoding**:
- NVIDIA: NVENC H.264
- AMD: AMF H.264
- Intel: QSV H.264
- Apple: VideoToolBox

### Network Requirements
- Upload speed: 2x your bitrate
- Minimal packet loss
- Wired connection recommended

### Content Tips
- Use overlays for branding
- Add scene transitions
- Include chat on screen
- Stinger transitions for events

## Integrations

### With OBS Studio
- Browser source for chat
- Display viewer count
- Show latest follower/donation

### With n8n
- Trigger workflows on new followers
- Send Discord/Slack alerts
- Auto-post when live

### With Mumble
- Voice chat for stream team
- Discuss stream while live

### With Directory Lister
- Share recording archives
- Distribute stream assets

## Recording & VoD

**Stream Recording**:
- Owncast can record streams
- Configure in Settings → Advanced
- Recordings saved to ${DATA_DIR}/data

**Exporting Recordings**:
\`\`\`bash
# Copy recording from container
docker cp winejs-owncast:/app/data/recordings ./recordings

# Convert with ConvertX if needed
winejs-convertx convert recording.mp4
\`\`\`

## Troubleshooting

### Stream Won't Start
- Verify stream key
- Check RTMP URL
- Ensure port $RTMP_PORT is open
- Check OBS logs

### Buffering/Stuttering
- Lower bitrate
- Reduce resolution
- Check upload speed
- Use hardware encoder

### Viewers Can't Connect
- Check firewall rules
- Verify SSL certificate
- Domain resolving correctly?
- Viewer location/CDN

### Chat Not Working
- Enable chat in settings
- Check websocket configuration
- Browser console errors

## Analytics

**Viewer Stats**:
- Concurrent viewers
- Total stream time
- Peak viewership
- Viewer geography (if enabled)

**Chat Stats**:
- Messages per minute
- Active chatters
- Emoji usage

## Commands

\`\`\`bash
# View logs
winejs-owncast logs

# Restart services
winejs-owncast restart

# Check status
winejs-owncast status

# View stream keys
docker exec winejs-owncast cat /app/data/config.yaml | grep streamKeys

# Open dashboard
winejs-owncast open
\`\`\`

## Support

- **GitHub**: https://github.com/owncast/owncast
- **Documentation**: https://owncast.online/docs/
- **Discord**: Join community
- **Directory**: https://directory.owncast.online

## Community

Share your stream:
- Add to Owncast Directory
- Submit to indie web rings
- Cross-post to Mastodon/Fediverse
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Owncast icon..."

if curl -L "$OWNCAST_LOGO_URL" -o "$ICON_DIR/owncast.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/owncast.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <circle cx="12" cy="12" r="10"/>
  <polygon points="10 8 16 12 10 16 10 8"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-owncast << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
RTMP_PORT=${RTMP_PORT}"
ADMIN_USER="${ADMIN_USER}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"

case "\$1" in
    status)
        docker ps | grep winejs-owncast
        ;;
    logs)
        docker logs winejs-owncast --tail 50
        ;;
    restart)
        docker restart winejs-owncast
        echo "Owncast restarted"
        ;;
    stream-key)
        echo "🎬 Stream Key Management:"
        echo "  Login to admin dashboard: https://\${DOMAIN_NAME}/watch/admin"
        echo "  Go to Settings → Stream Keys"
        echo "  Create or revoke stream keys"
        ;;
    rtmp)
        echo "📡 RTMP Ingest URL: rtmp://\${DOMAIN_NAME}:${RTMP_PORT}/live"
        echo "  Use this in OBS with your stream key"
        ;;
    viewers)
        echo "👥 Current viewer count:"
        curl -s "https://\${DOMAIN_NAME}/api/status" | jq '.viewerCount'
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/watch/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/watch/"
        fi
        ;;
    admin)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/watch/admin"
        else
            echo "Admin: https://\${DOMAIN_NAME}/watch/admin"
        fi
        ;;
    *)
        echo "Owncast Live Streaming Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-owncast open           # Open viewer page"
        echo "  winejs-owncast admin          # Open admin dashboard"
        echo "  winejs-owncast status         # Check status"
        echo "  winejs-owncast logs           # View logs"
        echo "  winejs-owncast restart        # Restart"
        echo "  winejs-owncast stream-key     # Stream key help"
        echo "  winejs-owncast rtmp           # RTMP URL info"
        echo "  winejs-owncast viewers        # Current viewer count"
        echo ""
        echo "Access URLs:"
        echo "  • Viewer: https://\${DOMAIN_NAME}/watch/"
        echo "  • Admin: https://\${DOMAIN_NAME}/watch/admin"
        echo ""
        echo "Admin Login: $ADMIN_USER / $ADMIN_PASSWORD"
        echo "⚠️  CHANGE DEFAULT PASSWORD IMMEDIATELY!"
        echo ""
        echo "RTMP Ingest: rtmp://\${DOMAIN_NAME}:${RTMP_PORT}/live"
        echo ""
        echo "Streamer Guide: cat /opt/winejs/apps/owncast/streamer-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-owncast

# ============= UPDATE NGINX FOR OWNCAST =============
log "📝 Setting up nginx reverse proxy for Owncast..."

# Add websocket support to nginx config if not already present
if [ -f "/etc/nginx/nginx.conf" ]; then
    if ! grep -q "map \$http_upgrade \$connection_upgrade" /etc/nginx/nginx.conf; then
        sed -i '/http {/a \\n    map $http_upgrade $connection_upgrade {\n        default upgrade;\n        ""      close;\n    }' /etc/nginx/nginx.conf
    fi
fi

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /watch" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Owncast Live Streaming\n\
    location /watch {\n\
        rewrite ^/watch(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \\\$connection_upgrade;\n\
        proxy_read_timeout 86400s;\n\
        proxy_buffering off;\n\
        client_max_body_size 0;\n\
    }\n\
    \n\
    # Owncast API\n\
    location /watch/api/ {\n\
        rewrite ^/watch/api/(.*)$ /api/\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Owncast routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_owncast.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Owncast..."

docker stop winejs-owncast 2>/dev/null
docker rm winejs-owncast 2>/dev/null

# Ask about removing recordings
read -p "Remove recorded streams? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /opt/winejs/apps/owncast
    rm -rf /opt/winejs/kasmvnc-instances/owncast
    rm -rf /opt/winejs/data/owncast
    log "✅ All data removed"
else
    rm -rf /opt/winejs/apps/owncast
    rm -rf /opt/winejs/kasmvnc-instances/owncast
    rm -rf /opt/winejs/data/owncast/config.yaml
fi

rm -f /usr/local/bin/winejs-owncast

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Owncast Live Streaming/,/location \/watch\/api\//d' /etc/nginx/sites-available/winejs
    sed -i '/location \/watch {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Owncast uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_owncast.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              OWNCAST INSTALLED ON WINEJS!                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Owncast Live Streaming installed!"
echo ""
info "🌐 Access URLs:"
info "   • Viewer Page: https://$DOMAIN_NAME/watch/"
info "   • Admin Dashboard: https://$DOMAIN_NAME/watch/admin"
echo ""
info "🔐 Admin Login:"
info "   • Username: $ADMIN_USER"
info "   • Password: $ADMIN_PASSWORD"
echo "⚠️  CHANGE THE DEFAULT PASSWORD IMMEDIATELY!"
echo ""
info "📡 RTMP Ingest:"
info "   • rtmp://$DOMAIN_NAME:$RTMP_PORT/live"
info "   • Configure in OBS with your stream key"
echo ""
info "⚙️ Configuration:"
info "   • Stream Title: $STREAM_TITLE"
info "   • Server Name: $SERVER_NAME"
info "   • Chat Enabled: $CHAT_ENABLED"
info "   • Social Sharing: $SOCIAL_ENABLED"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-owncast open        # Open viewer"
info "   • winejs-owncast admin       # Open admin"
info "   • winejs-owncast status      # Check status"
info "   • winejs-owncast logs        # View logs"
info "   • winejs-owncast rtmp        # RTMP URL"
info "   • winejs-owncast viewers     # Viewer count"
info "   • winejs-owncast stream-key  # Stream key help"
echo ""
info "📁 Data Directory:"
info "   • ${DATA_DIR}/data"
echo ""
info "📚 Streamer Guide:"
info "   • cat /opt/winejs/apps/owncast/streamer-guide.md"
echo ""
info "🔧 OBS Settings:"
info "   • Server: rtmp://$DOMAIN_NAME:$RTMP_PORT/live"
info "   • Stream Key: Create in admin dashboard"
info "   • Video Bitrate: 2500-6000 Kbps"
info "   • Encoder: x264 or hardware encoder"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_owncast.sh"
echo ""
success "✨ Owncast is ready! Start streaming at https://$DOMAIN_NAME/watch/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Owncast Does:

# Owncast is a self-hosted live video streaming platform (Twitch alternative):
# Key Features:
#     Live Streaming - Stream video to viewers in real-time
#     RTMP Ingest - Works with OBS, Streamlabs, any RTMP encoder
#     Chat System - Built-in real-time chat for viewers
#     Admin Dashboard - Full control over stream settings
#     Customizable Interface - Themes, logos, colors
#     Viewer Analytics - Track viewers and engagement
#     Stream Recording - Automatically record streams for VoD
#     Federation - Connect with other Owncast instances
#     Social Sharing - Share stream on social media
#     No Ads - Completely ad-free and privacy-focused

# Perfect For:
#     Content Creators - Independent streaming platform
#     Gamers - Live gameplay streaming
#     Events - Stream conferences, meetups, concerts
#     Education - Live classes and workshops
#     Corporate - Internal communications, all-hands meetings