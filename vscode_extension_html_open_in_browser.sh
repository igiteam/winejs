#!/bin/bash
set -e

# ======================================================
# HTML Browser Opener VS Code Extension                #
# ======================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║        HTML Browser Opener VS Code Extension            ║"
echo "║         (Opens HTML files in default browser)           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${PURPLE}🌐 This extension adds a 'Browser' button to:${NC}"
echo "   - Editor title bar for HTML files"
echo "   - File explorer context menu for HTML files"
echo "   - Opens HTML in your default browser (Safari, Firefox, Chrome, etc.)"
echo ""

# Ask for extension name
read -p "Enter your extension folder name (default: vscode-html-browser): " EXTNAME
EXTNAME=${EXTNAME:-vscode-html-browser}

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
mkdir -p "$EXTNAME" "$EXTNAME/media"
cd "$EXTNAME" || exit

# Create simple browser icon using base64
echo -e "${CYAN}📱 Creating browser icon...${NC}"
cat > media/logo.png.base64 << 'EOL'
iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAAsTAAALEwEAmpwYAAAA
AXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAACFSURBVHgB7ZLBCcAgDETdQaeoU+QKbpEt3M
ARHAFnKCRFfz2k6Q8K9YNDSI4jRy7IzPTYQT4lSeQMbPAWDAALtMAF2EEFXIByCIaVoAWeEVF6
a/h+2g6oBWfBDlg3rSVgv+w0kJkqE4BdJtMTP4Jq9i8N+7V8YL/wIRPewA94a6k91ZqW2gAAAAB
JRU5ErkJggg==
EOL

# Decode base64 to PNG
base64 -d media/logo.png.base64 > media/logo.png 2>/dev/null || echo "Using text-based icon"

# Create package.json - SIMPLIFIED VERSION WITHOUT NODE DEPENDENCIES
cat << 'EOL' > package.json
{
  "name": "html-browser-opener",
  "displayName": "HTML Browser",
  "description": "Open HTML files in default browser with one click",
  "publisher": "html-tools",
  "icon": "media/logo.png",
  "version": "1.0.0",
  "engines": {
    "vscode": "^1.60.0"
  },
  "categories": [
    "Other",
    "Visualization"
  ],
  "keywords": [
    "html",
    "browser",
    "preview",
    "open",
    "view"
  ],
  "activationEvents": [
    "onLanguage:html"
  ],
  "main": "./extension.js",
  "contributes": {
    "commands": [
      {
        "command": "htmlbrowser.openInBrowser",
        "title": "Browser",
        "category": "HTML"
      }
    ],
    "menus": {
      "explorer/context": [
        {
          "command": "htmlbrowser.openInBrowser",
          "group": "navigation",
          "when": "resourceExtname == .html"
        }
      ],
      "editor/title": [
        {
          "command": "htmlbrowser.openInBrowser",
          "when": "resourceLangId == html",
          "group": "navigation"
        }
      ],
      "editor/context": [
        {
          "command": "htmlbrowser.openInBrowser",
          "when": "resourceLangId == html",
          "group": "navigation"
        }
      ]
    },
    "configuration": {
      "title": "HTML Browser",
      "properties": {
        "htmlbrowser.openInDefaultBrowser": {
          "type": "boolean",
          "default": true,
          "description": "Open HTML files in default system browser"
        },
        "htmlbrowser.showFilePath": {
          "type": "boolean",
          "default": false,
          "description": "Show file path in notification"
        }
      }
    }
  }
}
EOL

# Create extension.js - PLAIN JAVASCRIPT VERSION (NO TYPESCRIPT)
cat << 'EOL' > extension.js
const vscode = require('vscode');
const os = require('os');
const path = require('path');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

function activate(context) {
    console.log('✅ HTML Browser extension activated!');

    // Register the command
    const disposable = vscode.commands.registerCommand('htmlbrowser.openInBrowser', async (resource) => {
        let filePath;

        // Determine which file to open
        if (resource) {
            // If called from context menu with a file
            filePath = resource.fsPath;
        } else if (vscode.window.activeTextEditor) {
            // If called from editor title bar or command palette
            filePath = vscode.window.activeTextEditor.document.uri.fsPath;
        } else {
            vscode.window.showWarningMessage('Please open an HTML file first.');
            return;
        }

        // Check if file is HTML
        if (!filePath.toLowerCase().endsWith('.html') && !filePath.toLowerCase().endsWith('.htm')) {
            vscode.window.showErrorMessage('Only HTML files can be opened in browser.');
            return;
        }

        // Check if file exists
        try {
            await vscode.workspace.fs.stat(vscode.Uri.file(filePath));
        } catch {
            vscode.window.showErrorMessage(`File not found: ${filePath}`);
            return;
        }

        // Get configuration
        const config = vscode.workspace.getConfiguration('htmlbrowser');
        const showFilePath = config.get('showFilePath');
        const fileName = path.basename(filePath);

        // Show progress notification
        await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: `Opening ${fileName} in browser...`,
            cancellable: false
        }, async () => {
            try {
                // Open in browser based on OS
                await openInBrowser(filePath);
                
                // Show success message
                if (showFilePath) {
                    vscode.window.showInformationMessage(`✅ Opened: ${filePath}`, 'OK');
                } else {
                    vscode.window.showInformationMessage(`✅ ${fileName} opened in browser`, 'OK');
                }
            } catch (error) {
                vscode.window.showErrorMessage(`Failed to open in browser: ${error.message}`);
            }
        });
    });

    context.subscriptions.push(disposable);

    // Optional: Add status bar item
    const statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    statusBarItem.text = "$(globe) Browser";
    statusBarItem.tooltip = "Open current HTML file in browser";
    statusBarItem.command = 'htmlbrowser.openInBrowser';
    
    // Show status bar only when HTML file is active
    const updateStatusBar = () => {
        if (vscode.window.activeTextEditor && vscode.window.activeTextEditor.document.languageId === 'html') {
            statusBarItem.show();
        } else {
            statusBarItem.hide();
        }
    };

    updateStatusBar();
    context.subscriptions.push(statusBarItem);
    
    // Update status bar when active editor changes
    vscode.window.onDidChangeActiveTextEditor(updateStatusBar, null, context.subscriptions);
}

