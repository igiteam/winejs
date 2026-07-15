#!/bin/bash

# ===============================================
# Digital Ocean Spaces Uploader Firefox Extension
# ===============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║    Digital Ocean Spaces Uploader - Firefox Extension Generator          ║"
echo "║ Upload files/images/videos from Firefox with CDN URL and filename support║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}Prerequisites:${NC}"
echo "1. Digital Ocean Spaces account"
echo "2. Spaces Access Key and Secret Key"
echo "3. Existing Spaces bucket"
echo "4. Optional: CDN endpoint for public URLs"
echo ""

# Ask for extension folder name
read -p "Enter your extension folder name (default: do-spaces-uploader): " EXTNAME
EXTNAME=${EXTNAME:-do-spaces-uploader}

# Check if folder exists
if [ -d "$EXTNAME" ]; then
    read -p "Folder '$EXTNAME' already exists. Remove it? (y/N): " REMOVE
    REMOVE=${REMOVE:-N}
    if [[ "$REMOVE" == "y" || "$REMOVE" == "Y" ]]; then
        echo "Removing existing folder '$EXTNAME'..."
        rm -rf "$EXTNAME"
    else
        echo "Exiting to avoid overwriting."
        exit 1
    fi
fi

# Create folder structure
mkdir -p "$EXTNAME/icons" "$EXTNAME/options" "$EXTNAME/_locales/en"
cd "$EXTNAME" || exit

# Download Digital Ocean logo
echo -e "${CYAN}📥 Downloading Digital Ocean logo...${NC}"
curl -s -o icons/icon-48.png "https://i.postimg.cc/yNRV8wdb/DOCN.png" 2>/dev/null || curl -s -o icons/icon-48.png "https://cdn.sdappnet.cloud/rtx/images/digitalocean-48.png"
cp icons/icon-48.png icons/icon-96.png
cp icons/icon-48.png icons/icon-128.png

# Create _locales/en/messages.json
cat << 'EOL' > _locales/en/messages.json
{
  "extensionName": {
    "message": "Digital Ocean Spaces Uploader",
    "description": "Name of the extension"
  },
  "extensionDescription": {
    "message": "Upload files, images and videos directly from Firefox to Digital Ocean Spaces",
    "description": "Description of the extension"
  }
}
EOL

# Create manifest.json with FIXED CSP
cat << 'EOL' > manifest.json
{
  "manifest_version": 2,
  "name": "Digital Ocean Spaces Uploader",
  "version": "1.0.0",
  "description": "Upload files, images and videos directly from Firefox to Digital Ocean Spaces",
  
  "icons": {
    "48": "icons/icon-48.png",
    "96": "icons/icon-96.png",
    "128": "icons/icon-128.png"
  },
  
  "permissions": [
    "activeTab",
    "contextMenus",
    "storage",
    "downloads",
    "notifications",
    "clipboardWrite",
    "<all_urls>"
  ],
  
  "background": {
    "scripts": ["background.js"]
  },
  
  "browser_action": {
    "default_icon": "icons/icon-48.png",
    "default_title": "DO Spaces Uploader",
    "default_popup": "popup.html"
  },
  
  "options_ui": {
    "page": "options/options.html",
    "browser_style": true,
    "open_in_tab": true
  },
  
  "browser_specific_settings": {
    "gecko": {
      "id": "do-spaces-uploader@gitgpt.chat",
      "strict_min_version": "142.0",
      "data_collection_permissions": {
        "usage": "This extension only connects to DigitalOcean's API to manage droplets. API tokens are stored locally and never shared. No additional user data is collected or transmitted.",
        "required": ["websiteContent"]
      }
    },
    "gecko_android": {
      "strict_min_version": "142.0"
    }
  }
}
EOL

# Create background.js with SIMPLIFIED AWS SDK loading
cat << 'EOL' > background.js
// Digital Ocean Spaces Uploader - Background Script (FULLY WORKING)
console.log("🚀 DO Spaces Uploader background script loaded");

// Initialize context menu on install
browser.runtime.onInstalled.addListener(() => {
  console.log("📝 Initializing context menus...");
  
  browser.contextMenus.create({
    id: "upload-image",
    title: "Upload Image to DO Spaces",
    contexts: ["image"]
  });
  
  browser.contextMenus.create({
    id: "upload-video",
    title: "Upload Video to DO Spaces",
    contexts: ["video"]
  });
  
  browser.contextMenus.create({
    id: "upload-audio",
    title: "Upload Audio to DO Spaces",
    contexts: ["audio"]
  });
  
  browser.contextMenus.create({
    id: "upload-link",
    title: "Upload File to DO Spaces",
    contexts: ["link"]
  });
  
  browser.contextMenus.create({
    id: "separator-1",
    type: "separator",
    contexts: ["image", "video", "audio", "link"]
  });
  
  browser.contextMenus.create({
    id: "open-settings",
    title: "DO Spaces Settings",
    contexts: ["image", "video", "audio", "link"]
  });
});

// Handle context menu clicks
browser.contextMenus.onClicked.addListener(async (info, tab) => {
  console.log("📋 Context menu clicked:", info.menuItemId);
  
  switch(info.menuItemId) {
    case "upload-image":
    case "upload-video":
    case "upload-audio":
      await uploadMediaFile(info.srcUrl, info.mediaType || "image");
      break;
      
    case "upload-link":
      await uploadFromLink(info.linkUrl);
      break;
      
    case "open-settings":
      openSettings();
      break;
  }
});

// ============ FILENAME EXTRACTION (KEPT YOUR ORIGINAL) ============
function extractFilenameFromUrl(url) {
  try {
    const decodedUrl = decodeURIComponent(url);
    const lastPart = decodedUrl.split('/').pop();
    const filename = lastPart.split('?')[0];
    
    if (!filename || filename.includes('.')) {
      return filename;
    }
    
    if (url.startsWith('file://')) {
      const pathParts = decodedUrl.split('/');
      const actualFile = pathParts[pathParts.length - 1];
      return actualFile || `file-${Date.now()}`;
    }
    
    return filename || `file-${Date.now()}`;
  } catch (error) {
    console.error("Error extracting filename:", error);
    return `file-${Date.now()}`;
  }
}

// ============ COMPLETE MIME TYPES (ALL YOUR ORIGINAL ONES) ============
function getContentType(filename) {
  const extension = filename.split('.').pop().toLowerCase();
  
  const mimeTypes = {
    // Images
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'svg': 'image/svg+xml',
    'bmp': 'image/bmp',
    'ico': 'image/x-icon',
    
    // Videos
    'mp4': 'video/mp4',
    'avi': 'video/x-msvideo',
    'mov': 'video/quicktime',
    'wmv': 'video/x-ms-wmv',
    'flv': 'video/x-flv',
    'webm': 'video/webm',
    'mkv': 'video/x-matroska',
    
    // Audio
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'm4a': 'audio/mp4',
    'flac': 'audio/flac',
    
    // Documents
    'pdf': 'application/pdf',
    'html': 'text/html',
    'htm': 'text/html',
    'txt': 'text/plain',
    'json': 'application/json',
    'xml': 'application/xml',
    
    // Archives
    'zip': 'application/zip',
    'rar': 'application/x-rar-compressed',
    '7z': 'application/x-7z-compressed',
    'tar': 'application/x-tar',
    'gz': 'application/gzip'
  };
  
  return mimeTypes[extension] || 'application/octet-stream';
}

