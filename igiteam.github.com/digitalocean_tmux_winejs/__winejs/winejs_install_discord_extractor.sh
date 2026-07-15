#!/bin/bash
# ============================================
# DiscordChatExporter - WineJS Installer
# Adds Discord Channel Exporter to WineJS Platform
# ============================================
# App: DiscordChatExporter
# Category: Tools
# Features: Export Discord messages, Multiple formats, CLI & GUI options
# ============================================

APP_LOGO_URL="https://raw.githubusercontent.com/Tyrrrz/DiscordChatExporter/refs/heads/prime/favicon.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📥 Installing DiscordChatExporter for WineJS..."

# ============= VERIFY WINEJS PLATFORM =============
log "Verifying WineJS platform..."

if [ ! -d "/opt/winejs" ]; then
    error "WineJS platform not found at /opt/winejs"
fi

if [ ! -f "/opt/winejs/translator/index.js" ]; then
    error "WineJS translator not found. Please install WineJS first."
fi

# Ensure winejs-net network exists
log "Checking winejs-net network..."
if ! docker network inspect winejs-net &>/dev/null; then
    docker network create winejs-net
    log "✅ winejs-net network created"
fi

# ============= GET DOMAIN FROM WINEJS CONFIG =============
if [ -f "/opt/winejs/translator/index.js" ]; then
    DOMAIN_NAME=$(grep "const DOMAIN_NAME" /opt/winejs/translator/index.js | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/")
fi

if [ -z "$DOMAIN_NAME" ]; then
    read -p "Enter your WineJS domain: " DOMAIN_NAME
fi

info "Using domain: $DOMAIN_NAME"

# ============= ASK FOR DISCORD CONFIGURATION =============
echo ""
info "📝 DiscordChatExporter Configuration"
echo "================================================"
read -p "Discord Token (required): " DISCORD_TOKEN

if [ -z "$DISCORD_TOKEN" ]; then
    error "Discord token is required!"
fi

read -p "Server/Guild ID (optional, for quick export): " GUILD_ID
read -p "Channel ID (optional, for quick export): " CHANNEL_ID
read -p "Default export format [HtmlDark]: " EXPORT_FORMAT
EXPORT_FORMAT=${EXPORT_FORMAT:-"HtmlDark"}

info "Available formats: HtmlDark, HtmlLight, PlainText, Json, Csv"

read -p "Download media attachments? (true/false) [false]: " DOWNLOAD_MEDIA
DOWNLOAD_MEDIA=${DOWNLOAD_MEDIA:-"false"}

read -p "Default output directory [/opt/winejs/data/discord-exports]: " OUTPUT_DIR
OUTPUT_DIR=${OUTPUT_DIR:-"/opt/winejs/data/discord-exports"}

# ============= CREATE APP DIRECTORIES =============
APP_NAME="discord-exporter"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/discord-exporter"
CONFIG_DIR="/opt/winejs/config/discord-exporter"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$ICON_DIR" "$OUTPUT_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/discord-exporter"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  winejs-discord-exporter-web:
    image: nginx:alpine
    container_name: winejs-${APP_NAME}-web
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ${APP_DIR}/web:/usr/share/nginx/html:ro
    networks:
      - winejs-net
    depends_on:
      - winejs-discord-exporter-api

  winejs-discord-exporter-api:
    build: ${APP_DIR}/api
    container_name: winejs-${APP_NAME}-api
    restart: unless-stopped
    environment:
      - OUTPUT_DIR=${OUTPUT_DIR}
      - DOMAIN_NAME=${DOMAIN_NAME}
    volumes:
      - ${OUTPUT_DIR}:/exports
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE WEB INTERFACE =============
log "📄 Creating web interface..."

mkdir -p "$APP_DIR/web/css" "$APP_DIR/web/js"

# Create CSS
cat > "$APP_DIR/web/css/style.css" << 'CSS_EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    background: linear-gradient(135deg, #1e1e2e 0%, #181825 100%);
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    color: #cdd6f4;
    min-height: 100vh;
}

.container {
    max-width: 1600px;
    margin: 0 auto;
    padding: 20px;
}

.header {
    background: #11111b;
    border-radius: 12px;
    padding: 24px;
    margin-bottom: 30px;
    border: 1px solid #313244;
    box-shadow: 0 4px 12px rgba(0,0,0,0.3);
}

.header h1 {
    font-size: 28px;
    margin-bottom: 8px;
    display: flex;
    align-items: center;
    gap: 12px;
}

.header h1 img {
    width: 40px;
    height: 40px;
}

.header p {
    color: #6c7086;
    font-size: 14px;
}

.card {
    background: #1e1e2e;
    border-radius: 12px;
    padding: 24px;
    margin-bottom: 24px;
    border: 1px solid #313244;
    transition: transform 0.2s, box-shadow 0.2s;
}

.card:hover {
    box-shadow: 0 6px 16px rgba(0,0,0,0.3);
}

.card h2 {
    font-size: 20px;
    margin-bottom: 20px;
    color: #89b4fa;
    border-left: 3px solid #89b4fa;
    padding-left: 12px;
}

.form-group {
    margin-bottom: 16px;
}

.form-group label {
    display: block;
    margin-bottom: 6px;
    font-size: 13px;
    font-weight: 500;
    color: #a6adc8;
}

.form-group input, .form-group select, .form-group textarea {
    width: 100%;
    padding: 10px 12px;
    background: #11111b;
    border: 1px solid #313244;
    border-radius: 8px;
    color: #cdd6f4;
    font-size: 14px;
    transition: border-color 0.2s;
}

.form-group input:focus, .form-group select:focus, .form-group textarea:focus {
    outline: none;
    border-color: #89b4fa;
}

.form-group input[type="password"] {
    font-family: monospace;
}

.form-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 16px;
}

.btn {
    padding: 10px 20px;
    border-radius: 8px;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s;
    border: none;
    display: inline-flex;
    align-items: center;
    gap: 8px;
}

.btn-primary {
    background: #89b4fa;
    color: #1e1e2e;
}

.btn-primary:hover {
    background: #b4befe;
    transform: translateY(-1px);
}

.btn-success {
    background: #a6e3a1;
    color: #1e1e2e;
}

