import { spawn } from "node:child_process";
import { randomBytes, randomUUID } from "node:crypto";
import { promises as fs } from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const tilePath = path.resolve(scriptDir, "..", "sharptools", "lg-tv-remote.html");
const smartThingsCli = process.env.SMARTTHINGS_CLI
  || (process.platform === "win32" ? "smartthings.exe" : "smartthings");
const profile = process.env.SMARTTHINGS_PROFILE || "oauth";
const port = Number(process.env.LG_TV_REMOTE_PORT || "8787");
const remoteCapability = "mirrordouble43237.lgTvRemote";
const accessToken = randomBytes(24).toString("hex");
const cacheDurationMs = 10_000;
const bodyLimitBytes = 4096;
const commandTimeoutMs = 20_000;
const allowedButtons = new Set([
  "LEFT", "RIGHT", "UP", "DOWN",
  "RED", "GREEN", "YELLOW", "BLUE",
  "CHANNELUP", "CHANNELDOWN", "VOLUMEUP", "VOLUMEDOWN",
  "PLAY", "PAUSE", "STOP", "REWIND", "FASTFORWARD",
  "ASTERISK", "BACK", "EXIT", "ENTER",
  "AMAZON", "NETFLIX", "DISNEY_PLUS", "COUPANG_PLAY", "TVING", "LAFTEL",
  "3D_MODE", "AD", "ASPECT_RATIO", "CC", "DASH", "GUIDE", "HOME", "INFO",
  "INPUT_HUB", "LIST", "LIVE_ZOOM", "MAGNIFIER_ZOOM", "MENU", "MUTE",
  "MYAPPS", "POWER", "PROGRAM", "QMENU", "RECENT", "RECORD", "SAP",
  "SCREEN_REMOTE", "TELETEXT", "TEXTOPTION",
  "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"
]);

if (!Number.isInteger(port) || port < 1024 || port > 65535) {
  throw new Error("LG_TV_REMOTE_PORT must be an integer between 1024 and 65535.");
}

let cachedDevices = [];
let cachedDevicesAt = 0;
let commandQueue = Promise.resolve();

function runSmartThings(args) {
  return new Promise((resolve, reject) => {
    const child = spawn(smartThingsCli, args, {
      env: { ...process.env, SMARTTHINGS_PROFILE: profile },
      windowsHide: true
    });
    let stdout = "";
    let stderr = "";
    let settled = false;

    const timeout = setTimeout(() => {
      if (settled) return;
      settled = true;
      child.kill();
      reject(new Error("SmartThings CLI command timed out."));
    }, commandTimeoutMs);

    child.stdout.on("data", chunk => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", chunk => {
      stderr += chunk.toString();
    });
    child.on("error", error => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    });
    child.on("close", code => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (code === 0) {
        resolve(stdout);
      } else {
        reject(new Error(stderr.trim() || `SmartThings CLI exited with code ${code}.`));
      }
    });
  });
}

async function getDevices(forceRefresh = false) {
  if (!forceRefresh && Date.now() - cachedDevicesAt < cacheDurationMs) {
    return cachedDevices;
  }

  const output = await runSmartThings([
    "devices",
    "--capability",
    remoteCapability,
    "--profile",
    profile,
    "--json"
  ]);
  const result = JSON.parse(output);
  if (!Array.isArray(result)) {
    throw new Error("SmartThings returned an invalid device list.");
  }

  cachedDevices = result
    .filter(device => typeof device.deviceId === "string")
    .map(device => ({
      id: device.deviceId,
      label: typeof device.label === "string" && device.label
        ? device.label
        : (device.deviceModel || "LG webOS TV"),
      model: typeof device.deviceModel === "string" ? device.deviceModel : ""
    }))
    .sort((left, right) => left.label.localeCompare(right.label));
  cachedDevicesAt = Date.now();
  return cachedDevices;
}

function isPrivateClient(address) {
  const ip = (address || "").replace(/^::ffff:/, "");
  if (ip === "127.0.0.1" || ip === "::1" || ip.startsWith("fc") || ip.startsWith("fd") || ip.startsWith("fe80:")) {
    return true;
  }

  const octets = ip.split(".").map(Number);
  if (octets.length !== 4 || octets.some(value => !Number.isInteger(value) || value < 0 || value > 255)) {
    return false;
  }
  return octets[0] === 10
    || (octets[0] === 192 && octets[1] === 168)
    || (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31)
    || (octets[0] === 169 && octets[1] === 254);
}

