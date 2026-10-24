# Commodore VIC-20 (`Mega-Cart`) Memory Contract

Placement, `Mega-Cart` ROM/SRAM/NVRAM banking, VIC-I (`6560`/`6561`) internal
video RAM ownership, and KERNAL/IEC/VIA hardware-safety source of truth for the
Commodore VIC-20 port (`platforms/commodore/vic20/`). Enforced at assembly time
by Kick Assembler `.assert` guards in `platforms/commodore/vic20/memory.s` and
`platforms/commodore/vic20/main.s`, and at build time by
`platforms/commodore/vic20/check_memory_contract.py`.

---

## 1. Machine Baseline & `Mega-Cart` (`cartconv -p -t mega`) Banking Model

The VIC-20 port targets a stock **Commodore VIC-20** (`MOS 6502` @ `1.0227 MHz`
NTSC / `1.1084 MHz` PAL, `6560`/`6561` VIC-I video/audio chip, Dual `6522`
VIAs at `$9110-$912F`, and standard Commodore KERNAL/IEC serial bus) equipped
with a **`Mega-Cart` (`cartconv -p -t mega`, `xvic -cartcrt` / `-cartmega`)**
cartridge:

1. **Contiguous `27 KB` Cartridge SRAM + `5 KB` Internal RAM (`32 KB` Total RAM):**
   * Writing `$01` to the `Mega-Cart` RAM Enable register (`$9D80` in `IO3`)
     maps **`27 KB` of linear unbanked Cartridge SRAM** across:
     * **`RAM123` (`$0400-$0FFF`, `3,072` B):** Permanently mapped low RAM
       holding `FLOOR_ITEM_BASE` (`$0400-$04FF`, `256` B for `MAX_FLOOR_ITEMS = 42`),
       `monster_table` (`$0500-$067F`, `384` B for `32 × 12` B active monsters),
       `player_data`/`inv_*`/`equip_*`/`trap_*`/`door_*` (`$0680-$07DF`, `352` B),
       `ovl_vars` (`$07E0-$08DF`, `256` B shared overlay mutable union),
       `msg_history` (`$08E0-$0A1F`, `320` B), `vic_char_shadow` (`$0A20-$0DDF`,
       `40×24 = 960` B), `vic_cell_color_shadow` (`$0DE0-$0ECF`, `20×12 = 240` B),
       and RAM-resident bank/NVRAM switch trampolines + HAL state (`$0ED0-$0FFF`,
       `304` B).
     * **`BLK1 + BLK2 + BLK3` (`$2000-$7FFF`, `24,576` B = `24 KB`):**
       Permanently mapped contiguous RAM holding `MAP_BASE` (`$2000-$2EFF`,
       `80×48 = 3,840` B), `PLATFORM_TIER_NAME_POOL_BASE` (`$2F00-$32FF`, `1 KB`),
       `VicAuxRam` (`$3300-$37FF`, `1,280` B writable store/recall state), and
       the **`18.0 KB` Always-Resident Core & HAL (`VicResident` at
       `$3800-$7FFF`, `18,432` B)**!
   * **Internal VIC-20 Video RAM (`$1000-$1FFF`, `4 KB`) & Color RAM (`$9400-$94EF`):**
     Dedicated exclusively to the VIC-I (`6560`/`6561`) **`160×192` bitmap**
     (`$1000-$10EF` `20×12` Screen Matrix pre-filled with indices `16..255`,
     and `$1100-$1FFF` `3,840` B `8×16` bitmap cells; during dungeon generation,
     `$1100-$14FF` transiently serves as `DUNGEON_GEN_SCAN_SCRATCH_BASE`).
