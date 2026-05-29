# BootEntryManager.ps1
# Version: 2.0.0
# Purpose: Manage Windows Boot Manager entries (rename, delete, set default)
# Changes in 2.0.0:
# - Finalized menu-first then entries output layout.
# - Improved spinner clear behavior to fully erase the symbol line.
# - Corrected Linux type fallback behavior for unresolved Ubuntu entries.
# - Added stale marker (s) and alias marker (a) support in Volume # values.
# - Minimized Volume # and Type columns with dynamic aligned widths.

param(
    [string]$LoadBackupFileName
)


$ErrorActionPreference = "Stop"

# --- CONFIG -------------------------------------------------------------------

$BackupDir = "D:\OneDrive\Documents\Einstellungen\BCD"
$BcdEditExe = Join-Path $env:WINDIR "System32\bcdedit.exe"
$HasInitialBackupBeenDone = $false
$ScriptVersion = "2.0.0"

function Get-EfiSystemPartitionVolume {
    $efiGuid = "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}"
    $efiPartition = Get-Partition | Where-Object { $_.GptType -eq $efiGuid } | Select-Object -First 1
    if (-not $efiPartition) {
        throw "EFI System Partition not found."
    }

    $efiVolume = $efiPartition | Get-Volume -ErrorAction Stop
    if (-not $efiVolume) {
        throw "EFI System Partition volume not found."
    }

    return $efiVolume
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    param([string]$LoadBackupFileName)

    $shellExe = if ($PSVersionTable.PSEdition -eq "Core") {
        Join-Path $PSHOME "pwsh.exe"
    }
    else {
        Join-Path $PSHOME "powershell.exe"
    }

    if (-not (Test-Path -LiteralPath $shellExe)) {
        $shellExe = "powershell.exe"
    }

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $PSCommandPath)
    )

    if (-not [string]::IsNullOrWhiteSpace($LoadBackupFileName)) {
        $arguments += @("-LoadBackupFileName", ('"{0}"' -f $LoadBackupFileName))
    }

    Start-Process -FilePath $shellExe -ArgumentList $arguments -Verb RunAs | Out-Null
}

if (-not (Test-IsAdministrator)) {
    try {
        Restart-Elevated -LoadBackupFileName $LoadBackupFileName
    }
    catch {
        Write-Host "Administrator elevation failed or was canceled." -ForegroundColor Red
    }
    return
}

function Start-BusyRotator {
    param(
        [string]$Message = "Initializing"
    )

    $sourceId = "BootEntryManager.BusyRotator"
    $frames = @("|", "/", "-", "\\")

    Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
    Get-Job -Name $sourceId -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue

    $timer = New-Object System.Timers.Timer
    $timer.Interval = 120
    $timer.AutoReset = $true

    Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $sourceId -MessageData @{
        Message = $Message
        Frames  = $frames
        Index   = 0
    } -Action {
        $state = $event.MessageData
        $frame = $state.Frames[$state.Index]
        $state.Index = ($state.Index + 1) % $state.Frames.Count
        Write-Host -NoNewline ("`r{0} {1}" -f $state.Message, $frame)
    } | Out-Null

    $timer.Start()

    [PSCustomObject]@{
        Timer    = $timer
        SourceId = $sourceId
    }
}

function Stop-BusyRotator {
    param(
        [pscustomobject]$Handle
    )

    if ($null -eq $Handle) { return }

    try {
        $Handle.Timer.Stop()
    }
    catch {
    }

    try {
        $Handle.Timer.Dispose()
    }
    catch {
    }

    Unregister-Event -SourceIdentifier $Handle.SourceId -ErrorAction SilentlyContinue
    Get-Job -Name $Handle.SourceId -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue

    # Clear the spinner line before showing regular output.
    $clearWidth = 120
    try {
        if ($Host -and $Host.UI -and $Host.UI.RawUI) {
            $clearWidth = [Math]::Max(120, ($Host.UI.RawUI.WindowSize.Width - 1))
        }
    }
    catch {
    }

    Write-Host -NoNewline ("`r{0}`r" -f (" " * $clearWidth))
}

if (-not ("NativeMethods" -as [type])) {
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class NativeMethods {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint QueryDosDevice(string lpDeviceName, StringBuilder lpTargetPath, int ucchMax);
}
"@
}

function Get-DriveLetterFromNtDevicePath {
    param([string]$NtDevicePath)

    if ([string]::IsNullOrWhiteSpace($NtDevicePath)) { return $null }

    $normalizedPath = $NtDevicePath.Trim()
    foreach ($letter in ([char[]](65..90) | ForEach-Object { [string]$_ })) {
        $drive = "${letter}:"
        $targetPath = New-Object System.Text.StringBuilder 1024
        $result = [NativeMethods]::QueryDosDevice($drive, $targetPath, $targetPath.Capacity)
        if ($result -gt 0) {
            $resolved = $targetPath.ToString().Split([char]0)[0]
            if ($resolved -ieq $normalizedPath) {
                return $drive
            }
        }
    }

    return $null
}

function Get-BootVolumeLabel {
    $volume = Get-EfiSystemPartitionVolume
    $label = [string]$volume.FileSystemLabel
    if ([string]::IsNullOrWhiteSpace($label)) {
        throw "EFI System Partition volume label is empty."
    }

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($invalidChar in $invalidChars) {
        $label = $label.Replace([string]$invalidChar, "_")
    }

    $label.Trim()
}

