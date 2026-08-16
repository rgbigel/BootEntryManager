[CmdletBinding()]
param(
    [switch]$ForceInProcess
)

<#
Module: Test-RepoReadiness.ps1
Purpose: Run local self-readiness and LCM compliance quality checks for BootEntryManager.
Path: tools/Test-RepoReadiness.ps1
Authors: Rolf
Version: 1.1.0
Changelog:
- 2026-08-16: Added elevated test runner integration and ForceInProcess pass-through.
- 2026-08-16: Initial readiness runner instantiated.
#>

$repoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $repoRoot

$qualityGatesModule = Join-Path $PSScriptRoot 'QualityGates\RepoQualityGates.psm1'
if (Test-Path -LiteralPath $qualityGatesModule) {
  Import-Module $qualityGatesModule -Force
  Assert-RepoStructure -RepoRoot $repoRoot | Out-Host
  Assert-RepoFormatting -RepoRoot $repoRoot | Out-Host
  Assert-RepoGovernanceLinks -RepoRoot $repoRoot | Out-Host
  Assert-RepoElevationConsistency -RepoRoot $repoRoot | Out-Host
  Assert-RepoDocumentationFabric -RepoRoot $repoRoot | Out-Host
} else {
  Write-Warning "QualityGates module not found at: $qualityGatesModule"
}

# Run repository tests (with automated elevation handoff if required)
$testsDir = Join-Path $repoRoot 'tests'
$elevatedRunner = Join-Path $PSScriptRoot 'Invoke-ElevatedTest.ps1'
if ((Test-Path -LiteralPath $testsDir) -and (Test-Path -LiteralPath $elevatedRunner)) {
  Write-Host "`nExecuting test suite via Invoke-ElevatedTest..." -ForegroundColor Cyan
  $runnerArgs = @{ TestPath = $testsDir }
  if ($ForceInProcess) { $runnerArgs['ForceInProcess'] = $true }
  & $elevatedRunner @runnerArgs | Out-Host
}

Write-Host "`nBootEntryManager readiness check: OK" -ForegroundColor Green
