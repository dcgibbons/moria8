# Architecture Reference

## Source Layout

| Path | Purpose |
| --- | --- |
| `Makefile` | Root build, disk, cartridge, run, and test wrapper across all seven platform ports |
| `core/` | Platform-agnostic 6502 gameplay, UI, data, and utility modules |
| `platforms/commodore/Makefile` | Commodore build, disk, cartridge, run, and test orchestration |
| `platforms/commodore/c64/` | C64 entry, platform code, cartridge builder glue, tests, and harness scripts |
| `platforms/commodore/c128/` | C128 boot, VDC/MMU, dual-bank runtime, cartridge builder glue, tests, and harness scripts |
| `platforms/commodore/plus4/` | Plus/4 entry, TED platform code, cartridge builder glue, tests, and harness scripts |
| `platforms/commodore/common/` | Shared Commodore KERNAL, disk, overlay, catalog, REU, and compatibility modules |
| `platforms/shared/` | Cross-architecture modules shared by all seven ports (`save.s`, `save_slot_menu.s`, `legal_disk_stream.s`, `legal_entry.s`, shared catalog/item generators) |
| `platforms/apple2/` | Apple IIe entry, ProDOS/aux/LC platform code, MAME harness, and memory-contract checker |
| `platforms/cx16/` | Commander X16 entry, VERA/banked-RAM platform code, cartridge loader, `x16emu` TestBench harness, and memory-contract checker |
| `platforms/atari8/` | Atari 8-bit (800XL/65XE/130XE) entry, ANTIC/POKEY/SIO/130XE platform code, cartridge loader, MAME harness, and memory-contract checker |
| `platforms/bbcmaster/` | Acorn BBC Master 128 entry, Mode 0 `LYNNE`/Sideways RAM/DFS platform code, MAME harness, and memory-contract checker |
| `build/` | Generated payloads, disk images, cartridge images, checksums, and test scratch output |
| `data/` | Source data consumed by generators (`LICENSE`, `SOURCE-OFFER`, item/monster/title assets) |
| `tools/` | Build-time conversion, catalog/Huffman/cartridge generation, lint, and budget checkers |
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
line-of-sight, combat, monster AI, item and chest handling, stores, magic,
monster/item catalog lookup, save/load (Format V2 `$22`), score handling,
Huffman/string banks, legal notice viewers, and common UI. Platform files
provide display, input, memory, and loader services behind target-specific HAL
APIs.

Entity data follows struct-of-arrays layout. Arithmetic should use the existing
math helpers, and random behavior should use the project RNG.

## Current Footprint

These figures come from the disk/bundle runtime payloads emitted by
`make build` (`tools/report_memory_budgets.py` + `build/<port>/` artifacts).
Payload byte counts exclude two-byte PRG load-address headers, standalone boot
stubs (`MORIA8.SYSTEM` / `boot.prg`), `title` art blobs, mutually exclusive cold
C128 `128.persist`, and the cold `legalui` overlay (`2,056–2,424` bytes).
Because every port externalizes the 279-species monster catalog and 361-item
`'ITM2'` catalog outside resident RAM, those catalog payloads are shown in
their own column alongside the resident/banked code and `12–13` mutually
exclusive overlays.

| Port | Resident + banked/aux | Monster + item catalogs | Overlay total (`classes`) | Largest overlay | Flat contiguous (`res + ovl` / incl. catalogs) |
| --- | ---: | ---: | ---: | ---: | ---: |
| C64 | 53,692 bytes | 24,288 bytes | 47,620 bytes (13) | 4,069 bytes | 101,312 B (98.9 KiB) / 125,600 B (122.7 KiB) |
| C128 | 56,951 bytes | 18,949 bytes | 41,972 bytes (12) | 4,045 bytes | 98,923 B (96.6 KiB) / 117,872 B (115.1 KiB) |
| Plus/4 | 50,747 bytes | 24,288 bytes | 49,258 bytes (13) | 4,089 bytes | 100,005 B (97.7 KiB) / 124,293 B (121.4 KiB) |
| Apple IIe | 50,680 bytes | 15,569 bytes | 55,417 bytes (13) | 5,565 bytes | 106,097 B (103.6 KiB) / 121,666 B (118.8 KiB) |
| Commander X16 | 48,749 bytes | 15,686 bytes | 54,225 bytes (13) | 7,109 bytes | 102,974 B (100.6 KiB) / 118,660 B (115.9 KiB) |
| Atari 8-bit | 50,292 bytes | 23,381 bytes | 48,338 bytes (13) | 4,024 bytes | 98,630 B (96.3 KiB) / 122,011 B (119.2 KiB) |
| BBC Master 128 | 46,773 bytes | 18,949 bytes | 53,424 bytes (13) | 5,744 bytes | 100,197 B (97.8 KiB) / 119,146 B (116.4 KiB) |

Notes on the disk payload sums:

- **C64 / Plus/4**: `moria8.prg` (`49,634` B) and `moria4.prg` (`47,739` B)
  include init-only startup tails past `MAP_BASE` (`InitTail` ends at `$C9E3`
  and `$CA7C`, respectively) that are overwritten once the first map generates.
- **C128**: `56,951` B sums `moria128.prg`, common runtime payloads
  (`128.proj`, `128.input`, `128.fdisk`, `128.runtime`), `128.bank`, `128.play`,
  and Bank 1 Huffman (`128.huff`, `128.hvec`); `128.persist` (`4,386` B) shares
  the `$AF00-$CFFF` slot with `128.play`.