.btn-danger {
    background: #f38ba8;
    color: #1e1e2e;
}

.btn-secondary {
    background: #313244;
    color: #cdd6f4;
}

.btn-secondary:hover {
    background: #45475a;
}

.btn-group {
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
    margin-top: 16px;
}

.output-area {
    background: #11111b;
    border-radius: 8px;
    padding: 16px;
    margin-top: 16px;
    max-height: 400px;
    overflow-y: auto;
    font-family: 'Courier New', monospace;
    font-size: 12px;
    border: 1px solid #313244;
}

.log-line {
    padding: 4px 0;
    border-bottom: 1px solid #1e1e2e;
    font-family: monospace;
}

.log-info { color: #89b4fa; }
.log-success { color: #a6e3a1; }
.log-error { color: #f38ba8; }
.log-warning { color: #f9e2af; }

.progress-container {
    margin-top: 16px;
    display: none;
}

.progress-bar {
    width: 100%;
    height: 4px;
    background: #313244;
    border-radius: 2px;
    overflow: hidden;
}

.progress-fill {
    height: 100%;
    background: #89b4fa;
    width: 0%;
    transition: width 0.3s;
    border-radius: 2px;
}

/* Exports list styles */
.exports-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
    gap: 16px;
    margin-top: 16px;
}

.export-item {
    background: #11111b;
    border: 1px solid #313244;
    border-radius: 10px;
    padding: 16px;
    transition: all 0.2s;
}

.export-item:hover {
    border-color: #89b4fa;
    transform: translateY(-2px);
}

.export-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 12px;
    padding-bottom: 8px;
    border-bottom: 1px solid #313244;
}

.export-type {
    font-size: 12px;
    padding: 4px 8px;
    border-radius: 6px;
    background: #1e1e2e;
    color: #89b4fa;
}

.export-date {
    font-size: 11px;
    color: #6c7086;
}

.export-name {
    font-weight: 600;
    margin-bottom: 8px;
    word-break: break-all;
}

.export-name code {
    background: #1e1e2e;
    padding: 2px 6px;
    border-radius: 4px;
    font-size: 11px;
}

.export-files {
    margin: 12px 0;
    max-height: 150px;
    overflow-y: auto;
}

.file-link {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 8px;
    margin: 4px 0;
    background: #1e1e2e;
    border-radius: 6px;
    text-decoration: none;
    color: #a6e3a1;
    font-size: 12px;
    font-family: monospace;
    transition: background 0.2s;
}

.file-link:hover {
    background: #313244;
    color: #89b4fa;
}

.file-link .file-icon {
    font-size: 14px;
}

.file-link .file-size {
    margin-left: auto;
    color: #6c7086;
    font-size: 10px;
}

.export-actions {
    display: flex;
    gap: 8px;
    margin-top: 12px;
    padding-top: 8px;
    border-top: 1px solid #313244;
}

.export-actions button {
    flex: 1;
    padding: 6px 12px;
    font-size: 12px;
}

.empty-state {
    text-align: center;
    padding: 60px;
    color: #6c7086;
}

.empty-state .emoji {
    font-size: 48px;
    margin-bottom: 16px;
}

.modal {
    display: none;
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(0,0,0,0.8);
    z-index: 1000;
    justify-content: center;
    align-items: center;
}

.modal-content {
    background: #1e1e2e;
    border-radius: 12px;
    padding: 24px;
    max-width: 500px;
    width: 90%;
    border: 1px solid #313244;
}

.modal-buttons {
    display: flex;
    gap: 10px;
    justify-content: flex-end;
    margin-top: 16px;
}

.alert {
    position: fixed;
    bottom: 20px;
    right: 20px;
    background: #313244;
    padding: 12px 20px;
    border-radius: 8px;
    z-index: 1001;
    animation: slideIn 0.3s ease;
}

.alert-success { background: #a6e3a1; color: #1e1e2e; }
.alert-error { background: #f38ba8; color: #1e1e2e; }
.alert-info { background: #89b4fa; color: #1e1e2e; }

@keyframes slideIn {
    from { transform: translateX(100%); opacity: 0; }
    to { transform: translateX(0); opacity: 1; }
}

.footer {
    text-align: center;
    padding: 20px;
    color: #6c7086;
    font-size: 12px;
    border-top: 1px solid #313244;
    margin-top: 30px;
}

.footer a {
    color: #89b4fa;
    text-decoration: none;
}

@media (max-width: 768px) {
    .container { padding: 12px; }
    .form-row { grid-template-columns: 1fr; }
    .exports-grid { grid-template-columns: 1fr; }
}
CSS_EOF

# Create JavaScript
cat > "$APP_DIR/web/js/app.js" << 'JS_EOF'
let currentExportRunning = false;

function showAlert(message, type = 'info') {
    const alert = document.createElement('div');
    alert.className = `alert alert-${type}`;
    alert.textContent = message;
    document.body.appendChild(alert);
    setTimeout(() => alert.remove(), 3000);
}

function addLog(message, type = 'info') {
    const output = document.getElementById('output');
    const line = document.createElement('div');
    line.className = `log-line log-${type}`;
    line.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
    output.appendChild(line);
    line.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

function clearLogs() {
    document.getElementById('output').innerHTML = '';
    addLog('Logs cleared', 'info');
}

function saveConfig() {
    const config = {
        token: document.getElementById('token').value,
        guildId: document.getElementById('guildId').value,
        channelId: document.getElementById('channelId').value,
        format: document.getElementById('format').value,
        downloadMedia: document.getElementById('downloadMedia').value,
        outputDir: document.getElementById('outputDir').value,
        beforeDate: document.getElementById('beforeDate').value,
        afterDate: document.getElementById('afterDate').value,
        filter: document.getElementById('filter').value
    };
    localStorage.setItem('discordExporterConfig', JSON.stringify(config));
    showAlert('Configuration saved!', 'success');
}

function loadConfig() {
    const saved = localStorage.getItem('discordExporterConfig');
    if (saved) {
        const config = JSON.parse(saved);
        document.getElementById('token').value = config.token || '';
        document.getElementById('guildId').value = config.guildId || '';
        document.getElementById('channelId').value = config.channelId || '';
        document.getElementById('format').value = config.format || 'HtmlDark';
        document.getElementById('downloadMedia').value = config.downloadMedia || 'false';
        document.getElementById('outputDir').value = config.outputDir || '/opt/winejs/data/discord-exports';
        document.getElementById('beforeDate').value = config.beforeDate || '';
        document.getElementById('afterDate').value = config.afterDate || '';
        document.getElementById('filter').value = config.filter || '';
    }
}

async function startExport(type, id) {
    currentExportRunning = true;
    document.getElementById('progressContainer').style.display = 'block';
    addLog(`Starting ${type} export...`, 'info');
    
    const token = document.getElementById('token').value;
    if (!token) {
        addLog('ERROR: No token provided!', 'error');
        showAlert('Please enter your Discord token', 'error');
        currentExportRunning = false;
        document.getElementById('progressContainer').style.display = 'none';
        return;
    }
    
    const config = {
        token: token,
        type: type,
        id: id,
        format: document.getElementById('format').value,
        downloadMedia: document.getElementById('downloadMedia').value === 'true',
        outputDir: document.getElementById('outputDir').value,
        beforeDate: document.getElementById('beforeDate').value,
        afterDate: document.getElementById('afterDate').value,
        filter: document.getElementById('filter').value
    };
    
    try {
        const response = await fetch('/discord-exporter/api/export', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(config)
        });
        
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        
        while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            
            const text = decoder.decode(value);
            const lines = text.split('\n');
            
            for (const line of lines) {
                if (line.startsWith('data: ')) {
                    const data = JSON.parse(line.slice(6));
                    addLog(data.message, data.type || 'info');
                    
                    if (data.complete) {
                        showAlert('Export completed successfully!', 'success');
                        refreshExports();
                    }
                }
            }
        }
    } catch (error) {
        addLog(`ERROR: ${error.message}`, 'error');
        showAlert(`Export failed: ${error.message}`, 'error');
    }
    
    currentExportRunning = false;
    document.getElementById('progressContainer').style.display = 'none';
    document.getElementById('progressFill').style.width = '0%';
}

function exportChannel() {
    const channelId = document.getElementById('channelId').value;
    if (!channelId) {
        showAlert('Please enter a Channel ID', 'error');
        return;
    }
    startExport('channel', channelId);
}

function exportGuild() {
    const guildId = document.getElementById('guildId').value;
    if (!guildId) {
        showAlert('Please enter a Server/Guild ID', 'error');
        return;
    }
    startExport('guild', guildId);
}

function exportDMs() {
    startExport('dm', null);
}

function exportAll() {
    startExport('all', null);
}

async function listServers() {
    const token = document.getElementById('token').value;
    if (!token) {
        showAlert('Please enter your Discord token', 'error');
        return;
    }
    
    addLog('Fetching accessible servers...', 'info');
    
    try {
        const response = await fetch('/discord-exporter/api/servers', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ token: token })
        });
        
        const data = await response.json();
        
        if (data.servers && data.servers.length > 0) {
            addLog(`Found ${data.servers.length} servers:`, 'success');
            data.servers.forEach(server => {
                addLog(`  - ${server.name} (ID: ${server.id})`, 'info');
            });
        } else {
            addLog('No servers found or invalid token', 'warning');
        }
    } catch (error) {
        addLog(`Error fetching servers: ${error.message}`, 'error');
    }
}

async function listChannels() {
    const token = document.getElementById('token').value;
    const guildId = document.getElementById('guildId').value;
    
    if (!token || !guildId) {
        showAlert('Please enter both token and server ID', 'error');
        return;
    }
    
    addLog(`Fetching channels for guild ${guildId}...`, 'info');
    
    try {
        const response = await fetch('/discord-exporter/api/channels', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ token: token, guildId: guildId })
        });
        
        const data = await response.json();
        
        if (data.channels && data.channels.length > 0) {
            addLog(`Found ${data.channels.length} channels:`, 'success');
            data.channels.forEach(channel => {
                const type = channel.type === 0 ? '📝 Text' : '🎙️ Voice';
                addLog(`  ${type} - ${channel.name} (ID: ${channel.id})`, 'info');
            });
        } else {
            addLog('No channels found', 'warning');
        }
    } catch (error) {
        addLog(`Error fetching channels: ${error.message}`, 'error');
    }
}

