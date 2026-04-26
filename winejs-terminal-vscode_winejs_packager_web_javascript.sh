#!/bin/bash
set -e

# =================================================
# WineJS Web App Packager - VS Code Extension
# Paste URL → Package Web Apps for WineJS
# =================================================

# Key Features:
# Feature	How it works
# GitHub Repos	Clones repo, serves with nginx:alpine
# Docker Hub	Pulls image, runs directly
# Auto port	Same dynamic port detection in WineJS
# Same dashboard	Appears alongside MilkShape
# Shared storage	/uploads mounted to all containers
# One command	sudo bash install_appname.sh

# Now you can package ANYTHING!
#     🪟 Windows apps (EXE folder)
#     🌐 Web apps (GitHub repo)
#     🐳 Docker apps (any image)
#     🎮 Games (both Windows and web)
#     📊 Databases (PostgreSQL, MySQL)
#     🔧 Tools (VS Code Server, Jupyter)

# The unified platform is complete! 🚀

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo -e "${MAGENTA}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           WineJS Web Packager - VS Code Extension             ║"
echo "║                                                               ║"
echo "║   Paste GitHub URL or Docker image → Package for WineJS       ║"
echo "║                                                               ║"
echo "║   📝 Enter GitHub URL or Docker image                         ║"
echo "║   📝 Enter app name (auto-filled)                             ║"
echo "║   🎨 Icon from URL or default                                 ║"
echo "║   📝 Generates install_webapp.sh script                       ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Ask for extension name
read -p "Enter extension folder name (default: winejs-web-packager): " EXTNAME
EXTNAME=${EXTNAME:-winejs-web-packager}

# Check if folder exists
if [ -d "$EXTNAME" ]; then
    read -p "Folder '$EXTNAME' already exists. Remove it? (y/N): " REMOVE
    REMOVE=${REMOVE:-N}
    if [[ "$REMOVE" == "y" || "$REMOVE" == "Y" ]]; then
        echo "Removing existing folder '$EXTNAME'..."
        rm -rf "$EXTNAME"
    else
        echo "Exiting to avoid overwriting."
        exit 1
    fi
fi

# Create folder structure
mkdir -p "$EXTNAME/src" "$EXTNAME/out" "$EXTNAME/media"
cd "$EXTNAME" || exit

# Download logo
echo -e "${CYAN}📥 Downloading extension logo...${NC}"
curl -s -o media/logo.png "https://cdn.gitgpt.chat/rtx/images/winejs-packager-logo.png" 2>/dev/null || echo "Logo download skipped"

# ===============================================
# Create package.json
# ===============================================
cat <<EOL > package.json
{
  "name": "winejs-web-packager",
  "displayName": "WineJS Web Packager",
  "description": "Paste GitHub URL or Docker image → Package web apps for WineJS",
  "repository": "https://github.com/winejs/web-packager",
  "publisher": "winejs",
  "version": "1.0.0",
  "icon": "media/logo.png",
  "engines": {
    "vscode": "^1.81.0"
  },
  "categories": ["Other"],
  "activationEvents": ["onCommand:winejs.packageWebApp"],
  "main": "./out/extension.js",
  "contributes": {
    "commands": [
      {
        "command": "winejs.packageWebApp",
        "title": "WineJS: Package Web App",
        "category": "WineJS"
      }
    ],
    "configuration": {
      "title": "WineJS Web Packager",
      "properties": {
        "winejs.spaces.accessKey": {
          "type": "string",
          "description": "DigitalOcean Spaces Access Key"
        },
        "winejs.spaces.secretKey": {
          "type": "string",
          "description": "DigitalOcean Spaces Secret Key"
        },
        "winejs.spaces.bucket": {
          "type": "string",
          "default": "sdappnet-cloud",
          "description": "DigitalOcean Spaces Bucket Name"
        },
        "winejs.spaces.folder": {
          "type": "string",
          "default": "rtx/wine/webapps",
          "description": "Folder in bucket for web app packages"
        },
        "winejs.spaces.endpoint": {
          "type": "string",
          "default": "https://fra1.digitaloceanspaces.com",
          "description": "DigitalOcean Spaces Endpoint URL"
        },
        "winejs.spaces.makePublic": {
          "type": "boolean",
          "default": true,
          "description": "Make uploaded files publicly accessible"
        },
        "winejs.spaces.cdnEndpoint": {
          "type": "string",
          "description": "DigitalOcean CDN Endpoint URL (optional)"
        }
      }
    }
  },
  "scripts": {
    "compile": "tsc -p ./",
    "watch": "tsc -watch -p ./"
  },
  "devDependencies": {
    "@types/node": "20.x",
    "@types/vscode": "^1.81.0",
    "typescript": "^5.7.2"
  },
  "dependencies": {
    "@aws-sdk/client-s3": "^3.654.0"
  }
}
EOL

