[CmdletBinding()]
param(
    [switch]$SkipUpdate
)

$ErrorActionPreference = "Stop"

function Get-ScriptRoot {
    Split-Path -Parent $MyInvocation.ScriptName
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )
    $json = $Value | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Get-RepoFromOrigin {
    param([string]$RepoRoot)

    try {
        $origin = git -C $RepoRoot remote get-url origin 2>$null
        if (-not $origin) {
            return $null
        }

        if ($origin -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)(?:\.git)?$') {
            return @{
                owner = $Matches.owner
                repo = $Matches.repo
            }
        }
    } catch {
        return $null
    }

    return $null
}

function Get-LauncherConfig {
    param(
        [string]$ConfigPath,
        [string]$RepoRoot
    )

    $config = Read-JsonFile -Path $ConfigPath
    if ($null -eq $config) {
        throw "Missing launcher config at $ConfigPath"
    }

    if (($config.provider -eq "manifest") -and [string]::IsNullOrWhiteSpace($config.manifest_url)) {
        if ([string]::IsNullOrWhiteSpace($config.repo_owner) -or [string]::IsNullOrWhiteSpace($config.repo_name)) {
            $repo = Get-RepoFromOrigin -RepoRoot $RepoRoot
            if ($null -ne $repo) {
                $config.repo_owner = $repo.owner
                $config.repo_name = $repo.repo
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($config.repo_owner) -and -not [string]::IsNullOrWhiteSpace($config.repo_name)) {
            $config.manifest_url = "https://raw.githubusercontent.com/$($config.repo_owner)/$($config.repo_name)/main/public/launcher/latest.json"
        }
    }

    if (($config.provider -eq "manifest") -and [string]::IsNullOrWhiteSpace($config.manifest_url)) {
        throw "Set manifest_url in launcher-config.json."
    }

    return $config
}

function Get-LatestManifestRelease {
    param([object]$Config)

    $manifest = Invoke-RestMethod -Uri $Config.manifest_url -Method Get
    if (-not $manifest.version) {
        throw "Manifest at $($Config.manifest_url) is missing version."
    }
    if ((-not $manifest.download_url) -and (-not $manifest.download_parts)) {
        throw "Manifest at $($Config.manifest_url) is missing download_url or download_parts."
    }

    $assetName = [string]($manifest.asset_name)
    if ([string]::IsNullOrWhiteSpace($assetName)) {
        if ($manifest.download_url) {
            try {
                $uri = [System.Uri]$manifest.download_url
                $assetName = [System.IO.Path]::GetFileName($uri.AbsolutePath)
            } catch {
                $assetName = "package.zip"
            }
        } else {
            $assetName = "package.zip"
        }
    }

    return @{
        tag = [string]$manifest.version
        name = [string]($manifest.name)
        asset_name = $assetName
        asset_url = [string]($manifest.download_url)
        asset_parts = $manifest.download_parts
        published_at = [string]($manifest.published_at)
    }
}

function Get-LatestRelease {
    param([object]$Config)
    return Get-LatestManifestRelease -Config $Config
}

function Download-ReleasePackage {
    param(
        [object]$Release,
        [string]$DownloadsDir,
        [string]$ZipPath
    )

    if ($Release.asset_parts -and $Release.asset_parts.Count -gt 0) {
        $partDir = Join-Path $DownloadsDir "parts"
        New-Item -ItemType Directory -Force -Path $partDir | Out-Null

        if (Test-Path -LiteralPath $ZipPath) {
            Remove-Item -LiteralPath $ZipPath -Force
        }

        $targetStream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        try {
            $buffer = New-Object byte[] 1048576
            foreach ($partUrl in $Release.asset_parts) {
                $partName = [System.IO.Path]::GetFileName(([System.Uri]$partUrl).AbsolutePath)
                $partPath = Join-Path $partDir $partName
                Write-Host "Downloading $partName..."
                Invoke-WebRequest -Uri $partUrl -OutFile $partPath

                $sourceStream = [System.IO.File]::OpenRead($partPath)
                try {
                    while (($read = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $targetStream.Write($buffer, 0, $read)
                    }
                } finally {
                    $sourceStream.Dispose()
                }
            }
        } finally {
            $targetStream.Dispose()
        }
        return
    }

    if (-not $Release.asset_url) {
        throw "Release manifest does not contain a usable download source."
    }

    Write-Host "Downloading $($Release.asset_name)..."
    Invoke-WebRequest -Uri $Release.asset_url -OutFile $ZipPath
}

function Install-Release {
    param(
        [object]$Release,
        [object]$Config,
        [string]$LauncherRoot,
        [string]$StatePath
    )

    $downloadsDir = Join-Path $LauncherRoot "downloads"
    $installedDir = Join-Path $LauncherRoot "installed"
    $currentDir = Join-Path $installedDir "current"
    $stagingDir = Join-Path $installedDir ("staging-" + [Guid]::NewGuid().ToString("N"))

    New-Item -ItemType Directory -Force -Path $downloadsDir | Out-Null
    New-Item -ItemType Directory -Force -Path $installedDir | Out-Null
    New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

    $zipPath = Join-Path $downloadsDir $Release.asset_name
    Download-ReleasePackage -Release $Release -DownloadsDir $downloadsDir -ZipPath $zipPath

    Write-Host "Extracting update..."
    Expand-Archive -Path $zipPath -DestinationPath $stagingDir -Force

    $exe = Get-ChildItem -Path $stagingDir -Recurse -Filter $Config.exe_name | Select-Object -First 1
    if ($null -eq $exe) {
        throw "Downloaded release does not contain $($Config.exe_name)."
    }

    if (Test-Path -LiteralPath $currentDir) {
        Remove-Item -LiteralPath $currentDir -Recurse -Force
    }

    Move-Item -LiteralPath $stagingDir -Destination $currentDir

    $state = [ordered]@{
        installed_tag = $Release.tag
        installed_name = $Release.name
        asset_name = $Release.asset_name
        installed_at = (Get-Date).ToString("o")
        exe_relative_path = $exe.FullName.Substring($stagingDir.Length).TrimStart('\\')
    }
    Write-JsonFile -Path $StatePath -Value $state
}

function Get-InstalledExecutable {
    param(
        [string]$LauncherRoot,
        [string]$ExeName,
        [string]$StatePath
    )

    $state = Read-JsonFile -Path $StatePath
    if ($null -ne $state -and $state.exe_relative_path) {
        $candidate = Join-Path (Join-Path $LauncherRoot "installed\\current") $state.exe_relative_path
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $fallback = Get-ChildItem -Path (Join-Path $LauncherRoot "installed\\current") -Recurse -Filter $ExeName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $fallback) {
        return $fallback.FullName
    }

    return $null
}

$launcherRoot = Get-ScriptRoot
$repoRoot = Split-Path -Parent $launcherRoot
$configPath = Join-Path $launcherRoot "launcher-config.json"
$statePath = Join-Path $launcherRoot "state.json"

$config = Get-LauncherConfig -ConfigPath $configPath -RepoRoot $repoRoot
$state = Read-JsonFile -Path $statePath

if (-not $SkipUpdate) {
    $release = Get-LatestRelease -Config $config
    if ($null -eq $state -or $state.installed_tag -ne $release.tag) {
        Install-Release -Release $release -Config $config -LauncherRoot $launcherRoot -StatePath $statePath
        $state = Read-JsonFile -Path $statePath
    }
}

$exePath = Get-InstalledExecutable -LauncherRoot $launcherRoot -ExeName $config.exe_name -StatePath $statePath
if ($null -eq $exePath) {
    throw "No installed client was found. Run without -SkipUpdate after you publish a release."
}

Write-Host "Launching $exePath"
Start-Process -FilePath $exePath -WorkingDirectory (Split-Path -Parent $exePath) -ArgumentList $config.launch_args