2. **`BLK5` (`$A000-$BFFF`, `8 KB`) Switchable `Mega-Cart` Flash ROM Window:**
   * Controlled by RAM-resident trampolines writing `$80 | bank_id` to `$9D00`
     (`bank_high_reg`) and `bank_id` to `$9C80` (`bank_low_reg`) in `IO3` under
     `SEI`:
     * **Banks `0..11` (`12 × 8 KB`):** 12 Code Overlays (`OVL.START`..`OVL.TITLE`,
       max `~5.3 KB` each), executing **directly in-place from `$A000-$BFFF`
       Cartridge ROM** with zero RAM copy and zero disk seeks.
     * **Banks `12..14` (`3 × 8 KB`):** `VicAuxRom` (`item_defs`, `store_data`,
       `spell_data`), `VicHuffData`, and `MONSTER.DB.1..4`.
     * **Bank `15` (`8 KB` — Default Exploration Bank at `$A000-$BFFF`):**
       **`VicPlaySlot`** (`combat`, `projectile`, `monster_ai`, `monster_attack`,
       `dungeon_los`, `player_move`, `player_run`, `turn` = `~7.8 KB`), mapped
       at `$A000-$BFFF` during active dungeon turns (mirroring `BeebPlaySlot` on
       BBC Master 128!).
     * **Bank `16` (`8 KB`):** **`VicModalUIRom`** (`ui_inventory`,
       `ui_equipment`, `ui_character`, `ui_store`, `score`, `save` = `~6.5 KB`),
       invoked via the `RAM123` far-call trampoline so `VicResident` (`18.0 KB`)
       + `VicPlaySlot` (`8.0 KB`) + `VicModalUIRom` (`8.0 KB`) provide **`34.0 KB`
       of Resident/Play/UI code capacity** without touching overlay banks!
     * **Bank `$7F` (`Bank 127` — Power-On Default at `$A000-$BFFF`):**
       Carries the standard VIC-20 `'A0CBM'` (`$41, $30, $C3, $C2, $CD`)
       autostart header at `$A000-$A009`, the cold-boot loader (which enables
       `RAM123` + `BLK1..3` SRAM via `$9D80 = $01` and copies `18.0 KB`
       `VicResident` into `$3800-$7FFF`), `TITLE`, the dual pre-shifted `1 KB`
       `font_4x8_left`/`font_4x8_right` tables, and the `8×8` Pixel-Art &
       Classic ASCII tilesets. The raw binary is padded with `$FF` through Bank
       `$7F` and converted via `cartconv -p -t mega`.
3. **Dual Save Architecture (`8 KB` `Mega-Cart` NVRAM + Standard `1541` `.d64` IEC Floppy):**
   * **On-Cartridge `8 KB` NVRAM (`$A000-$BFFF` when `[$9E00] = $01`):**
     Holds `HISCORE` (`60` B) + `"M8VICNV1"` 8-byte magic at `$BF80-$BFFF` and
     a full `6,616`-byte instant **Cartridge Save Slot (`Cart Slot 0` at
     `$A000-$B9D7`)** for diskless play (persisted via `-mcnvramfile` /
     `-mcnvramwriteback` in `xvic` or battery/FRAM on physical hardware).
   * **Standard Commodore IEC Serial Bus (`Devices 8–11`, `.d64` Save Disk):**
     Supports all 4 standard disk save slots (`SAVE0..SAVE3`) and `HISCORE` via
     KERNAL `OPEN`/`CHKIN`/`CHKOUT`/`CHRIN`/`CHROUT`/`CLOSE`, reusing
     `platforms/commodore/common/`.

---

## 2. Critical Hardware Invariants

1. **VIC-I (`6560`/`6561`) Internal Memory Bus Restriction, `$9002` Bit 7 = 0, & `8×16` Cell Color Alignment:**
   * The VIC-I video chip's 14-bit internal address bus (`VA0..VA13`) **cannot**
     address Cartridge RAM (`$0400-$0FFF` or `$2000-$7FFF`).
   * The active video display resides strictly in internal RAM at
     **`$1000-$1FFF` (`4,096` B)** with `$9005 = $CC` (Screen Matrix base =
     `$1000`, Character Generator base = `$1000`), **`$9002 = 20` (`$14`, bit
     `7` MUST be `0` so Screen Matrix stays at `$1000` and Color RAM stays at
     `$9400-$94EF`)**, and `$9003 = (12 << 1) | 1 = $19` (`12` double-height
     `8×16` character rows), with NTSC (`6560`: `$9000 = 6, $9001 = 18`) vs. PAL
     (`6561`: `$9000 = 14, $9001 = 32`) centering auto-detected at boot:
     * **`$1000-$10EF` (`240` B):** `20×12` Screen Matrix, initialized at boot
       to character indices **`16..255` (`$10..$FF`)** and never modified
       afterward.
     * **`$10F0-$10FF` (`16` B):** Unused character index `15` (`16` B guard
       gap).
     * **`$1100-$1FFF` (`3,840` B = `240 × 16` B):** The `240` `8×16` bitmap
       cells (`indices 16..255`), forming a contiguous **`160×192` bitmap**
       (`40 columns × 24 rows` of `4×8` condensed characters, or `20 columns ×
       24 rows` of `8×8` world tiles) with **zero overlap** with the Screen
       Matrix at `$1000-$10EF`.
   * **Mandatory Even-Row `8×16` Cell Alignment (`F-03` & `Staff-02`):**
     Because each `8×16` cell `(cell_col = 0..19, cell_row = 0..11)` shares a
     **single 4-bit Color RAM nibble** in `$9400-$94EF` across two vertically
     stacked `8×8` rows (`even_row = cell_row*2`, `odd_row = cell_row*2 + 1`),
     exploration screen regions are aligned strictly to `8×16` cell boundaries:
     * **Cell Row `0` (`Rows 0–1`):** 2-Row Top Message Bar (White `$01`).
     * **Cell Rows `1..9` (`Rows 2–19`):** **`20×18` Dungeon / Town Viewport**
       (never shares a Color RAM cell with the Message Bar or Bottom HUD!).
       Within each `8×16` viewport cell, color is arbitrated by priority:
       `Player (@) > Awake Monster > Asleep Monster > Floor Item / Chest > Door / Stairs / Trap > Lit Wall / Floor > Remembered Dim Wall`.
     * **Cell Rows `10..11` (`Rows 20–23`):** 4-Row 40-Column Bottom HUD (White
       `$01` / Yellow `$07`).
