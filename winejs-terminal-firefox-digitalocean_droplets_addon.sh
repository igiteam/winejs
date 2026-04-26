#!/bin/bash

# ===============================================
# DigitalOcean Manager Firefox Extension
# Complete droplet management with terminal access
# Left-click → Open DigitalOcean Popup
# ===============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     DigitalOcean Manager Firefox Extension                    ║"
echo "║  Create, List, Delete Droplets & Terminal Access             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Required Scopes for Full Functionality
# Create your DigitalOcean Personal access tokens @https://cloud.digitalocean.com/account/api/tokens
# Tag Scopes (for droplet tagging)
#     ✅ tag:create - Create resource tags (for your wine subdomain tags)
#     ✅ tag:read - View resource tags
#     ✅ tag:delete - Clean up tags when droplets are deleted
# Droplet Scopes
#     ✅ droplet:create - Create new droplets
#     ✅ droplet:read - List and view droplet details
#     ✅ droplet:update - Modify droplet configurations
#     ✅ droplet:delete - Delete droplets
# Domain Scopes (for DNS management)
#     ✅ domain:create - Create domains
#     ✅ domain:read - List domain records
#     ✅ domain:update - Update DNS records
#     ✅ domain:delete - Delete DNS records
# Region & Size Scopes (for droplet creation options)
#     ✅ regions:read - View available regions
#     ✅ sizes:read - View droplet sizes
# Additional Required Scopes (automatically required by droplet actions)
#     ✅ actions:read - Track droplet creation progress
#     ✅ image:read - View Ubuntu images
#     ✅ snapshot:read - View snapshots (for backups)
#     ✅ vpc:read - View VPC networks (for VPC UUID field)

# Summary Table
# Category	Scopes Needed	Purpose
# Tag	create, read, delete	Wine subdomain tagging
# Droplet	create, read, update, delete	Full droplet lifecycle
# Domain	create, read, update, delete	DNS record management
# Region	read	Region selection
# Size	read	Size selection
# Actions	read	Track progress
# Image	read	Ubuntu images
# Snapshot	read	Backups
# VPC	read	VPC networking

# Total: 16 scopes (including automatically required ones)

# Ask for extension folder name
read -p "Enter your extension folder name (default: do-manager): " EXTNAME
EXTNAME=${EXTNAME:-do-manager}

# Check if folder exists
if [ -d "$EXTNAME" ]; then
    read -p "Folder '$EXTNAME' already exists. Remove it? (y/N): " REMOVE
    REMOVE=${REMOVE:-N}
    if [[ "$REMOVE" == "y" || "$REMOVE" == "Y" ]]; then
        rm -rf "$EXTNAME"
    else
        echo "Exiting to avoid overwriting."
        exit 1
    fi
fi

# Create folder structure
mkdir -p "$EXTNAME/icons"
cd "$EXTNAME" || exit

# Download icon
echo -e "${CYAN}📥 Downloading extension icon...${NC}"
curl -s -o icons/icon.png "https://cdn.sdappnet.cloud/rtx/images/digitalocean-black-icon.png"
cp icons/icon.png icons/icon128.png

# Create manifest.json
cat << 'EOL' > manifest.json
{
  "manifest_version": 2,
  "name": "DigitalOcean Manager",
  "version": "1.0",
  "description": "Manage DigitalOcean droplets - create, list, delete, and access terminals",
  "icons": {
    "48": "icons/icon.png",
    "128": "icons/icon128.png"
  },
  "permissions": [
    "storage",
    "tabs",
    "notifications",
    "contextMenus",
    "webNavigation",
    "<all_urls>"
  ],
  "browser_action": {
    "default_icon": "icons/icon.png",
    "default_title": "DO Manager",
    "default_popup": "popup.html"
  },
  "background": {
    "scripts": ["background.js"],
    "persistent": true
  },
  "browser_specific_settings": {
    "gecko": {
      "id": "@do-manager",
      "strict_min_version": "78.0"
    }
  }
}
EOL

// Create background.js
cat << 'EOL' > background.js
// ===============================================
// DigitalOcean Manager - Background Script
// Handles API communication and background processes
// ===============================================

let apiToken = "";
let activeCreations = new Map(); // Track ongoing droplet creations
let activeDeletions = new Map(); // Track ongoing deletions with DNS cleanup

// Load saved API token
browser.storage.local.get(['apiToken']).then(result => {
  if (result.apiToken) {
    apiToken = result.apiToken;
    console.log("API token loaded");
  }
});

// Create context menu
browser.runtime.onInstalled.addListener(() => {
  browser.contextMenus.create({
    id: "do-manager",
    title: "DigitalOcean Manager",
    contexts: ["all"]
  });
  
  browser.contextMenus.create({
    id: "list-droplets",
    parentId: "do-manager",
    title: "List Droplets",
    contexts: ["all"]
  });
  
  browser.contextMenus.create({
    id: "create-droplet",
    parentId: "do-manager",
    title: "Create Droplet",
    contexts: ["all"]
  });
  
  browser.contextMenus.create({
    id: "open-console",
    parentId: "do-manager",
    title: "Open DO Console",
    contexts: ["all"]
  });
});

// Handle context menu clicks
browser.contextMenus.onClicked.addListener((info, tab) => {
  switch(info.menuItemId) {
    case "list-droplets":
      browser.browserAction.openPopup();
      break;
    case "create-droplet":
      browser.browserAction.openPopup();
      setTimeout(() => {
        browser.runtime.sendMessage({action: "switchToCreate"}).catch(() => {});
      }, 500);
      break;
    case "open-console":
      browser.tabs.create({ url: "https://cloud.digitalocean.com/droplets" });
      break;
  }
});