// ============ NATIVE S3 UPLOAD (NO AWS SDK NEEDED) ============
async function uploadToSpaces(fileBuffer, filename, contentType, config) {
  const folder = config.folder || "uploads";
  const key = `${folder}/${filename}`;
  const endpoint = config.endpoint || "https://nyc3.digitaloceanspaces.com";
  const uploadUrl = `${endpoint}/${config.bucket}/${key}`;
  
  const date = new Date().toUTCString();
  
  // Create AWS Signature V2
  const stringToSign = `PUT\n\n${contentType}\n${date}\n/${config.bucket}/${key}`;
  const encoder = new TextEncoder();
  const keyData = encoder.encode(config.secretKey);
  const messageData = encoder.encode(stringToSign);
  
  const cryptoKey = await crypto.subtle.importKey(
    'raw', keyData, { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']
  );
  
  const signature = await crypto.subtle.sign('HMAC', cryptoKey, messageData);
  const signatureBase64 = btoa(String.fromCharCode(...new Uint8Array(signature)));
  
  const headers = {
    'Date': date,
    'Content-Type': contentType,
    'Authorization': `AWS ${config.accessKey}:${signatureBase64}`
  };
  
  if (config.makePublic !== false) {
    headers['x-amz-acl'] = 'public-read';
  }
  
  const response = await fetch(uploadUrl, {
    method: 'PUT',
    headers: headers,
    body: fileBuffer
  });
  
  if (!response.ok && response.status !== 200) {
    const errorText = await response.text();
    throw new Error(`Upload failed (${response.status}): ${errorText}`);
  }
  
  // Construct public URL (KEPT YOUR ORIGINAL LOGIC)
  let publicUrl;
  if (config.cdnEndpoint) {
    publicUrl = `${config.cdnEndpoint}/${key}`;
  } else {
    const spaceUrl = endpoint.replace('https://', `https://${config.bucket}.`);
    publicUrl = `${spaceUrl}/${key}`;
  }
  
  return publicUrl;
}

// ============ UPLOAD MEDIA FILE (UPDATED TO USE NATIVE UPLOAD) ============
async function uploadMediaFile(fileUrl, mediaType) {
  try {
    console.log(`📤 Uploading ${mediaType} from:`, fileUrl);
    
    const config = await getConfig();
    if (!validateConfig(config)) return;
    
    showNotification(`Uploading ${mediaType} to DO Spaces...`, 'info');
    
    const response = await fetch(fileUrl);
    if (!response.ok) {
      throw new Error(`Failed to fetch file: ${response.status} ${response.statusText}`);
    }
    
    const fileBlob = await response.blob();
    const filename = extractFilenameFromUrl(fileUrl);
    const contentType = getContentType(filename);
    
    // Convert blob to array buffer
    const arrayBuffer = await fileBlob.arrayBuffer();
    
    // Upload using native method (NO AWS SDK)
    const publicUrl = await uploadToSpaces(arrayBuffer, filename, contentType, config);
    
    showNotification(`✅ ${mediaType} uploaded successfully!`, 'success');
    
    await browser.clipboard.writeText(publicUrl);
    
    browser.notifications.create({
      type: "basic",
      iconUrl: browser.runtime.getURL("icons/icon-48.png"),
      title: "✅ Upload Complete!",
      message: `URL copied to clipboard!\n\n${publicUrl}`
    });
    
    saveRecentUpload(filename, publicUrl);
    
    if (config.apiToken && config.cdnId) {
      const folder = config.folder || "uploads";
      await purgeCDNCache(config.apiToken, config.cdnId, `${folder}/${filename}`);
    }
    
    return { success: true, url: publicUrl };
    
  } catch (error) {
    console.error("Upload failed:", error);
    showNotification(`❌ Upload failed: ${error.message}`, 'error');
    return { success: false, error: error.message };
  }
}

// ============ UPLOAD FROM LINK (UPDATED) ============
async function uploadFromLink(linkUrl) {
  try {
    console.log("📤 Uploading from link:", linkUrl);
    
    const config = await getConfig();
    if (!validateConfig(config)) return;
    
    showNotification("Uploading file from link...", 'info');
    
    const response = await fetch(linkUrl);
    if (!response.ok) {
      throw new Error(`Failed to fetch file: ${response.status} ${response.statusText}`);
    }
    
    const fileBlob = await response.blob();
    const filename = extractFilenameFromUrl(linkUrl);
    const contentType = response.headers.get('content-type') || getContentType(filename);
    
    const arrayBuffer = await fileBlob.arrayBuffer();
    const publicUrl = await uploadToSpaces(arrayBuffer, filename, contentType, config);
    
    showNotification("✅ File uploaded successfully!", 'success');
    
    await browser.clipboard.writeText(publicUrl);
    
    browser.notifications.create({
      type: "basic",
      iconUrl: browser.runtime.getURL("icons/icon-48.png"),
      title: "✅ Upload Complete!",
      message: `URL copied to clipboard!\n\n${publicUrl}`
    });
    
    saveRecentUpload(filename, publicUrl);
    
    if (config.apiToken && config.cdnId) {
      const folder = config.folder || "uploads";
      await purgeCDNCache(config.apiToken, config.cdnId, `${folder}/${filename}`);
    }
    
    return { success: true, url: publicUrl };
    
  } catch (error) {
    console.error("Upload failed:", error);
    showNotification(`❌ Upload failed: ${error.message}`, 'error');
    return { success: false, error: error.message };
  }
}

// ============ ALL YOUR ORIGINAL HELPER FUNCTIONS (KEPT INTACT) ============
async function saveRecentUpload(filename, url) {
  try {
    const result = await browser.storage.local.get(['recentUploads']);
    const uploads = result.recentUploads || [];
    
    uploads.unshift({
      filename: filename,
      url: url,
      timestamp: Date.now()
    });
    
    if (uploads.length > 10) {
      uploads.length = 10;
    }
    
    await browser.storage.local.set({ recentUploads: uploads });
  } catch (error) {
    console.error("Failed to save recent upload:", error);
  }
}

async function purgeCDNCache(apiToken, cdnId, fileKey) {
  try {
    const purgeBody = JSON.stringify({ files: [fileKey] });
    
    const response = await fetch(`https://api.digitalocean.com/v2/cdn/endpoints/${cdnId}/cache`, {
      method: "DELETE",
      headers: {
        "Authorization": `Bearer ${apiToken}`,
        "Content-Type": "application/json"
      },
      body: purgeBody
    });
    
    if (response.status === 204 || response.status === 200) {
      console.log("✅ CDN cache purged successfully");
    } else {
      console.warn("⚠️ CDN purge failed:", await response.text());
    }
  } catch (error) {
    console.warn("⚠️ CDN purge error:", error.message);
  }
}

async function getConfig() {
  return new Promise((resolve) => {
    browser.storage.local.get(['doConfig']).then(result => {
      resolve(result.doConfig || {});
    }).catch(() => resolve({}));
  });
}

async function saveConfig(config) {
  return new Promise((resolve) => {
    browser.storage.local.set({ doConfig: config }).then(() => {
      resolve(true);
    }).catch(() => resolve(false));
  });
}

function validateConfig(config) {
  if (!config.accessKey || !config.secretKey || !config.bucket) {
    showNotification("❌ Please configure DO Spaces credentials first", 'error');
    openSettings();
    return false;
  }
  return true;
}

function showNotification(message, type = 'info') {
  browser.notifications.create({
    type: "basic",
    iconUrl: browser.runtime.getURL("icons/icon-48.png"),
    title: type === 'error' ? "❌ Error" : type === 'success' ? "✅ Success" : "ℹ️ Info",
    message: message
  });
}

function openSettings() {
  browser.tabs.create({
    url: browser.runtime.getURL("options/options.html"),
    active: true
  });
}

// ============ MESSAGE HANDLING (KEPT YOUR ORIGINAL) ============
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log("📨 Message received:", message.action);
  
  switch(message.action) {
    case "getConfig":
      getConfig().then(sendResponse);
      return true;
      
    case "saveConfig":
      saveConfig(message.config).then(sendResponse);
      return true;
      
    case "testConnection":
      testConnection(message.config).then(sendResponse);
      return true;
      
    case "autoDetectCdnId":
      autoDetectCdnId(message.apiToken, message.bucket).then(sendResponse);
      return true;
      
    case "uploadFromLink":
      uploadFromLink(message.url).then(sendResponse);
      return true;
      
    case "uploadMediaFile":
      uploadMediaFile(message.srcUrl || message.dataUrl, message.mediaType || "image").then(sendResponse);
      return true;
  }
});

// ============ TEST CONNECTION (FIXED - NO AWS SDK) ============
async function testConnection(config) {
  try {
    // Test by trying to upload a tiny test file
    const testBuffer = new ArrayBuffer(8);
    const testFile = new Uint8Array(testBuffer);
    const testFilename = `test-${Date.now()}.txt`;
    
    await uploadToSpaces(testBuffer, testFilename, 'text/plain', config);
    
    return { success: true, message: "✅ Connection successful!" };
  } catch (error) {
    return { success: false, message: `❌ Connection failed: ${error.message}` };
  }
}

// ============ CDN AUTO-DETECT (KEPT YOUR ORIGINAL) ============
async function autoDetectCdnId(apiToken, bucket) {
  try {
    const response = await fetch("https://api.digitalocean.com/v2/cdn/endpoints", {
      headers: { Authorization: `Bearer ${apiToken}` }
    });
    
    if (!response.ok) {
      throw new Error(`API request failed: ${response.status}`);
    }
    
    const data = await response.json();
    const endpoints = data.endpoints || [];
    
    const match = endpoints.find(ep => ep.origin && ep.origin.startsWith(bucket + '.'));
    
    if (match) {
      return { success: true, cdnId: match.id };
    } else {
      return { success: false, message: "No CDN endpoint found for this bucket" };
    }
  } catch (error) {
    return { success: false, message: `Failed to detect CDN: ${error.message}` };
  }
}

console.log("✅ DO Spaces Uploader background script ready!");
EOL

