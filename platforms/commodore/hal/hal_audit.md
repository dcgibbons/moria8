# Commodore HAL Audit

This directory is contract-only. Platform-owned code must live under
`platforms/commodore/c64/hal`, `platforms/commodore/c128/hal`, or
`platforms/commodore/plus4/hal`.

Static boundary checks are intentionally baseline-aware while the migration is
in progress. Existing leaks are listed in `docs/hal_boundary_allowlist.txt`.
New common-code references to platform hardware, drive assumptions, or raw
machine-specific banking should fail `make check-hal-boundaries`.

The allowlist is technical debt, not permission to extend the old pattern.
