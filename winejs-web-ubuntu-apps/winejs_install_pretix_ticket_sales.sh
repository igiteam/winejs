#!/bin/bash
# ============================================
# Pretix Ticketing System - WineJS Installer
# Adds Event Ticketing Platform to WineJS
# ============================================
# App: Pretix
# Category: Commerce
# Features: Event Tickets, Seating, Discounts, Payment Gateways
# ============================================

PRETIX_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/pretix_logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🎟️ Installing WineJS Pretix Ticketing System..."

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

# ============= ASK FOR PRETIX CONFIGURATION =============
echo ""
info "📝 Pretix Configuration"
echo "================================"
read -p "Instance name [WineJS Tickets]: " INSTANCE_NAME
INSTANCE_NAME=${INSTANCE_NAME:-"WineJS Tickets"}

read -p "Currency (EUR/USD/GBP/PLN/CHF/CZK/SEK/DKK/NOK) [EUR]: " CURRENCY
CURRENCY=${CURRENCY:-"EUR"}

read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

read -p "SMTP server for email: " SMTP_HOST
read -p "SMTP port: " SMTP_PORT
read -p "SMTP user: " SMTP_USER
read -s -p "SMTP password: " SMTP_PASSWORD
echo ""
read -p "From email address: " FROM_EMAIL

read -p "Enable payment via Stripe? (true/false) [false]: " STRIPE_ENABLED
if [ "$STRIPE_ENABLED" = "true" ]; then
    read -p "Stripe Public Key: " STRIPE_PUBLIC_KEY
    read -s -p "Stripe Secret Key: " STRIPE_SECRET_KEY
    echo ""
fi

read -p "Enable payment via PayPal? (true/false) [false]: " PAYPAL_ENABLED
if [ "$PAYPAL_ENABLED" = "true" ]; then
    read -p "PayPal Client ID: " PAYPAL_CLIENT_ID
    read -s -p "PayPal Secret: " PAYPAL_SECRET
    echo ""
fi

# Generate database password
DB_PASSWORD=$(openssl rand -base64 16 | tr -d '\n=+/' | head -c 16)

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=8000  # Start after Artalk's range (7900+)
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

# Find available port for Pretix
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Pretix"
fi

log "Using port: Pretix=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="pretix"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/pretix"
CONFIG_DIR="/opt/winejs/config/pretix"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$ICON_DIR"
chown -R 15371:15371 "$DATA_DIR" "$CONFIG_DIR" 2>/dev/null || true

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/pretix"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # PostgreSQL Database
  postgres:
    image: postgres:14
    container_name: winejs-pretix-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: pretix
      POSTGRES_USER: pretix
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U pretix"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis Cache
  redis:
    image: redis:7-alpine
    container_name: winejs-pretix-redis
    restart: unless-stopped
    command: redis-server --appendonly yes --save 60 500
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Pretix Worker
  worker:
    image: pretix/standalone:stable
    container_name: winejs-pretix-worker
    restart: unless-stopped
    environment:
      - PRETIX_CONFIG_FILE=/etc/pretix/pretix.cfg
    volumes:
      - ${DATA_DIR}:/data
      - ${CONFIG_DIR}:/etc/pretix:ro
    command: taskworker
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - winejs-net

  # Pretix Web Server
  web:
    image: pretix/standalone:stable
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:80"
    environment:
      - PRETIX_CONFIG_FILE=/etc/pretix/pretix.cfg
      - NUM_WORKERS=2
    volumes:
      - ${DATA_DIR}:/data
      - ${CONFIG_DIR}:/etc/pretix:ro
    command: web
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      worker:
        condition: service_started
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE PRETIX CONFIGURATION =============
log "📝 Creating Pretix configuration..."

# Build payment settings
PAYMENT_CONFIG=""
if [ "$STRIPE_ENABLED" = "true" ]; then
    PAYMENT_CONFIG="$PAYMENT_CONFIG
[stripe]
enabled=True
public_key=$STRIPE_PUBLIC_KEY
secret_key=$STRIPE_SECRET_KEY"
fi

if [ "$PAYPAL_ENABLED" = "true" ]; then
    PAYMENT_CONFIG="$PAYMENT_CONFIG
[paypal]
enabled=True
client_id=$PAYPAL_CLIENT_ID
secret=$PAYPAL_SECRET
endpoint=live"
fi

