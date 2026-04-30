#!/bin/bash
# ============================================
# Neko Virtual Browser - WineJS Installer
# Adds Virtual Browser with Multi-User Control to WineJS
# ============================================
# App: Neko
# Category: Productivity
# Features: Virtual Browser, Collaborative Browsing, Remote Control
# ============================================

NEKO_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/neko-social-virtual-browser.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🐱 Installing WineJS Neko Virtual Browser..."

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

# ============= ASK FOR NEKO CONFIGURATION =============
echo ""
info "📝 Neko Configuration"
echo "================================"
echo "Browser flavors available:"
echo "  1) Firefox (recommended - stable, wide compatibility)"
echo "  2) Chromium"
echo "  3) Google Chrome"
echo "  4) Brave"
echo "  5) Vivaldi"
echo "  6) Tor Browser (privacy-focused)"
echo "  7) Xfce Desktop (full desktop environment)"
echo "  8) VLC Media Player"
echo ""
read -p "Select browser (1-8) [1]: " BROWSER_CHOICE
BROWSER_CHOICE=${BROWSER_CHOICE:-1}

case $BROWSER_CHOICE in
    1) BROWSER_IMAGE="firefox" ;;
    2) BROWSER_IMAGE="chromium" ;;
    3) BROWSER_IMAGE="google-chrome" ;;
    4) BROWSER_IMAGE="brave" ;;
    5) BROWSER_IMAGE="vivaldi" ;;
    6) BROWSER_IMAGE="tor-browser" ;;
    7) BROWSER_IMAGE="xfce" ;;
    8) BROWSER_IMAGE="vlc" ;;
    *) BROWSER_IMAGE="firefox" ;;
esac

read -p "User password: " USER_PASSWORD
USER_PASSWORD=${USER_PASSWORD:-"neko"}
read -s -p "Admin password: " ADMIN_PASSWORD
ADMIN_PASSWORD=${ADMIN_PASSWORD:-"admin"}
echo ""

read -p "Screen resolution (e.g., 1920x1080@30) [1920x1080@30]: " SCREEN_RES
SCREEN_RES=${SCREEN_RES:-"1920x1080@30"}

read -p "WebRTC UDP port range [52000-52100]: " WEBRTC_PORTS
WEBRTC_PORTS=${WEBRTC_PORTS:-"52000-52100"}

read -p "Enable persistent profile? (true/false) [false]: " PERSISTENT_PROFILE
PERSISTENT_PROFILE=${PERSISTENT_PROFILE:-false}

read -p "Enable file upload/download? (true/false) [true]: " FILE_TRANSFER
FILE_TRANSFER=${FILE_TRANSFER:-true}

read -p "Enable chat? (true/false) [true]: " CHAT_ENABLED
CHAT_ENABLED=${CHAT_ENABLED:-true}

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=9400  # Start after Karaoke Eternal's range (9300+)
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

# Find available port for Neko web interface
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Neko"
fi

log "Using port: Neko=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="neko"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/neko"
DATA_DIR="/opt/winejs/data/neko"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{profile,uploads,config}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/neko"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

# Build volume mounts
VOLUME_MOUNTS=""
if [ "$PERSISTENT_PROFILE" = "true" ]; then
    VOLUME_MOUNTS="$VOLUME_MOUNTS\n      - ${DATA_DIR}/profile:/home/neko/.mozilla/firefox/profile.default"
fi
if [ "$FILE_TRANSFER" = "true" ]; then
    VOLUME_MOUNTS="$VOLUME_MOUNTS\n      - ${DATA_DIR}/uploads:/home/neko/Downloads"
fi

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Neko Virtual Browser
  winejs-neko:
    image: ghcr.io/m1k1o/neko/${BROWSER_IMAGE}:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    shm_size: "2gb"
    ports:
      - "127.0.0.1:${APP_PORT}:8080"
      - "${WEBRTC_PORTS}:${WEBRTC_PORTS}/udp"
    volumes:${VOLUME_MOUNTS}
    environment:
      - NEKO_DESKTOP_SCREEN=${SCREEN_RES}
      - NEKO_MEMBER_MULTIUSER_USER_PASSWORD=${USER_PASSWORD}
      - NEKO_MEMBER_MULTIUSER_ADMIN_PASSWORD=${ADMIN_PASSWORD}
      - NEKO_WEBRTC_EPR=${WEBRTC_PORTS}
      - NEKO_WEBRTC_ICELITE=1
      - NEKO_SERVER_BIND=0.0.0.0:8080
      - TZ=UTC
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080"]
      interval: 30s
      timeout: 10s
      retries: 5

networks:
  winejs-net:
    external: true
DOCKER_EOF

