# Elevation & Privilege Governance Policy

- Rule ID: `RULE-ELEV-001` through `RULE-ELEV-004`
- Scope: Solution-Wide (All Repositories Governed by LCM v4.1.0)
- Classification: Invariant Rule
- Version: 1.0.0
- Updated: 2026-08-16

---

## 1. Rule Overview & Core Invariants

Certain solution components (such as disk/volume inspectors, boot configuration tools, driver managers, and background service setters) require Windows Administrator privileges to access low-level operating system APIs (e.g. `bcdedit`, `fltmc`, `fsutil`, `Get-Partition`, `DiskPart`).

To maintain predictability, prevent hanging automated runners, and enforce documentation-to-code consistency across the workspace, the following rules are mandatory:

---

## 2. Normative Elevation Rules

### `RULE-ELEV-001` (Mandatory Elevation Metadata)
Every repository governed under LCM `MUST` declare an explicit `execution_context` block inside its `.lcm/config.json`:
```json
"execution_context": {
  "elevation_required": true,
  "minimum_privilege": "Administrator",
  "reason": "Requires low-level access to bcdedit, fltmc volumes, and storage IOCTLs"
}
```
* If the repository does not require elevation, `elevation_required` `MUST` be set to `false`, `minimum_privilege` to `"User"`, and `reason` to `"Standard user execution"`.

### `RULE-ELEV-002` (Guarded Self-Elevation in Source Code)
Any script within `src/` or `Source/` that implements interactive self-elevation (`Start-Process pwsh -Verb RunAs`) `MUST` guard the elevation call with non-interactive detection:
1. `MUST` check whether the environment is interactive (`[Environment]::UserInteractive` and presence of console UI).
2. `MUST` support an explicit `-NoElevation` or `-ForceInProcess` switch to suppress UAC popups during automated test execution.
3. `MUST NOT` block headless CI/CD agents, IDE test adapters, or background runners on modal GUI UAC prompts.

### `RULE-ELEV-003` (Privileged Code Declaration & Anti-Drift)
Any code in `src/` or `Source/` utilizing privileged Windows commands (`bcdedit`, `fltmc`, `fsutil`, `Get-Partition`, `DiskPart`, `Add-BitLockerKeyProtector`, or `Verb RunAs`) `MUST` have `elevation_required: true` declared in `.lcm/config.json`.
* The quality gate `Assert-RepoElevationConsistency` `MUST` fail if undeclared privileged code is detected in a repository configured with `elevation_required: false`.

### `RULE-ELEV-004` (Automated Elevated Test Runner)
Every repository with `elevation_required: true` `MUST` provide a standardized elevated test runner (`tools/Invoke-ElevatedTest.ps1`):
1. Automatically executes Pester tests in-process when the current session is already elevated.
2. When called from a standard user session, dispatches an elevated worker process (`Start-Process -Verb RunAs`), captures the test run, and writes structured JSON test evidence (`out/test_results.json`).
3. Quality gates `MUST` certify test passage based on the generated test evidence.
