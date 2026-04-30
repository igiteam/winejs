#!/bin/bash
# ============================================
# ConvertX File Converter - WineJS Installer
# Adds File Conversion Platform to WineJS
# ============================================
# App: ConvertX
# Category: Productivity
# Features: File Conversion, Batch Processing, Multiple Formats
# ============================================

CONVERTX_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/convertx-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🔄 Installing WineJS ConvertX File Converter..."

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

# ============= ASK FOR CONVERTX CONFIGURATION =============
echo ""
info "📝 ConvertX Configuration"
echo "================================"
read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

read -p "Allow new account registration? (true/false) [false]: " ACCOUNT_REGISTRATION
ACCOUNT_REGISTRATION=${ACCOUNT_REGISTRATION:-false}

read -p "Allow unauthenticated usage? (true/false) [false]: " ALLOW_UNAUTHENTICATED
ALLOW_UNAUTHENTICATED=${ALLOW_UNAUTHENTICATED:-false}

read -p "Auto-delete files after (hours) [24]: " AUTO_DELETE_HOURS
AUTO_DELETE_HOURS=${AUTO_DELETE_HOURS:-24}

read -p "Maximum concurrent conversions (0=unlimited) [2]: " MAX_CONCURRENT
MAX_CONCURRENT=${MAX_CONCURRENT:-2}

read -p "Webroot path (leave empty for /convert) [/convert]: " WEBROOT
WEBROOT=${WEBROOT:-"/convert"}

# Generate JWT secret
JWT_SECRET=$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=8800  # Start after CommaFeed's range (8700+)
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

# Find available port for ConvertX
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for ConvertX"
fi

log "Using port: ConvertX=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="convertx"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/convertx"
DATA_DIR="/opt/winejs/data/convertx"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{data,temp}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/convertx"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # ConvertX File Converter
  winejs-convertx:
    image: ghcr.io/c4illin/convertx:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:3000"
    volumes:
      - ${DATA_DIR}:/app/data
    environment:
      - JWT_SECRET=${JWT_SECRET}
      - ACCOUNT_REGISTRATION=${ACCOUNT_REGISTRATION}
      - ALLOW_UNAUTHENTICATED=${ALLOW_UNAUTHENTICATED}
      - AUTO_DELETE_EVERY_N_HOURS=${AUTO_DELETE_HOURS}
      - MAX_CONVERT_PROCESS=${MAX_CONCURRENT}
      - WEBROOT=/convert
      - LANGUAGE=en
      - HIDE_HISTORY=false
      - UNAUTHENTICATED_USER_SHARING=false
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= START CONTAINER =============
log "🚀 Starting ConvertX container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for ConvertX to initialize..."
sleep 15

# Create admin account via API or UI
log "🔐 Setting up admin account..."

# Wait for service to be ready
MAX_ATTEMPTS=30
for i in $(seq 1 $MAX_ATTEMPTS); do
    if curl -s -f "http://127.0.0.1:${APP_PORT}/" >/dev/null 2>&1; then
        log "✅ ConvertX is ready"
        
        # Try to register admin via API
        curl -X POST "http://127.0.0.1:${APP_PORT}/api/register" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" 2>/dev/null || true
        break
    fi
    if [ $i -eq $MAX_ATTEMPTS ]; then
        warn "ConvertX may not be fully ready. Please register manually at https://${DOMAIN_NAME}/convert"
    fi
    sleep 2
done

log "✅ ConvertX initialized"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

# Build features list
cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "ConvertX File Converter",
    "version": "latest",
    "description": "Self-hosted online file converter supporting 1000+ formats",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/convertx.png",
    "category": "Productivity",
    "features": [
        "🔄 1000+ File Formats",
        "📦 Batch Conversion",
        "🔐 Password Protection",
        "👥 Multiple Accounts",
        "🖼️ Image Conversion",
        "🎬 Video Conversion",
        "📄 Document Conversion",
        "📚 E-book Conversion",
        "🎨 Vector Graphics",
        "3D Model Conversion",
        "📧 Email Conversion",
        "🗄️ Data Format Conversion",
        "⚡ Fast Processing",
        "🔒 Self-hosted"
    ]
}
CONF_EOF

