#!/bin/bash
# ============================================
# ofpigi.com - Operation Flashpoint Server Browser
# Installs game server list on root domain
# ============================================
# This script:
# 1. Creates nginx config for ofpigi.com
# 2. Sets up the server browser HTML/CSS/JS
# 3. Configures API proxy to OpenSpy
# ============================================

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🎮 Installing ofpigi.com Operation Flashpoint Server Browser..."

# ============= CONFIGURABLE API URL =============
# Ask user for OpenSpy API endpoint
echo ""
info "📡 OpenSpy API Configuration"
echo "================================"
read -p "Enter OpenSpy API URL [https://wine.ofpigi.com/openspy/api/servers?game=operationflashpoint]: " API_URL
API_URL=${API_URL:-"https://wine.ofpigi.com/openspy/api/servers?game=operationflashpoint"}
info "Using API endpoint: $API_URL"

# ============= GET DOMAIN INFO =============
DOMAIN="ofpigi.com"
WINEJS_DOMAIN="wine.ofpigi.com"

# Get server IP
SERVER_IP=$(curl -s ifconfig.me)
info "Server IP: $SERVER_IP"

# ============= CREATE WEB DIRECTORY =============
WEB_ROOT="/var/www/ofpigi"
mkdir -p "$WEB_ROOT"
log "✅ Created web root: $WEB_ROOT"

# ============= CREATE MASTER SERVERS LIST =============
log "📝 Creating master servers list..."

mkdir -p "$WEB_ROOT/api"
cat > "$WEB_ROOT/api/servers.txt" << 'EOF'
# Operation Flashpoint Master Servers
# Format: IP:PORT
# Add your game servers below:

# Example servers (replace with your actual servers)
# 165.232.107.127:2302
# 165.232.107.127:2303
EOF

# ============= CREATE THE SERVER BROWSER HTML =============
log "📝 Creating server browser HTML..."

cat > "$WEB_ROOT/index.html" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">