# Add file transfer plugin if enabled
if [ "$FILE_TRANSFER" = "true" ]; then
    cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF

  # File transfer volume
  filetransfer:
    image: alpine:latest
    container_name: winejs-neko-filetransfer
    restart: "no"
    volumes:
      - ${DATA_DIR}/uploads:/uploads
    command: "true"
DOCKER_EOF
fi

# ============= START CONTAINER =============
log "🚀 Starting Neko container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Neko to initialize..."
sleep 15

if docker ps | grep -q "winejs-${APP_NAME}"; then
    success "✅ Container started successfully"
else
    warn "⚠️ Container may not have started. Check: docker logs winejs-${APP_NAME}"
    docker logs winejs-${APP_NAME} --tail 20
fi

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

# Determine browser name for display
case $BROWSER_CHOICE in
    1) BROWSER_NAME="Firefox" ;;
    2) BROWSER_NAME="Chromium" ;;
    3) BROWSER_NAME="Google Chrome" ;;
    4) BROWSER_NAME="Brave" ;;
    5) BROWSER_NAME="Vivaldi" ;;
    6) BROWSER_NAME="Tor Browser" ;;
    7) BROWSER_NAME="Xfce Desktop" ;;
    8) BROWSER_NAME="VLC Media Player" ;;
esac

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Neko Virtual Browser (${BROWSER_NAME})",
    "version": "latest",
    "description": "Self-hosted virtual browser with multi-user control and WebRTC streaming",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/neko.png",
    "category": "Productivity",
    "features": [
        "🌐 Virtual Browser",
        "👥 Multi-User Control",
        "🎬 Watch Party",
        "🎤 Interactive Presentations",
        "🤝 Collaborative Tool",
        "📺 Live Broadcasting (RTMP)",
        "💾 Persistent Profile",
        "🔒 Throwaway Sessions",
        "🔐 OIDC Authentication",
        "📁 File Transfer",
        "💬 Real-time Chat",
        "🖥️ Remote Teaching/Support",
        "📊 Ultra Low Latency (<300ms)"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << GUIDE_EOF
# Neko Virtual Browser - User Guide

## Access
- **Web Interface**: https://$DOMAIN_NAME/neko/

## Login Credentials
- **User Password**: $USER_PASSWORD
- **Admin Password**: $ADMIN_PASSWORD

## Browser Flavor
- **Selected**: $BROWSER_NAME

## First-Time Setup

1. **Login**:
   - Visit the URL above
   - Use user or admin password
   - Admin has full control privileges

2. **Browser Features**:
   - Full browser functionality
   - Multi-user control (admins can grant control)
   - Real-time cursor sharing
   - Chat with other users

3. **Persistent Profile**:
   $([ "$PERSISTENT_PROFILE" = "true" ] && echo "✅ Enabled - Your browser data persists across restarts" || echo "❌ Disabled - Fresh session each restart")

## Usage Scenarios

### Watch Party
1. Admin starts playing video
2. Other users watch synchronized
3. Real-time reactions via chat
4. Host controls playback

### Interactive Presentation
1. Presenter shares screen
2. Viewers watch in real-time
3. Host can grant control to others
4. Collaborative editing possible

### Remote Support/Teaching
1. Student/admin shares control
2. Teacher demonstrates actions
3. Student watches and learns
4. Safe, controlled environment

### Collaborative Browsing
1. Multiple users browse same site
2. Discuss in chat
3. Control switches between users
4. Great for debugging together

## Browser Customization

### Installing Extensions

**Firefox-based**:
1. Visit addons.mozilla.org
2. Install desired extensions
$([ "$PERSISTENT_PROFILE" = "true" ] && echo "   - Extensions will persist" || echo "   - Extensions reset each session")

**Chromium-based**:
1. Visit Chrome Web Store
2. Install extensions

### Policy Files
To customize browser policies, mount a policy JSON file to:
- Firefox: `/usr/lib/firefox/distribution/policies.json`
- Chromium: `/etc/chromium/policies/managed/policies.json`

Example policy to allow file uploads:
\`\`\`json
{
  "DownloadRestrictions": 0,
  "AllowFileSelectionDialogs": true
}
\`\`\`

## File Transfer

$([ "$FILE_TRANSFER" = "true" ] && echo "✅ File transfer ENABLED")
$([ "$FILE_TRANSFER" = "true" ] && echo "   - Uploads go to: ${DATA_DIR}/uploads")
$([ "$FILE_TRANSFER" = "false" ] && echo "❌ File transfer DISABLED")

To transfer files:
1. Download files inside browser
2. Files are saved to Downloads folder
3. Access via volume mount

## Advanced Features

### Live Broadcasting
Stream your browser to Twitch/YouTube:
1. Set RTMP URL in Settings
2. Start broadcast
3. Stream continues even with no viewers

### Private Mode
Enable in Settings:
- Users don't receive video/audio
- Admins can still monitor
- Perfect for secure browsing

### Control Protection
- Admins can lock controls
- Users request control
- Perfect for presentations

## Administration

### Managing Users
1. Login as admin
2. Go to Settings → Users
3. View connected users
4. Grant/revoke control

### Room Settings
- Private mode
- Locked logins
- Control protection
- Implicit hosting

### Session Management
- Active sessions list
- Force disconnect users
- View session activity

## Integration with WineJS Apps

### With Directory Lister
Share downloaded files:
\`\`\`bash
cp -r ${DATA_DIR}/uploads/* /opt/winejs/data/directorylister/share/
\`\`\`

### With ArchiveBox
Archive important web pages browsed in Neko

### With ConvertX
Convert downloaded files to different formats

### With n8n
Automate browser tasks with Playwright/Puppeteer
- Scrape websites
- Fill forms
- Take screenshots

## Performance Tuning

### Resolution Settings
Current: $SCREEN_RES
- Higher resolution = better quality but more bandwidth
- Lower resolution = lower quality but smoother streaming

### WebRTC Ports
Range: $WEBRTC_PORTS
- Ensure these ports are open in firewall
- UDP protocol required

### Hardware Acceleration

**Intel GPU**:
\`\`\`yaml
image: ghcr.io/m1k1o/neko/intel-${BROWSER_IMAGE}:latest
\`\`\`

**Nvidia GPU**:
\`\`\`yaml
image: ghcr.io/m1k1o/neko/nvidia-${BROWSER_IMAGE}:latest
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: 1
          capabilities: [gpu]
\`\`\`

## Troubleshooting

### Connection Issues
- Check WebRTC ports are open
- Verify firewall settings
- Try different browser (Chrome works best)

### Black Screen
- Increase shm_size to 4gb
- Check GPU drivers
- Reduce resolution

### High Latency
- Use wired connection
- Reduce resolution/framerate
- Check network bandwidth

### No Audio
- Check browser autoplay policies
- Click "Enable Audio" button
- Refresh page

## Security Best Practices

1. **Change default passwords immediately**
2. **Use HTTPS** (configure reverse proxy)
3. **Enable private mode** for sensitive browsing
4. **Regular updates** (pull new Docker images)
5. **Monitor active sessions**

## Commands

\`\`\`bash
# View logs
winejs-neko logs

# Restart services
winejs-neko restart

# Check status
winejs-neko status

# View downloads
winejs-neko downloads

# Open dashboard
winejs-neko open
\`\`\`

## Support

- **GitHub**: https://github.com/m1k1o/neko
- **Discord**: Available via GitHub
- **Documentation**: https://neko.m1k1o.net
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Neko icon..."

if curl -L "$NEKO_LOGO_URL" -o "$ICON_DIR/neko.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/neko.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/>
  <path d="M8 12h8"/>
  <path d="M12 8v8"/>
  <circle cx="8" cy="8" r="1"/>
  <circle cx="16" cy="8" r="1"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-neko << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
DATA_DIR="${DATA_DIR}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"
USER_PASSWORD="${USER_PASSWORD}"

case "\$1" in
    status)
        docker ps | grep winejs-neko
        ;;
    logs)
        docker logs winejs-neko --tail 50
        ;;
    restart)
        docker restart winejs-neko
        echo "Neko restarted"
        ;;
    downloads)
        echo "📁 Downloads directory: ${DATA_DIR}/uploads"
        ls -la "${DATA_DIR}/uploads" 2>/dev/null || echo "  No files yet"
        ;;
    users)
        echo "👥 Active users:"
        echo "  User password: $USER_PASSWORD"
        echo "  Admin password: $ADMIN_PASSWORD"
        ;;
    settings)
        echo "⚙️ Current settings:"
        echo "  Browser: $BROWSER_NAME"
        echo "  Resolution: $SCREEN_RES"
        echo "  WebRTC ports: $WEBRTC_PORTS"
        echo "  Persistent profile: $PERSISTENT_PROFILE"
        echo "  File transfer: $FILE_TRANSFER"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/neko/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/neko/"
        fi
        ;;
    *)
        echo "Neko Virtual Browser Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-neko open           - Open virtual browser"
        echo "  winejs-neko status         - Check status"
        echo "  winejs-neko logs           - View logs"
        echo "  winejs-neko restart        - Restart"
        echo "  winejs-neko downloads      - Show downloads folder"
        echo "  winejs-neko users          - Show credentials"
        echo "  winejs-neko settings       - Show current settings"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/neko/"
        echo ""
        echo "Login Credentials:"
        echo "  User: $USER_PASSWORD"
        echo "  Admin: $ADMIN_PASSWORD"
        echo ""
        echo "Browser: $BROWSER_NAME"
        echo "Resolution: $SCREEN_RES"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/neko/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-neko

# ============= UPDATE NGINX FOR NEKO =============
log "📝 Setting up nginx reverse proxy for Neko..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /neko" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Neko Virtual Browser\n\
    location /neko {\n\
        rewrite ^/neko(/.*)?$ /\\\$1 break;\n\
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
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Neko routes"
            else
                warn "Nginx test failed, restoring backup"
                cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                nginx -t && systemctl reload nginx
            fi
        fi
    fi
fi

# ============= CREATE SAMPLE HTML FILES =============
log "📁 Creating sample welcome page in uploads..."

cat > "$DATA_DIR/uploads/welcome.html" << 'HTML_EOF'
<!DOCTYPE html>
<html>
<head><title>Welcome to Neko Virtual Browser!</title></head>
<body>
<h1>🎉 Welcome to Neko Virtual Browser!</h1>
<p>Files you download will appear in this directory.</p>
<p>To share files with users, place them in this folder.</p>
</body>
</html>
HTML_EOF

# ============= RESTART TRANSLATOR =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_neko.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Neko..."

docker stop winejs-neko 2>/dev/null
docker rm winejs-neko 2>/dev/null

# Ask about removing persistent data
read -p "Remove persistent profile and data? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /opt/winejs/apps/neko
    rm -rf /opt/winejs/kasmvnc-instances/neko
    rm -rf /opt/winejs/data/neko
    log "✅ All data removed"
else
    rm -rf /opt/winejs/apps/neko
    rm -rf /opt/winejs/kasmvnc-instances/neko
    rm -rf /opt/winejs/data/neko/config
fi

rm -f /usr/local/bin/winejs-neko

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Neko Virtual Browser/,/location \/neko/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/neko {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Neko uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_neko.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                 NEKO INSTALLED ON WINEJS!                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Neko Virtual Browser installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/neko/"
echo ""
info "🔐 Login Credentials:"
info "   • User password: $USER_PASSWORD"
info "   • Admin password: $ADMIN_PASSWORD"
echo ""
info "🌐 Browser:"
info "   • $BROWSER_NAME"
echo ""
info "⚙️ Configuration:"
info "   • Resolution: $SCREEN_RES"
info "   • WebRTC Ports: $WEBRTC_PORTS"
info "   • Persistent Profile: $PERSISTENT_PROFILE"
info "   • File Transfer: $FILE_TRANSFER"
info "   • Chat: $CHAT_ENABLED"
echo ""
info "🎯 Use Cases:"
info "   • Watch Party - Synchronized video watching"
info "   • Remote Teaching - Interactive lessons"
info "   • Collaborative Browsing - Team debugging"
info "   • Secure Browsing - Isolated environment"
info "   • Live Broadcasting - RTMP streaming"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-neko open        # Open virtual browser"
info "   • winejs-neko status      # Check status"
info "   • winejs-neko logs        # View logs"
info "   • winejs-neko downloads   # Show downloads folder"
info "   • winejs-neko users       # Show credentials"
info "   • winejs-neko settings    # Show configuration"
echo ""
info "📁 Data Directories:"
info "   • Downloads: ${DATA_DIR}/uploads"
if [ "$PERSISTENT_PROFILE" = "true" ]; then
    info "   • Profile: ${DATA_DIR}/profile"
fi
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/neko/user-guide.md"
echo ""
info "⚠️  Important Notes:"
info "   • WebRTC requires UDP ports $WEBRTC_PORTS to be open"
info "   • For best performance, use Chrome browser"
info "   • Admin has full control, user is view-only"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_neko.sh"
echo ""
success "✨ Neko is ready! Start your virtual browser at https://$DOMAIN_NAME/neko/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Neko Does:

# Neko is a self-hosted virtual browser with multi-user control using WebRTC:
# Key Features:
#     Virtual Browser - Run a full browser in Docker accessible via web
#     Multi-User Control - Multiple users can control the same browser
#     Watch Party - Watch videos together with synchronized playback
#     Interactive Presentations - Share screen, others can watch
#     Collaborative Tool - Browse together, share control
#     Remote Teaching - Teacher demonstrates, student watches
#     Live Broadcasting - Stream to Twitch/YouTube via RTMP
#     Persistent Profile - Save bookmarks, history, extensions
#     Throwaway Sessions - No data left behind (privacy mode)
#     File Transfer - Upload/download files

# Available Browser Flavors:
# Browser	Best For
# Firefox	General use, stable
# Chromium	Open source Chrome
# Google Chrome	Full Google integration
# Brave	Privacy focused
# Vivaldi	Highly customizable
# Tor Browser	Anonymity
# Xfce Desktop	Full desktop environment
# VLC	Media playback

# Perfect For:
#     Remote Work - Secure browsing from any device
#     Team Collaboration - Debug websites together
#     Online Teaching - Interactive lessons
#     Watch Parties - Watch movies with friends
#     Secure Browsing - Isolated environment
#     Demo/Presentations - Show products remotely