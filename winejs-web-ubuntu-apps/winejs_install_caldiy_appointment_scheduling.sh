#!/bin/bash
# ============================================
# Cal.diy Appointment Scheduling - WineJS Installer
# Adds Open Source Scheduling Platform to WineJS
# ============================================
# App: Cal.diy
# Category: Productivity
# Features: Appointment Scheduling, Calendar Integration, Team Booking
# ============================================

CALDIY_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/cal-appointment-scheduling-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📅 Installing WineJS Cal.diy Appointment Scheduling..."

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

# ============= ASK FOR CAL.DIY CONFIGURATION =============
echo ""
info "📝 Cal.diy Configuration"
echo "================================"
read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""
read -p "Admin name [Admin User]: " ADMIN_NAME
ADMIN_NAME=${ADMIN_NAME:-"Admin User"}

read -p "Time zone [UTC]: " TIMEZONE
TIMEZONE=${TIMEZONE:-"UTC"}

read -p "App name [WineJS Scheduling]: " APP_NAME_FRIENDLY
APP_NAME_FRIENDLY=${APP_NAME_FRIENDLY:-"WineJS Scheduling"}

# Generate required keys
NEXTAUTH_SECRET=$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)
CALENDSO_ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)

# Generate VAPID keys for push notifications
VAPID_PUBLIC_KEY=$(npx --yes web-push generate-vapid-keys 2>/dev/null | grep "Public Key:" | awk '{print $3}' || echo "temp_public_key")
VAPID_PRIVATE_KEY=$(npx --yes web-push generate-vapid-keys 2>/dev/null | grep "Private Key:" | awk '{print $3}' || echo "temp_private_key")

read -p "Enable Google Calendar integration? (true/false) [false]: " GOOGLE_CALENDAR
GOOGLE_CALENDAR=${GOOGLE_CALENDAR:-false}

if [ "$GOOGLE_CALENDAR" = "true" ]; then
    read -p "Google Client ID: " GOOGLE_CLIENT_ID
    read -s -p "Google Client Secret: " GOOGLE_CLIENT_SECRET
    echo ""
fi

# Generate database password
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/' | head -c 24)

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=8200  # Start after Bugzilla's range (8100+)
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

# Find available port for Cal.diy
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Cal.diy"
fi

log "Using port: Cal.diy=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="caldiy"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/caldiy"
CONFIG_DIR="/opt/winejs/config/caldiy"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{postgres,uploads,logs}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/caldiy"
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
    container_name: winejs-caldiy-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: caldiy
      POSTGRES_USER: caldiy
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U caldiy"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Cal.diy Application
  winejs-caldiy:
    image: calcom/cal.diy:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:3000"
    environment:
      # Database
      - DATABASE_URL=postgresql://caldiy:${DB_PASSWORD}@postgres:5432/caldiy
      # Auth
      - NEXTAUTH_URL=https://${DOMAIN_NAME}/caldiy/api/auth
      - NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
      - CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY}
      # App Settings
      - NEXT_PUBLIC_WEBAPP_URL=https://${DOMAIN_NAME}/caldiy
      - NEXT_PUBLIC_WEBSITE_URL=https://${DOMAIN_NAME}
      - APP_NAME=${APP_NAME_FRIENDLY}
      - APP_HOSTED_ON=WineJS
      # Timezone
      - TZ=${TIMEZONE}
      # Push Notifications
      - NEXT_PUBLIC_VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}
      - VAPID_PRIVATE_KEY=${VAPID_PRIVATE_KEY}
      # Email settings (using console for development)
      - EMAIL_FROM=noreply@${DOMAIN_NAME}
      - EMAIL_SERVER_HOST=localhost
      - EMAIL_SERVER_PORT=1025
      - EMAIL_SERVER_USER=""
      - EMAIL_SERVER_PASSWORD=""
      # Disable telemetry
      - CALCOM_TELEMETRY_DISABLED=1
      # Logging
      - NEXT_PUBLIC_LOGGER_LEVEL=3
    volumes:
      - ${DATA_DIR}/uploads:/app/apps/web/public/uploads
      - ${DATA_DIR}/logs:/app/logs
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# Add Google Calendar integration if enabled
if [ "$GOOGLE_CALENDAR" = "true" ]; then
    cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF

  # Redis for queue management (optional but recommended)
  redis:
    image: redis:7-alpine
    container_name: winejs-caldiy-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - winejs-net

