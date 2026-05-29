# BootEntryManager Functional Documentation

## Repository Layout
- `Source\BootEntryManager.ps1` contains the runtime script.
- `BootEntryManager_Install.ps1` installs the runtime script into a cmd target folder.

## Installation Script

### `BootEntryManager_Install.ps1`
- Parameter:
  - `cmd_location` (default: `D:\OneDrive\cmd`)
- Source path used by installer:
  - `<repo_root>\Source\BootEntryManager.ps1`
- Install target path:
  - `<cmd_location>\BootEntryManager.ps1`
- Existing target script is overwritten.

## Script
- Name: `BootEntryManager.ps1`
- Version: `2.0.0`
- Purpose: Manage Windows Boot Manager menu entries with interactive actions (rename, delete, set default, cleanup dangling/stale references) and BCD backup/import/report support.

## Runtime Requirements
- Must run in an elevated PowerShell session (Administrator).
- Uses Windows `bcdedit.exe` at:
  - `%WINDIR%\System32\bcdedit.exe`
- Creates and uses backup/log directory:
  - `D:\OneDrive\Documents\Einstellungen\BCD`

If not elevated, the script attempts to relaunch itself elevated (`RunAs`) and exits the original process.

## Parameters

### `LoadBackupFileName`
- Type: `string`
- Optional.
- If provided, the script attempts to import this backup from the fixed backup directory at startup.
- Only the file name part is used; directory parts are discarded.

## Boot Volume Label Resolution
- The script detects the EFI System Partition by GPT type:
  - `{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}`
- It resolves the corresponding volume and reads `FileSystemLabel` via `Get-Volume`.
- This label is required and used in backup/log file names.
- If label is empty, the script throws an error and stops.

## File Naming

### Backup files (`.bak` and `.txt`)
- Format:
  - `yyyyMMdd HHmm <BootVolumeLabel> <ComputerName>.bak`
  - `yyyyMMdd HHmm <BootVolumeLabel> <ComputerName>.txt`
- Example pattern source values:
  - timestamp from current time
  - detected boot volume label
  - `$env:COMPUTERNAME`

### Log files (`.log`)
- Session log file is created in the same directory.
- Format:
  - `yyyyMMdd HHmm <BootVolumeLabel> <ComputerName>.log`
- Timestamp part is fixed at script start for the whole session.

## Main Functional Areas

### 1. Backup Safety
- Before the first modifying action in a session, the script automatically performs one initial BCD backup.
- Modifying actions include:
  - import from backup
  - rename entry
  - delete entry
  - set default entry
  - cleanup dangling displayorder entries
- Additional manual backups can be triggered from the menu.

For each backup event, the script writes:
- `bcdedit /export` output as `.bak`
- a text snapshot (`bcdedit /enum all /v`) as `.txt`

Post-export cleanup:
- Script removes sidecar BCD transaction files next to the backup when present:
  - `<backup>.bak.LOG`
  - `<backup>.bak.LOG1`
  - `<backup>.bak.LOG2`

Text snapshot post-processing:
- Script resolves symbolic BCD aliases from non-verbose output (`bcdedit /enum all`).
- It maps alias -> GUID by resolving each symbolic identifier with `bcdedit /enum {alias} /v`.
- In `.txt` output, lines containing GUIDs are appended with mapped symbolic names when available.
- Example: `... {<guid>}  | {ramdiskoptions}`

### 2. Boot Entry Discovery
The script reads BCD data using:
- `bcdedit /enum {bootmgr} /v`
- `bcdedit /enum all /v`

It builds the visible boot menu list from `{bootmgr}` `displayorder` only, preserving order and removing duplicates.

For each menu entry, it resolves:
- `GUID`
- `Volume #` marker
- `Type`
- `Description`

`Volume #` column behavior:
- Extracts partition text from the BCD `device` line when it is in `partition=...` form.
- Appends `**` for the current default entry.
- Appends `a` for entries detected as simple aliases.
- Appends `s` for entries classified as stale firmware targets.

Simple alias detection fingerprint:
- `device`
- `path`
- `systemroot`
- `winpe`