cat > "$CONFIG_DIR/pretix.cfg" << EOF
[pretix]
instance_name=$INSTANCE_NAME
url=https://$DOMAIN_NAME/pretix
currency=$CURRENCY
datadir=/data
trust_x_forwarded_for=on
trust_x_forwarded_proto=on

[database]
backend=postgresql
name=pretix
user=pretix
password=$DB_PASSWORD
host=postgres

[mail]
from=$FROM_EMAIL
host=$SMTP_HOST
port=$SMTP_PORT
username=$SMTP_USER
password=$SMTP_PASSWORD
tls=on

[redis]
location=redis://redis:6379/0
sessions=true

[celery]
backend=redis://redis:6379/1
broker=redis://redis:6379/2
$PAYMENT_CONFIG
EOF

# ============= CREATE SYSTEMD SERVICE FILE =============
log "📝 Creating systemd service..."

cat > "$APP_DIR/pretix.service" << SERVICE_EOF
[Unit]
Description=Pretix Ticketing System
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
ExecStartPre=-/usr/bin/docker kill pretix.service
ExecStartPre=-/usr/bin/docker rm pretix.service
ExecStart=/usr/bin/docker run --name pretix.service -p 127.0.0.1:${APP_PORT}:80 \\
    -v ${DATA_DIR}:/data \\
    -v ${CONFIG_DIR}:/etc/pretix \\
    --sysctl net.core.somaxconn=4096 \\
    pretix/standalone:stable all
ExecStop=/usr/bin/docker stop pretix.service
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# ============= INITIALIZE PRETIX =============
log "🚀 Starting Pretix containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Pretix to initialize (this may take 1-2 minutes)..."
sleep 60

# Run initial setup and create admin user
log "🔐 Creating admin user..."

docker exec winejs-pretix pretix migrate 2>/dev/null || true
docker exec winejs-pretix pretix rebuild 2>/dev/null || true

# Create admin user non-interactively
docker exec winejs-pretix pretix createsuperuser \
    --username admin \
    --email "$ADMIN_EMAIL" \
    --noinput 2>/dev/null || true

# Set admin password
docker exec winejs-pretix pretix changepassword admin <<< "$ADMIN_PASSWORD" 2>/dev/null || true

# Create initial organizer and team
docker exec winejs-pretix pretix shell << PYTHON_EOF
from pretix.base.models import Organizer, Team, User
try:
    organizer = Organizer.objects.create(
        slug="winejs",
        name="WineJS Events",
        default_locale="en"
    )
    print("Organizer created")
except:
    print("Organizer may already exist")
PYTHON_EOF

log "✅ Pretix initialized"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

# Build features list
FEATURES_LIST='[
        "🎟️ Event Ticketing",
        "📊 Seat Maps & Reservations",
        "💰 Discount Codes & Vouchers",'
if [ "$STRIPE_ENABLED" = "true" ]; then
    FEATURES_LIST="$FEATURES_LIST\n        \"💳 Stripe Integration\","
fi
if [ "$PAYPAL_ENABLED" = "true" ]; then
    FEATURES_LIST="$FEATURES_LIST\n        \"💸 PayPal Integration\","
fi
FEATURES_LIST="$FEATURES_LIST
        "📧 Automated Email Confirmations",
        "📈 Sales Reports & Analytics",
        "🎫 PDF Ticket Generation",
        "📱 Mobile-Ready Check-in",
        "🔗 API for Integrations",
        "🌍 Multi-language Support",
        "🔄 Waitlists & Quotas",
        "📊 Custom Questions & Forms"
    ]"

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Pretix Ticketing System",
    "version": "stable",
    "description": "Powerful event ticketing platform with seating, discounts, and payment gateways",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/pretix.png",
    "category": "Commerce",
    "features": ${FEATURES_LIST}
}
CONF_EOF

# ============= CREATE SETUP GUIDE =============
log "📝 Creating setup guide..."

cat > "$APP_DIR/setup-guide.md" << GUIDE_EOF
# Pretix Ticketing System - Quick Start Guide

## Access URLs

- **Main Site**: https://$DOMAIN_NAME/pretix/
- **Admin Panel**: https://$DOMAIN_NAME/pretix/control/

## Default Admin Login
- **Username**: admin
- **Password**: [the password you set]

## First Steps

