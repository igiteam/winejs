#!/bin/bash
# ============================================
# Discount Bandit Price Tracker - WineJS Installer
# Adds Price Monitoring & Alerts to WineJS Platform
# ============================================
# App: Discount Bandit
# Category: Productivity
# Features: Price Tracking, Multi-Store Monitoring, Notifications
# ============================================

DISCOUNT_BANDIT_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/discount-bandit-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🏷️ Installing WineJS Discount Bandit Price Tracker..."

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

# ============= ASK FOR DISCOUNT BANDIT CONFIGURATION =============
echo ""
info "📝 Discount Bandit Configuration"
echo "================================"
read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

read -p "Admin username: " ADMIN_USERNAME

read -p "Theme color (Stone/Red/Blue/Green/Purple/Pink) [Stone]: " THEME_COLOR
THEME_COLOR=${THEME_COLOR:-"Stone"}

read -p "Default currency (USD/EUR/GBP/CAD/AUD) [USD]: " DEFAULT_CURRENCY
DEFAULT_CURRENCY=${DEFAULT_CURRENCY:-"USD"}

read -p "Exchange rate API key (optional): " EXCHANGE_API_KEY

read -p "Enable Telegram notifications? (true/false) [false]: " TELEGRAM_ENABLED
if [ "$TELEGRAM_ENABLED" = "true" ]; then
    read -p "Telegram Bot Token: " TELEGRAM_TOKEN
    read -p "Telegram Chat ID: " TELEGRAM_CHAT_ID
fi

read -p "Enable Ntfy notifications? (true/false) [false]: " NTFY_ENABLED
if [ "$NTFY_ENABLED" = "true" ]; then
    read -p "Ntfy Topic: " NTFY_TOPIC
    read -p "Ntfy Server URL [https://ntfy.sh]: " NTFY_SERVER
    NTFY_SERVER=${NTFY_SERVER:-"https://ntfy.sh"}
fi

read -p "Cron schedule (default: */5 * * * * for every 5 minutes) [*/5 * * * *]: " CRON_SCHEDULE
CRON_SCHEDULE=${CRON_SCHEDULE:-"*/5 * * * *"}

# Generate app key
APP_KEY=$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=9000  # Start after Directory Lister's range (8900+)
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
done

# Find available port for Discount Bandit
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Discount Bandit"
fi

log "Using port: Discount Bandit=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="discountbandit"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/discountbandit"
DATA_DIR="/opt/winejs/data/discountbandit"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{database,logs}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/discountbandit"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

# Build notification config
NOTIFICATION_CONFIG=""
if [ "$TELEGRAM_ENABLED" = "true" ]; then
    NOTIFICATION_CONFIG="$NOTIFICATION_CONFIG\n      - TELEGRAM_BOT_TOKEN=${TELEGRAM_TOKEN}"
    NOTIFICATION_CONFIG="$NOTIFICATION_CONFIG\n      - TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}"
fi

if [ "$NTFY_ENABLED" = "true" ]; then
    NOTIFICATION_CONFIG="$NOTIFICATION_CONFIG\n      - NTFY_TOPIC=${NTFY_TOPIC}"
    NOTIFICATION_CONFIG="$NOTIFICATION_CONFIG\n      - NTFY_SERVER=${NTFY_SERVER}"
fi

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Discount Bandit Price Tracker
  winejs-discountbandit:
    image: cybrarist/discount-bandit:v4
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:80"
    volumes:
      - ${DATA_DIR}/database:/app/database
      - ${DATA_DIR}/logs:/logs
    environment:
      - APP_KEY=${APP_KEY}
      - APP_TIMEZONE=UTC
      - APP_URL=https://${DOMAIN_NAME}/prices
      - ASSET_URL=https://${DOMAIN_NAME}/prices
      - DB_CONNECTION=sqlite
      - THEME_COLOR=${THEME_COLOR}
      - DEFAULT_CURRENCY=${DEFAULT_CURRENCY}
      - EXCHANGE_RATE_API_KEY=${EXCHANGE_API_KEY}
      - CRON=${CRON_SCHEDULE}
      ${NOTIFICATION_CONFIG}
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

# ============= INITIALIZE DATABASE AND CREATE ADMIN =============
log "🚀 Starting Discount Bandit container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Discount Bandit to initialize..."
sleep 20

