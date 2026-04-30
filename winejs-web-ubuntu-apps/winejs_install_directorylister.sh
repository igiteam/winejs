#!/bin/bash
# ============================================
# Directory Lister - WineJS Installer
# Adds File Browser & Sharing to WineJS Platform
# ============================================
# App: Directory Lister
# Category: Productivity
# Features: File Browsing, Directory Sharing, File Management
# ============================================

DIRECTORY_LISTER_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/directorylister-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📁 Installing WineJS Directory Lister..."

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

# ============= ASK FOR DIRECTORY LISTER CONFIGURATION =============
echo ""
info "📝 Directory Lister Configuration"
echo "================================"
read -p "Site title [File Browser]: " SITE_TITLE
SITE_TITLE=${SITE_TITLE:-"File Browser"}

read -p "Directory to share [/opt/winejs/shared]: " SHARE_PATH
SHARE_PATH=${SHARE_PATH:-"/opt/winejs/shared"}

read -p "Enable zip downloads? (true/false) [true]: " ZIP_DOWNLOADS
ZIP_DOWNLOADS=${ZIP_DOWNLOADS:-true}

read -p "Display README files? (true/false) [true]: " DISPLAY_READMES
DISPLAY_READMES=${DISPLAY_READMES:-true}

read -p "Hide dot files? (true/false) [true]: " HIDE_DOT_FILES
HIDE_DOT_FILES=${HIDE_DOT_FILES:-true}

read -p "Sort order (type/name/modified/size) [type]: " SORT_ORDER
SORT_ORDER=${SORT_ORDER:-"type"}

read -p "Reverse sort? (true/false) [false]: " REVERSE_SORT
REVERSE_SORT=${REVERSE_SORT:-false}

read -p "App language (en/es/fr/de/ja/zh) [en]: " APP_LANGUAGE
APP_LANGUAGE=${APP_LANGUAGE:-"en"}

# ============= CREATE SHARE DIRECTORY IF NOT EXISTS =============
if [ ! -d "$SHARE_PATH" ]; then
    log "📁 Creating share directory: $SHARE_PATH"
    mkdir -p "$SHARE_PATH"
    chmod 755 "$SHARE_PATH"
fi

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=8900  # Start after ConvertX's range (8800+)
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

# Find available port for Directory Lister
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Directory Lister"
fi

log "Using port: Directory Lister=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="directorylister"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/directorylister"
DATA_DIR="/opt/winejs/data/directorylister"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/directorylister"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE .env FILE =============
log "📝 Creating .env configuration..."

cat > "$DATA_DIR/.env" << EOF
# Directory Lister Configuration
APP_DEBUG=false
APP_LANGUAGE=${APP_LANGUAGE}
SITE_TITLE="${SITE_TITLE}"
DISPLAY_READMES=${DISPLAY_READMES}
ZIP_DOWNLOADS=${ZIP_DOWNLOADS}
HIDE_DOT_FILES=${HIDE_DOT_FILES}
SORT_ORDER=${SORT_ORDER}
REVERSE_SORT=${REVERSE_SORT}
TIMEZONE=UTC
MAX_HASH_SIZE=104857600
EOF

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Directory Lister File Browser
  winejs-directorylister:
    image: directorylister/directorylister:5
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:80"
    volumes:
      - ${SHARE_PATH}:/data:ro
      - ${DATA_DIR}/.env:/var/www/html/.env:ro
    environment:
      - FILES_PATH=/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost/"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE .htaccess FOR HIDING FILES =============
log "📝 Creating .hidden file configuration..."

cat > "$DATA_DIR/.hidden" << EOF
# Hidden files and directories
.git
.svn
.hg
.DS_Store
Thumbs.db
*.tmp
*.log
*.cache
EOF