# ============= CREATE USAGE GUIDE =============
log "📝 Creating usage guide..."

cat > "$APP_DIR/usage-guide.md" << GUIDE_EOF
# ConvertX File Converter - Usage Guide

## Access
- **Main Interface**: https://$DOMAIN_NAME/convert/
- **Login**: Use your registered email and password

## Supported Conversions

### Images (300+ formats)
- **Convert to**: PNG, JPEG, WEBP, AVIF, HEIC, TIFF, GIF, BMP
- **From**: Any image format, raw camera files, PSD, AI, CDR
- **Use case**: Website optimization, thumbnails, format compatibility

### Documents
- **Convert to**: PDF, DOCX, ODT, TXT, HTML, EPUB
- **From**: Word, Excel, PowerPoint, OpenOffice, Markdown, LaTeX
- **Use case**: Reports, contracts, sharing, archiving

### E-books
- **Convert to**: EPUB, MOBI, AZW3, PDF, DOCX
- **From**: EPUB, PDF, MOBI, AZW, DOCX, HTML
- **Use case**: Kindle, Kobo, Apple Books, reading apps

### Video
- **Convert to**: MP4, WEBM, MKV, AVI, MOV, GIF
- **From**: Any video format (472+ input formats)
- **Use case**: Social media, web optimization, editing

### Vector Graphics
- **Convert to**: SVG, PDF, EPS, DXF
- **From**: SVG, PDF, AI, EPS, CDR
- **Use case**: Logos, illustrations, print design

### 3D Models
- **Convert to**: GLTF, GLB, OBJ, STL, PLY, FBX
- **From**: 77 source formats including Blend, OBJ, FBX, STL
- **Use case**: 3D printing, game assets, AR/VR

### Audio
- **Convert to**: MP3, WAV, OGG, AAC, FLAC, M4A
- **From**: Any audio format
- **Use case**: Podcasts, music, ringtones

### Data Files
- **Convert to**: JSON, YAML, TOML, XML, CSV
- **From**: Data formats, API responses, configuration files
- **Use case**: Data processing, API integration

## How to Use

### Single File Conversion
1. Visit https://$DOMAIN_NAME/convert/
2. Upload your file (drag & drop supported)
3. Select target format
4. Click "Convert"
5. Download your converted file

### Batch Conversion
1. Upload multiple files
2. Select same or different target formats
3. Convert all at once
4. Download as zip archive

### Password Protection
1. Use your account (first user registers as admin)
2. $([ "$ACCOUNT_REGISTRATION" = "true" ] && echo "New users can register" || echo "Account registration is disabled")
3. $([ "$ALLOW_UNAUTHENTICATED" = "true" ] && echo "Unauthenticated usage is allowed" || echo "Authentication required for conversions")

## Integration Examples

### With WineJS Apps

**Convert images for ArchiveBox:**
1. Upload screenshot to ConvertX
2. Convert to WEBP (smaller size)
3. Archive the optimized version

**Prepare documents for Huly:**
1. Convert Word docs to PDF
2. Upload to Huly project
3. Team can view without Word

**Process e-books for Calibre/Readarr:**
1. Upload EPUB/MOBI
2. Convert to Kindle format
3. Add to your reading app

**Convert 3D models for OpenSpy:**
1. Upload OBJ files
2. Convert to GLTF for web display
3. Use in 3D game previews

## API Usage

ConvertX has a REST API for programmatic conversion:

