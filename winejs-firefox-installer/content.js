// Content script for WINEJS Installer + Console New Tab - FIXED TERMINAL DETECTION

console.log("WINEJS Installer + Console New Tab loaded");

// Logo URL
const logoUrl = browser.runtime.getURL("icons/icon.png");

// State
let domainDetected = false;
let startTime = null;
let elapsedTimerInterval = null;
let outputMonitorInterval = null;
let connectionMonitorInterval = null;
let connectionAttempts = 0;
const MAX_CONNECTION_ATTEMPTS = 360;
let processedPings = new Set();
// ============= TERMINAL LINE DETECTION - PROPER SPAN PARSING =============
function getTerminalText() {
    const xtermRows = document.querySelector('.xterm-rows');
    if (!xtermRows) return [];
    
    const lines = [];
    const rowDivs = xtermRows.querySelectorAll(':scope > div');
    
    for (let row of rowDivs) {
        // Get ALL spans in this row
        const spans = row.querySelectorAll('span');
        let lineText = '';
        
        // Combine text from ALL spans
        for (let span of spans) {
            lineText += span.textContent;
        }
        
        // Also check if there's text directly in the div
        if (lineText === '' && row.textContent) {
            lineText = row.textContent;
        }
        
        lineText = lineText.trim();
        if (lineText) {
            lines.push(lineText);
        }
    }
    
    console.log(`📝 Captured ${lines.length} terminal lines`);
    if (lines.length > 0) {
        console.log(`📝 Last 3 lines:`, lines.slice(-3));
    }
    return lines;
}

function getLastTerminalLine() {
    const lines = getTerminalText();
    if (lines.length === 0) return "";
    return lines[lines.length - 1];
}

// ============= CONSOLE NEW TAB FUNCTIONALITY =============
function setupConsoleNewTab() {
    console.log('🚀 Converting console links to open in new tab');
    
    function convertConsoleLinks() {
        const consoleLinks = document.querySelectorAll('a.console-link[role="button"]');
        
        consoleLinks.forEach(link => {
            if (!link.hasAttribute('data-winejs-converted')) {
                const dropletIdMatch = window.location.href.match(/\/droplets\/(\d+)/);
                
                if (dropletIdMatch && dropletIdMatch[1]) {
                    const dropletId = dropletIdMatch[1];
                    const consoleUrl = `https://cloud.digitalocean.com/droplets/${dropletId}/terminal/ui/`;
                    
                    const newLink = document.createElement('a');
                    newLink.href = consoleUrl;
                    newLink.target = '_blank';
                    newLink.className = link.className;
                    newLink.setAttribute('role', 'button');
                    newLink.innerHTML = link.innerHTML;
                    newLink.setAttribute('data-winejs-converted', 'true');
                    
                    link.parentNode.replaceChild(newLink, link);
                    console.log('✅ Converted console link');
                }
            }
        });
    }
    
    convertConsoleLinks();
    const observer = new MutationObserver(convertConsoleLinks);
    observer.observe(document.body, { childList: true, subtree: true });
}

