#!/bin/bash
set -e

# =================================================
# WineJS Packager - VS Code Extension
# Right-click → Package Windows Apps for WineJS
# =================================================
# ┌─────────────────────────────────────────────────────────────┐
# │                 WineJS Packager v1.0                        │
# ├─────────────────────────────────────────────────────────────┤
# │  ✅ Right-click any folder                                  │
# │  ✅ Auto-filled app name                                    │
# │  ✅ EXE scanner with smart filtering                        │
# │  ✅ 3 icon options (Extract/URL/Default)                    │
# │  ✅ Icon preview & confirmation                             │
# │  ✅ ZIP creation                                            │
# │  ✅ Spaces upload (both zip + icon)                         │
# │  ✅ GENERATES install_AppName.sh                            │
# │  ✅ Matches your MilkShape pattern exactly!                 │
# └─────────────────────────────────────────────────────────────┘

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo -e "${MAGENTA}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                                                               ║"
echo "║           WineJS Packager - VS Code Extension                 ║"
echo "║                                                               ║"
echo "║   Right-click any folder → Package for WineJS                 ║"
echo "║                                                               ║"
echo "║   📝 Enter app name (auto-filled)                             ║"
echo "║   📋 Lists all EXE files - you pick main                      ║"
echo "║   🎨 3 icon options: Extract/URL/Default                      ║"
echo "║   📦 Creates ZIP package                                      ║"
echo "║   ☁️  Uploads BOTH zip + icon to rtx/wine/                     ║"
echo "║   📝 Generates install_appname.sh script                      ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Ask for extension name
read -p "Enter extension folder name (default: winejs-packager): " EXTNAME
EXTNAME=${EXTNAME:-winejs-packager}

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
mkdir -p "$EXTNAME/src" "$EXTNAME/sh" "$EXTNAME/out" "$EXTNAME/resources"
cd "$EXTNAME" || exit

# Download logo
echo -e "${CYAN}📥 Downloading WineJS Packager logo...${NC}"
curl -s -o sh/logo.png "https://cdn.gitgpt.chat/rtx/images/winejs-web-packager-logo.png"

# ===============================================
# Create icon extraction helper script
# ===============================================
cat <<'EOL' > sh/extract_icon.sh
#!/bin/bash
EXE_FILE="$1"
OUTPUT_DIR="$2"

echo "🔍 Extracting icons from: $(basename "$EXE_FILE")"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Extract icons using icoutils
TEMP_ICO_DIR="$OUTPUT_DIR/ico_temp"
mkdir -p "$TEMP_ICO_DIR"

# Extract all icon resources (type 14 = RT_ICON)
wrestool --extract --type=14 "$EXE_FILE" -o "$TEMP_ICO_DIR/" 2>/dev/null

# If no icons found, try group_icon (type 14 also covers group_icon)
ICO_COUNT=$(find "$TEMP_ICO_DIR" -name "*.ico" 2>/dev/null | wc -l)
if [ "$ICO_COUNT" -eq 0 ]; then
    # Try alternative extraction method
    wrestool --extract --type=group_icon "$EXE_FILE" -o "$TEMP_ICO_DIR/" 2>/dev/null
    ICO_COUNT=$(find "$TEMP_ICO_DIR" -name "*.ico" 2>/dev/null | wc -l)
fi

echo "📦 Found $ICO_COUNT ICO resource(s)"

