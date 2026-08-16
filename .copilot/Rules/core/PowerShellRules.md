# File: PowerShellRules.md

Module: PowerShellRules
Purpose: Authoritative rules for PowerShell script generation and normalization.
Path: .copilot/Rules/PowerShellRules.md
Authors: Rolf
Version: 2.0.0
Changelog:
- 2026-07-27: Split unified rule file; clarified ASCII constraints; stabilized PS rules.

POWERSHELL-RULES
- ascii-default: ASCII required; umlauts allowed in literal strings and comments
- utf8-without-bom: scripts must be UTF-8 without BOM
- newline-crlf: scripts must end with CRLF
- no-backticks: forbidden
- no-interpolated-calls: forbid method calls inside interpolated strings
- assign-$_-first: always assign $_ to a variable before use
- no-non-ascii-identifiers: identifiers must be ASCII-only
- no-hidden-state: forbid hidden pipeline or implicit variable usage
- deterministic-output: identical input → identical output

POWERSHELL-METADATA
- scope: durable-memory
- location: .copilot/Rules/PowerShellRules.md
