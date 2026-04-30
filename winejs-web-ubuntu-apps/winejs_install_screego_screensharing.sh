#!/bin/bash
# ============================================
# Screego Screen Sharing - WineJS Installer
# Adds Screen Sharing & Collaboration to WineJS
# ============================================
# App: Screego
# Category: Communication
# Features: Screen Sharing, WebRTC, Multi-User
# ============================================

SCREEGO_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/screego_screensharing_logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🖥️ Installing WineJS Screego Screen Sharing..."

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

# ============= GET EXTERNAL IP =============
log "🌐 Detecting external IP..."
EXTERNAL_IP=$(curl -s 'https://api.ipify.org' || echo "")
if [ -z "$EXTERNAL_IP" ]; then
    warn "Could not detect external IP automatically"
    read -p "Enter your external IP address: " EXTERNAL_IP
fi
info "External IP: $EXTERNAL_IP"

# ============= ASK FOR SCREEGO CONFIGURATION =============
echo ""
info "📝 Screego Configuration"
echo "================================"
read -p "Admin username: " ADMIN_USER
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""

read -p "Authentication mode (none/turn/all) [turn]: " AUTH_MODE
AUTH_MODE=${AUTH_MODE:-"turn"}

read -p "Close room when owner leaves? (true/false) [true]: " CLOSE_ROOM
CLOSE_ROOM=${CLOSE_ROOM:-true}

read -p "Enable Prometheus metrics? (true/false) [false]: " PROMETHEUS
PROMETHEUS=${PROMETHEUS:-false}

# Generate secret
SCREEGO_SECRET=$(openssl rand -base64 32 | tr -d '\n=+/')

# Generate bcrypt password hash for users file
log "🔐 Generating password hash..."
PASSWORD_HASH=$(docker run --rm screego/server:latest screego hash --name "$ADMIN_USER" --pass "$ADMIN_PASSWORD" 2>/dev/null | grep -o 'password:.*' | cut -d' ' -f2 || echo "")

if [ -z "$PASSWORD_HASH" ]; then
    # Fallback - create a simple hash (note: this is not as secure, but works as fallback)
    PASSWORD_HASH="$ADMIN_USER:$(echo -n "$ADMIN_PASSWORD" | sha256sum | cut -d' ' -f1)"
fi

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=9800  # Start after Saleor's range (9700+)
MAX_RETRIES=50
APP_PORT=""
TURN_PORT=3478
TURN_PORT_RANGE_START=50000
TURN_PORT_RANGE_END=55000

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

# Find available port for Screego web interface
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Screego"
fi

log "Using ports: Web=$APP_PORT, TURN=$TURN_PORT, TURN Range=$TURN_PORT_RANGE_START-$TURN_PORT_RANGE_END"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="screego"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/screego"
DATA_DIR="/opt/winejs/data/screego"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/screego"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE USERS FILE =============
log "📝 Creating users file..."

cat > "$DATA_DIR/users" << EOF
$PASSWORD_HASH
EOF

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

# Note: Screego needs host network for WebRTC/TURN to work properly
# We'll use network_mode: host for the screego container

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Screego Screen Sharing Server
  winejs-screego:
    image: ghcr.io/screego/server:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    network_mode: host
    volumes:
      - ${DATA_DIR}:/data
    environment:
      - SCREEGO_EXTERNAL_IP=${EXTERNAL_IP}
      - SCREEGO_SECRET=${SCREEGO_SECRET}
      - SCREEGO_SERVER_ADDRESS=0.0.0.0:${APP_PORT}
      - SCREEGO_TURN_ADDRESS=0.0.0.0:${TURN_PORT}
      - SCREEGO_TURN_PORT_RANGE=${TURN_PORT_RANGE_START}:${TURN_PORT_RANGE_END}
      - SCREEGO_AUTH_MODE=${AUTH_MODE}
      - SCREEGO_CLOSE_ROOM_WHEN_OWNER_LEAVES=${CLOSE_ROOM}
      - SCREEGO_PROMETHEUS=${PROMETHEUS}
      - SCREEGO_USERS_FILE=/data/users
      - SCREEGO_LOG_LEVEL=info
      - SCREEGO_SESSION_TIMEOUT_SECONDS=0
      - SCREEGO_CORS_ALLOWED_ORIGINS=https://${DOMAIN_NAME}
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:${APP_PORT}"]
      interval: 30s
      timeout: 10s
      retries: 5

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= START CONTAINER =============
log "🚀 Starting Screego container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