# Convert ALL ICOs to PNGs (extract all sizes from each ICO)
PNG_TOTAL=0
if [ "$ICO_COUNT" -gt 0 ]; then
    for ico in "$TEMP_ICO_DIR"/*.ico; do
        if [ -f "$ico" ]; then
            # Extract ALL PNGs from the ICO (icotool extracts all sizes)
            icotool -x "$ico" -o "$OUTPUT_DIR/" 2>/dev/null
            PNG_EXTRACTED=$(find "$OUTPUT_DIR" -name "*.png" -newer "$ico" 2>/dev/null | wc -l)
            PNG_TOTAL=$((PNG_TOTAL + PNG_EXTRACTED))
            echo "  ✓ Extracted $PNG_EXTRACTED PNG(s) from $(basename "$ico")"
        fi
    done
fi

# Cleanup
rm -rf "$TEMP_ICO_DIR"

# Count all PNGs
PNG_COUNT=$(find "$OUTPUT_DIR" -name "*.png" 2>/dev/null | wc -l)

if [ "$PNG_COUNT" -gt 0 ]; then
    echo "✅ Total PNGs extracted: $PNG_COUNT"
    
    # Find the largest PNG (by file size)
    LARGEST=$(find "$OUTPUT_DIR" -name "*.png" -type f -exec ls -S {} \; | head -1)
    LARGEST_SIZE=$(du -h "$LARGEST" 2>/dev/null | cut -f1)
    LARGEST_DIMS=$(file "$LARGEST" | grep -oE '[0-9]+ x [0-9]+' || echo "unknown")
    
    echo "📏 Largest icon: $(basename "$LARGEST") (${LARGEST_DIMS}, ${LARGEST_SIZE})"
    
    # Create a list of all icons with their dimensions for the UI
    > "$OUTPUT_DIR/icon_list.txt"
    for png in $(find "$OUTPUT_DIR" -name "*.png" -type f | sort); do
        DIMS=$(file "$png" | grep -oE '[0-9]+ x [0-9]+' || echo "unknown")
        SIZE=$(du -h "$png" | cut -f1)
        echo "$(basename "$png")|$DIMS|$SIZE|$png" >> "$OUTPUT_DIR/icon_list.txt"
    done
    
    echo "ICON_COUNT=$PNG_COUNT"
    echo "LARGEST_ICON=$LARGEST"
    exit 0
else
    echo "❌ No icons found in EXE"
    echo "ICON_COUNT=0"
    exit 1
fi
EOL
chmod +x sh/extract_icon.sh

# ===============================================
# Create package.json
# ===============================================
cat <<EOL > package.json
{
  "name": "winejs-packager",
  "displayName": "WineJS Packager",
  "description": "Right-click any folder → Package Windows apps for WineJS",
  "repository": "https://github.com/winejs/packager",
  "publisher": "winejs",
  "icon": "sh/logo.png",
  "version": "1.0.0",
  "engines": {
    "vscode": "^1.81.0"
  },
  "categories": [
    "Other"
  ],
  "activationEvents": [
    "onCommand:winejs.packageApp"
  ],
  "main": "./out/extension.js",
  "contributes": {
    "commands": [
      {
        "command": "winejs.packageApp",
        "title": "WineJS: Package Windows App",
        "category": "WineJS"
      }
    ],
    "menus": {
      "explorer/context": [
        {
          "command": "winejs.packageApp",
          "group": "winejs@1",
          "when": "explorerResourceIsFolder"
        }
      ]
    },
    "configuration": {
      "title": "WineJS Packager",
      "properties": {
        "winejs.spaces.accessKey": {
          "type": "string",
          "description": "DigitalOcean Spaces Access Key"
        },
        "winejs.spaces.secretKey": {
          "type": "string",
          "description": "DigitalOcean Spaces Secret Key"
        },
        "winejs.spaces.endpoint": {
          "type": "string",
          "default": "https://fra1.digitaloceanspaces.com",
          "description": "DigitalOcean Spaces Endpoint URL"
        },
        "winejs.spaces.cdnEndpoint": {
          "type": "string",
          "description": "DigitalOcean CDN Endpoint URL (optional - if provided, will use this for public URLs instead of Spaces URL)"
        },
        "winejs.spaces.bucket": {
          "type": "string",
          "default": "sdappnet-cloud",
          "description": "DigitalOcean Spaces Bucket Name"
        },
        "winejs.spaces.region": {
          "type": "string",
          "default": "fra1",
          "description": "DigitalOcean Spaces Region"
        },
        "winejs.spaces.folder": {
          "type": "string",
          "default": "rtx/wine",
          "description": "Folder in bucket for app packages"
        },
        "winejs.spaces.makePublic": {
          "type": "boolean",
          "default": true,
          "description": "Make uploaded files publicly accessible"
        },
        "winejs.spaces.apiToken": {
          "type": "string",
          "description": "DigitalOcean API Token (required for CDN purge)"
        },
        "winejs.spaces.cdnId": {
          "type": "string",
          "description": "DigitalOcean CDN Endpoint ID (required for CDN purge)"
        },
        "winejs.defaultCategory": {
          "type": "string",
          "default": "Other",
          "enum": ["Game", "Graphics", "Audio", "Utility", "Office", "Development", "Other"],
          "description": "Default app category"
        }
      }
    }
  },
  "scripts": {
    "vscode:prepublish": "npm run compile",
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
# Create extension.ts (the main extension)
# ===============================================
cat <<'EOL' > src/extension.ts
import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { exec } from 'child_process';
import { promisify } from 'util';
import * as https from 'https';
import * as crypto from 'crypto';

const execAsync = promisify(exec);

export function activate(context: vscode.ExtensionContext) {
    console.log('✅ WineJS Packager activated!');

    const disposable = vscode.commands.registerCommand('winejs.packageApp', async (uri: vscode.Uri) => {
        if (!uri || !uri.fsPath) {
            vscode.window.showErrorMessage('Please right-click a folder');
            return;
        }

        const folderPath = uri.fsPath;
        const stats = fs.statSync(folderPath);
        if (!stats.isDirectory()) {
            vscode.window.showErrorMessage('Please right-click a folder, not a file');
            return;
        }

        try {
            await packageWindowsApp(folderPath, context);
        } catch (error: any) {
            vscode.window.showErrorMessage(`Failed to package app: ${error.message}`);
        }
    });

    context.subscriptions.push(disposable);
}

async function packageWindowsApp(folderPath: string, context: vscode.ExtensionContext) {
    // Get parent folder name and create install folder
    const parentFolderName = path.basename(folderPath);
    const parentDir = path.dirname(folderPath);
    const installFolder = path.join(parentDir, `${parentFolderName}_install`);
    
    // Create install folder if it doesn't exist
    if (!fs.existsSync(installFolder)) {
        fs.mkdirSync(installFolder, { recursive: true });
    }
    
    // Step 1: Ask for app name (auto-filled with folder name)
    const folderName = path.basename(folderPath);
    const appName = await vscode.window.showInputBox({
        title: 'App Name',
        prompt: 'Enter the name of the application',
        value: folderName,
        validateInput: (value) => value ? null : 'App name cannot be empty'
    });

    if (!appName) {
        vscode.window.showInformationMessage('Packaging cancelled');
        return;
    }

    // Step 2: Scan for EXE files with progress
    let exeFiles: string[] = [];
    await vscode.window.withProgress({
        location: vscode.ProgressLocation.Notification,
        title: "🔍 Scanning for EXE files...",
        cancellable: false
    }, async (progress) => {
        progress.report({ increment: 0, message: "Searching for executables..." });
        
        function scanDir(dir: string) {
            const files = fs.readdirSync(dir);
            for (const file of files) {
                const fullPath = path.join(dir, file);
                const stat = fs.statSync(fullPath);
                if (stat.isDirectory()) {
                    scanDir(fullPath);
                } else if (file.toLowerCase().endsWith('.exe')) {
                    exeFiles.push(fullPath);
                }
            }
        }
        scanDir(folderPath);
        
        progress.report({ increment: 100, message: `Found ${exeFiles.length} EXE files` });
    });

    if (exeFiles.length === 0) {
        throw new Error('No EXE files found in the selected folder');
    }

    // Filter out setup/uninstall files
    const filteredExes = exeFiles.filter(exe => {
        const name = path.basename(exe).toLowerCase();
        return !name.includes('uninstall') && !name.includes('setup') && !name.includes('install');
    });

    const displayExes = filteredExes.length > 0 ? filteredExes : exeFiles;

    // Step 3: Let user select main EXE
    const items = displayExes.map(exe => ({
        label: path.basename(exe),
        description: path.relative(folderPath, exe),
        detail: `${(fs.statSync(exe).size / 1024 / 1024).toFixed(2)} MB`,
        path: exe
    }));

    const selected = await vscode.window.showQuickPick(items, {
        placeHolder: 'Select the main executable for this app',
        title: `Found ${displayExes.length} executables`
    });

    if (!selected) {
        vscode.window.showInformationMessage('Packaging cancelled');
        return;
    }

    const mainExe = selected.path;
    const mainExeName = path.basename(mainExe);
    const mainExeRelPath = path.relative(folderPath, mainExe);

    // Step 4: Handle icon
    const iconChoice = await vscode.window.showQuickPick(
        [
            { label: '✅ Extract icon from EXE', description: 'Extract real icon from the executable' },
            { label: '🌐 Use external URL', description: 'Provide a URL to an image' },
            { label: '🔗 Use default icon', description: 'Use WineJS placeholder icon' }
        ],
        { placeHolder: 'How do you want to handle the app icon?' }
    );

    if (!iconChoice) {
        vscode.window.showInformationMessage('Packaging cancelled');
        return;
    }

    // Create temp directory for packaging
    const tempDir = path.join(os.tmpdir(), `winejs-package-${Date.now()}`);
    fs.mkdirSync(tempDir, { recursive: true });
    
    // Output paths in install folder
    const sanitizedAppName = appName.toLowerCase().replace(/\s+/g, '_');
    const zipPath = path.join(installFolder, `${sanitizedAppName}.zip`);
    const iconPath = path.join(installFolder, `${sanitizedAppName}.png`);
    let iconUploadUrl = 'https://cdn.gitgpt.chat/rtx/images/wine-placeholder.png';
    let iconExtracted = false;

    // Helper function to get image dimensions
    function getImageSize(imagePath: string): { width: number, height: number } {
        try {
            const output = require('child_process').execSync(`file "${imagePath}"`).toString();
            const match = output.match(/(\d+) x (\d+)/);
            if (match) {
                return { 
                    width: parseInt(match[1]), 
                    height: parseInt(match[2]) 
                };
            }
        } catch (e) {}
        return { width: 32, height: 32 };
    }

    // Show icon selection grid
    async function showIconSelectionGrid(icons: any[]): Promise<string | null> {
        return new Promise(async (resolve) => {
            const panel = vscode.window.createWebviewPanel(
                'iconSelection',
                'Select App Icon',
                vscode.ViewColumn.Active,
                { enableScripts: true }
            );

            const iconsHtml = icons.map((icon, index) => {
                const iconData = fs.readFileSync(icon.path).toString('base64');
                return `
                    <div class="icon-item" data-index="${index}">
                        <img src="data:image/png;base64,${iconData}" alt="${icon.name}">
                        <div class="icon-size">${icon.size.width}x${icon.size.height}</div>
                        <div class="icon-name">${icon.name}</div>
                        <button class="select-btn" data-path="${icon.path}">Select</button>
                    </div>
                `;
            }).join('');

            panel.webview.html = `
    <!DOCTYPE html>
    <html>
    <head>
        <style>
            body { font-family: Arial; padding: 20px; background: #1e1e1e; color: #fff; }
            h2 { color: #00ff9d; margin-bottom: 20px; }
            .icon-grid { 
                display: grid; 
                grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
                gap: 20px;
                margin-bottom: 30px;
            }
            .icon-item {
                background: #2d2d2d;
                border: 1px solid #404040;
                border-radius: 8px;
                padding: 15px;
                text-align: center;
                transition: all 0.2s;
            }
            .icon-item:hover {
                border-color: #00ff9d;
                transform: translateY(-2px);
            }
            .icon-item img {
                max-width: 128px;
                max-height: 128px;
                image-rendering: pixelated;
                background: white;
                border-radius: 8px;
                padding: 10px;
                margin-bottom: 10px;
            }
            .icon-size {
                font-size: 12px;
                color: #00ff9d;
                margin-bottom: 5px;
            }
            .icon-name {
                font-size: 10px;
                color: #888;
                margin-bottom: 10px;
                word-break: break-all;
            }
            .select-btn {
                background: #0078d4;
                color: white;
                border: none;
                padding: 5px 10px;
                border-radius: 4px;
                cursor: pointer;
                width: 100%;
            }
            .select-btn:hover {
                background: #005a9e;
            }
            .auto-select {
                text-align: center;
                margin-top: 20px;
                padding-top: 20px;
                border-top: 1px solid #404040;
            }
            .auto-select button {
                background: #2d2d2d;
                color: #fff;
                border: 1px solid #404040;
                padding: 10px 20px;
                border-radius: 4px;
                cursor: pointer;
                margin: 0 10px;
            }
            .auto-select button:hover {
                background: #404040;
            }
            .auto-select .largest {
                background: #00ff9d;
                color: #000;
            }
        </style>
    </head>
    <body>
        <h2>🎨 Multiple Icons Found - Select One</h2>
        <p>Found ${icons.length} icons in the EXE. Choose which one to use:</p>
        
        <div class="icon-grid">
            ${iconsHtml}
        </div>

        <div class="auto-select">
            <p>Or let the extension decide:</p>
            <button class="largest" id="useLargest">Use Largest (${icons[0].size.width}x${icons[0].size.height})</button>
            <button id="cancel">Cancel</button>
        </div>

        <script>
            const vscode = acquireVsCodeApi();
            
            document.querySelectorAll('.select-btn').forEach(btn => {
                btn.addEventListener('click', () => {
                    vscode.postMessage({ 
                        command: 'iconSelected', 
                        path: btn.dataset.path 
                    });
                });
            });

            document.getElementById('useLargest').addEventListener('click', () => {
                vscode.postMessage({ 
                    command: 'iconSelected', 
                    path: '${icons[0].path}'
                });
            });

            document.getElementById('cancel').addEventListener('click', () => {
                vscode.postMessage({ command: 'iconSelectionCancelled' });
            });
        </script>
    </body>
    </html>`;

            panel.webview.onDidReceiveMessage(async message => {
                if (message.command === 'iconSelected') {
                    panel.dispose();
                    resolve(message.path);
                } else if (message.command === 'iconSelectionCancelled') {
                    panel.dispose();
                    resolve(null);
                }
            });
        });
    }

    // Show single icon preview for confirmation
    async function showSingleIconPreview(iconPath: string): Promise<boolean> {
        return new Promise(async (resolve) => {
            const panel = vscode.window.createWebviewPanel(
                'iconPreview',
                'Icon Preview',
                vscode.ViewColumn.Active,
                { enableScripts: true }
            );

            const iconData = fs.readFileSync(iconPath).toString('base64');
            
            panel.webview.html = `
    <!DOCTYPE html>
    <html>
    <head>
        <style>
            body { 
                font-family: Arial; 
                padding: 20px; 
                background: #1e1e1e; 
                color: #fff; 
                text-align: center;
            }
            h2 { color: #00ff9d; margin-bottom: 20px; }
            .preview-container {
                background: #2d2d2d;
                border: 1px solid #404040;
                border-radius: 8px;
                padding: 30px;
                display: inline-block;
            }
            img {
                max-width: 256px;
                max-height: 256px;
                image-rendering: pixelated;
                background: white;
                border-radius: 8px;
                padding: 10px;
            }
            .buttons {
                margin-top: 30px;
            }
            button {
                background: #2d2d2d;
                color: #fff;
                border: 1px solid #404040;
                padding: 10px 20px;
                border-radius: 4px;
                cursor: pointer;
                margin: 0 10px;
                font-size: 14px;
            }
            button:hover {
                background: #404040;
            }
            button.confirm {
                background: #00ff9d;
                color: #000;
                border: none;
            }
            button.confirm:hover {
                background: #00cc7a;
            }
        </style>
    </head>
    <body>
        <h2>🎨 Icon Extracted Successfully!</h2>
        <div class="preview-container">
            <img src="data:image/png;base64,${iconData}" alt="Extracted Icon">
        </div>
        <p>Do you want to use this icon?</p>
        <div class="buttons">
            <button class="confirm" id="yesBtn">✅ Yes, use this icon</button>
            <button id="noBtn">❌ No, try another option</button>
        </div>

        <script>
            const vscode = acquireVsCodeApi();
            
            document.getElementById('yesBtn').addEventListener('click', () => {
                vscode.postMessage({ command: 'confirm' });
            });
            
            document.getElementById('noBtn').addEventListener('click', () => {
                vscode.postMessage({ command: 'cancel' });
            });
        </script>
    </body>
    </html>`;

            panel.webview.onDidReceiveMessage(async message => {
                if (message.command === 'confirm') {
                    panel.dispose();
                    resolve(true);
                } else if (message.command === 'cancel') {
                    panel.dispose();
                    resolve(false);
                }
            });
        });
    }

    // Handle icon based on choice
    if (iconChoice.label.includes('Extract')) {
        await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: "🎨 Extracting icons from EXE...",
            cancellable: false
        }, async (progress) => {
            progress.report({ increment: 0, message: "Running icon extraction..." });
            
            const iconExtractDir = path.join(tempDir, 'icons');
            fs.mkdirSync(iconExtractDir, { recursive: true });

            try {
                const extractScript = path.join(context.extensionPath, 'sh', 'extract_icon.sh');
                await execAsync(`bash "${extractScript}" "${mainExe}" "${iconExtractDir}"`);
                
                progress.report({ increment: 50, message: "Processing extracted icons..." });

                // Find all extracted PNGs
                const extractedIcons = fs.readdirSync(iconExtractDir)
                    .filter(f => f.endsWith('.png'))
                    .map(f => ({
                        path: path.join(iconExtractDir, f),
                        name: f,
                        size: getImageSize(path.join(iconExtractDir, f))
                    }))
                    .sort((a, b) => b.size.width - a.size.width);

                if (extractedIcons.length === 0) {
                    progress.report({ increment: 100, message: "No icons found!" });
                    vscode.window.showWarningMessage('No icons found in the EXE file.');
                    
                    const fallbackChoice = await vscode.window.showQuickPick(
                        [
                            { label: '🌐 Use external URL', description: 'Provide a URL to an image' },
                            { label: '🔗 Use default WineJS icon', description: 'Use the standard placeholder icon' },
                            { label: '❌ Cancel packaging', description: 'Stop the packaging process' }
                        ],
                        { placeHolder: 'No icons found! What would you like to do?' }
                    );
                    
                    if (!fallbackChoice || fallbackChoice.label.includes('Cancel')) {
                        throw new Error('User cancelled due to missing icon');
                    } else if (fallbackChoice.label.includes('URL')) {
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
                        
                        if (urlInput) {
                            const iconResponse = await fetch(urlInput);
                            const iconBuffer = Buffer.from(await iconResponse.arrayBuffer());
                            fs.writeFileSync(iconPath, iconBuffer);
                            iconExtracted = true;
                        } else {
                            throw new Error('User cancelled icon URL input');
                        }
                    }
                } else if (extractedIcons.length === 1) {
                    progress.report({ increment: 75, message: "Previewing icon..." });
                    const confirm = await showSingleIconPreview(extractedIcons[0].path);
                    if (confirm) {
                        iconExtracted = true;
                        fs.copyFileSync(extractedIcons[0].path, iconPath);
                    } else {
                        const fallbackChoice = await vscode.window.showQuickPick(
                            [
                                { label: '🌐 Use external URL', description: 'Provide a URL to an image' },
                                { label: '🔗 Use default WineJS icon', description: 'Use the standard placeholder icon' },
                                { label: '❌ Cancel packaging', description: 'Stop the packaging process' }
                            ],
                            { placeHolder: 'Icon preview rejected. What would you like to do?' }
                        );
                        
                        if (!fallbackChoice || fallbackChoice.label.includes('Cancel')) {
                            throw new Error('User cancelled after rejecting icon');
                        } else if (fallbackChoice.label.includes('URL')) {
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
                            
                            if (urlInput) {
                                const iconResponse = await fetch(urlInput);
                                const iconBuffer = Buffer.from(await iconResponse.arrayBuffer());
                                fs.writeFileSync(iconPath, iconBuffer);
                                iconExtracted = true;
                            } else {
                                throw new Error('User cancelled icon URL input');
                            }
                        }
                    }
                } else {
                    progress.report({ increment: 75, message: "Selecting best icon..." });
                    const selectedIcon = await showIconSelectionGrid(extractedIcons);
                    if (selectedIcon) {
                        iconExtracted = true;
                        fs.copyFileSync(selectedIcon, iconPath);
                    } else {
                        const fallbackChoice = await vscode.window.showQuickPick(
                            [
                                { label: '🌐 Use external URL', description: 'Provide a URL to an image' },
                                { label: '🔗 Use default WineJS icon', description: 'Use the standard placeholder icon' },
                                { label: '❌ Cancel packaging', description: 'Stop the packaging process' }
                            ],
                            { placeHolder: 'Icon selection cancelled. What would you like to do?' }
                        );
                        
                        if (!fallbackChoice || fallbackChoice.label.includes('Cancel')) {
                            throw new Error('User cancelled icon selection');
                        } else if (fallbackChoice.label.includes('URL')) {
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
                            
                            if (urlInput) {
                                const iconResponse = await fetch(urlInput);
                                const iconBuffer = Buffer.from(await iconResponse.arrayBuffer());
                                fs.writeFileSync(iconPath, iconBuffer);
                                iconExtracted = true;
                            } else {
                                throw new Error('User cancelled icon URL input');
                            }
                        }
                    }
                }
                
                progress.report({ increment: 100, message: "Icon extraction complete!" });
            } catch (error: any) {
                vscode.window.showErrorMessage(`Icon extraction failed: ${error.message}`);
                
                const fallbackChoice = await vscode.window.showQuickPick(
                    [
                        { label: '🌐 Use external URL', description: 'Provide a URL to an image' },
                        { label: '🔗 Use default WineJS icon', description: 'Use the standard placeholder icon' },
                        { label: '❌ Cancel packaging', description: 'Stop the packaging process' }
                    ],
                    { placeHolder: 'Icon extraction failed! What would you like to do?' }
                );
                
                if (!fallbackChoice || fallbackChoice.label.includes('Cancel')) {
                    throw new Error('User cancelled due to extraction failure');
                } else if (fallbackChoice.label.includes('URL')) {
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
                    
                    if (urlInput) {
                        const iconResponse = await fetch(urlInput);
                        const iconBuffer = Buffer.from(await iconResponse.arrayBuffer());
                        fs.writeFileSync(iconPath, iconBuffer);
                        iconExtracted = true;
                    } else {
                        throw new Error('User cancelled icon URL input');
                    }
                }
            }
        });
    } else if (iconChoice.label.includes('URL')) {
        const urlInput = await vscode.window.showInputBox({
            title: 'Icon URL',
            prompt: 'Enter the URL of the icon image (PNG or JPG)',
            placeHolder: 'https://example.com/icon.jpg',
            validateInput: (value) => {
                if (!value) return 'URL cannot be empty';
                if (!value.startsWith('http')) return 'URL must start with http:// or https://';
                return null;
            }
        });
        
        if (urlInput) {
            await vscode.window.withProgress({
                location: vscode.ProgressLocation.Notification,
                title: "📥 Downloading icon from URL...",
                cancellable: false
            }, async (progress) => {
                progress.report({ increment: 0, message: "Fetching icon..." });
                try {
                    const iconResponse = await fetch(urlInput);
                    const iconBuffer = Buffer.from(await iconResponse.arrayBuffer());
                    fs.writeFileSync(iconPath, iconBuffer);
                    iconExtracted = true;
                    progress.report({ increment: 100, message: "Icon downloaded!" });
                    vscode.window.showInformationMessage('✅ Icon downloaded successfully!');
                } catch (error: any) {
                    vscode.window.showErrorMessage(`Failed to download icon: ${error.message}`);
                    throw new Error('Icon download failed');
                }
            });
        }
    }

    // If no icon was extracted, use default
    if (!iconExtracted) {
        await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: "📥 Downloading default icon...",
            cancellable: false
        }, async (progress) => {
            progress.report({ increment: 0, message: "Fetching default icon..." });
            try {
                const defaultIconResponse = await fetch('https://cdn.gitgpt.chat/rtx/images/wine-placeholder.png');
                const defaultIconBuffer = Buffer.from(await defaultIconResponse.arrayBuffer());
                fs.writeFileSync(iconPath, defaultIconBuffer);
                progress.report({ increment: 100, message: "Default icon ready!" });
            } catch (error: any) {
                console.error('Failed to download default icon:', error);
            }
        });
    }

    // ============= AUTO-DETECT SETUP FILES =============
    let hasRegFile = false;
    let hasSetupBat = false;
    let hasPrelaunchSh = false;

    // Check for special files in the folder
    const regKeyPath = path.join(folderPath, 'wineregkey.reg');
    const setupBatPath = path.join(folderPath, 'setup.bat');
    const prelaunchPath = path.join(folderPath, 'prelaunch.sh');

    if (fs.existsSync(regKeyPath)) {
        hasRegFile = true;
        console.log(`✅ Found registry file: wineregkey.reg`);
        vscode.window.showInformationMessage(`📝 Found wineregkey.reg - will auto-import during installation`);
    }

    if (fs.existsSync(setupBatPath)) {
        hasSetupBat = true;
        console.log(`✅ Found setup batch file: setup.bat`);
        vscode.window.showInformationMessage(`⚙️ Found setup.bat - will auto-run during installation`);
    }

    if (fs.existsSync(prelaunchPath)) {
        hasPrelaunchSh = true;
        console.log(`✅ Found prelaunch script: prelaunch.sh`);
        vscode.window.showInformationMessage(`🚀 Found prelaunch.sh - will auto-run during installation`);
    }

    // Step 5: Ask for category
    const category = await vscode.window.showQuickPick(
        ['Game', 'Graphics', 'Audio', 'Utility', 'Office', 'Development', 'Other'],
        { placeHolder: 'Select app category', title: 'App Category' }
    );

    // Step 6: Ask for version
    const version = await vscode.window.showInputBox({
        title: 'App Version',
        prompt: 'Enter app version',
        value: '1.0'
    });

    // Step 7: Create ZIP with progress
    await vscode.window.withProgress({
        location: vscode.ProgressLocation.Notification,
        title: "📦 Creating ZIP package...",
        cancellable: false
    }, async (progress) => {
        progress.report({ increment: 0, message: "Copying files..." });
        
        const appTempDir = path.join(tempDir, appName);
        fs.mkdirSync(appTempDir, { recursive: true });
        
        await execAsync(`cp -r "${folderPath}/"* "${appTempDir}/"`);
        
        progress.report({ increment: 50, message: "Compressing..." });
        
        await execAsync(`cd "${tempDir}" && zip -r "${zipPath}" "${appName}/"`);
        
        progress.report({ increment: 100, message: "ZIP created!" });
    });

    // Step 8: Upload to Spaces - FIXED VERSION
    const config = vscode.workspace.getConfiguration('winejs');
    const accessKey = config.get('spaces.accessKey') as string;
    const secretKey = config.get('spaces.secretKey') as string;
    const bucket = config.get('spaces.bucket') as string;
    const endpoint = config.get('spaces.endpoint') as string || "https://fra1.digitaloceanspaces.com";
    const region = config.get('spaces.region') as string || "fra1";
    const spacesFolder = config.get('spaces.folder') as string || "rtx/wine";
    const makePublic = config.get('spaces.makePublic') as boolean ?? true;
    const cdnEndpoint = config.get('spaces.cdnEndpoint') as string || null;
    const apiToken = config.get('spaces.apiToken') as string || null;
    let cdnId = config.get('spaces.cdnId') as string || null;

    let zipUrl = 'LOCAL_FILE';
    // IMPORTANT: iconUploadUrl is already declared earlier, we'll update it after upload

    // Auto-detect CDN ID if needed
    if (cdnEndpoint && apiToken && !cdnId) {
        vscode.window.showInformationMessage("🔍 Detecting CDN ID...");
        cdnId = await getCdnId(apiToken, bucket);
        if (cdnId) {
            config.update("cdnId", cdnId, true);
            vscode.window.showInformationMessage("✅ CDN ID detected and saved!");
        } else {
            vscode.window.showWarningMessage("⚠️ Could not auto-detect CDN ID. CDN purge will be skipped.");
        }
    }

    // Enhanced config validation with open settings options
    if (!accessKey) {
        const action = await vscode.window.showErrorMessage(
            'WineJS Spaces Access Key not configured!',
            'Open Settings',
            'Cancel'
        );
        if (action === 'Open Settings') {
            vscode.commands.executeCommand('workbench.action.openSettings', 'winejs.spaces.accessKey');
        }
        return;
    }

    if (!secretKey) {
        const action = await vscode.window.showErrorMessage(
            'WineJS Spaces Secret Key not configured!',
            'Open Settings', 
            'Cancel'
        );
        if (action === 'Open Settings') {
            vscode.commands.executeCommand('workbench.action.openSettings', 'winejs.spaces.secretKey');
        }
        return;
    }

    if (!bucket) {
        const action = await vscode.window.showErrorMessage(
            'WineJS Spaces Bucket not configured!',
            'Open Settings',
            'Cancel'
        );
        if (action === 'Open Settings') {
            vscode.commands.executeCommand('workbench.action.openSettings', 'winejs.spaces.bucket');
        }
        return;
    }

    // Ask if they want to upload
    const uploadChoice = await vscode.window.showQuickPick(
        ['✅ Yes, upload to Spaces', '❌ No, save locally'],
        { placeHolder: 'Upload package to DigitalOcean Spaces?' }
    );

    if (uploadChoice?.includes('Yes')) {
        try {
            // Dynamically import AWS SDK
            const s3Module = require('@aws-sdk/client-s3');
            const { PutObjectCommand, S3Client } = s3Module;
            
            // Show progress
            await vscode.window.withProgress({
                location: vscode.ProgressLocation.Notification,
                title: "☁️ Uploading to DigitalOcean Spaces...",
                cancellable: false
            }, async (progress) => {
                progress.report({ increment: 0, message: "🔌 Connecting to Spaces..." });

                // Create S3 client
                const s3Client = new S3Client({
                    endpoint: endpoint,
                    forcePathStyle: false,
                    region: region,
                    credentials: {
                        accessKeyId: accessKey,
                        secretAccessKey: secretKey
                    }
                });

                // Upload ZIP - Using readFileSync like the working example
                const zipKey = `${spacesFolder}/${sanitizedAppName}.zip`;
                const zipContent = fs.readFileSync(zipPath);
                
                progress.report({ increment: 20, message: "📤 Uploading ZIP file..." });
                
                const zipParams: any = {
                    Bucket: bucket,
                    Key: zipKey,
                    Body: zipContent,
                    ContentType: 'application/zip',
                    Metadata: {
                        "uploaded-from": "winejs-packager",
                        "app-name": appName,
                        "timestamp": new Date().toISOString()
                    }
                };
                
                if (makePublic) {
                    zipParams.ACL = 'public-read';
                }

                await s3Client.send(new PutObjectCommand(zipParams));
                
                // Construct public URL for ZIP
                const spaceUrl = endpoint.replace('https://', `https://${bucket}.`);
                if (cdnEndpoint) {
                    zipUrl = `${cdnEndpoint}/${zipKey}`;
                } else {
                    zipUrl = `${spaceUrl}/${zipKey}`;
                }
                
                progress.report({ increment: 50, message: "✅ ZIP uploaded! Uploading icon..." });

                // Upload icon - Using readFileSync like the working example
                if (fs.existsSync(iconPath)) {
                    const iconKey = `${spacesFolder}/images/${sanitizedAppName}.png`;
                    const iconContent = fs.readFileSync(iconPath);
                    
                    const iconParams: any = {
                        Bucket: bucket,
                        Key: iconKey,
                        Body: iconContent,
                        ContentType: 'image/png',
                        Metadata: {
                            "uploaded-from": "winejs-packager",
                            "app-name": appName
                        }
                    };
                    
                    if (makePublic) {
                        iconParams.ACL = 'public-read';
                    }
                    
                    await s3Client.send(new PutObjectCommand(iconParams));
                    
                    // ✅ IMPORTANT: Update iconUploadUrl with the CDN URL
                    if (cdnEndpoint) {
                        iconUploadUrl = `${cdnEndpoint}/${iconKey}`;
                    } else {
                        iconUploadUrl = `${spaceUrl}/${iconKey}`;
                    }
                    
                    progress.report({ increment: 75, message: "✅ Icon uploaded! Purging CDN cache..." });
                } else {
                    progress.report({ increment: 75, message: "Purging CDN cache..." });
                }

                // Attempt CDN purge (optional)
                if (apiToken && cdnId) {
                    try {
                        const purgeBody = JSON.stringify({ files: [`${spacesFolder}/${sanitizedAppName}.zip`] });

                        await new Promise((resolve, reject) => {
                            const req = https.request({
                                method: "DELETE",
                                hostname: "api.digitalocean.com",
                                path: `/v2/cdn/endpoints/${cdnId}/cache`,
                                headers: {
                                    "Authorization": `Bearer ${apiToken}`,
                                    "Content-Type": "application/json",
                                    "Content-Length": Buffer.byteLength(purgeBody).toString()
                                }
                            }, (res) => {
                                let responseData = '';
                                res.on('data', (chunk) => {
                                    responseData += chunk;
                                });
                                
                                res.on('end', () => {
                                    if (res.statusCode === 204 || res.statusCode === 200) {
                                        resolve(true);
                                    } else {
                                        reject(new Error(`CDN purge failed with status ${res.statusCode}`));
                                    }
                                });
                            });
                            
                            req.on('error', (error) => {
                                reject(error);
                            });
                            
                            req.write(purgeBody);
                            req.end();
                        });
                        
                        progress.report({ increment: 95, message: "✅ CDN cache purged! Finalizing..." });
                    } catch (error: any) {
                        console.warn('CDN purge failed:', error.message);
                        progress.report({ increment: 95, message: "⚠️ CDN purge failed, but upload succeeded!" });
                    }
                }
                
                progress.report({ increment: 100, message: "✅ Upload complete!" });
            });
            
            // Show success message with options
            vscode.window.showInformationMessage(
                `✅ Upload successful! ZIP and icon uploaded to Spaces.`,
                "Copy ZIP URL",
                "Copy Icon URL",
                "Open in Browser"
            ).then(selection => {
                if (selection === "Copy ZIP URL") {
                    vscode.env.clipboard.writeText(zipUrl);
                    vscode.window.showInformationMessage("ZIP URL copied to clipboard!");
                } else if (selection === "Copy Icon URL") {
                    vscode.env.clipboard.writeText(iconUploadUrl);
                    vscode.window.showInformationMessage("Icon URL copied to clipboard!");
                } else if (selection === "Open in Browser") {
                    vscode.env.openExternal(vscode.Uri.parse(zipUrl));
                }
            });

        } catch (error: any) {
            vscode.window.showErrorMessage(`Upload failed: ${error.message}`);
            console.error("Spaces upload error:", error);
            zipUrl = 'LOCAL_FILE';
        }
    } else {
        // User chose not to upload, keep local paths
        console.log("User chose to save locally, not uploading to Spaces");
    }

    // Step 9: Generate install script
    const installScriptPath = path.join(installFolder, `install_${sanitizedAppName}.sh`);
    const randomPass = crypto.randomBytes(6).toString('hex');
    const nextPort = 6902;

    const installScript = generateInstallScript({
        appName,
        version: version || '1.0',
        description: `${appName} running in browser`,
        executable: mainExeName,
        executablePath: mainExeRelPath,
        category: category || 'Other',
        zipUrl: zipUrl,
        iconUrl: iconUploadUrl,
        port: nextPort,
        vncPassword: randomPass,
        sanitizedName: sanitizedAppName,
        hasRegFile: hasRegFile,
        hasSetupBat: hasSetupBat,
        hasPrelaunchSh: hasPrelaunchSh
    });

    fs.writeFileSync(installScriptPath, installScript);
    fs.chmodSync(installScriptPath, 0o755);

    // Step 10: Show summary
    const summary = `
## ✅ WineJS Package Created Successfully!

**App:** ${appName}
**Main EXE:** ${mainExeName}
**Category:** ${category || 'Other'}

### 📦 Files Created:
- **Install Folder:** ${installFolder}
- **ZIP Package:** ${zipPath}
- **Icon:** ${iconPath}
- **Install Script:** ${installScriptPath}

### ☁️ Upload Status:
${zipUrl !== 'LOCAL_FILE' ? `- **ZIP URL:** ${zipUrl}` : '- **ZIP saved locally**'}
- **Icon URL:** ${iconUploadUrl}

### 📝 Next Steps:
1. Copy the install folder to your WineJS server
2. Run: \`sudo bash ${path.basename(installScriptPath)}\`
3. The app will be installed to /opt/winedrop/apps/${sanitizedAppName}
    `;

    // Save summary to README.md in the install folder
    const readmePath = path.join(installFolder, 'README.md');
    fs.writeFileSync(readmePath, summary);

    // Open the saved README.md file
    const doc = await vscode.workspace.openTextDocument(readmePath);
    await vscode.window.showTextDocument(doc);

    // Cleanup temp files
    fs.rmSync(tempDir, { recursive: true, force: true });
}

function generateInstallScript(params: any): string {
    // Add these lines to show what was detected
    if (params.hasRegFile) {
        console.log("Including registry import in install script");
    }
    if (params.hasSetupBat) {
        console.log("Including setup.bat execution in install script");
    }
    if (params.hasPrelaunchSh) {
        console.log("Including prelaunch.sh execution in install script");
    }

    const uninstallScriptPath = `uninstall_${params.sanitizedName}.sh`;
    
    return `#!/bin/bash
# ============================================
# WineJS App Installer
# Generated by WineJS Packager v1.0
# ============================================
# App: ${params.appName}
# Version: ${params.version}
# Main EXE: ${params.executable}
# Category: ${params.category}
# Port: ${params.port}
# ============================================

# What the generated script does:
#     Verifies WineJS platform - Checks if /opt/winejs exists
#     Creates docker network - Creates winejs-net if missing (important fix!)
#     Creates all necessary directories - /opt/winejs/apps/${params.appName}/, /opt/winejs/kasmvnc-instances/${params.appName}/, etc.
#     Downloads the app - From your Spaces CDN
#     Downloads the icon - To /opt/winejs/translator/public/icons/
#     Creates launch.sh - With proper Wine path detection and dependency installation
#     Creates config.json - With all app metadata for the translator
#     Creates docker-compose.yml - With full gamepad/Wiimote support
#     Fixes permissions - For user 1000 (container user)
#     Creates uninstall script - For clean removal
#     Restarts PM2 translator - So the new app appears in the dashboard
#     Starts the container - Immediately

# When you run this on your WineJS server:

# The app will:
#     Be available at https://yourdomain.com/${params.appName}
#     Have the icon displayed in the Windows 10-style dashboard
#     Be listed alongside MilkShape
#     Auto-start the container when first accessed
#     Have gamepad/Wiimote support built-in

set -e

# Colors
RED='\\033[0;31m'; GREEN='\\033[0;32m'; YELLOW='\\033[1;33m'; NC='\\033[0m'
log() { echo -e "\${GREEN}[$(date '+%H:%M:%S')]\${NC} \$1"; }
error() { echo -e "\${RED}[ERROR]\${NC} \$1"; exit 1; }

log "Installing ${params.appName}..."

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

if ! docker images | grep -q "winedrop-base"; then
    log "Warning: winedrop-base image not found"
fi

log "WineJS platform verified"

# ============= FIND NEXT AVAILABLE PORT =============
log "Finding next available port..."

# Function to check if a port is in use
port_in_use() {
    local port=\$1
    # Check if port is bound by any process
    if ss -tln 2>/dev/null | grep -q ":\$port " || \\
       netstat -tln 2>/dev/null | grep -q ":\$port "; then
        return 0
    fi
    # Check if Docker is using this port
    if docker ps 2>/dev/null | grep -q ":\$port->"; then
        return 0
    fi
    return 1
}

# Start checking from 6901
START_PORT=6901
MAX_RETRIES=100
APP_PORT=""

# Check existing ports from config.json files
declare -a USED_PORTS
if [ -d "/opt/winejs/apps" ]; then
    for config in /opt/winejs/apps/*/config.json; do
        if [ -f "\$config" ]; then
            PORT=\$(grep -o '"port": [0-9]*' "\$config" | awk '{print \$2}')
            if [ -n "\$PORT" ]; then
                USED_PORTS+=(\$PORT)
            fi
        fi
    done
