const { app, BrowserWindow, ipcMain, shell } = require('electron')
const path = require('path')
const fs = require('fs')
const https = require('https')
const http = require('http')
const net = require('net')
const crypto = require('crypto')
const { spawn } = require('child_process')
const os = require('os')

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const MANIFEST_URL     = 'https://raw.githubusercontent.com/blueavlo-hash/EraOnlinePort/main/public/launcher/latest.json'
const NEWS_URL         = 'https://raw.githubusercontent.com/blueavlo-hash/EraOnlinePort/main/public/launcher/news.json'
const LAUNCHER_YML_URL = 'https://raw.githubusercontent.com/blueavlo-hash/EraOnlinePort/main/public/launcher/latest.yml'
const INSTALL_DIR  = path.join(app.getPath('appData'), 'EraOnline')
const GAME_EXE     = path.join(INSTALL_DIR, 'EraOnline.exe')
const VERSION_FILE = path.join(INSTALL_DIR, 'version.txt')

let win = null

// ---------------------------------------------------------------------------
// Window
// ---------------------------------------------------------------------------
function createWindow() {
  win = new BrowserWindow({
    width: 960,
    height: 580,
    resizable: false,
    frame: false,
    transparent: false,
    backgroundColor: '#0d0a05',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    icon: path.join(__dirname, '..', 'assets', 'icon.ico'),
  })

  win.loadFile(path.join(__dirname, 'index.html'))

  // win.webContents.openDevTools({ mode: 'detach' })
}

app.whenReady().then(() => {
  createWindow()
  setupLauncherUpdateCheck()
})
app.on('window-all-closed', () => app.quit())

// ---------------------------------------------------------------------------
// Launcher self-update — manual HTTPS, no electron-updater
// ---------------------------------------------------------------------------
// electron-updater has a documented issue where none of its events fire on
// certain Windows NSIS installs, leaving the UI stuck forever. This replaces
// it with a plain HTTPS fetch of latest.yml, version compare, and NSIS /S.

let _resolveUpdateCheck = null
const _updateCheckPromise = new Promise((resolve) => { _resolveUpdateCheck = resolve })
const _resolveOnce = (() => {
  let settled = false
  return (result) => { if (!settled) { settled = true; _resolveUpdateCheck(result) } }
})()

function setupLauncherUpdateCheck() {
  // Hard deadline — unblock the renderer after 10s even if GitHub is down
  const timeoutHandle = setTimeout(() => _resolveOnce({ upToDate: true }), 10000)

  _runLauncherUpdateCheck(timeoutHandle).catch(() => {
    clearTimeout(timeoutHandle)
    _resolveOnce({ upToDate: true })
  })
}

async function _runLauncherUpdateCheck(timeoutHandle) {
  const ymlText = await fetchText(LAUNCHER_YML_URL, 9000)
  const info    = parseLatestYml(ymlText)

  if (info.version === app.getVersion()) {
    clearTimeout(timeoutHandle)
    _resolveOnce({ upToDate: true })
    return
  }

  // Tell the renderer an update is available — it will show the download UI
  clearTimeout(timeoutHandle)
  _resolveOnce({ upToDate: false, version: info.version })

  // Download + install runs concurrently; progress events update the renderer
  await _downloadAndInstallLauncher(info)
}

