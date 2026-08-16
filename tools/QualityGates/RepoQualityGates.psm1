<#
Module: RepoQualityGates.psm1
Purpose: Local quality gate assertions for {{REPO_NAME}}.
Path: tools/QualityGates/RepoQualityGates.psm1
Authors: {{AUTHOR}}
Version: 1.2.0
Changelog:
- 2026-08-16: Added Assert-RepoDocumentationFabric gate validating System Prerequisites and DOX compliance under LCM v4.2.0.
- 2026-08-16: Added Assert-RepoElevationConsistency gate enforcing RULE-ELEV-001 through RULE-ELEV-004.
- {{DATE}}: Initial quality gate module instantiated.
#>

function Assert-RepoStructure {
  [CmdletBinding()]
  param([string]$RepoRoot)

  $requiredPaths = @(
    (Join-Path $RepoRoot 'docs\README.md'),
    (Join-Path $RepoRoot '.lcm\config.json'),
    (Join-Path $RepoRoot '.lcm\overrides.json'),
    (Join-Path $RepoRoot '.vscode\settings.json')
  )

  foreach ($req in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $req)) {
      throw "Missing required repository structure file: $req"
    }
  }

  return [pscustomobject]@{
    Status = 'OK'
    Structure = 'Valid'
    CheckedFiles = $requiredPaths.Count
  }
}

function Assert-RepoFormatting {
  [CmdletBinding()]
  param([string]$RepoRoot)

  $files = Get-ChildItem -Path $RepoRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\\.git\\' -and $_.FullName -notmatch '\\\.agents\\rules\\core\\'
  }

  $issues = @()
  foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
      $issues += "$($f.Name): Contains UTF-8 BOM"
    }
  }

  if ($issues.Count -gt 0) {
    throw ("Formatting violations detected: " + ($issues -join '; '))
  }

  return [pscustomobject]@{
    Status = 'OK'
    Formatting = 'Valid'
    ScannedFiles = $files.Count
  }
}

function Assert-RepoGovernanceLinks {
  [CmdletBinding()]
  param([string]$RepoRoot)

  # 1. Verify AGENTS.md exists at repository root
  $agentsMd = Join-Path $RepoRoot 'AGENTS.md'
  if (-not (Test-Path -LiteralPath $agentsMd)) {
    throw "Missing AGENTS.md governance pointer at: $agentsMd"
  }

  # 2. Verify root governance rules are accessible from workspace parent
  $wsRoot = Split-Path $RepoRoot -Parent
  $rootRules = Join-Path $wsRoot '.agents\rules'
  if (-not (Test-Path -LiteralPath $rootRules)) {
    $rootRules = Join-Path $wsRoot 'Workspace_AI\.agents\rules'
  }
  if (-not (Test-Path -LiteralPath $rootRules)) {
    throw "Root governance rules not found at: $rootRules"
  }

  # 3. Assert zero duplicated rule folders in child repository
  $duplicateCoreRules = Join-Path $RepoRoot '.agents\rules\core'
  if (Test-Path -LiteralPath $duplicateCoreRules) {
    throw "Redundant rule duplication detected: $duplicateCoreRules. Child repositories must inherit from root $rootRules directly without local rule copies."
  }

  return [pscustomobject]@{
    Status = 'OK'
    GovernanceInheritance = 'Valid'
    RootRulesPath = $rootRules
  }
}

