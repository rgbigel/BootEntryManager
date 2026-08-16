# BootEntryManager: Requirements Specification

Module: docs/Requirements.md  
Authors: Rolf, BootEntryManager Architecture Team  
Version: 2.0.0  
Status: Authoritative Specification  
Date: 2026-08-16  

---

## 1. Executive Summary

`BootEntryManager` is an administrative Windows Boot Configuration Data (BCD) management and maintenance utility. It provides a menu-driven interface to safely inspect, rename, reorder, delete, and repair boot loader entries, with automated pre-modification BCD backups and comprehensive session audit logs.

---

## 2. Functional Requirements

### A. Execution Context & Privilege Governance (`REQ-BEM-001..002`)
* **`REQ-BEM-001` (Administrative Elevation)**: The system `MUST` execute within an elevated Administrator context to interact with `%WINDIR%\System32\bcdedit.exe`. If launched unelevated, it `MUST` detect the non-privileged state and offer a self-elevating relaunch.
* **`REQ-BEM-002` (EFI System Partition Label Resolution)**: The system `MUST` identify the active EFI System Partition via GPT type `{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}` and resolve its `FileSystemLabel`. This label is incorporated into all backup and log filenames.

---

### B. Safety & Backup Engine (`REQ-BEM-003..004`)
* **`REQ-BEM-003` (Automated Pre-Modification Backup)**: The system `MUST` automatically create a full BCD backup prior to executing any modifying action (rename, delete, set default, import, or cleanup).
* **`REQ-BEM-004` (Dual Backup Format & Alias Enrichment)**: Each backup event `MUST` generate:
  1. A binary BCD hive export (`.bak`) via `bcdedit /export`.
  2. A formatted text snapshot (`.txt`) via `bcdedit /enum all /v`, post-processed to append symbolic alias annotations (e.g. `{ramdiskoptions}`, `{current}`).
  3. Automatic cleanup of transient transaction sidecar files (`.bak.LOG`, `.bak.LOG1`, `.bak.LOG2`).

---

### C. Boot Entry Discovery & Maintenance (`REQ-BEM-005..007`)
* **`REQ-BEM-005` (Display Order Enumeration)**: The system `MUST` parse the `{bootmgr}` `displayorder` list to construct the active boot menu view, mapping each entry's GUID, device partition, type, description, and status markers (`**` for default, `a` for alias).
* **`REQ-BEM-006` (Dangling Reference Detection & Cleanup)**: The system `MUST` detect GUIDs listed in `{bootmgr}` `displayorder` that do not exist as valid BCD objects, offering safe removal upon confirmation.
* **`REQ-BEM-007` (Stale Firmware Application Detection)**: The system `MUST` verify physical target path existence for firmware application entries, identifying orphaned or stale EFI references for optional cleanup.

---

### D. User Interface & Session Audit (`REQ-BEM-008..009`)
* **`REQ-BEM-008` (Interactive Console Menu)**: The system `MUST` provide a clear console menu supporting:
  * `[1] Rename entry`
  * `[2] Delete entry`
  * `[3] Set default entry`
  * `[4] Load BCD from backup`
  * `[5] Backup BCD now`
  * `[6] Cleanup dangling entries`
  * `[7] Cleanup stale firmware entries`
  * `[8] Open text backup report`
  * `[q|e] Quit / Exit`
* **`REQ-BEM-009` (Audit Logging)**: All operations, menu selections, and BCD modifications `MUST` be logged with timestamps to a session log file (`yyyyMMdd HHmm <BootVolumeLabel> <ComputerName>.log`).

---

### E. Quality Assurance & Safe Testing (`REQ-BEM-010`)
* **`REQ-BEM-010` (Zero-Reboot Test Invariant)**: Automated unit and integration tests `MUST NEVER` invoke system restart commands (`Restart-Computer`, `shutdown /r`). Testing `MUST` validate syntax, argument binding, BCD parsing, and backup naming using static text fixtures and mock execution handlers.