# --- HELPERS ------------------------------------------------------------------

function Write-Log {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "$timestamp  $Message"
}

function Ensure-BackupDir {
    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
    }
}

function Invoke-WithBusyRotator {
    param(
        [string]$Message,
        [scriptblock]$Action
    )

    $handle = Start-BusyRotator -Message $Message
    try {
        & $Action
    }
    finally {
        Stop-BusyRotator -Handle $handle
    }
}

$startupRotator = Start-BusyRotator -Message "Loading BootEntryManager"
try {
    $script:BootVolumeLabel = Get-BootVolumeLabel
    $script:SessionTime = Get-Date
    $logTimestampPart = $script:SessionTime.ToString("yyyyMMdd HHmm").Trim()
    $logBootVolumePart = $script:BootVolumeLabel.Trim()
    $logSystemNamePart = $env:COMPUTERNAME.Trim()
    $logNameParts = @($logTimestampPart, $logBootVolumePart, $logSystemNamePart) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $LogFile = Join-Path $BackupDir ((($logNameParts -join " ").Trim()) + ".log")

    Ensure-BackupDir
}
finally {
    Stop-BusyRotator -Handle $startupRotator
}

function Get-BackupFilePath {
    $timestampPart = (Get-Date).ToString("yyMMdd_HHmmss").Trim()
    $bootVolumePart = $script:BootVolumeLabel.Trim()
    $systemNamePart = $env:COMPUTERNAME.Trim()

    $fileName = ("{0} BootEntryManager - {1} - {2}.bak" -f $timestampPart, $bootVolumePart, $systemNamePart).Trim()

    Join-Path $BackupDir $fileName
}

function Get-SymbolicIdentifierMap {
    $map = @{}

    $nonVerbose = & $BcdEditExe /enum all 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "bcdedit /enum all failed while building symbolic identifier map"
    }

    $aliases = [regex]::Matches($nonVerbose, "(?im)^\s*identifier\s+(\{[^}]+\})") |
        ForEach-Object { $_.Groups[1].Value.ToLower() } |
        Where-Object { $_ -notmatch "^\{[0-9a-f-]{36}\}$" } |
        Select-Object -Unique

    foreach ($alias in $aliases) {
        $resolved = & $BcdEditExe /enum "$alias" /v 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { continue }

        if ($resolved -match "(?im)^\s*identifier\s+(\{[0-9a-f-]{36}\})") {
            $guid = $matches[1].ToLower()
            if (-not $map.ContainsKey($guid)) {
                $map[$guid] = $alias
            }
        }
    }

    return $map
}

function Export-BCDTextBackup {
    param([string]$OutputPath)

    $symbolMap = Get-SymbolicIdentifierMap

    $verbose = & $BcdEditExe /enum all /v 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "bcdedit /enum all /v failed while creating text backup"
    }

    $descByGuid = @{}
    $blocks = [regex]::Split($verbose.Trim(), "(?:`r?`n){2,}")
    foreach ($block in $blocks) {
        if ($block -match "(?im)^\s*identifier\s+(\{[0-9a-f-]{36}\})") {
            $guid = $matches[1].ToLower()
            $desc = ""
            if ($block -match "(?im)^\s*description\s+(.+)$") {
                $desc = $matches[1].Trim()
            }

            $descByGuid[$guid] = $desc
        }
    }

    $resultLines = foreach ($line in ($verbose -split "`r?`n")) {
        $guidMatches = [regex]::Matches($line, "\{[0-9a-fA-F-]{36}\}")
        if ($guidMatches.Count -eq 0) {
            $line
            continue
        }

        $aliases = $guidMatches |
            ForEach-Object { $_.Value.ToLower() } |
            Where-Object { $symbolMap.ContainsKey($_) } |
            ForEach-Object { $symbolMap[$_] } |
            Select-Object -Unique

        $descriptions = $guidMatches |
            ForEach-Object { $_.Value.ToLower() } |
            Where-Object { $descByGuid.ContainsKey($_) } |
            ForEach-Object { $descByGuid[$_] } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique

        $suffixParts = @()
        if ($descriptions -and $descriptions.Count -gt 0) {
            $suffixParts += ($descriptions -join ", ")
        }

        if ($aliases -and $aliases.Count -gt 0) {
            $suffixParts += ($aliases -join ", ")
        }

        if (-not $suffixParts -or $suffixParts.Count -eq 0) {
            $line
            continue
        }

        "{0}  | {1}" -f $line, ($suffixParts -join " | ")
    }

    Set-Content -Path $OutputPath -Value $resultLines -Encoding UTF8
}

function Resolve-BackupFilePath {
    param([string]$BackupFileName)

    if ([string]::IsNullOrWhiteSpace($BackupFileName)) { return $null }

    $fileNameOnly = [System.IO.Path]::GetFileName($BackupFileName.Trim())
    if ([string]::IsNullOrWhiteSpace($fileNameOnly)) { return $null }

    Join-Path $BackupDir $fileNameOnly
}