# ===============================================
# Create tsconfig.json
# ===============================================
cat <<EOL > tsconfig.json
{
  "compilerOptions": {
    "module": "Node16",
    "target": "ES2022",
    "outDir": "out",
    "lib": ["ES2022"],
    "sourceMap": true,
    "rootDir": "src",
    "strict": true
  }
}
EOL

# ===============================================
# Create extension.ts (FULL VERSION)
# ===============================================
cat <<'EOL' > src/extension.ts
import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import * as crypto from 'crypto';
import * as https from 'https';

export function activate(context: vscode.ExtensionContext) {
    console.log('✅ WineJS Web Packager activated!');

    const disposable = vscode.commands.registerCommand('winejs.packageWebApp', async () => {
        try {
            await packageWebApp();
        } catch (error: any) {
            vscode.window.showErrorMessage(`Failed to package web app: ${error.message}`);
        }
    });

    context.subscriptions.push(disposable);
}

async function packageWebApp() {
    // Step 1: Get source URL
    const sourceUrl = await vscode.window.showInputBox({
        title: 'WineJS Web Packager',
        prompt: 'Enter GitHub repository URL or Docker Hub image name',
        placeHolder: 'https://github.com/user/repo  or  nginx:alpine',
        validateInput: (value) => {
            if (!value) return 'URL or image name cannot be empty';
            return null;
        }
    });
    
    if (!sourceUrl) {
        vscode.window.showInformationMessage('Packaging cancelled');
        return;
    }
    
    // Determine source type
    let sourceType: 'github' | 'docker' = 'docker';
    let defaultAppName = '';
    
    if (sourceUrl.includes('github.com')) {
        sourceType = 'github';
        const repoMatch = sourceUrl.match(/github\.com\/([^\/]+\/[^\/]+)/);
        if (repoMatch) {
            defaultAppName = repoMatch[1].split('/')[1];
        }
    } else {
        const imageMatch = sourceUrl.match(/^([^\/:]+)/);
        if (imageMatch) {
            defaultAppName = imageMatch[1];
        }
    }
    
    // Step 2: Get app name
    const appName = await vscode.window.showInputBox({
        title: 'App Name',
        prompt: 'Enter the name of the web application',
        value: defaultAppName,
        validateInput: (value) => value ? null : 'App name cannot be empty'
    });

    if (!appName) {
        vscode.window.showInformationMessage('Packaging cancelled');
        return;
    }
    
    // Step 3: Get container port (for Docker)
    let containerPort = 80;
    if (sourceType === 'docker') {
        const portInput = await vscode.window.showInputBox({
            title: 'Container Port',
            prompt: 'Port the container listens on (usually 80, 3000, 8080)',
            value: '80',
            placeHolder: '80, 3000, 8080',
            validateInput: (value) => /^\d+$/.test(value) ? null : 'Must be a number'
        });
        if (portInput) containerPort = parseInt(portInput);
        if (!portInput) {
            vscode.window.showInformationMessage('Packaging cancelled');
            return;
        }
    }
    
    // Step 4: Get category
    const category = await vscode.window.showQuickPick(
        ['Web App', 'Game', 'Dashboard', 'API', 'Database', 'Media', 'Utility', 'Other'],
        { placeHolder: 'Select app category', title: 'App Category' }
    );
    
    // Step 5: Get icon
    const iconChoice = await vscode.window.showQuickPick(
        [
            { label: '🌐 Use URL', description: 'Provide a URL to an icon image' },
            { label: '🔗 Use default WineJS icon', description: 'Use the standard placeholder icon' }
        ],
        { placeHolder: 'How do you want to handle the app icon?' }
    );

    let iconUrl = 'https://cdn.gitgpt.chat/rtx/images/wine-placeholder.png';
    
    if (iconChoice?.label.includes('URL')) {
        const urlInput = await vscode.window.showInputBox({
            title: 'Icon URL',
            prompt: 'Enter the URL of the icon image (PNG or JPG)',
            placeHolder: 'https://example.com/icon.png',
            validateInput: (value) => {
                if (!value) return 'URL cannot be empty';
                if (!value.startsWith('http')) return 'URL must start with http:// or https://';
                return null;
            }
        });
        if (urlInput) iconUrl = urlInput;
        if (!urlInput) {
            vscode.window.showInformationMessage('Packaging cancelled');
            return;
        }
    }
    
    // Step 6: Create install folder
    const sanitizedAppName = appName.toLowerCase().replace(/\s+/g, '_');
    const installFolder = path.join(os.homedir(), 'Desktop', `${sanitizedAppName}_install`);
    
    if (!fs.existsSync(installFolder)) {
        fs.mkdirSync(installFolder, { recursive: true });
    }
    
    const installScriptPath = path.join(installFolder, `install_${sanitizedAppName}.sh`);
    const iconPath = path.join(installFolder, `${sanitizedAppName}.png`);
    let iconUploadUrl = iconUrl;
    let zipUrl = 'LOCAL_FILE';
    const randomPass = crypto.randomBytes(6).toString('hex');
    const nextPort = 6902;
    
    // Download icon locally
    if (iconUrl.startsWith('http')) {
        try {
            const iconResponse = await fetch(iconUrl);
            const iconBuffer = Buffer.from(await iconResponse.arrayBuffer());
            fs.writeFileSync(iconPath, iconBuffer);
            iconUploadUrl = 'LOCAL_FILE';
        } catch (error) {
            console.log('Failed to download icon, will use URL in install script');
        }
    }
    
    // Step 7: Upload to Spaces
    const config = vscode.workspace.getConfiguration('winejs');
    const accessKey = config.get('spaces.accessKey') as string;
    const secretKey = config.get('spaces.secretKey') as string;
    const bucket = config.get('spaces.bucket') as string;
    const endpoint = config.get('spaces.endpoint') as string || "https://fra1.digitaloceanspaces.com";
    const region = config.get('spaces.region') as string || "fra1";
    const spacesFolder = config.get('spaces.folder') as string || "rtx/wine/webapps";
    const makePublic = config.get('spaces.makePublic') as boolean ?? true;
    const cdnEndpoint = config.get('spaces.cdnEndpoint') as string || null;
    
    const uploadChoice = await vscode.window.showQuickPick(
        ['✅ Yes, upload to Spaces', '❌ No, save locally'],
        { placeHolder: 'Upload package to DigitalOcean Spaces?' }
    );

    if (uploadChoice?.includes('Yes') && accessKey && secretKey && bucket) {
        try {
            const s3Module = require('@aws-sdk/client-s3');
            const { PutObjectCommand, S3Client } = s3Module;
            
            await vscode.window.withProgress({
                location: vscode.ProgressLocation.Notification,
                title: "☁️ Uploading to DigitalOcean Spaces...",
                cancellable: false
            }, async (progress) => {
                const s3Client = new S3Client({
                    endpoint: endpoint,
                    forcePathStyle: false,
                    region: region,
                    credentials: { accessKeyId: accessKey, secretAccessKey: secretKey }
                });
                
                // Create ZIP of the install folder
                const tempZip = path.join(os.tmpdir(), `${sanitizedAppName}.zip`);
                const exec = require('child_process').execSync;
                exec(`cd "${installFolder}" && zip -r "${tempZip}" .`);
                
                const zipKey = `${spacesFolder}/${sanitizedAppName}.zip`;
                const zipContent = fs.readFileSync(tempZip);
                
                const zipParams: any = {
                    Bucket: bucket,
                    Key: zipKey,
                    Body: zipContent,
                    ContentType: 'application/zip',
                    Metadata: { "app-name": appName }
                };
                if (makePublic) zipParams.ACL = 'public-read';
                await s3Client.send(new PutObjectCommand(zipParams));
                
                const spaceUrl = endpoint.replace('https://', `https://${bucket}.`);
                zipUrl = cdnEndpoint ? `${cdnEndpoint}/${zipKey}` : `${spaceUrl}/${zipKey}`;
                
                // Upload icon if exists
                if (fs.existsSync(iconPath)) {
                    const iconKey = `${spacesFolder}/images/${sanitizedAppName}.png`;
                    const iconContent = fs.readFileSync(iconPath);
                    const iconParams: any = {
                        Bucket: bucket,
                        Key: iconKey,
                        Body: iconContent,
                        ContentType: 'image/png',
                        Metadata: { "app-name": appName }
                    };
                    if (makePublic) iconParams.ACL = 'public-read';
                    await s3Client.send(new PutObjectCommand(iconParams));
                    iconUploadUrl = cdnEndpoint ? `${cdnEndpoint}/${iconKey}` : `${spaceUrl}/${iconKey}`;
                }
                
                fs.unlinkSync(tempZip);
            });
            
            vscode.window.showInformationMessage(`✅ Uploaded to Spaces!`, "Copy URL").then(selection => {
                if (selection === "Copy URL") vscode.env.clipboard.writeText(zipUrl);
            });
        } catch (error: any) {
            vscode.window.showErrorMessage(`Upload failed: ${error.message}`);
            zipUrl = 'LOCAL_FILE';
        }
    }
    
    // Step 8: Generate install script
    const installScript = generateWebAppInstallScript({
        appName: sanitizedAppName,
        displayName: appName,
        sourceUrl: sourceUrl,
        sourceType: sourceType,
        containerPort: containerPort,
        category: category || 'Web App',
        iconUrl: iconUploadUrl,
        zipUrl: zipUrl,
        vncPassword: randomPass,
        port: nextPort
    });
    
    fs.writeFileSync(installScriptPath, installScript);
    fs.chmodSync(installScriptPath, 0o755);
    
    // Step 9: Show success
    const openFolder = await vscode.window.showInformationMessage(
        `✅ Web app package created: ${installFolder}`,
        'Open Folder',
        'Show README'
    );
    
    if (openFolder === 'Open Folder') {
        vscode.commands.executeCommand('revealFileInOS', vscode.Uri.file(installFolder));
    } else if (openFolder === 'Show README') {
        const readmePath = path.join(installFolder, 'README.md');
        if (fs.existsSync(readmePath)) {
            const doc = await vscode.workspace.openTextDocument(readmePath);
            await vscode.window.showTextDocument(doc);
        }
    }
}

