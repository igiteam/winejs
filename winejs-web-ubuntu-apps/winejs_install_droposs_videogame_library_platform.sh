#!/bin/bash
# ============================================
# Drop OSS Game Library Manager - WineJS Installer
# Adds Self-Hosted Game Launcher to WineJS Platform
# ============================================
# App: Drop OSS
# Category: Gaming
# Features: Game Library, Game Downloads, Version Management
# ============================================

DROPOSS_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/droposs-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🎮 Installing WineJS Drop OSS Game Library..."

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

# ============= ASK FOR DROP OSS CONFIGURATION =============
echo ""
info "📝 Drop OSS Configuration"
echo "================================"
read -p "Admin username: " ADMIN_USER
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""
read -p "Admin email: " ADMIN_EMAIL

read -p "External URL (https://${DOMAIN_NAME}/games): " EXTERNAL_URL
EXTERNAL_URL=${EXTERNAL_URL:-"https://${DOMAIN_NAME}/games"}

read -p "Metadata provider (giantbomb/igdb/none) [giantbomb]: " METADATA_PROVIDER
METADATA_PROVIDER=${METADATA_PROVIDER:-"giantbomb"}

if [ "$METADATA_PROVIDER" = "giantbomb" ]; then
    read -p "GiantBomb API key: " GIANTBOMB_API_KEY
fi

if [ "$METADATA_PROVIDER" = "igdb" ]; then
    read -p "IGDB Client ID: " IGDB_CLIENT_ID
    read -s -p "IGDB Client Secret: " IGDB_CLIENT_SECRET
    echo ""
fi

read -p "Enable OIDC authentication? (true/false) [false]: " OIDC_ENABLED
if [ "$OIDC_ENABLED" = "true" ]; then
    read -p "OIDC Client ID: " OIDC_CLIENT_ID
    read -s -p "OIDC Client Secret: " OIDC_CLIENT_SECRET
    echo ""
    read -p "OIDC Well-known URL: " OIDC_WELLKNOWN
fi

# Generate PostgreSQL password
POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/')

# ============= CREATE APP DIRECTORIES =============
APP_NAME="droposs"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/droposs"
DATA_DIR="/opt/winejs/data/droposs"
LIBRARY_DIR="/opt/winejs/data/droposs-library"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$LIBRARY_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{db,data,library}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/droposs"
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
    container_name: winejs-droposs-db
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U drop"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 10s
    volumes:
      - ${DATA_DIR}/db:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=drop
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=drop
    networks:
      - winejs-net

  # Drop OSS Server
  drop:
    image: ghcr.io/drop-oss/drop:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "127.0.0.1:${APP_PORT}:3000"
    volumes:
      - ${LIBRARY_DIR}:/library
      - ${DATA_DIR}/data:/data
    environment:
      - DATABASE_URL=postgres://drop:${POSTGRES_PASSWORD}@postgres:5432/drop
      - EXTERNAL_URL=${EXTERNAL_URL}
      - GIANT_BOMB_API_KEY=${GIANTBOMB_API_KEY}
      - IGDB_CLIENT_ID=${IGDB_CLIENT_ID}
      - IGDB_CLIENT_SECRET=${IGDB_CLIENT_SECRET}
DOCKER_EOF

# Add OIDC config if enabled
if [ "$OIDC_ENABLED" = "true" ]; then
    cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
      - OIDC_CLIENT_ID=${OIDC_CLIENT_ID}
      - OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}
      - OIDC_WELLKNOWN=${OIDC_WELLKNOWN}
      - DISABLE_SIMPLE_AUTH=false
DOCKER_EOF
fi

# Add networks section
cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= START CONTAINERS =============
log "🚀 Starting Drop OSS containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Drop OSS to initialize (this may take 1-2 minutes)..."
sleep 30

# Get setup key and URL from logs
log "🔑 Extracting setup information from logs..."
SETUP_URL=$(docker logs winejs-droposs 2>&1 | grep -oP 'Setup URL: \K[^\s]+' | head -1)
SETUP_KEY=$(docker logs winejs-droposs 2>&1 | grep -oP 'key=\K[^\s]+' | head -1)

