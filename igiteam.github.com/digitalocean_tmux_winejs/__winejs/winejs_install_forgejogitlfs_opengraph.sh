#!/bin/bash
# ============================================
# WineJS Forgejo Installer
# Adds Forgejo Git Service to WineJS Platform
# ============================================
# App: Forgejo Git Server
# Category: Development
# Features: Git Repositories, LFS Support, Issue Tracker, CI/CD
# ============================================

# What this script does:
#     ✓ Verifies WineJS platform - Checks if /opt/winejs exists
#     ✓ Creates docker network - Creates winejs-net if missing
#     ✓ Creates all necessary directories with data persistence
#     ✓ Downloads/Configures Forgejo - Latest version with Git LFS support
#     ✓ Creates Git LFS path mapping server for large file handling
#     ✓ Sets up shared volumes system (like Docker mounts)
#     ✓ Creates launch.sh with auto-heal monitor
#     ✓ Creates config.json with all app metadata
#     ✓ Creates docker-compose.yml with volume mounts
#     ✓ Sets up automated backup system
#     ✓ Creates uninstall script with cleanup
#     ✓ Sets up PM2 for LFS mapper persistence
#     ✓ Creates CLI helper tools
#     ✓ Installs Git hooks for WineJS integration
#     ✓ Restarts translator and starts containers

# FORGEJO MODDING STARTS at line 1162 # ============= INJECT
# here you can mod the forgejo before installat

APP_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/gitlfs.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }
header() { echo -e "${CYAN}$1${NC}"; }

log "🚀 Installing WineJS Forgejo Server..."

# ============= VERIFY WINEJS PLATFORM =============
log "Verifying WineJS platform..."

if [ ! -d "/opt/winejs" ]; then
    error "WineJS platform not found at /opt/winejs"
    exit 1
fi

# Ensure winejs-net network exists and is properly created
log "Checking winejs-net network..."
if docker network ls | grep -q "winejs-net"; then
    log "✅ winejs-net network already exists"
    # Verify the network is actually usable
    if ! docker network inspect winejs-net &>/dev/null; then
        log "⚠️ Network exists but is corrupted, recreating..."
        docker network rm winejs-net 2>/dev/null || true
        docker network create winejs-net
        log "✅ winejs-net network recreated"
    fi
else
    log "Creating winejs-net network..."
    docker network create winejs-net
    if [ $? -eq 0 ]; then
        log "✅ winejs-net network created"
    else
        error "Failed to create winejs-net network"
    fi
fi

# Final verification
if ! docker network inspect winejs-net &>/dev/null; then
    error "winejs-net network is not available. Please run: docker network create winejs-net"
fi

