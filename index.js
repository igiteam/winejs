const express = require("express");
const httpProxy = require("http-proxy");
const fs = require("fs").promises;
const path = require("path");
const { createClient } = require("redis");
const axios = require("axios");
const { exec } = require("child_process");
const util = require("util");
const execPromise = util.promisify(exec);
const https = require("https");
const http = require("http");

const app = express();
const server = http.createServer(app);

const proxy = httpProxy.createProxyServer({
  ws: true,
  xfwd: true,
  secure: false,
  changeOrigin: true,
  prependPath: false,
  ignorePath: false,
});

// Serve static files from public directory (including icons)
app.use(express.static("public"));

// Serve icons specifically from /icons path
app.use("/icons", express.static(path.join(__dirname, "public/icons")));

// Proxy KasmVNC static assets
app.use("/dist/:path(.*)", async (req, res) => {
  const target = `https://127.0.0.1:6901/dist/${req.params.path}`;
  try {
    const response = await axios.get(target, {
      responseType: "stream",
      httpsAgent: new https.Agent({ rejectUnauthorized: false }),
    });

    if (response.headers["content-type"]) {
      res.set("Content-Type", response.headers["content-type"]);
    }
    res.set("Cache-Control", "public, max-age=3600");
    response.data.pipe(res);
  } catch (err) {
    console.error(`Failed to proxy ${target}:`, err.message);
    res.status(404).send("Not found");
  }
});

app.use("/vendor/:path(.*)", async (req, res) => {
  const target = `https://127.0.0.1:6901/vendor/${req.params.path}`;
  try {
    const response = await axios.get(target, {
      responseType: "stream",
      httpsAgent: new https.Agent({ rejectUnauthorized: false }),
    });

    if (response.headers["content-type"]) {
      res.set("Content-Type", response.headers["content-type"]);
    }
    response.data.pipe(res);
  } catch (err) {
    res.status(404).send("Not found");
  }
});

app.use("/app/:path(.*)", async (req, res) => {
  const target = `https://127.0.0.1:6901/app/${req.params.path}`;
  try {
    const response = await axios.get(target, {
      responseType: "stream",
      httpsAgent: new https.Agent({ rejectUnauthorized: false }),
    });

    if (response.headers["content-type"]) {
      res.set("Content-Type", response.headers["content-type"]);
    }
    response.data.pipe(res);
  } catch (err) {
    res.status(404).send("Not found");
  }
});

// Package.json endpoint
app.get("/package.json", (req, res) => {
  res.json({
    name: "kasmvnc-client",
    version: "1.0.0",
    description: "KasmVNC Client",
  });
});

// Serve VNC client at root
app.get("/", (req, res) => {
  const target = `https://127.0.0.1:6901/vnc.html`;
  proxy.web(req, res, { target, changeOrigin: true });
});

const APPS_DIR = "/opt/winejs/apps";
const INSTANCES_DIR = "/opt/winejs/kasmvnc-instances";
const PORT = process.env.PORT || 3000;

const redis = createClient({ url: "redis://localhost:6379" });
redis.on("error", (err) => console.log("Redis Client Error", err));

let appRegistry = {};
let portCounter = 6901;

async function loadApps() {
  try {
    const apps = await fs.readdir(APPS_DIR);
    for (const app of apps) {
      const appPath = path.join(APPS_DIR, app);
      const stat = await fs.stat(appPath);
      if (stat.isDirectory()) {
        try {
          const configPath = path.join(appPath, "config.json");
          const configData = await fs.readFile(configPath, "utf8");
          const config = JSON.parse(configData);

          appRegistry[app] = {
            ...config,
            id: app,
            path: appPath,
            port: config.port || portCounter++,
            running: false,
            lastUsed: null,
          };

          console.log(`✅ Loaded app: ${app} on port ${appRegistry[app].port}`);
          console.log(`   Icon path: ${config.icon || "default"}`);
        } catch (err) {
          console.log(`⚠️  No valid config for ${app}:`, err.message);
        }
      }
    }
    console.log(`✅ Total apps loaded: ${Object.keys(appRegistry).length}`);
    await redis.set("appRegistry", JSON.stringify(appRegistry));
  } catch (err) {
    console.error("Error loading apps:", err);
  }
}