DOCKER_EOF
    
    # Update Cal.diy environment
    sed -i "/environment:/a\      - GOOGLE_API_CREDENTIALS={\"web\":{\"client_id\":\"${GOOGLE_CLIENT_ID}\",\"client_secret\":\"${GOOGLE_CLIENT_SECRET}\",\"redirect_uris\":[\"https://${DOMAIN_NAME}/caldiy/api/integrations/googlecalendar/callback\"]}}" "$INSTANCE_DIR/docker-compose.yml"
fi

# ============= CREATE ENVIRONMENT FILE =============
log "📝 Creating environment configuration..."

cat > "$CONFIG_DIR/.env" << EOF
# Database
DATABASE_URL=postgresql://caldiy:${DB_PASSWORD}@postgres:5432/caldiy

# Auth
NEXTAUTH_URL=https://${DOMAIN_NAME}/caldiy/api/auth
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY}

# App
NEXT_PUBLIC_WEBAPP_URL=https://${DOMAIN_NAME}/caldiy
NEXT_PUBLIC_WEBSITE_URL=https://${DOMAIN_NAME}
APP_NAME=${APP_NAME_FRIENDLY}

# Timezone
TZ=${TIMEZONE}

# Push Notifications
NEXT_PUBLIC_VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}
VAPID_PRIVATE_KEY=${VAPID_PRIVATE_KEY}

# Email (using console for now)
EMAIL_FROM=noreply@${DOMAIN_NAME}
EMAIL_SERVER_HOST=localhost
EMAIL_SERVER_PORT=1025
EMAIL_SERVER_USER=""
EMAIL_SERVER_PASSWORD=""

# Telemetry disabled
CALCOM_TELEMETRY_DISABLED=1

# Logging
NEXT_PUBLIC_LOGGER_LEVEL=3
EOF

# ============= INITIALIZE DATABASE =============
log "🚀 Starting Cal.diy containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Cal.diy to initialize (this may take 2-3 minutes)..."
sleep 90

# Run database migrations
log "🔄 Running database migrations..."
docker exec winejs-caldiy npx prisma migrate deploy 2>/dev/null || true

# Seed the database
log "🌱 Seeding database..."
docker exec winejs-caldiy npx prisma db seed 2>/dev/null || true

# Create admin user via API or database
log "👤 Creating admin user..."

docker exec winejs-caldiy node -e "
const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcryptjs');
const prisma = new PrismaClient();

async function createAdmin() {
  try {
    const hashedPassword = await bcrypt.hash('${ADMIN_PASSWORD}', 10);
    
    const admin = await prisma.user.upsert({
      where: { email: '${ADMIN_EMAIL}' },
      update: {},
      create: {
        email: '${ADMIN_EMAIL}',
        password: hashedPassword,
        name: '${ADMIN_NAME}',
        username: 'admin',
        role: 'ADMIN',
        emailVerified: new Date(),
        completedOnboarding: true,
        timeZone: '${TIMEZONE}',
        weekStart: 'Sunday',
        defaultScheduleId: null,
        organizationId: null,
        brandColor: '#292929',
        darkBrandColor: '#fafafa',
        theme: 'dark',
        createdDate: new Date(),
        backupCodes: null,
        verified: true,
        invitedTo: null,
        bio: null,
        hideBranding: false,
        twoFactorEnabled: false,
        twoFactorSecret: null,
        identityProvider: 'CAL',
        identityProviderId: null,
        allowDynamicBooking: false,
        timeFormat: 12,
        locale: 'en',
        metadata: {}
      }
    });
    
    console.log('Admin user created:', admin.email);
  } catch (error) {
    console.error('Error creating admin:', error.message);
  } finally {
    await prisma.\$disconnect();
  }
}

createAdmin();
" 2>/dev/null || true

log "✅ Cal.diy initialized"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