- **Atari 8-bit**: Catalog sum reflects `279 × 57 B` Phase 5 monster records
  (`15,903` B) + `'ITM2'` `ITEM.CAT` (`7,478` B); on DOS 2.5 `.atr` disk,
  `MONSTER.CAT` is padded to 2 records per 125-byte sector (`17,432` B raw).

The overlay and banked-catalog architecture is therefore load-bearing: every
port would far exceed a flat 64 KB address space if all resident code,
catalogs, and overlays had to coexist continuously.

## Screen Ownership

Screen redraws must be owned by the view being entered, not by incidental
cleanup in the caller. Full-screen views should establish their whole visible
contract before drawing dynamic text; modal or overlay exits should restore the
gameplay view through the platform-safe full-screen clear path before rendering
viewport, status, and messages.

The title screen has an explicit shared clear contract:

- `title_clear_full_screen` clears all rows before and after title-art loading,
  removing loader/status residue before the title art is rendered.
- `title_clear_below_menu` clears only the title screen's unowned lower band
  between the title art bottom border and the system-information row. On the
  25-row targets this is rows 20–22; row 19 is title-art border, row 23 is
  system information, and row 24 is left untouched.
- C128 mirrors the same behavior in its resident title/menu code, including the
  Bank 1 title-art cache path.

Gameplay-view restoration uses `ui_clear_full_screen_safe` rather than raw
platform clears so all ports can preserve their own clear semantics while still
rebuilding the viewport from a clean screen.

## C64 Runtime Model

- BASIC stub loads and enters machine code (`$0801`).
- BASIC ROM is banked out after startup so RAM under `$A000-$BFFF` holds
  program code/data.
- Forever-resident code (`Default`) runs `$0801-$BFC1` (`47,041` B, asserted
  `<= MAP_BASE`, `62` B free); `InitTail` continues to `$C9E2` (`49,634` B total,
  asserted `<= CATALOG_IDX_LOAD`) and is overwritten once the map builds.
- `$C000-$CEFF` owns the compact live 80x48 map (`3,840` B); `$CE00` doubles at
  boot as `CATALOG_IDX_LOAD` for `monster.idx`/`item.idx`.
- `$CF00-$CFFF` owns the fixed 256-byte floor-item table.
- Hidden RAM under `$D000-$DFFF` (`SEI + BANK_ALL_RAM` `$30`):
  - `$D000-$D3FF`: `CATALOG_NAME_POOL` (32 active species × 32 B).
  - `$D400-$D4FF`: `CATALOG_HIDDEN` (monster level index + sector tables).
  - `$D500-$D6FF`: `C64HuffIndex` (`496` B Huffman string index).
  - `$D700-$DEFF`: `C64HiddenAux` (`zp_save_buf` `$D700-$D78D` 142 B on disk,
    `msg_history` `$D78E-$D8CD` 320 B, `recall[279]` `$D8CE-$DD29` 1,116 B,
    and disk `ITEM_PICKUP_CACHE` `$DD2A-$DEFF` 470 B).
  - `$DF00-$DFFF`: strictly untouched (`REU` / cartridge I/O reserve).
- `$E000-$EFFF` is the overlay window (`13` mutually exclusive classes:
  `ovl.start`, `ovl.town`, `ovl.death`, `ovl.modal`, `ovl.gen`, `ovl.help`,
  `ovl.ui`, `ovl.items`, `ovl.spell`, `ovl.chest`, `ovl.home`, `ovl.storage`,
  `ovl.title`, plus cold `legalui`).
- `$F000-$FFFA` holds `64.bank` banked runtime payload below CPU vectors.
- Disk catalog files on `.d64` (loaded/streamed on demand and optionally cached
  into Commodore REU): `monster.cat1..4`, `monster.ext`, `monster.idx`,
  `item.cat`, `item.idx`.

Current disk product payloads (`build/c64/`):

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `moria8.prg` (`Default <= $C000` / full w/ `InitTail`) | `$0801-$BFC2` / `$C9E3` | 47,041 / 49,634 bytes |
| `C64HuffIndex` | `$D500-$D6F0` | 496 bytes |
| `C64HiddenAux` | `$D700-$DF00` | 2,048 bytes |
| `64.bank` | `$F000-$FFDA` | 4,058 bytes |
| `ovl.start..ovl.title` (13 overlays) | `$E000-$EFE5` | 2,930–4,069 bytes each |
| `legalui` (cold legal screen) | `$E000-$E978` | 2,424 bytes |

### C64 Cartridge Model (`moria8-c64.crt`)

- Builds under `-define C64_CARTRIDGE` into `build/c64-cart/` (`moria8-c64.crt`):
  CRT Type 32 `512 KB` banked ROML format (`147,808` B CRT file, `18` sparse
  8 KB CHIP packets allocated = `139,264` B, `132,845` B ROML used / `385,024`
  B free across `17` ROML banks at `$8000-$9FFF` selected via `$DE00` plus `1`
  Ultimax boot `ROMH` bank at `$E000-$FFFF`).
- Stores `23` assets (`124,653` B) indexed by 8-byte descriptors at `$8100`:
  boot loader copies `moria8.prg` (`$0801-$B638`, `44,599` B; `InitTail` to
  `$BA70`, `45,679` B) and `64.bank` (`4,058` B) into RAM via `$033C-$03FB`
  scratch before entering `$080E`.
- `C64HiddenAux` drops `zp_save_buf` and disk pickup caching (`1,578` B used /
  `2,048` B cap); `13` overlays, `MONSTER.CAT`, `MONSTER.EXT`, `ITEM.CAT`,
  `legalui` (`2,154` B), `LICENSE`, and `SOURCE-OFFER` stream directly from ROML
  banks without disk swaps or REU overhead. Character saves (`MORIA01`) still
  target IEC drives `8–11`.