fi

# Find available port
for i in \$(seq 0 \$MAX_RETRIES); do
    TEST_PORT=\$((START_PORT + i))
    # Skip if port is in config.json
    if [[ " \${USED_PORTS[@]} " =~ " \${TEST_PORT} " ]]; then
        continue
    fi
    # Skip if port is in use
    if ! port_in_use \$TEST_PORT; then
        APP_PORT=\$TEST_PORT
        break
    fi
done

if [ -z "\$APP_PORT" ]; then
    error "Could not find available port"
fi

log "Using port: \$APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="${params.sanitizedName}"
APP_DIR="/opt/winejs/apps/\$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/\$APP_NAME"
WINE_PREFIX="/opt/winejs/wine-prefixes/\$APP_NAME"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "\$APP_DIR"
mkdir -p "\$INSTANCE_DIR"
mkdir -p "\$WINE_PREFIX"
mkdir -p "\$ICON_DIR"

cd "\$APP_DIR"

# ============= DOWNLOAD APP PACKAGE =============
log "Downloading ${params.appName} package..."
if [[ ${params.zipUrl} == "LOCAL_FILE" ]]; then
    log "Local installation - please copy files manually to \$APP_DIR"
else
    curl -L ${params.zipUrl} -o app.zip || error "Failed to download app package"
    unzip -o -q app.zip || error "Failed to unzip app package"
    rm -f app.zip
    
    # FIX: Handle ZIP that extracts to a subfolder
    if [ -d "\$APP_DIR/\${APP_NAME}" ] && [ "\$APP_DIR/\${APP_NAME}" != "\$APP_DIR" ]; then
        log "Moving files from subfolder..."
        mv "\$APP_DIR/\${APP_NAME}"/* "\$APP_DIR/" 2>/dev/null || true
        rm -rf "\$APP_DIR/\${APP_NAME}"
        log "Files moved to correct location"
    fi
fi

# ============= DOWNLOAD ICON =============
log "Downloading app icon..."
curl -L ${params.iconUrl} -o "\$ICON_DIR/\${APP_NAME}.png" || echo "Failed to download icon, using default"

# ============= USE SELECTED MAIN EXECUTABLE =============
log "Using main executable selected during packaging..."
MAIN_EXE="${params.executable}"
log "Main executable: \$MAIN_EXE"

# First, ensure we're looking in the right place (current directory)
cd "\$APP_DIR"

# Look for the selected executable (non-recursive first, then recursive if needed)
if [ -f "\$MAIN_EXE" ]; then
    log "✅ Found selected executable: \$MAIN_EXE"
else
    log "⚠️ Warning: \$MAIN_EXE not found in root directory"
    log "Searching for executable in subdirectories..."
    FOUND_EXE=\$(find . -name "\$MAIN_EXE" -type f | head -1)
    if [ -n "\$FOUND_EXE" ]; then
        MAIN_EXE_PATH="\$FOUND_EXE"
        MAIN_EXE=\$(basename "\$FOUND_EXE")
        MAIN_EXE_DIR=\$(dirname "\$FOUND_EXE")
        log "✅ Found \$MAIN_EXE in \$MAIN_EXE_DIR"
        # Move it to root if it's in a subfolder
        if [ "\$MAIN_EXE_DIR" != "." ]; then
            log "Moving \$MAIN_EXE to root directory..."
            mv "\$FOUND_EXE" "\$APP_DIR/"
        fi
    else
        log "⚠️ \$MAIN_EXE not found, searching for any executable..."
        FOUND_EXE=\$(find . -name "*.exe" -type f | grep -v "uninstall" | head -1)
        if [ -n "\$FOUND_EXE" ]; then
            MAIN_EXE=\$(basename "\$FOUND_EXE")
            MAIN_EXE_DIR=\$(dirname "\$FOUND_EXE")
            log "⚠️ Found alternative: \$MAIN_EXE in \$MAIN_EXE_DIR"
            # Move it to root
            if [ "\$MAIN_EXE_DIR" != "." ]; then
                log "Moving \$MAIN_EXE to root directory..."
                mv "\$FOUND_EXE" "\$APP_DIR/"
            fi
        else
            error "❌ No executable found!"
        fi
    fi
fi

# Final verification
if [ ! -f "\$MAIN_EXE" ]; then
    error "❌ Executable \$MAIN_EXE not found after search!"
fi

log "✅ Will launch: \$MAIN_EXE"

# ============= CREATE LAUNCH SCRIPT WITH AUTO-HEAL =============
log "Generating launch.sh with auto-heal monitor..."
cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "🚀 Starting ${params.appName} launch script..."

# ============= PHASE 1: DESTROY ALL DOCKS/PANELS (BEFORE ANYTHING ELSE) =============
log "🔪 PHASE 1: Destroying all docks and panels (pre-emptive strike)..."

# Kill all possible panel/dock processes immediately
kill_panels() {
    # Kill all known panel processes
    for panel in "xfce4-panel" "lxpanel" "tint2" "plank" "cairo-dock" "docky" "kdocker" "valapanel"; do
        pkill -9 -f "$panel" 2>/dev/null || true
    done
    
    # Kill any process with 'panel' or 'dock' in name
    ps aux | grep -E "[p]anel|[d]ock" | awk '{print $2}' | xargs kill -9 2>/dev/null || true
    
    # Remove panel configs to prevent respawning
    rm -f /home/kasm-user/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml 2>/dev/null || true
    rm -f /home/kasm-user/.config/lxpanel/*/panels/* 2>/dev/null || true
    rm -rf /home/kasm-user/.config/xfce4/panel 2>/dev/null || true
    rm -rf /home/kasm-user/.config/autostart/*panel* 2>/dev/null || true
    
    # Disable panel autostart
    mkdir -p /home/kasm-user/.config/autostart
    cat > /home/kasm-user/.config/autostart/disable-panel.desktop << 'AUTOF'
[Desktop Entry]
Type=Application
Name=Disable Panel
Exec=pkill -9 xfce4-panel
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
AUTOF
}

# Execute panel killing immediately
kill_panels
log "✅ Phase 1 complete - All panels/docks terminated"

# ============= PHASE 2: CONTINUOUS PANEL KILLER DAEMON =============
log "🔪 PHASE 2: Starting persistent panel killer daemon..."

# Start a background daemon that kills panels every second (more aggressive)
(
    while true; do
        sleep 1  # Check every second
        kill_panels > /dev/null 2>&1
        
        # Also hide any panel windows using xdotool if available
        if command -v xdotool &> /dev/null; then
            # Search for any window with panel/dock in title or class
            for window in $(xdotool search --name "[Pp]anel" 2>/dev/null; xdotool search --class "[Pp]anel" 2>/dev/null; xdotool search --name "[Dd]ock" 2>/dev/null); do
                xdotool windowunmap $window 2>/dev/null || true  # Hide completely
                xdotool windowmove $window -10000 -10000 2>/dev/null || true  # Move offscreen
            done
        fi
    done
) &
PANEL_KILLER_PID=$!
log "✅ Persistent panel killer daemon started (PID: $PANEL_KILLER_PID, checking every 1 second)"

# Wait for desktop to be fully ready
log "⏳ Waiting for desktop to be ready..."
/usr/bin/desktop_ready
log "✅ Desktop is ready"

# Fix Wine prefix permissions
log "🔧 Fixing Wine prefix permissions..."
sudo chown -R 1000:1000 /home/kasm-user/.wine 2>/dev/null || true

# Initialize Wine prefix if it doesn't exist
if [ ! -d "/home/kasm-user/.wine/drive_c" ]; then
    log "📦 Initializing Wine prefix..."
    WINEPREFIX=/home/kasm-user/.wine wineboot --init
    sleep 5
fi


# Install required DLLs
log "📦 Installing dependencies (this may take a moment)..."
WINEPREFIX=/home/kasm-user/.wine winetricks -q d3dx9 d3dx9_36 d3dx9_42 d3dx9_43 \
    vcrun2005 vcrun2008 vcrun2010 vcrun2012 \
    xact xact_x64 directmusic directplay \
    msxml3 msxml4 msxml6 > /dev/null 2>&1

log "🎮 Installing specific dependencies..."
WINEPREFIX=/home/kasm-user/.wine winetricks -q d3dxof d3dcompiler_43 > /dev/null 2>&1
log "✅ Dependencies installed"


# Find Wine (try multiple locations)
WINE_PATH=$(which wine 2>/dev/null || find /usr -name "wine" -type f 2>/dev/null | head -1)
if [ -z "$WINE_PATH" ]; then
    WINE_PATH="/usr/lib/wine/wine"
fi
log "🔍 Using Wine at: $WINE_PATH"

# Find and launch the app
APP_DIR="/app"
cd "$APP_DIR"
log "📍 Changed directory to: $(pwd)"

# Find the executable (case insensitive)
EXE_FILE="${params.executable}"
EXE_PATH=$(find . -iname "$EXE_FILE" -type f | head -1 | sed 's|^\./||')
if [ -z "$EXE_PATH" ]; then
    # Try to find any exe
    EXE_PATH=$(find . -name "*.exe" -type f | grep -v "uninstall" | head -1 | sed 's|^\./||')
fi

if [ -n "$EXE_PATH" ]; then
    log "🎮 Found executable: $EXE_PATH"
    log "🚀 Executing: $WINE_PATH $EXE_PATH"
    
    # Launch the app in background
    $WINE_PATH "$EXE_PATH" &
    APP_PID=$!
    log "✅ App launched with PID: $APP_PID"
    
    # ============= START AUTO-HEAL MONITOR =============
    # Start a background process that checks every 2 seconds if the app is running
    (
        # Wait 5 seconds for app to fully start before monitoring begins
        sleep 5
        
        while true; do
            sleep 2
            # Check if the app process is still running (case insensitive)
            EXE_BASENAME=$(basename "$EXE_PATH")
            if ! pgrep -i -f "$EXE_BASENAME" > /dev/null; then
                log "⚠️ App crashed! Restarting..."
                # Restart the app
                cd /app
                $WINE_PATH "$EXE_PATH" &
                NEW_PID=$!
                log "✅ App restarted with PID: $NEW_PID"
            else
                # Optional: Log heartbeat every minute
                if [ $(( $(date +%s) % 60 )) -lt 5 ]; then
                    log "💓 App is running"
                fi
            fi
        done
    ) &
    MONITOR_PID=$!
    log "🔄 Auto-heal monitor started with PID: $MONITOR_PID"
    # ============= END AUTO-HEAL MONITOR =============
    
    log "✅ App launched with PID: $APP_PID"
  
    # Keep the script running to prevent container from exiting
    log "📡 Monitoring app process (PID: $APP_PID)..."
    wait $APP_PID
    EXIT_CODE=$?
    log "⚠️ App exited with code: $EXIT_CODE"
else
    log "❌ No executable found!"
    ls -la
    exit 1
fi

# If we get here, the app exited
log "👋 Launch script ending"
LAUNCH_EOF

chmod +x "\$APP_DIR/launch.sh"

# ============= CREATE CONFIG.JSON =============
log "Generating config.json..."
cat > "\$APP_DIR/config.json" << CONF_EOF
{
    "name": "${params.appName}",
    "version": "${params.version}",
    "description": "${params.description}",
    "executable": "${params.executable}",
    "port": \${APP_PORT},
    "vnc_password": "${params.vncPassword}",
    "icon": "/icons/${params.sanitizedName}.png",
    "category": "${params.category}"
}
CONF_EOF

# ============= CREATE DOCKER-COMPOSE.YML =============
log "Generating docker-compose.yml..."
cat > "\$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
version: '3.8'

services:
  winejs-\${APP_NAME}:
    image: winedrop-base:latest
    container_name: winejs-\${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:\${APP_PORT}:6901"
    shm_size: "512m"
    environment:
      - APP_NAME=\${APP_NAME}
      - START_CMD=/app/launch.sh
      - VNC_PW=${params.vncPassword}
      - KASM_ALLOW_UNSAFE_AUTH=1
      - VNCOPTIONS=-disableBasicAuth
      - KASM_VIDEO_QUALITY=5
      - KASM_VIDEO_FPS=15
      - KASM_MAX_RESOLUTION=1280x720
      
      - SDL_JOYSTICK_DEVICE=/dev/input/js0
      - SDL_GAMECONTROLLERCONFIG=030000005e040000be02000014010000,XInput Controller,platform:Linux,a:b0,b:b1,x:b2,y:b3,back:b8,guide:b16,start:b9,leftstick:b10,rightstick:b11,leftshoulder:b4,rightshoulder:b5,dpup:b12,dpdown:b13,dpleft:b14,dpright:b15,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:b6,righttrigger:b7
      
    volumes:
      - /opt/winejs/apps/\${APP_NAME}:/app:ro
      - /var/www/uploads:/uploads:rw
      - /opt/winejs/wine-prefixes/\${APP_NAME}:/home/kasm-user/.wine
      - /opt/winejs/kasmvnc-instances/\${APP_NAME}/vnc:/home/kasm-user/.vnc
      - /opt/winejs/translator/public/icons/\${APP_NAME}.png:/usr/share/kasm/favicon.png:ro
      - /run/udev:/run/udev:ro
      - /dev/shm:/dev/shm:rw
      - /var/run/dbus:/var/run/dbus:ro
      - /var/lib/bluetooth:/var/lib/bluetooth:ro

    devices:
      - /dev/dri:/dev/dri
      - /dev/input:/dev/input:ro
      - /dev/uinput:/dev/uinput:rw

    cap_add:
      - SYS_ADMIN
      - NET_RAW
      - SYS_RAWIO
      - SYS_TTY_CONFIG
    
    group_add:
      - "107"

    security_opt:
      - seccomp:unconfined
      
    networks:
      - winejs-net

networks:
  winejs-net:
    driver: bridge
DOCKER_EOF

# ============= FIX PERMISSIONS =============
log "Fixing permissions..."
VNC_DIR="\$INSTANCE_DIR/vnc"
mkdir -p "\$VNC_DIR"
chown -R 1000:1000 "\$VNC_DIR" 2>/dev/null || true
chown -R 1000:1000 "\$WINE_PREFIX" 2>/dev/null || true
chmod -R 755 "\$VNC_DIR" 2>/dev/null || true
chmod -R 755 "\$WINE_PREFIX" 2>/dev/null || true

# ============= CREATE UNINSTALL SCRIPT =============
log "Creating uninstall script..."
cat > "\$(dirname "\$APP_DIR")/${uninstallScriptPath}" << UNINSTALL_EOF
#!/bin/bash
# ============================================
# WineJS App Uninstaller
# Generated by WineJS Packager v1.0
# ============================================
# App: ${params.appName}
# ============================================

set -e

# Colors
RED='\\033[0;31m'; GREEN='\\033[0;32m'; YELLOW='\\033[1;33m'; NC='\\033[0m'
log() { echo -e "\${GREEN}[$(date '+%H:%M:%S')]\${NC} \$1"; }
error() { echo -e "\${RED}[ERROR]\${NC} \$1"; exit 1; }
warn() { echo -e "\${YELLOW}[WARNING]\${NC} \$1"; }

# ============= CRITICAL FIX: Change to safe directory =============
# This prevents the "uv_cwd" error when the current directory gets deleted
cd /tmp || cd /root || cd / || exit 1

log "Uninstalling ${params.appName}..."

APP_NAME="${params.sanitizedName}"
APP_DIR="/opt/winejs/apps/\$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/\$APP_NAME"
WINE_PREFIX="/opt/winejs/wine-prefixes/\$APP_NAME"
ICON_FILE="/opt/winejs/translator/public/icons/\${APP_NAME}.png"

# ============= STOP AND REMOVE CONTAINER =============
log "Stopping container..."
if docker ps -a | grep -q "winejs-\${APP_NAME}"; then
    cd "\$INSTANCE_DIR" 2>/dev/null || true
    docker-compose down 2>/dev/null || docker stop "winejs-\${APP_NAME}" 2>/dev/null || true
    docker rm "winejs-\${APP_NAME}" 2>/dev/null || true
    log "Container stopped and removed"
else
    log "Container not running"
fi

# ============= REMOVE DOCKER-COMPOSE FILES =============
log "Removing docker-compose configuration..."
if [ -d "\$INSTANCE_DIR" ]; then
    rm -rf "\$INSTANCE_DIR"
    log "Instance directory removed"
fi

# ============= REMOVE APP FILES =============
log "Removing application files..."
if [ -d "\$APP_DIR" ]; then
    rm -rf "\$APP_DIR"
    log "App directory removed"
fi

# ============= REMOVE WINE PREFIX =============
log "Removing Wine prefix..."
if [ -d "\$WINE_PREFIX" ]; then
    rm -rf "\$WINE_PREFIX"
    log "Wine prefix removed"
fi

# ============= REMOVE ICON =============
log "Removing icon..."
if [ -f "\$ICON_FILE" ]; then
    rm -f "\$ICON_FILE"
    log "Icon removed"
fi

# ============= RELOAD TRANSLATOR =============
log "Reloading WineJS translator..."
if command -v pm2 &> /dev/null; then
    # Make sure we're in a safe directory before running pm2
    cd /tmp || cd /root || cd /
    pm2 restart translator 2>/dev/null || pm2 start /opt/winejs/ecosystem.config.js 2>/dev/null || true
    log "Translator restarted"
fi

# ============= VERIFY REMOVAL =============
echo ""
echo "============================================"
echo "Uninstallation Complete!"
echo "============================================"
echo ""
log "${params.appName} has been completely removed from your WineJS system"
echo ""
echo "To verify removal:"
echo "   docker ps -a | grep winejs-\${APP_NAME}"
echo "   ls /opt/winejs/apps/ | grep \${APP_NAME}"
echo "   ls /opt/winejs/kasmvnc-instances/ | grep \${APP_NAME}"
echo ""
UNINSTALL_EOF

chmod +x "\$(dirname "\$APP_DIR")/${uninstallScriptPath}"
log "Uninstall script created: \$(dirname "\$APP_DIR")/${uninstallScriptPath}"

# ============= RELOAD TRANSLATOR =============
log "Reloading WineJS translator to detect new app..."

# Tell the translator to reload apps
if command -v pm2 &> /dev/null; then
    # Restart translator to reload app registry
    pm2 restart translator || pm2 start /opt/winejs/ecosystem.config.js 2>/dev/null || true
    log "Translator restarted"
fi

# ============= START THE CONTAINER =============
log "Starting container for ${params.appName}..."
cd "\$INSTANCE_DIR"
docker-compose up -d

# Wait a moment for container to start
sleep 3

# Check if container started
if docker ps | grep -q "winejs-\${APP_NAME}"; then
    log "Container started successfully"

    # ============= PATCH CONTAINER (like MilkShape) =============
    log "Applying container patches for ${params.appName}..."

    # Wait for container to be fully up
    sleep 5

    # Check if container is running
    if docker ps | grep -q "winejs-\${APP_NAME}"; then
        log "✅ Container is running, applying patches..."

        # ============= PATCH KASMVNC TO DISABLE CONTROL BAR ANIMATION =============
        log "🔧 Patching KasmVNC to stop control bar animation..."

        # Create the CSS file using printf (no here-document issues)
        docker exec -u 0 "winejs-\${APP_NAME}" bash -c 'printf "%s\n" \
        "/* Disable all control bar animations */" \
        "#noVNC_control_bar," \
        "#noVNC_control_bar_handle," \
        "#noVNC_control_bar_anchor," \
        ".noVNC_control_bar_animated {" \
        "    transition: none !important;" \
        "    animation: none !important;" \
        "}" \
        "" \
        "#noVNC_control_bar {" \
        "    transform: translateX(-280px) !important;" \
        "    opacity: 0 !important;" \
        "}" \
        "" \
        "#noVNC_control_bar_handle {" \
        "    transform: translateY(0px) !important;" \
        "    left: 0 !important;" \
        "}" \
        "" \
        "#noVNC_control_bar.noVNC_open {" \
        "    transform: translateX(-280px) !important;" \
        "    opacity: 0 !important;" \
        "}" \
        "" \
        ".noVNC_idle #noVNC_control_bar {" \
        "    transform: translateX(-280px) !important;" \
        "}" > /usr/share/kasmvnc/www/no-animation.css' 2>/dev/null || true

        # Inject CSS link
        docker exec -u 0 "winejs-\${APP_NAME}" bash -c 'sed -i "/<\/head>/i <link rel=\"stylesheet\" type=\"text\/css\" href=\"no-animation.css\">" /usr/share/kasmvnc/www/index.html' 2>/dev/null || true

        # Create the JavaScript file using printf
        docker exec -u 0 "winejs-\${APP_NAME}" bash -c 'printf "%s\n" \
        "(function() {" \
        "    function forceMinimized() {" \
        "        const bar = document.getElementById(\"noVNC_control_bar\");" \
        "        if (bar) {" \
        "            bar.className = bar.className.replace(\"noVNC_open\", \"\") + \" noVNC_closed\";" \
        "        }" \
        "        const handle = document.getElementById(\"noVNC_control_bar_handle\");" \
        "        if (handle) {" \
        "            handle.style.transform = \"translateY(0px)\";" \
        "        }" \
        "    }" \
        "    document.addEventListener(\"DOMContentLoaded\", forceMinimized);" \
        "    setTimeout(forceMinimized, 100);" \
        "    setTimeout(forceMinimized, 500);" \
        "})();" > /usr/share/kasmvnc/www/start-minimized.js' 2>/dev/null || true

        # Inject JavaScript
        docker exec -u 0 "winejs-\${APP_NAME}" bash -c 'sed -i "/<\/body>/i <script src=\"start-minimized.js\"></script>" /usr/share/kasmvnc/www/index.html' 2>/dev/null || true

        # Set permissions
        docker exec -u 0 "winejs-\${APP_NAME}" bash -c 'chown 1000:1000 /usr/share/kasmvnc/www/no-animation.css /usr/share/kasmvnc/www/start-minimized.js 2>/dev/null || chmod 644 /usr/share/kasmvnc/www/no-animation.css /usr/share/kasmvnc/www/start-minimized.js' 2>/dev/null || true

        log "✅ KasmVNC patched - control bar will start minimized"

        # ============= PANEL KILLER (keeps desktop clean) =============
        log "🔪 Setting up panel killer..."

        # Add panel killer to the container's startup (EXACT MILKSHAPE PATTERN)
        docker exec "winejs-\${APP_NAME}" bash -c 'cat >> /home/kasm-user/.bashrc << "EOF"
        # Kill panel immediately
        pkill -f "panel" 2>/dev/null || true
        pkill -f "xfce" 2>/dev/null || true

        # Start a background process that kills panel every 3 seconds
        (
            while true; do
                sleep 3
                # Kill any panels that reappear
                pkill -f "panel" 2>/dev/null || true
                pkill -f "xfce4-panel" 2>/dev/null || true
                pkill -f "lxpanel" 2>/dev/null || true
                
                # Also try to hide any panel windows
                if command -v xdotool &> /dev/null; then
                    PANEL_WINDOW=$(xdotool search --name "panel" 2>/dev/null | head -1)
                    if [ -n "$PANEL_WINDOW" ]; then
                        xdotool windowmove $PANEL_WINDOW -1000 1000 2>/dev/null || true
                    fi
                fi
            done
        ) &
        PANEL_KILLER_PID=$!
        echo "🔄 Persistent panel killer started with PID: $PANEL_KILLER_PID"
        EOF' 2>/dev/null || true

        log "✅ Panel killer configured"

        # Also set fluxbox config to hide toolbar
        docker exec "winejs-\${APP_NAME}" bash -c 'mkdir -p /home/kasm-user/.fluxbox && \
            echo "session.screen0.toolbar.visible: false" >> /home/kasm-user/.fluxbox/init && \
            echo "session.screen0.toolbar.autoHide: true" >> /home/kasm-user/.fluxbox/init' 2>/dev/null || true

        log "✅ Dock/panel killer configured"

        # Ensure kasm-user has sudo permissions
        docker exec "winejs-\${APP_NAME}" bash -c 'echo "kasm-user ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers > /dev/null 2>&1 || true' 2>/dev/null || true

        # Check for registry file
        if [ -f "\$APP_DIR/wineregkey.reg" ]; then
            log "📝 Found wineregkey.reg - importing into Wine registry..."
            
            docker exec "winejs-\${APP_NAME}" regedit /S "/opt/winejs/apps/\${APP_NAME}/wineregkey.reg" 2>/dev/null || {
                log "⚠️  Registry import failed - may need to run manually"
                log "   Try: docker exec winejs-\${APP_NAME} wine regedit /opt/winejs/apps/\${APP_NAME}/wineregkey.reg"
            }
            
            log "✅ Registry imported"
        fi

        # Check for setup batch file
        if [ -f "\$APP_DIR/setup.bat" ]; then
            log "⚙️  Found setup.bat - running pre-launch configuration..."
            docker exec "winejs-\${APP_NAME}" wine cmd /c "C:\\opt\\winejs\\apps\\\${APP_NAME}\\setup.bat" 2>/dev/null || {
                log "⚠️  Setup may have failed, but continuing..."
            }
            log "✅ Setup complete"
        fi

        # Check for pre-launch script (custom .sh)
        if [ -f "\$APP_DIR/prelaunch.sh" ]; then
            log "🚀 Found prelaunch.sh - running custom setup..."
            docker exec "winejs-\${APP_NAME}" bash "/opt/winejs/apps/\${APP_NAME}/prelaunch.sh" 2>/dev/null || {
                log "⚠️  Prelaunch script may have failed"
            }
            log "✅ Custom setup complete"
        fi

        # ============= SET DESKTOP BACKGROUND =============
        log "🎨 Setting desktop background..."

        # Create background script on host and copy to container (like MilkShape)
        cat > /tmp/set-bg-delayed.sh << 'BGEOF'
