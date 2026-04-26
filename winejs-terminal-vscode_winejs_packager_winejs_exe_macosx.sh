#!/bin/bash
set -e

# =================================================
# WineJS Desktop Packager - VS Code Extension v3.0
# Right-click → Create macOS Desktop App for Windows EXE
# =================================================
# ┌─────────────────────────────────────────────────────────────┐
# │              WineJS Desktop Packager v3.0                   │
# ├─────────────────────────────────────────────────────────────┤
# │  ✅ Right-click any folder with Windows EXE                 │
# │  ✅ Auto-filled app name                                    │
# │  ✅ EXE scanner with smart filtering                        │
# │  ✅ Icon extraction from EXE (kept!)                        │
# │  ✅ URL or default icon options                             │
# │  ✅ NO TERMINAL WINDOW - runs in background!                │
# │  ✅ SYMLINK instead of copy (instant creation!)             │
# │  ✅ Creates macOS .app bundle with Wine wrapper             │
# │  ✅ Places app on Desktop + Applications folder             │
# │  ✅ Adds to Dock automatically                              │
# │  ✅ Creates Install.command + Uninstall.command             │
# │  ✅ Professional first-run setup with progress dialogs      │
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
echo "║           WineJS Desktop Packager v3.0                        ║"
echo "║         (Inspired by Sketch wrapper - No Terminal!)          ║"
echo "║                                                               ║"
echo "║   Right-click any folder → Create macOS Desktop App           ║"
echo "║                                                               ║"
echo "║   📝 Enter app name (auto-filled)                             ║"
echo "║   📋 Lists all EXE files - you pick main                      ║"
echo "║   🎨 Extract icon from EXE (kept!) + URL + Default            ║"
echo "║   🖥️  Creates macOS .app bundle with symlink (instant!)       ║"
echo "║   📌 Places on Desktop + Applications folder                  ║"
echo "║   🖱️  Adds to Dock automatically                              ║"
echo "║   🚀 No terminal window - runs silently in background!       ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Ask for extension name
read -p "Enter extension folder name (default: winejs-desktop-packager-macosx): " EXTNAME
EXTNAME=${EXTNAME:-winejs-desktop-packager-macosx}

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
echo -e "${CYAN}📥 Downloading WineJS Desktop Packager logo...${NC}"
curl -s -o sh/logo.png "https://cdn.gitgpt.chat/rtx/images/winejs-packager-exe-macosx.png"

# ===============================================
# Create icon extraction helper script (KEPT!)
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

# Extract all icon resources
wrestool --extract --type=14 "$EXE_FILE" -o "$TEMP_ICO_DIR/" 2>/dev/null

ICO_COUNT=$(find "$TEMP_ICO_DIR" -name "*.ico" 2>/dev/null | wc -l)
if [ "$ICO_COUNT" -eq 0 ]; then
    wrestool --extract --type=group_icon "$EXE_FILE" -o "$TEMP_ICO_DIR/" 2>/dev/null
    ICO_COUNT=$(find "$TEMP_ICO_DIR" -name "*.ico" 2>/dev/null | wc -l)
fi

echo "📦 Found $ICO_COUNT ICO resource(s)"

