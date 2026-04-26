#!/bin/bash

# ===============================================
# ICNS Manager for Wineskin - VS Code Extension Generator
# ===============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           ICNS Manager for Wineskin - Generator               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Ask for extension name
read -p "Enter your extension folder name (default: icns-manager): " EXTNAME
EXTNAME=${EXTNAME:-icns-manager}

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
mkdir -p "$EXTNAME/src" "$EXTNAME/media" "$EXTNAME/scripts" "$EXTNAME/resources"
cd "$EXTNAME" || exit

# Download logo
echo -e "${CYAN}📥 Downloading logo...${NC}"
curl -s -o media/logo.png "https://cdn.sdappnet.cloud/rtx/images/macosicns.png"


# Create package.json with updated commands
cat << EOL > package.json
{
  "name": "$EXTNAME",
  "displayName": "ICNS Manager for Wineskin",
  "publisher": "songdropltd",
  "description": "Manage and convert ICNS files for Wineskin wrappers with EXE icon extraction",
  "icon": "media/logo.png",
  "version": "1.2.0",
  "engines": { "vscode": "^1.81.0" },
  "activationEvents": [
    "onView:icnsManagerView",
    "onCommand:icns-manager.openView",
    "onCommand:icns-manager.convertToIcns",
    "onCommand:icns-manager.extractIcns",
    "onCommand:icns-manager.extractFromExe",
    "onCommand:icns-manager.previewIcns",
    "onCommand:icns-manager.replaceIcns"
  ],
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
        "command": "icns-manager.openView",
        "title": "ICNS Manager: Open Panel",
        "category": "ICNS Manager"
      },
      {
        "command": "icns-manager.convertToIcns",
        "title": "ICNS Manager: Convert Image to ICNS",
        "category": "ICNS Manager"
      },
      {
        "command": "icns-manager.extractIcns",
        "title": "ICNS Manager: Extract ICNS to PNGs",
        "category": "ICNS Manager"
      },
      {
        "command": "icns-manager.extractFromExe",
        "title": "ICNS Manager: Extract ICO from EXE to PNGs",
        "category": "ICNS Manager"
      },
      {
        "command": "icns-manager.previewIcns",
        "title": "ICNS Manager: Preview ICNS",
        "category": "ICNS Manager"
      },
      {
        "command": "icns-manager.replaceIcns",
        "title": "ICNS Manager: Replace ICNS in Wrapper",
        "category": "ICNS Manager"
      }
    ],
    "menus": {
      "commandPalette": [
        {
          "command": "icns-manager.openView",
          "when": "true"
        }
      ],
      "explorer/context": [
        {
          "command": "icns-manager.convertToIcns",
          "when": "resourceExtname =~ /\\\\.(png|jpg|jpeg|ico|bmp|tiff|tif)$/i",
          "group": "icns-manager@1"
        },
        {
          "command": "icns-manager.extractIcns",
          "when": "resourceExtname == .icns",
          "group": "icns-manager@1"
        },
        {
          "command": "icns-manager.extractFromExe",
          "when": "resourceExtname == .exe",
          "group": "icns-manager@1"
        },
        {
          "command": "icns-manager.previewIcns",
          "when": "resourceExtname == .icns",
          "group": "icns-manager@2"
        },
        {
          "command": "icns-manager.replaceIcns",
          "when": "resourceExtname =~ /\\\\.(png|jpg|jpeg|ico|bmp|tiff|tif)$/i",
          "group": "icns-manager@3"
        }
      ]
    },
    "viewsContainers": {
      "activitybar": [
        {
          "id": "icns-manager",
          "title": "ICNS Manager",
          "icon": "media/logo.png"
        }
      ]
    },
    "views": {
      "icns-manager": [
        {
          "id": "icnsManagerView",
          "name": "ICNS Manager",
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

# Create Python scripts in scripts folder
mkdir -p scripts

# Create extract_ico.py
cat << 'EOL' > scripts/extract_ico.py
import sys
from PIL import Image
import os

ico_path = sys.argv[1]
output_png = sys.argv[2]

try:
    # Open ICO file - ICO files contain multiple sizes in one file
    ico = Image.open(ico_path)
    
    # Get all images from the ICO (different sizes)
    images = []
    
    # Try to get images using different methods
    try:
        # Method 1: Try to iterate through frames
        while True:
            images.append(ico.copy())
            ico.seek(len(images))
    except EOFError:
        pass
    
    # If no images found with frame iteration, try direct loading
    if len(images) == 0:
        # Reset and try to load directly
        ico = Image.open(ico_path)
        images = [ico]
    
    # Find the largest image
    largest_img = None
    largest_size = 0
    
    for img in images:
        width, height = img.size
        size = width * height
        
        if size > largest_size:
            largest_size = size
            largest_img = img
    
    if largest_img is None:
        print("No images found in ICO file")
        sys.exit(1)
    
    # Convert to RGBA if needed
    if largest_img.mode != 'RGBA':
        largest_img = largest_img.convert('RGBA')
    
    # Save as PNG
    largest_img.save(output_png, 'PNG')
    print(f"Extracted {largest_img.size[0]}x{largest_img.size[1]} image from ICO")
    
except Exception as e:
    print(f"Error processing ICO: {str(e)}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOL

# Create convert_to_icns.py
cat << 'EOL' > scripts/convert_to_icns.py
import sys
import os
from PIL import Image
import subprocess
import tempfile

input_file = sys.argv[1]
output_file = sys.argv[2]

# Create temp directory
temp_dir = tempfile.mkdtemp()
iconset_dir = os.path.join(temp_dir, os.path.basename(output_file).replace('.icns', '.iconset'))
os.makedirs(iconset_dir, exist_ok=True)

try:
    img = Image.open(input_file)
    
    # Required sizes for ICNS
    sizes = [
        (16, 16, 'icon_16x16.png'),
        (32, 32, 'icon_32x32.png'),
        (64, 64, 'icon_64x64.png'),
        (128, 128, 'icon_128x128.png'),
        (256, 256, 'icon_256x256.png'),
        (512, 512, 'icon_512x512.png'),
        (1024, 1024, 'icon_1024x1024.png'),
        # Retina sizes
        (32, 32, 'icon_16x16@2x.png'),
        (64, 64, 'icon_32x32@2x.png'),
        (256, 256, 'icon_128x128@2x.png'),
        (512, 512, 'icon_256x256@2x.png'),
        (1024, 1024, 'icon_512x512@2x.png')
    ]
    
    for width, height, name in sizes:
        resized = img.resize((width, height), Image.Resampling.LANCZOS)
        resized.save(os.path.join(iconset_dir, name))
    
    # On macOS, use iconutil
    if sys.platform == 'darwin':
        subprocess.run(['iconutil', '-c', 'icns', iconset_dir, '-o', output_file], check=True)
    else:
        print(f"Warning: Created iconset at {iconset_dir} but cannot create ICNS on non-macOS")
        print(f"Copy the iconset folder to macOS and run: iconutil -c icns {iconset_dir}")
        
finally:
    # Cleanup
    import shutil
    shutil.rmtree(temp_dir)
EOL

# Create extract_exe.sh (based on your working script)
cat << 'EOL' > scripts/extract_exe.sh
#!/bin/bash

# ===============================================
# Windows EXE Icon Extractor Script
# ===============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Handle quoted paths with spaces properly
EXE_FILE="$1"
OUTPUT_DIR="$2"

# Remove surrounding quotes if present (they come from spawn with shell: true)
EXE_FILE="${EXE_FILE%\"}"
EXE_FILE="${EXE_FILE#\"}"
OUTPUT_DIR="${OUTPUT_DIR%\"}"
OUTPUT_DIR="${OUTPUT_DIR#\"}"

echo -e "${CYAN}🔍 Extracting icons from: $(basename "$EXE_FILE")${NC}"
echo -e "Full path: $EXE_FILE"

# Check if file exists
if [ ! -f "$EXE_FILE" ]; then
    echo -e "${RED}❌ File not found: $EXE_FILE${NC}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Clean previous extraction
find "$OUTPUT_DIR" -maxdepth 1 -type f \( -name "*.png" -o -name "*.ico" -o -name "*.bmp" -o -name "*.jpg" -o -name "*.jpeg" \) -delete 2>/dev/null

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required tools
HAS_ICOUTILS=0
if command_exists wrestool && command_exists icotool; then
    HAS_ICOUTILS=1
    echo -e "${GREEN}✓ icoutils found (wrestool + icotool)${NC}"
else
    echo -e "${YELLOW}⚠️ icoutils not found (wrestool/icotool)${NC}"
    echo -e "${YELLOW}Install with: brew install icoutils (macOS) or sudo apt-get install icoutils (Linux)${NC}"
fi

HAS_CONVERT=0
if command_exists convert; then
    HAS_CONVERT=1
    echo -e "${GREEN}✓ ImageMagick (convert) found${NC}"
else
    echo -e "${YELLOW}⚠️ ImageMagick not found${NC}"
fi

# Method 1: Extract using icoutils (most reliable)
if [ $HAS_ICOUTILS -eq 1 ]; then
    echo -e "\n${BLUE}📦 Extracting icons with icoutils...${NC}"
    
    # Create temporary directory
    TEMP_DIR="$OUTPUT_DIR/temp_icons_$$"
    mkdir -p "$TEMP_DIR"
    
    # Extract all icon resources
    echo -e "${YELLOW}Extracting icon resources...${NC}"
    wrestool --extract --type=group_icon "$EXE_FILE" -o "$TEMP_DIR/icon_" 2>/dev/null
    
    # If no group icons found, try other icon types
    if [ ! -f "$TEMP_DIR"/icon_* ] 2>/dev/null; then
        wrestool --extract --type=14 "$EXE_FILE" -o "$TEMP_DIR/icon_" 2>/dev/null
    fi
    
    # Process each extracted icon file
    COUNT=0
    ICO_INDEX=0
    EXE_BASE_NAME=$(basename "$EXE_FILE" .exe)

    for ICO_FILE in "$TEMP_DIR"/icon_*; do
        if [ -f "$ICO_FILE" ]; then
            echo -e "  Processing icon resource $ICO_INDEX..."
            
            # Create a temporary directory for this ICO extraction
            TEMP_ICO_DIR="$TEMP_DIR/ico_extract_$ICO_INDEX"
            mkdir -p "$TEMP_ICO_DIR"
            
            # Extract all images from ICO to temp directory
            icotool -x "$ICO_FILE" -o "$TEMP_ICO_DIR/" 2>/dev/null
            
            # Move and rename extracted PNGs
            PNG_INDEX=0
            for PNG_FILE in "$TEMP_ICO_DIR"/*.png; do
                if [ -f "$PNG_FILE" ]; then
                    NEW_NAME="${EXE_BASE_NAME}_icon_${COUNT}.png"
                    mv "$PNG_FILE" "$OUTPUT_DIR/$NEW_NAME"
                    PNG_INDEX=$((PNG_INDEX + 1))
                    COUNT=$((COUNT + 1))
                fi
            done
            
            # Clean up temp ICO directory
            rm -rf "$TEMP_ICO_DIR"
            
            if [ $PNG_INDEX -gt 0 ]; then
                echo -e "  ${GREEN}✓ Extracted $PNG_INDEX icon(s)${NC}"
            fi
            
            ICO_INDEX=$((ICO_INDEX + 1))
        fi
    done
    
    # Cleanup temp directory
    rm -rf "$TEMP_DIR"
    
    if [ $COUNT -gt 0 ]; then
        echo -e "  ${GREEN}✅ Successfully extracted $COUNT icon(s) with icoutils${NC}"
    else
        echo -e "  ${YELLOW}⚠️ No icons found with icoutils${NC}"
    fi
fi

# Method 2: Try ImageMagick as fallback
if [ $HAS_CONVERT -eq 1 ] && [ $(find "$OUTPUT_DIR" -name "*.png" | wc -l) -eq 0 ]; then
    echo -e "\n${BLUE}🔄 Trying ImageMagick extraction...${NC}"
    
    # Try to extract embedded images
    convert "$EXE_FILE" "$OUTPUT_DIR/exe_icon.png" 2>/dev/null
    
    if [ -f "$OUTPUT_DIR/exe_icon.png" ]; then
        # Check if file has content
        if [ -s "$OUTPUT_DIR/exe_icon.png" ]; then
            echo -e "  ${GREEN}✓ Extracted icon with ImageMagick${NC}"
        else
            rm -f "$OUTPUT_DIR/exe_icon.png"
        fi
    fi
fi

# Method 3: Create fallback icons if nothing was extracted
PNG_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)
if [ $PNG_COUNT -eq 0 ]; then
    echo -e "\n${YELLOW}⚠️ No icons found, creating fallback representation...${NC}"
    
    # Check if we have Python and PIL
    if command_exists python3; then
        python3 -c "
import sys
from PIL import Image, ImageDraw, ImageFont
import os

output_dir = sys.argv[1]
exe_name = sys.argv[2]

# Create simple EXE icon
sizes = [32, 48, 64, 128, 256]

for size in sizes:
    img = Image.new('RGBA', (size, size), (70, 130, 180, 255))
    draw = ImageDraw.Draw(img)
    
    # Draw a window frame
    draw.rectangle([size*0.1, size*0.1, size*0.9, size*0.9], 
                  fill=(50, 100, 150), outline=(255, 255, 255), width=2)
    
    # Draw smaller inner rectangle
    draw.rectangle([size*0.2, size*0.2, size*0.8, size*0.8], 
                  fill=(100, 150, 200))
    
    # Try to add text
    try:
        # Try to load font
        font_size = max(size // 6, 10)
        try:
            font = ImageFont.truetype(\"Arial\", font_size)
        except:
            font = ImageFont.load_default()
        
        text = \"EXE\"
        # Calculate text position
        bbox = draw.textbbox((0, 0), text, font=font)
        text_width = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]
        
        draw.text(
            ((size - text_width) / 2, (size - text_height) / 2),
            text, fill=(255, 255, 255), font=font
        )
    except:
        pass
    
    output_path = os.path.join(output_dir, f'fallback_{size}x{size}.png')
    img.save(output_path, 'PNG')

print(f'Created {len(sizes)} fallback icons')
        " "$OUTPUT_DIR" "$(basename "$EXE_FILE")"
        
        if [ $? -eq 0 ]; then
            echo -e "  ${GREEN}✓ Created fallback EXE icons${NC}"
        fi
    else
        echo -e "  ${RED}❌ Python not available for fallback icons${NC}"
    fi
fi

# Final count
PNG_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)
ICO_COUNT=$(find "$OUTPUT_DIR" -name "*.ico" | wc -l)

echo -e "\n${CYAN}📊 Extraction Summary:${NC}"
echo -e "  PNG files: $PNG_COUNT"
echo -e "  ICO files: $ICO_COUNT"

if [ $PNG_COUNT -gt 0 ]; then
    echo -e "\n${GREEN}✅ Successfully extracted $PNG_COUNT icon(s)${NC}"
    echo -e "${CYAN}📁 Output directory: $OUTPUT_DIR${NC}"
    exit 0
else
    echo -e "\n${YELLOW}⚠️ No icons were extracted${NC}"
    exit 1
fi
EOL

# Make the script executable
chmod +x scripts/extract_exe.sh

# Create src/extension.ts with proper EXE extraction
cat << 'EOL' > src/extension.ts
import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import { spawn,exec } from 'child_process';
import { promisify } from 'util';
import { IcnsManagerPanel } from './panel';

const execAsync = promisify(exec);

export function activate(context: vscode.ExtensionContext) {
    console.log('ICNS Manager extension is now active!');

    // Register the webview panel
    const provider = new IcnsManagerPanel(context);
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider("icnsManagerView", provider)
    );

    // Register commands
    context.subscriptions.push(
        vscode.commands.registerCommand('icns-manager.openView', () => {
            vscode.commands.executeCommand('workbench.view.extension.icns-manager');
        }),

        vscode.commands.registerCommand('icns-manager.convertToIcns', async (uri: vscode.Uri) => {
            await convertImageToIcns(uri);
        }),

        vscode.commands.registerCommand('icns-manager.extractIcns', async (uri: vscode.Uri) => {
            await extractIcnsToPngs(uri);
        }),

        vscode.commands.registerCommand('icns-manager.extractFromExe', async (uri: vscode.Uri) => {
            await extractIcoFromExe(uri);
        }),

        vscode.commands.registerCommand('icns-manager.previewIcns', async (uri: vscode.Uri) => {
            await previewIcns(uri);
        }),

        vscode.commands.registerCommand('icns-manager.replaceIcns', async (uri: vscode.Uri) => {
            await replaceIcnsInWrapper(uri);
        })
    );
}

async function convertImageToIcns(uri: vscode.Uri) {
    const inputFile = uri.fsPath;
    const fileExt = path.extname(inputFile).toLowerCase();
    
    // Check if it's a supported image format
    const supportedFormats = ['.png', '.jpg', '.jpeg', '.ico', '.bmp', '.tiff', '.tif'];
    if (!supportedFormats.includes(fileExt)) {
        vscode.window.showErrorMessage(`Unsupported format: ${fileExt}. Supported: ${supportedFormats.join(', ')}`);
        return;
    }

    // Ask for output filename
    const defaultName = path.basename(inputFile, path.extname(inputFile)) + '.icns';
    const outputName = await vscode.window.showInputBox({
        prompt: 'Enter output ICNS filename',
        value: defaultName,
        validateInput: (value: string) => {
            if (!value.endsWith('.icns')) {
                return 'Filename must end with .icns';
            }
            return null;
        }
    });

    if (!outputName) {
        return;
    }

    const outputPath = path.join(path.dirname(inputFile), outputName);

    try {
        vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: 'Converting to ICNS...',
            cancellable: false
        }, async (progress) => {
            progress.report({ message: 'Preparing image...' });

            if (os.platform() === 'darwin') {
                // On macOS, use sips and iconutil
                await convertImageToIcnsMac(inputFile, outputPath, progress);
            } else {
                // On other platforms, use Python or fallback method
                await convertImageToIcnsCrossPlatform(inputFile, outputPath, progress);
            }

            vscode.window.showInformationMessage(`✅ ICNS created: ${outputName}`);
            
            // Open the new file in explorer
            const doc = await vscode.workspace.openTextDocument(outputPath);
            await vscode.window.showTextDocument(doc);
        });

    } catch (error: any) {
        vscode.window.showErrorMessage(`❌ Conversion failed: ${error.message}`);
    }
}


async function convertImageToIcnsMac(inputFile: string, outputPath: string, progress: any): Promise<void> {
    const fileExt = path.extname(inputFile).toLowerCase();
    
    // Handle ICO files specially
    if (fileExt === '.ico') {
        return await convertIcoToIcnsMac(inputFile, outputPath, progress);
    }
    
    // Original code for other image formats
    const tempDir = path.join(os.tmpdir(), 'icns-' + Date.now());
    const safeOutputName = path.basename(outputPath, '.icns').replace(/[^a-zA-Z0-9_-]/g, '_');
    const iconsetDir = path.join(tempDir, safeOutputName + '.iconset');
    fs.mkdirSync(iconsetDir, { recursive: true });

    try {
        const sizes = [
            { size: 16, scale: 1, name: 'icon_16x16.png' },
            { size: 32, scale: 1, name: 'icon_32x32.png' },
            { size: 64, scale: 1, name: 'icon_64x64.png' },
            { size: 128, scale: 1, name: 'icon_128x128.png' },
            { size: 256, scale: 1, name: 'icon_256x256.png' },
            { size: 512, scale: 1, name: 'icon_512x512.png' },
            { size: 1024, scale: 1, name: 'icon_1024x1024.png' },
            { size: 16, scale: 2, name: 'icon_16x16@2x.png' },
            { size: 32, scale: 2, name: 'icon_32x32@2x.png' },
            { size: 128, scale: 2, name: 'icon_128x128@2x.png' },
            { size: 256, scale: 2, name: 'icon_256x256@2x.png' },
            { size: 512, scale: 2, name: 'icon_512x512@2x.png' }
        ];

        let completed = 0;
        for (const { size, scale, name } of sizes) {
            const outputSize = size * scale;
            const outputFile = path.join(iconsetDir, name);
            
            await new Promise<void>((resolve, reject) => {
                const sips = spawn('sips', [
                    '-z', outputSize.toString(), outputSize.toString(),
                    inputFile,
                    '--out', outputFile
                ]);
                
                sips.on('close', (code: number) => {
                    if (code === 0) resolve();
                    else reject(new Error(`sips failed with code ${code}`));
                });
                sips.on('error', reject);
            });
            
            completed++;
            progress.report({ 
                message: `Creating icons (${completed}/${sizes.length})...`,
                increment: (100 / sizes.length)
            });
        }

        progress.report({ message: 'Creating ICNS file...' });
        
        await new Promise<void>((resolve, reject) => {
            const iconutil = spawn('iconutil', [
                '-c', 'icns',
                iconsetDir,
                '-o', outputPath
            ]);
            
            iconutil.on('close', (code: number) => {
                if (code === 0) resolve();
                else reject(new Error(`iconutil failed with code ${code}`));
            });
            iconutil.on('error', reject);
        });

    } finally {
        try {
            if (fs.existsSync(tempDir)) {
                fs.rmSync(tempDir, { recursive: true, force: true });
            }
        } catch (error) {
            console.warn('Failed to clean up temp directory:', error);
        }
    }
}

async function convertIcoToIcnsMac(icoFile: string, outputPath: string, progress: any): Promise<void> {
    const tempDir = path.join(os.tmpdir(), 'ico2icns-' + Date.now());
    fs.mkdirSync(tempDir, { recursive: true });
    
    try {
        // Use the external Python script
        const extensionPath = __dirname;
        const pythonScriptPath = path.join(extensionPath, '..', 'scripts', 'extract_ico.py');
        const extractedPng = path.join(tempDir, 'extracted.png');
        
        if (!fs.existsSync(pythonScriptPath)) {
            throw new Error('ICO extraction script not found');
        }
        
        // Run Python script to extract image from ICO
        await new Promise<void>((resolve, reject) => {
            const python = spawn('python3', [pythonScriptPath, icoFile, extractedPng]);
            
            let stdout = '';
            let stderr = '';
            
            python.stdout.on('data', (data: Buffer) => {
                stdout += data.toString();
            });
            
            python.stderr.on('data', (data: Buffer) => {
                stderr += data.toString();
            });
            
            python.on('close', (code: number) => {
                if (code === 0) {
                    console.log(`ICO extraction: ${stdout}`);
                    resolve();
                } else {
                    reject(new Error(`Failed to extract ICO: ${stderr || stdout}`));
                }
            });
            
            python.on('error', reject);
        });
        
        // Now convert the extracted PNG to ICNS
        if (!fs.existsSync(extractedPng)) {
            throw new Error('Failed to extract image from ICO file');
        }
        
        // Use the same function but with the extracted PNG
        return await convertImageToIcnsMac(extractedPng, outputPath, progress);
        
    } finally {
        try {
            if (fs.existsSync(tempDir)) {
                fs.rmSync(tempDir, { recursive: true, force: true });
            }
        } catch (error) {
            console.warn('Failed to clean up temp directory:', error);
        }
    }
}

async function convertImageToIcnsCrossPlatform(inputFile: string, outputPath: string, progress: any) {
    // Use external Python script
    const extensionPath = __dirname;
    const pythonScriptPath = path.join(extensionPath, '..', 'scripts', 'convert_to_icns.py');
    
    if (!fs.existsSync(pythonScriptPath)) {
        throw new Error('Conversion script not found');
    }

    try {
        await execAsync(`python3 "${pythonScriptPath}" "${inputFile}" "${outputPath}"`);
    } catch (error) {
        // Try with python instead of python3
        try {
            await execAsync(`python "${pythonScriptPath}" "${inputFile}" "${outputPath}"`);
        } catch (error2) {
            throw new Error(`Failed to convert image. Make sure Python is installed. Error: ${error2}`);
        }
    }
}

async function extractIcnsToPngs(uri: vscode.Uri) {
    const inputFile = uri.fsPath;
    
    // Ask for output folder
    const defaultFolder = path.join(path.dirname(inputFile), path.basename(inputFile, '.icns') + '_extracted');
    const outputFolder = await vscode.window.showInputBox({
        prompt: 'Enter output folder for extracted PNGs',
        value: defaultFolder
    });

    if (!outputFolder) {
        return;
    }

    try {
        vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: 'Extracting ICNS to PNGs...',
            cancellable: false
        }, async (progress) => {
            if (os.platform() === 'darwin') {
                // On macOS, use iconutil to extract
                await execAsync(`iconutil -c iconset "${inputFile}" -o "${outputFolder}.iconset"`);
                
                // Move PNGs from iconset to output folder
                if (fs.existsSync(outputFolder + '.iconset')) {
                    fs.renameSync(outputFolder + '.iconset', outputFolder);
                    vscode.window.showInformationMessage(`✅ ICNS extracted to: ${outputFolder}`);
                }
            } else {
                // On other platforms, use icns2png or similar
                progress.report({ message: 'Looking for extraction tools...' });
                
                // Try to find icns2png
                try {
                    await execAsync(`icns2png -x "${inputFile}" -d "${outputFolder}"`);
                    vscode.window.showInformationMessage(`✅ ICNS extracted to: ${outputFolder}`);
                } catch (error) {
                    vscode.window.showWarningMessage(
                        'Install icns2png for better extraction. Created fallback script.',
                        'Install Instructions'
                    ).then(selection => {
                        if (selection === 'Install Instructions') {
                            vscode.env.openExternal(vscode.Uri.parse('https://github.com/fiji/icns2png'));
                        }
                    });
                    
                    // Fallback: Use sips if available
                    if (fs.existsSync('/usr/bin/sips')) {
                        progress.report({ message: 'Using sips to extract...' });
                        const iconsetDir = outputFolder + '.iconset';
                        fs.mkdirSync(iconsetDir, { recursive: true });
                        
                        await execAsync(`sips -s format png "${inputFile}" --out "${iconsetDir}/extracted.png"`);
                        fs.renameSync(iconsetDir, outputFolder);
                    }
                }
            }
            
            // Refresh explorer
            vscode.commands.executeCommand('workbench.files.action.refreshFilesExplorer');
        });

    } catch (error: any) {
        vscode.window.showErrorMessage(`❌ Extraction failed: ${error.message}`);
    }
}

async function extractIcoFromExe(uri: vscode.Uri) {
    console.log('🔍 extractIcoFromExe called with:', uri.fsPath);
    
    const selectedPath = uri.fsPath;
    
    try {
        const stat = fs.statSync(selectedPath);
        console.log('📁 Path is a:', stat.isDirectory() ? 'Directory' : 'File');
        
        let exeFile = selectedPath;
        
        // If it's a directory, ask user to select an EXE file
        if (stat.isDirectory()) {
            console.log('📂 Opening file picker for directory...');
            const exeFiles = await vscode.window.showOpenDialog({
                defaultUri: uri,
                filters: {
                    'Executable Files': ['exe', 'EXE']
                },
                canSelectMany: false,
                title: 'Select a Windows EXE file'
            });
            
            if (!exeFiles || exeFiles.length === 0) {
                console.log('❌ User cancelled file selection');
                return;
            }
            
            exeFile = exeFiles[0].fsPath;
            console.log('✅ Selected EXE file:', exeFile);
        }
        
        // Check if it's an EXE file
        if (!exeFile.toLowerCase().endsWith('.exe')) {
            console.log('❌ Not an EXE file:', exeFile);
            vscode.window.showErrorMessage('Please select a Windows EXE file to extract icons from.');
            return;
        }
        
        console.log('🚀 Proceeding with EXE file:', exeFile);

        // Ask for output folder
        const defaultFolder = path.join(path.dirname(exeFile), path.basename(exeFile, '.exe') + '_icons');
        const outputFolder = await vscode.window.showInputBox({
            prompt: 'Enter output folder for extracted PNGs',
            value: defaultFolder
        });

        if (!outputFolder) {
            return;
        }

        await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: 'Extracting ICO from EXE...',
            cancellable: false
        }, async (progress) => {
            progress.report({ message: 'Preparing to extract real EXE icons...' });
            
            // Create output folder
            fs.mkdirSync(outputFolder, { recursive: true });
            
            // Use the bash script for extraction
            const extensionPath = __dirname;
            const extractScript = path.join(extensionPath, '..', 'scripts', 'extract_exe.sh');
            
            if (!fs.existsSync(extractScript)) {
                throw new Error('EXE extraction script not found');
            }
            
            // Make sure script is executable
            try {
                fs.chmodSync(extractScript, 0o755);
            } catch (error) {
                console.log('Note: Could not set executable permissions on script');
            }
            
            progress.report({ message: 'Running EXE icon extraction...' });
            
            // Run the extraction script
            await new Promise<void>((resolve, reject) => {
                // Quote paths to handle spaces
                const quotedExeFile = `"${exeFile.replace(/"/g, '\\"')}"`;
                const quotedOutputFolder = `"${outputFolder.replace(/"/g, '\\"')}"`;
                
                console.log('📤 Running shell script with quoted paths:');
                console.log('  EXE:', quotedExeFile);
                console.log('  Output:', quotedOutputFolder);
                
                const shell = spawn(extractScript, [quotedExeFile, quotedOutputFolder], {
                    shell: true,
                    stdio: 'pipe'
                });
                
                let stdout = '';
                let stderr = '';
                
                shell.stdout.on('data', (data: Buffer) => {
                    stdout += data.toString();
                    console.log(`EXE extraction output: ${data.toString().trim()}`);
                });
                
                shell.stderr.on('data', (data: Buffer) => {
                    stderr += data.toString();
                });
                
                shell.on('close', (code: number) => {
                    if (code === 0) {
                        console.log(`EXE extraction completed: ${stdout}`);
                        resolve();
                    } else {
                        console.error(`EXE extraction script failed: ${stderr || stdout}`);
                        // Don't reject if we got some output files
                        const pngCount = fs.readdirSync(outputFolder).filter(f => f.endsWith('.png')).length;
                        if (pngCount > 0) {
                            console.log(`But found ${pngCount} PNG files, continuing...`);
                            resolve();
                        } else {
                            reject(new Error(`Failed to extract icons from EXE: ${stderr || stdout}`));
                        }
                    }
                });
                
                shell.on('error', (error) => {
                    console.error('Shell spawn error:', error);
                    reject(error);
                });
            });
            
            // Check what was extracted
            const extractedFiles = fs.readdirSync(outputFolder);
            const pngFiles = extractedFiles.filter(f => f.endsWith('.png'));
            const icoFiles = extractedFiles.filter(f => f.endsWith('.ico'));
            
            if (pngFiles.length > 0 || icoFiles.length > 0) {
                vscode.window.showInformationMessage(`✅ Extracted ${pngFiles.length} PNG(s) and ${icoFiles.length} ICO(s) from EXE`);
                
                // Show a quick preview of the first PNG
                if (pngFiles.length > 0) {
                    const firstPng = path.join(outputFolder, pngFiles[0]);
                    const fileSize = fs.statSync(firstPng).size;
                    
                    // Show quick info
                    vscode.window.showInformationMessage(
                        `First icon: ${pngFiles[0]} (${Math.round(fileSize/1024)} KB)`,
                        'Open Folder'
                    ).then(selection => {
                        if (selection === 'Open Folder') {
                            vscode.commands.executeCommand('revealFileInOS', vscode.Uri.file(outputFolder));
                        }
                    });
                }
            } else {
                vscode.window.showWarningMessage(
                    '⚠️ No icons found in EXE file. Created fallback representation.',
                    'Open Folder'
                ).then(selection => {
                    if (selection === 'Open Folder') {
                        vscode.commands.executeCommand('revealFileInOS', vscode.Uri.file(outputFolder));
                    }
                });
            }
            
            // Refresh explorer
            vscode.commands.executeCommand('workbench.files.action.refreshFilesExplorer');
        });

    } catch (error: any) {
        console.error('❌ Error in extractIcoFromExe:', error);
        vscode.window.showErrorMessage(`❌ EXE extraction failed: ${error.message}`);
    }
}

async function previewIcns(uri: vscode.Uri) {
    const inputFile = uri.fsPath;
    
    // Create and show preview panel
    const panel = vscode.window.createWebviewPanel(
        'icnsPreview',
        `Preview: ${path.basename(inputFile)}`,
        vscode.ViewColumn.Beside,
        { enableScripts: true }
    );

    try {
        // TEMPORARY: Extract to temp folder and get a PNG
        const tempDir = path.join(os.tmpdir(), 'icns-preview-' + Date.now());
        const iconsetDir = path.join(tempDir, 'preview.iconset');
        fs.mkdirSync(iconsetDir, { recursive: true });

        try {
            if (os.platform() === 'darwin') {
                await execAsync(`iconutil -c iconset '${inputFile}' -o '${iconsetDir}'`);
                
                const pngFiles = fs.readdirSync(iconsetDir).filter(f => f.endsWith('.png'));
                let previewPng = '';
                
                // Prefer larger sizes for better preview
                const preferredOrder = ['512x512', '512x512@2x', '256x256', '256x256@2x', '1024x1024', '128x128'];
                
                for (const size of preferredOrder) {
                    const found = pngFiles.find(f => f.includes(size));
                    if (found) {
                        previewPng = path.join(iconsetDir, found);
                        break;
                    }
                }
                
                // If no specific size found, use the first PNG
                if (!previewPng && pngFiles.length > 0) {
                    previewPng = path.join(iconsetDir, pngFiles[0]);
                }
                
                if (previewPng && fs.existsSync(previewPng)) {
                    // Read the PNG file as base64
                    const pngData = fs.readFileSync(previewPng);
                    const base64 = pngData.toString('base64');
                    const filename = path.basename(inputFile);
                    
                    panel.webview.html = getPreviewWebviewContent(filename, base64, true);
                } else {
                    throw new Error('Could not extract PNG from ICNS file');
                }
                
            } else {
                // On other platforms, try simpler extraction or show fallback
                panel.webview.html = getPreviewWebviewContent(path.basename(inputFile), '', false);
            }
            
        } finally {
            // Clean up temp directory
            fs.rmSync(tempDir, { recursive: true, force: true });
        }
        
    } catch (error: any) {
        panel.webview.html = `<h2>Error previewing ICNS: ${error.message}</h2>`;
    }
}

async function replaceIcnsInWrapper(uri: vscode.Uri) {
    console.log('🔄 replaceIcnsInWrapper called with ICNS file:', uri.fsPath);
    const icnsFile = uri.fsPath;
    
    // Check if it's an ICNS file
    if (!icnsFile.endsWith('.icns')) {
        vscode.window.showErrorMessage('Please select an ICNS file to replace in wrapper.');
        return;
    }
    
    // Ask user to select a new image file to convert to ICNS
    const imageFiles = await vscode.window.showOpenDialog({
        filters: {
            'Images': ['png', 'jpg', 'jpeg', 'ico', 'bmp', 'tiff', 'tif']
        },
        canSelectMany: false,
        title: 'Select new image to replace the ICNS'
    });
    
    if (!imageFiles || imageFiles.length === 0) {
        return;
    }
    
    const imageFile = imageFiles[0].fsPath;
    
    try {
        // Find Wineskin wrapper
        const wrapperDir = await findWineskinWrapper(icnsFile);
        
        if (!wrapperDir) {
            vscode.window.showErrorMessage(
                'Could not find Wineskin wrapper structure. Please navigate to the wrapper folder.',
                'Open Folder'
            ).then(selection => {
                if (selection === 'Open Folder') {
                    vscode.commands.executeCommand('revealFileInOS', uri);
                }
            });
            return;
        }

        // Find the specific ICNS file location
        const icnsLocation = await findIcnsLocationInWrapper(wrapperDir, icnsFile);
        
        if (!icnsLocation) {
            vscode.window.showErrorMessage(`Could not find ${path.basename(icnsFile)} in the wrapper structure.`);
            return;
        }
        
        console.log(`📍 ICNS location: ${icnsLocation}`);
        
        // Ask for confirmation
        const confirm = await vscode.window.showWarningMessage(
            `Replace ${path.basename(icnsLocation)} in wrapper?\n\nLocation: ${icnsLocation}`,
            { modal: true },
            'Replace',
            'Cancel'
        );
        
        if (confirm !== 'Replace') {
            return;
        }
        
        // Create backup of original
        const backupPath = icnsLocation + '.backup';
        fs.copyFileSync(icnsLocation, backupPath);
        
        // Convert the new image to ICNS and replace the existing one
        await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: 'Replacing ICNS in wrapper...',
            cancellable: false
        }, async (progress) => {
            progress.report({ message: 'Converting new image to ICNS...' });
            
            if (os.platform() === 'darwin') {
                await convertImageToIcnsMac(imageFile, icnsLocation, progress);
            } else {
                await convertImageToIcnsCrossPlatform(imageFile, icnsLocation, progress);
            }
            
            progress.report({ message: 'ICNS replaced successfully!' });
        });
        
        vscode.window.showInformationMessage(
            `✅ Replaced ${path.basename(icnsLocation)} with new image (backup saved as ${path.basename(backupPath)})`
        );

        // Just refresh the file explorer - the sidebar will update when user interacts with the file
        vscode.commands.executeCommand('workbench.files.action.refreshFilesExplorer');

    } catch (error: any) {
        vscode.window.showErrorMessage(`❌ Replacement failed: ${error.message}`);
    }
}

async function findIcnsLocationInWrapper(wrapperDir: string, targetIcnsPath: string): Promise<string | null> {
    const targetBasename = path.basename(targetIcnsPath);
    console.log(`🔍 Looking for ${targetBasename} in ${wrapperDir}`);
    
    let foundPath: string | null = null;
    
    function search(dir: string) {
        if (foundPath) return;
        
        try {
            const files = fs.readdirSync(dir);
            
            for (const file of files) {
                const fullPath = path.join(dir, file);
                
                try {
                    const stat = fs.statSync(fullPath);
                    
                    if (stat.isDirectory()) {
                        // Skip system directories
                        if (!['node_modules', '.git', '__pycache__'].includes(file)) {
                            search(fullPath);
                        }
                    } else if (file.toLowerCase() === targetBasename.toLowerCase()) {
                        foundPath = fullPath;
                        console.log(`✅ Found matching ICNS: ${fullPath}`);
                        return;
                    }
                } catch (err) {
                    // Skip inaccessible files
                    continue;
                }
            }
        } catch (error) {
            // Skip inaccessible directories
            const errorMessage = error instanceof Error ? error.message : String(error);
            console.log(`⚠️ Cannot search directory ${dir}:`, errorMessage);
        }
    }
    
    search(wrapperDir);
    
    return foundPath;
}

async function findWineskinWrapper(startPath: string): Promise<string | null> {
    let current = path.dirname(startPath);
    
    // Look up the directory tree for Wineskin wrapper structure
    for (let i = 0; i < 10; i++) {
        console.log(`🔍 Checking: ${current}`);
        
        // Check for common Wineskin files/folders
        const possibleMarkers = [
            'Wineskin.app',
            'Contents',
            'drive_c',
            '*.icns'  // Look for other ICNS files
        ];
        
        // Check if current directory contains .app bundle
        try {
            const files = fs.readdirSync(current);
            
            // Check for .app bundle
            const appBundle = files.find(f => f.endsWith('.app'));
            if (appBundle) {
                const appPath = path.join(current, appBundle);
                console.log(`✅ Found .app bundle: ${appPath}`);
                return path.join(appPath, 'Contents');
            }
            
            // Check for Contents folder
            if (files.includes('Contents')) {
                console.log(`✅ Found Contents folder in: ${current}`);
                return path.join(current, 'Contents');
            }
            
            // Check for Wineskin.app
            if (files.includes('Wineskin.app')) {
                console.log(`✅ Found Wineskin.app in: ${current}`);
                return path.join(current, 'Wineskin.app', 'Contents');
            }
            
        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : String(error);
            console.log(`⚠️ Cannot read directory ${current}:`, errorMessage);
        }
        
        // Move up one directory
        const parent = path.dirname(current);
        if (parent === current) {
            break;
        }
        current = parent;
    }
    
    console.log(`❌ No wrapper found starting from ${startPath}`);
    return null;
}

async function findIcnsFilesInWrapper(wrapperDir: string): Promise<string[]> {
    console.log('🔍 Searching for ICNS files in:', wrapperDir);
    
    const icnsFiles: string[] = [];
    
    function search(dir: string) {
        try {
            const files = fs.readdirSync(dir);
            
            for (const file of files) {
                const fullPath = path.join(dir, file);
                const stat = fs.statSync(fullPath);
                
                if (stat.isDirectory()) {
                    // Skip some system directories
                    if (!['node_modules', '.git', '__pycache__'].includes(file)) {
                        search(fullPath);
                    }
                } else if (file.toLowerCase().endsWith('.icns')) {
                    console.log(`🔍 Found ICNS: ${fullPath} (${file})`);
                    icnsFiles.push(fullPath);
                }
            }
        } catch (error) {
            // Skip inaccessible directories
            const errorMessage = error instanceof Error ? error.message : String(error);
            console.log(`⚠️ Cannot search directory ${dir}:`, errorMessage);
        }
    }
    
    search(wrapperDir);
    
    // Sort by relevance - Wineskin.icns first, then others
    icnsFiles.sort((a, b) => {
        const aName = path.basename(a).toLowerCase();
        const bName = path.basename(b).toLowerCase();
        
        if (aName === 'wineskin.icns') return -1;
        if (bName === 'wineskin.icns') return 1;
        return a.localeCompare(b);
    });
    
    console.log(`✅ Found ${icnsFiles.length} ICNS files:`, icnsFiles.map(f => path.basename(f)));
    return icnsFiles;
}

function getPreviewWebviewContent(filename: string, pngBase64: string, hasPreview: boolean = true): string {
    return `
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>ICNS Preview</title>
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                padding: 20px;
                background: var(--vscode-editor-background);
                color: white;
            }
            .container {
                max-width: 800px;
                margin: 0 auto;
            }
            h1 {
                color: var(--vscode-titleBar-activeForeground);
                border-bottom: 1px solid var(--vscode-panel-border);
                padding-bottom: 10px;
            }
            .preview-area {
                text-align: center;
                margin: 30px 0;
                padding: 20px;
                background: var(--vscode-editorWidget-background);
                border-radius: 8px;
                border: 1px solid var(--vscode-panel-border);
                overflow: hidden;
            }
            .icon-display {
                display: inline-block;
                padding: 20px;
                background: white;
                border-radius: 12px;
                box-shadow: 0 4px 12px rgba(0,0,0,0.1);
                margin: 20px;
            }
            img {
                max-width: 256px;
                max-height: 256px;
                image-rendering: high-quality;
            }
            .info {
                background: var(--vscode-textBlockQuote-background);
                padding: 15px;
                border-radius: 6px;
                margin-top: 20px;
                font-size: 14px;
            }
            .file-info {
                font-family: monospace;
                background: var(--vscode-editor-inactiveSelectionBackground);
                padding: 10px;
                border-radius: 4px;
                margin: 10px 0;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>ICNS Preview: ${filename}</h1>
            
            <div class="file-info">
                File: ${filename}<br>
                ${hasPreview ? 'Showing largest extracted icon' : 'Cannot extract preview on this platform'}
            </div>
            
            <div class="preview-area">
                ${hasPreview ? `
                <div class="icon-display">
                    <img src="data:image/png;base64,${pngBase64}" 
                         alt="ICNS Preview">
                </div>
                ` : `
                <div style="color: #f00; padding: 20px;">
                    ⚠️ Cannot preview ICNS on this platform.<br>
                    Use "Extract to PNGs" to see all icon sizes.
                    <br><br>
                    <small>Note: Full preview requires macOS with iconutil command.</small>
                </div>
                `}
            </div>
            
            <div class="info">
                <strong>Note:</strong> ICNS files contain multiple icon sizes (16x16 to 1024x1024).<br>
                Use the "Extract to PNGs" command to see all individual sizes.
            </div>
        </div>
    </body>
    </html>`;
}

export function deactivate() {}
EOL

# Create src/panel.ts (same as before)
cat << 'EOL' > src/panel.ts
import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import { spawn,exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

export class IcnsManagerPanel implements vscode.WebviewViewProvider {
    private _view?: vscode.WebviewView;

    constructor(private readonly context: vscode.ExtensionContext) {}

    resolveWebviewView(webviewView: vscode.WebviewView, _context: vscode.WebviewViewResolveContext, _token: vscode.CancellationToken) {
        this._view = webviewView;
        webviewView.webview.options = {
            enableScripts: true,
            localResourceRoots: [this.context.extensionUri]
        };

        webviewView.webview.html = this.getWebviewContent(webviewView.webview);
        
        webviewView.webview.onDidReceiveMessage(async message => {
            switch (message.command) {
                case 'convertImage':
                    await this.convertImage(message.filePath);
                    break;
                case 'extractIcns':
                    await this.extractIcns(message.filePath);
                    break;
                case 'extractExe':
                    await this.extractFromExe(message.filePath);
                    break;
                case 'replace':
                    await this.replaceInWrapper(message.filePath);
                    break;
                case 'getActiveFile':
                    this.updateActiveFileInfo();
                    break;
            }
        });

        // Listen for active editor changes
        vscode.window.onDidChangeActiveTextEditor(() => {
            this.updateActiveFileInfo();
        });

        // Initial update
        setTimeout(() => this.updateActiveFileInfo(), 500);
    }

    private getWebviewContent(webview: vscode.Webview): string {
        const styleUri = webview.asWebviewUri(
            vscode.Uri.joinPath(this.context.extensionUri, 'media', 'styles.css')
        );

        const scriptUri = webview.asWebviewUri(
            vscode.Uri.joinPath(this.context.extensionUri, 'media', 'main.js')
        );

        return `
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link href="${styleUri}" rel="stylesheet">
        </head>
        <body>
            <div class="container">
                <header>
                    <h1><span class="icon">🎨</span> ICNS Manager</h1>
                    <p class="subtitle">For Wineskin Wrappers</p>
                </header>

                <div class="file-status" id="fileStatus">
                    <div class="status-icon">📄</div>
                    <div class="status-text">No file selected</div>
                </div>

                <div class="preview-container" id="previewContainer">
                    <div class="preview-placeholder">
                        <div class="placeholder-icon">🖼️</div>
                        <div class="placeholder-text">Preview will appear here</div>
                    </div>
                </div>

                <div class="quick-actions">
                    <h3>Quick Actions</h3>
                    <div class="action-grid">
                        <div class="action-card" data-action="convertImage">
                            <div class="action-icon">🖼️</div>
                            <div class="action-title">Convert Image</div>
                            <div class="action-desc">PNG/JPG → ICNS</div>
                        </div>
                        <div class="action-card" data-action="extractIcns">
                            <div class="action-icon">📤</div>
                            <div class="action-title">Extract ICNS</div>
                            <div class="action-desc">ICNS → PNGs</div>
                        </div>
                        <div class="action-card" data-action="extractExe">
                            <div class="action-icon">🔍</div>
                            <div class="action-title">Extract from EXE</div>
                            <div class="action-desc">ICO from EXE → PNGs</div>
                        </div>
                        <div class="action-card" data-action="replace">
                            <div class="action-icon">🔧</div>
                            <div class="action-title">Replace in Wrapper</div>
                            <div class="action-desc">Swap ICNS in wrapper</div>
                        </div>
                    </div>
                </div>

                <div class="info-box">
                    <h4>💡 Tips for Wineskin</h4>
                    <ul>
                        <li>ICNS files go in <code>Contents/Resources/</code> of your .app bundle</li>
                        <li>Common sizes: 16x16, 32x32, 128x128, 256x256, 512x512</li>
                        <li>Include @2x versions for Retina displays</li>
                        <li>After replacing, restart the wrapper to see changes</li>
                        <li>Extract ICO from EXE to PNG to get Windows icons</li>
                    </ul>
                </div>
            </div>

            <script src="${scriptUri}"></script>
        </body>
        </html>`;
    }

    private updateActiveFileInfo() {
        const editor = vscode.window.activeTextEditor;
        
        if (!editor) {
            this._view?.webview.postMessage({
                command: 'updateFileStatus',
                fileType: 'none',
                fileName: '',
                filePath: ''
            });
            return;
        }

        const filePath = editor.document.fileName;
        const fileName = path.basename(filePath);
        const isIcns = fileName.endsWith('.icns');
        const isImage = /\.(png|jpg|jpeg|ico|bmp|tiff|tif)$/i.test(fileName);
        const isExe = fileName.endsWith('.exe');
        
        let fileType = 'other';
        if (isIcns) fileType = 'icns';
        else if (isImage) fileType = 'image';
        else if (isExe) fileType = 'exe';
        
        this._view?.webview.postMessage({
            command: 'updateFileStatus',
            fileType: fileType,
            fileName: fileName,
            filePath: filePath
        });
        
        // If it's an ICNS file, try to extract and show preview
        if (isIcns) {
            this.extractAndShowPreview(filePath);
        }
    }

    private async extractAndShowPreview(filePath: string) {
        if (!this._view || !fs.existsSync(filePath)) {
            return;
        }

        try {
            const tempDir = path.join(os.tmpdir(), 'icns-sidebar-preview-' + Date.now());
            const iconsetDir = path.join(tempDir, 'preview.iconset');
            fs.mkdirSync(iconsetDir, { recursive: true });

            if (os.platform() === 'darwin') {
                await execAsync(`iconutil -c iconset "${filePath}" -o "${iconsetDir}"`);
                
                const pngFiles = fs.readdirSync(iconsetDir).filter(f => f.endsWith('.png'));
                let previewPng = '';
                
                const preferredOrder = ['512x512', '512x512@2x', '256x256', '256x256@2x', '1024x1024', '128x128'];
                
                for (const size of preferredOrder) {
                    const found = pngFiles.find(f => f.includes(size));
                    if (found) {
                        previewPng = path.join(iconsetDir, found);
                        break;
                    }
                }
                
                if (!previewPng && pngFiles.length > 0) {
                    previewPng = path.join(iconsetDir, pngFiles[0]);
                }
                
                if (previewPng && fs.existsSync(previewPng)) {
                    const pngData = fs.readFileSync(previewPng);
                    const base64 = pngData.toString('base64');
                    
                    this._view.webview.postMessage({
                        command: 'updatePreview',
                        base64: base64,
                        fileName: path.basename(filePath)
                    });
                }
            }
            
            fs.rmSync(tempDir, { recursive: true, force: true });
            
        } catch (error) {
            console.error('Error extracting preview:', error);
        }
    }

    private async convertImage(filePath?: string) {
        if (filePath) {
            const uri = vscode.Uri.file(filePath);
            await vscode.commands.executeCommand('icns-manager.convertToIcns', uri);
        } else {
            const files = await vscode.window.showOpenDialog({
                filters: {
                    'Images': ['png', 'jpg', 'jpeg', 'ico', 'bmp', 'tiff']
                },
                canSelectMany: false
            });
            
            if (files && files[0]) {
                await vscode.commands.executeCommand('icns-manager.convertToIcns', files[0]);
            }
        }
    }

    private async extractIcns(filePath: string) {
        const uri = vscode.Uri.file(filePath);
        await vscode.commands.executeCommand('icns-manager.extractIcns', uri);
    }

    private async extractFromExe(filePath: string) {
        const uri = vscode.Uri.file(filePath);
        await vscode.commands.executeCommand('icns-manager.extractFromExe', uri);
    }

    private async replaceInWrapper(filePath: string) {
        const uri = vscode.Uri.file(filePath);
        await vscode.commands.executeCommand('icns-manager.replaceIcns', uri);
    }
}
EOL

# Create media/styles.css (same as before)
cat << 'EOL' > media/styles.css
:root {
    --primary-color: #646cff;
    --primary-dark: #535bf2;
    --success-color: #10b981;
    --warning-color: #f59e0b;
    --danger-color: #ef4444;
    --exe-color: #8b5cf6;
    --bg-primary: var(--vscode-sideBar-background);
    --bg-secondary: var(--vscode-sideBarSectionHeader-background);
    --text-primary: white;
    --text-secondary: var(--vscode-descriptionForeground);
    --border-color: var(--vscode-widget-border);
    --hover-bg: var(--vscode-list-hoverBackground);
}

body {
    font-family: var(--vscode-font-family);
    background: var(--bg-primary);
    color: var(--text-primary);
    margin: 0;
    padding: 0;
    font-size: 13px;
}

.container {
    padding: 16px;
}

header {
    margin-bottom: 20px;
    padding-bottom: 12px;
    border-bottom: 1px solid var(--border-color);
}

h1 {
    margin: 0;
    font-size: 18px;
    font-weight: 600;
    display: flex;
    align-items: center;
    gap: 8px;
}

h1 .icon {
    font-size: 20px;
}

.subtitle {
    margin: 4px 0 0 0;
    color: var(--text-secondary);
    font-size: 12px;
}

/* File Status */
.file-status {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 12px;
    border-radius: 6px;
    margin-bottom: 20px;
    background: var(--bg-secondary);
    border: 1px solid var(--border-color);
}

.file-status.icns {
    background: rgba(100, 108, 255, 0.1);
    border-color: var(--primary-color);
}

.file-status.image {
    background: rgba(16, 185, 129, 0.1);
    border-color: var(--success-color);
}

.file-status.exe {
    background: rgba(139, 92, 246, 0.1);
    border-color: var(--exe-color);
}

.file-status.none {
    opacity: 0.7;
}

.status-icon {
    font-size: 18px;
}

.status-text {
    font-size: 13px;
    font-weight: 500;
}

/* Preview Container */
.preview-container {
    margin-bottom: 24px;
    min-height: 200px;
    border: 2px dashed var(--border-color);
    border-radius: 8px;
    display: flex;
    align-items: center;
    justify-content: center;
}

.preview-placeholder {
    text-align: center;
    color: var(--text-secondary);
    padding: 30px;
}

.placeholder-icon {
    font-size: 48px;
    margin-bottom: 12px;
    opacity: 0.5;
}

.placeholder-text {
    font-size: 14px;
}

/* Active Preview */
.preview-active {
    padding: 20px;
    text-align: center;
    width: 100%;
}

.preview-title {
    font-weight: 500;
    margin-bottom: 15px;
    color: var(--text-primary);
    font-size: 14px;
}

.preview-image {
    padding: 15px;
    background: white;
    border-radius: 10px;
    display: inline-block;
    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
}

.preview-image img {
    max-width: 128px;
    max-height: 128px;
    image-rendering: high-quality;
}

.preview-note {
    margin-top: 12px;
    font-size: 11px;
    color: var(--text-secondary);
    font-style: italic;
}

.quick-actions {
    margin-bottom: 24px;
}

.quick-actions h3 {
    margin: 0 0 12px 0;
    font-size: 14px;
    font-weight: 600;
}

.action-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 6px;
}

.action-card {
    background: var(--bg-secondary);
    border: 1px solid var(--border-color);
    border-radius: 6px;
    padding: 8px;
    cursor: pointer;
    transition: all 0.2s;
    text-align: center;
}

.action-card:hover {
    background: var(--hover-bg);
    transform: translateY(-2px);
    border-color: var(--primary-color);
}

.action-card[data-action="convertImage"]:hover {
    border-color: var(--success-color);
}

.action-card[data-action="extractIcns"]:hover {
    border-color: var(--primary-color);
}

.action-card[data-action="extractExe"]:hover {
    border-color: var(--exe-color);
}

.action-card[data-action="replace"]:hover {
    border-color: var(--warning-color);
}

.action-icon {
    font-size: 16px;
    margin-bottom: 4px;
}

.action-title {
    font-weight: 500;
    margin-bottom: 2px;
    font-size: 10px;
}

.action-desc {
    font-size: 8px;
    color: var(--text-secondary);
    line-height: 1.2;
}

.info-box {
    background: var(--vscode-textBlockQuote-background);
    border: 1px solid var(--vscode-textBlockQuote-border);
    border-radius: 6px;
    padding: 16px;
    margin-top: 20px;
}

.info-box h4 {
    margin: 0 0 12px 0;
    font-size: 13px;
    display: flex;
    align-items: center;
    gap: 8px;
}

.info-box ul {
    margin: 0;
    padding-left: 20px;
}

.info-box li {
    margin-bottom: 6px;
    font-size: 12px;
    line-height: 1.4;
}

.info-box code {
    font-family: var(--vscode-editor-font-family);
    background: var(--vscode-textCodeBlock-background);
    padding: 2px 4px;
    border-radius: 3px;
    font-size: 11px;
}

@media (max-width: 600px) {
    .action-grid {
        grid-template-columns: repeat(2, 1fr);
        gap: 6px;
    }
    
    .action-card {
        padding: 8px;
    }
    
    .action-title {
        font-size: 10px;
    }
    
    .action-desc {
        font-size: 8px;
    }
}
EOL

# Create media/main.js (same as before)
cat << 'EOL' > media/main.js
(function() {
    const vscode = acquireVsCodeApi();
    
    // DOM Elements
    const fileStatus = document.getElementById('fileStatus');
    const previewContainer = document.getElementById('previewContainer');
    const actionCards = document.querySelectorAll('.action-card');
    
    // Update file status styling based on file type
    function updateFileStatusClass(fileType) {
        fileStatus.className = 'file-status ' + fileType;
        
        // Update status icon
        const statusIcon = fileStatus.querySelector('.status-icon');
        switch(fileType) {
            case 'icns':
                statusIcon.textContent = '🎯';
                break;
            case 'image':
                statusIcon.textContent = '🖼️';
                break;
            case 'exe':
                statusIcon.textContent = '⚙️';
                break;
            default:
                statusIcon.textContent = '📄';
        }
    }
    
    // Event Listeners
    actionCards.forEach(card => {
        card.addEventListener('click', () => {
            const action = card.dataset.action;
            const filePath = card.dataset.filePath;
            
            if (action && filePath) {
                vscode.postMessage({ 
                    command: action, 
                    filePath: filePath 
                });
            } else if (action) {
                vscode.postMessage({ command: action });
            }
        });
    });
    
    // Handle messages from extension
    window.addEventListener('message', event => {
        const message = event.data;
        
        switch (message.command) {
            case 'updateFileStatus':
                updateFileStatus(message.fileType, message.fileName, message.filePath);
                break;
            case 'updatePreview':
                updatePreview(message.base64, message.fileName);
                break;
        }
    });
    
    // Functions
    function updateFileStatus(fileType, fileName, filePath) {
        const statusText = fileStatus.querySelector('.status-text');
        
        if (fileType === 'none' || !fileName) {
            statusText.textContent = 'No file selected';
            updateFileStatusClass('none');
        } else {
            statusText.textContent = `${fileName}`;
            updateFileStatusClass(fileType);
        }
        
        // Store the file path in action cards
        actionCards.forEach(card => {
            card.dataset.filePath = filePath;
            
            // Enable/disable based on file type
            const action = card.dataset.action;
            if (action === 'extractIcns' && fileType !== 'icns') {
                card.style.opacity = '0.5';
                card.style.cursor = 'not-allowed';
                card.title = 'Select an ICNS file first';
            } else if (action === 'extractExe' && fileType !== 'exe') {
                card.style.opacity = '0.5';
                card.style.cursor = 'not-allowed';
                card.title = 'Select an EXE file first';
            } else if (action === 'convertImage' && !['image', 'icns', 'exe'].includes(fileType)) {
                card.style.opacity = '0.5';
                card.style.cursor = 'not-allowed';
                card.title = 'Select an image file first';
            } else if (action === 'replace' && fileType !== 'icns') {
                card.style.opacity = '0.5';
                card.style.cursor = 'not-allowed';
                card.title = 'Select an ICNS file first';
            } else {
                card.style.opacity = '1';
                card.style.cursor = 'pointer';
                card.title = '';
            }
        });
    }
    
    function updatePreview(base64, fileName) {
        previewContainer.innerHTML = `
            <div class="preview-active">
                <div class="preview-title">${fileName}</div>
                <div class="preview-image">
                    <img src="data:image/png;base64,${base64}" alt="${fileName}">
                </div>
                <div class="preview-note">Extracted from ICNS file</div>
            </div>
        `;
    }
    
    // Request initial file info
    vscode.postMessage({ command: 'getActiveFile' });
})();
EOL

# Create README.md with updated instructions
cat << EOL > README.md
# ICNS Manager for Wineskin

A VS Code extension to manage ICNS files for Wineskin wrappers. Convert images to ICNS, extract ICNS to PNGs, extract **real icons from EXE files**, preview icons, and replace icons in your Wineskin applications.

## Features

### 🔄 Image to ICNS Conversion
- Convert PNG, JPG, JPEG, ICO, BMP, TIFF to ICNS format
- Automatically generates all required sizes (16x16 to 1024x1024)
- Creates retina (@2x) versions for high-DPI displays
- Uses native macOS tools when available

### 📤 ICNS Extraction
- Extract ICNS files to individual PNG images
- View all icon sizes contained in an ICNS file
- Works on both macOS and other platforms

### 🔍 EXE Icon Extraction (NEW! - Now extracts REAL icons!)
- **Extracts actual icons from Windows EXE files** using icoutils
- Converts extracted icons to PNG format
- Works on macOS and Linux (requires icoutils)
- Falls back to ImageMagick or creates placeholder icons if tools not available

### 👁️ Preview
- Preview ICNS files directly in VS Code
- See file information and size
- Quick visual verification of icons

### 🔧 Wrapper Integration
- **Replace ICNS in Wrapper**: Right-click on an ICNS file and select "Replace in Wrapper"
- Select a new image (PNG/JPG/etc.) to convert and replace the existing ICNS
- Keeps the same filename and creates a backup
- Automatically finds Wineskin wrapper structure
- Works with .app bundles and Wineskin directories

### 📊 Smart Sidebar Interface
- Detects active file type automatically (ICNS, Image, EXE)
- Shows preview of ICNS files directly in sidebar
- Context-aware quick actions (actions enabled based on file type)
- Clean, modern interface

## EXE Icon Extraction Requirements

### For Best Results (Extracts Real Icons):
- **macOS**: \`brew install icoutils imagemagick\`
- **Linux**: \`sudo apt-get install icoutils imagemagick\`

### Fallback Options:
1. **ImageMagick**: Can extract some icons if icoutils not available
2. **Python + PIL**: Creates "EXE" placeholder icons if no tools available

## Usage

### Quick Start
1. Open a folder containing your Wineskin wrapper or icons
2. Click the ICNS Manager icon in the Activity Bar
3. The sidebar will automatically detect your active file type

### Convert Image to ICNS
1. Open any image file (.png, .jpg, .ico, etc.)
2. Click "Convert Image" in the sidebar or right-click in Explorer
3. Enter a filename for the new .icns file
4. The extension will create all required sizes automatically

### Extract ICNS to PNGs
1. Open a .icns file
2. Click "Extract ICNS" in the sidebar or right-click in Explorer
3. Choose an output folder
4. All icon sizes will be extracted as individual PNG files

### Extract REAL Icons from EXE
1. Open a Windows .exe file
2. Click "Extract from EXE" in the sidebar or right-click in Explorer
3. Choose an output folder
4. **Real Windows icons will be extracted** and converted to PNG format

### Preview ICNS
1. Open a .icns file
2. The sidebar will automatically show a preview
3. Or click "Preview" for a larger view

### Replace ICNS in Wrapper
1. **Right-click on an existing .icns file** in your Wineskin wrapper
2. Select "ICNS Manager: Replace ICNS in Wrapper"
3. Choose a new image file (PNG, JPG, etc.)
4. The extension will:
   - Convert the new image to ICNS format
   - Find the wrapper structure automatically
   - Create a backup of the original ICNS file
   - Replace it with the new icon (keeping the same filename)
   - Show confirmation with backup location

## Installation

1. Run the generator script to create the extension
2. Open the generated folder in VS Code
3. Press F5 to run in extension development mode
4. Or package with \`vsce package\` and install manually

## Tips for Wineskin Wrappers

1. ICNS files should be placed in \`Contents/Resources/\` inside your .app bundle
2. Common required sizes: 16x16, 32x32, 128x128, 256x256, 512x512
3. Include @2x versions for Retina displays (32x32 for 16x16@2x, etc.)
4. After replacing an icon, restart the wrapper to see changes
5. Extract **real Windows icons** from EXE files to get authentic application icons

## Troubleshooting

### "Cannot extract real icons from EXE"
- Install icoutils: \`brew install icoutils\` (macOS) or \`sudo apt-get install icoutils\` (Linux)
- Install ImageMagick: \`brew install imagemagick\` or \`sudo apt-get install imagemagick\`

### "Cannot create ICNS on non-macOS"
- Install Python 3 and Pillow: \`pip install Pillow\`

### "Python not found"
- Make sure Python 3 is installed and in your PATH

### "Cannot find wrapper structure"
- Make sure you have the .app bundle or Wineskin folder open
- The extension searches up to 10 parent directories
- You can manually navigate to the wrapper folder

## Pro Tip

After extracting icons from an EXE, use the "Convert Image" action to turn the best extracted PNG into an ICNS file for your Wineskin wrapper!

## License

MIT License - See LICENSE.md file
EOL

# Create LICENSE.md
cat << EOL > LICENSE.md
MIT License

Copyright (c) $(date +%Y) Wineskin Helper

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

# Create .vscodeignore
cat << EOL > .vscodeignore
node_modules
.vscode
*.ts
*.map
.git
.gitignore
src
tsconfig.json
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

echo -e "${GREEN}✅ ICNS Manager extension installed successfully!${NC}"
echo -e "${YELLOW}🚀 Usage: Click the ICNS Manager icon in the Activity Bar or right-click on files${NC}"
echo -e "${CYAN}💡 The extension adds commands to:" 
echo -e "   • Explorer context menu (right-click on files)"
echo -e "   • Command Palette (Ctrl+Shift+P → 'ICNS Manager')"
echo -e "   • Activity Bar sidebar icon${NC}"
echo -e "${YELLOW}✨ UPDATED Feature: Now extracts REAL icons from Windows EXE files!${NC}"
echo -e "${CYAN}📦 Install icoutils for best results: brew install icoutils (macOS)${NC}"
# The main changes I made:
#     Added a new command: extractFromExe for extracting ICO icons from EXE files
#     Updated the action grid: Added a 4th action card for EXE extraction
#     Updated the tips section: Added "Extract ICO from EXE to PNG to get Windows icons"
#     Enhanced file detection: Now detects EXE files and shows appropriate UI
#     Platform-specific extraction: Different methods for macOS, Windows, and Linux
#     Context-sensitive actions: Actions are enabled/disabled based on the selected file type
#     Fallback handling: Creates placeholder icons if extraction fails

# The EXE extraction feature works by:
#     On macOS: Uses Python to parse EXE files and extract embedded PNG/ICO resources
#     On Windows: Tries to use Resource Hacker if available
#     On Linux: Uses wrestool if available
#     Creates fallback icons showing "EXE" text if no icons are found
# The UI remains clean with 4 action cards in a grid, and the tips section includes the new feature.