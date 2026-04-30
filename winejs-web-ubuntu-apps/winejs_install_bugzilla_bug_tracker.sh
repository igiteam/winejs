#!/bin/bash
# ============================================
# Bugzilla Bug Tracker - WineJS Installer
# Adds Bug Tracking System to WineJS Platform
# ============================================
# App: Bugzilla
# Category: Development
# Features: Bug Tracking, Issue Management, Workflow
# ============================================

BUGZILLA_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/bugzilla-bug-tracker-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🐛 Installing WineJS Bugzilla Bug Tracker..."

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

# ============= ASK FOR BUGZILLA CONFIGURATION =============
echo ""
info "📝 Bugzilla Configuration"
echo "================================"
read -p "Admin email address: " ADMIN_EMAIL
read -p "Admin real name: " ADMIN_NAME
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

read -p "Bugzilla URL base (https://$DOMAIN_NAME/bugzilla): " URLBASE
URLBASE=${URLBASE:-"https://$DOMAIN_NAME/bugzilla"}

read -p "SMTP server for email [smtp.gmail.com:465]: " SMTP_SERVER
SMTP_SERVER=${SMTP_SERVER:-"smtp.gmail.com:465"}

read -p "Email from address: " SMTP_FROM
read -p "SMTP username: " SMTP_USER
read -s -p "SMTP password: " SMTP_PASSWORD
echo ""

read -p "Enable SSL redirect? (true/false) [true]: " SSL_REDIRECT
SSL_REDIRECT=${SSL_REDIRECT:-true}

# Generate database password
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/' | head -c 24)

# Bugzilla version
BUGZILLA_VERSION="5.2"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="bugzilla"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/bugzilla"
CONFIG_DIR="/opt/winejs/config/bugzilla"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{mysql,webapps,logs}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/bugzilla"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE BUGZILLA DOCKERFILE =============
log "📝 Creating Bugzilla Dockerfile..."

cat > "$INSTANCE_DIR/Dockerfile" << 'DOCKERFILE_EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install prerequisites
RUN apt-get update && apt-get install -y \
    apache2 \
    build-essential \
    mariadb-client \
    libcgi-pm-perl \
    libdigest-sha-perl \
    libtimedate-perl \
    libdatetime-perl \
    libdatetime-timezone-perl \
    libdbi-perl \
    libdbix-connector-perl \
    libtemplate-perl \
    libemail-address-perl \
    libemail-sender-perl \
    libemail-mime-perl \
    liburi-perl \
    liblist-moreutils-perl \
    libmath-random-isaac-perl \
    libjson-xs-perl \
    libgd-perl \
    libchart-perl \
    libtemplate-plugin-gd-perl \
    libgd-text-perl \
    libgd-graph-perl \
    libmime-tools-perl \
    libwww-perl \
    libxml-twig-perl \
    libnet-ldap-perl \
    libauthen-sasl-perl \
    libnet-smtp-ssl-perl \
    libauthen-radius-perl \
    libsoap-lite-perl \
    libxmlrpc-lite-perl \
    libjson-rpc-perl \
    libtest-taint-perl \
    libhtml-parser-perl \
    libhtml-scrubber-perl \
    libencode-perl \
    libencode-detect-perl \
    libemail-reply-perl \
    libhtml-formattext-withlinks-perl \
    libtheschwartz-perl \
    libdaemon-generic-perl \
    libapache2-mod-perl2 \
    libfile-mimeinfo-perl \
    libio-stringy-perl \
    libcache-memcached-perl \
    libfile-copy-recursive-perl \
    libfile-which-perl \
    libmariadb-dev \
    perlmagick \
    lynx \
    graphviz \
    python3-sphinx \
    rst2pdf \
    git \
    nano \
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install additional Perl modules
RUN cpan -i Template Email::Sender Email::Address::XS DBD::MariaDB || true