// ============= CREATE OVERLAY =============
function createWineJsOverlay() {
    browser.storage.local.get(['overlayVisible']).then(result => {
        const isVisible = result.overlayVisible !== false;
        const overlay = document.getElementById('winejs-install');
        if (overlay && !isVisible) {
            overlay.classList.add('hidden');
        }
    });

    if (document.getElementById('winejs-install')) {
        return;
    }

    const overlay = document.createElement('div');
    overlay.id = 'winejs-install';
    overlay.className = 'winejs-install';

    const contentWrapper = document.createElement('div');
    contentWrapper.className = 'winejs-content';

    const logoContainer = document.createElement('div');
    logoContainer.className = 'winejs-logo-container';

    const logo = document.createElement('div');
    logo.className = 'winejs-logo';
    
    const logoImg = document.createElement('img');
    logoImg.src = logoUrl;
    logoImg.alt = 'WINEJS Logo';
    logoImg.onerror = function() {
        this.style.display = 'none';
        const fallbackLogo = document.createElement('div');
        fallbackLogo.style.color = 'white';
        fallbackLogo.style.fontSize = '48px';
        fallbackLogo.style.fontWeight = '300';
        fallbackLogo.style.letterSpacing = '2px';
        fallbackLogo.textContent = 'WINEJS';
        logoContainer.appendChild(fallbackLogo);
    };
    
    logo.appendChild(logoImg);
    logoContainer.appendChild(logo);
    contentWrapper.appendChild(logoContainer);

    const progressSection = document.createElement('div');
    progressSection.className = 'progress-section';
    progressSection.innerHTML = `
        <div class="progress-label">
            <span id="progressStatus">WINEJS Install</span>
            <span id="progressElapsed">00:00</span>
        </div>
        <div class="progress-track">
            <div class="progress-fill" id="progressFill" style="width: 0%;"></div>
        </div>
    `;
    contentWrapper.appendChild(progressSection);

    const logWindow = document.createElement('div');
    logWindow.className = 'log-window';
    logWindow.id = 'logWindow';
    contentWrapper.appendChild(logWindow);

    const statusArea = document.createElement('div');
    statusArea.className = 'status-area';
    statusArea.innerHTML = `
        <div id="statusMessage" class="status-message">Click start to begin</div>
        <button class="main-action-btn" id="startInstallBtn">▶ START INSTALLATION</button>
        <a href="#" class="main-action-btn hidden" id="openDomainBtn" target="_blank">🌐 OPEN WINEJS</a>
        <div><button class="reset-btn hidden" id="resetBtn">⟲ reset</button></div>
        <div class="signature">WINEJS · OS install · <a href="https://igiteam.github.io/sh/" target="_blank" rel="norefferer">Support Us</a></div>
    `;
    contentWrapper.appendChild(statusArea);

    overlay.appendChild(contentWrapper);
    document.body.appendChild(overlay);

    const popupOverlay = document.createElement('div');
    popupOverlay.className = 'popup-overlay';
    popupOverlay.id = 'popupOverlay';
    popupOverlay.innerHTML = `
        <div class="popup-card">
            <h3>Welcome to WineJS</h3>
            <label>Main domain</label>
            <input type="text" id="popupDomain" value="wine.gitgpt.chat" placeholder="e.g. wine.yourdomain.com">
            <label>SSL email</label>
            <input type="email" id="popupEmail" value="admin@wine.gitgpt.chat" placeholder="admin@example.com">
            <label>Download password (min 8 chars)</label>
            <input type="password" id="popupPassword" value="MyPassword12345">
            
            <div style="margin: 15px 0;">
                <label style="color: #ccc; display: block; margin-bottom: 8px; font-size: 13px;">
                    📤 UPLOAD PIN <span style="color: #888;">(optional, 4 digits)</span>
                </label>
                <div style="display: flex; gap: 8px; align-items: center; margin: 0; padding: 0; margin-bottom: 10px">
                    <div style="width: 16px; height: 16px; display: flex; align-items: center; justify-content: center; margin: 0; padding: 0;">
                        <input type="checkbox" id="enable-pin" checked style="width: 16px; height: 16px; margin: 0; padding: 0; cursor: pointer; background-color: rgba(0,0,255,0.3); border: 1px solid white; box-sizing: border-box;">
                    </div>
                    <label for="enable-pin" 
                          style="color: #ccc; font-size: 13px; cursor: pointer; user-select: none; line-height: 16px; margin: 0; padding: 0;">
                        Enable PIN protection
                    </label>
                </div>
                <input type="password" id="pin-input" maxlength="4" placeholder="Enter 4 digits"
                       style="width: 100%; padding: 10px; background: #2a2a2a; border: 1px solid #444; 
                              border-radius: 8px; color: white; font-size: 14px; box-sizing: border-box;">
            </div>

            <div style="margin-bottom: 20px;">
                <label style="color: #ccc; display: block; margin-bottom: 8px; font-size: 13px;">
                    📁 UPLOAD FILE EXTENSIONS (only these filetypes can be uploaded)
                </label>
                <div style="display: flex; gap: 10px; margin-bottom: 10px;">
                    <button id="use-default-ext" style="flex: 1; padding: 8px; background: #0078d4; 
                            border: none; color: white; border-radius: 4px; cursor: pointer;">Use Defaults</button>
                    <button id="custom-ext" style="flex: 1; padding: 8px; background: #2d2d2d; 
                            border: 1px solid #444; color: white; border-radius: 4px; cursor: pointer;">Custom</button>
                </div>
                <textarea id="extensions-input" readonly rows="3" 
                  style="width: 100%; padding: 10px; background: #2a2a2a; border: 1px solid #444; 
                         color: #888; border-radius: 8px; font-size: 12px; font-family: monospace; box-sizing: border-box;">.ms3d,.obj,.3ds,.fbx,.dae,.blend,.jpg,.png,.mp3,.wav,.mp4</textarea>
            </div>

            <div class="popup-buttons">
                <button class="popup-btn cancel" id="popupCancel">Cancel</button>
                <button class="popup-btn confirm" id="popupConfirm">Install</button>
            </div>
        </div>
    `;
    document.body.appendChild(popupOverlay);

    initEventListeners();
    startConnectionMonitor();
}

