# BootEntryManager.ps1
# Version: 1.9.0
# Purpose: Manage Windows Boot Manager entries (rename, delete, set default)

param(
    [string]$LoadBackupFileName
)


$ErrorActionPreference = "Stop"

# --- CONFIG -------------------------------------------------------------------

$BackupDir = "D:\OneDrive\Documents\Einstellungen\BCD"
$BcdEditExe = Join-Path $env:WINDIR "System32\bcdedit.exe"
$HasInitialBackupBeenDone = $false

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
    $currentEntry = & $BcdEditExe /enum "{current}" /v 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read current BCD entry for boot volume detection."
    }

    if ($currentEntry -notmatch "(?im)^\s*device\s+(.+)$") {
        throw "Current BCD entry does not contain a device line."
    }

    $deviceValue = $matches[1].Trim()
    if ($deviceValue -notmatch "(?i)^partition=(.+)$") {
        throw "Current BCD device is not a partition value: '$deviceValue'"
    }

    $partitionValue = $matches[1].Trim()
    $driveLetter = $null

    if ($partitionValue -match "(?i)^[A-Z]:$") {
        $driveLetter = $partitionValue
    }
    elseif ($partitionValue -match "(?i)^\\Device\\HarddiskVolume\d+$") {
        $driveLetter = Get-DriveLetterFromNtDevicePath -NtDevicePath $partitionValue
        if ([string]::IsNullOrWhiteSpace($driveLetter)) {
            throw "Unable to map '$partitionValue' to a drive letter."
        }
    }
    else {
        throw "Unsupported partition format for boot device: '$partitionValue'"
    }

    $volume = Get-Volume -DriveLetter $driveLetter.TrimEnd(':') -ErrorAction Stop
    $label = [string]$volume.FileSystemLabel
    if ([string]::IsNullOrWhiteSpace($label)) {
        throw "Boot device volume label is empty for drive '$driveLetter'."
    }

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($invalidChar in $invalidChars) {
        $label = $label.Replace([string]$invalidChar, "_")
    }

    $label.Trim()
}

$script:BootVolumeLabel = Get-BootVolumeLabel
$script:SessionTime = Get-Date
$logTimestampPart = $script:SessionTime.ToString("yyyyMMdd HHmm").Trim()
$logBootVolumePart = $script:BootVolumeLabel.Trim()
$logSystemNamePart = $env:COMPUTERNAME.Trim()
$logNameParts = @($logTimestampPart, $logBootVolumePart, $logSystemNamePart) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$LogFile = Join-Path $BackupDir ((($logNameParts -join " ").Trim()) + ".log")

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

Ensure-BackupDir

function Get-BackupFilePath {
    $timestampPart = (Get-Date).ToString("yyyyMMdd HHmm").Trim()
    $bootVolumePart = $script:BootVolumeLabel.Trim()
    $systemNamePart = $env:COMPUTERNAME.Trim()

    $nameParts = @($timestampPart, $bootVolumePart, $systemNamePart) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $fileName = (($nameParts -join " ").Trim() + ".bak")

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

        if (-not $aliases -or $aliases.Count -eq 0) {
            $line
            continue
        }

        "{0}  | {1}" -f $line, ($aliases -join ", ")
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
    & $BcdEditExe /import "$backupFilePath"
    Write-Log "IMPORT [$Reason]: BCD imported from '$backupFilePath'"
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
    & $BcdEditExe /export "$backupFile"
    Export-BCDTextBackup -OutputPath $backupTextFile
    Write-Log "BACKUP [$Reason]: BCD exported to '$backupFile' and '$backupTextFile'"
    $script:HasInitialBackupBeenDone = $true
}

function Ensure-InitialBackupBeforeChange {
    if (-not $script:HasInitialBackupBeenDone) {
        Backup-BCD -Reason "INITIAL"
    }
}

# --- REAL BOOT MENU PARSER ----------------------------------------------------

function Get-BootEntries {

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
    $blocks = [regex]::Split($all.Trim(), "(?:`r?`n){2,}")
    foreach ($block in $blocks) {
        if ($block -match "(?im)^\s*identifier\s+(\{[^}]+\})") {
            $id = $matches[1].ToLower()
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

            $descById[$id] = $desc
            $pathById[$id] = $path
            $deviceById[$id] = $device
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

            $entries += [PSCustomObject]@{
                GUID        = $resolved
                IsDefault   = ($defaultId -and $resolved -eq $defaultId)
                Description = $desc
            }
        }
    }

    $entries
}

