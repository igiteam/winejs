#!/bin/bash
# ============================================
# Karaoke Eternal - WineJS Installer
# Adds Open Karaoke Party System to WineJS Platform
# ============================================
# App: Karaoke Eternal
# Category: Media
# Features: Karaoke, Song Management, Party System
# ============================================

KARAOKE_ETERNAL_LOGO_URL="https://cdn.gitgpt.chat/rtx/mages/karaoke-eternal-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🎤 Installing WineJS Karaoke Eternal..."

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

# ============= ASK FOR KARAOKE ETERNAL CONFIGURATION =============
echo ""
info "📝 Karaoke Eternal Configuration"
echo "================================"
read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

read -p "Media folder path (where your karaoke files are stored) [/opt/winejs/data/karaoke/media]: " MEDIA_PATH
MEDIA_PATH=${MEDIA_PATH:-"/opt/winejs/data/karaoke/media"}

read -p "URL path (must start with /) [/karaoke]: " URL_PATH
URL_PATH=${URL_PATH:-"/karaoke"}

# ============= CREATE APP DIRECTORIES =============
APP_NAME="karaoke"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/karaoke"
DATA_DIR="/opt/winejs/data/karaoke"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{config,media,scanner-logs,server-logs}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/karaoke"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=9300  # Start after Ganymede's range (9200+)
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

# Find available port for Karaoke Eternal
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Karaoke Eternal"
fi

log "Using port: Karaoke Eternal=$APP_PORT"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Karaoke Eternal Server
  winejs-karaoke:
    image: radrootllc/karaoke-eternal:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:8080"
    volumes:
      - ${DATA_DIR}/config:/config
      - ${MEDIA_PATH}:/mnt/karaoke:ro
    environment:
      - TZ=UTC
      - PUID=1000
      - PGID=1000
      - KES_URL_PATH=${URL_PATH}
      - KES_SERVER_CONSOLE_LEVEL=3
      - KES_SCANNER_CONSOLE_LEVEL=3
      - KES_SCAN=all
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080${URL_PATH}"]
      interval: 30s
      timeout: 10s
      retries: 5

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE SAMPLE MEDIA FOLDER AND README =============
log "📁 Creating media folder structure..."

if [ ! -d "$MEDIA_PATH" ]; then
    mkdir -p "$MEDIA_PATH"
    log "✅ Created media folder at $MEDIA_PATH"
fi

# Create a README file in the media folder
cat > "$MEDIA_PATH/README.txt" << EOF
Karaoke Eternal Media Folder
============================

Supported file formats:
- MP4 video files
- MP3+G (MP3 + CDG files, can be zipped)

File naming convention:
Artist - Title.mp4
Example: "Journey - Don't Stop Believin'.mp4"

For MP3+G, place both files together:
Artist - Title.mp3
Artist - Title.cdg
(or zip them: Artist - Title.zip containing both files)

Subdirectories are supported and will be scanned recursively.

Advanced configuration:
Create a _kes.v2.json file in any folder to customize metadata parsing.
Example _kes.v2.json:
{
  "delimiter": "-",
  "artistOnLeft": true
}

For more details, visit: https://github.com/radrootllc/karaoke-eternal
EOF