// ============= EVENT LISTENERS =============
function initEventListeners() {
    const progressFill = document.getElementById('progressFill');
    const progressStatus = document.getElementById('progressStatus');
    const progressElapsed = document.getElementById('progressElapsed');
    const statusMsg = document.getElementById('statusMessage');
    const startBtn = document.getElementById('startInstallBtn');
    const openBtn = document.getElementById('openDomainBtn');
    const resetBtn = document.getElementById('resetBtn');
    const popup = document.getElementById('popupOverlay');
    
    const popupCancel = document.getElementById('popupCancel');
    const popupConfirm = document.getElementById('popupConfirm');
    const popupDomain = document.getElementById('popupDomain');
    const popupEmail = document.getElementById('popupEmail');
    const popupPassword = document.getElementById('popupPassword');
    const enablePin = document.getElementById('enable-pin');
    const pinInput = document.getElementById('pin-input');
    const defaultExtBtn = document.getElementById('use-default-ext');
    const customExtBtn = document.getElementById('custom-ext');
    const extensionsInput = document.getElementById('extensions-input');
    
    const toggleBtn = document.createElement('button');
    toggleBtn.className = 'winejs-toggle';
    const toggleImg = document.createElement('img');
    toggleImg.src = logoUrl;
    toggleImg.style.width = '26px';
    toggleImg.style.height = '26px';
    toggleBtn.appendChild(toggleImg);
    document.body.appendChild(toggleBtn);

    toggleBtn.addEventListener('click', () => {
        document.getElementById('winejs-install').classList.toggle('hidden');
    });

    browser.runtime.onMessage.addListener((message) => {
        if (message.action === 'toggleOverlay') {
            const overlay = document.getElementById('winejs-install');
            if (overlay) {
                if (!message.visible) {
                    overlay.classList.add('hidden');
                } else {
                    overlay.classList.remove('hidden');
                }
            }
        }
    });

    // Ensure PIN input state is correct on page load
    if (enablePin.checked) {
        pinInput.disabled = false;
    } else {
        pinInput.disabled = true;
    }

    // Keep them synced
    enablePin.addEventListener('change', () => {
        pinInput.disabled = !enablePin.checked;
        if (enablePin.checked) {
            pinInput.focus();
            // Clear any invalid value
            if (pinInput.value && !/^\d{4}$/.test(pinInput.value)) {
                pinInput.value = '';
            }
        }
    });
    
    // Also validate as user types
    pinInput.addEventListener('input', () => {
        if (pinInput.value.length > 4) {
            pinInput.value = pinInput.value.slice(0, 4);
        }
        if (!/^\d*$/.test(pinInput.value)) {
            pinInput.value = pinInput.value.replace(/\D/g, '');
        }
    });

    defaultExtBtn.addEventListener('click', () => {
        extensionsInput.value = ".ms3d,.obj,.3ds,.fbx,.dae,.blend,.jpg,.png,.mp3,.wav,.mp4";
        extensionsInput.style.color = "#888";
        extensionsInput.readOnly = true;
    });

    customExtBtn.addEventListener('click', () => {
        extensionsInput.readOnly = false;
        extensionsInput.style.color = "white";
        extensionsInput.style.background = "#252525";
        extensionsInput.focus();
    });

    extensionsInput.addEventListener('input', () => {
        let value = extensionsInput.value.replace(/\s/g, "");
        value = value.split(",").map((ext) => {
            ext = ext.trim();
            if (ext && !ext.startsWith(".")) ext = "." + ext;
            return ext;
        }).join(",");
        extensionsInput.value = value;
    });

    startBtn.addEventListener('click', () => {
        popup.classList.add('show');
    });

    popupCancel.addEventListener('click', () => {
        popup.classList.remove('show');
    });

    popupConfirm.addEventListener('click', () => {
        if (connectionMonitorInterval) {
            clearInterval(connectionMonitorInterval);
            connectionMonitorInterval = null;
        }

        // Get fresh references every time
        const popupDomain = document.getElementById('popupDomain');
        const popupEmail = document.getElementById('popupEmail');
        const popupPassword = document.getElementById('popupPassword');
        const pinInput = document.getElementById('pin-input');
        const enablePin = document.getElementById('enable-pin');
        const extensionsInput = document.getElementById('extensions-input');

        const domain = popupDomain.value.trim();
        const email = popupEmail.value.trim();
        const pass = popupPassword.value.trim();
        
        // Get PIN correctly
        const pinRaw = pinInput.value.trim();
        const pinEnabled = enablePin.checked;
        const pin = pinEnabled ? pinRaw : "";

        console.log("🔧 PIN DEBUG:");
        console.log("  Checkbox checked:", pinEnabled);
        console.log("  PIN input value:", pinRaw);
        console.log("  PIN disabled?", pinInput.disabled);
        console.log("  Final PIN sent:", pin ? pinRaw : "(empty)");

        console.log("🔧 INSTALL VALUES:");
        console.log("Domain:", domain);
        console.log("Email:", email);
        console.log("Password:", pass.replace(/./g, '*'));
        console.log("Extensions:", extensionsInput.value);

        if (!domain.includes('.')) {
            alert('Please enter a valid domain');
            return;
        }
        if (!email.includes('@')) {
            alert('Enter a valid email');
            return;
        }
        if (pass.length < 8) {
            alert('Password must be at least 8 characters');
            return;
        }
        
        // FIX: Validate PIN - check if enabled AND has value
        if (pinEnabled) {
            if (!pinRaw || pinRaw.length === 0) {
                alert('PIN cannot be empty when enabled');
                return;
            }
            if (!/^\d{4}$/.test(pinRaw)) {
                alert('PIN must be exactly 4 digits');
                return;
            }
        }

        popup.classList.remove('show');
        resetUI();

        // Build command - make sure PIN is sent correctly
        const command = `curl -o "winejs.sh" "https://cdn.gitgpt.chat/rtx/winejs.sh" && chmod +x "winejs.sh" && sudo ./"winejs.sh" << EOF\n${domain}\n${email}\n${pass}\n${pin}\n${extensionsInput.value}\nEOF\n`;

        console.log("📝 Command being sent:", command.replace(pass, '********'));

        const textarea = document.querySelector('.xterm-helper-textarea');
        if (textarea) {
            textarea.focus();
            document.execCommand('insertText', false, command);
            try {
                textarea.value = command;
                textarea.dispatchEvent(new Event('input', { bubbles: true }));
            } catch(e) {
                console.log("Could not set value directly:", e);
            }
        } else {
            console.log("❌ Could not find terminal textarea");
            addLogLine('[ERROR] Could not find terminal input', 'error');
        }

        startTime = Date.now();
        elapsedTimerInterval = setInterval(() => updateTimer(progressElapsed), 100);
        startOutputMonitoring();
        statusMsg.innerText = 'Installing...';
        statusMsg.style.color = 'white';
        addLogLine('[0.000] Installation started', 'info');
    });

    popup.addEventListener('click', (e) => {
        if (e.target === popup) popup.classList.remove('show');
    });

    resetBtn.addEventListener('click', () => {
        resetUI();
        browser.runtime.sendMessage({action: 'playPing'});
    });

    browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
        if (message.action === 'toggleOverlay') {
            const overlay = document.getElementById('winejs-install');
            if (overlay) {
                if (!message.visible) {
                    overlay.classList.add('hidden');
                } else {
                    overlay.classList.remove('hidden');
                }
            }
            sendResponse({success: true});
        }
        else if (message.action === 'showInstaller') {
            const overlay = document.getElementById('winejs-install');
            if (overlay) {
                overlay.classList.remove('hidden');
            }
            sendResponse({success: true});
        }
        else if (message.action === 'resetInstaller') {
            resetUI();
            sendResponse({success: true});
        }
        
        return true;
    });
}