## Plus/4 Runtime Model

The Plus/4 port follows the C64 40-column gameplay model and overlay strategy,
but TED screen/color ownership (`$0800-$0FFF`) and KERNAL workspaces move
product start and payload boundaries.

- BASIC stub loads at `$1001`.
- Forever-resident `Default` spans `$1001-$C776` (`46,966` B, asserted
  `<= MAP_BASE $C800`); `InitTail` runs to `$CA7B` (`47,739` B, asserted
  `<= CATALOG_IDX_LOAD $D600`) and is overwritten once the map builds.
- `$0400-$07FF` doubles: `ovl.gen` uses all `1,024` B as
  `DUNGEON_GEN_SCAN_SCRATCH` (`SEI` + all-RAM `$FF3F`); outside `ovl.gen`,
  caches dodge Plus/4 KERNAL workspaces (`$0400-$04FF` 256 B monster catalog
  LRU cache; `$0500-$05FF` KERNAL reserved; `$0600-$07AF` 432 B disk item
  pickup cache; `$07B0-$07FF` KERNAL reserved).
- `$C800-$D6FF` owns `MAP_BASE` (`$C800-$D6FF`); `$D700-$D7FF` owns
  `FLOOR_ITEM_BASE`.
- `$D800-$DFFF` hidden RAM under `$FF3F` (`PLATFORM_TIER_NAME_POOL_BASE`):
  - `$D800-$DBFF`: `CATALOG_NAME_POOL` (32 active species × 32 B).
  - `$DC00-$DCFF`: `CATALOG_HIDDEN` (`247` B disk / `117` B cart).
  - `$DD00-$DEFF`: `Plus4HuffIndex` (`496` B).
  - `$DF00-$DFFF`: `Plus4HighBss` (disk `item.cat` 64 B window + 63 B `item.idx`
    at `$DF00-$DF7E`, plus 254 B sector LRU buffer; unused on cart).
- `$E000-$EFFF` is the overlay window (`13` overlays + cold `legalui`).
- `$F000-$FBC0` holds `4.bank` banked runtime payload, strictly asserted below
  the hardware-visible `$FC00` TED/banking page ceiling.

Current disk product payloads (`build/plus4/`):

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `moria4.prg` (`Default <= $C800` / full w/ `InitTail`) | `$1001-$C777` / `$CA7C` | 46,966 / 47,739 bytes |
| `Plus4HuffIndex` | `$DD00-$DEF0` | 496 bytes |
| `Plus4HighBss` | `$DF00-$DF7F` | 127 bytes |
| `4.bank` | `$F000-$FBC0` | 3,008 bytes |
| `ovl.start..ovl.title` (13 overlays) | `$E000-$EFF9` | 3,305–4,089 bytes each |
| `legalui` (cold legal screen) | `$E000-$E831` | 2,097 bytes |

### Plus/4 Cartridge Model (`moria8-plus4.crt`)

- Builds under `-define PLUS4_CARTRIDGE` into `build/plus4-cart/`
  (`moria8-plus4.crt`): `c264 magic cart` (VICE CRT Type 1, `$FDD2` `C1LO` +
  `$FDFE` bank select, `16 × 16 KB` = `256 KB`, `141,540` B used / `120,604` B
  free, `23` assets = `125,156` B indexed at `$8100`).
- Enters at `$100E`; streams `13` overlays (`ovl.home` `4,070` B, `ovl.storage`
  `4,092` B), `MONSTER.CAT`, `MONSTER.EXT`, `ITEM.CAT`, `legalui` (`1,922` B),
  and legal docs directly from `$8000-$BFFF` ROM. Eliminates disk
  catalog/pickup caches (`Default` `$1001-$C10B` `45,322` B, `InitTail`
  `46,021` B, `4.bank` `$F000-$FAF3` `2,803` B, `Plus4HighBss` `0` B used),
  while saves (`MORIA+4`) use IEC drives `8–11`.

## Apple IIe Runtime Model

The Apple IIe port is ProDOS-based, 80-column (plain NMOS 6502 opcodes only),
and partitions a 128 KB Apple IIe across Main RAM, Aux RAM, and the Aux
Language Card (`$D000-$FFF9`). Memory rules live in
`docs/APPLE2_MEMORY_POLICY.md`.

- `MORIA8.SYSTEM` (`$2000-$231D`, `798` B ProDOS `SYS`) opens and streams the
  single-open `MORIA8.PAK` container (`22/42` entries, `110,146` B total; ProDOS
  `.po` image uses `264/280` blocks) into Main, Aux, and Aux Language Card RAM
  before jumping to resident entry.
- Main RAM:
  - `$0200-$028D`: `zp_save_buf` (`142` B `< $0290` MLI pathname).
  - `$02E0-$02F4`: ZP-free `ALTZP=1` Aux Language Card 16-byte bounce + args.
  - `$0301-$033A`: `MainLowScratch` (`58` B `< $033C` dungeon door scan).
  - `$0A00-$7BC1`: Always-resident `moria8a2.prg` (`29,122` B, `<= $7C00`, `62` B free).
  - `$7C00-$9FAE`: `A2.PLAY` play/modal slot (`9,135` B, `< $A000`).
  - `$A000-$A3FF`: `PLATFORM_TIER_NAME_POOL_BASE` (1 KB).
  - `$A400-$B9FF`: Overlay window (`13` overlay classes + cold `legalui`).
  - `$BB00-$BFFF`: ProDOS MLI staging buffer + MLI global page (`JSR $BF00`).
