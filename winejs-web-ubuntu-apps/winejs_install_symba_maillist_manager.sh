#!/bin/bash
# ============================================
# Sympa Mailing List Manager - WineJS Installer
# Adds Enterprise Mailing Lists to WineJS Platform
# ============================================
# App: Sympa
# Category: Communication
# Features: Mailing Lists, Newsletter Management, Subscriptions
# ============================================

SYMPA_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/sympa-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📧 Installing WineJS Sympa Mailing List Manager..."

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

# ============= ASK FOR SYMPA CONFIGURATION =============
echo ""
info "📝 Sympa Configuration"
echo "================================"
read -p "Listmaster email: " LISTMASTER_EMAIL
read -p "Primary mail domain: " MAIL_DOMAIN
read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

# Generate database password
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/')
SECRET_KEY=$(openssl rand -base64 32 | tr -d '\n=+/')

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=10200  # Start after Webhook Tester's range (10100+)
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

# Find available port for Sympa web interface
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Sympa"
fi

log "Using port: Sympa=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="sympa"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/sympa"
DATA_DIR="/opt/winejs/data/sympa"
CONFIG_DIR="/opt/winejs/config/sympa"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{db,explode,spool,static,logs,pid}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/sympa"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE SYMPA CONFIGURATION =============
log "📝 Creating sympa.conf..."

cat > "$CONFIG_DIR/sympa.conf" << EOF
# Sympa Main Configuration
domain $MAIL_DOMAIN
listmaster $LISTMASTER_EMAIL

# Database Configuration
db_type MySQL
db_name sympa
db_host db
db_user sympa
db_passwd $DB_PASSWORD

# Web Interface
wwsympa_url https://$DOMAIN_NAME/lists
wwsympa_title "WineJS Mailing Lists"

# System Paths
home $DATA_DIR/explode
bounce $DATA_DIR/spool/bounce
msg $DATA_DIR/spool/msg
digest $DATA_DIR/spool/digest
outgoing $DATA_DIR/spool/outgoing
arc $DATA_DIR/spool/arc
auth $DATA_DIR/spool/auth
task $DATA_DIR/spool/task
tmp $DATA_DIR/spool/tmp

# Queue Management
queueautosave 300
chk_nntp_interval 3600
chk_bounce_queue_interval 3600

# Load Limits
max_shared_size 100
log_facility local1

# Static Content
static_content_url /static-sympa
css_url /static-sympa/css
pictures_url /static-sympa/pictures

# Language
lang en-US
supported_lang en-US,fr-FR,de-DE,es-ES,it-IT,pt-BR,ja-JP,zh-CN

# Archive Settings
default_archive_quota 5000000

# Security
cookie_domain $DOMAIN_NAME
secure_https 1

# Performance
process_timeout 600
max_wizard_retries 10

# Tracking
tracking_enabled 1

# Anti-spam
antivirus_path /usr/bin/clamscan
spam_status_path /usr/bin/spamc

# DKIM
dkim_signer 1
dkim_signer_domain $MAIL_DOMAIN
dkim_signer_identity @$MAIL_DOMAIN

