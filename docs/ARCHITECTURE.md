# Architecture Reference

## Source Layout

| Path | Purpose |
| --- | --- |
| `Makefile` | Root build, disk, run, and test wrapper across all seven platform ports |
| `core/` | Platform-agnostic 6502 gameplay, UI, data, and utility modules |
| `platforms/commodore/Makefile` | Commodore build, disk, run, and test orchestration |
| `platforms/commodore/c64/` | C64 entry, platform code, tests, and harness scripts |
| `platforms/commodore/c128/` | C128 boot, VDC/MMU code, tests, and harness scripts |
| `platforms/commodore/plus4/` | Plus/4 entry, TED platform code, tests, and harness scripts |
| `platforms/commodore/common/` | Shared Commodore KERNAL, disk, overlay, and compatibility modules |
| `platforms/apple2/` | Apple IIe entry, ProDOS/aux platform code, MAME harness, and memory-contract checker |
| `platforms/cx16/` | Commander X16 entry, VERA/banked-RAM platform code, `x16emu` TestBench harness, and memory-contract checker |
| `platforms/atari8/` | Atari 8-bit (800XL/65XE/130XE) entry, ANTIC/POKEY/SIO/130XE platform code, MAME harness, and memory-contract checker |
| `platforms/bbcmaster/` | Acorn BBC Master 128 entry, Mode 0 `LYNNE`/Sideways RAM/DFS platform code, MAME harness, and memory-contract checker |
| `build/` | Generated payloads, disk images, checksums, and test scratch output |
| `data/` | Source data used by generators |
| `tools/` | Build-time conversion, generation, lint, and disk helpers |
| `artwork/` | Source artwork and public art credits |

Primary entry points are `platforms/commodore/c64/main.s`,
`platforms/commodore/c128/main.s`,
`platforms/commodore/plus4/main.s`,
`platforms/apple2/main.s`,
`platforms/cx16/main.s`,
`platforms/atari8/main.s`, and
`platforms/bbcmaster/main.s`.

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
| Apple IIe | 38,400 bytes | 39,445 bytes | 5,632 bytes | 77,845 bytes / 76.0 KiB |
| Commander X16 | 45,276 bytes | 42,332 bytes | 5,573 bytes | 87,608 bytes / 85.6 KiB |
| Atari 8-bit | 49,905 bytes | 35,862 bytes | 4,095 bytes | 85,767 bytes / 83.8 KiB |
| BBC Master 128 | 46,982 bytes | 42,746 bytes | 5,300 bytes | 89,728 bytes / 87.6 KiB |

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
| `ovl.modal` | `$E000-$E409` | 1,034 bytes |
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
| `ovl.modal` | `$E000-$E413` | 1,044 bytes |
| `ovl.help` | `$E000-$EE9D` | 3,742 bytes |
| `ovl.ui` | `$E000-$EFA1` | 4,002 bytes |
| `ovl.items` | `$E000-$EC47` | 3,144 bytes |
| `ovl.spell` | `$E000-$E9BD` | 2,494 bytes |
| `ovl.gen` | `$E000-$EDF7` | 3,576 bytes |

## Apple IIe Runtime Model

The Apple IIe port is ProDOS-based, 80-column, and uses the 128K IIe
main/aux memory split with disk-loaded overlays and an aux-resident cache
for hot classes. Memory rules live in `docs/APPLE2_MEMORY_POLICY.md`.

- `MORIA8.SYSTEM` (ProDOS SYS) loads at `$2000`, then streams the
  single-open `MORIA8.PAK` container (resident + auxdata + six hot
  overlays) with an `n/8` progress line before jumping to the resident
  entry.
- Resident code and data: `$0A00-$7BFF` in main RAM (hard boundary; the
  memory-contract checker enforces it).
- `A2.PLAY` (play payload, load-once + signature): `$7C00-$9FFF` in main RAM.
- Overlay window: `$A400-$B9FF` in main RAM; one overlay class resident at a
  time (start, town, death, modal, help, ui, items, spell, gen, storage,
  title).
- `A2.AUXDATA` (aux RAM at `$3B0C-$56FF`): read-only lookup tables, store
  data, spell helper tables, spell names; all access through the
  `AuxRead`/`AuxWrite` thunks.
- Dungeon map: aux RAM at `$0800` (198x66 tile rows); row pointer tables in
  main RAM, tile access through the `MapRead`/`MapWrite` thunks.