function Assert-RepoElevationConsistency {
  [CmdletBinding()]
  param([string]$RepoRoot)

  # 1. Validate .lcm/config.json has execution_context
  $cfgPath = Join-Path $RepoRoot '.lcm\config.json'
  if (-not (Test-Path -LiteralPath $cfgPath)) {
    throw "Missing .lcm/config.json for elevation consistency check at: $cfgPath"
  }

  $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
  if (-not $cfg.execution_context -or ($null -eq $cfg.execution_context.elevation_required)) {
    throw "Missing mandatory 'execution_context.elevation_required' block in $cfgPath (RULE-ELEV-001 violation)."
  }

  $declaredElevation = [bool]$cfg.execution_context.elevation_required

  # 2. Scan source files in src/ or Source/ for privileged/self-elevating code
  $srcDir = Join-Path $RepoRoot 'src'
  if (-not (Test-Path $srcDir)) { $srcDir = Join-Path $RepoRoot 'Source' }
  
  $detectedPatterns = @()
  if (Test-Path $srcDir) {
    $privilegedPatterns = @(
      'bcdedit',
      'fltmc',
      'fsutil\s+fsinfo',
      'DiskPart',
      'Start-Process.*-Verb\s+RunAs',
      'Get-Partition\b',
      'Add-BitLockerKeyProtector'
    )
    $codeFiles = Get-ChildItem -Path $srcDir -Include '*.ps1', '*.psm1', '*.cs', '*.cpp' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\\.git\\' }
    foreach ($cf in $codeFiles) {
      $text = Get-Content -Path $cf.FullName -Raw -ErrorAction SilentlyContinue
      if ($text) {
        foreach ($pattern in $privilegedPatterns) {
          if ($text -match "(?im)$pattern") {
            $detectedPatterns += "$($cf.Name) ($pattern)"
          }
        }
      }
    }
  }

  # Bi-directional consistency assertions
  if ($detectedPatterns.Count -gt 0 -and -not $declaredElevation) {
    throw "Elevation consistency violation (RULE-ELEV-003): Privileged/self-elevating code detected in source files [$($detectedPatterns -join ', ')], but .lcm/config.json declares 'elevation_required: false'."
  }

  # If elevation_required is true, verify tools/Invoke-ElevatedTest.ps1 exists
  if ($declaredElevation) {
    $elevatedRunner = Join-Path $RepoRoot 'tools\Invoke-ElevatedTest.ps1'
    if (-not (Test-Path -LiteralPath $elevatedRunner)) {
      throw "Elevation consistency violation (RULE-ELEV-004): 'elevation_required: true' is configured, but mandatory runner 'tools/Invoke-ElevatedTest.ps1' is missing."
    }
  }

  return [pscustomobject]@{
    Status               = 'OK'
    ElevationConsistency = 'Valid'
    DeclaredElevation    = $declaredElevation
    PrivilegedPatterns   = $detectedPatterns.Count
  }
}

function Assert-RepoDocumentationFabric {
  [CmdletBinding()]
  param([string]$RepoRoot)

  # 1. Assert top-level README.md exists and has ## System Prerequisites
  $readmePath = Join-Path $RepoRoot 'README.md'
  if (-not (Test-Path -LiteralPath $readmePath)) {
    throw "Missing top-level README.md (DOX violation)."
  }

  $readmeText = Get-Content -LiteralPath $readmePath -Raw
  if ($readmeText -notmatch '(?im)##\s+.*Prerequisites') {
    throw "README.md is missing mandatory '## System Prerequisites' section (DOX violation)."
  }

  # 2. Assert docs/README.md exists
  $docsReadme = Join-Path $RepoRoot 'docs\README.md'
  if (-not (Test-Path -LiteralPath $docsReadme)) {
    throw "Missing docs/README.md documentation index."
  }

  # 3. Assert .github/agents/RepoAgentIndex.md exists
  $agentIndex = Join-Path $RepoRoot '.github\agents\RepoAgentIndex.md'
  if (-not (Test-Path -LiteralPath $agentIndex)) {
    throw "Missing .github/agents/RepoAgentIndex.md agent mapping."
  }

  return [pscustomobject]@{
    Status               = 'OK'
    DocumentationFabric  = 'Valid'
    HasPrerequisites     = $true
    HasAgentIndex        = $true
  }
}

Export-ModuleMember -Function Assert-RepoStructure, Assert-RepoFormatting, Assert-RepoGovernanceLinks, Assert-RepoElevationConsistency, Assert-RepoDocumentationFabric