if [ -n "$SETUP_URL" ]; then
    log "✅ Setup URL found: $SETUP_URL"
    log "✅ Setup Key: $SETUP_KEY"
else
    warn "Could not auto-extract setup URL. Please check logs manually: docker logs winejs-droposs"
fi

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Drop OSS Game Library",
    "version": "latest",
    "description": "Self-hosted game library manager and launcher - like Steam but open source",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/droposs.png",
    "category": "Gaming",
    "features": [
        "🎮 Game Library Management",
        "📦 Version Control for Games",
        "🔄 Delta Updates",
        "📊 Game Metadata Import",
        "👥 Multi-User Support",
        "🔐 OIDC Authentication",
        "💾 Efficient Storage",
        "📱 Cross-Platform Clients",
        "🔍 Game Search",
        "📈 Playtime Tracking",
        "🎨 Modern UI",
        "🐳 Easy Deployment"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << GUIDE_EOF
# Drop OSS Game Library - User Guide

## Access
- **Web Interface**: https://$DOMAIN_NAME/games/
- **Setup URL**: $SETUP_URL (first-time setup only)

## Admin Setup

1. **Complete Setup Wizard**:
   - Visit the Setup URL above
   - Create your admin account
   - Configure library sources

2. **Configure Metadata Provider**:
   - Provider: $METADATA_PROVIDER
   $([ "$METADATA_PROVIDER" = "giantbomb" ] && echo "  - API Key configured")
   $([ "$METADATA_PROVIDER" = "igdb" ] && echo "  - Client ID/Secret configured")

3. **Create Library Source**:
   - Go to Admin → Library Sources
   - Create new source
   - Type: Filesystem (Drop-style recommended)
   - Path: /library

## Game Library Structure

### Drop-style (Recommended)
\`\`\`
/library/
  Game Name/
    version-1/
      game.exe
      data/
    version-2/
      game.exe
      data/
\`\`\`

### Flat-style (Compatibility)
\`\`\`
/library/
  Game Name/
    game.exe
    data/
  Game.zip
\`\`\`

## Adding Games

1. **Copy game files to library**:
   \`\`\`bash
   cp -r "My Game" $LIBRARY_DIR/
   \`\`\`

2. **Import in admin interface**:
   - Go to Library → Games
   - Click "Import Game"
   - Search for metadata
   - Select correct game

3. **Import versions**:
   - Click "Import Version"
   - Wait for checksum generation
   - Verify file count

## Installing Drop Client

### Linux (AppImage)
\`\`\`bash
# Download from GitHub releases
wget https://github.com/Drop-OSS/drop-app/releases/latest/download/drop-app.AppImage
chmod +x drop-app.AppImage
./drop-app.AppImage
\`\`\`

### Windows
Download .exe from releases page

### macOS
Download .dmg from releases page

### Steam Deck
Available via Discover Store or AUR

## Connecting Client

1. Open Drop client
2. Enter server URL: $EXTERNAL_URL
3. Login with admin credentials
4. Browse and download games!

## Game Updates

### Adding New Version
1. Create new version folder:
   \`\`\`bash
   mkdir -p /library/Game/version-2
   cp new-files/* /library/Game/version-2/
   \`\`\`
2. Import in admin interface
3. Users see new version

### Delta Updates
- Enable delta for updates
- Only changed files download
- Drag to set priority order
- Higher priority = newer files

## User Management

### Create Users
1. Admin → Users
2. Click "Create Invite"
3. Share invite link
4. User creates account

### Authentication
$([ "$OIDC_ENABLED" = "true" ] && echo "- OIDC enabled (SSO)" || echo "- Simple auth (username/password)")

## Metadata Providers

### GiantBomb
- Free API key
- Community-driven database
- Good for most games

### IGDB
- Requires Twitch account
- More comprehensive
- Official database

### PCGamingWiki
- Automatic if accessible
- Technical info
- Fixes and tweaks

## File Organization Tips

### Recommended Structure
\`\`\`
/library/
  [Game Title]/
    version-[number]/
      [game files]
    version-[number]-delta/
      [updated files only]
\`\`\`

### Large Games
- Use archives for big games
- Split into multiple parts
- Drop supports ZIP archives

### Mod Support
- Create mod as separate version
- Users can choose version
- Easy mod management

## Troubleshooting

### Time Sync Errors
\`\`\`bash
# Server and client must be within 30 seconds
sudo ntpdate -u pool.ntp.org
\`\`\`

### Library Import Fails
- Check file permissions
- Verify directory structure
- Check logs: \`docker logs winejs-droposs\`

### Client Connection Issues
- Verify EXTERNAL_URL is correct
- Check firewall rules
- Test connection from client machine

## Integration with WineJS

### Game Downloads
- Download games to Directory Lister
- Share with team
- Archive old versions

### Game Metadata
- Pull metadata from GiantBomb/IGDB
- Store in ArchiveBox
- Share via Artalk comments

### User Management
- Sync users with OIDC
- Integrate with ChiefOnboarding
- Track in Huly projects

## Commands

\`\`\`bash
# View logs
winejs-droposs logs

# Restart services
winejs-droposs restart

# Check status
winejs-droposs status

# View setup info
winejs-droposs setup

# Open dashboard
winejs-droposs open
\`\`\`

## Support

- **GitHub**: https://github.com/Drop-OSS/drop
- **Discord**: Join community
- **Docs**: https://droposs.org/docs
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Drop OSS icon..."

if curl -L "$DROPOSS_LOGO_URL" -o "$ICON_DIR/droposs.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/droposs.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1"/>
  <path d="M2 8s2-1 4-1 4 1 6 1 4-1 6-1 4 1 4 1"/>
  <path d="M6 15v-4"/>
  <path d="M10 15v-4"/>
  <path d="M14 15v-4"/>
  <path d="M18 15v-4"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-droposs << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
EXTERNAL_URL="${EXTERNAL_URL}"
LIBRARY_DIR="${LIBRARY_DIR}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/droposs && docker compose ps
        ;;
    logs)
        docker logs winejs-droposs --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/droposs && docker compose restart
        echo "Drop OSS restarted"
        ;;
    setup)
        echo "🔑 Setup Information:"
        echo "  Setup URL: https://\${DOMAIN_NAME}/games/setup"
        echo "  First-time setup required for admin account"
        echo ""
        echo "To get setup key:"
        echo "  docker logs winejs-droposs | grep 'Setup URL'"
        ;;
    library)
        echo "📁 Game Library Directory: $LIBRARY_DIR"
        echo ""
        echo "Current games:"
        ls -la "$LIBRARY_DIR" 2>/dev/null || echo "  No games yet"
        ;;
    add-game)
        shift
        if [ $# -lt 1 ]; then
            echo "Usage: winejs-droposs add-game <game-folder>"
            echo "Example: winejs-droposs add-game ~/Games/MyGame"
        else
            cp -r "\$1" "$LIBRARY_DIR/"
            echo "✅ Game added to library. Import via admin interface."
        fi
        ;;
    clients)
        echo "📱 Download Drop Client:"
        echo "  Linux: https://github.com/Drop-OSS/drop-app/releases"
        echo "  Windows: https://github.com/Drop-OSS/drop-app/releases"
        echo "  macOS: https://github.com/Drop-OSS/drop-app/releases"
        echo ""
        echo "Server URL: $EXTERNAL_URL"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/games/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/games/"
        fi
        ;;
    *)
        echo "Drop OSS Game Library Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-droposs open           - Open dashboard"
        echo "  winejs-droposs status         - Check status"
        echo "  winejs-droposs logs           - View logs"
        echo "  winejs-droposs restart        - Restart"
        echo "  winejs-droposs setup          - Show setup info"
        echo "  winejs-droposs library        - Show library directory"
        echo "  winejs-droposs add-game <dir> - Add game to library"
        echo "  winejs-droposs clients        - Client download links"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/games/"
        echo ""
        echo "First-Time Setup:"
        echo "  1. Visit the URL above"
        echo "  2. Complete setup wizard"
        echo "  3. Create admin account"
        echo "  4. Configure library source"
        echo ""
        echo "Game Library: $LIBRARY_DIR"
        echo ""
        echo "Metadata Provider: $METADATA_PROVIDER"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/droposs/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-droposs

# ============= UPDATE NGINX FOR DROP OSS =============
log "📝 Setting up nginx reverse proxy for Drop OSS..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /games" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Drop OSS Game Library\n\
    location /games {\n\
        rewrite ^/games(/.*)?$ /\\\$1 break;\n\
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
        client_max_body_size 0;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Drop OSS routes"
            else
                warn "Nginx test failed, restoring backup"
                cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                nginx -t && systemctl reload nginx
            fi
        fi
    fi
fi

# ============= CREATE SAMPLE GAME DIRECTORY STRUCTURE =============
log "📁 Creating sample game directory structure..."

mkdir -p "$LIBRARY_DIR/Sample Game/version-1"
cat > "$LIBRARY_DIR/Sample Game/version-1/readme.txt" << EOF
This is a sample game folder.

To add real games:
1. Copy your game files to /library/GameName/version-1/
2. Import in Drop admin interface
3. Game will be available to download via client
EOF

# ============= RESTART TRANSLATOR =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_droposs.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Drop OSS..."

cd /opt/winejs/kasmvnc-instances/droposs
docker compose down -v 2>/dev/null

rm -rf /opt/winejs/apps/droposs
rm -rf /opt/winejs/kasmvnc-instances/droposs
rm -rf /opt/winejs/data/droposs

rm -f /usr/local/bin/winejs-droposs

# Ask about removing game library
read -p "Remove game library directory ($LIBRARY_DIR)? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$LIBRARY_DIR"
    log "✅ Game library removed"
fi

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Drop OSS Game Library/,/location \/games/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/games {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Drop OSS uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_droposs.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              DROP OSS INSTALLED ON WINEJS!                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Drop OSS Game Library installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/games/"
echo ""
info "🔑 First-Time Setup:"
info "   • Visit the URL above"
info "   • Complete setup wizard"
info "   • Create admin account"
info "   • Configure library source"
echo ""
info "📁 Game Library Directory:"
info "   • $LIBRARY_DIR"
echo ""
info "🎮 Metadata Provider:"
info "   • $METADATA_PROVIDER"
if [ "$METADATA_PROVIDER" = "giantbomb" ]; then
    info "   • API Key configured"
fi
if [ "$METADATA_PROVIDER" = "igdb" ]; then
    info "   • IGDB credentials configured"
fi
echo ""
info "🔐 Authentication:"
if [ "$OIDC_ENABLED" = "true" ]; then
    info "   • OIDC enabled (SSO)"
else
    info "   • Simple auth (username/password)"
fi
echo ""
info "📱 Client Downloads:"
info "   • Linux: AppImage (GitHub releases)"
info "   • Windows: .exe installer"
info "   • macOS: .dmg package"
info "   • Steam Deck: Discover Store / AUR"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-droposs open           # Open dashboard"
info "   • winejs-droposs setup          # Show setup info"
info "   • winejs-droposs library        # Show game library"
info "   • winejs-droposs add-game <dir> # Add game to library"
info "   • winejs-droposs clients        # Client download links"
info "   • winejs-droposs status         # Check status"
echo ""
info "📁 Data Directories:"
info "   • Database: ${DATA_DIR}/db"
info "   • Game Library: ${LIBRARY_DIR}"
info "   • Drop Data: ${DATA_DIR}/data"
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/droposs/user-guide.md"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_droposs.sh"
echo ""
success "✨ Drop OSS is ready! Start managing your game library at https://$DOMAIN_NAME/games/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Drop OSS Does:

# Drop OSS is a self-hosted game library manager and launcher (like Steam but open source and self-hosted!):
# Key Features:

#     Game Library Management - Organize all your games in one place
#     Version Control - Keep multiple versions of games (vanilla, modded)
#     Delta Updates - Only download changed files
#     Metadata Import - Pull game info from GiantBomb/IGDB
#     Multi-User - Share games with friends/family
#     Cross-Platform - Clients for Linux, Windows, macOS, Steam Deck
#     Efficient Storage - Avoid duplicate files with deltas
#     Modern UI - Clean, attractive interface

# Perfect For:
#     Game Collectors - Organize your game collection
#     LAN Parties - Share games locally without re-downloading
#     Mod Enthusiasts - Keep multiple modded versions
#     Families - Share games with multiple users
#     Game Devs - Distribute builds to testers