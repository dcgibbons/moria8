# Commodore Plus/4 `c264 magic cart` Cartridge Build (`PLUS4_CARTRIDGE`)

## Purpose and Scope

`build/moria8-plus4.crt` packages Moria8 for the **Commodore Plus/4** as a read-only **256 KB `c264 magic cart`** cartridge (CRT v2.0 `$0200`, `PLUS4 CARTRIDGE `, Hardware ID `1`, `16 × 16 KB` C1LO ROM banks at `$8000-$BFFF`; raw binary `build/plus4-cart/moria8-plus4.bin` for `xplus4 -cartmagic`, manifest `build/plus4-cart/moria8-plus4.json`, diagnostic driver `build/plus4-cart/catalog-test.prg`).

- **No flash/cartridge saves**: Save files, loads, and high scores remain on IEC 1541 disk images (Devices `8..11`), sharing `SAVE_VERSION = $0A` bidirectionally with `build/moria8-plus4.d64`.
- **Zero disk-build impact**: Building with `-define PLUS4_CARTRIDGE` outputs to isolated `build/plus4-cart/`; `build/plus4/moria4.prg` and `build/moria8-plus4.d64` remain 100% byte-identical.
- **Standalone legal viewing (Rule 7)**: `data/LICENSE` and `data/SOURCE-OFFER` are embedded as NUL-padded ROM assets served through Title `A` (`About`) and Help `L` with zero drives/disks attached.

## Hardware Banking and Memory Rules

### Cartridge Registers and ROM Mapping (`platforms/commodore/plus4/cartridge_contract.s`)

| Address / Span | Name | Behavior |
| --- | --- | --- |
| `$8000-$BFFF` | `CART_ROM_WINDOW_BASE`..`END` | 16 KB active C1LO ROM bank (read-only ROM when `$FDD2` + `$FF3E` active; writes fall through to underlying RAM) |
| `$FDFE` | `CART_REG_BANK` | Selects `16 KB` C1LO bank `0..15` at `$8000-$BFFF` |
| `$FDD0` | `CART_REG_BASIC_KERNAL` | Selects `LO=BASIC + HI=KERNAL` when ROM is enabled (`$FF3E`); restored before returning or entering KERNAL I/O (note: `$FDD1` selects the built-in 3-plus-1 Function ROM, not external `C1LO`) |
| `$FDD2` | `CART_REG_C1LO_KERNAL` | Selects `LO=C1LO (c264 magic cart) + HI=KERNAL` when ROM is enabled (`$FF3E`) |
| `$FF3E` / `$FF3F` | `PLUS4_ROM_ENABLE` / `PLUS4_RAM_ENABLE` | Switches `$8000-$FFFF` between ROM (`$FF3E`) and all-RAM (`$FF3F`) |
| `$8000-$8009` | Bank 0 Autostart Header | `jmp cold` (`$8000`), `jmp cold` (`$8003`), `.byte $01` (`$8006` autostart ID), `"CBM"` (`$8007-$8009`) |
| `$8100-$818F` | `CART_DIRECTORY` | 18 × 8-byte asset descriptors: `bank`, `src_lo`, `src_hi`, `dst_lo`, `dst_hi`, `size_lo`, `size_hi`, `flags` |

### Cold-Boot Initialization & Bounce Copier (`platforms/commodore/plus4/cartridge_boot.s`)

