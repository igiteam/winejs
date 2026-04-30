#!/bin/bash
# ============================================
# Saleor E-commerce Platform - WineJS Installer
# Adds Headless E-commerce Platform to WineJS
# ============================================
# App: Saleor
# Category: Commerce
# Features: E-commerce, Headless Commerce, GraphQL API
# ============================================

SALEOR_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/saleor-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🛒 Installing WineJS Saleor E-commerce Platform..."

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

# ============= ASK FOR SALEOR CONFIGURATION =============
echo ""
info "📝 Saleor Configuration"
echo "================================"
read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

read -p "Store name [WineJS Store]: " STORE_NAME
STORE_NAME=${STORE_NAME:-"WineJS Store"}

read -p "Default currency (USD/EUR/GBP) [USD]: " DEFAULT_CURRENCY
DEFAULT_CURRENCY=${DEFAULT_CURRENCY:-"USD"}

read -p "Default country [US]: " DEFAULT_COUNTRY
DEFAULT_COUNTRY=${DEFAULT_COUNTRY:-"US"}

read -p "Enable sample data? (true/false) [true]: " SAMPLE_DATA
SAMPLE_DATA=${SAMPLE_DATA:-true}

read -p "Enable debug mode? (true/false) [false]: " DEBUG_MODE
DEBUG_MODE=${DEBUG_MODE:-false}

read -p "Enable telemetry? (true/false) [true]: " TELEMETRY
TELEMETRY=${TELEMETRY:-true}

# Generate secrets
SECRET_KEY=$(openssl rand -base64 50 | tr -d '\n=+/' | head -c 50)
JWT_SECRET=$(openssl rand -base64 50 | tr -d '\n=+/' | head -c 50)

# Database passwords
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/' | head -c 24)

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=9700  # Start after Paperless's range (9600+)
MAX_RETRIES=50
API_PORT=""
DASHBOARD_PORT=""
STOREFRONT_PORT=""

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

# Find available ports for Saleor services
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        API_PORT=$TEST_PORT
        break
    fi
done