// Handle messages from popup
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log("Background received:", message.action);
  
  if (message.action === "getApiToken") {
    sendResponse({apiToken: apiToken});
    return true;
  }
  
  if (message.action === "saveApiToken") {
    apiToken = message.apiToken;
    browser.storage.local.set({apiToken: message.apiToken})
      .then(() => sendResponse({success: true}))
      .catch(() => sendResponse({success: false}));
    return true;
  }
  
  if (message.action === "listDroplets") {
    listDroplets(message.apiToken)
      .then(result => sendResponse({success: true, droplets: result}))
      .catch(error => sendResponse({success: false, error: error.message}));
    return true;
  }
  
  if (message.action === "getDroplet") {
    getDroplet(message.apiToken, message.dropletId)
      .then(result => sendResponse({success: true, droplet: result}))
      .catch(error => sendResponse({success: false, error: error.message}));
    return true;
  }
  
  if (message.action === "createDroplet") {
    // Start background creation process
    const creationId = Date.now().toString() + '-' + Math.random().toString(36).substr(2, 9);
    createDropletBackground(message.apiToken, message.dropletConfig, message.domain, message.subdomain, creationId)
      .then(result => sendResponse({success: true, creationId, droplet: result}))
      .catch(error => sendResponse({success: false, error: error.message}));
    return true;
  }
  
  if (message.action === "deleteDroplet") {
    // Start background deletion process
    const deletionId = Date.now().toString() + '-' + Math.random().toString(36).substr(2, 9);
    deleteDropletBackground(message.apiToken, message.dropletId, message.domain, message.dropletIp, deletionId)
      .then(() => sendResponse({success: true, deletionId}))
      .catch(error => sendResponse({success: false, error: error.message}));
    return true;
  }
  
  if (message.action === "restartDroplet") {
    restartDropletBackground(message.apiToken, message.dropletId, message.dropletName)
      .then(() => sendResponse({success: true}))
      .catch(error => sendResponse({success: false, error: error.message}));
    return true;
  }

  if (message.action === "listDomainRecords") {
    listDomainRecords(message.apiToken, message.domain)
      .then(result => sendResponse({success: true, records: result}))
      .catch(error => sendResponse({success: false, error: error.message}));
    return true;
  }
  
  if (message.action === "createDomainRecord") {
    createDomainRecord(message.apiToken, message.domain, message.recordConfig)
      .then(result => sendResponse({success: true, record: result}))
      .catch(error => sendResponse({success: false, error: error.message}));
    return true;
  }
  
  if (message.action === "deleteDomainRecord") {
    deleteDomainRecord(message.apiToken, message.domain, message.recordId)
      .then(() => sendResponse({success: true}))
      .catch(error => sendResponse({success: false, error: error.message}));
    return true;
  }
  
  if (message.action === "ensureDomain") {
    ensureDomain(message.apiToken, message.domain, message.ipAddress)
      .then(() => sendResponse({success: true}))
      .catch(error => sendResponse({success: false, error: error.message}));
    return true;
  }
  
  if (message.action === "getProcessStatus") {
    const creation = activeCreations.get(message.processId);
    const deletion = activeDeletions.get(message.processId);
    sendResponse({success: true, process: creation || deletion});
    return true;
  }
  
  if (message.action === "getAllProcesses") {
    const processes = [];
    activeCreations.forEach((data, id) => {
      processes.push({id, type: 'creation', ...data});
    });
    activeDeletions.forEach((data, id) => {
      processes.push({id, type: 'deletion', ...data});
    });
    sendResponse({success: true, processes});
    return true;
  }
  
  sendResponse({success: false, error: "Unknown action"});
  return true;
});

// Background creation process
async function createDropletBackground(token, config, domain, subdomain, creationId) {
  const creationData = {
    status: 'starting',
    dropletName: config.name,
    domain: domain,
    subdomain: subdomain,
    timestamp: Date.now(),
    ip: null,
    error: null,
    progress: 'Starting creation...'
  };
  
  activeCreations.set(creationId, creationData);
  
  try {
    // Update status
    creationData.status = 'creating';
    creationData.progress = 'Creating droplet...';
    activeCreations.set(creationId, creationData);
    
    // Show notification
    browser.notifications.create({
      type: 'basic',
      title: 'DigitalOcean Manager',
      message: `Creating droplet: ${config.name}`,
      iconUrl: 'icons/icon.png'
    });
    
    // Create droplet
    const response = await fetch('https://api.digitalocean.com/v2/droplets', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(config)
    });
    
    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.message || 'Failed to create droplet');
    }
    
    const data = await response.json();
    const droplet = data.droplet;
    
    creationData.dropletId = droplet.id;
    creationData.status = 'waiting_ip';
    creationData.progress = 'Waiting for IP address...';
    activeCreations.set(creationId, creationData);
    
    // Show notification
    browser.notifications.create({
      type: 'basic',
      title: 'DigitalOcean Manager',
      message: `${config.name} created. Waiting for IP...`,
      iconUrl: 'icons/icon.png'
    });
    
    // Wait for IP
    const ip = await waitForDropletIPBackground(token, droplet.id, creationId);
    
    if (ip) {
      creationData.status = 'configuring_dns';
      creationData.progress = 'Configuring DNS...';
      creationData.ip = ip;
      activeCreations.set(creationId, creationData);
      
      // Setup DNS
      await setupDNSBackground(token, domain, subdomain, ip, creationId);
      
      creationData.status = 'complete';
      creationData.progress = 'Complete!';
      activeCreations.set(creationId, creationData);
      
      // Show success notification
      browser.notifications.create({
        type: 'basic',
        title: 'DigitalOcean Manager',
        message: `✅ Droplet ready: ${config.name} @ ${ip}`,
        iconUrl: 'icons/icon.png'
      });
      
      return droplet;
    }
  } catch (error) {
    creationData.status = 'failed';
    creationData.error = error.message;
    creationData.progress = `Failed: ${error.message}`;
    activeCreations.set(creationId, creationData);
    
    // Show error notification
    browser.notifications.create({
      type: 'basic',
      title: 'DigitalOcean Manager',
      message: `❌ Creation failed: ${error.message}`,
      iconUrl: 'icons/icon.png'
    });
    
    throw error;
  }
  
  // Clean up after 1 hour
  setTimeout(() => {
    activeCreations.delete(creationId);
  }, 3600000);
}