2. **RAM-Resident `BLK5` Bank & NVRAM Switch Trampolines Under `SEI` (`Staff-03`):**
   * Writing to `$9C80`/`$9D00` (ROM bank switch) or `$9E00` (NVRAM map)
     immediately replaces the entire `$A000-$BFFF` window.
   * Therefore, **no routine executing inside `$A000-$BFFF` may ever write to
     `$9C80-$9E00`**. All `BLK5` bank switches and NVRAM read/write operations
     execute strictly from unbanked RAM (`RAM123` `$0ED0-$0FFF` or `VicResident`
     `$3800-$7FFF`) wrapped in `PHP : SEI ... PLP`, restoring `VicPlaySlot`
     (Bank 15, `[$9E00] = $00`) before returning to exploration.
3. **Permanent Mapping of `MAP_BASE` (`$2000-$2EFF`) & `vic_char_shadow` (`$0A20-$0DDF`):**
   * Because `RAM123` (`$0400-$0FFF`) and `BLK1..3` (`$2000-$7FFF`) remain
     permanently mapped at all times (`[$9D80] = $01`):
     * `MAP_BASE` (`$2000-$2EFF`, `80×48 = 3,840` B), `FLOOR_ITEM_BASE`
       (`$0400-$04FF`, `256` B), and `monster_table` (`$0500-$067F`, `384` B)
       are accessed directly with **zero bank switching**.
     * `vic_char_shadow` (`$0A20-$0DDF`, `40×24 = 960` B, guarded by a hard
       defensive `cpy #24; bcs` row clamp) and KERNAL keyboard buffer `KEYD`
       (`$0277-$0280`, `NDX` at `$00C6`) are permanently mapped in unbanked low
       RAM, allowing the headless `xvic -remotemonitor` test harness to inject
       keys and inspect `40×24` C64 screen codes directly.
4. **Zero-Page (`$02-$8F`), KERNAL/IEC Ownership, & `VIA2 PB7` Joystick RIGHT Isolation (`F-04`):**
   * Moria8 owns zero-page **`$02-$8F`** (`zp_save_buf` at `$0340-$03CD` in the
     Cassette Buffer); KERNAL/IEC zero-page **`$90-$FF`** and `$0200-$033F`
     remain strictly reserved.
   * **Joystick RIGHT (`VIA2 PB7` `$9120`) vs. Keyboard Column 7 Isolation:**
     Because Joystick RIGHT shares `VIA2 PB7` (`$9120`) with Keyboard Scan
     Column 7 (driven as an output `$9122 = $FF` by KERNAL `SCNKEY`),
     `input_vic.s` must sample Joystick RIGHT under `SEI` by clearing `VIA2
     DDRB` (`$9122`) bit 7 to input (`0`), reading `$9120` bit 7, and restoring
     `$9122` before `CLI` so pushing Joystick RIGHT never shorts a driven output
     pin to ground.
