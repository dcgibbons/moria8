# Architecture Reference

## Source Layout

| Path | Purpose |
|---|---|
| `Makefile` | Thin root wrapper around `commodore/Makefile` |
| `commodore/Makefile` | Main build, disk, run, and test orchestration |
| `commodore/c64/` | C64 entry point, platform code, tests, and harness scripts |
| `commodore/c128/` | C128 boot, platform code, VDC/MMU code, tests, and harness scripts |
| `commodore/common/` | Shared gameplay, UI, data, and utility modules |
| `data/` | Source data used by generators |
| `tools/` | Build-time conversion, generation, lint, and disk helpers |
| `artwork/` | Source artwork and public art credits |

Primary entry points are `commodore/c64/main.s` and `commodore/c128/main.s`.

## Shared Runtime Modules

Shared modules cover turn sequencing, player state, dungeon generation,
line-of-sight, combat, monster AI, item handling, stores, magic, save/load,
score handling, string banks, and common UI. Platform files provide display,
input, memory, and loader services behind target-specific APIs.

Entity data follows struct-of-arrays layout. Arithmetic should use the existing
math helpers, and random behavior should use the project RNG.

## C64 Runtime Model

- BASIC stub loads and enters machine code.
- BASIC ROM is banked out after startup so RAM under `$A000-$BFFF` can hold
  program code/data.
- `$C000-$CEFF` owns the compact live map.
- `$CF00-$CFFF` owns the fixed floor-item table.
- `$D000-$DFFF` is the I/O/device window when I/O is visible.
- `$E000-$EFFF` is the overlay window.
- `$F000-$FFFA` is the banked runtime payload below CPU vectors.

All code and data movement around these boundaries must be checked with the
assembler memory map and existing `.assert` guards.

## C128 Runtime Model

The C128 build keeps game execution in Bank 0 except for scoped Bank 1 data
access. It uses explicit runtime-loaded payloads, C128 KERNAL bank setup, MMU
helpers, VDC display code, and fixed overlay/cache ownership.

### Bank 0

| Range | Owner |
|---:|---|
| `$0000-$03FF` | Zero page, stack, vectors |
| `$0400-$07FF` | Scratch/test/BFS path area |
| `$0A80-$0AFF` | `128.proj` projectile runtime payload |
| `$0B00-$0BFF` | `128.input` raw-input runtime payload |
| `$0C00-$0C05` | MMU/KERNAL save bytes |
| `$0C06` | MMU helper blob in common RAM |
| `$0D60-$0FFF` | Runtime-common payload |
| `$1000-$3FFF` | `128.runtime` low runtime payload |
| `$1A00-$1AFF` | Floor-item table |
| `$1B00-$1BFF` | Creature scratch |
| `$1C01-$5FFF` | Boot, loaders, trampolines, wrappers, cache state |
| `$6000-$8CFF` | `128.world` payload |
| `$8D00-$A7FF` | `128.item` payload |
| `$A800-$AAFF` | `128.select` payload |
| `$AB00-$AEFF` | `128.diskio` payload |
| `$AF00-$CFFF` | Modal slot: `128.play` or `128.persist` |
| `$D000-$DFFF` | I/O hole; forbidden for ordinary runtime payloads |
| `$E000-$EFFF` | Overlay execution window |
| `$F000-$FFFA` | Reloadable banked runtime payload, asserted below `$FF00` |

The modal slot is mutually exclusive. Save/load uses resident broker routines
to load `128.persist`, perform the operation, then restore `128.play` before
returning to gameplay.

### Bank 1

| Range | Owner |
|---:|---|
| `$0000-$0FFF` | 4 KB common RAM; not cache-safe |
| `$1000-$1FFF` | Overlay cache slot for `OVL_UI` |
| `$2000-$2FFF` | Overlay cache slot for `OVL_HELP` |
| `$3000-$3FFF` | Overlay cache slot for `OVL_ITEMS` |
| `$4000-$730B` | Live dungeon/town map |
| `$7400-$7FFF` | Bank 1 DB/data region |
| `$8000-$94F7` | Active monster tier-cache window |
| `$94F8-$9FFF` | C128 title cache / reserved gap |
| `$A000-$AFFF` | Overlay cache slot for `OVL_STARTUP` |
| `$B000-$BFFF` | Overlay cache slot for `OVL_TOWN` |
| `$C000-$CFFF` | Overlay cache slot for `OVL_DEATH` |
| `$D000-$DFFF` | I/O-visible gap; not cache-safe |
| `$E000-$EFFF` | Overlay cache slot for `OVL_DUNGEON_GEN` |
| `$F000-$FEFF` | Reserved top gap |

The source of truth for C128 ownership constants and overlap assertions is
`commodore/c128/memory128.s`.

## C128 MMU Rules

- Runtime normally executes in Bank 0 all-RAM mode with I/O visible.
- Map access goes through MMU-safe helpers; VDC render paths must not raw-read
  Bank 1 map pointers.
- KERNAL calls use explicit KERNAL entry/exit paths.
- `$1000-$3FFF` is not common RAM in the shipping runtime.
- `$D000-$DFFF` is not safe executable RAM with I/O visible.
- `$D506` common RAM configuration is a system invariant.

## Runtime-Loaded Code Contract

For any C128 routine that is loaded from disk, copied at startup, recopied
later, banked, or entered through a trampoline, verify all five facts together:

1. Linked symbol address
2. PRG load address/header
3. Destination bank at load time
4. Visible execution bank at the call site
5. Source-span survival for later recopies

Asserting only the trampoline address is insufficient. The callee placement and
the staged source span must also be covered by assertions or direct inspection.

## Test Harnesses

Runtime tests assemble target-specific PRGs and execute them under VICE
headless. C128 also has Python compare and smoke harnesses for faster iteration.

Useful gates:

```sh
make test
make test128-fast
make test128-fast-smoke
make test128
```

Tests that cross `$A000` on C64 need a bootstrap trampoline below the BASIC ROM
window before jumping to `test_start`.
