#!/bin/bash
# ============================================
# ChiefOnboarding Platform - WineJS Installer
# Adds Employee Onboarding System to WineJS
# ============================================
# App: ChiefOnboarding
# Category: Productivity
# Features: Employee Onboarding, Task Management, Slack Integration
# ============================================

CHIEFONBOARDING_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/chiefonboarding-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "👋 Installing WineJS ChiefOnboarding Platform..."

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

# ============= ASK FOR CHIEFONBOARDING CONFIGURATION =============
echo ""
info "📝 ChiefOnboarding Configuration"
echo "================================"
read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""
read -p "Company name: " COMPANY_NAME

read -p "Enable Slack integration? (true/false) [false]: " SLACK_ENABLED
if [ "$SLACK_ENABLED" = "true" ]; then
    read -p "Slack Bot Token: " SLACK_TOKEN
    read -p "Slack Signing Secret: " SLACK_SIGNING_SECRET
fi

read -p "Enable email notifications? (true/false) [true]: " EMAIL_ENABLED
EMAIL_ENABLED=${EMAIL_ENABLED:-true}

if [ "$EMAIL_ENABLED" = "true" ]; then
    read -p "SMTP Server: " SMTP_HOST
    read -p "SMTP Port [587]: " SMTP_PORT
    SMTP_PORT=${SMTP_PORT:-587}
    read -p "SMTP User: " SMTP_USER
    read -s -p "SMTP Password: " SMTP_PASSWORD
    echo ""
    read -p "From Email: " FROM_EMAIL
fi

# Generate secret key
SECRET_KEY=$(openssl rand -base64 32 | tr -d '\n=+/' | head -c 32)

# Generate database password
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/' | head -c 24)

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=8600  # Start after Chhoto URL's range (8500+)
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

# Find available port for ChiefOnboarding
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for ChiefOnboarding"
fi

log "Using port: ChiefOnboarding=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="chiefonboarding"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/chiefonboarding"
DATA_DIR="/opt/winejs/data/chiefonboarding"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"
mkdir -p "$DATA_DIR"/{pgdata,site,site_data}

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/chiefonboarding"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

# Build email config
EMAIL_CONFIG=""
if [ "$EMAIL_ENABLED" = "true" ]; then
    EMAIL_CONFIG="$EMAIL_CONFIG\n      - EMAIL_HOST=${SMTP_HOST}"
    EMAIL_CONFIG="$EMAIL_CONFIG\n      - EMAIL_PORT=${SMTP_PORT}"
    EMAIL_CONFIG="$EMAIL_CONFIG\n      - EMAIL_HOST_USER=${SMTP_USER}"
    EMAIL_CONFIG="$EMAIL_CONFIG\n      - EMAIL_HOST_PASSWORD=${SMTP_PASSWORD}"
    EMAIL_CONFIG="$EMAIL_CONFIG\n      - EMAIL_USE_TLS=True"
    EMAIL_CONFIG="$EMAIL_CONFIG\n      - DEFAULT_FROM_EMAIL=${FROM_EMAIL}"
fi

# Build Slack config
SLACK_CONFIG=""
if [ "$SLACK_ENABLED" = "true" ]; then
    SLACK_CONFIG="$SLACK_CONFIG\n      - SLACK_BOT_TOKEN=${SLACK_TOKEN}"
    SLACK_CONFIG="$SLACK_CONFIG\n      - SLACK_SIGNING_SECRET=${SLACK_SIGNING_SECRET}"