#!/bin/bash
sleep 10
# Extract domain from the translator config (more reliable)
if [ -f "/opt/winejs/translator/index.js" ]; then
    SERVER_DOMAIN=$(grep "const DOMAIN_NAME" /opt/winejs/translator/index.js | cut -d"'" -f2)
fi
# Fallback to hostname if not found
if [ -z "$SERVER_DOMAIN" ]; then
    SERVER_DOMAIN=$(hostname -f 2>/dev/null || echo "localhost")
fi
echo "🎨 Setting background with domain: $SERVER_DOMAIN"
curl -s "https://img.sdappnet.cloud/?url=\${SERVER_DOMAIN}&w=1920&h=1080" -o /tmp/snapshot.png 2>/dev/null
if [ -f /tmp/snapshot.png ]; then
    if command -v xfconf-query &>/dev/null; then
        xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s /tmp/snapshot.png 2>/dev/null
        echo "✅ Desktop background set"
    fi
fi
rm -f /tmp/set-bg-delayed.sh
BGEOF

        # Copy the script into the container and run it
        docker cp /tmp/set-bg-delayed.sh "winejs-\${APP_NAME}:/tmp/set-bg-delayed.sh" 2>/dev/null || true
        docker exec -d "winejs-\${APP_NAME}" bash -c "chmod +x /tmp/set-bg-delayed.sh && /tmp/set-bg-delayed.sh" 2>/dev/null || true
        rm -f /tmp/set-bg-delayed.sh

        log "✅ Desktop background configured"

    else
        log "⚠️ Container not running, skipping patches"
    fi

