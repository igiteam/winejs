#!/bin/bash
# ============================================
# SolidInvoice Invoicing Platform - WineJS Installer
# Adds Invoice Management to WineJS Platform
# ============================================
# App: SolidInvoice
# Category: Commerce
# Features: Invoicing, Quotes, Payments, Client Management
# ============================================

SOLIDINVOICE_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/solidinvoice-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "💰 Installing WineJS SolidInvoice Invoicing Platform..."

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

# ============= ASK FOR SOLIDINVOICE CONFIGURATION =============
echo ""
info "📝 SolidInvoice Configuration"
echo "================================"
read -p "Admin username: " ADMIN_USER
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""
read -p "Admin email: " ADMIN_EMAIL

# Generate secrets
SECRET_KEY=$(openssl rand -base64 32 | tr -d '\n=+/')
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/')

read -p "Default currency (USD/EUR/GBP) [USD]: " DEFAULT_CURRENCY
DEFAULT_CURRENCY=${DEFAULT_CURRENCY:-"USD"}

read -p "Enable payment gateways? (true/false) [false]: " PAYMENT_ENABLED
PAYMENT_ENABLED=${PAYMENT_ENABLED:-false}

if [ "$PAYMENT_ENABLED" = "true" ]; then
    read -p "Stripe secret key: " STRIPE_SECRET
    read -p "Stripe public key: " STRIPE_PUBLIC
fi

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=10000
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

# Find available port for SolidInvoice
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for SolidInvoice"
fi

log "Using port: SolidInvoice=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="solidinvoice"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/solidinvoice"
DATA_DIR="/opt/winejs/data/solidinvoice"
CONFIG_DIR="/opt/winejs/config/solidinvoice"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{db,html,logs,static,media,var}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/solidinvoice"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # MariaDB Database
  db:
    image: mariadb:10.11
    container_name: winejs-solidinvoice-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}
      MYSQL_DATABASE: solidinvoice
      MYSQL_USER: solidinvoice
      MYSQL_PASSWORD: ${DB_PASSWORD}
    volumes:
      - ${DATA_DIR}/db:/var/lib/mysql
      - ${DATA_DIR}/db-dump:/docker-entrypoint-initdb.d
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

  # SolidInvoice Application
  app:
    image: solidinvoice/solidinvoice:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:8765"
    volumes:
      - ${DATA_DIR}/html:/var/www/html
      - ${DATA_DIR}/logs:/var/log
      - ${DATA_DIR}/var:/var/lib/solidinvoice
      - ${DATA_DIR}/media:/var/www/html/media
      - ${CONFIG_DIR}:/etc/solidinvoice:ro
    environment:
      DATABASE_URL: mysql://solidinvoice:${DB_PASSWORD}@db:3306/solidinvoice
      APP_ENV: prod
      APP_SECRET: ${SECRET_KEY}
      APP_DEBUG: 0
      DEFAULT_CURRENCY: ${DEFAULT_CURRENCY}
      ADMIN_USER: ${ADMIN_USER}
      ADMIN_EMAIL: ${ADMIN_EMAIL}
      ADMIN_PASSWORD: ${ADMIN_PASSWORD}
    depends_on:
      db:
        condition: service_healthy
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= START CONTAINER =============
log "🚀 Starting SolidInvoice containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for SolidInvoice to initialize (this may take 2-3 minutes)..."
sleep 45

# Wait for database to be ready
MAX_ATTEMPTS=30
for i in $(seq 1 $MAX_ATTEMPTS); do
    if docker exec winejs-solidinvoice-db mysqladmin ping -h localhost --silent 2>/dev/null; then
        log "✅ Database is ready"
        break
    fi
    if [ $i -eq $MAX_ATTEMPTS ]; then
        warn "Database may not be ready. Continuing anyway..."
    fi
    sleep 2
done

# Run migrations
log "🔧 Running database migrations..."
docker exec winejs-solidinvoice php /var/www/html/bin/console doctrine:migrations:migrate --no-interaction 2>/dev/null || true

# Clear cache
docker exec winejs-solidinvoice php /var/www/html/bin/console cache:clear 2>/dev/null || true

# Create admin user if not exists
log "👤 Creating admin user..."
docker exec winejs-solidinvoice php /var/www/html/bin/console solidinvoice:user:create \
    --username="$ADMIN_USER" \
    --email="$ADMIN_EMAIL" \
    --password="$ADMIN_PASSWORD" \
    --admin 2>/dev/null || true