# ============= GET DOMAIN FROM WINEJS CONFIG =============
# Get domain from existing WineJS config
if [ -f "/opt/winejs/translator/index.js" ]; then
    # Extract just the domain value, removing quotes and the variable assignment
    DOMAIN_NAME=$(grep "const DOMAIN_NAME" /opt/winejs/translator/index.js | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/")
fi

if [ -z "$DOMAIN_NAME" ]; then
    read -p "Enter your WineJS domain (e.g., wine.yourdomain.com): " DOMAIN_NAME
fi

# Clean up any quotes or whitespace
DOMAIN_NAME=$(echo "$DOMAIN_NAME" | tr -d '"' | tr -d "'" | xargs)

info "Using domain: $DOMAIN_NAME"

# ============= ASK FOR ADMIN DETAILS =============
if [ -z "$ADMIN_EMAIL" ]; then
    read -p "Enter admin email: " ADMIN_EMAIL
fi

if [ -z "$ADMIN_PASSWORD" ]; then
    read -s -p "Enter admin password: " ADMIN_PASSWORD
    echo ""
fi

# ============= FIND NEXT AVAILABLE PORT =============
log "Finding next available port..."

# Function to check if a port is in use
port_in_use() {
    local port=$1
    # Check if port is bound by any process
    if ss -tln | grep -q ":$port " || netstat -tln 2>/dev/null | grep -q ":$port "; then
        return 0
    fi
    # Check if Docker is using this port
    if docker ps 2>/dev/null | grep -q ":$port->"; then
        return 0
    fi
    return 1
}

# Start checking from 6901
START_PORT=6901
MAX_RETRIES=100
APP_PORT=""
LFS_MAPPER_PORT=""

# Check existing ports from config.json files
declare -a USED_PORTS
if [ -d "/opt/winejs/apps" ]; then
    for config in /opt/winejs/apps/*/config.json; do
        if [ -f "$config" ]; then
            PORT=$(grep -o '"port": [0-9]*' "$config" | awk '{print $2}')
            if [ -n "$PORT" ]; then
                USED_PORTS+=($PORT)
            fi
        fi
    done
fi

# Find available port for Forgejo
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    # Skip if port is in config.json
    if [[ " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]]; then
        continue
    fi
    # Skip if port is in use
    if ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

# Find available port for LFS Mapper (start from APP_PORT+1)
if [ -n "$APP_PORT" ]; then
    for i in $(seq 1 $MAX_RETRIES); do
        TEST_PORT=$((APP_PORT + i))
        if [[ " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]]; then
            continue
        fi
        if ! port_in_use $TEST_PORT; then
            LFS_MAPPER_PORT=$TEST_PORT
            break
        fi
    done
fi

if [ -z "$APP_PORT" ] || [ -z "$LFS_MAPPER_PORT" ]; then
    error "Could not find available ports"
fi

log "Using ports: Forgejo=$APP_PORT, LFSMapper=$LFS_MAPPER_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="forgejo"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
FORGEJO_DATA="/opt/winejs/data/forgejo"
FORGEJO_CONFIG="/opt/winejs/config/forgejo"
ICON_DIR="/opt/winejs/translator/public/icons"
REPO_DIR="/opt/winejs/repositories"
SHARED_VOLUMES="/opt/winejs/shared-volumes"
LFS_MAPPER_DIR="/opt/winejs/lfs-mapper"

mkdir -p "$APP_DIR"
mkdir -p "$INSTANCE_DIR"
mkdir -p "$FORGEJO_DATA"/{gitea,git,repositories,lfs}
mkdir -p "$FORGEJO_CONFIG"
mkdir -p "$ICON_DIR"
mkdir -p "$REPO_DIR"
mkdir -p "$SHARED_VOLUMES"/{backups,imports,exports,ci-cd}
mkdir -p "$SHARED_VOLUMES"/ogimages
mkdir -p "$SHARED_VOLUMES"/ogimages/cache
mkdir -p "$SHARED_VOLUMES"/webhooks
mkdir -p "$LFS_MAPPER_DIR"

# ============= FIX PERMISSIONS FOR FORGEJO =============
log "🔧 Fixing permissions for Forgejo..."

# Create the .ssh directory with correct permissions
mkdir -p /opt/winejs/repositories/.ssh
chown -R 1000:1000 /opt/winejs/repositories
chmod 700 /opt/winejs/repositories/.ssh

# Fix all Forgejo directories
chown -R 1000:1000 "$FORGEJO_DATA"
chown -R 1000:1000 "$FORGEJO_CONFIG"
chown -R 1000:1000 "$REPO_DIR"
chmod -R 755 "$FORGEJO_DATA"
chmod -R 755 "$FORGEJO_CONFIG"

# ALSO create SSH directory inside Forgejo data (critical!)
mkdir -p "$FORGEJO_DATA/git/.ssh"
chown -R 1000:1000 "$FORGEJO_DATA/git"
chmod 700 "$FORGEJO_DATA/git/.ssh"

log "✅ Permissions fixed for Forgejo"

cd "$APP_DIR"

# Generate LFS JWT secret
LFS_JWT_SECRET=$(openssl rand -hex 32)

# ============= CREATE FORGEJO CONFIGURATION =============
log "📝 Creating Forgejo configuration..."

cat > "$FORGEJO_CONFIG/app.ini" << CONF_EOF
APP_NAME = WineJS Forgejo
RUN_USER = git
RUN_MODE = prod

[database]
DB_TYPE = sqlite3
PATH = /data/gitea/gitea.db

[repository]
ROOT = /data/git/repositories
DEFAULT_PRIVATE = private
DEFAULT_BRANCH = main

[server]
DOMAIN = ${DOMAIN_NAME}
HTTP_PORT = 3000
ROOT_URL = https://${DOMAIN_NAME}/forgejo/
HTTP_ADDR = 0.0.0.0
SSH_DOMAIN = ${DOMAIN_NAME}
SSH_PORT = 22
LFS_START_SERVER = true
LFS_CONTENT_PATH = /data/git/lfs
LOCAL_ROOT_URL = http://localhost:3000/

[lfs]
JWT_SECRET = ${LFS_JWT_SECRET}
MAX_FILE_SIZE = 1073741824

[security]
INSTALL_LOCK = true
SECRET_KEY = $(openssl rand -base64 32)

[service]
DISABLE_REGISTRATION = false
REQUIRE_SIGNIN_VIEW = false
ENABLE_CAPTCHA = false

[mailer]
ENABLED = false

[log]
MODE = console
LEVEL = info

[webhook]
ALLOWED_HOST_LIST = *
CONFIG_SUCCESS_URL = https://${DOMAIN_NAME}/forgejo

[cron]
ENABLED = true
RUN_AT_START = true
SCHEDULE = @every 24h

[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = https://codeberg.org
CONFIG_SUCCESS_URL = https://${DOMAIN_NAME}/forgejo
CONF_EOF

chown -R 1000:1000 "$FORGEJO_DATA" "$FORGEJO_CONFIG"

# ============= CREATE LFS MAPPING SERVER =============
log "📡 Creating Git LFS path mapping server..."

cat > "$LFS_MAPPER_DIR/package.json" << 'EOF'
{
    "name": "winejs-lfs-mapper",
    "version": "1.0.0",
    "description": "Git LFS path mapping server for WineJS Forgejo integration",
    "main": "server.js",
    "dependencies": {
        "express": "^4.18.2",
        "cors": "^2.8.5",
        "multer": "^1.4.5-lts.1"
    }
}
EOF

cat > "$LFS_MAPPER_DIR/server.js" << EOF
const express = require('express');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const multer = require('multer');
const http = require('http');

// Try to load canvas, but don't fail if not available
let createCanvas;
try {
    const canvas = require('canvas');
    createCanvas = canvas.createCanvas;
} catch (e) {
    console.log('Canvas module not available, using fallback mode');
    createCanvas = null;
}

const crypto = require('crypto');

const app = express();
const PORT = process.env.PORT || 3002;
const DOMAIN = '${DOMAIN_NAME}';

// Add OG_CACHE_DIR constant after DOMAIN
// Ensure OG cache directory exists
const OG_CACHE_DIR = '/opt/winejs/shared-volumes/ogimages/cache';
if (!fs.existsSync(OG_CACHE_DIR)) {
    fs.mkdirSync(OG_CACHE_DIR, { recursive: true });
}

// Configure multer for file uploads
const upload = multer({ dest: '/opt/winejs/shared-volumes/uploads/' });

app.use(cors());
app.use(express.json());
app.use('/icons', express.static('/opt/winejs/translator/public/icons'));


// Path mappings for repositories
const REPO_MAPPINGS = {
    '/repos': '/opt/winejs/repositories',
    '/forgejo/repos': '/opt/winejs/repositories',
    '/forgejo/data': '/opt/winejs/data/forgejo',
    '/winejs/repos': '/opt/winejs/repositories',
    '/winejs/data': '/opt/winejs/data',
    '/lfs-storage': '/opt/winejs/data/forgejo/lfs',
    '/backups': '/opt/winejs/shared-volumes/backups',
    '/webhooks': '/opt/winejs/shared-volumes/webhooks',
    '/api/webhooks': '/opt/winejs/shared-volumes/webhooks',
    '/ogimage': '/opt/winejs/shared-volumes/ogimages',
    '/api/ogimage': '/opt/winejs/shared-volumes/ogimages',
    '/api/v1/repos': '/opt/winejs/repositories',  // For Forgejo API proxy
    '/forgejo/api/v1': '/opt/winejs/data/forgejo',  // Forgejo API access
    '/og-images': '/opt/winejs/shared-volumes/ogimages/cache'  // Cached OG images
};

function resolvePath(reqPath) {
    for (const [shortcut, realPath] of Object.entries(REPO_MAPPINGS)) {
        if (reqPath === shortcut || reqPath.startsWith(shortcut + '/')) {
            const relativePath = reqPath.substring(shortcut.length);
            const fullPath = path.join(realPath, relativePath);
            return {
                fullPath: fullPath,
                exists: fs.existsSync(fullPath),
                isDirectory: fs.existsSync(fullPath) && fs.statSync(fullPath).isDirectory()
            };
        }
    }
    return { fullPath: reqPath, exists: false };
}

// List repositories
app.get('/api/repos', (req, res) => {
    const reposPath = '/opt/winejs/repositories';
    if (!fs.existsSync(reposPath)) {
        return res.json({ repos: [] });
    }
    
    try {
        const repos = fs.readdirSync(reposPath)
            .filter(item => fs.statSync(path.join(reposPath, item)).isDirectory())
            .map(repo => ({
                name: repo,
                path: path.join(reposPath, repo),
                url: \`https://\${DOMAIN}/forgejo/\${repo}\`
            }));
        res.json({ repos });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Browse repositories and files
app.get('/api/browse', (req, res) => {
    const browsePath = req.query.path || '/opt/winejs/repositories';
    const { fullPath, exists } = resolvePath(browsePath);
    
    if (!exists) {
        return res.status(404).json({ error: 'Path not found' });
    }
    
    try {
        const items = fs.readdirSync(fullPath)
            .filter(item => !item.startsWith('.'))
            .map(item => {
                const itemPath = path.join(fullPath, item);
                const stats = fs.statSync(itemPath);
                return {
                    name: item,
                    path: itemPath,
                    isDirectory: stats.isDirectory(),
                    size: stats.size,
                    modified: stats.mtime
                };
            });
        res.json(items);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Clone repository helper
app.post('/api/clone', express.json(), (req, res) => {
    const { repoUrl, targetName } = req.body;
    
    if (!repoUrl) {
        return res.status(400).json({ error: 'Repository URL required' });
    }
    
    const repoName = targetName || path.basename(repoUrl, '.git');
    const targetPath = path.join('/opt/winejs/repositories', repoName);
    
    res.json({
        success: true,
        message: 'Clone initiated',
        command: \`git clone \${repoUrl} \${targetPath}\`,
        targetPath: targetPath
    });
});

// OpenGraph image generation endpoint (GitHub-style)
app.get('/api/ogimage/:owner/:repo', async (req, res) => {
    const { owner, repo } = req.params;
    
    try {
        // Try to fetch repo info from Forgejo API
        const forgejoApi = \`http://winejs-forgejo:3000/api/v1/repos/\${owner}/\${repo}\`;
        let description = '';
        let stars = 0;
        
        try {
            const response = await fetch(forgejoApi);
            if (response.ok) {
                const data = await response.json();
                description = data.description || \`\${owner}/\${repo} - Git repository on WineJS Forgejo\`;
                stars = data.stars_count || 0;
            }
        } catch (error) {
            description = \`\${owner}/\${repo} - Git repository with issue tracking and CI/CD\`;
        }
        
        // Create canvas for OG image (1200x630)
        const canvas = createCanvas(1200, 630);
        const ctx = canvas.getContext('2d');
        
        // Background gradient
        const gradient = ctx.createLinearGradient(0, 0, 0, canvas.height);
        gradient.addColorStop(0, '#1a1e24');
        gradient.addColorStop(1, '#2d3748');
        ctx.fillStyle = gradient;
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        
        // Draw accent line
        ctx.fillStyle = '#f9826c';
        ctx.fillRect(0, 0, canvas.width, 8);
        
        // Draw repository icon/avatar
        ctx.fillStyle = '#ffffff';
        ctx.font = '80px -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif';
        ctx.fillText('📦', 80, 200);
        
        // Draw owner/repo name
        ctx.fillStyle = '#ffffff';
        ctx.font = 'Bold 52px -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif';
        ctx.fillText(\`\${owner}/\${repo}\`, 180, 190);
        
        // Draw description
        ctx.font = '28px -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif';
        ctx.fillStyle = '#e1e4e8';
        
        // Word wrap description
        const words = description.split(' ');
        let lines = [];
        let currentLine = '';
        
        for (let word of words) {
            const testLine = currentLine + (currentLine ? ' ' : '') + word;
            const metrics = ctx.measureText(testLine);
            if (metrics.width > 800) {
                lines.push(currentLine);
                currentLine = word;
            } else {
                currentLine = testLine;
            }
        }
        lines.push(currentLine);
        
        let y = 280;
        for (let line of lines.slice(0, 3)) {
            ctx.fillText(line, 80, y);
            y += 45;
        }
        
        // Draw stats
        ctx.font = '24px -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif';
        ctx.fillStyle = '#f9826c';
        ctx.fillText(\`★ \${stars.toLocaleString()} stars\`, 80, 480);
        
        // Draw footer
        ctx.font = '20px -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif';
        ctx.fillStyle = '#6a737d';
        ctx.fillText('WineJS Forgejo · Git Repository Hosting', 80, 580);
        
        // Draw WineJS logo
        ctx.fillStyle = '#ffffff';
        ctx.font = '24px monospace';
        ctx.fillText('⊞', 80, 560);
        
        // Set response headers
        res.setHeader('Content-Type', 'image/png');
        res.setHeader('Cache-Control', 'public, max-age=86400'); // Cache for 1 day
        
        // Send PNG
        canvas.createPNGStream().pipe(res);
        
    } catch (error) {
        console.error('OG image generation error:', error);
        res.status(500).send('Error generating image');
    }
});

// Also add route for the Forgejo API proxy for OG images
// Make sure this route is BEFORE the catch-all routes
// Also add route for the Forgejo API proxy for OG images
app.get('/api/v1/repos/:owner/:repo/ogimage', async (req, res) => {
    const { owner, repo } = req.params;
    
    try {
        // Copy the working code from /api/ogimage endpoint
        const forgejoApi = \`http://winejs-forgejo:3000/api/v1/repos/\${owner}/\${repo}\`;
        let description = '';
        let stars = 0;
        
        try {
            const response = await fetch(forgejoApi);
            if (response.ok) {
                const data = await response.json();
                description = data.description || \`\${owner}/\${repo} - Git repository on WineJS Forgejo\`;
                stars = data.stars_count || 0;
            }
        } catch (error) {
            description = \`\${owner}/\${repo} - Git repository with issue tracking and CI/CD\`;
        }
        
        const canvas = createCanvas(1200, 630);
        const ctx = canvas.getContext('2d');
        
        const gradient = ctx.createLinearGradient(0, 0, 0, canvas.height);
        gradient.addColorStop(0, '#1a1e24');
        gradient.addColorStop(1, '#2d3748');
        ctx.fillStyle = gradient;
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        
        ctx.fillStyle = '#f9826c';
        ctx.fillRect(0, 0, canvas.width, 8);
        
        ctx.fillStyle = '#ffffff';
        ctx.font = '80px -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif';
        ctx.fillText('📦', 80, 200);
        
        ctx.fillStyle = '#ffffff';
        ctx.font = 'Bold 52px -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif';
        ctx.fillText(\`\${owner}/\${repo}\`, 180, 190);
        
        ctx.font = '28px -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif';
        ctx.fillStyle = '#e1e4e8';
        
        const words = description.split(' ');
        let lines = [];
        let currentLine = '';
        
        for (let word of words) {
            const testLine = currentLine + (currentLine ? ' ' : '') + word;
            const metrics = ctx.measureText(testLine);
            if (metrics.width > 800) {
                lines.push(currentLine);
                currentLine = word;
            } else {
                currentLine = testLine;
            }
        }
        lines.push(currentLine);
        
        let y = 280;
        for (let line of lines.slice(0, 3)) {
            ctx.fillText(line, 80, y);
            y += 45;
        }
        
        ctx.font = '24px -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif';
        ctx.fillStyle = '#f9826c';
        ctx.fillText(\`★ \${stars.toLocaleString()} stars\`, 80, 480);
        
        ctx.font = '20px -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif';
        ctx.fillStyle = '#6a737d';
        ctx.fillText('WineJS Forgejo · Git Repository Hosting', 80, 580);
        
        ctx.fillStyle = '#ffffff';
        ctx.font = '24px monospace';
        ctx.fillText('⊞', 80, 560);
        
        res.setHeader('Content-Type', 'image/png');
        res.setHeader('Cache-Control', 'public, max-age=86400');
        canvas.createPNGStream().pipe(res);
        
    } catch (error) {
        console.error('OG image generation error:', error);
        res.status(500).send('Error generating image');
    }
});

app.post('/api/webhooks/repo-info', express.json(), (req, res) => {
    const repoData = req.body;
    
    console.log('Received repository info:', repoData.full_name);
    
    // Store in a database or file
    const webhookLogPath = '/opt/winejs/shared-volumes/webhooks/repo-info.jsonl';
    require('fs').appendFileSync(
        webhookLogPath,
        JSON.stringify({ timestamp: new Date().toISOString(), data: repoData }) + '\n'
    );
    
    res.json({ 
        success: true, 
        message: \`Repository info for \${repoData.full_name} received\`,
        received_at: new Date().toISOString()
    });
});

// LFS upload endpoint
app.post('/api/lfs/upload', upload.single('file'), (req, res) => {
    if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
    }
    
    res.json({
        success: true,
        file: req.file,
        message: 'File uploaded to LFS storage'
    });
});

// Health check
app.get('/health', (req, res) => {
    res.json({ 
        status: 'ok', 
        port: PORT, 
        forgejoPort: process.env.FORGEJO_PORT,
        domain: DOMAIN,
        lfsEnabled: true
    });
});

// Cache cleanup endpoint
app.delete('/api/ogimage/cache/:owner/:repo', (req, res) => {
    const { owner, repo } = req.params;
    const cacheKey = crypto.createHash('md5')
        .update(\`\${owner}/\${repo}-\${new Date().toDateString()}\`)
        .digest('hex');
    const cachePath = path.join(OG_CACHE_DIR, \`\${cacheKey}.png\`);
    
    if (fs.existsSync(cachePath)) {
        fs.unlinkSync(cachePath);
        res.json({ success: true, message: 'Cache cleared' });
    } else {
        res.json({ success: false, message: 'Cache not found' });
    }
});

// Stats endpoint
app.get('/api/stats', (req, res) => {
    const ogCacheDir = '/opt/winejs/shared-volumes/ogimages/cache';
    let cachedImages = 0;
    
    if (fs.existsSync(ogCacheDir)) {
        cachedImages = fs.readdirSync(ogCacheDir).filter(f => f.endsWith('.png')).length;
    }
    
    res.json({
        uptime: process.uptime(),
        memory: process.memoryUsage(),
        cached_og_images: cachedImages,
        version: '1.0.0'
    });
});

app.listen(PORT, () => {
    console.log(\`✅ WineJS LFS Mapper running on port \${PORT}\`);
    console.log(\`🌐 Forgejo URL: https://\${DOMAIN}/forgejo\`);
});
EOF

# Install Node dependencies for LFS mapper
log "📦 Installing LFS mapper dependencies..."
cd "$LFS_MAPPER_DIR"
npm install canvas node-fetch@2
npm install --production

# ============= CREATE SHARED VOLUMES SYSTEM =============
log "📦 Setting up shared volumes (like Docker mounts)..."

cat > "$SHARED_VOLUMES/mounts.conf" << EOF
# Shared Volume Mounts Configuration for Forgejo
# Format: mount_point:host_path:container_path

# Forgejo repositories
repos:$REPO_DIR:/repositories

# Forgejo data
forgejo-data:$FORGEJO_DATA:/data

# Forgejo config
forgejo-config:$FORGEJO_CONFIG:/etc/forgejo

# Backups mount
backups:$SHARED_VOLUMES/backups:/backups

# Imports mount
imports:$SHARED_VOLUMES/imports:/imports

# CI/CD artifacts
ci-cd:$SHARED_VOLUMES/ci-cd:/ci-cd
EOF

# Create mount helper script
cat > "$SHARED_VOLUMES/mount-helper.sh" << 'EOF'
#!/bin/bash
# Volume mount helper - like Docker volumes

MOUNT_CONFIG="/opt/winejs/shared-volumes/mounts.conf"

if [ ! -f "$MOUNT_CONFIG" ]; then
    echo "Error: Mount config not found"
    exit 1
fi

case "$1" in
    list)
        echo "Available mounts:"
        cat "$MOUNT_CONFIG" | grep -v '^#' | awk -F: '{print "  " $1 " -> " $2 " -> " $3}'
        ;;
    mount)
        MOUNT_NAME="$2"
        grep "^$MOUNT_NAME:" "$MOUNT_CONFIG" | while IFS=: read name host container; do
            echo "Mounting $name: $host -> $container"
            if [ -d "$host" ]; then
                echo "  ✅ Mount point ready: $host"
            else
                echo "  ⚠️  Host path doesn't exist, creating: $host"
                mkdir -p "$host"
            fi
        done
        ;;
    *)
        echo "Usage: mount-helper {list|mount <name>}"
        ;;
esac
EOF

chmod +x "$SHARED_VOLUMES/mount-helper.sh"

# ============= DOWNLOAD ICON =============
log "Downloading app icon..."
curl -L "$APP_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon, using default"

# ============= CREATE LAUNCH SCRIPT WITH AUTO-HEAL =============
log "Generating launch.sh with auto-heal monitor..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash

# ============================================
# WineJS Forgejo Server Launcher with Auto-Heal
# ============================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "🚀 Starting WineJS Forgejo Server..."

# ============= CONFIGURATION =============
FORGEJO_DATA="/data"
FORGEJO_CONFIG="/etc/forgejo"
REPO_PATH="/repositories"
PORT=3000

# Create required directories
mkdir -p "$FORGEJO_DATA"/{gitea,git,repositories,lfs}
mkdir -p "$FORGEJO_CONFIG"
mkdir -p "$REPO_PATH"

# ============= START AUTO-HEAL MONITOR =============
log "🔄 Starting auto-heal monitor..."

(
    while true; do
        sleep 30
        if ! pgrep -f "forgejo" > /dev/null; then
            log "⚠️ Forgejo crashed! Restarting..."
            /usr/local/bin/forgejo web --port $PORT --config $FORGEJO_CONFIG/app.ini &
        fi
        # Check if git-lfs is running
        if ! pgrep -f "git-lfs" > /dev/null; then
            log "⚠️ Git LFS not running, restarting..."
            git lfs install --system
        fi
    done
) &
AUTO_HEAL_PID=$!
log "✅ Auto-heal monitor started (PID: $AUTO_HEAL_PID)"

# ============= SETUP GIT HOOKS =============
log "🔧 Setting up Git hooks for WineJS integration..."

cat > "/usr/local/bin/forgejo-webhook" << 'HOOK_EOF'
#!/bin/bash
# WineJS Forgejo webhook handler
WEBHOOK_URL="https://${DOMAIN}/forgejo-webhook"
REPO_PATH="$1"
EVENT_TYPE="$2"

if [ -n "$REPO_PATH" ] && [ -n "$EVENT_TYPE" ]; then
    curl -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{\"repo\":\"$REPO_PATH\",\"event\":\"$EVENT_TYPE\",\"timestamp\":\"$(date -Iseconds)\"}" \
        --connect-timeout 5 || true
fi
HOOK_EOF

chmod +x /usr/local/bin/forgejo-webhook

# ============= START FORGEJO =============
log "🎯 Starting Forgejo Server..."
/usr/local/bin/forgejo web --port $PORT --config $FORGEJO_CONFIG/app.ini

# Keep script running
wait $!
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE CONFIG.JSON =============
log "Generating config.json..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Forgejo Git Server",
    "version": "1.21",
    "description": "Git repository hosting with issue tracker and CI/CD",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "winejs-forgejo",
    "icon": "/icons/forgejo.png",
    "category": "Development",
    "features": [
        "Git repository hosting",
        "Issue tracker",
        "Pull requests",
        "CI/CD with Actions",
        "Git LFS support",
        "Webhooks",
        "Code review",
        "Wiki"
    ]
}
CONF_EOF

# ============= CREATE DOCKER-COMPOSE.YML WITH VOLUME MOUNTS =============
log "Generating docker-compose.yml with volume mounts..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Main Forgejo Server
  winejs-${APP_NAME}:
    image: codeberg.org/forgejo/forgejo:1.21
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:3000"
      - "2222:22"
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - FORGEJO__server__DOMAIN=${DOMAIN_NAME}
      - FORGEJO__server__ROOT_URL=https://${DOMAIN_NAME}/forgejo/
      - FORGEJO__server__LOCAL_ROOT_URL=http://localhost:3000/
      - FORGEJO__server__LFS_START_SERVER=true
      - FORGEJO__lfs__JWT_SECRET=${LFS_JWT_SECRET}
      - FORGEJO__lfs__MAX_FILE_SIZE=1073741824
    volumes:
      # Forgejo data
      - ${FORGEJO_DATA}:/data
      # Forgejo config
      - ${FORGEJO_CONFIG}:/etc/forgejo
      # Shared repositories - FIXED PERMISSION PATH
      - ${REPO_DIR}:/data/git/repositories
      # Shared volumes
      - ${SHARED_VOLUMES}/backups:/backups
      - ${SHARED_VOLUMES}/imports:/imports
      - ${SHARED_VOLUMES}/ci-cd:/ci-cd
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    networks:
      - winejs-net

  # LFS Mapper Service
  winejs-lfs-mapper:
    image: node:18-alpine
    container_name: winejs-lfs-mapper
    restart: unless-stopped
    ports:
      - "127.0.0.1:${LFS_MAPPER_PORT}:3002"
    environment:
      - FORGEJO_PORT=${APP_PORT}
      - PORT=3002
      - NODE_NO_WARNINGS=1
      # Add canvas dependencies
      - NODE_OPTIONS=--max-old-space-size=512
    volumes:
      - ${LFS_MAPPER_DIR}:/app:ro
      - ${REPO_DIR}:/opt/winejs/repositories:ro
      - ${FORGEJO_DATA}:/opt/winejs/data/forgejo:ro
      - ${SHARED_VOLUMES}:/opt/winejs/shared-volumes:rw
      - ${SHARED_VOLUMES}/ogimages:/opt/winejs/shared-volumes/ogimages:rw
    working_dir: /app
    command: sh -c "apk add --no-cache msttcorefonts-installer fontconfig && update-ms-fonts && node server.js"
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE WINEJS GIT INTEGRATION =============
log "🔌 Creating WineJS Git integration..."

mkdir -p "/opt/winejs/git-hooks"

cat > "/opt/winejs/git-hooks/post-receive" << 'HOOK_EOF'
#!/bin/bash
# Post-receive hook for WineJS integration

while read oldrev newrev refname; do
    # Extract repository name
    REPO_NAME=$(basename "$PWD")
    
    # Notify WineJS about the push
    curl -X POST "http://localhost:3002/api/webhook" \
        -H "Content-Type: application/json" \
        -d "{\"repo\":\"$REPO_NAME\",\"ref\":\"$refname\",\"oldrev\":\"$oldrev\",\"newrev\":\"$newrev\"}" \
        --connect-timeout 5 || true
    
    echo "✅ WineJS notified of push to $REPO_NAME"
done
HOOK_EOF

chmod +x "/opt/winejs/git-hooks/post-receive"

# ============= SET UP PM2 FOR LFS MAPPER =============
log "🚀 Setting up PM2 for LFS mapper persistence..."

if command -v pm2 &> /dev/null; then
    cd "$LFS_MAPPER_DIR"
    
    # Stop and delete existing instance if it exists
    if pm2 list | grep -q "winejs-lfs-mapper"; then
        log "Stopping existing LFS mapper..."
        pm2 stop winejs-lfs-mapper 2>/dev/null || true
        pm2 delete winejs-lfs-mapper 2>/dev/null || true
    fi
    
    # Start new instance
    pm2 start server.js --name winejs-lfs-mapper --env FORGEJO_PORT=$APP_PORT
    pm2 save
    pm2 startup
fi

# ============= SETUP OG IMAGE CACHE CLEANUP =============
log "Setting up OG image cache cleanup cron job..."

cat > /etc/cron.daily/forgejo-og-cleanup << 'CRON_EOF'
#!/bin/bash
# Clean up OG images older than 7 days
find /opt/winejs/shared-volumes/ogimages/cache -name "*.png" -mtime +7 -delete 2>/dev/null
CRON_EOF

chmod +x /etc/cron.daily/forgejo-og-cleanup
log "✅ OG image cache cleanup scheduled (daily)"

# ============= CREATE ADMIN USER SCRIPT =============
log "Creating admin user setup script..."

cat > "$APP_DIR/setup-admin.sh" << 'ADMIN_EOF'
#!/bin/bash
# Forgejo admin user setup - FIXED VERSION

FORGEJO_URL="http://localhost:${APP_PORT}"
ADMIN_USERNAME="winejs-admin"
ADMIN_EMAIL="${ADMIN_EMAIL}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

# Wait for Forgejo to be ready
log "Waiting for Forgejo to start..."
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -s -f "http://localhost:${APP_PORT}/api/v1/version" > /dev/null 2>&1; then
        log "✅ Forgejo is ready!"
        break
    fi
    log "Attempt $attempt/$max_attempts: Waiting for Forgejo..."
    sleep 5
    attempt=$((attempt + 1))
done

if [ $attempt -gt $max_attempts ]; then
    log "⚠️ Timeout waiting for Forgejo. Admin user not created."
    log "Please create admin manually via:"
    log "  docker exec -it winejs-forgejo forgejo admin user create"
    exit 1
fi

# Create admin user using docker exec (MORE RELIABLE than API)
log "Creating admin user via docker exec..."
docker exec winejs-forgejo forgejo admin user create \
    --username "$ADMIN_USERNAME" \
    --email "$ADMIN_EMAIL" \
    --password "$ADMIN_PASSWORD" \
    --admin \
    --must-change-password=false 2>&1

if [ $? -eq 0 ]; then
    log "✅ Admin user '$ADMIN_USERNAME' created successfully"
else
    log "⚠️ Admin user may already exist or creation failed"
    log "You can try creating manually with:"
    log "  docker exec -it winejs-forgejo forgejo admin user create --username admin --email your@email.com --password pass --admin"
fi

log "✅ Admin setup complete. Login at: https://${DOMAIN_NAME}/forgejo/login"
ADMIN_EOF


chmod +x "$APP_DIR/setup-admin.sh"

# ============= CREATE UNINSTALL SCRIPT =============
log "Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_forgejo.sh" << 'UNINSTALL_EOF'
#!/bin/bash
# WineJS Forgejo Uninstaller

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

log "🧹 Uninstalling Forgejo Server..."

# ============= STOP PM2 PROCESSES =============
log "Stopping PM2 processes..."
if command -v pm2 &> /dev/null; then
    if pm2 list 2>/dev/null | grep -q "winejs-lfs-mapper"; then
        log "Stopping winejs-lfs-mapper..."
        pm2 stop winejs-lfs-mapper 2>/dev/null || true
        pm2 delete winejs-lfs-mapper 2>/dev/null || true
    fi
fi

# ============= STOP AND REMOVE DOCKER CONTAINERS =============
log "Stopping Docker containers..."

if docker ps -a 2>/dev/null | grep -q "winejs-forgejo"; then
    log "Stopping winejs-forgejo container..."
    docker stop winejs-forgejo 2>/dev/null || true
    docker rm winejs-forgejo 2>/dev/null || true
    log "✅ Forgejo container removed"
fi

if docker ps -a 2>/dev/null | grep -q "winejs-lfs-mapper"; then
    log "Stopping winejs-lfs-mapper container..."
    docker stop winejs-lfs-mapper 2>/dev/null || true
    docker rm winejs-lfs-mapper 2>/dev/null || true
    log "✅ LFS mapper container removed"
fi

# ============= REMOVE APP DIRECTORIES =============
log "Removing app directories..."

APP_NAME="forgejo"
APP_DIR="/opt/winejs/apps/${APP_NAME}"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/${APP_NAME}"
FORGEJO_DATA="/opt/winejs/data/forgejo"
FORGEJO_CONFIG="/opt/winejs/config/forgejo"
LFS_MAPPER_DIR="/opt/winejs/lfs-mapper"
ICON_FILE="/opt/winejs/translator/public/icons/${APP_NAME}.png"
ICON_SVG="/opt/winejs/translator/public/icons/${APP_NAME}.svg"

# Remove directories if they exist
[ -d "$INSTANCE_DIR" ] && rm -rf "$INSTANCE_DIR" && log "✅ Instance directory removed"
[ -d "$APP_DIR" ] && rm -rf "$APP_DIR" && log "✅ App directory removed"
[ -d "$FORGEJO_DATA" ] && rm -rf "$FORGEJO_DATA" && log "✅ Forgejo data removed"
[ -d "$FORGEJO_CONFIG" ] && rm -rf "$FORGEJO_CONFIG" && log "✅ Forgejo config removed"
[ -d "$LFS_MAPPER_DIR" ] && rm -rf "$LFS_MAPPER_DIR" && log "✅ LFS mapper removed"
[ -f "$ICON_FILE" ] && rm -f "$ICON_FILE" && log "✅ Icon removed"
[ -f "$ICON_SVG" ] && rm -f "$ICON_SVG" && log "✅ SVG icon removed"

# ============= REMOVE NGINX CONFIGURATION =============
log "Removing nginx configuration..."

NGINX_SITE="/etc/nginx/sites-available/winejs"

if [ ! -f "$NGINX_SITE" ]; then
    warn "nginx config not found at $NGINX_SITE"
else
    # Check if any Forgejo routes exist
    if ! grep -q "forgejo" "$NGINX_SITE"; then
        log "No Forgejo routes found in nginx config"
    else
        log "Removing Forgejo routes from nginx config..."
        
        # Create backup with timestamp
        BACKUP_FILE="${NGINX_SITE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$NGINX_SITE" "$BACKUP_FILE"
        log "✅ Backup created: $BACKUP_FILE"
        
        # Use Perl for more reliable multi-line removal (if available)
        if command -v perl &> /dev/null; then
            perl -i -0777 -pe 's/^[[:space:]]*# Forgejo Git Server\s*\n.*?location \/forgejo-lfs\/.*?^\s*}\s*$//gms' "$NGINX_SITE"
            perl -i -0777 -pe 's/^[[:space:]]*location \/forgejo\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
            perl -i -0777 -pe 's/^[[:space:]]*location \/forgejo\/api\/\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
            perl -i -0777 -pe 's/^[[:space:]]*location \/forgejo-lfs\/\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
        else
            # Fallback to sed for multi-line removal
            sed -i '/^[[:space:]]*# Forgejo Git Server/,/^[[:space:]]*}/d' "$NGINX_SITE"
            sed -i '/^[[:space:]]*location \/forgejo {/,/^[[:space:]]*}/d' "$NGINX_SITE"
            sed -i '/^[[:space:]]*location \/forgejo\/api\//,/^[[:space:]]*}/d' "$NGINX_SITE"
            sed -i '/^[[:space:]]*location \/forgejo-lfs\//,/^[[:space:]]*}/d' "$NGINX_SITE"
        fi
        
        # Remove any orphaned forgejo lines
        sed -i '/forgejo/d' "$NGINX_SITE"
        
        # Clean up multiple blank lines
        sed -i '/^$/N;/^\n$/D' "$NGINX_SITE"
        
        # Test and reload nginx
        log "Testing nginx configuration..."
        if nginx -t 2>&1 | tee /tmp/nginx_test.log; then
            systemctl reload nginx
            log "✅ Nginx configuration successfully updated - Forgejo routes removed"
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

# ============= RELOAD WINEJS TRANSLATOR =============
log "Reloading WineJS translator..."
if command -v pm2 &> /dev/null; then
    pm2 restart translator 2>/dev/null || true
    log "✅ Translator reloaded"
fi

# ============= REMOVE HELPER SCRIPT =============
if [ -f "/usr/local/bin/winejs-forgejo" ]; then
    rm -f "/usr/local/bin/winejs-forgejo"
    log "✅ Helper script removed"
fi

# ============= VERIFY REMOVAL =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           FORGEJO SERVER UNINSTALLED SUCCESSFULLY!            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
log "✅ Forgejo Server has been completely removed"
echo ""
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_forgejo.sh"
log "✅ Uninstall script created: $(dirname "$APP_DIR")/uninstall_forgejo.sh"

# ============= START CONTAINER =============
log "Starting Forgejo Server container..."

cd "$INSTANCE_DIR"
docker-compose up -d

sleep 10

# Fix permissions again after container start (in case container created files)
docker exec winejs-forgejo mkdir -p /data/git/.ssh 2>/dev/null || true
docker exec winejs-forgejo chown -R 1000:1000 /data/git/.ssh 2>/dev/null || true
docker exec winejs-forgejo chmod 700 /data/git/.ssh 2>/dev/null || true

if docker ps | grep -q "winejs-${APP_NAME}"; then
    success "✅ Container started successfully"
else
    warn "⚠️ Container may not have started. Check: docker logs winejs-${APP_NAME}"
fi

# ============= INJECT GIT LFS BUTTON AND REPO INFO EXTRACTOR =============
log "Injecting Git LFS button and Repository Info Extractor..."

# Create custom footer with JavaScript injection
docker exec winejs-forgejo mkdir -p /data/gitea/templates/custom

cat > /tmp/forgejo-enhancements.js << 'EOF'
<script>
(function() {
    "use strict";
    
    // Add custom CSS for the popup and buttons
    const style = document.createElement('style');
    style.textContent = `
        .forgejo-repo-popup {
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            z-index: 999999;
            min-width: 400px;
            max-width: 600px;
            max-height: 80vh;
            overflow-y: auto;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
        }

        .forgejo-repo-popup-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0,0,0,0.5);
            z-index: 999998;
        }

        .forgejo-repo-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 1px solid #e1e4e8;
        }

        .forgejo-repo-title {
            font-size: 18px;
            font-weight: 600;
            margin: 0;
        }

        .forgejo-repo-close {
            background: none;
            border: none;
            font-size: 20px;
            cursor: pointer;
            color: #586069;
            padding: 0;
            width: 24px;
            height: 24px;
            display: flex;
            align-items: center;
            justify-content: center;
            border-radius: 4px;
        }

        .forgejo-repo-close:hover {
            background: #f6f8fa;
            color: #24292e;
        }

        .forgejo-repo-json {
            background: #f6f8fa;
            border: 1px solid #e1e4e8;
            border-radius: 6px;
            padding: 15px;
            font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
            font-size: 12px;
            white-space: pre-wrap;
            word-break: break-all;
            margin-bottom: 15px;
            max-height: 300px;
            overflow-y: auto;
        }

        .forgejo-repo-buttons {
            display: flex;
            gap: 10px;
            justify-content: flex-end;
        }

        .forgejo-repo-copy-btn {
            background: #2ea44f;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
        }

        .forgejo-repo-copy-btn:hover {
            background: #2c974b;
        }

        .forgejo-repo-copy-btn.copied {
            background: #6e7681;
        }

        .forgejo-repo-info-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            margin-left: 8px;
            padding: 4px 8px;
            background: #f6f8fa;
            border: 1px solid rgba(27,31,36,0.15);
            border-radius: 6px;
            cursor: pointer;
            color: #24292e;
            font-size: 12px;
            font-weight: 500;
        }

        .forgejo-repo-info-btn:hover {
            background: #f3f4f6;
            border-color: rgba(27,31,36,0.3);
        }

        .forgejo-repo-info-btn svg {
            margin-right: 4px;
        }

        .gitlfs-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            margin-left: 8px;
            padding: 4px 8px;
            cursor: pointer;
        }

        .gitlfs-btn img {
            width: 30px;
            height: 30px;
            border: 1px solid lightgray;
            border-radius: 2px;
        }

        .vscode-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            margin-left: 8px;
            padding: 4px 8px;
            cursor: pointer;
        }

        .vscode-btn img {
            width: 30px;
            height: 30px;
            border: 1px solid lightgray;
            border-radius: 2px;
        }

        .vscode-prompt-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0,0,0,0.7);
            z-index: 9999999;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .vscode-prompt-popup {
            background: white;
            padding: 30px;
            border-radius: 12px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            min-width: 400px;
            max-width: 500px;
        }

        .vscode-prompt-popup h3 {
            margin: 0 0 10px 0;
            color: #333;
        }

        .vscode-prompt-popup p {
            margin: 0 0 15px 0;
            color: #666;
            font-size: 14px;
        }

        .vscode-prompt-popup input {
            width: 100%;
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 6px;
            font-size: 14px;
            margin-bottom: 15px;
            box-sizing: border-box;
        }

        .vscode-prompt-popup input:focus {
            outline: none;
            border-color: #0066cc;
        }

        .vscode-prompt-buttons {
            display: flex;
            gap: 10px;
            justify-content: flex-end;
        }

        .vscode-prompt-buttons button {
            padding: 8px 16px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            border: none;
        }

        .vscode-prompt-save {
            background: #2ea44f;
            color: white;
        }

        .vscode-prompt-save:hover {
            background: #2c974b;
        }

        .vscode-prompt-cancel {
            background: #f6f8fa;
            color: #24292e;
            border: 1px solid rgba(27,31,36,0.15);
        }

        .vscode-prompt-cancel:hover {
            background: #f3f4f6;
        }
    `;
    document.head.appendChild(style);
    
    // Info button SVG
    const infoSvg = `<svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" fill="currentColor">
        <path d="M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75ZM8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"></path>
    </svg>`;
    
    // Function to extract repository data from Forgejo
    function extractRepoData() {
        const url = window.location.href;
        const pathParts = window.location.pathname.split('/').filter(Boolean);

        // Forgejo URL structure: /forgejo/owner/repo
        let owner = "";
        let repo = "";

        // Find owner and repo from path
        const forgejoIndex = pathParts.indexOf('forgejo');
        if (forgejoIndex !== -1 && pathParts.length > forgejoIndex + 2) {
            owner = pathParts[forgejoIndex + 1];
            repo = pathParts[forgejoIndex + 2];
        }

        // Get favicon
        const favicon = document.querySelector('link[rel="icon"]')?.href ||
                       document.querySelector('link[rel="shortcut icon"]')?.href ||
                       "https://wine.gitgpt.chat/images/gitlfs.png";

        // Get repository name from repo-title
        let repoName = repo;
        const repoTitleElement = document.querySelector('.repo-title a:last-child');
        if (repoTitleElement) {
            repoName = repoTitleElement.textContent.trim();
        }

        // Get description
        let description = "";
        const descElement = document.querySelector('.repository-header .description, .repo-header .description, .repository-description');
        if (descElement) {
            description = descElement.textContent.trim();
        }

        // Get YouTube URL (if any in description)
        let youtubeUrl = "";
        const youtubeMatch = description.match(/(https?:\/\/)?(www\.)?(youtube\.com|youtu\.be)\/[^\s]+/i);
        if (youtubeMatch) youtubeUrl = youtubeMatch[0];

        // Forgejo URL (clean base URL without branch/file paths)
        const forgejoUrl = url.split('/src/')[0].split('/raw/')[0];

        // Generate OpenGraph image URL
        let imageUrl = OPENGRAPH_IMAGE_URL + `/forgejo/api/v1/repos/${owner}/${repo}/ogimage`;

        // Get stars count
        let stars = 0;
        const starElement = document.querySelector('.star-count, .ui .stars .count');
        if (starElement) {
            stars = parseInt(starElement.textContent.trim()) || 0;
        }

        // Get forks count
        let forks = 0;
        const forkElement = document.querySelector('.fork-count, .ui .forks .count');
        if (forkElement) {
            forks = parseInt(forkElement.textContent.trim()) || 0;
        }

        return {
            favicon: favicon,
            name: repoName,
            title: repoName,
            description: description,
            youtube_url: youtubeUrl,
            forgejo_url: forgejoUrl,
            image_url: imageUrl,
            url: forgejoUrl,
            stats: {
                stars: stars,
                forks: forks
            },
            owner: owner,
            repository: repo
        };
    }
    
    // Function to show popup
    function showInfoPopup() {
        const data = extractRepoData();
        const jsonString = JSON.stringify(data, null, 2);

        const overlay = document.createElement('div');
        overlay.className = 'forgejo-repo-popup-overlay';

        const popup = document.createElement('div');
        popup.className = 'forgejo-repo-popup';
        popup.innerHTML = `
            <div class="forgejo-repo-header">
                <h3 class="forgejo-repo-title">Repository Information</h3>
                <button class="forgejo-repo-close" aria-label="Close">×</button>
            </div>
            <div class="forgejo-repo-json">${jsonString.replace(/</g, '&lt;').replace(/>/g, '&gt;')}</div>
            <div class="forgejo-repo-buttons">
                <button class="forgejo-repo-copy-btn">📋 Copy JSON</button>
            </div>
        `;

        const closeBtn = popup.querySelector('.forgejo-repo-close');
        const copyBtn = popup.querySelector('.forgejo-repo-copy-btn');

        closeBtn.addEventListener('click', () => {
            document.body.removeChild(overlay);
            document.body.removeChild(popup);
        });

        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) {
                document.body.removeChild(overlay);
                document.body.removeChild(popup);
            }
        });

        copyBtn.addEventListener('click', async () => {
            try {
                await navigator.clipboard.writeText(jsonString);
                copyBtn.textContent = '✓ Copied!';
                copyBtn.classList.add('copied');
                setTimeout(() => {
                    copyBtn.textContent = '📋 Copy JSON';
                    copyBtn.classList.remove('copied');
                }, 2000);
            } catch (err) {
                console.error('Failed to copy:', err);
                copyBtn.textContent = '❌ Failed!';
                setTimeout(() => {
                    copyBtn.textContent = '📋 Copy JSON';
                    copyBtn.classList.remove('copied');
                }, 2000);
            }
        });

        document.body.appendChild(overlay);
        document.body.appendChild(popup);
        closeBtn.focus();
    }
    
    // Function to show VSCode URL prompt
    function showVSCodePrompt() {
        const overlay = document.createElement('div');
        overlay.className = 'vscode-prompt-overlay';

        const popup = document.createElement('div');
        popup.className = 'vscode-prompt-popup';
        popup.innerHTML = `
            <h3>🔧 Configure VSCode Server</h3>
            <p>Enter your VSCode Server base URL (e.g., https://wine.gitgpt.chat/vscode)</p>
            <input type="text" id="vscode-url-input" placeholder="https://wine.gitgpt.chat/vscode" value="${localStorage.getItem('vscode_server_url') || ''}">
            <div class="vscode-prompt-buttons">
                <button class="vscode-prompt-cancel">Cancel</button>
                <button class="vscode-prompt-save">Save</button>
            </div>
        `;

        overlay.appendChild(popup);
        document.body.appendChild(overlay);

        const input = popup.querySelector('#vscode-url-input');
        const saveBtn = popup.querySelector('.vscode-prompt-save');
        const cancelBtn = popup.querySelector('.vscode-prompt-cancel');

        saveBtn.addEventListener('click', () => {
            let url = input.value.trim();
            if (url) {
                url = url.replace(/\/$/, '');
                localStorage.setItem('vscode_server_url', url);
                updateVSCodeButton();
            }
            document.body.removeChild(overlay);
        });

        cancelBtn.addEventListener('click', () => {
            document.body.removeChild(overlay);
        });

        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) {
                document.body.removeChild(overlay);
            }
        });

        input.focus();
    }
    
    // Function to get VSCode URL for current repo
    function getVSCodeRepoUrl() {
        const baseUrl = localStorage.getItem('vscode_server_url');
        if (!baseUrl) return null;

        const pathParts = window.location.pathname.split('/').filter(Boolean);
        const forgejoIndex = pathParts.indexOf('forgejo');

        if (forgejoIndex !== -1 && pathParts.length > forgejoIndex + 2) {
            const owner = pathParts[forgejoIndex + 1];
            const repo = pathParts[forgejoIndex + 2];
            return `${baseUrl}/workspaces/${owner}/${repo}`;
        }

        return null;
    }
    
    // Function to update VSCode button href
    function updateVSCodeButton() {
        const vscodeBtn = document.getElementById('forgejo-vscode-btn');
        if (vscodeBtn) {
            const repoUrl = getVSCodeRepoUrl();
            if (repoUrl) {
                vscodeBtn.href = repoUrl;
                vscodeBtn.style.opacity = '1';
                vscodeBtn.style.cursor = 'pointer';
            } else {
                vscodeBtn.href = 'javascript:void(0)';
                vscodeBtn.style.opacity = '0.5';
                vscodeBtn.style.cursor = 'pointer';
            }
        }
    }
    
    // Function to add VSCode button
    function addVSCodeButton() {
        const repoTitle = document.querySelector('.repo-title');
        if (!repoTitle) return;
        if (document.getElementById('forgejo-vscode-btn')) return;

        const rssLink = repoTitle.querySelector('.rss-icon');

        const vscodeLink = document.createElement('a');
        vscodeLink.id = 'forgejo-vscode-btn';
        vscodeLink.className = 'gt-mr-3 vscode-btn';
        vscodeLink.title = 'Open in VSCode Server';
        vscodeLink.innerHTML = '<img src="https://cdn.gitgpt.chat/rtx/images/vscodeserver.png" style="width: 30px; height: 30px; border: 1px solid lightgray; border-radius: 2px;" alt="VSCode Server"/>';

        const repoUrl = getVSCodeRepoUrl();
        if (repoUrl) {
            vscodeLink.href = repoUrl;
            vscodeLink.style.opacity = '1';
        } else {
            vscodeLink.href = 'javascript:void(0)';
            vscodeLink.style.opacity = '0.5';
        }

        vscodeLink.addEventListener('click', (e) => {
            const storedUrl = localStorage.getItem('vscode_server_url');
            if (!storedUrl) {
                e.preventDefault();
                showVSCodePrompt();
            } else if (!getVSCodeRepoUrl()) {
                e.preventDefault();
                showVSCodePrompt();
            }
        });

        if (rssLink && rssLink.parentNode) {
            rssLink.parentNode.insertBefore(vscodeLink, rssLink.nextSibling);
        } else {
            repoTitle.appendChild(vscodeLink);
        }
    }
    
    // Function to add Git LFS button
    function addGitLFSButton() {
        const repoTitle = document.querySelector('.repo-title');
        if (!repoTitle) return;
        if (document.getElementById('forgejo-gitlfs-btn')) return;

        const rssLink = repoTitle.querySelector('.rss-icon');

        const lfsLink = document.createElement('a');
        lfsLink.id = 'forgejo-gitlfs-btn';
        lfsLink.className = 'gt-mr-3 gitlfs-btn';
        lfsLink.href = 'https://cdn.gitgpt.chat/rtx/forgejogitlfs.html';
        lfsLink.target = '_blank';
        lfsLink.title = 'Git LFS Support';
        lfsLink.innerHTML = '<img src="https://cdn.gitgpt.chat/rtx/images/gitlfs.png" style="width: 30px; height: 30px; border: 1px solid lightgray; border-radius: 2px;" alt="Git LFS"/>';

        if (rssLink && rssLink.parentNode) {
            rssLink.parentNode.insertBefore(lfsLink, rssLink.nextSibling);
        } else {
            repoTitle.appendChild(lfsLink);
        }
    }
    
    // Function to add Info button
    function addInfoButton() {
        const repoTitle = document.querySelector('.repo-title');
        if (!repoTitle) return;
        if (document.getElementById('forgejo-repo-info-btn')) return;

        const rssLink = repoTitle.querySelector('.rss-icon');

        const infoLink = document.createElement('a');
        infoLink.id = 'forgejo-repo-info-btn';
        infoLink.className = 'gt-mr-3 forgejo-repo-info-btn';
        infoLink.href = 'javascript:void(0)';
        infoLink.style.cursor = 'pointer';
        infoLink.style.display = 'inline-flex';
        infoLink.style.alignItems = 'center';
        infoLink.style.gap = '4px';
        infoLink.title = 'Extract repository information as JSON';
        infoLink.innerHTML = infoSvg + '<span style="font-size: 12px;">Info</span>';
        infoLink.addEventListener('click', showInfoPopup);

        if (rssLink && rssLink.parentNode) {
            rssLink.parentNode.insertBefore(infoLink, rssLink.nextSibling);
        } else {
            repoTitle.appendChild(infoLink);
        }
    }
    
    // Initialize all buttons
    function initButtons() {
        addVSCodeButton();
        addGitLFSButton();
        addInfoButton();
    }
    
    // Observe DOM changes
    const observer = new MutationObserver(() => {
        initButtons();
    });
    
    observer.observe(document.body, {
        childList: true,
        subtree: true
    });
    
    // Initial check
    initButtons();
    
    // Handle Turbo navigation
    if (typeof document.addEventListener !== 'undefined') {
        document.addEventListener('turbo:load', function() {
            setTimeout(initButtons, 100);
        });
    }
})();
</script>
EOF


# Replace the placeholder with actual API URL
sed -i "s|OPENGRAPH_IMAGE_URL|https://${DOMAIN_NAME}|g" "/tmp/forgejo-enhancements.js"

# Copy the enhanced script to the container
docker cp /tmp/forgejo-enhancements.js winejs-forgejo:/data/gitea/templates/custom/footer.tmpl

log "✅ Git LFS button and Repository Info Extractor injected"

# ============= INJECT OPENGRAPH META TAGS FOR FORGEJO =============
log "Injecting OpenGraph meta tags for better social sharing..."

# Create custom header template with OpenGraph tags
docker exec winejs-forgejo mkdir -p /data/gitea/templates/custom

cat > /tmp/forgejo-opengraph.js << 'EOF'
<script>
(function() {
    "use strict";
    
    // ============================================
    // OpenGraph Meta Tag Injection for Forgejo
    // Makes Forgejo share like GitHub on social media
    // ============================================
    
    function injectOpenGraphTags() {
        // Only run on repository pages
        if (!window.location.pathname || window.location.pathname.split('/').length < 3) {
            return;
        }
        
        const pathParts = window.location.pathname.split('/').filter(Boolean);
        const owner = pathParts[0];
        const repo = pathParts[1];
        
        if (!owner || !repo) return;
        
        // Extract repository information
        const repoData = extractForgejoRepoData(owner, repo);
        
        // Create OpenGraph meta tags if they don't exist
        const ogTags = [
            { property: 'og:title', content: repoData.title },
            { property: 'og:description', content: repoData.description },
            { property: 'og:image', content: repoData.image_url },
            { property: 'og:url', content: repoData.url },
            { property: 'og:type', content: 'object' },
            { property: 'og:site_name', content: 'WineJS Forgejo' },
            { name: 'twitter:card', content: 'summary_large_image' },
            { name: 'twitter:title', content: repoData.title },
            { name: 'twitter:description', content: repoData.description },
            { name: 'twitter:image', content: repoData.image_url },
            { property: 'og:image:width', content: '1200' },
            { property: 'og:image:height', content: '630' },
            { property: 'og:image:alt', content: `${owner}/${repo} repository banner` }
        ];
        
        // Remove existing tags first
        ogTags.forEach(tag => {
            const selector = tag.property ? `meta[property="${tag.property}"]` : `meta[name="${tag.name}"]`;
            document.querySelectorAll(selector).forEach(el => el.remove());
        });
        
        // Inject new tags
        ogTags.forEach(tag => {
            const meta = document.createElement('meta');
            if (tag.property) {
                meta.setAttribute('property', tag.property);
            } else {
                meta.setAttribute('name', tag.name);
            }
            meta.setAttribute('content', tag.content);
            document.head.appendChild(meta);
        });
        
        // Also update title
        document.title = `${owner}/${repo}: ${repoData.description.substring(0, 60)}${repoData.description.length > 60 ? '...' : ''} | WineJS Forgejo`;
        
        console.log('✅ OpenGraph tags injected for:', `${owner}/${repo}`);
    }
    
    function extractForgejoRepoData(owner, repo) {
        // Get repository description from page
        let description = '';
        const descSelectors = [
            '.repository-header .description',
            '.repo-header .description', 
            '.repository-description',
            '.ui .description p',
            '[itemprop="description"]'
        ];
        
        for (const selector of descSelectors) {
            const element = document.querySelector(selector);
            if (element && element.textContent.trim()) {
                description = element.textContent.trim();
                break;
            }
        }
        
        // Fallback description if none found
        if (!description) {
            description = `Repository ${owner}/${repo} on WineJS Forgejo - Git repository hosting with issue tracking and CI/CD`;
        }
        
        // Limit description length for OpenGraph
        if (description.length > 200) {
            description = description.substring(0, 197) + '...';
        }
        
        // Generate OpenGraph image URL (GitHub-style banner)
        const baseUrl = window.location.origin;
        const imageUrl = `${baseUrl}/api/v1/repos/${owner}/${repo}/ogimage`;
        
        // Create a JSON representation for structured data
        const structuredData = {
            "@context": "https://schema.org",
            "@type": "SoftwareSourceCode",
            "name": `${owner}/${repo}`,
            "description": description,
            "url": window.location.href,
            "codeRepository": window.location.href,
            "programmingLanguage": detectLanguage(),
            "dateCreated": getRepoAge(),
            "creator": {
                "@type": "Person",
                "name": owner
            }
        };
        
        // Add JSON-LD structured data
        const scriptTag = document.createElement('script');
        scriptTag.setAttribute('type', 'application/ld+json');
        scriptTag.textContent = JSON.stringify(structuredData);
        document.head.appendChild(scriptTag);
        
        return {
            title: `${owner}/${repo}: ${description.substring(0, 60)}${description.length > 60 ? '...' : ''}`,
            description: description,
            image_url: imageUrl,
            url: window.location.href,
            owner: owner,
            repo: repo
        };
    }
    
    function detectLanguage() {
        const langElement = document.querySelector('[data-primary-lang], .repo-language, .language');
        return langElement ? langElement.textContent.trim() : 'Unknown';
    }
    
    function getRepoAge() {
        const createdElement = document.querySelector('[rel="vcs-git"], time.datetime');
        if (createdElement && createdElement.getAttribute('datetime')) {
            return createdElement.getAttribute('datetime');
        }
        return new Date().toISOString().split('T')[0];
    }
    
    // Create OpenGraph image endpoint (if using a proxy)
    function setupOGImageEndpoint() {
        // This creates a canvas-generated OpenGraph image similar to GitHub
        const style = document.createElement('style');
        style.textContent = `
            .og-image-generator {
                display: none;
            }
        `;
        document.head.appendChild(style);
    }
    
    // Run on page load
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            injectOpenGraphTags();
            setupOGImageEndpoint();
        });
    } else {
        injectOpenGraphTags();
        setupOGImageEndpoint();
    }
    
    // Re-run on Turbolinks/Turbo navigation
    document.addEventListener('turbo:load', () => {
        setTimeout(injectOpenGraphTags, 100);
    });
    
    // Also listen for history changes (SPA navigation)
    let lastUrl = location.href;
    new MutationObserver(() => {
        const url = location.href;
        if (url !== lastUrl) {
            lastUrl = url;
            setTimeout(injectOpenGraphTags, 100);
        }
    }).observe(document, { subtree: true, childList: true });
    
})();
</script>

<!-- Server-side OpenGraph image generation -->
<script>
// Fallback: Generate client-side OpenGraph image if server doesn't provide one
(function() {
    async function generateFallbackOGImage(owner, repo, description) {
        const canvas = document.createElement('canvas');
        canvas.width = 1200;
        canvas.height = 630;
        const ctx = canvas.getContext('2d');
        
        // Background gradient (GitHub-style)
        const gradient = ctx.createLinearGradient(0, 0, 0, canvas.height);
        gradient.addColorStop(0, '#24292e');
        gradient.addColorStop(1, '#2c3e50');
        ctx.fillStyle = gradient;
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        
        // Draw repository name
        ctx.fillStyle = '#ffffff';
        ctx.font = 'Bold 48px -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif';
        ctx.fillText(`${owner}/${repo}`, 60, 200);
        
        // Draw description
        ctx.font = '24px -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif';
        ctx.fillStyle = '#e1e4e8';
        
        // Wrap description text
        const words = description.split(' ');
        let lines = [];
        let currentLine = '';
        
        for (let word of words) {
            const testLine = currentLine + (currentLine ? ' ' : '') + word;
            const metrics = ctx.measureText(testLine);
            if (metrics.width > 900) {
                lines.push(currentLine);
                currentLine = word;
            } else {
                currentLine = testLine;
            }
        }
        lines.push(currentLine);
        
        // Draw each line
        let y = 300;
        for (let line of lines.slice(0, 3)) {
            ctx.fillText(line, 60, y);
            y += 40;
        }
        
        // Draw Git icon
        ctx.fillStyle = '#f9826c';
        ctx.font = '32px "Segoe UI", Arial';
        ctx.fillText('📦', 60, 500);
        
        // Convert to data URL and set as og:image
        const imageDataUrl = canvas.toDataURL();
        
        // Update og:image meta tag
        let ogImage = document.querySelector('meta[property="og:image"]');
        if (ogImage) {
            ogImage.setAttribute('content', imageDataUrl);
        } else {
            ogImage = document.createElement('meta');
            ogImage.setAttribute('property', 'og:image');
            ogImage.setAttribute('content', imageDataUrl);
            document.head.appendChild(ogImage);
        }
        
        console.log('✅ Fallback OpenGraph image generated');
    }
    
    // Check if server provides OG image, if not generate client-side
    setTimeout(() => {
        const ogImage = document.querySelector('meta[property="og:image"]');
        if (ogImage && ogImage.getAttribute('content') && 
            !ogImage.getAttribute('content').includes('/api/v1/repos/')) {
            // Server provided an image, use it
            return;
        }
        
        const pathParts = window.location.pathname.split('/').filter(Boolean);
        if (pathParts.length >= 2) {
            const owner = pathParts[0];
            const repo = pathParts[1];
            let description = document.querySelector('[itemprop="description"]')?.textContent || 
                            `${owner}/${repo} - Git repository on WineJS Forgejo`;
            generateFallbackOGImage(owner, repo, description);
        }
    }, 1000);
})();
</script>
EOF

# Copy the OpenGraph injection script to the container
docker cp /tmp/forgejo-opengraph.js winejs-forgejo:/data/gitea/templates/custom/header.tmpl

log "✅ OpenGraph meta tags injected - Forgejo will now share like GitHub!"

# What this extended script adds:
# 1. Repository Info Extractor Button
#     Adds an "Info" button next to repository actions
#     Extracts comprehensive metadata including:
#         Repository name, owner, full name
#         Description with YouTube URL detection
#         Star and fork counts
#         Primary language, default branch
#         Whether it's a fork
#         Last update timestamp

# 2. Interactive Popup
#     Clean modal dialog showing JSON data
#     Syntax-highlighted output
#     Copy to clipboard functionality
#     Send to WineJS webhook integration

# 3. Forgejo-Specific Selectors
#     Works with Forgejo's HTML structure
#     Multiple fallback selectors for compatibility
#     Detects when page loads via Turbolinks/Turbo

# 4. Webhook Integration
#     Sends extracted data to /api/webhooks/repo-info
#     Visual feedback when sending
#     Error handling with status messages

# 5. Enhanced Features
#     Shows stars and forks statistics
#     Detects fork status
#     Extracts language and default branch
#     Includes timestamp of extraction
#     Clean, responsive design

# ============= SETUP ADMIN USER =============
log "Setting up admin user..."
bash "$APP_DIR/setup-admin.sh" &

# ============= UPDATE NGINX CONFIG =============
log "Updating nginx configuration for Forgejo..."
# The pattern for ALL installers (Mumble, PufferPanel, Forgejo, VSCode):
#   1. Find the HTTPS server block by locating "listen 443"
#   2. Count braces { and } to find the exact closing brace of that server block
#   3. Insert new location blocks BEFORE that closing brace
#   4. This guarantees routes are safely INSIDE the correct server block
# This method is proven to work (VSCode uses it) and never creates orphaned directives.
# DO NOT insert before "listen 443" - that breaks the config.
# DO NOT insert after random lines like "root" or "server_name" - that's fragile.
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    # Check if Forgejo routes already exist
    if ! grep -q "location /forgejo/" /etc/nginx/sites-available/winejs; then
        # Backup the current config
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
                # Insert routes BEFORE the closing brace (safe inside server block)
                sed -i "${HTTPS_END}i\\
    # Forgejo Git Server\n\
    location /forgejo/ {\n\
        rewrite ^/forgejo(/.*)$ \$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \$host;\n\
        proxy_set_header X-Real-IP \$remote_addr;\n\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        client_max_body_size 1024M;\n\
        proxy_buffering off;\n\
        proxy_read_timeout 86400s;\n\
        proxy_send_timeout 86400s;\n\
    }\n\
    location /forgejo-lfs/ {\n\
        proxy_pass http://127.0.0.1:${LFS_MAPPER_PORT};\n\
        proxy_set_header Host \$host;\n\
    }\n\
    location /api/v1/repos/ {\n\
        proxy_pass http://127.0.0.1:${LFS_MAPPER_PORT};\n\
        proxy_set_header Host \$host;\n\
        proxy_set_header X-Real-IP \$remote_addr;\n\
    }\n" /etc/nginx/sites-available/winejs
                
                log "✅ Forgejo routes inserted safely"
                
                # Test and reload
                if nginx -t; then
                    systemctl reload nginx
                    log "✅ Nginx updated with Forgejo routes"
                    log "   • /forgejo/ → Forgejo (port ${APP_PORT})"
                    log "   • /forgejo-lfs/ → LFS Mapper (port ${LFS_MAPPER_PORT})"
                    log "   • /api/v1/repos/ → LFS Mapper API (port ${LFS_MAPPER_PORT})"
                else
                    warn "Nginx test failed, restoring backup"
                    cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                    nginx -t && systemctl reload nginx
                    log "⚠️ Could not add Forgejo routes automatically"
                fi
            else
                warn "Could not find HTTPS block closing brace"
            fi
        else
            warn "Could not find HTTPS server block (listen 443)"
        fi
    else
        log "Forgejo routes already exist in nginx config"
    fi
else
    warn "nginx config not found, skipping"
fi

# ============= RELOAD TRANSLATOR =============
log "Reloading WineJS translator..."

pm2 restart translator 2>/dev/null || true

# ============= CREATE HELPER SCRIPT =============
log "Creating helper script..."

cat > /usr/local/bin/winejs-forgejo << EOF
#!/bin/bash
# Quick Forgejo launcher for WineJS

case "\$1" in
    repos)
        echo "Listing repositories..."
        curl -s "http://localhost:${LFS_MAPPER_PORT}/api/repos" | jq .
        ;;
    clone)
        if [ -n "\$2" ]; then
            echo "Cloning \$2..."
            curl -X POST "http://localhost:${LFS_MAPPER_PORT}/api/clone" \\
                -H "Content-Type: application/json" \\
                -d "{\"repoUrl\":\"\$2\"}" | jq .
        else
            echo "Usage: winejs-forgejo clone <repo-url>"
        fi
        ;;
    browse)
        PATH_TO_BROWSE="\${2:-/opt/winejs/repositories}"
        curl -s "http://localhost:${LFS_MAPPER_PORT}/api/browse?path=\$PATH_TO_BROWSE" | jq .
        ;;
    status)
        echo "Forgejo status:"
        docker ps | grep forgejo
        echo ""
        echo "LFS Mapper status:"
        pm2 list | grep lfs-mapper
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://${DOMAIN_NAME}/forgejo"
        elif command -v open &> /dev/null; then
            open "https://${DOMAIN_NAME}/forgejo"
        else
            echo "Visit: https://${DOMAIN_NAME}/forgejo"
        fi
        ;;
    *)
        echo "WineJS Forgejo Helper"
        echo ""
        echo "Commands:"
        echo "  winejs-forgejo open      - Open Forgejo in browser"
        echo "  winejs-forgejo repos     - List all repositories"
        echo "  winejs-forgejo browse    - Browse repositories"
        echo "  winejs-forgejo clone     - Clone a repository"
        echo "  winejs-forgejo status    - Check service status"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-forgejo

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            FORGEJO SERVER INSTALLED ON WINEJS!                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Forgejo Server installed as a WineJS app!"
echo ""
info "🌐 Access URLs:"
info "   • Forgejo UI: https://$DOMAIN_NAME/forgejo/"
info "   • Git Clone: git clone https://$DOMAIN_NAME/forgejo/username/repo.git"
info "   • SSH Clone: git clone git@$DOMAIN_NAME:username/repo.git"
echo ""
info "🔑 Admin Credentials:"
info "   • Email: $ADMIN_EMAIL"
info "   • Password: $ADMIN_PASSWORD"
echo ""
info "📂 Repository Storage:"
info "   • Repositories: /opt/winejs/repositories"
info "   • LFS Storage: /opt/winejs/data/forgejo/lfs"
info "   • Backups: /opt/winejs/shared-volumes/backups"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-forgejo open        # Open Forgejo in browser"
info "   • winejs-forgejo repos       # List all repositories"
info "   • winejs-forgejo clone <url> # Clone a repository"
info "   • winejs-forgejo status      # Check service status"
info "   • mount-helper list          # List shared volumes"
echo ""
info "🔧 Features:"
info "   • Git repository hosting"
info "   • Issue tracker and pull requests"
info "   • CI/CD with GitHub Actions compatible workflows"
info "   • Git LFS support for large files"
info "   • Webhooks for automation"
info "   • Code review and collaboration"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_forgejo.sh"
echo ""
success "✨ Forgejo Server is ready! Visit https://$DOMAIN_NAME/forgejo/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"
