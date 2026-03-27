# Moria8 — C128 Port

The C128 port runs in 80-column VDC mode and uses a stricter memory contract
than the C64 build:

- `$E000-$EFFF` is the live overlay execution window
- `$F000-$FFFA` is the reloadable banked payload window
- persistent overlay metadata/state lives in resident Bank 0 RAM
- callable residency contracts are declared in `io_contracts.s` and enforced by both `main.s` asserts and `run_tests128.sh`

That separation is mandatory. The original `New Game` CPU `JAM` failures were
caused by violating it.

## Key References

- [C128 Overlay / Preload Retrospective](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/c128/OVERLAY_PRELOAD_RETROSPECTIVE.md)
- [C128 Design Plan](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/c128/DESIGN_PLAN.md)
- [Top-level design reference](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-c128/commodore/DESIGN.md)

## Diagnostics Policy

Several incident-specific runners live in this directory. They are useful for
targeted failure analysis, but they are not architectural truth by themselves.

- Keep debug-only guards that enforce memory ownership or snapshot a preload transaction
- Prefer lightweight diagnostics that preserve `A/X/Y/P`
- Treat heavy exploratory runners as transient tools, not permanent design
- When a C128 callable path moves between resident, overlay, runtime-low, or banked regions, update `io_contracts.s` alongside the code change

## Regression Checklist

Any future C128 change touching overlays, preload I/O, banked payload
placement, or KERNAL wrappers should re-run:

1. `N` from title through summary, town entry, and first command
2. `N` twice in one session
3. at least one post-town overlay transition
4. help / inventory / character / equipment UI after town entry
