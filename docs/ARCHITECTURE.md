# Architecture Reference

## Source Layout

| Path | Purpose |
| --- | --- |
| `Makefile` | Thin root wrapper around `commodore/Makefile` |
| `commodore/Makefile` | Main build, disk, run, and test orchestration |
| `commodore/c64/` | C64 entry, platform code, tests, and harness scripts |
| `commodore/c128/` | C128 boot, VDC/MMU code, tests, and harness scripts |
| `commodore/plus4/` | Plus/4 entry, TED platform code, tests, and harness scripts |
| `commodore/common/` | Shared gameplay, UI, data, and utility modules |
| `data/` | Source data used by generators |
| `tools/` | Build-time conversion, generation, lint, and disk helpers |
| `artwork/` | Source artwork and public art credits |

Primary entry points are `commodore/c64/main.s`, `commodore/c128/main.s`,
and `commodore/plus4/main.s`.

## Shared Runtime Modules

Shared modules cover turn sequencing, player state, dungeon generation,
line-of-sight, combat, monster AI, item handling, stores, magic, save/load,
score handling, string banks, and common UI. Platform files provide display,
input, memory, and loader services behind target-specific APIs.

Entity data follows struct-of-arrays layout. Arithmetic should use the existing
math helpers, and random behavior should use the project RNG.

## Current Footprint

These figures are derived from the product PRG artifacts emitted by
`make build`. They count PRG payload bytes and exclude the two-byte load
address headers, boot stubs, and title art. The flat total is the hypothetical
size required if the resident payloads, banked/runtime payloads, and every
mutually exclusive overlay had to coexist in one contiguous address space.

| Port | Resident / non-overlay | Overlay total | Largest overlay slot | Flat contiguous total |
| --- | ---: | ---: | ---: | ---: |
| C64 | 51,481 bytes | 28,002 bytes | 4,068 bytes | 79,483 bytes / 77.6 KiB |
| C128 | 56,114 bytes | 29,254 bytes | 4,088 bytes | 85,368 bytes / 83.4 KiB |
| Plus/4 | 50,494 bytes | 27,793 bytes | 4,068 bytes | 78,287 bytes / 76.5 KiB |

The overlay architecture is therefore not optional polish: every current port
would exceed a practical flat 64 KB target if all loaded pieces had to be
resident at once.

## Screen Ownership

Screen redraws must be owned by the view being entered, not by incidental
cleanup in the caller. Full-screen views should establish their whole visible
contract before drawing dynamic text; modal or overlay exits should restore the
gameplay view through the platform-safe full-screen clear path before rendering
viewport, status, and messages.

The title screen has an explicit shared clear contract:

- `title_clear_full_screen` clears all rows before and after KERNAL title-art
  loading, removing loader/status residue before the title art is rendered.
- `title_clear_below_menu` clears only the title screen's unowned lower band
  between the title art bottom border and the system-information row. On the
  25-row targets this is rows 20-22; row 19 is title-art border, row 23 is
  system information, and row 24 is left untouched.
- C128 mirrors the same behavior in its resident title/menu code, including the
  Bank 1 title-art cache path.

Gameplay-view restoration uses `ui_clear_full_screen_safe` rather than raw
platform clears so C64, C128, and Plus/4 can preserve their own clear semantics
while still rebuilding the viewport from a clean screen.

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

Current product payloads:

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `moria8.prg` | `$0801-$C129` | 47,401 bytes |
| `64.bank` | `$F000-$FFEF` | 4,080 bytes |
| `ovl.start` | `$E000-$EFDF` | 4,064 bytes |
| `ovl.town` | `$E000-$EFE3` | 4,068 bytes |
| `ovl.death` | `$E000-$E644` | 1,605 bytes |
| `ovl.royal` | `$E000-$E233` | 564 bytes |
| `ovl.help` | `$E000-$EEAC` | 3,757 bytes |
| `ovl.ui` | `$E000-$EFA1` | 4,002 bytes |
| `ovl.items` | `$E000-$EF13` | 3,860 bytes |
| `ovl.spell` | `$E000-$E9C9` | 2,506 bytes |
| `ovl.gen` | `$E000-$EDF7` | 3,576 bytes |

## Plus/4 Runtime Model

The Plus/4 port follows the C64 40-column gameplay model and disk-loaded
overlay strategy, but TED screen/color ownership moves the product image start
and main payload boundaries for this target.

- BASIC stub loads at `$1001`.
- The main product image currently occupies `$1001-$C806`.
- `$D000-$DFFF` is not the C64 VIC-II/CIA/SID model; Plus/4 platform code owns
  TED and ROM/RAM switching behind its HAL.
- `$E000-$EFFF` is the overlay window.
- `$F000-$FD37` currently holds the banked runtime payload.