function Import-BCDFromBackup {
    param(
        [string]$BackupFileName,
        [string]$Reason = "LOAD"
    )

    $backupFilePath = Resolve-BackupFilePath -BackupFileName $BackupFileName
    if ([string]::IsNullOrWhiteSpace($backupFilePath)) {
        Write-Host "Invalid backup file name." -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path -LiteralPath $backupFilePath)) {
        Write-Host "Backup file not found: $backupFilePath" -ForegroundColor Yellow
        return
    }

    Ensure-InitialBackupBeforeChange
    Invoke-WithBusyRotator -Message "Importing BCD from backup" -Action {
        & $BcdEditExe /import "$backupFilePath"
    }
    Write-Log "IMPORT [$Reason]: BCD imported from '$backupFilePath'"
}

function Select-TextBackupFilePath {
    $textFiles = Get-ChildItem -Path $BackupDir -File -Filter "*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if (-not $textFiles -or $textFiles.Count -eq 0) {
        Write-Host "No text backup files found in $BackupDir" -ForegroundColor Yellow
        return $null
    }

    Write-Host ""
    Write-Host "Available text backup files:" -ForegroundColor Cyan
    $index = 1
    foreach ($file in $textFiles) {
        Write-Host ("[{0}] {1}" -f $index, $file.Name)
        $index++
    }

    $choice = Read-Host "Select text backup number (or press Enter to cancel)"
    if ([string]::IsNullOrWhiteSpace($choice)) { return $null }

    $selectedIndex = 0
    $isInt = [int]::TryParse($choice, [ref]$selectedIndex)
    if (-not $isInt -or $selectedIndex -lt 1 -or $selectedIndex -gt $textFiles.Count) {
        Write-Host "Invalid selection." -ForegroundColor Yellow
        return $null
    }

    return $textFiles[$selectedIndex - 1].FullName
}

function Open-TextBackupReport {
    $selectedPath = Select-TextBackupFilePath
    if ([string]::IsNullOrWhiteSpace($selectedPath)) { return }

    $notepadPlusPlusPaths = @(
        "C:\Program Files\Notepad++\notepad++.exe",
        "C:\Program Files (x86)\Notepad++\notepad++.exe"
    )

    $editor = $null
    foreach ($candidate in $notepadPlusPlusPaths) {
        if (Test-Path -LiteralPath $candidate) {
            $editor = $candidate
            break
        }
    }

    if ($null -eq $editor) {
        $cmd = Get-Command "notepad++.exe" -ErrorAction SilentlyContinue
        if ($cmd) {
            $editor = $cmd.Source
        }
    }

    if ([string]::IsNullOrWhiteSpace($editor)) {
        $editor = "notepad.exe"
    }

    Start-Process -FilePath $editor -ArgumentList ('"{0}"' -f $selectedPath) | Out-Null
    Write-Log "OPEN REPORT: '$selectedPath'"
}

function Select-BackupFileName {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.InitialDirectory = $BackupDir
        $dialog.Filter = "BCD backup files (*.bak)|*.bak|All files (*.*)|*.*"
        $dialog.Multiselect = $false

        $result = $dialog.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrWhiteSpace($dialog.FileName)) {
            return [System.IO.Path]::GetFileName($dialog.FileName)
        }
    }
    catch {
    }

    $backupFiles = Get-ChildItem -Path $BackupDir -File -Filter "*.bak" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if (-not $backupFiles -or $backupFiles.Count -eq 0) {
        Write-Host "No backup files found in $BackupDir" -ForegroundColor Yellow
        return $null
    }

    Write-Host ""
    Write-Host "Available backup files:" -ForegroundColor Cyan
    $index = 1
    foreach ($file in $backupFiles) {
        Write-Host ("[{0}] {1}" -f $index, $file.Name)
        $index++
    }

    $choice = Read-Host "Select backup number (or press Enter to cancel)"
    if ([string]::IsNullOrWhiteSpace($choice)) { return $null }

    $selectedIndex = 0
    $isInt = [int]::TryParse($choice, [ref]$selectedIndex)
    if (-not $isInt -or $selectedIndex -lt 1 -or $selectedIndex -gt $backupFiles.Count) {
        Write-Host "Invalid selection." -ForegroundColor Yellow
        return $null
    }

    $backupFiles[$selectedIndex - 1].Name
}

