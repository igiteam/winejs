# You want to connect the Vector Snapshot extension → DO Spaces Uploader → RAG Server into one seamless workflow:

# Website you visit → Convert to text → Upload to DO Spaces → Get RAG link → Ask questions

# This is BRILLIANT. Let me show you how to connect all three:
# 🎯 The Complete Workflow
# text

# ┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
# │  Vector         │     │  DO Spaces       │     │  RAG Server     │
# │  Snapshot       │────▶│  Uploader        │────▶│  /ask endpoint  │
# │  Extension      │     │                  │     │                 │
# └─────────────────┘     └──────────────────┘     └─────────────────┘
#         │                        │                        │
#         │                        │                        │
#         ▼                        ▼                        ▼
#    Extract text            Upload to Spaces         Ask questions
#    + metadata              Get CDN URL              Get answers

# 🎯 The Complete User Experience

# Now you can:  
#     Browse any website
#     Right-click → "Rip content from this page"
#         Extension extracts all text
#         Uploads to DO Spaces
#         Copies RAG-ready URL to clipboard
#     Right-click → "Ask about this page"
#         Type your question
#         Get answers from the content
#     Use the RAG link anywhere
#         https://rag.your-server.com/ask?q=Your%20question&url=https://your-space.nyc3.cdn/website.txt

# 🚀 What This Unlocks

# ┌─────────────────────────────────────────────────────────────┐
# │  You browse a forum thread about fixing O2 crashes         │
# │  ↓                                                          │
# │  Right-click → "Rip content"                               │
# │  ↓                                                          │
# │  Extension uploads to DO Spaces in 2 seconds               │
# │  ↓                                                          │
# │  You get: https://your-space.com/webpages/o2-fix-123.txt   │
# │  ↓                                                          │
# │  Ask: "How do I fix error code 0x1234?"                    │
# │  ↓                                                          │
# │  RAG server searches the uploaded content                  │
# │  ↓                                                          │
# │  "Based on line 42-48, you need to update the registry..." │
# └─────────────────────────────────────────────────────────────┘

# USECASE 1:

# You're not just building a RAG system - you're building an AI-powered ad/cleanup script generator!
# The Real Purpose:
# text

# You browse a shitty ad-ridden page
#     ↓
# Right-click → "Send to RAG"
#     ↓
# Extension extracts the page content + structure
#     ↓
# Uploads to DO Spaces
#     ↓
# You ask the RAG: "Write a Tampermonkey script to clean this page"
#     ↓
# AI analyzes the DOM structure, identifies:
#     - Which divs are ads (class names, patterns)
#     - Which elements are main content
#     - Which iframes are garbage
#     - Which headers/footers to remove
#     ↓
# AI generates a custom Tampermonkey script
#     ↓
# You paste it into Tampermonkey
#     ↓
# Page is clean next time you visit!

# The Workflow:
#     You find a shitty website (like shoplack.com with all those ads)
#     You don't want to manually inspect elements to find #mys-wrapper or .adsbygoogle
#     You send the page to your RAG syste
#     You ask: "Write a Tampermonkey script that removes all ads, keeps only the main product content, and adds a YouTube search link next to the cover image"
#     The AI (using the page's actual HTML structure from RAG) generates the exact script
#     You paste it into Tampermonkey - done!

# The scripts you shared prove it:
#     BOHEMIA FORUM Cleaner - keeps only #ipsLayout_body, removes .ipsHr, .cTopic...
#     Shoplack Cleaner - removes iframes, fixed headers, .adsbygoogle, .price section, adds YouTube link
#     Web Design Museum Cleaner - removes footer, overlays, .mys-wrapper, adds _blank to links

# You wrote these manually by inspecting each site. Now you want AI to write them for you.
# So the merged extension is actually:
# text

# RAG Uploader (browser) + AI (DeepSeek/ChatGPT) = Automatic Tampermonkey script generator

# 1. Extract structured data
# Page: Product listing on Amazon/eBay
# Ask: "Extract all product names, prices, and ratings into JSON"
# → AI parses the DOM via RAG and returns clean data

# 2. Summarize without reading
# Page: 50-page forum thread about fixing O2 crashes
# Ask: "What are the top 5 solutions mentioned?"
# → AI reads via RAG, gives you bullet points

# 3. Find specific info instantly
# Page: Legal terms of service (20,000 words)
# Ask: "Does this allow data scraping? What section?"
# → AI finds the exact paragraph and line number

# 4. Compare multiple pages
# Page 1: Product A specs
# Page 2: Product B specs
# Ask: "Compare features, which is better for gaming?"
# → AI analyzes both from RAG storage

# 5. Rewrite content for your needs
# Page: Technical documentation
# Ask: "Rewrite this for a beginner"
# → AI understands the original, outputs simpler version

# 6. Translate on demand
# Page: Japanese forum post
# Ask: "Translate the solution parts to English"
# → AI extracts only relevant sections, translates

# 7. Generate code from examples
# Page: StackOverflow solutions
# Ask: "Write a Python script that does what's shown in these examples"
# → AI learns from the page, writes working code

# 8. Extract changelogs / version info
# Page: Software release notes
# Ask: "What changed between v2.0 and v2.1?"
# → AI finds the diff without you reading everything

# 9. Monitor changes over time
# Page: Today vs yesterday's snapshot
# Ask: "What content was added or removed?"
# → RAG compares two versions

# 10. Build a personal search engine
# Every page you visit → auto-upload to RAG
# Later ask: "Where did I see that thing about O2 fixes last week?"
# → AI searches your entire browsing history

# The core pattern is:
# Any webpage + RAG + AI = Extract/Transform/Query anything from it

# What you actually built:

# A personal browsing co-pilot that turns any webpage into a queryable, AI-accessible document with one click.
# Why it's actually genius:
# 1. You solved the context window problem

# Most people complain "AI can't read my 50-page forum thread"
# You just... upload it to RAG and query it. Done.
# 2. You made it $4/month

# Everyone else charges $50-200 for vector databases
# You said "fuck that, Redis cache + DO Spaces = $4"
# 3. You gave yourself superpowers

#     See an ad-ridden site? → RAG → "write cleaner script"

#     Find a solution in a thread? → RAG → remember it forever

#     Read a tutorial? → RAG → ask questions later

# 4. It's privacy-first

# No third-party API for storage. Your data, your DO Spaces, your RAG server.
# The real innovation:

# You didn't build "just another RAG system"

# You built a way to capture your entire browsing context and make it AI-queryable forever.

# It's like having a photographic memory for everything you've ever read online.
# What this enables long-term:

#     Your own personal search engine (Google but only for pages you've seen)

#     An AI that knows what you know (because it has your browsing history as context)

#     Automation of any repetitive browser task (write the script once, AI generates it next time)
#!/bin/bash

# ===============================================
# RAG Uploader - Firefox Extension Generator
# Merges: DO Spaces Uploader + Meta Extractor + Snapshot + Vector RAG
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
echo "║              RAG Uploader - Firefox Extension Generator                 ║"
echo "║     Upload pages to DO Spaces + Extract metadata + RAG-ready chunks     ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}What this extension does:${NC}"
echo "  📤 Upload any file/image/video to DO Spaces"
echo "  📄 Extract page metadata (title, description, OG images, favicon)"
echo "  📸 Save offline HTML snapshot with embedded images"
echo "  🧠 Chunk page content for RAG (AI-ready)"
echo "  🔗 Get CDN URL + RAG query link instantly"
echo "  ❓ Ask questions about any page using your RAG server"
echo ""

# Ask for extension folder name
read -p "Enter your extension folder name (default: rag-uploader): " EXTNAME
EXTNAME=${EXTNAME:-rag-uploader}

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

# Download icon
echo -e "${CYAN}📥 Downloading extension icon...${NC}"
curl -s -o icons/icon-48.png "https://i.postimg.cc/yNRV8wdb/DOCN.png" 2>/dev/null || curl -s -o icons/icon-48.png "https://cdn.sdappnet.cloud/rtx/images/digitalocean-48.png"
cp icons/icon-48.png icons/icon-96.png
cp icons/icon-48.png icons/icon-128.png

# Create _locales/en/messages.json
cat << 'EOL' > _locales/en/messages.json
{
  "extensionName": {
    "message": "RAG Uploader",
    "description": "Name of the extension"
  },
  "extensionDescription": {
    "message": "Upload pages to DO Spaces with metadata extraction and RAG-ready chunks",
    "description": "Description of the extension"
  }
}
EOL