If an entry has no `description`, fallback text is generated:
- `(unnamed entry) path: <path>` when `path` exists
- `(unnamed entry) device: <device>` when only `device` exists
- `(empty BCD entry)` when neither exists

### 3. Dangling Entry Detection
- The script compares `displayorder` GUIDs against all known BCD identifiers.
- GUIDs present in `displayorder` but missing from full BCD objects are treated as dangling.
- Cleanup action removes those dangling GUIDs from `displayorder` after explicit confirmation.

### 4. Stale Firmware Entry Detection
- Firmware application entries are inspected for target file existence using resolved device + EFI path.
- Entries with missing target files are classified as stale.
- Cleanup action can delete selected stale firmware entries or all stale entries after explicit confirmation.

## Interactive Menu
Displayed repeatedly until exit:
- `[1] Rename entry`
- `[2] Delete entry`
- `[3] Set default entry`
- `[4] Load BCD from backup`
- `[5] Backup BCD now`
- `[6] Cleanup dangling entries`
- `[7] Cleanup stale firmware entries`
- `[8] Open text backup report`
- `[q|e] quit, exit`

The menu also shows:
- full log file path

Render order in the main loop:
- log line
- busy read indicator (`Reading BCD entries`)
- tool header line with version and boot volume label
- menu selections
- current boot entry table
- action prompt

## Action Behavior

### Rename Entry
1. User selects an entry by number.
2. Script shows selected GUID and current description.
3. Current description is copied to clipboard as seed text.
4. User pastes/edits input (`Ctrl+Shift+V`) and submits.
5. Input is trimmed.
6. If empty or length < 2, rename is canceled.
7. Otherwise, description is set via:
   - `bcdedit /set <GUID> description <new text>`

Clipboard restore behavior:
- Previous clipboard content is restored after input when possible.

### Delete Entry
1. User selects an entry.
2. Script asks confirmation: `Type Y to delete '<description>'`.
3. Only exact uppercase `Y` proceeds.
4. Deletion command:
   - `bcdedit /delete <GUID>`

### Set Default Entry
1. User selects an entry.
2. Default command:
   - `bcdedit /default <GUID>`

### Cleanup Dangling Entries
1. Script lists dangling GUIDs.
2. Asks confirmation: `Type Y to remove all dangling displayorder entries`.
3. For each dangling GUID:
   - `bcdedit /displayorder <GUID> /remove`

### Backup BCD Now
- Immediate backup commands:
  - `bcdedit /export <backup-file>`
  - `bcdedit /enum all /v` (saved as paired `.txt` backup)

### Load BCD From Backup
Selection method:
1. Tries `System.Windows.Forms.OpenFileDialog` in backup directory.
2. If unavailable/fails, falls back to numbered console picker of `*.bak` files.

Import command:
- `bcdedit /import <selected-backup-file>`

### Open Text Backup Report
- Lists available `*.txt` reports in backup directory.
- Opens selected report in Notepad++ when available, otherwise Notepad.

## Entry Selection Rules
- Boot entry lists are shown in a table with columns:
  - index (`#`), `GUID`, `Default`, `Description`
- Selection prompt accepts:
  - valid 1-based number
  - Enter to cancel
- Invalid selection causes re-prompt with validation message.

## Logging
- Log write format:
  - `yyyy-MM-dd HH:mm:ss  <message>`
- Logged operation types include:
  - `BACKUP`
  - `IMPORT`
  - `RENAMED`
  - `DELETED`
  - `DEFAULT`
  - `CLEANUP`
  - `ERROR` (for read/parsing failures)

## Error Handling
- Global setting: `$ErrorActionPreference = "Stop"`
- `Get-BootEntries` and dangling detection wrap BCD reads in `try/catch`.
- On read failure:
  - warning is shown
  - error is logged
  - empty entry set is returned
- Backup import validates file name and existence before import.

## Exit Behavior
- Menu exits on `q` or `e`.
- A `PowerShell.Exiting` engine event also prints `Exiting.` when session terminates.

## Example Invocation

### Default
```powershell
.\BootEntryManager.ps1
```

### Auto-import specific backup at startup
```powershell
.\BootEntryManager.ps1 -LoadBackupFileName "20260526 1020 System MYPC.bak"
```