- Aux RAM (`$0000-$BFFF`, accessed via ZP `AuxRead`/`AuxWrite` & `MapRead`/`MapWrite` thunks):
  - `$0200-$03FF`: `A2_AUX_SCRATCH` (`512` B reserved below Aux text page).
  - `$0400-$07FF`: 80-col even-column text page.
  - `$0800-$3B0B`: Live `198x66` dungeon map (`13,068` B).
  - `$3B0C-$4EEF`: `A2.AUXDATA` (`5,091` B, cap `$5000`).
  - `$5000-$66E2`: `A2.CATALOG` monster catalog fields (`5,859` B, cap `$6700`).
  - `$6700-$8CFF`: Preloaded overlay cache slots: `OVL.UI` (`$6700-$6CFF`),
    `OVL.SPELL` (`$6D00-$80FF`), `OVL.MODAL` (`$8100-$8CFF`).
  - `$8D00-$A9A3`: `A2.HUFFDATA` (`7,332` B, cap `$AA00`).
  - `$AA00-$BFFF`: Preloaded `OVL.ITEMS` cache slot (`5,498` B, cap `$BFFF`).
- Aux Language Card (`$D000-$FFF9`, `~16` KB; `10,826` / `16,378` B used via
  `a2_aux_lc_bounce_xfer`):
  - Bank 1 `$D000-$D45B`: persistent `recall[279]` (`1,116` B).
  - Bank 2 `$D000-$D8B7`: `A2.CATEXT` (`2,232` B, unpacked from PackBits `A2.CATEXT.PB` `1,228` B).
  - High RAM `$E000-$FD35`: `'ITM2'` `ITEM.CAT` (`7,478` B).

Current product payloads (`build/apple2/`):

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `MORIA8.SYSTEM` (`moria8.system.prg`) | `$2000-$231D` | 798 bytes |
| `moria8a2.prg` | `$0A00-$7BC2` | 29,122 bytes |
| `A2.PLAY` | `$7C00-$9FAF` | 9,135 bytes |
| `A2.AUXDATA` | aux `$3B0C-$4EEF` | 5,091 bytes |
| `A2.CATALOG` | aux `$5000-$66E3` | 5,859 bytes |
| `A2.HUFFDATA` | aux `$8D00-$A9A4` | 7,332 bytes |
| `A2.CATEXT` / `ITEM.CAT` | Aux LC B2 `$D000` / Hi `$E000` | 2,232 / 7,478 bytes |
| `ovl.start..ovl.title` (13 overlays) | `$A400-$B9BD` window | 1,515–5,565 bytes each |
| `legalui` (cold legal screen) | `$A400-$AD03` | 2,307 bytes |

## C128 Runtime Model

The C128 build runs game code in Bank 0 except for scoped Bank 1 data/cache
accesses via common-RAM MMU helpers, and stores `'ITM2'` item records in 16 KB
VDC RAM (disk) or cartridge ROM (cartridge) while keeping 80-column VDC text
output behind HAL. Authoritative constants and overlap asserts live in
`platforms/commodore/c128/memory128.s` and `docs/C128_MEMORY_CONTRACT.md`.

### Bank 0

| Range | Owner |
| ---: | --- |
| `$0000-$03FF` | Zero page, stack, vectors |
| `$0400-$07FF` | Scratch/BFS path area; VDC renderer row staging at `$0500-$05ED` |
| `$0A80-$0AFC` | `128.proj` common projectile runtime (`124` B) |
| `$0B00-$0BFE` | `128.input` common raw-input runtime (`254` B) |
| `$0C00-$0D51` | MMU/KERNAL save bytes + common MMU helper blob (`$0C06+`; cart adds 32 B chunk bounce up to `$0D51`) |
| `$0D60-$0FD2` | `128.fdisk` common feature-disk payload (`626` B disk / `579` B cart `< $0FB0`) |
| `$1000-$19F3` | `128.runtime` low runtime payload (`2,547` B `<= FLOOR_ITEM_BASE`) |
| `$1A00-$1AFF` | Floor-item table |
| `$1B00-$1BFF` | Creature scratch |
| `$1C01-$AEAB` | Consolidated `moria128.prg` resident image (`37,546` B, asserted `<= $AF00`; includes boot/loaders/world/item/store/catalog glue) |
| `$AF00-$C022` | `128.persist` save/modal payload when loaded (`4,386` B) |
| `$AF00-$CF1E` | `128.play` gameplay payload when loaded (`8,222` B, mutually exclusive with `128.persist`, `< $D000`) |
| `$D000-$DFFF` | I/O hole; forbidden to Bank 0 runtime payloads |
| `$E000-$EFFF` | Overlay execution window (`12` classes + cold `legalui`) |
| `$F000-$FEDE` | `128.bank` reloadable banked runtime payload (`3,806` B, asserted `<= $FF00`) |

### Bank 1 & 16 KB VDC RAM

