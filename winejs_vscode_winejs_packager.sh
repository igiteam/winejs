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
echo -e "${CYAN}📥 Downloading WineJS logo...${NC}"
curl -s -o sh/logo.png "https://cdn.sdappnet.cloud/rtx/images/wineskin.png"

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
          "enum": ["Graphics", "Game", "Utility", "Office", "Development", "Other"],
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
import * as https from 'https';  // 👈 ADD THIS LINE
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

    // Step 2: Scan for EXE files
    await vscode.window.withProgress({
        location: vscode.ProgressLocation.Notification,
        title: 'Scanning for EXE files...',
        cancellable: false
    }, async (progress) => {
        progress.report({ increment: 10 });

        const exeFiles: string[] = [];
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

        progress.report({ increment: 30 });

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

        progress.report({ increment: 50 });

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

        let iconUrl = 'https://cdn.sdappnet.cloud/rtx/images/wine-placeholder.png';
        let iconExtracted = false;

        // In the extension.ts, replace the icon extraction section with this:
        if (iconChoice.label.includes('Extract')) {
            // Extract icon from EXE
            const tempDir = path.join(os.tmpdir(), `winejs-icon-${Date.now()}`);
            fs.mkdirSync(tempDir, { recursive: true });

            try {
                const extractScript = path.join(context.extensionPath, 'sh', 'extract_icon.sh');
                await execAsync(`bash "${extractScript}" "${mainExe}" "${tempDir}"`);

                // Find all extracted PNGs
                const extractedIcons = fs.readdirSync(tempDir)
                    .filter(f => f.endsWith('.png'))
                    .map(f => ({
                        path: path.join(tempDir, f),
                        name: f,
                        size: getImageSize(path.join(tempDir, f))
                    }))
                    .sort((a, b) => b.size.width - a.size.width); // Sort by size, largest first

                if (extractedIcons.length === 0) {
                    vscode.window.showWarningMessage('No icon found in EXE, falling back to default');
                } else if (extractedIcons.length === 1) {
                    // Only one icon, use it directly
                    const confirm = await showSingleIconPreview(extractedIcons[0].path, context);
                    if (confirm) {
                        iconExtracted = true;
                        // Copy the icon to our working directory
                        fs.copyFileSync(extractedIcons[0].path, path.join(tempDir, 'icon.png'));
                    }
                } else {
                    // Multiple icons - show selection grid
                    const selectedIcon = await showIconSelectionGrid(extractedIcons, context);
                    if (selectedIcon) {
                        iconExtracted = true;
                        fs.copyFileSync(selectedIcon, path.join(tempDir, 'icon.png'));
                    }
                }
            } finally {
                if (!iconExtracted) {
                    fs.rmSync(tempDir, { recursive: true, force: true });
                }
            }
        }

        else if (iconChoice.label.includes('URL')) {
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
            
            if (!urlInput) {
                vscode.window.showInformationMessage('Icon selection cancelled, using default');
            } else {
                iconUrl = urlInput;
                iconExtracted = true; // Mark as true so we'll download it
            }
        }

        // Helper function to get image dimensions
        function getImageSize(imagePath: string): { width: number, height: number } {
            try {
                // Try to use 'file' command to get dimensions (works on most systems)
                const output = require('child_process').execSync(`file "${imagePath}"`).toString();
                const match = output.match(/(\d+) x (\d+)/);
                if (match) {
                    return { 
                        width: parseInt(match[1]), 
                        height: parseInt(match[2]) 
                    };
                }
            } catch (e) {
                // Fallback: estimate based on file size (rough approximation)
                const stats = fs.statSync(imagePath);
                const approxSize = Math.round(Math.sqrt(stats.size / 4));
                return { 
                    width: approxSize, 
                    height: approxSize 
                };
            }
            return { width: 32, height: 32 };
        }

        // Show icon selection grid
        async function showIconSelectionGrid(icons: any[], context: vscode.ExtensionContext): Promise<string | null> {
            return new Promise(async (resolve) => {
                const panel = vscode.window.createWebviewPanel(
                    'iconSelection',
                    'Select App Icon',
                    vscode.ViewColumn.Active,
                    { enableScripts: true }
                );

                // Generate HTML grid of all icons
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

                // Handle messages from the webview
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
        async function showSingleIconPreview(iconPath: string, context: vscode.ExtensionContext): Promise<boolean> {
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

                // Handle messages from the webview
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

        progress.report({ increment: 70 });

        // Step 5: Ask for category
        const category = await vscode.window.showQuickPick(
            ['Graphics', 'Game', 'Utility', 'Office', 'Development', 'Other'],
            { placeHolder: 'Select app category', title: 'App Category' }
        );

        // Step 6: Ask for version
        const version = await vscode.window.showInputBox({
            title: 'App Version',
            prompt: 'Enter app version',
            value: '1.0'
        });

        // Step 7: Create temporary directory for packaging
        const tempDir = path.join(os.tmpdir(), `winejs-package-${Date.now()}`);
        const appTempDir = path.join(tempDir, appName);
        fs.mkdirSync(appTempDir, { recursive: true });

        // Copy all app files
        await execAsync(`cp -r "${folderPath}/"* "${appTempDir}/"`);

        // Step 8: Create ZIP in the SAME folder as the install script
        const outputFolder = folderPath; // Use the original folder
        const zipPath = path.join(outputFolder, `${appName}.zip`);
        await execAsync(`cd "${tempDir}" && zip -r "${zipPath}" "${appName}/"`);

        // Handle icon from external URL
        let iconPath = '';
        let iconFileName = `${appName}.jpg`;

        if (iconChoice.label.includes('URL')) {
            // Download icon from URL
            const iconResponse = await fetch(iconUrl);
            const iconBuffer = Buffer.from(await iconResponse.arrayBuffer());
            iconPath = path.join(outputFolder, iconFileName);
            fs.writeFileSync(iconPath, iconBuffer);
            iconExtracted = true;
            console.log(`✅ Icon downloaded from URL to: ${iconPath}`);
        } else if (iconExtracted) {
            // Move extracted icon to output folder
            iconPath = path.join(outputFolder, iconFileName);
            fs.copyFileSync(path.join(tempDir, 'icon.png'), iconPath);
        }

        // Step 9: Upload to Spaces - EXACTLY like working example
        const config = vscode.workspace.getConfiguration('winejs');
        const accessKey = config.get('accessKey') as string;
        const secretKey = config.get('secretKey') as string;
        const bucket = config.get('bucket') as string;
        const endpoint = config.get('endpoint') as string || "https://fra1.digitaloceanspaces.com";
        const region = config.get('region') as string || "fra1";
        const spacesFolder = config.get('folder') as string || "rtx/wine";
        const makePublic = config.get('makePublic') as boolean ?? true;
        const cdnEndpoint = config.get('cdnEndpoint') as string || null;
        const apiToken = config.get('apiToken') as string || null;
        let cdnId = config.get('cdnId') as string || null;

        let zipUrl = '';
        let iconUploadUrl = 'https://cdn.sdappnet.cloud/rtx/images/wine-placeholder.png';

        // Auto-detect CDN ID if needed - EXACTLY like working example
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

        // Enhanced config validation with open settings options - EXACTLY like working example
        if (!accessKey) {
            const action = await vscode.window.showErrorMessage(
                'WineJS Spaces Access Key not configured!',
                'Open Settings',
                'Cancel'
            );
            if (action === 'Open Settings') {
                vscode.commands.executeCommand('workbench.action.openSettings', 'winejs.accessKey');
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
                vscode.commands.executeCommand('workbench.action.openSettings', 'winejs.secretKey');
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
                vscode.commands.executeCommand('workbench.action.openSettings', 'winejs.bucket');
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
                // Dynamically import AWS SDK - EXACTLY like working example
                const s3Module = require('@aws-sdk/client-s3');
                const { PutObjectCommand, S3Client } = s3Module;
                
                // Show progress
                await vscode.window.withProgress({
                    location: vscode.ProgressLocation.Notification,
                    title: "Uploading to DigitalOcean Spaces...",
                    cancellable: false
                }, async (progress) => {
                    progress.report({ increment: 0 });

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

                    // Upload ZIP
                    const zipKey = `${spacesFolder}/${appName}.zip`;
                    const zipContent = fs.readFileSync(zipPath);
                    
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
                    
                    // Construct public URL
                    const spaceUrl = endpoint.replace('https://', `https://${bucket}.`);
                    let publicUrl: string;
                    
                    if (cdnEndpoint) {
                        publicUrl = `${cdnEndpoint}/${zipKey}`;
                    } else {
                        publicUrl = `${spaceUrl}/${zipKey}`;
                    }
                    
                    zipUrl = publicUrl;
                    progress.report({ increment: 50 });

                    // Upload icon if we have one
                    if (iconPath && fs.existsSync(iconPath)) {
                        const iconKey = `${spacesFolder}/images/${appName}.jpg`;
                        const iconContent = fs.readFileSync(iconPath);
                        
                        const iconParams: any = {
                            Bucket: bucket,
                            Key: iconKey,
                            Body: iconContent,
                            ContentType: 'image/jpeg',
                            Metadata: {
                                "uploaded-from": "winejs-packager",
                                "app-name": appName
                            }
                        };
                        
                        if (makePublic) {
                            iconParams.ACL = 'public-read';
                        }
                        
                        await s3Client.send(new PutObjectCommand(iconParams));
                        
                        if (cdnEndpoint) {
                            iconUploadUrl = `${cdnEndpoint}/${iconKey}`;
                        } else {
                            iconUploadUrl = `${spaceUrl}/${iconKey}`;
                        }
                    }

                    progress.report({ increment: 100 });
                    
                    vscode.window.showInformationMessage(
                        `✅ ZIP uploaded successfully!`,
                        "Copy URL",
                        "Open in Browser"
                    ).then(selection => {
                        if (selection === "Copy URL") {
                            vscode.env.clipboard.writeText(zipUrl);
                            vscode.window.showInformationMessage("URL copied to clipboard!");
                        } else if (selection === "Open in Browser") {
                            vscode.env.openExternal(vscode.Uri.parse(zipUrl));
                        }
                    });
                });

                // Attempt CDN purge (optional) - EXACTLY like working example
                if (apiToken && cdnId) {
                    try {
                        const purgeBody = JSON.stringify({ files: [`${spacesFolder}/${appName}.zip`] });

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
                                        reject(new Error(`CDN purge failed with status ${res.statusCode}: ${responseData}`));
                                    }
                                });
                            });
                            
                            req.on('error', (error) => {
                                reject(error);
                            });
                            
                            req.write(purgeBody);
                            req.end();
                        });
                        
                        vscode.window.showInformationMessage("✅ CDN cache purged!");
                    } catch (error: any) {
                        vscode.window.showWarningMessage(`⚠️ CDN purge failed: ${error.message}`);
                    }
                }

            } catch (error: any) {
                vscode.window.showErrorMessage(`Upload failed: ${error.message}`);
                console.error("Spaces upload error:", error);
            }
        }

        progress.report({ increment: 90 });

        // Step 10: Generate install script
        const installScriptPath = path.join(folderPath, `install_${appName.toLowerCase().replace(/\s+/g, '_')}.sh`);
        const randomPass = crypto.randomBytes(6).toString('hex');
        const nextPort = 6902; // This should be dynamic in real implementation

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
            vncPassword: randomPass
        });

        fs.writeFileSync(installScriptPath, installScript);
        fs.chmodSync(installScriptPath, 0o755);

        progress.report({ increment: 100 });

        // Step 11: Show summary
        const summary = `
## ✅ WineJS Package Created Successfully!

**App:** ${appName}
**Main EXE:** ${mainExeName}
**Category:** ${category || 'Other'}

### 📦 Files Created:
- **ZIP Package:** ${zipPath}
- **Install Script:** ${installScriptPath}
${iconPath ? `- **Icon:** ${iconPath}` : ''}

### ☁️ Upload Status:
${zipUrl !== 'LOCAL_FILE' ? `- **ZIP URL:** ${zipUrl}` : '- **ZIP saved locally**'}
${iconUploadUrl !== 'https://cdn.sdappnet.cloud/rtx/images/wine-placeholder.png' ? `- **Icon URL:** ${iconUploadUrl}` : '- **Icon saved locally**'}

### 📝 Next Steps:
1. Copy the install script to your WineJS server
2. Run: \`sudo bash ${path.basename(installScriptPath)}\`
3. The app will be installed to /opt/winedrop/apps/${appName.toLowerCase().replace(/\s+/g, '_')}
        `;

        const doc = await vscode.workspace.openTextDocument({ content: summary, language: 'markdown' });
        await vscode.window.showTextDocument(doc);

        // Cleanup temp files
        fs.rmSync(tempDir, { recursive: true, force: true });
    });
}