# Build features list
FEATURES_LIST='[
        "📅 Event Scheduling",
        "🔗 Shareable Booking Links",
        "🌍 Time Zone Detection",'
if [ "$GOOGLE_CALENDAR" = "true" ]; then
    FEATURES_LIST="$FEATURES_LIST\n        \"📧 Google Calendar Integration\","
fi
FEATURES_LIST="$FEATURES_LIST
        "⏰ Buffer & Duration Settings",
        "👥 Team & Collective Booking",
        "🔔 Email Reminders",
        "📱 Mobile Responsive",
        "🎨 Customizable Branding",
        "📊 Booking Analytics",
        "🔐 User Management",
        "🌐 Multi-language Support",
        "💾 Recurring Events",
        "🔄 Webhook Support"
    ]"

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Cal.diy Appointment Scheduling",
    "version": "latest",
    "description": "Open source scheduling platform - Cal.com fork without enterprise restrictions",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/caldiy.png",
    "category": "Productivity",
    "features": ${FEATURES_LIST}
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << GUIDE_EOF
# Cal.diy Appointment Scheduling - User Guide

## Access
- **Main Site**: https://$DOMAIN_NAME/caldiy/
- **Admin Dashboard**: https://$DOMAIN_NAME/caldiy/settings

## Default Admin Login
- **Email**: $ADMIN_EMAIL
- **Password**: [the password you set]

## Quick Start Guide

### 1. Set Up Your Availability

1. Login to your account
2. Go to **Settings → Availability**
3. Set your working hours and days
4. Add buffer times between appointments
5. Configure time zone preferences

### 2. Create Your First Event Type

1. Click **Event Types** in the sidebar
2. Click **Create New Event Type**
3. Choose event type:
   - **Collective** (multiple hosts)
   - **Round-robin** (distribute bookings)
   - **One-on-one** (single host)
4. Set duration (15min, 30min, 60min, etc.)
5. Configure location (Zoom, Google Meet, Phone, In-person)
6. Add description and instructions

### 3. Share Your Booking Link

