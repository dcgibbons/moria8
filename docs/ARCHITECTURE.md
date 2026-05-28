# Architecture Reference

## Source Layout

| Path | Purpose |
| --- | --- |
| `Makefile` | Thin root wrapper around `commodore/Makefile` |
| `commodore/Makefile` | Main build, disk, run, and test orchestration |
| `commodore/c64/` | C64 entry, platform code, tests, and harness scripts |
| `commodore/c128/` | C128 boot, VDC/MMU code, tests, and harness scripts |
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

Current product build occupancy is listed with linked endpoints. Segment
definitions still provide the hard maximums, and the build asserts both the
start addresses and all cross-boundary limits.

| Range | Owner |
| ---: | --- |
| `$0000-$03FF` | Zero page, stack, vectors |
| `$0400-$07FF` | Scratch/test/BFS path area |
| `$0A80-$0AFB` | `128.proj` projectile runtime payload |
| `$0B00-$0BFD` | `128.input` raw-input runtime payload |
| `$0C00-$0C05` | MMU/KERNAL save bytes |
| `$0C06` | MMU helper blob in common RAM |
| `$0D60-$0FF3` | Runtime-common / feature-disk payload |
| `$1000-$19EC` | `128.runtime` low runtime payload |
| `$1A00-$1AFF` | Floor-item table |
| `$1B00-$1BFF` | Creature scratch |
| `$1C01-$5F8F` | Main program image: boot path, loaders, trampolines, wrappers |
| `$6000-$8C3D` | `128.world` resident world payload, including C128 cache/overlay state and overlay filename tables |
| `$8D00-$A686` | `128.item` resident item payload |
| `$A800-$AAE8` | `128.select` resident selector payload |
| `$AB00-$AEFF` | `128.diskio` payload |
| `$AF00-$B826` | `128.persist` save/modal payload when loaded |
| `$AF00-$CF28` | `128.play` gameplay payload when loaded |
| `$D000-$DFFF` | I/O hole; forbidden for ordinary runtime payloads |
| `$E000-$EFFF` | Overlay execution window |
| `$F000-$FEBD` | Reloadable banked runtime payload, asserted below `$FF00` |

The `$AF00-$CFFF` resident slot is mutually exclusive. Save/load uses resident
broker routines to load `128.persist`, perform the operation, then restore
`128.play` before returning to gameplay. `128.play` must remain entirely below
`$D000`; the current product build leaves `$CF29-$CFFF` free before the I/O
hole.

Recent size pressure in `128.play` was handled by moving data, not by weakening
the boundary. Combat message strings and the C128 overlay/cache state now live
in `128.world`, while shared combat/stat helpers are externalized from the play
payload where needed. Direct trap disarm is a separate `128.disarm` overlay
loaded into `$E000-$EFFF`; C128 preloads it into the small Bank 1 cache region
at startup so gameplay disarm does not touch disk.

The C128 segment definition maxima are:

| Payload | Declared max |
| --- | ---: |
| `128.proj` | `$0AFF` |
| `128.input` | `$0BFF` |
| `128.fdisk` | `$0FFF` |
| `128.runtime` | `$3FFF`, with runtime-low asserted below the floor-item table |
| `128.world` | `$8CFF` |
| `128.item` | `$A7FF` |
| `128.select` | `$AAFF` |
| `128.diskio` | `$AEFF` |
| `128.persist` / `128.play` | `$CFFF` |
| `128.bank` | `$FFFA`, with linked code asserted below `$FF00` |

### Bank 1

| Range | Owner |
| ---: | --- |
| `$0000-$0FFF` | 4 KB common RAM; not cache-safe |
| `$1000-$1FFF` | Overlay cache slot for `OVL_UI` |
| `$2000-$2FFF` | Overlay cache slot for `OVL_HELP` |
| `$3000-$3FFF` | Overlay cache slot for `OVL_ITEMS` |
| `$4000-$730B` | Reserved future map span / live dungeon-town map ownership |
| `$7400-$7FFF` | Bank 1 DB/data region |
| `$8000-$94F7` | Active monster tier-cache window, 5368 bytes |
| `$94F8-$9CFF` | Title-art session cache |
| `$9D00-$9FFF` | Small overlay cache region, currently `OVL_DISARM` |
| `$A000-$AFFF` | Overlay cache slot for `OVL_STARTUP` |
| `$B000-$BFFF` | Overlay cache slot for `OVL_TOWN` |
| `$C000-$CFFF` | Overlay cache slot for `OVL_DEATH` |
| `$D000-$DFFF` | I/O-visible gap; not cache-safe |
| `$E000-$EFFF` | Overlay cache slot for `OVL_DUNGEON_GEN` |
| `$F000-$FEFF` | Top common RAM shared with Bank 0; not cache-safe |

The C128 product disk carries eight overlay files: `128.start`, `128.town`,
`128.death`, `128.gen`, `128.help`, `128.ui`, `128.items`, and `128.disarm`.
All eight are preloaded into Bank 1 before gameplay. The first seven use full
4 KB cache slots; `128.disarm` uses a page-counted small cache slot at `$9D00`
because it currently needs only three pages. Runtime overlay fetches copy the
descriptor's page count, not an unconditional 4 KB.

The source of truth for C128 ownership constants and overlap assertions is
`commodore/c128/memory128.s`; the product segment definitions and Bank 0
payload asserts live in `commodore/c128/main.s`.

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
