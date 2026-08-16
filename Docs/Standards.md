# BootEntryManager Standards & Conventions

Module: Standards.md
Purpose: Code conventions, formatting rules, and development standards for BootEntryManager.
Path: docs/Standards.md
Authors: Rolf
Version: 1.0.0
Changelog:
- 2026-08-16: Initial standards scaffolding.

---
title: BootEntryManager Standards
updated: 2026-08-16
created: 2026-08-16
---

## 1. Universal Formatting Invariants
- **Character Encoding**: UTF-8 without BOM.
- **Line Endings**: Windows CRLF (`\r\n`).
- **Indentation**: 2 spaces (no hard tabs).
- **Language**: English only for code, documentation, comments, and identifiers.

## 2. Testing & Quality Invariants
All PRs and changes must satisfy `Test-RepoReadiness.ps1` before acceptance.
