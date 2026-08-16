# File: JsonRules.md

Module: JsonRules
Purpose: Authoritative rules for JSON normalization and generation.
Path: .copilot/Rules/JsonRules.md
Authors: Rolf
Version: 2.0.0
Changelog:
- 2026-07-27: Split unified rule file; stabilized JSON rules.

JSON-RULES
- unified JsonRules stored as authoritative rule set
- ascii-default: ASCII recommended; Unicode allowed
- utf8-without-bom: JSON must be UTF-8 without BOM
- newline-crlf: JSON files must end with CRLF
- deterministic-output: identical input → identical output

JSON-METADATA
- scope: durable-memory
- location: .copilot/Rules/JsonRules.md