function Backup-BCD {
    param(
        [string]$Reason = "MANUAL"
    )

    Ensure-BackupDir
    $backupFile = Get-BackupFilePath
    $backupTextFile = [System.IO.Path]::ChangeExtension($backupFile, ".txt")
    Invoke-WithBusyRotator -Message "Creating BCD backup" -Action {
        & $BcdEditExe /export "$backupFile"
        Export-BCDTextBackup -OutputPath $backupTextFile
    }

    foreach ($suffix in @(".LOG", ".LOG1", ".LOG2")) {
        $sidecarPath = "$backupFile$suffix"
        if (Test-Path -LiteralPath $sidecarPath) {
            Remove-Item -LiteralPath $sidecarPath -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Log "BACKUP [$Reason]: BCD exported to '$backupFile' and '$backupTextFile'"
    $script:HasInitialBackupBeenDone = $true
}

function Ensure-InitialBackupBeforeChange {
    if (-not $script:HasInitialBackupBeenDone) {
        Backup-BCD -Reason "INITIAL"
    }
}

function Get-NormalizedPartitionValue {
    param(
        [string]$Device
    )

    if ([string]::IsNullOrWhiteSpace($Device)) { return "" }
    $raw = $Device.Trim()
    if ($raw -match "(?i)^partition=(.+)$") {
        return $matches[1].Trim().ToLower()
    }

    return $raw.ToLower()
}

function Resolve-EfiTargetInfo {
    param(
        [string]$Device,
        [string]$Path
    )

    $normalizedDevice = Get-NormalizedPartitionValue -Device $Device
    $resolvedRoot = ""
    $resolvedDrive = ""
    $targetPath = ""
    $pathResolved = $false
    $pathExists = $false

    if ($normalizedDevice -match "(?i)^[A-Z]:$") {
        $resolvedDrive = $normalizedDevice.ToUpper()
        $resolvedRoot = "$resolvedDrive\"
    }
    elseif ($normalizedDevice -match "(?i)^\\Device\\HarddiskVolume\d+$") {
        $resolvedRoot = "\\?\GLOBALROOT$normalizedDevice"
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedRoot) -and -not [string]::IsNullOrWhiteSpace($Path)) {
        $normalizedPath = $Path.Trim().Replace('/', '\\')
        if (-not $normalizedPath.StartsWith("\\")) {
            $normalizedPath = "\\$normalizedPath"
        }

        if ($resolvedRoot.EndsWith("\\")) {
            $targetPath = "$resolvedRoot$($normalizedPath.TrimStart('\\'))"
        }
        else {
            $targetPath = "$resolvedRoot$normalizedPath"
        }

        $pathResolved = $true
        $pathExists = Test-Path -LiteralPath $targetPath -PathType Leaf -ErrorAction SilentlyContinue
    }

    [PSCustomObject]@{
        NormalizedDevice = $normalizedDevice
        ResolvedRoot     = $resolvedRoot
        ResolvedDrive    = $resolvedDrive
        TargetPath       = $targetPath
        PathResolved     = $pathResolved
        PathExists       = [bool]$pathExists
    }
}

function Get-SpecifiedValue {
    param(
        [string]$Device,
        [bool]$IsDefault,
        [bool]$IsAlias,
        [bool]$IsStale
    )

    $partition = ""
    if ($Device -match "(?i)^partition=(.+)$") {
        $partition = $matches[1].Trim()
    }

    if ($partition -match "(?i)^\\Device\\HarddiskVolume(\d+)$") {
        $partition = "Vol $($matches[1])"
    }

    $value = if ([string]::IsNullOrWhiteSpace($partition)) { "" } else { $partition }
    if ($IsDefault) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = "**"
        }
        else {
            $value = "$value **"
        }
    }

    $markers = @()
    if ($IsAlias) {
        $markers += "a"
    }

    if ($IsStale) {
        $markers += "s"
    }

    if ($markers.Count -gt 0) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            return ($markers -join " ")
        }

        return ("{0} {1}" -f $value, ($markers -join " "))
    }

    return $value
}

# --- REAL BOOT MENU PARSER ----------------------------------------------------

