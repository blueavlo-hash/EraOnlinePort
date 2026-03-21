const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('launcher', {
  // Window controls
  minimize: ()       => ipcRenderer.send('window-minimize'),
  close:    ()       => ipcRenderer.send('window-close'),
  openUrl:  (url)    => ipcRenderer.send('open-url', url),

  // Game lifecycle
  checkUpdate:     ()         => ipcRenderer.invoke('check-update'),
  installUpdate:          (manifest) => ipcRenderer.invoke('install-update', manifest),
  installLauncherUpdate:  (url)      => ipcRenderer.invoke('install-launcher-update', url),
  onLauncherUpdateProgress: (cb)     => ipcRenderer.on('launcher-update-progress', (_e, d) => cb(d)),
  launchGame:      (opts)     => ipcRenderer.invoke('launch-game', opts),
  getServerStatus: ()         => ipcRenderer.invoke('get-server-status'),
  getNews:         ()         => ipcRenderer.invoke('get-news'),

  // Progress events from main → renderer
  onProgress: (cb) => ipcRenderer.on('download-progress', (_e, data) => cb(data)),
})