async function refreshExports() {
    const exportsList = document.getElementById('exportsList');
    exportsList.innerHTML = '<div style="text-align: center; padding: 40px; color: #6c7086;">Loading exports...</div>';
    
    try {
        const response = await fetch('/discord-exporter/api/exports');
        const data = await response.json();
        
        if (data.exports && data.exports.length > 0) {
            renderExports(data.exports);
        } else {
            exportsList.innerHTML = `
                <div class="empty-state">
                    <div class="emoji">📭</div>
                    <div>No exports found</div>
                    <div style="font-size: 12px; margin-top: 8px;">Run an export above to get started</div>
                </div>
            `;
        }
    } catch (error) {
        console.error('Failed to load exports:', error);
        exportsList.innerHTML = `
            <div class="empty-state">
                <div class="emoji">⚠️</div>
                <div>Failed to load exports</div>
                <div style="font-size: 12px; margin-top: 8px;">${error.message}</div>
            </div>
        `;
    }
}

function formatFileSize(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function renderExports(exports) {
    const exportsList = document.getElementById('exportsList');
    
    const html = `
        <div class="exports-grid">
            ${exports.map(exp => `
                <div class="export-item">
                    <div class="export-header">
                        <span class="export-type">${exp.type}</span>
                        <span class="export-date">${exp.date}</span>
                    </div>
                    <div class="export-name">
                        <code>${exp.id || 'N/A'}</code>
                    </div>
                    <div class="export-files">
                        ${exp.files.map(file => `
                            <a href="/exports/${file.name}" class="file-link" download="${file.name}" target="_blank">
                                <span class="file-icon">${getFileIcon(file.extension)}</span>
                                <span>${file.name}</span>
                                <span class="file-size">${formatFileSize(file.size)}</span>
                            </a>
                        `).join('')}
                    </div>
                    <div class="export-actions">
                        <button class="btn btn-secondary" onclick="downloadExportAsZip('${exp.folder}')">📦 Download All as ZIP</button>
                        <button class="btn btn-danger" onclick="deleteExport('${exp.folder}')">🗑️ Delete</button>
                    </div>
                </div>
            `).join('')}
        </div>
    `;
    
    exportsList.innerHTML = html;
}

function getFileIcon(extension) {
    const icons = {
        '.html': '🌐',
        '.htm': '🌐',
        '.json': '📊',
        '.txt': '📝',
        '.csv': '📈',
        '.zip': '📦',
        '.png': '🖼️',
        '.jpg': '🖼️',
        '.jpeg': '🖼️',
        '.gif': '🖼️'
    };
    return icons[extension.toLowerCase()] || '📄';
}

async function deleteExport(folder) {
    if (!confirm(`Are you sure you want to delete this export? This action cannot be undone.`)) {
        return;
    }
    
    try {
        const response = await fetch('/discord-exporter/api/delete-export', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ folder: folder })
        });
        
        const data = await response.json();
        
        if (data.success) {
            showAlert('Export deleted successfully!', 'success');
            refreshExports();
        } else {
            showAlert('Failed to delete export: ' + data.error, 'error');
        }
    } catch (error) {
        showAlert('Error deleting export: ' + error.message, 'error');
    }
}

