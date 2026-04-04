# Launcher

`EraOnlineLauncher.exe` is the Windows launcher your testers should run. It checks the public update manifest, downloads the newest client package, installs it under its own `installed` folder, and launches `EraOnline.exe`.

## Tester use

1. Download `EraOnlineLauncher.zip`.
2. Extract it anywhere.
3. Run `EraOnlineLauncher.exe`.
4. Click `Launch` after the first update finishes.

## Update publishing

Run `powershell -ExecutionPolicy Bypass -File launcher/Publish-ClientRelease.ps1` after exporting a new client build. That script refreshes the hosted client package under `public/downloads` and rebuilds the launcher bundle.