function Get-BootEntries {
    $bootmgr = ""
    $all = ""

    try {
        $bootmgr = & $BcdEditExe /enum "{bootmgr}" /v 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "bcdedit /enum {bootmgr} /v failed" }

        $all = & $BcdEditExe /enum all /v 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "bcdedit /enum all /v failed" }
    }
    catch {
        Write-Warning "Unable to read BCD entries. Run PowerShell as Administrator."
        Write-Log "ERROR: Get-BootEntries failed: $($_.Exception.Message)"
        return @()
    }

    # Build identifier -> description map from full BCD output.
    $descById = @{}
    $hasDescById = @{}
    $pathById = @{}
    $deviceById = @{}
    $systemRootById = @{}
    $winPeById = @{}
    $objectTypeById = @{}
    $blocks = [regex]::Split($all.Trim(), "(?:`r?`n){2,}")
    foreach ($block in $blocks) {
        if ($block -match "(?im)^\s*identifier\s+(\{[^}]+\})") {
            $id = $matches[1].ToLower()
            $objectType = (($block -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1).Trim()
            $desc = ""
            if ($block -match "(?im)^\s*description\s+(.+)$") {
                $desc = $matches[1].Trim()
                $hasDescById[$id] = $true
            }
            else {
                $hasDescById[$id] = $false
            }

            $path = ""
            if ($block -match "(?im)^\s*path\s+(.+)$") {
                $path = $matches[1].Trim()
            }

            $device = ""
            if ($block -match "(?im)^\s*device\s+(.+)$") {
                $device = $matches[1].Trim()
            }

            $systemRoot = ""
            if ($block -match "(?im)^\s*systemroot\s+(.+)$") {
                $systemRoot = $matches[1].Trim()
            }

            $winPe = ""
            if ($block -match "(?im)^\s*winpe\s+(.+)$") {
                $winPe = $matches[1].Trim()
            }

            $descById[$id] = $desc
            $pathById[$id] = $path
            $deviceById[$id] = $device
            $systemRootById[$id] = $systemRoot
            $winPeById[$id] = $winPe
            $objectTypeById[$id] = $objectType
        }
    }

    # Resolve aliases if displayorder contains {current} or {default}.
    $currentId = $null
    $currentInfo = & $BcdEditExe /enum "{current}" /v 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $currentInfo -match "(?im)^\s*identifier\s+(\{[^}]+\})") {
        $currentId = $matches[1].ToLower()
    }

    $defaultId = $null
    if ($bootmgr -match "(?im)^\s*default\s+(\{[^}]+\})") {
        $defaultId = $matches[1].ToLower()
    }

    $preferredEfiDevice = ""
    if ($bootmgr -match "(?im)^\s*device\s+(.+)$") {
        $preferredEfiDevice = Get-NormalizedPartitionValue -Device $matches[1]
    }

    # Read only displayorder entries in order as shown by boot manager.
    $order = New-Object System.Collections.Generic.List[string]
    $inDisplayOrder = $false
    foreach ($line in $bootmgr -split "`r?`n") {
        if ($line -match "(?im)^\s*displayorder\s+(\{[^}]+\})") {
            [void]$order.Add($matches[1].ToLower())
            $inDisplayOrder = $true
            continue
        }

        if ($inDisplayOrder) {
            if ($line -match "^\s+(\{[^}]+\})") {
                [void]$order.Add($matches[1].ToLower())
                continue
            }

            $inDisplayOrder = $false
        }
    }

    # Remove duplicates while preserving order.
    $seen = @{}
    $entries = @()
    $fingerprintsById = @{}
    foreach ($id in $order) {
        $resolved = $id
        if ($id -eq "{current}" -and $currentId) { $resolved = $currentId }
        if ($id -eq "{default}" -and $defaultId) { $resolved = $defaultId }

        if (-not $seen.ContainsKey($resolved)) {
            $seen[$resolved] = $true

            $desc = if ($descById.ContainsKey($resolved)) { $descById[$resolved] } else { "" }
            $hasDesc = $hasDescById.ContainsKey($resolved) -and $hasDescById[$resolved]
            $path = if ($pathById.ContainsKey($resolved)) { $pathById[$resolved] } else { "" }
            $device = if ($deviceById.ContainsKey($resolved)) { $deviceById[$resolved] } else { "" }
            $systemRoot = if ($systemRootById.ContainsKey($resolved)) { $systemRootById[$resolved] } else { "" }
            $winPe = if ($winPeById.ContainsKey($resolved)) { $winPeById[$resolved] } else { "" }
            $objectType = if ($objectTypeById.ContainsKey($resolved)) { $objectTypeById[$resolved] } else { "" }

            # Hide only the Windows Boot Manager self-entry from displayorder.
            $isFirmwareApplication = $objectType -match "(?i)^Firmware\s+Application\b"
            $isWindowsBootManagerSelfEntry =
                ($desc -match "(?i)^Windows\s+Boot\s+Manager$") -and
                ($path -match "(?i)^\\EFI\\MICROSOFT\\BOOT\\BOOTMGFW\.EFI$")

            if ($isFirmwareApplication -and $isWindowsBootManagerSelfEntry) {
                continue
            }

            if (-not $hasDesc) {
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    $desc = "(unnamed entry) path: $path"
                }
                elseif (-not [string]::IsNullOrWhiteSpace($device)) {
                    $desc = "(unnamed entry) device: $device"
                }
                else {
                    $desc = "(empty BCD entry)"
                }
            }

            $fingerprintsById[$resolved] = @(
                $device.Trim().ToLower(),
                $path.Trim().ToLower(),
                $systemRoot.Trim().ToLower(),
                $winPe.Trim().ToLower()
            ) -join "|"

            $entries += [PSCustomObject]@{
                GUID        = $resolved
                IsDefault   = ($defaultId -and $resolved -eq $defaultId)
                Device      = $device
                Path        = $path
                ObjectType  = $objectType
                Description = $desc
            }
        }
    }

    $duplicatePathCount = @{}
    foreach ($entry in $entries) {
        $isFirmwareApplication = $entry.ObjectType -match "(?i)^Firmware\s+Application\b"
        $targetInfo = Resolve-EfiTargetInfo -Device $entry.Device -Path $entry.Path
        $entry | Add-Member -NotePropertyName IsFirmwareApplication -NotePropertyValue ([bool]$isFirmwareApplication)
        $entry | Add-Member -NotePropertyName PathResolved -NotePropertyValue ([bool]$targetInfo.PathResolved)
        $entry | Add-Member -NotePropertyName PathExists -NotePropertyValue ([bool]$targetInfo.PathExists)
        $entry | Add-Member -NotePropertyName TargetPath -NotePropertyValue $targetInfo.TargetPath
        $entry | Add-Member -NotePropertyName ResolvedDrive -NotePropertyValue $targetInfo.ResolvedDrive
        $entry | Add-Member -NotePropertyName MatchesPreferredEsp -NotePropertyValue ([bool]($targetInfo.NormalizedDevice -eq $preferredEfiDevice))

        if ($isFirmwareApplication -and $targetInfo.PathExists -and -not [string]::IsNullOrWhiteSpace($entry.Path)) {
            $pathKey = $entry.Path.Trim().ToLower()
            if (-not $duplicatePathCount.ContainsKey($pathKey)) {
                $duplicatePathCount[$pathKey] = 0
            }

            $duplicatePathCount[$pathKey]++
        }
    }

    foreach ($entry in $entries) {
        $status = ""
        $partitionType = ""

        if ($entry.ResolvedDrive) {
            try {
                $partitionType = (Get-Volume -DriveLetter $entry.ResolvedDrive.TrimEnd(':') -ErrorAction Stop).FileSystemType
            }
            catch {
                $partitionType = ""
            }
        }
        if ([string]::IsNullOrWhiteSpace($partitionType) -and
            $entry.IsFirmwareApplication -and
            -not [string]::IsNullOrWhiteSpace($entry.Path) -and
            $entry.Path -match "(?i)\\EFI\\ubuntu\\") {
            $partitionType = "Linux"
        }

        if ($entry.IsFirmwareApplication) {
            if ([string]::IsNullOrWhiteSpace($entry.Path)) {
                $status = "CHECK"
            }
            elseif (-not $entry.PathResolved) {
                $status = "CHECK"
            }
            elseif (-not $entry.PathExists) {
                $status = "STALE"
            }
            else {
                $isDuplicateValidPath = $false
                $pathKey = $entry.Path.Trim().ToLower()
                if ($duplicatePathCount.ContainsKey($pathKey)) {
                    $isDuplicateValidPath = $duplicatePathCount[$pathKey] -gt 1
                }

                if ($isDuplicateValidPath) {
                    $status = "DUPLICATE"
                }
                elseif (-not [string]::IsNullOrWhiteSpace($preferredEfiDevice) -and -not $entry.MatchesPreferredEsp) {
                    $status = "OTHER ESP"
                }
                else {
                    $status = "OK"
                }
            }
        }

        $entry | Add-Member -NotePropertyName EntryStatus -NotePropertyValue $status
        $entry | Add-Member -NotePropertyName PartitionType -NotePropertyValue $partitionType
    }

    $fingerprintCounts = @{}
    foreach ($fingerprint in $fingerprintsById.Values) {
        if ([string]::IsNullOrWhiteSpace($fingerprint.Replace("|", ""))) { continue }

        if (-not $fingerprintCounts.ContainsKey($fingerprint)) {
            $fingerprintCounts[$fingerprint] = 0
        }

        $fingerprintCounts[$fingerprint]++
    }

    foreach ($entry in $entries) {
        $fingerprint = $fingerprintsById[$entry.GUID]
        $isAlias = $fingerprintCounts.ContainsKey($fingerprint) -and $fingerprintCounts[$fingerprint] -gt 1
        $isStale = ($entry.EntryStatus -eq "STALE")
        $entry | Add-Member -NotePropertyName Specified -NotePropertyValue (Get-SpecifiedValue -Device $entry.Device -IsDefault ([bool]$entry.IsDefault) -IsAlias $isAlias -IsStale $isStale)
    }

    $entries
}