5. **`Mega-Cart` NVRAM Write-Protection & Cold-Boot `HISCORE` Preservation:**
   * Throughout normal gameplay, `[$9E00] = $00` keeps the `8 KB` NVRAM
     unmapped and write-protected.
   * At cold boot, `boot_init` checks the 8-byte signature `"M8VICNV1"` at
     `$BFF8-$BFFF` in NVRAM; if valid, `$BF80-$BFFF` (`HISCORE`) and
     `$A000-$B9D7` (`Cart Slot 0`) are preserved untouched across power cycles.

---

## 3. Complete `6502` CPU & `Mega-Cart` Memory Map (`$0000-$FFFF`)

| Address Range | Size | Hardware Region | Moria8 Ownership & Notes |
| --- | ---: | --- | --- |
| `$0000-$008F` | 144 B | **Internal Zero Page (Moria8)** | Hot core & HAL zero-page pointers/temps (`$02-$8F`, matching C64/Plus/4) |
| `$0090-$00FF` | 112 B | **Internal Zero Page (KERNAL)** | Strictly reserved for VIC-20 KERNAL, VIA timer IRQ, keyboard, and IEC bus |
| `$0100-$01FF` | 256 B | **Internal 6502 Hardware Stack** | Standard CPU call stack |
| `$0200-$033F` | 320 B | **Internal KERNAL Work Area** | `$0277-$0280` `KEYD` (`NDX` at `$00C6`), hardware vectors (`$0314-$0333`) |
| `$0340-$03FF` | 192 B | **Internal Cassette Buffer** | `$0340-$03CD` `zp_save_buf` (`142` B) + `$03CE-$03FF` IEC filename/command scratch |
| `$0400-$04FF` | 256 B | **Cartridge SRAM (`RAM123`)** | **`FLOOR_ITEM_BASE` (`256` B for `MAX_FLOOR_ITEMS = 42` — unbanked)** |
| `$0500-$067F` | 384 B | **Cartridge SRAM (`RAM123`)** | **`monster_table` (`32 × 12 = 384` B active monster records — unbanked)** |
| `$0680-$07DF` | 352 B | **Cartridge SRAM (`RAM123`)** | Resident `player_data`, `inv_*`, `equip_*`, `trap_*`, `door_*`, `game_flags` |
| `$07E0-$08DF` | 256 B | **Cartridge SRAM (`RAM123`)** | **`ovl_vars` (`256` B shared mutable variable union for active `$A000` ROM overlay)** |
| `$08E0-$0A1F` | 320 B | **Cartridge SRAM (`RAM123`)** | `msg_history` (`4 × 80` B message history ring buffer) |
| `$0A20-$0DDF` | 960 B | **Cartridge SRAM (`RAM123`)** | **Authoritative `vic_char_shadow` (`40×24 = 960` B C64 screen codes; inspected by `xvic` harness)** |
| `$0DE0-$0ECF` | 240 B | **Cartridge SRAM (`RAM123`)** | `vic_cell_color_shadow` (`20×12 = 240` B arbitrated `8×16` cell colors) |
| `$0ED0-$0FFF` | 304 B | **Cartridge SRAM (`RAM123`)** | **RAM-resident `BLK5` bank/NVRAM switch trampolines (`SEI`) & HAL state** |
| `$1000-$10EF` | 240 B | **Internal Video RAM (`Screen Matrix`)** | **`20×12` VIC-I Screen Matrix (`$9005 = $CC`, `$9002 = $14`), fixed to indices `16..255` (`$10..$FF`)** |
| `$10F0-$10FF` | 16 B | **Internal Video RAM (`Index 15`)** | 16 B guard gap between Screen Matrix and Bitmap |
| `$1100-$1FFF` | 3,840 B | **Internal Video RAM (`160×192` Bitmap)** | **`240 × 16` B `8×16` cells (`Indices 16..255`), forming a `160×192` bitmap (`40×24` `4×8` text + `20×18` `8×8` tiles; `$1100-$14FF` reused as `DUNGEON_GEN_SCAN_SCRATCH_BASE` during level gen)** |
| `$2000-$2EFF` | 3,840 B | **Cartridge SRAM (`BLK1`)** | **`MAP_BASE` (`80×48 = 3,840` B live dungeon map — permanently mapped!)** |
| `$2F00-$32FF` | 1 KB | **Cartridge SRAM (`BLK1`)** | `PLATFORM_TIER_NAME_POOL_BASE` (`1,024` B active monster tier strings) |
| `$3300-$37FF` | 1,280 B | **Cartridge SRAM (`BLK1`)** | `VicAuxRam` (`1,280` B writable store inventory & monster recall arrays) |
| `$3800-$7FFF` | 18,432 B | **Cartridge SRAM (`BLK1 + BLK2 + BLK3`)** | **Always-Resident Core & VIC-20 HAL (`VicResident`, `18.0 KB` contiguous RAM!)** |
| `$8000-$8FFF` | 4 KB | **Internal Character ROM** | Unused after boot (bitmap resides at `$1100-$1FFF`) |
| `$9000-$93FF` | 1 KB | **VIC-I (`$9000-$900F`) & VIAs (`$9110-$912F`)** | Video geometry (`$9000-$9005`), 4-voice sound (`$900A-$900E`), background/border (`$900F`), keyboard/joystick/IEC VIAs |
| `$9400-$97FF` | 1 KB | **Internal Color RAM (`4-Bit Nibbles`)** | `$9400-$94EF` (`240` nibbles): per-`8×16`-cell foreground color (`0..7`) |
| `$9800-$9FFF` | 2 KB | **`Mega-Cart` `IO2` / `IO3` Registers** | `$9C80` `bank_low_reg`; `$9D00` `bank_high_reg` (`$80\|bank`); `$9D80` `ram_en_reg` (`$01`); `$9E00` `nvram_en_reg` (`$00`/`$01`) |
| `$A000-$BFFF` | 8 KB | **`BLK5` Banked ROM / `8 KB` NVRAM** | **ROM (`[$9E00]=$00`):** **Bank `15` (Default Exploration):** `VicPlaySlot` (`8 KB`); **Bank `16`:** `VicModalUIRom` (`8 KB`); **Banks `0..11`:** 12 Overlays in-place; **Banks `12..14`:** `VicAuxRom` + `VicHuffData` + `MONSTER.DB.1..4`; **Bank `$7F`:** `'A0CBM'` boot, `4×8` font, `8×8` tilesets; **NVRAM (`[$9E00]=$01`):** `Cart Slot 0` (`$A000-$B9D7`) + `HISCORE` & `"M8VICNV1"` (`$BF80-$BFFF`) |
| `$C000-$DFFF` | 8 KB | **Internal BASIC ROM** | Unused after boot |
| `$E000-$FFFF` | 8 KB | **Internal KERNAL ROM** | Standard Commodore KERNAL (`IEC` serial disk I/O, `SCNKEY`, hardware vectors) |

