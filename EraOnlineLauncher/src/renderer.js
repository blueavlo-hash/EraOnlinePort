// ---------------------------------------------------------------------------
// Era Online Launcher — Renderer Process
// ---------------------------------------------------------------------------

const api = window.launcher

// ---------------------------------------------------------------------------
// Background music
// ---------------------------------------------------------------------------
;(function initMusic() {
  const music = document.getElementById('bg-music')
  if (!music) return
  music.volume = 0.45
  music.play().catch(() => {})
})()

// ---------------------------------------------------------------------------
// Particles
// ---------------------------------------------------------------------------
;(function initParticles() {
  const canvas = document.getElementById('particles')
  const ctx    = canvas.getContext('2d')
  canvas.width  = 960
  canvas.height = 580

  const PARTICLE_COUNT = 55
  const particles = []

  function rand(min, max) { return Math.random() * (max - min) + min }

  for (let i = 0; i < PARTICLE_COUNT; i++) {
    particles.push({
      x:     rand(0, 960),
      y:     rand(0, 580),
      size:  rand(1, 2.8),
      speed: rand(0.2, 0.7),
      drift: rand(-0.15, 0.15),
      alpha: rand(0.1, 0.55),
      // ember glow color: gold/orange tones
      hue:   rand(25, 45),
    })
  }

  function tick() {
    ctx.clearRect(0, 0, 960, 580)
    for (const p of particles) {
      p.y -= p.speed
      p.x += p.drift
      // twinkle
      p.alpha += rand(-0.02, 0.02)
      p.alpha  = Math.max(0.05, Math.min(0.6, p.alpha))

      if (p.y < -4) { p.y = 584; p.x = rand(0, 960) }
      if (p.x < -4) { p.x = 964 }
      if (p.x > 964) { p.x = -4 }

      ctx.save()
      ctx.globalAlpha = p.alpha
      ctx.beginPath()
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2)
      // subtle glow
      const grad = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.size * 2.5)
      grad.addColorStop(0, `hsl(${p.hue}, 80%, 75%)`)
      grad.addColorStop(1, `hsla(${p.hue}, 60%, 50%, 0)`)
      ctx.fillStyle = grad
      ctx.fill()
      ctx.restore()
    }
    requestAnimationFrame(tick)
  }
  tick()
})()

// ---------------------------------------------------------------------------
// Titlebar
// ---------------------------------------------------------------------------
document.getElementById('btn-minimize').addEventListener('click', () => api.minimize())
document.getElementById('btn-close').addEventListener('click',    () => api.close())

// ---------------------------------------------------------------------------
// Server toggle (custom server fields)
// ---------------------------------------------------------------------------
const serverToggle   = document.getElementById('server-toggle')
const serverAdvanced = document.getElementById('server-advanced')
serverToggle.addEventListener('click', () => {
  serverAdvanced.classList.toggle('open')
  serverToggle.textContent = serverAdvanced.classList.contains('open')
    ? '▾ Custom server'
    : '▸ Custom server'
})

// ---------------------------------------------------------------------------
// Footer links
// ---------------------------------------------------------------------------
document.getElementById('link-discord').addEventListener('click', () =>
  api.openUrl('https://discord.gg/eraonline'))
document.getElementById('link-website').addEventListener('click', () =>
  api.openUrl('https://github.com/blueavlo-hash/EraOnlinePort'))

