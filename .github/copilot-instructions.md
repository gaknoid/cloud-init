# Copilot Instructions for cloud-init (WSL on Windows)

## Repository purpose

This repository manages repeatable WSL Ubuntu bootstrap and maintenance using:

- PowerShell automation scripts for Windows-side setup and cleanup.
- cloud-init user-data files for Ubuntu distro initialization.

Primary files:

- `WSL2-Install-PreSetup.ps1`
- `WSL2-Optimize-VHDX.ps1`
- `Ubuntu-22.04.user-data`
- `Ubuntu-24.04.user-data`
- `Ubuntu-26.04.user-data`

## General coding expectations

- Keep changes minimal and focused on the requested task.
- Preserve script behavior and public parameters unless a change is
	explicitly required.
- Prefer safe defaults and explicit error handling
	(`$ErrorActionPreference = "Stop"`).
- Keep all content ASCII unless Unicode is already required.
- Document non-obvious logic with short, practical comments.

## PowerShell conventions

- Use advanced functions/cmdlets and clear parameter validation.
- Preserve support for `-WhatIf` where script design already supports
	`SupportsShouldProcess`.
- Avoid destructive operations unless clearly requested.
- When reading external command output that may be empty, normalize
	using array syntax (`@(...)`) and return `@()` instead of `$null`
	where collection semantics are expected.
- For mandatory `[string[]]` parameters that may intentionally be
	empty, use `[AllowEmptyCollection()]`.
- Treat unexpected empty discovery results (for example distro
	discovery) as unknown state and avoid aggressive removals.

## cloud-init conventions

- Keep cloud-init YAML valid and idempotent.
- Do not commit real credentials or environment-specific secrets.
- Keep placeholders explicit for values users must replace.
- Maintain compatibility across the supported Ubuntu versions unless
	version-specific behavior is intentional.

## Validation checklist for changes

When modifying PowerShell scripts:

1. Verify parameter and control-flow logic still works with `-WhatIf`.
2. Ensure failure paths provide actionable errors.
3. Confirm no regressions in admin/non-admin behavior.

When modifying cloud-init files:

1. Validate YAML structure and indentation.
2. Re-check all placeholder credentials and sample mount values.
3. Confirm package and command changes are suitable for non-interactive
	first boot.

## README and documentation

- Keep `README.md` aligned with script names, parameters, and execution order.
- Update docs in the same change when behavior or prerequisites change.