Current product payloads:

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `moria4.prg` | `$1001-$C806` | 47,110 bytes |
| `4.bank` | `$F000-$FD37` | 3,384 bytes |
| `ovl.start` | `$E000-$EFDF` | 4,064 bytes |
| `ovl.town` | `$E000-$EFE3` | 4,068 bytes |
| `ovl.death` | `$E000-$E85A` | 2,139 bytes |
| `ovl.royal` | `$E000-$E233` | 564 bytes |
| `ovl.help` | `$E000-$EE9D` | 3,742 bytes |
| `ovl.ui` | `$E000-$EFA1` | 4,002 bytes |
| `ovl.items` | `$E000-$EC47` | 3,144 bytes |
| `ovl.spell` | `$E000-$E9BD` | 2,494 bytes |
| `ovl.gen` | `$E000-$EDF7` | 3,576 bytes |

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
| `$0400-$07FF` | Scratch/test/BFS path area; C128 VDC renderer stages row buffers at `$0500-$05ED` |
| `$0A80-$0AFB` | `128.proj` projectile runtime payload |
| `$0B00-$0BF7` | `128.input` raw-input runtime payload |
| `$0C00-$0C05` | MMU/KERNAL save bytes |
| `$0C06` | MMU helper blob in common RAM |
| `$0D60-$0FF3` | Runtime-common / feature-disk payload |
| `$1000-$19FD` | `128.runtime` low runtime payload |
| `$1A00-$1AFF` | Floor-item table |
| `$1B00-$1BFF` | Creature scratch |
| `$1C01-$5FFF` | Main program image: boot path, loaders, trampolines, wrappers |
| `$6000-$8C69` | `128.world` resident world payload, including C128 cache/overlay state, overlay filename tables, and C128 infravision helpers |
| `$8C70-$A648` | `128.item` resident item payload |
| `$A800-$AAE0` | `128.select` resident selector payload |
| `$AB00-$AEE0` | `128.diskio` payload |
| `$AF00-$B85A` | `128.persist` save/modal payload when loaded |
| `$AF00-$CFE7` | `128.play` gameplay payload when loaded |
| `$D000-$DFFF` | I/O hole; forbidden for ordinary runtime payloads |
| `$E000-$EFFF` | Overlay execution window |
| `$F000-$FEAF` | Reloadable banked runtime payload, asserted below `$FF00` |

The `$AF00-$CFFF` resident slot is mutually exclusive. Save/load uses resident
broker routines to load `128.persist`, perform the operation, then restore
`128.play` before returning to gameplay. `128.play` must remain entirely below
`$D000`; the current product build leaves `$CFE8-$CFFF` free before the I/O
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
| `128.names` | `$7FFF`, loaded into Bank 1 DB/data RAM |
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

The C128 product disk also carries `128.names`, a resident Bank 1 DB payload
loaded after the boot copy/scrub sequence. It currently occupies `$7400-$7734`
inside the Bank 1 DB/data window and stores fixed known item-name token streams.
The token dictionary remains in Bank 0 `128.item`, and C128 known-name decoding
reads Bank 1 source bytes through the DB MMU helpers.

Current product payloads:

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `moria128.prg` | `$1C01-$5FFF` | 17,407 bytes |
| `128.input.prg` | `$0B00-$0BF7` | 248 bytes |
| `128.proj.prg` | `$0A80-$0AFB` | 124 bytes |
| `128.fdisk.prg` | `$0D60-$0FF3` | 660 bytes |
| `128.runtime.prg` | `$1000-$19FD` | 2,558 bytes |
| `128.names.prg` | `$7400-$7734` | 821 bytes |
| `128.world.prg` | `$6000-$8C69` | 11,370 bytes |
| `128.item.prg` | `$8C70-$A648` | 6,617 bytes |
| `128.select.prg` | `$A800-$AAE0` | 737 bytes |
| `128.diskio.prg` | `$AB00-$AEE0` | 993 bytes |
| `128.persist.prg` | `$AF00-$B85A` | 2,395 bytes |
| `128.play.prg` | `$AF00-$CFE7` | 8,424 bytes |
| `128.bank.prg` | `$F000-$FEAF` | 3,760 bytes |
| `ovl.start` | `$E000-$EFDF` | 4,064 bytes |
| `ovl.town` | `$E000-$EF6F` | 3,952 bytes |
| `ovl.death` | `$E000-$EFF7` | 4,088 bytes |
| `ovl.royal` | `$E000-$E233` | 564 bytes |
| `ovl.gen` | `$E000-$EFE7` | 4,072 bytes |
| `ovl.help` | `$E000-$EEA6` | 3,751 bytes |
| `ovl.ui` | `$E000-$EFF4` | 4,085 bytes |
| `ovl.items` | `$E000-$EF79` | 3,962 bytes |
| `ovl.disarm` | `$E000-$E2CB` | 716 bytes |

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
