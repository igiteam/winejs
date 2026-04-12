// ==UserScript==
// @name         YouTubeEmbed Redirect
// @namespace    http://tampermonkey.net/
// @version      2.5
// @description  Add YouTube embed icons everywhere (logo, player, lists)
// @match        *://*.youtube.com/*
// @grant        GM_addStyle
// @run-at       document-end
// @icon         https://www.google.com/s2/favicons?sz=64&domain=youtube.com
// ==/UserScript==

(function () {
  "use strict";

  const logoBlack = "https://cdn.sdappnet.cloud/rtx/images/ytembedblack.png";
  const logoWhite = "https://cdn.sdappnet.cloud/rtx/images/ytembedwhite.png";

  const CONFIG = {
    embedBaseUrl: "https://ytembedxyz.netlify.app?",
    debug: true,
  };

  GM_addStyle(`
        .youtube-embed-icon-btn {
            display: inline-flex !important;
            align-items: center !important;
            justify-content: center !important;
            margin: 6px !important;
            padding: 4px !important;
            border: 1px solid rgba(255,0,0,0.35) !important;
            background: rgba(255,0,0,0.12) !important;
            border-radius: 4px !important;
            cursor: pointer !important;
            pointer-events: auto !important;
            z-index: 9999999 !important;
        }

        .youtube-embed-icon-btn img {
            width: 18px !important;
            height: 18px !important;
        }

        .ytp-embed-btn img {
            width: 22px !important;
            height: 22px !important;
        }
    `);

  function extractVideoId(url) {
    try {
      const u = new URL(url, location.origin);

      // Standard watch URLs
      if (u.searchParams.has("v")) {
        return u.searchParams.get("v");
      }

      // youtu.be short links
      if (u.hostname.includes("youtu.be")) {
        return u.pathname.split("/")[1] || null;
      }

      // /watch/VIDEOID fallback
      const parts = u.pathname.split("/");
      if (parts.length === 3 && parts[1] === "watch") {
        return parts[2];
      }

      return null;
    } catch {
      return null;
    }
  }

  function createEmbedUrl(videoId) {
    const code = btoa(videoId)
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");
    return `${CONFIG.embedBaseUrl}${code}`;
  }

  function createEmbedButton(extraClass, logo, getVideoId) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = `youtube-embed-icon-btn ${extraClass || ""}`;
    btn.innerHTML = `<img src="${logo}" alt="Embed">`;
    btn.title = "Open in YouTube Embed";

    btn.addEventListener(
      "mousedown",
      (e) => {
        e.preventDefault();
        e.stopImmediatePropagation();

        const videoId = getVideoId();
        if (!videoId) return;

        window.open(createEmbedUrl(videoId), "_blank");
      },
      true
    );

    btn.addEventListener(
      "click",
      (e) => {
        e.preventDefault();
        e.stopImmediatePropagation();

        const videoId = getVideoId();
        if (!videoId) return;

        window.open(createEmbedUrl(videoId), "_blank");
      },
      true
    );

    return btn;
  }

  function addIconNextToYouTubeLogo() {
    if (document.querySelector("#youtube-embed-logo-icon")) return;

    const logo = document.querySelector("#logo");
    if (!logo || !logo.parentElement) return;

    const btn = createEmbedButton("", logoBlack, () =>
      extractVideoId(location.href)
    );
    btn.id = "youtube-embed-logo-icon";

    logo.parentElement.insertBefore(btn, logo.nextSibling);
  }

  function addIconToPlayer() {
    if (document.querySelector(".ytp-embed-btn")) return;

    const leftControls = document.querySelector(".ytp-left-controls");
    if (!leftControls) return;

    const btn = createEmbedButton("ytp-embed-btn", logoWhite, () =>
      extractVideoId(location.href)
    );

    const playBtn = leftControls.querySelector(".ytp-play-button");
    playBtn?.after(btn);
  }

  const processedVideoIds = new Set();

  // ✅ LIST / RADIO HANDLING (one button per videoId)
  function addIconsToVideoList() {
    document
      .querySelectorAll(
        'a[href^="/watch"], a[href^="https://www.youtube.com/watch"]'
      )
      .forEach((anchor) => {
        const href = anchor.href;

        if (href.includes("&lc=")) return;
        if (anchor.closest("#player") || anchor.closest("#logo")) return;

        const videoId = extractVideoId(href);
        if (!videoId) return;

        // 🔒 GLOBAL de-duplication by videoId
        if (processedVideoIds.has(videoId)) return;
        processedVideoIds.add(videoId);

        // DOM safety check (optional but harmless)
        const next = anchor.nextElementSibling;
        if (next && next.classList.contains("youtube-embed-icon-btn")) return;

        const btn = createEmbedButton("", logoBlack, () => videoId);
        anchor.after(btn);
      });
  }

  function injectButtonToRichGrid(videoItem) {
    const buttonsDiv = videoItem.querySelector("#buttons");
    if (!buttonsDiv || buttonsDiv.dataset.embedAdded) return;

    const videoLink = videoItem.querySelector("#video-title-link");
    if (!videoLink) return;

    const videoId = extractVideoId(videoLink.href);
    if (!videoId) return;

    const btn = createEmbedButton("", logoBlack, () => videoId);
    btn.style.width = "100%";
    btn.style.margin = "0px";
    btn.style.verticalAlign = "middle";

    videoLink.after(btn);
    buttonsDiv.dataset.embedAdded = "true";
  }

  // Observe grid for dynamically loaded videos
  function observeRichGrid() {
    const grid = document.querySelector("ytd-rich-grid-renderer");
    if (!grid) return;

    const observer = new MutationObserver(() => {
      grid
        .querySelectorAll("ytd-rich-item-renderer ytd-rich-grid-media")
        .forEach(injectButtonToRichGrid);
    });

    observer.observe(grid, { childList: true, subtree: true });

    // Initial pass
    grid
      .querySelectorAll("ytd-rich-item-renderer ytd-rich-grid-media")
      .forEach(injectButtonToRichGrid);
  }

  function processAll() {
    addIconNextToYouTubeLogo();
    addIconToPlayer();
    addIconsToVideoList();
    observeRichGrid(); // <-- new
  }

  function init() {
    processAll();

    const observer = new MutationObserver(() => {
      setTimeout(processAll, 300);
    });

    observer.observe(document.body, {
      childList: true,
      subtree: true,
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