\`\`\`bash
# Register
curl -X POST https://$DOMAIN_NAME/convert/api/register \\
  -H "Content-Type: application/json" \\
  -d '{"email":"user@example.com","password":"secret"}'

# Login
curl -X POST https://$DOMAIN_NAME/convert/api/login \\
  -H "Content-Type: application/json" \\
  -d '{"email":"user@example.com","password":"secret"}'

# Convert file
curl -X POST https://$DOMAIN_NAME/convert/api/convert \\
  -H "Authorization: Bearer <token>" \\
  -F "file=@document.pdf" \\
  -F "format=docx"
\`\`\`

## Advanced Options

### FFmpeg Arguments
Add custom ffmpeg parameters for video conversion (configured in environment)

### Quality Settings
- **Images**: Adjust compression level (0-100)
- **Video**: Set bitrate, codec, resolution
- **Audio**: Sample rate, bit rate, channels

### Batch Processing
- Upload up to 50 files at once
- Each file processes independently
- Download individual results or all as ZIP

## Tips & Tricks

### Reduce Image Sizes
- Convert PNG to WEBP (60-80% smaller)
- Adjust quality to 80-85% for web
- Use progressive JPEG for faster loading

### Optimize for Web
- Convert video to MP4 with H.264
- Generate WebM for modern browsers
- Create thumbnails with specific dimensions

### Document Compatibility
- Convert DOCX to PDF for sharing
- Use TXT for maximum compatibility
- HTML conversion for web publishing

### E-book Best Practices
- EPUB for most readers
- MOBI/AZW3 for Kindle
- PDF for print/archive

## Troubleshooting

**File too large?**
- ConvertX handles files up to server limits
- Check your nginx client_max_body_size

**Slow conversion?**
- Video/3D files take longer
- Adjust MAX_CONVERT_PROCESS for more parallel jobs

**Format not supported?**
- Open an issue on GitHub
- Request new converters

**Can't login?**
- First user to visit becomes admin
- $([ "$ACCOUNT_REGISTRATION" = "true" ] && echo "Registration is open" || echo "Registration requires admin approval"))

## Commands

\`\`\`bash
# View logs
winejs-convertx logs

# Restart services
winejs-convertx restart

# Check status
winejs-convertx status

# Open converter
winejs-convertx open
\`\`\`

## Support

- GitHub: https://github.com/C4illin/ConvertX
- Issues: Report bugs or request converters
- Documentation: In-app and online
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up ConvertX icon..."

if curl -L "$CONVERTX_LOGO_URL" -o "$ICON_DIR/convertx.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/convertx.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M21 12L15 6M21 12L15 18M21 12H3M9 6L3 12L9 18"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-convertx << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

case "\$1" in
    status)
        docker ps | grep winejs-convertx
        ;;
    logs)
        docker logs winejs-convertx --tail 50
        ;;
    restart)
        docker restart winejs-convertx
        echo "ConvertX restarted"
        ;;
    config)
        echo "📋 ConvertX Configuration:"
        echo "  • Admin Email: $ADMIN_EMAIL"
        echo "  • Registration: $ACCOUNT_REGISTRATION"
        echo "  • Unauthenticated: $ALLOW_UNAUTHENTICATED"
        echo "  • Auto-delete: ${AUTO_DELETE_HOURS}h"
        echo "  • Max concurrent: $MAX_CONCURRENT"
        ;;
    stats)
        echo "📊 Data directory size:"
        du -sh /opt/winejs/data/convertx 2>/dev/null || echo "No data yet"
        ;;
    cleanup)
        echo "🗑️ Manual cleanup of old files..."
        echo "Files older than ${AUTO_DELETE_HOURS} hours are auto-deleted"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/convert/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/convert/"
        fi
        ;;
    *)
        echo "ConvertX File Converter Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-convertx open           - Open ConvertX"
        echo "  winejs-convertx status         - Check status"
        echo "  winejs-convertx logs           - View logs"
        echo "  winejs-convertx restart        - Restart"
        echo "  winejs-convertx config         - Show config"
        echo "  winejs-convertx stats          - Show stats"
        echo "  winejs-convertx cleanup        - Cleanup guide"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/convert/"
        echo ""
        echo "Admin Setup:"
        echo "  The first person to visit the site and register becomes admin"
        echo "  Register with: $ADMIN_EMAIL"
        echo ""
        echo "Supported Formats:"
        echo "  • 1000+ file formats"
        echo "  • Images, video, audio, documents"
        echo "  • E-books, 3D models, vector graphics"
        echo "  • Data formats, emails, archives"
        echo ""
        echo "Usage Guide: cat /opt/winejs/apps/convertx/usage-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-convertx

# ============= UPDATE NGINX FOR CONVERTX =============
log "📝 Setting up nginx reverse proxy for ConvertX..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /convert" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # ConvertX File Converter\n\
    location /convert {\n\
        rewrite ^/convert(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 3600s;\n\
        proxy_buffering off;\n\
        client_max_body_size 1024M;\n\
    }\n\
    \n\
    # ConvertX API\n\
    location /convert/api/ {\n\
        rewrite ^/convert/api/(.*)$ /api/\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_read_timeout 3600s;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with ConvertX routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_convertx.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling ConvertX..."

docker stop winejs-convertx 2>/dev/null
docker rm winejs-convertx 2>/dev/null

rm -rf /opt/winejs/apps/convertx
rm -rf /opt/winejs/kasmvnc-instances/convertx
rm -rf /opt/winejs/data/convertx

rm -f /usr/local/bin/winejs-convertx

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# ConvertX File Converter/,/location \/convert\/api\//d' /etc/nginx/sites-available/winejs
    sed -i '/location \/convert {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ ConvertX uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_convertx.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              CONVERTX INSTALLED ON WINEJS!                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ ConvertX File Converter installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/convert/"
echo ""
info "🔐 Setup:"
info "   • First visitor registers as admin"
info "   • Email: $ADMIN_EMAIL"
info "   • Password: [the password you set]"
echo ""
info "🔄 Supported Formats:"
info "   • Images (300+ formats) - PNG, JPEG, WEBP, GIF, HEIC"
info "   • Video (472+ formats) - MP4, WEBM, MKV, AVI"
info "   • Documents (84+ formats) - PDF, DOCX, ODT, HTML"
info "   • E-books (45+ formats) - EPUB, MOBI, AZW3"
info "   • 3D Models (100+ formats) - GLTF, OBJ, STL"
info "   • Audio - MP3, WAV, FLAC, OGG, AAC"
info "   • Vector Graphics - SVG, PDF, EPS"
info "   • Data Formats - JSON, YAML, XML, CSV"
echo ""
info "⚙️ Configuration:"
info "   • Account Registration: $ACCOUNT_REGISTRATION"
info "   • Unauthenticated Usage: $ALLOW_UNAUTHENTICATED"
info "   • Auto-delete after: ${AUTO_DELETE_HOURS} hours"
info "   • Max concurrent: $MAX_CONCURRENT"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-convertx open        # Open converter"
info "   • winejs-convertx status      # Check status"
info "   • winejs-convertx logs        # View logs"
info "   • winejs-convertx config      # Show config"
info "   • winejs-convertx stats       # Show storage stats"
echo ""
info "📁 Data Directory:"
info "   • ${DATA_DIR}"
echo ""
info "📚 Usage Guide:"
info "   • cat /opt/winejs/apps/convertx/usage-guide.md"
echo ""
info "💡 Use Cases:"
info "   • Convert Office docs to PDF"
info "   • Optimize images for web"
info "   • Prepare e-books for Kindle"
info "   • Transcode video formats"
info "   • Convert 3D models for printing"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_convertx.sh"
echo ""
success "✨ ConvertX is ready! Start converting files at https://$DOMAIN_NAME/convert/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What ConvertX Does:

# ConvertX is a powerful self-hosted file converter supporting 1000+ formats:
# Key Features:
#     1000+ File Formats - Images, video, audio, documents, e-books, 3D models
#     Batch Conversion - Convert multiple files at once
#     Password Protection - Secure your conversions
#     Multiple Accounts - Support for multiple users
#     Self-hosted - Full control over your data

# Major Converters Included:
# Converter	Use Case	Formats
# FFmpeg	Video/Audio	472→199 formats
# ImageMagick	Images	245→183 formats
# LibreOffice	Documents	41→22 formats
# Calibre	E-books	26→19 formats
# Pandoc	Documents	43→65 formats
# Assimp	3D Models	77→23 formats
# Inkscape	Vector	7→17 formats
# Vips	Images	45→23 formats

# Perfect For:
#     Web Developers - Optimize images, convert videos
#     Content Creators - Format conversion for publishing
#     E-book Readers - Convert for Kindle/Kobo
#     3D Printing - Convert 3D models to STL
#     Office Work - Convert documents between formats