function generateInstallScript(params: any): string {
    const appDir = params.appName.toLowerCase().replace(/\s+/g, '_');
    
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

set -e

# Colors
RED='\\033[0;31m'; GREEN='\\033[0;32m'; YELLOW='\\033[1;33m'; NC='\\033[0m'
log() { echo -e "\${GREEN}[$(date '+%H:%M:%S')]\${NC} \$1"; }
error() { echo -e "\${RED}[ERROR]\${NC} \$1"; exit 1; }

log "🚀 Installing ${params.appName}..."

# Create app directory
APP_DIR="/opt/winedrop/apps/${appDir}"
mkdir -p "\$APP_DIR"
cd "\$APP_DIR"

# Download app package
log "📥 Downloading ${params.appName} package..."
if [[ "${params.zipUrl}" == "LOCAL_FILE" ]]; then
    log "⚠️  Local installation - please copy files manually to \$APP_DIR"
else
    curl -L "${params.zipUrl}" -o app.zip || error "Failed to download app package"
    unzip -o -q app.zip || error "Failed to unzip app package"
    rm -f app.zip
fi

# Download icon
log "🎨 Downloading app icon..."
mkdir -p /opt/winedrop/translator/public/icons
curl -L "${params.iconUrl}" -o /opt/winedrop/translator/public/icons/${appDir}.jpg || echo "⚠️ Failed to download icon, using default"

# Find the main executable
log "🔍 Locating main executable..."
MAIN_EXE=\$(find . -name "*.exe" -type f | grep -v "uninstall" | head -1 | sed 's|.*/||')
if [ -z "\$MAIN_EXE" ]; then
    MAIN_EXE="${params.executable}"
    log "⚠️  Using configured executable: \$MAIN_EXE"
fi
log "✅ Found executable: \$MAIN_EXE"

# Create launch script with Wine path detection
log "🚀 Generating launch.sh..."
cat > /opt/winedrop/apps/${appDir}/launch.sh << 'EOF'
#!/bin/bash
# Find Wine (try multiple locations)
WINE_PATH=$(which wine 2>/dev/null || find /usr -name "wine" -type f 2>/dev/null | head -1)
if [ -z "$WINE_PATH" ]; then
    WINE_PATH="/usr/lib/wine/wine"
fi
echo "Using Wine at: $WINE_PATH"

# Find and launch the app
EXE_PATH=$(find /app -name "*.exe" -type f | grep -v "uninstall" | head -1)
if [ -z "$EXE_PATH" ]; then
    echo "❌ No executable found!"
    exit 1
fi

cd "$(dirname "$EXE_PATH")"
EXE_FILE=$(basename "$EXE_PATH")
echo "🚀 Launching $EXE_FILE from $(pwd)"
$WINE_PATH "$EXE_FILE"
EOF

# Create config.json
log "📝 Generating config.json..."
cat > /opt/winedrop/apps/${appDir}/config.json << EOF
{
    "name": "${params.appName}",
    "version": "${params.version}",
    "description": "${params.description}",
    "executable": "\$MAIN_EXE",
    "port": ${params.port},
    "vnc_password": "${params.vncPassword}",
    "icon": "/icons/${appDir}.jpg",
    "category": "${params.category}"
}
EOF

# Create docker-compose.yml
log "🐳 Generating docker-compose.yml..."
mkdir -p /opt/winedrop/kasmvnc-instances/${appDir}
cat > /opt/winedrop/kasmvnc-instances/${appDir}/docker-compose.yml << EOF
version: '3.8'
services:
  winedrop-${appDir}:
    image: winedrop-base:latest
    container_name: winedrop-${appDir}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${params.port}:6901"
    shm_size: "512m"
    environment:
      - START_CMD=/app/launch.sh
      - VNC_PW=${params.vncPassword}
      - KASM_ALLOW_UNSAFE_AUTH=1
      - VNCOPTIONS=-disableBasicAuth
      - KASM_VIDEO_QUALITY=5
      - KASM_VIDEO_FPS=15
    volumes:
      - /opt/winedrop/apps/${appDir}:/app:ro
      - /var/www/uploads:/uploads:rw
    networks:
      - winedrop-net

networks:
  winedrop-net:
    external: true
EOF

log "✅ ${params.appName} installed successfully!"
log "🌐 Access at: https://yourdomain.com/${appDir}"
log "🔑 VNC Password: ${params.vncPassword}"

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    Installation Complete!                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "📱 App: ${params.appName}"
echo "🌐 URL: https://yourdomain.com/${appDir}"
echo "🔑 VNC Password: ${params.vncPassword}"
${params.zipUrl !== 'LOCAL_FILE' ? `echo "📦 Download ZIP: ${params.zipUrl}"` : ''}
${params.iconUrl !== 'https://cdn.sdappnet.cloud/rtx/images/wine-placeholder.png' ? `echo "🎨 Download Icon: ${params.iconUrl}"` : ''}
echo ""
`;
}

async function generatePreviewHtml(iconPath: string): Promise<string> {
    const iconData = fs.readFileSync(iconPath).toString('base64');
    return `<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial; padding: 20px; text-align: center; }
        img { max-width: 256px; max-height: 256px; border: 2px solid #333; border-radius: 10px; }
        h2 { color: #333; }
    </style>
</head>
<body>
    <h2>Extracted Icon Preview</h2>
    <img src="data:image/png;base64,${iconData}" alt="Extracted Icon">
    <p>Close this tab and check VS Code for confirmation prompt</p>
</body>
</html>`;
}

// Auto-fetch CDN ID (copied from working uploader)
async function getCdnId(apiToken: string, bucket: string): Promise<string | null> {
    return new Promise((resolve) => {
        const req = https.request({
            method: "GET",
            hostname: "api.digitalocean.com",
            path: "/v2/cdn/endpoints",
            headers: { Authorization: `Bearer ${apiToken}` }
        }, (res: any) => {  // 👈 Add type here
            let data = "";
            res.on("data", (chunk: any) => data += chunk);  // 👈 Add type here
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
node_modules
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

# After creating package.json, FORCE INSTALL AWS SDK
echo -e "${CYAN}📦 FORCE INSTALLING AWS SDK...${NC}"

# Delete node_modules if exists to start fresh
rm -rf node_modules package-lock.json

# Install with force and legacy peer deps
npm install --force --legacy-peer-deps

# Specifically ensure AWS SDK is installed
npm install @aws-sdk/client-s3@3.654.0 --save --force

# Verify installation
if [ -d "node_modules/@aws-sdk/client-s3" ]; then
    echo -e "${GREEN}✅ AWS SDK installed successfully!${NC}"
else
    echo -e "${RED}❌ AWS SDK STILL NOT FOUND! Trying alternative method...${NC}"
    
    # Try with specific version and no cache
    npm cache clean --force
    npm install @aws-sdk/client-s3@3.654.0 --save --force --no-cache
    
    # Final check
    if [ -d "node_modules/@aws-sdk/client-s3" ]; then
        echo -e "${GREEN}✅ AWS SDK installed on second attempt!${NC}"
    else
        echo -e "${RED}❌ CRITICAL: AWS SDK failed to install. Extension will not upload.${NC}"
    fi
fi

# Install dependencies
if [ ! -d "node_modules" ]; then
    echo -e "${CYAN}📦 Installing Node dependencies...${NC}"
    npm install
fi

# Compile TypeScript
echo -e "${CYAN}🔨 Compiling TypeScript...${NC}"
npm run compile

# Package extension
echo -e "${CYAN}📦 Packaging extension...${NC}"

if ! command -v vsce &> /dev/null; then
    echo -e "${YELLOW}Installing vsce...${NC}"
    npm install -g vsce
fi

vsce package --allow-missing-repository

VSIX_FILE=$(ls winejs-packager-*.vsix 2>/dev/null | head -n1)

if [ ! -f "$VSIX_FILE" ]; then
    echo -e "${RED}❌ Failed to package extension${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Extension packaged: $VSIX_FILE${NC}"

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
echo "   - AppName.zip (your app package)"
echo "   - install_AppName.sh (installer script)"
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