"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = __importStar(require("vscode"));
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
const os = __importStar(require("os"));
const crypto = __importStar(require("crypto"));
function activate(context) {
    console.log('✅ WineJS Web Packager activated!');
    const disposable = vscode.commands.registerCommand('winejs.packageWebApp', async () => {
        try {
            await packageWebApp();
        }
        catch (error) {
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
            if (!value)
                return 'URL or image name cannot be empty';
            return null;
        }
    });
    if (!sourceUrl) {
        vscode.window.showInformationMessage('Packaging cancelled');
        return;
    }
    // Determine source type
    let sourceType = 'docker';
    let defaultAppName = '';
    if (sourceUrl.includes('github.com')) {
        sourceType = 'github';
        const repoMatch = sourceUrl.match(/github\.com\/([^\/]+\/[^\/]+)/);
        if (repoMatch) {
            defaultAppName = repoMatch[1].split('/')[1];
        }
    }
    else {
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
        if (portInput)
            containerPort = parseInt(portInput);
        if (!portInput) {
            vscode.window.showInformationMessage('Packaging cancelled');
            return;
        }
    }
    // Step 4: Get category
    const category = await vscode.window.showQuickPick(['Web App', 'Game', 'Dashboard', 'API', 'Database', 'Media', 'Utility', 'Other'], { placeHolder: 'Select app category', title: 'App Category' });
    // Step 5: Get icon
    const iconChoice = await vscode.window.showQuickPick([
        { label: '🌐 Use URL', description: 'Provide a URL to an icon image' },
        { label: '🔗 Use default WineJS icon', description: 'Use the standard placeholder icon' }
    ], { placeHolder: 'How do you want to handle the app icon?' });
    let iconUrl = 'https://cdn.gitgpt.chat/rtx/images/wine-placeholder.png';
    if (iconChoice?.label.includes('URL')) {
        const urlInput = await vscode.window.showInputBox({
            title: 'Icon URL',
            prompt: 'Enter the URL of the icon image (PNG or JPG)',
            placeHolder: 'https://example.com/icon.png',
            validateInput: (value) => {
                if (!value)
                    return 'URL cannot be empty';
                if (!value.startsWith('http'))
                    return 'URL must start with http:// or https://';
                return null;
            }
        });
        if (urlInput)
            iconUrl = urlInput;
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
        }
        catch (error) {
            console.log('Failed to download icon, will use URL in install script');
        }
    }
    // Step 7: Upload to Spaces
    const config = vscode.workspace.getConfiguration('winejs');
    const accessKey = config.get('spaces.accessKey');
    const secretKey = config.get('spaces.secretKey');
    const bucket = config.get('spaces.bucket');
    const endpoint = config.get('spaces.endpoint') || "https://fra1.digitaloceanspaces.com";
    const region = config.get('spaces.region') || "fra1";
    const spacesFolder = config.get('spaces.folder') || "rtx/wine/webapps";
    const makePublic = config.get('spaces.makePublic') ?? true;
    const cdnEndpoint = config.get('spaces.cdnEndpoint') || null;
    const uploadChoice = await vscode.window.showQuickPick(['✅ Yes, upload to Spaces', '❌ No, save locally'], { placeHolder: 'Upload package to DigitalOcean Spaces?' });
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
                const zipParams = {
                    Bucket: bucket,
                    Key: zipKey,
                    Body: zipContent,
                    ContentType: 'application/zip',
                    Metadata: { "app-name": appName }
                };
                if (makePublic)
                    zipParams.ACL = 'public-read';
                await s3Client.send(new PutObjectCommand(zipParams));
                const spaceUrl = endpoint.replace('https://', `https://${bucket}.`);
                zipUrl = cdnEndpoint ? `${cdnEndpoint}/${zipKey}` : `${spaceUrl}/${zipKey}`;
                // Upload icon if exists
                if (fs.existsSync(iconPath)) {
                    const iconKey = `${spacesFolder}/images/${sanitizedAppName}.png`;
                    const iconContent = fs.readFileSync(iconPath);
                    const iconParams = {
                        Bucket: bucket,
                        Key: iconKey,
                        Body: iconContent,
                        ContentType: 'image/png',
                        Metadata: { "app-name": appName }
                    };
                    if (makePublic)
                        iconParams.ACL = 'public-read';
                    await s3Client.send(new PutObjectCommand(iconParams));
                    iconUploadUrl = cdnEndpoint ? `${cdnEndpoint}/${iconKey}` : `${spaceUrl}/${iconKey}`;
                }
                fs.unlinkSync(tempZip);
            });
            vscode.window.showInformationMessage(`✅ Uploaded to Spaces!`, "Copy URL").then(selection => {
                if (selection === "Copy URL")
                    vscode.env.clipboard.writeText(zipUrl);
            });
        }
        catch (error) {
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
    const openFolder = await vscode.window.showInformationMessage(`✅ Web app package created: ${installFolder}`, 'Open Folder', 'Show README');
    if (openFolder === 'Open Folder') {
        vscode.commands.executeCommand('revealFileInOS', vscode.Uri.file(installFolder));
    }
    else if (openFolder === 'Show README') {
        const readmePath = path.join(installFolder, 'README.md');
        if (fs.existsSync(readmePath)) {
            const doc = await vscode.workspace.openTextDocument(readmePath);
            await vscode.window.showTextDocument(doc);
        }
    }
}
function generateWebAppInstallScript(params) {
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
function deactivate() { }
//# sourceMappingURL=extension.js.map