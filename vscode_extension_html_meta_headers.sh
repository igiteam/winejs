#!/bin/bash

# ===============================================
# Meta Headers Manager VS Code Extension Generator
# ===============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Meta Headers Manager Extension Generator            ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Ask for extension name
read -p "Enter your extension folder name (default: meta-headers-manager): " EXTNAME
EXTNAME=${EXTNAME:-meta-headers-manager}

# Check if folder exists
if [ -d "$EXTNAME" ]; then
    read -p "Folder '$EXTNAME' already exists. Do you want to remove it? (y/N): " REMOVE
    REMOVE=${REMOVE:-N}
    if [[ "$REMOVE" == "y" || "$REMOVE" == "Y" ]]; then
        echo "Removing existing folder '$EXTNAME'..."
        rm -rf "$EXTNAME"
    else
        echo "Exiting to avoid overwriting existing folder."
        exit 1
    fi
fi

# Create folder structure
mkdir -p "$EXTNAME/src" "$EXTNAME/media" "$EXTNAME/scripts"
cd "$EXTNAME" || exit

# Download logo
echo -e "${CYAN}📥 Downloading logo...${NC}"
curl -s -o media/logo.png "https://cdn.sdappnet.cloud/rtx/images/htmlmetatags.png"

# Create package.json
cat << EOL > package.json
{
  "name": "$EXTNAME",
  "displayName": "Meta Headers Manager",
  "publisher": "songdropltd",
  "description": "Easily insert and manage HTML meta headers with SEO optimization",
  "icon": "media/logo.png",
  "version": "1.0.0",
  "engines": { "vscode": "^1.81.0" },
  "activationEvents": ["onCommand:meta-headers-manager.openPanel"],
  "main": "./out/extension.js",
  "scripts": {
    "compile": "tsc -p ./",
    "watch": "tsc -watch -p ./"
  },
  "devDependencies": {
    "typescript": "^5.9.2",
    "@types/node": "^20.6.2",
    "@types/vscode": "^1.81.0"
  },
  "contributes": {
    "commands": [
      {
        "command": "meta-headers-manager.openPanel",
        "title": "Manage Meta Headers",
        "category": "Meta Headers"
      }
    ],
    "menus": {
      "commandPalette": [
        {
          "command": "meta-headers-manager.openPanel",
          "when": "editorLangId == html || editorLangId == codecanvas"
        }
      ],
      "editor/context": [
        {
          "command": "meta-headers-manager.openPanel",
          "when": "editorLangId == html || editorLangId == codecanvas",
          "group": "navigation"
        }
      ]
    },
    "viewsContainers": {
      "activitybar": [
        {
          "id": "metaHeadersActivity",
          "title": "Meta Headers",
          "icon": "media/logo.png"
        }
      ]
    },
    "views": {
      "metaHeadersActivity": [
        {
          "id": "metaHeadersView",
          "name": "Meta Headers Manager",
          "type": "webview",
          "icon": "media/logo.png"
        }
      ]
    }
  }
}
EOL

# Create tsconfig.json
cat << EOL > tsconfig.json
{
  "compilerOptions": {
    "module": "commonjs",
    "target": "ES2020",
    "outDir": "out",
    "lib": ["ES2020", "DOM"],
    "sourceMap": true,
    "rootDir": "src",
    "strict": true,
    "types": ["node"]
  },
  "exclude": ["node_modules", ".vscode-test"]
}
EOL

# Create src/extension.ts
cat << 'EOL' > src/extension.ts
import * as vscode from 'vscode';
import { MetaHeadersPanel } from './webview';

export function activate(context: vscode.ExtensionContext) {
    // Register .codecanvas as HTML language
    vscode.languages.setLanguageConfiguration('codecanvas', {
        comments: {
            blockComment: ['<!--', '-->']
        },
        brackets: [
            ['<', '>']
        ],
        autoClosingPairs: [
            { open: '<', close: '>' },
            { open: '"', close: '"' },
            { open: "'", close: "'" }
        ]
    });
    // Register the webview panel
    const provider = new MetaHeadersPanel(context);
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider("metaHeadersView", provider)
    );

    // Register the command
    const disposable = vscode.commands.registerCommand('meta-headers-manager.openPanel', async () => {
        // This will open the sidebar view
        await vscode.commands.executeCommand('metaHeadersView.focus');
    });

    context.subscriptions.push(disposable);
}

export function deactivate() {}
EOL

