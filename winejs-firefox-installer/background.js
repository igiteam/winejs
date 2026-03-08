// Background script for WINEJS Installer
console.log("🔥 WINEJS Installer background loaded at:", new Date().toISOString());

// Track injected tabs to avoid double injection
const injectedTabs = new Set();

// Listen for DOMContentLoaded on Digital Ocean pages
browser.webNavigation.onDOMContentLoaded.addListener(
  handleDOMContentLoaded,
  {
    url: [
      { hostEquals: 'cloud.digitalocean.com', pathPrefix: '/droplets/' }
    ]
  }
);

// Also listen for history changes (for single-page app navigation)
browser.webNavigation.onHistoryStateUpdated.addListener(
  handleDOMContentLoaded,
  {
    url: [
      { hostEquals: 'cloud.digitalocean.com', pathPrefix: '/droplets/' }
    ]
  }
);

function handleDOMContentLoaded(details) {
  const tabId = details.tabId;
  
  // Skip if tabId is invalid or we've already injected
  if (tabId === -1 || injectedTabs.has(tabId)) {
    return;
  }
  
  console.log(`📄 DOM Content Loaded in tab ${tabId}:`, details.url);
  
  // Inject the content script
  browser.tabs.executeScript(tabId, {
    file: 'content.js',
    runAt: 'document_idle'
  }).then(() => {
    console.log(`✅ Injected content.js into tab ${tabId}`);
    injectedTabs.add(tabId);
    
    // Also inject CSS
    return browser.tabs.insertCSS(tabId, {
      file: 'styles.css'
    });
  }).then(() => {
    console.log(`✅ Injected styles.css into tab ${tabId}`);
  }).catch(error => {
    console.error(`❌ Failed to inject into tab ${tabId}:`, error);
  });
}

// Clean up when tabs are closed
browser.tabs.onRemoved.addListener((tabId) => {
  injectedTabs.delete(tabId);
  console.log(`🧹 Cleaned up tab ${tabId}`);
});

// Also handle tab updates (just in case)
browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete' && 
      tab.url && 
      tab.url.includes('cloud.digitalocean.com/droplets/') &&
      !injectedTabs.has(tabId)) {
    
    console.log(`🔄 Tab ${tabId} updated, injecting...`);
    browser.tabs.executeScript(tabId, {
      file: 'content.js',
      runAt: 'document_idle'
    }).then(() => {
      injectedTabs.add(tabId);
      return browser.tabs.insertCSS(tabId, { file: 'styles.css' });
    }).catch(error => {
      console.error(`❌ Failed to inject onUpdate for tab ${tabId}:`, error);
    });
  }
});

let lastPingTime = 0;
const PING_COOLDOWN = 1000; // Minimum 1 second between pings

// Play ping sound
function playPing() {
    const now = Date.now();
    if (now - lastPingTime < PING_COOLDOWN) {
        return;
    }
    lastPingTime = now;
    
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

// Handle messages from content script
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    console.log("Background received message:", message.action);
    
    switch(message.action) {
        case "playPing":
            playPing();
            sendResponse({success: true});
            break;
            
        case "saveSettings":
            browser.storage.local.set({winejsSettings: message.settings})
                .then(() => {
                    console.log("Settings saved");
                    sendResponse({success: true});
                })
                .catch(error => {
                    console.error("Failed to save settings:", error);
                    sendResponse({success: false, error: error.message});
                });
            return true;
            
        case "loadSettings":
            browser.storage.local.get(['winejsSettings'])
                .then(result => {
                    sendResponse({settings: result.winejsSettings || {}});
                })
                .catch(error => {
                    console.error("Failed to load settings:", error);
                    sendResponse({settings: {}});
                });
            return true;
            
        default:
            console.log("Unknown action:", message.action);
            sendResponse({success: false, error: "Unknown action"});
    }
});

// Show notification
function showNotification(message) {
    try {
        browser.notifications.create({
            type: "basic",
            iconUrl: browser.runtime.getURL("icons/icon.png"),
            title: "WINEJS Installer",
            message: message
        });
    } catch (error) {
        console.error("Failed to show notification:", error);
    }
}
