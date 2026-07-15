#!/bin/bash
# ============================================
# Mumble VOIP Server - WineJS Installer
# Adds Team Voice Chat Server to WineJS Platform
# ============================================
# App: Mumble Server (Murmur)
# Category: Communication
# Features: Team VOIP, Low-latency voice chat, Channel management
# ============================================

APP_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/mumble-voip-server-icon.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🎙️ Installing WineJS Mumble VOIP Server..."

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

# ============= ASK FOR MUMBLE CONFIGURATION =============
echo ""
info "📝 Mumble Server Configuration"
echo "================================"
read -p "Server name [WineJS Mumble Server]: " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-"WineJS Mumble Server"}

read -p "Max users [100]: " MAX_USERS
MAX_USERS=${MAX_USERS:-100}

read -p "Welcome message [Welcome to WineJS Mumble!]: " WELCOME_TEXT
WELCOME_TEXT=${WELCOME_TEXT:-"Welcome to WineJS Mumble!"}

read -p "Server password (leave empty for no password): " SERVER_PASSWORD

read -s -p "SuperUser (admin) password (min 8 chars): " SUPERUSER_PASSWORD
echo ""
if [ -z "$SUPERUSER_PASSWORD" ]; then
    SUPERUSER_PASSWORD=$(openssl rand -base64 12)
    warn "Generated SuperUser password: $SUPERUSER_PASSWORD"
fi

read -p "Max bandwidth (kbit/s) [72000]: " MAX_BANDWIDTH
MAX_BANDWIDTH=${MAX_BANDWIDTH:-72000}

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=7000  # Start after PufferPanel's range (6900+)
MAX_RETRIES=50
APP_PORT=""
ICE_PORT=""

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

# Find available port for Mumble voice (TCP & UDP share same port)
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