# Clone Bugzilla
RUN mkdir -p /var/www/webapps && \
    cd /var/www/webapps && \
    git clone --branch release-5.2-stable https://github.com/bugzilla/bugzilla bugzilla

# Configure Apache
RUN a2enmod cgid headers expires rewrite && \
    a2enmod cgi

COPY bugzilla.conf /etc/apache2/sites-available/

RUN a2ensite bugzilla && \
    a2dissite 000-default && \
    service apache2 restart || true

# Fix permissions
RUN chown -R www-data:www-data /var/www/webapps/bugzilla && \
    chmod -R 755 /var/www/webapps/bugzilla

EXPOSE 80

CMD ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]
DOCKERFILE_EOF

# ============= CREATE APACHE CONFIGURATION =============
log "📝 Creating Apache configuration..."

cat > "$INSTANCE_DIR/bugzilla.conf" << EOF
Alias /bugzilla /var/www/webapps/bugzilla
<Directory /var/www/webapps/bugzilla>
  AddHandler cgi-script .cgi
  Options +ExecCGI
  DirectoryIndex index.cgi index.html
  AllowOverride All
  Require all granted
</Directory>
EOF

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # MariaDB Database
  mariadb:
    image: mariadb:10.11
    container_name: winejs-bugzilla-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}
      MYSQL_DATABASE: bugs
      MYSQL_USER: bugs
      MYSQL_PASSWORD: ${DB_PASSWORD}
    volumes:
      - ${DATA_DIR}/mysql:/var/lib/mysql
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Bugzilla Application
  winejs-bugzilla:
    build: .
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:80"
    volumes:
      - ${DATA_DIR}/webapps:/var/www/webapps
      - ${DATA_DIR}/logs:/var/log/apache2
    depends_on:
      mariadb:
        condition: service_healthy
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= BUILD AND START CONTAINERS =============
log "🏗️ Building Bugzilla Docker image (this may take a few minutes)..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose build --no-cache

log "🚀 Starting Bugzilla containers..."
docker-compose up -d

log "⏳ Waiting for Bugzilla to initialize..."
sleep 45

# ============= CONFIGURE BUGZILLA =============
log "🔧 Configuring Bugzilla..."

# Run checksetup.pl first time
docker exec winejs-bugzilla bash -c "cd /var/www/webapps/bugzilla && ./checksetup.pl" 2>/dev/null || true

# Create localconfig with settings
docker exec winejs-bugzilla bash -c "cat > /var/www/webapps/bugzilla/localconfig << EOF
# Bugzilla Local Configuration
\$webservergroup = 'www-data';
\$db_driver = 'mariadb';
\$db_host = 'mariadb';
\$db_name = 'bugs';
\$db_user = 'bugs';
\$db_pass = '${DB_PASSWORD}';
\$db_port = 3306;
EOF" 2>/dev/null || true

# Fix permissions
docker exec winejs-bugzilla chown -R www-data:www-data /var/www/webapps/bugzilla
docker exec winejs-bugzilla chmod -R 755 /var/www/webapps/bugzilla

# Run checksetup.pl second time (creates admin user)
docker exec winejs-bugzilla bash -c "cd /var/www/webapps/bugzilla && echo '${ADMIN_EMAIL}
${ADMIN_NAME}
${ADMIN_PASSWORD}
${ADMIN_PASSWORD}' | ./checksetup.pl" 2>/dev/null || true

# Configure Bugzilla parameters
docker exec winejs-bugzilla bash -c "cd /var/www/webapps/bugzilla && ./testserver.pl http://localhost/bugzilla" 2>/dev/null || true

