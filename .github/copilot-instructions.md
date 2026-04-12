# Copilot Instructions for cloud-init (WSL on Windows)

## Repository purpose

This repository manages repeatable WSL Ubuntu bootstrap and maintenance using cloud-init user-data files.

Primary files:

- `Ubuntu-22.04.user-data`
- `Ubuntu-24.04.user-data`
- `Ubuntu-26.04.user-data`

## General coding expectations

- Keep changes minimal and focused on the requested task.
- Preserve behavior and public parameters unless a change is
	explicitly required.
- Prefer safe defaults and explicit error handling.
- Keep all content ASCII unless Unicode is already required.
- Document non-obvious logic with short, practical comments.

## cloud-init conventions

- Keep cloud-init YAML valid and idempotent.
- Do not commit real credentials or environment-specific secrets.
- Keep placeholders explicit for values users must replace.
- Maintain compatibility across the supported Ubuntu versions unless
	version-specific behavior is intentional.

## Validation checklist for changes

When modifying cloud-init files:

1. Validate YAML structure and indentation.
2. Re-check all placeholder credentials and sample mount values.
3. Confirm package and command changes are suitable for non-interactive
	first boot.

## README and documentation

- Keep `README.md` aligned with file names, parameters, and execution order.
- Update docs in the same change when behavior or prerequisites change.