# Find available port for ICE interface (optional)
for i in $(seq 1 $MAX_RETRIES); do
    TEST_PORT=$((APP_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        ICE_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Mumble"
fi

log "Using ports: Mumble=$APP_PORT (TCP+UDP), ICE=$ICE_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="mumble"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/mumble"
CONFIG_DIR="/opt/winejs/config/mumble"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/mumble"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Mumble VOIP Server
  winejs-mumble:
    image: mumblevoip/mumble-server:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "${APP_PORT}:64738/tcp"
      - "${APP_PORT}:64738/udp"
    environment:
      - MUMBLE_CONFIG_BANDWIDTH=${MAX_BANDWIDTH}
      - MUMBLE_CONFIG_USERS=${MAX_USERS}
      - MUMBLE_CONFIG_WELCOMETEXT=${WELCOME_TEXT}
      - MUMBLE_CONFIG_REGISTERNAME=${SERVER_NAME}
      - MUMBLE_SUPERUSER_PASSWORD=${SUPERUSER_PASSWORD}
DOCKER_EOF

# Add server password if provided
if [ -n "$SERVER_PASSWORD" ]; then
    cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
      - MUMBLE_CONFIG_SERVER_PASSWORD=${SERVER_PASSWORD}
DOCKER_EOF
fi

# Add volumes and networks
cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
    volumes:
      - ${DATA_DIR}:/data
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE CONNECTION INFO PAGE =============
log "📄 Creating connection info page..."
 
# Get the server's IP address
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || hostname -I | awk '{print $1}')

# Create the HTML matching official Mumble website style
cat > "$APP_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Mumble VOIP Server - WineJS</title>
    <link rel="icon" type="image/png" target="_blank" rel="norefferer" href="https://cdn.gitgpt.chat/rtx/images/mumble-voip-server-icon.png">
    <link rel="apple-touch-icon" type="image/png" target="_blank" rel="norefferer" href="https://cdn.gitgpt.chat/rtx/images/mumble-voip-server-icon.png" sizes="180x180">
    <link rel="icon" type="image/png" target="_blank" rel="norefferer" href="https://cdn.gitgpt.chat/rtx/images/mumble-voip-server-icon.png" sizes="192x192">
    <link rel="icon" type="image/png" target="_blank" rel="norefferer" href="https://cdn.gitgpt.chat/rtx/images/mumble-voip-server-icon.png" sizes="512x512">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            background: white;
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, sans-serif;
            line-height: 1.5;
            color: #24292e;
        }
        
        /* Header styles - matching mumble.info */
        #page-head {
            background: #F2F2F2;
            color: black;
            border-bottom: 1px solid #dee2e6;
        }
        
        #header-content {
            max-width: 1100px;
            margin: 0 auto;
            padding: 10px;
            display: flex;
            align-items: center;
            gap: 5px;
        }
        
        .logo {
            flex-shrink: 0;
        }
        
        .logo a {
            display: block;
            width: 100px;
            height: 100px;
            background: url('https://cdn.gitgpt.chat/rtx/images/mumble-voip-server-icon.png') no-repeat center;
            background-size: contain;
            border-radius: 50%;
        }
        
        #header-content h1 {
            font-size: 32px;
            margin: 0;
            color: black;
            font-weight: normal;
        }
        
        #header-content h1 a {
            color: black;
            text-decoration: none;
        }
        
        #header-content sub {
            font-size: 14px;
            opacity: 0.8;
            display: block;
            margin-top: 5px;
        }
        
        nav ul {
            list-style: none;
            display: flex;
            gap: 30px;
            margin-left: auto;
        }
        
        nav ul li a {
            color: black;
            text-decoration: none;
            font-weight: 500;
            opacity: 0.9;
        }
        
        nav ul li a:hover {
            opacity: 1;
            text-decoration: underline;
        }
        
        /* Content container */
        .content-container {
            max-width: 1200px;
            margin: 0px auto;
            padding: 0 20px;
        }
        
        .content {
            overflow: hidden;
        }
        
        main {
            padding: 40px;
        }
        
        /* Markdown body styles */
        .markdown-body {
            font-size: 16px;
            line-height: 1.5;
            word-wrap: break-word;
        }
        
        .markdown-body h2 {
            font-size: 24px;
            font-weight: 600;
            margin-top: 24px;
            margin-bottom: 16px;
            padding-bottom: 0.3em;
        }
        
        .markdown-body h3 {
            font-size: 20px;
            font-weight: 600;
            margin-top: 24px;
            margin-bottom: 16px;
        }
        
        .markdown-body p {
            margin-bottom: 16px;
        }
        
        /* Screenshot gallery */
        .home-screenshots {
            float: right;
            margin-left: 30px;
            margin-bottom: 20px;
            display: flex;
            flex-direction: column;
            gap: 15px;
        }
        
        .home-screenshot {
            max-width: 300px;
        }
        
        figure {
            text-align: center;
        }
        
        figcaption {
            font-size: 13px;
            color: #6a737d;
            margin-top: -2px;
        }
        
        /* Download button */
        .download-button {
            display: inline-block;
            background: #7cb342;
            color: white;
            padding: 12px 24px;
            border-radius: 6px;
            text-decoration: none;
            font-weight: 600;
            font-size: 16px;
            margin: 20px 0;
            transition: background 0.2s;
        }
        
        .download-button:hover {
            background: #689f38;
        }
        
        /* Connection info box */
        .connection-info {
            background: #f6f8fa;
            border-left: 4px solid #7cb342;
            padding: 20px;
            border-radius: 6px;
            margin: 20px 0;
            font-family: monospace;
        }
        
        .info-card {
            background: #ffffff;
            padding: 25px;
            margin-bottom: 25px;
            border: 1px solid #e0e0e0;
            box-shadow: 0 1px 3px rgba(0,0,0,0.05);
        }
        
        .info-card h3 {
            color: #24292e;
            margin-bottom: 20px;
            font-size: 20px;
            font-weight: 600;
            border-left: 4px solid #7cb342;
            padding-left: 15px;
        }
        
        .connection-string {
            background: #2d3748;
            color: #68d391;
            padding: 15px;
            border-radius: 6px;
            font-family: 'Courier New', monospace;
            font-size: 14px;
            word-break: break-all;
            margin: 15px 0;
        }
        
        .button {
            display: inline-block;
            background: #7cb342;
            color: white;
            padding: 10px 20px;
            border-radius: 4px;
            text-decoration: none;
            font-weight: 600;
            font-size: 14px;
            margin-top: 10px;
            margin-right: 10px;
            border: none;
            cursor: pointer;
            transition: background 0.2s;
        }
        
        .button:hover {
            background: #689f38;
        }
        
        .button-secondary {
            background: #0364D5;
        }
        
        .button-secondary:hover {
            background: #0364D9;
        }
        
        .client-list {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        
        .client-item {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 6px;
            text-align: center;
            color: #0364D5;
            border: 1px solid #e0e0e0;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        
        .client-item:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.1);
        }
        
        .client-item a {
            color: #0364D5;
            text-decoration: none;
            font-weight: 600;
            font-size: 14px;
        }
        
        .client-item a:hover {
            text-decoration: underline;
        }
        
        ul {
            margin-left: 20px;
            margin-top: 10px;
        }
        
        li {
            margin: 8px 0;
            line-height: 1.5;
        }
        
        code {
            background: #f8f9fa;
            padding: 2px 6px;
            border-radius: 4px;
            font-family: 'Courier New', monospace;
            font-size: 13px;
            color: #d63384;
            border: 1px solid #dee2e6;
        }
        
        .credentials {
            background: #fff8e1;
            border-left: 4px solid #ffa000;
        }
        
        .warning {
            background: #e3f2fd;
            border-left: 4px solid #1976d2;
        }
        
        .footer {
            background: #F2F2F2;
            padding: 20px;
            text-align: center;
            color: #6c757d;
            font-size: 13px;
            border-top: 1px solid #dee2e6;
        }
        
        .footer a {
            color: #0364D5;
            text-decoration: none;
        }
        
        .footer a:hover {
            text-decoration: underline;
        }
        
        @media (max-width: 768px) {
            #header-content {
                flex-direction: column;
                text-align: center;
            }
            nav ul {
                margin-left: 0;
                justify-content: center;
            }
            .home-screenshots {
                float: none;
                margin-left: 0;
                margin-bottom: 20px;
                align-items: center;
            }
            main {
                padding: 20px;
            }
        }
        
        .alert {
            position: fixed;
            top: 20px;
            right: 20px;
            background: #4caf50;
            color: white;
            padding: 12px 20px;
            border-radius: 4px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.2);
            z-index: 1000;
            animation: slideIn 0.3s ease-out;
        }
        
        @keyframes slideIn {
            from { transform: translateX(100%); opacity: 0; }
            to { transform: translateX(0); opacity: 1; }
        }
        
        .clearfix::after {
            content: "";
            clear: both;
            display: table;
        }
    </style>
