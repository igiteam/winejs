// ==UserScript==
// @name         Website Metatag Extractor
// @namespace    http://tampermonkey.net/
// @version      2.0
// @description  Extract and display meta tags, favicon, meta images, and website snapshot. Left-click to activate.
// @author       Your Name
// @match        *://*/*
// @grant        GM_addStyle
// @grant        GM_registerMenuCommand
// @icon         https://cdn.sdappnet.cloud/rtx/images/htmlmetatags.png
// @run-at       document-end
// ==/UserScript==

(function () {
  ("use strict");

  // Add custom CSS for the popup
  GM_addStyle(`
        .meta-extractor-popup {
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: white;
            padding: 25px;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            z-index: 10000;
            width: 90%;
            max-width: 900px;
            max-height: 85vh;
            overflow-y: auto;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Arial', sans-serif;
            border: 1px solid #e0e0e0;
        }

        .meta-extractor-popup-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0,0,0,0.7);
            backdrop-filter: blur(3px);
            z-index: 9999;
        }

        .meta-extractor-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 25px;
            padding-bottom: 15px;
            border-bottom: 2px solid #f0f0f0;
        }

        .meta-extractor-title {
            font-size: 22px;
            font-weight: 700;
            margin: 0;
            color: #2c3e50;
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .meta-extractor-close {
            background: #f0f0f0;
            border: none;
            font-size: 24px;
            cursor: pointer;
            color: #666;
            padding: 5px 12px;
            display: flex;
            align-items: center;
            justify-content: center;
         }


        .meta-extractor-content {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 25px;
        }

        @media (max-width: 768px) {
            .meta-extractor-content {
                grid-template-columns: 1fr;
            }
        }

        .meta-extractor-section {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            border: 1px solid #e9ecef;
        }

        .meta-extractor-section-title {
            font-size: 16px;
            font-weight: 600;
            margin: 0 0 15px 0;
            color: #495057;
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .meta-extractor-section-title svg {
            color: #6c757d;
        }

        .meta-extractor-tags {
            display: flex;
            flex-direction: column;
            gap: 12px;
        }

        .meta-tag-item {
            background: white;
            padding: 12px 15px;
            border-radius: 8px;
            border-left: 4px solid #3498db;
            box-shadow: 0 2px 4px rgba(0,0,0,0.05);
        }

        .meta-tag-name {
            font-weight: 600;
            color: #2c3e50;
            font-size: 14px;
            margin-bottom: 5px;
            display: flex;
            align-items: center;
            gap: 6px;
        }

        .meta-tag-name svg {
            color: #7f8c8d;
        }

        .meta-tag-value {
            color: #34495e;
            font-size: 13px;
            line-height: 1.5;
            word-break: break-word;
            background: #f8f9fa;
            padding: 8px 10px;
            border-radius: 4px;
            border: 1px solid #e9ecef;
        }

        .meta-tag-value.url {
            color: #2980b9;
        }

        .meta-extractor-images {
            display: flex;
            flex-direction: column;
            gap: 20px;
        }

        .meta-image-container {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 3px 10px rgba(0,0,0,0.08);
            text-align: center;
        }

        .meta-image-label {
            font-weight: 600;
            color: #2c3e50;
            margin-bottom: 15px;
            font-size: 15px;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
        }

        .meta-image-preview {
            max-width: 100%;
            max-height: 200px;
            border-radius: 8px;
            border: 2px solid #e9ecef;
            padding: 5px;
            background: white;
            cursor: pointer;
            transition: transform 0.2s;
        }

        .meta-image-preview:hover {
            transform: scale(1.02);
            border-color: #3498db;
        }

        .meta-image-url {
            margin-top: 12px;
            color: #7f8c8d;
            font-size: 12px;
            word-break: break-all;
            background: #f8f9fa;
            padding: 8px;
            border-radius: 4px;
            border: 1px solid #e9ecef;
        }

        .snapshot-container {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 3px 10px rgba(0,0,0,0.08);
            text-align: center;
            margin-bottom: 20px;
        }

        .snapshot-preview {
            max-width: 100%;
            max-height: 300px;
            border-radius: 8px;
            border: 2px solid #e9ecef;
            padding: 5px;
            background: white;
            cursor: pointer;
            transition: transform 0.2s;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }

        .snapshot-preview:hover {
            transform: scale(1.02);
            border-color: #3498db;
        }

        .snapshot-url {
            margin-top: 12px;
            color: #7f8c8d;
            font-size: 12px;
            word-break: break-all;
            background: #f8f9fa;
            padding: 8px;
            border-radius: 4px;
            border: 1px solid #e9ecef;
        }

        .snapshot-controls {
            display: flex;
            gap: 10px;
            justify-content: center;
            margin: 15px 0;
        }

        .snapshot-size-btn {
            background: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 4px;
            padding: 5px 10px;
            font-size: 12px;
            cursor: pointer;
            transition: all 0.2s;
        }

        .snapshot-size-btn:hover {
            background: #e9ecef;
            border-color: #adb5bd;
        }

        .snapshot-size-btn.active {
            background: #3498db;
            color: white;
            border-color: #2980b9;
        }

        .meta-extractor-buttons {
            display: flex;
            gap: 10px;
            margin-top: 25px;
            padding-top: 20px;
            border-top: 2px solid #f0f0f0;
            justify-content: flex-end;
        }

        .meta-extractor-btn {
            padding: 10px 20px;
            border-radius: 6px;
            border: none;
            font-weight: 600;
            font-size: 14px;
            cursor: pointer;
            transition: all 0.2s;
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .meta-extractor-btn.copy {
            background: #3498db;
            color: white;
        }

        .meta-extractor-btn.copy:hover {
            background: #2980b9;
        }

        .meta-extractor-btn.copied {
            background: #27ae60;
        }

        .meta-extractor-btn.json {
            background: #2ecc71;
            color: white;
        }

        .meta-extractor-btn.json:hover {
            background: #27ae60;
        }

        .meta-extractor-btn.json-view {
            background: #9b59b6;
            color: white;
        }

        .meta-extractor-btn.json-view:hover {
            background: #8e44ad;
        }

        .no-image {
            color: #95a5a6;
            font-style: italic;
            padding: 40px 20px;
            text-align: center;
            background: #f8f9fa;
            border-radius: 8px;
            border: 2px dashed #dee2e6;
        }

        .copy-hint {
            color: #7f8c8d;
            font-size: 12px;
            text-align: center;
            margin-top: 10px;
            font-style: italic;
        }

        .image-right-click-hint {
            color: #e74c3c;
            font-size: 11px;
            text-align: center;
            margin-top: 8px;
            font-weight: 500;
            background: #fff5f5;
            padding: 4px 8px;
            border-radius: 4px;
            display: inline-block;
        }

        .snapshot-loading {
            padding: 40px;
            text-align: center;
            color: #7f8c8d;
            background: #f8f9fa;
            border-radius: 8px;
            border: 2px dashed #dee2e6;
        }

        .snapshot-loading::after {
            content: '';
            display: inline-block;
            width: 20px;
            height: 20px;
            margin-left: 10px;
            border: 2px solid #3498db;
            border-top-color: transparent;
            border-radius: 50%;
            animation: snapshot-spin 1s linear infinite;
        }

        @keyframes snapshot-spin {
            to { transform: rotate(360deg); }
        }

        .snapshot-error {
            padding: 40px;
            text-align: center;
            color: #e74c3c;
            background: #fdf3f2;
            border-radius: 8px;
            border: 2px dashed #e74c3c;
        }
    `);

  // SVG Icons
  const svgIcons = {
    close: `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>`,
    tag: `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M20 10V8h-4V4h-2v4h-4V4H8v4H4v2h4v4H4v2h4v4h2v-4h4v4h2v-4h4v-2h-4v-4h4zm-6 4h-4v-4h4v4z"/></svg>`,
    image: `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/></svg>`,
    copy: `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>`,
    json: `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M14.6 16.6l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4zm-5.2 0L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4z"/></svg>`,
    favicon: `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/></svg>`,
    link: `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z"/></svg>`,
    camera: `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 6c-3.31 0-6 2.69-6 6s2.69 6 6 6 6-2.69 6-6-2.69-6-6-6zm0 10c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4zm8-10h-3l-2-2H9L7 6H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2zm0 14H4V8h16v12z"/></svg>`,
  };

  // Function to get website snapshot URL
  function getWebsiteSnapshotUrl(url, width = 1920, height = 1080) {
    // Clean up URL (remove protocol and www)
    let cleanUrl = url.replace(/^https?:\/\//, "").replace(/^www\./, "");
    // Remove trailing slash if present
    cleanUrl = cleanUrl.replace(/\/$/, "");

    // Encode the URL properly
    const encodedUrl = encodeURIComponent(cleanUrl);
    return `https://img.sdappnet.cloud/?url=${encodedUrl}&w=${width}&h=${height}`;
  }

  // Function to extract all meta tags
  function extractMetaTags() {
    const metaTags = [];
    const metaElements = document.querySelectorAll("meta");

    // Get Open Graph tags
    const ogTags = {};
    metaElements.forEach((meta) => {
      const property =
        meta.getAttribute("property") || meta.getAttribute("name");
      const content = meta.getAttribute("content");

      if (property && content) {
        const key = property.toLowerCase();
        if (key.startsWith("og:")) {
          const cleanKey = key.replace("og:", "og_");
          ogTags[cleanKey] = content;
        } else if (key.startsWith("twitter:")) {
          const cleanKey = key.replace("twitter:", "twitter_");
          ogTags[cleanKey] = content;
        } else {
          metaTags.push({
            name: property,
            value: content,
          });
        }
      }
    });

    // Get standard meta tags
    const description =
      document.querySelector('meta[name="description"]')?.content || "";
    const keywords =
      document.querySelector('meta[name="keywords"]')?.content || "";
    const author = document.querySelector('meta[name="author"]')?.content || "";
    const viewport =
      document.querySelector('meta[name="viewport"]')?.content || "";
    const charset =
      document.querySelector("meta[charset]")?.getAttribute("charset") ||
      document.querySelector("meta[charset]")?.content ||
      "";

    // Add standard tags to the array
    if (description) metaTags.push({ name: "description", value: description });
    if (keywords) metaTags.push({ name: "keywords", value: keywords });
    if (author) metaTags.push({ name: "author", value: author });
    if (viewport) metaTags.push({ name: "viewport", value: viewport });
    if (charset) metaTags.push({ name: "charset", value: charset });

    // Add Open Graph tags to the array
    Object.entries(ogTags).forEach(([key, value]) => {
      metaTags.push({ name: key, value: value });
    });

    // Add page title
    const title = document.title;
    if (title) metaTags.unshift({ name: "title", value: title });

    // Add URL
    metaTags.unshift({ name: "url", value: window.location.href });

    return metaTags;
  }

  // Function to extract favicon
  function extractFavicon() {
    const faviconSelectors = [
      'link[rel="icon"]',
      'link[rel="shortcut icon"]',
      'link[rel="apple-touch-icon"]',
      'link[rel="apple-touch-icon-precomposed"]',
      'link[rel="mask-icon"]',
      'link[rel="fluid-icon"]',
    ];

    for (const selector of faviconSelectors) {
      const icon = document.querySelector(selector);
      if (icon && icon.href) {
        return icon.href;
      }
    }

    // Fallback to default favicon location
    const baseURL = window.location.origin;
    return `${baseURL}/favicon.ico`;
  }

  // Function to extract meta images
  function extractMetaImages() {
    const images = [];

    // Check Open Graph image
    const ogImage =
      document.querySelector('meta[property="og:image"]')?.content ||
      document.querySelector('meta[name="og:image"]')?.content;
    if (ogImage) {
      images.push({
        type: "og:image",
        url: ogImage,
        alt:
          document.querySelector('meta[property="og:image:alt"]')?.content ||
          "Open Graph Image",
      });
    }

    // Check Twitter image
    const twitterImage =
      document.querySelector('meta[name="twitter:image"]')?.content ||
      document.querySelector('meta[property="twitter:image"]')?.content;
    if (twitterImage) {
      images.push({
        type: "twitter:image",
        url: twitterImage,
        alt: "Twitter Card Image",
      });
    }

    // Check for other image meta tags
    const imageMeta = document.querySelector('meta[itemprop="image"]')?.content;
    if (imageMeta) {
      images.push({
        type: "schema:image",
        url: imageMeta,
        alt: "Schema.org Image",
      });
    }

    return images;
  }

  // Function to create meta tag HTML
  function createMetaTagHTML(metaTags) {
    return metaTags
      .map((tag) => {
        const isUrl = tag.name.includes("url") || tag.value.startsWith("http");
        return `
        <div class="meta-tag-item">
          <div class="meta-tag-name">
            ${svgIcons.tag}
            ${tag.name}
          </div>
          <div class="meta-tag-value ${isUrl ? "url" : ""}">
            ${tag.value}
          </div>
        </div>
      `;
      })
      .join("");
  }

  // Function to create image HTML
  function createImageHTML(images, faviconUrl) {
    const imageHTML = images
      .map(
        (img) => `
      <div class="meta-image-container">
        <div class="meta-image-label">
          ${svgIcons.image}
          ${img.type}
        </div>
        <img src="${img.url}"
             alt="${img.alt}"
             class="meta-image-preview"
             title="Right-click to save or copy image"
             </div>';">

        <div class="meta-image-url">${img.url}</div>
        <div class="image-right-click-hint">Right-click image to save/copy</div>
      </div>
    `
      )
      .join("");

    // Add favicon as an image
    const faviconHTML = `
      <div class="meta-image-container">
        <div class="meta-image-label">
          ${svgIcons.favicon}
          Favicon
        </div>
        <img src="${faviconUrl}"
             alt="Website Favicon"
             class="meta-image-preview"
             title="Right-click to save or copy favicon"
             onerror="this.style.display='none'; this.parentElement.innerHTML='<div class=\\'no-image\\'>Failed to load favicon<br><small>${faviconUrl}</small></div>';">
        <div class="meta-image-url">${faviconUrl}</div>
        <div class="image-right-click-hint">Right-click favicon to save/copy</div>
      </div>
    `;

    return faviconHTML + imageHTML;
  }

  // Function to create snapshot HTML
  function createSnapshotHTML(url, width = 1920, height = 1080) {
    const snapshotUrl = getWebsiteSnapshotUrl(url, width, height);

    return `
      <div class="snapshot-container">
        <div class="meta-image-label">
          ${svgIcons.camera}
          Website Snapshot (${width}x${height})
        </div>
        <div class="snapshot-controls">
          <button class="snapshot-size-btn ${
            width === 800 ? "active" : ""
          }" data-width="800" data-height="600">800x600</button>
          <button class="snapshot-size-btn ${
            width === 1280 ? "active" : ""
          }" data-width="1280" data-height="720">1280x720</button>
          <button class="snapshot-size-btn ${
            width === 1920 ? "active" : ""
          }" data-width="1920" data-height="1080">1920x1080</button>
        </div>
        <img src="${snapshotUrl}"
             alt="Website Snapshot"
             class="snapshot-preview"
             title="Right-click to save or copy snapshot">
        <div class="snapshot-url">${snapshotUrl}</div>
        <div class="image-right-click-hint">Right-click snapshot to save/copy</div>
      </div>
    `;
  }

  // Function to get all data as JSON
  function getMetaDataAsJSON(snapshotWidth = 1920, snapshotHeight = 1080) {
    const metaTags = extractMetaTags();
    const favicon = extractFavicon();
    const images = extractMetaImages();
    const snapshotUrl = getWebsiteSnapshotUrl(
      window.location.href,
      snapshotWidth,
      snapshotHeight
    );

    return {
      url: window.location.href,
      title: document.title,
      metaTags: metaTags.reduce((obj, tag) => {
        obj[tag.name] = tag.value;
        return obj;
      }, {}),
      favicon: favicon,
      metaImages: images,
      snapshot: {
        url: snapshotUrl,
        width: snapshotWidth,
        height: snapshotHeight,
      },
      extractedAt: new Date().toISOString(),
    };
  }

  // Function to show popup
  function showMetaPopup() {
    const metaTags = extractMetaTags();
    const faviconUrl = extractFavicon();
    const images = extractMetaImages();

    // Default snapshot size
    let currentWidth = 1920;
    let currentHeight = 1080;

    const jsonData = getMetaDataAsJSON(currentWidth, currentHeight);

    // Create overlay
    const overlay = document.createElement("div");
    overlay.className = "meta-extractor-popup-overlay";

    // Create popup
    const popup = document.createElement("div");
    popup.className = "meta-extractor-popup";
    popup.innerHTML = `
      <div class="meta-extractor-header">
        <h3 class="meta-extractor-title">
          ${svgIcons.tag}
          Website Meta Tag Extractor
        </h3>
        <button class="meta-extractor-close" aria-label="Close">
          ${svgIcons.close}
        </button>
      </div>

      <div class="meta-extractor-content">

        <div class="meta-extractor-section">
          <h4 class="meta-extractor-section-title">
            ${svgIcons.tag}
            Meta Tags (${metaTags.length})
          </h4>
          <div class="meta-extractor-tags" id="meta-tags-list">
            ${createMetaTagHTML(metaTags)}
          </div>
        </div>
        <div class="meta-extractor-section">
          <h4 class="meta-extractor-section-title">
            ${svgIcons.camera}
            Website Snapshot
          </h4>
          <div id="snapshot-container">
            ${createSnapshotHTML(
              window.location.href,
              currentWidth,
              currentHeight
            )}
          </div>
           <h4 class="meta-extractor-section-title">
            ${svgIcons.image}
            Images (${images.length + 1})
          </h4>
          <div class="meta-extractor-images" id="meta-images-list">
            ${
              images.length > 0 || faviconUrl
                ? createImageHTML(images, faviconUrl)
                : '<div class="no-image">No meta images or favicon found</div>'
            }
          </div>
        </div>

      </div>

      <div class="meta-extractor-buttons">
        <button class="meta-extractor-btn json-view" id="json-view-btn">
          ${svgIcons.json}
          View JSON
        </button>
        <button class="meta-extractor-btn json" id="json-copy-btn">
          ${svgIcons.copy}
          Copy JSON
        </button>
        <button class="meta-extractor-btn copy" id="meta-copy-btn">
          ${svgIcons.copy}
          Copy Meta Tags
        </button>
      </div>
    `;

    // Add event listeners
    const closeBtn = popup.querySelector(".meta-extractor-close");
    const metaCopyBtn = popup.querySelector("#meta-copy-btn");
    const jsonCopyBtn = popup.querySelector("#json-copy-btn");
    const jsonViewBtn = popup.querySelector("#json-view-btn");
    const snapshotContainer = popup.querySelector("#snapshot-container");
    const sizeButtons = popup.querySelectorAll(".snapshot-size-btn");

    // Handle snapshot size changes
    sizeButtons.forEach((btn) => {
      btn.addEventListener("click", () => {
        const width = parseInt(btn.dataset.width);
        const height = parseInt(btn.dataset.height);

        // Update active state
        sizeButtons.forEach((b) => b.classList.remove("active"));
        btn.classList.add("active");

        // Update snapshot
        currentWidth = width;
        currentHeight = height;
        snapshotContainer.innerHTML = createSnapshotHTML(
          window.location.href,
          width,
          height
        );

        // Re-attach event listeners to new size buttons
        const newButtons =
          snapshotContainer.querySelectorAll(".snapshot-size-btn");
        newButtons.forEach((newBtn) => {
          newBtn.addEventListener("click", () => {
            const newWidth = parseInt(newBtn.dataset.width);
            const newHeight = parseInt(newBtn.dataset.height);

            newButtons.forEach((b) => b.classList.remove("active"));
            newBtn.classList.add("active");

            currentWidth = newWidth;
            currentHeight = newHeight;
            snapshotContainer.innerHTML = createSnapshotHTML(
              window.location.href,
              newWidth,
              newHeight
            );

            // Recursively re-attach
            const finalButtons =
              snapshotContainer.querySelectorAll(".snapshot-size-btn");
            finalButtons.forEach((finalBtn) => {
              finalBtn.addEventListener("click", () => {
                const finalWidth = parseInt(finalBtn.dataset.width);
                const finalHeight = parseInt(finalBtn.dataset.height);

                finalButtons.forEach((fb) => fb.classList.remove("active"));
                finalBtn.classList.add("active");
                snapshotContainer.innerHTML = createSnapshotHTML(
                  window.location.href,
                  finalWidth,
                  finalHeight
                );
              });
            });
          });
        });
      });
    });

    // Close popup
    closeBtn.addEventListener("click", () => {
      document.body.removeChild(overlay);
      document.body.removeChild(popup);
    });

    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) {
        document.body.removeChild(overlay);
        document.body.removeChild(popup);
      }
    });

    // Escape key to close
    document.addEventListener("keydown", function closeOnEscape(e) {
      if (e.key === "Escape") {
        document.body.removeChild(overlay);
        document.body.removeChild(popup);
        document.removeEventListener("keydown", closeOnEscape);
      }
    });

    // Copy meta tags as text
    metaCopyBtn.addEventListener("click", async () => {
      const metaText = metaTags
        .map((tag) => `${tag.name}: ${tag.value}`)
        .join("\n");
      try {
        await navigator.clipboard.writeText(metaText);
        metaCopyBtn.innerHTML = `${svgIcons.copy} Copied!`;
        metaCopyBtn.classList.add("copied");
        setTimeout(() => {
          metaCopyBtn.innerHTML = `${svgIcons.copy} Copy Meta Tags`;
          metaCopyBtn.classList.remove("copied");
        }, 2000);
      } catch (err) {
        console.error("Failed to copy:", err);
        metaCopyBtn.textContent = "Failed to copy";
        setTimeout(() => {
          metaCopyBtn.innerHTML = `${svgIcons.copy} Copy Meta Tags`;
        }, 2000);
      }
    });

    // Copy JSON
    jsonCopyBtn.addEventListener("click", async () => {
      const updatedJsonData = getMetaDataAsJSON(currentWidth, currentHeight);
      try {
        await navigator.clipboard.writeText(
          JSON.stringify(updatedJsonData, null, 2)
        );
        jsonCopyBtn.innerHTML = `${svgIcons.copy} Copied JSON!`;
        jsonCopyBtn.classList.add("copied");
        setTimeout(() => {
          jsonCopyBtn.innerHTML = `${svgIcons.copy} Copy JSON`;
          jsonCopyBtn.classList.remove("copied");
        }, 2000);
      } catch (err) {
        console.error("Failed to copy JSON:", err);
        jsonCopyBtn.textContent = "Failed to copy";
        setTimeout(() => {
          jsonCopyBtn.innerHTML = `${svgIcons.copy} Copy JSON`;
        }, 2000);
      }
    });

    // View JSON in new window
    jsonViewBtn.addEventListener("click", () => {
      const updatedJsonData = getMetaDataAsJSON(currentWidth, currentHeight);
      const jsonString = JSON.stringify(updatedJsonData, null, 2);
      const jsonWindow = window.open();
      jsonWindow.document.write(
        `<pre style="padding:20px;font-family:monospace;">${jsonString}</pre>`
      );
      jsonWindow.document.close();
    });

    // Add to page
    document.body.appendChild(overlay);
    document.body.appendChild(popup);

    // Focus the close button for accessibility
    closeBtn.focus();
  }

  // Function to setup keyboard shortcut
  function setupKeydownHandler() {
    // Use both keydown and keyup for better compatibility
    document.addEventListener(
      "keydown",
      function (e) {
        // Check for Alt+Shift+M (case insensitive)
        if (e.altKey && e.shiftKey && (e.key === "m" || e.key === "M")) {
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          console.log("Alt+Shift+M pressed - opening meta extractor");
          showMetaPopup();
          return false;
        }
      },
      true
    ); // Use capture phase to ensure we get the event first

    // Also add a fallback using the key combination in a different way
    document.addEventListener(
      "keyup",
      function (e) {
        if (e.altKey && e.shiftKey && (e.key === "m" || e.key === "M")) {
          e.preventDefault();
          e.stopPropagation();
          // Don't show popup on keyup to avoid duplicates
        }
      },
      true
    );

    // Add an alternative shortcut (Ctrl+Shift+M) as backup
    document.addEventListener(
      "keydown",
      function (e) {
        if (e.ctrlKey && e.shiftKey && (e.key === "m" || e.key === "M")) {
          e.preventDefault();
          e.stopPropagation();
          console.log("Ctrl+Shift+M pressed - opening meta extractor");
          showMetaPopup();
          return false;
        }
      },
      true
    );

    console.log("Keyboard shortcuts registered: Alt+Shift+M or Ctrl+Shift+M");
  }
  // Initialize
  setupKeydownHandler();

  // Add Tampermonkey menu command (appears in right-click menu)
  if (typeof GM_registerMenuCommand !== "undefined") {
    GM_registerMenuCommand("📋 Extract Meta Tags", showMetaPopup, "E");
  }

  // Add notification about how to activate
  setTimeout(() => {
    console.log("Website MetaTag Extractor v2.0 loaded!");
    console.log("Activate by:");
    console.log("1. Press Alt+Shift+M keyboard shortcut");
    console.log("2. Use Tampermonkey menu command");
    console.log("3. Website snapshot available via img.sdappnet.cloud API");
  }, 1000);
})();