log "⏳ Waiting for Screego to initialize..."
sleep 15

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
    "name": "Screego Screen Sharing",
    "version": "latest",
    "description": "Self-hosted screen sharing with low latency and high quality",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/screego.png",
    "category": "Communication",
    "features": [
        "🖥️ Low-Latency Screen Sharing",
        "📡 WebRTC Technology",
        "👥 Multi-User Support",
        "🔒 Secure Encrypted Streams",
        "🎯 High Resolution",
        "🔄 Built-in TURN Server",
        "🔐 Authentication Options",
        "🚫 No Registration Required",
        "🎨 Simple Interface",
        "💻 Code/IDE Friendly",
        "📱 Any Browser Support",
        "🛡️ Privacy Focused"
    ]
}
CONF_EOF

# ============= CREATE USER GUIDE =============
log "📝 Creating user guide..."

cat > "$APP_DIR/user-guide.md" << GUIDE_EOF
# Screego Screen Sharing - User Guide

## Access
- **Web Interface**: https://$DOMAIN_NAME/screenshare/

## Authentication
- **Mode**: $AUTH_MODE
- **Username**: $ADMIN_USER
- **Password**: [the password you set]

## Getting Started

### 1. Create a Room

1. Visit https://$DOMAIN_NAME/screenshare/
2. Enter a room name
3. Click "Create Room"
4. Share the room URL with participants

### 2. Share Your Screen

1. Click "Start Sharing"
2. Choose what to share:
   - Entire screen
   - Application window
   - Browser tab
3. Click "Share"
4. Participants can now see your screen

### 3. Join Existing Room

1. Get room URL from host
2. Click "Join Room"
3. Enter room name
4. Start viewing!

## Features

### Low Latency
- WebRTC technology
- Sub-second delay
- Perfect for code reviews
- Real-time collaboration

### High Quality
- High resolution support
- Clear text readability
- No compression artifacts
- Adjustable quality

### Multi-User
- Unlimited participants
- Multiple concurrent rooms
- Anyone can share with permission

### Security

**Encryption**:
- All streams encrypted
- WebRTC DTLS
- Secure signaling

**Authentication**:
$([ "$AUTH_MODE" = "none" ] && echo "  - No authentication (public access)" || echo "  - TURN authentication required")
$([ "$AUTH_MODE" = "all" ] && echo "  - Login required for all access")

**Room Privacy**:
- Unique room IDs
- Password protection option
- $([ "$CLOSE_ROOM" = "true" ] && echo "Room closes when owner leaves")

## Use Cases

### Code Reviews
- Share IDE screen
- Real-time feedback
- Low latency cursor tracking
- Perfect for pair programming

### Presentations
- Share slides
- Demo software
- Team meetings
- Training sessions

### Collaboration
- Design reviews
- Document editing
- Whiteboard sessions
- Brainstorming

### Support
- Remote troubleshooting
- User guidance
- Training sessions
- IT support

## WebRTC Technical Details

### STUN Server
- Built-in STUN server
- Helps with NAT traversal
- Direct peer connection when possible

### TURN Server
**Built-in TURN Server**:
- Address: $EXTERNAL_IP:$TURN_PORT
- Port range: $TURN_PORT_RANGE_START-$TURN_PORT_RANGE_END
- Handles symmetric NATs
- Relays when direct connection fails

### Connection Flow
1. Browser checks local IP
2. STUN finds public IP
3. ICE negotiates best path
4. Direct connection established
5. Or TURN relay if needed