async function isInstanceRunning(appName, port) {
  try {
    const response = await axios.get(`https://127.0.0.1:${port}/`, {
      timeout: 5000,
      httpsAgent: new https.Agent({ rejectUnauthorized: false }),
    });
    return true;
  } catch (err) {
    if (err.response) {
      console.log(
        `Health check got status ${err.response.status} - server is running`
      );
      return true;
    }
    console.log(`Health check failed for port ${port}:`, err.message);
    return false;
  }
}

async function startInstance(appName, port) {
  console.log(`🚀 Starting ${appName} on port ${port}...`);
  try {
    await execPromise(`cd ${INSTANCES_DIR}/${appName} && docker-compose up -d`);
    await new Promise((resolve) => setTimeout(resolve, 5000));
    if (appRegistry[appName]) {
      appRegistry[appName].running = true;
      appRegistry[appName].lastUsed = new Date().toISOString();
      await redis.set("appRegistry", JSON.stringify(appRegistry));
    }
    console.log(`✅ ${appName} started successfully`);
    return true;
  } catch (err) {
    console.error(`❌ Failed to start ${appName}:`, err.message);
    return false;
  }
}

app.get("/health", (req, res) => {
  res.json({
    status: "OK",
    apps: Object.keys(appRegistry).length,
    running: Object.values(appRegistry).filter((a) => a.running).length,
    uploads: "/upload",
    downloads: "/download",
  });
});

app.get("/apps", async (req, res) => {
  const apps = {};
  for (const [name, config] of Object.entries(appRegistry)) {
    apps[name] = {
      name: config.name,
      description: config.description,
      category: config.category,
      version: config.version,
      icon: config.icon,
      running: config.running,
    };
  }
  res.json(apps);
});

// Helper function to generate HTML head with proper meta tags
function generateHead(appName, app) {
  const title = app
    ? `${app.name} - WineJS`
    : "WINEJS - Windows Apps in Browser";
  const iconUrl = app && app.icon ? app.icon : "/icons/wine-placeholder.png";
  const fullIconUrl = `https://${req.headers.host}${iconUrl}`;
  const previewUrl = `https://img.sdappnet.cloud/?url=https://${req.headers.host}/${appName}&w=1920&h=1080`;

  return `
    <link rel="icon" href="${iconUrl}" type="image/png">
    <link rel="apple-touch-icon" href="${iconUrl}" sizes="180x180">
    <link rel="icon" type="image/png" href="${iconUrl}" sizes="192x192">
    <link rel="icon" type="image/png" href="${iconUrl}" sizes="512x512">
    <meta itemprop="name" content="${title}">
    <meta itemprop="image" content="${previewUrl}">
    <meta property="og:title" content="${title}">
    <meta property="og:image" content="${previewUrl}">
    <meta property="og:url" content="https://${req.headers.host}/${appName}">
    <meta property="og:type" content="website">
    <meta name="twitter:title" content="${title}">
    <meta name="twitter:image" content="${previewUrl}">
    <meta name="twitter:card" content="summary_large_image">
    <link rel="apple-touch-icon" href="${iconUrl}" sizes="180x180">
    <title>${title}</title>
  `;
}

// Dynamic favicon based on app name
app.get("/:appName/favicon.ico", async (req, res) => {
  const appName = req.params.appName;
  const app = appRegistry[appName];

  // Try app-specific icon first
  let iconPath = path.join(__dirname, "public/icons", `${appName}.jpg`);

  if (!fs.existsSync(iconPath)) {
    // Try from config
    if (app && app.icon) {
      iconPath = path.join(__dirname, "public", app.icon);
    } else {
      // Fallback to generic wine icon
      iconPath = path.join(__dirname, "public/icons/wine-placeholder.png");
    }
  }

  res.sendFile(iconPath);
});