function Get-DanglingDisplayOrderEntries {
    $bootmgr = ""
    $all = ""

    try {
        $bootmgr = & $BcdEditExe /enum "{bootmgr}" /v 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "bcdedit /enum {bootmgr} /v failed" }

        $all = & $BcdEditExe /enum all /v 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "bcdedit /enum all /v failed" }
    }
    catch {
        Write-Warning "Unable to read BCD entries. Run PowerShell as Administrator."
        Write-Log "ERROR: Get-DanglingDisplayOrderEntries failed: $($_.Exception.Message)"
        return @()
    }

    $idsAll = @{}
    foreach ($match in [regex]::Matches($all, "(?im)^\s*identifier\s+(\{[^}]+\})")) {
        $idsAll[$match.Groups[1].Value.ToLower()] = $true
    }

    $displayOrder = New-Object System.Collections.Generic.List[string]
    $inDisplayOrder = $false
    foreach ($line in $bootmgr -split "`r?`n") {
        if ($line -match "(?im)^\s*displayorder\s+(\{[^}]+\})") {
            [void]$displayOrder.Add($matches[1].ToLower())
            $inDisplayOrder = $true
            continue
        }

        if ($inDisplayOrder) {
            if ($line -match "^\s+(\{[^}]+\})") {
                [void]$displayOrder.Add($matches[1].ToLower())
                continue
            }

            $inDisplayOrder = $false
        }
    }

    $danglingEntries = @()
    foreach ($id in $displayOrder) {
        if (-not $idsAll.ContainsKey($id)) {
            $danglingEntries += [PSCustomObject]@{
                GUID = $id
            }
        }
    }

    $danglingEntries
}

