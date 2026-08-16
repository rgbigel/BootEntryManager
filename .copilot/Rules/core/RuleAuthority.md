# File: RuleAuthority.md

Module: RuleAuthority
Purpose: Defines canonical rule authority and mirror policy for Workspace_AI governance engines.
Path: .copilot/Rules/RuleAuthority.md
Authors: Workspace_AI Engine
Version: 1.0.0
Changelog:
- 2026-08-01: Added canonical rule authority and Continue mirror policy for Gemini/Continue migration.

RULE-AUTHORITY
- canonical-root: .copilot remains the active canonical governance core during Workspace_AI migration
- canonical-rules: .copilot/Rules contains authoritative machine-readable rule files
- canonical-methods: tools contains native PowerShell governance methods
- canonical-logs: .copilot/Logs contains governance logs
- continue-role: .continuerules and VS Code workspace settings are discovery and adapter surfaces only
- no-rule-forking: Continue/Gemini rules must point to canonical .copilot rules or generated mirrors with source references
- no-independent-truth: adapter surfaces must not define conflicting rule authority
- mirror-policy: any generated mirror must identify its canonical source file and regeneration method
- migration-policy: any later move from .copilot to a neutral governance root must use an alias or mirror phase before rename

RULE-AUTHORITY-COMMANDS
- @RULEAUTH activates this source-of-truth and mirror policy

RULE-AUTHORITY-METADATA
- scope: Workspace_AI migration
- location: .copilot/Rules/RuleAuthority.md