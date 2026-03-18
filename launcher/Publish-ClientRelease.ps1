[CmdletBinding()]
param(
    [string]$ProjectRoot = (Join-Path $PSScriptRoot "..\\EraOnline"),
    [string]$OutputRoot = (Join-Path $PSScriptRoot "release"),
    [string]$PublicRoot = (Join-Path $PSScriptRoot "..\\public\\launcher"),
    [string]$DownloadUrl = ""
)

$ErrorActionPreference = "Stop"

function Get-ProjectVersion {
    param([string]$GodotProjectPath)

    $line = Get-Content -LiteralPath $GodotProjectPath | Where-Object { $_ -match '^config/version=' } | Select-Object -First 1
    if (-not $line) {
        throw "Could not find config/version in $GodotProjectPath"
    }

    return ($line -replace '^config/version="', '') -replace '"$', ''
}

function Resolve-LocalPath {
    param(
        [string]$PathValue,
        [string]$BasePath
    )

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return (Join-Path $BasePath $PathValue)
}

$projectRoot = (Resolve-Path $ProjectRoot).Path
$buildClientDir = Join-Path $projectRoot "build\\dist\\client"
$projectFile = Join-Path $projectRoot "project.godot"
$outputRootPath = Resolve-LocalPath -PathValue $OutputRoot -BasePath $PSScriptRoot
$publicRootPath = Resolve-LocalPath -PathValue $PublicRoot -BasePath $PSScriptRoot

if (-not (Test-Path -LiteralPath $buildClientDir)) {
    throw "Expected exported client at $buildClientDir"
}

$version = Get-ProjectVersion -GodotProjectPath $projectFile
$releaseName = "EraOnline-v$version-client"
New-Item -ItemType Directory -Force -Path $outputRootPath | Out-Null
New-Item -ItemType Directory -Force -Path $publicRootPath | Out-Null

$stagingDir = Join-Path $outputRootPath $releaseName
$zipPath = Join-Path $outputRootPath "$releaseName.zip"

if (Test-Path -LiteralPath $stagingDir) {
    Remove-Item -LiteralPath $stagingDir -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Copy-Item -LiteralPath $buildClientDir -Destination $stagingDir -Recurse
Set-Content -LiteralPath (Join-Path $stagingDir "version.txt") -Value $version -Encoding UTF8

Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $zipPath -CompressionLevel Optimal

$resolvedDownloadUrl = $DownloadUrl
if ([string]::IsNullOrWhiteSpace($resolvedDownloadUrl)) {
    $resolvedDownloadUrl = "REPLACE_WITH_PUBLIC_ZIP_URL/$releaseName.zip"
}

$manifest = [ordered]@{
    version = $version
    name = "Era Online $version"
    published_at = (Get-Date).ToUniversalTime().ToString("o")
    download_url = $resolvedDownloadUrl
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $publicRootPath "latest.json") -Encoding UTF8

Write-Host "Created $zipPath"
Write-Host "Updated $(Join-Path $publicRootPath 'latest.json')"