// ---------------------------------------------------------------------------
// Toast helper
// ---------------------------------------------------------------------------
function toast(msg, type = 'info', duration = 4000) {
  const area = document.getElementById('toast-area')
  const el   = document.createElement('div')
  el.className = 'toast ' + type
  el.textContent = msg
  area.appendChild(el)
  setTimeout(() => {
    el.style.transition = 'opacity 0.4s'
    el.style.opacity = '0'
    setTimeout(() => el.remove(), 400)
  }, duration)
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
let _manifest       = null
let _needsUpdate    = false
let _isDownloading  = false

const playBtn    = document.getElementById('play-btn')
const progWrap   = document.getElementById('progress-wrap')
const progFill   = document.getElementById('progress-bar-fill')
const progLabel  = document.getElementById('progress-label')

function setProgress(pct, label) {
  progWrap.classList.add('visible')
  progFill.style.width = pct + '%'
  if (label) progLabel.textContent = label
}

function hideProgress() {
  progWrap.classList.remove('visible')
}

function setPlayBtn(state) {
  playBtn.classList.remove('pulse')
  switch(state) {
    case 'checking':
      playBtn.disabled = true
      playBtn.textContent = 'Checking...'
      break
    case 'downloading':
      playBtn.disabled = true
      playBtn.textContent = 'Updating...'
      break
    case 'update':
      playBtn.disabled = false
      playBtn.textContent = 'Update'
      break
    case 'play':
      playBtn.disabled = false
      playBtn.textContent = 'Play'
      playBtn.classList.add('pulse')
      break
    case 'launching':
      playBtn.disabled = true
      playBtn.textContent = 'Launching...'
      break
  }
}

// ---------------------------------------------------------------------------
// Download progress from main process
// ---------------------------------------------------------------------------
api.onProgress((data) => {
  if (data.phase) {
    setProgress(100, data.phase)
    return
  }
  const pct   = data.percent || 0
  const mbRec = ((data.received || 0) / 1048576).toFixed(1)
  const mbTot = ((data.total    || 0) / 1048576).toFixed(1)
  const label = mbTot > 0
    ? `Downloading... ${mbRec} MB / ${mbTot} MB  (${pct}%)`
    : `Downloading... ${pct}%`
  setProgress(pct, label)
})

// ---------------------------------------------------------------------------
// Server status
// ---------------------------------------------------------------------------
async function refreshStatus() {
  const dot   = document.getElementById('status-dot')
  const text  = document.getElementById('status-text')
  const extra = document.getElementById('status-extra')

  const result = await api.getServerStatus()
  if (result.online) {
    dot.className = 'online'
    text.textContent = 'Online'
    extra.textContent = result.players + ' / ' + result.max + ' players'
  } else {
    dot.className = 'offline'
    text.textContent = 'Offline'
    extra.textContent = 'Server not reachable'
  }
}

// ---------------------------------------------------------------------------
// News feed
// ---------------------------------------------------------------------------
async function loadNews() {
  const list   = document.getElementById('news-list')
  const result = await api.getNews()

  if (!result.ok || !result.news || result.news.length === 0) {
    // Fallback hardcoded news if fetch fails
    list.innerHTML = `
      <div class="news-item">
        <div class="news-date">MARCH 2026</div>
        <div class="news-title">v0.5.0-alpha — First Multiplayer Test</div>
        <div class="news-body">
          Directional melee, PK gold loot, dead body visuals, vendor fixes, and more.
          Thanks to everyone who helped test!
        </div>
      </div>
      <hr class="news-divider">
      <div class="news-item">
        <div class="news-date">MARCH 2026</div>
        <div class="news-title">Launcher Live</div>
        <div class="news-body">
          The auto-updating launcher is now live. Future updates will download automatically.
        </div>
      </div>
    `
    return
  }

  list.innerHTML = result.news.map((item, i) => `
    ${i > 0 ? '<hr class="news-divider">' : ''}
    <div class="news-item">
      <div class="news-date">${item.date || ''}</div>
      <div class="news-title">${item.title || ''}</div>
      <div class="news-body">${item.body || ''}</div>
    </div>
  `).join('')
}

// ---------------------------------------------------------------------------
// Startup: check for updates
// ---------------------------------------------------------------------------
async function startup() {
  setPlayBtn('checking')
  setProgress(0, 'Checking for updates...')
  progWrap.classList.add('visible')

  const result = await api.checkUpdate()

  if (!result.ok) {
    // Can't reach manifest — if game is installed, let them play anyway
    hideProgress()
    if (result.installedVersion) {
      setPlayBtn('play')
      toast('Could not check for updates. Playing offline cached version.', 'error')
    } else {
      setPlayBtn('checking')
      playBtn.textContent = 'No Connection'
      toast('Could not reach update server. Check your connection.', 'error')
    }
    return
  }

  _manifest    = result.manifest
  _needsUpdate = result.needsUpdate

  // Update version display
  const verTag = document.getElementById('version-tag')
  if (verTag) verTag.textContent =
    result.installedVersion ? `installed: ${result.installedVersion}` : 'not installed'

  hideProgress()

  if (_needsUpdate) {
    const label = result.installedVersion
      ? `Update available: ${result.installedVersion} → ${result.manifest.version}`
      : `Download required: ${result.manifest.version}`
    toast(label, 'info', 6000)
    setPlayBtn('update')
  } else {
    setPlayBtn('play')
  }
}

// ---------------------------------------------------------------------------
// Play / Update button
// ---------------------------------------------------------------------------
playBtn.addEventListener('click', async () => {
  if (_isDownloading) return

  if (_needsUpdate && _manifest) {
    // Download & install
    _isDownloading = true
    setPlayBtn('downloading')
    setProgress(0, 'Starting download...')
    progWrap.classList.add('visible')

    const result = await api.installUpdate(_manifest)
    _isDownloading = false

    if (!result.ok) {
      hideProgress()
      setPlayBtn('update')
      toast('Update failed: ' + result.error, 'error')
      return
    }

    hideProgress()
    _needsUpdate = false
    toast('Update installed successfully!', 'success')
    setPlayBtn('play')

    // Update version tag
    document.getElementById('version-tag').textContent = 'installed: ' + _manifest.version
    return
  }

  // Launch
  setPlayBtn('launching')
  const username = document.getElementById('inp-username').value.trim()
  const password = document.getElementById('inp-password').value
  const addr     = document.getElementById('inp-server-addr').value.trim() || '127.0.0.1'
  const port     = parseInt(document.getElementById('server-port-input').value.trim()) || 6969

  const result = await api.launchGame({
    username:        username || null,
    token:           password || null,
    serverAddress:   addr,
    serverPort:      port,
    expectedVersion: _manifest?.version || null,
  })

  if (!result.ok) {
    setPlayBtn('play')
    toast('Launch failed: ' + result.error, 'error')
    return
  }

  toast('Launching Era Online...', 'success', 2000)
  // Re-enable after a moment (launcher stays open)
  setTimeout(() => setPlayBtn('play'), 3000)
})

// Also allow Enter in password field to trigger play
document.getElementById('inp-password').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !playBtn.disabled) playBtn.click()
})

