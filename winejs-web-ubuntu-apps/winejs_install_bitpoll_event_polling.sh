#!/bin/bash
# ============================================
# Bitpoll Voting System - WineJS Installer
# Adds Polling & Voting Platform to WineJS
# ============================================
# App: Bitpoll
# Category: Productivity
# Features: Polls, Voting, Surveys, Event Planning
# ============================================

BITPOLL_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/bitpoll-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📊 Installing WineJS Bitpoll Voting System..."

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

# ============= ASK FOR BITPOLL CONFIGURATION =============
echo ""
info "📝 Bitpoll Configuration"
echo "================================"
read -p "Admin email: " ADMIN_EMAIL
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

read -p "Site name [WineJS Polls]: " SITE_NAME
SITE_NAME=${SITE_NAME:-"WineJS Polls"}

read -p "Enable LDAP authentication? (true/false) [false]: " LDAP_ENABLED
LDAP_ENABLED=${LDAP_ENABLED:-false}

if [ "$LDAP_ENABLED" = "true" ]; then
    read -p "LDAP Server URL: " LDAP_SERVER
    read -p "LDAP Base DN: " LDAP_BASE_DN
    read -p "LDAP Bind DN: " LDAP_BIND_DN
    read -s -p "LDAP Bind Password: " LDAP_BIND_PASSWORD
    echo ""
fi

read -p "Enable Sentry error reporting? (true/false) [false]: " SENTRY_ENABLED
SENTRY_ENABLED=${SENTRY_ENABLED:-false}

if [ "$SENTRY_ENABLED" = "true" ]; then
    read -p "Sentry DSN: " SENTRY_DSN
fi

# Generate secure secret key
SECRET_KEY=$(openssl rand -base64 50 | tr -d '\n=+/' | head -c 50)

# Generate database password
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '\n=+/' | head -c 24)

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=8100  # Start after Pretix's range (8000+)
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

# Find available port for Bitpoll web interface
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Bitpoll"
fi

log "Using port: Bitpoll=$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="bitpoll"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/bitpoll"
CONFIG_DIR="/opt/winejs/config/bitpoll"
STATIC_DIR="$DATA_DIR/static"
LOG_DIR="$DATA_DIR/log"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$STATIC_DIR" "$LOG_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/bitpoll"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE BITPOLL SETTINGS =============
log "📝 Creating Bitpoll settings..."

# Build LDAP config
LDAP_CONFIG=""
if [ "$LDAP_ENABLED" = "true" ]; then
    LDAP_CONFIG="
# LDAP Authentication
AUTH_LDAP_SERVER_URI = \"$LDAP_SERVER\"
AUTH_LDAP_BASE_DN = \"$LDAP_BASE_DN\"
AUTH_LDAP_BIND_DN = \"$LDAP_BIND_DN\"
AUTH_LDAP_BIND_PASSWORD = \"$LDAP_BIND_PASSWORD\"
AUTH_LDAP_USER_SEARCH = LDAPSearch(\"$LDAP_BASE_DN\", ldap.SCOPE_SUBTREE, \"(uid=%(user)s)\")
AUTH_LDAP_ALWAYS_UPDATE_USER = True
AUTHENTICATION_BACKENDS = ['django_auth_ldap.backend.LDAPBackend', 'django.contrib.auth.backends.ModelBackend']"
fi

# Build Sentry config
SENTRY_CONFIG=""
if [ "$SENTRY_ENABLED" = "true" ]; then
    SENTRY_CONFIG="
# Sentry Error Reporting
import sentry_sdk
from sentry_sdk.integrations.django import DjangoIntegration

sentry_sdk.init(
    dsn=\"$SENTRY_DSN\",
    integrations=[DjangoIntegration()],
    traces_sample_rate=1.0,
    send_default_pii=True
)"
fi

cat > "$CONFIG_DIR/settings.py" << EOF
# Bitpoll Settings - WineJS Installer
import os
from django.utils.translation import gettext_lazy as _

# Security
SECRET_KEY = '$SECRET_KEY'
DEBUG = False
ALLOWED_HOSTS = ['$DOMAIN_NAME', 'localhost', '127.0.0.1']
CSRF_TRUSTED_ORIGINS = ['https://$DOMAIN_NAME']

# Application definition
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'bitpoll.base',
    'bitpoll.poll',
    'bitpoll.user',
    'bitpoll.dates',
    'bitpoll.ldap_sync',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.locale.LocaleMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'bitpoll.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'bitpoll.wsgi.application'

# Database
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'bitpoll',
        'USER': 'bitpoll',
        'PASSWORD': '$DB_PASSWORD',
        'HOST': 'postgres',
        'PORT': '5432',
    }
}

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

