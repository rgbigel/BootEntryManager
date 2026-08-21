# BootEntryManager

Version: 2.0.1 (LCM Governed v4.2.0)

Windows Boot Configuration Data (BCD) management and menu configuration utility written in PowerShell.

`BootEntryManager` provides an interactive menu and automated management workflows for Windows Boot Manager entries using `bcdedit.exe`:
- Enumerate, inspect, and rename boot loader entries.
- Set default boot entry and manage display order.
- Clean up dangling or stale boot configuration references.
- Automated BCD backup, export, report generation, and restoration.

---

## Repository Layout

- `Source/BootEntryManager.ps1`: Main interactive runtime script.
- `BootEntryManager_Install.ps1`: Installer script to deploy `BootEntryManager.ps1` into a target command directory.
- `tests/BootEntryManager.Tests.ps1`: Pester contract and parser test suite (zero reboot execution).
- `docs/`: Comprehensive architecture, requirements, and LCM governance documentation.
- `tools/`: Quality gates, elevated test runners, and readiness verification scripts.

---

## System Prerequisites

- **Operating System**: Windows 10/11 x64 (UEFI / GPT recommended)
- **PowerShell**: PowerShell 7 (`pwsh.exe` 7.0+) or Windows PowerShell 5.1
- **Git**: Git for Windows
- **Filesystem**: NTFS filesystem (directory junctions & hardlinks)
- **Privileges**: Administrator privileges required to access and modify the BCD store via `bcdedit.exe`

---

## Usage

### Interactive Management Mode
Run the main script from an elevated PowerShell session:
```powershell
pwsh -File .\Source\BootEntryManager.ps1
```

### Automated Backup Import Mode
Import a specific BCD backup file from the standard backup directory:
```powershell
pwsh -File .\Source\BootEntryManager.ps1 -LoadBackupFileName "20260815 1430 Win11 HostPC.bak"
```

### Installation
Deploy to a custom tools directory (default: `D:\OneDrive\cmd`):
```powershell
pwsh -File .\BootEntryManager_Install.ps1 -cmd_location "D:\OneDrive\cmd"
```

---

## Documentation

- **[Requirements.md](docs/Requirements.md)** — Normative functional requirements and parameter contracts.
- **[Architecture.md](docs/Architecture.md)** — Subsystem architecture, parser pipeline, and backup engine.
- **[Standards.md](docs/Standards.md)** — Project coding conventions and LCM governance invariants.
- **[Changelog.md](docs/Changelog.md)** — Project release history.