// Background deletion process
async function deleteDropletBackground(token, dropletId, domain, dropletIp, deletionId) {
  const deletionData = {
    status: 'starting',
    dropletId: dropletId,
    domain: domain,
    dropletIp: dropletIp,
    timestamp: Date.now(),
    error: null,
    progress: 'Starting deletion...'
  };
  
  activeDeletions.set(deletionId, deletionData);
  
  try {
    // Show notification
    browser.notifications.create({
      type: 'basic',
      title: 'DigitalOcean Manager',
      message: `Deleting droplet ${dropletId}...`,
      iconUrl: 'icons/icon.png'
    });
    
    // Delete droplet
    deletionData.status = 'deleting';
    deletionData.progress = 'Deleting droplet...';
    activeDeletions.set(deletionId, deletionData);
    
    const deleteResponse = await fetch(`https://api.digitalocean.com/v2/droplets/${dropletId}`, {
      method: 'DELETE',
      headers: { 'Authorization': `Bearer ${token}` }
    });
    
    if (!deleteResponse.ok && deleteResponse.status !== 204) {
      const error = await deleteResponse.json();
      throw new Error(error.message || 'Failed to delete droplet');
    }
    
    // Clean up DNS if domain is set
    if (domain && dropletIp) {
      deletionData.status = 'cleaning_dns';
      deletionData.progress = 'Cleaning up DNS records...';
      activeDeletions.set(deletionId, deletionData);
      
      try {
        const recordsResponse = await fetch(`https://api.digitalocean.com/v2/domains/${domain}/records`, {
          headers: { 'Authorization': `Bearer ${token}` }
        });
        
        if (recordsResponse.ok) {
          const data = await recordsResponse.json();
          
          for (const record of data.domain_records) {
            if (record.type === 'A' && record.data === dropletIp) {
              await fetch(`https://api.digitalocean.com/v2/domains/${domain}/records/${record.id}`, {
                method: 'DELETE',
                headers: { 'Authorization': `Bearer ${token}` }
              });
            }
          }
        }
      } catch (dnsError) {
        console.error('DNS cleanup error:', dnsError);
      }
    }
    
    deletionData.status = 'complete';
    deletionData.progress = 'Complete!';
    activeDeletions.set(deletionId, deletionData);
    
    // Show success notification
    browser.notifications.create({
      type: 'basic',
      title: 'DigitalOcean Manager',
      message: `✅ Droplet ${dropletId} deleted successfully`,
      iconUrl: 'icons/icon.png'
    });
    
  } catch (error) {
    deletionData.status = 'failed';
    deletionData.error = error.message;
    deletionData.progress = `Failed: ${error.message}`;
    activeDeletions.set(deletionId, deletionData);
    
    // Show error notification
    browser.notifications.create({
      type: 'basic',
      title: 'DigitalOcean Manager',
      message: `❌ Deletion failed: ${error.message}`,
      iconUrl: 'icons/icon.png'
    });
    
    throw error;
  }
  
  // Clean up after 1 hour
  setTimeout(() => {
    activeDeletions.delete(deletionId);
  }, 3600000);
}

// Background restart process
async function restartDropletBackground(token, dropletId, dropletName) {
  try {
    // Show notification
    browser.notifications.create({
      type: 'basic',
      title: 'DigitalOcean Manager',
      message: `Restarting ${dropletName}...`,
      iconUrl: 'icons/icon.png'
    });
    
    const response = await fetch(`https://api.digitalocean.com/v2/droplets/${dropletId}/actions`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ type: 'reboot' })
    });
    
    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.message || 'Failed to restart droplet');
    }
    
    // Show success notification
    browser.notifications.create({
      type: 'basic',
      title: 'DigitalOcean Manager',
      message: `✅ ${dropletName} restart initiated`,
      iconUrl: 'icons/icon.png'
    });
    
    return true;
  } catch (error) {
    // Show error notification
    browser.notifications.create({
      type: 'basic',
      title: 'DigitalOcean Manager',
      message: `❌ Restart failed: ${error.message}`,
      iconUrl: 'icons/icon.png'
    });
    throw error;
  }
}

async function waitForDropletIPBackground(token, dropletId, creationId, maxAttempts = 20) {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const response = await fetch(`https://api.digitalocean.com/v2/droplets/${dropletId}`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      
      if (!response.ok) {
        await sleep(3000);
        continue;
      }
      
      const data = await response.json();
      const droplet = data.droplet;
      
      if (droplet.networks && droplet.networks.v4) {
        const publicIP = droplet.networks.v4.find(net => net.type === 'public');
        if (publicIP) {
          return publicIP.ip_address;
        }
      }
      
      // Update progress
      const creationData = activeCreations.get(creationId);
      if (creationData) {
        creationData.progress = `Waiting for IP... (${attempt}/${maxAttempts})`;
        activeCreations.set(creationId, creationData);
      }
      
      await sleep(3000);
    } catch (error) {
      await sleep(3000);
    }
  }
  return null;
}

async function setupDNSBackground(token, domain, subdomain, ipAddress, creationId) {
  try {
    // Check if domain exists
    const checkResponse = await fetch(`https://api.digitalocean.com/v2/domains/${domain}`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    
    if (checkResponse.status === 404) {
      // Create domain
      await fetch('https://api.digitalocean.com/v2/domains', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ name: domain, ip_address: ipAddress })
      });
    }
    
    // List existing records
    const recordsResponse = await fetch(`https://api.digitalocean.com/v2/domains/${domain}/records`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    
    if (recordsResponse.ok) {
      const data = await recordsResponse.json();
      
      // Delete existing A record for this subdomain
      for (const record of data.domain_records) {
        if (record.type === 'A' && record.name === subdomain) {
          await fetch(`https://api.digitalocean.com/v2/domains/${domain}/records/${record.id}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${token}` }
          });
        }
      }
    }
    
    // Create new A record
    await fetch(`https://api.digitalocean.com/v2/domains/${domain}/records`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        type: 'A',
        name: subdomain,
        data: ipAddress,
        ttl: 1800
      })
    });
    
    return true;
  } catch (error) {
    console.error('DNS setup error:', error);
    return false;
  }
}

// API Functions
async function listDroplets(token) {
  const response = await fetch('https://api.digitalocean.com/v2/droplets?per_page=200', {
    headers: { 'Authorization': `Bearer ${token}` }
  });
  
  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.message || 'Failed to list droplets');
  }
  
  const data = await response.json();
  return data.droplets;
}

async function getDroplet(token, dropletId) {
  const response = await fetch(`https://api.digitalocean.com/v2/droplets/${dropletId}`, {
    headers: { 'Authorization': `Bearer ${token}` }
  });
  
  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.message || 'Failed to get droplet');
  }
  
  const data = await response.json();
  return data.droplet;
}

async function listDomainRecords(token, domain) {
  const response = await fetch(`https://api.digitalocean.com/v2/domains/${domain}/records`, {
    headers: { 'Authorization': `Bearer ${token}` }
  });
  
  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.message || 'Failed to list records');
  }
  
  const data = await response.json();
  return data.domain_records;
}

async function createDomainRecord(token, domain, recordConfig) {
  const response = await fetch(`https://api.digitalocean.com/v2/domains/${domain}/records`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(recordConfig)
  });
  
  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.message || 'Failed to create record');
  }
  
  const data = await response.json();
  return data.domain_record;
}

async function deleteDomainRecord(token, domain, recordId) {
  const response = await fetch(`https://api.digitalocean.com/v2/domains/${domain}/records/${recordId}`, {
    method: 'DELETE',
    headers: { 'Authorization': `Bearer ${token}` }
  });
  
  if (!response.ok && response.status !== 204) {
    const error = await response.json();
    throw new Error(error.message || 'Failed to delete record');
  }
}