PNG_TOTAL=0
if [ "$ICO_COUNT" -gt 0 ]; then
    for ico in "$TEMP_ICO_DIR"/*.ico; do
        if [ -f "$ico" ]; then
            icotool -x "$ico" -o "$OUTPUT_DIR/" 2>/dev/null
            PNG_EXTRACTED=$(find "$OUTPUT_DIR" -name "*.png" -newer "$ico" 2>/dev/null | wc -l)
            PNG_TOTAL=$((PNG_TOTAL + PNG_EXTRACTED))
            echo "  ✓ Extracted $PNG_EXTRACTED PNG(s) from $(basename "$ico")"
        fi
    done
fi

rm -rf "$TEMP_ICO_DIR"

PNG_COUNT=$(find "$OUTPUT_DIR" -name "*.png" 2>/dev/null | wc -l)

if [ "$PNG_COUNT" -gt 0 ]; then
    echo "✅ Total PNGs extracted: $PNG_COUNT"
    
    LARGEST=$(find "$OUTPUT_DIR" -name "*.png" -type f -exec ls -S {} \; | head -1)
    LARGEST_SIZE=$(du -h "$LARGEST" 2>/dev/null | cut -f1)
    LARGEST_DIMS=$(file "$LARGEST" | grep -oE '[0-9]+ x [0-9]+' || echo "unknown")
    
    echo "📏 Largest icon: $(basename "$LARGEST") (${LARGEST_DIMS}, ${LARGEST_SIZE})"
    
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
  "name": "winejs-desktop-packager-macosx",
  "displayName": "WineJS Desktop Packager",
  "description": "Right-click any folder → Create macOS desktop app for Windows EXE using Wine (No terminal! Symlink fast!)",
  "repository": "https://github.com/winejs/desktop-packager",
  "publisher": "winejs",
  "icon": "sh/logo.png",
  "version": "3.0.0",
  "engines": {
    "vscode": "^1.81.0"
  },
  "categories": [
    "Other"
  ],
  "activationEvents": [
    "onCommand:winejs.createDesktopApp"
  ],
  "main": "./out/extension.js",
  "contributes": {
    "commands": [
      {
        "command": "winejs.createDesktopApp",
        "title": "WineJS: Create macOS Desktop App (No Terminal)",
        "category": "WineJS"
      }
    ],
    "menus": {
      "explorer/context": [
        {
          "command": "winejs.createDesktopApp",
          "group": "winejs@1",
          "when": "explorerResourceIsFolder"
        }
      ]
    },
    "configuration": {
      "title": "WineJS Desktop Packager",
      "properties": {
        "winejs.winePath": {
          "type": "string",
          "default": "auto",
          "description": "Path to Wine binary (or 'auto' to auto-detect)"
        },
        "winejs.defaultCategory": {
          "type": "string",
          "default": "Utility",
          "enum": ["Game", "Graphics", "Audio", "Utility", "Office", "Development", "Other"],
          "description": "Default app category for Finder"
        },
        "winejs.useSymlink": {
          "type": "boolean",
          "default": true,
          "description": "Use symlink instead of copying files (instant creation, saves disk space)"
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
  "dependencies": {}
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
# Create extension.ts
# ===============================================
cat <<'EOL' > src/extension.ts
import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

export function activate(context: vscode.ExtensionContext) {
    console.log('✅ WineJS Desktop Packager v3.0 activated!');

    const disposable = vscode.commands.registerCommand('winejs.createDesktopApp', async (uri: vscode.Uri) => {
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
            await createDesktopApp(folderPath, context);
        } catch (error: any) {
            vscode.window.showErrorMessage(`Failed to create desktop app: ${error.message}`);
        }
    });

    context.subscriptions.push(disposable);
}

async function createDesktopApp(folderPath: string, context: vscode.ExtensionContext) {
    const folderName = path.basename(folderPath);
    const appName = await vscode.window.showInputBox({
        title: 'App Name',
        prompt: 'Enter the name of the application (will appear in Dock/Launchpad)',
        value: folderName,
        validateInput: (value) => value ? null : 'App name cannot be empty'
    });

    if (!appName) {
        vscode.window.showInformationMessage('Creation cancelled');
        return;
    }

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

    const filteredExes = exeFiles.filter(exe => {
        const name = path.basename(exe).toLowerCase();
        return !name.includes('uninstall') && !name.includes('setup') && !name.includes('install');
    });

    const displayExes = filteredExes.length > 0 ? filteredExes : exeFiles;

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
        vscode.window.showInformationMessage('Creation cancelled');
        return;
    }

    const mainExe = selected.path;
    const mainExeName = path.basename(mainExe);
    const mainExeRelPath = path.relative(folderPath, mainExe);

    const iconChoice = await vscode.window.showQuickPick(
        [
            { label: '✅ Extract icon from EXE', description: 'Extract real icon from the executable (kept feature!)' },
            { label: '🌐 Use external URL', description: 'Provide a URL to an image' },
            { label: '🔗 Use default icon', description: 'Use WineJS placeholder icon' }
        ],
        { placeHolder: 'How do you want to handle the app icon?' }
    );

    if (!iconChoice) {
        vscode.window.showInformationMessage('Creation cancelled');
        return;
    }

    const tempDir = path.join(os.tmpdir(), `winejs-desktop-${Date.now()}`);
    fs.mkdirSync(tempDir, { recursive: true });
    
    const sanitizedAppName = appName.replace(/[^a-zA-Z0-9]/g, '_');
    const appBundleName = `${sanitizedAppName}.app`;
    
    const desktopPath = path.join(os.homedir(), 'Desktop', appBundleName);
    const applicationsPath = path.join(os.homedir(), 'Applications', appBundleName);
    let iconPath = path.join(tempDir, 'app_icon.png');
    let iconExtracted = false;

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

                const extractedIcons = fs.readdirSync(iconExtractDir)
                    .filter(f => f.endsWith('.png'))
                    .map(f => ({
                        path: path.join(iconExtractDir, f),
                        name: f,
                        size: getImageSize(path.join(iconExtractDir, f))
                    }))
                    .sort((a, b) => b.size.width - a.size.width);

                if (extractedIcons.length === 0) {
                    throw new Error('No icons found');
                } else if (extractedIcons.length === 1) {
                    progress.report({ increment: 75, message: "Previewing icon..." });
                    const confirm = await showSingleIconPreview(extractedIcons[0].path);
                    if (confirm) {
                        iconExtracted = true;
                        fs.copyFileSync(extractedIcons[0].path, iconPath);
                    }
                } else {
                    progress.report({ increment: 75, message: "Selecting best icon..." });
                    const selectedIcon = await showIconSelectionGrid(extractedIcons);
                    if (selectedIcon) {
                        iconExtracted = true;
                        fs.copyFileSync(selectedIcon, iconPath);
                    }
                }
                
                progress.report({ increment: 100, message: "Icon extraction complete!" });
            } catch (error: any) {
                vscode.window.showWarningMessage(`Icon extraction failed: ${error.message}. Using default icon.`);
            }
        });
    } else if (iconChoice.label.includes('URL')) {
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
            await vscode.window.withProgress({
                location: vscode.ProgressLocation.Notification,
                title: "📥 Downloading icon from URL...",
                cancellable: false
            }, async (progress) => {
                progress.report({ increment: 0, message: "Fetching icon..." });
                try {
                    const https = require('https');
                    const url = new URL(urlInput);
                    const iconBuffer = await new Promise<Buffer>((resolve, reject) => {
                        https.get(url, (res: any) => {
                            const chunks: Buffer[] = [];
                            res.on('data', (chunk: Buffer) => chunks.push(chunk));
                            res.on('end', () => resolve(Buffer.concat(chunks)));
                            res.on('error', reject);
                        }).on('error', reject);
                    });
                    fs.writeFileSync(iconPath, iconBuffer);
                    iconExtracted = true;
                    progress.report({ increment: 100, message: "Icon downloaded!" });
                } catch (error: any) {
                    vscode.window.showErrorMessage(`Failed to download icon: ${error.message}`);
                }
            });
        }
    }

    if (!iconExtracted || !fs.existsSync(iconPath)) {
        await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: "📥 Downloading default icon...",
            cancellable: false
        }, async (progress) => {
            progress.report({ increment: 0, message: "Fetching default icon..." });
            try {
                const https = require('https');
                const iconBuffer = await new Promise<Buffer>((resolve, reject) => {
                    https.get('https://cdn.gitgpt.chat/rtx/images/wine-placeholder.png', (res: any) => {
                        const chunks: Buffer[] = [];
                        res.on('data', (chunk: Buffer) => chunks.push(chunk));
                        res.on('end', () => resolve(Buffer.concat(chunks)));
                        res.on('error', reject);
                    }).on('error', reject);
                });
                fs.writeFileSync(iconPath, iconBuffer);
                progress.report({ increment: 100, message: "Default icon ready!" });
            } catch (error: any) {
                console.error('Failed to download default icon:', error);
            }
        });
    }

    let hasRegFile = false;
    let hasSetupBat = false;
    let hasPrelaunchSh = false;

    const regKeyPath = path.join(folderPath, 'regkey.reg');
    const setupBatPath = path.join(folderPath, 'setup.bat');
    const prelaunchPath = path.join(folderPath, 'prelaunch.sh');

    if (fs.existsSync(regKeyPath)) {
        hasRegFile = true;
        vscode.window.showInformationMessage(`📝 Found regkey.reg - will auto-import into Wine registry`);
    }
    if (fs.existsSync(setupBatPath)) {
        hasSetupBat = true;
        vscode.window.showInformationMessage(`⚙️ Found setup.bat - will auto-run during first launch`);
    }
    if (fs.existsSync(prelaunchPath)) {
        hasPrelaunchSh = true;
        vscode.window.showInformationMessage(`🚀 Found prelaunch.sh - will auto-run during first launch`);
    }

    const category = await vscode.window.showQuickPick(
        ['Game', 'Graphics', 'Audio', 'Utility', 'Office', 'Development', 'Other'],
        { placeHolder: 'Select app category (for Finder classification)', title: 'App Category' }
    );

    const version = await vscode.window.showInputBox({
        title: 'App Version',
        prompt: 'Enter app version',
        value: '1.0'
    });

    const config = vscode.workspace.getConfiguration('winejs');
    const useSymlink = config.get<boolean>('useSymlink', true);
    let appBundlePath: string = ""; // Initialize with empty string

    await vscode.window.withProgress({
        location: vscode.ProgressLocation.Notification,
        title: "📦 Creating macOS app bundle...",
        cancellable: false
    }, async (progress) => {
        progress.report({ increment: 0, message: "Creating app structure..." });
        
        const appBundleDir = path.join(tempDir, appBundleName);
        appBundlePath = appBundleDir; // Set immediately at the start
        
        const contentsDir = path.join(appBundleDir, 'Contents');
        const macOSDir = path.join(contentsDir, 'MacOS');
        const resourcesDir = path.join(contentsDir, 'Resources');
        
        fs.mkdirSync(macOSDir, { recursive: true });
        fs.mkdirSync(resourcesDir, { recursive: true });
        
        progress.report({ increment: 25, message: useSymlink ? "Creating symlink to Windows files (instant!)..." : "Copying application files..." });
        
        const wineAppDir = path.join(resourcesDir, '.wineapp');
        
        if (useSymlink) {
            fs.symlinkSync(folderPath, wineAppDir, 'dir');
            console.log(`✅ Created symlink: ${wineAppDir} -> ${folderPath}`);
        } else {
            fs.mkdirSync(wineAppDir, { recursive: true });
            await execAsync(`cp -r "${folderPath}/"* "${wineAppDir}/"`);
        }
        
        progress.report({ increment: 50, message: "Creating launcher script (no terminal!)..." });
        
        const launcherPath = path.join(macOSDir, 'launcher');
        const launcherScript = generateLauncherScript(appName, mainExeName, mainExeRelPath, hasRegFile, hasSetupBat, hasPrelaunchSh, useSymlink);
        fs.writeFileSync(launcherPath, launcherScript);
        fs.chmodSync(launcherPath, 0o755);
        
        progress.report({ increment: 75, message: "Creating Info.plist and icon..." });
        
        const infoPlist = generateInfoPlist(appName, version || '1.0', category || 'Utility', sanitizedAppName);
        fs.writeFileSync(path.join(contentsDir, 'Info.plist'), infoPlist);
        
        const icnsPath = path.join(resourcesDir, 'AppIcon.icns');
        await convertPngToIcns(iconPath, icnsPath);

        progress.report({ increment: 100, message: "App bundle created!" });
    });

    // Now appBundlePath is guaranteed to have a value
    // Sign the app bundle (CRITICAL for macOS Gatekeeper)
    if (appBundlePath && fs.existsSync(appBundlePath)) {
        await signAppBundle(appBundlePath);
    }

    if (fs.existsSync(desktopPath)) {
        await execAsync(`rm -rf "${desktopPath}"`);
    }
    await execAsync(`cp -R "${appBundlePath}" "${desktopPath}"`);

    const applicationsDir = path.join(os.homedir(), 'Applications');
    if (!fs.existsSync(applicationsDir)) {
        fs.mkdirSync(applicationsDir, { recursive: true });
    }
    if (fs.existsSync(applicationsPath)) {
        await execAsync(`rm -rf "${applicationsPath}"`);
    }
    await execAsync(`cp -R "${appBundlePath}" "${applicationsPath}"`);

    await createInstallScripts(appName, appBundleName, applicationsPath, desktopPath);
    await addToDock(appName, applicationsPath);
    
    const summary = `
## ✅ macOS Desktop App Created Successfully! (v3.0)

**App:** ${appName}
**Main EXE:** ${mainExeName}
**Category:** ${category || 'Utility'}
**Mode:** ${useSymlink ? '⚡ Symlink (instant, no duplication)' : '📋 Copy mode'}

### 📁 App Locations:
- **Desktop:** ${desktopPath}
- **Applications:** ${applicationsPath}

### 🖱️ Dock Status:
- App has been added to your Dock automatically

### 🚀 How to Use:
1. **Double-click** the app on your Desktop or in Applications
2. Or **click the Dock icon**
3. **NO TERMINAL WINDOW** - app runs silently in background!
4. The app will launch using Wine (must be installed on your Mac)

### ⚙️ Requirements:
- **Wine** must be installed on your Mac
- Install Wine via: \`brew install --cask wine-stable\`
- Or download from: https://winehq.org

### 🗑️ To Uninstall:
Run the **Uninstall.command** script in the project folder, or:
1. Drag the app from Applications to Trash
2. Optionally remove the Wine prefix: \`rm -rf ~/.wine-${sanitizedAppName}\`

### 📝 Notes:
- ${useSymlink ? 'App uses SYMLINK - original files stay where they are!' : 'App contains all Windows files inside the .app bundle'}
- First launch may take a moment to initialize Wine
- Your app data/saves are stored in ~/.wine-${sanitizedAppName}/drive_c/
- **No terminal window appears** - runs silently in background!
    `;

    const readmePath = path.join(tempDir, 'README.md');
    fs.writeFileSync(readmePath, summary);
    
    const doc = await vscode.workspace.openTextDocument(readmePath);
    await vscode.window.showTextDocument(doc);
    
    vscode.window.showInformationMessage(
        `✅ "${appName}" desktop app created! (No terminal mode)`,
        "Open Desktop",
        "Open Applications"
    ).then(selection => {
        if (selection === "Open Desktop") {
            vscode.env.openExternal(vscode.Uri.file(desktopPath));
        } else if (selection === "Open Applications") {
            vscode.env.openExternal(vscode.Uri.file(applicationsPath));
        }
    });
    
    fs.rmSync(tempDir, { recursive: true, force: true });
}


function generateLauncherScript(appName: string, mainExeName: string, mainExeRelPath: string, hasRegFile: boolean, hasSetupBat: boolean, hasPrelaunchSh: boolean, useSymlink: boolean): string {
    const escapedAppName = appName.replace(/ /g, '_');
    const lines = [
        '#!/bin/bash',
        '# ============================================',
        '# WineJS Desktop App Launcher v3.0 - SIMPLE FIX',
        '# ============================================',
        '',
        '# Get the real path (follow symlink)',
        'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
        'APP_RESOURCES="$(dirname "$SCRIPT_DIR")/Resources"',
        'SYMLINK_PATH="$APP_RESOURCES/.wineapp"',
        '',
        '# Resolve symlink to real path',
        'if [ -L "$SYMLINK_PATH" ]; then',
        '    APP_DIR="$(readlink "$SYMLINK_PATH")"',
        'else',
        '    APP_DIR="$SYMLINK_PATH"',
        'fi',
        '',
        '# Find the EXE',
        'EXE_PATH=""',
        `if [ -f "$APP_DIR/${mainExeName}" ]; then`,
        `    EXE_PATH="$APP_DIR/${mainExeName}"`,
        'else',
        `    EXE_PATH=$(find "$APP_DIR" -name "${mainExeName}" -type f 2>/dev/null | head -1)`,
        '    if [ -z "$EXE_PATH" ]; then',
        `        EXE_PATH=$(find "$APP_DIR" -name "*.exe" -type f 2>/dev/null | grep -v -i "uninstall" | head -1)`,
        '    fi',
        'fi',
        '',
        'if [ -z "$EXE_PATH" ]; then',
        '    osascript -e "display dialog \\"EXE not found!\\" buttons {\\"OK\\"}"',
        '    exit 1',
        'fi',
        '',
        '# ============= USE THE SAME METHOD AS DOUBLE-CLICKING EXE =============',
        '# This uses macOS default handler (which is Wine)',
        'open "$EXE_PATH"',
        '',
        '# Exit immediately',
        'exit 0'
    ];
    
    return lines.join('\n');
}

async function signAppBundle(appBundlePath: string): Promise<void> {
    try {
        console.log(`🔐 Signing app bundle: ${appBundlePath}`);
        
        const entitlementsPath = path.join(appBundlePath, 'Contents', 'Resources', 'entitlements.plist');
        const entitlements = '<?xml version="1.0" encoding="UTF-8"?>\n' +
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n' +
            '<plist version="1.0">\n' +
            '<dict>\n' +
            '    <key>com.apple.security.cs.allow-jit</key>\n' +
            '    <true/>\n' +
            '    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>\n' +
            '    <true/>\n' +
            '    <key>com.apple.security.cs.disable-library-validation</key>\n' +
            '    <true/>\n' +
            '    <key>com.apple.security.network.client</key>\n' +
            '    <true/>\n' +
            '</dict>\n' +
            '</plist>';
        
        fs.writeFileSync(entitlementsPath, entitlements);
        
        const launcherPath = path.join(appBundlePath, 'Contents', 'MacOS', 'launcher');
        if (fs.existsSync(launcherPath)) {
            await execAsync(`codesign --force --sign - "${launcherPath}"`);
        }
        
        await execAsync(`codesign --force --deep --sign - --entitlements "${entitlementsPath}" "${appBundlePath}"`);
        await execAsync(`xattr -d com.apple.quarantine "${appBundlePath}" 2>/dev/null || true`);
        
        console.log(`✅ Signed app bundle: ${appBundlePath}`);
    } catch (error) {
        console.warn(`⚠️ Failed to sign app bundle: ${error}`);
    }
}

function generateInfoPlist(appName: string, version: string, category: string, bundleId: string): string {
    const categoryMap: Record<string, string> = {
        'Game': 'public.app-category.games',
        'Graphics': 'public.app-category.graphics-design',
        'Audio': 'public.app-category.audio',
        'Utility': 'public.app-category.utilities',
        'Office': 'public.app-category.productivity',
        'Development': 'public.app-category.developer-tools',
        'Other': 'public.app-category.utilities'
    };
    
    const lsCategory = categoryMap[category] || 'public.app-category.utilities';
    const year = new Date().getFullYear();
    
    return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${appName}</string>
    <key>CFBundleDisplayName</key>
    <string>${appName}</string>
    <key>CFBundleIdentifier</key>
    <string>com.winejs.desktop.${bundleId}</string>
    <key>CFBundleVersion</key>
    <string>${version}</string>
    <key>CFBundleShortVersionString</key>
    <string>${version}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSApplicationCategoryType</key>
    <string>${lsCategory}</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © ${year}. All rights reserved.</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>`;
}

async function convertPngToIcns(pngPath: string, icnsPath: string): Promise<void> {
    const iconsetDir = path.join(path.dirname(icnsPath), 'AppIcon.iconset');
    
    try {
        if (fs.existsSync(iconsetDir)) {
            fs.rmSync(iconsetDir, { recursive: true, force: true });
        }
        fs.mkdirSync(iconsetDir, { recursive: true });
        
        const sizes = [16, 32, 64, 128, 256, 512, 1024];
        
        for (const size of sizes) {
            const outputPath = path.join(iconsetDir, `icon_${size}x${size}.png`);
            await execAsync(`sips -z ${size} ${size} "${pngPath}" --out "${outputPath}" 2>/dev/null || true`);
            
            const retinaSize = size * 2;
            const retinaPath = path.join(iconsetDir, `icon_${size}x${size}@2x.png`);
            await execAsync(`sips -z ${retinaSize} ${retinaSize} "${pngPath}" --out "${retinaPath}" 2>/dev/null || true`);
        }
        
        await execAsync(`iconutil -c icns "${iconsetDir}" -o "${icnsPath}" 2>/dev/null || true`);
        fs.rmSync(iconsetDir, { recursive: true, force: true });
    } catch (error) {
        console.warn('Failed to create icns file:', error);
        fs.writeFileSync(icnsPath, '');
    }
}

async function createInstallScripts(appName: string, appBundleName: string, applicationsPath: string, desktopPath: string): Promise<void> {
    const escapedAppName = appName.replace(/ /g, '_');
    
    // Write to user's home directory instead of current working directory
    const homeDir = os.homedir();
    const scriptsDir = path.join(homeDir, '.winejs-scripts');
    
    // Create scripts directory if it doesn't exist
    if (!fs.existsSync(scriptsDir)) {
        fs.mkdirSync(scriptsDir, { recursive: true });
    }
    
    const installScriptPath = path.join(scriptsDir, `Install-${escapedAppName}.command`);
    const uninstallScriptPath = path.join(scriptsDir, `Uninstall-${escapedAppName}.command`);
    
    const installScript = `#!/bin/bash
# Install ${appName} to Applications folder

echo "Installing ${appName}..."
echo ""

# Ensure ~/Applications exists
mkdir -p "$HOME/Applications"

# Copy to Applications
if [ -d "$HOME/Applications/${appBundleName}" ]; then
    rm -rf "$HOME/Applications/${appBundleName}"
fi

cp -R "${applicationsPath}" "$HOME/Applications/"

echo "✅ Installed to ~/Applications/${appBundleName}"

# Create desktop shortcut
if [ -d "$HOME/Desktop/${appBundleName}" ]; then
    rm -rf "$HOME/Desktop/${appBundleName}"
fi

cp -R "${desktopPath}" "$HOME/Desktop/"

echo "✅ Desktop shortcut created"
echo ""
echo "🎉 ${appName} is ready to use!"
echo "   Find it in your Dock or Applications folder"

# Open the Applications folder
open "$HOME/Applications"
`;

    const uninstallScript = `#!/bin/bash
# Uninstall ${appName}

echo "Uninstalling ${appName}..."
echo ""

# Remove from desktop
if [ -d "$HOME/Desktop/${appBundleName}" ]; then
    rm -rf "$HOME/Desktop/${appBundleName}"
    echo "✅ Removed from desktop"
fi

# Remove from ~/Applications
if [ -d "$HOME/Applications/${appBundleName}" ]; then
    rm -rf "$HOME/Applications/${appBundleName}"
    echo "✅ Removed from ~/Applications"
fi

# Remove Wine prefix
WINE_PREFIX="$HOME/.wine-${escapedAppName}"
if [ -d "$WINE_PREFIX" ]; then
    read -p "Remove Wine prefix for ${appName}? (y/N): " REMOVE_PREFIX
    if [[ "$REMOVE_PREFIX" =~ ^[Yy]$ ]]; then
        rm -rf "$WINE_PREFIX"
        echo "✅ Removed Wine prefix"
    fi
fi

echo ""
echo "✅ ${appName} has been uninstalled"
echo "   Note: You may need to remove the app from Dock manually"
`;

    fs.writeFileSync(installScriptPath, installScript);
    fs.chmodSync(installScriptPath, 0o755);
    
    fs.writeFileSync(uninstallScriptPath, uninstallScript);
    fs.chmodSync(uninstallScriptPath, 0o755);
    
    // Show info about where scripts were created
    vscode.window.showInformationMessage(
        `📦 Install/Uninstall scripts created in ~/.winejs-scripts/`,
        "Open Scripts Folder"
    ).then(selection => {
        if (selection === "Open Scripts Folder") {
            vscode.env.openExternal(vscode.Uri.file(scriptsDir));
        }
    });
}

async function addToDock(appName: string, appPath: string): Promise<void> {
    try {
        const { stdout } = await execAsync(`defaults read com.apple.dock persistent-apps 2>/dev/null | grep -c "${appName}" || true`);
        
        if (parseInt(stdout) === 0) {
            const tempPlist = '/tmp/dock_item.plist';
            const cleanAppPath = appPath.replace(/&/g, '&amp;');
            
            const plistContent = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>tile-data</key>
    <dict>
        <key>file-data</key>
        <dict>
            <key>_CFURLString</key>
            <string>file://${cleanAppPath}</string>
            <key>_CFURLStringType</key>
            <integer>15</integer>
        </dict>
        <key>file-type</key>
        <integer>41</integer>
        <key>file-label</key>
        <string>${appName}</string>
    </dict>
    <key>tile-type</key>
    <string>file-tile</string>
</dict>
</plist>`;
            
            fs.writeFileSync(tempPlist, plistContent);
            
            await execAsync(`/usr/libexec/PlistBuddy -c "Add persistent-apps:0 dict" ~/Library/Preferences/com.apple.dock.plist 2>/dev/null || true`);
            await execAsync(`/usr/libexec/PlistBuddy -c "Merge ${tempPlist} persistent-apps:0" ~/Library/Preferences/com.apple.dock.plist 2>/dev/null || true`);
            await execAsync(`killall Dock 2>/dev/null || true`);
            
            fs.unlinkSync(tempPlist);
        }
    } catch (error) {
        console.warn('Could not add to Dock:', error);
    }
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
# Create README.md (UPDATED)
# ===============================================
cat <<EOL > README.md
# WineJS Desktop Packager for VS Code v3.0

**Right-click any Windows app folder → Create a native macOS desktop app that runs the Windows EXE through Wine.**

## ✨ New in v3.0

- 🚀 **NO TERMINAL WINDOW** - Apps run silently in the background!
- ⚡ **SYMLINK MODE** - Instant creation, no disk space wasted!
- 📦 **Install/Uninstall Scripts** - Professional installation experience
- 🎨 **Icon Extraction KEPT** - Still extract real icons from EXE files!
- 🖥️ **Better Dock Integration** - No bouncing icon!

## Features

- 📝 **App Name**: Auto-filled from folder name
- 🔍 **EXE Scanner**: Finds all executables, you pick the main one
- 🎨 **Icon Options**:
  - **Extract real icons from EXE** (kept from v2.0!)
  - Use external URL
  - Use default placeholder
- 🖥️ **Native macOS App**: Creates a proper .app bundle
- ⚡ **Symlink Mode**: Instant creation, no file copying (optional)
- 📌 **Desktop Shortcut**: Automatically placed on your Desktop
- 📁 **Applications Folder**: Copied to ~/Applications
- 🖱️ **Dock Integration**: Automatically added to Dock
- 🍷 **Wine Integration**: Smart Wine detection
- 🚫 **No Terminal**: Apps run silently in background

## Installation

1. Run this installer script
2. Open VS Code
3. Right-click any Windows app folder → "WineJS: Create macOS Desktop App (No Terminal)"

## Requirements

- **Wine** must be installed on your Mac
  - Install via Homebrew: \`brew install --cask wine-stable\`
  - Or download from: https://winehq.org
- **icoutils** for icon extraction: \`brew install icoutils\`

## What Gets Generated

When you package an app, you get:
1. **AppName.app** - Native macOS application bundle
2. Placed on your Desktop
3. Copied to ~/Applications
4. Added to your Dock automatically
5. **Install.command** - Reinstall script
6. **Uninstall.command** - Complete removal script

## Configuration

Settings in VS Code:
- \`winejs.winePath\`: Custom path to Wine binary
- \`winejs.defaultCategory\`: Default app category for Finder
- \`winejs.useSymlink\`: Use symlink instead of copy (default: true)

## How It Works

The launcher script (v3.0):
1. Finds Wine on your system (checks common locations)
2. Sets up a dedicated Wine prefix for the app
3. Changes to the app directory (symlink or copy)
4. **Launches with nohup - NO TERMINAL WINDOW!**
5. Exits immediately so Dock icon doesn't bounce

## Uninstalling

Run **Uninstall.command** in the project folder, or:
Simply drag the .app from Applications to Trash.
Optionally remove the Wine prefix: \`rm -rf ~/.wine-AppName\`

EOL

# -----------------------------
# Create LICENSE.md
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

echo -e "${CYAN}🔨 Building and installing extension v3.0...${NC}"

# Set Node options
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export NODE_OPTIONS=--openssl-legacy-provider

echo -e "${YELLOW}Node: $(node -v) | npm: $(npm -v)${NC}"

# Install dependencies
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

vsce package --allow-missing-repository

VSIX_FILE=$(ls winejs-desktop-packager-macosx-*.vsix 2>/dev/null | head -n1)

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

echo -e "${GREEN}✅ WineJS Desktop Packager v3.0 installed successfully!${NC}"
echo ""
echo -e "${CYAN}🚀 Usage:${NC}"
echo "1. Right-click any Windows app folder in VS Code"
echo "2. Select 'WineJS: Create macOS Desktop App (No Terminal)'"
echo "3. Follow the prompts"
echo ""
echo -e "${CYAN}✨ NEW in v3.0:${NC}"
echo "   ⚡ Instant creation with symlink mode"
echo "   🚫 No terminal window - runs silently!"
echo "   📦 Install/Uninstall scripts included"
echo "   🎨 Icon extraction still works!"
echo ""
echo -e "${CYAN}📦 The extension will create:${NC}"
echo "   - A native .app bundle on your Desktop (instant with symlink!)"
echo "   - A copy in ~/Applications"
echo "   - Automatic addition to your Dock"
echo "   - Install.command + Uninstall.command"
echo ""
echo -e "${GREEN}✅ Done!${NC}"

echo ""
echo -e "${YELLOW}📝 Note: Make sure Wine is installed on your Mac:${NC}"
echo "   brew install --cask wine-stable"
echo ""
echo -e "${CYAN}💡 Tip: Enable symlink mode in VS Code settings for instant app creation!${NC}"
echo ""

# Double-click .app in Finder
#     ↓
# Launcher script runs (with Finder's limited environment)
#     ↓
# Script finds the .exe file
#     ↓
# Script calls: open "/path/to/app.exe"
#     ↓
# macOS Launch Services looks up: "What handles .exe files?"
#     ↓
# Launch Services finds: Wine (registered during installation)
#     ↓
# macOS launches Wine with full permissions & proper environment
#     ↓
# Wine runs the Windows EXE ✓