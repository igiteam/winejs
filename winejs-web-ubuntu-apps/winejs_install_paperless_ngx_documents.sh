#!/bin/bash
# ============================================
# Paperless-ngx Document Management - WineJS Installer
# Adds Document Management System to WineJS Platform
# ============================================
# App: Paperless-ngx
# Category: Productivity
# Features: Document OCR, Searchable Archive, Tagging
# ============================================

PAPERLESS_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/paperless-ngx-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📄 Installing WineJS Paperless-ngx Document Management..."

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

# ============= ASK FOR PAPERLESS CONFIGURATION =============
echo ""
info "📝 Paperless-ngx Configuration"
echo "================================"
read -p "Admin username: " ADMIN_USER
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""
read -p "Admin email: " ADMIN_EMAIL

read -p "OCR Language (eng/deu/fra/ita/spa/nld/swe/nor/dan/fin) [eng]: " OCR_LANG
OCR_LANG=${OCR_LANG:-"eng"}

read -p "Timezone [UTC]: " TIMEZONE
TIMEZONE=${TIMEZONE:-"UTC"}

read -p "Database type (postgresql/sqlite) [postgresql]: " DB_TYPE
DB_TYPE=${DB_TYPE:-"postgresql"}

if [ "$DB_TYPE" = "postgresql" ]; then
    DB_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/')
fi

read -p "Consumption directory (where to scan for documents) [/opt/winejs/data/paperless/consume]: " CONSUME_DIR
CONSUME_DIR=${CONSUME_DIR:-"/opt/winejs/data/paperless/consume"}

read -p "Enable NLTK for better language processing? (true/false) [false]: " ENABLE_NLTK
ENABLE_NLTK=${ENABLE_NLTK:-false}

read -p "OCR mode (skip/redo/force) [skip]: " OCR_MODE
OCR_MODE=${OCR_MODE:-"skip"}

SECRET_KEY=$(openssl rand -base64 32 | tr -d '\n=+/')

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=9600  # Start after Owncast's range (9500+)
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

# Find available port for Paperless
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Paperless"
fi

log "Using port: Paperless=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="paperless"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/paperless"
DATA_DIR="/opt/winejs/data/paperless"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{consume,data,media,db,redis,export}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/paperless"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

if [ "$DB_TYPE" = "postgresql" ]; then
    cat > "$INSTANCE_DIR/docker-compose.yml" << 'DOCKER_EOF'
services:
  # PostgreSQL Database
  database:
    image: postgres:15
    container_name: winejs-paperless-db
    restart: unless-stopped
    volumes:
      - ${DATA_DIR}/db:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: paperless
      POSTGRES_USER: paperless
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U paperless"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis Broker
  redis:
    image: redis:7-alpine
    container_name: winejs-paperless-redis
    restart: unless-stopped
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Paperless-ngx Webserver
  webserver:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:8000"
    volumes:
      - ${DATA_DIR}/consume:/usr/src/paperless/consume
      - ${DATA_DIR}/data:/usr/src/paperless/data
      - ${DATA_DIR}/media:/usr/src/paperless/media
      - ${DATA_DIR}/export:/usr/src/paperless/export
    environment:
      PAPERLESS_REDIS: redis://redis:6379
      PAPERLESS_DBHOST: database
      PAPERLESS_DBNAME: paperless
      PAPERLESS_DBUSER: paperless
      PAPERLESS_DBPASS: ${DB_PASSWORD}
      PAPERLESS_SECRET_KEY: ${SECRET_KEY}
      PAPERLESS_URL: https://${DOMAIN_NAME}/docs
      PAPERLESS_OCR_LANGUAGE: ${OCR_LANG}
      PAPERLESS_TIME_ZONE: ${TIMEZONE}
      PAPERLESS_OCR_MODE: ${OCR_MODE}
      PAPERLESS_ENABLE_NLTK: ${ENABLE_NLTK}
      PAPERLESS_ADMIN_USER: ${ADMIN_USER}
      PAPERLESS_ADMIN_PASSWORD: ${ADMIN_PASSWORD}
      PAPERLESS_ADMIN_EMAIL: ${ADMIN_EMAIL}
      USERMAP_UID: 1000
      USERMAP_GID: 1000
    depends_on:
      database:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF
else
    # SQLite version
    cat > "$INSTANCE_DIR/docker-compose.yml" << 'DOCKER_EOF'