</head>
<body>
    <header id="page-head">
        <div id="header-content">
            <div class="logo"><a target="_blank" rel="norefferer" href="https://www.mumble.info/"></a></div>
            <h1>
                <a target="_blank" rel="norefferer" href="https://www.mumble.info/">Mumble</a>
                <sub>Open Source, Low Latency, High Quality Voice Chat</sub>
            </h1>
            <nav>
                <ul class="menu">
                    <li><a target="_blank" rel="norefferer" href="https://www.mumble.info/">Home</a></li>
                    <li><a target="_blank" rel="norefferer" href="https://www.mumble.info/downloads/">Downloads</a></li>
                    <li><a target="_blank" rel="norefferer" href="https://www.mumble.info/documentation/">Documentation</a></li>
                    <li><a target="_blank" rel="norefferer" href="https://www.mumble.info/blog/">Blog</a></li>
                    <li><a target="_blank" rel="norefferer" href="https://comfy.guide/server/mumble/">About</a></li>
                </ul>
            </nav>
        </div>
    </header>
    
    <div class="content-container">
        <div class="content">
            <main>
                <div class="markdown-body">
                    <p>Welcome to <b>your Mumble server!</b></p>
                    
                    <div class="home-screenshots">
                        <figure>
                            <img class="home-screenshot" src="https://www.mumble.info/client-screenshots/empty.png" alt="Mumble Client">
                            <figcaption>Mumble Client</figcaption>
                        </figure>
                        <figure>
                            <img class="home-screenshot" src="https://www.mumble.info/client-screenshots/connected.png" alt="Connected to a Server">
                            <figcaption>Connected to a Server</figcaption>
                        </figure>
                        <figure>
                            <img class="home-screenshot" src="https://www.mumble.info/client-screenshots/public-server-list.png" alt="Public Server List">
                            <figcaption>Public Server List</figcaption>
                        </figure>
                    </div>
                    
                    <div class="info-card">
                        <h3>🔗 Connection Information</h3>
                        <div class="connection-string" id="connectionString">mumble://IP_PLACEHOLDER:PORT_PLACEHOLDER/</div>
                        <button class="button" onclick="copyConnection()">📋 Copy Connection String</button>
                        <button class="button button-secondary" onclick="openMumbleClient()">🚀 Open in Mumble Client</button>
                    </div>
                    <div class="info-card">
                        <h3>📱 Scan to Connect (Mobile)</h3>
                        <div style="text-align: left;">
                            <div id="qrcode" style="display: inline-block; padding: 10px; background: white; border-radius: 10px;"></div>
                            <p style="margin-top: 15px;">
                                <span style="font-size: 14px;">📱 <strong>iOS:</strong> Scan with camera → Open in Mumble</span><br>
                                <span style="font-size: 14px;">🤖 <strong>Android:</strong> Scan with Mumla app</span><br>
                                <span style="font-size: 12px; color: #6c757d;">Connection string: mumble://IP_PLACEHOLDER:PORT_PLACEHOLDER/</span>
                            </p>
                        </div>
                    </div>
                    <div class="info-card">
                        <h3>📱 How to Connect</h3>
                        <p><strong>Step 1:</strong> Download the Mumble client for your platform:</p>
                        <div class="client-list">
                            <div class="client-item"><a target="_blank" rel="norefferer" href="https://www.mumble.info/downloads/" target="_blank">💻 Windows / Mac / Linux</a></div>
                            <div class="client-item"><a target="_blank" rel="norefferer" href="https://play.google.com/store/apps/details?id=se.lublin.mumla" target="_blank">📱 Android (Mumla)</a></div>
                            <div class="client-item"><a target="_blank" rel="norefferer" href="https://apps.apple.com/app/mumble/id443472808" target="_blank">🍎 iOS (Mumble)</a></div>
                        </div>
                        <p><strong>Step 2:</strong> Connect using these details:</p>
                        <ul>
                            <li><strong>Address:</strong> IP_PLACEHOLDER</li>
                            <li><strong>Port:</strong> PORT_PLACEHOLDER</li>
                            <li><strong>Username:</strong> Choose any name you like</li>
                            SERVER_PASSWORD_LI_PLACEHOLDER
                        </ul>
                    </div>
                    
                    <div class="info-card credentials">
                        <h3>🔑 Administrator Access</h3>
                        <p><strong>SuperUser Password:</strong> <code id="superuserPassword">PASSWORD_PLACEHOLDER</code></p>
                        <button class="button" onclick="copyPassword()">📋 Copy SuperUser Password</button>
                        <p style="margin-top: 15px; font-size: 14px;">⚠️ <strong>Note:</strong> Use "SuperUser" as the username with this password to access admin features.<br>In Mumble client: <em>Server → Connect → Edit → Advanced → Username: SuperUser</em></p>
                    </div>
                    
                    <div class="info-card warning">
                        <h3>ℹ️ Important Information</h3>
                        <ul>
                            <li>Mumble uses <strong>both TCP and UDP port PORT_PLACEHOLDER</strong> - ensure your firewall allows both protocols</li>
                            <li>For best quality, use a wired connection or strong WiFi signal</li>
                            <li>Voice is encrypted using the Opus codec at up to BANDWIDTH_PLACEHOLDER kbit/s</li>
                            <li>Server supports up to USERS_PLACEHOLDER concurrent users</li>
                            <li>Welcome message: "WELCOME_PLACEHOLDER"</li>
                        </ul>
                    </div>
                </div>
            </main>
        </div>
    </div>
    
    <div class="footer">
        Powered by WineJS Platform | <a target="_blank" rel="norefferer" href="https://www.mumble.info" target="_blank">Mumble Open Source VOIP</a>
    </div>
    
    <script>
        function copyConnection() {
            const conn = document.getElementById('connectionString').innerText;
            navigator.clipboard.writeText(conn).then(() => {
                showAlert('✅ Connection string copied to clipboard!');
            });
        }
        function copyPassword() {
            const pwd = document.getElementById('superuserPassword').innerText;
            navigator.clipboard.writeText(pwd).then(() => {
                showAlert('🔑 SuperUser password copied to clipboard!');
            });
        }
        function openMumbleClient() {
            const conn = document.getElementById('connectionString').innerText;
            window.location.href = conn;
        }
        function showAlert(message) {
            const existingAlert = document.querySelector('.alert');
            if (existingAlert) existingAlert.remove();
            const alert = document.createElement('div');
            alert.className = 'alert';
            alert.textContent = message;
            document.body.appendChild(alert);
            setTimeout(() => { alert.remove(); }, 2000);
        }
    </script>
    <script src="https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js"></script>
    <script>    
        // Generate QR code on page load
        document.addEventListener('DOMContentLoaded', function() {
            const qrContainer = document.getElementById('qrcode');
            if (qrContainer) {
                const conn = document.getElementById('connectionString').innerText;
                new QRCode(qrContainer, {
                    text: conn,
                    width: 200,
                    height: 200,
                    colorDark: "#000000",
                    colorLight: "#ffffff",
                    correctLevel: QRCode.CorrectLevel.H
                });
            }
        });
    </script>
