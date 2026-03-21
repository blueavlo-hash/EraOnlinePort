const { app, BrowserWindow, ipcMain, shell } = require('electron')
const { autoUpdater } = require('electron-updater')
const path = require('path')
const fs = require('fs')
const https = require('https')
const http = require('http')
const net = require('net')
const { spawn } = require('child_process')
const os = require('os')

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const MANIFEST_URL = 'https://raw.githubusercontent.com/blueavlo-hash/EraOnlinePort/main/public/launcher/latest.json'
const NEWS_URL     = 'https://raw.githubusercontent.com/blueavlo-hash/EraOnlinePort/main/public/launcher/news.json'
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
  setupAutoUpdater()
})
app.on('window-all-closed', () => app.quit())

// ---------------------------------------------------------------------------
// Auto-updater (launcher self-update via electron-updater)
// ---------------------------------------------------------------------------
// Promise that resolves once we know whether a launcher update is available.
// Renderer invokes 'check-launcher-update' to await this result — pull-based,
// so there are no IPC timing issues regardless of when the renderer loads.
let _resolveUpdateCheck = null
const _updateCheckPromise = new Promise((resolve) => { _resolveUpdateCheck = resolve })
const _resolveOnce = (result) => {
  if (_resolveUpdateCheck) { _resolveUpdateCheck(result); _resolveUpdateCheck = null }
}

function setupAutoUpdater() {
  autoUpdater.setFeedURL({
    provider: 'generic',
    url: 'https://raw.githubusercontent.com/blueavlo-hash/EraOnlinePort/main/public/launcher',
  })
  autoUpdater.autoDownload         = true
  autoUpdater.autoInstallOnAppQuit = false

  autoUpdater.on('update-not-available', () => _resolveOnce({ upToDate: true }))
  autoUpdater.on('update-available',  (info) => _resolveOnce({ upToDate: false, version: info.version }))
  autoUpdater.on('error',             ()     => _resolveOnce({ upToDate: true }))

  autoUpdater.on('download-progress', (p) => {
    win?.webContents.send('launcher-update-progress', {
      phase: `Downloading launcher... ${Math.round(p.percent)}%`,
    })
  })
  autoUpdater.on('update-downloaded', () => {
    win?.webContents.send('launcher-update-progress', { phase: 'Installing...' })
    setTimeout(() => autoUpdater.quitAndInstall(true, true), 1500)
  })

  // Safety timeout — proceed after 10s even if GitHub is unreachable
  setTimeout(() => _resolveOnce({ upToDate: true }), 10000)

  autoUpdater.checkForUpdates().catch(() => _resolveOnce({ upToDate: true }))
}

ipcMain.handle('get-version',            () => app.getVersion())
ipcMain.handle('check-launcher-update',  () => _updateCheckPromise)

// ---------------------------------------------------------------------------
// IPC: window controls
// ---------------------------------------------------------------------------
ipcMain.on('window-minimize', () => win?.minimize())
ipcMain.on('window-close',    () => app.quit())


// ---------------------------------------------------------------------------
// IPC: fetch manifest + check for update
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
// IPC: download + install update
// ---------------------------------------------------------------------------
ipcMain.handle('install-update', async (_event, manifest) => {
  try {
    fs.mkdirSync(INSTALL_DIR, { recursive: true })

    const parts = manifest.download_parts
    const tmpZip = path.join(os.tmpdir(), `EraOnline-${manifest.version}.zip`)

    // Single URL (GitHub release) or multi-part: both handled the same way
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

    // Extract to a temp dir first so we can handle subfolder structure
    win?.webContents.send('download-progress', { percent: 100, phase: 'Extracting...' })
    const tmpExtract = path.join(os.tmpdir(), `EraOnline-extract-${Date.now()}`)
    if (fs.existsSync(tmpExtract)) fs.rmSync(tmpExtract, { recursive: true, force: true })
    await extractZip(tmpZip, tmpExtract)
    fs.unlinkSync(tmpZip)

    // Find the directory that contains EraOnline.exe (handles any subfolder depth)
    const gameDir = findFileDir(tmpExtract, 'EraOnline.exe')
    if (!gameDir) throw new Error('EraOnline.exe not found in downloaded package.')

    // Copy game files to install dir
    fs.mkdirSync(INSTALL_DIR, { recursive: true })
    win?.webContents.send('download-progress', { percent: 100, phase: 'Installing...' })
    await copyDir(gameDir, INSTALL_DIR)
    fs.rmSync(tmpExtract, { recursive: true, force: true })

    // Write version marker
    fs.writeFileSync(VERSION_FILE, manifest.version, 'utf8')

    // Verify the exe is actually there (antivirus can silently remove it)
    if (!fs.existsSync(GAME_EXE)) {
      return { ok: false, error: 'EraOnline.exe was not found after installation. It may have been blocked by antivirus — try adding an exclusion for ' + INSTALL_DIR }
    }

    return { ok: true }
  } catch (e) {
    return { ok: false, error: e.message }
  }
})

// ---------------------------------------------------------------------------
// IPC: verify game install (for post-install check)
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
  if (username) args.push('--username', username)
  if (token)    args.push('--token',    token)
  if (serverAddress) args.push('--server-address', serverAddress)
  if (serverPort)    args.push('--server-port',    String(serverPort))

  const child = spawn(GAME_EXE, args, { detached: true, stdio: 'ignore', cwd: INSTALL_DIR })
  child.unref()
  // Optionally hide launcher while game runs:
  // win?.hide()
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
function fetchJson(url) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith('https') ? https : http
    const req = mod.get(url, { timeout: 8000 }, (res) => {
      // Follow redirects
      if (res.statusCode === 301 || res.statusCode === 302) {
        return fetchJson(res.headers.location).then(resolve).catch(reject)
      }
      let data = ''
      res.on('data', c => data += c)
      res.on('end', () => {
        try { resolve(JSON.parse(data)) }
        catch(e) { reject(new Error('Invalid JSON from ' + url)) }
      })
    })
    req.on('error', reject)
    req.on('timeout', () => { req.destroy(); reject(new Error('Timeout fetching ' + url)) })
  })
}

function downloadWithProgress(url, onProgress) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith('https') ? https : http
    mod.get(url, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) {
        return downloadWithProgress(res.headers.location, onProgress).then(resolve).catch(reject)
      }
      const total = parseInt(res.headers['content-length'] || '0', 10)
      let received = 0
      const chunks = []
      res.on('data', chunk => {
        chunks.push(chunk)
        received += chunk.length
        onProgress(received, total)
      })
      res.on('end', () => resolve(Buffer.concat(chunks)))
      res.on('error', reject)
    }).on('error', reject)
  })
}

// Find the directory containing a target filename (recursive)
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

// Recursively copy a directory
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