services:
  # Redis Broker
  redis:
    image: redis:7-alpine
    container_name: winejs-paperless-redis
    restart: unless-stopped
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Paperless-ngx Webserver
  webserver:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:8000"
    volumes:
      - ${DATA_DIR}/consume:/usr/src/paperless/consume
      - ${DATA_DIR}/data:/usr/src/paperless/data
      - ${DATA_DIR}/media:/usr/src/paperless/media
      - ${DATA_DIR}/export:/usr/src/paperless/export
    environment:
      PAPERLESS_REDIS: redis://redis:6379
      PAPERLESS_DBENGINE: sqlite
      PAPERLESS_SECRET_KEY: ${SECRET_KEY}
      PAPERLESS_URL: https://${DOMAIN_NAME}/docs
      PAPERLESS_OCR_LANGUAGE: ${OCR_LANG}
      PAPERLESS_TIME_ZONE: ${TIMEZONE}
      PAPERLESS_OCR_MODE: ${OCR_MODE}
      PAPERLESS_ENABLE_NLTK: ${ENABLE_NLTK}
      PAPERLESS_ADMIN_USER: ${ADMIN_USER}
      PAPERLESS_ADMIN_PASSWORD: ${ADMIN_PASSWORD}
      PAPERLESS_ADMIN_EMAIL: ${ADMIN_EMAIL}
      USERMAP_UID: 1000
      USERMAP_GID: 1000
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF
fi