| Bank 1 Range | Owner |
| ---: | --- |
| `$0000-$0FFF` | 4 KB common RAM (shared with Bank 0; not cache-safe) |
| `$1000-$3FFF` | Cached hot overlays: `OVL_UI` (`$1000`), `OVL_HELP` (`$2000`), `OVL_ITEMS` (`$3000`) |
| `$4000-$730B` | Live `198x66` dungeon/town map (`MAP_BASE`, `13,068` B) |
| `$7400-$7A5F` | `Bank1DB`: `recall[279]` (`$7400-$785B`, `1,116` B) + `zp_save_buf` (`$785C-$78E9`, `142` B) |
| `$7A60-$9567` | Monster catalog region: `PLATFORM_TIER_NAME_POOL_BASE` (`$7A60-$7E5F`, `1,024` B) + `128.cat` (`$7E60-$9543`, `5,859` B) |
| `$9568-$97FF` | Title-art session cache |
| `$9800-$9FFF` | Small overlay caches: `OVL_MODAL` (`$9800-$9CFF`, `1,139` B payload / `1,141` B PRG, `141` B free; owns `winner_apply_retirement_bonus_storage`) + `OVL_DISARM` (`$9D00-$9FFF`, `740` B) |
| `$A000-$AFFF` | `OVL_STARTUP` boot slot, later overwritten post-startup by `128.cnm` catalog names (`$A000-$AD34`, `3,380` B) |
| `$B000-$CFFF` | Cached overlays: `OVL_TOWN` (`$B000`), `OVL_DEATH` (`$C000`) |
| `$D000-$DFFF` | `Bank1High` under `SEI + $7F NOIO` via `< $4000` trampoline: `128.cex` (`$D000-$D8B7`, `2,232` B) + store reserve (`$D8B8-$DCB7`, `1,024` B) + `msg_history` (`$DCB8-$DF37`, `640` B) |
| `$E000-$EFFF` | Cached overlay: `OVL_DUNGEON_GEN` |
| `$F000-$FEFF` | Top common (`128.huff` in physical Bank 1 `$F000-$FEF0`, `3,824` B; `$FFFA-$FFFB` `128.hvec` NMI bridge) |

On disk (`moria8-c128.{d64,d71,d81}`), the `12` overlays are `ovl.start`,
`ovl.town`, `ovl.death`, `ovl.modal`, `ovl.gen`, `ovl.help`, `ovl.ui`,
`ovl.items`, `ovl.disarm`, `ovl.chest`, `ovl.home`, and `ovl.storage` (the last
three are cold/uncached; `title` renders via Bank 1 session cache rather than
an `$E000` title overlay). Because Bank 1 has no spare slot for `'ITM2'`
`item.cat` (`7,478` B), the disk build partitions the **16 KB physical VDC RAM**:
`$1100-$1FFF` holds bytes `0..3839` and `$2008-$3C6D` packs bytes `3840..7477`
into the unused upper 8 bytes (`+$08..+$0F`) of each 16-byte `$2000-$3FFF` VDC
font slot, leaving display/attribute RAM intact on both 16 KB and 64 KB VDCs.

Current disk product payloads (`build/c128/`):

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `moria128.prg` | `$1C01-$AEAB` | 37,546 bytes |
| `128.proj` / `128.input` / `128.fdisk` / `128.runtime` | `$0A80–$19F3` | 124 / 254 / 626 / 2,547 bytes |
| `128.persist` / `128.play` (mutually exclusive) | `$AF00-$C022` / `$CF1E` | 4,386 / 8,222 bytes |
| `128.bank` | `$F000-$FEDE` | 3,806 bytes |
| `128.cat` / `128.cnm` / `128.cex` / `128.huff` | Bank 1 | 5,859 / 3,380 / 2,232 / 3,824 bytes |
| `item.cat` (to 16 KB VDC RAM on disk) | VDC `$1100` + `$2008+` | 7,478 bytes |
| `ovl.*` (12 overlays) | `$E000-$EFCD` | 740–4,045 bytes each |
| `legalui` (cold legal screen) | `$E000-$E879` | 2,169 bytes |

### C128 Cartridge Model (`moria8-c128.crt`)

- Builds under `-define C128_CARTRIDGE` into `build/c128-cart/` (`moria8-c128.crt`):
  Magic Desk 128 External Function ROM (`$8000-$BFFF`, VICE CRT Type 4,
  `16 × 16 KB` = `256 KB`, `141,718` B used / `120,426` B free), with `30/32`
  asset descriptors (`125,334` B) indexed at `$8100`.
- Boot code (`RomBoot <= $80FF`) selects cartridge banks via `$DE00`, runs Bank 0
  `cart_reader` (`$1FBF-$220F` under `MMU_CR=$3A`) plus bottom-common
  `mmu_common_cart_copy_chunk` (`$0FB0-$0FF3`, 32 B bounce at `$0D2E-$0D51`)
  to populate Bank 0 (`moria128` `$1C01-$AC7C` `36,987` B, `128.fdisk` `579` B),
  common slots, Bank 1 data (`128.cat`, `128.cnm`, `128.cex`, `128.huff`,
  `title`), overlays, and `legalui` (`2,036` B).
- `hal_item_cat_cart_read_byte` reads `'ITM2'` `ITEM.CAT` directly byte-by-byte
  from MD128 ROM (`$3A`), eliminating VDC `item.cat` staging and freeing Bank 0
  resident bytes while keeping disk saves (`MORIA01`) on IEC drives `8–11`.

## C128 MMU Rules

- Runtime normally executes in Bank 0 all-RAM mode with I/O visible.
- Map access goes through MMU-safe helpers; VDC render paths must not raw-read
  Bank 1 map pointers.
- KERNAL calls use explicit KERNAL entry/exit paths.
- `$1000-$3FFF` is not common RAM in the shipping runtime.
- `$D000-$DFFF` is not safe executable RAM with I/O visible; Bank 1 `$D000-$DFFF`
  reads/writes execute from bottom common (`< $4000`) under `SEI + $7F NOIO`.
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