function Get-DanglingDisplayOrderEntries {

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

    $confirm = Read-Host "Type YES to remove all dangling displayorder entries"
    if ($confirm -ne "YES") { return }

    Ensure-InitialBackupBeforeChange
    foreach ($entry in $danglingEntries) {
        & $BcdEditExe /displayorder "$($entry.GUID)" /remove
        Write-Log "CLEANUP: removed dangling displayorder GUID=$($entry.GUID)"
    }
}

if (-not [string]::IsNullOrWhiteSpace($LoadBackupFileName)) {
    Import-BCDFromBackup -BackupFileName $LoadBackupFileName -Reason "PARAM"
}

function Show-BootEntriesTable {
    param(
        [array]$Entries,
        [string]$Title = "Boot menu entries:"
    )

    Write-Host ""
    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        Write-Host $Title -ForegroundColor Cyan
        Write-Host ""
    }

    if (-not $Entries -or $Entries.Count -eq 0) {
        Write-Host "(no boot menu entries found)" -ForegroundColor Yellow
        return
    }

    $indexWidth = [Math]::Max(2, $Entries.Count.ToString().Length)
    $guidWidth = 38

    $header = ("{0,$indexWidth} | {1,-$guidWidth} | {2,-7} | {3}" -f "#", "GUID", "Default", "Description")
    Write-Host $header
    Write-Host ("-" * $header.Length)

    $i = 1
    foreach ($e in $Entries) {
        $defaultMarker = if ($e.IsDefault) { "yes" } else { "" }
        Write-Host ("{0,$indexWidth} | {1,-$guidWidth} | {2,-7} | {3}" -f $i, $e.GUID, $defaultMarker, $e.Description)
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
    $confirm = Read-Host "Type YES to delete '$name'"
    if ($confirm -ne "YES") { return }

    Ensure-InitialBackupBeforeChange
    & $BcdEditExe /delete "$($Entry.GUID)"
    Write-Log "DELETED: '$name'  GUID=$($Entry.GUID)"
}

function SetDefault-BootEntry {
    param([pscustomobject]$Entry)

    Ensure-InitialBackupBeforeChange
    & $BcdEditExe /default "$($Entry.GUID)"
    Write-Log "DEFAULT: '$($Entry.Description)'  GUID=$($Entry.GUID)"
}

# --- MAIN LOOP ----------------------------------------------------------------

$null = Register-EngineEvent PowerShell.Exiting -Action {
    Write-Host "`nExiting." -ForegroundColor Cyan
}

while ($true) {
    $currentEntries = Get-BootEntries
    Show-BootEntriesTable -Entries $currentEntries -Title "Current boot menu entries:"

    Write-Host ""
    Write-Host ("Boot volume label: {0}" -f $script:BootVolumeLabel) -ForegroundColor DarkCyan
    Write-Host ("Log file: {0}" -f $LogFile) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "=== BootEntryManager ===" -ForegroundColor Cyan
    Write-Host "[1] Rename entry"
    Write-Host "[2] Delete entry"
    Write-Host "[3] Set default entry"
    Write-Host "[4] Cleanup dangling entries"
    Write-Host "[5] Backup BCD now"
    Write-Host "[6] Load BCD from backup"
    Write-Host "[7] Exit"
    Write-Host "(q or e also exit)"
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

        "4" { Cleanup-DanglingDisplayOrderEntries }
        "5" { Backup-BCD -Reason "MANUAL" }
        "6" {
            $selectedBackup = Select-BackupFileName
            if (-not [string]::IsNullOrWhiteSpace($selectedBackup)) {
                Import-BCDFromBackup -BackupFileName $selectedBackup -Reason "MENU"
            }
        }
        "7" { Write-Host "Exiting." -ForegroundColor Cyan; return }
        "q" { Write-Host "Exiting." -ForegroundColor Cyan; return }
        "e" { Write-Host "Exiting." -ForegroundColor Cyan; return }

        default { }
    }
}
