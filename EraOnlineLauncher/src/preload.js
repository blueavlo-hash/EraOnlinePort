const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('launcher', {
  // Window controls
  minimize: ()       => ipcRenderer.send('window-minimize'),
  close:    ()       => ipcRenderer.send('window-close'),
  openUrl:  (url)    => ipcRenderer.send('open-url', url),

  // Game lifecycle
  checkUpdate:    ()         => ipcRenderer.invoke('check-update'),
  verifyInstall:  ()         => ipcRenderer.invoke('verify-install'),
  installUpdate: (manifest) => ipcRenderer.invoke('install-update', manifest),
  launchGame:    (opts)     => ipcRenderer.invoke('launch-game', opts),
  getServerStatus: (h, p)   => ipcRenderer.invoke('get-server-status', h, p),
  getNews:         ()       => ipcRenderer.invoke('get-news'),

  // Game download progress
  onProgress: (cb) => ipcRenderer.on('download-progress', (_e, data) => cb(data)),

  // Launcher version
  getVersion: () => ipcRenderer.invoke('get-version'),

  // Launcher auto-update — pull-based: renderer asks, main answers
  checkLauncherUpdate:      ()   => ipcRenderer.invoke('check-launcher-update'),
  onLauncherUpdateProgress: (cb) => ipcRenderer.on('launcher-update-progress', (_e, d) => cb(d)),
})