function sendJson(response, statusCode, value) {
  response.writeHead(statusCode, {
    "Cache-Control": "no-store",
    "Content-Type": "application/json; charset=utf-8",
    "X-Content-Type-Options": "nosniff"
  });
  response.end(JSON.stringify(value));
}

function createLocalBridgeScript() {
  const basePath = JSON.stringify(`/${accessToken}`);
  return `<script>
window.LG_TV_REMOTE_LOCAL = true;
(function () {
  var basePath = ${basePath};
  var root = document.getElementById("lg-tv-remote");
  var picker = document.getElementById("local-device-picker");
  var select = document.getElementById("local-tv-select");
  root.dataset.localMode = "true";
  picker.hidden = false;

  function makeTv(device) {
    return {
      name: device.label,
      attributes: {
        supportedInputSources: { value: [] },
        inputSource: { value: "" }
      },
      sendCommand: function (command, args) {
        return fetch(basePath + "/api/command", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            deviceId: device.id,
            command: command,
            args: Array.isArray(args) ? args : []
          })
        }).then(function (response) {
          return response.json().then(function (result) {
            if (!response.ok) {
              throw new Error(result.error || "SmartThings 명령 전송 실패");
            }
            return result;
          });
        });
      }
    };
  }

  window.stio = {
    ready: function (callback) {
      fetch(basePath + "/api/devices", { cache: "no-store" })
        .then(function (response) {
          return response.json().then(function (result) {
            if (!response.ok) {
              throw new Error(result.error || "LG TV 목록을 가져오지 못했습니다");
            }
            return result;
          });
        })
        .then(function (result) {
          var devices = Array.isArray(result.devices) ? result.devices : [];
          select.replaceChildren();

          if (devices.length === 0) {
            var emptyOption = document.createElement("option");
            emptyOption.value = "";
            emptyOption.textContent = "SmartThings에 등록된 LG TV가 없습니다";
            select.appendChild(emptyOption);
            select.disabled = true;
            callback({ settings: { tv: null } });
            return;
          }

          devices.forEach(function (device) {
            var option = document.createElement("option");
            option.value = device.id;
            option.textContent = device.label + (device.model && device.label.indexOf(device.model) === -1
              ? " (" + device.model + ")"
              : "");
            select.appendChild(option);
          });

          var requestedId = new URLSearchParams(window.location.search).get("device");
          var selected = devices.find(function (device) { return device.id === requestedId; }) || devices[0];
          select.value = selected.id;
          select.disabled = false;
          select.addEventListener("change", function () {
            var url = new URL(window.location.href);
            url.searchParams.set("device", select.value);
            window.location.assign(url.toString());
          });

          callback({ settings: { tv: makeTv(selected) } });
        })
        .catch(function (error) {
          console.error("Local LG TV remote initialization failed", error);
          select.disabled = true;
          callback({ settings: { tv: null } });
        });
    }
  };
})();
</script>`;
}

function buildLocalPage(tileSource) {
  const sharpToolsScript = '<script src="https://cdn.sharptools.io/js/custom-tiles/0.2.1/stio.js"></script>';
  if (!tileSource.includes(sharpToolsScript)) {
    throw new Error("Could not locate the SharpTools adapter in the remote tile.");
  }

  const styleMatch = tileSource.match(/<style>[\s\S]*?<\/style>/i);
  if (!styleMatch) {
    throw new Error("Could not locate the remote tile styles.");
  }
  const bodyMarkup = tileSource
    .replace(styleMatch[0], "")
    .replace(sharpToolsScript, createLocalBridgeScript());

  return `<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="theme-color" content="#141415">
  <title>LG TV 브라우저 리모컨</title>
  ${styleMatch[0]}
</head>
<body>
${bodyMarkup}
</body>
</html>`;
}

async function readJsonBody(request) {
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > bodyLimitBytes) {
      const error = new Error("Request body is too large.");
      error.statusCode = 413;
      throw error;
    }
    chunks.push(chunk);
  }

  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    const error = new Error("Invalid JSON request.");
    error.statusCode = 400;
    throw error;
  }
}