---

## 4. Verification Checklist (`docs/VIC20_MEMORY_CONTRACT.md`)

| # | Contract Row | Verification Method |
| --- | --- | --- |
| 1 | `RAM123` allocations fit in `$0400-$0FFF`, `VicResident` fits in `$3800-$7FFF` (`18.0 KB`), and `VicPlaySlot` (Bank 15), `VicModalUIRom` (Bank 16), and every Overlay/Data bank fit in `$A000-$BFFF` (`8.0 KB`) with zero mutable variables in ROM | Kick Assembler `.assert` guards + `platforms/commodore/vic20/check_memory_contract.py` |
| 2 | `$1000-$10EF` (`240` B Screen Matrix = `$10..$FF`) and `$1100-$1FFF` (`3,840` B `160×192` bitmap) have zero overlap under `$9005 = $CC` and `$9002 = $14` (bit 7 = 0), and exploration regions align to even `8×16` cell boundaries (`Rows 0–1`, `Rows 2–19`, `Rows 20–23`) | Static bounds check in `check_memory_contract.py` + `boot_title` `xvic` scenario |
| 3 | `vic_char_shadow` (`$0A20-$0DDF`, `960` B) stays fixed in `RAM123`, `screen_vic.s` clamps `row < 24`, `input_vic.s` isolates `VIA2 DDRB` bit 7 (`$9122`) under `SEI` when sampling Joystick RIGHT, and zero-page usage stays strictly within `$02-$8F` | `tools/check_zp_usage.py` + `tools/check_6502_lint.py` + `check_memory_contract.py` + `make testvic20` |
| 4 | All `BLK5` bank/NVRAM switches execute from `RAM123`/`VicResident` under `SEI`, `Mega-Cart` NVRAM (`$9E00`) stays disabled (`$00`) outside `storage_vic20.s`, cold boot preserves `HISCORE` (`$BF80-$BFFF`) and `Cart Slot 0` (`$A000-$B9D7`) when `"M8VICNV1"` is valid, and both NVRAM and `.d64` saves pass round-trip verification | `save_load_roundtrip` and `death_hiscore` scenarios in `platforms/commodore/vic20/harness_smoke.py` |
