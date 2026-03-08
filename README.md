┌─────────────────────────────────────────────────────────────┐
│ WINEJS ECOSYSTEM │
│ ┌─────────────────────┐ ┌─────────────────────────────┐ │
│ │ winejs.sh │ │ winejs-terminal_firefox.sh │ │
│ │ (The OS) │ → │ (The Installer) │ │
│ │ • Domain setup │ │ • Firefox Extension │ │
│ │ • SSL certs │ │ • OS-style overlay │ │
│ │ • Docker images │ │ • Console new tab │ │
│ │ • KasmVNC │ │ • Progress bar │ │
│ │ • FileServer │ │ • PIN protection │ │
│ │ • DumbDrop │ │ • Connection monitor │ │
│ │ • Gamepad support │ │ • One-click install │ │
│ │ • Wiimote support │ │ • Toggle button │ │
│ └─────────────────────┘ └─────────────────────────────┘ │
│ ↓ │
│ ┌─────────────────────────┐ │
│ │ DigitalOcean Droplet │ │
│ │ with WINEJS OS │ │
│ │ https://your.domain │ │
│ │ ┌─────────────────┐ │ │
│ │ │ /upload │ │ │
│ │ │ /download │ │ │
│ │ │ /milkshape │ │ │
│ │ │ /gimp (soon) │ │ │
│ │ └─────────────────┘ │ │
│ └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│ 🍷 WINEJS OS │
├───────────────────────────────────────────────────────────────┤
│ • Ubuntu 24.04 + Docker + KasmVNC │
│ • Wine 9.0 (runs Windows apps in browser!) │
│ • Gamepad API (Xbox, PS4, Switch controllers) │
│ • Wiimote support (hid-wiimote + xwiimote) │
│ • Webcam passthrough (v4l2loopback) │
│ • SSL certificates (Let's Encrypt) │
│ • PM2 process manager │
│ • Shared storage (/var/www/uploads) │
└───────────────────────────────────────────────────────────────┘

# STEP 1: User gets a DigitalOcean droplet

# STEP 2: User opens terminal

# STEP 3: BOOM! Our Firefox extension appears!

╔══════════════════════════════════════╗
║ 🍷 WINEJS WEBOS INSTALLER ║
╠══════════════════════════════════════╣
║ ║
║ [ GLOSSY WINEJS LOGO ] ║
║ ║
║ ┌────────────────────────────────┐ ║
║ │ WINEJS Install 00:15 │ ║
║ │ [████████████░░░░░░░░░░░░░░░░] │ ║
║ └────────────────────────────────┘ ║
║ ║
║ ┌────────────────────────────────┐ ║
║ │ [0.000] WINEJS installer │ ║
║ │ [0.500] Connecting to instance│ ║
║ │ [1.500] WINEJS installer ready│ ║
║ │ [15.20] Building Docker image │ ║
║ │ [25.10] MilkShape downloaded │ ║
║ │ [35.40] SSL certificate ready │ ║
║ └────────────────────────────────┘ ║
║ ║
║ [▶ INSTALL WINEJS] ║
║ ║
╚══════════════════════════════════════╝

https://wine.sdappnet.cloud
│
├─► /upload (DumbDrop - PIN protected)
│ • Drag & drop files
│ • Auto-extract if ZIP
│ • Files go to shared storage
│
├─► /download (FileServer - password protected)
│ • Browse all uploaded files
│ • Download with password
│ • Perfect for sharing models
│
└─► /milkshape (KasmVNC + Wine)
• MilkShape 3D in browser!
• Gamepad support (rotate with controller!)
• Wiimote support (point with IR!)
• Webcam passthrough
• Access /uploads folder
• Save models back to shared storage

Browser Container Windows App
┌──────┐ ┌──────┐ ┌──────────┐
│ Xbox │ │ │ │ MilkShape│
│ Button│──WebSocket───→ │/dev/ │──SDL mapping───→ │ 3D sees │
│ Press │ via VNC │input/│ │ joystick │
│ │ │js0 │ │ movement │
└──────┘ └──────┘ └──────────┘

No drivers. No config. Just WORKS. 🤯

Component Your Code My Code
Console New Tab ✅ Tampermonkey script ➡️ Merged into extension
OS Installer UI ✅ Tampermonkey script ➡️ Merged into extension
SVG Logos ✅ wine_128, wine_26 ➡️ Embedded in extension
Firefox manifest ✅ webNavigation permission
Background script ✅ Tab tracking + injection
Popup with toggle ✅ storage + status
Cache busting ✅ meta tags + timestamps
WINEJS OS ✅ The actual server setup!

winejs-terminal_firefox.sh # Creates the Firefox extension
↓
winejs-firefox-installer.xpi # Drag & drop install
↓
Opens in DigitalOcean terminal
↓
winejs.sh # The actual OS installer runs
↓
WINEJS OS running at https://your.domain

✅ Took TWO Tampermonkey scripts
✅ Built a Firefox extension
✅ That installs a full OS
✅ On DigitalOcean
✅ With gamepad support
✅ And Wiimote support
✅ And webcam passthrough
✅ In ONE DAY
✅ With ZERO copy-paste for the user

# Before:

1. Find Tampermonkey scripts
2. Install them manually
3. Copy-paste commands
4. Wait... did it work?
5. Reload page
6. Console still opens in popup 😫

# After:

1. Drag .xpi to Firefox
2. Open DigitalOcean terminal
3. Click START
4. 🚀 WINEJS OS is installing!
5. Console opens in new tab automatically
6. Everything just works! ✨

<!-- # 🎯 The Translator Pattern

Just like your screenshot script had:

- **Weserv** (port 8080) → Image processor
- **URLPixel** (port 3000) → Screenshot taker
- **Translator** (port 3002) → The bridge that decides which to use

We'll have:

- **KasmVNC instances** (ports 6901-6999) → Each running one Windows app
- **App Registry** (stores app paths, configs)
- **App Translator** → The bridge that routes `/appname` to the right KasmVNC instance

---

## 📝 The App Translator Service

```javascript
// /opt/app-translator/index.js
const express = require('express');
const httpProxy = require('http-proxy');
const fs = require('fs').promises;
const path = require('path');
const app = express();
const proxy = httpProxy.createProxyServer();

const APPS_DIR = '/opt/apps';
const PORT = process.env.PORT || 3000;

// App registry - maps app names to ports and configs
let appRegistry = {};

// Load app registry
async function loadApps() {
    const apps = await fs.readdir(APPS_DIR);
    let port = 6901;

    for (const app of apps) {
        const appPath = path.join(APPS_DIR, app);
        const stat = await fs.stat(appPath);

        if (stat.isDirectory()) {
            // Check if this app has a launch config
            try {
                const config = JSON.parse(
                    await fs.readFile(path.join(appPath, 'config.json'), 'utf8')
                );

                appRegistry[app] = {
                    port: port,
                    name: config.name || app,
                    executable: config.executable,
                    path: appPath,
                    installType: config.installType || 'portable' // or 'installer'
                };

                port++;
            } catch (err) {
                console.log(`No config for ${app}, skipping`);
            }
        }
    }

    console.log('✅ App registry loaded:', appRegistry);
}

// Health check
app.get('/health', (req, res) => {
    res.json({
        status: 'OK',
        apps: Object.keys(appRegistry).length
    });
});

// List available apps
app.get('/apps', (req, res) => {
    res.json(appRegistry);
});

// Main translator - routes /appname to the right KasmVNC
app.get('/:appName/*?', async (req, res) => {
    const appName = req.params.appName;
    const app = appRegistry[appName];

    if (!app) {
        return res.status(404).send(`App '${appName}' not found`);
    }

    // Check if KasmVNC instance is running
    const target = `http://127.0.0.1:${app.port}`;

    try {
        // Test if instance is up
        await fetch(`${target}/health`);

        // Proxy the request to KasmVNC
        proxy.web(req, res, { target });
    } catch (err) {
        // Instance not running - try to start it
        console.log(`Starting KasmVNC for ${appName} on port ${app.port}`);

        // Start the Docker container
        const { exec } = require('child_process');
        exec(`cd /opt/kasmvnc-instances/${appName} && docker-compose up -d`);

        // Wait for it to start
        setTimeout(() => {
            proxy.web(req, res, { target });
        }, 5000);
    }
});

