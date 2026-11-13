# Commodore 128 `Magic Desk 128` Cartridge Build (`C128_CARTRIDGE`)

## Purpose and Scope

`build/moria8-c128.crt` packages Moria8 for the **Commodore 128** as a read-only **256 KB `Magic Desk 128`** External Function ROM cartridge (CRT v2.0 `$0200`, `C128 CARTRIDGE  `, Hardware ID `4`, `16 × 16 KB` banks at `$8000-$BFFF`; raw binary `build/c128-cart/moria8-c128.bin` for `x128 -cartmd128`, manifest `build/c128-cart/moria8-c128.json`).

- **No flash/cartridge saves**: Save files (`"THE.GAME"`..`"THE.GAME4"`) and `HALL.OF.FAME` remain on IEC 1541/1571/1581 disk images (Devices `8..11`), sharing `hal_storage_save_version = $1B` bidirectionally with `build/moria8-c128.d71`.
- **Isolated cartridge build**: Building with `-define C128_CARTRIDGE` outputs solely to `build/c128-cart/`, `build/moria8-c128.crt`; all cartridge code and assertions are gated behind `#if C128_CARTRIDGE` so the non-cartridge disk build in `build/c128/` carries zero cartridge overhead. (In this change set, `platforms/shared/save.s` also fixes a pre-existing `save_write_map_banked` label placement bug under `HAL_STORAGE_STREAM_CHUNKED && HAL_STORAGE_MAP_BANKED` so both disk and cartridge C128 saves persist the 13,068-byte Bank 1 map.)
- **Standalone legal viewing (Rule 7)**: `data/LICENSE` and `data/SOURCE-OFFER` are embedded as NUL-padded ROM assets served through Title `A` (`About`) and Help `L` with zero drives/disks attached.

## Hardware Banking and Memory Rules

### Cartridge Registers and MMU Rules (`platforms/commodore/c128/cartridge_contract.s`)

| Address / Span | Name | Behavior |
| --- | --- | --- |
| `$8000-$BFFF` | `CART_ROM_WINDOW_BASE`..`END` | 16 KB active External Function ROM bank (`0..15`) when `MMU_CR` (`$FF00`) sets bits `3:2 = %10` |
| `$DE00` | `CART_REG_BANK` | Selects `16 KB` External Function ROM bank `0..15` (`bit 7 = 0`) while I/O is visible |
| `$FF00 = $3A` | `MMU_EXT_ROM_IO` | Bank 0 RAM (`$0000-$7FFF`, `$C000-$CFFF`, `$E000-$FFFF`), External Function ROM (`$8000-$BFFF`), I/O visible (`$D000-$DFFF`) |
| `$D506 = $05` | Bottom-common config | 4 KB bottom common (`$0000-$0FFF`), top common OFF (`$F000-$FFFF` tracks `MMU_CR` RAM bank) |
| `$D506 = $0D` | Runtime common config | 4 KB bottom common (`$0000-$0FFF`) + 4 KB top common (`$F000-$FFFF`, Bank 0 runtime + vectors) |
| `$8000-$8009` | Bank 0 Autostart Header | `jmp cold_start` (`$8000`), `jmp cold_start` (`$8003`), `.byte $01` (`$8006` autostart ID), `"CBM"` (`$8007-$8009`) |
| `$8100-$81FF` | `CART_DIRECTORY` | 31 × 8-byte asset descriptors: `bank`, `src_lo`, `src_hi`, `dst_lo`, `dst_hi`, `size_lo`, `size_hi`, `flags` |

### Cold-Boot Initialization & Bottom-Common Bounce Thunk

