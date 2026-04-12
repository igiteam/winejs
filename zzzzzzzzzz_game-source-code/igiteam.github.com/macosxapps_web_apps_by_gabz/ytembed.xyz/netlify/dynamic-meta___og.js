import { HTMLRewriter } from "https://raw.githubusercontent.com/worker-tools/html-rewriter/master/index.ts";

const fallbackImageUrl = "https://cdn.sdappnet.cloud/rtx/images/ytembed.png";

class MetaRewriter {
  constructor(imageUrl) {
    this.imageUrl = imageUrl;
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

export default async (request, context) => {
  const url = new URL(request.url);
  const pathname = url.pathname;

  // Get the code from query parameters
  const urlParams = url.searchParams;
  const code = urlParams.keys().next().value;

  let imageUrl = fallbackImageUrl;

  // Try to extract YouTube video ID from URL parameter
  if (code && code.length > 0) {
    try {
      const decoded = decodeYouTubeCode(code);
      const videoId = extractYouTubeId(decoded) || decoded;
      if (videoId && videoId.length === 11) {
        // Use YouTube thumbnail as meta image
        imageUrl = `https://i.ytimg.com/vi/${videoId}/maxresdefault.jpg`;
      }
    } catch (e) {
      console.error("Failed to decode URL parameter:", e);
    }
  }

  const response = await context.next();
  if (!response.headers.get("content-type")?.includes("text/html")) {
    return response;
  }

  // Update only the meta image tags
  return new HTMLRewriter()
    .on("meta[property='og:image']", new MetaRewriter(imageUrl))
    .on("meta[name='twitter:image']", new MetaRewriter(imageUrl))
    .transform(response);
};

export const config = {
  path: "/*",
};