function Cleanup-DanglingDisplayOrderEntries {
    $danglingEntries = Get-DanglingDisplayOrderEntries
    if (-not $danglingEntries -or $danglingEntries.Count -eq 0) {
        Write-Host "No dangling displayorder entries found." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Dangling displayorder entries:" -ForegroundColor Yellow
    foreach ($entry in $danglingEntries) {
        Write-Host $entry.GUID
    }

    $confirm = Read-Host "Type Y to remove all dangling displayorder entries"
    if ($confirm -cne "Y") { return }

    Ensure-InitialBackupBeforeChange
    foreach ($entry in $danglingEntries) {
        & $BcdEditExe /displayorder "$($entry.GUID)" /remove
        Write-Log "CLEANUP: removed dangling displayorder GUID=$($entry.GUID)"
    }
}

function Cleanup-StaleFirmwareEntries {
    $entries = Get-BootEntries
    $stale = @($entries | Where-Object {
        $_.IsFirmwareApplication -and $_.EntryStatus -eq "STALE"
    })

    if (-not $stale -or $stale.Count -eq 0) {
        Write-Host "No stale firmware entries found." -ForegroundColor Yellow
        return
    }

    Show-BootEntriesTable -Entries $stale -Title "Stale firmware entries (target file missing):"

    Write-Host ""
    $selection = Read-Host "Enter numbers to delete (comma separated), A for all, or Enter to cancel"
    if ([string]::IsNullOrWhiteSpace($selection)) { return }

    $selected = @()
    if ($selection.Trim().ToUpper() -eq "A") {
        $selected = @($stale)
    }
    else {
        $tokens = $selection -split "[\s,;]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $pickedIndexes = @{}

        foreach ($token in $tokens) {
            $index = 0
            if ([int]::TryParse($token, [ref]$index) -and $index -ge 1 -and $index -le $stale.Count) {
                if (-not $pickedIndexes.ContainsKey($index)) {
                    $pickedIndexes[$index] = $true
                    $selected += $stale[$index - 1]
                }
            }
        }

        if (-not $selected -or $selected.Count -eq 0) {
            Write-Host "No valid selection." -ForegroundColor Yellow
            return
        }
    }

    Write-Host ""
    Write-Host "Selected stale entries:" -ForegroundColor Yellow
    foreach ($entry in $selected) {
        Write-Host ("{0}  {1}" -f $entry.GUID, $entry.Description)
    }

    $confirm = Read-Host "Type Y to delete selected stale firmware entries"
    if ($confirm -cne "Y") { return }

    Ensure-InitialBackupBeforeChange
    Invoke-WithBusyRotator -Message "Deleting stale firmware entries" -Action {
        foreach ($entry in $selected) {
            if ($entry.GUID -notmatch "^\{[0-9a-f-]{36}\}$") {
                Write-Log "CLEANUP STALE: skipped non-GUID entry $($entry.GUID)"
                continue
            }

            & $BcdEditExe /delete "$($entry.GUID)"
            Write-Log "CLEANUP STALE: removed GUID=$($entry.GUID) desc='$($entry.Description)' path='$($entry.Path)' device='$($entry.Device)'"
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($LoadBackupFileName)) {
    Import-BCDFromBackup -BackupFileName $LoadBackupFileName -Reason "PARAM"
}

function Show-BootEntriesTable {
    param(
        [array]$Entries,
        [string]$Title = "Boot menu entries:",
        [pscustomobject]$BusyHandle = $null
    )

    Write-Host ""
    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        Write-Host $Title -ForegroundColor Cyan
        if ($null -ne $BusyHandle) {
            Stop-BusyRotator -Handle $BusyHandle
        }
        Write-Host ""
    }

    if (-not $Entries -or $Entries.Count -eq 0) {
        Write-Host "(no boot menu entries found)" -ForegroundColor Yellow
        return
    }

    $indexWidth = [Math]::Max(2, $Entries.Count.ToString().Length)
    $guidWidth = 38
    $volumeHeader = "Volume #"
    $typeHeader = "Type"
    $volumeMax = ($Entries | ForEach-Object { ([string]$_.Specified).Length } | Measure-Object -Maximum).Maximum
    $typeMax = ($Entries | ForEach-Object { ([string]$_.PartitionType).Length } | Measure-Object -Maximum).Maximum
    if ($null -eq $volumeMax) { $volumeMax = 0 }
    if ($null -eq $typeMax) { $typeMax = 0 }
    $specifiedWidth = [Math]::Max($volumeHeader.Length, [int]$volumeMax)
    $healthWidth = [Math]::Max($typeHeader.Length, [int]$typeMax)

    $header = ("{0,$indexWidth} | {1,-$guidWidth} | {2,-$specifiedWidth} | {3,-$healthWidth} | {4}" -f "#", "GUID", $volumeHeader, $typeHeader, "Description")
    Write-Host $header
    Write-Host ("-" * $header.Length)

    $i = 1
    foreach ($e in $Entries) {
        $health = if ($null -eq $e.PSObject.Properties["PartitionType"]) { "" } else { $e.PartitionType }
        Write-Host ("{0,$indexWidth} | {1,-$guidWidth} | {2,-$specifiedWidth} | {3,-$healthWidth} | {4}" -f $i, $e.GUID, $e.Specified, $health, $e.Description)
        $i++
    }
}

function Invoke-ReadHostWithClipboardSeed {
    param(
        [string]$Prompt,
        [string]$SeedText
    )

    $hadClipboard = $false
    $previousClipboard = $null

    try {
        $previousClipboard = Get-Clipboard -Raw -ErrorAction Stop
        $hadClipboard = $true
    }
    catch {
        $hadClipboard = $false
    }

    try {
        Set-Clipboard -Value $SeedText -ErrorAction Stop
        Write-Host "Current description copied to clipboard. Paste (Ctrl+Shift+V), edit, then press Enter." -ForegroundColor Yellow
    }
    catch {
        Write-Host "Clipboard access failed. Type the new description manually." -ForegroundColor Yellow
    }

    $value = Read-Host $Prompt

    try {
        if ($hadClipboard) {
            Set-Clipboard -Value $previousClipboard -ErrorAction Stop
        }
        else {
            Set-Clipboard -Value "" -ErrorAction Stop
        }
    }
    catch {
    }

    return $value
}

# --- ENTRY SELECTION ----------------------------------------------------------

function Select-BootEntry {
    param([array]$Entries)

    if (-not $Entries -or $Entries.Count -eq 0) { return $null }

    Show-BootEntriesTable -Entries $Entries -Title "Boot menu entries:"

    while ($true) {
        $choice = Read-Host "Select entry number (or press Enter to cancel)"

        if ([string]::IsNullOrWhiteSpace($choice)) { return $null }

        $index = 0
        $isInt = [int]::TryParse($choice, [ref]$index)
        if ($isInt -and $index -ge 1 -and $index -le $Entries.Count) {
            return $Entries[$index - 1]
        }

        Write-Host "Invalid selection. Enter a number from 1 to $($Entries.Count), or press Enter to cancel." -ForegroundColor Yellow
    }
}

# --- ACTIONS ------------------------------------------------------------------

function Rename-BootEntry {
    param([pscustomobject]$Entry)

    $oldName = $Entry.Description
    Write-Host ""
    Write-Host "Selected GUID:" -ForegroundColor Green
    Write-Host $Entry.GUID
    Write-Host "Current description:" -ForegroundColor Green
    Write-Host $oldName
    $newName = Invoke-ReadHostWithClipboardSeed -Prompt "New description (paste/edit, Enter to cancel)" -SeedText $oldName
    if ([string]::IsNullOrWhiteSpace($newName)) { return }

    $newName = $newName.Trim()
    if ($newName.Length -lt 2) {
        Write-Host "Rename canceled (input shorter than 2 characters)." -ForegroundColor Yellow
        return
    }

    Ensure-InitialBackupBeforeChange
    & $BcdEditExe /set "$($Entry.GUID)" description "$newName"
    Write-Log "RENAMED: '$oldName' -> '$newName'  GUID=$($Entry.GUID)"
}

function Delete-BootEntry {
    param([pscustomobject]$Entry)

    $name = $Entry.Description
    $confirm = Read-Host "Type Y to delete '$name'"
    if ($confirm -cne "Y") { return }

    Ensure-InitialBackupBeforeChange
    Invoke-WithBusyRotator -Message "Deleting boot entry" -Action {
        & $BcdEditExe /delete "$($Entry.GUID)"
    }
    Write-Log "DELETED: '$name'  GUID=$($Entry.GUID)"
}

function SetDefault-BootEntry {
    param([pscustomobject]$Entry)

    Ensure-InitialBackupBeforeChange
    Invoke-WithBusyRotator -Message "Setting default entry" -Action {
        & $BcdEditExe /default "$($Entry.GUID)"
    }
    Write-Log "DEFAULT: '$($Entry.Description)'  GUID=$($Entry.GUID)"
}

# --- MAIN LOOP ----------------------------------------------------------------

$null = Register-EngineEvent PowerShell.Exiting -Action {
    Write-Host "`nExiting." -ForegroundColor Cyan
}

while ($true) {
    Write-Host ("Log file: {0}" -f $LogFile) -ForegroundColor DarkCyan
    Write-Host ""

    $tableBusy = Start-BusyRotator -Message "Reading BCD entries"
    try {
        $currentEntries = Get-BootEntries
        Stop-BusyRotator -Handle $tableBusy
        $tableBusy = $null
    }
    finally {
        if ($null -ne $tableBusy) {
            Stop-BusyRotator -Handle $tableBusy
        }
    }

    Write-Host ("=== BootEntryManager === Version {0} {1} from {2} ===" -f $ScriptVersion, $script:BootVolumeLabel, $env:COMPUTERNAME.Trim()) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[1] Rename entry"
    Write-Host "[2] Delete entry"
    Write-Host "[3] Set default entry"
    Write-Host "[4] Load BCD from backup"
    Write-Host "[5] Backup BCD now"
    Write-Host "[6] Cleanup dangling entries"
    Write-Host "[7] Cleanup stale firmware entries"
    Write-Host "[8] Open text backup report"
    Write-Host "[q|e] quit, exit"
    Write-Host ""

    Show-BootEntriesTable -Entries $currentEntries -Title ""
    Write-Host ""

    $menu = Read-Host "Choose action"
    $menu = $menu.ToLower()

    switch ($menu) {

        "1" {
            $entries = Get-BootEntries
            $selected = Select-BootEntry -Entries $entries
            if ($selected) { Rename-BootEntry -Entry $selected }
        }

        "2" {
            $entries = Get-BootEntries
            $selected = Select-BootEntry -Entries $entries
            if ($selected) { Delete-BootEntry -Entry $selected }
        }

        "3" {
            $entries = Get-BootEntries
            $selected = Select-BootEntry -Entries $entries
            if ($selected) { SetDefault-BootEntry -Entry $selected }
        }

        "4" {
            $selectedBackup = Select-BackupFileName
            if (-not [string]::IsNullOrWhiteSpace($selectedBackup)) {
                Import-BCDFromBackup -BackupFileName $selectedBackup -Reason "MENU"
            }
        }
        "5" { Backup-BCD -Reason "MANUAL" }
        "6" { Cleanup-DanglingDisplayOrderEntries }
        "7" { Cleanup-StaleFirmwareEntries }
        "8" { Open-TextBackupReport }
        "q" { Write-Host "Exiting." -ForegroundColor Cyan; return }
        "e" { Write-Host "Exiting." -ForegroundColor Cyan; return }

        default { }
    }
}