- Hot overlay classes are cached in aux RAM; cold classes load from disk on
  demand (`docs/CROSS_PLATFORM_STRATEGY.md` — partial cache, not full
  preload).
- Overlay-loaded code must return through the owning overlay's resident
  trampoline; trampolines that switch overlays restore the caller's overlay
  (see the spell/item/modal restore trampolines in
  `platforms/apple2/main.s`).

Current product payloads:

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `MORIA8.SYSTEM` | `$2000-$21DD` | 478 bytes |
| `MORIA8.PAK` | `$0A00-$7BFF` resident | ~62 KB |
| `A2.PLAY` | `$7C00-$9FFF` | 9,216 bytes |
| `OVL.*` (11 classes) | `$A400-$B9FF` window | 0.3-5.6 KB each |
| `A2.AUXDATA` | aux `$3B0C-$55B5` | ~6.7 KB |

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
| `$F000-$FEFF` | Runtime top-common view shared with Bank 0; physical Bank 1 `$F000-$FD3A` holds the read-only Huffman corpus |
| `$FFFA-$FFFB` | Physical Bank 1 NMI vector bridge for transient Huffman corpus reads |

The C128 product disk carries nine overlay files: `128.start`, `128.town`,
`128.death`, `128.gen`, `128.help`, `128.ui`, `128.items`, `128.disarm`, and
`128.chest`. The first eight are preloaded into Bank 1 before gameplay; of
those, seven use full 4 KB cache slots while `128.disarm` uses a page-counted
small cache slot at `$9D00` because it currently needs only three pages.
`128.chest` is deliberately cold: it bypasses the cache and disk-loads on
demand. Runtime overlay fetches copy the descriptor's page count, not an
unconditional 4 KB.

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
| `128.persist.prg` | `$AF00-$BC19` | 3,354 bytes |
| `128.play.prg` | `$AF00-$CFF8` | 8,441 bytes |
| `128.bank.prg` | `$F000-$FEAF` | 3,760 bytes |
| `128.huff.prg` | Bank 1 `$F000-$FD3A` | 3,387 bytes |
| `128.hvec.prg` | Bank 1 `$FFFA-$FFFB` | 2 bytes |
| `ovl.start` | `$E000-$EFDF` | 4,064 bytes |
| `ovl.town` | `$E000-$EF6F` | 3,952 bytes |
| `ovl.death` | `$E000-$EFF7` | 4,088 bytes |
| `ovl.modal` | `$E000-$E233` | 564 bytes |
| `ovl.gen` | `$E000-$EFE7` | 4,072 bytes |
| `ovl.help` | `$E000-$EEA6` | 3,751 bytes |
| `ovl.ui` | `$E000-$EFF4` | 4,085 bytes |
| `ovl.items` | `$E000-$EF79` | 3,962 bytes |
| `ovl.disarm` | `$E000-$E2CB` | 716 bytes |
| `ovl.chest` | `$E000-$E41E` | 1,055 bytes |

The source of truth for C128 ownership constants and overlap assertions is
`platforms/commodore/c128/memory128.s`; the product segment definitions and
Bank 0 payload asserts live in `platforms/commodore/c128/main.s`.

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

## Commander X16 Runtime Model

The Commander X16 port is 80-column (VERA text in VRAM `$1B000`), uses the
38.6 KB unbanked low RAM (`$0801-$9EFF`) for a unified resident + gameplay
image, and maps the `$A000-$BFFF` 8 KB banked RAM window (selected via ZP
`$00`) to hold the live 198x66 dungeon map, read-only data banks, monster
tiers, and preloaded overlays. Full rules live in `docs/CX16_MEMORY_CONTRACT.md`.

- `$0400-$07FF` holds `FLOOR_ITEM_BASE` (`$0400`), `CREATURE_BASE` (`$0500`),
  `PLATFORM_HD_DECODE_BUF_BASE` / `DUNGEON_GEN_DOOR_SCAN_BASE` (`$0600`), and
  `CX16_ROW_STAGE_BASE` (`$0700`).
- `MORIA8.PRG`: `$0801-$97C8` (unified resident + gameplay image, asserted
  `<= $9AFF`).