fi

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # PostgreSQL Database
  db:
    image: postgres:latest
    container_name: winejs-chiefonboarding-db
    restart: unless-stopped
    expose:
      - "5432"
    volumes:
      - ${DATA_DIR}/pgdata:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=chiefonboarding
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ChiefOnboarding Web Application
  web:
    image: chiefonboarding/chiefonboarding:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:8000"
    environment:
      - SECRET_KEY=${SECRET_KEY}
      - DATABASE_URL=postgres://postgres:${DB_PASSWORD}@db:5432/chiefonboarding
      - ALLOWED_HOSTS=${DOMAIN_NAME},localhost,127.0.0.1
      - CSRF_TRUSTED_ORIGINS=https://${DOMAIN_NAME}
      - COMPANY_NAME=${COMPANY_NAME}
      - SITE_URL=https://${DOMAIN_NAME}/onboarding${EMAIL_CONFIG}${SLACK_CONFIG}
    volumes:
      - ${DATA_DIR}/site:/site
      - ${DATA_DIR}/site_data:/site_data
    depends_on:
      db:
        condition: service_healthy
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= INITIALIZE DATABASE AND CREATE ADMIN =============
log "🚀 Starting ChiefOnboarding containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for ChiefOnboarding to initialize (this may take 1-2 minutes)..."
sleep 45

# Run migrations and create admin user
log "🔧 Setting up database and admin user..."

# Create admin user via Django management command
docker exec winejs-chiefonboarding python manage.py migrate --noinput 2>/dev/null || true
docker exec winejs-chiefonboarding python manage.py collectstatic --noinput 2>/dev/null || true

# Create superuser
docker exec winejs-chiefonboarding python manage.py shell << PYTHON_EOF
from django.contrib.auth.models import User
from django.contrib.auth.hashers import make_password

if not User.objects.filter(username='admin').exists():
    User.objects.create(
        username='admin',
        email='${ADMIN_EMAIL}',
        password=make_password('${ADMIN_PASSWORD}'),
        is_staff=True,
        is_superuser=True,
        is_active=True
    )
    print("Admin user created successfully")
else:
    print("Admin user already exists")
PYTHON_EOF

