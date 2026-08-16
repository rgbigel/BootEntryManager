# File: InvariantRules.md

Module: InvariantRules
Purpose: Authoritative invariant rules for workspace behavior and generation.
Path: .copilot/Rules/InvariantRules.md
Authors: Rolf
Version: 2.0.0
Changelog:
- 2026-08-01: Corrected TimeStampHeaderRule command to @THR and documented required timestamp format.
- 2026-07-27: Split unified rule file; corrected ASCII exceptions; stabilized invariants.

INVARIANT-RULES
- determinism: identical input → identical output
- reproducibility: no randomness
- ascii-default: ASCII required unless explicit exception applies
- ascii-exception-md: .md files may contain Unicode (arrows, bullets, umlauts, typographic symbols)
- ascii-exception-ps: PowerShell literal strings and comments may contain umlauts
- no-non-ascii-identifiers: identifiers must be ASCII-only
- constant-string-apostrophes: use single ASCII apostrophe
- indent-2: indentation level is exactly 2 spaces
- newline-crlf: Windows-native files end with CRLF
- utf8-without-bom: all text files UTF-8 without BOM
- structure: sections, lists, code blocks
- no-assumptions: unknown > guessing
- no-inference: do not invent missing facts
- no-speculation: no hypothetical reasoning
- no-verbosity: minimal-chat-style
- no-restating: do not repeat user facts
- no-repetition: no duplicated statements
- no-filler: every sentence must contribute
- explicit-reasoning: state logic when needed
- stepwise: only when required
- address-current-question-only
- refinements-modify-active-query
- english-default-language
- english-comments: all generated comments must be English
- timestamp-header-rule: TimeStampHeaderRule uses yyyyMMdd_HHmmss unless a technical exception is explicitly discussed

INVARIANT-COMMANDS
- @IRA activates InvariantRules
- @THR activates TimeStampHeaderRule
- @ml shows ordered visible messages in current chat

INVARIANT-METADATA
- scope: durable-memory
- location: .copilot/Rules/InvariantRules.md