// Also handle root favicon
app.get("/favicon.ico", (req, res) => {
  res.sendFile(path.join(__dirname, "public/icons/milkshape.jpg"));
});

// Main translator - routes /appname to KasmVNC with meta injection
app.get("/:appName*", async (req, res, next) => {
  const appName = req.params.appName;

  // Special case: don't handle WebSocket paths
  if (req.url.includes("/websockify")) {
    return next();
  }

  // Skip special paths
  if (
    appName === "upload" ||
    appName === "download" ||
    appName === "health" ||
    appName === "apps" ||
    appName === "api" ||
    appName === "icons" ||
    appName === "package.json"
  ) {
    return next();
  }

  const app = appRegistry[appName];

  if (!app) {
    return res.status(404).send(`
      <html>
        <head><title>App Not Found</title></head>
        <body style="font-family: Arial; background: #1a1a1a; color: white; text-align: center; padding: 50px;">
          <h1>❌ App Not Found</h1>
          <p>The app "${appName}" is not installed.</p>
          <p>Available apps: ${Object.keys(appRegistry).join(", ")}</p>
          <p><a href="/" style="color: #00ff9d;">Go Home</a></p>
        </body>
      </html>
    `);
  }

  const running = await isInstanceRunning(appName, app.port);
  if (!running) {
    const started = await startInstance(appName, app.port);
    if (!started) {
      return res.status(500).send("Failed to start app instance");
    }
  }

  app.lastUsed = new Date().toISOString();

  // Intercept the response to inject custom head
  const target = `https://127.0.0.1:${app.port}`;

  // Make request to KasmVNC
  try {
    const response = await axios.get(`${target}/vnc.html`, {
      httpsAgent: new https.Agent({ rejectUnauthorized: false }),
      responseType: "text",
    });

    let html = response.data;

    // Generate custom head with app-specific metadata
    const customHead = generateHead(appName, app, req.headers.host);

    // Replace the head section
    html = html.replace("<head>", `<head>${customHead}`);

    res.send(html);
  } catch (err) {
    // Fallback to proxy if fetch fails
    req.url = "/vnc.html";
    proxy.web(req, res, { target, changeOrigin: true });
  }
});

// WebSocket support for VNC - Attached to server, not app!
server.on("upgrade", (req, socket, head) => {
  console.log("🔥🔥🔥 WebSocket upgrade request received! 🔥🔥🔥");
  console.log("URL:", req.url);

  // Extract the app name from the path
  const pathParts = req.url.split("/").filter((p) => p.length > 0);
  let appName = null;
  let targetPath = req.url;

  // Handle different path patterns
  if (pathParts.length > 0) {
    // Check if first part is an app name
    if (appRegistry[pathParts[0]]) {
      appName = pathParts[0];
      // Remove app name from path for target
      targetPath = "/" + pathParts.slice(1).join("/");
      console.log(
        `Found app name in path: ${appName}, target path: ${targetPath}`
      );
    }
    // Check if it's a direct websockify path
    else if (pathParts[0] === "websockify") {
      appName = "milkshape";
      targetPath = req.url;
      console.log("Direct websockify path, defaulting to milkshape");
    }
  }

  // If no app name found, default to milkshape
  if (!appName) {
    appName = "milkshape";
    console.log("No app found in path, defaulting to milkshape");
  }

  const app = appRegistry[appName];
  if (!app) {
    console.log(`❌ No app found for WebSocket: ${appName}`);
    socket.write("HTTP/1.1 404 Not Found\r\n\r\n");
    socket.destroy();
    return;
  }

  console.log(
    `🎯 Proxying WebSocket for ${appName} to port ${app.port} with path ${targetPath}`
  );

  // Ensure the target path starts with /
  if (!targetPath.startsWith("/")) {
    targetPath = "/" + targetPath;
  }

  proxy.ws(req, socket, head, {
    target: `wss://127.0.0.1:${app.port}`,
    path: targetPath,
    secure: false,
    ws: true,
    headers: {
      Host: `127.0.0.1:${app.port}`,
      Origin: `https://${req.headers.host}`,
      Upgrade: "websocket",
      Connection: "Upgrade",
    },
  });
});