## Browser Support

**Supported Browsers**:
- Chrome/Edge (recommended)
- Firefox
- Safari (limited)
- Opera
- Brave

**Requirements**:
- WebRTC support
- HTTPS connection
- Camera/mic permissions (optional)

## Troubleshooting

### Can't Share Screen

**Check permissions**:
1. Click camera icon in address bar
2. Allow screen sharing
3. Reload page

**Browser issues**:
- Use Chrome for best compatibility
- Clear site data
- Try incognito mode

### High Latency

**Reduce quality**:
- Share smaller window
- Lower resolution
- Check network connection

**Network issues**:
- Test upload speed
- Wired vs WiFi
- Corporate VPN restrictions

### TURN Connection Issues

**Check ports**:
- TURN port $TURN_PORT open (UDP/TCP)
- Range $TURN_PORT_RANGE_START-$TURN_PORT_RANGE_END open
- Firewall rules

**Authentication**:
- Verify credentials
- Check SCREEGO_SECRET
- Users file valid

### Audio Not Working

- Check mic permissions
- Browser audio settings
- System audio devices

## Integration with WineJS Apps

### With Mumble
- Screen share while voice chatting
- Perfect for team collaboration
- Low latency for both

### With Neko
- Share Neko virtual browser
- Demonstrate web apps
- Remote support

### With Owncast
- Share live stream preview
- Behind-the-scenes production
- Team coordination

### With Screego + Mumble + Neko
- Complete remote pair programming
- Voice + screen + virtual browser
- Ultimate collaboration suite

## Advanced Configuration

### Custom STUN/TURN
Edit environment variables to:
- Add external TURN servers
- Custom port ranges
- Whitelist/blacklist IPs

### Authentication Modes

**none**: No login required
- Public access
- No TURN authentication
- Not recommended for public internet

**turn**: TURN requires auth
- Default mode
- Screen sharing works without login
- TURN relay requires credentials

**all**: Everything requires auth
- Most secure
- Login for all features
- Recommended for sensitive content

## Commands