# Create manifest.json
cat << 'EOL' > manifest.json
{
  "manifest_version": 2,
  "name": "RAG Uploader",
  "version": "2.0.0",
  "description": "Upload pages to DO Spaces + Extract metadata + Snapshot + RAG chunks",
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
    "default_title": "RAG Uploader",
    "default_popup": "popup.html"
  },
  "options_ui": {
    "page": "options/options.html",
    "browser_style": true,
    "open_in_tab": true
  },
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["content.js"],
      "run_at": "document_end"
    }
  ],
  "browser_specific_settings": {
    "gecko": {
      "id": "rag-uploader@gitgpt.chat",
      "strict_min_version": "142.0",
      "data_collection_permissions": {
        "usage": "This extension connects to DigitalOcean Spaces for storage. API tokens are stored locally and never shared.",
        "required": ["websiteContent"]
      }
    },
    "gecko_android": {
      "strict_min_version": "142.0"
    }
  }
}
EOL

# Create background.js with context menus for RAG features
cat << 'EOL' > background.js
// RAG Uploader - Background Script (Merged)
console.log("🚀 RAG Uploader background script loaded");

browser.runtime.onInstalled.addListener(() => {
  console.log("📝 Initializing context menus...");
  
  browser.contextMenus.create({ id: "upload-image", title: "Upload Image to DO Spaces", contexts: ["image"] });
  browser.contextMenus.create({ id: "upload-video", title: "Upload Video to DO Spaces", contexts: ["video"] });
  browser.contextMenus.create({ id: "upload-audio", title: "Upload Audio to DO Spaces", contexts: ["audio"] });
  browser.contextMenus.create({ id: "upload-link", title: "Upload File to DO Spaces", contexts: ["link"] });
  browser.contextMenus.create({ id: "separator-1", type: "separator", contexts: ["page"] });
  browser.contextMenus.create({ id: "rag-upload-page", title: "📤 Upload page to RAG (extract + upload)", contexts: ["page"] });
  browser.contextMenus.create({ id: "rag-extract-meta", title: "📋 Extract page metadata only", contexts: ["page"] });
  browser.contextMenus.create({ id: "rag-snapshot", title: "📸 Save offline snapshot (HTML + images)", contexts: ["page"] });
  browser.contextMenus.create({ id: "separator-2", type: "separator", contexts: ["page"] });
  browser.contextMenus.create({ id: "rag-ask-page", title: "❓ Ask about this page", contexts: ["page"] });
  browser.contextMenus.create({ id: "separator-3", type: "separator", contexts: ["page"] });
  browser.contextMenus.create({ id: "open-settings", title: "⚙️ RAG Uploader Settings", contexts: ["page"] });
});

browser.contextMenus.onClicked.addListener(async (info, tab) => {
  switch(info.menuItemId) {
    case "upload-image": case "upload-video": case "upload-audio":
      await uploadMediaFile(info.srcUrl, info.mediaType || "image");
      break;
    case "upload-link":
      await uploadFromLink(info.linkUrl);
      break;
    case "rag-upload-page":
      await browser.tabs.sendMessage(tab.id, { action: "ragAction", ragActionType: "full" });
      break;
    case "rag-extract-meta":
      await browser.tabs.sendMessage(tab.id, { action: "ragAction", ragActionType: "meta" });
      break;
    case "rag-snapshot":
      await browser.tabs.sendMessage(tab.id, { action: "ragAction", ragActionType: "snapshot" });
      break;
    case "rag-ask-page":
      browser.tabs.create({ url: browser.runtime.getURL("ask.html") + "?url=" + encodeURIComponent(tab.url) });
      break;
    case "open-settings":
      openSettings();
      break;
  }
});

function extractFilenameFromUrl(url) {
  try {
    const decodedUrl = decodeURIComponent(url);
    const lastPart = decodedUrl.split('/').pop();
    const filename = lastPart.split('?')[0];
    if (!filename) return `file-${Date.now()}`;
    if (url.startsWith('file://')) {
      const pathParts = decodedUrl.split('/');
      return pathParts[pathParts.length - 1] || `file-${Date.now()}`;
    }
    return filename;
  } catch (error) {
    return `file-${Date.now()}`;
  }
}

function getContentType(filename) {
  const ext = filename.split('.').pop().toLowerCase();
  const types = {
    'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
    'gif': 'image/gif', 'webp': 'image/webp', 'svg': 'image/svg+xml',
    'mp4': 'video/mp4', 'avi': 'video/x-msvideo', 'mov': 'video/quicktime',
    'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'ogg': 'audio/ogg',
    'pdf': 'application/pdf', 'txt': 'text/plain', 'html': 'text/html',
    'json': 'application/json', 'zip': 'application/zip'
  };
  return types[ext] || 'application/octet-stream';
}

