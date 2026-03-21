// ---------------------------------------------------------------------------
// Era Online Launcher — Renderer Process
// ---------------------------------------------------------------------------

const api = window.launcher

// ---------------------------------------------------------------------------
// Background music + mute button
// ---------------------------------------------------------------------------
;(function initMusic() {
  const music = document.getElementById('bg-music')
  if (!music) return
  const saved = localStorage.getItem('eo_muted')
  music.muted  = saved === 'true'
  music.volume = 0.05
  music.play().catch(() => {})

  // Inject mute button into titlebar
  const titlebar = document.getElementById('titlebar')
  if (titlebar) {
    const btn = document.createElement('button')
    btn.id = 'btn-mute'
    btn.title = 'Toggle music'
    btn.textContent = music.muted ? '🔇' : '🔊'
    btn.style.cssText = `
      background:transparent; border:none; color:#8c8270;
      font-size:14px; cursor:pointer; padding:0 6px;
      line-height:1; margin-right:2px;
    `
    btn.addEventListener('click', () => {
      music.muted = !music.muted
      btn.textContent = music.muted ? '🔇' : '🔊'
      localStorage.setItem('eo_muted', music.muted)
    })
    // Insert before minimize button
    const minBtn = document.getElementById('btn-minimize')
    titlebar.insertBefore(btn, minBtn)
  }
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
      playBtn.textContent = 'Downloading...'
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
    case 'error':
      playBtn.disabled = false
      playBtn.textContent = 'Retry'
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

  // Show offline immediately so we never appear stuck on "Checking..."
  dot.className = 'offline'
  text.textContent = 'Offline'
  extra.textContent = 'Checking...'

  const addr = document.getElementById('inp-server-addr').value.trim() || '127.0.0.1'
  const port = parseInt(document.getElementById('server-port-input').value.trim()) || 7777

  const result = await api.getServerStatus(addr, port)
  if (result.online) {
    dot.className = 'online'
    text.textContent = 'Online'
    extra.textContent = result.players > 0
      ? result.players + ' / ' + result.max + ' players'
      : 'Server is up'
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
// Startup: check + auto-install if needed
// ---------------------------------------------------------------------------
async function startup() {
  setPlayBtn('checking')
  setProgress(0, 'Checking for updates...')
  progWrap.classList.add('visible')

  const result = await api.checkUpdate()

  if (!result.ok) {
    hideProgress()
    if (result.installedVersion) {
      setPlayBtn('play')
      toast('Could not reach update server. Playing installed version.', 'error')
    } else {
      setPlayBtn('error')
      toast('No connection. Check your internet and retry.', 'error')
    }
    return
  }

  _manifest    = result.manifest
  _needsUpdate = result.needsUpdate

  const verTag = document.getElementById('version-tag')
  if (verTag) {
    verTag.dataset.gameVersion = result.installedVersion || ''
    _updateVersionTag()
  }

  if (_needsUpdate) {
    await _autoInstall()
  } else {
    hideProgress()
    setPlayBtn('play')
  }
}

async function _autoInstall() {
  _isDownloading = true
  setPlayBtn('downloading')
  setProgress(0, _manifest.installedVersion
    ? `Updating to ${_manifest.version}...`
    : `Downloading Era Online ${_manifest.version}...`)

  const result = await api.installUpdate(_manifest)
  _isDownloading = false

  if (!result.ok) {
    hideProgress()
    setPlayBtn('error')
    toast('Download failed: ' + result.error + ' — click Retry.', 'error', 8000)
    return
  }

  // Verify the exe actually landed (antivirus can silently remove it)
  const verify = await api.verifyInstall()
  if (!verify.installed) {
    hideProgress()
    setPlayBtn('error')
    toast('Game files were blocked — check Windows Defender exclusions for %APPDATA%\\EraOnline, then click Retry.', 'error', 12000)
    return
  }

  hideProgress()
  _needsUpdate = false
  const verTag = document.getElementById('version-tag')
  if (verTag) {
    verTag.dataset.gameVersion = _manifest.version
    _updateVersionTag()
  }
  setPlayBtn('play')
  toast('Era Online is ready!', 'success', 3000)
}

// ---------------------------------------------------------------------------
// Play button (launch only — updates are automatic)
// ---------------------------------------------------------------------------
playBtn.addEventListener('click', async () => {
  if (_isDownloading) return

  // Retry after failed download
  if (_needsUpdate && _manifest) {
    await _autoInstall()
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
    if (!result.ok && result.error && result.error.includes('not installed')) {
      // Exe is missing — re-download automatically
      _needsUpdate = true
      await _autoInstall()
      return
    }
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
// Launcher auto-update overlay + boot sequencer
// ---------------------------------------------------------------------------
;(function boot() {
  // Build and show overlay immediately — no waiting for IPC events
  const overlay = document.createElement('div')
  overlay.style.cssText = `
    position: fixed; inset: 0; z-index: 9999;
    background: rgba(8,5,2,0.97);
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    gap: 18px;
  `
  overlay.innerHTML = `
    <div style="color:#D9A626;font-size:15px;font-weight:bold;letter-spacing:2px;text-transform:uppercase;">
      Era Online Launcher
    </div>
    <div id="lu-status" style="color:#c8b97a;font-size:12px;">Checking for updates...</div>
    <div style="width:340px;height:6px;background:rgba(255,255,255,0.08);border-radius:3px;overflow:hidden;">
      <div id="lu-bar" style="height:100%;width:0%;background:linear-gradient(90deg,#8B5E0A,#D9A626);border-radius:3px;transition:width 0.3s;"></div>
    </div>
  `
  document.body.appendChild(overlay)

  const luStatus = overlay.querySelector('#lu-status')
  const luBar    = overlay.querySelector('#lu-bar')

  // Download progress events (fires if an update is being downloaded)
  api.onLauncherUpdateProgress((data) => {
    if (data.phase) luStatus.textContent = data.phase
    const m = (data.phase || '').match(/(\d+)%/)
    if (m) luBar.style.width = m[1] + '%'
  })

  // Absolute renderer-side fallback — if ANYTHING goes wrong for ANY reason,
  // the overlay is removed after 12s and the launcher proceeds normally.
  const absoluteFallback = setTimeout(() => {
    console.warn('[boot] absolute fallback fired — proceeding without update check')
    overlay.remove()
    startup()
    refreshStatus()
    loadNews()
  }, 12000)

  function proceed(result) {
    clearTimeout(absoluteFallback)
    if (result && !result.upToDate) {
      luStatus.textContent = `Downloading launcher v${result.version}...`
      return // overlay stays until launcher restarts
    }
    overlay.remove()
    startup()
    refreshStatus()
    loadNews()
  }

  // Wrap in try/catch: if api.checkLauncherUpdate is undefined (old preload
  // cached from a previous install), it throws synchronously and .catch() on
  // the promise chain won't catch it.
  try {
    api.checkLauncherUpdate().then(proceed).catch((err) => {
      console.error('[boot] checkLauncherUpdate rejected:', err)
      proceed({ upToDate: true })
    })
  } catch (err) {
    console.error('[boot] checkLauncherUpdate threw:', err)
    proceed({ upToDate: true })
  }
})()

// ---------------------------------------------------------------------------
// Boot — show launcher version
// ---------------------------------------------------------------------------
let _launcherVersion = ''
api.getVersion().then(v => {
  _launcherVersion = v
  _updateVersionTag()
})

function _updateVersionTag() {
  const verTag = document.getElementById('version-tag')
  if (!verTag) return
  const parts = []
  if (verTag.dataset.gameVersion) parts.push('Game ' + verTag.dataset.gameVersion)
  if (_launcherVersion)           parts.push('Launcher v' + _launcherVersion)
  verTag.textContent = parts.length ? parts.join(' | ') : ''
}

// Refresh server status every 30s
setInterval(refreshStatus, 30000)