1. **Login** to the admin panel
2. **Create an Organizer** (if not already created)
3. **Create your first Event**
4. **Configure ticket types** (early bird, regular, VIP)
5. **Set up seating** (if applicable)
6. **Configure payment methods**
7. **Start selling tickets!**

## Creating Your First Event

1. Go to Control → Events → Create Event
2. Fill in event details:
   - Name, date, location
   - Ticket types and prices
   - Sales start/end dates
3. Configure payment settings
4. Publish when ready

## Adding Tickets to Your Website

\`\`\`html
<!-- Direct link to ticket shop -->
<a href="https://$DOMAIN_NAME/pretix/YOUR-ORGANIZER/YOUR-EVENT/">Buy Tickets</a>

<!-- Embedded widget -->
<iframe src="https://$DOMAIN_NAME/pretix/YOUR-ORGANIZER/YOUR-EVENT/widget/v1.html"
        frameborder="0" width="100%" height="600"></iframe>
\`\`\`

## Managing Check-ins

Download the **Pretix Check-in** app from:
- iOS: App Store
- Android: Google Play

Configure check-in lists in Control → Events → Your Event → Check-in

## Reports & Export

- Sales reports: Control → Events → Reports
- Export attendee lists: CSV/Excel format
- API access for custom integrations

## Daily Operations

\`\`\`bash
# View logs
winejs-pretix logs

# Check status
winejs-pretix status

# Run periodic tasks (cron)
docker exec winejs-pretix pretix runperiodic
\`\`\`

## Backup

\`\`\`bash
# Backup database and files
docker exec winejs-pretix pretix backup
# Files saved in: ${DATA_DIR}/backups/
\`\`\`

## Helpful Links

- [Pretix Documentation](https://docs.pretix.eu/)
- [Ticket Shop Widget](https://docs.pretix.eu/en/latest/user/widgets.html)
- [API Reference](https://docs.pretix.eu/en/latest/api/index.html)
GUIDE_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading Pretix icon..."
curl -L "$PRETIX_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-pretix << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
DATA_DIR="${DATA_DIR}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/pretix && docker compose ps
        ;;
    logs)
        docker logs winejs-pretix --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/pretix && docker compose restart
        echo "Pretix restarted"
        ;;
    migrate)
        echo "🔄 Running database migrations..."
        docker exec winejs-pretix pretix migrate
        docker exec winejs-pretix pretix rebuild
        ;;
    cron)
        echo "⏰ Running periodic tasks..."
        docker exec winejs-pretix pretix runperiodic
        ;;
    backup)
        echo "💾 Creating backup..."
        docker exec winejs-pretix pretix backup
        echo "Backup saved in: \$DATA_DIR/backups/"
        ;;
    shell)
        docker exec -it winejs-pretix pretix shell
        ;;
    events)
        echo "📅 Your events:"
        docker exec winejs-pretix pretix shell -c "from pretix.base.models import Event; [print(f'  • {e.name} ({e.slug}) - Status: {e.live}') for e in Event.objects.all()]"
        ;;
    reports)
        echo "📊 Generating sales report..."
        docker exec winejs-pretix pretix shell -c "from pretix.base.models import Order, Event; from datetime import datetime, timedelta; week_ago = datetime.now() - timedelta(days=7); orders = Order.objects.filter(datetime__gte=week_ago, status='p'); print(f'Orders in last 7 days: {orders.count()}')"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/pretix/control/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/pretix/control/"
        fi
        ;;
    *)
        echo "Pretix Ticketing System Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-pretix open           - Open Admin Panel"
        echo "  winejs-pretix status         - Check status"
        echo "  winejs-pretix logs           - View logs"
        echo "  winejs-pretix restart        - Restart services"
        echo "  winejs-pretix migrate        - Run migrations"
        echo "  winejs-pretix cron           - Run periodic tasks"
        echo "  winejs-pretix backup         - Create backup"
        echo "  winejs-pretix shell          - Django shell"
        echo "  winejs-pretix events         - List events"
        echo "  winejs-pretix reports        - Quick sales report"
        echo ""
        echo "Access URLs:"
        echo "  • Main Site: https://\${DOMAIN_NAME}/pretix/"
        echo "  • Admin: https://\${DOMAIN_NAME}/pretix/control/"
        echo ""
        echo "Admin Login: admin / (password you set)"
        echo "Admin Email: $ADMIN_EMAIL"
        echo ""
        echo "Setup Guide: cat /opt/winejs/apps/pretix/setup-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-pretix

# ============= UPDATE NGINX FOR PRETIX =============
log "📝 Setting up nginx reverse proxy for Pretix..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /pretix" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Pretix Ticketing System\n\
    location /pretix {\n\
        rewrite ^/pretix(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 86400;\n\
        proxy_buffering off;\n\
        client_max_body_size 20M;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Pretix routes"
            else
                warn "Nginx test failed, restoring backup"
                cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                nginx -t && systemctl reload nginx
            fi
        fi
    fi
fi

# ============= SETUP CRONJOBS =============
log "⏰ Setting up cronjobs for periodic tasks..."

(crontab -l 2>/dev/null | grep -v "pretix cron" || true; 
 echo "*/15 * * * * /usr/bin/docker exec winejs-pretix pretix runperiodic") | crontab -

# ============= RESTART TRANSLATOR =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_pretix.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Pretix..."

cd /opt/winejs/kasmvnc-instances/pretix
docker compose down -v 2>/dev/null

rm -rf /opt/winejs/apps/pretix
rm -rf /opt/winejs/kasmvnc-instances/pretix
rm -rf /opt/winejs/data/pretix
rm -rf /opt/winejs/config/pretix

rm -f /usr/local/bin/winejs-pretix

# Remove cronjobs
crontab -l 2>/dev/null | grep -v "pretix cron" | crontab - 2>/dev/null || true

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Pretix Ticketing System/,/location \/pretix/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/pretix {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Pretix uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_pretix.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              PRETIX INSTALLED ON WINEJS!                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Pretix Ticketing System installed!"
echo ""
info "🌐 Access URLs:"
info "   • Main Site: https://$DOMAIN_NAME/pretix/"
info "   • Admin Panel: https://$DOMAIN_NAME/pretix/control/"
echo ""
info "🔐 Admin Login:"
info "   • Username: admin"
info "   • Password: [the password you set]"
info "   • Email: $ADMIN_EMAIL"
echo ""
info "💰 Payment Gateways:"
if [ "$STRIPE_ENABLED" = "true" ]; then
    info "   • Stripe: Enabled ✓"
else
    info "   • Stripe: Disabled (configure in settings)"
fi
if [ "$PAYPAL_ENABLED" = "true" ]; then
    info "   • PayPal: Enabled ✓"
else
    info "   • PayPal: Disabled (configure in settings)"
fi
echo ""
info "📧 Email Configuration:"
info "   • SMTP Server: $SMTP_HOST:$SMTP_PORT"
info "   • From: $FROM_EMAIL"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-pretix open        # Open Admin Panel"
info "   • winejs-pretix status      # Check status"
info "   • winejs-pretix logs        # View logs"
info "   • winejs-pretix events      # List your events"
info "   • winejs-pretix reports     # Quick sales report"
info "   • winejs-pretix backup      # Create backup"
info "   • winejs-pretix cron        # Run periodic tasks"
echo ""
info "📁 Data Directories:"
info "   • Uploads: $DATA_DIR"
info "   • Config: $CONFIG_DIR/pretix.cfg"
echo ""
info "📚 Setup Guide:"
info "   • cat /opt/winejs/apps/pretix/setup-guide.md"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_pretix.sh"
echo ""
success "✨ Pretix is ready! Start selling tickets at https://$DOMAIN_NAME/pretix/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Pretix Does:

# Pretix is a powerful event ticketing platform - sell tickets for conferences, concerts, workshops:
# Key Features:
#     Event Management - Create and manage multiple events
#     Ticket Types - Early bird, regular, VIP, group discounts
#     Seat Maps - Reserved seating with visual seat selection
#     Payment Gateways - Stripe, PayPal, and more
#     Check-in App - Mobile app for scanning tickets at the door
#     Discount Codes - Create vouchers and promo codes
#     Waitlists - Automatic notifications when tickets become available
#     Export Reports - Sales reports, attendee lists, analytics

# Perfect For:
#     Conferences - Sell tickets with different tiers
#     Workshops - Limited capacity with waitlists
#     Concerts - Reserved seating and GA tickets
#     Meetups - Free or paid events
#     WineJS itself - Sell tickets for your launch event!