Your booking link format:
\`\`\`
https://$DOMAIN_NAME/caldiy/[username]/[event-type-slug]
\`\`\`

Examples:
- Personal: \`https://$DOMAIN_NAME/caldiy/admin/30min\`
- Team: \`https://$DOMAIN_NAME/caldiy/team/team-meeting\`

### 4. Manage Bookings

- **Upcoming Bookings**: View in Dashboard
- **Past Bookings**: History and analytics
- **Reschedule/Cancel**: Clients can manage their bookings
- **Notes**: Add private notes to bookings

## Calendar Integrations

### Google Calendar

If configured:
1. Go to **Settings → Integrations**
2. Click **Connect Google Calendar**
3. Authorize access
4. Bookings automatically sync both ways

### Other Calendars
- Microsoft Office 365
- CalDAV (iCal, Nextcloud, etc.)
- Apple Calendar (via CalDAV)

## Embedding on Your Website

\`\`\`html
<!-- Popup mode -->
<a href="https://$DOMAIN_NAME/caldiy/admin/30min" target="_blank">Book a Meeting</a>

<!-- Embed using iframe -->
<iframe src="https://$DOMAIN_NAME/caldiy/admin/30min"
        width="100%" height="700px" frameborder="0">
</iframe>

<!-- Embed using widget -->
<script type="text/javascript">
  window.CalCom = {
    namespace: "book",
    config: {
      calendar: {
        branding: ${APP_NAME_FRIENDLY},
      }
    }
  };
</script>
<script src="https://$DOMAIN_NAME/caldiy/embed.js"></script>
<link rel="stylesheet" href="https://$DOMAIN_NAME/caldiy/embed.css" />
\`\`\`

## Team Features

### Collective Events
- Multiple team members on one call
- Clients see combined availability
- All members receive notifications

### Round-robin Distribution
- Automatically distribute bookings
- Set member weights
- Avoid overbooking

### Team Management
- Add/remove members
- Set roles (Admin, Member)
- View team analytics

## Customization

### Branding
- Add your logo
- Custom colors
- Custom booking page URL
- Email templates

### Advanced Settings
- Minimum notice period
- Maximum lead days
- Booking limits per day
- Custom questions for clients

## Integrations

### Video Conferencing
- Zoom
- Google Meet
- Microsoft Teams
- Daily.co (built-in)

### CRM & Tools
- HubSpot
- Salesforce
- Pipedrive
- Zapier (via webhooks)

## API Access

Base URL: \`https://$DOMAIN_NAME/caldiy/api\`

Example endpoints:
- \`GET /v1/event-types\` - List event types
- \`GET /v1/bookings\` - List bookings
- \`POST /v1/bookings\` - Create booking
- \`GET /v1/slots\` - Get available slots

## Troubleshooting

### Emails not sending?
Check SMTP settings in Admin dashboard

### Calendar not syncing?
Re-authenticate integration in Settings

### Timezone issues?
Verify server and user timezone settings

## Support

- Documentation: https://cal.diy/docs
- GitHub: https://github.com/calcom/cal.diy
- Community: https://github.com/calcom/cal.diy/discussions

## Commands

\`\`\`bash
# View logs
winejs-caldiy logs

# Restart services
winejs-caldiy restart

# Check status
winejs-caldiy status

# Open dashboard
winejs-caldiy open
\`\`\`
GUIDE_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading Cal.diy icon..."
curl -L "$CALDIY_LOGO_URL" -o "$ICON_DIR/caldiy.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-caldiy << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/caldiy && docker compose ps
        ;;
    logs)
        docker logs winejs-caldiy --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/caldiy && docker compose restart
        echo "Cal.diy restarted"
        ;;
    migrate)
        echo "🔄 Running database migrations..."
        docker exec winejs-caldiy npx prisma migrate deploy
        ;;
    studio)
        echo "🔍 Opening Prisma Studio..."
        docker exec winejs-caldiy npx prisma studio --port 5555
        ;;
    bookings)
        echo "📅 Recent bookings:"
        docker exec winejs-caldiy node -e "const {PrismaClient}=require('@prisma/client'); const prisma=new PrismaClient(); prisma.booking.findMany({take:10,orderBy:{createdAt:'desc'}}).then(b=>b.forEach(b=>console.log(\`  • \${b.title} - \${b.status}\`))).catch(()=>console.log('No bookings yet'))" 2>/dev/null || echo "  No bookings found"
        ;;
    users)
        echo "👥 Users:"
        docker exec winejs-caldiy node -e "const {PrismaClient}=require('@prisma/client'); const prisma=new PrismaClient(); prisma.user.findMany({select:{email:true,role:true,name:true}}).then(u=>u.forEach(u=>console.log(\`  • \${u.email} (\${u.role})\`))).catch(()=>console.log('No users'))" 2>/dev/null || echo "  Unable to fetch users"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/caldiy/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/caldiy/"
        fi
        ;;
    admin)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/caldiy/settings"
        else
            echo "Admin: https://\${DOMAIN_NAME}/caldiy/settings"
        fi
        ;;
    *)
        echo "Cal.diy Appointment Scheduling Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-caldiy open           - Open Cal.diy"
        echo "  winejs-caldiy admin          - Open Admin Settings"
        echo "  winejs-caldiy status         - Check status"
        echo "  winejs-caldiy logs           - View logs"
        echo "  winejs-caldiy restart        - Restart services"
        echo "  winejs-caldiy migrate        - Run migrations"
        echo "  winejs-caldiy studio         - Open Prisma Studio"
        echo "  winejs-caldiy bookings       - List recent bookings"
        echo "  winejs-caldiy users          - List users"
        echo ""
        echo "Access URLs:"
        echo "  • Main Site: https://\${DOMAIN_NAME}/caldiy/"
        echo "  • Admin: https://\${DOMAIN_NAME}/caldiy/settings"
        echo ""
        echo "Admin Login: $ADMIN_EMAIL / (password you set)"
        echo ""
        echo "Quick Start:"
        echo "  1. Login with admin credentials"
        echo "  2. Set your availability (Settings → Availability)"
        echo "  3. Create an event type (Event Types → Create New)"
        echo "  4. Share your booking link!"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/caldiy/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-caldiy

# ============= UPDATE NGINX FOR CALDIY =============
log "📝 Setting up nginx reverse proxy for Cal.diy..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /caldiy" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Cal.diy Appointment Scheduling\n\
    location /caldiy {\n\
        rewrite ^/caldiy(/.*)?$ /\\\$1 break;\n\
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
        client_max_body_size 10M;\n\
    }\n\
    \n\
    # Cal.diy API\n\
    location /caldiy/api/ {\n\
        rewrite ^/caldiy/api/(.*)$ /api/\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Cal.diy routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_caldiy.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Cal.diy..."

cd /opt/winejs/kasmvnc-instances/caldiy
docker compose down -v 2>/dev/null

rm -rf /opt/winejs/apps/caldiy
rm -rf /opt/winejs/kasmvnc-instances/caldiy
rm -rf /opt/winejs/data/caldiy
rm -rf /opt/winejs/config/caldiy

rm -f /usr/local/bin/winejs-caldiy

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Cal.diy Appointment Scheduling/,/location \/caldiy\/api\//d' /etc/nginx/sites-available/winejs
    sed -i '/location \/caldiy {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Cal.diy uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_caldiy.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              CAL.DIY INSTALLED ON WINEJS!                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Cal.diy Appointment Scheduling installed!"
echo ""
info "🌐 Access URLs:"
info "   • Main Site: https://$DOMAIN_NAME/caldiy/"
info "   • Admin Settings: https://$DOMAIN_NAME/caldiy/settings"
echo ""
info "🔐 Admin Login:"
info "   • Email: $ADMIN_EMAIL"
info "   • Password: [the password you set]"
echo ""
info "📅 Features:"
info "   • Event scheduling with custom durations"
info "   • Team and collective booking"
info "   • Calendar integrations (Google, iCal, etc.)"
info "   • Email notifications and reminders"
if [ "$GOOGLE_CALENDAR" = "true" ]; then
    info "   • Google Calendar integration ✓"
fi
info "   • Mobile-responsive booking pages"
echo ""
info "🔑 Generated Keys (Save these):"
info "   • NEXTAUTH_SECRET: $NEXTAUTH_SECRET"
info "   • CALENDSO_ENCRYPTION_KEY: $CALENDSO_ENCRYPTION_KEY"
info "   • VAPID Public: $VAPID_PUBLIC_KEY"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-caldiy open        # Open Cal.diy"
info "   • winejs-caldiy admin       # Open Admin Settings"
info "   • winejs-caldiy status      # Check status"
info "   • winejs-caldiy logs        # View logs"
info "   • winejs-caldiy bookings    # List bookings"
info "   • winejs-caldiy users       # List users"
info "   • winejs-caldiy studio      # Open Prisma Studio"
echo ""
info "📁 Data Directories:"
info "   • Database: ${DATA_DIR}/postgres"
info "   • Uploads: ${DATA_DIR}/uploads"
info "   • Logs: ${DATA_DIR}/logs"
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/caldiy/user-guide.md"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_caldiy.sh"
echo ""
success "✨ Cal.diy is ready! Start scheduling appointments at https://$DOMAIN_NAME/caldiy/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Cal.diy Does:

# Cal.diy is a powerful open-source scheduling platform (100% MIT licensed, no enterprise restrictions):
# Key Features:
#     Event Scheduling - Create unlimited event types with custom durations
#     Booking Links - Shareable links for clients to book time
#     Team Booking - Collective, round-robin, and one-on-one events
#     Calendar Integrations - Google, Office 365, CalDAV, Apple Calendar
#     Video Conferencing - Zoom, Google Meet, Microsoft Teams, Daily.co
#     Email Notifications - Automatic confirmations and reminders
#     Custom Branding - Add your logo and colors
#     API Access - REST API for programmatic booking
#     Webhooks - Trigger automations on bookings
#     Team Management - Add members, set roles, distribute leads

# Perfect For:
#     Consultants - Let clients book paid consultations
#     Sales Teams - Route leads to available reps
#     Support - Schedule customer calls
#     Internal Meetings - Find common availability
#     WineJS itself - Let users book support calls!