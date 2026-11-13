# Atari 8-bit 128 KB AtariMax MaxFlash Cartridge Build (`ATARI8_CARTRIDGE`)

## Purpose and Scope

`build/moria8-atari8.car` packages Moria8 for the **Atari 800XL / 65XE / 130XE** as a read-only **128 KB AtariMax MaxFlash cartridge** (`.car` Type `41`, 16 × 8 KB banks, raw ROM `build/atari8-cart/moria8-atari8.bin`, manifest `build/atari8-cart/moria8-atari8.json`).

- **No flash saves**: Save files, loads, and high scores remain on DOS 2.5 floppy images (`D1:`–`D4:`, HAL devices `8..11`), sharing `SAVE_VERSION = $18` bidirectionally with `build/moria8-atari8.atr`.
- **Zero disk-build impact**: Assembling without `-define ATARI8_CARTRIDGE` produces the byte-identical `build/moria8-atari8.atr` release image.
- **No external release promotion**: `make disk` / `RELEASE_ARTIFACTS` remain untouched until explicitly requested; `make build` / `make cartridgeatari8` builds the `.car`, raw `.bin`, and `.json` manifest.
- **Standalone legal viewing (Rule 7)**: `data/LICENSE` and `data/SOURCE-OFFER` are embedded in cartridge ROM and served through Title `A` (`About`) and Help `L` with zero floppies attached.

## Hardware Banking and Memory Rules

### Cartridge Registers and Vectors (`platforms/atari8/cartridge_contract.s`)

| Address / Span | Name | Behavior |
| --- | --- | --- |
| `$A000-$BFFF` | `CART_WINDOW` | 8 KB active ROM bank (`RD5 = 1` when enabled; **no RAM write-through** while enabled) |
| `$D500 + bank` (`0..15`) | `CART_BANK_SELECT` | Any write (`STA $D500,X`) enables the cartridge and maps bank `X` at `$A000-$BFFF` |
| `$D510` | `CART_DISABLE` | Any write (`STA $D510`) disables cartridge ROM (`RD5 = 0`) so `$A000-$BFFF` accesses Main RAM |
| `$D013` / `$03FA` | `CART_TRIG3` / `CART_OS_GINTLK` | Atari OS VBI compares `TRIG3` (`RD5` hardware sense) against `GINTLK`; any code toggling the cartridge must sync `GINTLK = TRIG3` while `RD5 = 0` before restoring NMIs (`NMIEN`) or returning to OS code |
| `$BFFA-$BFFF` | Atari Cart Trailer | In Bank 0: `cart_start` (`$A000+$01`), `$00` (present), `$04` (run cart, no disk boot), `cart_init` (`$A000` `RTS`) |

### Cold-Boot Bank-0 Copier (`platforms/atari8/cartridge_boot.s`)

Because Atari XL/XE hardware suppresses writes to Main RAM beneath `$A000-$BFFF` whenever a cartridge asserts `RD5 = 1`:

1. OS cold-boot enters `cart_start` in Bank 0 with `PORTB = PORTB_GAME_RAM` (`$FE`, OS ROM disabled, BASIC off).
2. `cart_start` copies the relocatable `boot_copier` loop (`<= 256` bytes) into `SCREEN_RAM` (`$0800`) and jumps there.
3. `boot_copier` reads asset `0` (`MORIA8.RES`, `$0C00–$BE02`, spanning beneath `$A000-$BFFF`) from ROM in `<= 256`-byte chunks into `BOOT_BOUNCE` (`$0900-$09FF`), writes `CART_DISABLE` (`$D510`), copies `BOOT_BOUNCE` into RAM destination `$0C00..$BE02`, and advances source banks (`CART_BANK_SELECT,X`) automatically across `$C000` boundaries.
4. Once `MORIA8.RES` is copied, `boot_copier` disables the cartridge (`STA $D510`), updates `OS_GINTLK = TRIG3`, and jumps to `CART_ENTRY` (`$0C00`).

### Runtime ROM Reader (`platforms/atari8/cartridge_copy.s`)

`cart_read` (placed strictly `< $4000` inside `MORIA8.RES`) serves all post-boot assets, monster catalog records (`49` B × `279`), and 256-byte legal text slices:

- Saves caller IRQ mask (`I`), sets `SEI`, writes `NMIEN = $00`, maps `PORTB = $FE`.
- Maps Bank 0 (`$D500`) to read the 8-byte descriptor from `CART_DIRECTORY` (`$A100`), normalizes source bank and `$A000-$BFFF` page offset, and rejects any post-boot RAM destination overlapping `$A000-$BFFF`.
- Copies bytes directly from `$A000-$BFFF` to Main RAM `< $A000` or `>= $C000` (`MAP_BASE`, `$E000-$EFFF` overlays/legal, `$F000-$FFF9` `RuntimeBanked`), then writes `CART_DISABLE` (`$D510`), syncs `OS_GINTLK = TRIG3`, restores `NMIEN` and `IRQ` state, and preserves core ZP `$02-$8F`.
- **130XE MMU Compatibility**: Because the `128 KB` MaxFlash ROM sits directly on the CPU bus, `#if !ATARI8_CARTRIDGE` compiles out `xe_detect`, `init_xe_preload`, and the 130XE `$4000-$7FFF` RAM cache (`platforms/atari8/main.s`, `platforms/atari8/storage.s`). Both `800XL`/`65XE` and `130XE` run identically in Main RAM (`PORTB = $FE`, bit 4 = 1 keeping 130XE CPU banking on Main RAM) with `$D013/$03FA` clean after return.

