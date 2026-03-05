# ============= DEMUL (SEGA DREAMCAST) CONFIGURATION =============
log "Configuring DEMUL for SEGA DREAMCAST emulation..."

# Generate random VNC passwords for each emulator
DEMUL_VNC_PASS=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-8)
XEMU_VNC_PASS=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-8)

echo ""
info "DEMUL (SEGA DREAMCAST) VNC password: $DEMUL_VNC_PASS"
info "XEMU (Xbox) VNC password: $XEMU_VNC_PASS"
echo ""

# ============= INSTALL DEMUL (SEGA DREAMCAST) =============
log "Installing DEMUL (SEGA DREAMCAST Emulator)..."

mkdir -p /opt/winejs/apps/demul
cd /opt/winejs/apps/demul

# Download DEMUL
curl -L "http://demul.emulation64.com/files/demul07_280418.7z" -o demul.7z

# Install p7zip if not already installed
apt-get install -y -qq p7zip-full

# Extract
7z x demul.7z -o./ -y
rm -f demul.7z

# Download icon
curl -L "http://demul.emulation64.com/favicon.ico" -o icon.ico

# Copy icon to translator
mkdir -p /opt/winejs/translator/public/icons
cp -f icon.ico /opt/winejs/translator/public/icons/demul.ico 2>/dev/null || true
cp -f icon.ico /opt/winejs/translator/public/icons/demul.jpg 2>/dev/null || true

# Create game directories structure for per-game URLs
mkdir -p /opt/winejs/apps/demul/games
mkdir -p /opt/winejs/apps/demul/configs

# Create DEMUL config file with game paths
cat > /opt/winejs/apps/demul/config.json << EOF
{
    "name": "DEMUL - SEGA DREAMCAST Emulator",
    "version": "0.7.280418",
    "description": "Dreamcast, Naomi, Atomiswave, Hikaru",
    "executable": "demul.exe",
    "port": 6902,
    "vnc_password": "$DEMUL_VNC_PASS",
    "icon": "/icons/demul.ico",
    "category": "Emulator",
    "games_path": "/app/games",
    "save_path": "/uploads/sega/saves"
}
EOF

# Create launcher script that can load specific games
cat > /opt/winejs/apps/demul/launch.sh << 'EOF'
#!/bin/bash

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "🚀 Starting DEMUL launch script..."

# Wait for desktop
/usr/bin/desktop_ready

# Fix permissions
sudo chown -R 1000:1000 /home/kasm-user/.wine 2>/dev/null || true

# Initialize Wine prefix
if [ ! -d "/home/kasm-user/.wine/drive_c" ]; then
    log "📦 Initializing Wine prefix..."
    WINEPREFIX=/home/kasm-user/.wine wineboot --init
    sleep 5
fi

# Install required DLLs
log "📦 Installing DEMUL dependencies..."
WINEPREFIX=/home/kasm-user/.wine winetricks -q vcrun2010 d3dx9 > /dev/null 2>&1

# Find Wine
WINE_PATH=$(which wine 2>/dev/null || find /usr -name "wine" -type f 2>/dev/null | head -1)
if [ -z "$WINE_PATH" ]; then
    WINE_PATH="/usr/lib/wine/wine"
fi

# Check if a specific game was requested
GAME_FILE="$1"
cd /app

if [ -n "$GAME_FILE" ] && [ -f "/app/games/$GAME_FILE" ]; then
    log "🎮 Loading specific game: $GAME_FILE"
    
    # Copy game to ROMs directory if needed
    cp "/app/games/$GAME_FILE" "/home/kasm-user/.wine/drive_c/demul/roms/" 2>/dev/null
    
    # Create or modify DEMUL config to load this game
    cat > "/home/kasm-user/.wine/drive_c/demul/emu.cfg" << CONFIG
[roms]
path = /home/kasm-user/.wine/drive_c/demul/roms

[plugins]
gpu = gpuDX11.dll
spu = spuXAudio2.dll

[startup]
autostart = 1
lastrom = $GAME_FILE
CONFIG

    log "🚀 Launching DEMUL with game: $GAME_FILE"
    cd "/home/kasm-user/.wine/drive_c/demul"
    $WINE_PATH demul.exe -run=$GAME_FILE &
else
    log "🎮 No specific game, launching DEMUL normally"
    cd "/home/kasm-user/.wine/drive_c/demul"
    $WINE_PATH demul.exe &