</body>
</html>
EOF

# Replace placeholders with actual values
sed -i "s/IP_PLACEHOLDER/${SERVER_IP}/g" "$APP_DIR/index.html"
sed -i "s/PORT_PLACEHOLDER/${APP_PORT}/g" "$APP_DIR/index.html"
sed -i "s/PASSWORD_PLACEHOLDER/${SUPERUSER_PASSWORD}/g" "$APP_DIR/index.html"
sed -i "s/BANDWIDTH_PLACEHOLDER/${MAX_BANDWIDTH}/g" "$APP_DIR/index.html"
sed -i "s/USERS_PLACEHOLDER/${MAX_USERS}/g" "$APP_DIR/index.html"
sed -i "s/WELCOME_PLACEHOLDER/${WELCOME_TEXT}/g" "$APP_DIR/index.html"

# Add server password line if needed
if [ -n "$SERVER_PASSWORD" ]; then
    sed -i "s/SERVER_PASSWORD_LI_PLACEHOLDER/                    <li><strong>Server Password:<\/strong> ${SERVER_PASSWORD}<\/li>/g" "$APP_DIR/index.html"
else
    sed -i "/SERVER_PASSWORD_LI_PLACEHOLDER/d" "$APP_DIR/index.html"
fi

# ============= CREATE CONFIG.JSON (CRITICAL FOR APP REGISTRATION) =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Mumble VOIP Server",
    "version": "latest",
    "description": "Open source, low-latency, high-quality team voice chat server",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/mumble.png",
    "category": "Communication",
    "features": [
        "🎙️ High-quality team voice chat (Opus codec)",
        "⚡ Low latency communication",
        "🔐 Server password protection",
        "👑 SuperUser administrator access",
        "📁 Organized channel hierarchy",
        "📱 Cross-platform clients (Windows/Mac/Linux/Android/iOS)",
        "🎨 Per-user permissions system",
        "🔊 Dynamic audio quality adjustment",
        "🛡️ Encrypted voice communication",
        "📊 Up to ${MAX_USERS} concurrent users"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading app icon..."
curl -L "$APP_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon, using default"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-mumble << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}
SUPERUSER_PASSWORD="${SUPERUSER_PASSWORD}"