1. **Pre-BASIC KERNAL autostart**: Plus/4 KERNAL reset (`$FFF6 -> $F2A4 -> $CFA6 -> $FC1E`) scans external cartridge headers and enters `$8000` (`cold`) at `$FC4E` whenever `$8006 == $01`, **before** `IOINIT`, `RAMTAS`, `RESTOR`, or `CINT` have run. Leaving those uninitialized causes `KERNAL_GETIN` (`JMP ($0328)`) to jump through `$0000` (`BRK` loop).
2. `cold` (`$800A`) locks Bank 0 (`$FDFE = 0`, `$FDD2`, `$FF3E`), calls `IOINIT` (`$FF84`), `RAMTAS` (`$FF87`), `RESTOR` (`$FF8A`), and `CINT` (`$FF81`) **before** copying `moria4.prg` (initializing KERNAL vectors `$0312-$0331`, keyboard editor tables, TED display, and ZP/memory bounds safely), and immediately parks the TED hardware cursor (`$FF0C`/`$FF0D = $03FF`) off-screen past cell `999` (`plus4_display_resync` in `platforms/commodore/plus4/screen.s` enforces the same on display resyncs).
3. Because `moria4.prg` spans `$1001..$C78C` (overlapping `$8000-$BFFF` C1LO), `boot_copy_prepare` copies the relocatable copier (`158` bytes, using `ldx #len; dex; bne` since `158 > 127`) into cassette scratch `$033C-$03FB` (`CART_BOOT_COPY_BASE < CART_BOOT_COPY_END = $03FC`, below `$0312-$0331` KERNAL vectors).
4. The copier reads `moria4.prg` from Bank 1 `$8000` in `<= 256`-byte chunks into the `$0400-$04FF` bounce buffer (`CART_BOOT_BOUNCE`, unused until dungeon generation), switches to RAM (`$FDFE = 0`, `$FDD0`, `$FF3F`), writes the chunk to `$1001+`, advances banks across `$C000`, restores `$FDD0` + `$FF3E` (KERNAL visible for `entry`'s `KERNAL_SETMSG`), and jumps to `CART_ENTRY` (`$100E`).
5. **Clean restart / `exit_trampoline`** (`platforms/commodore/plus4/main.s`): Placed `< $8000`; clears `CART_REG_BANK = 0`, restores `CART_REG_C1LO_KERNAL` (`$FDD2`) and `PLUS4_EXIT_ROM_ENABLE` (`$FF3E`), and executes `jmp $fff6` so quitting/resetting re-enters the cartridge cleanly rather than dropping to dead BASIC.

### Runtime ROM Reader, Catalog, Legal Streamer & HAL Policies

- **Low-RAM `cart_read` (`platforms/commodore/plus4/cartridge_copy.s`)**: Placed strictly in `$1001..<$8000` (`cart_reader_start >= $1001`, `.assert < $8000`). Saves `P` (`php; sei`), selects Bank 0 + `$FDD2` + `$FF3E` to read the `CART_DIRECTORY` descriptor, switches to the target bank, writes directly to underlying RAM beneath `$8000-$BFFF` and `>= $FC00` (all runtime targets `runtime <= $FC00`, `MAP_BASE = $C800`, overlays `$E000-$EFFF`, `cat_record < $8000`, and `legal_input_cache = $E700` are verified free of `$8000-$BFFF` / `$FC00+` overlaps by `tools/make_plus4_magic.py` and `tools/check_plus4_magic.py`), then restores `CART_REG_BANK = 0`, `CART_REG_BASIC_KERNAL` (`$FDD0`), `PLUS4_RAM_ENABLE` (`$FF3F`), and `plp`. Zero core ZP bytes are borrowed.
- **Monster catalog (`platforms/commodore/plus4/cartridge_catalog.s`)**: `CatalogHidden` (`$DC00-$DC74`) + `catalog_fetch_record` multiplies 16-bit `cat_id` by `CATALOG_RECORD_SIZE` (`49` = `id * 48 + id`) across `279` records (`13,671` bytes), preserving `zp_math_a..zp_math_tmp1`, and invokes `cart_read` (`cart_is_record = 1`) into `cat_record` (`< $8000`).
- **Legal ROM streamer (`platforms/commodore/plus4/legal_stream.s`, `legal.s`)**: Streams NUL-padded `data/LICENSE` and `data/SOURCE-OFFER` in `256`-byte pages (`cart_is_record = 2`) into `legal_input_cache` (`$E700`), rejecting out-of-range page offsets without altering `legal_input_cache`.
- **HAL Policies (`platforms/commodore/plus4/hal/{storage_policy,lifecycle_policy}.s`, `config.s`, `main.s`)**: Sets `HAL_STORAGE_PROGRAM_MEDIA_ALWAYS_AVAILABLE`, `HAL_STORAGE_ASSET_LOAD_INFALLIBLE`, and `HAL_PLATFORM_REU_DISABLED`, disables `HAL_STORAGE_LOAD_PROGRAM_MEDIA_PROBE` and `HAL_STORAGE_LEGAL_COMMAND_STATUS`, makes `plus4_require_program_media` a `clc; rts` no-op, defaults `program_device = 8` / `save_device = 8` cleanly without a program disk, and leaves `tools/check_plus4_hal_independence.py` 100% clean (no `c64_*` symbols).

## 256 KB `c264 magic cart` Asset Map (`build/plus4-cart/moria8-plus4.json`)

- **Format**: `c264 magic cart`, CRT v2.0, Type `1`, `16 × 16,384` B (`262,144` ROM bytes; `119,539` used)
- **Measured speeds (`xplus4`)**:
  - Boot copy (`moria4.prg`, `46,988` B): `2,369,258` TED ticks (PAL)
  - Startup overlay (`ovl.start`, `4,024` B): `104,119` TED ticks (PAL) (~`25.9` TED ticks/byte with active TED display single-clocking)

| ID | Asset | Bank | ROM Src | RAM Dest | Size (B) | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `0` | `resident` | `1` | `$8000` | `$1001` | `46,988` | `moria4.prg` (`$1001-$C78C`) |
| `1` | `runtime` | `3` | `$B78C` | `$F000` | `2,917` | `4.bank` (`$F000-$FB64`, `< $FC00`) |
| `2` | `index` | `4` | `$82F1` | `$D600` | `117` | `monster.idx` (`CATALOG_IDX_LOAD`) |
| `3` | `title` | `4` | `$8366` | `$C800` | `627` | `title` (`MAP_BASE`) |
| `4` | `ovl.start` | `4` | `$85D9` | `$E000` | `4,024` | Startup overlay |
| `5` | `ovl.town` | `4` | `$9591` | `$E000` | `4,073` | Town / Stores overlay |
| `6` | `ovl.death` | `4` | `$A57A` | `$E000` | `2,450` | Death / Tombstone overlay |
| `7` | `ovl.gen` | `4` | `$AF0C` | `$E000` | `3,838` | Dungeon Gen overlay |
| `8` | `ovl.help` | `4` | `$BE0A` | `$E000` | `3,818` | Help overlay |
| `9` | `ovl.ui` | `5` | `$8CF4` | `$E000` | `3,951` | Character / UI overlay |
| `10` | `ovl.items` | `5` | `$9C63` | `$E000` | `3,729` | Items / Inventory overlay |
| `11` | `ovl.spell` | `5` | `$AAF4` | `$E000` | `4,007` | Spells / Disarm overlay |
| `12` | `ovl.modal` | `5` | `$BA9B` | `$E000` | `4,008` | Modal / Inspect overlay |
| `13` | `ovl.chest` | `6` | `$8A43` | `$E000` | `3,050` | Chests / Monster Inspect overlay |
| `14` | `catalog` | `6` | `$962D` | stream | `13,671` | `279 × 49` B packed catalog records |
| `15` | `legalui` | `7` | `$8B94` | `$E000` | `863` | `LegalOverlay` |
| `16` | `license` | `7` | `$8EF3` | stream | `512` | NUL-padded `data/LICENSE` (raw `LF` EOL) |
| `17` | `source-offer` | `7` | `$90F3` | stream | `512` | NUL-padded `data/SOURCE-OFFER` (raw `LF` EOL) |

## Build and Verification Targets

- **Build**: `make cartridgeplus4` (wired into `buildplus4` and `disk`), producing `build/moria8-plus4.crt`, `build/plus4-cart/moria8-plus4.bin`, `build/plus4-cart/moria8-plus4.json`, and `build/plus4-cart/catalog-test.prg`.
- **Interactive VICE Launch**: `make runplus4-cart` (launches `xplus4 -cartcrt build/moria8-plus4.crt`).
- **Static Checks**:
  - `python3 platforms/commodore/plus4/test_cartridge.py --selftest`
  - `python3 tools/check_plus4_magic.py --selftest`
  - `python3 tools/check_plus4_magic.py build/moria8-plus4.crt build/plus4-cart`
  - `cartconv -c build/moria8-plus4.crt`
  - `python3 tools/check_plus4_hal_independence.py`
  - `make check-hal-boundaries`, `make check-6502-lint`
- **Runtime VICE Suite (`make testplus4-cartridge`, wired into `test-stage-plus4`)**:
  - `testplus4-cartridge-assets` (PAL + NTSC): 18 checks per video standard covering boot copier preservation of `$0312-$0331` KERNAL vectors, resident copy across `$8000-$BFFF` and banks, title boot with zero disks (`4.bank` at `$F000`, device `8` defaults), all 10 overlays in both IRQ states, boundary/279-record catalog parity (`catalog-test.prg`), title art reload at `$C800`, legal boundary rejection, page-2 scratch preservation, Title `A` + Help `L` legal viewer, New Game -> town -> dungeon DL1 -> Quit -> `exit_trampoline` reset, zero-length descriptor guard, and raw `-cartmagic` boot.
  - `testplus4-cartridge-persistence` (PAL + NTSC): 11 checks per video standard covering cancelled/single-drive Disk Setup, repeated media checks with IRQ preservation, incomplete-setup & changed-media marker rejection/recovery, bidirectional save/load interchange with `build/moria8-plus4.d64`, cancelled overwrite preservation, and Drive 9 IEC save/reload.

## Behavioral Change Protocol Record

- **Problem / Success**: Deliver a `256 KB` `c264 magic cart` `.crt` (and `-cartmagic` `.bin`) cold-booting on Plus/4 PAL/NTSC with zero attached disks, full overlay/catalog/legal support, clean Quit/`exit_trampoline` reset, bidirectional `.d64` saves on IEC Drives `8..11`, and 100% byte-identical disk builds.
- **Authority & Decisions**: Stage 1 Plus/4 cartridge implementation reusing `core/` gameplay, `49`-byte monster catalogs, and `SAVE_VERSION = $0A`; hardware banking empirically verified against `xplus4` (`$FDD2` = C1LO+KERNAL vs `$FDD1` = 3-plus-1 Function ROM; `$FC4E` autostart before `IOINIT`/`RAMTAS`/`RESTOR`/`CINT`).
- **Ownership & Ranges**: All Plus/4 cartridge assembly and harnesses live under `platforms/commodore/plus4/` (`cartridge_{contract,boot,copy,catalog,test_catalog}.s`, `legal_stream.s`, `test_cartridge{,_persistence}.py`), `tools/{make,check}_plus4_magic.py`, and `#if PLUS4_CARTRIDGE` HAL policy/boot branches in `platforms/commodore/plus4/{main,config,legal,monster_catalog4}.s` and `hal/{storage,lifecycle}_policy.s`. Disk builds (`build/plus4/moria4.prg`, `build/moria8-plus4.d64`) remain untouched.
- **RNG & Gameplay Arithmetic**: N/A — `cartridge_catalog.s` computes deterministic `id * 49` offsets (`id * 48 + id`) matching `catalog_disk.records()` across all `279` entries; no RNG draws, turn consumption, visibility, or monster AI logic changed.
- **Contract Rows**:
  - `TURN_RENDER`: Re-entry via Help -> `L` (`LegalOverlay`) -> `Q` and normal stairs (`>` -> DL1 -> `main_loop`) verified with intact player/inventory/map state (`snapshot(exp)`).
  - `DUNGEON_GENERATION`: Shared dungeon generation invoked via `ovl.gen` on DL1 descent; topology, RNG, and stages unchanged.
  - `MONSTER_STATE`: `catalog_fetch_record` preserves `zp_math_a..zp_math_tmp1` and matches all `279` records; AI/visibility/attacks unchanged.
- **Verification**: Static checks (`check_plus4_magic.py --selftest`, `check_plus4_magic.py`, `cartconv -c`, `check_plus4_hal_independence.py`, `check-hal-boundaries`, `check-6502-lint`), `make testplus4-cartridge` (PAL + NTSC), `make testplus4`, and disk-build SHA256 invariance all pass.