async function ensureDomain(token, domain, ipAddress) {
  // Check if domain exists
  const checkResponse = await fetch(`https://api.digitalocean.com/v2/domains/${domain}`, {
    headers: { 'Authorization': `Bearer ${token}` }
  });
  
  if (checkResponse.status === 404) {
    // Create domain
    const createResponse = await fetch('https://api.digitalocean.com/v2/domains', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ name: domain, ip_address: ipAddress })
    });
    
    if (!createResponse.ok) {
      const error = await createResponse.json();
      throw new Error(error.message || 'Failed to create domain');
    }
  } else if (!checkResponse.ok) {
    const error = await checkResponse.json();
    throw new Error(error.message || 'Failed to check domain');
  }
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
EOL

# Create popup.html
cat << 'EOL' > popup.html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>DigitalOcean Manager</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
      user-select: none;
      -moz-user-select: none;
    }
    
    body {
      width: 340px;
      background: #1e1e1e;
      color: #e0e0e0;
      overflow: hidden;
    }
    
    .container {
      padding: 12px;
    }
    
    /* Header */
    .header {
      display: flex;
      align-items: center;
      gap: 10px;
      margin-bottom: 12px;
      padding-bottom: 8px;
      border-bottom: 1px solid #333;
    }
    
    .logo {
      width: 32px;
      height: 32px;
      background: #0066ff;
      border-radius: 6px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: white;
      font-weight: bold;
      font-size: 16px;
    }
    
    .logo img {
      width: 100%;
      height: 100%;
      border-radius: 6px;
    }
    
    .title {
      flex: 1;
    }
    
    .title h1 {
      font-size: 15px;
      font-weight: 600;
      color: #fff;
      margin-bottom: 2px;
    }
    
    .title p {
      font-size: 11px;
      color: #999;
    }
    
    .title a {
      color: #3b8cff;
      text-decoration: none;
    }
    
    /* Token Input */
    .token-section {
      background: #252525;
      border-radius: 6px;
      padding: 8px;
      margin-bottom: 12px;
    }
    
    .token-input {
      width: 100%;
      padding: 8px;
      background: #333;
      border: 1px solid #444;
      border-radius: 4px;
      color: #fff;
      font-size: 12px;
      font-family: monospace;
    }
    
    .token-input:focus {
      outline: none;
      border-color: #3b8cff;
    }
    
    /* Tabs */
    .tabs {
      display: flex;
      gap: 4px;
      background: #252525;
      padding: 4px;
      border-radius: 6px;
      margin-bottom: 12px;
    }
    
    .tab {
      flex: 1;
      padding: 8px 4px;
      text-align: center;
      font-size: 12px;
      font-weight: 500;
      border-radius: 4px;
      cursor: pointer;
      color: #999;
      transition: all 0.2s;
    }
    
    .tab.active {
      background: #3b8cff;
      color: white;
    }
    
    .tab:hover:not(.active) {
      background: #333;
    }
    
    /* Content Sections */
    .content-section {
      display: none;
      background: #252525;
      border-radius: 6px;
      padding: 8px;
      max-height: 300px;
      overflow-y: auto;
    }
    
    .content-section.active {
      display: block;
    }
    
    /* Droplet List */
    .droplet-item {
      padding: 10px;
      border-bottom: 1px solid #333;
      cursor: pointer;
      transition: background 0.2s;
    }
    
    .droplet-item:hover {
      background: #2a2a2a;
    }
    
    .droplet-item.selected {
      background: #2a3a4a;
      border-left: 3px solid #3b8cff;
    }
    
    .droplet-name {
      font-weight: 600;
      font-size: 13px;
      color: #fff;
      margin-bottom: 6px;
      display: flex;
      align-items: center;
      gap: 6px;
    }
    
    .wine-tag {
      background: #6b4f9c;
      color: white;
      font-size: 9px;
      padding: 2px 6px;
      border-radius: 3px;
    }
    
    .droplet-details {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      font-size: 11px;
      color: #999;
    }
    
    .droplet-detail {
      display: flex;
      align-items: center;
      gap: 3px;
    }
    
    .status-indicator {
      display: inline-block;
      width: 8px;
      height: 8px;
      border-radius: 50%;
    }
    
    .status-active { background: #6eca8b; }
    .status-off { background: #f48771; }
    .status-other { background: #f9c35f; }
    
    /* Action Buttons */
    .action-buttons {
      display: flex;
      gap: 6px;
      margin-top: 10px;
    }
    
    .action-btn {
      flex: 1;
      padding: 8px;
      background: #333;
      border: none;
      border-radius: 4px;
      color: #fff;
      font-size: 11px;
      font-weight: 500;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 4px;
      transition: background 0.2s;
    }
    
    .action-btn:hover:not(:disabled) {
      background: #404040;
    }
    
    .action-btn.primary {
      background: #3b8cff;
    }
    
    .action-btn.primary:hover:not(:disabled) {
      background: #2a7ae0;
    }
    
    .action-btn.danger {
      background: #f48771;
    }
    
    .action-btn.danger:hover:not(:disabled) {
      background: #e06a50;
    }
    
    .action-btn:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }
    
    /* Form */
    .form-group {
      margin-bottom: 12px;
    }
    
    .form-group label {
      display: block;
      font-size: 11px;
      color: #999;
      margin-bottom: 4px;
    }
    
    .form-group input,
    .form-group select {
      width: 100%;
      padding: 8px;
      background: #333;
      border: 1px solid #444;
      border-radius: 4px;
      color: #fff;
      font-size: 12px;
    }
    
    .form-group input:focus,
    .form-group select:focus {
      outline: none;
      border-color: #3b8cff;
    }
    
    .form-row {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 8px;
    }
    
    /* Status */
    .status {
      margin-top: 12px;
      padding: 8px;
      background: #252525;
      border-radius: 6px;
      font-size: 12px;
    }
    
    .status.success { color: #6eca8b; }
    .status.error { color: #f48771; }
    .status.warning { color: #f9c35f; }
    
    /* Progress */
    .progress {
      display: none;
      margin-top: 8px;
      padding: 8px;
      background: #333;
      border-radius: 4px;
      font-size: 11px;
      color: #999;
      text-align: center;
    }
    
    .progress.active {
      display: block;
    }
    
    /* Footer */
    .footer {
      margin-top: 12px;
      padding-top: 8px;
      border-top: 1px solid #333;
      font-size: 10px;
      color: #555;
      text-align: center;
    }
    
    .footer a {
      color: #3b8cff;
      text-decoration: none;
    }
    
    /* Referral */
    .referral {
      display: flex;
      justify-content: center;
      margin-top: 8px;
    }
    
    .referral img {
      max-width: 100%;
      height: auto;
      border-radius: 4px;
    }
    
    /* Empty state */
    .empty-state {
      padding: 20px;
      text-align: center;
      color: #666;
      font-size: 12px;
    }
    
    /* Quick actions */
    .quick-actions {
      display: flex;
      gap: 4px;
      margin-top: 6px;
    }
    
    .quick-btn {
      flex: 1;
      padding: 4px;
      background: #333;
      border: none;
      border-radius: 3px;
      color: #999;
      font-size: 10px;
      cursor: pointer;
    }
    
    .quick-btn:hover {
      background: #404040;
      color: #fff;
    }
  </style>
</head>
<body>
  <div class="container">
    <!-- Header -->
    <div class="header">
      <div class="logo">
        <img src="icons/icon.png" alt="DO">
      </div>
      <div class="title">
        <h1>DigitalOcean Manager</h1>
        <p><a href="https://cloud.digitalocean.com/droplets" target="_blank">Droplets</a> · DNS · Console</p>
      </div>
    </div>
    
    <!-- API Token -->
    <div class="token-section">
      <div style="display: flex; gap: 8px; align-items: center;">
        <input type="password" id="apiToken" class="token-input" placeholder="Enter DigitalOcean API Token" style="flex: 1;">
        <a href="https://cloud.digitalocean.com/account/api/tokens" target="_blank" style="color: #3b8cff; font-size: 20px; text-decoration: none; line-height: 1;">🔗</a>
      </div>
    </div>
    
    <!-- Tabs -->
    <div class="tabs">
      <div class="tab active" data-tab="terminal">💻 Terminal</div>
      <div class="tab" data-tab="list">📋 List</div>
      <div class="tab" data-tab="create">➕ Create</div>
    </div>

    <!-- Terminal Tab -->
    <div id="terminalContent" class="content-section active">
      <div id="terminalsList"></div>
      <div class="action-buttons">
        <button id="refreshTerminals" class="action-btn">🔄 Refresh</button>
      </div>
    </div>
    
    <!-- List Tab -->
    <div id="listContent" class="content-section">
      <div id="dropletsList"></div>
      <div class="action-buttons">
        <button id="refreshDroplets" class="action-btn">🔄 Refresh</button>
        <button id="restartSelected" class="action-btn primary" style="display: none;">🔄 Restart</button>
        <button id="deleteSelected" class="action-btn danger" style="display: none;">🗑️ Delete</button>
      </div>
    </div>
    
    <!-- Create Tab -->
    <div id="createContent" class="content-section">
      <div class="form-group">
        <label>Domain (for subdomain)</label>
        <input type="text" id="createDomain" placeholder="example.com">
      </div>
      <div class="form-group">
        <label>Subdomain</label>
        <input type="text" id="createSubdomain" value="wine" placeholder="wine">
      </div>
      <div class="form-group">
        <label>Root Password</label>
        <input type="text" id="createPassword" value="YourPassword1234!">
      </div>
      <div class="form-row">
        <div class="form-group">
          <label>Region</label>
          <select id="createRegion">
            <option value="lon1">London (lon1)</option>
            <option value="nyc1">New York (nyc1)</option>
            <option value="nyc3">New York (nyc3)</option>
            <option value="sfo3">San Francisco (sfo3)</option>
            <option value="ams3">Amsterdam (ams3)</option>
            <option value="sgp1">Singapore (sgp1)</option>
          </select>
        </div>
        <div class="form-group">
          <label>Size</label>
          <select id="createSize">
            <option value="s-1vcpu-1gb-amd">1 vCPU, 1GB</option>
            <option value="s-1vcpu-2gb-amd">1 vCPU, 2GB</option>
            <option value="s-2vcpu-2gb-amd">2 vCPU, 2GB</option>
            <option value="s-2vcpu-4gb-amd">2 vCPU, 4GB</option>
          </select>
        </div>
      </div>
      <div class="form-group">
        <label>VPC UUID (optional)</label>
        <input type="text" id="createVpcUuid" placeholder="vpc-uuid">
      </div>
      <div class="action-buttons">
        <button id="createDropletBtn" class="action-btn primary">🚀 Create Droplet</button>
      </div>
    </div>
    
    <!-- Status -->
    <div id="status" class="status"></div>
    
    <!-- Progress -->
    <div id="progress" class="progress">
      <span id="progressMessage">Processing...</span>
    </div>
    
    <!-- Referral -->
    <div class="referral">
      <a href="https://www.digitalocean.com/?refcode=582fcc29135e&utm_campaign=Referral_Invite&utm_medium=Referral_Program&utm_source=badge">
        <img src="https://web-platforms.sfo2.cdn.digitaloceanspaces.com/WWW/Badge%203.svg" alt="DigitalOcean Referral Badge">
      </a>
    </div>
    
    <!-- Footer -->
    <div class="footer">
      <a href="#" id="openConsole">Open DO Console</a> · v1.0
    </div>
  </div>
  
  <script src="popup.js"></script>
</body>
</html>
EOL

// Create popup.js
cat << 'EOL' > popup.js
// ===============================================
// DigitalOcean Manager - Popup Script
// Handles UI interactions and API calls
// ===============================================

document.addEventListener('DOMContentLoaded', function() {
  // DOM Elements
  const apiToken = document.getElementById('apiToken');
  const tabs = document.querySelectorAll('.tab');
  const listContent = document.getElementById('listContent');
  const createContent = document.getElementById('createContent');
  const terminalContent = document.getElementById('terminalContent');
  const statusEl = document.getElementById('status');
  const progress = document.getElementById('progress');
  const progressMessage = document.getElementById('progressMessage');
  
  // Create form elements
  const createDomain = document.getElementById('createDomain');
  const createSubdomain = document.getElementById('createSubdomain');
  const createPassword = document.getElementById('createPassword');
  const createRegion = document.getElementById('createRegion');
  const createSize = document.getElementById('createSize');
  const createVpcUuid = document.getElementById('createVpcUuid');
  
  // Buttons
  const refreshDroplets = document.getElementById('refreshDroplets');
  const refreshTerminals = document.getElementById('refreshTerminals');
  const restartSelected = document.getElementById('restartSelected');
  const deleteSelected = document.getElementById('deleteSelected');
  const createDropletBtn = document.getElementById('createDropletBtn');
  const openConsole = document.getElementById('openConsole');
  
  // State
  let currentToken = '';
  let selectedDropletId = null;
  let droplets = [];
  
  // Load saved token and form values
  browser.storage.local.get(['apiToken', 'createFormValues']).then(result => {
    if (result.apiToken) {
      apiToken.value = result.apiToken;
      currentToken = result.apiToken;
    }
    
    // Load saved form values
    if (result.createFormValues) {
      const saved = result.createFormValues;
      if (saved.domain) createDomain.value = saved.domain;
      if (saved.subdomain) createSubdomain.value = saved.subdomain;
      if (saved.password) createPassword.value = saved.password;
      if (saved.region) createRegion.value = saved.region;
      if (saved.size) createSize.value = saved.size;
      if (saved.vpcUuid) createVpcUuid.value = saved.vpcUuid;
    }
    
    // Check which tab is active and load appropriate content
    const activeTab = document.querySelector('.tab.active').dataset.tab;
    if (activeTab === 'terminal') {
      loadTerminals();
    } else {
      loadDroplets();
    }
  });

  // Function to get droplets data
  async function getDropletsData() {
    if (!currentToken) {
      showStatus('Enter API token first', 'warning');
      return null;
    }
    
    try {
      const response = await browser.runtime.sendMessage({
        action: 'listDroplets',
        apiToken: currentToken
      });
      
      if (!response.success) throw new Error(response.error);
      return response.droplets;
    } catch (error) {
      showStatus(`Error: ${error.message}`, 'error');
      return null;
    }
  }
  
  // Tab switching
  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      tabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      
      const tabName = tab.dataset.tab;
      listContent.classList.toggle('active', tabName === 'list');
      createContent.classList.toggle('active', tabName === 'create');
      terminalContent.classList.toggle('active', tabName === 'terminal');
      
      if (tabName === 'list' && currentToken) loadDroplets();
      if (tabName === 'terminal' && currentToken) loadTerminals();
    });
  });
  
  // Save token on change
  apiToken.addEventListener('change', () => {
    currentToken = apiToken.value.trim();
    browser.runtime.sendMessage({
      action: 'saveApiToken',
      apiToken: currentToken
    }).then(() => {
      showStatus('Token saved', 'success');
      if (currentToken) loadDroplets();
    });
  });
  
  // Auto-save form values on any change
  function saveFormValues() {
    const formValues = {
      domain: createDomain.value.trim(),
      subdomain: createSubdomain.value.trim(),
      password: createPassword.value.trim(),
      region: createRegion.value,
      size: createSize.value,
      vpcUuid: createVpcUuid.value.trim()
    };
    
    browser.storage.local.set({ createFormValues: formValues }).catch(error => {
      console.error('Failed to save form values:', error);
    });
  }
  
  // Add event listeners for auto-save
  createDomain.addEventListener('input', saveFormValues);
  createSubdomain.addEventListener('input', saveFormValues);
  createPassword.addEventListener('input', saveFormValues);
  createRegion.addEventListener('change', saveFormValues);
  createSize.addEventListener('change', saveFormValues);
  createVpcUuid.addEventListener('input', saveFormValues);
  
  // Refresh buttons
  refreshDroplets.addEventListener('click', () => loadDroplets());
  refreshTerminals.addEventListener('click', () => loadTerminals());
  
  // Create droplet
  createDropletBtn.addEventListener('click', createDroplet);
  
  // Delete selected
  deleteSelected.addEventListener('click', deleteSelectedDroplet);
  
  // Restart selected
  restartSelected.addEventListener('click', restartSelectedDroplet);

  // Open console
  openConsole.addEventListener('click', (e) => {
    e.preventDefault();
    browser.tabs.create({ url: 'https://cloud.digitalocean.com/droplets' });
  });
  
  // Load droplets
  async function loadDroplets() {
    if (!currentToken) {
      showStatus('Enter API token first', 'warning');
      return;
    }
    
    showProgress('Fetching droplets...');
    
    // Hide action buttons
    restartSelected.style.display = 'none';
    deleteSelected.style.display = 'none';

    const data = await getDropletsData();
    if (data) {
      droplets = data;
      displayDroplets(droplets);
      showStatus(`Found ${droplets.length} droplet(s)`, 'success');
    }
    hideProgress();
  }
  
  function displayDroplets(droplets) {
    const listEl = document.getElementById('dropletsList');
    
    if (!droplets || droplets.length === 0) {
      listEl.innerHTML = '<div class="empty-state">No droplets found</div>';
      return;
    }
    
    let html = '';
    droplets.forEach(droplet => {
      const ip = getDropletIP(droplet);
      const hasWineTag = droplet.tags && droplet.tags.some(t => t.includes('wine') || t.includes('subdomain'));
      const status = droplet.status;
      
      html += `
        <div class="droplet-item" data-id="${droplet.id}" data-ip="${ip || ''}">
          <div class="droplet-name">
            ${droplet.name}
            ${hasWineTag ? '<span class="wine-tag">🍷</span>' : ''}
          </div>
          <div class="droplet-details">
            <span class="droplet-detail">
              <span class="status-indicator status-${status === 'active' ? 'active' : status === 'off' ? 'off' : 'other'}"></span>
              ${status}
            </span>
            <span class="droplet-detail">🆔 ${droplet.id}</span>
            <span class="droplet-detail">🌐 ${ip || 'No IP'}</span>
            <span class="droplet-detail">📍 ${droplet.region.slug}</span>
          </div>
        </div>
      `;
    });
    
    listEl.innerHTML = html;
    
    // Add click handlers
    document.querySelectorAll('.droplet-item').forEach(item => {
      item.addEventListener('click', () => {
        document.querySelectorAll('.droplet-item').forEach(i => i.classList.remove('selected'));
        item.classList.add('selected');
        selectedDropletId = item.dataset.id;
        restartSelected.style.display = 'block';
        deleteSelected.style.display = 'block';
      });
    });
  }
  
  function loadTerminals() {
    if (!currentToken) {
      showStatus('Enter API token first', 'warning');
      return;
    }
    
    showProgress('Loading terminals...');
    
    getDropletsData().then(data => {
      if (data) {
        droplets = data;
        displayTerminals(droplets);
        showStatus(`Found ${droplets.length} terminal(s)`, 'success');
      }
      hideProgress();
    });
  }

  function displayTerminals(droplets) {
    const terminalsEl = document.getElementById('terminalsList');
    
    if (!droplets || droplets.length === 0) {
      terminalsEl.innerHTML = '<div class="empty-state">No droplets found for terminal access</div>';
      return;
    }
    
    let html = '';
    droplets.forEach(droplet => {
      const ip = getDropletIP(droplet);
      const status = droplet.status;
      
      if (status === 'active' && ip) {
        html += `
          <a href="https://cloud.digitalocean.com/droplets/${droplet.id}/terminal/ui/" target="_blank" class="droplet-item" style="text-decoration: none; color: inherit; display: block;" data-id="${droplet.id}" data-ip="${ip}">
            <div class="droplet-name">
              ${droplet.name}
            </div>
            <div class="droplet-details">
              <span class="droplet-detail">
                <span class="status-indicator status-active"></span>
                active
              </span>
              <span class="droplet-detail">🌐 ${ip}</span>
              <span class="droplet-detail">💻</span>
            </div>
          </a>
        `;
      }
    });
    
    if (html === '') {
      terminalsEl.innerHTML = '<div class="empty-state">No active droplets with IP addresses</div>';
    } else {
      terminalsEl.innerHTML = html;
    }
  }
  
  async function createDroplet() {
    if (!currentToken) {
      showStatus('Enter API token first', 'warning');
      return;
    }
    
    const domain = createDomain.value.trim();
    const subdomain = createSubdomain.value.trim();
    const password = createPassword.value.trim();
    const region = createRegion.value;
    const size = createSize.value;
    const vpcUuid = createVpcUuid.value.trim();
    
    if (!domain || !password) {
      showStatus('Domain and password required', 'warning');
      return;
    }
    
    showProgress('Starting background creation...');
    
    try {
      const randomId = generateRandomId(4);
      const dropletName = `ubuntu-${size}-${region}-${randomId}`;
      
      // Cloud-init user data
      const userData = `#cloud-config
  chpasswd:
    list: |
      root:${password}
    expire: False
  ssh_pwauth: true
  runcmd:
    - echo "root:${password}" | chpasswd
    - sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    - sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    - systemctl restart ssh`;
      
      const dropletConfig = {
        name: dropletName,
        region: region,
        size: size,
        image: "ubuntu-24-04-x64",
        tags: ["do-manager", "automated", "password-auth", `${subdomain}-subdomain`],
        monitoring: true,
        ipv6: false,
        with_droplet_agent: true,
        user_data: userData
      };
      
      if (vpcUuid) {
        dropletConfig.vpc_uuid = vpcUuid;
      }
      
      // Start creation in background
      const createResponse = await browser.runtime.sendMessage({
        action: 'createDroplet',
        apiToken: currentToken,
        dropletConfig,
        domain,
        subdomain
      });
      
      if (!createResponse.success) throw new Error(createResponse.error);
      
      showStatus('✅ Creation started in background! You can close this popup.', 'success');
      
      // Show notification that process started
      if (Notification.permission === 'granted') {
        new Notification('DigitalOcean Manager', {
          body: `Creating ${dropletName}... You'll be notified when complete.`,
          icon: 'icons/icon.png'
        });
      }
      
      // Switch to list tab after 2 seconds
      setTimeout(() => {
        document.querySelector('[data-tab="list"]').click();
        loadDroplets();
        showStatus('Creating in background... Check notifications', 'info');
      }, 2000);
      
    } catch (error) {
      showStatus(`Error: ${error.message}`, 'error');
    } finally {
      hideProgress();
    }
  }
  
  async function waitForDropletIP(dropletId, maxAttempts = 20) {
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        const response = await browser.runtime.sendMessage({
          action: 'getDroplet',
          apiToken: currentToken,
          dropletId
        });
        
        if (!response.success) throw new Error(response.error);
        
        const droplet = response.droplet;
        const ip = getDropletIP(droplet);
        
        if (ip) return ip;
        
        showProgress(`Waiting for IP... (${attempt}/${maxAttempts})`);
        await sleep(3000);
      } catch (error) {
        await sleep(3000);
      }
    }
    return null;
  }
  
  async function setupDNS(domain, subdomain, ipAddress) {
    try {
      // Ensure domain exists
      await browser.runtime.sendMessage({
        action: 'ensureDomain',
        apiToken: currentToken,
        domain,
        ipAddress
      });
      
      // List existing records
      const listResponse = await browser.runtime.sendMessage({
        action: 'listDomainRecords',
        apiToken: currentToken,
        domain
      });
      
      if (listResponse.success && listResponse.records) {
        // Delete existing A record for this subdomain
        for (const record of listResponse.records) {
          if (record.type === 'A' && record.name === subdomain) {
            await browser.runtime.sendMessage({
              action: 'deleteDomainRecord',
              apiToken: currentToken,
              domain,
              recordId: record.id
            });
          }
        }
      }
      
      // Create new A record
      await browser.runtime.sendMessage({
        action: 'createDomainRecord',
        apiToken: currentToken,
        domain,
        recordConfig: {
          type: 'A',
          name: subdomain,
          data: ipAddress,
          ttl: 1800
        }
      });
      
      return true;
    } catch (error) {
      console.error('DNS setup error:', error);
      return false;
    }
  }
  
  async function deleteSelectedDroplet() {
    if (!selectedDropletId) return;
    
    if (!confirm('Delete this droplet? This cannot be undone.')) return;
    
    showProgress('Starting background deletion...');
    
    try {
      const droplet = droplets.find(d => d.id == selectedDropletId);
      const dropletIp = droplet ? getDropletIP(droplet) : null;
      const domain = createDomain.value.trim();
      
      // Start deletion in background
      const deleteResponse = await browser.runtime.sendMessage({
        action: 'deleteDroplet',
        apiToken: currentToken,
        dropletId: selectedDropletId,
        domain,
        dropletIp
      });
      
      if (!deleteResponse.success) throw new Error(deleteResponse.error);
      
      showStatus('✅ Deletion started in background', 'success');
      
      // Show notification
      if (Notification.permission === 'granted') {
        new Notification('DigitalOcean Manager', {
          body: `Deleting droplet... You'll be notified when complete.`,
          icon: 'icons/icon.png'
        });
      }
      
      selectedDropletId = null;
      restartSelected.style.display = 'none';
      deleteSelected.style.display = 'none';
      
      // Refresh list after 2 seconds
      setTimeout(() => {
        loadDroplets();
      }, 2000);
      
    } catch (error) {
      showStatus(`Error: ${error.message}`, 'error');
    } finally {
      hideProgress();
    }
  }

  async function restartSelectedDroplet() {
    if (!selectedDropletId) return;
    
    if (!confirm('Restart this droplet? It will be unavailable for a few minutes.')) return;
    
    showProgress('Starting restart...');
    
    try {
      const droplet = droplets.find(d => d.id == selectedDropletId);
      const dropletName = droplet ? droplet.name : 'Droplet';
      
      const restartResponse = await browser.runtime.sendMessage({
        action: 'restartDroplet',
        apiToken: currentToken,
        dropletId: selectedDropletId,
        dropletName: dropletName
      });
      
      if (!restartResponse.success) throw new Error(restartResponse.error);
      
      showStatus('✅ Restart initiated', 'success');
      
      // Show notification
      if (Notification.permission === 'granted') {
        new Notification('DigitalOcean Manager', {
          body: `Restarting ${dropletName}...`,
          icon: 'icons/icon.png'
        });
      }
      
      selectedDropletId = null;
      restartSelected.style.display = 'none';
      deleteSelected.style.display = 'none';
      
      // Refresh list after 2 seconds
      setTimeout(() => {
        loadDroplets();
      }, 2000);
      
    } catch (error) {
      showStatus(`Error: ${error.message}`, 'error');
    } finally {
      hideProgress();
    }
  }

  // Request notification permission on load
  if (Notification.permission === 'default') {
    Notification.requestPermission();
  }
  
  function getDropletIP(droplet) {
    if (droplet.networks && droplet.networks.v4) {
      const publicIP = droplet.networks.v4.find(net => net.type === 'public');
      return publicIP ? publicIP.ip_address : null;
    }
    return null;
  }
  
  function generateRandomId(length = 4) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    for (let i = 0; i < length; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }
  
  function showStatus(message, type = 'info') {
    statusEl.textContent = message;
    statusEl.className = 'status ' + type;
  }
  
  function showProgress(message) {
    progressMessage.textContent = message;
    progress.classList.add('active');
  }
  
  function hideProgress() {
    progress.classList.remove('active');
  }
  
  function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
});
EOL