The Commander X16 port is 80-column (65C02 @ 8 MHz, VERA text in VRAM `$1B000`),
uses unbanked low RAM (`$0801-$9EFF`) for a unified resident + gameplay image
plus the tier-name pool, and switches the `$A000-$BFFF` 8 KB banked RAM window
via ZP `$00`. Full rules live in `docs/CX16_MEMORY_CONTRACT.md`.

- `$0400-$07FF` holds `FLOOR_ITEM_BASE` (`$0400`), `CREATURE_BASE` (`$0500`),
  `PLATFORM_HD_DECODE_BUF_BASE` / `DUNGEON_GEN_DOOR_SCAN_BASE` (`$0600`), and
  `CX16_ROW_STAGE_BASE` (`$0700`).
- `MORIA8.PRG`: `$0801-$9386` (`35,718` B unified resident + play image,
  asserted `<= $9B00`).
- `PLATFORM_TIER_NAME_POOL_BASE`: `$9B00-$9EFF` (`1,024` B).
- `$9F00-$9FFF`: VERA / VIA1 / VIA2 hardware I/O hole (forbidden to code/data).
- `$A000-$BFFF` 8 KB banked RAM window (`23/64` banks allocated, `41` banks =
  `328` KB free):
  - Bank 0: reserved for CX16 KERNAL `KVARSB0`
  - Banks 1–2: live `198x66` dungeon map (`13,068` B)
  - Bank 3: `CX16.AUXDATA` (`$6000-$76C2`, `5,827` B)
  - Bank 4: `CX16.HUFFDATA` (`$8000-$9C23`, `7,204` B; incl. Huffman catalog names)
  - Bank 5: `MONSTER.EXT` (`$A000-$A8B7`, `2,232` B extended monster catalog)
  - Bank 6: `ITEM.CAT` (`$A000-$BD35`, `7,478` B `'ITM2'` item catalog)
  - Banks 7–8: reserved extension banks
  - Banks 9–21: `13` preloaded overlays (`OVL.START`..`OVL.TITLE`, including
    `OVL.CHEST` Bank 18, `OVL.HOME` Bank 19, `OVL.STORAGE` Bank 20, `OVL.TITLE` Bank 21)
  - Bank 22: `TITLE` artwork (`622` B)
  - Bank 23: `MONSTER.CAT` (`$A000-$B757`, `5,976` B monster catalog fields)
  - Bank 24: cold `LEGALUI` (`$A000-$A807`, `2,056` B, cap `$AE00`)
  - Banks 25–63: free / warm pool

Current disk/bundle product payloads (`build/cx16/`):

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `MORIA8.PRG` | `$0801-$9387` | 35,718 bytes |
| `CX16.AUXDATA` / `CX16.HUFFDATA` | Bank 3 `$6000` / Bank 4 `$8000` | 5,827 / 7,204 bytes |
| `MONSTER.CAT` / `MONSTER.EXT` / `ITEM.CAT` | Banks 23 / 5 / 6 (`$A000`) | 5,976 / 2,232 / 7,478 bytes |
| `OVL.*` (13 overlays) | `$A000-$BBC5` (Banks 9–21) | 630–7,109 bytes each |
| `LEGALUI` (cold legal screen) | Bank 24 `$A000-$A808` | 2,056 bytes |

### Commander X16 Cartridge Model (`moria8-cx16.crt`)

- Builds into `build/moria8-cx16.crt` (`128 KB` = `8 × 16 KB` ROM Banks `32–39`
  mapped at `$C000-$FFFF` via ZP `$01`, `122,656` B used / `8,416` B free, `23`
  assets = `122,144` B indexed at `$C100`).
- Zero-bounce direct boot copy (`CART_COPY_STUB_ADDR = $0400`): because `$A000-$BFFF`
  banked RAM and `$C000-$FFFF` banked ROM never overlap, boot copies
  `MORIA8.PRG` (`35,690` B), `CX16.AUXDATA`, `CX16.HUFFDATA`, all `13` overlays,
  `TITLE`, `MONSTER.CAT`, `MONSTER.EXT`, and `ITEM.CAT` straight from ROM into
  RAM/HiRAM Banks `3–23`. `LEGALUI` (`2,047` B), `LICENSE`, and `SOURCE-OFFER`
  stream from ROM on demand; saves use HostFS/SD via KERNAL.

## Atari 8-Bit Runtime Model

The Atari 8-bit port targets the stock 64 KB Atari 800XL / 65XE (40-column
ANTIC Mode 2 display with DLI color zones and a 1 KB RAM font at `$0400-$07FF`)
and automatically detects 128 KB Atari 130XE extended RAM (`$4000-$7FFF` via
`PORTB` `$D301`) to cache overlays, `MONSTER.CAT`, and title artwork across
`256/256` 256-byte pages (`Slots 0..17`). Full rules live in
`docs/ATARI8_MEMORY_CONTRACT.md`.

- `$0200-$031A` reserves Atari OS vectors, Page 2 display/timer shadows, and the
  `SIOV` DCB (`$0300-$030B`); `$0380-$03BF` holds `ATARI_DISPLAY_LIST`;
  `$0400-$07FF` holds `ATARI_CHARSET_BASE`; `$0800-$0BE7` holds `SCREEN_RAM`
  (all below `$4000` so OS ROM/130XE banking never disturbs ANTIC DMA).
- `LowHelpers` (`$0C00-$23BA`, `6,075` B, asserted `<= $4000`) holds `PORTB`
  banking, `EnterSio`/`ExitSio` bounce I/O, NMI/IRQ handlers, and 130XE cache
  routines (`xe_detect`, `xe_cache_stash`, `xe_cache_fetch`).