async function deleteAllExports() {
    if (!confirm(`⚠️ WARNING: This will delete ALL exports. This action cannot be undone.\n\nAre you absolutely sure?`)) {
        return;
    }
    
    try {
        const response = await fetch('/discord-exporter/api/delete-all-exports', {
            method: 'POST'
        });
        
        const data = await response.json();
        
        if (data.success) {
            showAlert('All exports deleted successfully!', 'success');
            refreshExports();
        } else {
            showAlert('Failed to delete exports: ' + data.error, 'error');
        }
    } catch (error) {
        showAlert('Error deleting exports: ' + error.message, 'error');
    }
}

async function downloadExportAsZip(folder) {
    showAlert('Preparing ZIP download...', 'info');
    
    try {
        const response = await fetch('/discord-exporter/api/download-zip', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ folder: folder })
        });
        
        const blob = await response.blob();
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${folder}.zip`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        window.URL.revokeObjectURL(url);
        
        showAlert('Download started!', 'success');
    } catch (error) {
        showAlert('Failed to create ZIP: ' + error.message, 'error');
    }
}

function copyToClipboard(text) {
    navigator.clipboard.writeText(text);
    showAlert('Copied to clipboard!', 'success');
}

function showTokenHelp() {
    document.getElementById('tokenHelpModal').style.display = 'flex';
}

function closeModal() {
    document.getElementById('tokenHelpModal').style.display = 'none';
}

document.addEventListener('DOMContentLoaded', () => {
    loadConfig();
    refreshExports();
    
    const inputs = ['token', 'guildId', 'channelId', 'format', 'downloadMedia', 'outputDir', 'beforeDate', 'afterDate', 'filter'];
    inputs.forEach(id => {
        const el = document.getElementById(id);
        if (el) {
            el.addEventListener('change', saveConfig);
            el.addEventListener('input', saveConfig);
        }
    });
    
    setInterval(refreshExports, 30000);
});
JS_EOF

# Create main HTML
cat > "$APP_DIR/web/index.html" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DiscordChatExporter - WineJS</title>
    <link rel="stylesheet" href="/css/style.css">
    <link rel="icon" type="image/png" href="https://cdn.jsdelivr.net/gh/Tyrrrz/DiscordChatExporter/master/.assets/icon.png">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>
                <img src="https://cdn.jsdelivr.net/gh/Tyrrrz/DiscordChatExporter/master/.assets/icon.png" alt="Icon">
                DiscordChatExporter
            </h1>
            <p>Export Discord messages to HTML, JSON, CSV, or Plain Text</p>
        </div>
        
        <!-- Configuration Card -->
        <div class="card">
            <h2>⚙️ Configuration</h2>
            <div class="form-group">
                <label>🔑 Discord Token *</label>
                <input type="password" id="token" placeholder="Enter your Discord user token">
                <small style="color: #f38ba8;">⚠️ Automating user accounts violates Discord ToS - use at your own risk!</small>
                <button class="btn btn-secondary" style="margin-top: 8px;" onclick="showTokenHelp()">❓ How to get token</button>
            </div>
            
            <div class="form-row">
                <div class="form-group">
                    <label>🏢 Server/Guild ID</label>
                    <input type="text" id="guildId" placeholder="Optional for quick export">
                </div>
                <div class="form-group">
                    <label>💬 Channel ID</label>
                    <input type="text" id="channelId" placeholder="Optional for quick export">
                </div>
            </div>
            
            <div class="form-row">
                <div class="form-group">
                    <label>📄 Export Format</label>
                    <select id="format">
                        <option value="HtmlDark">HTML Dark Theme</option>
                        <option value="HtmlLight">HTML Light Theme</option>
                        <option value="PlainText">Plain Text</option>
                        <option value="Json">JSON</option>
                        <option value="Csv">CSV</option>
                    </select>
                </div>
                <div class="form-group">
                    <label>📎 Download Media</label>
                    <select id="downloadMedia">
                        <option value="false">No</option>
                        <option value="true">Yes (slower, larger files)</option>
                    </select>
                </div>
            </div>
            
            <div class="form-group">
                <label>📁 Output Directory</label>
                <input type="text" id="outputDir" placeholder="/opt/winejs/data/discord-exports">
            </div>
            
            <div class="form-row">
                <div class="form-group">
                    <label>📅 After Date (optional)</label>
                    <input type="text" id="afterDate" placeholder="2024-01-01 or 2024-01-01 23:34">
                </div>
                <div class="form-group">
                    <label>📅 Before Date (optional)</label>
                    <input type="text" id="beforeDate" placeholder="2024-12-31">
                </div>
            </div>
            
            <div class="form-group">
                <label>🔍 Message Filter (optional)</label>
                <input type="text" id="filter" placeholder="from:username has:image">
                <small>Examples: "from:Tyrrrz", "has:image", "hello world", "from:user1 | from:user2"</small>
            </div>
        </div>
        
        <!-- Export Actions Card -->
        <div class="card">
            <h2>🚀 Export Actions</h2>
            <div class="btn-group">
                <button class="btn btn-primary" onclick="exportChannel()">📝 Export Current Channel</button>
                <button class="btn btn-primary" onclick="exportGuild()">🏢 Export Entire Server</button>
                <button class="btn btn-primary" onclick="exportDMs()">💬 Export All DMs</button>
                <button class="btn btn-warning" onclick="exportAll()">🌐 Export All Accessible Channels</button>
            </div>
            
            <div class="btn-group">
                <button class="btn btn-secondary" onclick="listServers()">📋 List My Servers</button>
                <button class="btn btn-secondary" onclick="listChannels()">📋 List Channels in Server</button>
                <button class="btn btn-secondary" onclick="clearLogs()">🗑️ Clear Logs</button>
                <button class="btn btn-secondary" onclick="saveConfig()">💾 Save Config</button>
            </div>
            
            <div class="progress-container" id="progressContainer">
                <div class="progress-bar">
                    <div class="progress-fill" id="progressFill"></div>
                </div>
            </div>
            
            <div class="output-area" id="output">
                <div class="log-line log-info">[System] Ready to export Discord channels...</div>
            </div>
        </div>
        
        <!-- Saved Exports Card -->
        <div class="card">
            <h2>📁 Saved Exports</h2>
            <div style="margin-bottom: 16px;">
                <button class="btn btn-secondary" onclick="refreshExports()" style="margin-right: 10px;">🔄 Refresh List</button>
                <button class="btn btn-danger" onclick="deleteAllExports()">🗑️ Delete All Exports</button>
            </div>
            <div id="exportsList">
                <div style="text-align: center; padding: 40px; color: #6c7086;">
                    Loading exports...
                </div>
            </div>
        </div>
        
        <!-- Token Help Modal -->
        <div id="tokenHelpModal" class="modal" onclick="if(event.target===this)closeModal()">
            <div class="modal-content">
                <h3>🔑 How to get your Discord Token</h3>
                <p>⚠️ <strong>Warning:</strong> Automating user accounts violates Discord ToS!</p>
                <ol style="margin: 16px 0 16px 20px;">
                    <li>Open Discord in your web browser</li>
                    <li>Press <code>Ctrl+Shift+I</code> (Windows) or <code>Cmd+Option+I</code> (Mac)</li>
                    <li>Go to the <strong>Network</strong> tab</li>
                    <li>Press <code>F5</code> to refresh</li>
                    <li>Type <code>messages</code> in the filter box</li>
                    <li>Click on any <code>messages?limit=50</code> request</li>
                    <li>Find <strong>authorization</strong> in Request Headers</li>
                    <li>Copy the value - that's your token!</li>
                </ol>
                <div class="modal-buttons">
                    <button class="btn btn-secondary" onclick="closeModal()">Close</button>
                </div>
            </div>
        </div>
        
        <div class="footer">
            Powered by WineJS Platform | <a href="https://github.com/Tyrrrz/DiscordChatExporter" target="_blank">DiscordChatExporter on GitHub</a>
        </div>
    </div>
    
    <script src="/js/app.js"></script>
</body>
</html>
HTML_EOF

# ============= CREATE BACKEND API SERVICE =============
log "📝 Creating backend API service..."

mkdir -p "$APP_DIR/api"

cat > "$APP_DIR/api/server.js" << 'API_EOF'
const express = require('express');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const cors = require('cors');
const archiver = require('archiver');

const app = express();
const PORT = 3001;
const OUTPUT_DIR = process.env.OUTPUT_DIR || '/opt/winejs/data/discord-exports';

app.use(cors());
app.use(express.json());

if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

app.get('/discord-exporter/api/ip', (req, res) => {
    const { networkInterfaces } = require('os');
    const interfaces = networkInterfaces();
    let ip = 'localhost';
    
    for (const iface of Object.values(interfaces)) {
        for (const addr of iface) {
            if (addr.family === 'IPv4' && !addr.internal) {
                ip = addr.address;
                break;
            }
        }
    }
    
    res.json({ ip, domain: process.env.DOMAIN_NAME || 'localhost' });
});

app.post('/discord-exporter/api/servers', (req, res) => {
    const { token } = req.body;
    if (!token) return res.status(400).json({ error: 'Token required' });
    
    exec(`DiscordChatExporter.Cli guilds -t "${token}"`, { cwd: '/app' }, (error, stdout) => {
        if (error) return res.status(500).json({ error: error.message });
        
        const lines = stdout.split('\n').filter(l => l.trim());
        const servers = [];
        
        for (const line of lines) {
            const match = line.match(/(.+?)\s*\(ID:\s*(\d+)\)/);
            if (match) servers.push({ name: match[1].trim(), id: match[2] });
        }
        res.json({ servers });
    });
});

app.post('/discord-exporter/api/channels', (req, res) => {
    const { token, guildId } = req.body;
    if (!token || !guildId) return res.status(400).json({ error: 'Token and Guild ID required' });
    
    exec(`DiscordChatExporter.Cli channels -g "${guildId}" -t "${token}"`, { cwd: '/app' }, (error, stdout) => {
        if (error) return res.status(500).json({ error: error.message });
        
        const lines = stdout.split('\n').filter(l => l.trim());
        const channels = [];
        
        for (const line of lines) {
            const idMatch = line.match(/ID:\s*(\d+)/);
            const nameMatch = line.match(/^(.+?)\s*\(/);
            const typeMatch = line.match(/\((Text|Voice|Category)\)/);
            
            if (idMatch) {
                channels.push({
                    name: nameMatch ? nameMatch[1].trim() : 'Unknown',
                    type: typeMatch ? typeMatch[1] : 'Unknown',
                    id: idMatch[1]
                });
            }
        }
        res.json({ channels });
    });
});

app.post('/discord-exporter/api/export', (req, res) => {
    const { token, type, id, format, downloadMedia, outputDir, beforeDate, afterDate, filter } = req.body;
    
    if (!token) return res.status(400).json({ error: 'Token required' });
    
    const exportDir = outputDir || OUTPUT_DIR;
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    let command = '';
    let outputPath = '';
    
    switch (type) {
        case 'channel':
            if (!id) return res.status(400).json({ error: 'Channel ID required' });
            outputPath = path.join(exportDir, `channel_${id}_${timestamp}`);
            command = `DiscordChatExporter.Cli export -c "${id}" -t "${token}" -f ${format} -o "${outputPath}"`;
            break;
        case 'guild':
            if (!id) return res.status(400).json({ error: 'Guild ID required' });
            outputPath = path.join(exportDir, `guild_${id}_${timestamp}`);
            command = `DiscordChatExporter.Cli exportguild -g "${id}" -t "${token}" -f ${format} -o "${outputPath}"`;
            break;
        case 'dm':
            outputPath = path.join(exportDir, `dms_${timestamp}`);
            command = `DiscordChatExporter.Cli exportdm -t "${token}" -f ${format} -o "${outputPath}"`;
            break;
        case 'all':
            outputPath = path.join(exportDir, `all_${timestamp}`);
            command = `DiscordChatExporter.Cli exportall -t "${token}" -f ${format} -o "${outputPath}"`;
            break;
        default:
            return res.status(400).json({ error: 'Invalid export type' });
    }
    
    if (downloadMedia === 'true' || downloadMedia === true) command += ' --media';
    if (beforeDate) command += ` --before "${beforeDate}"`;
    if (afterDate) command += ` --after "${afterDate}"`;
    if (filter) command += ` --filter "${filter.replace(/"/g, '\\"')}"`;
    
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    
    res.write(`data: ${JSON.stringify({ message: `Starting export...`, type: 'info' })}\n\n`);
    
    const proc = exec(command, { cwd: '/app', maxBuffer: 50 * 1024 * 1024 });
    
    proc.stdout.on('data', (data) => {
        const lines = data.toString().split('\n');
        for (const line of lines) {
            if (line.trim()) {
                res.write(`data: ${JSON.stringify({ message: line.trim(), type: 'info' })}\n\n`);
            }
        }
    });
    
    proc.stderr.on('data', (data) => {
        res.write(`data: ${JSON.stringify({ message: data.toString().trim(), type: 'error' })}\n\n`);
    });
    
    proc.on('close', (code) => {
        if (code === 0) {
            res.write(`data: ${JSON.stringify({ message: `✅ Export completed! Saved to: ${outputPath}`, type: 'success', complete: true, outputPath })}\n\n`);
        } else {
            res.write(`data: ${JSON.stringify({ message: `❌ Export failed with code ${code}`, type: 'error', complete: true })}\n\n`);
        }
        res.end();
    });
});