case "\$1" in
    status)
        docker ps | grep winejs-mumble
        ;;
    logs)
        docker logs winejs-mumble --tail 50
        ;;
    restart)
        docker restart winejs-mumble
        echo "Mumble server restarted"
        ;;
    password)
        echo "SuperUser Password: \$SUPERUSER_PASSWORD"
        ;;
    connect)
        echo "Connection string: mumble://\$DOMAIN_NAME:\$APP_PORT/"
        ;;
    users)
        echo "Showing connected users..."
        docker exec winejs-mumble murmurd -ini /data/mumble-server.ini -users
        ;;
    config)
        echo "Opening configuration directory..."
        echo "/opt/winejs/config/mumble/"
        ls -la /opt/winejs/config/mumble/
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/mumble/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/mumble/"
        fi
        ;;
    *)
        echo "Mumble VOIP Server Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-mumble open        - Open connection info page"
        echo "  winejs-mumble status      - Check server status"
        echo "  winejs-mumble logs        - View server logs"
        echo "  winejs-mumble restart     - Restart server"
        echo "  winejs-mumble password    - Show SuperUser password"
        echo "  winejs-mumble connect     - Show connection string"
        echo "  winejs-mumble users       - List connected users"
        echo "  winejs-mumble config      - Show config location"
        echo ""
        echo "Connection: mumble://\${DOMAIN_NAME}:\${APP_PORT}/"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-mumble