- Resident `Default` (`MORIA8.RES`, stored PackBits-compressed on `.atr` disk as
  `MORIA8.PKB` `41,065` B): `$0C00-$C0A5` (`46,246` B, asserted `<= $C100`).
- `MAP_BASE`: `$C100-$CFFF` (`80x48` live map, `3,840` B; `$C100-$C36C` also
  stages `TITLE.DAT` at title screen before gameplay).
- `$D000-$D7FF`: immovable GTIA / POKEY / PIA / ANTIC hardware I/O hole.
- `$D800-$DFFF`: high resident tables under OS ROM (`PLATFORM_TIER_NAME_POOL_BASE`,
  `FLOOR_ITEM_BASE`, Huffman decode buf, `zp_save_buf`, `HighResident`
  `$DDCE-$DF3D` = `msg_history` + `item_name_decode_buf` (`368` B), and
  `HighRAM Tail` `$DF3E-$DFC3` (`134` B)).
- `$E000-$EFFF`: overlay execution window (`13` overlays `OVL.STA`..`OVL.TTL` +
  cold `legalui`); on disk, `MONSTER.CAT` (`17,432` B sector-padded `57 B/rec`,
  or `15,903` B unpadded) and `'ITM2'` `ITEM.CAT` (`7,478` B) stream from DOS
  2.5 `.atr` (or 130XE cache for `MONSTER.CAT`).
- `$F000-$FFF9`: `RuntimeBanked` (`ATARI.BNK`, `4,046` B), below RAM CPU vectors
  at `$FFFA-$FFFF`.

Current disk product payloads (`build/atari8/`):

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `boot.prg` | `$0800-$097F` | 384 bytes |
| `MORIA8.RES` (`MORIA8.PKB` PackBits on `.atr`) | `$0C00-$C0A6` | 46,246 (41,065) bytes |
| `ATARI.BNK` | `$F000-$FFCE` | 4,046 bytes |
| `MONSTER.CAT` (57 B/rec) / `ITEM.CAT` | DOS 2.5 (or 130XE cache) | 17,432 (15,903) / 7,478 bytes |
| `OVL.STA..OVL.TTL` (13 overlays) | `$E000-$EFB8` window | 3,317–4,024 bytes each |
| `legalui` (cold legal screen) | `$E000-$E854` | 2,132 bytes |

(Round-2 overlay rebalance moves `door_open_close_cold.s` from
`HomeOverlay`/`HelpOverlay` to `OVL.ITM` [`3,450` B, `646` B free `< $F000` /
`390` B free in 130XE Slot 6], leaving `OVL.HOM` at `3,918` B [`178` B free]
and `OVL.STO` at `3,645` B disk / `3,641` B cart.)

### Atari 8-Bit Cartridge Model (`moria8-atari8.car`)

- Builds into `build/atari8-cart/` (`moria8-atari8.car`): AtariMax `128 KB`
  Type `41` (`16 × 8 KB` ROM banks at `$A000-$BFFF` switched via `$D500-$D50F`,
  `127,798` B used / `3,274` B free, `21` assets = `119,361` B indexed at
  `$A100`).
- Because `$A000-$BFFF` shares addresses with the upper 8 KB of Main RAM
  `MORIA8.RES` (`$0C00-$BDCA`, `45,515` B; `LowHelpers` `5,535` B; `ATARI.BNK`
  `3,820` B), `cartridge_boot.s`/`cartridge_copy.s` enable `$D500,x` only long
  enough to read ROM bytes and immediately write `CART_DISABLE` (`$D510`) to
  unmap the cartridge (`RD5=0`) before touching Main RAM.
- Compiles out 130XE extended-RAM caching; streams all `13` overlays, `TITLE.DAT`,
  uncompressed `57 B/rec` `MONSTER.CAT`, `ITEM.CAT`, `legalui` (`1,983` B),
  `LICENSE`, and `SOURCE-OFFER` on demand from ROM banks while saves (`D:MORIA.SAV`)
  use `SIOV`.

## Acorn BBC Master 128 Runtime Model

The Acorn BBC Master 128 port targets the stock 128 KB BBC Master 128 (65C12 @
2 MHz, MOS 3.20, DFS 2.24), using an 80x24 Mode 0 bitmap in 20 KB Shadow RAM
`LYNNE` (`$3000-$7FFF` via `ACCCON` `$FE34`), `BeebHuffData` + `zp_save_buf` in
4 KB Private RAM `ANDY` (`$8000-$8FFF` via `ROMSEL` `$FE30`), and 64 KB Sideways
RAM (Banks 4–7 at `$8000-$BFFF`, `256/256` 256-byte pages allocated). Full rules
live in `docs/BBCMASTER_MEMORY_CONTRACT.md`.

- `$0400-$07FF`: `FLOOR_ITEM_BASE` (`$0400`), `CREATURE_BASE` (`$0500`),
  `PLATFORM_HD_DECODE_BUF_BASE` (`$0600`), `DUNGEON_GEN_DOOR_SCAN_BASE` (`$0640`),
  MOS blocks (`$0681-$06FF`), and `beeb_ss_buf` (`$0700`).
- `$0800-$0DFF`: preserved Acorn MOS sound/envelope/DFS workspace (`PAGE = $0E00`).
- `LowHelpers` (`$0E00-$23FF`, `5,632` B, asserted `<= $3000`): owns `ACCCON`/`ROMSEL`
  switching, the Mode 0 software blitter, `EnterMos`/`ExitMos`, and `BRKV`.