function generateWebAppInstallScript(params: any): string {
    const uninstallScriptPath = `uninstall_${params.appName}.sh`;
    
    return `#!/bin/bash
# ============================================
# WineJS Web App Installer
# Generated by WineJS Web Packager v1.0
# ============================================
# App: ${params.displayName}
# Type: Web App
# Source: ${params.sourceUrl}
# Category: ${params.category}
# ============================================

set -e

# Colors
RED='\\033[0;31m'; GREEN='\\033[0;32m'; YELLOW='\\033[1;33m'; NC='\\033[0m'
log() { echo -e "\${GREEN}[$(date '+%H:%M:%S')]\${NC} \$1"; }
error() { echo -e "\${RED}[ERROR]\${NC} \$1"; exit 1; }

log "Installing ${params.displayName}..."

# ============= VERIFY WINEJS PLATFORM =============
log "Verifying WineJS platform..."

if [ ! -d "/opt/winejs" ]; then
    error "WineJS platform not found at /opt/winejs"
    exit 1
fi

if ! docker network ls | grep -q "winejs-net"; then
    log "Creating winejs-net network..."
    docker network create winejs-net
fi

log "WineJS platform verified"

# ============= FIND NEXT AVAILABLE PORT =============
log "Finding next available port..."

MAX_PORT=6900
if [ -d "/opt/winejs/apps" ]; then
    for config in /opt/winejs/apps/*/config.json; do
        if [ -f "\$config" ]; then
            PORT=\$(grep -o '"port": [0-9]*' "\$config" | awk '{print \$2}')
            if [ -n "\$PORT" ] && [ "\$PORT" -gt "\$MAX_PORT" ]; then
                MAX_PORT=\$PORT
            fi
        fi
    done
fi

APP_PORT=\$((MAX_PORT + 1))
log "Using port: \$APP_PORT (next available after \$MAX_PORT)"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="${params.appName}"
APP_DIR="/opt/winejs/apps/\$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/\$APP_NAME"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "\$APP_DIR"
mkdir -p "\$INSTANCE_DIR"
mkdir -p "\$ICON_DIR"

# ============= DOWNLOAD APP =============
log "Downloading ${params.displayName}..."

if [[ "${params.sourceType}" == "github" ]]; then
    git clone ${params.sourceUrl} "\$APP_DIR"
    log "✅ Cloned from GitHub"
else
    docker pull ${params.sourceUrl}
    log "✅ Docker image pulled"
fi

# ============= DOWNLOAD ICON =============
log "Downloading app icon..."
if [[ ${params.iconUrl} == "LOCAL_FILE" ]]; then
    log "Local icon - please copy manually"
else
    curl -L ${params.iconUrl} -o "\$ICON_DIR/\${APP_NAME}.png" 2>/dev/null || echo "Failed to download icon"
fi

# ============= CREATE CONFIG.JSON =============
log "Generating config.json..."
cat > "\$APP_DIR/config.json" << CONF_EOF
{
    "name": "${params.displayName}",
    "type": "web",
    "port": \${APP_PORT},
    "icon": "/icons/${params.sanitizedName}.png",
    "category": "${params.category}"
}
CONF_EOF

# ============= CREATE DOCKER-COMPOSE.YML =============
log "Generating docker-compose.yml..."

if [[ "${params.sourceType}" == "github" ]]; then
    cat > "\$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
version: '3.8'

services:
  winejs-\${APP_NAME}:
    image: nginx:alpine
    container_name: winejs-\${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:\${APP_PORT}:80"
    volumes:
      - \$APP_DIR:/usr/share/nginx/html:ro
      - /var/www/uploads:/uploads:ro
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF
else
    cat > "\$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
version: '3.8'

services:
  winejs-\${APP_NAME}:
    image: ${params.sourceUrl}
    container_name: winejs-\${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:\${APP_PORT}:${params.containerPort}"
    volumes:
      - /var/www/uploads:/uploads:rw
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF
fi

# ============= CREATE UNINSTALL SCRIPT =============
log "Creating uninstall script..."
cat > "\$(dirname "\$APP_DIR")/${uninstallScriptPath}" << UNINSTALL_EOF
#!/bin/bash
# ============================================
# WineJS Web App Uninstaller
# Generated by WineJS Web Packager v1.0
# ============================================
# App: ${params.displayName}
# ============================================

set -e

cd /tmp || cd /root || cd / || exit 1

log "Uninstalling ${params.displayName}..."

APP_NAME="${params.appName}"
APP_DIR="/opt/winejs/apps/\$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/\$APP_NAME"
ICON_FILE="/opt/winejs/translator/public/icons/\${APP_NAME}.png"

if docker ps -a | grep -q "winejs-\${APP_NAME}"; then
    cd "\$INSTANCE_DIR" 2>/dev/null || true
    docker-compose down 2>/dev/null || true
    docker rm "winejs-\${APP_NAME}" 2>/dev/null || true
fi

rm -rf "\$INSTANCE_DIR" 2>/dev/null || true
rm -rf "\$APP_DIR" 2>/dev/null || true
rm -f "\$ICON_FILE" 2>/dev/null || true

cd /tmp || cd /root || cd /
pm2 restart translator 2>/dev/null || true

log "${params.displayName} uninstalled successfully"
UNINSTALL_EOF

chmod +x "\$(dirname "\$APP_DIR")/${uninstallScriptPath}"
log "Uninstall script created: \$(dirname "\$APP_DIR")/${uninstallScriptPath}"

# ============= RELOAD TRANSLATOR =============
log "Reloading WineJS translator..."
pm2 restart translator 2>/dev/null || pm2 start /opt/winejs/ecosystem.config.js 2>/dev/null || true

# ============= START THE CONTAINER =============
log "Starting container for ${params.displayName}..."
cd "\$INSTANCE_DIR"
docker-compose up -d

sleep 3

if docker ps | grep -q "winejs-\${APP_NAME}"; then
    log "Container started successfully"
else
    log "Container may not have started. Check with: docker logs winejs-\${APP_NAME}"
fi

# ============= SHOW ACCESS INFO =============
log "${params.displayName} installed successfully!"
log "Access at: https://\$(hostname -f)/\${APP_NAME}"

echo ""
echo "============================================"
echo "Installation Complete!"
echo "============================================"
echo ""
echo "App: ${params.displayName}"
echo "URL: https://\$(hostname -f)/\${APP_NAME}"
echo "Source: ${params.sourceUrl}"
echo ""
echo "To uninstall: sudo bash \$(dirname "\$APP_DIR")/${uninstallScriptPath}"
echo ""
`;
}