<head>
    <meta http-equiv="content-type" content="text/html; charset=UTF-8">
    <title>ofpigi.com - Operation Flashpoint Server Browser</title>

    <link rel="icon" href="https://cdn.gitgpt.chat/rtx/images/ofpigicom-icon.png" type="image/png">
    <link rel="apple-touch-icon" href="https://cdn.gitgpt.chat/rtx/images/ofpigicom-icon.png" sizes="180x180">
    <link rel="icon" type="image/png" href="https://cdn.gitgpt.chat/rtx/images/ofpigicom-icon.png" sizes="192x192">
    <link rel="icon" type="image/png" href="https://cdn.gitgpt.chat/rtx/images/ofpigicom-icon.png" sizes="512x512">
    <meta itemprop="name" content="ofpigi.com online server browser">
    <meta property="og:title" content="ofpigi.com online server browser">
    <meta property="og:url" content="https://ofpigi.com">
    <meta property="og:type" content="website">
    <meta name="twitter:title" content="ofpigi.com online server browser">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="theme-color" content="black">
    <meta charset="UTF-8">
    
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font: 700 14px 'Courier New', Courier, monospace;
            text-align: left;
            color: #0e9b0e;
            background-color: #000;
            min-height: 100vh;
            padding: 20px;
        }

        /* Retro Windows 95 / DOS style */
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }

        .title {
            font-size: 24px;
            margin-bottom: 20px;
            border-bottom: 2px solid #0e9b0e;
            padding-bottom: 10px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            flex-wrap: wrap;
            gap: 15px;
        }

        .title a {
            color: #0e9b0e;
            text-decoration: none;
        }

        .title a:hover {
            text-decoration: underline;
        }

        .github {
            font-size: 0;
            display: inline-flex;
            align-items: center;
        }

        .github svg {
            fill: #0e9b0e;
            transition: fill 0.2s;
        }

        .github:hover svg {
            fill: #0af00a;
        }

        /* Refresh button */
        .refresh-btn {
            background: #000;
            border: 1px solid #0e9b0e;
            color: #0e9b0e;
            padding: 5px 15px;
            cursor: pointer;
            font-family: monospace;
            font-size: 14px;
            font-weight: bold;
        }

        .refresh-btn:hover {
            background: #0e9b0e;
            color: #000;
        }

        /* Status bar */
        .status-bar {
            background: #030f03;
            border: 1px solid #0e9b0e;
            padding: 8px 12px;
            margin-bottom: 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 10px;
            font-size: 12px;
        }

        .status-online {
            color: #0af00a;
        }

        .status-offline {
            color: #ff4444;
        }

        .loading-spinner {
            display: inline-block;
            width: 16px;
            height: 16px;
            border: 2px solid #0e9b0e;
            border-top-color: transparent;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin-right: 8px;
        }

        @keyframes spin {
            to { transform: rotate(360deg); }
        }

        /* Server table */
        .servers-table {
            width: 100%;
            border-collapse: collapse;
            border: 1px solid #0e9b0e;
            font-size: 13px;
        }

        .servers-table th {
            border: 1px solid #0e9b0e;
            padding: 10px 8px;
            text-align: left;
            background: #030f03;
            font-weight: bold;
        }

        .servers-table td {
            border-left: 1px solid #0e9b0e;
            border-bottom: 1px solid #0e9b0e;
            padding: 8px;
            vertical-align: top;
            word-wrap: break-word;
        }

        .servers-table tr:last-child td {
            border-bottom: none;
        }

        .servers-table tbody tr:nth-child(odd) {
            background-color: #030f03;
        }

        .servers-table tbody tr:hover {
            background-color: #0a1a0a;
            cursor: pointer;
        }

        /* Column widths */
        .col-id { width: 40px; }
        .col-server { width: 25%; }
        .col-mission { width: 30%; }
        .col-status { width: 80px; }
        .col-players { width: 70px; }
        .col-ping { width: 70px; }

        /* Server info */
        .server-name {
            font-weight: bold;
            color: #0af00a;
        }
        .server-ip {
            font-size: 11px;
            color: #0e9b0e;
            margin-top: 4px;
            font-family: monospace;
        }
        .server-version {
            font-size: 10px;
            color: #0a8a0a;
            margin-top: 4px;
        }

        /* Status colors */
        .status-playing { color: #ff4444; font-weight: bold; }
        .status-waiting { color: #ffaa44; }
        .status-briefing { color: #44ff44; }
        .status-debriefing { color: #44aaff; }
        .status-unknown { color: #888; }

        /* Players column */
        .players-count {
            font-weight: bold;
            cursor: help;
        }
        .players-list {
            display: none;
            margin-top: 8px;
            padding: 8px;
            background: #0a1a0a;
            border: 1px solid #0e9b0e;
            font-size: 11px;
            max-height: 150px;
            overflow-y: auto;
        }
        .players-list.visible {
            display: block;
        }
        .player-name {
            padding: 2px 0;
            border-bottom: 1px dotted #0e9b0e;
        }
        .player-name:last-child {
            border-bottom: none;
        }

        /* Mod/mission info */
        .mission-name {
            color: #0af00a;
        }
        .mod-name {
            font-size: 11px;
            color: #0a8a0a;
            margin-top: 4px;
        }

        /* No servers message */
        .no-servers {
            text-align: center;
            padding: 40px;
            color: #0e9b0e;
            border: 1px dashed #0e9b0e;
            margin-top: 20px;
        }

        /* Credits */
        .Credits {
            text-align: center;
            font-size: 12px;
            line-height: 1.5;
            padding: 20px;
            margin-top: 30px;
            border-top: 1px solid #0e9b0e;
            color: #0a8a0a;
        }

        .Credits a {
            color: #0e9b0e;
            text-decoration: none;
        }

        .Credits a:hover {
            text-decoration: underline;
        }

        /* Progress bar */
        .progress-container {
            margin: 10px 0;
        }
        progress {
            -webkit-appearance: none;
            width: 100%;
            height: 6px;
        }
        progress::-webkit-progress-bar {
            background-color: #053805;
        }
        progress::-webkit-progress-value {
            background: #0af00a;
        }
        progress::-moz-progress-bar {
            background-color: #0af00a;
        }

        /* Responsive */
        @media screen and (max-width: 768px) {
            body { padding: 10px; }
            .title { font-size: 18px; flex-direction: column; text-align: center; }
            
            .servers-table thead {
                display: none;
            }
            .servers-table tr {
                display: block;
                margin-bottom: 15px;
                border: 1px solid #0e9b0e;
            }
            .servers-table td {
                display: block;
                text-align: right;
                border-left: none;
                border-bottom: 1px solid #0e9b0e;
                padding: 8px;
            }
            .servers-table td::before {
                content: attr(data-label);
                float: left;
                font-weight: bold;
            }
            .servers-table td:last-child {
                border-bottom: none;
            }
            
            .col-id, .col-server, .col-mission, .col-status, .col-players, .col-ping {
                width: 100%;
            }
        }
    </style>
</head>

<body>
    <div class="container">
        <div class="title">
            <span>
                <a href="https://ofpigi.com" target="_blank">ofpigi.com</a> 
                Operation Flashpoint Server Browser
                <a href="https://github.com/ofpigi-com/server-browser" target="_blank" rel="noopener" class="github">
                    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
                        <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"></path>
                    </svg>
                </a>
            </span>
            <button class="refresh-btn" onclick="refreshServers()">🔄 Refresh</button>
        </div>

        <div class="status-bar" id="statusBar">
            <span id="statusText">🟢 Online - Loading servers...</span>
            <span id="serverCount">0 servers found</span>
        </div>

        <div class="progress-container" id="progressContainer">
            <progress id="loadingProgress" value="0" max="100"></progress>
        </div>

        <div id="serversContainer">
            <div class="no-servers">Loading game servers from master server...</div>
        </div>

        <div class="Credits">
            <p>Based on original <a href="http://kondor.armagame.pl/" target="_blank" rel="noopener">online browser</a> by
                <a target="_blank" rel="noopener" href="https://forums.bohemia.net/profile/749525-przemek_kondor/">Przemek_kondor</a>
            </p>
            <p>Using <a target="_blank" href="https://github.com/ofpigi-com/ofp-api" rel="noopener">ofp-api</a> and
                <a target="_blank" href="https://github.com/simi/PowerServer" rel="noopener">PowerServer</a> based on code
                by <a rel="noopener" target="_blank" href="https://forums.bohemia.net/profile/734396-poweruser/">Poweruser</a> &amp; Luigi Auriemma
            </p>
            <p>Master Server: <code id="masterServerUrl">https://wine.ofpigi.com/openspy/api/servers</code></p>
        </div>
    </div>

    <script>
        // Configuration
        const MASTER_SERVER_URL = "API_URL_PLACEHOLDER";
        let servers = [];
        let loading = false;
        let autoRefresh = true;
        let refreshInterval = null;

        // Status mapping
        const statusMap = {
            2: 'Creating',
            6: 'Waiting',
            9: 'Debriefing',
            12: 'Setting Up',
            13: 'Briefing',
            14: 'Playing'
        };

        // Helper: Format status
        function formatStatus(gstate) {
            const status = statusMap[parseInt(gstate)] || 'Unknown';
            const statusClass = status === 'Playing' ? 'status-playing' : 
                               status === 'Waiting' ? 'status-waiting' :
                               status === 'Briefing' ? 'status-briefing' :
                               status === 'Debriefing' ? 'status-debriefing' : '';
            return `<span class="${statusClass}">${status}</span>`;
        }

        // Helper: Get status class
        function getStatusClass(gstate) {
            const status = statusMap[parseInt(gstate)] || 'Unknown';
            return status === 'Playing' ? 'status-playing' : 
                   status === 'Waiting' ? 'status-waiting' :
                   status === 'Briefing' ? 'status-briefing' :
                   status === 'Debriefing' ? 'status-debriefing' : '';
        }

        // Helper: Format players display
        function formatPlayers(players, maxPlayers) {
            const count = players ? players.length : 0;
            return `<span class="players-count" onclick="togglePlayers(this)">${count}/${maxPlayers}</span>
                    <div class="players-list">
                        ${players && players.length ? players.map(p => `<div class="player-name">${escapeHtml(p.player)}</div>`).join('') : '<div class="player-name">No players</div>'}
                    </div>`;
        }

        // Toggle players list
        function togglePlayers(element) {
            const playersList = element.nextElementSibling;
            if (playersList) {
                playersList.classList.toggle('visible');
            }
        }

        // Escape HTML
        function escapeHtml(text) {
            if (!text) return '';
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        // Render servers table
        function renderServers() {
            const container = document.getElementById('serversContainer');
            const serverCountSpan = document.getElementById('serverCount');
            const loadingProgress = document.getElementById('loadingProgress');
            
            const respondingServers = servers.filter(s => s.loaded && s.payload && !s.error);
            
            serverCountSpan.textContent = `${respondingServers.length} active servers`;
            
            if (loadingProgress) {
                const loadedCount = servers.filter(s => s.loaded).length;
                loadingProgress.value = servers.length ? (loadedCount / servers.length) * 100 : 0;
            }
            
            if (respondingServers.length === 0) {
                if (servers.length > 0 && servers.every(s => s.loaded)) {
                    container.innerHTML = '<div class="no-servers">⚠️ No active servers found. Check back later!</div>';
                } else if (loading) {
                    container.innerHTML = '<div class="no-servers"><span class="loading-spinner"></span> Fetching server list...</div>';
                } else {
                    container.innerHTML = '<div class="no-servers">📡 No servers available. Add your server to the master list!</div>';
                }
                return;
            }
            
            // Sort by player count (descending)
            const sorted = [...respondingServers].sort((a, b) => {
                const aPlayers = a.payload ? parseInt(a.payload.numplayers, 10) : 0;
                const bPlayers = b.payload ? parseInt(b.payload.numplayers, 10) : 0;
                return bPlayers - aPlayers;
            });
            
            let html = `<table class="servers-table">
                <thead>
                    <tr>
                        <th class="col-id">ID</th>
                        <th class="col-server">Server</th>
                        <th class="col-mission">Mission / Mods</th>
                        <th class="col-status">Status</th>
                        <th class="col-players">Players</th>
                        <th class="col-ping">Ping</th>
                    </tr>
                </thead>
                <tbody>`;
            
            sorted.forEach((server, idx) => {
                const payload = server.payload;
                const hostname = payload.hostname || `${server.ip}:${server.port}`;
                const gameType = payload.gametype || 'Unknown';
                const mission = payload.mission || 'Unknown';
                const mod = payload.mod || '';
                const numPlayers = parseInt(payload.numplayers, 10) || 0;
                const maxPlayers = parseInt(payload.maxplayers, 10) || 0;
                const ping = Math.round(payload.replied_in * 1000) || 0;
                const version = payload.gamever || '1.96';
                const gstate = parseInt(payload.gstate, 10);
                
                html += `<tr>
                    <td data-label="ID">${idx + 1}</td>
                    <td data-label="Server">
                        <div class="server-name">${escapeHtml(hostname)}</div>
                        <div class="server-ip">${server.ip}:${server.port}</div>
                        <div class="server-version">v${escapeHtml(version)}</div>
                    </td>
                    <td data-label="Mission / Mods">
                        <div class="mission-name">${escapeHtml(mission)}</div>
                        ${mod ? `<div class="mod-name">🎮 ${escapeHtml(mod)}</div>` : ''}
                        ${gameType !== 'Unknown' && gameType !== mission ? `<div class="mod-name">📦 ${escapeHtml(gameType)}</div>` : ''}
                    </td>
                    <td data-label="Status" class="${getStatusClass(gstate)}">
                        ${formatStatus(gstate)}
                    </td>
                    <td data-label="Players" class="Players">
                        ${formatPlayers(payload.players, maxPlayers)}
                    </td>
                    <td data-label="Ping">
                        ${ping} ms
                    </td>
                </tr>`;
            });
            
            html += `</tbody>
            </table>`;
            container.innerHTML = html;
        }
        
        // Fetch a single server status
        async function fetchServerStatus(server) {
            try {
                const response = await fetch(`${MASTER_SERVER_URL}/${server.ip}/${server.port}`);
                if (response.ok) {
                    const data = await response.json();
                    server.payload = data;
                    server.players = parseInt(data.numplayers, 10) || 0;
                    server.error = false;
                } else {
                    server.error = true;
                    server.payload = null;
                }
            } catch (err) {
                server.error = true;
                server.payload = null;
            }
            server.loaded = true;
            renderServers();
            return server;
        }
        
        // Load master server list
        async function loadMasterServers() {
            try {
                loading = true;
                updateStatusBar('🟡 Fetching server list...', true);
                
                const response = await fetch(MASTER_SERVER_URL);
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                
                const data = await response.json();
                
                // Parse servers from OpenSpy API response
                let serverList = [];
                if (Array.isArray(data)) {
                    serverList = data;
                } else if (data.servers && Array.isArray(data.servers)) {
                    serverList = data.servers;
                } else if (data.data && Array.isArray(data.data)) {
                    serverList = data.data;
                }
                
                servers = serverList.map(s => ({
                    ip: s.ip || s.host,
                    port: s.port || 2302,
                    loaded: false,
                    error: false,
                    players: 0,
                    payload: null
                }));
                
                updateStatusBar(`🟢 Found ${servers.length} servers, querying status...`, true);
                
                // Fetch all server statuses in parallel with limit
                const batchSize = 10;
                for (let i = 0; i < servers.length; i += batchSize) {
                    const batch = servers.slice(i, i + batchSize);
                    await Promise.all(batch.map(server => fetchServerStatus(server)));
                }
                
                updateStatusBar(`🟢 Online - ${servers.filter(s => s.payload && !s.error).length} active servers`, false);
                loading = false;
                
                if (autoRefresh) {
                    scheduleRefresh();
                }
                
            } catch (err) {
                console.error('Failed to load master server:', err);
                updateStatusBar('🔴 Error connecting to master server', false);
                document.getElementById('serversContainer').innerHTML = `<div class="no-servers">❌ Failed to connect to master server. Make sure OpenSpy is running at ${MASTER_SERVER_URL}</div>`;
                loading = false;
            }
        }
        
        // Schedule auto-refresh
        function scheduleRefresh() {
            if (refreshInterval) clearTimeout(refreshInterval);
            refreshInterval = setTimeout(() => {
                if (autoRefresh && !loading) {
                    refreshServers();
                }
            }, 30000); // Refresh every 30 seconds
        }
        
        // Refresh servers
        async function refreshServers() {
            if (loading) return;
            loading = true;
            updateStatusBar('🔄 Refreshing server status...', true);
            
            // Reset all servers
            servers.forEach(s => {
                s.loaded = false;
                s.error = false;
                s.payload = null;
            });
            
            // Re-fetch all statuses
            const batchSize = 10;
            for (let i = 0; i < servers.length; i += batchSize) {
                const batch = servers.slice(i, i + batchSize);
                await Promise.all(batch.map(server => fetchServerStatus(server)));
            }
            
            updateStatusBar(`🟢 Online - ${servers.filter(s => s.payload && !s.error).length} active servers`, false);
            loading = false;
            
            if (autoRefresh) {
                scheduleRefresh();
            }
        }
        
        // Update status bar
        function updateStatusBar(text, isLoading) {
            const statusText = document.getElementById('statusText');
            statusText.innerHTML = isLoading ? `<span class="loading-spinner"></span> ${text}` : text;
        }
        
        // Initialize
        document.addEventListener('DOMContentLoaded', () => {
            loadMasterServers();
            
            // Auto-refresh toggle (Alt+R)
            document.addEventListener('keydown', (e) => {
                if (e.altKey && e.key === 'r') {
                    refreshServers();
                    e.preventDefault();
                }
            });
        });
    </script>
</body>

</html>
HTML_EOF

# Replace the placeholder with actual API URL
sed -i "s|API_URL_PLACEHOLDER|${API_URL}|g" "$WEB_ROOT/index.html"

log "✅ Server browser HTML created"

# ============= CREATE SIMPLE API PROXY =============
log "📝 Creating API proxy for OpenSpy..."

cat > "$WEB_ROOT/api/proxy.php" << 'PHP_EOF'
<?php
// Simple proxy to OpenSpy API
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$target = 'https://wine.ofpigi.com/openspy/api/servers';

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $target);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_TIMEOUT, 10);

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($httpCode === 200) {
    echo $response;
} else {
    echo json_encode(['error' => 'Failed to fetch servers', 'servers' => []]);
}
?>
PHP_EOF

# ============= CREATE NGINX CONFIG =============
log "📝 Creating nginx configuration for ofpigi.com..."

# Get SSL certificate for root domain if not exists
if [ ! -f "/etc/letsencrypt/live/ofpigi.com/fullchain.pem" ]; then
    log "Getting SSL certificate for ofpigi.com..."
    certbot certonly --standalone -d ofpigi.com --non-interactive --agree-tos -m admin@ofpigi.com 2>/dev/null || \
    warn "SSL certificate for ofpigi.com failed - will use existing wine.ofpigi.com cert"
fi

# Check if nginx config already has ofpigi.com block
if ! grep -q "server_name ofpigi.com" /etc/nginx/sites-available/winejs 2>/dev/null; then
    # Backup current config
    cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
    
    # Insert ofpigi.com block before the existing config
    cat > /tmp/ofpigi-nginx.conf << 'NGINX_EOF'
# Root domain - ofpigi.com Game Server Browser
server {
    listen 80;
    server_name ofpigi.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ofpigi.com;
    
    ssl_certificate /etc/letsencrypt/live/ofpigi.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ofpigi.com/privkey.pem;
    
    root /var/www/ofpigi;
    index index.html;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Main page
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    # API proxy to OpenSpy
    location /api/ {
        proxy_pass https://wine.ofpigi.com/openspy/api/;
        proxy_set_header Host wine.ofpigi.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Static assets cache
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}

NGINX_EOF

    # Insert at beginning of the file
    cat /tmp/ofpigi-nginx.conf /etc/nginx/sites-available/winejs > /tmp/winejs-new.conf
    mv /tmp/winejs-new.conf /etc/nginx/sites-available/winejs
    rm /tmp/ofpigi-nginx.conf
    
    # Test and reload nginx
    if nginx -t; then
        systemctl reload nginx
        log "✅ Nginx updated with ofpigi.com configuration"
    else
        warn "Nginx test failed, restoring backup"
        cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
        nginx -t && systemctl reload nginx
    fi
else
    log "ofpigi.com already configured in nginx"
fi

# ============= SETUP MASTER SERVER ENDPOINT =============
log "📝 Setting up master server endpoint on wine.ofpigi.com..."

# Create a simple master server list endpoint in OpenSpy if needed
mkdir -p /opt/winejs/data/openspy/master
cat > /opt/winejs/data/openspy/master/servers.txt << EOF
# Operation Flashpoint Master Servers
# Format: IP:PORT
# Add your game servers here to be listed in the browser

# Example server (replace with your actual server)
# YOUR_SERVER_IP:2302
EOF

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              OFPIGI.COM SERVER BROWSER INSTALLED!              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Server browser installed at /var/www/ofpigi/index.html"
echo ""
info "🌐 Access URLs:"
info "   • Main site: https://ofpigi.com"
info "   • Server browser: https://ofpigi.com"
echo ""
info "📁 Files installed:"
info "   • Web root: /var/www/ofpigi"
info "   • Master server list: /opt/winejs/data/openspy/master/servers.txt"
echo ""
info "🔧 To add your game servers:"
info "  1. Edit the master server list:"
info "     nano /opt/winejs/data/openspy/master/servers.txt"
info "  2. Add your servers in format: IP:PORT"
info "  3. Restart OpenSpy: docker restart winejs-openspy-core"
echo ""
info "🎮 The server browser will show:"
info "   • Server name, IP, port"
info "   • Current mission/mod"
info "   • Player count and names"
info "   • Server status (Playing/Waiting/Briefing)"
info "   • Ping times"
echo ""
info "📝 To update nginx: sudo nginx -t && sudo systemctl reload nginx"
echo ""
success "✨ ofpigi.com is ready! Visit https://ofpigi.com to see your server browser!"
echo ""

# ============= CREATE UNINSTALL SCRIPT =============
cat > /opt/winejs/apps/uninstall_ofpigi.sh << 'UNINSTALL_EOF'
#!/bin/bash
# ofpigi.com Uninstaller

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }

log "🧹 Uninstalling ofpigi.com server browser..."

# Remove web directory
rm -rf /var/www/ofpigi

# Remove nginx config for ofpigi.com
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
    sed -i '/# Root domain - ofpigi.com Game Server Browser/,/server {/d' /etc/nginx/sites-available/winejs
    sed -i '/server_name ofpigi.com;/,/^}/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

log "✅ ofpigi.com uninstalled"
UNINSTALL_EOF

chmod +x /opt/winejs/apps/uninstall_ofpigi.sh
info "📝 Uninstall script: /opt/winejs/apps/uninstall_ofpigi.sh"

echo ""
echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"