1. **Cold Boot (`platforms/commodore/c128/cartridge_boot.s`)**: Built standalone into `rom0.bin` (`$8000-$80BB`). `cold_start` copies `boot_copier` (`> 127` bytes, using `ldx #0; inx; cpx #len; bne`) into `$1800` (Bank 0 RAM below `$1C01`), switches `$FF00 = $00` (Bank 15) to run C128 `IOINIT` (`$FF84`), `RAMTAS` (`$FF87`), `RESTOR` (`$FF8A`), and `CINT` (`$FF81`) so `$0314-$0333` KERNAL IEC/IRQ vectors and editor tables are valid before Drive 8/9 I/O, then sets `sei`, `$D506 = $05`, and `$FF00 = $3A` (`MMU_EXT_ROM_IO`), streams `moria128.prg` (`CART_ASSET_RESIDENT`) across ROM bank boundaries into Bank 0 `$1C01+`, restores `$FF00 = $0E` (`MMU_NORMAL`) and `$01 = $36`, and jumps to `CART_ENTRY` (`$1C0E`).
2. **Bottom-Common Bounce Rule (`platforms/commodore/c128/memory128.s`)**: Because `$1000-$5FFF` is bank-private in the C128 runtime, switching `$FF00` to Bank 1 (`$7E`) or disabling top common (`$D506 = $05`) must never execute from `$1000+` or `$8000+`. Under `#if C128_CARTRIDGE`, `mmu_common_cart_copy_chunk` lives in bottom common at `$0FB0-$0FF3` (`MMU_COMMON_CART_BASE`) and uses a 32-byte bounce buffer + metadata (`mmu_common_cart_{bank,dst_mmu,dst_d506,len,buf}`) appended to `mmu_common_helpers_blob` (`$0D2E-$0D51`), keeping `RuntimeCommonData` (`128.fdisk.prg`) at `$0D60-$0FA6` (`< $0FB0`).
3. **NMI Safety for `128.huff` & `128.hvec`**: Under `sei`, `CART_DEST_BANK1_TOP_OFF` (`$02`) temporarily sets `$D506 = $05` and `$FF00 = $7E` inside `mmu_common_cart_copy_chunk` after loading `128.hvec.prg` (`$FFFA-$FFFB` -> `mmu_common_nmi`) before `128.huff.prg` (`$F000-$FEC2`), then restores `$D506 = $0D` and caller `$FF00` & `P`.
4. **Runtime Reader & HAL Policies (`cartridge_copy.s`, `legal_stream.s`, `legal.s`, `hal/storage_policy.s`, `main.s`)**:
   - `cart_read` / `cart_load_asset` / `cart_load_prg` reside in Bank 0 `Default` (`< $6000`), clamp ROM reads to page boundaries (so `zp_ptr0` never wraps mid-chunk), handle 16 KB ROM bank crossings (`$C000 -> $8000`), and service all 14 `c128_load_*_prg` loaders, `128.cat.prg`/`128.cnm.prg`, Bank 1 preload/title cache, `LEGALUI`, all 10 `ovl.*` overlays (including cold `ovl.chest`), and `legal_stream_{open,read,pause,close}` (`LICENSE`/`SOURCE-OFFER`).
   - `c128_require_program_media` clears Carry directly without prompting; `disk_program_media_present` returns `sec; rts` (preserving `C128M-008` `.assert` in `128.world`); `exit_trampoline` resets `CART_REG_BANK = 0` and `$D506 = $00` (disabling common RAM), then sets `$FF00 = $00` (full ROM) and `$01 = BANK_ALL_ROM` before `jmp ($fffc)`.

## 256 KB `Magic Desk 128` Asset Map (`build/c128-cart/moria8-c128.json`)

- **Format**: `Magic Desk 128`, CRT v2.0 (`$0200`), Type `4`, `16 × 16,384` B (`262,144` ROM bytes; `121,255` used across Bank `0` + `31` assets in Banks `1..7`; Banks `8..15` padded with `$FF`).
- **Bank 0**: `$8000-$80BB` (`rom0.bin`), `$8100-$81F7` (`31 × 8` B `CART_DIRECTORY`).
- **Bank 1–7 payloads**: `moria128.prg` (`0`), `128.{runtime,input,proj,fdisk,diskio,bank,world,item,names,hvec,huff,cat,cnm,select,persist,play}.prg` (`1..16`), `ovl.{start,town,death,gen,help,ui,items,disarm,modal,chest}` (`17..26`), `title` (`27`), `legalui` (`28`), NUL-padded `LICENSE` (`29`), NUL-padded `SOURCE-OFFER` (`30`).

## Build and Verification Targets

- **Build**: `make cartridge128` (wired into `build128` and `disk`), producing `build/moria8-c128.crt`, `build/c128-cart/moria8-c128.bin`, and `build/c128-cart/moria8-c128.json`.
- **Interactive VICE Launch**: `make run128-cart` (launches `x128 -80col -cartcrt build/moria8-c128.crt`).
- **Static Checks**:
  - `python3 -B tools/check_c128_md128.py --selftest`
  - `python3 -B tools/check_c128_md128.py build/moria8-c128.crt build/c128-cart`
  - `python3 -B tools/check_c128_payloads.py build/c128-cart`
  - `cartconv -c build/moria8-c128.crt`
  - `python3 -B platforms/commodore/c128/test_cartridge.py --selftest`
  - `make check-hal-boundaries`, `make check-6502-lint`
- **Runtime VICE Suite (`make test128-cartridge`, wired into `test-stage-c128`)**:
  - PAL and NTSC (`--ntsc`) runs of `platforms/commodore/c128/test_cartridge.py`, bounded to `30s` per launched `x128` instance:
    - Zero-disk `-cartcrt` cold boot, 80-column VDC centered title menu, `program_device=8`/`save_device=8`, Bank 0 & Bank 1 PRG/catalog/Huffman/vector parity, Title `A` `LEGALUI` (`LICENSE` + `SOURCE-OFFER`), all 10 overlays via `overlay_load` (including cold `ovl.chest`).
    - Raw `-cartmd128` `.bin` boot, New Game (`ovl.start`) -> Town (`ovl.town`) -> in-game Help/Legal modal (`?`/`L`) state preservation -> dungeon descent (`ovl.gen`, monster spawn from 279-creature Bank 1 catalog) -> cold `ovl.chest` -> `exit_trampoline` reset.
    - Drive 8 `.d71` Disk Setup, `128.play <-> 128.persist` swap, save/load snapshot parity, overwrite save without swap prompt, and bidirectional `.d71` save load on `build/moria8-c128.d71` disk edition.