- `PLATFORM_TIER_NAME_POOL_BASE`: `$9B00-$9EFF` (1,024 bytes).
- `$9F00-$9FFF`: VERA / VIA1 / VIA2 hardware I/O hole (forbidden to code/data).
- `$A000-$BFFF` banked RAM window (8 KB per bank):
  - Bank 0: reserved for CX16 KERNAL `KVARSB0`
  - Banks 1–2: live 198x66 dungeon map (virtual `$2000-$530B`)
  - Bank 3: `CX16.AUXDATA` (virtual `$6000-$737F`)
  - Bank 4: `CX16.HUFFDATA` (virtual `$8000-$8D93`)
  - Banks 5–8: `MONSTER.DB.1..4` (preloaded at boot)
  - Banks 9–20: `OVL.START`..`OVL.TITLE` (12 overlays, preloaded at boot)
  - Bank 21: `TITLE` artwork stream

Current product payloads:

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `MORIA8.PRG` | `$0801-$97C8` | 36,808 bytes |
| `CX16.AUXDATA` | virtual `$6000-$737F` (Bank 3) | 4,992 bytes |
| `CX16.HUFFDATA` | virtual `$8000-$8D93` (Bank 4) | 3,476 bytes |
| `OVL.*` (12 classes) | `$A000-$BFFF` window (Banks 9–20) | 0.3–5.6 KB each |

## Atari 8-Bit Runtime Model

The Atari 8-bit port targets the stock 64 KB Atari 800XL / 65XE (40-column
ANTIC Mode 2 display with DLI color zones and a 1 KB C64-screen-code-ordered
RAM font at `$0400-$07FF`) and automatically detects 128 KB Atari 130XE
extended RAM (`$4000-$7FFF` via `PORTB` `$D301`) at boot to cache overlays,
monster tiers, and title artwork. Full rules live in
`docs/ATARI8_MEMORY_CONTRACT.md`.

- `$0200-$031A` is reserved for Atari OS vectors, Page 2 display/timer shadows,
  and the `SIOV` DCB (`$0300-$030B`).
- `$0380-$03BF` holds `ATARI_DISPLAY_LIST`; `$0400-$07FF` holds
  `ATARI_CHARSET_BASE`; `$0800-$0BE7` holds `SCREEN_RAM` (all below `$4000` so
  neither OS ROM activation nor 130XE banking affects ANTIC DMA).
- Low resident helpers (`$0C00-$1FA1`, asserted `<= $4000`) hold all `PORTB`
  banking, `EnterSio`/`ExitSio` bounce I/O, interrupt handlers, and 130XE cache
  routines (`xe_detect`, `xe_cache_stash`, `xe_cache_fetch`).
- Resident `Default` (`MORIA8.RES`): `$0C00-$C03D` (asserted `<= $C100`).
- `MAP_BASE`: `$C100-$CFFF` (80x48 live map, 3,840 bytes, ending immediately
  below `$D000`).
- `$D000-$D7FF`: immovable GTIA / POKEY / PIA / ANTIC hardware I/O hole.
- `$D800-$DFFF`: high resident tables under OS ROM (`PLATFORM_TIER_NAME_POOL_BASE`
  `$D800-$DBFF`, `FLOOR_ITEM_BASE` `$DC00-$DCFF`, `PLATFORM_HD_DECODE_BUF_BASE`
  `$DD00-$DD3F`, `zp_save_buf` `$DD40-$DDCD`, and `msg_history` `$DDCE-$DF0D`).
- `$E000-$EFFF`: overlay and monster-tier execution/staging window (10 overlays
  `OVL.STA`..`OVL.GEN` and 4 monster tiers `MONSTER.DB1..4`).
- `$F000-$FFF9`: `RuntimeBanked` (`ATARI.BNK`), below the RAM CPU vectors at
  `$FFFA-$FFFF`.

Current product payloads:

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `boot.prg` | `$0800-$097F` | 384 bytes |
| `MORIA8.RES` | `$0C00-$C03D` | 46,142 bytes |
| `ATARI.BNK` | `$F000-$FEB2` | 3,763 bytes |
| `OVL.*` (10 classes) | `$E000-$EFFF` window | 2.1–4.1 KB each |

## Acorn BBC Master 128 Runtime Model

The Acorn BBC Master 128 port targets the stock 128 KB BBC Master 128 (65C12,
MOS 3.20, DFS 2.24), using an 80x24 Mode 0 bitmap in 20 KB Shadow RAM `LYNNE`
(`$3000-$7FFF` via `ACCCON` `$FE34`), `BeebHuffData` in 4 KB Private RAM `ANDY`
(`$8000-$8FFF` via `ROMSEL` `$FE30 = $84`), and 64 KB Sideways RAM (Banks 4–7
at `$8000-$BFFF`). Full rules live in `docs/BBCMASTER_MEMORY_CONTRACT.md`.

