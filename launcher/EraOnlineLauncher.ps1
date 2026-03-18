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
        throw "Set manifest_url in launcher\launcher-config.json or add a GitHub origin remote."
    }

    if (($config.provider -eq "github") -and ([string]::IsNullOrWhiteSpace($config.repo_owner) -or [string]::IsNullOrWhiteSpace($config.repo_name))) {
        throw "Set repo_owner and repo_name in launcher\launcher-config.json or add an origin remote."
    }

    return $config
}

function Get-LatestManifestRelease {
    param([object]$Config)

    $manifest = Invoke-RestMethod -Uri $Config.manifest_url -Method Get
    if (-not $manifest.version -or -not $manifest.download_url) {
        throw "Manifest at $($Config.manifest_url) is missing version or download_url."
    }

    $assetName = $Config.exe_name
    try {
        $uri = [System.Uri]$manifest.download_url
        $assetName = [System.IO.Path]::GetFileName($uri.AbsolutePath)
    } catch {
    }

    return @{
        tag = [string]$manifest.version
        name = [string]$manifest.name
        asset_name = [string]$assetName
        asset_url = [string]$manifest.download_url
        published_at = [string]$manifest.published_at
    }
}

function Get-LatestGitHubRelease {
    param([object]$Config)

    $headers = @{
        "User-Agent" = "EraOnlineLauncher"
        "Accept" = "application/vnd.github+json"
    }
    $url = "https://api.github.com/repos/$($Config.repo_owner)/$($Config.repo_name)/releases"
    $releases = Invoke-RestMethod -Uri $url -Headers $headers -Method Get

    $eligible = $releases | Where-Object {
        -not $_.draft -and ($Config.allow_prerelease -or -not $_.prerelease)
    } | Sort-Object {[DateTime]$_.published_at} -Descending

    if (-not $eligible) {
        throw "No eligible releases found for $($Config.repo_owner)/$($Config.repo_name)."
    }

    foreach ($release in $eligible) {
        $asset = $release.assets | Where-Object { $_.name -like $Config.asset_pattern } | Select-Object -First 1
        if ($null -ne $asset) {
            return @{
                tag = $release.tag_name
                name = $release.name
                asset_name = $asset.name
                asset_url = $asset.browser_download_url
                published_at = $release.published_at
            }
        }
    }

    throw "No release asset matching '$($Config.asset_pattern)' was found."
}

function Get-LatestRelease {
    param([object]$Config)

    if ($Config.provider -eq "manifest") {
        return Get-LatestManifestRelease -Config $Config
    }

    return Get-LatestGitHubRelease -Config $Config
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
    Write-Host "Downloading $($Release.asset_name)..."
    Invoke-WebRequest -Uri $Release.asset_url -OutFile $zipPath

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
        exe_relative_path = $exe.FullName.Substring($stagingDir.Length).TrimStart('\')
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
