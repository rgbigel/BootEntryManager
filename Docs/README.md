# BootEntryManager Documentation Directory

Module: docs/README.md  
Authors: Rolf, BootEntryManager Architecture Team  
Version: 2.0.0  
Status: Authoritative Standard  
Date: 2026-08-16  

---

## 1. Documentation Fabric

- **[Requirements.md](Requirements.md)** — Normative requirements for BCD discovery, backup engine, menu operations, and zero-reboot testing.
- **[Architecture.md](Architecture.md)** — System architecture, subsystem breakdown, BCD parsing pipeline, and safety workflows.
- **[Standards.md](Standards.md)** — Coding conventions, formatting invariants, and LCM governance rules.
- **[Changelog.md](Changelog.md)** — Project change history.

---

## 2. Verification & Quality Gates

Run the local readiness test runner:
```powershell
pwsh -ExecutionPolicy Bypass -File .\tools\Test-RepoReadiness.ps1
```
