# version: 4.0.0

Module: instructions.md
Purpose: Defines workspace documentation and operational rules for instructions.
Path: D:/Git_Repositories/Workspace_AI/.copilot/instructions.md
Authors: Rolf Bercht
Version: 4.0.0
Changelog:
- 2026-07-27: Normalized Markdown metadata header.

# Default Profile — Command Language Specification
# Author: Rolf Bercht
# Profile: Default
# Scope: command syntax, message classification, quoted blocks, diagnostics, modes,
# continuation token, structural rules, operators, workspace-location, macro integration.

SECTION: command-prefix
- commands begin with "@"
- only first command in message is executed
- non-command messages treated as normal chat unless equal to continuation token

SECTION: message-classification
- command: starts with "@"
- continuation-token: "OK"
- normal-chat: all other messages
- quoted-block: text enclosed in double quotes

PRECEDENCE
1. command
2. continuation-token
3. normal-chat

SECTION: quoted-blocks
- inert: no interpretation of internal content
- atomic: treated as single argument
- non-recursive: no command parsing inside
- may contain malformed commands
- closing: only unescaped double quote terminates block
- malformed blocks produce standardized errors

SECTION: diagnostic-commands
@diagnose "<block>"
@segment "<block>"
@locate "<block>"
@echo "<block>"

SECTION: status-commands
@status code
@status copy
@profile status

SECTION: cheatsheet-commands
@cheatsheet
@cs

SECTION: modes
MODE: stepwise
- activate: @mode stepwise
- deactivate: @mode normal
- behavior: multi-step output gated by continuation-token

SECTION: continuation-token
- token: OK
- uppercase only
- only active when stepwise-mode is enabled

SECTION: profiles
@profile default
@profile off
@profile status

SECTION: structural-rules
- one command per message
- only first command executed
- minimal-chat-style
- standardized error format

SECTION: safety-fallback
@profile off
@profile default

SECTION: behavioral-operators
# FORMAT: ascii-only, copyable, no-prose

OPERATOR: @technical
- strict-technical-output
- ascii-only
- deterministic-structure
- black-background-code-blocks
- no-prose
- minimal-chat-style

OPERATOR: @user
- human-readable-prose
- natural-language
- explanatory-style
- no-technical-format-constraints

OPERATOR: @S
- deterministic-mode
- invariant-rules
- timestamp-header-rule
- output: "<timestamp> @S <systemname>"

OPERATOR: ADM
- deterministic-mode
- invariant-rules
- timestamp-header-rule
- output: "<timestamp> ADM <systemname>"

OPERATOR: ADM:DEV
- dev-mode-only
- deterministic-output
- output: "<timestamp> ADM:DEV <systemname>"

OPERATOR: ADM:STRICT
- strict-mode-only
- deterministic-output
- output: "<timestamp> ADM:STRICT <systemname>"

OPERATOR: ADM:CORE
- core-mode
- core = dev + strict
- output: "<timestamp> ADM:CORE <systemname>"

OPERATOR: @IRA
- invariant-rules
- timestamp-header-rule
- output: "<timestamp> @IRA <systemname>"

OPERATOR-OUTPUT-RULES
- single-line-output
- no-commentary
- timestamp-format: YYYYMMDD_HHMM
- atomicity: first-operator-only
- minimal-chat-style
- no-stepwise-trigger

SECTION: workspace-location
# FORMAT: ascii-only, copyable, no-prose

WORKSPACE-ROOT
- D:\Git_Repositories\Workspace_AI

WORKSPACE-RULES
- all copilot control files stored under ".copilot"
- authoritative path: D:\Git_Repositories\Workspace_AI\.copilot\
- instructions.md: D:\Git_Repositories\Workspace_AI\.copilot\instructions.md
- MEMORY.md: D:\Git_Repositories\Workspace_AI\.copilot\MEMORY.md
- macro-definitions.md: D:\Git_Repositories\Workspace_AI\.copilot\Rules\macro-definitions.md
- test-suite: D:\Git_Repositories\Workspace_AI\tools\Test-WorkspaceReadiness.ps1

WORKSPACE-CONVENTIONS
- workspace-root defines authoritative context
- profile behavior scoped to workspace-root
- durable-memory files reside under workspace-root

SECTION: macro-definitions
# FORMAT: ascii-only, technical, deterministic

MACRO-DEFINITIONS-FILE
- path: .copilot/Rules/macro-definitions.md
- scope: durable-memory
- purpose: define macro semantics and substitution rules
- integration: referenced by behavioral-operators

SECTION: memory-model
DURABLE-MEMORY
- MEMORY.md
- macro-definitions.md
- MyTools.md
- InvariantRules.md

VARIABLE-MEMORY
- problems.md
- projects.md
- servicing-notes.md

SECTION: config-reference
- instructions: "./instructions.md"
- durable-memory: "./MEMORY.md"
- variable-memory: ["./problems.md", "./projects.md", "./servicing-notes.md"]