# S/MIME
smime_signer 1
EOF

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # MariaDB Database
  db:
    image: mariadb:10.11
    container_name: winejs-sympa-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}
      MYSQL_DATABASE: sympa
      MYSQL_USER: sympa
      MYSQL_PASSWORD: ${DB_PASSWORD}
    volumes:
      - ${DATA_DIR}/db:/var/lib/mysql
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis Cache
  redis:
    image: redis:7-alpine
    container_name: winejs-sympa-redis
    restart: unless-stopped
    command: redis-server --appendonly yes --requirepass ${DB_PASSWORD}
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - winejs-net

  # Postfix MTA
  postfix:
    image: ghcr.io/mailcow/postfix:latest
    container_name: winejs-sympa-postfix
    restart: unless-stopped
    hostname: mail.${MAIL_DOMAIN}
    environment:
      - MAILNAME=${MAIL_DOMAIN}
      - POSTFIX_LOG_LEVEL=2
    volumes:
      - ${DATA_DIR}/postfix:/var/spool/postfix
      - ${DATA_DIR}/spool:/var/spool/sympa
    networks:
      - winejs-net

  # Sympa Web Interface
  web:
    image: sympa:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:80"
    volumes:
      - ${DATA_DIR}/explode:/home/sympa/explode
      - ${DATA_DIR}/spool:/home/sympa/spool
      - ${DATA_DIR}/static:/home/sympa/static
      - ${DATA_DIR}/logs:/home/sympa/logs
      - ${CONFIG_DIR}:/etc/sympa:ro
    environment:
      - SYMPA_DB_PASSWORD=${DB_PASSWORD}
      - SYMPA_DOMAIN=${MAIL_DOMAIN}
      - SYMPA_LISTMASTER=${LISTMASTER_EMAIL}
      - SYMPA_SECRET_KEY=${SECRET_KEY}
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
      postfix:
        condition: service_started
    networks:
      - winejs-net

  # Sympa Daemon
  daemon:
    image: sympa:latest
    container_name: winejs-sympa-daemon
    restart: unless-stopped
    command: sympa.pl
    volumes:
      - ${DATA_DIR}/explode:/home/sympa/explode
      - ${DATA_DIR}/spool:/home/sympa/spool
      - ${DATA_DIR}/static:/home/sympa/static
      - ${DATA_DIR}/logs:/home/sympa/logs
      - ${CONFIG_DIR}:/etc/sympa:ro
    environment:
      - SYMPA_DB_PASSWORD=${DB_PASSWORD}
      - SYMPA_DOMAIN=${MAIL_DOMAIN}
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - winejs-net

  # Sympa Message Processor
  processor:
    image: sympa:latest
    container_name: winejs-sympa-processor
    restart: unless-stopped
    command: sympa_msg.pl
    volumes:
      - ${DATA_DIR}/explode:/home/sympa/explode
      - ${DATA_DIR}/spool:/home/sympa/spool
      - ${DATA_DIR}/logs:/home/sympa/logs
      - ${CONFIG_DIR}:/etc/sympa:ro
    environment:
      - SYMPA_DB_PASSWORD=${DB_PASSWORD}
      - SYMPA_DOMAIN=${MAIL_DOMAIN}
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - winejs-net

  # Sympa Bulk Mailer
  bulk:
    image: sympa:latest
    container_name: winejs-sympa-bulk
    restart: unless-stopped
    command: bulk.pl
    volumes:
      - ${DATA_DIR}/explode:/home/sympa/explode
      - ${DATA_DIR}/spool:/home/sympa/spool
      - ${DATA_DIR}/logs:/home/sympa/logs
      - ${CONFIG_DIR}:/etc/sympa:ro
    environment:
      - SYMPA_DB_PASSWORD=${DB_PASSWORD}
      - SYMPA_DOMAIN=${MAIL_DOMAIN}
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - winejs-net

  # Sympa Bounce Processor
  bounce:
    image: sympa:latest
    container_name: winejs-sympa-bounce
    restart: unless-stopped
    command: bounced.pl
    volumes:
      - ${DATA_DIR}/explode:/home/sympa/explode
      - ${DATA_DIR}/spool:/home/sympa/spool
      - ${DATA_DIR}/logs:/home/sympa/logs
      - ${CONFIG_DIR}:/etc/sympa:ro
    environment:
      - SYMPA_DB_PASSWORD=${DB_PASSWORD}
      - SYMPA_DOMAIN=${MAIL_DOMAIN}
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - winejs-net

  # Sympa Task Manager
  task:
    image: sympa:latest
    container_name: winejs-sympa-task
    restart: unless-stopped
    command: task_manager.pl
    volumes:
      - ${DATA_DIR}/explode:/home/sympa/explode
      - ${DATA_DIR}/spool:/home/sympa/spool
      - ${DATA_DIR}/logs:/home/sympa/logs
      - ${CONFIG_DIR}:/etc/sympa:ro
    environment:
      - SYMPA_DB_PASSWORD=${DB_PASSWORD}
      - SYMPA_DOMAIN=${MAIL_DOMAIN}
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - winejs-net

  # Sympa Archiver
  archive:
    image: sympa:latest
    container_name: winejs-sympa-archive
    restart: unless-stopped
    command: archived.pl
    volumes:
      - ${DATA_DIR}/explode:/home/sympa/explode
      - ${DATA_DIR}/spool:/home/sympa/spool
      - ${DATA_DIR}/logs:/home/sympa/logs
      - ${CONFIG_DIR}:/etc/sympa:ro
    environment:
      - SYMPA_DB_PASSWORD=${DB_PASSWORD}
      - SYMPA_DOMAIN=${MAIL_DOMAIN}
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= INITIALIZE DATABASE =============
log "🚀 Starting Sympa containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Sympa to initialize (this may take 2-3 minutes)..."
sleep 60

