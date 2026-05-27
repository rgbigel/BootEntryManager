# BootEntryManager Functional Documentation

## Repository Layout
- `Source\BootEntryManager.ps1` contains the runtime script.
- `BootEntrayManager_Install.ps1` installs the runtime script into a cmd target folder.

## Installation Script

### `BootEntrayManager_Install.ps1`
- Parameter:
  - `cmd_location` (default: `D:\OneDrive\cmd`)
- Source path used by installer:
  - `<repo_root>\Source\BootEntryManager.ps1`
- Install target path:
  - `<cmd_location>\BootEntryManager\BootEntryManager.ps1`
- If `<cmd_location>\BootEntryManager` does not exist, it is created.
- Existing target script is overwritten.

## Script
- Name: `BootEntryManager.ps1`
- Version: `1.9.0`
- Purpose: Manage Windows Boot Manager menu entries with interactive actions (rename, delete, set default, cleanup dangling menu references) and BCD backup/import support.

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
- The script reads the current boot entry with `bcdedit /enum {current} /v`.
- It reads the `device` line and requires `partition=...` format.
- Supported partition source formats:
  - drive letter (for example `C:`)
  - NT device path (for example `\Device\HarddiskVolume2`)
- NT device path is mapped to drive letter via `QueryDosDevice`.
- The script reads the filesystem label using `Get-Volume`.
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
- `Description`
- `IsDefault` flag (from `{bootmgr}` default)

If an entry has no `description`, fallback text is generated:
- `(unnamed entry) path: <path>` when `path` exists
- `(unnamed entry) device: <device>` when only `device` exists
- `(empty BCD entry)` when neither exists

### 3. Dangling Entry Detection
- The script compares `displayorder` GUIDs against all known BCD identifiers.
- GUIDs present in `displayorder` but missing from full BCD objects are treated as dangling.
- Cleanup action removes those dangling GUIDs from `displayorder` after explicit confirmation.

## Interactive Menu
Displayed repeatedly until exit:
- `[1] Rename entry`
- `[2] Delete entry`
- `[3] Set default entry`
- `[4] Cleanup dangling entries`
- `[5] Backup BCD now`
- `[6] Load BCD from backup`
- `[7] Exit`
- `q` or `e` also exit

The menu also shows:
- boot volume label
- full log file path

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
2. Script asks confirmation: `Type YES to delete '<description>'`.
3. Only exact `YES` proceeds.
4. Deletion command:
   - `bcdedit /delete <GUID>`

### Set Default Entry
1. User selects an entry.
2. Default command:
   - `bcdedit /default <GUID>`

### Cleanup Dangling Entries
1. Script lists dangling GUIDs.
2. Asks confirmation: `Type YES to remove all dangling displayorder entries`.
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
- Menu exits on `7`, `q`, or `e`.
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