# Create admin user via container command
log "🔐 Setting up admin user..."

docker exec winejs-discountbandit php artisan migrate --force 2>/dev/null || true

# Create admin user using artisan
docker exec winejs-discountbandit php artisan tinker << PHP_EOF
use App\Models\User;
use Illuminate\Support\Facades\Hash;

\$user = User::where('email', '${ADMIN_EMAIL}')->first();
if (!\$user) {
    \$user = new User();
    \$user->name = '${ADMIN_USERNAME}';
    \$user->email = '${ADMIN_EMAIL}';
    \$user->password = Hash::make('${ADMIN_PASSWORD}');
    \$user->email_verified_at = now();
    \$user->save();
    echo "Admin user created successfully\\n";
} else {
    echo "Admin user already exists\\n";
}
PHP_EOF

log "✅ Discount Bandit initialized"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Discount Bandit",
    "version": "latest",
    "description": "Price tracker for your favorite products across multiple stores with notifications",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/discountbandit.png",
    "category": "Productivity",
    "features": [
        "🏷️ Price Tracking",
        "🛒 30+ Supported Stores",
        "🔔 Price Drop Notifications",
        "📊 Price History Charts",
        "🎨 Customizable Themes",
        "💱 Currency Conversion",
        "👥 Multi-User Support",
        "📈 Price Drop Percentage",
        "📦 Stock Availability Alerts",
        "🏪 Custom Store Support",
        "🤖 Telegram/Ntfy/Gotify Alerts",
        "📱 Mobile Responsive"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << GUIDE_EOF
# Discount Bandit - Price Tracker User Guide

## Access
- **Main Dashboard**: https://$DOMAIN_NAME/prices/
- **Login**: Use your admin email and password

## Supported Stores (30+)

### Major Retailers
- Amazon, eBay, Walmart, Target
- Best Buy, New Egg, Costco
- AliExpress, FlipKart, Snapdeal
- Argos, Currys, DIY, FNAC
- Home Depot, Canadian Tire
- And many more!

### Regional Stores
- Ajio, Myntra, Nykaa (India)
- Noon, Otaku ME (Middle East)
- Media Markt, EPrice (Europe)
- Princess Auto (Canada)

### Custom Stores
Add ANY store by pasting product URL - system auto-detects!

## Adding Products to Track

### Method 1: Quick Add
1. Click "Add Product"
2. Paste product URL
3. System auto-fetches product info
4. Set notification rules
5. Start tracking!

### Method 2: Manual Entry
1. Enter product name
2. Set current price
3. Choose store
4. Configure rules

## Notification Rules

### Price Drop Rules
- **Desired Price**: Alert when price hits X
- **Percentage Drop**: Alert when price drops X%
- **Lowest in X days**: Alert when price hits lowest in X days
- **Any Change**: Alert on any price change

### Availability Rules
- **Stock Alert**: Notify when back in stock
- **Official Sellers Only**: Only track from official vendors

### Advanced Rules
- Combine multiple criteria
- Set different rules per store
- Apply rules to specific sellers

## Notifications Setup

### Telegram
\`\`\`bash
1. Create bot via @BotFather
2. Get bot token
3. Get chat ID
4. Configure in .env
\`\`\`

### Ntfy
\`\`\`bash
1. Choose topic name
2. Use ntfy.sh (free) or self-host
3. Subscribe on mobile/desktop
\`\`\`

### Gotify
- Self-hosted notification server
- Full control over data
- SSL support

## Dashboard Features

### Overview
- Recent price changes
- Active notifications
- Tracked products summary

### Product Details
- Price history graph
- Store comparison
- Historical lows
- Price predictions

### Multi-Store Comparison
- Compare same product across stores
- See cheapest option
- Track price trends per store

## Multi-User Management (Admin)

### User Roles
- **Admin**: Full system access
- **User**: Manage own products only

### Per-User Limits
- Set max products per user
- Control notification frequency
- Manage storage usage

### Creating Users
1. Admin panel → Users
2. Add new user
3. Set limits
4. User manages own products

## Currency Conversion

### Setup
1. Get free API key from exchangerate-api.com
2. Add to .env
3. Set default currency per user

### Features
- Real-time exchange rates
- Automatic conversion
- Multi-currency support

## Price History Analytics

### Graphs Show
- Price trend over time
- Seasonal patterns
- Best time to buy

### Export Data
- CSV export
- Price history download
- Notification logs

## Custom Store Integration

### Auto-Detect
Most stores work automatically - just paste URL!

### Manual Setup
For stores needing custom selectors:
1. Add to custom_stores config
2. Define price selector
3. Set availability indicator

### Request Support
Open GitHub issue for new store support

## Tips & Tricks

### Best Practices
- Start with 5-10 products
- Use percentage drops for volatile items
- Set desired price for must-buy items
- Enable stock alerts for hot items

### Smart Tracking
- Track competitors' pricing
- Monitor seasonal sales
- Get alerts before holidays

### Saving Money
- Combine with cashback sites
- Track price trends before large purchases
- Set alerts for multiple stores

## Integrations

### With Changedetection.io
Monitor product pages for:
- Price text changes
- Stock status changes
- New variants

### With n8n
- Trigger workflows on price drops
- Send to Discord/Slack
- Add to spreadsheets

### With Huly
- Create purchase tasks
- Link to procurement
- Track approvals

## Mobile Access

### Web Interface
- Fully responsive
- Works on any device
- No app needed

### PWA Installation
1. Visit https://$DOMAIN_NAME/prices/
2. Install as app (browser prompt)
3. Access like native app

## Commands

\`\`\`bash
# View logs
winejs-discountbandit logs

# Restart services
winejs-discountbandit restart

# Check status
winejs-discountbandit status

# Run price check manually
docker exec winejs-discountbandit php artisan schedule:run

# Open dashboard
winejs-discountbandit open
\`\`\`

## Troubleshooting

**Products not updating?**
- Check cron job is running
- Verify rate limits
- Increase timeout settings

**Notifications not sending?**
- Check API keys are valid
- Verify Telegram/Ntfy configuration
- Check notification logs

**Wrong price detected?**
- Some stores have dynamic pricing
- Add CSS selector manually
- Report issue on GitHub

## Support

- **Documentation**: https://discount-bandit.cybrarist.com
- **Discord**: Join community
- **GitHub**: Report issues
- **Email**: Support available
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Discount Bandit icon..."

if curl -L "$DISCOUNT_BANDIT_LOGO_URL" -o "$ICON_DIR/discountbandit.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/discountbandit.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/>
  <circle cx="12" cy="12" r="3"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-discountbandit << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

case "\$1" in
    status)
        docker ps | grep winejs-discountbandit
        ;;
    logs)
        docker logs winejs-discountbandit --tail 50
        ;;
    restart)
        docker restart winejs-discountbandit
        echo "Discount Bandit restarted"
        ;;
    check)
        echo "🔍 Running price checks..."
        docker exec winejs-discountbandit php artisan schedule:run
        ;;
    products)
        echo "📦 Tracking summary:"
        docker exec winejs-discountbandit php artisan tinker --execute="echo 'Products tracked: ' . \\App\\Models\\Product::count()"
        ;;
    users)
        echo "👥 User summary:"
        docker exec winejs-discountbandit php artisan tinker --execute="echo 'Total users: ' . \\App\\Models\\User::count()"
        ;;
    artisan)
        shift
        docker exec winejs-discountbandit php artisan "\$@"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/prices/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/prices/"
        fi
        ;;
    *)
        echo "Discount Bandit Price Tracker Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-discountbandit open        - Open dashboard"
        echo "  winejs-discountbandit status      - Check status"
        echo "  winejs-discountbandit logs        - View logs"
        echo "  winejs-discountbandit restart     - Restart"
        echo "  winejs-discountbandit check       - Run price checks"
        echo "  winejs-discountbandit products    - Show product stats"
        echo "  winejs-discountbandit users       - Show user stats"
        echo "  winejs-discountbandit artisan     - Run artisan commands"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/prices/"
        echo ""
        echo "Admin Login: $ADMIN_EMAIL / (password you set)"
        echo ""
        echo "Supported Stores: Amazon, eBay, Walmart, AliExpress,"
        echo "Best Buy, Target, Costco, and 30+ more!"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/discountbandit/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-discountbandit

# ============= UPDATE NGINX FOR DISCOUNT BANDIT =============
log "📝 Setting up nginx reverse proxy for Discount Bandit..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /prices" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Discount Bandit Price Tracker\n\
    location /prices {\n\
        rewrite ^/prices(/.*)?$ /\\\$1 break;\n\
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
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Discount Bandit routes"
            else
                warn "Nginx test failed, restoring backup"
                cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                nginx -t && systemctl reload nginx
            fi
        fi
    fi
fi

# ============= SETUP CRON JOBS =============
log "⏰ Setting up cron jobs for price checking..."

# Add cron job for Discount Bandit price checks
(crontab -l 2>/dev/null | grep -v "discountbandit schedule" || true; 
 echo "${CRON_SCHEDULE} /usr/bin/docker exec winejs-discountbandit php artisan schedule:run >> /var/log/discountbandit-cron.log 2>&1") | crontab -

# ============= RESTART TRANSLATOR =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_discountbandit.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Discount Bandit..."

docker stop winejs-discountbandit 2>/dev/null
docker rm winejs-discountbandit 2>/dev/null

rm -rf /opt/winejs/apps/discountbandit
rm -rf /opt/winejs/kasmvnc-instances/discountbandit
rm -rf /opt/winejs/data/discountbandit

rm -f /usr/local/bin/winejs-discountbandit

# Remove cronjobs
crontab -l 2>/dev/null | grep -v "discountbandit schedule" | crontab - 2>/dev/null || true

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Discount Bandit Price Tracker/,/location \/prices/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/prices {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Discount Bandit uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_discountbandit.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           DISCOUNT BANDIT INSTALLED ON WINEJS!                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Discount Bandit Price Tracker installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/prices/"
echo ""
info "🔐 Admin Login:"
info "   • Username: $ADMIN_USERNAME"
info "   • Email: $ADMIN_EMAIL"
info "   • Password: [the password you set]"
echo ""
info "🏷️ Key Features:"
info "   • Track prices across 30+ stores"
info "   • Price drop notifications"
info "   • Stock availability alerts"
info "   • Multi-currency support"
info "   • Custom store integration"
if [ "$TELEGRAM_ENABLED" = "true" ]; then
    info "   • Telegram notifications ✓"
fi
if [ "$NTFY_ENABLED" = "true" ]; then
    info "   • Ntfy notifications ✓"
fi
echo ""
info "⚙️ Configuration:"
info "   • Theme: $THEME_COLOR"
info "   • Default Currency: $DEFAULT_CURRENCY"
info "   • Check Schedule: $CRON_SCHEDULE"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-discountbandit open        # Open dashboard"
info "   • winejs-discountbandit status      # Check status"
info "   • winejs-discountbandit logs        # View logs"
info "   • winejs-discountbandit check       # Manual price check"
info "   • winejs-discountbandit products    # Show product stats"
info "   • winejs-discountbandit users       # Show user stats"
echo ""
info "📁 Data Directories:"
info "   • Database: ${DATA_DIR}/database"
info "   • Logs: ${DATA_DIR}/logs"
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/discountbandit/user-guide.md"
echo ""
info "🏪 Supported Stores:"
echo "   • Amazon, eBay, Walmart, Target, Best Buy"
echo "   • AliExpress, FlipKart, Snapdeal, Costco"
echo "   • Argos, Currys, FNAC, Home Depot"
echo "   • And 20+ more + custom stores!"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_discountbandit.sh"
echo ""
success "✨ Discount Bandit is ready! Start saving money at https://$DOMAIN_NAME/prices/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Discount Bandit Does:

# Discount Bandit is a price tracker that monitors products across multiple stores:
# Key Features:
#     30+ Supported Stores - Amazon, eBay, Walmart, AliExpress, Best Buy, Target, Costco, and more
#     Price Drop Alerts - Get notified when prices hit your target
#     Stock Alerts - Know when items are back in stock
#     Multi-User Support - Each user manages their own products
#     Currency Conversion - Track prices in your local currency
#     Custom Stores - Add any store manually
#     Multiple Notifications - Telegram, Ntfy, Gotify
#     Price History - View trends and historical lows

# Perfect For:
#     Savvy Shoppers - Never overpay again
#     Deal Hunters - Get alerts for price drops
#     Gift Planning - Track items for holidays
#     Business Purchasing - Monitor procurement prices
#     Collectors - Track rare item prices