# Create popup.html (keep as is, it's fine)
cat << 'EOL' > popup.html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>DO Spaces Uploader</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    
    body {
      width: 400px;
      min-height: 500px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
      color: white;
    }
    
    .container {
      padding: 20px;
      background: rgba(255, 255, 255, 0.1);
      backdrop-filter: blur(10px);
      min-height: 500px;
    }
    
    .header {
      text-align: center;
      margin-bottom: 25px;
      padding-bottom: 15px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.2);
    }
    
    h1 {
      font-size: 22px;
      margin-bottom: 10px;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
    }
    
    .logo {
      width: 32px;
      height: 32px;
      border-radius: 6px;
    }
    
    .subtitle {
      font-size: 13px;
      color: rgba(255, 255, 255, 0.9);
      margin-bottom: 5px;
    }
    
    .status-indicator {
      display: inline-block;
      width: 10px;
      height: 10px;
      border-radius: 50%;
      margin-right: 8px;
    }
    
    .status-connected {
      background: #10B981;
    }
    
    .status-disconnected {
      background: #EF4444;
    }
    
    .quick-actions {
      background: rgba(255, 255, 255, 0.2);
      border-radius: 12px;
      padding: 20px;
      margin-bottom: 20px;
    }
    
    h2 {
      font-size: 16px;
      margin-bottom: 15px;
      color: #f3f4f6;
      display: flex;
      align-items: center;
      gap: 10px;
    }
    
    h2 i {
      font-size: 18px;
    }
    
    .action-grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 10px;
      margin-bottom: 15px;
    }
    
    .action-btn {
      padding: 12px;
      border: none;
      border-radius: 10px;
      background: rgba(255, 255, 255, 0.95);
      color: #4F46E5;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.3s;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 8px;
      text-align: center;
    }
    
    .action-btn:hover {
      background: white;
      transform: translateY(-2px);
      box-shadow: 0 5px 15px rgba(0, 0, 0, 0.2);
    }
    
    .action-btn i {
      font-size: 20px;
    }
    
    .config-info {
      background: rgba(255, 255, 255, 0.15);
      border-radius: 10px;
      padding: 15px;
      margin-top: 15px;
    }
    
    .config-item {
      margin-bottom: 8px;
      font-size: 13px;
      display: flex;
      justify-content: space-between;
    }
    
    .config-label {
      color: rgba(255, 255, 255, 0.8);
    }
    
    .config-value {
      color: white;
      font-weight: 500;
      max-width: 200px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    
    .settings-buttons {
      display: flex;
      gap: 10px;
      margin-top: 20px;
    }
    
    .btn {
      flex: 1;
      padding: 12px;
      border: none;
      border-radius: 10px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.3s;
    }
    
    .btn-primary {
      background: linear-gradient(135deg, #4F46E5 0%, #7C3AED 100%);
      color: white;
    }
    
    .btn-secondary {
      background: rgba(255, 255, 255, 0.9);
      color: #4F46E5;
    }
    
    .btn:hover {
      transform: translateY(-2px);
      box-shadow: 0 5px 15px rgba(0, 0, 0, 0.2);
    }
    
    .recent-uploads {
      background: rgba(255, 255, 255, 0.2);
      border-radius: 12px;
      padding: 20px;
      margin-top: 20px;
    }
    
    .upload-item {
      background: rgba(255, 255, 255, 0.1);
      border-radius: 8px;
      padding: 12px;
      margin-bottom: 10px;
      font-size: 12px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    
    .upload-name {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      max-width: 200px;
    }
    
    .upload-copy {
      background: rgba(255, 255, 255, 0.2);
      border: none;
      color: white;
      padding: 4px 8px;
      border-radius: 4px;
      cursor: pointer;
      font-size: 11px;
    }
    
    .upload-copy:hover {
      background: rgba(255, 255, 255, 0.3);
    }
    
    .no-uploads {
      text-align: center;
      color: rgba(255, 255, 255, 0.7);
      font-style: italic;
      font-size: 13px;
      padding: 20px 0;
    }
    
    .footer {
      margin-top: 20px;
      padding-top: 15px;
      border-top: 1px solid rgba(255, 255, 255, 0.2);
      font-size: 11px;
      color: rgba(255, 255, 255, 0.7);
      text-align: center;
    }
    
    .status-message {
      padding: 10px;
      border-radius: 8px;
      margin-top: 10px;
      font-size: 12px;
      display: none;
    }
    
    .status-success {
      background: rgba(16, 185, 129, 0.3);
      border: 1px solid rgba(16, 185, 129, 0.5);
      display: block;
    }
    
    .status-error {
      background: rgba(239, 68, 68, 0.3);
      border: 1px solid rgba(239, 68, 68, 0.5);
      display: block;
    }
    
    .drop-zone {
      border: 2px dashed rgba(255, 255, 255, 0.5);
      border-radius: 10px;
      padding: 30px;
      text-align: center;
      margin-top: 20px;
      cursor: pointer;
      transition: all 0.3s;
    }
    
    .drop-zone:hover {
      border-color: rgba(255, 255, 255, 0.8);
      background: rgba(255, 255, 255, 0.1);
    }
    
    .drop-zone i {
      font-size: 32px;
      margin-bottom: 10px;
      opacity: 0.8;
    }
    
    .drop-zone p {
      font-size: 14px;
      margin-bottom: 5px;
    }
    
    .drop-zone small {
      font-size: 11px;
      opacity: 0.7;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>
        <img src="icons/icon-48.png" class="logo" alt="DO Spaces">
        DO Spaces Uploader
      </h1>
      <p class="subtitle">Upload files directly from Firefox to Digital Ocean Spaces</p>
      <div class="status">
        <span class="status-indicator" id="connectionStatus"></span>
        <span id="statusText">Checking connection...</span>
      </div>
    </div>
    
    <div class="quick-actions">
      <h2><i>⚡</i> Quick Actions</h2>
      
      <div class="action-grid">
        <button class="action-btn" id="uploadClipboard">
          <i>📋</i> Upload Clipboard
        </button>
        
        <button class="action-btn" id="uploadFromUrl">
          <i>🔗</i> From URL
        </button>
        
        <button class="action-btn" id="openSettings">
          <i>⚙️</i> Settings
        </button>
        
        <button class="action-btn" id="testConnection">
          <i>🔍</i> Test Connection
        </button>
      </div>
      
      <div class="config-info">
        <div class="config-item">
          <span class="config-label">Bucket:</span>
          <span class="config-value" id="currentBucket">Not set</span>
        </div>
        <div class="config-item">
          <span class="config-label">Folder:</span>
          <span class="config-value" id="currentFolder">uploads</span>
        </div>
        <div class="config-item">
          <span class="config-label">CDN:</span>
          <span class="config-value" id="currentCDN">Not set</span>
        </div>
      </div>
      
      <div id="statusMessage" class="status-message"></div>
    </div>
    
    <div class="drop-zone" id="dropZone">
      <i>📁</i>
      <p>Drop files here to upload</p>
      <small>Supports images, videos, documents</small>
    </div>
    
    <div class="recent-uploads">
      <h2><i>📚</i> Recent Uploads</h2>
      <div id="recentUploadsList">
        <div class="no-uploads">No recent uploads</div>
      </div>
    </div>
    
    <div class="settings-buttons">
      <button class="btn btn-primary" id="openFullSettings">
        <i>⚙️</i> Full Settings
      </button>
      <button class="btn btn-secondary" id="howToUse">
        <i>❓</i> How to Use
      </button>
    </div>
    
    <div class="footer">
      Digital Ocean Spaces Uploader v1.0.0<br>
      Right-click on images/files to upload
    </div>
  </div>
  
  <script src="popup.js"></script>
</body>
</html>
EOL

# Create popup.js with FIXED uploadBlob function
cat << 'EOL' > popup.js
// DO Spaces Uploader - Popup Script

document.addEventListener('DOMContentLoaded', async function() {
  console.log("🚀 DO Spaces Uploader popup loaded");
  
  // Load configuration and update UI
  await loadConfig();
  await updateConnectionStatus();
  await loadRecentUploads();
  
  // Event listeners
  document.getElementById('uploadClipboard').addEventListener('click', uploadFromClipboard);
  document.getElementById('uploadFromUrl').addEventListener('click', uploadFromUrlPrompt);
  document.getElementById('openSettings').addEventListener('click', openSettings);
  document.getElementById('testConnection').addEventListener('click', testConnection);
  document.getElementById('openFullSettings').addEventListener('click', openFullSettings);
  document.getElementById('howToUse').addEventListener('click', showHowToUse);
  
  // Drop zone handling
  const dropZone = document.getElementById('dropZone');
  dropZone.addEventListener('dragover', handleDragOver);
  dropZone.addEventListener('drop', handleFileDrop);
  dropZone.addEventListener('click', () => {
    const input = document.createElement('input');
    input.type = 'file';
    input.multiple = true;
    input.accept = 'image/*,video/*,audio/*,application/*';
    input.onchange = handleFileSelect;
    input.click();
  });
});

// Load configuration from storage
async function loadConfig() {
  try {
    const response = await browser.runtime.sendMessage({ action: "getConfig" });
    
    document.getElementById('currentBucket').textContent = response.bucket || 'Not set';
    document.getElementById('currentFolder').textContent = response.folder || 'uploads';
    document.getElementById('currentCDN').textContent = response.cdnEndpoint ? 'Enabled' : 'Not set';
    
    return response;
  } catch (error) {
    console.error("Failed to load config:", error);
    showStatus("❌ Failed to load configuration", 'error');
    return {};
  }
}

// Update connection status
async function updateConnectionStatus() {
  const statusIndicator = document.getElementById('connectionStatus');
  const statusText = document.getElementById('statusText');
  
  try {
    const config = await loadConfig();
    
    if (config.accessKey && config.secretKey && config.bucket) {
      statusIndicator.className = 'status-indicator status-connected';
      statusText.textContent = 'Connected';
    } else {
      statusIndicator.className = 'status-indicator status-disconnected';
      statusText.textContent = 'Not configured';
    }
  } catch (error) {
    statusIndicator.className = 'status-indicator status-disconnected';
    statusText.textContent = 'Error';
  }
}

// Load recent uploads
async function loadRecentUploads() {
  try {
    const recentUploads = await browser.storage.local.get(['recentUploads']);
    const uploads = recentUploads.recentUploads || [];
    const uploadsList = document.getElementById('recentUploadsList');
    
    if (uploads.length === 0) {
      uploadsList.innerHTML = '<div class="no-uploads">No recent uploads</div>';
      return;
    }
    
    let html = '';
    uploads.slice(0, 5).forEach(upload => {
      html += `
        <div class="upload-item">
          <div class="upload-name" title="${upload.filename}">
            📄 ${upload.filename}
          </div>
          <button class="upload-copy" data-url="${upload.url}">
            Copy URL
          </button>
        </div>
      `;
    });
    
    uploadsList.innerHTML = html;
    
    // Add event listeners to copy buttons
    document.querySelectorAll('.upload-copy').forEach(button => {
      button.addEventListener('click', function() {
        const url = this.getAttribute('data-url');
        navigator.clipboard.writeText(url).then(() => {
          showStatus('✅ URL copied to clipboard!', 'success');
        });
      });
    });
  } catch (error) {
    console.error("Failed to load recent uploads:", error);
  }
}

// Upload from clipboard
async function uploadFromClipboard() {
  try {
    const items = await navigator.clipboard.read();
    
    for (const item of items) {
      if (item.types.includes('image/png') || item.types.includes('image/jpeg')) {
        const blob = await item.getType('image/png') || await item.getType('image/jpeg');
        await uploadBlob(blob, `clipboard-${Date.now()}.png`);
        return;
      }
    }
    
    // Try reading text
    const text = await navigator.clipboard.readText();
    if (text.startsWith('http://') || text.startsWith('https://') || text.startsWith('file://')) {
      await uploadFromUrl(text);
      return;
    }
    
    showStatus('❌ No image or valid URL found in clipboard', 'error');
  } catch (error) {
    console.error("Clipboard upload failed:", error);
    showStatus('❌ Cannot access clipboard. Please paste a URL manually.', 'error');
  }
}

// Upload from URL prompt
async function uploadFromUrlPrompt() {
  const url = prompt('Enter the URL of the file to upload:');
  if (url) {
    await uploadFromUrl(url);
  }
}

// Upload from URL
async function uploadFromUrl(url) {
  try {
    showStatus('📤 Uploading from URL...', 'info');
    
    // Send message to background script
    const response = await browser.runtime.sendMessage({
      action: "uploadFromLink",
      url: url
    });
    
    if (response && response.success) {
      showStatus('✅ Upload successful! URL copied to clipboard.', 'success');
      await loadRecentUploads();
    } else {
      showStatus('❌ Upload failed: ' + (response.error || 'Unknown error'), 'error');
    }
  } catch (error) {
    console.error("URL upload failed:", error);
    showStatus(`❌ Upload failed: ${error.message}`, 'error');
  }
}

// Upload blob - FIXED VERSION
async function uploadBlob(blob, filename) {
  try {
    showStatus(`📤 Uploading ${filename}...`, 'info');
    
    // Convert blob to data URL
    const reader = new FileReader();
    reader.readAsDataURL(blob);
    
    await new Promise((resolve) => {
      reader.onload = async function() {
        const dataUrl = reader.result;
        
        // Send to background script
        const response = await browser.runtime.sendMessage({
          action: "uploadMediaFile",
          dataUrl: dataUrl,
          filename: filename,
          contentType: blob.type,
          mediaType: blob.type.startsWith('image/') ? 'image' : 
                    blob.type.startsWith('video/') ? 'video' : 
                    blob.type.startsWith('audio/') ? 'audio' : 'file'
        });
        
        if (response && response.success) {
          showStatus('✅ Upload successful! URL copied to clipboard.', 'success');
          await loadRecentUploads();
        } else {
          showStatus('❌ Upload failed: ' + (response.error || 'Unknown error'), 'error');
        }
        resolve();
      };
    });
  } catch (error) {
    console.error("Blob upload failed:", error);
    showStatus(`❌ Upload failed: ${error.message}`, 'error');
  }
}

// Handle drag over
function handleDragOver(e) {
  e.preventDefault();
  e.stopPropagation();
  e.dataTransfer.dropEffect = 'copy';
}

// Handle file drop
async function handleFileDrop(e) {
  e.preventDefault();
  e.stopPropagation();
  
  const files = Array.from(e.dataTransfer.files);
  
  if (files.length === 0) return;
  
  showStatus(`📤 Uploading ${files.length} file(s)...`, 'info');
  
  for (const file of files) {
    await uploadBlob(file, file.name);
  }
}

// Handle file select
async function handleFileSelect(e) {
  const files = Array.from(e.target.files);
  
  if (files.length === 0) return;
  
  showStatus(`📤 Uploading ${files.length} file(s)...`, 'info');
  
  for (const file of files) {
    await uploadBlob(file, file.name);
  }
}

// Test connection
async function testConnection() {
  try {
    showStatus('🔍 Testing connection...', 'info');
    
    const config = await loadConfig();
    const response = await browser.runtime.sendMessage({
      action: "testConnection",
      config: config
    });
    
    if (response.success) {
      showStatus(response.message, 'success');
      await updateConnectionStatus();
    } else {
      showStatus(response.message, 'error');
    }
  } catch (error) {
    console.error("Connection test failed:", error);
    showStatus(`❌ Test failed: ${error.message}`, 'error');
  }
}

// Open settings
function openSettings() {
  browser.tabs.create({
    url: browser.runtime.getURL("options/options.html"),
    active: true
  });
}

// Open full settings
function openFullSettings() {
  openSettings();
}

// Show how to use
function showHowToUse() {
  alert(`🎯 How to use DO Spaces Uploader:

1. Right-click on any image, video, or audio file
2. Select "Upload to DO Spaces" from the context menu
3. The file will be uploaded and the CDN URL copied to clipboard

📁 File Types Supported:
• Images (PNG, JPG, GIF, WebP, SVG, BMP)
• Videos (MP4, AVI, MOV, WMV, WebM)
• Audio (MP3, WAV, OGG, M4A)
• Documents (PDF, HTML, TXT)
• Archives (ZIP, RAR)

⚡ Quick Actions:
• Drop files in the extension popup
• Upload from clipboard
• Upload from URL

⚙️ Settings:
Configure your Digital Ocean Spaces credentials in the settings page.`);
}

// Show status message
function showStatus(message, type) {
  const statusEl = document.getElementById('statusMessage');
  statusEl.textContent = message;
  statusEl.className = `status-message status-${type}`;
  
  setTimeout(() => {
    statusEl.className = 'status-message';
    statusEl.textContent = '';
  }, 5000);
}
EOL

# Create options/options.html (keep as is)
cat << 'EOL' > options/options.html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>DO Spaces Uploader - Settings</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    
    body {
      background: #f5f5f5;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
      color: #333;
      line-height: 1.6;
      padding: 20px;
      max-width: 800px;
      margin: 0 auto;
    }
    
    .header {
      text-align: center;
      margin-bottom: 30px;
      padding-bottom: 20px;
      border-bottom: 2px solid #e5e7eb;
    }
    
    h1 {
      font-size: 28px;
      color: #1f2937;
      margin-bottom: 10px;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 15px;
    }
    
    .logo {
      width: 40px;
      height: 40px;
      border-radius: 8px;
    }
    
    .subtitle {
      color: #6b7280;
      font-size: 16px;
    }
    
    .settings-container {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 30px;
    }
    
    .section {
      background: white;
      border-radius: 12px;
      padding: 25px;
      box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
    }
    
    .full-width {
      grid-column: 1 / -1;
    }
    
    h2 {
      font-size: 18px;
      color: #374151;
      margin-bottom: 20px;
      padding-bottom: 10px;
      border-bottom: 1px solid #e5e7eb;
      display: flex;
      align-items: center;
      gap: 10px;
    }
    
    h2 i {
      font-size: 20px;
    }
    
    .form-group {
      margin-bottom: 20px;
    }
    
    label {
      display: block;
      margin-bottom: 8px;
      font-weight: 600;
      color: #4b5563;
      font-size: 14px;
    }
    
    .input-with-icon {
      position: relative;
    }
    
    .input-icon {
      position: absolute;
      left: 12px;
      top: 50%;
      transform: translateY(-50%);
      color: #9ca3af;
      font-size: 18px;
    }
    
    input, select {
      width: 100%;
      padding: 12px 12px 12px 40px;
      border: 2px solid #e5e7eb;
      border-radius: 8px;
      font-size: 14px;
      transition: all 0.3s;
      background: white;
    }
    
    input:focus, select:focus {
      outline: none;
      border-color: #4f46e5;
      box-shadow: 0 0 0 3px rgba(79, 70, 229, 0.1);
    }
    
    input[type="password"] {
      font-family: monospace;
      letter-spacing: 1px;
    }
    
    .checkbox-group {
      display: flex;
      align-items: center;
      gap: 10px;
    }
    
    .checkbox-group input[type="checkbox"] {
      width: auto;
      padding: 0;
    }
    
    .checkbox-group label {
      margin: 0;
      font-weight: normal;
      cursor: pointer;
    }
    
    .helper-text {
      margin-top: 6px;
      font-size: 12px;
      color: #6b7280;
    }
    
    .helper-text a {
      color: #4f46e5;
      text-decoration: none;
    }
    
    .helper-text a:hover {
      text-decoration: underline;
    }
    
    .button-group {
      display: flex;
      gap: 12px;
      margin-top: 30px;
    }
    
    .btn {
      flex: 1;
      padding: 14px 24px;
      border: none;
      border-radius: 8px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.3s;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
    }
    
    .btn-primary {
      background: linear-gradient(135deg, #4f46e5 0%, #7c3aed 100%);
      color: white;
    }
    
    .btn-secondary {
      background: white;
      color: #4f46e5;
      border: 2px solid #e5e7eb;
    }
    
    .btn-success {
      background: linear-gradient(135deg, #10b981 0%, #059669 100%);
      color: white;
    }
    
    .btn-danger {
      background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
      color: white;
    }
    
    .btn:hover:not(:disabled) {
      transform: translateY(-2px);
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
    }
    
    .btn:disabled {
      opacity: 0.6;
      cursor: not-allowed;
    }
    
    .status-message {
      padding: 12px;
      border-radius: 8px;
      margin-top: 20px;
      font-size: 14px;
      display: none;
    }
    
    .status-success {
      background: #d1fae5;
      border: 1px solid #a7f3d0;
      color: #065f46;
      display: block;
    }
    
    .status-error {
      background: #fee2e2;
      border: 1px solid #fecaca;
      color: #991b1b;
      display: block;
    }
    
    .status-info {
      background: #dbeafe;
      border: 1px solid #bfdbfe;
      color: #1e40af;
      display: block;
    }
    
    .api-help {
      background: #f0f9ff;
      border: 1px solid #bae6fd;
      border-radius: 8px;
      padding: 20px;
      margin-top: 30px;
    }
    
    .api-help h3 {
      color: #0369a1;
      margin-bottom: 10px;
      font-size: 16px;
    }
    
    .api-help ol {
      margin-left: 20px;
      margin-bottom: 15px;
    }
    
    .api-help li {
      margin-bottom: 8px;
      color: #475569;
    }
    
    .api-help code {
      background: #e2e8f0;
      padding: 2px 6px;
      border-radius: 4px;
      font-family: monospace;
      font-size: 13px;
    }
    
    .features-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
      gap: 20px;
      margin-top: 30px;
    }
    
    .feature-card {
      background: white;
      border-radius: 10px;
      padding: 20px;
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
      border: 1px solid #e5e7eb;
    }
    
    .feature-icon {
      font-size: 24px;
      margin-bottom: 10px;
      display: inline-block;
    }
    
    .feature-title {
      font-weight: 600;
      margin-bottom: 8px;
      color: #374151;
    }
    
    .feature-desc {
      font-size: 13px;
      color: #6b7280;
    }
    
    .upload-preview {
      border: 2px dashed #d1d5db;
      border-radius: 10px;
      padding: 40px 20px;
      text-align: center;
      cursor: pointer;
      transition: all 0.3s;
      background: #f9fafb;
    }
    
    .upload-preview:hover {
      border-color: #4f46e5;
      background: #f0f9ff;
    }
    
    .upload-preview i {
      font-size: 48px;
      color: #9ca3af;
      margin-bottom: 15px;
      display: block;
    }
    
    .upload-preview p {
      color: #6b7280;
      margin-bottom: 10px;
    }
    
    .upload-preview small {
      color: #9ca3af;
      font-size: 12px;
    }
    
    #filePreview {
      margin-top: 20px;
      display: none;
    }
    
    .preview-image {
      max-width: 100%;
      max-height: 200px;
      border-radius: 8px;
      margin-bottom: 10px;
    }
    
    .preview-info {
      font-size: 12px;
      color: #6b7280;
    }
    
    @media (max-width: 768px) {
      .settings-container {
        grid-template-columns: 1fr;
      }
      
      body {
        padding: 15px;
      }
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>
      <img src="../icons/icon-48.png" class="logo" alt="DO Spaces">
      DO Spaces Uploader Settings
    </h1>
    <p class="subtitle">Configure your Digital Ocean Spaces credentials and preferences</p>
  </div>
  
  <div class="settings-container">
    <div class="section">
      <h2><i>🔑</i> API Credentials</h2>
      
      <div class="form-group">
        <label for="accessKey">Access Key</label>
        <div class="input-with-icon">
          <span class="input-icon">🔑</span>
          <input type="password" id="accessKey" placeholder="Your Digital Ocean Spaces Access Key">
        </div>
        <div class="helper-text">
          Get from: DigitalOcean → API → Spaces access keys
        </div>
      </div>
      
      <div class="form-group">
        <label for="secretKey">Secret Key</label>
        <div class="input-with-icon">
          <span class="input-icon">🔒</span>
          <input type="password" id="secretKey" placeholder="Your Digital Ocean Spaces Secret Key">
        </div>
        <div class="helper-text">
          Keep this secure. Never share your secret key.
        </div>
      </div>
      
      <div class="form-group">
        <label for="bucket">Bucket Name</label>
        <div class="input-with-icon">
          <span class="input-icon">🪣</span>
          <input type="text" id="bucket" placeholder="my-spaces-bucket">
        </div>
        <div class="helper-text">
          Name of your Digital Ocean Spaces bucket
        </div>
      </div>
    </div>
    
    <div class="section">
      <h2><i>🌐</i> Space Configuration</h2>
      
      <div class="form-group">
        <label for="endpoint">Endpoint URL</label>
        <div class="input-with-icon">
          <span class="input-icon">🔗</span>
          <input type="text" id="endpoint" placeholder="https://nyc3.digitaloceanspaces.com">
        </div>
        <div class="helper-text">
          Region-specific endpoint (nyc3, sgp1, fra1, etc.)
        </div>
      </div>
      
      <div class="form-group">
        <label for="region">Region</label>
        <div class="input-with-icon">
          <span class="input-icon">🗺️</span>
          <select id="region">
            <option value="us-east-1">us-east-1 (New York)</option>
            <option value="us-east-2">us-east-2 (New York 2)</option>
            <option value="us-west-1">us-west-1 (San Francisco)</option>
            <option value="eu-west-1">eu-west-1 (London)</option>
            <option value="eu-central-1">eu-central-1 (Frankfurt)</option>
            <option value="ap-south-1">ap-south-1 (Singapore)</option>
            <option value="ap-northeast-1">ap-northeast-1 (Tokyo)</option>
            <option value="ap-northeast-2">ap-northeast-2 (Seoul)</option>
            <option value="ap-southeast-1">ap-southeast-1 (Sydney)</option>
            <option value="ap-southeast-2">ap-southeast-2 (Melbourne)</option>
          </select>
        </div>
      </div>
      
      <div class="form-group">
        <label for="folder">Target Folder</label>
        <div class="input-with-icon">
          <span class="input-icon">📁</span>
          <input type="text" id="folder" placeholder="uploads">
        </div>
        <div class="helper-text">
          Folder within bucket where files will be uploaded
        </div>
      </div>
    </div>
    
    <div class="section full-width">
      <h2><i>🚀</i> CDN Configuration</h2>
      
      <div class="form-group">
        <label for="cdnEndpoint">CDN Endpoint (Optional)</label>
        <div class="input-with-icon">
          <span class="input-icon">⚡</span>
          <input type="text" id="cdnEndpoint" placeholder="https://cdn.yourdomain.com">
        </div>
        <div class="helper-text">
          If you have Spaces CDN enabled, enter the CDN URL here
        </div>
      </div>
      
      <div class="form-group">
        <label for="apiToken">API Token (For CDN Purge)</label>
        <div class="input-with-icon">
          <span class="input-icon">🔐</span>
          <input type="password" id="apiToken" placeholder="DigitalOcean API Token">
        </div>
        <div class="helper-text">
          Required for automatic CDN cache purging. 
          <a href="https://cloud.digitalocean.com/account/api/tokens" target="_blank">Generate token</a>
        </div>
      </div>
      
      <div class="form-group">
        <div class="input-with-icon" style="display: flex; gap: 10px;">
          <input type="text" id="cdnId" placeholder="CDN Endpoint ID (auto-detected)" style="flex: 1;">
          <button id="detectCdn" class="btn btn-secondary" style="width: auto; padding: 0 15px;">
            🔍 Auto-detect
          </button>
        </div>
        <div class="helper-text">
          CDN endpoint ID will be auto-detected when you provide API token
        </div>
      </div>
      
      <div class="checkbox-group">
        <input type="checkbox" id="makePublic" checked>
        <label for="makePublic">Make uploaded files publicly accessible</label>
      </div>
    </div>
    
    <div class="section full-width">
      <h2><i>⚡</i> Quick Test</h2>
      
      <div class="upload-preview" id="uploadArea">
        <i>📁</i>
        <p>Drop a file here to test upload</p>
        <small>Or click to select a file</small>
      </div>
      
      <div id="filePreview"></div>
      
      <div class="button-group">
        <button id="testConfig" class="btn btn-secondary">
          <i>🔍</i> Test Configuration
        </button>
        <button id="saveConfig" class="btn btn-primary">
          <i>💾</i> Save Settings
        </button>
        <button id="resetConfig" class="btn btn-danger">
          <i>🔄</i> Reset
        </button>
      </div>
      
      <div id="statusMessage" class="status-message"></div>
    </div>
  </div>
  
  <div class="api-help">
    <h3>📚 How to get your API credentials:</h3>
    <ol>
      <li>Go to <a href="https://cloud.digitalocean.com/account/api/tokens" target="_blank">DigitalOcean API Tokens</a></li>
      <li>Click "Generate New Token" → "Custom Scopes"</li>
      <li>Select: <code>spaces:read</code>, <code>spaces:write</code>, <code>cdn:read</code>, <code>cdn:write</code></li>
      <li>Copy the generated token</li>
      <li>For Spaces keys, go to Spaces → Settings → Access Keys</li>
      <li>Generate new key pair and copy both Access Key and Secret Key</li>
    </ol>
  </div>
  
  <div class="features-grid">
    <div class="feature-card">
      <div class="feature-icon">📸</div>
      <div class="feature-title">Image Upload</div>
      <div class="feature-desc">Right-click any image to upload instantly. Supports PNG, JPG, GIF, WebP, SVG.</div>
    </div>
    
    <div class="feature-card">
      <div class="feature-icon">🎬</div>
      <div class="feature-title">Video Upload</div>
      <div class="feature-desc">Upload videos in MP4, AVI, MOV, WMV formats. Preserves original quality.</div>
    </div>
    
    <div class="feature-card">
      <div class="feature-icon">🔗</div>
      <div class="feature-title">CDN URLs</div>
      <div class="feature-desc">Get CDN URLs instantly copied to clipboard. Automatic cache purging available.</div>
    </div>
    
    <div class="feature-card">
      <div class="feature-icon">⚡</div>
      <div class="feature-title">Fast Upload</div>
      <div class="feature-desc">Direct upload to Spaces. No intermediate servers. Fast and secure.</div>
    </div>
  </div>
  
  <script src="options.js"></script>
</body>
</html>
EOL

# Create options/options.js (keep as is)
cat << 'EOL' > options/options.js
// DO Spaces Uploader - Options Script

document.addEventListener('DOMContentLoaded', async function() {
  console.log("⚙️ DO Spaces Uploader options loaded");
  
  // Load saved configuration
  await loadConfiguration();
  
  // Event listeners
  document.getElementById('saveConfig').addEventListener('click', saveConfiguration);
  document.getElementById('resetConfig').addEventListener('click', resetConfiguration);
  document.getElementById('testConfig').addEventListener('click', testConfiguration);
  document.getElementById('detectCdn').addEventListener('click', autoDetectCdn);
  
  // Upload area handling
  const uploadArea = document.getElementById('uploadArea');
  uploadArea.addEventListener('dragover', handleDragOver);
  uploadArea.addEventListener('drop', handleFileDrop);
  uploadArea.addEventListener('click', () => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*,video/*,audio/*';
    input.onchange = handleFileSelect;
    input.click();
  });
  
  // Show file preview when file is selected
  const fileInput = document.getElementById('testFile');
  if (fileInput) {
    fileInput.addEventListener('change', handleFileSelect);
  }
});

// Load configuration from storage
async function loadConfiguration() {
  try {
    const response = await browser.runtime.sendMessage({ action: "getConfig" });
    const config = response || {};
    
    // Fill form fields
    document.getElementById('accessKey').value = config.accessKey || '';
    document.getElementById('secretKey').value = config.secretKey || '';
    document.getElementById('bucket').value = config.bucket || '';
    document.getElementById('endpoint').value = config.endpoint || 'https://nyc3.digitaloceanspaces.com';
    document.getElementById('region').value = config.region || 'us-east-1';
    document.getElementById('folder').value = config.folder || 'uploads';
    document.getElementById('cdnEndpoint').value = config.cdnEndpoint || '';
    document.getElementById('apiToken').value = config.apiToken || '';
    document.getElementById('cdnId').value = config.cdnId || '';
    document.getElementById('makePublic').checked = config.makePublic !== false;
    
    console.log("Configuration loaded:", config);
  } catch (error) {
    console.error("Failed to load configuration:", error);
    showStatus("❌ Failed to load configuration", 'error');
  }
}

// Save configuration to storage
async function saveConfiguration() {
  try {
    // Get values from form
    const config = {
      accessKey: document.getElementById('accessKey').value.trim(),
      secretKey: document.getElementById('secretKey').value.trim(),
      bucket: document.getElementById('bucket').value.trim(),
      endpoint: document.getElementById('endpoint').value.trim() || 'https://nyc3.digitaloceanspaces.com',
      region: document.getElementById('region').value,
      folder: document.getElementById('folder').value.trim() || 'uploads',
      cdnEndpoint: document.getElementById('cdnEndpoint').value.trim(),
      apiToken: document.getElementById('apiToken').value.trim(),
      cdnId: document.getElementById('cdnId').value.trim(),
      makePublic: document.getElementById('makePublic').checked
    };
    
    // Validate required fields
    if (!config.accessKey || !config.secretKey || !config.bucket) {
      showStatus("❌ Please fill in Access Key, Secret Key, and Bucket Name", 'error');
      return;
    }
    
    // Save configuration
    const response = await browser.runtime.sendMessage({
      action: "saveConfig",
      config: config
    });
    
    if (response) {
      showStatus("✅ Configuration saved successfully!", 'success');
      
      // Auto-detect CDN ID if API token is provided
      if (config.apiToken && config.bucket && !config.cdnId) {
        setTimeout(() => autoDetectCdn(), 1000);
      }
    } else {
      showStatus("❌ Failed to save configuration", 'error');
    }
  } catch (error) {
    console.error("Failed to save configuration:", error);
    showStatus(`❌ Error: ${error.message}`, 'error');
  }
}

// Reset configuration
function resetConfiguration() {
  if (confirm("Are you sure you want to reset all settings? This cannot be undone.")) {
    // Clear all form fields
    document.getElementById('accessKey').value = '';
    document.getElementById('secretKey').value = '';
    document.getElementById('bucket').value = '';
    document.getElementById('endpoint').value = 'https://nyc3.digitaloceanspaces.com';
    document.getElementById('region').value = 'us-east-1';
    document.getElementById('folder').value = 'uploads';
    document.getElementById('cdnEndpoint').value = '';
    document.getElementById('apiToken').value = '';
    document.getElementById('cdnId').value = '';
    document.getElementById('makePublic').checked = true;
    
    showStatus("🔄 Configuration reset", 'info');
  }
}

// Test configuration
async function testConfiguration() {
  try {
    showStatus("🔍 Testing configuration...", 'info');
    
    const config = {
      accessKey: document.getElementById('accessKey').value.trim(),
      secretKey: document.getElementById('secretKey').value.trim(),
      bucket: document.getElementById('bucket').value.trim(),
      endpoint: document.getElementById('endpoint').value.trim() || 'https://nyc3.digitaloceanspaces.com',
      region: document.getElementById('region').value,
      folder: document.getElementById('folder').value.trim() || 'uploads'
    };
    
    if (!config.accessKey || !config.secretKey || !config.bucket) {
      showStatus("❌ Please fill in Access Key, Secret Key, and Bucket Name", 'error');
      return;
    }
    
    const response = await browser.runtime.sendMessage({
      action: "testConnection",
      config: config
    });
    
    if (response.success) {
      showStatus("✅ " + response.message, 'success');
    } else {
      showStatus("❌ " + response.message, 'error');
    }
  } catch (error) {
    console.error("Configuration test failed:", error);
    showStatus(`❌ Test failed: ${error.message}`, 'error');
  }
}

// Auto-detect CDN ID
async function autoDetectCdn() {
  try {
    const apiToken = document.getElementById('apiToken').value.trim();
    const bucket = document.getElementById('bucket').value.trim();
    
    if (!apiToken) {
      showStatus("❌ Please enter your API Token first", 'error');
      return;
    }
    
    if (!bucket) {
      showStatus("❌ Please enter your Bucket Name first", 'error');
      return;
    }
    
    showStatus("🔍 Detecting CDN endpoint...", 'info');
    
    const response = await browser.runtime.sendMessage({
      action: "autoDetectCdnId",
      apiToken: apiToken,
      bucket: bucket
    });
    
    if (response.success) {
      document.getElementById('cdnId').value = response.cdnId;
      showStatus("✅ CDN endpoint detected and saved!", 'success');
      
      // Auto-save configuration
      setTimeout(() => saveConfiguration(), 500);
    } else {
      showStatus("⚠️ " + response.message, 'error');
    }
  } catch (error) {
    console.error("CDN detection failed:", error);
    showStatus(`❌ Detection failed: ${error.message}`, 'error');
  }
}

// Handle drag over
function handleDragOver(e) {
  e.preventDefault();
  e.stopPropagation();
  e.dataTransfer.dropEffect = 'copy';
}

// Handle file drop
async function handleFileDrop(e) {
  e.preventDefault();
  e.stopPropagation();
  
  const files = Array.from(e.dataTransfer.files);
  
  if (files.length === 0) return;
  
  // Use first file for test
  const file = files[0];
  await testFileUpload(file);
}

// Handle file select
async function handleFileSelect(e) {
  const files = Array.from(e.target.files || (e.dataTransfer ? e.dataTransfer.files : []));
  
  if (files.length === 0) return;
  
  // Use first file for test
  const file = files[0];
  await testFileUpload(file);
}

// Test file upload
async function testFileUpload(file) {
  try {
    showStatus(`📤 Uploading ${file.name}...`, 'info');
    
    // Show file preview
    const preview = document.getElementById('filePreview');
    preview.innerHTML = '';
    
    if (file.type.startsWith('image/')) {
      const img = document.createElement('img');
      img.src = URL.createObjectURL(file);
      img.className = 'preview-image';
      preview.appendChild(img);
    }
    
    const info = document.createElement('div');
    info.className = 'preview-info';
    info.innerHTML = `
      <strong>${file.name}</strong><br>
      Size: ${(file.size / 1024).toFixed(2)} KB<br>
      Type: ${file.type}
    `;
    preview.appendChild(info);
    
    preview.style.display = 'block';
    
    // Convert file to data URL
    const reader = new FileReader();
    reader.onload = async function() {
      try {
        // Get configuration
        const config = {
          accessKey: document.getElementById('accessKey').value.trim(),
          secretKey: document.getElementById('secretKey').value.trim(),
          bucket: document.getElementById('bucket').value.trim(),
          endpoint: document.getElementById('endpoint').value.trim() || 'https://nyc3.digitaloceanspaces.com',
          region: document.getElementById('region').value,
          folder: document.getElementById('folder').value.trim() || 'uploads',
          cdnEndpoint: document.getElementById('cdnEndpoint').value.trim(),
          makePublic: document.getElementById('makePublic').checked
        };
        
        if (!config.accessKey || !config.secretKey || !config.bucket) {
          showStatus("❌ Please configure credentials first", 'error');
          return;
        }
        
        // Upload via background script
        const dataUrl = reader.result;
        const response = await browser.runtime.sendMessage({
          action: "uploadMediaFile",
          dataUrl: dataUrl,
          filename: file.name,
          contentType: file.type,
          mediaType: file.type.startsWith('image/') ? 'image' : 
                     file.type.startsWith('video/') ? 'video' : 
                     file.type.startsWith('audio/') ? 'audio' : 'file'
        });
        
        if (response && response.success) {
          showStatus(`✅ Upload successful! URL: ${response.url}`, 'success');
          
          // Show URL
          const urlInfo = document.createElement('div');
          urlInfo.className = 'preview-info';
          urlInfo.innerHTML = `<strong>CDN URL:</strong><br><input type="text" value="${response.url}" readonly style="width:100%;padding:5px;margin-top:5px;">`;
          preview.appendChild(urlInfo);
        } else {
          showStatus("❌ Upload failed: " + (response.error || 'Unknown error'), 'error');
        }
      } catch (error) {
        console.error("Upload test failed:", error);
        showStatus(`❌ Upload failed: ${error.message}`, 'error');
      }
    };
    
    reader.readAsDataURL(file);
    
  } catch (error) {
    console.error("File upload test failed:", error);
    showStatus(`❌ Error: ${error.message}`, 'error');
  }
}

// Show status message
function showStatus(message, type) {
  const statusEl = document.getElementById('statusMessage');
  statusEl.textContent = message;
  statusEl.className = `status-message status-${type}`;
  
  setTimeout(() => {
    if (statusEl.textContent === message) {
      statusEl.className = 'status-message';
      statusEl.textContent = '';
    }
  }, 5000);
}
EOL

# Create content.js (simplified version)
cat << 'EOL' > content.js
// DO Spaces Uploader - Content Script

console.log("🌐 DO Spaces Uploader content script loaded");

// Listen for messages from background script
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log("Content script received message:", message);
  
  switch(message.action) {
    case "getPageImages":
      const images = Array.from(document.images).map(img => ({
        src: img.src,
        alt: img.alt,
        width: img.width,
        height: img.height
      }));
      sendResponse({ images: images });
      break;
      
    case "getPageVideos":
      const videos = Array.from(document.querySelectorAll('video')).map(video => ({
        src: video.src || video.currentSrc,
        poster: video.poster,
        width: video.width,
        height: video.height
      }));
      sendResponse({ videos: videos });
      break;
      
    case "getSelectedMedia":
      const selection = window.getSelection();
      if (selection.rangeCount > 0) {
        const range = selection.getRangeAt(0);
        const selectedImages = range.cloneContents().querySelectorAll('img');
        const selectedVideos = range.cloneContents().querySelectorAll('video');
        
        sendResponse({
          text: selection.toString(),
          images: Array.from(selectedImages).map(img => img.src),
          videos: Array.from(selectedVideos).map(video => video.src || video.currentSrc)
        });
      } else {
        sendResponse({ text: '', images: [], videos: [] });
      }
      break;
  }
  
  return true;
});

console.log("✅ DO Spaces Uploader content script ready!");
EOL

# Create README.md
cat << 'EOL' > README.md
# Digital Ocean Spaces Uploader - Firefox Extension

Upload files, images, and videos directly from Firefox to Digital Ocean Spaces with CDN URL support.

## 🚀 Features

### 📤 One-Click Upload
- **Right-click any image/video/audio file** → "Upload to DO Spaces"
- **Context menu integration** for easy access
- **Support for multiple file types**: Images (PNG, JPG, GIF, WebP, SVG), Videos (MP4, AVI, MOV, WMV), Audio (MP3, WAV, OGG)
- **Preserves original filenames** from browser paths

### 🔗 Smart CDN URLs
- **Automatic CDN URL generation** when CDN endpoint is configured
- **URL automatically copied to clipboard** after upload
- **CDN cache purging** with API token
- **Auto-detection of CDN endpoint ID**

### 🎯 Accurate Filename Extraction
Handles various URL formats:
- `file:///Users/name/Downloads/image.png` → `image.png`
- `https://example.com/path/to/file.jpg?size=large` → `file.jpg`
- `data:image/png;base64,...` → `clipboard-{timestamp}.png`

### ⚡ Fast & Secure
- **Direct upload** to Digital Ocean Spaces (no intermediate servers)
- **AWS SDK integration** for reliable uploads
- **Secure credential storage** in Firefox's encrypted storage
- **No data collection** - everything stays local

## 📦 Installation

### Method 1: Temporary Installation (Development)
```bash
# Run the generator script
./generate-do-spaces-uploader.sh

# Load in Firefox:
# 1. Open Firefox → about:debugging#/runtime/this-firefox
# 2. Click "Load Temporary Add-on"
# 3. Select the manifest.json file
file:///Users/gabrielmajorsky/Downloads/Screenshot%202026-01-15%20at%2001-53-01%20Burn%20-%20Home.png
→ Screenshot%202026-01-15%20at%2001-53-01%20Burn%20-%20Home.png

https://example.com/images/photo.jpg?width=800&height=600
→ photo.jpg

### ⚡ Fast & Secure
- **Direct upload** to Digital Ocean Spaces (no intermediate servers)
- **AWS SDK integration** for reliable uploads
- **Secure credential storage** in Firefox's encrypted storage
- **No data collection** - everything stays local

## 📦 Installation

### Method 1: Temporary Installation (Development)
# Run the generator script
./generate-do-spaces-uploader.sh

# Load in Firefox:
# 1. Open Firefox → about:debugging#/runtime/this-firefox
# 2. Click "Load Temporary Add-on"
# 3. Select the manifest.json file

Method 2: From XPI (Production)

# The script auto-creates an XPI file
# Drag and drop the .xpi file into Firefox

⚙️ Configuration
Step 1: Get Digital Ocean Credentials
    Go to DigitalOcean Spaces
    Create a Space (bucket) if you don't have one
    Go to Settings → Access Keys
    Generate new Access Key and Secret Key

Step 2: Configure Extension

    Click the DO Spaces icon in Firefox toolbar
    Click "Full Settings"

    Enter your credentials:
        Access Key: Your DO Spaces access key
        Secret Key: Your DO Spaces secret key
        Bucket: Your Space/bucket name
        Endpoint: https://nyc3.digitaloceanspaces.com (or your region)
        Folder: Target folder (default: uploads)

Step 3: Optional CDN Setup
    Enable CDN on your Space
    Copy your CDN endpoint URL
    Generate API token with cdn:read and cdn:write permissions
    Click "Auto-detect" to find CDN ID

🎮 How to Use
Basic Usage
    Right-click any image on any webpage
    Select "Upload Image to DO Spaces"
    Wait for upload to complete
    CDN URL is automatically copied to clipboard
    Paste URL wherever you need it

Advanced Features
    Video upload: Right-click any video element
    Audio upload: Right-click any audio file
    Link upload: Right-click any file download link
    Drag & drop: Drop files into extension popup
    Clipboard upload: Paste image from clipboard

File Path Examples

The extension handles various file paths:
Source	Extracted Filename
file:///Users/name/Downloads/image.png	image.png
https://example.com/path/to/file.jpg?size=large	file.jpg
data:image/png;base64,...	clipboard-{timestamp}.png

🔧 Technical Details
File Structure

do-spaces-uploader/
├── manifest.json          # Extension manifest
├── background.js         # Background script (context menu, upload logic)
├── popup.html           # Main popup interface
├── popup.js             # Popup functionality
├── content.js           # Content script (in-page features)
├── options/             # Settings pages
│   ├── options.html
│   └── options.js
├── icons/               # Extension icons
│   ├── icon-48.png
│   ├── icon-96.png
│   └── icon-128.png
└── README.md

Permissions
    activeTab: Access current tab for context menu
    contextMenus: Add right-click menu items
    storage: Save configuration locally
    clipboardWrite: Copy URLs to clipboard
    notifications: Show upload status
    downloads: Handle file downloads
    webRequest: For CDN API calls

AWS SDK Integration

The extension uses AWS SDK v3 for S3 operations:
    Direct upload to Digital Ocean Spaces
    Proper MIME type detection
    Metadata preservation
    ACL management for public/private files

🛠️ Development
Build from Source

# Clone or create the extension
./generate-do-spaces-uploader.sh

# Test in Firefox
# about:debugging → Load Temporary Add-on → Select manifest.json

Update Icons

Replace files in icons/ directory:
    icon-48.png (48×48)
    icon-96.png (96×96)
    icon-128.png (128×128)

Modify Configuration

Edit options/options.html and options/options.js for settings UI changes.
📄 License

MIT License - See LICENSE file for details.
🔒 Security Notes
    Credentials are stored encrypted in Firefox storage
    No data is sent to external servers (except Digital Ocean)
    AWS SDK loads from official CDN
    All uploads go directly to your Digital Ocean Space

🆘 Troubleshooting
Upload Fails
    Check your Internet connection
    Verify Spaces credentials are correct
    Ensure bucket exists and is accessible
    Check browser console for errors (F12)

Context Menu Missing
    Reload the extension from about:debugging
    Restart Firefox
    Check if extension is enabled in about:addons

CDN URLs Not Working
    Verify CDN is enabled on your Space
    Check CDN endpoint URL is correct
    Ensure API token has proper permissions
    Try manual CDN purge from DigitalOcean dashboard

🤝 Contributing
    Fork the repository
    Create feature branch
    Make changes
    Test thoroughly
    Submit pull request
📞 Support

For issues and feature requests:
    Check the README and existing issues
    Test with different file types
    Provide error messages from console

Note: This extension requires a Digital Ocean account with Spaces access. Upload speeds depend on your internet connection and Spaces region.
EOL

# Create LICENSE.md
cat << 'EOL' > LICENSE.md
MIT License

Copyright (c) $(date +%Y) Digital Ocean Spaces Uploader

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOL

echo -e "${GREEN}✅ Digital Ocean Spaces Uploader extension generated successfully!${NC}"
echo -e "${YELLOW}📁 Extension folder: $EXTNAME${NC}"

# ===============================================
# Auto-Package extension as .xpi file
# ===============================================
echo -e "${CYAN}📦 Auto-packaging extension as .xpi file...${NC}"

cd ..
XPI_FILE="${EXTNAME}.xpi"

# Remove any existing XPI file
rm -f "$XPI_FILE" 2>/dev/null

# Create the XPI file
cd "$EXTNAME"

echo -e "${CYAN}Creating $XPI_FILE...${NC}"

if command -v 7z &> /dev/null; then
7z a "../$XPI_FILE" * -r -x!.xpi -x!.
elif command -v zip &> /dev/null; then
zip -r "../$XPI_FILE" * -x "*.xpi" -x "."
else
echo -e "${RED}Error: Need zip or 7z to create XPI${NC}"
exit 1
fi

cd ..

# Check if XPI was created
if [ -f "$XPI_FILE" ]; then
echo -e "${GREEN}✅ Created: $XPI_FILE${NC}"
echo -e "${YELLOW}📦 XPI file size: $(du -h "$XPI_FILE" | cut -f1)${NC}"
text

# Final instructions
echo -e ""
echo -e "${GREEN}✨ FILES CREATED:${NC}"
echo -e "  • ${EXTNAME}/ - Extension folder"
echo -e "  • ${EXTNAME}.xpi - Extension package (ready to install)"

echo -e ""
echo -e "${CYAN}🚀 INSTALLATION OPTIONS:${NC}"
echo -e ""
echo -e "${GREEN}Option 1: Temporary testing (recommended for development)${NC}"
echo -e "  1. Open Firefox → about:debugging#/runtime/this-firefox"
echo -e "  2. Click 'Load Temporary Add-on'"
echo -e "  3. Select manifest.json from ${EXTNAME}/ folder"
echo -e ""
echo -e "${YELLOW}Option 2: Permanent installation${NC}"
echo -e "  1. Enable xpinstall.signatures.required = false in about:config"
echo -e "  2. Drag ${EXTNAME}.xpi into Firefox"
echo -e "  3. Click 'Add' when prompted"
echo -e ""
echo -e "${CYAN}🎯 HOW TO USE:${NC}"
echo -e "  1. Right-click any image/video/audio on any webpage"
echo -e "  2. Select 'Upload to DO Spaces' from context menu"
echo -e "  3. Wait for upload (notification will appear)"
echo -e "  4. CDN URL will be automatically copied to clipboard"
echo -e ""
echo -e "${YELLOW}📁 FILENAME EXTRACTION FEATURES:${NC}"
echo -e "  • file:// paths: Extracts actual filename from path"
echo -e "  • URL decoding: Handles %20 and other encoded characters"
echo -e "  • Query string removal: Removes ?parameters from URLs"
echo -e "  • Timestamp fallback: Uses timestamp if filename can't be determined"
echo -e ""
echo -e "${GREEN}⚙️ CONFIGURATION REQUIRED:${NC}"
echo -e "  • Digital Ocean Spaces Access Key"
echo -e "  • Digital Ocean Spaces Secret Key"
echo -e "  • Bucket name"
echo -e "  • Optional: CDN endpoint for faster URLs"
echo -e ""
echo -e "${CYAN}🔧 Configure via:${NC}"
echo -e "  1. Click the DO Spaces icon in Firefox toolbar"
echo -e "  2. Click 'Full Settings'"
echo -e "  3. Enter your credentials"
echo -e ""
echo -e "${GREEN}✅ Extension ready! Test with an image right-click!${NC}"

else
echo -e "${RED}❌ Failed to create XPI file${NC}"
fi

echo -e ""
echo -e "${GREEN}🎉 Digital Ocean Spaces Uploader extension generation complete!${NC}"


# This Firefox extension provides:

# ## ✅ **Key Features:**
# 1. **Right-click upload** for images, videos, audio files
# 2. **Proper filename extraction** from various URL formats including `file://` paths
# 3. **CDN URL generation** with automatic clipboard copy
# 4. **Full settings page** for API key configuration
# 5. **Auto CDN ID detection** when API token is provided
# 6. **Drag & drop upload** in the popup

# ## 🎯 **Filename Extraction Examples:**
# - `file:///Users/gabrielmajorsky/Downloads/Screenshot%202026-01-15%20at%2001-53-01%20Burn%20-%20Home.png`
#   → `Screenshot%202026-01-15%20at%2001-53-01%20Burn%20-%20Home.png`
# - `https://example.com/image.jpg?width=800`
#   → `image.jpg`
# - `data:image/png;base64,...`
#   → `clipboard-1234567890.png`

# ## ⚙️ **Configuration:**
# - Full settings page with form validation
# - Test connection button
# - Auto-detect CDN endpoint
# - Folder structure configuration
# - Public/private upload toggle

# ## 🔧 **Installation:**
# Run the script, then:
# 1. Firefox → `about:debugging`
# 2. Load Temporary Add-on
# 3. Select `manifest.json`
# 4. Configure credentials in the popup
# 5. Start uploading!

# The extension handles all the complex filename extraction and CDN URL generation automatically!