app.get('/discord-exporter/api/exports', (req, res) => {
    if (!fs.existsSync(OUTPUT_DIR)) {
        return res.json({ exports: [] });
    }
    
    const items = fs.readdirSync(OUTPUT_DIR);
    const exports = [];
    
    for (const item of items) {
        const itemPath = path.join(OUTPUT_DIR, item);
        const stat = fs.statSync(itemPath);
        
        if (stat.isDirectory()) {
            const files = fs.readdirSync(itemPath);
            const fileInfos = [];
            
            for (const file of files) {
                const filePath = path.join(itemPath, file);
                const fileStat = fs.statSync(filePath);
                const ext = path.extname(file).toLowerCase();
                
                fileInfos.push({
                    name: `${item}/${file}`,
                    extension: ext,
                    size: fileStat.size,
                    modified: fileStat.mtime
                });
            }
            
            let type = 'unknown';
            if (item.startsWith('channel_')) type = '📝 Channel';
            else if (item.startsWith('guild_')) type = '🏢 Server';
            else if (item.startsWith('dms_')) type = '💬 DMs';
            else if (item.startsWith('all_')) type = '🌐 All';
            
            const idMatch = item.match(/(?:channel_|guild_)(\d+)/);
            const exportId = idMatch ? idMatch[1] : null;
            
            exports.push({
                folder: item,
                type: type,
                id: exportId,
                date: stat.mtime.toLocaleString(),
                files: fileInfos
            });
        }
    }
    
    exports.sort((a, b) => new Date(b.date) - new Date(a.date));
    res.json({ exports });
});