log "✅ ChiefOnboarding initialized"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "ChiefOnboarding",
    "version": "latest",
    "description": "Free & open source employee onboarding platform with Slack integration",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/chiefonboarding.png",
    "category": "Productivity",
    "features": [
        "👋 Employee Onboarding",
        "✅ Task Management",
        "📚 Knowledge Base",
        "🏆 Badges & Rewards",
        "👥 Team Introductions",
        "📅 Pre-boarding Pages",
        "⏰ Timezone Support",
        "🌍 Multi-language (10+ languages)",
        "🤖 Slack Bot Integration",
        "📧 Email Notifications",
        "🔄 Webhook Triggers",
        "📊 Progress Tracking",
        "🎨 Customizable Branding",
        "🔐 Self-hosted & Private"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << GUIDE_EOF
# ChiefOnboarding - Employee Onboarding Guide

## Access
- **Main Dashboard**: https://$DOMAIN_NAME/onboarding/
- **Admin Panel**: https://$DOMAIN_NAME/onboarding/admin/

## Default Admin Login
- **Username**: admin
- **Password**: [the password you set]
- **Email**: $ADMIN_EMAIL

## Quick Start Guide

### 1. Set Up Your Company
- Login to the admin panel
- Go to Settings → Company Settings
- Upload your logo and set branding colors
- Configure your timezone

### 2. Create Your First Onboarding Sequence

1. Go to **Sequences** → **Create New Sequence**
2. Add tasks for new hires:
   - Read company handbook
   - Set up email signature
   - Complete IT setup form
   - Introduction meetings
3. Set timing (day 1, week 1, month 1)
4. Assign to departments

### 3. Add Resources

1. Go to **Resources** → **Add Resource**
2. Upload documents:
   - Employee handbook
   - Benefits guide
   - IT policies
   - Training videos
3. Organize by categories
4. Set required vs optional

### 4. Invite New Hires

1. Click **Add New Hire**
2. Enter their email and start date
3. Select onboarding sequence
4. Choose timezone
5. Send invitation

## Pre-boarding

Send pre-boarding pages before day 1:
- Welcome message from CEO
- Required paperwork
- Equipment shipping status
- First week schedule

## Slack Integration

$([ "$SLACK_ENABLED" = "true" ] && echo "Slack is ENABLED. New hires can:
- Complete tasks via Slack
- Ask questions in #onboarding channel
- Get daily reminders
- Receive welcome messages

To set up Slack:
1. Go to Settings → Integrations
2. Add Slack Bot token
3. Configure channels" || echo "Slack is DISABLED. To enable, reconfigure with Slack credentials.")

## Email Notifications

$([ "$EMAIL_ENABLED" = "true" ] && echo "Email notifications are ENABLED:
- Welcome emails
- Task reminders
- Completion confirmations
- Admin alerts

SMTP Configuration:
- Server: $SMTP_HOST:$SMTP_PORT
- From: $FROM_EMAIL" || echo "Email notifications are DISABLED. To enable, reconfigure with SMTP credentials.")

## Team Collaboration

### Admin Tasks
Assign internal tasks to team members:
- IT: Setup laptop
- HR: Benefits enrollment
- Manager: Schedule 1:1s
- Facilities: Assign desk

### Introductions
Automatically introduce new hires to:
- Team members
- Mentors
- Department heads
- Cross-functional partners

## Tracking Progress

Monitor new hire progress:
- Task completion rates
- Time to completion
- Resource engagement
- Survey responses

## API & Webhooks

Trigger actions when:
- New hire added
- Task completed
- Sequence finished
- Document reviewed

Webhook URL: \`https://$DOMAIN_NAME/onboarding/api/webhooks/\`

## Customization

### Branding
- Upload your logo
- Set primary colors
- Custom email templates
- White-label the platform

### Content
- Add custom tasks
- Create resource categories
- Build pre-boarding pages
- Design badges

## Best Practices

### Before Day 1
- Send welcome kit
- Ship equipment
- Share pre-boarding materials
- Set up accounts

### Week 1
- IT orientation
- Team introductions
- Role training
- Benefits enrollment

### Month 1
- Goal setting
- 60-day check-in
- Culture integration
- Ongoing education

## Integrations

Connect with:
- Slack/Discord/Microsoft Teams
- Google Workspace
- Microsoft 365
- HRIS systems (via API)
- Custom webhooks

## Reports

View analytics:
- Onboarding completion rates
- Task timing
- Department comparisons
- New hire satisfaction

## Commands

\`\`\`bash
# View logs
winejs-chiefonboarding logs

# Restart services
winejs-chiefonboarding restart

# Check status
winejs-chiefonboarding status

# Create admin user
winejs-chiefonboarding create-admin

# Open dashboard
winejs-chiefonboarding open
\`\`\`
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up ChiefOnboarding icon..."

if curl -L "$CHIEFONBOARDING_LOGO_URL" -o "$ICON_DIR/chiefonboarding.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/chiefonboarding.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/>
  <circle cx="12" cy="7" r="4"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-chiefonboarding << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/chiefonboarding && docker compose ps
        ;;
    logs)
        docker logs winejs-chiefonboarding --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/chiefonboarding && docker compose restart
        echo "ChiefOnboarding restarted"
        ;;
    migrate)
        echo "🔄 Running database migrations..."
        docker exec winejs-chiefonboarding python manage.py migrate
        ;;
    create-admin)
        echo "👤 Creating admin user..."
        docker exec -it winejs-chiefonboarding python manage.py createsuperuser
        ;;
    shell)
        docker exec -it winejs-chiefonboarding python manage.py shell
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/onboarding/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/onboarding/"
        fi
        ;;
    admin)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/onboarding/admin/"
        else
            echo "Admin: https://\${DOMAIN_NAME}/onboarding/admin/"
        fi
        ;;
    *)
        echo "ChiefOnboarding Employee Onboarding Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-chiefonboarding open           - Open ChiefOnboarding"
        echo "  winejs-chiefonboarding admin          - Open Admin Panel"
        echo "  winejs-chiefonboarding status         - Check status"
        echo "  winejs-chiefonboarding logs           - View logs"
        echo "  winejs-chiefonboarding restart        - Restart services"
        echo "  winejs-chiefonboarding migrate        - Run migrations"
        echo "  winejs-chiefonboarding create-admin   - Create admin user"
        echo "  winejs-chiefonboarding shell          - Django shell"
        echo ""
        echo "Access URLs:"
        echo "  • Main Dashboard: https://\${DOMAIN_NAME}/onboarding/"
        echo "  • Admin Panel: https://\${DOMAIN_NAME}/onboarding/admin/"
        echo ""
        echo "Admin Login: admin / (password you set)"
        echo "Admin Email: $ADMIN_EMAIL"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/chiefonboarding/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-chiefonboarding

# ============= UPDATE NGINX FOR CHIEFONBOARDING =============
log "📝 Setting up nginx reverse proxy for ChiefOnboarding..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /onboarding" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # ChiefOnboarding Employee Onboarding\n\
    location /onboarding {\n\
        rewrite ^/onboarding(/.*)?$ /\\\$1 break;\n\
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
        client_max_body_size 20M;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with ChiefOnboarding routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_chiefonboarding.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling ChiefOnboarding..."

cd /opt/winejs/kasmvnc-instances/chiefonboarding
docker compose down -v 2>/dev/null

rm -rf /opt/winejs/apps/chiefonboarding
rm -rf /opt/winejs/kasmvnc-instances/chiefonboarding
rm -rf /opt/winejs/data/chiefonboarding

rm -f /usr/local/bin/winejs-chiefonboarding

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# ChiefOnboarding Employee Onboarding/,/location \/onboarding/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/onboarding {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ ChiefOnboarding uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_chiefonboarding.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           CHIEFONBOARDING INSTALLED ON WINEJS!                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ ChiefOnboarding Employee Onboarding Platform installed!"
echo ""
info "🌐 Access URLs:"
info "   • Main Dashboard: https://$DOMAIN_NAME/onboarding/"
info "   • Admin Panel: https://$DOMAIN_NAME/onboarding/admin/"
echo ""
info "🔐 Admin Login:"
info "   • Username: admin"
info "   • Password: [the password you set]"
info "   • Email: $ADMIN_EMAIL"
echo ""
info "👋 Key Features:"
info "   • Employee onboarding sequences"
info "   • Task management & tracking"
info "   • Resource/knowledge base"
info "   • Pre-boarding pages"
if [ "$SLACK_ENABLED" = "true" ]; then
    info "   • Slack integration ✓"
fi
if [ "$EMAIL_ENABLED" = "true" ]; then
    info "   • Email notifications ✓"
fi
info "   • Multi-language support"
info "   • Customizable branding"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-chiefonboarding open        # Open dashboard"
info "   • winejs-chiefonboarding admin       # Open admin panel"
info "   • winejs-chiefonboarding status      # Check status"
info "   • winejs-chiefonboarding logs        # View logs"
info "   • winejs-chiefonboarding migrate     # Run migrations"
info "   • winejs-chiefonboarding create-admin # Create admin user"
echo ""
info "📁 Data Directories:"
info "   • Database: ${DATA_DIR}/pgdata"
info "   • Site Data: ${DATA_DIR}/site"
info "   • Uploads: ${DATA_DIR}/site_data"
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/chiefonboarding/user-guide.md"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_chiefonboarding.sh"
echo ""
success "✨ ChiefOnboarding is ready! Start onboarding employees at https://$DOMAIN_NAME/onboarding/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What ChiefOnboarding Does:

# ChiefOnboarding is a comprehensive employee onboarding platform:
# Key Features:
#     Onboarding Sequences - Drip-feed tasks over time
#     Task Management - Track what new hires need to complete
#     Resource Library - Knowledge base & training materials
#     Pre-boarding - Welcome new hires before day 1
#     Badges & Rewards - Gamification to keep motivation high
#     Team Introductions - Automatically introduce new hires
#     Slack Integration - Complete tasks via Slack bot
#     Multi-language - 10+ languages supported
#     Custom Branding - White-label completely
#     Webhooks - Trigger automations

# Perfect For:
#     HR Teams - Standardize onboarding across the company
#     Growing Startups - Scale onboarding as you hire
#     Remote Companies - Digital-first onboarding experience
#     WineJS itself - Onboard new team members!