/**
 * Open file in default browser based on operating system
 */
async function openInBrowser(filePath) {
    const platform = os.platform();
    
    // Convert path to file:// URL for proper browser handling
    const fileUrl = `file://${filePath.replace(/\\/g, '/')}`;
    
    switch (platform) {
        case 'darwin': // macOS
            await execAsync(`open "${fileUrl}"`);
            break;
            
        case 'win32': // Windows
            await execAsync(`start "" "${fileUrl}"`);
            break;
            
        case 'linux': // Linux
            // Try various Linux browser open commands
            try {
                await execAsync(`xdg-open "${fileUrl}"`);
            } catch {
                try {
                    await execAsync(`gnome-open "${fileUrl}"`);
                } catch {
                    await execAsync(`kde-open "${fileUrl}"`);
                }
            }
            break;
            
        default:
            throw new Error(`Unsupported platform: ${platform}`);
    }
}

function deactivate() {}

module.exports = {
    activate,
    deactivate
};
EOL

# Create README.md
cat << 'EOL' > README.md
# HTML Browser Extension

Open HTML files in your default browser with one click!

## Features

- **Browser button** in editor title bar for HTML files
- **Browser option** in file explorer context menu for HTML files
- **Status bar indicator** when HTML file is active
- Opens in default system browser (Safari, Firefox, Chrome, Edge, etc.)
- Works on macOS, Windows, and Linux

## Usage

### Three ways to open HTML in browser:

1. **Editor Title Bar** - Click the "Browser" button when editing HTML files
2. **File Explorer** - Right-click any HTML file → "Browser"
3. **Command Palette** - Press `Ctrl+Shift+P` → "Browser"

## Requirements

- VS Code 1.60.0 or higher
- Any modern web browser installed
- HTML files with `.html` or `.htm` extension

## Installation

This extension is pre-built and ready to install. No Node.js required!

## Troubleshooting

If the browser doesn't open:
1. Make sure you have a default browser set in your OS
2. Check file permissions
3. Try opening the file manually first: `file:///path/to/your/file.html`

## License

MIT
EOL

# Create .vscodeignore
cat << 'EOL' > .vscodeignore
.vscode
.git
.gitignore
*.sh
README.md
media/logo.png.base64
EOL

echo -e "${GREEN}✅ Extension created in '$EXTNAME'${NC}"
echo -e "${YELLOW}📝 No Node.js required - extension is ready to use!${NC}"

# Package extension manually (no vsce needed)
echo -e "${CYAN}📦 Creating VSIX package...${NC}"

# Create a zip file that can be renamed to .vsix
cd ..
zip -r "${EXTNAME}.zip" "${EXTNAME}/" > /dev/null 2>&1
mv "${EXTNAME}.zip" "${EXTNAME}.vsix"

echo -e "${GREEN}✅ Created ${EXTNAME}.vsix${NC}"

# Installation instructions
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${PURPLE}📥 Installation Instructions:${NC}"
echo ""
echo "To install this extension:"
echo ""
echo "1. Open VS Code"
echo "2. Go to Extensions (Ctrl+Shift+X)"
echo "3. Click '...' menu in top-right"
echo "4. Select 'Install from VSIX...'"
echo "5. Choose: $(pwd)/${EXTNAME}.vsix"
echo ""
echo "Alternative command line method:"
echo "code --install-extension $(pwd)/${EXTNAME}.vsix"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ HTML Browser extension created successfully!${NC}"
echo ""
echo -e "${YELLOW}Usage after installation:${NC}"
echo "1. Open any HTML file in VS Code"
echo "2. Click the 'Browser' button in editor title bar"
echo "3. Or right-click HTML file → 'Browser'"
echo "4. Or use Command Palette (Ctrl+Shift+P) → 'Browser'"