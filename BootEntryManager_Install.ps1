param(
    [string]$cmd_location = "D:\OneDrive\cmd"
)

$ErrorActionPreference = "Stop"

$sourceScript = Join-Path $PSScriptRoot "Source\BootEntryManager.ps1"
if (-not (Test-Path -LiteralPath $sourceScript)) {
    throw "Source script not found: $sourceScript"
}

$targetScript = Join-Path $cmd_location "BootEntryManager.ps1"
Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force

Write-Host "Installed BootEntryManager to: $targetScript" -ForegroundColor Green