# Internationalization
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_L10N = True
USE_TZ = True
LANGUAGES = [
    ('en', _('English')),
    ('de', _('German')),
]

LOCALE_PATHS = [
    os.path.join(BASE_DIR, 'locale'),
]

# Static files (CSS, JavaScript, Images)
STATIC_URL = '/static/'
STATIC_ROOT = '/opt/static'
STATICFILES_DIRS = []

# Media files
MEDIA_URL = '/media/'
MEDIA_ROOT = '/opt/media'

# Session
SESSION_ENGINE = 'django.contrib.sessions.backends.db'
SESSION_COOKIE_AGE = 1209600  # 2 weeks
SESSION_COOKIE_SECURE = True
SESSION_COOKIE_HTTPONLY = True

# CSRF
CSRF_COOKIE_SECURE = True
CSRF_COOKIE_HTTPONLY = True

# Security
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = 'DENY'

# Email
EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend'

# Site
SITE_NAME = '$SITE_NAME'
SITE_URL = 'https://$DOMAIN_NAME/bitpoll'

$LDAP_CONFIG
$SENTRY_CONFIG

# Logging
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        'file': {
            'level': 'ERROR',
            'class': 'logging.FileHandler',
            'filename': '/opt/log/bitpoll.log',
        },
    },
    'root': {
        'handlers': ['file'],
        'level': 'ERROR',
    },
}
EOF

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # PostgreSQL Database
  postgres:
    image: postgres:14
    container_name: winejs-bitpoll-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: bitpoll
      POSTGRES_USER: bitpoll
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U bitpoll"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Bitpoll Application
  winejs-bitpoll:
    image: ghcr.io/fsinfuhh/bitpoll:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:3009"
    volumes:
      - ${STATIC_DIR}:/opt/static
      - ${CONFIG_DIR}:/opt/config
      - ${LOG_DIR}:/opt/log
      - ${DATA_DIR}/media:/opt/media
    environment:
      - DJANGO_SETTINGS_MODULE=bitpoll.settings
      - PYTHONUNBUFFERED=1
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= INITIALIZE BITPOLL =============
log "🚀 Starting Bitpoll containers..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Bitpoll to initialize..."
sleep 30

# Run migrations and create admin user
log "🔐 Setting up database and admin user..."

docker exec winejs-bitpoll python manage.py migrate --noinput 2>/dev/null || true
docker exec winejs-bitpoll python manage.py collectstatic --noinput 2>/dev/null || true
docker exec winejs-bitpoll python manage.py compilemessages 2>/dev/null || true

# Create superuser
docker exec winejs-bitpoll python manage.py shell << PYTHON_EOF
from django.contrib.auth.models import User
if not User.objects.filter(username='admin').exists():
    User.objects.create_superuser('admin', '$ADMIN_EMAIL', '$ADMIN_PASSWORD')
    print("Admin user created")
else:
    print("Admin user already exists")
PYTHON_EOF

log "✅ Bitpoll initialized"

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json for app registration..."

# Build features list
FEATURES_LIST='[
        "📊 Poll Creation & Voting",
        "📅 Date & Time Polls",
        "🔒 Anonymous Voting Options",
        "📈 Real-time Results",'
if [ "$LDAP_ENABLED" = "true" ]; then
    FEATURES_LIST="$FEATURES_LIST\n        \"🔐 LDAP Authentication\","
fi
FEATURES_LIST="$FEATURES_LIST
        "🌍 Multi-language Support",
        "📱 Mobile Responsive",
        "🔗 Shareable Poll Links",
        "📧 Email Notifications",
        "📋 CSV Export",
        "🔐 User Permissions",
        "🎨 Customizable Themes"
    ]"

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Bitpoll Voting System",
    "version": "latest",
    "description": "Create polls, surveys, and voting events for team decisions",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/bitpoll.png",
    "category": "Productivity",
    "features": ${FEATURES_LIST}
}
CONF_EOF

# ============= CREATE ADMIN GUIDE =============
log "📝 Creating admin guide..."

cat > "$APP_DIR/admin-guide.md" << GUIDE_EOF
# Bitpoll Voting System - Admin Guide

## Access
- **Main Site**: https://$DOMAIN_NAME/bitpoll/
- **Admin Panel**: https://$DOMAIN_NAME/bitpoll/admin/

## Default Admin Login
- **Username**: admin
- **Password**: [the password you set]
- **Email**: $ADMIN_EMAIL

## Creating Your First Poll