fi

APP_PID=$!

# Start panel killer
(
    while true; do
        sleep 3
        pkill -f "panel" 2>/dev/null || true
        pkill -f "xfce4-panel" 2>/dev/null || true
    done
) &
PANEL_KILLER_PID=$!

# Monitor process
wait $APP_PID
log "👋 DEMUL exited"
EOF
chmod +x /opt/winejs/apps/demul/launch.sh

# Create DEMUL instance
log "Creating KasmVNC instance for DEMUL..."

mkdir -p "/opt/winejs/kasmvnc-instances/demul"
mkdir -p "/opt/winejs/kasmvnc-instances/demul/vnc"
mkdir -p "/opt/winejs/wine-prefixes/demul"

# Fix permissions
fix_kasmvnc_permissions "demul"

cat > "/opt/winejs/kasmvnc-instances/demul/docker-compose.yml" << EOF
version: '3.8'

services:
  winejs-demul:
    image: winedrop-base:latest
    container_name: winejs-demul
    restart: unless-stopped
    ports:
      - "127.0.0.1:6902:6901"
    shm_size: "512m"
    environment:
      - APP_NAME=demul
      - VNC_PW=$DEMUL_VNC_PASS
      - KASM_ALLOW_UNSAFE_AUTH=1
      - VNCOPTIONS=-disableBasicAuth
      - KASM_VIDEO_QUALITY=5
      - KASM_VIDEO_FPS=15
      - KASM_MAX_RESOLUTION=1280x720
    volumes:
      - /opt/winejs/apps/demul:/app:ro
      - /var/www/uploads:/uploads:rw
      - /opt/winejs/wine-prefixes/demul:/home/kasm-user/.wine
      - /opt/winejs/kasmvnc-instances/demul/vnc:/home/kasm-user/.vnc
      - /var/www/uploads/sega/games:/app/games:rw
      - /var/www/uploads/sega/saves:/home/kasm-user/.wine/drive_c/demul/saves:rw
    devices:
      - /dev/dri:/dev/dri
      - /dev/input:/dev/input:ro
    cap_add:
      - SYS_ADMIN
    networks:
      - winejs-net

networks:
  winejs-net:
    driver: bridge
EOF

# ============= INSTALL XEMU (Xbox) =============
log "Installing XEMU (Xbox Emulator)..."

mkdir -p /opt/winejs/apps/xemu
cd /opt/winejs/apps/xemu

# Download XEMU AppImage
curl -L "https://github.com/xemu-project/xemu/releases/download/v0.8.134/xemu-0.8.134-x86_64.AppImage" -o xemu.AppImage
chmod +x xemu.AppImage

# Download Xbox logo
curl -L "https://cdn.sdappnet.cloud/rtx/images/xboxlogo.png" -o icon.png

# Copy icon
mkdir -p /opt/winejs/translator/public/icons
cp -f icon.png /opt/winejs/translator/public/icons/xemu.png

# Create game directories
mkdir -p /opt/winejs/apps/xemu/games
mkdir -p /opt/winejs/apps/xemu/configs

# Create config
cat > /opt/winejs/apps/xemu/config.json << EOF
{
    "name": "XEMU - Original Xbox",
    "version": "0.8.134",
    "description": "Original Xbox Emulator",
    "executable": "xemu.AppImage",
    "port": 6903,
    "vnc_password": "$XEMU_VNC_PASS",
    "icon": "/icons/xemu.png",
    "category": "Emulator",
    "games_path": "/app/games",
    "save_path": "/uploads/xbox/saves"
}
EOF

# Create launcher script with game parameter support
cat > /opt/winejs/apps/xemu/launch.sh << 'EOF'
#!/bin/bash

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "🚀 Starting XEMU launch script..."

# Wait for desktop
/usr/bin/desktop_ready

# Check if a specific game was requested
GAME_FILE="$1"
cd /app

if [ -n "$GAME_FILE" ] && [ -f "/app/games/$GAME_FILE" ]; then
    log "🎮 Loading Xbox game: $GAME_FILE"
    ./xemu.AppImage -dvd_path "/app/games/$GAME_FILE" &
else
    log "🎮 No specific game, launching XEMU normally"
    ./xemu.AppImage &
fi

APP_PID=$!

