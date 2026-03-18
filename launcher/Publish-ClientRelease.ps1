[CmdletBinding()]
param(
    [string]$ProjectRoot = (Join-Path $PSScriptRoot "..\\EraOnline"),
    [string]$OutputRoot = (Join-Path $PSScriptRoot "release"),
    [string]$PublicRoot = (Join-Path $PSScriptRoot "..\\public"),
    [string]$RepoOwner = "blueavlo-hash",
    [string]$RepoName = "EraOnlinePort",
    [int]$ChunkSizeBytes = 95000000
)

$ErrorActionPreference = "Stop"

function Get-ProjectVersion {
    param([string]$GodotProjectPath)
    $line = Get-Content -LiteralPath $GodotProjectPath | Where-Object { $_ -match '^config/version=' } | Select-Object -First 1
    if (-not $line) { throw "Could not find config/version in $GodotProjectPath" }
    return ($line -replace '^config/version="', '') -replace '"$', ''
}

function Resolve-LocalPath {
    param([string]$PathValue, [string]$BasePath)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $BasePath $PathValue)
}

function Split-File {
    param(
        [string]$SourcePath,
        [string]$DestinationDir,
        [int]$ChunkSizeBytes
    )

    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    Get-ChildItem -LiteralPath $DestinationDir -File -ErrorAction SilentlyContinue | Remove-Item -Force

    $bufferSize = 1048576
    $buffer = New-Object byte[] $bufferSize
    $index = 1
    $parts = @()
    $source = [System.IO.File]::OpenRead($SourcePath)
    try {
        while ($source.Position -lt $source.Length) {
            $partName = "{0}.part{1:D3}" -f [System.IO.Path]::GetFileName($SourcePath), $index
            $partPath = Join-Path $DestinationDir $partName
            $written = 0L
            $outStream = [System.IO.File]::Open($partPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
            try {
                while ($written -lt $ChunkSizeBytes -and $source.Position -lt $source.Length) {
                    $remaining = [int][Math]::Min($bufferSize, $ChunkSizeBytes - $written)
                    $read = $source.Read($buffer, 0, $remaining)
                    if ($read -le 0) { break }
                    $outStream.Write($buffer, 0, $read)
                    $written += $read
                }
            } finally {
                $outStream.Dispose()
            }
            $parts += $partPath
            $index += 1
        }
    } finally {
        $source.Dispose()
    }

    return $parts
}

$projectRoot = (Resolve-Path $ProjectRoot).Path
$buildClientDir = Join-Path $projectRoot "build\\dist\\client"
$projectFile = Join-Path $projectRoot "project.godot"
$outputRootPath = Resolve-LocalPath -PathValue $OutputRoot -BasePath $PSScriptRoot
$publicRootPath = Resolve-LocalPath -PathValue $PublicRoot -BasePath $PSScriptRoot
$publicDownloadsPath = Join-Path $publicRootPath "downloads"
$publicLauncherPath = Join-Path $publicRootPath "launcher"

if (-not (Test-Path -LiteralPath $buildClientDir)) { throw "Expected exported client at $buildClientDir" }

$version = Get-ProjectVersion -GodotProjectPath $projectFile
$releaseName = "EraOnline-v$version-client"
$baseUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/main/public/downloads"
New-Item -ItemType Directory -Force -Path $outputRootPath | Out-Null
New-Item -ItemType Directory -Force -Path $publicDownloadsPath | Out-Null
New-Item -ItemType Directory -Force -Path $publicLauncherPath | Out-Null

$stagingDir = Join-Path $outputRootPath $releaseName
$zipPath = Join-Path $outputRootPath "$releaseName.zip"
$publicPartsDir = Join-Path $publicDownloadsPath $releaseName

if (Test-Path -LiteralPath $stagingDir) { Remove-Item -LiteralPath $stagingDir -Recurse -Force }
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
if (Test-Path -LiteralPath $publicPartsDir) { Remove-Item -LiteralPath $publicPartsDir -Recurse -Force }

Copy-Item -LiteralPath $buildClientDir -Destination $stagingDir -Recurse
Set-Content -LiteralPath (Join-Path $stagingDir "version.txt") -Value $version -Encoding UTF8
Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $zipPath -CompressionLevel Optimal

$parts = Split-File -SourcePath $zipPath -DestinationDir $publicPartsDir -ChunkSizeBytes $ChunkSizeBytes
$partUrls = @()
foreach ($partPath in $parts) {
    $partUrls += "$baseUrl/$releaseName/$([System.IO.Path]::GetFileName($partPath))"
}

$manifest = [ordered]@{
    version = $version
    name = "Era Online $version"
    published_at = (Get-Date).ToUniversalTime().ToString("o")
    asset_name = "$releaseName.zip"
    download_parts = $partUrls
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $publicLauncherPath "latest.json") -Encoding UTF8

$launcherBundleDir = Join-Path $outputRootPath "EraOnlineLauncher"
$launcherBundleZip = Join-Path $publicDownloadsPath "EraOnlineLauncher.zip"
if (Test-Path -LiteralPath $launcherBundleDir) { Remove-Item -LiteralPath $launcherBundleDir -Recurse -Force }
if (Test-Path -LiteralPath $launcherBundleZip) { Remove-Item -LiteralPath $launcherBundleZip -Force }
New-Item -ItemType Directory -Force -Path $launcherBundleDir | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'EraOnlineLauncher.ps1') -Destination $launcherBundleDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Start-EraOnline.cmd') -Destination $launcherBundleDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'launcher-config.json') -Destination $launcherBundleDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination $launcherBundleDir
Compress-Archive -Path (Join-Path $launcherBundleDir '*') -DestinationPath $launcherBundleZip -CompressionLevel Optimal

Write-Host "Created $zipPath"
Write-Host "Split into $($parts.Count) part(s) under $publicPartsDir"
Write-Host "Updated $(Join-Path $publicLauncherPath 'latest.json')"
Write-Host "Created $launcherBundleZip"