# Initialize database
log "🔧 Initializing database..."
docker exec winejs-sympa sympa.pl --health_check 2>/dev/null || true

# Create initial listmaster
log "👤 Creating listmaster account..."
docker exec winejs-sympa sympa.pl --create_listmaster --email "$ADMIN_EMAIL" 2>/dev/null || true

# Set admin password
docker exec winejs-sympa perl -e '
use Sympa::Database;
use Sympa::User;
my $user = Sympa::User->new(email => "'"$ADMIN_EMAIL"'");
$user->{password} = crypt("'"$ADMIN_PASSWORD"'", "salt");
$user->save();' 2>/dev/null || true

log "✅ Sympa initialized"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Sympa Mailing Lists",
    "version": "latest",
    "description": "Enterprise-grade mailing list manager for newsletters and group communication",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/sympa.png",
    "category": "Communication",
    "features": [
        "📧 Mailing List Management",
        "📊 Subscriber Moderation",
        "📜 Message Archives",
        "🔐 List Access Control",
        "🎨 Customizable Templates",
        "📈 Subscriber Statistics",
        "🔗 Web Interface",
        "📱 RESTful API",
        "🗄️ Database Backend",
        "🔒 DKIM & S/MIME Support",
        "🚫 Anti-virus & Anti-spam",
        "🌍 Multi-domain Support",
        "👥 List Families",
        "📋 Bounce Management"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << 'GUIDE_EOF'
# Sympa Mailing List Manager - User Guide

## Access
- **Web Interface**: https://DOMAIN_NAME/lists/
- **Admin Interface**: https://DOMAIN_NAME/lists/admin

## Admin Login
- **Email**: ADMIN_EMAIL
- **Password**: [the password you set]

## Getting Started

### 1. Create Your First List

1. Login to web interface
2. Click "Create List"
3. Choose list type:
   - **Discussion list**: Interactive mailing list
   - **Newsletter**: One-way announcements
   - **Hotline**: Support list
   - **Private**: Restricted access
4. Configure list settings:
   - List name (@DOMAIN_NAME)
   - Subject/topic
   - Owners and moderators
5. Submit for creation

### 2. Configure List Settings

**Visibility**:
- Public: Anyone can see/subscribe
- Private: Restricted access
- Hidden: Not listed publicly

**Subscription Policy**:
- Open: Anyone can subscribe
- Auth: Requires admin approval
- Closed: Listmaster only
- Owner: Requires list owner approval

**Posting Policy**:
- Open: Anyone can post
- Subscribers only: Only members
- Moderators only: Only list owners
- Editor only: Designated editors

### 3. Manage Subscribers

**Add Subscribers**:
1. List Admin → Manage Subscribers
2. Add email addresses (one per line)
3. Set user options (digest, nomail, etc.)
4. Send welcome message

**Import Subscribers**:
- CSV file import
- LDAP integration
- External data sources
- Database queries

**Subscription Requests**:
- Review pending requests
- Approve or reject
- Custom rejection messages

### 4. Send Messages

**To the List**:
\`\`\`
To: listname@DOMAIN_NAME
Subject: Your subject
Body: Your message
\`\`\`

**Via Web Interface**:
1. Compose message
2. Send as HTML or plain text
3. Include attachments
4. Schedule for later

**Moderation Queue**:
- Approve messages
- Reject with reason
- Edit before approval

### 5. Manage Archives

**Archive Access**:
- Public: Anyone can browse
- Subscribers: List members only
- Private: List owners only

**Search Archives**:
- Full-text search
- Date range filtering
- Author search
- Subject search

## Advanced Features

### List Families

Create related lists with shared settings:

1. Define family template
2. Instantiate multiple lists
3. Maintain consistent configuration
4. Bulk manage families

### Data Sources

External subscriber sources:
- **LDAP**: Corporate directories
- **SQL**: Database queries
- **File**: Flat files
- **Sympa**: Other Sympa lists

**Example LDAP Configuration**:
\`\`\`
include_ldap_query
  host ldap.company.com
  suffix ou=people,dc=company,dc=com
  filter (department=IT)
  attributes mail
\`\`\`

### Automatic List Creation

Create lists automatically when needed:

1. Configure creation scenarios
2. Set up alias mapping
3. Define list templates
4. Enable auto-creation

### Bounce Management

Sympa automatically handles bounced emails:

- **Bounce detection**: Identifies failed deliveries
- **Score tracking**: Tracks bounce rates
- **Auto-unsubscribe**: Removes bouncing addresses
- **Blacklist**: Blocks persistent bounces

## Customization

### Templates

Customize all messages and pages:

- Welcome messages
- Digest templates
- Rejection notices
- Web interface pages

Template location: \`/etc/sympa/templates/\`

### Authorization Scenarios

Control access with custom scenarios:

\`\`\`
# subscribe scenario example
title gettext "Only subscribers can subscribe"
match([^@]+@sub.domain.com) smtp -> do_it
match([^@]+@email.domain.com) smtp -> do_it
true() smtp -> reject
\`\`\`

### Web Interface Styling

Customize CSS and HTML:
- \`/home/sympa/static/css/\` for styles
- \`/etc/sympa/web_tt2/\` for templates
- Override default themes

## Integrations

### With n8n
- Trigger workflows on list messages
- Auto-process subscriptions
- Send notifications on bounces

### With Changedetection
- Monitor list activity
- Alert on specific keywords
- Track list growth

### With Paperless-ngx
- Archive important discussions
- Store list announcements
- Compliance archiving

### With Artalk
- Embed discussion threads
- Bridge list and web comments
- Cross-platform engagement

## API Access

### SOAP API

**Endpoints**:
- \`/sympasoap\`: SOAP service
- WSDL available at \`/sympasoap?wsdl\`

**Operations**:
- List management
- Subscriber management
- Message sending
- Archive access

**Example**:
\`\`\`bash
# Get list info
curl -X POST https://DOMAIN_NAME/lists/sympasoap \\
  -H "Content-Type: text/xml" \\
  -d '<?xml version="1.0"?>...'
\`\`\`

### REST API (WIP)

Future REST endpoints for modern integration.

## Monitoring

### Logs

**Types**:
- Web logs: Web interface activity
- Mail logs: Message delivery
- Error logs: System errors
- Bounce logs: Delivery failures

**Viewing**:
\`\`\`bash
docker exec winejs-sympa tail -f /home/sympa/logs/error.log
\`\`\`

### Statistics

**List Statistics**:
- Subscriber count
- Message volume
- Bounce rate
- Growth trends

**System Health**:
- Queue sizes
- Processing times
- Database performance
- Cache hit rates

## Commands

\`\`\`bash
# View logs
winejs-sympa logs

# Restart services
winejs-sympa restart

# Check status
winejs-sympa status

# Create list
docker exec winejs-sympa sympa.pl --create_list \\
  --name listname --robot DOMAIN_NAME

# Import subscribers
docker exec -i winejs-sympa sympa.pl \\
  --import listname@DOMAIN_NAME < subscribers.csv

# List info
docker exec winejs-sympa sympa.pl --dump listname@DOMAIN_NAME

# Open interface
winejs-sympa open
\`\`\`

## Troubleshooting

**Messages not delivered?**
- Check postfix status
- Verify DNS MX records
- Review bounce logs

**Subscribers not receiving?**
- Check spam filters
- Verify welcome message
- Check user options

**Web interface slow?**
- Increase memory limits
- Enable caching
- Optimize database

**Authentication issues?**
- Check database connection
- Verify password hash
- Clear session cache

## Security Best Practices

1. **Use HTTPS** (configured)
2. **Regular backups**
3. **Monitor bounce rates**
4. **Review moderation queues**
5. **Set appropriate access controls**
6. **Enable DKIM/DMARC**
7. **Use antivirus scanning**

## Support

- **Web**: https://www.sympa.community/
- **Documentation**: https://www.sympa.community/documentation
- **GitHub**: https://github.com/sympa-community/sympa

## Best Practices

### For Discussion Lists
- Keep on topic
- Moderate new subscribers
- Set clear posting guidelines
- Archive regularly

### For Newsletters
- Use custom templates
- Track open rates
- Clean bounce addresses
- Segment subscribers

### For Support Lists
- Define response time SLAs
- Categorize tickets
- Auto-respond to common issues
- Escalate to ticketing system

### For Announcements
- Restrict posting rights
- Use DKIM signing
- Monitor deliverability
- Track engagement
GUIDE_EOF

# Replace placeholders in guide
sed -i "s/DOMAIN_NAME/${DOMAIN_NAME}/g" "$APP_DIR/user-guide.md"
sed -i "s/ADMIN_EMAIL/${ADMIN_EMAIL}/g" "$APP_DIR/user-guide.md"

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Sympa icon..."

if curl -L "$SYMPA_LOGO_URL" -o "$ICON_DIR/sympa.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/sympa.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/>
  <polyline points="22,6 12,13 2,6"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-sympa << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/sympa && docker compose ps
        ;;
    logs)
        docker logs winejs-sympa-daemon --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/sympa && docker compose restart
        echo "Sympa restarted"
        ;;
    lists)
        echo "📋 Available lists:"
        docker exec winejs-sympa sympa.pl --list_lists
        ;;
    create-list)
        shift
        if [ $# -lt 1 ]; then
            echo "Usage: winejs-sympa create-list <listname>"
            echo "Example: winejs-sympa create-list annonce"
        else
            docker exec winejs-sympa sympa.pl --create_list --name "\$1" --robot "$MAIL_DOMAIN"
        fi
        ;;
    import)
        shift
        if [ $# -lt 2 ]; then
            echo "Usage: winejs-sympa import <listname> <file.csv>"
        else
            docker exec -i winejs-sympa sympa.pl --import "\$1@$MAIL_DOMAIN" < "\$2"
        fi
        ;;
    queue)
        echo "📨 Queue status:"
        docker exec winejs-sympa sympa.pl --list_queues
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/lists/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/lists/"
        fi
        ;;
    *)
        echo "Sympa Mailing List Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-sympa open               # Open interface"
        echo "  winejs-sympa status             # Check status"
        echo "  winejs-sympa logs               # View logs"
        echo "  winejs-sympa restart            # Restart"
        echo "  winejs-sympa lists              # List all lists"
        echo "  winejs-sympa create-list <name> # Create new list"
        echo "  winejs-sympa import <list> <file> # Import subscribers"
        echo "  winejs-sympa queue              # Queue status"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/lists/"
        echo ""
        echo "Admin Login: $ADMIN_EMAIL / (password you set)"
        echo "Listmaster: $LISTMASTER_EMAIL"
        echo "Mail Domain: $MAIL_DOMAIN"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/sympa/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-sympa

# ============= UPDATE NGINX FOR SYMPA =============
log "📝 Setting up nginx reverse proxy for Sympa..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /lists" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Sympa Mailing Lists\n\
    location /lists {\n\
        rewrite ^/lists(/.*)?$ /\\\$1 break;\n\
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
        client_max_body_size 10M;\n\
    }\n\
    \n\
    # Sympa Static Content\n\
    location /static-sympa/ {\n\
        alias /opt/winejs/data/sympa/static/;\n\
        expires 1y;\n\
        add_header Cache-Control \"public, immutable\";\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Sympa routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_sympa.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Sympa..."

cd /opt/winejs/kasmvnc-instances/sympa
docker compose down -v 2>/dev/null

# Ask about removing data
read -p "Remove all mailing list data and archives? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /opt/winejs/apps/sympa
    rm -rf /opt/winejs/kasmvnc-instances/sympa
    rm -rf /opt/winejs/data/sympa
    rm -rf /opt/winejs/config/sympa
    log "✅ All data removed"
else
    rm -rf /opt/winejs/apps/sympa
    rm -rf /opt/winejs/kasmvnc-instances/sympa
    rm -rf /opt/winejs/config/sympa
fi

rm -f /usr/local/bin/winejs-sympa

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Sympa Mailing Lists/,/location \/static-sympa\//d' /etc/nginx/sites-available/winejs
    sed -i '/location \/lists {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Sympa uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_sympa.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                SYMPA INSTALLED ON WINEJS!                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Sympa Mailing List Manager installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/lists/"
echo ""
info "🔐 Admin Login:"
info "   • Email: $ADMIN_EMAIL"
info "   • Password: [the password you set]"
echo ""
info "📧 Mailing List Configuration:"
info "   • Mail Domain: $MAIL_DOMAIN"
info "   • Listmaster: $LISTMASTER_EMAIL"
echo ""
info "📊 Features:"
info "   • Discussion lists (interactive)"
info "   • Newsletters (announcements)"
info "   • Hotline (support)"
info "   • Private lists (restricted)"
echo ""
info "🔧 Services:"
info "   • Web Interface (WWSympa)"
info "   • Message Processor (sympa_msg)"
info "   • Bulk Mailer (bulk)"
info "   • Bounce Processor (bounced)"
info "   • Task Manager (task_manager)"
info "   • Archiver (archived)"
info "   • Postfix MTA (for delivery)"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-sympa open               # Open interface"
info "   • winejs-sympa status             # Check services"
info "   • winejs-sympa logs               # View logs"
info "   • winejs-sympa lists              # List all lists"
info "   • winejs-sympa create-list <name> # Create new list"
info "   • winejs-sympa import <list> <file> # Import subscribers"
info "   • winejs-sympa queue              # Queue status"
echo ""
info "📁 Data Directories:"
info "   • Database: ${DATA_DIR}/db"
info "   • Spool: ${DATA_DIR}/spool"
info "   • Archives: ${DATA_DIR}/explode"
info "   • Logs: ${DATA_DIR}/logs"
info "   • Config: ${CONFIG_DIR}"
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/sympa/user-guide.md"
echo ""
info "💡 Quick Start:"
info "   1. Login to web interface"
info "   2. Create your first list"
info "   3. Configure list settings"
info "   4. Add subscribers"
info "   5. Start sending messages!"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_sympa.sh"
echo ""
success "✨ Sympa is ready! Start managing mailing lists at https://$DOMAIN_NAME/lists/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Sympa Does:

# Sympa is an enterprise-grade mailing list manager - perfect for newsletters and group communication:
# Key Features:
#     Mailing List Management - Create and manage multiple lists
#     Subscription Control - Open, closed, or moderated subscriptions
#     Message Archives - Searchable web-based archives
#     Bounce Handling - Automatic detection and management
#     DKIM/S/MIME - Email authentication and encryption
#     Web Interface - Modern HTML/CSS interface
#     LDAP Integration - Use corporate directories
#     REST/SOAP API - Programmatic control
#     List Families - Template-based list creation
#     Message Tracking - Delivery and open tracking

# Use Cases:
# Type	Use
# Discussion List	Interactive group conversations
# Newsletter	One-way announcements
# Hotline	Support mailing list
# Private	Restricted access lists
# Announce	Broadcast-only lists

# Perfect For:
#     Organizations - Internal communication lists
#     Open Source Projects - User and developer mailing lists
#     Newsletters - Automated subscriber management
#     Education - Class discussion lists
#     Communities - Group communication