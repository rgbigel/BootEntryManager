# File: CMDRules.md

Module: CMDRules
Purpose: Authoritative rules for CMD batch generation and normalization.
Path: .copilot/Rules/CMDRules.md
Authors: Rolf
Version: 2.0.0
Changelog:
- 2026-07-27: Split unified rule file; stabilized CMD rules.

CMD-RULES
- unified CMDRules stored as authoritative rule set
- ascii-default: ASCII required
- newline-crlf: batch files must end with CRLF
- deterministic-output: identical input → identical output

CMD-METADATA
- scope: durable-memory
- location: .copilot/Rules/CMDRules.md