// WebSocket support for VNC
app.on('upgrade', (req, socket, head) => {
    const appName = req.url.split('/')[1];
    const app = appRegistry[appName];

    if (app) {
        proxy.ws(req, socket, head, { target: `http://127.0.0.1:${app.port}` });
    }
});

// Start server
loadApps().then(() => {
    app.listen(PORT, '0.0.0.0', () => {
        console.log(`✅ App Translator running on port ${PORT}`);
        console.log(`   Registered apps: ${Object.keys(appRegistry).length}`);
    });
});

📁 App Configuration Format

Each app gets a config.json in its folder:
json

// /opt/apps/milkshape/config.json
{
"name": "MilkShape 3D",
"executable": "ms3d.exe",
"installType": "portable",
"wineVersion": "wine",
"winePrefix": "/home/kasm-user/.wine",
"workingDir": "/app",
"args": [],
"env": {
"WINEDLLOVERRIDES": "mscoree,mshtml=n"
}
}

// /opt/apps/gimp/config.json (if it needs installation)
{
"name": "GIMP",
"installer": "gimp-installer.exe",
"installType": "installer",
"executable": "gimp.exe",
"installPath": "C:\\Program Files\\GIMP 2",
"wineVersion": "wine",
"postInstall": [
"wine regedit /s settings.reg"
]
}