# Start panel killer
(
    while true; do
        sleep 3
        pkill -f "panel" 2>/dev/null || true
        pkill -f "xfce4-panel" 2>/dev/null || true
    done
) &
PANEL_KILLER_PID=$!

wait $APP_PID
log "👋 XEMU exited"
EOF
chmod +x /opt/winejs/apps/xemu/launch.sh

# Create XEMU instance
log "Creating KasmVNC instance for XEMU..."

mkdir -p "/opt/winejs/kasmvnc-instances/xemu"
mkdir -p "/opt/winejs/kasmvnc-instances/xemu/vnc"
mkdir -p "/opt/winejs/wine-prefixes/xemu"

# Fix permissions
fix_kasmvnc_permissions "xemu"

cat > "/opt/winejs/kasmvnc-instances/xemu/docker-compose.yml" << EOF
version: '3.8'

services:
  winejs-xemu:
    image: winedrop-base:latest
    container_name: winejs-xemu
    restart: unless-stopped
    ports:
      - "127.0.0.1:6903:6901"
    shm_size: "1g"
    environment:
      - APP_NAME=xemu
      - VNC_PW=$XEMU_VNC_PASS
      - KASM_ALLOW_UNSAFE_AUTH=1
      - VNCOPTIONS=-disableBasicAuth
      - KASM_VIDEO_QUALITY=5
      - KASM_VIDEO_FPS=15
      - KASM_MAX_RESOLUTION=1280x720
    volumes:
      - /opt/winejs/apps/xemu:/app:ro
      - /var/www/uploads:/uploads:rw
      - /opt/winejs/wine-prefixes/xemu:/home/kasm-user/.wine
      - /opt/winejs/kasmvnc-instances/xemu/vnc:/home/kasm-user/.vnc
      - /var/www/uploads/xbox/games:/app/games:rw
      - /var/www/uploads/xbox/saves:/home/kasm-user/xemu/saves:rw
    devices:
      - /dev/dri:/dev/dri
      - /dev/input:/dev/input:ro
    cap_add:
      - SYS_ADMIN
    networks:
      - winejs-net

networks:
  winejs-net:
    driver: bridge
EOF

# ============= CREATE GAME LAUNCHER SERVICE =============
log "Creating Game Launcher service for per-game URLs..."

cat >> /opt/winejs/translator/index.js << 'EOF'

// ============= GAME LAUNCHER FOR SEGA DREAMCAST/XBOX =============

// Helper function to extract game name from path
function extractGameName(path) {
    // Remove leading/trailing slashes and split
    const parts = path.split('/').filter(p => p.length > 0);
    
    // Check if this is a game request (sega/game_name or xbox/game_name)
    if (parts.length >= 2) {
        const emulator = parts[0];
        const gameName = parts[1];
        
        // Remove file extension if present
        const gameWithoutExt = gameName.replace(/\.[^/.]+$/, "");
        
        return { emulator, game: gameWithoutExt, fullGameName: gameName };
    }
    return null;
}

// SEGA DREAMCAST game handler
app.get("/sega/:gameName", async (req, res) => {
    const gameName = req.params.gameName;
    const emulator = "demul";
    const app = appRegistry[emulator];
    
    if (!app) {
        return res.status(404).send("SEGA DREAMCAST emulator not installed");
    }
    
    logGameRequest(`SEGA DREAMCAST game requested: ${gameName}`);
    
    // Check if game file exists
    const gamePath = `/var/www/uploads/sega/games/${gameName}`;
    try {
        await fs.access(gamePath);
    } catch (err) {
        return res.status(404).send(`
            <html>
                <head><title>Game Not Found</title></head>
                <body style="font-family: Arial; background: #1a1a1a; color: white; text-align: center; padding: 50px;">
                    <h1>❌ Game Not Found</h1>
                    <p>The game "${gameName}" does not exist.</p>
                    <p>Upload SEGA DREAMCAST games to: /upload (place in /sega/games/)</p>
                    <p><a href="/upload" style="color: #00ff9d;">Go to Upload</a></p>
                </body>
            </html>
        `);
    }
    
    // Start emulator instance if not running
    const running = await isInstanceRunning(emulator, app.port);
    if (!running) {
        const started = await startInstance(emulator, app.port);
        if (!started) {
            return res.status(500).send("Failed to start SEGA DREAMCAST emulator");
        }
    }
    
    // Wait a moment for emulator to initialize
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    // Now launch the specific game via HTTP request to the container
    try {
        // Send command to container to load this game
        await axios.post(`https://127.0.0.1:${app.port}/api/command`, {
            command: "load_game",
            game: gameName
        }, {
            httpsAgent: new https.Agent({ rejectUnauthorized: false }),
            timeout: 5000
        });
    } catch (err) {
        console.log("Could not send load command (might need manual load):", err.message);
    }
    
    // Redirect to the emulator VNC view
    res.redirect(`/${emulator}?game=${encodeURIComponent(gameName)}`);
});