### Cartridge Catalog & Legal Streamers

- `platforms/atari8/cartridge_catalog.s` (`get_monster_catalog_record`): computes `id * 49` using an unsigned 16-bit shift/add sequence (`id * 48 + id`, exact across `0..278`, `13,671` bytes), invokes `cart_read` (`cart_is_record = 1`) into `MON_REC_BUFFER`, with zero SIO reads and zero memory allocations.
- `platforms/atari8/legal_stream.s` + `platforms/atari8/legal.s`: embeds `data/LICENSE` and `data/SOURCE-OFFER` as NUL-terminated ROM assets read in 256-byte pages (`cart_is_record = 2`) into `legal_input_cache` (`$E700`), without mounting or touching a floppy drive.

### Storage Policy (`D1:`–`D4:` Saves Only)

- `disk_require_program_media` (`platforms/atari8/save_stream.s`) returns immediately (`C=0`) on `ATARI8_CARTRIDGE` with zero swap prompts and without clobbering `save_device`.
- `save_device` defaults to `1` (`D1:`) on cartridge builds (vs. `2` / `D2:` on disk builds), matching single-drive save diskettes on real hardware and allowing `1..4` via Disk Setup (`C` on title or `O` in options).
- `TITLE.DAT` (read-only program disk marker) is rejected as save media by `disk_prepare_selected_save_media`; uninitialized blank formatted `.atr` / DOS 2.5 save disks receive `MORIA8.ID` on selection.

## 128 KB MaxFlash ROM Layout (`build/atari8-cart/moria8-atari8.json`)

- **Format**: `AtariMax-128KB` (`.car` Type `41`), `16 × 8 KB` banks (`131,072` bytes)
- **ROM used**: `110,592` / `131,072` bytes (`20,480` bytes free across Banks `13..15`)
- **ROM checksum**: `$00f50348`

| ID | Asset | Bank | ROM Src | RAM Dest | Size (B) | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `0` | `resident` | `1` | `$A000` | `$0C00` | `45,571` | `MORIA8.RES` (`Default` + `< $4000` helpers; spans `$0C00-$BE02`) |
| `1` | `runtime` | `6` | `$B203` | `$F000` | `3,849` | `ATARI.BNK` (`RuntimeBanked`) |
| `2` | `title` | `7` | `$A10C` | `$C100` | `621` | `TITLE.DAT` (`MAP_BASE`) |
| `3` | `OVL.STA` | `7` | `$A379` | `$E000` | `4,024` | Startup overlay |
| `4` | `OVL.TWN` | `7` | `$B331` | `$E000` | `4,073` | Town / Stores overlay |
| `5` | `OVL.DTH` | `8` | `$A31A` | `$E000` | `3,022` | Death / Tombstone overlay |
| `6` | `OVL.GEN` | `8` | `$AEE8` | `$E000` | `3,838` | Dungeon Gen overlay |
| `7` | `OVL.HLP` | `8` | `$BDE6` | `$E000` | `3,679` | Help overlay |
| `8` | `OVL.UI` | `9` | `$AC45` | `$E000` | `4,024` | Character / UI overlay |
| `9` | `OVL.ITM` | `9` | `$BBFD` | `$E000` | `3,729` | Items / Inventory overlay |
| `10` | `OVL.SPL` | `10` | `$AA8E` | `$E000` | `3,897` | Spells / Disarm overlay |
| `11` | `OVL.MDL` | `10` | `$B9C7` | `$E000` | `3,454` | Modal / Inspect overlay |
| `12` | `OVL.CHS` | `11` | `$A745` | `$E000` | `3,015` | Chests / Monster Inspect overlay |
| `13` | `catalog` | `11` | `$B30C` | stream | `13,671` | `279 × 49` B packed catalog records |
| `14` | `legalui` | `13` | `$A873` | `$E000` | `863` | `LegalOverlay` |
| `15` | `license` | `13` | `$AC00` | stream | `512` | NUL-padded `data/LICENSE` |
| `16` | `source-offer` | `13` | `$AE00` | stream | `512` | NUL-padded `data/SOURCE-OFFER` |

## Build and Verification Targets

- **Build**: `make cartridgeatari8` (outputs `build/moria8-atari8.car`, `build/atari8-cart/moria8-atari8.bin`, `build/atari8-cart/moria8-atari8.json`, and `build/atari8-cart/catalog-test.prg`).
- **Interactive MAME Launch**: `make runatari8-cart` (`a800xl`) and `make runatari8-cart-130xe` (`a130xe`), requiring `ATARI8ROMS`.
- **Static Checks**:
  - `python3 tools/check_atari8_car.py --selftest`
  - `python3 tools/check_atari8_car.py build/moria8-atari8.car build/atari8-cart`
  - `make -C platforms/atari8 test-memory-contract` (checks both `build/atari8/` disk and `build/atari8-cart/` cartridge layouts when built)
  - `python3 platforms/atari8/test_cartridge.py --selftest`