# Create README.md
cat << 'EOL' > README.md
# DigitalOcean Manager - Firefox Extension

A complete DigitalOcean droplet management tool for Firefox.

## Features
- 📋 **List Droplets** - View all droplets with status, IP, region
- ➕ **Create Droplets** - Create Ubuntu droplets with custom subdomain DNS
- 🗑️ **Delete Droplets** - Safely delete droplets and clean up DNS records
- 💻 **Terminal Access** - Open web terminals directly
- 🌐 **DNS Management** - Auto-create/clean up A records
- 🔐 **Password Auth** - Configure root password via cloud-init
- 🍷 **Wine Subdomain** - Special tagging for wine subdomains

## Installation
1. Open Firefox and go to `about:debugging`
2. Click "This Firefox" → "Load Temporary Add-on"
3. Select the `manifest.json` file

## Getting API Token
1. Go to https://cloud.digitalocean.com/account/api/tokens
2. Generate a new token with read/write permissions
3. Enter token in extension popup

## Usage
1. Enter your DigitalOcean API token
2. Use tabs to switch between:
   - **List** - View and manage droplets
   - **Create** - Create new droplets with subdomain
   - **Terminal** - Quick access to terminals

## Credits
- Icon: DigitalOcean brand
- Built for Firefox
EOL