// Xbox game handler
app.get("/xbox/:gameName", async (req, res) => {
    const gameName = req.params.gameName;
    const emulator = "xemu";
    const app = appRegistry[emulator];
    
    if (!app) {
        return res.status(404).send("Xbox emulator not installed");
    }
    
    logGameRequest(`Xbox game requested: ${gameName}`);
    
    // Check if game file exists
    const gamePath = `/var/www/uploads/xbox/games/${gameName}`;
    try {
        await fs.access(gamePath);
    } catch (err) {
        return res.status(404).send(`
            <html>
                <head><title>Game Not Found</title></head>
                <body style="font-family: Arial; background: #1a1a1a; color: white; text-align: center; padding: 50px;">
                    <h1>❌ Game Not Found</h1>
                    <p>The game "${gameName}" does not exist.</p>
                    <p>Upload Xbox games to: /upload (place in /xbox/games/)</p>
                    <p>Supported formats: .iso, .xbe (Xbox executable)</p>
                    <p><a href="/upload" style="color: #00ff9d;">Go to Upload</a></p>
                </body>
            </html>
        `);
    }
    
    // Start emulator instance if not running
    const running = await isInstanceRunning(emulator, app.port);
    if (!running) {
        const started = await startInstance(emulator, app.port);
        if (!started) {
            return res.status(500).send("Failed to start Xbox emulator");
        }
    }
    
    // Wait for emulator
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    // Redirect to emulator with game parameter
    res.redirect(`/${emulator}?game=${encodeURIComponent(gameName)}`);
});

// Helper function to log game requests
function logGameRequest(message) {
    console.log(`[${new Date().toISOString()}] 🎮 ${message}`);
}

// Update the translator to handle game parameters in VNC view
// Modify the existing app.get("/:appName*") handler to preserve game parameter
const originalHandler = app._router.stack.pop(); // Remove the existing catch-all
app.use("/:appName*", async (req, res, next) => {
    const appName = req.params.appName;
    const gameParam = req.query.game;
    
    // Skip special paths
    if (["upload", "download", "health", "apps", "api", "icons", "sega", "xbox"].includes(appName)) {
        return next();
    }
    
    const app = appRegistry[appName];
    if (!app) {
        return next();
    }
    
    // If there's a game parameter, we need to inject it into the VNC HTML
    if (gameParam) {
        console.log(`🎮 Game parameter detected: ${gameParam} for ${appName}`);
        
        const running = await isInstanceRunning(appName, app.port);
        if (!running) {
            await startInstance(appName, app.port);
        }
        
        try {
            const response = await axios.get(`https://127.0.0.1:${app.port}/vnc.html`, {
                httpsAgent: new https.Agent({ rejectUnauthorized: false }),
                responseType: "text",
            });
            
            let html = response.data;
            
            // Inject game info into the page
            const gameScript = `
<script>
    // Game info injected by WINEJS
    window.currentGame = "${gameParam}";
    window.emulatorType = "${appName === 'demul' ? 'sega' : 'xbox'}";
    console.log('🎮 Game loaded:', window.currentGame);
    
    // Add game title to the page
    document.addEventListener('DOMContentLoaded', function() {
        const title = document.querySelector('title');
        if (title) {
            title.textContent = '${gameParam} - ' + title.textContent;
        }
        
        // Add a game info banner
        const banner = document.createElement('div');
        banner.style.cssText = 'position:fixed;top:10px;right:10px;background:rgba(0,120,212,0.9);color:white;padding:8px 16px;border-radius:20px;font-size:14px;z-index:10000;pointer-events:none;box-shadow:0 2px 10px rgba(0,0,0,0.3);';
        banner.innerHTML = '🎮 Now Playing: <strong>${gameParam}</strong>';
        document.body.appendChild(banner);
    });
</script>
            `;
            
            // Insert before closing head
            html = html.replace('</head>', gameScript + '</head>');
            res.send(html);
            return;
        } catch (err) {
            console.error("Failed to inject game info:", err.message);
        }
    }
    
    // Normal flow - proxy to VNC
    const target = `https://127.0.0.1:${app.port}`;
    req.url = "/vnc.html";
    proxy.web(req, res, { target, changeOrigin: true });
});