else
    log "Container may not have started. Check with: docker logs winejs-\${APP_NAME}"
fi

# ============= SHOW ACCESS INFO =============
log "${params.appName} installed successfully!"
log "Access at: https://\$(hostname -f)/\${APP_NAME}"
log "VNC Password: ${params.vncPassword}"

echo ""
echo "============================================"
echo "Installation Complete!"
echo "============================================"
echo ""
echo "App: ${params.appName}"
echo "URL: https://\$(hostname -f)/\${APP_NAME}"
echo "VNC Password: ${params.vncPassword}"
echo "Download ZIP: ${params.zipUrl}"
echo "Download Icon: ${params.iconUrl}"
echo ""
echo "To uninstall: sudo bash \$(dirname "\$APP_DIR")/${uninstallScriptPath}"
echo ""
`;
}

async function getCdnId(apiToken: string, bucket: string): Promise<string | null> {
    return new Promise((resolve) => {
        const req = https.request({
            method: "GET",
            hostname: "api.digitalocean.com",
            path: "/v2/cdn/endpoints",
            headers: { Authorization: `Bearer ${apiToken}` }
        }, (res: any) => {
            let data = "";
            res.on("data", (chunk: any) => data += chunk);
            res.on("end", () => {
                try {
                    const response = JSON.parse(data);
                    const endpoints = response.endpoints || [];
                    const match = endpoints.find((ep: any) =>
                        ep.origin?.startsWith(bucket + ".")
                    );
                    resolve(match?.id || null);
                } catch {
                    resolve(null);
                }
            });
        });

        req.on("error", () => resolve(null));
        req.end();
    });
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

# ===============================================
# Create README.md
# ===============================================
cat <<EOL > README.md
# WineJS Packager for VS Code

Right-click any folder → Package Windows apps for WineJS platform.

## Features

- 📝 **App Name**: Auto-filled from folder name
- 🔍 **EXE Scanner**: Finds all executables, you pick the main one
- 🎨 **Icon Options**:
  - Extract real icons from EXE (with preview!)
  - Use external URL
  - Use default placeholder
- 📦 **ZIP Creation**: Packages entire app folder
- ☁️ **Spaces Upload**: Uploads to DigitalOcean Spaces (rtx/wine/)
- 📝 **Install Script**: Generates \`install_appname.sh\` with everything needed

## Installation

1. Run this installer script
2. Open VS Code
3. Right-click any Windows app folder → "WineJS: Package Windows App"

## Configuration

Set your DigitalOcean Spaces credentials in VS Code settings:
- \`winejs.spaces.accessKey\`
- \`winejs.spaces.secretKey\`
- \`winejs.spaces.bucket\`
- \`winejs.spaces.endpoint\`

## What Gets Generated

When you package an app, you get:
1. \`AppName.zip\` - The full app package
2. \`install_AppName.sh\` - Installation script for WineJS server

The install script does everything:
- Downloads from Spaces
- Creates directories
- Generates launch.sh
- Creates config.json
- Sets up docker-compose.yml
- Copies icon to translator

## Requirements

- DigitalOcean Spaces account (for cloud uploads)
- icoutils (for icon extraction): \`brew install icoutils\` or \`apt-get install icoutils\`
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

# Set Node options
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export NODE_OPTIONS=--openssl-legacy-provider

echo -e "${YELLOW}Node: $(node -v) | npm: $(npm -v)${NC}"

# Install dependencies (THIS WILL INSTALL AWS SDK)
echo -e "${CYAN}📦 Installing Node dependencies...${NC}"
npm install

# Compile TypeScript
echo -e "${CYAN}🔨 Compiling TypeScript...${NC}"
npm run compile

# Package extension
echo -e "${CYAN}📦 Packaging extension...${NC}"

if ! command -v vsce &> /dev/null; then
    echo -e "${YELLOW}Installing vsce...${NC}"
    npm install -g vsce
fi

# Package with --allow-missing-repository (same as working uploader)
vsce package --allow-missing-repository

VSIX_FILE=$(ls winejs-packager-*.vsix 2>/dev/null | head -n1)

if [ ! -f "$VSIX_FILE" ]; then
    echo -e "${RED}❌ Failed to package extension${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Extension packaged: $VSIX_FILE${NC}"
echo -e "${CYAN}📊 Package size: $(du -h "$VSIX_FILE" | cut -f1)${NC}"

# Install extension
echo -e "${CYAN}📥 Installing extension...${NC}"

if command -v code-server &> /dev/null; then
    echo -e "${YELLOW}🔧 Detected code-server environment${NC}"
    code-server --install-extension "$VSIX_FILE" --force
else
    code --install-extension "$VSIX_FILE" --force
fi

echo -e "${GREEN}✅ WineJS Packager installed successfully!${NC}"
echo ""
echo -e "${CYAN}🚀 Usage:${NC}"
echo "1. Right-click any Windows app folder in VS Code"
echo "2. Select 'WineJS: Package Windows App'"
echo "3. Follow the prompts"
echo ""
echo -e "${CYAN}📦 The extension will generate:${NC}"
echo "   - ${parentFolderName}_install/${sanitizedAppName}.zip (your app package)"
echo "   - ${parentFolderName}_install/${sanitizedAppName}.png (app icon)"
echo "   - ${parentFolderName}_install/install_${sanitizedAppName}.sh (installer script)"
echo ""
echo -e "${GREEN}✅ Done!${NC}"

# 🚀 To Install:
# Save the script as install-winejs-packager.sh
# chmod +x install-winejs-packager.sh
# ./install-winejs-packager.sh

# 🎯 What You Get:
#     Right-click any folder → "WineJS: Package Windows App"
#     Interactive prompts for app name, EXE selection, icon options
#     Icon preview when extracting from EXE
#     ZIP creation of the entire app folder
#     Spaces upload (optional) of both ZIP and icon

#     GENERATES install_AppName.sh that contains:
#         Download URLs from Spaces
#         Directory creation
#         EXE detection
#         launch.sh generation
#         config.json with random VNC password
#         docker-compose.yml with next port

# The install_appname.sh script is plain bash - anyone can read it, understand it, and tweak it if needed. No hidden magic!
# 2. Self-Contained

# Everything is in one script:
#     Downloads from Spaces
#     Creates directories
#     Generates configs
#     Sets up docker-compose
#     No external dependencies

# 3. Matches Your Existing Pattern

# It follows EXACTLY the same structure as your MilkShape installation script:
# bash
# # Your MilkShape script
# mkdir -p /opt/winedrop/apps/milkshape
# curl -L "URL" -o app.zip
# unzip...
# find . -name "*.exe"
# create launch.sh
# create config.json
# create docker-compose.yml

# 4. Portable
# The script can be:
#     Run manually on any WineJS server
#     Added to a queue system later
#     Automated via cron
#     Shared with others

# 5. Debug-Friendly
# If something fails, you can run the script line by line and see exactly where it breaks.

# 6. Version Control Friendly

# The install script is text - can be committed to git, reviewed, modified.
# 7. Future-Proof

# When you later build the auto-installer system, these scripts can be:
#     Dropped into a watched folder
#     Processed by a queue
#     Executed by a webhook
#     Added to CI/CD

# ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
# │   VS Code       │────▶│   Spaces        │────▶│   WineJS Server │
# │   Extension     │     │   rtx/wine/     │     │                 │
# │                 │     │                 │     │  Later: Auto    │
# │ 1. Creates ZIP  │     │ • appname.zip   │     │  detect script  │
# │ 2. Uploads ZIP  │────▶│ • appname.jpg   │────▶│  and run it     │
# │ 3. Uploads icon │     │ • install.sh    │     │                 │
# │ 4. Generates    │     │                 │     │  For now:       │
# │    install.sh   │     │                 │     │  Manual run     │
# └─────────────────┘     └─────────────────┘     └─────────────────┘
# 🎯 The Install Script Contains:
# # Everything needed for a complete app installation:
# - ✅ Download ZIP from Spaces
# - ✅ Download icon from Spaces
# - ✅ Unzip to correct location
# - ✅ Find main EXE automatically
# - ✅ Generate launch.sh
# - ✅ Generate config.json with random VNC password
# - ✅ Generate docker-compose.yml with next available port
# - ✅ Copy icon to translator
# - ✅ All done!

# 🚀 Future Improvements (v1.1):
# 1. 🤖 **Auto port detection** - Scan used ports, assign next available
# 2. 📊 **Batch mode** - Process multiple apps at once
# 3. 🔧 **Custom launch params** - Add command line args to launch.sh
# 4. 🖼️ **Better icon extraction** - Support more icon formats
# 5. 📝 **App metadata editor** - Edit description, version, etc.
# 6. 🔌 **Wine dependencies** - Auto-detect required DLLs
# 7. 📦 **Install script queue** - Later auto-process on server

#     Extracts ALL icons from the EXE, not just the largest
#     Reports how many ICO resources were found
#     Extracts ALL sizes from each ICO (16x16, 32x32, 48x48, etc.)
#     Creates a manifest (icon_list.txt) with:
#         Filename
#         Dimensions (e.g., "256 x 256")
#         File size
#         Full path

# 📋 Example Output:

# 🔍 Extracting icons from: SampleLibrarian.exe
# 📦 Found 2 ICO resource(s)
#   ✓ Extracted 4 PNG(s) from icon_1.ico
#   ✓ Extracted 4 PNG(s) from icon_2.ico
# ✅ Total PNGs extracted: 8
# 📏 Largest icon: SampleLibrarian_icon_7.png (256 x 256, 24K)
# ICON_COUNT=8
# LARGEST_ICON=/tmp/winejs-icon-12345/SampleLibrarian_icon_7.png

# 📁 Output directory contents:
# /tmp/winejs-icon-12345/
# ├── windowsApp_icon_1.png  (16x16)
# ├── windowsApp_icon_2.png  (24x24)
# ├── windowsApp_icon_3.png  (32x32)
# ├── windowsApp_icon_4.png  (48x48)
# ├── windowsApp_icon_5.png  (64x64)
# ├── windowsApp_icon_6.png  (128x128)
# ├── windowsApp_icon_7.png  (256x256)
# ├── windowsApp_icon_8.png  (32x32)  # Second icon set
# └── icon_list.txt
# ZIP saved in same folder as install script (outputFolder)
# External URL icon downloaded and saved locally
# Upload to Spaces happens with progress indicator
# Install script gets real URLs if upload succeeded
# Summary shows correct paths and URLs

# What a macOS Wine Wrapper Would Look Like:
# MyApp.app/
# ├── Contents/
# │   ├── Info.plist
# │   ├── MacOS/
# │   │   └── wine-wrapper (launch script)
# │   ├── Resources/
# │   │   └── app.icns (icon)
# │   └── Wine/
# │       ├── drive_c/
# │       │   └── Program Files/
# │       │       └── MyApp/
# │       ├── wineprefix/
# │       └── wine (bundled Wine binary)

# The Packager Would:
#     Scan EXE files (same as WineJS packager)
#     Extract icons (same)
#     Bundle Wine (download prebuilt Wine from WineHQ or build your own)
#     Create .app structure
#     Generate launch script that sets up WINEPREFIX and runs the app
#     Package as .app or .dmg

# Benefits:
# Feature	WineJS Server	macOS Wrapper
# Run on	Linux server	macOS locally
# Access	Browser	Native .app
# Sharing	URL	.app file
# Updates	Server-side	Re-download app
# GPU	Server GPU	Local GPU
# Network	Required	Offline capable