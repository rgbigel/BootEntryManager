<#
Module: tools/Invoke-ElevatedTest.ps1
Purpose: Runs Pester test suites with automatic Administrator elevation handoff and structured JSON evidence generation.
Path: tools/Invoke-ElevatedTest.ps1
Authors: Rolf, Workspace_AI Engine
Version: 1.0.0
Date: 2026-08-16
Changelog:
- 2026-08-16: Initial standardized implementation of elevated test runner with JSON evidence streaming.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$TestPath = (Join-Path $PSScriptRoot '..\tests'),
    
    [Parameter(Mandatory=$false)]
    [string]$OutEvidencePath = (Join-Path $PSScriptRoot '..\out\test_results.json'),
    
    [Parameter(Mandatory=$false)]
    [switch]$ForceInProcess
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-ElevationRequired {
    param([string]$TargetRepoRoot)

    # 1. Check local .lcm/config.json
    $lcmConfigFile = Join-Path $TargetRepoRoot '.lcm\config.json'
    if (Test-Path $lcmConfigFile) {
        try {
            $cfg = Get-Content -Path $lcmConfigFile -Raw | ConvertFrom-Json
            if ($cfg.execution_context -and ($null -ne $cfg.execution_context.elevation_required)) {
                return [bool]$cfg.execution_context.elevation_required
            }
        } catch { }
    }

    # 2. Check Workspace_Inventory database cache
    $workspaceRoot = Split-Path $TargetRepoRoot -Parent
    $invPath = Join-Path $workspaceRoot 'Workspace_Inventory\data\inventory.json'
    if (Test-Path $invPath) {
        try {
            $inv = Get-Content -Path $invPath -Raw | ConvertFrom-Json
            $repoName = Split-Path $TargetRepoRoot -Leaf
            $repoRecord = $inv.repositories | Where-Object { $_.RepositoryName -eq $repoName } | Select-Object -First 1
            if ($repoRecord -and ($null -ne $repoRecord.ElevationRequired)) {
                return [bool]$repoRecord.ElevationRequired
            }
        } catch { }
    }

    return $false
}

$isAdmin = Test-IsAdmin
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$needsElevation = Test-ElevationRequired -TargetRepoRoot $repoRoot

$outDir = Split-Path $OutEvidencePath -Parent
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

if ($isAdmin -or (-not $needsElevation) -or $ForceInProcess) {
    # Elevated / In-Process Execution Mode
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host " Running Test Suite (Context: $(if ($isAdmin) { 'Elevated (Administrator)' } else { 'Standard User' }))" -ForegroundColor Cyan
    Write-Host " Repository Root: $repoRoot" -ForegroundColor Cyan
    Write-Host " Test Path      : $TestPath" -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan

    $pesterResults = Invoke-Pester -Path $TestPath -PassThru

    $passed = ($pesterResults.FailedCount -eq 0)
    $failedContainers = @()
    if ($pesterResults.PSObject.Properties['FailedContainers']) {
        $failedContainers = @($pesterResults.FailedContainers | ForEach-Object { $_.Name })
    }

    $duration = 0
    if ($pesterResults.PSObject.Properties['Time'] -and $pesterResults.Time) {
        $duration = [int]($pesterResults.Time.TotalMilliseconds)
    }

    $evidence = [ordered]@{
        '$schema'          = 'https://json-schema.org/draft/2020-12/schema'
        title              = 'Repository Test Execution Evidence'
        timestamp          = (Get-Date).ToString('o')
        repository_root    = $repoRoot
        elevation_context  = if ($isAdmin) { 'Administrator' } else { 'User' }
        total_count        = $pesterResults.TotalCount
        passed_count       = $pesterResults.PassedCount
        failed_count       = $pesterResults.FailedCount
        skipped_count      = $pesterResults.SkippedCount
        duration_ms        = $duration
        passed             = $passed
        failed_containers  = $failedContainers
    }

    $evidence | ConvertTo-Json -Depth 5 | Set-Content -Path $OutEvidencePath -Encoding UTF8
    Write-Host "`nTest evidence recorded: $OutEvidencePath" -ForegroundColor Green
    
    if (-not $passed) {
        throw "Pester test suite failed with $($pesterResults.FailedCount) failure(s)."
    }
} else {
    # Non-Elevated IDE / Runner Mode: Launch Elevated Process
    Write-Host "=================================================================" -ForegroundColor Yellow
    Write-Host " Elevation Required: Launching Elevated Test Runner             " -ForegroundColor Yellow
    Write-Host " Target Repository : $repoRoot" -ForegroundColor Yellow
    Write-Host " Evidence Path     : $OutEvidencePath" -ForegroundColor Yellow
    Write-Host "=================================================================" -ForegroundColor Yellow

    # Clear previous evidence file to ensure fresh results
    if (Test-Path $OutEvidencePath) {
        Remove-Item -Path $OutEvidencePath -Force
    }

    $scriptPath = $PSCommandPath
    $argList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$scriptPath`"",
        "-TestPath", "`"$TestPath`"",
        "-OutEvidencePath", "`"$OutEvidencePath`""
    )

    Write-Host "Dispatching elevated runner via Start-Process -Verb RunAs..." -ForegroundColor Cyan
    $process = Start-Process -FilePath "pwsh.exe" -ArgumentList $argList -Verb RunAs -PassThru -Wait

    Write-Host "Elevated process finished (ExitCode: $($process.ExitCode))." -ForegroundColor Cyan

    # Read back generated JSON evidence
    if (Test-Path $OutEvidencePath) {
        $evidenceData = Get-Content -Path $OutEvidencePath -Raw | ConvertFrom-Json
        Write-Host "`n=== Elevated Test Execution Summary ===" -ForegroundColor Green
        Write-Host "  Context      : $($evidenceData.elevation_context)" -ForegroundColor Green
        Write-Host "  Total Tests  : $($evidenceData.total_count)" -ForegroundColor Green
        Write-Host "  Passed Tests : $($evidenceData.passed_count)" -ForegroundColor Green
        Write-Host "  Failed Tests : $($evidenceData.failed_count)" -ForegroundColor $(if ($evidenceData.failed_count -gt 0) { 'Red' } else { 'Green' })
        Write-Host "  Duration     : $($evidenceData.duration_ms) ms" -ForegroundColor Green
        Write-Host "  Passed Gate  : $($evidenceData.passed)" -ForegroundColor $(if ($evidenceData.passed) { 'Green' } else { 'Red' })
        
        if (-not $evidenceData.passed) {
            throw "Elevated test suite reported $($evidenceData.failed_count) failure(s)."
        }
    } else {
        throw "Elevated test execution did not produce expected evidence at: $OutEvidencePath"
    }
}