1. **Login** to the admin panel or click "Create Poll" on the main page
2. **Choose poll type**:
   - Simple poll (yes/no/maybe)
   - Multiple choice
   - Date poll (find the best date for an event)
3. **Add options** and configure settings
4. **Set voting period** (start/end dates)
5. **Share the link** with voters
6. **View results** in real-time

## Poll Types

### Simple Poll
Best for: Team decisions, approvals, feedback
- Options: Yes/No/Abstain
- Unlimited choices per voter

### Multiple Choice
Best for: Surveys, opinions, rankings
- Multiple options per question
- Single or multiple answers allowed

### Date Poll
Best for: Meeting scheduling, event planning
- Propose multiple dates/times
- Voters select their availability
- Find the best common slot

## Managing Polls

### Settings
- **Anonymous voting**: Hide voter identities
- **Results visibility**: Show results during/after voting
- **Voter limits**: Restrict to logged-in users
- **Deadline**: Auto-close poll on date

### Exporting Results
- CSV export for analysis
- Visual charts for presentation
- Raw data for integration

## Embedding Polls

\`\`\`html
<!-- Direct link -->
<a href="https://$DOMAIN_NAME/bitpoll/poll/YOUR-POLL-ID/">Vote Now</a>

<!-- Iframe embed -->
<iframe src="https://$DOMAIN_NAME/bitpoll/poll/YOUR-POLL-ID/embed/"
        width="100%" height="600" frameborder="0"></iframe>
\`\`\`

## Use Cases

### Team Meetings
- Find best meeting time (Date poll)
- Vote on agenda items (Simple poll)
- Collect feedback (Multiple choice)

### Event Planning
- Choose event date (Date poll)
- Session selection (Multiple choice)
- Catering preferences (Simple poll)

### Development
- Feature prioritization (Simple poll)
- Sprint planning (Date poll)
- Code review assignments (Multiple choice)

## API Access

Bitpoll provides basic API endpoints:
- \`/api/v1/polls/\` - List polls
- \`/api/v1/polls/{id}/\` - Get poll details
- \`/api/v1/polls/{id}/vote/\` - Submit vote

## Daily Operations

\`\`\`bash
# View logs
winejs-bitpoll logs

# Check status
winejs-bitpoll status

# Restart services
winejs-bitpoll restart
\`\`\`

## Helpful Links
- [Bitpoll Documentation](https://github.com/fsinfuhh/Bitpoll)
- [Django Admin Guide](https://docs.djangoproject.com/en/stable/ref/contrib/admin/)
GUIDE_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading Bitpoll icon..."
curl -L "$BITPOLL_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-bitpoll << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

case "\$1" in
    status)
        cd /opt/winejs/kasmvnc-instances/bitpoll && docker compose ps
        ;;
    logs)
        docker logs winejs-bitpoll --tail 50
        ;;
    restart)
        cd /opt/winejs/kasmvnc-instances/bitpoll && docker compose restart
        echo "Bitpoll restarted"
        ;;
    migrate)
        echo "🔄 Running database migrations..."
        docker exec winejs-bitpoll python manage.py migrate
        ;;
    shell)
        docker exec -it winejs-bitpoll python manage.py shell
        ;;
    polls)
        echo "📊 Recent polls:"
        docker exec winejs-bitpoll python manage.py shell -c "from bitpoll.poll.models import Poll; [print(f'  • {p.title} - {p.status}') for p in Poll.objects.all()[:10]]"
        ;;
    createsuperuser)
        echo "👤 Creating superuser..."
        docker exec -it winejs-bitpoll python manage.py createsuperuser
        ;;
    backup)
        echo "💾 Creating backup..."
        BACKUP_DIR="/opt/winejs/data/bitpoll/backups"
        mkdir -p "\$BACKUP_DIR"
        docker exec winejs-bitpoll python manage.py dumpdata > "\$BACKUP_DIR/bitpoll_\$(date +%Y%m%d_%H%M%S).json"
        echo "Backup saved in: \$BACKUP_DIR"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/bitpoll/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/bitpoll/"
        fi
        ;;
    admin)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/bitpoll/admin/"
        else
            echo "Admin: https://\${DOMAIN_NAME}/bitpoll/admin/"
        fi
        ;;
    *)
        echo "Bitpoll Voting System Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-bitpoll open           - Open Bitpoll"
        echo "  winejs-bitpoll admin          - Open Admin Panel"
        echo "  winejs-bitpoll status         - Check status"
        echo "  winejs-bitpoll logs           - View logs"
        echo "  winejs-bitpoll restart        - Restart services"
        echo "  winejs-bitpoll migrate        - Run migrations"
        echo "  winejs-bitpoll polls          - List recent polls"
        echo "  winejs-bitpoll shell          - Django shell"
        echo "  winejs-bitpoll backup         - Backup database"
        echo "  winejs-bitpoll createsuperuser - Create admin user"
        echo ""
        echo "Access URLs:"
        echo "  • Main Site: https://\${DOMAIN_NAME}/bitpoll/"
        echo "  • Admin: https://\${DOMAIN_NAME}/bitpoll/admin/"
        echo ""
        echo "Admin Login: admin / (password you set)"
        echo "Admin Email: $ADMIN_EMAIL"
        echo ""
        echo "Admin Guide: cat /opt/winejs/apps/bitpoll/admin-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-bitpoll

# ============= UPDATE NGINX FOR BITPOLL =============
log "📝 Setting up nginx reverse proxy for Bitpoll..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /bitpoll" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Bitpoll Voting System\n\
    location /bitpoll {\n\
        rewrite ^/bitpoll(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 86400;\n\
        client_max_body_size 10M;\n\
    }\n\
    \n\
    # Bitpoll Static Files\n\
    location /bitpoll/static/ {\n\
        rewrite ^/bitpoll/static/(.*)$ /static/\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        expires 1y;\n\
        add_header Cache-Control \"public, immutable\";\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Bitpoll routes"
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

cat > "$(dirname "$APP_DIR")/uninstall_bitpoll.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Bitpoll..."

cd /opt/winejs/kasmvnc-instances/bitpoll
docker compose down -v 2>/dev/null

rm -rf /opt/winejs/apps/bitpoll
rm -rf /opt/winejs/kasmvnc-instances/bitpoll
rm -rf /opt/winejs/data/bitpoll
rm -rf /opt/winejs/config/bitpoll

rm -f /usr/local/bin/winejs-bitpoll

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Bitpoll Voting System/,/location \/bitpoll\/static\//d' /etc/nginx/sites-available/winejs
    sed -i '/location \/bitpoll {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Bitpoll uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_bitpoll.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              BITPOLL INSTALLED ON WINEJS!                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Bitpoll Voting System installed!"
echo ""
info "🌐 Access URLs:"
info "   • Main Site: https://$DOMAIN_NAME/bitpoll/"
info "   • Admin Panel: https://$DOMAIN_NAME/bitpoll/admin/"
echo ""
info "🔐 Admin Login:"
info "   • Username: admin"
info "   • Password: [the password you set]"
info "   • Email: $ADMIN_EMAIL"
echo ""
info "📊 Poll Features:"
info "   • Simple polls (Yes/No/Abstain)"
info "   • Multiple choice surveys"
info "   • Date/time scheduling polls"
info "   • Anonymous or named voting"
info "   • Real-time results"
echo ""
if [ "$LDAP_ENABLED" = "true" ]; then
    info "🔐 LDAP Authentication: Enabled"
else
    info "🔐 LDAP Authentication: Disabled"
fi
echo ""
info "🎯 Quick Commands:"
info "   • winejs-bitpoll open        # Open Bitpoll"
info "   • winejs-bitpoll admin       # Open Admin Panel"
info "   • winejs-bitpoll status      # Check status"
info "   • winejs-bitpoll logs        # View logs"
info "   • winejs-bitpoll polls       # List recent polls"
info "   • winejs-bitpoll backup      # Backup database"
info "   • winejs-bitpoll createsuperuser # Create admin"
echo ""
info "📁 Data Directories:"
info "   • Database: ${DATA_DIR}/postgres"
info "   • Static: ${STATIC_DIR}"
info "   • Media: ${DATA_DIR}/media"
info "   • Logs: ${LOG_DIR}"
echo ""
info "📝 Admin Guide:"
info "   • cat /opt/winejs/apps/bitpoll/admin-guide.md"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_bitpoll.sh"
echo ""
success "✨ Bitpoll is ready! Create your first poll at https://$DOMAIN_NAME/bitpoll/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Bitpoll Does:

# Bitpoll is a flexible voting and polling system - perfect for team decisions and event planning:
# Key Features:
#     Multiple Poll Types - Simple polls, multiple choice, date polls
#     Anonymous Voting - Hide voter identities
#     Date Scheduling - Find the best meeting time for everyone
#     Real-time Results - See votes as they come in
#     CSV Export - Download data for analysis
#     LDAP Integration - Connect to existing authentication
#     Multi-language - English, German support

# Perfect For:
#     Team meetings - Find the best time for everyone
#     Feature voting - Prioritize development tasks
#     Event planning - Decide on dates and activities
#     Surveys - Collect feedback from users
#     Consensus building - Make democratic decisions