# ============= START CONTAINER =============
log "🚀 Starting Directory Lister container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Directory Lister to initialize..."
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
    "name": "Directory Lister",
    "version": "5",
    "description": "Simple file browser to expose and share directory contents",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/directorylister.png",
    "category": "Productivity",
    "features": [
        "📁 File Browsing",
        "🔍 File Search",
        "📦 Zip Downloads",
        "📖 README Rendering",
        "🌙 Light/Dark Themes",
        "🔐 File Hashing",
        "🌍 Multi-language",
        "📱 Responsive Design",
        "⚡ Zero Configuration",
        "🔄 Custom Sort Order",
        "🚫 Hide Files Pattern"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << GUIDE_EOF
# Directory Lister - User Guide

## Access
- **File Browser**: https://$DOMAIN_NAME/files/

## Overview

Directory Lister provides a clean, modern interface for browsing and sharing files in a directory.

## Features

### File Browsing
- Navigate through folders
- View file details (size, modified date)
- Sort by name, size, type, or date
- Toggle between grid and list views

### File Search
- Search for files by name
- Real-time filtering
- Case-insensitive matching

### Zip Downloads
- Download entire folders as ZIP
- Preserves directory structure
- Progress indication

### README Support
- README.md files render as HTML
- Multiple README formats supported
- Display before or after file listing

### File Hashing
- MD5, SHA1, SHA256 hashes
- Verify file integrity
- Configurable max file size

### Themes
- Light theme (default)
- Dark theme (eye-friendly)
- Auto-detects system preference

## Managing Shared Files

### Adding Files
Simply copy files to: \`$SHARE_PATH\`

\`\`\`bash
# Example: Share a file
cp important.pdf $SHARE_PATH/

# Example: Create a shared folder
mkdir -p $SHARE_PATH/projects
cp -r myproject/* $SHARE_PATH/projects/
\`\`\`

### Hiding Files

Create patterns in \`.hidden\` file:
\`\`\`
# Hide backup files
*.bak
*.tmp

# Hide specific folders
private/
confidential/
\`\`\`

### Custom Styling

Add \`.customizations.html\` to inject CSS/JS:
\`\`\`html
<style>
  /* Custom styles */
  .file-list { font-size: 14px; }
</style>

<script>
  // Analytics tracking
  console.log("Custom script loaded");
</script>
\`\`\`

## Configuration Options

### Current Settings
- **Share Directory**: $SHARE_PATH
- **Site Title**: $SITE_TITLE
- **Language**: $APP_LANGUAGE
- **Zip Downloads**: $ZIP_DOWNLOADS
- **README Display**: $DISPLAY_READMES
- **Hide Dot Files**: $HIDE_DOT_FILES
- **Sort Order**: $SORT_ORDER
- **Reverse Sort**: $REVERSE_SORT

## Integration with WineJS Apps

### Share Files Between Apps

\`\`\`bash
# ArchiveBox exports
cp -r /opt/winejs/data/archivebox/archive/* $SHARE_PATH/

# ConvertX outputs
cp /opt/winejs/data/convertx/data/*.pdf $SHARE_PATH/

# Castopod media
ln -s /opt/winejs/data/castopod/media $SHARE_PATH/podcasts
\`\`\`

### Create Download Portal
1. Symlink other app data directories
2. Organize into categories
3. Share the URL with team

### Automated File Publishing

Use with n8n workflows:
1. Watch directory for changes
2. Process files (ConvertX)
3. Publish to Directory Lister
4. Notify team (Mumble/Slack)

## Security Considerations

### Authentication

Directory Lister doesn't include built-in auth. Add protection via:

**HTTP Basic Auth (Nginx):**
\`\`\`nginx
location /files {
    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/.htpasswd;
}
\`\`\`

**Authelia Integration:**
- Configure Authelia as reverse proxy
- Add 2FA protection
- SSO with existing identity provider

### Access Control

\`\`\`bash
# Read-only share
chmod -R 755 $SHARE_PATH

# Specific user access
chown -R www-data:www-data $SHARE_PATH
chmod -R 750 $SHARE_PATH
\`\`\`

## Use Cases

### Team File Sharing
- Share documents, assets, builds
- Centralized download portal
- Versioned file access

### Public Download Area
- Software distributions
- Documentation packages
- Media files

### Internal Knowledge Base
- Store guides and documentation
- Share training materials
- Distribute company policies

### Backup Viewer
- Browse backup archives
- Restore individual files
- Verify backup contents

## Troubleshooting

**Files not appearing?**
- Check directory permissions
- Verify mount path in docker-compose
- Clear browser cache

**Zip downloads failing?**
- Check disk space
- Verify PHP memory limit
- Large directories may timeout

**Search not working?**
- Rebuild index (restart container)
- Check file permissions

## Commands

\`\`\`bash
# View logs
winejs-directorylister logs

# Restart services
winejs-directorylister restart

# Check status
winejs-directorylister status

# Open browser
winejs-directorylister open

# Add file to share
cp file.txt $SHARE_PATH/

# List shared files
ls -la $SHARE_PATH/
\`\`\`

## Customization

### Add Analytics
Create \`$DATA_DIR/.customizations.html\`:

\`\`\`html
<!-- Google Analytics -->
<script async src="https://www.googletagmanager.com/gtag/js?id=G-XXXXXXXXXX"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', 'G-XXXXXXXXXX');
</script>

<!-- Matomo Analytics -->
<script>
  var _paq = window._paq = window._paq || [];
  _paq.push(['trackPageView']);
  _paq.push(['enableLinkTracking']);
  (function() {
    var u="//matomo.example.com/";
    _paq.push(['setTrackerUrl', u+'matomo.php']);
    _paq.push(['setSiteId', '1']);
    var d=document, g=d.createElement('script'), s=d.getElementsByTagName('script')[0];
    g.async=true; g.src=u+'matomo.js'; s.parentNode.insertBefore(g,s);
  })();
</script>
\`\`\`
GUIDE_EOF

# ============= CREATE SAMPLE FILES =============
log "📝 Creating sample files in share directory..."

cat > "$SHARE_PATH/README.md" << EOF
# Welcome to Directory Lister

This is a sample README file. Directory Lister automatically displays README files in the file listing.

## Features
- Browse files and folders
- Download entire directories as ZIP
- Search for files
- View file hashes (MD5, SHA1, SHA256)

## Quick Links
- [Back to WineJS](https://$DOMAIN_NAME/)
- [Directory Lister Docs](https://$DOMAIN_NAME/files/)

## Tip
Create a \`.hidden\` file to hide sensitive files or folders.
EOF

echo "Sample file created at $(date)" > "$SHARE_PATH/welcome.txt"
mkdir -p "$SHARE_PATH/sample-folder"
echo "This is a sample file in a subfolder" > "$SHARE_PATH/sample-folder/sample.txt"

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Directory Lister icon..."

if curl -L "$DIRECTORY_LISTER_LOGO_URL" -o "$ICON_DIR/directorylister.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/directorylister.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7l-2-2H4a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2Z"/>
  <path d="M12 10v4"/>
  <path d="M10 12h4"/>
</svg>
SVG_EOF
    # Try to convert SVG to PNG if ImageMagick is available
    if command -v convert &>/dev/null; then
        convert "$ICON_DIR/directorylister.svg" "$ICON_DIR/directorylister.png" 2>/dev/null || true
    else
        # Use a data URI base64 encoded 1x1 pixel as fallback, or copy default
        cp /opt/winejs/translator/public/icons/default-app.png "$ICON_DIR/directorylister.png" 2>/dev/null || true
    fi
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-directorylister << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
SHARE_PATH="${SHARE_PATH}"

case "\$1" in
    status)
        docker ps | grep winejs-directorylister
        ;;
    logs)
        docker logs winejs-directorylister --tail 50
        ;;
    restart)
        docker restart winejs-directorylister
        echo "Directory Lister restarted"
        ;;
    share)
        echo "📁 Shared directory: $SHARE_PATH"
        echo "Contents:"
        ls -la "$SHARE_PATH"
        ;;
    add)
        shift
        if [ $# -lt 1 ]; then
            echo "Usage: winejs-directorylister add <file-or-directory>"
        else
            cp -r "\$@" "$SHARE_PATH/"
            echo "✅ Added to shared directory"
        fi
        ;;
    remove)
        shift
        if [ $# -lt 1 ]; then
            echo "Usage: winejs-directorylister remove <filename>"
        else
            rm -rf "$SHARE_PATH/\$1"
            echo "✅ Removed from shared directory"
        fi
        ;;
    size)
        echo "📊 Share directory size:"
        du -sh "$SHARE_PATH" 2>/dev/null || echo "0"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/files/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/files/"
        fi
        ;;
    *)
        echo "Directory Lister File Browser Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-directorylister open        - Open file browser"
        echo "  winejs-directorylister status      - Check status"
        echo "  winejs-directorylister logs        - View logs"
        echo "  winejs-directorylister restart     - Restart"
        echo "  winejs-directorylister share       - Show share directory"
        echo "  winejs-directorylister add <file>  - Add file to share"
        echo "  winejs-directorylister remove <f>  - Remove from share"
        echo "  winejs-directorylister size        - Show directory size"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/files/"
        echo ""
        echo "Share Directory: $SHARE_PATH"
        echo ""
        echo "To share files, copy them to: $SHARE_PATH"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/directorylister/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-directorylister

# ============= UPDATE NGINX FOR DIRECTORY LISTER =============
log "📝 Setting up nginx reverse proxy for Directory Lister..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /files" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Directory Lister File Browser\n\
    location /files {\n\
        rewrite ^/files(/.*)?$ /\\\$1 break;\n\
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
        client_max_body_size 1024M;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Directory Lister routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_directorylister.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Directory Lister..."

docker stop winejs-directorylister 2>/dev/null
docker rm winejs-directorylister 2>/dev/null

rm -rf /opt/winejs/apps/directorylister
rm -rf /opt/winejs/kasmvnc-instances/directorylister
rm -rf /opt/winejs/data/directorylister

rm -f /usr/local/bin/winejs-directorylister

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Directory Lister File Browser/,/location \/files/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/files {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

# Ask about removing shared files
read -p "Remove shared files directory ($SHARE_PATH)? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$SHARE_PATH"
    log "✅ Shared files removed"
fi

log "✅ Directory Lister uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_directorylister.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           DIRECTORY LISTER INSTALLED ON WINEJS!                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Directory Lister File Browser installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/files/"
echo ""
info "📁 Share Directory:"
info "   • $SHARE_PATH"
echo ""
info "📋 Features:"
info "   • File browsing with search"
info "   • Zip downloads of folders"
info "   • README file rendering"
info "   • Light/dark themes"
info "   • File hashing (MD5/SHA1/SHA256)"
info "   • Multi-language support"
echo ""
info "⚙️ Configuration:"
info "   • Site Title: $SITE_TITLE"
info "   • Language: $APP_LANGUAGE"
info "   • Zip Downloads: $ZIP_DOWNLOADS"
info "   • Sort Order: $SORT_ORDER"
info "   • Reverse Sort: $REVERSE_SORT"
info "   • Hide Dot Files: $HIDE_DOT_FILES"
info "   • README Display: $DISPLAY_READMES"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-directorylister open        # Open file browser"
info "   • winejs-directorylister share       # Show share directory"
info "   • winejs-directorylister add <file>  # Add file to share"
info "   • winejs-directorylister remove <f>  # Remove from share"
info "   • winejs-directorylister size        # Show directory size"
info "   • winejs-directorylister status      # Check status"
echo ""
info "📂 To share files:"
info "   • Copy files to: $SHARE_PATH"
info "   • winejs-directorylister add myfile.pdf"
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/directorylister/user-guide.md"
echo ""
info "🔐 Security Note:"
info "   • No built-in authentication"
info "   • Add HTTP basic auth via nginx if needed"
info "   • Consider Authelia for advanced auth"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_directorylister.sh"
echo ""
success "✨ Directory Lister is ready! Browse files at https://$DOMAIN_NAME/files/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Directory Lister Does:

# Directory Lister is a simple, elegant file browser for sharing directories:
# Key Features:
#     File Browsing - Navigate directories with clean interface
#     File Search - Find files quickly with real-time search
#     Zip Downloads - Download entire folders as ZIP archives
#     README Support - Display README files as HTML
#     File Hashing - MD5, SHA1, SHA256 integrity verification
#     Dual Themes - Light and dark mode
#     Multi-language - Support for many languages
#     Zero Config - Works immediately with sensible defaults

# Perfect For:
#     File Sharing - Share documents with team or public
#     Download Portal - Distribute software packages
#     Internal Knowledge Base - Share documentation
#     Backup Explorer - Browse backup archives
#     Asset Library - Share images, videos, assets