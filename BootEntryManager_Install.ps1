<#
.SYNOPSIS
    Installs BootEntryManager script to the runtime cmd directory.

.DESCRIPTION
    Copies Source\BootEntryManager.ps1 from the repository into the configured
    cmd target folder.

.PARAMETER cmd_location
    Target cmd directory. Default: D:\OneDrive\cmd

.PARAMETER HelpMode
    Shows full help and exits.
    Aliases: h, ?
#>

[CmdletBinding()]
param(
    [string]$cmd_location = "D:\OneDrive\cmd",
    [Alias("h","?")]
    [switch]$HelpMode
)

if ($HelpMode) {
    Get-Help $PSCommandPath -Full
    exit 0
}

$ErrorActionPreference = "Stop"

$sourceScript = Join-Path $PSScriptRoot "Source\BootEntryManager.ps1"
if (-not (Test-Path -LiteralPath $sourceScript)) {
    throw "Source script not found: $sourceScript"
}

$targetScript = Join-Path $cmd_location "BootEntryManager.ps1"
Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force

Write-Host "Installed BootEntryManager to: $targetScript" -ForegroundColor Green