# Set parameters via Perl script
docker exec winejs-bugzilla bash -c "cd /var/www/webapps/bugzilla && perl -e '
use Bugzilla;
Bugzilla->init_page();
my \$params = Bugzilla->params();
\$params->{\"urlbase\"} = \"${URLBASE}\";
\$params->{\"ssl_redirect\"} = \"${SSL_REDIRECT}\";
\$params->{\"mail_delivery_method\"} = \"SMTP\";
\$params->{\"mailfrom\"} = \"${SMTP_FROM}\";
\$params->{\"smtpserver\"} = \"${SMTP_SERVER}\";
\$params->{\"smtp_username\"} = \"${SMTP_USER}\";
\$params->{\"smtp_password\"} = \"${SMTP_PASSWORD}\";
\$params->{\"smtp_ssl\"} = \"On\";
\$params->write();
print \"Parameters updated\\n\";
'" 2>/dev/null || true

# Restart Apache to apply changes
docker exec winejs-bugzilla service apache2 restart

log "✅ Bugzilla configured"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Bugzilla Bug Tracker",
    "version": "${BUGZILLA_VERSION}",
    "description": "Mature, web-based bug tracking system used by Mozilla, GNOME, and thousands of organizations",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/bugzilla.png",
    "category": "Development",
    "features": [
        "🐛 Bug & Issue Tracking",
        "📊 Advanced Search & Filtering",
        "📧 Email Notifications",
        "🔐 Granular Permissions",
        "🏷️ Custom Fields & Workflows",
        "📈 Reports & Charts",
        "🔗 Dependency Tracking",
        "📎 File Attachments",
        "💬 Comment History",
        "🌍 Multi-Product Support",
        "🔄 API for Integrations",
        "📱 Email Interface",
        "🔍 Time Tracking",
        "📋 Patch Review System"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading Bugzilla icon..."
curl -L "$BUGZILLA_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-bugzilla << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/bugzilla && docker compose ps
        ;;
    logs)
        docker logs winejs-bugzilla --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/bugzilla && docker compose restart
        echo "Bugzilla restarted"
        ;;
    shell)
        docker exec -it winejs-bugzilla bash
        ;;
    checksetup)
        echo "🔧 Running checksetup..."
        docker exec winejs-bugzilla bash -c "cd /var/www/webapps/bugzilla && ./checksetup.pl"
        ;;
    rebuild)
        echo "🔄 Rebuilding Bugzilla configuration..."
        docker exec winejs-bugzilla bash -c "cd /var/www/webapps/bugzilla && perl -e 'use Bugzilla; Bugzilla->init_page();'"
        ;;
    sync)
        echo "🔄 Syncing permissions..."
        docker exec winejs-bugzilla bash -c "cd /var/www/webapps/bugzilla && ./syncparams.pl"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/bugzilla/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/bugzilla/"
        fi
        ;;
    admin)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/bugzilla/editusers.cgi"
        else
            echo "Admin: https://\${DOMAIN_NAME}/bugzilla/editusers.cgi"
        fi
        ;;
    createuser)
        echo "👤 Creating new user..."
        echo "Use the web interface: https://\${DOMAIN_NAME}/bugzilla/editusers.cgi"
        ;;
    *)
        echo "Bugzilla Bug Tracker Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-bugzilla open           - Open Bugzilla"
        echo "  winejs-bugzilla admin          - Open Admin Panel"
        echo "  winejs-bugzilla status         - Check status"
        echo "  winejs-bugzilla logs           - View logs"
        echo "  winejs-bugzilla restart        - Restart services"
        echo "  winejs-bugzilla shell          - Container shell"
        echo "  winejs-bugzilla checksetup     - Run checksetup"
        echo "  winejs-bugzilla rebuild        - Rebuild config"
        echo "  winejs-bugzilla sync           - Sync parameters"
        echo "  winejs-bugzilla createuser     - Create user guide"
        echo ""
        echo "Access URLs:"
        echo "  • Main Site: https://\${DOMAIN_NAME}/bugzilla/"
        echo "  • Admin Login: https://\${DOMAIN_NAME}/bugzilla/query.cgi"
        echo ""
        echo "Admin User: $ADMIN_EMAIL"
        echo "Admin Password: [the password you set]"
        echo ""
        echo "Quick Start:"
        echo "  1. Login with admin credentials"
        echo "  2. Create a product (Products → Add)"
        echo "  3. Create components (Products → Edit Components)"
        echo "  4. File your first bug (New → Enter a new bug report)"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-bugzilla

# ============= UPDATE NGINX FOR BUGZILLA =============
log "📝 Setting up nginx reverse proxy for Bugzilla..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /bugzilla" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Bugzilla Bug Tracker\n\
    location /bugzilla {\n\
        rewrite ^/bugzilla(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 86400;\n\
        client_max_body_size 20M;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Bugzilla routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_bugzilla.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Bugzilla..."

cd /opt/winejs/kasmvnc-instances/bugzilla
docker compose down -v 2>/dev/null

rm -rf /opt/winejs/apps/bugzilla
rm -rf /opt/winejs/kasmvnc-instances/bugzilla
rm -rf /opt/winejs/data/bugzilla
rm -rf /opt/winejs/config/bugzilla

rm -f /usr/local/bin/winejs-bugzilla

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Bugzilla Bug Tracker/,/location \/bugzilla/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/bugzilla {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Bugzilla uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_bugzilla.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              BUGZILLA INSTALLED ON WINEJS!                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Bugzilla Bug Tracker installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/bugzilla/"
echo ""
info "🔐 Admin Login:"
info "   • Email: $ADMIN_EMAIL"
info "   • Password: [the password you set]"
info "   • Name: $ADMIN_NAME"
echo ""
info "📧 Email Configuration:"
info "   • SMTP Server: $SMTP_SERVER"
info "   • From: $SMTP_FROM"
info "   • SSL: Enabled"
echo ""
info "🔧 Bugzilla Settings:"
info "   • URL Base: $URLBASE"
info "   • SSL Redirect: $SSL_REDIRECT"
echo ""
info "🎯 Quick Start Commands:"
info "   • winejs-bugzilla open        # Open Bugzilla"
info "   • winejs-bugzilla admin       # Open Admin Panel"
info "   • winejs-bugzilla status      # Check status"
info "   • winejs-bugzilla logs        # View logs"
info "   • winejs-bugzilla checksetup  # Run maintenance"
info "   • winejs-bugzilla shell       # Container shell"
echo ""
info "📁 Data Directories:"
info "   • Database: ${DATA_DIR}/mysql"
info "   • Web Files: ${DATA_DIR}/webapps"
info "   • Logs: ${DATA_DIR}/logs"
echo ""
info "📚 Quick Tutorial:"
info "   1. Login at https://$DOMAIN_NAME/bugzilla/"
info "   2. Click 'New' → 'Enter a new bug report'"
info "   3. Fill in bug details (summary, description)"
info "   4. Submit and track the bug"
info "   5. Add comments, attachments, and status updates"
echo ""
info "🔗 Integrations:"
info "   • Email: Reply to notifications to update bugs"
info "   • API: https://$DOMAIN_NAME/bugzilla/rest/"
info "   • Webhooks: Configure in Parameters"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_bugzilla.sh"
echo ""
success "✨ Bugzilla is ready! Track your first bug at https://$DOMAIN_NAME/bugzilla/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Bugzilla Does:

# Bugzilla is the industry-standard bug tracking system - used by Mozilla, GNOME, Linux Kernel, and thousands of organizations:
# Key Features:
#     Bug Tracking - Report, track, and manage bugs/issues
#     Advanced Search - Complex queries with custom fields
#     Email Notifications - Automatic updates via email
#     Workflow - Custom states and transitions
#     Permissions System - Granular access control
#     Reporting & Charts - Visualize bug data
#     Dependency Tracking - Block/blocked relationships
#     Patch Review - Built-in code review system
#     Time Tracking - Track time spent on bugs
#     API Access - REST API for integrations

# Perfect For:
#     Software Development - Track bugs and feature requests
#     QA Teams - Manage testing and validation
#     Open Source Projects - Community issue tracking
#     Internal IT - Track internal issues and requests
#     WineJS itself - Track user-reported issues!