// ---------------------------------------------------------------------------
// Parse electron-builder's latest.yml (no js-yaml dependency needed)
// ---------------------------------------------------------------------------
function parseLatestYml(text) {
  const get = (key) => {
    // Match only unindented keys (col 0) to avoid the nested files: block
    const m = text.match(new RegExp(`^${key}:\\s*(.+)$`, 'm'))
    if (!m) throw new Error(`latest.yml: missing field "${key}"`)
    return m[1].trim().replace(/^['"]|['"]$/g, '')
  }
  const version = get('version')
  const sha512  = get('sha512')
  const url     = get('path')
  if (!/^\d+\.\d+/.test(version))      throw new Error(`latest.yml: bad version "${version}"`)
  if (sha512.length < 80)               throw new Error('latest.yml: sha512 looks truncated')
  if (!url.startsWith('https://'))      throw new Error(`latest.yml: path not https: "${url}"`)
  return { version, sha512, url }
}

// ---------------------------------------------------------------------------
// Download, verify sha512, run NSIS /S, quit
// ---------------------------------------------------------------------------
async function _downloadAndInstallLauncher({ version, sha512, url }) {
  const tmpPath = path.join(os.tmpdir(), `EraOnlineLauncherSetup-${version}.exe`)
  try {
    let lastPct = -1
    const buf = await downloadWithProgress(url, (received, total) => {
      const pct = total > 0 ? Math.round(received / total * 100) : 0
      if (pct !== lastPct) {
        lastPct = pct
        win?.webContents.send('launcher-update-progress', {
          phase: `Downloading launcher v${version}... ${pct}%`,
        })
      }
    })

    win?.webContents.send('launcher-update-progress', { phase: 'Verifying...' })
    const digest = crypto.createHash('sha512').update(buf).digest('base64')
    if (digest !== sha512) throw new Error('SHA-512 mismatch — download may be corrupt')

    fs.writeFileSync(tmpPath, buf)
    win?.webContents.send('launcher-update-progress', { phase: 'Installing...' })

    const child = spawn(tmpPath, ['/S'], { detached: true, stdio: 'ignore', cwd: os.tmpdir() })
    child.unref()
    await new Promise(r => setTimeout(r, 500))
    app.quit()

  } catch (err) {
    try { if (fs.existsSync(tmpPath)) fs.unlinkSync(tmpPath) } catch {}
    console.error('[launcher-update] failed:', err.message)
    win?.webContents.send('launcher-update-progress', {
      phase: `Update failed: ${err.message}. Restart to retry.`,
    })
  }
}

// ---------------------------------------------------------------------------
// IPC handlers
// ---------------------------------------------------------------------------
ipcMain.handle('get-version',           () => app.getVersion())
ipcMain.handle('check-launcher-update', () => _updateCheckPromise)

// ---------------------------------------------------------------------------
// IPC: window controls
// ---------------------------------------------------------------------------
ipcMain.on('window-minimize', () => win?.minimize())
ipcMain.on('window-close',    () => app.quit())

// ---------------------------------------------------------------------------
// IPC: fetch manifest + check for game update
// ---------------------------------------------------------------------------
ipcMain.handle('check-update', async () => {
  try {
    const manifest = await fetchJson(MANIFEST_URL)
    const installedVersion = fs.existsSync(VERSION_FILE)
      ? fs.readFileSync(VERSION_FILE, 'utf8').trim()
      : null
    return {
      ok: true,
      manifest,
      installedVersion,
      needsUpdate: installedVersion !== manifest.version,
    }
  } catch (e) {
    return { ok: false, error: e.message }
  }
})

// ---------------------------------------------------------------------------
// IPC: download + install game update
// ---------------------------------------------------------------------------
ipcMain.handle('install-update', async (_event, manifest) => {
  try {
    fs.mkdirSync(INSTALL_DIR, { recursive: true })

    const parts = manifest.download_parts
    const tmpZip = path.join(os.tmpdir(), `EraOnline-${manifest.version}.zip`)

    let totalBytes = 0
    const chunks = []
    for (let i = 0; i < parts.length; i++) {
      const url = parts[i]
      const data = await downloadWithProgress(url, (received, total) => {
        const partFraction = i / parts.length
        const partSize     = 1 / parts.length
        const overall = partFraction + partSize * (received / (total || 1))
        win?.webContents.send('download-progress', {
          percent: Math.round(overall * 100),
          received: totalBytes + received,
          total: total * parts.length,
          speed: 0,
        })
      })
      chunks.push(data)
      totalBytes += data.length
    }

    const combined = Buffer.concat(chunks)
    fs.writeFileSync(tmpZip, combined)

    win?.webContents.send('download-progress', { percent: 100, phase: 'Extracting...' })
    const tmpExtract = path.join(os.tmpdir(), `EraOnline-extract-${Date.now()}`)
    if (fs.existsSync(tmpExtract)) fs.rmSync(tmpExtract, { recursive: true, force: true })
    await extractZip(tmpZip, tmpExtract)
    fs.unlinkSync(tmpZip)

    const gameDir = findFileDir(tmpExtract, 'EraOnline.exe')
    if (!gameDir) throw new Error('EraOnline.exe not found in downloaded package.')

    fs.mkdirSync(INSTALL_DIR, { recursive: true })
    win?.webContents.send('download-progress', { percent: 100, phase: 'Installing...' })
    await copyDir(gameDir, INSTALL_DIR)
    fs.rmSync(tmpExtract, { recursive: true, force: true })

    fs.writeFileSync(VERSION_FILE, manifest.version, 'utf8')

    if (!fs.existsSync(GAME_EXE)) {
      return { ok: false, error: 'EraOnline.exe was not found after installation. It may have been blocked by antivirus — try adding an exclusion for ' + INSTALL_DIR }
    }

    return { ok: true }
  } catch (e) {
    return { ok: false, error: e.message }
  }
})

// ---------------------------------------------------------------------------
// IPC: verify game install
// ---------------------------------------------------------------------------
ipcMain.handle('verify-install', () => {
  return { installed: fs.existsSync(GAME_EXE) }
})

// ---------------------------------------------------------------------------
// IPC: launch game
// ---------------------------------------------------------------------------
ipcMain.handle('launch-game', async (_event, { username, token, serverAddress, serverPort, expectedVersion }) => {
  if (!fs.existsSync(GAME_EXE)) {
    return { ok: false, error: 'Game not installed. Click Update to download.' }
  }
  const installedVersion = fs.existsSync(VERSION_FILE)
    ? fs.readFileSync(VERSION_FILE, 'utf8').trim() : null
  if (expectedVersion && installedVersion !== expectedVersion) {
    return { ok: false, error: 'Game client is outdated. Click Update before launching.' }
  }
  const args = []
  if (username)      args.push('--username',       username)
  if (token)         args.push('--token',           token)
  if (serverAddress) args.push('--server-address',  serverAddress)
  if (serverPort)    args.push('--server-port',     String(serverPort))

  const child = spawn(GAME_EXE, args, { detached: true, stdio: 'ignore', cwd: INSTALL_DIR })
  child.unref()
  return { ok: true }
})

// ---------------------------------------------------------------------------
// IPC: server status — TCP reachability check on the game port
// ---------------------------------------------------------------------------
ipcMain.handle('get-server-status', (_event, host, port) => {
  return new Promise((resolve) => {
    const socket = new net.Socket()
    let done = false
    const finish = (online) => {
      if (done) return
      done = true
      socket.destroy()
      resolve({ ok: true, online, players: 0, max: 0 })
    }
    socket.setTimeout(3000)
    socket.once('connect',  () => finish(true))
    socket.once('error',    () => finish(false))
    socket.once('timeout',  () => finish(false))
    socket.connect(port || 7777, host || '127.0.0.1')
  })
})

// ---------------------------------------------------------------------------
// IPC: news feed
// ---------------------------------------------------------------------------
ipcMain.handle('get-news', async () => {
  try {
    const news = await fetchJson(NEWS_URL)
    return { ok: true, news }
  } catch {
    return { ok: true, news: [] }
  }
})

// ---------------------------------------------------------------------------
// IPC: open external URL
// ---------------------------------------------------------------------------
ipcMain.on('open-url', (_event, url) => shell.openExternal(url))

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function fetchText(url, timeoutMs = 8000) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { timeout: timeoutMs }, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302 || res.statusCode === 307) {
        res.resume()
        return fetchText(res.headers.location, timeoutMs).then(resolve).catch(reject)
      }
      if (res.statusCode !== 200) {
        res.resume()
        return reject(new Error(`HTTP ${res.statusCode} from ${url}`))
      }
      const chunks = []
      res.on('data', c => chunks.push(c))
      res.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')))
      res.on('error', reject)
    })
    req.on('error', reject)
    req.on('timeout', () => { req.destroy(new Error(`Timeout fetching ${url}`)) })
  })
}