for i in $(seq 1 $MAX_RETRIES); do
    TEST_PORT=$((API_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        DASHBOARD_PORT=$TEST_PORT
        break
    fi
done

for i in $(seq 2 $MAX_RETRIES); do
    TEST_PORT=$((DASHBOARD_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        STOREFRONT_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$API_PORT" ] || [ -z "$DASHBOARD_PORT" ] || [ -z "$STOREFRONT_PORT" ]; then
    error "Could not find available ports for Saleor"
fi

log "Using ports: API=$API_PORT, Dashboard=$DASHBOARD_PORT, Storefront=$STOREFRONT_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="saleor"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/saleor"
DATA_DIR="/opt/winejs/data/saleor"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{postgres,redis,media,static,logs}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/saleor"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << 'DOCKER_EOF'
services:
  # PostgreSQL Database
  db:
    image: postgres:15
    container_name: winejs-saleor-db
    restart: unless-stopped
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: saleor
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: saleor
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U saleor"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis Cache & Broker
  redis:
    image: redis:7-alpine
    container_name: winejs-saleor-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Saleor API
  api:
    image: ghcr.io/saleor/saleor:latest
    container_name: winejs-saleor-api
    restart: unless-stopped
    ports:
      - "127.0.0.1:${API_PORT}:8000"
    volumes:
      - ${DATA_DIR}/media:/app/media
      - ${DATA_DIR}/static:/app/static
      - ${DATA_DIR}/logs:/app/logs
    environment:
      DATABASE_URL: postgres://saleor:${DB_PASSWORD}@db:5432/saleor
      CELERY_BROKER_URL: redis://redis:6379/0
      SECRET_KEY: ${SECRET_KEY}
      JWT_SECRET: ${JWT_SECRET}
      DEBUG: ${DEBUG_MODE}
      ALLOWED_HOSTS: ${DOMAIN_NAME},localhost,127.0.0.1
      ALLOWED_CLIENT_HOSTS: https://${DOMAIN_NAME}/store,https://${DOMAIN_NAME}/dashboard
      DEFAULT_FROM_EMAIL: noreply@${DOMAIN_NAME}
      DEFAULT_COUNTRY: ${DEFAULT_COUNTRY}
      DEFAULT_CURRENCY: ${DEFAULT_CURRENCY}
      SEND_USAGE_TELEMETRY: ${TELEMETRY}
      PUBLIC_URL: https://${DOMAIN_NAME}/store/api
      STATIC_URL: /static/
      MEDIA_URL: /media/
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - winejs-net

  # Saleor Worker (Celery)
  worker:
    image: ghcr.io/saleor/saleor:latest
    container_name: winejs-saleor-worker
    restart: unless-stopped
    command: celery --app saleor.celeryconf:app worker -E --loglevel=info
    volumes:
      - ${DATA_DIR}/media:/app/media
      - ${DATA_DIR}/logs:/app/logs
    environment:
      DATABASE_URL: postgres://saleor:${DB_PASSWORD}@db:5432/saleor
      CELERY_BROKER_URL: redis://redis:6379/0
      SECRET_KEY: ${SECRET_KEY}
      DEBUG: ${DEBUG_MODE}
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - winejs-net

  # Saleor Scheduler (Celery Beat)
  scheduler:
    image: ghcr.io/saleor/saleor:latest
    container_name: winejs-saleor-scheduler
    restart: unless-stopped
    command: celery --app saleor.celeryconf:app beat --scheduler saleor.schedulers.schedulers.DatabaseScheduler
    environment:
      DATABASE_URL: postgres://saleor:${DB_PASSWORD}@db:5432/saleor
      CELERY_BROKER_URL: redis://redis:6379/0
      SECRET_KEY: ${SECRET_KEY}
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - winejs-net

  # Saleor Dashboard
  dashboard:
    image: ghcr.io/saleor/saleor-dashboard:latest
    container_name: winejs-saleor-dashboard
    restart: unless-stopped
    ports:
      - "127.0.0.1:${DASHBOARD_PORT}:80"
    environment:
      API_URL: https://${DOMAIN_NAME}/store/api/graphql/
    networks:
      - winejs-net

  # React Storefront
  storefront:
    image: ghcr.io/saleor/saleor-storefront:latest
    container_name: winejs-saleor-storefront
    restart: unless-stopped
    ports:
      - "127.0.0.1:${STOREFRONT_PORT}:3000"
    environment:
      NEXT_PUBLIC_SALEOR_API_URL: https://${DOMAIN_NAME}/store/api/graphql/
      NEXT_PUBLIC_STOREFONT_URL: https://${DOMAIN_NAME}/store
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= INITIALIZE DATABASE =============
log "🚀 Starting Saleor containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Saleor to initialize (this may take 3-5 minutes)..."
sleep 90

# Run migrations
log "🔄 Running database migrations..."
docker exec winejs-saleor-api python3 manage.py migrate --noinput 2>/dev/null || true

# Collect static files
log "📦 Collecting static files..."
docker exec winejs-saleor-api python3 manage.py collectstatic --noinput 2>/dev/null || true

# Add sample data if enabled
if [ "$SAMPLE_DATA" = "true" ]; then
    log "📊 Populating database with sample data..."
    docker exec winejs-saleor-api python3 manage.py populatedb 2>/dev/null || true
fi

# Create superuser
log "👤 Creating admin user..."
docker exec winejs-saleor-api python3 manage.py shell << PYTHON_EOF
from django.contrib.auth import get_user_model
User = get_user_model()
if not User.objects.filter(email='${ADMIN_EMAIL}').exists():
    User.objects.create_superuser('${ADMIN_EMAIL}', '${ADMIN_PASSWORD}')
    print("Superuser created")
else:
    print("Superuser already exists")
PYTHON_EOF

log "✅ Saleor initialized"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Saleor E-commerce Platform",
    "version": "latest",
    "description": "Headless e-commerce platform with GraphQL API, modern storefront, and powerful dashboard",
    "executable": "launch.sh",
    "port": ${API_PORT},
    "vnc_password": "",
    "icon": "/icons/saleor.png",
    "category": "Commerce",
    "features": [
        "🛒 Headless E-commerce",
        "📊 GraphQL API",
        "📱 Modern Storefront (Next.js)",
        "🔧 Powerful Admin Dashboard",
        "💳 Multi-currency Support",
        "📦 Multi-channel Management",
        "🏷️ Product & Category Management",
        "👥 Customer Management",
        "📈 Order Management",
        "🚚 Shipping & Tax Configuration",
        "🔄 Webhook Integrations",
        "📱 Mobile-Responsive",
        "🔌 App Marketplace",
        "📊 Analytics & Reporting"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << GUIDE_EOF
# Saleor E-commerce Platform - User Guide

## Access URLs
- **Storefront (Customer View)**: https://$DOMAIN_NAME/store/
- **Admin Dashboard**: https://$DOMAIN_NAME/dashboard/
- **GraphQL API**: https://$DOMAIN_NAME/store/api/graphql/
- **GraphQL Playground**: https://$DOMAIN_NAME/store/api/graphql/ (use cmd+space)

## Admin Login
- **Email**: $ADMIN_EMAIL
- **Password**: [the password you set]

## First Steps

### 1. Configure Your Store

1. Login to the admin dashboard
2. Go to **Configuration** → **Site Settings**
3. Set your store name: $STORE_NAME
4. Configure default currency: $DEFAULT_CURRENCY
5. Set up payment gateways (Stripe, PayPal, etc.)

### 2. Manage Products

**Add Products**:
1. Go to **Catalog** → **Products**
2. Click "Create Product"
3. Choose product type
4. Fill in product details:
   - Name, description, price
   - Images, SEO metadata
   - Variants (size, color, etc.)
   - Inventory tracking

**Product Types**:
- Simple product (one variant)
- Product with variants (size, color)
- Configurable products

### 3. Set Up Channels

Saleor supports multiple sales channels:
- Online store (web)
- Mobile app
- Marketplaces
- Wholesale/B2B

**Configure Channel**:
1. Settings → Channels
2. Create channel
3. Set currency, taxes, shipping
4. Assign products

### 4. Configure Shipping

1. Go to **Configuration** → **Shipping**
2. Add shipping zones
3. Define shipping methods:
   - Flat rate
   - Weight-based
   - Price-based
4. Set shipping rules

### 5. Set Up Payments

Supported payment gateways:
- Stripe
- PayPal
- Adyen
- Braintree
- Authorize.net
- Custom via webhooks

### 6. Manage Orders

**Order Workflow**:
1. Customer places order
2. Payment is processed
3. Admin receives notification
4. Fulfill order (pick, pack, ship)
5. Mark as delivered
6. Handle returns/refunds

## Storefront Customization

### React Storefront Features
- Next.js 14 with App Router
- Tailwind CSS styling
- Fully responsive
- SEO optimized
- Core Web Vitals ready

### Customizing Storefront
\`\`\`bash
# The storefront is a separate container but can be customized:
# Clone the official storefront:
git clone https://github.com/saleor/react-storefront.git

# Modify components in src/app/
# Rebuild with customizations
\`\`\`

## GraphQL API

### Public API (Storefront)
- Authentication not required
- Product browsing
- Checkout creation
- Order tracking

### Admin API
- Requires JWT token
- Full CRUD operations
- App management
- Webhook configuration

### Example Queries

**Fetch Products**:
\`\`\`graphql
{
  products(first: 10, channel: "default-channel") {
    edges {
      node {
        id
        name
        pricing {
          priceRange {
            start {
              gross {
                amount
                currency
              }
            }
          }
        }
      }
    }
  }
}
\`\`\`

**Create Checkout**:
\`\`\`graphql
mutation {
  checkoutCreate(
    input: {
      channel: "default-channel"
      lines: [
        {
          quantity: 1
          variantId: "UHJvZHVjdFZhcmlhbnQ6MQ=="
        }
      ]
    }
  ) {
    checkout {
      id
      token
    }
  }
}
\`\`\`

## Integrations

### With WineJS Apps

**ConvertX**:
- Process product images
- Optimize for web
- Resize thumbnails

**Directory Lister**:
- Share product catalogs
- Export order reports
- Distribute assets

**n8n**:
- Automate order processing
- Sync with ERP/CRM
- Email notifications

**Dittofeed**:
- Marketing automation
- Abandoned cart emails
- Customer newsletters

## Development & Extensibility

### Apps & Webhooks

**Installing Apps**:
1. Go to **Apps** → **Create App**
2. Provide manifest URL
3. Authorize permissions
4. Configure webhooks

**Webhook Events**:
- ORDER_CREATED
- ORDER_FULFILLED
- PRODUCT_CREATED
- PRODUCT_UPDATED
- CUSTOMER_CREATED

### Custom Extensions

Dashboard UI Extensions (45+ mount points):
- Add custom views
- Extend forms
- Inject custom buttons

## Performance

### Caching
- Redis for task queue
- Database query optimization
- Static file CDN (optional)

### Scaling
- Horizontal scaling of API
- Read replicas for database
- Background workers

## Commands

\`\`\`bash
# View logs
winejs-saleor logs

# Restart services
winejs-saleor restart

# Check status
winejs-saleor status

# Run migrations
docker exec winejs-saleor-api python3 manage.py migrate

# Create app
docker exec winejs-saleor-api python3 manage.py create_app MY_APP --permission MANAGE_ORDERS

# Rebuild search index
docker exec winejs-saleor-api python3 manage.py update_search_vectors

# Open dashboard
winejs-saleor open
\`\`\`

## Troubleshooting

**API not responding?**
- Check logs: \`winejs-saleor logs\`
- Verify database connection
- Ensure migrations ran

**Images not showing?**
- Check media directory permissions
- Verify S3 configuration
- Clear cache

**Webhooks not triggering?**
- Check Celery worker status
- Verify endpoint reachable
- Check webhook logs

**Checkout issues?**
- Verify channel setup
- Check shipping methods
- Ensure payment gateway configured

## Support

- **Docs**: https://docs.saleor.io
- **GitHub**: https://github.com/saleor/saleor
- **Discord**: Join community
- **Dashboard**: https://github.com/saleor/saleor-dashboard
- **Storefront**: https://github.com/saleor/react-storefront

## Next Steps

1. **Add Your Products**: Start with 5-10 products
2. **Configure Payment**: Set up Stripe or PayPal
3. **Test Checkout**: Place test order
4. **Customize Storefront**: Match brand
5. **Launch Marketing**: SEO, Social media
6. **Monitor Analytics**: Track sales
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Saleor icon..."

if curl -L "$SALEOR_LOGO_URL" -o "$ICON_DIR/saleor.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/saleor.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M20 7h-4.18A3 3 0 0 0 16 5.18V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v1.18A3 3 0 0 0 8.18 7H4a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2z"/>
  <circle cx="12" cy="13" r="3"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-saleor << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
API_PORT=${API_PORT}"
DASHBOARD_PORT=${DASHBOARD_PORT}"
STOREFRONT_PORT=${STOREFRONT_PORT}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/saleor && docker compose ps
        ;;
    logs)
        docker logs winejs-saleor-api --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/saleor && docker compose restart
        echo "Saleor restarted"
        ;;
    migrate)
        echo "🔄 Running migrations..."
        docker exec winejs-saleor-api python3 manage.py migrate
        ;;
    create-app)
        shift
        if [ $# -lt 1 ]; then
            echo "Usage: winejs-saleor create-app <app_name>"
        else
            docker exec winejs-saleor-api python3 manage.py create_app "\$1" --activate
        fi
        ;;
    shell)
        docker exec -it winejs-saleor-api python3 manage.py shell
        ;;
    open-store)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/store/"
        else
            echo "Storefront: https://\${DOMAIN_NAME}/store/"
        fi
        ;;
    open-dashboard)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/dashboard/"
        else
            echo "Dashboard: https://\${DOMAIN_NAME}/dashboard/"
        fi
        ;;
    open-api)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/store/api/graphql/"
        else
            echo "GraphQL API: https://\${DOMAIN_NAME}/store/api/graphql/"
        fi
        ;;
    *)
        echo "Saleor E-commerce Platform Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-saleor open-store         # Open storefront"
        echo "  winejs-saleor open-dashboard     # Open admin dashboard"
        echo "  winejs-saleor open-api           # Open GraphQL API"
        echo "  winejs-saleor status             # Check status"
        echo "  winejs-saleor logs               # View logs"
        echo "  winejs-saleor restart            # Restart"
        echo "  winejs-saleor migrate            # Run migrations"
        echo "  winejs-saleor create-app <name>  # Create app"
        echo "  winejs-saleor shell              # Django shell"
        echo ""
        echo "Access URLs:"
        echo "  • Storefront: https://\${DOMAIN_NAME}/store/"
        echo "  • Admin: https://\${DOMAIN_NAME}/dashboard/"
        echo "  • GraphQL API: https://\${DOMAIN_NAME}/store/api/graphql/"
        echo ""
        echo "Admin Login: $ADMIN_EMAIL / (password you set)"
        echo ""
        echo "Database: PostgreSQL"
        echo "Cache/Queue: Redis"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/saleor/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-saleor

# ============= UPDATE NGINX FOR SALEOR =============
log "📝 Setting up nginx reverse proxy for Saleor..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /store" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Saleor E-commerce\n\
    location /store {\n\
        rewrite ^/store(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${STOREFRONT_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
    }\n\
    \n\
    location /dashboard {\n\
        rewrite ^/dashboard(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${DASHBOARD_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
    }\n\
    \n\
    location /store/api {\n\
        rewrite ^/store/api(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${API_PORT};\n\
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
    }\n\
    \n\
    location /store/media {\n\
        rewrite ^/store/media(/.*)?$ /media/\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${API_PORT};\n\
        expires 1y;\n\
        add_header Cache-Control \"public, immutable\";\n\
    }\n\
    \n\
    location /store/static {\n\
        rewrite ^/store/static(/.*)?$ /static/\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${API_PORT};\n\
        expires 1y;\n\
        add_header Cache-Control \"public, immutable\";\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Saleor routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_saleor.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Saleor..."

cd /opt/winejs/kasmvnc-instances/saleor
docker compose down -v 2>/dev/null

# Ask about removing data
read -p "Remove all e-commerce data (products, orders, etc.)? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /opt/winejs/apps/saleor
    rm -rf /opt/winejs/kasmvnc-instances/saleor
    rm -rf /opt/winejs/data/saleor
    log "✅ All data removed"
else
    rm -rf /opt/winejs/apps/saleor
    rm -rf /opt/winejs/kasmvnc-instances/saleor
    rm -rf /opt/winejs/data/saleor/logs
fi

rm -f /usr/local/bin/winejs-saleor

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Saleor E-commerce/,/location \/store\/static/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/store {/,/^    }/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/dashboard {/,/^    }/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/store\/api {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Saleor uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_saleor.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              SALEOR INSTALLED ON WINEJS!                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Saleor E-commerce Platform installed!"
echo ""
info "🌐 Access URLs:"
info "   • Storefront: https://$DOMAIN_NAME/store/"
info "   • Admin Dashboard: https://$DOMAIN_NAME/dashboard/"
info "   • GraphQL API: https://$DOMAIN_NAME/store/api/graphql/"
echo ""
info "🔐 Admin Login:"
info "   • Email: $ADMIN_EMAIL"
info "   • Password: [the password you set]"
echo ""
info "🛒 Configuration:"
info "   • Store Name: $STORE_NAME"
info "   • Currency: $DEFAULT_CURRENCY"
info "   • Country: $DEFAULT_COUNTRY"
info "   • Sample Data: $SAMPLE_DATA"
info "   • Debug Mode: $DEBUG_MODE"
info "   • Telemetry: $TELEMETRY"
echo ""
info "🔑 Generated Secrets (Save these):"
info "   • SECRET_KEY: $SECRET_KEY"
info "   • JWT_SECRET: $JWT_SECRET"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-saleor open-store       # Open storefront"
info "   • winejs-saleor open-dashboard   # Open admin"
info "   • winejs-saleor open-api         # Open GraphQL API"
info "   • winejs-saleor status           # Check status"
info "   • winejs-saleor logs             # View logs"
info "   • winejs-saleor migrate          # Run migrations"
info "   • winejs-saleor create-app       # Create app"
echo ""
info "📁 Data Directories:"
info "   • Database: ${DATA_DIR}/postgres"
info "   • Redis: ${DATA_DIR}/redis"
info "   • Media: ${DATA_DIR}/media"
info "   • Static: ${DATA_DIR}/static"
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/saleor/user-guide.md"
echo ""
info "📦 Architecture:"
info "   • API (Python/Django + Graphene)"
info "   • Worker (Celery for background tasks)"
info "   • Scheduler (Celery Beat)"
info "   • Dashboard (React/TypeScript)"
info "   • Storefront (Next.js)"
info "   • PostgreSQL + Redis"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_saleor.sh"
echo ""
success "✨ Saleor is ready! Start selling at https://$DOMAIN_NAME/store/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Saleor Does:

# Saleor is a headless e-commerce platform (GraphQL-first, MACH architecture):
# Key Features:
#     Headless Commerce - Frontend completely decoupled from backend
#     GraphQL API - Powerful, flexible, typed API
#     Next.js Storefront - Modern, fast, SEO-optimized
#     Admin Dashboard - Full catalog, order, customer management
#     Multi-channel - Sell across web, mobile, marketplaces
#     Multi-currency - Global selling support
#     Product Management - Complex products with variants
#     Order Management - Complete order lifecycle
#     Payment Gateways - Stripe, PayPal, Adyen, etc.
#     App Marketplace - Extend with apps and webhooks

# Architecture Components:
# Component	Technology	Purpose
# API	Python/Django + Graphene	GraphQL backend
# Worker	Celery	Async tasks (emails, webhooks)
# Scheduler	Celery Beat	Periodic tasks
# Dashboard	React/TypeScript	Admin interface
# Storefront	Next.js	Customer-facing store
# Database	PostgreSQL	Primary data store
# Cache/Queue	Redis	Caching & message broker

# Perfect For:
#     Online Stores - Launch modern e-commerce
#     DTC Brands - Direct-to-consumer sales
#     Marketplaces - Multiple vendors
#     B2B Commerce - Wholesale, bulk ordering
#     Omnichannel - Unified selling across platforms