# ============= START CONTAINER =============
log "🚀 Starting Paperless-ngx containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Paperless-ngx to initialize (this may take 2-3 minutes)..."
sleep 60

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
    "name": "Paperless-ngx Document Management",
    "version": "latest",
    "description": "Document management system that transforms physical documents into a searchable online archive",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/paperless.png",
    "category": "Productivity",
    "features": [
        "📄 Document OCR & Text Recognition",
        "🔍 Full-Text Search",
        "🏷️ Automatic Tagging & Classification",
        "📎 Email & Scanner Integration",
        "📊 Correspondent Management",
        "📅 Document Dating",
        "💾 Multi-Format Support (PDF, Images, Office)",
        "🔐 User & Group Permissions",
        "🌐 Multi-Language OCR",
        "📱 Mobile Responsive",
        "📥 Consumption Folder",
        "🔄 Automatic Matching"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << GUIDE_EOF
# Paperless-ngx Document Management - User Guide

## Access
- **Web Interface**: https://$DOMAIN_NAME/docs/

## Admin Login
- **Username**: $ADMIN_USER
- **Password**: [the password you set]

## Getting Started

### 1. Add Your First Document

**Method 1 - Consumption Folder**:
1. Place PDF/image files in: `$CONSUME_DIR`
2. Paperless automatically detects and processes them
3. Documents appear in the web interface

**Method 2 - Web Upload**:
1. Login to the web interface
2. Click "Add" → "Document"
3. Upload file
4. Set metadata (title, date, correspondent, tags)

**Method 3 - Email**:
1. Configure email consumption in admin
2. Forward documents to your Paperless email address
3. Auto-imported and processed

### 2. Organize Documents

**Correspondents**:
- Create correspondents (banks, utilities, clients)
- Associate documents with them
- Filter by correspondent

**Document Types**:
- Invoice, Receipt, Contract, Letter, etc.
- Custom document types
- Quick filtering

**Tags**:
- Color-coded tags
- Multiple tags per document
- Auto-tagging rules

### 3. Search & Find

**Full-Text Search**:
- Search within document text (OCR)
- Search by filename
- Search by metadata

**Saved Views**:
- Save custom filters
- Quick access to common searches
- Share with other users

**Filters**:
- Date ranges
- Correspondent
- Document type
- Tags
- Custom fields

## Document Processing

### OCR Settings
- Language: $OCR_LANG
- Mode: $OCR_MODE
- NLTK: $ENABLE_NLTK

### Automatic Matching
Paperless automatically:
- Assigns correspondents
- Adds tags
- Sets document types
- Based on content rules

**Create Matching Rules**:
1. Admin → Correspondents/Tags/Document Types
2. Enable "Automatic Matching"
3. Define matching algorithm
4. Test before saving

## Consumption Options

### Consumption Folder
- **Path**: `$CONSUME_DIR`
- **Processing**: 5 minute polling
- **Supported formats**: PDF, PNG, JPG, TIFF, GIF, BMP, TXT, DOCX, ODT, EML, MSG

### Email Consumption
Configure IMAP retrieval:
- Host, port, SSL
- Username, password
- Folder (INBOX, etc.)
- Processing interval

### Scanner Integration
- Scan directly to consumption folder
- Use network scanners (SMB/NFS)
- FTP/SFTP upload scripts

## Advanced Features

### Custom Fields
Create custom fields for:
- Invoice numbers
- Due dates
- Amounts
- Project codes

### Saved Views
- Named filters
- Sorting preferences
- Column visibility
- Share with team

### Bulk Operations
- Bulk edit metadata
- Bulk download
- Bulk delete
- Batch processing

### Export & Backup
- Export documents (original + metadata)
- Export to JSON/CSV
- Documentation backups
- Migration tools

## Integrations

### With WineJS Apps

**ConvertX**:
- Convert non-PDF documents
- Optimize for OCR
- Batch conversions

**Directory Lister**:
- Share scanned documents
- Create document portals
- Collaboration

**ArchiveBox**:
- Archive document snapshots
- Version control
- Long-term preservation

**n8n**:
- Automate document workflows
- Connect to CRM/ERP
- Email notifications

## Mobile Access

- Responsive web design
- Works on phones/tablets
- No native app needed

## Administration

### User Management
- Create user accounts
- Set permissions
- Groups and sharing

### System Settings
- Change OCR language
- Adjust polling intervals
- Configure email
- Security settings

### Maintenance
- **Index rebuild**:
  \`\`\`bash
  docker exec winejs-paperless document_index reindex
  \`\`\`
- **Sanity check**:
  \`\`\`bash
  docker exec winejs-paperless document_sanity_checker
  \`\`\`
- **Manage tasks**:
  Admin → Dashboard → Tasks

## Troubleshooting

**Document not processing?**
- Check consumption folder permissions
- Verify file format
- Check container logs

**OCR not working?**
- Install language pack: \`$OCR_LANG\`
- Check ImageMagick policy
- Verify file quality

**Search slow?**
- Rebuild search index
- Optimize database
- Archive old documents

**Login issues?**
- Reset admin password with:

\`\`\`bash
docker exec -it winejs-paperless python3 manage.py changepassword admin
\`\`\`

## Commands

\`\`\`bash
# View logs
winejs-paperless logs

# Restart services
winejs-paperless restart

# Check status
winejs-paperless status

# Rebuild search index
docker exec winejs-paperless document_index reindex

# Process consumption folder manually
docker exec winejs-paperless document_consumer

# Create backup
docker exec winejs-paperless document_exporter /export

# Open dashboard
winejs-paperless open
\`\`\`

## Best Practices

**Document Naming**:
- Use descriptive filenames
- Include dates (YYYY-MM-DD)
- Avoid special characters

**Tags Strategy**:
- Create tag hierarchy
- Use consistent colors
- Document tag meanings

**Retention**:
- Set up automatic deletion
- Archive old documents
- Export important files

**Security**:
- Regular backups
- User access control
- HTTPS enforcement
- Audit logging

## Support

- **Docs**: https://docs.paperless-ngx.com
- **GitHub**: https://github.com/paperless-ngx/paperless-ngx
- **Matrix**: Join community chat
- **Crowdin**: Help translate

## Sample Workflows

### Invoice Automation
1. Scan invoice to consumption folder
2. Paperless OCRs and extracts data
3. Auto-tags as "Invoice"
4. Sets correspondent (vendor)
5. Adds custom fields (due date, amount)

### Email Archiving
1. Forward important emails
2. Auto-convert to PDF
3. Extract attachments
4. Tag based on subject

### Receipt Tracking
1. Mobile scan receipts
2. Auto-OCR amount and date
3. Tag for expense reports
4. Export to accounting software
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Paperless icon..."

if curl -L "$PAPERLESS_LOGO_URL" -o "$ICON_DIR/paperless.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/paperless.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
  <polyline points="14 2 14 8 20 8"/>
  <line x1="16" y1="13" x2="8" y2="13"/>
  <line x1="16" y1="17" x2="8" y2="17"/>
  <polyline points="10 9 9 9 8 9"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-paperless << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
DATA_DIR="${DATA_DIR}"
ADMIN_USER="${ADMIN_USER}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/paperless && docker compose ps
        ;;
    logs)
        docker logs winejs-paperless --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/paperless && docker compose restart
        echo "Paperless restarted"
        ;;
    consume)
        echo "📁 Consumption directory: $DATA_DIR/consume"
        echo ""
        echo "Place documents here to auto-import:"
        ls -la "$DATA_DIR/consume" 2>/dev/null || echo "  (empty)"
        ;;
    scan)
        echo "🔍 Running manual consumption scan..."
        docker exec winejs-paperless document_consumer
        ;;
    reindex)
        echo "🔄 Rebuilding search index..."
        docker exec winejs-paperless document_index reindex
        ;;
    export)
        echo "📦 Exporting all documents..."
        docker exec winejs-paperless document_exporter /export
        echo "Export saved to: $DATA_DIR/export"
        ;;
    admin-pass)
        echo "🔐 Reset admin password:"
        docker exec -it winejs-paperless python3 manage.py changepassword "\${1:-$ADMIN_USER}"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/docs/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/docs/"
        fi
        ;;
    *)
        echo "Paperless-ngx Document Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-paperless open           # Open dashboard"
        echo "  winejs-paperless status         # Check status"
        echo "  winejs-paperless logs           # View logs"
        echo "  winejs-paperless restart        # Restart"
        echo "  winejs-paperless consume        # Show consumption folder"
        echo "  winejs-paperless scan           # Manual consumption scan"
        echo "  winejs-paperless reindex        # Rebuild search index"
        echo "  winejs-paperless export         # Export all documents"
        echo "  winejs-paperless admin-pass     # Reset admin password"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/docs/"
        echo ""
        echo "Admin Login: $ADMIN_USER / (password you set)"
        echo ""
        echo "Database: $DB_TYPE"
        echo "OCR Language: $OCR_LANG"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/paperless/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-paperless

# ============= CREATE SAMPLE README IN CONSUME FOLDER =============
log "📄 Creating sample README in consumption folder..."

cat > "$CONSUME_DIR/README.md" << 'EOF'
# Paperless Consumption Folder

Place any PDF, image, or document files here to be automatically imported into Paperless-ngx.

Supported formats:
- PDF
- PNG, JPG, JPEG, TIFF, GIF, BMP
- TXT
- DOCX, ODT
- EML, MSG

Files are processed every 5 minutes.

After processing, files are moved to the media directory and no longer appear here.
EOF

# ============= RESTART TRANSLATOR =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_paperless.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Paperless-ngx..."

cd /opt/winejs/kasmvnc-instances/paperless
docker compose down -v 2>/dev/null

# Ask about removing documents
read -p "Remove all documents and data? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /opt/winejs/apps/paperless
    rm -rf /opt/winejs/kasmvnc-instances/paperless
    rm -rf /opt/winejs/data/paperless
    log "✅ All documents removed"
else
    rm -rf /opt/winejs/apps/paperless
    rm -rf /opt/winejs/kasmvnc-instances/paperless
    rm -rf /opt/winejs/data/paperless/redis
    rm -rf /opt/winejs/data/paperless/db
fi

rm -f /usr/local/bin/winejs-paperless

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Paperless Document Management/,/location \/docs/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/docs {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Paperless-ngx uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_paperless.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           PAPERLESS-NGX INSTALLED ON WINEJS!                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Paperless-ngx Document Management installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/docs/"
echo ""
info "🔐 Admin Login:"
info "   • Username: $ADMIN_USER"
info "   • Password: [the password you set]"
info "   • Email: $ADMIN_EMAIL"
echo ""
info "📄 Document Processing:"
info "   • OCR Language: $OCR_LANG"
info "   • OCR Mode: $OCR_MODE"
info "   • NLTK: $ENABLE_NLTK"
info "   • Database: $DB_TYPE"
echo ""
info "📁 Directories:"
info "   • Consumption: $CONSUME_DIR"
info "   • Data: ${DATA_DIR}/data"
info "   • Media: ${DATA_DIR}/media"
info "   • Export: ${DATA_DIR}/export"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-paperless open        # Open dashboard"
info "   • winejs-paperless status      # Check status"
info "   • winejs-paperless logs        # View logs"
info "   • winejs-paperless consume     # Show consumption folder"
info "   • winejs-paperless scan        # Manual consumption scan"
info "   • winejs-paperless reindex     # Rebuild search index"
info "   • winejs-paperless export      # Export all documents"
info "   • winejs-paperless admin-pass  # Reset admin password"
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/paperless/user-guide.md"
echo ""
info "💡 Getting Started:"
info "   1. Login to the web interface"
info "   2. Place a PDF in: $CONSUME_DIR"
info "   3. Wait 5 minutes or run 'winejs-paperless scan'"
info "   4. Document appears in the dashboard"
info "   5. Add tags, correspondents, and document types"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_paperless.sh"
echo ""
success "✨ Paperless-ngx is ready! Start managing your documents at https://$DOMAIN_NAME/docs/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Paperless-ngx Does:

# Paperless-ngx is a document management system that transforms physical documents into a searchable online archive:
# Key Features:
#     Document OCR - Converts scanned documents to searchable text
#     Full-Text Search - Find any document by its content
#     Automatic Tagging - Auto-classify documents based on content
#     Email Integration - Import documents via email
#     Consumption Folder - Drop documents to auto-import
#     Correspondent Management - Track document senders
#     Document Types - Invoices, receipts, contracts, etc.
#     Custom Fields - Add metadata like invoice numbers, due dates
#     Multi-Language OCR - Supports many languages
#     User Permissions - Share with specific users/groups

# Supported Formats:
#     PDF - Scanned or digital
#     Images - PNG, JPG, TIFF, GIF, BMP
#     Office - DOCX, ODT
#     Email - EML, MSG
#     Text - TXT

# Perfect For:
#     Home Organization - Bills, receipts, warranties
#     Small Business - Invoices, contracts, HR documents
#     Accounting - Keep tax documents searchable
#     Legal - Case files, contracts, correspondence
#     Personal - Medical records, insurance documents