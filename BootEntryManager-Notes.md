# BootEntryManager Notes

## Version 2.0.0 (2026-05-29)

Changes:
- Updated runtime script version to 2.0.0.
- Finalized output order in main loop:
  - log line
  - reading spinner
  - header
  - menu
  - boot entries table
  - prompt
- Removed numeric exit menu action and kept `q`/`e` exit line.
- Added stale marker `s` in `Volume #` data and retained alias marker `a`.
- Restored table focus to `Volume #` + `Type` and minimized both columns using dynamic width calculation.
- Improved spinner clear behavior to avoid leaving trailing spinner characters on screen.
- Kept stale cleanup action restricted to entries classified as stale firmware targets.

## Version 1.9.4 (2026-05-27)

Changes:
- Replaced the shared table column `Default` with `Specified`.
- `Specified` now shows the partition extracted from the BCD `device` line when available (for example `C:`).
- Default entry is marked by appending `**` in the `Specified` column.
- Added simple alias indication:
  - entries with matching `device + path + systemroot + winpe` fingerprint are marked with `a` in the `Specified` column.

## Version 1.9.3 (2026-05-27)

Changes:
- Added post-backup cleanup for BCD sidecar transaction files:
  - After successful backup export, script removes `<backup>.bak.LOG`, `<backup>.bak.LOG1`, and `<backup>.bak.LOG2` when present.

## Version 1.9.2 (2026-05-27)

Changes:
- Aligned runtime layout to cmd-root architecture:
  - Runtime script location is `D:\OneDrive\cmd\BootEntryManager.ps1`.
  - Runtime docs are kept in repository only.
- Updated installer target path:
  - `BootEntrayManager_Install.ps1` now installs to `<cmd_location>\BootEntryManager.ps1`.

## Version 1.9.1 (2026-05-27)

Changes:
- Added repository source layout for the executable script:
  - `Source\BootEntryManager.ps1`
- Added install script:
  - `BootEntrayManager_Install.ps1`
- Install script behavior:
  - Parameter `cmd_location` with default `D:\OneDrive\cmd`
  - Installs `BootEntryManager.ps1` to `<cmd_location>\BootEntryManager.ps1`

## Version 1.9.0 (2026-05-27)

Changes:
- Added automatic self-elevation flow:
  - If not running as Administrator, the script relaunches itself with `RunAs`.
  - Script exits in the original non-elevated process after relaunch attempt.
- Removed optional parameter `BootDrive`.
- Added boot volume label detection from current BCD `device` line:
  - Reads `partition=...` from `{current}`.
  - Resolves `\Device\HarddiskVolumeX` to drive letter.
  - Reads filesystem label from that volume.
  - Uses volume label in backup and log file names.
  - Throws an error when the detected boot volume label is empty.
- Backup operation now writes two files per backup event:
  - BCD store export as `.bak`.
  - Text snapshot as `.txt` (from `bcdedit /enum all /v`).
- `.txt` backup is post-processed to append symbolic identifier names where GUIDs are present and a symbolic mapping exists (for example appending `| {ramdiskoptions}`).
- Menu status line now shows boot volume label instead of `BootDrive`.

## Version 1.8.1 (2026-05-26)

Changes:
- Added menu status lines showing:
  - active `BootDrive` value
  - current log file path

## Version 1.8.0 (2026-05-26)

Changes:
- Added optional parameter `LoadBackupFileName` to import BCD from a backup file in the fixed backup directory.
- Added menu action `Load BCD from backup`.
- Load action uses a file selector (`OpenFileDialog`) when available and falls back to a numbered list picker.
- Log file moved to the fixed backup directory.
- Log filename now follows the same naming scheme as backup files, with extension `.log`:
  - `yyyyMMdd HHmm <BootDrive> <ComputerName>.log`

## Version 1.7.0 (2026-05-26)

Changes:
- Added optional parameter `BootDrive` with default value `D0P0`.
- Backup location changed to `D:\OneDrive\Documents\Einstellungen\BCD`.
- Backup filename now uses compact timestamp first, then boot drive, then computer name:
  - `yyyyMMdd HHmm <BootDrive> <ComputerName>.bak`
- Added session-scoped automatic initial backup before the first modifying action.
- Added explicit `Backup BCD now` menu action.
- Added `Cleanup dangling entries` menu action.
- Cleanup removes GUIDs that are still present in `displayorder` but do not exist as BCD objects.

## Version 1.6.9 (2026-05-26)

Changes:
- Improved handling of entries without a `description` value.
- If description is missing, output now uses fallback text based on available data:
  - `(unnamed entry) path: ...` when path exists.
  - `(unnamed entry) device: ...` when only device exists.
  - `(empty BCD entry)` when both path and device are missing.
- This makes unresolved displayorder objects explicit instead of showing generic `(no description)`.

## Version 1.6.8 (2026-05-26)

Changes:
- Boot entry parser now reads only identifiers from the `displayorder` block in `{bootmgr}` output.
- Excludes non-menu GUID references (for example `inherit`, `resumeobject`, `bootsequence`, `toolsdisplayorder`) from the main list.
- Added a `Default` column in the shared table output.
- Current default entry is marked with `yes` in all boot entry tables.

## Version 1.6.7 (2026-05-26)

Changes:
- Rename input handling updated:
  - After trimming, description length < 2 is treated as cancel/exit.
  - No rename action is executed in that case.

## Version 1.6.6 (2026-05-26)

Changes:
- Updated rename prompt instruction text to use `Ctrl+Shift+V` for paste.

## Version 1.6.5 (2026-05-26)

Changes:
- Added clipboard-seeded rename input flow.
- On rename, the current description is copied to clipboard before prompting.
- User can paste and edit inline in the terminal input field.
- Previous clipboard content is restored after input.

## Version 1.6.4 (2026-05-26)

Changes:
- Replaced duplicated listing logic with one shared display function for all boot entry tables.
- Standardized overview and selection output to the same numbered table format.
- Improved table alignment for 1+ digit row numbers (including rows >9).
- Updated rename flow prompt:
  - Shows selected GUID on its own line.
  - Shows current description on its own line.
  - Requests new description in a separate input line.

## Version 1.6.3 (2026-05-26)

Changes:
- Fixed bcdedit invocation reliability by using explicit executable path and quoted BCD identifiers/GUID arguments.
- Changed current overview output to full, non-truncated lines in the format: `GUID | Description`.
- Made action selection list format consistent with the overview: `[index] GUID | Description`.
- Improved entry selection input handling:
  - Re-prompts on invalid input.
  - Shows an explicit validation message.
  - Keeps Enter-to-cancel behavior.

Observed behavior after fix:
- Rename flow now consistently prompts: `Enter new description for '<current description>':`
- Long descriptions are no longer truncated with ellipsis in the overview.