# Create src/generate_html.ts
cat << 'EOL' > src/generate_html.ts
export function generateHtml(nonce: string, cspSource: string): string {
    return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta http-equiv="Content-Security-Policy" 
              content="default-src 'none'; style-src ${cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}';">
        <title>Meta Headers Manager</title>
        <style>
            body {
                font-family: var(--vscode-font-family);
                padding: 16px;
                background: var(--vscode-sideBar-background);
                color: var(--vscode-sideBar-foreground);
            }
            .header {
                display: flex;
                align-items: center;
                gap: 8px;
                margin-bottom: 16px;
            }
            .header h3 {
                margin: 0;
                color: var(--vscode-foreground);
            }
            .logo {
                width: 20px;
                height: 20px;
            }
            .form-group {
                margin-bottom: 12px;
            }
            label {
                display: block;
                margin-bottom: 4px;
                font-size: 12px;
                font-weight: 600;
                color: var(--vscode-foreground);
            }
            input, textarea {
                width: 100%;
                padding: 6px 8px;
                background: var(--vscode-input-background);
                color: var(--vscode-input-foreground);
                border: 1px solid var(--vscode-input-border);
                border-radius: 3px;
                font-size: 13px;
                box-sizing: border-box;
            }
            textarea {
                min-height: 60px;
                resize: vertical;
            }
            input:focus, textarea:focus {
                outline: 1px solid var(--vscode-focusBorder);
            }
            button {
                padding: 8px 16px;
                background: var(--vscode-button-background);
                color: var(--vscode-button-foreground);
                border: none;
                border-radius: 3px;
                cursor: pointer;
                font-size: 13px;
                width: 100%;
                margin-bottom: 8px;
            }
            button:hover {
                background: var(--vscode-button-hoverBackground);
            }
            button:disabled {
                opacity: 0.6;
                cursor: not-allowed;
            }
            button.secondary {
                background: var(--vscode-button-secondaryBackground);
                color: var(--vscode-button-secondaryForeground);
            }
            .status {
                margin: 12px 0;
                padding: 8px;
                border-radius: 3px;
                font-size: 12px;
                min-height: 16px;
            }
            .success {
                background: var(--vscode-inputValidation-infoBackground);
                border: 1px solid var(--vscode-inputValidation-infoBorder);
                color: white;
            }
            .error {
                background: var(--vscode-inputValidation-errorBackground);
                border: 1px solid var(--vscode-inputValidation-errorBorder);
                color: white;

            }
            .info {
                background: var(--vscode-textBlockQuote-background);
                border: 1px solid var(--vscode-textBlockQuote-border);
                color: white;
                padding: 8px;
                border-radius: 3px;
                margin: 12px 0;
                font-size: 11px;
            }
            .loader {
                display: none;
                width: 16px;
                height: 16px;
                border: 2px solid var(--vscode-foreground);
                border-top: 2px solid transparent;
                border-radius: 50%;
                animation: spin 1s linear infinite;
                margin: 8px auto;
            }
            @keyframes spin {
                0% { transform: rotate(0deg); }
                100% { transform: rotate(360deg); }
            }
            .file-info {
                background: var(--vscode-input-background);
                border: 1px solid var(--vscode-input-border);
                color: white;
                padding: 8px;
                border-radius: 3px;
                margin: 12px 0;
                font-size: 12px;
            }
            .button-group {
                display: flex;
                gap: 8px;
            }
            .button-group button {
                flex: 1;
            }
        </style>
    </head>
    <body>
        <div class="header">
            <h3>Meta Headers Manager</h3>
        </div>
        
        <div class="file-info" id="fileInfo">
            No HTML file active
        </div>
        
        <div class="form-group">
            <label for="title">Title:</label>
            <input type="text" id="title" placeholder="Page title">
        </div>
        
        <div class="form-group">
            <label for="description">Description:</label>
            <textarea id="description" placeholder="Page description"></textarea>
        </div>
        
        <div class="form-group">
            <label for="faviconUrl">Favicon URL (PNG):</label>
            <input type="text" id="faviconUrl" placeholder="https://example.com/favicon.png">
        </div>

        <div class="form-group">
            <label for="imageUrl">Image URL:</label>
            <input type="text" id="imageUrl" placeholder="https://example.com/image.png">
        </div>
        
        <div class="form-group">
            <label for="keywords">Keywords:</label>
            <textarea id="keywords" placeholder="keyword1, keyword2, keyword3"></textarea>
        </div>
        
        <div class="form-group" style="display: none">
            <label for="url">Page URL:</label>
            <input type="text" id="url" placeholder="https://example.com/page.html" value="">
        </div>

        <div class="button-group">
            <button id="readBtn">Read Headers</button>
            <button id="updateBtn">Update Headers</button>
        </div>
        
        <div class="loader" id="loader"></div>
        
        <div class="status" id="status"></div>
        
        <div class="info">
            <strong>Supported Meta Tags:</strong><br>
            • HTML Meta Tags (description)<br>
            • Google / Search Engine Tags<br>
            • Facebook Open Graph Tags<br>
            • Twitter Card Tags<br>
            • Additional SEO keywords
        </div>

        <script nonce="${nonce}">
            const vscode = acquireVsCodeApi();
            const titleInput = document.getElementById('title');
            const descriptionInput = document.getElementById('description');
            const faviconUrlInput = document.getElementById('faviconUrl');
            const imageUrlInput = document.getElementById('imageUrl');
            const keywordsInput = document.getElementById('keywords');
            const urlInput = document.getElementById('url'); 
            const readBtn = document.getElementById('readBtn');
            const updateBtn = document.getElementById('updateBtn');
            const loader = document.getElementById('loader');
            const status = document.getElementById('status');
            const fileInfo = document.getElementById('fileInfo');

            readBtn.addEventListener('click', () => {
                readBtn.disabled = true;
                loader.style.display = 'block';
                status.textContent = 'Reading meta headers...';
                status.className = 'status';
                
                vscode.postMessage({
                    command: 'readMetaHeaders'
                });
            });

            updateBtn.addEventListener('click', () => {
                const data = {
                    title: titleInput.value,
                    description: descriptionInput.value,
                    faviconUrl: faviconUrlInput.value,
                    imageUrl: imageUrlInput.value,
                    keywords: keywordsInput.value,
                    url: urlInput.value
                };
                
                updateBtn.disabled = true;
                loader.style.display = 'block';
                status.textContent = 'Updating meta headers...';
                status.className = 'status';
                
                vscode.postMessage({
                    command: 'updateMetaHeaders',
                    data: data
                });
            });

            // Handle messages from extension
            window.addEventListener('message', event => {
                const message = event.data;
                
                switch (message.command) {
                    case 'updateFileInfo':
                        fileInfo.textContent = message.text;
                        const isSupportedFile = message.isHtmlFile; // Renamed
                        readBtn.disabled = !isSupportedFile;
                        updateBtn.disabled = !isSupportedFile;
                        if (isSupportedFile) {
                            fileInfo.style.background = 'var(--vscode-inputValidation-infoBackground)';
                        } else {
                            fileInfo.style.background = 'var(--vscode-input-background)';
                        }
                        break;
                        
                    case 'metaHeadersData':
                        titleInput.value = message.data.title || '';
                        descriptionInput.value = message.data.description || '';
                        faviconUrlInput.value = message.data.faviconUrl || '';
                        imageUrlInput.value = message.data.imageUrl || '';
                        keywordsInput.value = message.data.keywords || '';
                        urlInput.value = message.data.url || '';

                        readBtn.disabled = false;
                        updateBtn.disabled = false;
                        loader.style.display = 'none';
                        status.textContent = '✅ Meta headers loaded successfully';
                        status.className = 'status success';
                        break;
                        
                    case 'updateSuccess':
                        updateBtn.disabled = false;
                        loader.style.display = 'none';
                        status.textContent = '✅ ' + message.text;
                        status.className = 'status success';
                        break;
                        
                    case 'updateError':
                        readBtn.disabled = false;
                        updateBtn.disabled = false;
                        loader.style.display = 'none';
                        status.textContent = '❌ ' + message.text;
                        status.className = 'status error';
                        break;
                }
            });

            // Request initial file info
            vscode.postMessage({ command: 'getFileInfo' });
        </script>
    </body>
    </html>
    `;
}
EOL

# Create src/webview.ts
cat << 'EOL' > src/webview.ts
import * as vscode from 'vscode';
import * as path from 'path';
import { generateHtml } from './generate_html';

interface MetaHeadersData {
    title: string;
    description: string;
    faviconUrl: string;
    imageUrl: string;
    keywords: string;
    url: string;
}

export class MetaHeadersPanel implements vscode.WebviewViewProvider {
    private _view?: vscode.WebviewView;

    constructor(private readonly context: vscode.ExtensionContext) {}

    resolveWebviewView(webviewView: vscode.WebviewView, _context: vscode.WebviewViewResolveContext, _token: vscode.CancellationToken) {
        this._view = webviewView;
        webviewView.webview.options = { enableScripts: true };

        const nonce = this.getNonce();
        const cspSource = webviewView.webview.cspSource;
        webviewView.webview.html = generateHtml(nonce, cspSource);

        webviewView.webview.onDidReceiveMessage(async message => {
            switch (message.command) {
                case 'readMetaHeaders':
                    await this.readMetaHeaders();
                    break;
                case 'updateMetaHeaders':
                    await this.updateMetaHeaders(message.data);
                    break;
                case 'getFileInfo':
                    this.updateFileInfo();
                    break;
            }
        });

        // Listen for active editor changes
        vscode.window.onDidChangeActiveTextEditor(() => {
            this.updateFileInfo();
        });

        // Initial update
        this.updateFileInfo();
    }

    private updateFileInfo() {
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            this._view?.webview.postMessage({
                command: 'updateFileInfo',
                text: 'No file active',
                isHtmlFile: false
            });
            return;
        }

        const filePath = editor.document.fileName;
        const isHtmlFile = filePath.endsWith('.html');
        const isCodeCanvasFile = filePath.endsWith('.codecanvas');
        const isSupportedFile = isHtmlFile || isCodeCanvasFile;
            
        this._view?.webview.postMessage({
            command: 'updateFileInfo',
            text: isSupportedFile 
                ? `Active file: ${path.basename(filePath)} (${filePath.endsWith('.codecanvas') ? 'CodeCanvas' : 'HTML'})` 
                : `Not a supported file: ${path.basename(filePath)}`,
            isHtmlFile: isSupportedFile  // Rename this to isSupportedFile for clarity
        });
    }

    private async readMetaHeaders() {
        const editor = vscode.window.activeTextEditor;
        
        if (!editor) {
            this._view?.webview.postMessage({
                command: 'updateError',
                text: 'No active editor found!'
            });
            return;
        }

        const document = editor.document;
        const filePath = document.fileName;
        
        // Check if it's an HTML or CODECANVAS file
        if (!filePath.endsWith('.html') && !filePath.endsWith('.codecanvas')) {
            this._view?.webview.postMessage({
                command: 'updateError',
                text: 'This command only works with .html or .codecanvas files!'
            });
            return;
        }

        try {
            const content = document.getText();
            const metaData = this.extractMetaHeaders(content);
            
            this._view?.webview.postMessage({
                command: 'metaHeadersData',
                data: metaData
            });
            
        } catch (error: any) {
            this._view?.webview.postMessage({
                command: 'updateError',
                text: `Error reading meta headers: ${error.message}`
            });
        }
    }

    private async updateMetaHeaders(data: MetaHeadersData) {
        const editor = vscode.window.activeTextEditor;
        
        if (!editor) {
            this._view?.webview.postMessage({
                command: 'updateError',
                text: 'No active editor found!'
            });
            return;
        }

        const document = editor.document;
        const filePath = document.fileName;
        
        // Check if it's a supported file
        if (!filePath.endsWith('.html') && !filePath.endsWith('.codecanvas')) {
            this._view?.webview.postMessage({
                command: 'updateError',
                text: 'This command only works with .html or .codecanvas files!'
            });
            return;
        }

        try {
            const content = document.getText();
            const newContent = this.updateMetaHeadersInContent(content, data);
            
            // Apply the edits
            const edit = new vscode.WorkspaceEdit();
            const fullRange = new vscode.Range(
                document.positionAt(0),
                document.positionAt(content.length)
            );
            edit.replace(document.uri, fullRange, newContent);
            
            await vscode.workspace.applyEdit(edit);
            await document.save();
            
            this._view?.webview.postMessage({
                command: 'updateSuccess',
                text: 'Meta headers updated successfully!'
            });
            
        } catch (error: any) {
            this._view?.webview.postMessage({
                command: 'updateError',
                text: `Error updating meta headers: ${error.message}`
            });
        }
    }

    private extractMetaHeaders(content: string): MetaHeadersData {
        const metaData: MetaHeadersData = {
            title: '',
            description: '',
            faviconUrl: '',
            imageUrl: '',
            keywords: '',
            url: ''
        };

        // Extract title
        const titleMatch = content.match(/<title>(.*?)<\/title>/i);
        if (titleMatch) {
            metaData.title = titleMatch[1];
        }

        // Extract description
        const descMatch = content.match(/<meta\s+name="description"\s+content="(.*?)"/i);
        if (descMatch) {
            metaData.description = descMatch[1];
        }

        // Extract favicon URL
        const faviconMatch = content.match(/<link\s+rel="(?:shortcut )?icon"\s+(?:type="[^"]*"\s+)?href="(.*?)"/i);
        if (faviconMatch) {
            metaData.faviconUrl = faviconMatch[1];
        }

        // Extract image URL
        const imageMatch = content.match(/<meta\s+(property="og:image"|itemprop="image"|name="twitter:image")\s+content="(.*?)"/i);
        if (imageMatch) {
            metaData.imageUrl = imageMatch[2];
        }

        // Extract keywords
        const keywordsMatch = content.match(/<meta\s+name="keywords"\s+content="(.*?)"/i);
        if (keywordsMatch) {
            metaData.keywords = keywordsMatch[1];
        }

        // Extract URL from og:url or canonical
        const urlMatch = content.match(/<meta\s+(property="og:url"|name="canonical")\s+(?:content|href)="(.*?)"/i);
        if (urlMatch) {
            metaData.url = urlMatch[2];
        }

        return metaData;
    }

    private updateMetaHeadersInContent(content: string, data: MetaHeadersData): string {
        let newContent = content;

        // Update or add title
        const titleRegex = /<title>.*?<\/title>/i;
        const newTitle = `<title>${data.title}</title>`;
        if (titleRegex.test(newContent)) {
            newContent = newContent.replace(titleRegex, newTitle);
        } else {
            // Insert after <head> if no title exists
            const headRegex = /<head[^>]*>/i;
            newContent = newContent.replace(headRegex, `$&\n    ${newTitle}`);
        }

        // Update or add meta tags
        const metaTags = this.generateMetaTags(data);
        
        // Remove existing meta tags we're going to replace
        const metaTagRegexes = [
            /<meta\s+name="description".*?>/gi,
            /<meta\s+name="keywords".*?>/gi,
            /<meta\s+itemprop="name".*?>/gi,
            /<link\s+rel="(?:shortcut )?icon".*?>/gi,
            /<meta\s+itemprop="description".*?>/gi,
            /<meta\s+itemprop="image".*?>/gi,
            /<meta\s+property="og:title".*?>/gi,
            /<meta\s+property="og:description".*?>/gi,
            /<meta\s+property="og:image".*?>/gi,
            /<meta\s+property="og:url".*?>/gi,
            /<meta\s+property="og:type".*?>/gi,
            /<meta\s+name="twitter:title".*?>/gi,
            /<meta\s+name="twitter:description".*?>/gi,
            /<meta\s+name="twitter:image".*?>/gi,
            /<meta\s+name="twitter:card".*?>/gi
        ];

        // Remove meta tags and clean up the blank lines they leave behind
        metaTagRegexes.forEach(regex => {
            newContent = newContent.replace(regex, (match) => {
                // Replace with empty string and also try to remove the newline before it
                return '';
            });
        });

        // Clean up multiple consecutive blank lines
        newContent = newContent.replace(/\n\s*\n\s*\n/g, '\n\n');

        // Add new meta tags after title
        const titlePosition = newContent.indexOf('</title>');
        if (titlePosition !== -1) {
            // Find the next non-whitespace character after </title>
            let insertPosition = titlePosition + 8;
            while (insertPosition < newContent.length && 
                (newContent[insertPosition] === ' ' || 
                    newContent[insertPosition] === '\t' || 
                    newContent[insertPosition] === '\n')) {
                insertPosition++;
            }
            
            newContent = newContent.slice(0, insertPosition) + 
                        '\n' + metaTags + 
                        newContent.slice(insertPosition);
        } else {
            // If no title, add after head
            const headPosition = newContent.indexOf('<head>');
            if (headPosition !== -1) {
                let insertPosition = headPosition + 6;
                while (insertPosition < newContent.length && 
                    (newContent[insertPosition] === ' ' || 
                        newContent[insertPosition] === '\t' || 
                        newContent[insertPosition] === '\n')) {
                    insertPosition++;
                }
                
                newContent = newContent.slice(0, insertPosition) + 
                            '\n' + metaTags + 
                            newContent.slice(insertPosition);
            }
        }

        // Final cleanup of excessive blank lines
        newContent = newContent.replace(/\n\s*\n\s*\n/g, '\n\n');
        
        return newContent;
    }

    private generateMetaTags(data: MetaHeadersData): string {
        const tags = [];

        // HTML Meta Tags
        if (data.description) {
            tags.push(`<meta name="description" content="${data.description}">`);
        }
        if (data.keywords) {
            tags.push(`<meta name="keywords" content="${data.keywords}">`);
        }
        // Favicon
        if (data.faviconUrl) {
            tags.push(`<link rel="icon" href="${data.faviconUrl}" type="image/png">`);
            // Generate Apple Touch Icon from favicon
            tags.push(`<link rel="apple-touch-icon" href="${data.faviconUrl}" sizes="180x180">`);
            // Generate Android icons from favicon
            tags.push(`<link rel="icon" type="image/png" href="${data.faviconUrl}" sizes="192x192">`);
            tags.push(`<link rel="icon" type="image/png" href="${data.faviconUrl}" sizes="512x512">`);
        }
        // Google / Search Engine Tags
        if (data.title) {
            tags.push(`<meta itemprop="name" content="${data.title}">`);
        }
        if (data.description) {
            tags.push(`<meta itemprop="description" content="${data.description}">`);
        }
        if (data.imageUrl) {
            tags.push(`<meta itemprop="image" content="${data.imageUrl}">`);
        }
        // Facebook Meta Tags
        if (data.title) {
            tags.push(`<meta property="og:title" content="${data.title}">`);
        }
        if (data.description) {
            tags.push(`<meta property="og:description" content="${data.description}">`);
        }
        if (data.imageUrl) {
            tags.push(`<meta property="og:image" content="${data.imageUrl}">`);
        }
        tags.push(`<meta property="og:url" content="${data.url}">`);
        tags.push('<meta property="og:type" content="website">');

        // Twitter Meta Tags
        if (data.title) {
            tags.push(`<meta name="twitter:title" content="${data.title}">`);
        }
        if (data.description) {
            tags.push(`<meta name="twitter:description" content="${data.description}">`);
        }
        if (data.imageUrl) {
            tags.push(`<meta name="twitter:image" content="${data.imageUrl}">`);
        }
        tags.push('<meta name="twitter:card" content="summary_large_image">');

        return tags.map(tag => `    ${tag}`).join('\n');
    }

    private getNonce(): string {
        return Math.random().toString(36).substring(2, 15);
    }
}
EOL

# Create requirements.txt (empty for this extension)
cat << EOL > requirements.txt
# No Python dependencies needed for this extension
EOL

# Create README.md
cat << EOL > README.md
# Meta Headers Manager VS Code Extension

Easily insert and manage HTML meta headers with SEO optimization.

## Features

- Read existing meta headers from HTML files
- Update meta headers with a simple form
- Supports multiple meta tag types:
  - HTML Meta Tags (description, keywords)
  - Google / Search Engine Tags
  - Facebook Open Graph Tags
  - Twitter Card Tags
- Real-time preview of active HTML file
- Sidebar interface for easy access

## Supported File Types

- .html - Standard HTML files
- .codecanvas - CodeCanvas files (visual representation of README.md)

## Usage

1. Open an HTML file in VS Code
2. Use the sidebar "Meta Headers Manager" panel OR
3. Press Ctrl+Shift+P and type "Manage Meta Headers"
4. Click "Read Headers" to load existing meta data
5. Modify the fields and click "Update Headers"

## Supported Meta Tags

- **Title**: Page title for all platforms
- **Description**: Page description for SEO and social sharing
- **Image URL**: Featured image for social media previews
- **Keywords**: SEO keywords for search engines

## Requirements

- VS Code 1.81.0 or later
- HTML files with proper structure
EOL

# Create .vscodeignore
cat << EOL > .vscodeignore
node_modules
.vscode
*.ts
*.map
.git
.gitignore
src
EOL

# Create LICENSE.md
cat << EOL > LICENSE.md
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

VSIX_FILE=$(ls $EXTNAME-*.vsix 2>/dev/null | head -n1)

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

echo -e "${GREEN}✅ Meta Headers Manager extension installed successfully!${NC}"
echo -e "${YELLOW}🚀 Usage: Open an HTML file and use the 'Meta Headers Manager' sidebar or command palette${NC}"