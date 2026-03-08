// Popup script for WINEJS Installer

document.addEventListener('DOMContentLoaded', function() {
    const overlayToggle = document.getElementById('overlayToggle');
    const statusMessage = document.getElementById('statusMessage');
    
    // Load saved overlay setting
    browser.storage.local.get(['overlayVisible']).then(result => {
        const isVisible = result.overlayVisible !== false;
        overlayToggle.checked = isVisible;
    });
    
    // Check current page status
    browser.tabs.query({active: true, currentWindow: true}).then(tabs => {
        const tab = tabs[0];
        if (tab.url && tab.url.includes('cloud.digitalocean.com/droplets/')) {
            if (tab.url.includes('/terminal/')) {
                statusMessage.textContent = '✅ Connected to terminal';
                statusMessage.style.color = '#6eca8b';
            } else {
                statusMessage.textContent = '⚠️ Open a terminal first';
                statusMessage.style.color = '#f9c35f';
            }
        } else {
            statusMessage.textContent = '⚠️ Not on Digital Ocean';
            statusMessage.style.color = '#f9c35f';
        }
    }).catch(() => {
        statusMessage.textContent = '❌ Error checking page';
        statusMessage.style.color = '#f48771';
    });
    
    // Toggle overlay visibility
    overlayToggle.addEventListener('change', () => {
        const isVisible = overlayToggle.checked;
        browser.storage.local.set({overlayVisible: isVisible});
        
        browser.tabs.query({active: true, currentWindow: true}).then(tabs => {
            const tab = tabs[0];
            browser.tabs.sendMessage(tab.id, {
                action: 'toggleOverlay',
                visible: isVisible
            }).catch(() => {});
        });
    });
});
