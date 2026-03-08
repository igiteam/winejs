# WINEJS Digital Ocean Installer

A Firefox extension that adds a clean OS-style installation screen to Digital Ocean droplet terminals for one-click WINEJS deployment.

## 🚀 Features

### 🎯 One-Click Installation
- **Auto-detects** when you're connected to a droplet
- **Pre-filled defaults** for quick setup
- **Progress tracking** with visual feedback
- **Auto-detects** installation completion

### 📋 Configuration Popup
- **Domain setup** - Main domain for your WINEJS instance
- **SSL email** - For Let's Encrypt certificates
- **Download password** - Secure file access
- **PIN protection** - Optional 4-digit PIN for uploads
- **File extensions** - Customizable allowed file types

### 🖥️ OS-Style Interface
- **Glossy logo** with drop shadow effects
- **Progress bar** with elapsed timer
- **Scrollable log window** - Real-time installation output
- **Status messages** - Clear feedback at every step
- **Toggle button** - Hide/show the installer overlay

## 📦 Installation

### Step 1: Generate Extension
Run the generator script:
```bash
chmod +x winejs-generator.sh
./winejs-generator.sh

Step 2: Load in Firefox
    Open Firefox and go to about:debugging
    Click "This Firefox"
    Click "Load Temporary Add-on"
    Select the manifest.json file from the generated folder

Step 3: Use on Digital Ocean
    Navigate to your droplet terminal
    The installer overlay appears automatically
    Click "▶ START INSTALLATION"
    Configure your settings
    Watch the installation progress

🎮 How to Use
Method 1: Automatic Overlay
    Open any Digital Ocean droplet terminal
    The installer overlay appears automatically
    Wait for connection (progress bar shows connecting)
    Click start and configure

Method 2: Toolbar Button
    Click the WINEJS icon in Firefox toolbar
    Check status indicator
    Click "Open Installer" to show/hide the overlay

📁 File Structure
winejs-firefox-installer/
├── manifest.json      # Extension configuration
├── background.js      # Background script (audio, storage)
├── content.js         # Main installer script
├── styles.css         # All styling
├── popup.html         # Toolbar popup
├── popup.js          # Popup functionality
├── icons/            # Extension icons
│   ├── icon.png
│   └── icon128.png
└── README.md         # This file

🔧 Configuration
Default Settings
    Domain: wine.sdappnet.cloud
    Email: admin@wine.sdappnet.cloud
    Password: MyPassword12345
    File Extensions: .ms3d,.obj,.3ds,.fbx,.dae,.blend,.jpg,.png,.mp3,.wav,.mp4

PIN Protection
    Optional 4-digit PIN for upload security
    Enable/disable via checkbox
    Auto-focus on PIN input when enabled

🎯 Installation Process

    Connection Phase
        Monitors terminal for shell prompt
        Shows connecting status
        30-second timeout with error handling

    Configuration Phase
        Popup form with all settings
        Validation for each field
        Save settings to browser storage

    Installation Phase
        Injects curl command
        Monitors progress (PROGRESS: messages)
        Updates progress bar in real-time
        Logs all output to scrollable window

    Completion Phase
        Detects DOMAIN: output
        Shows "OPEN WINEJS" button
        Links directly to your instance
        Play success ping sound

🔐 Permissions Explained
    activeTab - Access current Digital Ocean tab
    storage - Save user preferences
    https://cloud.digitalocean.com/* - Digital Ocean terminal
    https://cdn.sdappnet.cloud/* - Download WINEJS scripts

🎨 UI Features
    Glossy logo with backdrop filter
    Progress bar with gradient fill
    Scrollable log with color-coded lines
    Responsive design - Works on all screen sizes
    Keyboard shortcuts - Enter to submit forms

⚡ Troubleshooting
Connection Issues
    ❌ "Failed to connect" - Check droplet is running
    ❌ "Connection timeout" - Refresh and try again
    ✅ Solution: Wait for droplet to fully boot

Installation Errors
    ❌ "Command not found" - Check curl is installed
    ❌ "Permission denied" - Use sudo (script handles this)
    ✅ Solution: Check droplet has internet access

Extension Issues
    ❌ Overlay not showing - Click toolbar icon
    ❌ Popup not working - Reload extension
    ✅ Solution: Go to about:debugging → Reload

🚀 Pro Tips
    Use defaults for quick testing
    Enable PIN for production uploads
    Custom extensions for your file types
    Toggle overlay when you need terminal access
    Reset button to start fresh installation

📝 License

MIT License - Free to use, modify, and distribute.

Note: Works with any Digital Ocean droplet running Ubuntu/Debian.