export function deactivate() {}
EOL

# ===============================================
# Create .vscodeignore
# ===============================================
cat <<EOL > .vscodeignore
.vscode
src
*.ts
*.map
.git
.gitignore
EOL


# -----------------------------
# Create License.md (MIT License)
# -----------------------------
cat <<EOL > LICENSE.md
MIT License

Copyright (c) $(date +%Y) Gabriel Majorsky

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
EOL

# ===============================================
# Build and Install Extension
# ===============================================

echo -e "${CYAN}🔨 Building and installing extension...${NC}"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
export NODE_OPTIONS=--openssl-legacy-provider

echo -e "${YELLOW}Node: $(node -v) | npm: $(npm -v)${NC}"

echo -e "${CYAN}📦 Installing Node dependencies...${NC}"
npm install

echo -e "${CYAN}🔨 Compiling TypeScript...${NC}"
npm run compile

echo -e "${CYAN}📦 Packaging extension...${NC}"

if ! command -v vsce &> /dev/null; then
    echo -e "${YELLOW}Installing vsce...${NC}"
    npm install -g vsce
fi

vsce package --allow-missing-repository

VSIX_FILE=$(ls winejs-web-packager-*.vsix 2>/dev/null | head -n1)

if [ ! -f "$VSIX_FILE" ]; then
    echo -e "${RED}❌ Failed to package extension${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Extension packaged: $VSIX_FILE${NC}"
echo -e "${CYAN}📊 Package size: $(du -h "$VSIX_FILE" | cut -f1)${NC}"

echo -e "${CYAN}📥 Installing extension...${NC}"

if command -v code-server &> /dev/null; then
    code-server --install-extension "$VSIX_FILE" --force
else
    code --install-extension "$VSIX_FILE" --force
fi

echo -e "${GREEN}✅ WineJS Web Packager installed successfully!${NC}"
echo ""
echo -e "${CYAN}🚀 Usage:${NC}"
echo "1. Open Command Palette (Cmd+Shift+P / Ctrl+Shift+P)"
echo "2. Search for 'WineJS: Package Web App'"
echo "3. Paste GitHub URL or Docker image"
echo "4. Follow the prompts"
echo ""
echo -e "${GREEN}✅ Done!${NC}"

