---
name: LanguagePolicy
description: Mandatory rule to enforce English language for all documentation, file names, code, and comments.
globs: "*"
---
<!-- ===================================================================== -->
<!-- ANTIGRAVITY RULE                                                      -->
<!-- Activation: Workspace Automatic                                       -->
<!-- ===================================================================== -->
# File: LanguagePolicy.md

Module: LanguagePolicy
Purpose: Authoritative rule enforcing English language usage across all workspace documentation, file names, and code.
Path: .agents/rules/LanguagePolicy.md
Authors: Rolf
Version: 1.0.0
Changelog:
- 2026-08-15: Initial persistent rule for English language invariant across all documentation, file names, code, and comments.

LANGUAGE-POLICY-RULES
- english-always: Use English language always for all documentation, file names, code, comments, change proposals, and commit messages.
- foreign-language-exception: Non-English languages are permitted only when explicitly working on targeted foreign language localization or translation tasks.
- english-filenames: All file and directory names must use English, ASCII-only naming.
- documentation-language: All markdown (.md) documents, headers, and specifications must be written in English.
- code-comments: All source code comments and docstrings must be written in English.
