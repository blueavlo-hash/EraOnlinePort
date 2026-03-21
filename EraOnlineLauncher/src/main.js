const { app, BrowserWindow, ipcMain, shell } = require('electron')
const { autoUpdater } = require('electron-updater')
const path = require('path')
const fs = require('fs')
const https = require('https')
const http = require('http')
const { spawn } = require('child_process')
const os = require('os')

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const MANIFEST_URL      = 'https://raw.githubusercontent.com/blueavlo-hash/EraOnlinePort/main/public/launcher/latest.json'
const NEWS_URL          = 'https://raw.githubusercontent.com/blueavlo-hash/EraOnlinePort/main/public/launcher/news.json'
const SERVER_STATUS_URL = 'http://127.0.0.1:6970/status'
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
function setupAutoUpdater() {
  autoUpdater.setFeedURL({
    provider: 'generic',
    url: 'https://raw.githubusercontent.com/blueavlo-hash/EraOnlinePort/main/public/launcher',
  })
  autoUpdater.autoDownload    = true
  autoUpdater.autoInstallOnAppQuit = false

  autoUpdater.on('update-available', (info) => {
    win?.webContents.send('launcher-update-available', info.version)
  })
  autoUpdater.on('download-progress', (p) => {
    win?.webContents.send('launcher-update-progress', {
      phase: `Downloading launcher... ${Math.round(p.percent)}%`,
    })
  })
  autoUpdater.on('update-downloaded', () => {
    win?.webContents.send('launcher-update-progress', { phase: 'Installing...' })
    setTimeout(() => autoUpdater.quitAndInstall(true, true), 1500)
  })
  autoUpdater.on('error', (err) => {
    win?.webContents.send('launcher-update-error', err.message)
  })

  // Delay first check so window is ready
  setTimeout(() => autoUpdater.checkForUpdates().catch(() => {}), 3000)
}

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

    // Extract zip via PowerShell (no extra deps)
    win?.webContents.send('download-progress', { percent: 100, phase: 'Extracting...' })
    await extractZip(tmpZip, INSTALL_DIR)

    // Write version marker
    fs.writeFileSync(VERSION_FILE, manifest.version, 'utf8')
    fs.unlinkSync(tmpZip)

    return { ok: true }
  } catch (e) {
    return { ok: false, error: e.message }
  }
})

// ---------------------------------------------------------------------------
// IPC: launch game
// ---------------------------------------------------------------------------
ipcMain.handle('launch-game', async (_event, { username, token, serverAddress, serverPort }) => {
  if (!fs.existsSync(GAME_EXE)) {
    return { ok: false, error: 'Game not installed.' }
  }
  const args = []
  if (username) args.push('--username', username)
  if (token)    args.push('--token',    token)
  if (serverAddress) args.push('--server-address', serverAddress)
  if (serverPort)    args.push('--server-port',    String(serverPort))

  const child = spawn(GAME_EXE, args, { detached: true, stdio: 'ignore' })
  child.unref()
  // Optionally hide launcher while game runs:
  // win?.hide()
  return { ok: true }
})

// ---------------------------------------------------------------------------
// IPC: server status
// ---------------------------------------------------------------------------
ipcMain.handle('get-server-status', async () => {
  try {
    const data = await fetchJson(SERVER_STATUS_URL)
    return { ok: true, online: true, players: data.players ?? 0, max: data.max ?? 0 }
  } catch {
    return { ok: true, online: false, players: 0, max: 0 }
  }
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

function extractZip(zipPath, destDir) {
  return new Promise((resolve, reject) => {
    const ps = spawn('powershell', [
      '-NoProfile', '-NonInteractive', '-Command',
      `Expand-Archive -LiteralPath '${zipPath}' -DestinationPath '${destDir}' -Force`
    ])
    ps.on('close', code => code === 0 ? resolve() : reject(new Error(`Extract failed (code ${code})`)))
  })
}