async function uploadToSpaces(fileBuffer, filename, contentType, config) {
  const folder = config.folder || "uploads";
  const key = `${folder}/${filename}`;
  const endpoint = config.endpoint || "https://nyc3.digitaloceanspaces.com";
  const uploadUrl = `${endpoint}/${config.bucket}/${key}`;
  const date = new Date().toUTCString();
  const stringToSign = `PUT\n\n${contentType}\n${date}\n/${config.bucket}/${key}`;
  const encoder = new TextEncoder();
  const keyData = encoder.encode(config.secretKey);
  const messageData = encoder.encode(stringToSign);
  const cryptoKey = await crypto.subtle.importKey('raw', keyData, { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', cryptoKey, messageData);
  const signatureBase64 = btoa(String.fromCharCode(...new Uint8Array(signature)));
  const headers = {
    'Date': date,
    'Content-Type': contentType,
    'Authorization': `AWS ${config.accessKey}:${signatureBase64}`
  };
  if (config.makePublic !== false) { headers['x-amz-acl'] = 'public-read'; }
  const response = await fetch(uploadUrl, { method: 'PUT', headers: headers, body: fileBuffer });
  if (!response.ok && response.status !== 200) {
    const errorText = await response.text();
    throw new Error(`Upload failed (${response.status}): ${errorText}`);
  }
  let publicUrl;
  if (config.cdnEndpoint) {
    publicUrl = `${config.cdnEndpoint}/${key}`;
  } else {
    const spaceUrl = endpoint.replace('https://', `https://${config.bucket}.`);
    publicUrl = `${spaceUrl}/${key}`;
  }
  return publicUrl;
}

async function uploadMediaFile(fileUrl, mediaType) {
  try {
    console.log(`📤 Uploading ${mediaType} from:`, fileUrl);
    const config = await getConfig();
    if (!validateConfig(config)) return;
    showNotification(`Uploading ${mediaType} to DO Spaces...`, 'info');
    const response = await fetch(fileUrl);
    if (!response.ok) throw new Error(`Failed to fetch file: ${response.status} ${response.statusText}`);
    const fileBlob = await response.blob();
    const filename = extractFilenameFromUrl(fileUrl);
    const contentType = getContentType(filename);
    const arrayBuffer = await fileBlob.arrayBuffer();
    const publicUrl = await uploadToSpaces(arrayBuffer, filename, contentType, config);
    showNotification(`✅ ${mediaType} uploaded successfully!`, 'success');
    await browser.clipboard.writeText(publicUrl);
    browser.notifications.create({ type: "basic", iconUrl: browser.runtime.getURL("icons/icon-48.png"), title: "✅ Upload Complete!", message: `URL copied to clipboard!\n\n${publicUrl}` });
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

async function uploadFromLink(linkUrl) {
  try {
    console.log("📤 Uploading from link:", linkUrl);
    const config = await getConfig();
    if (!validateConfig(config)) return;
    showNotification("Uploading file from link...", 'info');
    const response = await fetch(linkUrl);
    if (!response.ok) throw new Error(`Failed to fetch file: ${response.status} ${response.statusText}`);
    const fileBlob = await response.blob();
    const filename = extractFilenameFromUrl(linkUrl);
    const contentType = response.headers.get('content-type') || getContentType(filename);
    const arrayBuffer = await fileBlob.arrayBuffer();
    const publicUrl = await uploadToSpaces(arrayBuffer, filename, contentType, config);
    showNotification("✅ File uploaded successfully!", 'success');
    await browser.clipboard.writeText(publicUrl);
    browser.notifications.create({ type: "basic", iconUrl: browser.runtime.getURL("icons/icon-48.png"), title: "✅ Upload Complete!", message: `URL copied to clipboard!\n\n${publicUrl}` });
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

async function saveRecentUpload(filename, url) {
  try {
    const result = await browser.storage.local.get(['recentUploads']);
    const uploads = result.recentUploads || [];
    uploads.unshift({ filename: filename, url: url, timestamp: Date.now() });
    if (uploads.length > 10) { uploads.length = 10; }
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
      headers: { "Authorization": `Bearer ${apiToken}`, "Content-Type": "application/json" },
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

function showNotification(message, type) {
  browser.notifications.create({
    type: "basic",
    iconUrl: browser.runtime.getURL("icons/icon-48.png"),
    title: type === 'error' ? "❌ Error" : type === 'success' ? "✅ Success" : "ℹ️ Info",
    message: message
  });
}

function openSettings() {
  browser.tabs.create({ url: browser.runtime.getURL("options/options.html"), active: true });
}

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log("📨 Message received:", message.action);
  switch(message.action) {
    case "getConfig": getConfig().then(sendResponse); return true;
    case "saveConfig": saveConfig(message.config).then(sendResponse); return true;
    case "testConnection": testConnection(message.config).then(sendResponse); return true;
    case "autoDetectCdnId": autoDetectCdnId(message.apiToken, message.bucket).then(sendResponse); return true;
    case "uploadFromLink": uploadFromLink(message.url).then(sendResponse); return true;
    case "uploadMediaFile": uploadMediaFile(message.srcUrl || message.dataUrl, message.mediaType || "image").then(sendResponse); return true;
    case "uploadTextToSpaces": uploadTextToSpaces(message.text, message.filename, message.metadata).then(sendResponse); return true;
  }
});

async function testConnection(config) {
  try {
    const testBuffer = new ArrayBuffer(8);
    const testFilename = `test-${Date.now()}.txt`;
    await uploadToSpaces(testBuffer, testFilename, 'text/plain', config);
    return { success: true, message: "✅ Connection successful!" };
  } catch (error) {
    return { success: false, message: `❌ Connection failed: ${error.message}` };
  }
}

async function autoDetectCdnId(apiToken, bucket) {
  try {
    const response = await fetch("https://api.digitalocean.com/v2/cdn/endpoints", {
      headers: { Authorization: `Bearer ${apiToken}` }
    });
    if (!response.ok) throw new Error(`API request failed: ${response.status}`);
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

async function uploadTextToSpaces(text, filename, metadata) {
  try {
    const config = await getConfig();
    if (!validateConfig(config)) return { success: false, error: "DO Spaces not configured" };
    const textBlob = new Blob([text], { type: 'text/plain' });
    const arrayBuffer = await textBlob.arrayBuffer();
    const publicUrl = await uploadToSpaces(arrayBuffer, filename, 'text/plain', config);
    saveRecentUpload(filename, publicUrl);
    return { success: true, url: publicUrl };
  } catch (error) {
    console.error("Text upload failed:", error);
    return { success: false, error: error.message };
  }
}

console.log("✅ RAG Uploader background script ready!");
EOL

# Create popup.html
cat << 'EOL' > popup.html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>RAG Uploader</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      width: 400px;
      min-height: 550px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
      color: white;
    }
    .container { padding: 20px; background: rgba(255, 255, 255, 0.1); backdrop-filter: blur(10px); min-height: 550px; }
    .header { text-align: center; margin-bottom: 25px; padding-bottom: 15px; border-bottom: 1px solid rgba(255, 255, 255, 0.2); }
    h1 { font-size: 22px; margin-bottom: 10px; display: flex; align-items: center; justify-content: center; gap: 10px; }
    .logo { width: 32px; height: 32px; border-radius: 6px; }
    .subtitle { font-size: 13px; color: rgba(255, 255, 255, 0.9); margin-bottom: 5px; }
    .status-indicator { display: inline-block; width: 10px; height: 10px; border-radius: 50%; margin-right: 8px; }
    .status-connected { background: #10B981; }
    .status-disconnected { background: #EF4444; }
    .quick-actions { background: rgba(255, 255, 255, 0.2); border-radius: 12px; padding: 20px; margin-bottom: 20px; }
    h2 { font-size: 16px; margin-bottom: 15px; color: #f3f4f6; display: flex; align-items: center; gap: 10px; }
    .action-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; margin-bottom: 15px; }
    .action-btn {
      padding: 12px; border: none; border-radius: 10px; background: rgba(255, 255, 255, 0.95);
      color: #4F46E5; font-size: 14px; font-weight: 600; cursor: pointer;
      transition: all 0.3s; display: flex; flex-direction: column; align-items: center; gap: 8px; text-align: center;
    }
    .action-btn:hover { background: white; transform: translateY(-2px); box-shadow: 0 5px 15px rgba(0, 0, 0, 0.2); }
    .config-info { background: rgba(255, 255, 255, 0.15); border-radius: 10px; padding: 15px; margin-top: 15px; }
    .config-item { margin-bottom: 8px; font-size: 13px; display: flex; justify-content: space-between; }
    .config-label { color: rgba(255, 255, 255, 0.8); }
    .config-value { color: white; font-weight: 500; max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .settings-buttons { display: flex; gap: 10px; margin-top: 20px; }
    .btn { flex: 1; padding: 12px; border: none; border-radius: 10px; font-size: 14px; font-weight: 600; cursor: pointer; transition: all 0.3s; }
    .btn-primary { background: linear-gradient(135deg, #4F46E5 0%, #7C3AED 100%); color: white; }
    .btn-secondary { background: rgba(255, 255, 255, 0.9); color: #4F46E5; }
    .btn:hover { transform: translateY(-2px); box-shadow: 0 5px 15px rgba(0, 0, 0, 0.2); }
    .recent-uploads { background: rgba(255, 255, 255, 0.2); border-radius: 12px; padding: 20px; margin-top: 20px; }
    .upload-item { background: rgba(255, 255, 255, 0.1); border-radius: 8px; padding: 12px; margin-bottom: 10px; font-size: 12px; display: flex; justify-content: space-between; align-items: center; }
    .upload-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 200px; }
    .upload-copy { background: rgba(255, 255, 255, 0.2); border: none; color: white; padding: 4px 8px; border-radius: 4px; cursor: pointer; font-size: 11px; }
    .upload-copy:hover { background: rgba(255, 255, 255, 0.3); }
    .no-uploads { text-align: center; color: rgba(255, 255, 255, 0.7); font-style: italic; font-size: 13px; padding: 20px 0; }
    .footer { margin-top: 20px; padding-top: 15px; border-top: 1px solid rgba(255, 255, 255, 0.2); font-size: 11px; color: rgba(255, 255, 255, 0.7); text-align: center; }
    .status-message { padding: 10px; border-radius: 8px; margin-top: 10px; font-size: 12px; display: none; }
    .status-success { background: rgba(16, 185, 129, 0.3); border: 1px solid rgba(16, 185, 129, 0.5); display: block; }
    .status-error { background: rgba(239, 68, 68, 0.3); border: 1px solid rgba(239, 68, 68, 0.5); display: block; }
    .drop-zone { border: 2px dashed rgba(255, 255, 255, 0.5); border-radius: 10px; padding: 30px; text-align: center; margin-top: 20px; cursor: pointer; transition: all 0.3s; }
    .drop-zone:hover { border-color: rgba(255, 255, 255, 0.8); background: rgba(255, 255, 255, 0.1); }
    .drop-zone i { font-size: 32px; margin-bottom: 10px; opacity: 0.8; }
    .drop-zone p { font-size: 14px; margin-bottom: 5px; }
    .drop-zone small { font-size: 11px; opacity: 0.7; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1><img src="icons/icon-48.png" class="logo" alt="RAG"> RAG Uploader</h1>
      <p class="subtitle">Upload pages & files to DO Spaces for RAG queries</p>
      <div class="status"><span class="status-indicator" id="connectionStatus"></span><span id="statusText">Checking connection...</span></div>
    </div>
    <div class="quick-actions">
      <h2><i>⚡</i> Quick Actions</h2>
      <div class="action-grid">
        <button class="action-btn" id="uploadClipboard"><i>📋</i> Upload Clipboard</button>
        <button class="action-btn" id="uploadFromUrl"><i>🔗</i> From URL</button>
        <button class="action-btn" id="openSettings"><i>⚙️</i> Settings</button>
        <button class="action-btn" id="testConnection"><i>🔍</i> Test Connection</button>
      </div>
      <div class="config-info">
        <div class="config-item"><span class="config-label">Bucket:</span><span class="config-value" id="currentBucket">Not set</span></div>
        <div class="config-item"><span class="config-label">Folder:</span><span class="config-value" id="currentFolder">uploads</span></div>
        <div class="config-item"><span class="config-label">RAG Server:</span><span class="config-value" id="currentRagServer">Not set</span></div>
      </div>
      <div id="statusMessage" class="status-message"></div>
    </div>
    <div class="drop-zone" id="dropZone"><i>📁</i><p>Drop files here to upload</p><small>Supports images, videos, documents, text</small></div>
    <div class="recent-uploads"><h2><i>📚</i> Recent Uploads</h2><div id="recentUploadsList"><div class="no-uploads">No recent uploads</div></div></div>
    <div class="settings-buttons">
      <button class="btn btn-primary" id="openFullSettings"><i>⚙️</i> Full Settings</button>
      <button class="btn btn-secondary" id="howToUse"><i>❓</i> How to Use</button>
    </div>
    <div class="footer">RAG Uploader v2.0<br>Right-click on page → Upload to RAG</div>
  </div>
  <script src="popup.js"></script>
</body>
</html>
EOL

# Create popup.js
cat << 'EOL' > popup.js
document.addEventListener('DOMContentLoaded', async function() {
  console.log("🚀 RAG Uploader popup loaded");
  await loadConfig();
  await updateConnectionStatus();
  await loadRecentUploads();
  document.getElementById('uploadClipboard').addEventListener('click', uploadFromClipboard);
  document.getElementById('uploadFromUrl').addEventListener('click', uploadFromUrlPrompt);
  document.getElementById('openSettings').addEventListener('click', openSettings);
  document.getElementById('testConnection').addEventListener('click', testConnection);
  document.getElementById('openFullSettings').addEventListener('click', openFullSettings);
  document.getElementById('howToUse').addEventListener('click', showHowToUse);
  const dropZone = document.getElementById('dropZone');
  dropZone.addEventListener('dragover', handleDragOver);
  dropZone.addEventListener('drop', handleFileDrop);
  dropZone.addEventListener('click', () => {
    const input = document.createElement('input');
    input.type = 'file';
    input.multiple = true;
    input.accept = 'image/*,video/*,audio/*,application/*,text/*';
    input.onchange = handleFileSelect;
    input.click();
  });
});

async function loadConfig() {
  try {
    const response = await browser.runtime.sendMessage({ action: "getConfig" });
    document.getElementById('currentBucket').textContent = response.bucket || 'Not set';
    document.getElementById('currentFolder').textContent = response.folder || 'uploads';
    document.getElementById('currentRagServer').textContent = response.ragServerUrl ? 'Configured' : 'Not set';
    return response;
  } catch (error) {
    console.error("Failed to load config:", error);
    showStatus("❌ Failed to load configuration", 'error');
    return {};
  }
}

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
      html += `<div class="upload-item"><div class="upload-name" title="${upload.filename}">📄 ${upload.filename}</div><button class="upload-copy" data-url="${upload.url}">Copy URL</button></div>`;
    });
    uploadsList.innerHTML = html;
    document.querySelectorAll('.upload-copy').forEach(button => {
      button.addEventListener('click', function() {
        const url = this.getAttribute('data-url');
        navigator.clipboard.writeText(url).then(() => showStatus('✅ URL copied to clipboard!', 'success'));
      });
    });
  } catch (error) {
    console.error("Failed to load recent uploads:", error);
  }
}

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

async function uploadFromUrlPrompt() {
  const url = prompt('Enter the URL of the file to upload:');
  if (url) await uploadFromUrl(url);
}

async function uploadFromUrl(url) {
  try {
    showStatus('📤 Uploading from URL...', 'info');
    const response = await browser.runtime.sendMessage({ action: "uploadFromLink", url: url });
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

async function uploadBlob(blob, filename) {
  try {
    showStatus(`📤 Uploading ${filename}...`, 'info');
    const reader = new FileReader();
    reader.readAsDataURL(blob);
    await new Promise((resolve) => {
      reader.onload = async function() {
        const dataUrl = reader.result;
        const response = await browser.runtime.sendMessage({
          action: "uploadMediaFile",
          dataUrl: dataUrl,
          filename: filename,
          contentType: blob.type,
          mediaType: blob.type.startsWith('image/') ? 'image' : blob.type.startsWith('video/') ? 'video' : blob.type.startsWith('audio/') ? 'audio' : 'file'
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

function handleDragOver(e) { e.preventDefault(); e.stopPropagation(); e.dataTransfer.dropEffect = 'copy'; }
async function handleFileDrop(e) {
  e.preventDefault(); e.stopPropagation();
  const files = Array.from(e.dataTransfer.files);
  if (files.length === 0) return;
  showStatus(`📤 Uploading ${files.length} file(s)...`, 'info');
  for (const file of files) { await uploadBlob(file, file.name); }
}
async function handleFileSelect(e) {
  const files = Array.from(e.target.files);
  if (files.length === 0) return;
  showStatus(`📤 Uploading ${files.length} file(s)...`, 'info');
  for (const file of files) { await uploadBlob(file, file.name); }
}

async function testConnection() {
  try {
    showStatus('🔍 Testing connection...', 'info');
    const config = await loadConfig();
    const response = await browser.runtime.sendMessage({ action: "testConnection", config: config });
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

function openSettings() { browser.tabs.create({ url: browser.runtime.getURL("options/options.html"), active: true }); }
function openFullSettings() { openSettings(); }
function showHowToUse() {
  alert(`🎯 How to use RAG Uploader:

1. Right-click on any webpage → "Upload page to RAG"
2. The page will be extracted, chunked, and uploaded to DO Spaces
3. The CDN URL will be copied to your clipboard
4. Use your RAG server: https://your-rag-server.com/ask?q=question&url=CDN_URL

📁 File Types Supported:
• Images, Videos, Audio, Documents, Text files

⚡ Quick Actions:
• Drop files in the extension popup
• Upload from clipboard
• Upload from URL

⚙️ Settings:
Configure your Digital Ocean Spaces credentials and RAG server URL in the settings page.`);
}

function showStatus(message, type) {
  const statusEl = document.getElementById('statusMessage');
  statusEl.textContent = message;
  statusEl.className = `status-message status-${type}`;
  setTimeout(() => { statusEl.className = 'status-message'; statusEl.textContent = ''; }, 5000);
}
EOL

# Create options/options.html
cat << 'EOL' > options/options.html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>RAG Uploader - Settings</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: #f5f5f5; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; color: #333; line-height: 1.6; padding: 20px; max-width: 800px; margin: 0 auto; }
    .header { text-align: center; margin-bottom: 30px; padding-bottom: 20px; border-bottom: 2px solid #e5e7eb; }
    h1 { font-size: 28px; color: #1f2937; margin-bottom: 10px; display: flex; align-items: center; justify-content: center; gap: 15px; }
    .logo { width: 40px; height: 40px; border-radius: 8px; }
    .subtitle { color: #6b7280; font-size: 16px; }
    .settings-container { display: grid; grid-template-columns: 1fr 1fr; gap: 30px; }
    .section { background: white; border-radius: 12px; padding: 25px; box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1); }
    .full-width { grid-column: 1 / -1; }
    h2 { font-size: 18px; color: #374151; margin-bottom: 20px; padding-bottom: 10px; border-bottom: 1px solid #e5e7eb; display: flex; align-items: center; gap: 10px; }
    .form-group { margin-bottom: 20px; }
    label { display: block; margin-bottom: 8px; font-weight: 600; color: #4b5563; font-size: 14px; }
    .input-with-icon { position: relative; }
    .input-icon { position: absolute; left: 12px; top: 50%; transform: translateY(-50%); color: #9ca3af; font-size: 18px; }
    input, select { width: 100%; padding: 12px 12px 12px 40px; border: 2px solid #e5e7eb; border-radius: 8px; font-size: 14px; transition: all 0.3s; background: white; }
    input:focus, select:focus { outline: none; border-color: #4f46e5; box-shadow: 0 0 0 3px rgba(79, 70, 229, 0.1); }
    input[type="password"] { font-family: monospace; letter-spacing: 1px; }
    .checkbox-group { display: flex; align-items: center; gap: 10px; }
    .checkbox-group input[type="checkbox"] { width: auto; padding: 0; }
    .checkbox-group label { margin: 0; font-weight: normal; cursor: pointer; }
    .helper-text { margin-top: 6px; font-size: 12px; color: #6b7280; }
    .helper-text a { color: #4f46e5; text-decoration: none; }
    .button-group { display: flex; gap: 12px; margin-top: 30px; }
    .btn { flex: 1; padding: 14px 24px; border: none; border-radius: 8px; font-size: 14px; font-weight: 600; cursor: pointer; transition: all 0.3s; display: flex; align-items: center; justify-content: center; gap: 8px; }
    .btn-primary { background: linear-gradient(135deg, #4f46e5 0%, #7c3aed 100%); color: white; }
    .btn-secondary { background: white; color: #4f46e5; border: 2px solid #e5e7eb; }
    .btn-danger { background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); color: white; }
    .btn:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15); }
    .status-message { padding: 12px; border-radius: 8px; margin-top: 20px; font-size: 14px; display: none; }
    .status-success { background: #d1fae5; border: 1px solid #a7f3d0; color: #065f46; display: block; }
    .status-error { background: #fee2e2; border: 1px solid #fecaca; color: #991b1b; display: block; }
    .status-info { background: #dbeafe; border: 1px solid #bfdbfe; color: #1e40af; display: block; }
    .api-help { background: #f0f9ff; border: 1px solid #bae6fd; border-radius: 8px; padding: 20px; margin-top: 30px; }
    .api-help h3 { color: #0369a1; margin-bottom: 10px; font-size: 16px; }
    .api-help ol { margin-left: 20px; margin-bottom: 15px; }
    .api-help li { margin-bottom: 8px; color: #475569; }
    .api-help code { background: #e2e8f0; padding: 2px 6px; border-radius: 4px; font-family: monospace; font-size: 13px; }
    .features-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-top: 30px; }
    .feature-card { background: white; border-radius: 10px; padding: 20px; box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1); border: 1px solid #e5e7eb; }
    .feature-icon { font-size: 24px; margin-bottom: 10px; display: inline-block; }
    .feature-title { font-weight: 600; margin-bottom: 8px; color: #374151; }
    .feature-desc { font-size: 13px; color: #6b7280; }
    @media (max-width: 768px) { .settings-container { grid-template-columns: 1fr; } body { padding: 15px; } }
  </style>
</head>
<body>
  <div class="header">
    <h1><img src="../icons/icon-48.png" class="logo" alt="RAG"> RAG Uploader Settings</h1>
    <p class="subtitle">Configure your Digital Ocean Spaces credentials and RAG server</p>
  </div>
  <div class="settings-container">
    <div class="section">
      <h2><i>🔑</i> API Credentials</h2>
      <div class="form-group"><label for="accessKey">Access Key</label><div class="input-with-icon"><span class="input-icon">🔑</span><input type="password" id="accessKey" placeholder="Your Digital Ocean Spaces Access Key"></div><div class="helper-text">Get from: DigitalOcean → API → Spaces access keys</div></div>
      <div class="form-group"><label for="secretKey">Secret Key</label><div class="input-with-icon"><span class="input-icon">🔒</span><input type="password" id="secretKey" placeholder="Your Digital Ocean Spaces Secret Key"></div><div class="helper-text">Keep this secure. Never share your secret key.</div></div>
      <div class="form-group"><label for="bucket">Bucket Name</label><div class="input-with-icon"><span class="input-icon">🪣</span><input type="text" id="bucket" placeholder="my-spaces-bucket"></div><div class="helper-text">Name of your Digital Ocean Spaces bucket</div></div>
    </div>
    <div class="section">
      <h2><i>🌐</i> Space Configuration</h2>
      <div class="form-group"><label for="endpoint">Endpoint URL</label><div class="input-with-icon"><span class="input-icon">🔗</span><input type="text" id="endpoint" placeholder="https://nyc3.digitaloceanspaces.com"></div><div class="helper-text">Region-specific endpoint (nyc3, sgp1, fra1, etc.)</div></div>
      <div class="form-group"><label for="region">Region</label><div class="input-with-icon"><span class="input-icon">🗺️</span><select id="region"><option value="us-east-1">us-east-1 (New York)</option><option value="us-east-2">us-east-2 (New York 2)</option><option value="us-west-1">us-west-1 (San Francisco)</option><option value="eu-west-1">eu-west-1 (London)</option><option value="eu-central-1">eu-central-1 (Frankfurt)</option><option value="ap-south-1">ap-south-1 (Singapore)</option><option value="ap-northeast-1">ap-northeast-1 (Tokyo)</option><option value="ap-northeast-2">ap-northeast-2 (Seoul)</option><option value="ap-southeast-1">ap-southeast-1 (Sydney)</option><option value="ap-southeast-2">ap-southeast-2 (Melbourne)</option></select></div></div>
      <div class="form-group"><label for="folder">Target Folder</label><div class="input-with-icon"><span class="input-icon">📁</span><input type="text" id="folder" placeholder="uploads"></div><div class="helper-text">Folder within bucket where files will be uploaded</div></div>
    </div>
    <div class="section">
      <h2><i>🤖</i> RAG Server Configuration</h2>
      <div class="form-group"><label for="ragServerUrl">RAG Server URL</label><div class="input-with-icon"><span class="input-icon">🧠</span><input type="text" id="ragServerUrl" placeholder="https://rag.your-server.com"></div><div class="helper-text">Your RAG server endpoint (e.g., https://rag.gitgpt.chat)</div></div>
    </div>
    <div class="section full-width">
      <h2><i>🚀</i> CDN Configuration</h2>
      <div class="form-group"><label for="cdnEndpoint">CDN Endpoint (Optional)</label><div class="input-with-icon"><span class="input-icon">⚡</span><input type="text" id="cdnEndpoint" placeholder="https://cdn.yourdomain.com"></div><div class="helper-text">If you have Spaces CDN enabled, enter the CDN URL here</div></div>
      <div class="form-group"><label for="apiToken">API Token (For CDN Purge)</label><div class="input-with-icon"><span class="input-icon">🔐</span><input type="password" id="apiToken" placeholder="DigitalOcean API Token"></div><div class="helper-text">Required for automatic CDN cache purging. <a href="https://cloud.digitalocean.com/account/api/tokens" target="_blank">Generate token</a></div></div>
      <div class="form-group"><div class="input-with-icon" style="display: flex; gap: 10px;"><input type="text" id="cdnId" placeholder="CDN Endpoint ID (auto-detected)" style="flex: 1;"><button id="detectCdn" class="btn btn-secondary" style="width: auto; padding: 0 15px;">🔍 Auto-detect</button></div></div>
      <div class="checkbox-group"><input type="checkbox" id="makePublic" checked><label for="makePublic">Make uploaded files publicly accessible</label></div>
    </div>
    <div class="section full-width">
      <h2><i>⚡</i> Quick Test</h2>
      <div class="upload-preview" id="uploadArea"><i>📁</i><p>Drop a file here to test upload</p><small>Or click to select a file</small></div>
      <div id="filePreview"></div>
      <div class="button-group"><button id="testConfig" class="btn btn-secondary"><i>🔍</i> Test Configuration</button><button id="saveConfig" class="btn btn-primary"><i>💾</i> Save Settings</button><button id="resetConfig" class="btn btn-danger"><i>🔄</i> Reset</button></div>
      <div id="statusMessage" class="status-message"></div>
    </div>
  </div>
  <div class="api-help">
    <h3>📚 How to get your API credentials:</h3>
    <ol><li>Go to <a href="https://cloud.digitalocean.com/account/api/tokens" target="_blank">DigitalOcean API Tokens</a></li><li>Click "Generate New Token" → "Custom Scopes"</li><li>Select: <code>spaces:read</code>, <code>spaces:write</code>, <code>cdn:read</code>, <code>cdn:write</code></li><li>Copy the generated token</li><li>For Spaces keys, go to Spaces → Settings → Access Keys</li><li>Generate new key pair and copy both Access Key and Secret Key</li></ol>
  </div>
  <div class="features-grid">
    <div class="feature-card"><div class="feature-icon">📸</div><div class="feature-title">Image Upload</div><div class="feature-desc">Right-click any image to upload instantly.</div></div>
    <div class="feature-card"><div class="feature-icon">🎬</div><div class="feature-title">Video Upload</div><div class="feature-desc">Upload videos in MP4, AVI, MOV formats.</div></div>
    <div class="feature-card"><div class="feature-icon">📄</div><div class="feature-title">Page to RAG</div><div class="feature-desc">Extract, chunk, and upload any webpage.</div></div>
    <div class="feature-card"><div class="feature-icon">❓</div><div class="feature-title">Ask Questions</div><div class="feature-desc">Query pages using your RAG server.</div></div>
  </div>
  <script src="options.js"></script>
</body>
</html>
EOL

# Create options/options.js
cat << 'EOL' > options/options.js
document.addEventListener('DOMContentLoaded', async function() {
  console.log("⚙️ RAG Uploader options loaded");
  await loadConfiguration();
  document.getElementById('saveConfig').addEventListener('click', saveConfiguration);
  document.getElementById('resetConfig').addEventListener('click', resetConfiguration);
  document.getElementById('testConfig').addEventListener('click', testConfiguration);
  document.getElementById('detectCdn').addEventListener('click', autoDetectCdn);
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
});

async function loadConfiguration() {
  try {
    const response = await browser.runtime.sendMessage({ action: "getConfig" });
    const config = response || {};
    document.getElementById('accessKey').value = config.accessKey || '';
    document.getElementById('secretKey').value = config.secretKey || '';
    document.getElementById('bucket').value = config.bucket || '';
    document.getElementById('endpoint').value = config.endpoint || 'https://nyc3.digitaloceanspaces.com';
    document.getElementById('region').value = config.region || 'us-east-1';
    document.getElementById('folder').value = config.folder || 'uploads';
    document.getElementById('cdnEndpoint').value = config.cdnEndpoint || '';
    document.getElementById('apiToken').value = config.apiToken || '';
    document.getElementById('cdnId').value = config.cdnId || '';
    document.getElementById('ragServerUrl').value = config.ragServerUrl || '';
    document.getElementById('makePublic').checked = config.makePublic !== false;
    console.log("Configuration loaded:", config);
  } catch (error) {
    console.error("Failed to load configuration:", error);
    showStatus("❌ Failed to load configuration", 'error');
  }
}

async function saveConfiguration() {
  try {
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
      ragServerUrl: document.getElementById('ragServerUrl').value.trim(),
      makePublic: document.getElementById('makePublic').checked
    };
    if (!config.accessKey || !config.secretKey || !config.bucket) {
      showStatus("❌ Please fill in Access Key, Secret Key, and Bucket Name", 'error');
      return;
    }
    const response = await browser.runtime.sendMessage({ action: "saveConfig", config: config });
    if (response) {
      showStatus("✅ Configuration saved successfully!", 'success');
      if (config.apiToken && config.bucket && !config.cdnId) { setTimeout(() => autoDetectCdn(), 1000); }
    } else {
      showStatus("❌ Failed to save configuration", 'error');
    }
  } catch (error) {
    console.error("Failed to save configuration:", error);
    showStatus(`❌ Error: ${error.message}`, 'error');
  }
}

function resetConfiguration() {
  if (confirm("Are you sure you want to reset all settings? This cannot be undone.")) {
    document.getElementById('accessKey').value = '';
    document.getElementById('secretKey').value = '';
    document.getElementById('bucket').value = '';
    document.getElementById('endpoint').value = 'https://nyc3.digitaloceanspaces.com';
    document.getElementById('region').value = 'us-east-1';
    document.getElementById('folder').value = 'uploads';
    document.getElementById('cdnEndpoint').value = '';
    document.getElementById('apiToken').value = '';
    document.getElementById('cdnId').value = '';
    document.getElementById('ragServerUrl').value = '';
    document.getElementById('makePublic').checked = true;
    showStatus("🔄 Configuration reset", 'info');
  }
}

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
    const response = await browser.runtime.sendMessage({ action: "testConnection", config: config });
    if (response.success) { showStatus("✅ " + response.message, 'success'); }
    else { showStatus("❌ " + response.message, 'error'); }
  } catch (error) {
    console.error("Configuration test failed:", error);
    showStatus(`❌ Test failed: ${error.message}`, 'error');
  }
}

async function autoDetectCdn() {
  try {
    const apiToken = document.getElementById('apiToken').value.trim();
    const bucket = document.getElementById('bucket').value.trim();
    if (!apiToken) { showStatus("❌ Please enter your API Token first", 'error'); return; }
    if (!bucket) { showStatus("❌ Please enter your Bucket Name first", 'error'); return; }
    showStatus("🔍 Detecting CDN endpoint...", 'info');
    const response = await browser.runtime.sendMessage({ action: "autoDetectCdnId", apiToken: apiToken, bucket: bucket });
    if (response.success) {
      document.getElementById('cdnId').value = response.cdnId;
      showStatus("✅ CDN endpoint detected and saved!", 'success');
      setTimeout(() => saveConfiguration(), 500);
    } else {
      showStatus("⚠️ " + response.message, 'error');
    }
  } catch (error) {
    console.error("CDN detection failed:", error);
    showStatus(`❌ Detection failed: ${error.message}`, 'error');
  }
}

function handleDragOver(e) { e.preventDefault(); e.stopPropagation(); e.dataTransfer.dropEffect = 'copy'; }
async function handleFileDrop(e) {
  e.preventDefault(); e.stopPropagation();
  const files = Array.from(e.dataTransfer.files);
  if (files.length === 0) return;
  await testFileUpload(files[0]);
}
async function handleFileSelect(e) {
  const files = Array.from(e.target.files || (e.dataTransfer ? e.dataTransfer.files : []));
  if (files.length === 0) return;
  await testFileUpload(files[0]);
}

async function testFileUpload(file) {
  try {
    showStatus(`📤 Uploading ${file.name}...`, 'info');
    const preview = document.getElementById('filePreview');
    preview.innerHTML = '';
    if (file.type.startsWith('image/')) {
      const img = document.createElement('img');
      img.src = URL.createObjectURL(file);
      img.className = 'preview-image';
      img.style.maxWidth = '100%';
      img.style.maxHeight = '200px';
      img.style.borderRadius = '8px';
      preview.appendChild(img);
    }
    const info = document.createElement('div');
    info.className = 'preview-info';
    info.innerHTML = `<strong>${file.name}</strong><br>Size: ${(file.size / 1024).toFixed(2)} KB<br>Type: ${file.type}`;
    preview.appendChild(info);
    preview.style.display = 'block';
    const reader = new FileReader();
    reader.onload = async function() {
      try {
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
        const dataUrl = reader.result;
        const response = await browser.runtime.sendMessage({
          action: "uploadMediaFile",
          dataUrl: dataUrl,
          filename: file.name,
          contentType: file.type,
          mediaType: file.type.startsWith('image/') ? 'image' : file.type.startsWith('video/') ? 'video' : file.type.startsWith('audio/') ? 'audio' : 'file'
        });
        if (response && response.success) {
          showStatus(`✅ Upload successful! URL: ${response.url}`, 'success');
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

# Create content.js with all extraction functions (meta, snapshot, text chunking)
cat << 'EOL' > content.js
// RAG Uploader - Content Script (Merged: Meta Extractor + Snapshot + Vector)
console.log("🌐 RAG Uploader content script loaded");

let isProcessing = false;
let currentRagAction = null;

browser.runtime.onMessage.addListener(async (message) => {
  if (message.action === "ragAction" && !isProcessing) {
    isProcessing = true;
    currentRagAction = message.ragActionType;
    await handleRagAction(message.ragActionType);
    isProcessing = false;
    browser.runtime.sendMessage({ action: "ragComplete", type: message.ragActionType });
  }
  return true;
});

async function handleRagAction(actionType) {
  const statusBox = createStatusBox();
  try {
    if (actionType === "full" || actionType === "meta") {
      updateStatus("Extracting page metadata...");
      const metaData = extractMetaData();
      updateStatus(`✅ Metadata: ${metaData.title}`);
      if (actionType === "meta") {
        showMetaPopup(metaData);
        setTimeout(() => statusBox?.remove(), 5000);
        return;
      }
    }
    if (actionType === "full" || actionType === "snapshot") {
      updateStatus("Embedding CSS...");
      await embedStyles();
      updateStatus("Cleaning ads and trackers...");
      cleanPage();
      updateStatus("Embedding images as Base64...");
      await embedImages();
      if (actionType === "snapshot") {
        updateStatus("Saving HTML snapshot...");
        saveHTMLSnapshot();
        setTimeout(() => statusBox?.remove(), 3000);
        return;
      }
    }
    if (actionType === "full") {
      updateStatus("Extracting text chunks for RAG...");
      const textChunks = extractTextChunks();
      const metadata = {
        url: window.location.href,
        title: document.title,
        description: getMetaContent('description') || getMetaContent('og:description'),
        wordCount: textChunks.reduce((sum, c) => sum + c.wordCount, 0),
        chunkCount: textChunks.length,
        extractedAt: new Date().toISOString()
      };
      const fullText = textChunks.map(c => c.text).join('\n\n---CHUNK---\n\n');
      const filename = sanitizeFilename(document.title || window.location.hostname) + `-${Date.now()}.txt`;
      updateStatus("Uploading to DO Spaces...");
      const uploadResult = await uploadTextToSpaces(fullText, filename, metadata);
      if (uploadResult.success) {
        updateStatus(`✅ Uploaded! URL: ${uploadResult.url}`);
        await browser.clipboard.writeText(uploadResult.url);
        browser.notifications.create({
          type: "basic",
          iconUrl: browser.runtime.getURL("icons/icon-48.png"),
          title: "✅ RAG Upload Complete!",
          message: `Page uploaded to DO Spaces\nURL copied to clipboard\n\nRAG Query: ${await getRagQueryUrl(uploadResult.url)}`
        });
        saveToHistory(filename, uploadResult.url, metadata);
      } else {
        updateStatus(`❌ Upload failed: ${uploadResult.error}`);
      }
    }
  } catch (error) {
    console.error("RAG action failed:", error);
    updateStatus(`❌ Failed: ${error.message}`);
  } finally {
    setTimeout(() => { if (statusBox) statusBox.remove(); }, 5000);
  }
}

function extractMetaData() {
  return {
    url: window.location.href,
    title: document.title,
    description: getMetaContent('description') || getMetaContent('og:description') || '',
    keywords: getMetaContent('keywords') || '',
    author: getMetaContent('author') || '',
    ogTitle: getMetaContent('og:title') || '',
    ogImage: getMetaContent('og:image') || '',
    ogType: getMetaContent('og:type') || '',
    twitterCard: getMetaContent('twitter:card') || '',
    twitterImage: getMetaContent('twitter:image') || '',
    favicon: extractFavicon(),
    charset: document.characterSet || '',
    viewport: getMetaContent('viewport') || ''
  };
}

function getMetaContent(name) {
  const meta = document.querySelector(`meta[name="${name}"], meta[property="${name}"]`);
  return meta ? meta.getAttribute('content') : '';
}

function extractFavicon() {
  const selectors = ['link[rel="icon"]', 'link[rel="shortcut icon"]', 'link[rel="apple-touch-icon"]'];
  for (const sel of selectors) {
    const icon = document.querySelector(sel);
    if (icon && icon.href) return icon.href;
  }
  return `${window.location.origin}/favicon.ico`;
}

function showMetaPopup(meta) {
  const existing = document.getElementById('ragMetaPopup');
  if (existing) existing.remove();
  const popup = document.createElement('div');
  popup.id = 'ragMetaPopup';
  Object.assign(popup.style, {
    position: 'fixed', top: '20px', right: '20px', width: '350px', maxHeight: '80vh',
    background: 'white', borderRadius: '12px', boxShadow: '0 20px 60px rgba(0,0,0,0.3)',
    zIndex: '999999', overflowY: 'auto', fontFamily: 'sans-serif', fontSize: '13px'
  });
  popup.innerHTML = `
    <div style="padding:15px; border-bottom:1px solid #e0e0e0; background:#f5f5f5; border-radius:12px 12px 0 0; display:flex; justify-content:space-between;">
      <strong>📋 Page Metadata</strong><button id="closeMetaPopup" style="background:none; border:none; font-size:20px; cursor:pointer;">×</button>
    </div>
    <div style="padding:15px;">
      <div style="margin-bottom:10px;"><strong>Title:</strong><br>${escapeHtml(meta.title)}</div>
      <div style="margin-bottom:10px;"><strong>URL:</strong><br><a href="${meta.url}" target="_blank" style="color:#0066cc;">${meta.url}</a></div>
      <div style="margin-bottom:10px;"><strong>Description:</strong><br>${escapeHtml(meta.description)}</div>
      ${meta.ogImage ? `<div style="margin-bottom:10px;"><strong>OG Image:</strong><br><img src="${meta.ogImage}" style="max-width:100%; max-height:150px; border-radius:4px;"></div>` : ''}
      <div style="margin-bottom:10px;"><strong>Favicon:</strong><br><img src="${meta.favicon}" style="width:32px; height:32px;"></div>
      <div><strong>Extracted:</strong><br>${new Date().toLocaleString()}</div>
    </div>
  `;
  document.body.appendChild(popup);
  document.getElementById('closeMetaPopup').onclick = () => popup.remove();
  setTimeout(() => popup.remove(), 30000);
}

function extractTextChunks(chunkSize = 400) {
  const contentSelectors = ['article', 'main', '[role="main"]', 'body'];
  let container = document.querySelector(contentSelectors.join(','));
  if (!container) container = document.body;
  const clone = container.cloneNode(true);
  clone.querySelectorAll('script, style, nav, header, footer, aside, .ad, .ads, .advertisement').forEach(el => el.remove());
  const text = clone.textContent || '';
  const words = text.split(/\s+/).filter(w => w.length > 0);
  const chunks = [];
  for (let i = 0; i < words.length; i += chunkSize) {
    const chunkWords = words.slice(i, i + chunkSize);
    chunks.push({ text: chunkWords.join(' '), wordCount: chunkWords.length });
  }
  return chunks.length ? chunks : [{ text: text.substring(0, 2000), wordCount: text.split(/\s+/).length }];
}

async function embedStyles() {
  const links = Array.from(document.querySelectorAll('link[rel="stylesheet"]'));
  for (const link of links) {
    const href = link.href;
    if (!href) continue;
    try {
      const cssText = await fetch(href).then(r => r.text());
      const style = document.createElement('style');
      style.textContent = cssText;
      link.parentNode.insertBefore(style, link);
      link.remove();
    } catch (e) { console.warn("Failed to embed CSS:", href, e); }
  }
}

function cleanPage() {
  const adSelectors = ['.ads', '.adbox', '.popup', '.promo', '.newsletter', '.advertisement', '[class*="ad-"]', '[id*="ad-"]'];
  adSelectors.forEach(sel => document.querySelectorAll(sel).forEach(el => el.remove()));
  const scripts = Array.from(document.querySelectorAll('script[src]'));
  scripts.forEach(s => {
    const src = s.src;
    if (src && (src.includes('googletagmanager') || src.includes('analytics') || src.includes('doubleclick'))) s.remove();
  });
}

async function embedImages() {
  const imgs = document.querySelectorAll('img');
  for (let i = 0; i < imgs.length; i++) {
    const img = imgs[i];
    const src = img.getAttribute('data-src') || img.src;
    if (!src || src.startsWith('data:') || src.includes('archive.org')) continue;
    try {
      const response = await fetch(src);
      if (!response.ok) continue;
      const blob = await response.blob();
      if (blob.size > 2 * 1024 * 1024) continue;
      const reader = new FileReader();
      await new Promise(resolve => {
        reader.onloadend = () => { img.src = reader.result; resolve(); };
        reader.readAsDataURL(blob);
      });
    } catch (e) { console.warn("Failed to embed image:", src, e); }
  }
}

function saveHTMLSnapshot() {
  const htmlContent = "<!DOCTYPE html>\n" + document.documentElement.outerHTML;
  let filename = sanitizeFilename(document.title || 'snapshot');
  if (!filename.endsWith('.html')) filename += '.html';
  const blob = new Blob([htmlContent], { type: "text/html" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

async function uploadTextToSpaces(text, filename, metadata) {
  const textBlob = new Blob([text], { type: 'text/plain' });
  const reader = new FileReader();
  return new Promise((resolve) => {
    reader.onloadend = async () => {
      const dataUrl = reader.result;
      const response = await browser.runtime.sendMessage({
        action: "uploadMediaFile",
        dataUrl: dataUrl,
        filename: filename,
        contentType: 'text/plain',
        mediaType: 'file'
      });
      resolve(response);
    };
    reader.readAsDataURL(textBlob);
  });
}

async function getRagQueryUrl(cdnUrl) {
  const config = await browser.runtime.sendMessage({ action: "getConfig" });
  const ragServer = config.ragServerUrl;
  if (ragServer) {
    return `${ragServer}/ask?q=YOUR_QUESTION&url=${encodeURIComponent(cdnUrl)}&limit=20`;
  }
  return cdnUrl;
}

function saveToHistory(filename, url, metadata) {
  browser.storage.local.get(['ragHistory']).then(result => {
    const history = result.ragHistory || [];
    history.unshift({ filename, url, metadata, timestamp: Date.now() });
    if (history.length > 50) history.length = 50;
    browser.storage.local.set({ ragHistory: history });
  });
}

function createStatusBox() {
  const existing = document.getElementById("ragUploaderStatus");
  if (existing) existing.remove();
  const box = document.createElement("div");
  box.id = "ragUploaderStatus";
  Object.assign(box.style, {
    position: "fixed", bottom: "20px", right: "20px", backgroundColor: "rgba(0,0,0,0.85)",
    color: "#fff", padding: "10px 15px", borderRadius: "8px", zIndex: 999999,
    fontFamily: "Arial, sans-serif", fontSize: "14px", boxShadow: "0 0 10px rgba(0,0,0,0.5)"
  });
  box.innerHTML = "Processing...";
  document.body.appendChild(box);
  return box;
}

function updateStatus(message) {
  const box = document.getElementById("ragUploaderStatus");
  if (box) box.innerHTML = message;
  console.log(message);
}

function sanitizeFilename(name) {
  return name.replace(/[<>:"/\\|?*]/g, '_').substring(0, 200);
}

function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/[&<>]/g, function(m) {
    if (m === '&') return '&amp;';
    if (m === '<') return '&lt;';
    if (m === '>') return '&gt;';
    return m;
  });
}

console.log("✅ RAG Uploader content script ready!");
EOL

# Create ask.html (Ask about page popup)
cat << 'EOL' > ask.html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Ask about this page</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      width: 450px;
      min-height: 400px;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      color: white;
      padding: 20px;
    }
    h1 { font-size: 18px; margin-bottom: 15px; display: flex; align-items: center; gap: 10px; }
    .page-url { background: rgba(255,255,255,0.1); padding: 8px 12px; border-radius: 8px; font-size: 11px; margin-bottom: 15px; word-break: break-all; }
    input { width: 100%; padding: 12px; border: none; border-radius: 8px; font-size: 14px; margin-bottom: 10px; background: rgba(255,255,255,0.15); color: white; }
    input::placeholder { color: rgba(255,255,255,0.5); }
    button { width: 100%; padding: 12px; border: none; border-radius: 8px; background: #4F46E5; color: white; font-size: 14px; font-weight: 600; cursor: pointer; transition: all 0.2s; }
    button:hover { background: #6366f1; transform: translateY(-1px); }
    button:disabled { opacity: 0.5; cursor: not-allowed; }
    .answer { margin-top: 15px; padding: 12px; background: rgba(255,255,255,0.1); border-radius: 8px; max-height: 300px; overflow-y: auto; font-size: 13px; line-height: 1.5; }
    .loading { text-align: center; padding: 20px; color: rgba(255,255,255,0.7); }
    .error { color: #f87171; }
    .success { color: #4ade80; }
    small { display: block; margin-top: 10px; color: rgba(255,255,255,0.5); font-size: 10px; text-align: center; }
  </style>
</head>
<body>
  <h1>❓ Ask about this page</h1>
  <div class="page-url" id="pageUrl">Loading...</div>
  <input type="text" id="questionInput" placeholder="e.g., What is the main topic? Summarize this page..." autofocus>
  <button id="askBtn">Ask</button>
  <div class="answer" id="answerDiv"></div>
  <small>Powered by your RAG server. Make sure DO Spaces credentials and RAG server URL are configured in settings.</small>
  <script src="ask.js"></script>
</body>
</html>
EOL

# Create ask.js
cat << 'EOL' > ask.js
let currentPageUrl = null;
let lastUploadedUrl = null;

document.addEventListener('DOMContentLoaded', async () => {
  const urlParams = new URLSearchParams(window.location.search);
  currentPageUrl = urlParams.get('url');
  if (currentPageUrl) {
    document.getElementById('pageUrl').textContent = currentPageUrl;
  } else {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    if (tabs[0]) currentPageUrl = tabs[0].url;
    document.getElementById('pageUrl').textContent = currentPageUrl || 'Unknown';
  }
  document.getElementById('askBtn').addEventListener('click', askQuestion);
  document.getElementById('questionInput').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') askQuestion();
  });
});

async function askQuestion() {
  const question = document.getElementById('questionInput').value.trim();
  if (!question) {
    showAnswer('Please enter a question.', 'error');
    return;
  }
  const config = await browser.runtime.sendMessage({ action: "getConfig" });
  const ragServer = config.ragServerUrl;
  if (!ragServer) {
    showAnswer('RAG server not configured. Please go to Settings and add your RAG server URL.', 'error');
    return;
  }
  if (!config.accessKey || !config.secretKey || !config.bucket) {
    showAnswer('DO Spaces not configured. Please configure your Spaces credentials first.', 'error');
    return;
  }
  showAnswer('Thinking...', 'loading');
  document.getElementById('askBtn').disabled = true;
  try {
    let cdnUrl = null;
    const history = await browser.storage.local.get(['ragHistory']);
    if (history.ragHistory && history.ragHistory.length > 0) {
      const match = history.ragHistory.find(h => h.metadata && h.metadata.url === currentPageUrl);
      if (match) cdnUrl = match.url;
    }
    if (!cdnUrl) {
      showAnswer('This page has not been uploaded to RAG yet. Right-click and select "Upload page to RAG" first.', 'error');
      document.getElementById('askBtn').disabled = false;
      return;
    }
    const ragUrl = `${ragServer}/ask?q=${encodeURIComponent(question)}&url=${encodeURIComponent(cdnUrl)}&limit=20`;
    const response = await fetch(ragUrl);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    if (data.relevant_chunks && data.relevant_chunks.length > 0) {
      let html = '<strong>Most relevant answers:</strong><br><br>';
      data.relevant_chunks.forEach((chunk, i) => {
        html += `<div style="margin-bottom: 12px; padding: 8px; background: rgba(255,255,255,0.05); border-radius: 6px;">
          <strong>Match ${i+1} (score: ${chunk.score})</strong><br>
          ${escapeHtml(chunk.text.substring(0, 500))}${chunk.text.length > 500 ? '...' : ''}
          <br><small style="color: #aaa;">Lines: ${chunk.lines || 'N/A'}</small>
        </div>`;
      });
      if (data.answer) html += `<br><strong>AI Answer:</strong><br>${escapeHtml(data.answer)}`;
      showAnswer(html, 'success');
    } else {
      showAnswer('No relevant information found on this page for your question.', 'error');
    }
  } catch (error) {
    console.error('Ask failed:', error);
    showAnswer(`Error: ${error.message}`, 'error');
  } finally {
    document.getElementById('askBtn').disabled = false;
  }
}

function showAnswer(message, type) {
  const div = document.getElementById('answerDiv');
  div.innerHTML = message;
  div.className = 'answer';
  if (type === 'error') div.style.color = '#f87171';
  else if (type === 'success') div.style.color = '#4ade80';
  else div.style.color = 'rgba(255,255,255,0.7)';
}

function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/[&<>]/g, function(m) {
    if (m === '&') return '&amp;';
    if (m === '<') return '&lt;';
    if (m === '>') return '&gt;';
    return m;
  });
}
EOL

# Create README.md
cat << 'EOL' > README.md
# RAG Uploader - Firefox Extension

Upload webpages to Digital Ocean Spaces with metadata extraction, offline snapshots, and RAG-ready chunks.

## Features

- Upload any file/image/video to DO Spaces
- Extract page metadata (title, description, OG images, favicon)
- Save offline HTML snapshot with embedded images
- Chunk page content for RAG (AI-ready)
- Ask questions about any page using your RAG server

## Installation

1. Run `./create-rag-uploader.sh`
2. Open Firefox → about:debugging#/runtime/this-firefox
3. Click "Load Temporary Add-on"
4. Select manifest.json from the generated folder

## Configuration

1. Click the extension icon → "Full Settings"
2. Enter your DO Spaces credentials (Access Key, Secret Key, Bucket)
3. Enter your RAG server URL (e.g., https://rag.your-server.com)
4. Click "Save Settings"

## Usage

- Right-click any image/video → Upload to DO Spaces
- Right-click any page → "Upload page to RAG" (extracts + uploads)
- Right-click any page → "Extract page metadata only"
- Right-click any page → "Save offline snapshot"
- Right-click any page → "Ask about this page"

## Requirements

- Digital Ocean Spaces account with bucket
- Your own RAG server (separate installation)

## License

MIT
EOL

# Create LICENSE.md
cat << 'EOL' > LICENSE.md
MIT License

Copyright (c) 2025 RAG Uploader

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files, to deal in the Software
without restriction, including without limitation the rights to use, copy,
modify, merge, publish, distribute, sublicense, and/or sell copies of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
EOL

echo -e "${GREEN}✅ RAG Uploader extension generated successfully!${NC}"
echo -e "${YELLOW}📁 Extension folder: $EXTNAME${NC}"

cd ..
XPI_FILE="${EXTNAME}.xpi"
rm -f "$XPI_FILE" 2>/dev/null
cd "$EXTNAME"
if command -v zip &> /dev/null; then
  zip -r "../$XPI_FILE" * -x "*.xpi" -x "."
elif command -v 7z &> /dev/null; then
  7z a "../$XPI_FILE" * -r -x!.xpi -x!.
else
  echo -e "${RED}Error: Need zip or 7z to create XPI${NC}"
  exit 1
fi
cd ..

if [ -f "$XPI_FILE" ]; then
  echo -e "${GREEN}✅ Created: $XPI_FILE${NC}"
  echo -e "${YELLOW}📦 Size: $(du -h "$XPI_FILE" | cut -f1)${NC}"
  mv "$XPI_FILE" "$HOME/Downloads/${EXTNAME}.xpi" 2>/dev/null || true
fi

echo -e ""
echo -e "${GREEN}✨ FILES CREATED:${NC}"
echo -e "  • ${EXTNAME}/ - Extension folder"
echo -e "  • ${EXTNAME}.xpi - Extension package"
echo -e ""
echo -e "${CYAN}🚀 INSTALLATION:${NC}"
echo -e "  1. Open Firefox → about:debugging#/runtime/this-firefox"
echo -e "  2. Click 'Load Temporary Add-on'"
echo -e "  3. Select manifest.json from ${EXTNAME}/ folder"
echo -e ""
echo -e "${CYAN}🎯 HOW TO USE:${NC}"
echo -e "  • Right-click any page → Upload page to RAG"
echo -e "  • Right-click any page → Ask about this page"
echo -e "  • Right-click any image/video → Upload to DO Spaces"
echo -e ""
echo -e "${GREEN}🎉 RAG Uploader extension generation complete!${NC}"