// ============= HELPER FUNCTIONS =============
function addLogLine(text, className = '') {
    const logWin = document.getElementById('logWindow');
    if (!text || text.trim() === '') return;
    
    const line = document.createElement('div');
    line.className = 'log-line' + (className ? ' ' + className : '');
    line.textContent = text;
    logWin.appendChild(line);
    logWin.scrollTop = logWin.scrollHeight;
}

function removeLastEmptyLogLine() {
    const logWin = document.getElementById('logWindow');
    const lastLine = logWin.lastElementChild;
    if (lastLine) {
        const content = lastLine.textContent || '';
        if (content.trim() === '' || content === '-' || content === '.' || content === '...' || content.includes('PING:')) {
            logWin.removeChild(lastLine);
        }
    }
}

function updateTimer(progressElapsed) {
    if (!startTime) {
        progressElapsed.innerText = '00:00';
        return;
    }
    const elapsed = Date.now() - startTime;
    const totalSec = Math.floor(elapsed / 1000);
    const mins = Math.floor(totalSec / 60);
    const secs = totalSec % 60;
    progressElapsed.innerText = `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
}

function startOutputMonitoring() {
    console.log("🔍 [OUTPUT MONITOR] Starting...");
    
    if (outputMonitorInterval) {
        clearInterval(outputMonitorInterval);
        outputMonitorInterval = null;
    }

    let errorHandled = false;
    let completionHandled = false;
    let processedLines = new Set();
    
    const statusMsg = document.getElementById('statusMessage');
    const progressStatus = document.getElementById('progressStatus');
    const progressFill = document.getElementById('progressFill');
    const progressElapsed = document.getElementById('progressElapsed');
    const startBtn = document.getElementById('startInstallBtn');
    const openBtn = document.getElementById('openDomainBtn');
    const resetBtn = document.getElementById('resetBtn');
    
    if (startBtn) startBtn.classList.add('hidden');
    if (resetBtn) resetBtn.classList.add('hidden');
    
    
    outputMonitorInterval = setInterval(() => {
        const allLines = getTerminalText();
        
        // ============= CHECK ALL LINES FOR ERRORS =============
        if (!errorHandled) {
            for (let i = 0; i < allLines.length; i++) {
                const line = allLines[i];
                if (line.includes('[ERROR]') || 
                    line.toLowerCase().includes('invalid email format')) {
                    console.log(`🔍 [OUTPUT MONITOR] 🚨 ERROR DETECTED: "${line}"`);
                    errorHandled = true;
                    
                    addLogLine(line, 'error');
                    
                    if (statusMsg) {
                        statusMsg.innerText = '❌ Installation failed - Invalid email';
                        statusMsg.style.color = '#f48771';
                    }
                    if (progressStatus) progressStatus.innerText = 'Error: Invalid email';
                    if (progressFill) progressFill.style.width = '0%';
                    if (progressElapsed) progressElapsed.innerText = '00:00';
                    if (startBtn) startBtn.classList.remove('hidden');
                    if (resetBtn) resetBtn.classList.remove('hidden');
                    if (openBtn) openBtn.classList.add('hidden');
                    
                    browser.runtime.sendMessage({action: 'playPing'});
                    
                    if (outputMonitorInterval) clearInterval(outputMonitorInterval);
                    if (elapsedTimerInterval) clearInterval(elapsedTimerInterval);
                    outputMonitorInterval = null;
                    elapsedTimerInterval = null;
                    return;
                }
            }
        }
        
        // Process new lines
        for (let i = 0; i < allLines.length; i++) {
            const line = allLines[i];
            if (processedLines.has(line)) continue;
            processedLines.add(line);
            
            const cleanLine = line.replace(/\x1b\[[0-9;]*[mK]/g, '').trim();
            
            if (cleanLine && !cleanLine.includes('PING:')) {
                addLogLine(cleanLine);
            }

            // ============= PLAY PING =============
            if (cleanLine && cleanLine.includes('PING:')) {
                browser.runtime.sendMessage({action: 'playPing'});
            }

            // ============= DETECT INTERRUPT (Ctrl+C) =============
            if (cleanLine && cleanLine.includes('^C')) {
                console.log(`🔍 Installation interrupted - Ctrl+C detected`);
                addLogLine('[INTERRUPTED] Installation was cancelled (Ctrl+C detected)', 'warning');
                
                if (statusMsg) {
                    statusMsg.innerText = '⚠️ Installation interrupted';
                    statusMsg.style.color = '#f9c35f';
                }
                if (progressStatus) progressStatus.innerText = 'Interrupted';
                if (progressFill) progressFill.style.width = '0%';
                if (startBtn) startBtn.classList.remove('hidden');
                if (resetBtn) resetBtn.classList.remove('hidden');
                
                // Clean up intervals
                if (outputMonitorInterval) clearInterval(outputMonitorInterval);
                if (elapsedTimerInterval) clearInterval(elapsedTimerInterval);
                outputMonitorInterval = null;
                elapsedTimerInterval = null;
                // ============= PLAY PING =============
                browser.runtime.sendMessage({action: 'playPing'});
                return;
            }
            
            console.log(`🔍 New line: "${cleanLine.substring(0, 80)}"`);
            
            // ============= CHECK PROGRESS =============
            const progressMatch = cleanLine.match(/PROGRESS:(\d+):(.*)/);
            if (progressMatch && !errorHandled) {
                const percent = parseInt(progressMatch[1]);
                const message = progressMatch[2];
                
                if (progressFill) progressFill.style.width = percent + '%';
                if (progressStatus) progressStatus.innerText = message;
                if (statusMsg) statusMsg.innerText = percent < 100 ? 'Installing...' : '✅ Installation complete!';
                
                if (percent === 100 && !completionHandled) {
                    completionHandled = true;
                    if (openBtn) openBtn.classList.remove('hidden');
                    if (startBtn) startBtn.classList.add('hidden');
                    if (resetBtn) resetBtn.classList.add('hidden');
                    
                    // Search ALL previous lines for the domain
                    for (let j = 0; j < allLines.length; j++) {
                        const domainMatch = allLines[j].match(/🌐 Main domain: (https:\/\/[^\s]+)/);
                        if (domainMatch) {
                            openBtn.href = domainMatch[1];
                            console.log(`🔍 Domain found: ${domainMatch[1]}`);
                            break;
                        }
                    }
                    
                    if (outputMonitorInterval) clearInterval(outputMonitorInterval);
                    if (elapsedTimerInterval) clearInterval(elapsedTimerInterval);
                    outputMonitorInterval = null;
                    elapsedTimerInterval = null;
                    return;
                }
            }
            
            // ============= CHECK COMPLETION =============
            if (!completionHandled && !errorHandled && (
                cleanLine.includes('Main domain: https://') || 
                cleanLine.includes('🌐 Main domain:')
            )) {
                console.log(`🔍 ✅ COMPLETION DETECTED: "${cleanLine}"`);
                completionHandled = true;
                
                if (progressFill) progressFill.style.width = '100%';
                if (progressStatus) progressStatus.innerText = 'Installation complete!';
                if (statusMsg) statusMsg.innerText = '✅ Installation complete!';
                if (openBtn) openBtn.classList.remove('hidden');
                if (startBtn) startBtn.classList.add('hidden');
                if (resetBtn) resetBtn.classList.add('hidden');
                
                for (let j = 0; j < allLines.length; j++) {
                    const domainMatch = allLines[j].match(/🌐 Main domain: (https:\/\/[^\s]+)/);
                    if (domainMatch) {
                        openBtn.href = domainMatch[1];
                        console.log(`🔍 Domain found: ${domainMatch[1]}`);
                        break;
                    }
                }
                
                if (outputMonitorInterval) clearInterval(outputMonitorInterval);
                if (elapsedTimerInterval) clearInterval(elapsedTimerInterval);
                outputMonitorInterval = null;
                elapsedTimerInterval = null;
                return;
            }
        }
    }, 200);
}

// ============= CONNECTION MONITOR =============
function startConnectionMonitor() {
    if (connectionMonitorInterval) clearInterval(connectionMonitorInterval);
    connectionAttempts = 0;
    
    const startBtn = document.getElementById('startInstallBtn');
    const logWin = document.getElementById('logWindow');
    const statusMsg = document.getElementById('statusMessage');
    const progressStatus = document.getElementById('progressStatus');
    
    if (startBtn) startBtn.classList.add('hidden');
    if (logWin) logWin.innerHTML = '';
    addLogLine('[0.000] Connecting to instance...', 'info');
    if (statusMsg) statusMsg.innerText = 'Connecting to instance...';

    connectionMonitorInterval = setInterval(() => {
        connectionAttempts++;
        
        const lines = getTerminalText();
        let connected = false;
        
        for (const line of lines) {
            const text = line.toLowerCase();
            if (text.includes('root@') || text.includes('$') || text.includes('#') || 
                text.includes('welcome to ubuntu') || text.includes('last login:') ||
                text.includes('user@') || text.includes('~$')) {
                connected = true;
                break;
            }
        }

        if (connected) {
            clearInterval(connectionMonitorInterval);
            connectionMonitorInterval = null;
            
            if (logWin) logWin.innerHTML = '';
            addLogLine(`[${(connectionAttempts * 0.5).toFixed(1)}s] WINEJS installer ready`, 'info');
            if (statusMsg) statusMsg.innerText = 'Connected! Click start to begin';
            if (progressStatus) progressStatus.innerText = 'Install WINEJS';
            if (startBtn) startBtn.classList.remove('hidden');
            return;
        }

        if (connectionAttempts >= MAX_CONNECTION_ATTEMPTS) {
            clearInterval(connectionMonitorInterval);
            connectionMonitorInterval = null;
            
            addLogLine(`[ERROR] ❌ Failed to connect after ${MAX_CONNECTION_ATTEMPTS / 2} seconds`, 'error');
            addLogLine(`[ERROR] Check your droplet is running`, 'error');
            
            if (statusMsg) statusMsg.innerText = '❌ Connection failed';
            if (progressStatus) progressStatus.innerText = 'Error';
            if (progressFill) progressFill.style.width = '0%';
            if (startBtn) startBtn.classList.remove('hidden');
        }
    }, 500);
}

// ============= RESET UI =============
function resetUI() {
    if (elapsedTimerInterval) clearInterval(elapsedTimerInterval);
    if (outputMonitorInterval) clearInterval(outputMonitorInterval);
    if (connectionMonitorInterval) clearInterval(connectionMonitorInterval);
    
    domainDetected = false;
    startTime = null;
    processedPings.clear();

    const progressFill = document.getElementById('progressFill');
    const progressStatus = document.getElementById('progressStatus');
    const progressElapsed = document.getElementById('progressElapsed');
    const statusMsg = document.getElementById('statusMessage');
    const startBtn = document.getElementById('startInstallBtn');
    const openBtn = document.getElementById('openDomainBtn');
    const resetBtn = document.getElementById('resetBtn');
    const logWin = document.getElementById('logWindow');

    if (progressFill) progressFill.style.width = '0%';
    if (progressStatus) progressStatus.innerText = 'WINEJS Install';
    if (progressElapsed) progressElapsed.innerText = '00:00';
    if (statusMsg) statusMsg.innerText = 'Click start to begin';
    if (startBtn) startBtn.classList.remove('hidden');
    if (openBtn) openBtn.classList.add('hidden');
    if (resetBtn) resetBtn.classList.add('hidden');
    if (logWin) logWin.innerHTML = '';
    addLogLine('[0.000] WINEJS installer', 'info');
}

// ============= INITIALIZATION =============
console.log("WINEJS: Initializing...");

function initializeBasedOnPage() {
    const currentUrl = window.location.href;
    const isTerminalPage = currentUrl.includes('/terminal/ui/');
    
    if (!isTerminalPage) {
        setupConsoleNewTab();
    } else {
        createWineJsOverlay();
    }
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeBasedOnPage);
} else {
    initializeBasedOnPage();
}

let lastUrl = location.href;
new MutationObserver(() => {
    const url = location.href;
    if (url !== lastUrl) {
        lastUrl = url;
        initializeBasedOnPage();
    }
}).observe(document, { subtree: true, childList: true });
