// ==UserScript==
// @name         Digital Ocean WINEJS OS Install Screen
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  Clean OS-style install screen with logo, auto-detect and Start button
// @author       You
// @match        https://cloud.digitalocean.com/droplets/*/terminal/ui/*
// @grant        none
// @run-at       document-idle
// @icon         https://cdn.sdappnet.cloud/rtx/images/winejs-logo.png
// ==/UserScript==

(function () {
  ("use strict");
  const wine_128 = `https://cdn.sdappnet.cloud/rtx/images/winejs-logo.png`;
  const wine_26 = `https://cdn.sdappnet.cloud/rtx/images/winejs-logo.png`;

  // ============= STYLES FROM HTML (FIXED) =============
  const style = document.createElement("style");
  style.textContent = `
    /* RESET & GLOBAL DARK BASE */
    * {
        margin: 0;
        padding: 0;
        box-sizing: border-box;
    }

    body {
        background: #000;
        min-height: 100vh;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
        overflow: hidden; /* PREVENT BODY SCROLLING */
    }

    a {
      color: white;
    }

    /* FULLSCREEN INSTALL OVERLAY – macOS / Windows hybrid style */
    .winejs-install {
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background-color: #000000;
        z-index: 9999;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: flex-start;
        overflow: hidden; /* NO SCROLLING ON OVERLAY */
        padding: 0;
        box-sizing: border-box;
        color: white;
    }

    .winejs-install.hidden {
        opacity: 0;
        pointer-events: none;
    }

    /* CONTENT WRAPPER - THIS SCROLLS IF NEEDED */
    .winejs-content {
        display: flex;
        flex-direction: column;
        align-items: center;
        width: 100%;
        max-width: 620px;
        height: 100vh;
        padding: 20px 20px 0 20px;
        box-sizing: border-box;
        overflow-y: auto; /* ONLY CONTENT SCROLLS */
        scrollbar-width: none; /* Firefox */
        -ms-overflow-style: none; /* IE/Edge */
    }

    .winejs-content::-webkit-scrollbar {
        display: none; /* Chrome/Safari/Opera */
    }

    /* STICKY GLOSSY LOGO CONTAINER - FIXED CENTERING */
    .winejs-logo-container {
        text-align: center;
        flex-shrink: 0;
        margin-top: 50px;
        margin-bottom: 65px;
        z-index: 10;
        padding: 20px 40px;
        border-radius: 16px;
        backdrop-filter: blur(8px);
        width: auto;
        display: inline-block;
    }

    /* SIMPLE IMAGE LOGO – using provided URL */
    .winejs-logo {
        display: flex;
        justify-content: center;
        align-items: center;
        width: 100%;
        transform: scale(1.4,1.4);
        filter: drop-shadow(0 4px 12px rgba(0, 150, 255, 0.3));
    }

    .winejs-logo img {
        max-width: 180px;
        height: auto;
        display: block;
        margin: 0 auto;
    }

    /* PROGRESS BAR */
    .progress-section {
        width: 100%;
        max-width: 520px;
        margin: 10px 0 20px;
        padding: 0;
        box-sizing: border-box;
        flex-shrink: 0;
    }

    .progress-label {
        display: flex;
        justify-content: space-between;
        color: #e0e0e0;
        font-size: 13px;
        letter-spacing: 0.5px;
        margin-bottom: 8px;
        font-weight: 300;
        text-transform: uppercase;
    }

    .progress-track {
        background: #1e1e1e;
        height: 4px;
        border-radius: 4px;
        overflow: hidden;
        border: 1px solid #333;
        box-shadow: inset 0 1px 3px rgba(0, 0, 0, 0.5);
    }

    .progress-fill {
        height: 100%;
        width: 0%;
        background: linear-gradient(90deg, #3b8cff, #6eb5ff);
        border-radius: 4px;
        transition: width 0.25s linear;
        box-shadow: 0 0 10px #3b8cff88;
    }

    /* LOG WINDOW – SCROLLABLE INSIDE */
    .log-window {
        width: 100%;
        max-width: 620px;
        background: rgba(12, 12, 12, 0.8);
        border: 1px solid #2a2a2a;
        border-radius: 12px;
        padding: 18px 20px;
        margin: 10px 0 20px;
        font-family: 'Menlo', 'Consolas', 'Courier New', monospace;
        font-size: 13px;
        line-height: 1.7;
        color: #c0c0c0;
        box-shadow: 0 20px 40px -15px black;
        backdrop-filter: blur(2px);
        max-height: 140px;
        overflow-y: auto;
        flex-shrink: 0;
    }

    .log-line {
        white-space: pre-wrap;
        word-break: break-word;
        border-bottom: 1px solid #222;
        padding: 4px 0;
        opacity: 0.9;
    }

    .log-line:last-child {
        border-bottom: none;
    }

    .log-line.success {
        color: #6eca8b;
        font-weight: 500;
    }

    .log-line.info {
        color: #7aa9ff;
    }

    .log-line.warning {
        color: #f9c35f;
    }

    /* STATUS & ACTION BUTTONS - SINGLE BUTTON SECTION */
    .status-area {
        width: 100%;
        max-width: 600px;
        padding: 10px 20px 30px;
        text-align: center;
        color: #aaa;
        font-size: 14px;
        letter-spacing: 0.8px;
        flex-shrink: 0;
    }

    .main-action-btn {
        display: inline-block;
        margin: 10px auto 15px;
        padding: 10px 36px;
        background: linear-gradient(to bottom, #f0f0f0 0%, #d8d8d8 100%);
        color: #000;
        border: 1px solid #6b6b6b;
        border-radius: 20px;
        font-size: 15px;
        font-weight: 500;
        cursor: pointer;
        text-decoration: none;
        letter-spacing: 0.5px;
        transition: 0.1s ease;
        box-shadow: 0 4px 12px rgba(255, 255, 255, 0.05);
    }

    .main-action-btn:hover {
        background: linear-gradient(to bottom, #ffffff, #e8e8e8);
        border-color: #8a8a8a;
    }

    .main-action-btn.hidden {
        display: none;
    }

    .reset-btn {
        background: transparent;
        border: 1px solid #3c3c3c;
        color: #aaa;
        padding: 6px 20px;
        border-radius: 30px;
        font-size: 12px;
        margin-top: 12px;
        cursor: pointer;
        transition: 0.1s;
    }

    .reset-btn.hidden {
        display: none;
    }

    .reset-btn:hover {
        border-color: #777;
        color: #fff;
    }

    /* POPUP OVERLAY - CENTERED, SCROLLABLE INSIDE */
    .popup-overlay {
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background: rgba(0, 0, 0, 0.85);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 10000;
        visibility: hidden;
        opacity: 0;
        transition: 0.2s ease;
    }

    .popup-overlay.show {
        visibility: visible;
        opacity: 1;
    }

    .popup-card {
        background: #1a1a1a;
        border: 1px solid #3a3a3a;
        border-radius: 20px;
        padding: 30px;
        max-width: 600px;
        width: 90%;
        max-height: 80vh; /* 80% of viewport height */
        overflow-y: auto; /* SCROLL INSIDE POPUP */
        color: white;
        box-shadow: 0 30px 50px rgba(0, 0, 0, 0.8);
    }

    .popup-card h3 {
        margin-bottom: 20px;
        font-weight: 300;
        text-align: center;
        color: #ddd;
    }

    .popup-card label {
        display: block;
        margin: 15px 0 5px;
        color: #aaa;
        font-size: 13px;
    }

    .popup-card input {
        width: 100%;
        padding: 10px;
        background: #2a2a2a;
        border: 1px solid #444;
        border-radius: 8px;
        color: white;
        font-size: 14px;
    }

    .popup-buttons {
        display: flex;
        gap: 12px;
        margin-top: 25px;
        margin-bottom: 10px;
    }

    .popup-btn {
        flex: 1;
        padding: 12px;
        border: none;
        border-radius: 30px;
        font-weight: 500;
        cursor: pointer;
        transition: 0.1s;
    }

    .popup-btn.cancel {
        background: #333;
        color: #ccc;
    }

    .popup-btn.cancel:hover {
        background: #444;
    }

    .popup-btn.confirm {
        background: #3b8cff;
        color: white;
    }

    .popup-btn.confirm:hover {
        background: #2a7ae0;
    }

    .signature {
        margin-top: 45px;
        color: #3a3a3a;
        font-size: 11px;
    }

    /* Toggle button */
    .winejs-toggle {
        position: fixed;
        top: 10px;
        left: 10px;
        z-index: 10000;
        background: none;
        border: none;
        cursor: pointer;
    }

    /* Hide the old duplicate text */
    .winejs-install-text {
        display: none;
    }
  `;
  document.head.appendChild(style);

  // ============= CREATE OVERLAY STRUCTURE =============
  const overlay = document.createElement("div");
  overlay.className = "winejs-install";

  const contentWrapper = document.createElement("div");
  contentWrapper.className = "winejs-content";

  // Logo container - FIXED CENTERING
  const logoContainer = document.createElement("div");
  logoContainer.className = "winejs-logo-container";

  const logo = document.createElement("div");
  logo.className = "winejs-logo";
  logo.innerHTML = wine_128;

  logo.onerror = function () {
    this.style.display = "none";
    const fallbackLogo = document.createElement("div");
    fallbackLogo.style.color = "white";
    fallbackLogo.style.fontSize = "48px";
    fallbackLogo.style.fontWeight = "300";
    fallbackLogo.style.letterSpacing = "2px";
    fallbackLogo.textContent = "WINEJS";
    logoContainer.appendChild(fallbackLogo);
  };

  logoContainer.appendChild(logo);
  contentWrapper.appendChild(logoContainer);

  // PROGRESS BAR
  const progressSection = document.createElement("div");
  progressSection.className = "progress-section";
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

  // LOG WINDOW
  const logWindow = document.createElement("div");
  logWindow.className = "log-window";
  logWindow.id = "logWindow";
  contentWrapper.appendChild(logWindow);

  // STATUS AREA - SINGLE BUTTON SECTION
  const statusArea = document.createElement("div");
  statusArea.className = "status-area";
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

  // ============= POPUP OVERLAY =============
  const popupOverlay = document.createElement("div");
  popupOverlay.className = "popup-overlay";
  popupOverlay.id = "popupOverlay";
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
          <div style="  width: 16px; height: 16px; display: flex; align-items: center; justify-content: center; margin: 0; padding: 0;">
            <input type="checkbox" id="enable-pin" checked
                  style="width: 16px; height: 16px; margin: 0; padding: 0; cursor: pointer; background-color: rgba(0,0,255,0.3); border: 1px solid white; box-sizing: border-box;">
          </div>
          <label for="enable-pin" 
                style="color: #ccc; font-size: 13px; cursor: pointer; user-select: none; line-height: 16px;   margin: 0; padding: 0;">
            Enable PIN protection
          </label>
        </div>
        <input type="password" id="pin-input" maxlength="4" placeholder="Enter 4 digits" disabled
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

  // ============= TOGGLE BUTTON =============
  const toggleBtn = document.createElement("button");
  toggleBtn.className = "winejs-toggle";
  toggleBtn.innerHTML = wine_26;
  document.body.appendChild(toggleBtn);

  // ============= PING FUNCTION =============
  function playPing() {
    try {
      const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      const now = audioCtx.currentTime;
      const osc = audioCtx.createOscillator();
      const gainNode = audioCtx.createGain();
      osc.type = "square";
      osc.frequency.setValueAtTime(880, now);
      gainNode.gain.setValueAtTime(0.15, now);
      gainNode.gain.exponentialRampToValueAtTime(0.001, now + 0.15);
      osc.connect(gainNode);
      gainNode.connect(audioCtx.destination);
      osc.start(now);
      osc.stop(now + 0.15);
    } catch (e) {}
  }

  // ============= DOM ELEMENTS =============
  const progressFill = document.getElementById("progressFill");
  const progressStatus = document.getElementById("progressStatus");
  const progressElapsed = document.getElementById("progressElapsed");
  const statusMsg = document.getElementById("statusMessage");
  const startBtn = document.getElementById("startInstallBtn");
  const openBtn = document.getElementById("openDomainBtn");
  const resetBtn = document.getElementById("resetBtn");
  const logWin = document.getElementById("logWindow");

  // Popup elements
  const popup = document.getElementById("popupOverlay");
  const popupCancel = document.getElementById("popupCancel");
  const popupConfirm = document.getElementById("popupConfirm");
  const popupDomain = document.getElementById("popupDomain");
  const popupEmail = document.getElementById("popupEmail");
  const popupPassword = document.getElementById("popupPassword");
  const enablePin = document.getElementById("enable-pin");
  const pinInput = document.getElementById("pin-input");
  const defaultExtBtn = document.getElementById("use-default-ext");
  const customExtBtn = document.getElementById("custom-ext");
  const extensionsInput = document.getElementById("extensions-input");

  // ============= STATE =============
  let domainDetected = false;
  let startTime = null;
  let timerInterval = null;
  let monitorInterval = null;

  // ============= HELPER FUNCTIONS =============
  function addLogLine(text, className = "") {
    // Skip empty or whitespace-only lines
    if (!text || text.trim() === "") {
      return;
    }
    const line = document.createElement("div");
    line.className = "log-line" + (className ? " " + className : "");
    line.textContent = text;
    logWin.appendChild(line);
    logWin.scrollTop = logWin.scrollHeight;
    removeLastEmptyLogLine();
  }

  function removeLastEmptyLogLine() {
    const lastLine = logWin.lastElementChild;
    if (lastLine) {
      const content = lastLine.textContent || "";
      // Remove if empty, just whitespace, or just a single dash/dot
      if (
        content.trim() === "" ||
        content === "-" ||
        content === "." ||
        content === "..."
      ) {
        logWin.removeChild(lastLine);
      }
    }
  }

  function updateTimer() {
    if (!startTime) {
      progressElapsed.innerText = "00:00";
      return;
    }
    const elapsed = Date.now() - startTime;
    const totalSec = Math.floor(elapsed / 1000);
    const mins = Math.floor(totalSec / 60);
    const secs = totalSec % 60;
    progressElapsed.innerText = `${mins.toString().padStart(2, "0")}:${secs
      .toString()
      .padStart(2, "0")}`;
  }

  function resetSimulation() {
    if (timerInterval) clearInterval(timerInterval);
    if (monitorInterval) clearInterval(monitorInterval);
    domainDetected = false;
    startTime = null;

    progressFill.style.width = "0%";
    progressStatus.innerText = "WINEJS Install";
    progressElapsed.innerText = "00:00";
    statusMsg.innerText = "Click start to begin";
    startBtn.classList.remove("hidden");
    openBtn.classList.add("hidden");
    resetBtn.classList.add("hidden");
    logWin.innerHTML = "";
    addLogLine("[0.000] WINEJS installer", "info");
  }

  // ============= TERMINAL MONITOR =============
  function startMonitoring() {
    if (monitorInterval) clearInterval(monitorInterval);

    monitorInterval = setInterval(() => {
      const rows = document.querySelectorAll(
        ".xterm-rows div[data-line-number]"
      );

      rows.forEach((row) => {
        const text = row.innerText;

        // Check for ERROR first - this should reset the view
        if (text.includes("[ERROR]")) {
          addLogLine(text, "error");
          statusMsg.innerText = "❌ Installation failed";
          progressStatus.innerText = "Error";
          progressFill.style.width = "0%";

          // AUTO RESET THE VIEW - show start button again
          startBtn.classList.remove("hidden");
          openBtn.classList.add("hidden");
          resetBtn.classList.remove("hidden");
          domainDetected = false;

          // Stop monitoring and timer
          if (timerInterval) clearInterval(timerInterval);
          if (monitorInterval) clearInterval(monitorInterval);
          monitorInterval = null;
          startTime = null;

          // Play error sound (lower frequency)
          try {
            const audioCtx = new (window.AudioContext ||
              window.webkitAudioContext)();
            const now = audioCtx.currentTime;
            const osc = audioCtx.createOscillator();
            const gainNode = audioCtx.createGain();
            osc.type = "square";
            osc.frequency.setValueAtTime(440, now); // Lower A4 for error
            gainNode.gain.setValueAtTime(0.15, now);
            gainNode.gain.exponentialRampToValueAtTime(0.001, now + 0.2);
            osc.connect(gainNode);
            gainNode.connect(audioCtx.destination);
            osc.start(now);
            osc.stop(now + 0.2);
          } catch (e) {}

          return; // Exit early on error
        }

        if (text.startsWith("PROGRESS:")) {
          const parts = text.split(":");
          if (parts.length >= 3) {
            const percent = parseInt(parts[1]);
            const message = parts.slice(2).join(":");

            progressFill.style.width = percent + "%";
            progressStatus.innerText = message;

            if (percent === 100) {
              statusMsg.innerText = "✅ Installation complete!";
            } else if (percent > 0) {
              statusMsg.innerText = "Installing...";
            }
          }
        } else if (text.startsWith("PING:")) {
          playPing();
        } else if (text.startsWith("DOMAIN:")) {
          const domain = text.substring(7).trim();
          openBtn.href = domain;
          openBtn.classList.remove("hidden");
          startBtn.classList.add("hidden");
          domainDetected = true;
          statusMsg.innerText = "✅ Installation complete!";
        } else {
          const match = text.match(
            /\[SUCCESS\] 🌐 Main domain: (https?:\/\/[^\s]+)/
          );
          if (match && !domainDetected) {
            const domain = match[1];
            domainDetected = true;
            openBtn.href = domain;
            openBtn.classList.remove("hidden");
            startBtn.classList.add("hidden");
            statusMsg.innerText = "✅ Installation complete!";
          }

          let className = "";
          if (text.includes("✅") || text.includes("success"))
            className = "success";
          else if (text.includes("⚠️") || text.includes("WARNING"))
            className = "warning";
          else if (text.includes("ℹ️") || text.includes("INFO"))
            className = "info";

          addLogLine(text, className);
        }
      });
    }, 500);
  }

  // ============= POPUP EVENT HANDLERS =============
  enablePin.addEventListener("change", () => {
    pinInput.disabled = !enablePin.checked;
    if (enablePin.checked) pinInput.focus();
  });

  defaultExtBtn.addEventListener("click", () => {
    extensionsInput.value =
      ".ms3d,.obj,.3ds,.fbx,.dae,.blend,.jpg,.png,.mp3,.wav,.mp4";
    extensionsInput.style.color = "#888";
    extensionsInput.readOnly = true;
  });

  customExtBtn.addEventListener("click", () => {
    extensionsInput.readOnly = false;
    extensionsInput.style.color = "white";
    extensionsInput.style.background = "#252525";
    extensionsInput.focus();
  });

  extensionsInput.addEventListener("input", () => {
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

  // ============= MAIN START BUTTON =============
  startBtn.addEventListener("click", () => {
    popup.classList.add("show");
  });

  popupCancel.addEventListener("click", () => {
    popup.classList.remove("show");
  });

  popupConfirm.addEventListener("click", () => {
    const domain = popupDomain.value.trim();
    const email = popupEmail.value.trim();
    const pass = popupPassword.value.trim();
    const pin = enablePin.checked ? pinInput.value : "";
    const extensions = extensionsInput.value;

    if (!domain.includes(".")) {
      alert("Please enter a valid domain");
      return;
    }
    if (!email.includes("@")) {
      alert("Enter a valid email");
      return;
    }
    if (pass.length < 8) {
      alert("Password must be at least 8 characters");
      return;
    }
    if (enablePin.checked && !/^\d{4}$/.test(pin)) {
      alert("PIN must be exactly 4 digits");
      return;
    }

    popup.classList.remove("show");
    resetSimulation();

    const command = `curl -o "winejs.sh" "https://cdn.sdappnet.cloud/rtx/winejs.sh" && chmod +x "winejs.sh" && sudo ./"winejs.sh" << EOF\n${domain}\n${email}\n${pass}\n${pin}\n${extensions}\nEOF\n`;

    const textarea = document.querySelector(".xterm-helper-textarea");
    if (textarea) {
      textarea.focus();
      document.execCommand("insertText", false, command);
    }

    startTime = Date.now();
    timerInterval = setInterval(updateTimer, 100);
    startMonitoring();
    statusMsg.innerText = "Installing...";
    addLogLine("[0.000] Installation started", "info");
  });

  popup.addEventListener("click", (e) => {
    if (e.target === popup) popup.classList.remove("show");
  });

  resetBtn.addEventListener("click", () => {
    resetSimulation();
    playPing();
  });

  toggleBtn.addEventListener("click", () => {
    overlay.classList.toggle("hidden");
  });

  // ============= CONNECTION MONITOR =============
  let connectionCheckInterval = null;
  let connectionAttempts = 0;
  const MAX_CONNECTION_ATTEMPTS = 90; // 30 seconds max

  function startConnectionMonitor() {
    if (connectionCheckInterval) clearInterval(connectionCheckInterval);
    connectionAttempts = 0;
    // Show start button again
    startBtn.classList.add("hidden");
    logWin.innerHTML = "";
    addLogLine("[0.000] Connecting to instance...", "info");
    statusMsg.innerText = "Connecting to instance...";

    connectionCheckInterval = setInterval(() => {
      connectionAttempts++;

      // Look for shell prompt or any sign we're connected
      const rows = document.querySelectorAll(".xterm-rows div");
      let connected = false;

      rows.forEach((row) => {
        const text = row.innerText;
        // Check for various shell prompt patterns
        if (
          text.includes("root@") ||
          text.includes("$") ||
          text.includes("#") ||
          text.includes("Welcome to Ubuntu") ||
          text.includes("Last login:")
        ) {
          connected = true;
        }
      });

      if (connected) {
        // We're connected! Clear the interval and update UI
        clearInterval(connectionCheckInterval);
        connectionCheckInterval = null;
        logWin.innerHTML = "";
        addLogLine(
          `[${(connectionAttempts * 0.5).toFixed(1)}s] WINEJS installer ready`,
          "info"
        );
        statusMsg.innerText = "Connected! Click start to begin";
        progressStatus.innerText = "Install WINEJS";
        // Show start button again
        startBtn.classList.remove("hidden");
        return;
      }

      // Update progress every 5 attempts
      if (connectionAttempts % 5 === 0) {
        const elapsed = connectionAttempts * 0.5;

        // Update progress bar to show waiting
        const progressPercent = Math.min(
          30,
          (connectionAttempts / MAX_CONNECTION_ATTEMPTS) * 30
        );
        console.log(progressPercent);
        progressStatus.innerText = "Connecting...";
      }

      // Check if we've timed out
      if (connectionAttempts >= MAX_CONNECTION_ATTEMPTS) {
        clearInterval(connectionCheckInterval);
        connectionCheckInterval = null;
        addLogLine(
          `[ERROR] ❌ Failed to connect to instance after ${
            MAX_CONNECTION_ATTEMPTS / 2
          } seconds`,
          "error"
        );
        addLogLine(
          `[ERROR] Please check your Digital Ocean droplet is running and try again`,
          "error"
        );
        statusMsg.innerText = "❌ Connection failed";
        progressStatus.innerText = "Error";
        progressFill.style.width = "0%";

        // Show start button again
        startBtn.classList.remove("hidden");
      }
    }, 500); // Check every 500ms
  }
  // Initial state
  resetSimulation();
  startConnectionMonitor(); // ADD THIS
})();