- `$0400-$07FF` holds `FLOOR_ITEM_BASE` (`$0400`), `CREATURE_BASE` (`$0500`),
  `PLATFORM_HD_DECODE_BUF_BASE` (`$0600`), `DUNGEON_GEN_DOOR_SCAN_BASE`
  (`$0640`), MOS control blocks (`$0681-$06FF`), and `beeb_ss_buf` (`$0700`).
- `$0800-$0DFF`: preserved Acorn MOS sound/envelope/DFS workspace (`PAGE = $0E00`).
- Low resident helpers (`$0E00-$2FFF`, asserted `<= $3000`) own all `ACCCON`
  and `ROMSEL` switching, the Mode 0 software blitter, `EnterMos`/`ExitMos`, and
  the `BRKV` fault handler.
- Resident `Default` (`MORIA8.RES`): `$0E00-$7FAD` (asserted `<= $8000`).
- 20 KB Shadow RAM `LYNNE` (`$3000-$7FFF`, `ACCCON = $05`): C64-ordered font
  (`$3000-$33FF`), `DUNGEON_GEN_SCAN_SCRATCH_BASE` (`$3400-$37FF`),
  `beeb_char_shadow` (`$3800-$3F7F`), and the 80x24 Mode 0 display bitmap
  (`$4400-$7FFF`).
- 4 KB Private RAM `ANDY` (`$8000-$8FFF`, `ROMSEL = $84`): `BeebHuffData`
  (`$8000-$8D93`).
- Sideways RAM Banks 4–7 (`$8000-$BFFF`):
  - Bank 4: `BeebPlaySlot` (`$8000-$A3E5`), `PLATFORM_TIER_NAME_POOL_BASE`
    (`$A400-$A7FF`), and the `$A800-$BFFF` active overlay/tier window (12
    overlays and 4 monster tiers)
  - Bank 5: live 198x66 dungeon map (`$8000-$B30B`) + cached `OVL.UI`
    (`$B400-$BDFF`)
  - Bank 6: `BeebAuxData` (`$8000-$945D`, virtual `$6000-$745D`) + cached
    `OVL.TOWN`, `OVL.MODAL`, and `MONSTER.DB1`
  - Bank 7: cached `OVL.SPELL`, `OVL.ITEMS`, and `OVL.GEN` (cold overlays and
    tiers 2–4 load on demand from DFS disk)

Current product payloads:

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `boot.prg` | `$1900-$1AAE` (relocates to `$0400`) | 431 bytes |
| `moria8.res.prg` | `$0E00-$7FAD` | 29,102 bytes |
| `beeb.play` | Bank 4 `$8000-$A3E5` | 9,190 bytes |
| `beeb.auxdata` | Bank 6 `$8000-$945D` (virtual `$6000-$745D`) | 5,214 bytes |
| `beeb.huffdata` | `ANDY` `$8000-$8D93` | 3,476 bytes |
| `ovl.*` (12 classes) | Bank 4 `$A800-$BFFF` window | 0.2–5.3 KB each |

## Test Harnesses

Runtime tests assemble target-specific PRGs and execute them under VICE
headless (`x64sc`, `x128`, `xplus4`), MAME headless (`apple2ee`, `a800xl`,
`a130xe`, `bbcm`), and `x16emu -testbench`. The non-Commodore ports each pair a
static memory-contract checker with a headless runtime scenario harness:

- Apple IIe: `platforms/apple2/harness_smoke.py` (14 scenarios + `boot_title`,
  requires `A2ROMS`) + `make testapple2-memory-contract`
- Commander X16: `platforms/cx16/harness_smoke.py` (20 scenarios under
  `x16emu -testbench`, requires `X16EMU`/`X16ROM`) +
  `make testcx16-memory-contract`
- Atari 8-bit: `platforms/atari8/harness_smoke.py` (15 `a800xl` scenarios + 3
  `a130xe` scenarios, requires `ATARI8ROMS`) +
  `make testatari8-memory-contract`
- Acorn BBC Master 128: `platforms/bbcmaster/harness_smoke.py` (15 `bbcm`
  scenarios, requires `BBCMROMS`) + `make testbbcmaster-memory-contract`

Useful gates:

```sh
make test
make test64
make testplus4
make test128-fast
make test128-fast-smoke
make test128
make testapple2
make testcx16
make testatari8
make testbbcmaster
```

Tests that cross `$A000` on C64 need a bootstrap trampoline below the BASIC ROM
window before jumping to `test_start`.