# Create LICENSE
cat << EOL > LICENSE
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
# Package extension as .xpi file
# ===============================================

echo -e "${CYAN}📦 Packaging extension as .xpi file...${NC}"

XPI_FILE="${EXTNAME}.xpi"

# Remove any existing XPI
rm -f "$XPI_FILE" 2>/dev/null

# Create XPI
if command -v zip &> /dev/null; then
  zip -r "$XPI_FILE" * -x "*.xpi" -x "*.DS_Store"
elif command -v 7z &> /dev/null; then
  7z a "$XPI_FILE" * -r -x!*.xpi -x!*.DS_Store
else
  echo -e "${RED}Error: Need zip or 7z to create XPI${NC}"
  exit 1
fi

# Check if XPI was created
if [ -f "$XPI_FILE" ]; then
  echo -e "${GREEN}✅ Created: $XPI_FILE${NC}"
  echo -e "${YELLOW}📦 Size: $(du -h "$XPI_FILE" | cut -f1)${NC}"
  
  # Move to Downloads
  echo -e "${CYAN}📁 Moving to Downloads...${NC}"
  mv "$XPI_FILE" "$HOME/Downloads/${EXTNAME}.xpi"
  echo -e "${GREEN}✅ XPI saved to: $HOME/Downloads/${EXTNAME}.xpi${NC}"