# ============= START CONTAINER =============
log "🚀 Starting Karaoke Eternal container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Karaoke Eternal to initialize..."
sleep 15

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
    "name": "Karaoke Eternal",
    "version": "latest",
    "description": "Open karaoke party system with full library management",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/karaoke.png",
    "category": "Media",
    "features": [
        "🎤 Karaoke Song Management",
        "🎬 MP4 & MP3+G Support",
        "📱 Mobile-Friendly Interface",
        "👥 Multi-Room Support",
        "🎵 Queue System",
        "🔍 Artist/Title Search",
        "📊 Playback Controls",
        "👑 Admin Account",
        "💾 SQLite Database",
        "🔧 Custom Metadata Parser",
        "🔄 Auto Media Scanner",
        "🎨 Responsive Design"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" GUIDE_EOF
# Karaoke Eternal - User Guide

## Access
- **Web Interface**: https://$DOMAIN_NAME$URL_PATH/

## First-Time Setup

1. **Create Admin Account**:
   - First visit will prompt to create admin account
   - Use email: $ADMIN_EMAIL
   - Password: [the password you set]
   - Store password safely!

2. **Add Media Folders**:
   - Click account icon (bottom navigation)
   - Go to Preferences → Media Folders
   - Add `/mnt/karaoke` as media source
   - Scanner will run automatically

3. **Queue Songs**:
   - Browse Library by artist/song
   - Tap song to queue
   - Queued songs glow

4. **Start Player**:
   - On display system, visit https://$DOMAIN_NAME$URL_PATH/
   - Sign in with admin account
   - Click "Start Player" if no player active
   - Press play to start the party!

## Media File Formats

### MP4 Video
- Standard video files with music and on-screen lyrics
- Naming: `Artist - Title.mp4`

### MP3+G
- Two files: audio (MP3) + graphics (CDG)
- Must be in same folder
- Naming: `Artist - Title.mp3` and `Artist - Title.cdg`
- Can also be zipped: `Artist - Title.zip`

## File Naming Convention

**Default**: `Artist - Title`
Examples:
- `Journey - Don't Stop Believin'.mp4`
- `Whitney Houston - I Will Always Love You.mp3`
- `Queen - Bohemian Rhapsody.zip`

## Custom Metadata Parser

Create `_kes.v2.json` in any media folder to customize parsing:

### Basic Configuration
\`\`\`json
{
  "artistOnLeft": true,  // false if "Title - Artist"
  "delimiter": "-",      // separator between artist/title
  "articles": ["A", "An", "The"]  // words to ignore in sorting
}
\`\`\`

### Advanced Templating
\`\`\`json
{
  "artist": "My Custom Artist",
  "title": {
    "\$eval": "replace(title, \"v2\", \"\")"
  }
}
\`\`\`

## Using Karaoke Eternal

### Library View
- Browse by artist or song title
- Search bar for quick filtering
- Tap artist to see their songs
- Tap song to queue

### Queue View
- See upcoming songs
- Reorder or remove queued songs
- Currently playing song highlighted

### Player View (Display)
- Fullscreen karaoke display
- Shows lyrics for MP3+G files
- Video playback for MP4 files
- Play/pause, skip, volume controls

### Account View
- **Admin Settings**: Manage users, rooms, preferences
- **Media Folders**: Add/remove media sources
- **Room Settings**: Configure player room
- **Scanner Log**: View media scan results

## Tips & Tricks

### Finding Karaoke Songs
- Search for "Karaoke" + song name on YouTube
- Online karaoke stores (e.g., Karaoke Version)
- Karaoke CD rips (MP3+G format)
- Music stores (Amazon Music, Apple Music)

### Organizing Large Libraries
- Use subfolders by artist: `./Artist Name/Song Title.mp4`
- Custom metadata parser per folder
- Regular scanner updates

### Party Setup
1. **Server**: Any computer (Raspberry Pi works!)
2. **Display**: Laptop/tablet connected to TV
3. **Audio**: Speakers connected to display system
4. **Mobile**: Phones/tablets for queue control

### Multi-Room Support
- Create multiple rooms for different parties
- Each room has independent queue and player
- Admins can manage all rooms

## Troubleshooting

### Songs Not Appearing
- Check file naming format
- Verify file permissions
- Run media scanner manually in Admin
- Check scanner logs for parsing errors

### Player Won't Start
- Browser may block popups/autoplay
- Need user interaction first (click something)
- Try different browser (Chrome works best)

### No Lyrics on MP3+G
- Verify CDG file exists and matches MP3 name
- Check CDG file is not corrupt
- Browser may not support CDG (use MP4 instead)

### Scanner Taking Too Long
- Large libraries take time on first scan
- Subsequent scans are incremental
- Set scanner to run at off-peak hours

## Commands

\`\`\`bash
# View logs
winejs-karaoke logs

# Restart services
winejs-karaoke restart

# Check status
winejs-karaoke status

# Run media scanner manually
docker exec winejs-karaoke node /app/src/scanner.js

# Open dashboard
winejs-karaoke open
\`\`\`

## Support

- **GitHub**: https://github.com/radrootllc/karaoke-eternal
- **Discord**: Join Karaoke Eternal Discord
- **Sponsor**: Consider supporting the project!

## Legal

- Only use with properly licensed karaoke files
- Respect copyright laws in your country
- Karaoke Eternal is open source software
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Karaoke Eternal icon..."

if curl -L "$KARAOKE_ETERNAL_LOGO_URL" -o "$ICON_DIR/karaoke.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/karaoke.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M3 9h18v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9z"/>
  <path d="M7 9V5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v4"/>
  <circle cx="9.5" cy="14.5" r="1.5"/>
  <circle cx="14.5" cy="14.5" r="1.5"/>
  <path d="M8 12h8"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-karaoke << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
URL_PATH="${URL_PATH}"
APP_PORT=${APP_PORT}"
MEDIA_PATH="${MEDIA_PATH}"

case "\$1" in
    status)
        docker ps | grep winejs-karaoke
        ;;
    logs)
        docker logs winejs-karaoke --tail 50
        ;;
    restart)
        docker restart winejs-karaoke
        echo "Karaoke Eternal restarted"
        ;;
    scan)
        echo "🔄 Running media scanner..."
        docker exec winejs-karaoke node /app/src/scanner.js
        ;;
    media)
        echo "📁 Media folder: $MEDIA_PATH"
        echo ""
        echo "Statistics:"
        echo "  Total songs: \$(find "$MEDIA_PATH" -type f \( -name "*.mp4" -o -name "*.mp3" \) 2>/dev/null | wc -l)"
        echo "  Total artists: \$(find "$MEDIA_PATH" -type d -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
        ;;
    add-song)
        shift
        if [ $# -lt 1 ]; then
            echo "Usage: winejs-karaoke add-song <file>"
            echo "Example: winejs-karaoke add-song ~/Music/Journey- Don't Stop Believin'.mp4"
        else
            cp "\$@" "$MEDIA_PATH/"
            echo "✅ Song added. Run 'winejs-karaoke scan' to update library."
        fi
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}${URL_PATH}"
        else
            echo "Visit: https://\${DOMAIN_NAME}${URL_PATH}"
        fi
        ;;
    *)
        echo "Karaoke Eternal Karaoke System Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-karaoke open           - Open Karaoke system"
        echo "  winejs-karaoke status         - Check status"
        echo "  winejs-karaoke logs           - View logs"
        echo "  winejs-karaoke restart        - Restart services"
        echo "  winejs-karaoke scan           - Run media scanner"
        echo "  winejs-karaoke media          - Show media statistics"
        echo "  winejs-karaoke add-song <file> - Add song to library"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}${URL_PATH}"
        echo ""
        echo "Admin Setup (First Visit):"
        echo "  1. Visit the URL above"
        echo "  2. Create admin account with: $ADMIN_EMAIL"
        echo "  3. Add media folder: /mnt/karaoke"
        echo "  4. Wait for scanner to finish"
        echo "  5. Start the party!"
        echo ""
        echo "Media Folder: $MEDIA_PATH"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/karaoke/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-karaoke

# ============= UPDATE NGINX FOR KARAOKE ETERNAL =============
log "📝 Setting up nginx reverse proxy for Karaoke Eternal..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location $URL_PATH" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Karaoke Eternal Karaoke System\n\
    location ${URL_PATH} {\n\
        rewrite ^${URL_PATH}(/.*)?$ /\\\$1 break;\n\
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
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Karaoke Eternal routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_karaoke.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Karaoke Eternal..."

docker stop winejs-karaoke 2>/dev/null
docker rm winejs-karaoke 2>/dev/null

# Ask about removing media files
read -p "Remove media folder ($MEDIA_PATH)? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$MEDIA_PATH"
    log "✅ Media folder removed"
fi

read -p "Remove all Karaoke Eternal data? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /opt/winejs/apps/karaoke
    rm -rf /opt/winejs/kasmvnc-instances/karaoke
    rm -rf /opt/winejs/data/karaoke
    log "✅ All data removed"
else
    rm -rf /opt/winejs/apps/karaoke
    rm -rf /opt/winejs/kasmvnc-instances/karaoke
    rm -rf /opt/winejs/data/karaoke/config
fi

rm -f /usr/local/bin/winejs-karaoke

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Karaoke Eternal Karaoke System/,/location '${URL_PATH}'/d' /etc/nginx/sites-available/winejs
    sed -i '/location '${URL_PATH}' {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Karaoke Eternal uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_karaoke.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           KARAOKE ETERNAL INSTALLED ON WINEJS!                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Karaoke Eternal installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME$URL_PATH/"
echo ""
info "🔐 Admin Setup (First Visit):"
info "   • Create account with email: $ADMIN_EMAIL"
info "   • Password: [the password you set]"
echo ""
info "📁 Media Folder:"
info "   • $MEDIA_PATH"
echo ""
info "🎤 Key Features:"
info "   • MP4 video and MP3+G support"
info "   • Mobile-friendly interface"
info "   • Queue management"
info "   • Multi-room support"
info "   • Custom metadata parser"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-karaoke open        # Open karaoke"
info "   • winejs-karaoke status      # Check status"
info "   • winejs-karaoke logs        # View logs"
info "   • winejs-karaoke scan        # Run media scanner"
info "   • winejs-karaoke media       # Show statistics"
info "   • winejs-karaoke add-song <file> # Add song"
echo ""
info "📁 Data Directories:"
info "   • Database: ${DATA_DIR}/config"
info "   • Media: ${MEDIA_PATH}"
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/karaoke/user-guide.md"
echo ""
info "🎵 Song Naming Convention:"
info "   • Artist - Title.mp4"
info "   • Artist - Title.mp3 + Artist - Title.cdg"
info "   • Artist - Title.zip (with both files)"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_karaoke.sh"
echo ""
success "✨ Karaoke Eternal is ready! Start the party at https://$DOMAIN_NAME$URL_PATH/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Karaoke Eternal Does:

# Karaoke Eternal is an open karaoke party system:
# Key Features:
#     Karaoke Library Management - Organize all your karaoke songs
#     MP4 & MP3+G Support - Both video and CDG formats
#     Mobile-Friendly Interface - Control from phones/tablets
#     Queue System - Manage song requests
#     Multi-Room Support - Multiple parties simultaneously
#     Custom Metadata Parser - Flexible file naming rules
#     Admin Controls - User management, preferences
#     Auto Media Scanner - Automatically detects new songs

# Supported Formats:
#     MP4 Video - Songs with on-screen lyrics
#     MP3+G - Audio + CDG graphics (can be zipped)
#     Naming Convention: Artist - Title.ext

# Perfect For:
#     Parties - Let guests request songs
#     Bars/Pubs - Professional karaoke system
#     Home Entertainment - Family karaoke nights
#     Events - Weddings, corporate parties
#     Karaoke Hosts - Manage large song libraries