\`\`\`bash
# View logs
winejs-screego logs

# Restart services
winejs-screego restart

# Check status
winejs-screego status

# Add new user
docker exec -it winejs-screego screego hash --name "username" --pass "password"

# Check TURN status
docker logs winejs-screego | grep TURN

# Open interface
winejs-screego open
\`\`\`

## Prometheus Metrics

$([ "$PROMETHEUS" = "true" ] && echo "✅ Metrics enabled at https://$DOMAIN_NAME/screenshare/metrics" || echo "❌ Metrics disabled")

## Security Best Practices

1. **Use HTTPS** (configured via reverse proxy)
2. **Set strong passwords**
3. **Enable authentication** (TURN or all mode)
4. **Regular updates**
5. **Monitor active rooms**
6. **Firewall TURN ports**

## Support

- **GitHub**: https://github.com/screego/server
- **Documentation**: https://screego.net/docs
- **Demo**: https://app.screego.net

## Troubleshooting Commands

\`\`\`bash
# Test TURN server
docker exec winejs-screego nc -vz localhost ${TURN_PORT}

# Check WebRTC stats
# Open browser console and run:
# chrome://webrtc-internals/

# Verify external IP
docker exec winejs-screego curl ifconfig.me

# Check connected peers
docker logs winejs-screego | grep "peer connected"
\`\`\`
GUIDE_EOF

# ============= DOWNLOAD AND SETUP ICON =============
log "📥 Setting up Screego icon..."

if curl -L "$SCREEGO_LOGO_URL" -o "$ICON_DIR/screego.png" 2>/dev/null; then
    success "✅ Icon downloaded successfully"
else
    warn "Failed to download icon, creating placeholder..."
    cat > "$ICON_DIR/screego.svg" << 'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <rect x="2" y="3" width="20" height="14" rx="2" ry="2"/>
  <line x1="8" y1="21" x2="16" y2="21"/>
  <line x1="12" y1="17" x2="12" y2="21"/>
  <rect x="6" y="7" width="12" height="6" rx="1"/>
</svg>
SVG_EOF
fi

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-screego << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}"
TURN_PORT=${TURN_PORT}"
ADMIN_USER="${ADMIN_USER}"
AUTH_MODE="${AUTH_MODE}"

case "\$1" in
    status)
        docker ps | grep winejs-screego
        ;;
    logs)
        docker logs winejs-screego --tail 50
        ;;
    restart)
        docker restart winejs-screego
        echo "Screego restarted"
        ;;
    add-user)
        shift
        if [ $# -lt 2 ]; then
            echo "Usage: winejs-screego add-user <username> <password>"
        else
            docker exec -it winejs-screego screego hash --name "\$1" --pass "\$2"
        fi
        ;;
    turn-test)
        echo "🔄 Testing TURN server connectivity..."
        echo "TURN Server: ${EXTERNAL_IP}:${TURN_PORT}"
        docker exec winejs-screego nc -vz localhost ${TURN_PORT} 2>&1 || echo "Port check failed"
        ;;
    rooms)
        echo "🏠 Active rooms:"
        docker logs winejs-screego 2>&1 | grep "room created" | tail -10
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/screenshare/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/screenshare/"
        fi
        ;;
    *)
        echo "Screego Screen Sharing Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-screego open           # Open screen sharing"
        echo "  winejs-screego status         # Check status"
        echo "  winejs-screego logs           # View logs"
        echo "  winejs-screego restart        # Restart"
        echo "  winejs-screego add-user <u> <p> # Add user"
        echo "  winejs-screego turn-test      # Test TURN server"
        echo "  winejs-screego rooms          # List active rooms"
        echo ""
        echo "Access URL: https://\${DOMAIN_NAME}/screenshare/"
        echo ""
        echo "Authentication Mode: $AUTH_MODE"
        if [ "$AUTH_MODE" != "none" ]; then
            echo "Login: $ADMIN_USER / (password you set)"
        fi
        echo ""
        echo "TURN Server: ${EXTERNAL_IP}:${TURN_PORT}"
        echo "WebRTC Port Range: ${TURN_PORT_RANGE_START}-${TURN_PORT_RANGE_END}"
        echo ""
        echo "User Guide: cat /opt/winejs/apps/screego/user-guide.md"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-screego

# ============= UPDATE NGINX FOR SCREEGO =============
log "📝 Setting up nginx reverse proxy for Screego..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /screenshare" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Screego Screen Sharing (WebSocket support required)\n\
    location /screenshare {\n\
        rewrite ^/screenshare(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 86400s;\n\
        proxy_buffering off;\n\
    }\n\
    \n\
    # Screego WebSocket streaming endpoint\n\
    location /screenshare/stream {\n\
        rewrite ^/screenshare/stream(.*)$ /stream\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 86400s;\n\
        proxy_buffering off;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Screego routes"
            else
                warn "Nginx test failed, restoring backup"
                cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                nginx -t && systemctl reload nginx
            fi
        fi
    fi
fi

# Add WebSocket upgrade map to nginx.conf if not present
if [ -f "/etc/nginx/nginx.conf" ]; then
    if ! grep -q "map \$http_upgrade \$connection_upgrade" /etc/nginx/nginx.conf; then
        sed -i '/http {/a \\n    map $http_upgrade $connection_upgrade {\n        default upgrade;\n        ""      close;\n    }' /etc/nginx/nginx.conf
        systemctl reload nginx
    fi
fi

# ============= FIREWALL RULES =============
log "🔥 Configuring firewall for TURN server..."

# Open TURN port and range if ufw is active
if command -v ufw &>/dev/null && ufw status | grep -q active; then
    ufw allow $TURN_PORT/tcp
    ufw allow $TURN_PORT/udp
    ufw allow $TURN_PORT_RANGE_START:$TURN_PORT_RANGE_END/udp
    log "✅ Firewall rules added for TURN server"
fi

# ============= RESTART TRANSLATOR =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_screego.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Screego..."

docker stop winejs-screego 2>/dev/null
docker rm winejs-screego 2>/dev/null

# Ask about removing data
read -p "Remove all screego data? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /opt/winejs/apps/screego
    rm -rf /opt/winejs/kasmvnc-instances/screego
    rm -rf /opt/winejs/data/screego
    log "✅ All data removed"
else
    rm -rf /opt/winejs/apps/screego
    rm -rf /opt/winejs/kasmvnc-instances/screego
    rm -rf /opt/winejs/data/screego/users
fi

rm -f /usr/local/bin/winejs-screego

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Screego Screen Sharing (WebSocket support required)/,/location \/screenshare\/stream/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/screenshare {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Screego uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_screego.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              SCREEGO INSTALLED ON WINEJS!                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Screego Screen Sharing installed!"
echo ""
info "🌐 Access URL:"
info "   • https://$DOMAIN_NAME/screenshare/"
echo ""
info "🔐 Authentication:"
info "   • Mode: $AUTH_MODE"
if [ "$AUTH_MODE" != "none" ]; then
    info "   • Username: $ADMIN_USER"
    info "   • Password: [the password you set]"
fi
echo ""
info "🖥️ TURN Server:"
info "   • Address: $EXTERNAL_IP:$TURN_PORT"
info "   • Port Range: $TURN_PORT_RANGE_START-$TURN_PORT_RANGE_END"
info "   • Protocol: UDP (primary) + TCP (fallback)"
echo ""
info "⚙️ Configuration:"
info "   • Close room when owner leaves: $CLOSE_ROOM"
info "   • Prometheus metrics: $PROMETHEUS"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-screego open           # Open screen sharing"
info "   • winejs-screego status         # Check status"
info "   • winejs-screego logs           # View logs"
info "   • winejs-screego add-user <u> <p> # Add user"
info "   • winejs-screego turn-test      # Test TURN server"
info "   • winejs-screego rooms          # List active rooms"
echo ""
info "📁 Data Directory:"
info "   • ${DATA_DIR}"
echo ""
info "📚 User Guide:"
info "   • cat /opt/winejs/apps/screego/user-guide.md"
echo ""
info "🔄 Firewall Requirements:"
info "   • Port $TURN_PORT (TCP+UDP) must be open"
info "   • Ports $TURN_PORT_RANGE_START-$TURN_PORT_RANGE_END (UDP) must be open"
info "   • $([ "$AUTH_MODE" != "none" ] && echo "Authentication configured" || echo "⚠️ No authentication - public access!")"
echo ""
info "🔧 For NAT traversal issues:"
info "   • Ensure external IP is correct: $EXTERNAL_IP"
info "   • Configure port forwarding on router"
info "   • Set SCREEGO_EXTERNAL_IP if IP changes"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_screego.sh"
echo ""
success "✨ Screego is ready! Start sharing your screen at https://$DOMAIN_NAME/screenshare/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"

# What Screego Does:

# Screego is a self-hosted screen sharing solution with low latency and high quality:
# Key Features:
#     Low Latency - Sub-second delay via WebRTC
#     High Resolution - Clear text, perfect for code
#     Multi-User - Many participants can watch/share
#     Built-in TURN Server - Works through firewalls/NAT
#     Secure - Encrypted WebRTC streams
#     Simple - No registration needed (configurable)
#     Lightweight - Easy to deploy

# Technical Details:
# Component	Purpose
# WebRTC	Peer-to-peer streaming
# STUN	NAT discovery (built-in)
# TURN	Relay when direct fails (built-in)
# WebSocket	Signaling

# Perfect For:
#     Code Reviews - Share IDE with perfect clarity
#     Pair Programming - Real-time collaboration
#     Presentations - Show slides, demos
#     Remote Support - Guide users through issues
#     Team Meetings - Share screens in real-time