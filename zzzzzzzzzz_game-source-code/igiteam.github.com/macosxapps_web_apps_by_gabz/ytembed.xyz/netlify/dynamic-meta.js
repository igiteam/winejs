import { HTMLRewriter } from "https://raw.githubusercontent.com/worker-tools/html-rewriter/master/index.ts";

const fallbackImageUrl = "https://cdn.sdappnet.cloud/rtx/images/ytembed.png";
const defaultTitle = "YouTube Full-Screen";

class MetaRewriter {
  constructor(imageUrl, videoTitle) {
    this.imageUrl = imageUrl;
    this.videoTitle = videoTitle;
  }

  element(element) {
    // Update Open Graph image
    if (element.getAttribute("property") === "og:image") {
      element.setAttribute("content", this.imageUrl);
    }

    // Update Twitter card image
    if (element.getAttribute("name") === "twitter:image") {
      element.setAttribute("content", this.imageUrl);
    }

    // Update Open Graph title
    if (element.getAttribute("property") === "og:title") {
      element.setAttribute("content", this.videoTitle);
    }

    // Update Twitter card title
    if (element.getAttribute("name") === "twitter:title") {
      element.setAttribute("content", this.videoTitle);
    }
  }
}

class TitleRewriter {
  constructor(videoTitle) {
    this.videoTitle = videoTitle;
  }

  element(element) {
    // Update the main HTML title tag
    element.setInnerContent(this.videoTitle);
  }
}

// URL encoding/decoding functions
function encodeYouTubeUrl(youtubeUrl) {
  const videoId = extractYouTubeId(youtubeUrl);
  if (!videoId) return null;
  return btoa(videoId)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function decodeYouTubeCode(shortCode) {
  let base64 = shortCode.replace(/-/g, "+").replace(/_/g, "/");
  while (base64.length % 4) {
    base64 += "=";
  }
  return atob(base64);
}

function extractYouTubeId(url) {
  const patterns = [
    /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([^&\?\/\s]{11})/,
    /^([^&\?\/\s]{11})$/,
  ];

  for (const pattern of patterns) {
    const match = url.match(pattern);
    if (match) return match[1];
  }
  return null;
}

// Fetch YouTube video title
async function fetchYouTubeTitle(videoId) {
  try {
    // Try to fetch from YouTube's oEmbed endpoint
    const response = await fetch(
      `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=${videoId}&format=json`
    );

    if (response.ok) {
      const data = await response.json();
      return data.title || `YouTube Video: ${videoId}`;
    }

    // Fallback: Try to fetch the page and extract title
    const pageResponse = await fetch(
      `https://www.youtube.com/watch?v=${videoId}`
    );
    const html = await pageResponse.text();

    // Extract title from meta tag
    const titleMatch = html.match(
      /<meta property="og:title" content="([^"]*)"/
    );
    if (titleMatch) {
      return titleMatch[1];
    }

    // Extract title from the page title
    const titleTagMatch = html.match(/<title>([^<]*)<\/title>/);
    if (titleTagMatch) {
      return titleTagMatch[1].replace(" - YouTube", "").trim();
    }
  } catch (error) {
    console.error("Failed to fetch YouTube title:", error);
  }

  return `YouTube Video: ${videoId}`;
}

export default async (request, context) => {
  const url = new URL(request.url);
  const pathname = url.pathname;

  // Get the code from query parameters
  const urlParams = url.searchParams;
  const code = urlParams.keys().next().value;

  let imageUrl = fallbackImageUrl;
  let videoTitle = defaultTitle;

  // Try to extract YouTube video ID from URL parameter
  if (code && code.length > 0) {
    try {
      const decoded = decodeYouTubeCode(code);
      const videoId = extractYouTubeId(decoded) || decoded;

      if (videoId && videoId.length === 11) {
        // Use YouTube thumbnail as meta image
        imageUrl = `https://i.ytimg.com/vi/${videoId}/maxresdefault.jpg`;

        // Fetch the YouTube video title
        videoTitle = await fetchYouTubeTitle(videoId);
      }
    } catch (e) {
      console.error("Failed to decode URL parameter:", e);
    }
  }

  const response = await context.next();
  if (!response.headers.get("content-type")?.includes("text/html")) {
    return response;
  }

  // Update meta tags and title
  return new HTMLRewriter()
    .on("meta[property='og:image']", new MetaRewriter(imageUrl, videoTitle))
    .on("meta[name='twitter:image']", new MetaRewriter(imageUrl, videoTitle))
    .on("meta[property='og:title']", new MetaRewriter(imageUrl, videoTitle))
    .on("meta[name='twitter:title']", new MetaRewriter(imageUrl, videoTitle))
    .on("title", new TitleRewriter(videoTitle))
    .transform(response);
};

export const config = {
  path: "/*",
};