app.post('/discord-exporter/api/delete-export', (req, res) => {
    const { folder } = req.body;
    if (!folder) return res.status(400).json({ error: 'Folder name required' });
    
    const folderPath = path.join(OUTPUT_DIR, folder);
    
    if (!fs.existsSync(folderPath)) {
        return res.status(404).json({ error: 'Export not found' });
    }
    
    try {
        fs.rmSync(folderPath, { recursive: true, force: true });
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.post('/discord-exporter/api/delete-all-exports', (req, res) => {
    if (!fs.existsSync(OUTPUT_DIR)) {
        return res.json({ success: true });
    }
    
    try {
        const items = fs.readdirSync(OUTPUT_DIR);
        for (const item of items) {
            const itemPath = path.join(OUTPUT_DIR, item);
            fs.rmSync(itemPath, { recursive: true, force: true });
        }
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.post('/discord-exporter/api/download-zip', (req, res) => {
    const { folder } = req.body;
    if (!folder) return res.status(400).json({ error: 'Folder name required' });
    
    const folderPath = path.join(OUTPUT_DIR, folder);
    
    if (!fs.existsSync(folderPath)) {
        return res.status(404).json({ error: 'Export not found' });
    }
    
    res.setHeader('Content-Type', 'application/zip');
    res.setHeader('Content-Disposition', `attachment; filename="${folder}.zip"`);
    
    const archive = archiver('zip', { zlib: { level: 9 } });
    archive.on('error', (err) => {
        res.status(500).json({ error: err.message });
    });
    
    archive.pipe(res);
    archive.directory(folderPath, false);
    archive.finalize();
});

app.listen(PORT, () => {
    console.log(`DiscordChatExporter API running on port ${PORT}`);
});
API_EOF

# Create Dockerfile for API
cat > "$APP_DIR/api/Dockerfile" << 'DOCKERFILE_EOF'
FROM mcr.microsoft.com/dotnet/runtime:8.0

RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/Tyrrrz/DiscordChatExporter/releases/latest/download/DiscordChatExporter.Cli.linux-x64.zip \
    && unzip DiscordChatExporter.Cli.linux-x64.zip -d /app \
    && chmod +x /app/DiscordChatExporter.Cli \
    && rm DiscordChatExporter.Cli.linux-x64.zip

RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs

WORKDIR /api

COPY package*.json ./
RUN npm install

COPY server.js .

EXPOSE 3001

CMD ["node", "server.js"]
DOCKERFILE_EOF

# Create package.json for API
cat > "$APP_DIR/api/package.json" << 'PACKAGE_EOF'
{
    "name": "discord-exporter-api",
    "version": "1.0.0",
    "description": "DiscordChatExporter API for WineJS",
    "main": "server.js",
    "scripts": {
        "start": "node server.js"
    },
    "dependencies": {
        "express": "^4.18.2",
        "cors": "^2.8.5",
        "archiver": "^6.0.0"
    }
}
PACKAGE_EOF

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "DiscordChatExporter",
    "version": "latest",
    "description": "Export Discord messages to HTML, JSON, CSV, or Plain Text. View and download all your saved exports.",
    "executable": "launch.sh",
    "port": 8080,
    "vnc_password": "",
    "icon": "/icons/discord-exporter.png",
    "category": "Tools",
    "features": [
        "📝 Export Discord messages to multiple formats",
        "🏢 Export entire servers or specific channels",
        "💬 Export all direct messages",
        "📁 View all saved exports with download links",
        "📦 Download exports as ZIP files",
        "🗑️ Delete individual exports or all at once",
        "📎 Download and embed media attachments",
        "🔍 Advanced message filtering",
        "📅 Date range filtering",
        "💾 Save and reuse configurations"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading app icon..."
curl -L "$APP_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon, using default"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-discord-exporter << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
OUTPUT_DIR="${OUTPUT_DIR}"

case "\$1" in
    status)
        docker ps | grep winejs-discord-exporter
        ;;
    logs-web)
        docker logs winejs-${APP_NAME}-web --tail 50
        ;;
    logs-api)
        docker logs winejs-${APP_NAME}-api --tail 50
        ;;
    restart)
        docker restart winejs-${APP_NAME}-web
        docker restart winejs-${APP_NAME}-api
        echo "DiscordChatExporter restarted"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/discord-exporter/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/discord-exporter/"
        fi
        ;;
    output)
        echo "Export output directory: \$OUTPUT_DIR"
        ls -la "\$OUTPUT_DIR"
        ;;
    *)
        echo "DiscordChatExporter Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-discord-exporter open        - Open web interface"
        echo "  winejs-discord-exporter status      - Check server status"
        echo "  winejs-discord-exporter logs-web    - View web server logs"
        echo "  winejs-discord-exporter logs-api    - View API logs"
        echo "  winejs-discord-exporter restart     - Restart all services"
        echo "  winejs-discord-exporter output      - Show export directory"
        echo ""
        echo "Web Interface: https://\${DOMAIN_NAME}/discord-exporter/"
        echo "Export Directory: \$OUTPUT_DIR"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-discord-exporter

# ============= START CONTAINERS =============
log "🚀 Building and starting containers..."

cd "$INSTANCE_DIR"

docker build -t winejs-discord-exporter-api:latest "$APP_DIR/api" 2>&1 | tail -20
docker-compose down 2>/dev/null
docker-compose up -d

sleep 10

if docker ps | grep -q "winejs-${APP_NAME}-api"; then
    success "✅ API container started successfully"
else
    warn "⚠️ API container may not have started"
fi

if docker ps | grep -q "winejs-${APP_NAME}-web"; then
    success "✅ Web container started successfully"
else
    warn "⚠️ Web container may not have started"
fi

# ============= UPDATE NGINX =============
log "📝 Setting up nginx..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /discord-exporter" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        HTTPS_START=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$HTTPS_START" ]; then
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
                sed -i "${HTTPS_END}i\\
    # DiscordChatExporter Web Interface\n\
    location = /discord-exporter {\n\
        return 301 /discord-exporter/;\n\
    }\n\
    \n\
    location /discord-exporter/ {\n\
        proxy_pass http://127.0.0.1:8080/;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection 'upgrade';\n\
        proxy_set_header Host \\\$host;\n\
        proxy_cache_bypass \\\$http_upgrade;\n\
        proxy_buffering off;\n\
        proxy_read_timeout 300s;\n\
        sub_filter_once off;\n\
        sub_filter 'href=\"/' 'href=\"/discord-exporter/';\n\
        sub_filter 'src=\"/' 'src=\"/discord-exporter/';\n\
        sub_filter 'url(\\'/' 'url(/discord-exporter/';\n\
        sub_filter '\\"/api/' '\\"/discord-exporter/api/';\n\
    }\n\
    \n\
    location /discord-exporter/api/ {\n\
        proxy_pass http://127.0.0.1:3001/api/;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_buffering off;\n\
        proxy_read_timeout 300s;\n\
    }\n\
    \n\
    location /discord-exporter/exports/ {\n\
        alias ${OUTPUT_DIR}/;\n\
        autoindex on;\n\
    }\n" /etc/nginx/sites-available/winejs
                
                if nginx -t; then
                    systemctl reload nginx
                    log "✅ Nginx updated with DiscordChatExporter routes"
                else
                    warn "Nginx test failed, restoring backup"
                    cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                    nginx -t && systemctl reload nginx
                fi
            else
                warn "Could not find HTTPS block closing brace"
            fi
        else
            warn "Could not find HTTPS server block (listen 443)"
        fi
    else
        log "DiscordChatExporter routes already exist"
    fi
fi

# ============= RESTART TRANSLATOR =============
log "🔄 Restarting WineJS translator..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_discord-exporter.sh" << 'UNINSTALL_EOF'
#!/bin/bash
# WineJS DiscordChatExporter Uninstaller

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

log "🧹 Uninstalling DiscordChatExporter..."

# ============= STOP AND REMOVE DOCKER CONTAINERS =============
log "Stopping Docker containers..."

for container in winejs-discord-exporter-web winejs-discord-exporter-api; do
    if docker ps -a 2>/dev/null | grep -q "$container"; then
        log "Stopping $container..."
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
    fi
done

# ============= REMOVE APP DIRECTORIES =============
log "Removing app directories..."

APP_NAME="discord-exporter"
APP_DIR="/opt/winejs/apps/${APP_NAME}"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/${APP_NAME}"
EXPORTS_DATA="/opt/winejs/data/discord-exports"
CONFIG_DIR="/opt/winejs/config/${APP_NAME}"
ICON_FILE="/opt/winejs/translator/public/icons/${APP_NAME}.png"

[ -d "$INSTANCE_DIR" ] && rm -rf "$INSTANCE_DIR" && log "✅ Instance directory removed"
[ -d "$APP_DIR" ] && rm -rf "$APP_DIR" && log "✅ App directory removed"
[ -d "$EXPORTS_DATA" ] && rm -rf "$EXPORTS_DATA" && log "✅ Exports data removed"
[ -d "$CONFIG_DIR" ] && rm -rf "$CONFIG_DIR" && log "✅ Config directory removed"
[ -f "$ICON_FILE" ] && rm -f "$ICON_FILE" && log "✅ Icon removed"

# ============= REMOVE NGINX CONFIGURATION =============
log "Removing nginx configuration..."

NGINX_SITE="/etc/nginx/sites-available/winejs"

if [ -f "$NGINX_SITE" ]; then
    if grep -q "discord-exporter" "$NGINX_SITE"; then
        cp "$NGINX_SITE" "${NGINX_SITE}.backup.$(date +%Y%m%d_%H%M%S)"
        
        if command -v perl &> /dev/null; then
            perl -i -0777 -pe 's/^[[:space:]]*# DiscordChatExporter Web Interface.*?location \/discord-exporter\/\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
        else
            sed -i '/# DiscordChatExporter Web Interface/,/location \/discord-exporter\/ {/d' "$NGINX_SITE"
            sed -i '/location = \/discord-exporter {/,/^    }/d' "$NGINX_SITE"
            sed -i '/location \/api\/ {/,/^    }/d' "$NGINX_SITE"
        fi
        
        sed -i '/discord-exporter/d' "$NGINX_SITE"
        
        if nginx -t 2>/dev/null; then
            systemctl reload nginx
            log "✅ Nginx configuration updated"
        else
            warn "Nginx test failed, manual intervention may be needed"
        fi
    fi
fi

# ============= REMOVE HELPER SCRIPT =============
[ -f "/usr/local/bin/winejs-discord-exporter" ] && rm -f "/usr/local/bin/winejs-discord-exporter" && log "✅ Helper script removed"

# ============= RELOAD WINEJS TRANSLATOR =============
log "Reloading WineJS translator..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        DISCORDCHATEXPORTER UNINSTALLED SUCCESSFULLY!           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
log "✅ DiscordChatExporter has been completely removed"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_discord-exporter.sh"
log "✅ Uninstall script created"


# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           DISCORDCHATEXPORTER INSTALLED ON WINEJS!             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ DiscordChatExporter installed!"
echo ""
info "🌐 Web Interface:"
info "   • https://$DOMAIN_NAME/discord-exporter/"
echo ""
info "📁 Export Directory:"
info "   • $OUTPUT_DIR"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-discord-exporter open     # Open web interface"
info "   • winejs-discord-exporter status   # Check server status"
info "   • winejs-discord-exporter output   # Show export directory"
echo ""
info "⚠️ IMPORTANT:"
info "   • Using user tokens violates Discord ToS!"
info "   • Reset your token after use by changing password"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_discord-exporter.sh"
echo ""
success "✨ Ready! Visit https://$DOMAIN_NAME/discord-exporter/"
echo ""

# This creates a complete WineJS app with:
# Features:
#     Web-based interface to configure and run exports
#     Real-time progress tracking with server-sent events
#     Multiple export types: Channel, Guild, DMs, All channels
#     Format options: HtmlDark, HtmlLight, PlainText, Json, Csv
#     Media download option
#     Date range filtering
#     Message filtering (by user, content type, etc.)
#     Utility tools: List servers, list channels
#     CLI command generator for advanced users
#     Configuration save/load using localStorage

# To install:
#     Save the script as install-discord-exporter.sh
#     Make executable: chmod +x install-discord-exporter.sh
#     Run: sudo ./install-discord-exporter.sh
#     Enter your Discord token and other preferences
#     Access the web interface at https://your-domain/discord-exporter/

# ⚠️ Important:
#     Using user tokens violates Discord ToS
#     Reset your token after use by changing your Discord password
#     Consider using a bot token for production use

# The exported files will be saved to:
# Default Location:
# text

# /opt/winejs/data/discord-exports/

# During installation, you can customize it:

# When running the installer, you'll be prompted:
# text

# Default output directory [/opt/winejs/data/discord-exports]: 

# You can enter a custom path here, or press Enter to accept the default.
# File naming convention:

# The script creates organized folders with timestamps:
# text

# /opt/winejs/data/discord-exports/
# ├── channel_1010234248684392508_2026-06-04T22-30-15/
# │   └── channel.html (or .json, .txt, etc.)
# ├── guild_304618767068037120_2026-06-04T22-35-22/
# │   ├── general.html
# │   ├── random.html
# │   └── ...
# ├── dms_2026-06-04T22-40-10/
# │   ├── @username1.html
# │   └── @username2.html
# └── all_2026-06-04T22-45-33/
#     └── (all channels from all servers + DMs)

# To check your exports after running:
# bash

# # View the export directory
# ls -la /opt/winejs/data/discord-exports/

# # Or use the helper command
# winejs-discord-exporter output

# # Open the web interface to browse files
# winejs-discord-exporter open

# To change the output directory after installation:

# You can edit the web interface's "Output Directory" field before running an export - it will override the default for that specific export.
# To find specific exported files:
# bash

# # Find all HTML exports
# find /opt/winejs/data/discord-exports -name "*.html"

# # Find all JSON exports
# find /opt/winejs/data/discord-exports -name "*.json"

# # Search by channel ID
# find /opt/winejs/data/discord-exports -name "*1010234248684392508*"

# The exports are saved on your host machine (not inside the Docker container), so they persist even if you remove the Docker containers.