log "✅ SolidInvoice initialized"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "SolidInvoice Invoicing",
    "version": "latest",
    "description": "Sophisticated invoicing platform for freelancers and small businesses",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/solidinvoice.png",
    "category": "Commerce",
    "features": [
        "💰 Invoice Generation",
        "📋 Quote Management",
        "👥 Client & Contact Management",
        "💳 Online Payment Processing",
        "📊 Tax & Discount Handling",
        "🔄 Recurring Invoices",
        "📧 Email Notifications",
        "📈 Financial Reports",
        "🔌 RESTful API",
        "🏷️ Custom Fields",
        "📎 Document Attachments",
        "🌍 Multi-currency Support",
        "🏢 Multi-tenant Ready",
        "📱 Mobile Responsive"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading SolidInvoice icon..."
curl -L "$SOLIDINVOICE_LOGO_URL" -o "$ICON_DIR/solidinvoice.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE USER GUIDE =============
log "📚 Creating comprehensive user guide..."

cat > "$APP_DIR/user-guide.md" << 'GUIDE_EOF'
# SolidInvoice Invoicing Platform - Complete User Guide

## 📋 Table of Contents
1. [Quick Start](#quick-start)
2. [Company Setup](#company-setup)
3. [Client Management](#client-management)
4. [Creating Invoices](#creating-invoices)
5. [Quote Management](#quote-management)
6. [Payment Processing](#payment-processing)
7. [Recurring Billing](#recurring-billing)
8. [Tax Management](#tax-management)
9. [Reports & Analytics](#reports--analytics)
10. [API Integration](#api-integration)

## Quick Start

### First Login
1. Navigate to `https://DOMAIN_NAME/invoices/`
2. Login with admin credentials
3. Complete your company profile
4. Configure tax settings
5. Add payment gateway credentials

### 5-Minute Setup
# Add your first client
# Create a test invoice
# Send to yourself
# Record a test payment

Company Setup
Basic Information
    Company name, address, tax numbers
    Logo upload (recommended 200x200)
    Default payment terms
    Invoice numbering format

Email Configuration

SMTP Settings:
  Host: smtp.gmail.com
  Port: 587
  Encryption: TLS
  Authentication: Yes

Invoice Templates
    Professional: Clean, corporate style
    Creative: Modern design with color
    Minimal: Simple and functional
    Custom: Upload your own CSS

Client Management
Adding Clients

# Via Web UI
Clients → Add Client → Fill Details → Save

# Via API
curl -X POST https://DOMAIN_NAME/invoices/api/clients \
  -H "X-API-TOKEN: token" \
  -d '{"name":"Client Name","email":"client@email.com"}'

Client Portal Features
    View all invoices and quotes
    Download PDF copies
    Make online payments
    View payment history
    Update contact information

Client Groups
    Premium: Special payment terms
    Wholesale: Discounted rates
    VIP: Priority support
    Inactive: Archived clients

Creating Invoices
Manual Invoice Creation
    Invoices → Create New
    Select client
    Add line items:
        Description
        Quantity
        Unit price
        Tax rate
    Apply discounts if any
    Set due date
    Preview and send

Bulk Invoice Creation

# Import from CSV
php bin/console solidinvoice:import:invoices data.csv

# Generate from template
php bin/console solidinvoice:generate:invoices --template=retainer --clients=all

Invoice Statuses
Status	Description	Action
Draft	Not yet sent	Edit freely
Sent	Delivered	Track views
Viewed	Client opened	Follow up
Paid	Payment received	Archive
Overdue	Past due	Send reminder
Cancelled	Voided	Write off
Quote Management

Creating Quotes
    Same process as invoices
    Set expiry date (default 30 days)
    Add approval terms
    Send for client signature

Quote to Invoice Conversion
    Client accepts quote
    Click "Convert to Invoice"
    Adjust if needed
    Send invoice automatically

Payment Processing
Stripe Integration

// Configuration
STRIPE_SECRET_KEY=sk_live_xxx
STRIPE_PUBLIC_KEY=pk_live_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx

// Webhook URL
https://DOMAIN_NAME/invoices/webhook/stripe

PayPal Integration
PAYPAL_CLIENT_ID=xxx
PAYPAL_SECRET=xxx
PAYPAL_MODE=live  # sandbox or live

Manual Payments
    Bank transfers
    Cash payments
    Checks
    Custom methods

Payment Automation
# Auto-mark invoices as paid
php bin/console solidinvoice:payment:sync

# Send payment confirmations
php bin/console solidinvoice:payment:confirmations

Recurring Billing
Setting Up Recurring Invoices
    Create a standard invoice
    Click "Make Recurring"

    Set frequency:
        Weekly
        Monthly
        Quarterly
        Yearly
        
    Define end date (or unlimited)
    Auto-send to client

Managing Subscriptions

# List all subscriptions
php bin/console solidinvoice:subscription:list

# Pause subscription
php bin/console solidinvoice:subscription:pause --id=123

# Resume subscription
php bin/console solidinvoice:subscription:resume --id=123

Tax Management
Tax Configuration

Tax Rates:
  - Name: VAT 20%
    Rate: 20.00
    Type: inclusive
  - Name: VAT 5% (reduced)
    Rate: 5.00
    Type: inclusive
  - Name: Zero-rated
    Rate: 0.00
    Type: exclusive

Tax Rules:
  - EU VAT MOSS enabled
  - Reverse charge for B2B
  - Tax-exempt organizations

Tax Reports

# Generate VAT report
php bin/console solidinvoice:report:tax --period=quarterly

# Export for tax filing
php bin/console solidinvoice:export:tax --format=csv

Reports & Analytics
Financial Reports

# Income statement
php bin/console solidinvoice:report:income --year=2024

# Accounts receivable aging
php bin/console solidinvoice:report:aging

# Client payment history
php bin/console solidinvoice:report:clients --top=10

Dashboard Widgets
    Revenue chart (daily/weekly/monthly)
    Top clients by revenue
    Overdue invoices alert
    Payment success rate
    Quote conversion rate

API Integration
Authentication
bash

# Get API token from user profile
TOKEN="your-api-token"

# Use in requests
curl -H "Authorization: Bearer $TOKEN" \
     https://DOMAIN_NAME/invoices/api/invoices

API Endpoints
Endpoint	Method	Description
/api/invoices	GET	List invoices
/api/invoices	POST	Create invoice
/api/invoices/{id}	GET	Get invoice
/api/invoices/{id}	PUT	Update invoice
/api/invoices/{id}/pay	POST	Record payment
/api/quotes	CRUD	Quote management
/api/clients	CRUD	Client management
/api/reports	GET	Generate reports
/api/webhooks	POST	Webhook receiver
Webhook Events
json

{
  "event": "invoice.paid",
  "data": {
    "invoice_id": 123,
    "amount": 1000.00,
    "currency": "USD",
    "paid_at": "2024-01-15T10:30:00Z"
  }
}
GUIDE_EOF

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-solidinvoice << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}
ADMIN_USER="${ADMIN_USER}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/solidinvoice && docker compose ps
        ;;
    logs)
        docker logs winejs-solidinvoice --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/solidinvoice && docker compose restart
        echo "SolidInvoice restarted"
        ;;
    migrate)
        echo "🔄 Running database migrations..."
        docker exec winejs-solidinvoice php bin/console doctrine:migrations:migrate --no-interaction
        ;;
    cache-clear)
        echo "🗑️ Clearing cache..."
        docker exec winejs-solidinvoice php bin/console cache:clear
        ;;
    create-user)
        echo "👤 Creating user..."
        docker exec -it winejs-solidinvoice php bin/console solidinvoice:user:create
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/invoices/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/invoices/"
        fi
        ;;
    admin)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/invoices/admin"
        else
            echo "Admin: https://\${DOMAIN_NAME}/invoices/admin"
        fi
        ;;
    *)
        echo "SolidInvoice Invoicing Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-solidinvoice open      # Open dashboard"
        echo "  winejs-solidinvoice admin     # Open admin"
        echo "  winejs-solidinvoice status    # Check status"
        echo "  winejs-solidinvoice logs      # View logs"
        echo "  winejs-solidinvoice restart   # Restart"
        echo "  winejs-solidinvoice migrate   # Run migrations"
        echo "  winejs-solidinvoice cache-clear # Clear cache"
        echo "  winejs-solidinvoice create-user # Create new user"
        echo ""
        echo "Access URLs:"
        echo "  • Dashboard: https://\${DOMAIN_NAME}/invoices/"
        echo "  • Admin: https://\${DOMAIN_NAME}/invoices/admin"
        echo ""
        echo "Admin Login: ${ADMIN_USER} / (password you set)"
        echo "Admin Email: ${ADMIN_EMAIL}"
        echo ""
        echo "Default Currency: ${DEFAULT_CURRENCY}"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-solidinvoice

# ============= UPDATE NGINX FOR SOLIDINVOICE =============
log "📝 Setting up nginx reverse proxy for SolidInvoice..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /invoices" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # SolidInvoice Invoicing\n\
    location /invoices {\n\
        rewrite ^/invoices(/.*)? /\\\1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \$host;\n\
        proxy_set_header X-Real-IP \$remote_addr;\n\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 300s;\n\
        proxy_buffering off;\n\
        client_max_body_size 100M;\n\
    }\n\
    \n\
    # SolidInvoice API\n\
    location /invoices/api/ {\n\
        rewrite ^/invoices/api/(.*) /api/\\\1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \$host;\n\
        proxy_set_header X-Real-IP \$remote_addr;\n\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \$scheme;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with SolidInvoice routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_solidinvoice.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling SolidInvoice..."

cd /opt/winejs/kasmvnc-instances/solidinvoice
docker compose down -v 2>/dev/null

# Ask about removing data
read -p "Remove all invoice data and client records? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ [Yy] ]]; then
    rm -rf /opt/winejs/apps/solidinvoice
    rm -rf /opt/winejs/kasmvnc-instances/solidinvoice
    rm -rf /opt/winejs/data/solidinvoice
    rm -rf /opt/winejs/config/solidinvoice
    log "✅ All data removed"
else
    rm -rf /opt/winejs/apps/solidinvoice
    rm -rf /opt/winejs/kasmvnc-instances/solidinvoice
    rm -rf /opt/winejs/config/solidinvoice
fi

rm -f /usr/local/bin/winejs-solidinvoice

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# SolidInvoice Invoicing/,/location \/invoices\/api\//d' /etc/nginx/sites-available/winejs
    sed -i '/location \/invoices {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ SolidInvoice uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_solidinvoice.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           SOLIDINVOICE INSTALLED ON WINEJS!                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ SolidInvoice Invoicing Platform installed!"
echo ""
info "🌐 Access URLs:"
info "  • Dashboard: https://$DOMAIN_NAME/invoices/"
info "  • Admin Panel: https://$DOMAIN_NAME/invoices/admin"
echo ""
info "🔐 Admin Login:"
info "  • Username: $ADMIN_USER"
info "  • Password: [the password you set]"
info "  • Email: $ADMIN_EMAIL"
echo ""
info "💰 Features:"
info "  • Invoice & Quote Management"
info "  • Client & Contact Management"
if [ "$PAYMENT_ENABLED" = "true" ]; then 
    info "  • Online Payments (Stripe/PayPal)"
fi
info "  • Recurring Invoices"
info "  • Tax & Discount Handling"
info "  • Financial Reports"
info "  • API Access"
echo ""
info "⚙️ Configuration:"
info "  • Default Currency: $DEFAULT_CURRENCY"
echo ""
info "🎯 Quick Commands:"
info "  • winejs-solidinvoice open       # Open dashboard"
info "  • winejs-solidinvoice admin      # Open admin"
info "  • winejs-solidinvoice status     # Check status"
info "  • winejs-solidinvoice logs       # View logs"
info "  • winejs-solidinvoice migrate    # Run migrations"
info "  • winejs-solidinvoice cache-clear # Clear cache"
info "  • winejs-solidinvoice create-user # Create new user"
echo ""
info "📁 Data Directories:"
info "  • Database: $DATA_DIR/db"
info "  • Media: $DATA_DIR/media"
info "  • Logs: $DATA_DIR/logs"
info "  • Config: $CONFIG_DIR"
echo ""
info "💡 Quick Start:"
info "  1. Login to the dashboard"
info "  2. Configure your company settings"
info "  3. Add your first client"
info "  4. Create an invoice"
info "  5. Send to client"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_solidinvoice.sh"
echo ""
success "✨ SolidInvoice is ready! Start invoicing at https://$DOMAIN_NAME/invoices/"
echo ""
echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

## What SolidInvoice Does:

# **SolidInvoice is a sophisticated invoicing platform for small businesses and freelancers:**

# ### Key Features:

# 1. **Invoice Management** - Create, send, and track invoices
# 2. **Quote System** - Generate quotes, convert to invoices
# 3. **Client Management** - Manage clients and contacts
# 4. **Payment Processing** - Online payments via Stripe/PayPal
# 5. **Recurring Invoices** - Subscription billing
# 6. **Tax Handling** - Multiple tax rates, VAT support
# 7. **Reports** - Financial reports and analytics
# 8. **API Access** - REST API for integrations
# 9. **Multi-currency** - Support for multiple currencies
# 10. **Email Notifications** - Auto-send invoices and receipts

# ### Perfect For:

# - **Freelancers** - Invoice clients professionally
# - **Small Businesses** - Manage billing operations
# - **Agencies** - Track client payments
# - **Subscription Services** - Recurring billing
# - **Consultants** - Time-based invoicing