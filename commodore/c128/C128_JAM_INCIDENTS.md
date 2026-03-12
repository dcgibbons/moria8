# C128 JAM Incident Note

Recovery branch baseline: `23145d5`

This note records the recurring failure signatures that motivated the C128 stabilization work.

## Low-RAM / data execution signatures

- `$000A`
- `$3035`
- `$3043`
- `$7668`

These signatures indicate control-flow corruption or helper corruption that redirected execution into low RAM or data tables.

## I/O-hole / unsafe placement signatures

- `$D0A6`
- `$D153`
- `$D7EA`

These signatures indicate code or runtime strings drifting into the C128 `$D000-$DFFF` I/O-visible hole.

## Preload / overlay hang signature

- repeated hangs during `OVL.TOWN` preload/load handoff

These signatures indicate runtime invariant drift across KERNAL I/O boundaries:
- `$FF00`
- `$01`
- IRQ/NMI vector ownership
- CHRIN stub ownership
- common-RAM helper survival

## Stabilization requirements

- one owner module for runtime vectors, CHRIN stub, helper integrity, and named runtime states
- dedicated helper-page ownership in common RAM with guards and checksum
- compile-time and runner-level placement enforcement for critical symbols
- deterministic diagnostics that report the last reached gameplay stage instead of relying on monitor inference