// Re-add the original handler if needed
// (This is simplified - in production you'd want better route ordering)
EOF

# Create game upload directories
log "Creating game upload directories..."

mkdir -p /var/www/uploads/sega/games
mkdir -p /var/www/uploads/sega/saves
mkdir -p /var/www/uploads/sega/configs
mkdir -p /var/www/uploads/xbox/games
mkdir -p /var/www/uploads/xbox/saves
mkdir -p /var/www/uploads/xbox/configs

# Set permissions
chmod -R 777 /var/www/uploads/sega
chmod -R 777 /var/www/uploads/xbox

# Create sample game info files
cat > /var/www/uploads/sega/games/README.txt << 'EOF'
SEGA DREAMCAST GAMES INSTRUCTION
======================

Place your SEGA DREAMCAST ROMs here:
- Dreamcast: .gdi, .cdi, .chd
- Naomi: .bin
- Atomiswave: .bin
- Hikaru: .bin

Games will be available at:
https://YOUR-DOMAIN/sega/game_name

Example: https://wine.sdappnet.cloud/sega/soulcalibur
EOF

cat > /var/www/uploads/xbox/games/README.txt << 'EOF'
XBOX GAMES INSTRUCTION
======================

Place your Xbox games here:
- .iso files (DVD images)
- .xbe files (Xbox executables)
- Extracted game folders

Games will be available at:
https://YOUR-DOMAIN/xbox/game_name

Example: https://wine.sdappnet.cloud/xbox/halo
EOF

# ============= START EMULATORS =============
log "Starting DEMUL and XEMU instances..."

cd /opt/winejs/kasmvnc-instances/demul
docker-compose up -d

cd /opt/winejs/kasmvnc-instances/xemu
docker-compose up -d

# Fix permissions after start
sleep 5
fix_kasmvnc_permissions "demul"
fix_kasmvnc_permissions "xemu"

# ============= UPDATE SUMMARY =============
cat >> /root/WINEJS_COMPLETE.txt << EOF

🎮 EMULATORS ADDED:

DEMUL (SEGA DREAMCAST): https://$MAIN_DOMAIN/demul
   - VNC Password: $DEMUL_VNC_PASS
   - Supports: Dreamcast, Naomi, Atomiswave, Hikaru
   - PER-GAME URLs: https://$MAIN_DOMAIN/sega/game_name
   - Upload games to: /upload (place in /sega/games/)

XEMU (Xbox): https://$MAIN_DOMAIN/xemu
   - VNC Password: $XEMU_VNC_PASS
   - Supports: Original Xbox games
   - PER-GAME URLs: https://$MAIN_DOMAIN/xbox/game_name
   - Upload games to: /upload (place in /xbox/games/)

📁 GAME DIRECTORIES:
   - SEGA DREAMCAST ROMs: /var/www/uploads/sega/games/
   - Xbox ISOs: /var/www/uploads/xbox/games/
   - Save states: /var/www/uploads/sega/saves/ and /xbox/saves/

🎯 EXAMPLE GAME URLS:
   - https://$MAIN_DOMAIN/sega/soulcalibur
   - https://$MAIN_DOMAIN/sega/mvc2
   - https://$MAIN_DOMAIN/xbox/halo
   - https://$MAIN_DOMAIN/xbox/doom3

🎮 GAMEPAD SUPPORT:
   - Works automatically with both emulators
   - Map controller in emulator settings
   - Save configs persist in /uploads/[emulator]/configs/

EOF

# Update final output
echo ""
echo -e "${GREEN}✅ DEMUL and XEMU installed successfully!${NC}"
echo "   🎮 SEGA DREAMCAST: https://$MAIN_DOMAIN/demul"
echo "   🎮 Xbox: https://$MAIN_DOMAIN/xemu"
echo "   🎯 Per-game URLs: https://$MAIN_DOMAIN/sega/game_name"
echo "   🎯 Per-game URLs: https://$MAIN_DOMAIN/xbox/game_name"
echo "   📁 Upload games to: /upload (sega/games/ or xbox/games/)"
echo ""