function queueCommand(task) {
  const current = commandQueue.then(task, task);
  commandQueue = current.catch(() => {});
  return current;
}

async function executeDeviceCommand(deviceId, command, args) {
  const inputPath = path.join(os.tmpdir(), `lg-tv-command-${randomUUID()}.json`);
  const payload = {
    commands: [{
      component: "main",
      capability: remoteCapability,
      command,
      arguments: args
    }]
  };

  await fs.writeFile(inputPath, JSON.stringify(payload), { encoding: "utf8", flag: "wx" });
  try {
    await runSmartThings([
      "devices:commands",
      deviceId,
      "--input",
      inputPath,
      "--profile",
      profile
    ]);
  } finally {
    try {
      await fs.rm(inputPath, { force: true });
    } catch (error) {
      console.warn("Could not remove temporary command file:", error.message);
    }
  }
}

const tileSource = await fs.readFile(tilePath, "utf8");
const page = buildLocalPage(tileSource);

async function handleRequest(request, response) {
  if (!isPrivateClient(request.socket.remoteAddress)) {
    sendJson(response, 403, { error: "Local network access only." });
    return;
  }

  const requestUrl = new URL(request.url || "/", "http://localhost");
  const segments = requestUrl.pathname.split("/").filter(Boolean);
  if (segments[0] !== accessToken) {
    sendJson(response, 404, { error: "Not found." });
    return;
  }
  const route = `/${segments.slice(1).join("/")}`;

  if (request.method === "GET" && route === "/") {
    response.writeHead(200, {
      "Cache-Control": "no-store",
      "Content-Security-Policy": "default-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
      "Content-Type": "text/html; charset=utf-8",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY"
    });
    response.end(page);
    return;
  }

  if (request.method === "GET" && route === "/api/devices") {
    const devices = await getDevices(true);
    sendJson(response, 200, { devices });
    return;
  }

  if (request.method === "POST" && route === "/api/command") {
    const body = await readJsonBody(request);
    const deviceId = body && body.deviceId;
    const command = body && body.command;
    const args = body && body.args;
    if (typeof deviceId !== "string" || !/^[0-9a-f-]{36}$/i.test(deviceId)) {
      sendJson(response, 400, { error: "Invalid device ID." });
      return;
    }
    if (!Array.isArray(args) || args.length !== 1) {
      sendJson(response, 400, { error: "Invalid command arguments." });
      return;
    }
    if (command === "pressButton" && typeof args[0] === "string" && allowedButtons.has(args[0])) {
      // Allowed remote button.
    } else if (command === "selectRemoteInputSource"
      && typeof args[0] === "string" && args[0].length > 0 && args[0].length <= 64) {
      // Allowed input source command.
    } else {
      sendJson(response, 400, { error: "Unsupported remote command." });
      return;
    }

    const devices = await getDevices();
    if (!devices.some(device => device.id === deviceId)) {
      sendJson(response, 404, { error: "LG TV is not available in SmartThings." });
      return;
    }

    await queueCommand(() => executeDeviceCommand(deviceId, command, args));
    sendJson(response, 200, { ok: true });
    return;
  }

  sendJson(response, 404, { error: "Not found." });
}

function getLanAddresses() {
  return Object.values(os.networkInterfaces())
    .flat()
    .filter(item => item && !item.internal && (item.family === "IPv4" || item.family === 4))
    .map(item => item.address);
}

await getDevices(true);
const server = http.createServer((request, response) => {
  handleRequest(request, response).catch(error => {
    console.error("Local browser remote request failed:", error.message);
    if (!response.headersSent) {
      sendJson(response, error.statusCode || 502, {
        error: error.statusCode ? error.message : "SmartThings command failed. Check the CLI profile and Hub connection."
      });
    } else {
      response.destroy();
    }
  });
});

server.listen(port, "0.0.0.0", () => {
  const lanAddresses = getLanAddresses();
  console.log(`LG TV browser remote is running on port ${port}.`);
  console.log(`Open on this PC: http://127.0.0.1:${port}/${accessToken}/`);
  for (const address of lanAddresses) {
    console.log(`Open on a device on the same Wi-Fi: http://${address}:${port}/${accessToken}/`);
  }
  console.log("Keep this terminal open. Stop the server with Ctrl+C, and do not share the access URL.");
});