- **Runtime MAME Suite (`make testatari8-cartridge`)**:
  1. `cold_boot_gameplay_legal_a800xl`: boots `.car` with no floppies on `a800xl`, verifies `$D013`/`$03FA == 0`, checks Help -> `L` (`LICENSE`) and `S` (`SOURCE-OFFER`), title `A` (`About`), descends to DL1 and plays a turn.
  2. `cold_boot_and_catalog_279_a130xe`: boots `.car` on 130XE (`a130xe`), runs `$C400` catalog test across all `279` monsters against `catalog_disk.records()` and confirms zero `0xD000`/`0xD5xx` leaks and clean `TRIG3`/`OS_GINTLK`.
  3. `disk_setup_guards_a800xl`: verifies default save device `D1:`, rejection of `TITLE.DAT` diskettes as save targets, initialization of blank DOS 2.5 `.atr` with `MORIA8.ID`, and `O` options persistence.
  4. `save_persistence_and_disk_interchange`: saves on disk build (`D2:`), loads and re-saves on cartridge (`D1:`) with zero program-disk swap prompts, and reloads on disk build (`D2:`), asserting matching player coordinates, level, HP, and `SIO` save sector payloads (`>= 50` sectors).
- **MAME `:sio:fdc` Writeback Harness Note**: MAME `0.289`'s HLE `:sio:fdc` caches modified `.atr` sectors in RAM and does not flush them to the host `.atr` file on `im:unload()` or exit. `platforms/atari8/test_cartridge.py` therefore captures completed `SIO` sector writes (`DCB_DSTATS == $01`, `DDEVIC == $31`, `DCOMND in {'P','W'}`) in Lua and writes them back to the temporary per-run `save.atr` before `manager.machine:exit()` so separate MAME processes see genuine persisted sectors without modifying Atari product code or MAME itself.

## Behavioral Change Protocol Record

- **Success**: 128 KB MaxFlash `.car` Type `41` cold-boots and plays identically to disk builds on `64 KB` XL/XE and `128 KB` `130XE`, keeps DOS 2.5 `D1:`–`D4:` saves compatible with `build/moria8-atari8.atr`, serves embedded legal texts with no floppy mounted, and leaves disk payloads byte-identical.
- **Authority & Deviation**: Maintainer selected the AtariMax 128 KB cartridge port (`"let's do the atari8 version first. proceed."`, no flash saves); reuses shared `core/` gameplay, catalogs (`49` B), and `SAVE_VERSION = $18`.
- **Ownership & Ranges**: All cartridge `.car`-specific assembly lives in `platforms/atari8/` and `tools/{make_atari8_car.py,check_atari8_car.py}` (`$0800-$09FF` boot copier/bounce; `< $4000` `cart_read` + `cartridge_catalog`; `$A100` Bank 0 directory; `$E000-$EFFF` `LegalOverlay` + `$E700` `legal_input_cache`; `ATARI8_CARTRIDGE`-guarded HAL policies). Disk builds keep their exact resident/banked layout.
- **RNG & Gameplay Arithmetic**: N/A — `cartridge_catalog.s` computes deterministic `id * 49` ROM offsets matching `catalog_disk.records()` byte-for-byte; no RNG draws, turn consumption, visibility, or monster AI logic changed.
- **Applicable Verification**: All 4 cross-domain contract suites (`make testatari8-cartridge`, `make testatari8`, `make testatari8-memory-contract`, `make check-hal-boundaries`, `make check-item-docs`, `make playtest-check`, and full 7-platform `make -j7 -O test`).

## Physical Hardware Shipping Notes

- **Supported Hardware**: Runs directly as a Type `41` `.car` or `128 KB` `.bin` on SD/multicart adapters (AtariMax MaxFlash USB/SD programmer, Ultimate Cart, Fujinet / SIDE / AVGCart / Subcart supporting AtariMax `128 KB` / `.car` Type `41`).
- **Discrete 3-Chip Cartridge Board**: `SST39SF010A` (128 KB Flash) + `74HCT174` (hex D flip-flop latching `A13–A16` and `RD5` enable from `$D500-$D51F` decode `CCTL`) + `74HCT00` (reset `D500` bank `0` / `RD5=1`, `A4` enable/disable `D510`).
- **Important Hardware Details**:
  - `cart_boot.s` guarantees `boot_bank` and Bank 0 mapping are explicitly re-latched via `STA CART_BANK_SELECT` and expects hardware power-on / reset to present Bank 0 with `RD5 = 1`.
  - Real SIO drives (1050 / XF551 / Happy / SDrive / FujiNet) handle floppy persistence natively without the MAME test harness's RAM-FDC writeback workaround.
