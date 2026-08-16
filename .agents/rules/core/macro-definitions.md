---
name: macro-definitions
description: Authoritative governance rule mirror for macro-definitions
globs: "*"
---
<!-- ===================================================================== -->
<!-- ANTIGRAVITY RULE MIRROR                                               -->
<!-- Source Authority: .copilot/Rules/macro-definitions.md                            -->
<!-- Activation: Workspace Automatic                                       -->
<!-- ===================================================================== -->
# macro-definitions.md
# version: 4.0.0

# MACRO-DEFINITIONS-METADATA
# scope: durable-memory
# location: .copilot/Rules/macro-definitions.md
# update-policy: manual

MACRO: @technical
- description: enforce strict technical, ascii-only, deterministic output
- rules:
  - no prose
  - no decoration
  - no emojis
  - no unicode
  - explicit structures only

MACRO: @user
- description: normal user-facing mode
- rules:
  - allow brief explanations
  - allow minimal formatting
  - keep responses concise

MACRO: @S
- description: system-aligned mode
- rules:
  - follow workspace rules
  - follow copilot profile
  - respect durable-memory files

MACRO: @profile status
- description: report current copilot profile state
- rules:
  - summarize durable-memory presence
  - summarize test-suite presence
  - summarize version alignment
