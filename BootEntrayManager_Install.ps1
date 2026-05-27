param(
    [string]$cmd_location = "D:\OneDrive\cmd"
)

$ErrorActionPreference = "Stop"

$sourceScript = Join-Path $PSScriptRoot "Source\BootEntryManager.ps1"
if (-not (Test-Path -LiteralPath $sourceScript)) {
    throw "Source script not found: $sourceScript"
}

$installDir = Join-Path $cmd_location "BootEntryManager"
if (-not (Test-Path -LiteralPath $installDir)) {
    New-Item -ItemType Directory -Path $installDir | Out-Null
}

$targetScript = Join-Path $installDir "BootEntryManager.ps1"
Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force

Write-Host "Installed BootEntryManager to: $targetScript" -ForegroundColor Green