# ============= START CONTAINER =============
log "🚀 Starting Mumble container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

sleep 10

if docker ps | grep -q "winejs-${APP_NAME}"; then
    success "✅ Container started successfully"
else
    warn "⚠️ Container may not have started. Check: docker logs winejs-${APP_NAME}"
    docker logs winejs-${APP_NAME} --tail 20
fi

# ============= GENERATE SSL CERTIFICATE =============
log "🔐 Generating SSL certificate for Mumble..."

# Get server IP if not already set
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || hostname -I | awk '{print $1}')
fi

# Generate certificate in the data directory
cd "$DATA_DIR"

# Generate a proper self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout murmur.key -out murmur.crt \
  -subj "/CN=${DOMAIN_NAME}" \
  -addext "subjectAltName=DNS:${DOMAIN_NAME},IP:${SERVER_IP}" 2>/dev/null

# Set proper permissions
chmod 600 murmur.key
chmod 644 murmur.crt

# Restart container to use new certificate
docker restart winejs-${APP_NAME}

log "✅ SSL certificate generated and applied"
sleep 3

# ============= WAIT FOR MUMBLE TO INITIALIZE =============
log "⏳ Waiting for Mumble to initialize..."
sleep 5

# ============= UPDATE NGINX FOR INFO PAGE =============
log "📝 Setting up nginx for Mumble info page..."
# The pattern for ALL installers (Mumble, PufferPanel, Forgejo, VSCode):
#   1. Find the HTTPS server block by locating "listen 443"
#   2. Count braces { and } to find the exact closing brace of that server block
#   3. Insert new location blocks BEFORE that closing brace
#   4. This guarantees routes are safely INSIDE the correct server block
# This method is proven to work (VSCode uses it) and never creates orphaned directives.
# DO NOT insert before "listen 443" - that breaks the config.
# DO NOT insert after random lines like "root" or "server_name" - that's fragile.
# The pattern from PufferPanel - proven to work with proper SPA support
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    # Check if Mumble routes already exist
    if ! grep -q "location /mumble" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        # Find the HTTPS server block (listen 443)
        HTTPS_START=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$HTTPS_START" ]; then
            # Find the closing brace of the HTTPS block by counting braces
            BRACE_COUNT=0
            LINE_NUM=$HTTPS_START
            TOTAL_LINES=$(wc -l < /etc/nginx/sites-available/winejs)
            HTTPS_END=""
            
            while [ $LINE_NUM -le $TOTAL_LINES ]; do
                LINE=$(sed -n "${LINE_NUM}p" /etc/nginx/sites-available/winejs)
                for ((i=0; i<${#LINE}; i++)); do
                    char="${LINE:$i:1}"
                    if [ "$char" = "{" ]; then
                        BRACE_COUNT=$((BRACE_COUNT + 1))
                    elif [ "$char" = "}" ]; then
                        BRACE_COUNT=$((BRACE_COUNT - 1))
                    fi
                done
                if [ $BRACE_COUNT -eq 0 ]; then
                    HTTPS_END=$LINE_NUM
                    break
                fi
                LINE_NUM=$((LINE_NUM + 1))
            done
            
            if [ -n "$HTTPS_END" ]; then
                # Insert routes BEFORE the closing brace (safe inside server block) - matches PufferPanel pattern
                sed -i "${HTTPS_END}i\\
    # Mumble VOIP Server Info Page\n\
    location = /mumble {\n\
        return 301 /mumble/;\n\
    }\n\
    \n\
    location /mumble/ {\n\
        alias /opt/winejs/apps/mumble/;\n\
        try_files \\\$uri \\\$uri/ /mumble/index.html;\n\
    }\n\
    \n\
    # Mumble connection info endpoint\n\
    location /mumble/info {\n\
        return 200 '{\"server\":\"${DOMAIN_NAME}\",\"port\":${APP_PORT},\"protocol\":\"mumble\"}';\n\
        add_header Content-Type application/json;\n\
        add_header Access-Control-Allow-Origin \"*\";\n\
    }\n" /etc/nginx/sites-available/winejs
                
                if nginx -t; then
                    systemctl reload nginx
                    log "✅ Nginx updated with Mumble routes (SPA support enabled)"
                else
                    warn "Nginx test failed, restoring backup"
                    cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                    nginx -t && systemctl reload nginx
                fi
            else
                warn "Could not find HTTPS block closing brace"
            fi
        else
            warn "Could not find HTTPS server block (listen 443)"
        fi
    else
        log "Mumble routes already exist - updating for SPA support"
        # Update existing config to add proper redirect
        sed -i 's|location /mumble {|location = /mumble {|' /etc/nginx/sites-available/winejs
        nginx -t && systemctl reload nginx
    fi
fi

# ============= RESTART TRANSLATOR TO REGISTER APP =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_mumble.sh" << 'UNINSTALL_EOF'
#!/bin/bash
# WineJS Mumble Uninstaller

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Change to safe directory first
cd /tmp || cd /root || exit 1

log "🧹 Uninstalling Mumble VOIP Server..."

# ============= STOP AND REMOVE DOCKER CONTAINERS =============
log "Stopping Docker containers..."

if docker ps -a 2>/dev/null | grep -q "winejs-mumble"; then
    log "Stopping winejs-mumble container..."
    docker stop winejs-mumble 2>/dev/null || true
    docker rm winejs-mumble 2>/dev/null || true
    log "✅ Mumble container removed"
fi

# ============= REMOVE APP DIRECTORIES =============
log "Removing app directories..."

APP_NAME="mumble"
APP_DIR="/opt/winejs/apps/${APP_NAME}"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/${APP_NAME}"
MUMBLE_DATA="/opt/winejs/data/mumble"
MUMBLE_CONFIG="/opt/winejs/config/mumble"
ICON_FILE="/opt/winejs/translator/public/icons/${APP_NAME}.png"

# Remove directories if they exist
[ -d "$INSTANCE_DIR" ] && rm -rf "$INSTANCE_DIR" && log "✅ Instance directory removed"
[ -d "$APP_DIR" ] && rm -rf "$APP_DIR" && log "✅ App directory removed"
[ -d "$MUMBLE_DATA" ] && rm -rf "$MUMBLE_DATA" && log "✅ Mumble data removed"
[ -d "$MUMBLE_CONFIG" ] && rm -rf "$MUMBLE_CONFIG" && log "✅ Mumble config removed"
[ -f "$ICON_FILE" ] && rm -f "$ICON_FILE" && log "✅ Icon removed"

# ============= REMOVE NGINX CONFIGURATION =============
log "Removing nginx configuration..."

NGINX_SITE="/etc/nginx/sites-available/winejs"

if [ ! -f "$NGINX_SITE" ]; then
    warn "nginx config not found at $NGINX_SITE"
else
    # Check if any Mumble routes exist
    if ! grep -q "mumble" "$NGINX_SITE"; then
        log "No Mumble routes found in nginx config"
    else
        log "Removing Mumble routes from nginx config..."
        
        # Create backup with timestamp
        BACKUP_FILE="${NGINX_SITE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$NGINX_SITE" "$BACKUP_FILE"
        log "✅ Backup created: $BACKUP_FILE"
        
        # Use Perl for more reliable multi-line removal (from PufferPanel pattern)
        if command -v perl &> /dev/null; then
            # Remove the Mumble location blocks (matches PufferPanel approach)
            perl -i -0777 -pe 's/^[[:space:]]*# Mumble VOIP Server Info Page\s*\n.*?location = \/mumble\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
            perl -i -0777 -pe 's/^[[:space:]]*location = \/mumble\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
            perl -i -0777 -pe 's/^[[:space:]]*location \/mumble\/\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
            perl -i -0777 -pe 's/^[[:space:]]*# Mumble connection info endpoint\s*\n.*?location \/mumble\/info\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
        else
            # Fallback to sed for multi-line removal
            sed -i '/^[[:space:]]*# Mumble VOIP Server Info Page/,/^[[:space:]]*}/d' "$NGINX_SITE"
            sed -i '/^[[:space:]]*location = \/mumble {/,/^[[:space:]]*}/d' "$NGINX_SITE"
            sed -i '/^[[:space:]]*location \/mumble\/ {/,/^[[:space:]]*}/d' "$NGINX_SITE"
            sed -i '/^[[:space:]]*# Mumble connection info endpoint/,/^[[:space:]]*}/d' "$NGINX_SITE"
        fi
        
        # Remove any orphaned mumble lines
        sed -i '/mumble/d' "$NGINX_SITE"
        
        # Clean up multiple blank lines
        sed -i '/^$/N;/^\n$/D' "$NGINX_SITE"
        
        # Test and reload nginx
        log "Testing nginx configuration..."
        if nginx -t 2>&1 | tee /tmp/nginx_test.log; then
            systemctl reload nginx
            log "✅ Nginx configuration successfully updated - Mumble routes removed"
        else
            warn "Nginx test failed! Restoring from backup..."
            if [ -f "$BACKUP_FILE" ]; then
                cp "$BACKUP_FILE" "$NGINX_SITE"
                if nginx -t 2>/dev/null; then
                    systemctl reload nginx
                    log "✅ Successfully restored previous nginx config"
                else
                    error "CRITICAL: Even backup config fails! Check nginx manually"
                    exit 1
                fi
            else
                error "No backup available! Manual intervention required"
                log "Check nginx config at: $NGINX_SITE"
                log "Previous error: $(cat /tmp/nginx_test.log)"
                exit 1
            fi
        fi
    fi
fi

# ============= REMOVE HELPER SCRIPT =============
if [ -f "/usr/local/bin/winejs-mumble" ]; then
    rm -f "/usr/local/bin/winejs-mumble"
    log "✅ Helper script removed"
fi

# ============= RELOAD WINEJS TRANSLATOR =============
log "Reloading WineJS translator..."
if command -v pm2 &> /dev/null; then
    pm2 restart translator 2>/dev/null || true
    log "✅ Translator reloaded"
fi

# ============= VERIFY REMOVAL =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              MUMBLE VOIP SERVER UNINSTALLED!                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
log "✅ Mumble VOIP Server has been completely removed"
echo ""
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_mumble.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           MUMBLE VOIP SERVER INSTALLED ON WINEJS!              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Mumble VOIP Server installed!"
echo ""
info "🌐 Connection Info Page:"
info "   • https://$DOMAIN_NAME/mumble/"
echo ""
info "🔗 Direct Connection:"
info "   • mumble://$DOMAIN_NAME:$APP_PORT/"
echo ""
info "🔑 Administrator Access:"
info "   • SuperUser Password: $SUPERUSER_PASSWORD"
if [ -n "$SERVER_PASSWORD" ]; then
    info "   • Server Password: $SERVER_PASSWORD"
fi
echo ""
info "📊 Server Configuration:"
info "   • Server Name: $SERVER_NAME"
info "   • Max Users: $MAX_USERS"
info "   • Max Bandwidth: $MAX_BANDWIDTH kbit/s"
info "   • Welcome Text: $WELCOME_TEXT"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-mumble open        # Open connection page"
info "   • winejs-mumble status      # Check server status"
info "   • winejs-mumble password    # Show SuperUser password"
info "   • winejs-mumble connect     # Show connection string"
info "   • winejs-mumble users       # List connected users"
echo ""
info "📱 Client Downloads:"
info "   • Desktop: https://www.mumble.info/downloads/"
info "   • Android: Plumble on Google Play"
info "   • iOS: Mumble on App Store"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_mumble.sh"
echo ""
success "✨ Mumble VOIP Server is ready! Visit https://$DOMAIN_NAME/mumble/ for connection info"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"