- Resident `Default` (`moria8.res.prg`): `$0E00-$7FCF` (`29,136` B, asserted `<= $8000`).
- 20 KB Shadow RAM `LYNNE` (`$3000-$7FFF`): C64-ordered font (`$3000-$33FF`),
  `DUNGEON_GEN_SCAN_SCRATCH_BASE` (`$3400-$37FF`), `beeb_char_shadow`
  (`$3800-$3F7F`), `BeebLynneAux` (`$3F80-$43DB`, `recall[279]` `1,116` B), and
  the 80x24 Mode 0 display bitmap (`$4400-$7FFF`).
- 4 KB Private RAM `ANDY` (`$8000-$8FFF`): `BeebHuffData` (`$8000-$8EEF`, `3,824`
  B) + `zp_save_buf` (`$8F00-$8FAD`, `174` B).
- Sideways RAM Banks 4–7 (`$8000-$BFFF`, `0` free pages):
  - Bank 4: `BeebPlaySlot` (`$8000-$A33D`, `9,022` B), `PLATFORM_TIER_NAME_POOL_BASE`
    (`$A400-$A7FF`), and the `$A800-$BFFF` active overlay window (`13` overlays).
  - Bank 5: live `198x66` dungeon map (`$8000-$B30B`) + cached `OVL.MODAL`
    (`$B400-$BFFF`, `2,439` B).
  - Bank 6: `BeebAuxData` (`$8000-$92B6`, virtual `$6000-$72B6`, `4,791` B) +
    `ITEMCAT` cache pages (`$9300-$94FF`, `2` pages) + `beeb.catalog`
    (`$9500-$B916`, `9,239` B) + cached `OVL.UI` (`$BA00-$BFFF`, `1,515` B).
  - Bank 7: cached `OVL.SPELL` (`$8000-$94FF`, `5,202` B), `OVL.ITEMS`
    (`$9500-$ABFF`, `5,744` B), `OVL.GEN` (`$AC00-$BBFF`, `4,055` B), and
    `ITEMCAT` cache (`$BC00-$BFFF`, `4` pages). Cold overlays (`OVL.HOME`,
    `OVL.STORAGE`, etc.), `MONEXT` (`2,232` B streamed 8 B/species via
    `OSGBPB A=3`), `ITEMCAT` (`7,478` B), and cold `legalui` (`2,147` B) stream
    from DFS `.ssd`.

Current product payloads (`build/bbcmaster/`):

| Payload | Linked range | Size |
| --- | ---: | ---: |
| `boot.prg` | `$1900-$1AAE` (relocates to `$0400`) | 431 bytes |
| `moria8.res.prg` | `$0E00-$7FD0` | 29,136 bytes |
| `beeb.play` | Bank 4 `$8000-$A33E` | 9,022 bytes |
| `beeb.auxdata` | Bank 6 `$8000-$92B7` (`$6000-$72B7`) | 4,791 bytes |
| `beeb.huffdata` | `ANDY` `$8000-$8EF0` | 3,824 bytes |
| `beeb.catalog` / `MONEXT` / `ITEMCAT` | Bank 6 `$9500` / DFS | 9,239 / 2,232 / 7,478 bytes |
| `ovl.start..ovl.title` (13 overlays) | Bank 4 `$A800-$BE70` window | 1,515–5,744 bytes each |
| `legalui` (cold legal screen) | Bank 4 `$A800-$B063` | 2,147 bytes |

## Test Harnesses

Runtime tests assemble target-specific binaries and execute under VICE headless
(`x64sc`, `x128`, `xplus4`), MAME headless (`apple2ee`, `a800xl`, `a130xe`,
`bbcm`), and `x16emu -testbench`. The non-Commodore ports each pair a static
memory-contract checker with a headless runtime scenario harness:

- Apple IIe: `platforms/apple2/harness_smoke.py` (27 scenarios under `apple2ee`,
  requires `A2ROMS`) + `make testapple2-memory-contract` (verifies `moria8-apple2.po`)
- Commander X16: `platforms/cx16/harness_smoke.py` (28 scenarios under
  `x16emu -testbench`, requires `X16EMU`/`X16ROM`) +
  `make testcx16-memory-contract` + `make testcx16-cartridge`
- Atari 8-bit: `platforms/atari8/harness_smoke.py` (17 `a800xl` + 5 `a130xe` =
  22 scenarios, requires `ATARI8ROMS`) + `make testatari8-memory-contract` +
  `make testatari8-cartridge`
- Acorn BBC Master 128: `platforms/bbcmaster/harness_smoke.py` (19 `bbcm`
  scenarios, requires `BBCMROMS`) + `make testbbcmaster-memory-contract`
- Playtester & unit suite: `make playtest-check` (`885` Python unit tests in
  `playtest/tests/`), `make playtest-gate` (automated bot across all 7 disk ports
  + 5 cartridges), plus Commodore VICE suites (`make test64`, `make testplus4`,
  `make test128` + `-cartridge` / `-cartridge-persistence` targets).

Useful gates:

```sh
make check-item-docs
make check-hal-boundaries
make check-zp && make check-6502-lint
make report-budgets
make -j7 -O test               # default regression + cart suites (set REQUIRE_ALL_ROMS=1 in release gates)
make test64 test64-cartridge
make testplus4 testplus4-cartridge
make test128-fast test128-fast-smoke test128 test128-cartridge
make testapple2 testapple2-runtime
make testcx16 testcx16-cartridge
make testatari8 testatari8-cartridge
make testbbcmaster
```

Tests that cross `$A000` on C64 need a bootstrap trampoline below the BASIC ROM
window before jumping to `test_start`.