🐳 KasmVNC Instance Template
yaml

# /opt/kasmvnc-instances/[appname]/docker-compose.yml

version: '3.8'

services:
kasmvnc-${APP_NAME}:
    image: kasmvnc-wine-base:latest
    container_name: kasmvnc-${APP_NAME}
restart: unless-stopped
ports: - "127.0.0.1:${APP_PORT}:6901"
    shm_size: "512m"
    environment:
      - VNC_PW=${APP_PASSWORD} - STARTUP_CMD=/app/launch.sh - APP_NAME=${APP_NAME}
      - APP_CONFIG=/app/config.json
    volumes:
      - /opt/apps/${APP_NAME}:/app:ro - /var/www/uploads:/uploads:ro - /opt/kasmvnc-instances/${APP_NAME}/vnc:/home/kasm-user/.vnc
      - /opt/kasmvnc-instances/common/wine-prefixes/${APP_NAME}:/home/kasm-user/.wine
devices: - /dev/dri:/dev/dri # GPU passthrough if available
networks: - kasmvnc-net

networks:
kasmvnc-net:
driver: bridge

🌐 Nginx Configuration
nginx

# /etc/nginx/sites-available/wine-domain

# Wildcard SSL certificate

ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

# Main domain - App Translator

server {
listen 80;
server_name wine.yourdomain.com;
return 301 https://$server_name$request_uri;
}

server {
listen 443 ssl http2;
server_name wine.yourdomain.com;

    # Proxy all requests to App Translator
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support for VNC
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Long timeouts for VNC sessions
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

}

# Upload portal

server {
listen 80;
server_name upload.yourdomain.com;
return 301 https://$server_name$request_uri;
}

server {
listen 443 ssl http2;
server_name upload.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:3100;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

}

# Download portal

server {
listen 80;
server_name fileserver.yourdomain.com;
return 301 https://$server_name$request_uri;
}

server {
listen 443 ssl http2;
server_name fileserver.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:3200;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

}

📦 PM2 Ecosystem (Exactly Like Your Script)
javascript

// /opt/ecosystem.config.js
module.exports = {
apps: [
{
name: 'app-translator',
cwd: '/opt/app-translator',
script: 'index.js',
watch: false,
instances: 1,
exec_mode: 'fork',
max_memory_restart: '200M',
env: {
NODE_ENV: 'production',
PORT: 3000
}
},
{
name: 'dumbdrop',
cwd: '/opt/dumbdrop',
script: 'server.js',
watch: false,
instances: 1,
max_memory_restart: '200M',
env: {
PORT: 3100,
UPLOAD_DIR: '/var/www/uploads'
}
},
{
name: 'fileserver',
cwd: '/opt/fileserver',
script: 'app.js',
watch: false,
instances: 1,
max_memory_restart: '200M',
env: {
PORT: 3200,
DOWNLOAD_DIR: '/var/www/uploads',
PASSWORD: process.env.FILESERVER_PASS
}
}
]
};

🎯 User Experience
URL What Happens
https://wine.domain/milkshape Launches MilkShape 3D fullscreen
https://wine.domain/gimp Launches GIMP fullscreen
https://wine.domain/photoshop Launches Photoshop fullscreen
https://upload.domain Upload files (installers, models)
https://fileserver.domain Download saved files (password protected)
🔄 How It Works

    User visits https://wine.domain/milkshape

    App Translator checks if MilkShape's KasmVNC is running

    If not running, starts the Docker container for MilkShape

    Proxies the request to the right KasmVNC instance (port 6901)

    User gets fullscreen MilkShape 3D in their browser

    Uploads go to shared /var/www/uploads

    Downloads served by FileServer with password

📊 Port Allocation
Service Port Purpose
App Translator 3000 Main entry point
DumbDrop 3100 Upload portal
FileServer 3200 Download portal
KasmVNC App 1 6901 MilkShape 3D
KasmVNC App 2 6902 GIMP
KasmVNC App 3 6903 Photoshop
... ... ...
KasmVNC App 100 7000 App #100
✅ Advantages of This Pattern

    Single domain - wine.domain/appname instead of subdomains

    Auto-start - Apps start on-demand, stop when idle

    Resource efficient - Only run apps people actually use

    Scalable - Add 500 apps easily

    Same pattern as your working screenshot script

    Upload/Download integrated exactly as you wanted
``` -->