function fetchJson(url) {
  return fetchText(url).then(text => {
    try { return JSON.parse(text) }
    catch { throw new Error('Invalid JSON from ' + url) }
  })
}

function downloadWithProgress(url, onProgress) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith('https') ? https : http
    mod.get(url, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302 || res.statusCode === 307) {
        res.resume()
        return downloadWithProgress(res.headers.location, onProgress).then(resolve).catch(reject)
      }
      const total = parseInt(res.headers['content-length'] || '0', 10)
      let received = 0
      const chunks = []
      res.on('data', chunk => { chunks.push(chunk); received += chunk.length; onProgress(received, total) })
      res.on('end', () => resolve(Buffer.concat(chunks)))
      res.on('error', reject)
    }).on('error', reject)
  })
}

function findFileDir(dir, filename) {
  for (const entry of fs.readdirSync(dir)) {
    const full = path.join(dir, entry)
    if (entry === filename) return dir
    if (fs.statSync(full).isDirectory()) {
      const found = findFileDir(full, filename)
      if (found) return found
    }
  }
  return null
}

function copyDir(src, dest) {
  fs.mkdirSync(dest, { recursive: true })
  for (const entry of fs.readdirSync(src)) {
    const s = path.join(src, entry), d = path.join(dest, entry)
    if (fs.statSync(s).isDirectory()) copyDir(s, d)
    else fs.copyFileSync(s, d)
  }
}

function extractZip(zipPath, destDir) {
  return new Promise((resolve, reject) => {
    const ps = spawn('powershell', [
      '-NoProfile', '-NonInteractive', '-Command',
      `Expand-Archive -LiteralPath '${zipPath}' -DestinationPath '${destDir}' -Force`
    ])
    ps.on('close', code => code === 0 ? resolve() : reject(new Error(`Extract failed (code ${code})`)))
  })
}