else
  echo -e "${RED}❌ Failed to create XPI file${NC}"
fi

# Open Firefox Developer Edition addons page
echo -e "${CYAN}🌐 Opening Firefox Developer Edition addons page...${NC}"
/Applications/Firefox\ Developer\ Edition.app/Contents/MacOS/firefox "about:addons" &
# Go to parent directory
cd ..


echo -e ""
echo -e "${GREEN}✅ Extension generation complete!${NC}"
echo -e ""
echo -e "${YELLOW}🎯 Features:${NC}"
echo -e "  ✅ List droplets with status and IP"
echo -e "  ✅ Create droplets with cloud-init"
echo -e "  ✅ Delete droplets with DNS cleanup"
echo -e "  ✅ Terminal overlay for quick actions"
echo -e "  ✅ Context menu integration"
echo -e "  ✅ Wine subdomain tagging"
echo -e "  ✅ DNS record management"
echo -e ""
echo -e "${CYAN}Load in Firefox: about:debugging → This Firefox → Load Temporary Add-on${NC}"
echo -e "${CYAN}Or drag and drop the XPI file into Firefox${NC}"

# 🚀 How to Use
#     Save the script as create-do-manager.sh
#     Make it executable: chmod +x create-do-manager.sh
#     Run it: ./create-do-manager.sh
#     Enter extension name (or press Enter for default "do-manager")

#     The script will:
#         Create all necessary files
#         Download the icon
#         Package as .xpi
#         Save to Downloads folder
#         Open Firefox

# ✨ Features Implemented
# Feature	Description
# 📋 List Droplets	View all droplets with status, IP, region, tags
# ➕ Create Droplets	Create Ubuntu 24.04 droplets with cloud-init
# 🗑️ Delete Droplets	Delete droplets and clean up DNS records
# 💻 Terminal Access	Open web terminals with one click
# 🌐 DNS Management	Auto-create/delete A records for subdomains
# 🔐 Password Auth	Configure root password via cloud-init
# 🍷 Wine Subdomain	Special tagging for wine subdomains
# 🔄 Refresh	Update droplet list in real-time
# 📋 Copy SSH	Copy SSH command from terminal overlay

# The extension follows the same template structure as TinyIMG with:
#     Clean dark theme matching the DigitalOcean aesthetic
#     Tabbed interface for different functions
#     Progress indicators and status messages
#     Error handling and validation
#     Terminal overlay for quick actions