// ---------------------------------------------------------------------------
// Remember me (localStorage)
// ---------------------------------------------------------------------------
;(function loadSavedCreds() {
  const saved = localStorage.getItem('eo_remember')
  if (!saved) return
  try {
    const { username, remember } = JSON.parse(saved)
    if (remember) {
      document.getElementById('inp-username').value = username || ''
      document.getElementById('chk-remember').checked = true
    }
  } catch {}
})()

document.getElementById('chk-remember').addEventListener('change', (e) => {
  if (!e.target.checked) {
    localStorage.removeItem('eo_remember')
  }
})
document.getElementById('inp-username').addEventListener('input', () => {
  if (document.getElementById('chk-remember').checked) {
    localStorage.setItem('eo_remember', JSON.stringify({
      username: document.getElementById('inp-username').value,
      remember: true,
    }))
  }
})

// ---------------------------------------------------------------------------
// Launcher auto-update overlay (driven by electron-updater events)
// ---------------------------------------------------------------------------
;(function setupLauncherUpdateUI() {
  let overlay = null

  function getOverlay() {
    if (overlay) return overlay
    overlay = document.createElement('div')
    overlay.style.cssText = `
      position: fixed; inset: 0; z-index: 9999;
      background: rgba(8,5,2,0.97);
      display: flex; flex-direction: column;
      align-items: center; justify-content: center;
      gap: 18px;
    `
    overlay.innerHTML = `
      <div style="color:#D9A626;font-size:15px;font-weight:bold;letter-spacing:2px;text-transform:uppercase;">
        Launcher Update
      </div>
      <div id="lu-status" style="color:#c8b97a;font-size:12px;">Downloading update...</div>
      <div style="width:340px;height:6px;background:rgba(255,255,255,0.08);border-radius:3px;overflow:hidden;">
        <div id="lu-bar" style="height:100%;width:0%;background:linear-gradient(90deg,#8B5E0A,#D9A626);border-radius:3px;transition:width 0.3s;"></div>
      </div>
    `
    document.body.appendChild(overlay)
    return overlay
  }

  api.onLauncherUpdateAvailable((version) => {
    setPlayBtn('checking')
    playBtn.textContent = 'Updating...'
    const ov = getOverlay()
    ov.querySelector('#lu-status').textContent = `Downloading update v${version}...`
  })

  api.onLauncherUpdateProgress((data) => {
    const ov = getOverlay()
    const statusEl = ov.querySelector('#lu-status')
    const barEl    = ov.querySelector('#lu-bar')
    if (data.phase) statusEl.textContent = data.phase
    const m = (data.phase || '').match(/(\d+)%/)
    if (m) barEl.style.width = m[1] + '%'
  })

  api.onLauncherUpdateError((err) => {
    if (!overlay) return
    overlay.querySelector('#lu-status').textContent = 'Update failed — will retry next launch.'
    overlay.querySelector('#lu-bar').style.width = '0%'
    setTimeout(() => { overlay?.remove(); overlay = null }, 4000)
  })
})()

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------
startup()
refreshStatus()
loadNews()

// Refresh server status every 30s
setInterval(refreshStatus, 30000)
