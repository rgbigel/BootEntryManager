# BootEntryManager: Architecture Document

Module: docs/Architecture.md  
Authors: Rolf, BootEntryManager Architecture Team  
Version: 2.0.0  
Status: Authoritative Architecture  
Date: 2026-08-16  

---

## 1. Subsystem Architecture

`BootEntryManager` is organized into four decoupled functional subsystems:

```mermaid
graph TB
    subgraph UI ["User Interface Layer"]
        CLI["CLI Entry Point (Source/BootEntryManager.ps1)"]
        MENU["Interactive Console Menu Loop"]
        LOG["Session Audit Logger"]
        CLI --> MENU
        MENU --> LOG
    end

    subgraph ParserEngine ["BCD Discovery & Parsing Engine"]
        DISC["EFI Partition Resolver (Get-Volume / Partition Type)"]
        PARSER["BCD Text Parser (bcdedit /enum all /v)"]
        ALIAS["Symbolic Alias Mapper"]
        DISC --> PARSER
        PARSER --> ALIAS
    end

    subgraph OperationEngine ["Maintenance & Mutation Subsystem"]
        MOD["Entry Modifier (Rename, Set Default, Delete)"]
        CLEAN["Dangling & Stale Reference Cleaner"]
        MOD --> CLEAN
    end

    subgraph BackupEngine ["BCD Backup & Recovery Subsystem"]
        EXP["Binary Hive Exporter (bcdedit /export -> .bak)"]
        TXT["Annotated Text Snapshot Exporter (.txt)"]
        RESTORE["Backup Hive Importer (bcdedit /import)"]
        EXP --> TXT
    end

    MENU --> DISC
    MENU --> MOD
    MENU --> EXP
    MENU --> RESTORE
```

---

## 2. Component Boundaries & Pipeline

### A. Discovery Pipeline
1. Identifies the active EFI System Partition by GPT partition type GUID `{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}`.
2. Resolves partition volume label and establishes the session backup directory: `D:\OneDrive\Documents\Einstellungen\BCD`.
3. Executes `bcdedit /enum {bootmgr} /v` to extract the authoritative `displayorder` array.
4. Executes `bcdedit /enum all /v` to parse object GUIDs, descriptions, device paths, and firmware metadata.

### B. Backup & Safety Pipeline
1. Prior to any state-mutating operation, invokes the pre-modification safety backup.
2. Produces both `.bak` (binary hive) and `.txt` (human-readable annotated report).
3. Cleans up transactional `.LOG` sidecars.

### C. Safe Test Execution Strategy
* **Unit Testing**: Tests parsing logic, regular expressions, and argument contracts against pre-captured static BCD text files.
* **Zero-Reboot Invariant**: Non-destructive mock testing ensures full test coverage without triggering system restarts.