// Add error handler for WebSocket proxy
proxy.on("error", (err, req, res) => {
  console.error("Proxy error:", err);
  if (res && !res.headersSent) {
    try {
      if (typeof res.writeHead === "function") {
        res.writeHead(500, { "Content-Type": "text/plain" });
        res.end("Proxy error: " + err.message);
      }
    } catch (e) {
      console.error("Error sending response:", e);
    }
  }
});

proxy.on("ws:error", (err, req, socket) => {
  console.error("WebSocket proxy error:", err);
  if (socket && !socket.destroyed) {
    socket.destroy();
  }
});

proxy.on("open", (proxySocket) => {
  console.log("WebSocket connection opened");
});

proxy.on("close", (res, socket, head) => {
  console.log("WebSocket connection closed");
});

// Catch-all for other requests - THIS MUST BE LAST
app.use("/:any", (req, res, next) => {
  if (appRegistry[req.params.any]) {
    return next();
  }
  const target = `https://127.0.0.1:6901${req.url}`;
  proxy.web(req, res, { target, changeOrigin: true });
});

async function start() {
  await redis.connect();
  await loadApps();
  // ADD THIS DEBUG LINE
  console.log("🔍 Apps in registry:", Object.keys(appRegistry));
  if (Object.keys(appRegistry).length === 0) {
    console.error("❌ NO APPS LOADED! Check APPS_DIR path");
    console.log(`APPS_DIR = ${APPS_DIR}`);
  }
  // Use the server instance to listen, not app
  server.listen(PORT, "0.0.0.0", () => {
    console.log(`✅ WINEJS Translator running on port ${PORT}`);
    console.log(`   Apps loaded: ${Object.keys(appRegistry).length}`);
    console.log(`   Upload at: /upload (proxied to DumbDrop)`);
    console.log(`   Download at: /download (proxied to FileServer)`);
  });
}

start().catch(console.error);

//WEBSOCKET FIXES
// 1. Attached WebSocket handler to HTTP server, NOT Express app
// // BEFORE (WRONG):
// app.on("upgrade", (req, socket, head) => { ... })

// // AFTER (CORRECT):
// const server = http.createServer(app);
// server.on("upgrade", (req, socket, head) => { ... })

// Why: Express doesn't handle WebSocket upgrades - the raw HTTP server does. The upgrade event was never firing when attached to app!
// 2. Created server explicitly
// // BEFORE:
// app.listen(PORT, "0.0.0.0", () => { ... })

// // AFTER:
// const server = http.createServer(app);
// server.listen(PORT, "0.0.0.0", () => { ... })

// Why: Need the server instance to attach the upgrade handler
// 3. Fixed path extraction logic
// // Better path parsing that handles both:
// // /milkshape/websockify  -> appName = "milkshape", targetPath = "/websockify"
// // /websockify            -> appName = "milkshape" (default), targetPath = "/websockify"

// 4. Added proper target path construction
// // Ensures paths start with / and are formatted correctly for the target
// if (!targetPath.startsWith('/')) {
//   targetPath = '/' + targetPath;
// }

// 5. Added http module require
// const http = require("http");  // Needed to create the server

// That's it! The WebSocket was always working at the container level (we saw the 101 handshake earlier), but the translator wasn't catching the upgrade event because it was attached to the wrong object. Moving it to the HTTP server was the magic fix!
// Now your browser can do the WebSocket handshake through:
// Browser -> nginx -> translator (port 3000) -> MilkShape container (port 6901)
