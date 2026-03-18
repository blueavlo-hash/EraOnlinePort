# Launcher

`Start-EraOnline.cmd` is the player-facing launcher. It reads a public update manifest, downloads the newest client zip, installs it under `launcher/installed/current`, and then starts `EraOnline.exe`.

## Setup

1. Push this folder to a GitHub repository.
2. Make `public/launcher/latest.json` reachable from a public URL. Raw GitHub content works, and GitHub Pages works too.
3. Set `manifest_url` in `launcher-config.json`, or add an `origin` remote and keep the manifest at `public/launcher/latest.json` on `main`.
4. Export the Godot client into `EraOnline/build/dist/client`.
5. Run `launcher/Publish-ClientRelease.ps1 -DownloadUrl <public zip url>` to create the versioned zip and refresh the manifest.
6. Upload the zip to the public location referenced by `download_url`.

## Notes

- By default the launcher assumes `public/launcher/latest.json` on the `main` branch of your GitHub repo if `manifest_url` is blank.
- The launcher updates before every start unless you run `EraOnlineLauncher.ps1 -SkipUpdate`.
