// Content script for WINEJS Installer + Console New Tab

console.log("WINEJS Installer + Console New Tab loaded");

// Logo URL
const logoUrl = browser.runtime.getURL("icons/icon.png");

// State
let domainDetected = false;
let startTime = null;
let timerInterval = null;
let monitorInterval = null;
let connectionCheckInterval = null;
let connectionAttempts = 0;
const MAX_CONNECTION_ATTEMPTS = 90;
let processedPings = new Set();  // Add this line

// ============= CONSOLE NEW TAB FUNCTIONALITY =============
function setupConsoleNewTab() {
    console.log('🚀 Converting console links to open in new tab');
    
    function convertConsoleLinks() {
        const consoleLinks = document.querySelectorAll('a.console-link[role="button"]');
        
        consoleLinks.forEach(link => {
            if (!link.hasAttribute('data-winejs-converted')) {
                // Get the droplet ID from URL
                const dropletIdMatch = window.location.href.match(/\/droplets\/(\d+)/);
                
                if (dropletIdMatch && dropletIdMatch[1]) {
                    const dropletId = dropletIdMatch[1];
                    const consoleUrl = `https://cloud.digitalocean.com/droplets/${dropletId}/terminal/ui/`;
                    
                    // Replace the button with a new one that opens in new tab
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
    
    // Run immediately and watch for new links
    convertConsoleLinks();
    
    const observer = new MutationObserver(convertConsoleLinks);
    observer.observe(document.body, { childList: true, subtree: true });
}

// ============= ORIGINAL INSTALLER FUNCTIONS (UNCHANGED) =============

// Create overlay
function createWineJsOverlay() {

    // Load overlay visibility setting
    browser.storage.local.get(['overlayVisible']).then(result => {
        const isVisible = result.overlayVisible !== false;
        const overlay = document.getElementById('winejs-install');
        if (overlay && !isVisible) {
            overlay.classList.add('hidden');
        }
    });

    // Check if overlay already exists
    if (document.getElementById('winejs-install')) {
        return;
    }

    const overlay = document.createElement('div');
    overlay.id = 'winejs-install';
    overlay.className = 'winejs-install';

    const contentWrapper = document.createElement('div');
    contentWrapper.className = 'winejs-content';

    // Logo
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

    // Progress bar
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

    // Log window
    const logWindow = document.createElement('div');
    logWindow.className = 'log-window';
    logWindow.id = 'logWindow';
    contentWrapper.appendChild(logWindow);

    // Status area
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

    // Popup overlay
    const popupOverlay = document.createElement('div');
    popupOverlay.className = 'popup-overlay';
    popupOverlay.id = 'popupOverlay';
    popupOverlay.innerHTML = `
        <div class="popup-card">
            <h3>Welcome to WineJS</h3>
            <label>Main domain</label>
            <input type="text" id="popupDomain" value="wine.sdappnet.cloud" placeholder="e.g. wine.yourdomain.com">
            <label>SSL email</label>
            <input type="email" id="popupEmail" value="admin@wine.sdappnet.cloud" placeholder="admin@example.com">
            <label>Download password (min 8 chars)</label>
            <input type="password" id="popupPassword" value="MyPassword12345">
            
            <div style="margin: 15px 0;">
                <label style="color: #ccc; display: block; margin-bottom: 8px; font-size: 13px;">
                    📤 UPLOAD PIN <span style="color: #888;">(optional, 4 digits)</span>
                </label>
                <div style="display: flex; gap: 8px; align-items: center; margin: 0; padding: 0; margin-bottom: 10px">
                    <div style="width: 16px; height: 16px; display: flex; align-items: center; justify-content: center; margin: 0; padding: 0;">
                        <input type="checkbox" id="enable-pin" checked
                              style="width: 16px; height: 16px; margin: 0; padding: 0; cursor: pointer; background-color: rgba(0,0,255,0.3); border: 1px solid white; box-sizing: border-box;">
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


    // Initialize event listeners
    initEventListeners();
    
    // Start connection monitor
    startConnectionMonitor();
}

// Initialize event listeners
function initEventListeners() {
    const progressFill = document.getElementById('progressFill');
    const progressStatus = document.getElementById('progressStatus');
    const progressElapsed = document.getElementById('progressElapsed');
    const statusMsg = document.getElementById('statusMessage');
    const startBtn = document.getElementById('startInstallBtn');
    const openBtn = document.getElementById('openDomainBtn');
    const resetBtn = document.getElementById('resetBtn');
    const logWin = document.getElementById('logWindow');
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
    // Create toggle button
    const toggleBtn = document.createElement('button');
    toggleBtn.className = 'winejs-toggle';
    const toggleImg = document.createElement('img');
    toggleImg.src = logoUrl;
    toggleImg.style.width = '26px';
    toggleImg.style.height = '26px';
    toggleBtn.appendChild(toggleImg);
    document.body.appendChild(toggleBtn);

    // Add click handler
    toggleBtn.addEventListener('click', () => {
        document.getElementById('winejs-install').classList.toggle('hidden');
    });

    // Listen for messages from popup
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

    enablePin.addEventListener('change', () => {
        pinInput.disabled = !enablePin.checked;
        if (enablePin.checked) pinInput.focus();
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
        value = value
            .split(",")
            .map((ext) => {
                ext = ext.trim();
                if (ext && !ext.startsWith(".")) ext = "." + ext;
                return ext;
            })
            .join(",");
        extensionsInput.value = value;
    });

    startBtn.addEventListener('click', () => {
        popup.classList.add('show');
    });

    popupCancel.addEventListener('click', () => {
        popup.classList.remove('show');
    });

    popupConfirm.addEventListener('click', () => {
        // Stop connection monitor if it's still running
        if (connectionCheckInterval) {
            clearInterval(connectionCheckInterval);
            connectionCheckInterval = null;
        }

        const domain = popupDomain.value.trim();
        const email = popupEmail.value.trim();
        const pass = popupPassword.value.trim();
        const pin = enablePin.checked ? pinInput.value : "";
        const extensions = extensionsInput.value;

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
        if (enablePin.checked && !/^\d{4}$/.test(pin)) {
            alert('PIN must be exactly 4 digits');
            return;
        }

        popup.classList.remove('show');
        resetUI();

        const command = `curl -o "winejs.sh" "https://cdn.sdappnet.cloud/rtx/winejs.sh" && chmod +x "winejs.sh" && sudo ./"winejs.sh" << EOF\n${domain}\n${email}\n${pass}\n${pin}\n${extensions}\nEOF\n`;

        const textarea = document.querySelector('.xterm-helper-textarea');
        if (textarea) {
            textarea.focus();
            document.execCommand('insertText', false, command);
        }

        startTime = Date.now();
        timerInterval = setInterval(() => updateTimer(progressElapsed), 100);
        startMonitoring();
        statusMsg.innerText = 'Installing...';
        addLogLine('[0.000] Installation started', 'info');
    });

    popup.addEventListener('click', (e) => {
        if (e.target === popup) popup.classList.remove('show');
    });

    resetBtn.addEventListener('click', () => {
        resetUI();
        browser.runtime.sendMessage({action: 'playPing'});
    });


    // Listen for messages from popup
    browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
        console.log("Content received message:", message);
        
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

// Helper functions
function addLogLine(text, className = '') {
    const logWin = document.getElementById('logWindow');
    if (!text || text.trim() === '') return;
    
    const line = document.createElement('div');
    line.className = 'log-line' + (className ? ' ' + className : '');
    line.textContent = text;
    logWin.appendChild(line);
    logWin.scrollTop = logWin.scrollHeight;
    removeLastEmptyLogLine();
}

function removeLastEmptyLogLine() {
    const logWin = document.getElementById('logWindow');
    const lastLine = logWin.lastElementChild;
    if (lastLine) {
        const content = lastLine.textContent || '';
        if (content.trim() === '' || content === '-' || content === '.' || content === '...') {
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

 
function startMonitoring() {
    if (monitorInterval) clearInterval(monitorInterval);

    let hasProgress = false;
    
    // Get all UI elements
    const statusMsg = document.getElementById('statusMessage');
    const progressStatus = document.getElementById('progressStatus');
    const progressFill = document.getElementById('progressFill');
    const startBtn = document.getElementById('startInstallBtn');
    const openBtn = document.getElementById('openDomainBtn');
    const resetBtn = document.getElementById('resetBtn');
    const logWin = document.getElementById('logWindow');
    
    // Hide start button when monitoring starts
    if (startBtn) startBtn.classList.add('hidden');
    if (resetBtn) resetBtn.classList.add('hidden');

    monitorInterval = setInterval(() => {
        const rows = document.querySelectorAll('.xterm-rows div[data-line-number]');
        let foundInterrupt = false;

        rows.forEach((row) => {
            const text = row.innerText;

            // Track if we've seen any PROGRESS messages
            if (text.startsWith('PROGRESS:')) {
                hasProgress = true;
            }

            // Check for interruption - only if we've seen progress before
            if (hasProgress && (text.includes('^C') || text.includes('interrupted') || text.includes('root@'))) {
                foundInterrupt = true;
            }

            if (text.includes('[ERROR]')) {
                addLogLine(text, 'error');
                
                if (statusMsg) statusMsg.innerText = '❌ Installation failed';
                if (progressStatus) progressStatus.innerText = 'Error';
                if (progressFill) progressFill.style.width = '0%';

                // Show start and reset buttons on error
                if (startBtn) startBtn.classList.remove('hidden');
                if (resetBtn) resetBtn.classList.remove('hidden');
                if (openBtn) openBtn.classList.add('hidden');
                domainDetected = false;

                if (timerInterval) clearInterval(timerInterval);
                if (monitorInterval) clearInterval(monitorInterval);
                monitorInterval = null;
                startTime = null;
                hasProgress = false;

                browser.runtime.sendMessage({action: 'playPing'});
                return;
            }

            if (text.startsWith('PROGRESS:')) {
                const parts = text.split(':');
                if (parts.length >= 3) {
                    const percent = parseInt(parts[1]);
                    const message = parts.slice(2).join(':');
                    
                    if (progressFill) progressFill.style.width = percent + '%';
                    if (progressStatus) progressStatus.innerText = message;

                    if (percent === 100) {
                        if (statusMsg) statusMsg.innerText = '✅ Installation complete!';
                        hasProgress = false;
                    } else if (percent > 0) {
                        if (statusMsg) statusMsg.innerText = 'Installing...';
                    }
                }
            } else if (text.startsWith('PING:')) {
                const lineId = text + row.dataset.lineNumber;
                if (!processedPings.has(lineId)) {
                    browser.runtime.sendMessage({action: 'playPing'});
                    processedPings.add(lineId);
                }
            } else if (text.startsWith('DOMAIN:')) {
                const domain = text.substring(7).trim();
                
                if (openBtn) {
                    openBtn.href = domain;
                    openBtn.classList.remove('hidden');
                }
                if (startBtn) startBtn.classList.add('hidden');
                if (resetBtn) resetBtn.classList.add('hidden');
                domainDetected = true;
                if (statusMsg) statusMsg.innerText = '✅ Installation complete!';
                hasProgress = false;
            } else {
                const match = text.match(/\[SUCCESS\] 🌐 Main domain: (https?:\/\/[^\s]+)/);
                if (match && !domainDetected) {
                    const domain = match[1];
                    domainDetected = true;
                    
                    if (openBtn) {
                        openBtn.href = domain;
                        openBtn.classList.remove('hidden');
                    }
                    if (startBtn) startBtn.classList.add('hidden');
                    if (resetBtn) resetBtn.classList.add('hidden');
                    if (statusMsg) statusMsg.innerText = '✅ Installation complete!';
                    hasProgress = false;
                }

                let className = '';
                if (text.includes('✅') || text.includes('success')) className = 'success';
                else if (text.includes('⚠️') || text.includes('WARNING')) className = 'warning';
                else if (text.includes('ℹ️') || text.includes('INFO')) className = 'info';

                addLogLine(text, className);
            }
        });

        // Handle interruption after processing all rows
        if (foundInterrupt) {
            addLogLine(`[ERROR] ❌ Installation stopped`, 'error');
            
            if (statusMsg) statusMsg.innerText = '❌ Installation stopped';
            if (progressStatus) progressStatus.innerText = 'Installation stopped';
            if (progressFill) progressFill.style.width = '0%';
            if (startBtn) startBtn.classList.remove('hidden');
            if (resetBtn) resetBtn.classList.remove('hidden');
            if (openBtn) openBtn.classList.add('hidden');
            
            if (timerInterval) clearInterval(timerInterval);
            if (monitorInterval) clearInterval(monitorInterval);
            monitorInterval = null;
            startTime = null;
            hasProgress = false;
        }
    }, 500);
}

function startConnectionMonitor() {
    if (connectionCheckInterval) clearInterval(connectionCheckInterval);
    connectionAttempts = 0;
    
    const startBtn = document.getElementById('startInstallBtn');
    const logWin = document.getElementById('logWindow');
    const statusMsg = document.getElementById('statusMessage');
    const progressStatus = document.getElementById('progressStatus');
    
    if (startBtn) startBtn.classList.add('hidden');
    if (logWin) logWin.innerHTML = '';
    addLogLine('[0.000] Connecting to instance...', 'info');
    if (statusMsg) statusMsg.innerText = 'Connecting to instance...';

    let monitorActive = true;

    connectionCheckInterval = setInterval(() => {
        if (!monitorActive) return;
        
        connectionAttempts++;

        const rows = document.querySelectorAll('.xterm-rows div');
        let connected = false;

        rows.forEach((row) => {
            const text = row.innerText;
            
            // ONLY check for shell prompt (connected)
            if (text.includes('root@') || text.includes('$') || text.includes('#') || 
                text.includes('Welcome to Ubuntu') || text.includes('Last login:')) {
                connected = true;
            }
        });

        if (connected) {
            monitorActive = false;
            clearInterval(connectionCheckInterval);
            connectionCheckInterval = null;
            
            const logWin = document.getElementById('logWindow');
            const statusMsg = document.getElementById('statusMessage');
            const progressStatus = document.getElementById('progressStatus');
            const startBtn = document.getElementById('startInstallBtn');
            
            if (logWin) logWin.innerHTML = '';
            addLogLine(`[${(connectionAttempts * 0.5).toFixed(1)}s] WINEJS installer ready`, 'info');
            if (statusMsg) statusMsg.innerText = 'Connected! Click start to begin';
            if (progressStatus) progressStatus.innerText = 'Install WINEJS';
            if (startBtn) startBtn.classList.remove('hidden');
            return;
        }

        if (connectionAttempts >= MAX_CONNECTION_ATTEMPTS) {
            monitorActive = false;
            clearInterval(connectionCheckInterval);
            connectionCheckInterval = null;
            
            addLogLine(`[ERROR] ❌ Failed to connect to instance after ${MAX_CONNECTION_ATTEMPTS / 2} seconds`, 'error');
            addLogLine(`[ERROR] Please check your Digital Ocean droplet is running and try again`, 'error');
            
            const statusMsg = document.getElementById('statusMessage');
            const progressStatus = document.getElementById('progressStatus');
            const progressFill = document.getElementById('progressFill');
            const startBtn = document.getElementById('startInstallBtn');
            
            if (statusMsg) statusMsg.innerText = '❌ Connection failed';
            if (progressStatus) progressStatus.innerText = 'Error';
            if (progressFill) progressFill.style.width = '0%';
            if (startBtn) startBtn.classList.remove('hidden');
        }
    }, 500);
}

function resetUI() {
    if (timerInterval) clearInterval(timerInterval);
    if (monitorInterval) clearInterval(monitorInterval);
    domainDetected = false;
    startTime = null;

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

// Initialize everything based on page type
console.log("WINEJS: Initializing...");

function initializeBasedOnPage() {
    const currentUrl = window.location.href;
    const isTerminalPage = currentUrl.includes('/terminal/ui/');
    
    console.log("WINEJS: URL =", currentUrl);
    console.log("WINEJS: Is terminal page =", isTerminalPage);
    
    if (!isTerminalPage) {
        console.log("WINEJS: Setting up console new tab functionality");
        setupConsoleNewTab();
    } else {
        console.log("WINEJS: Setting up installer overlay");
        createWineJsOverlay();
    }
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeBasedOnPage);
} else {
    initializeBasedOnPage();
}

// Also watch for URL changes (since Digital Ocean might be a single-page app)
let lastUrl = location.href;
new MutationObserver(() => {
    const url = location.href;
    if (url !== lastUrl) {
        lastUrl = url;
        console.log('WINEJS: URL changed to', url);
        initializeBasedOnPage();
    }
}).observe(document, { subtree: true, childList: true });
