# ModRetro Chromatic / Game Boy Color (`CGB`) Memory Contract

Placement, banking, PPU/APU/DMA register ownership, and hardware-safety source
of truth for the ModRetro Chromatic / Game Boy Color port (`platforms/gbc/`).
Enforced at link time by `rgblink` section bounds and assertions in
`platforms/gbc/memory.inc` and `platforms/gbc/main.asm`, and at build time by
`platforms/gbc/check_memory_contract.py`.

---

## 1. Machine Baseline & `CGB` + `MBC5` Banking Model

The Chromatic / Game Boy Color port targets the stock **Game Boy Color (`CGB`)**
architecture (Sharp `SM83` CPU running in **CGB Double-Speed Mode at
`8.388608 MHz` / `2,097,152` M-cycles/sec**, `16 KB` banked VRAM, `32 KB` banked
WRAM, `64 B` RGB555 Palette RAM, and hardware `GDMA`/`HDMA`) with a **Nintendo
`MBC5 + RAM + BATTERY` (`$1B`)** cartridge:

* **Cartridge Header (`$0100-$014F`):**
  * `$0143` (CGB Flag): **`$C0`** (`CGB-Only` mode; unlocks `8.388 MHz` `KEY1`,
    `VBK`, `SVBK`, `HDMA`, and RGB555 palettes)
  * `$0147` (Mapper): **`$1B`** (`MBC5 + RAM + BATTERY`)
  * `$0148` (ROM Size): **`$02`** (`128 KB = 8 × 16 KB` ROM banks `0..7`)
  * `$0149` (SRAM Size): **`$03`** (`32 KB = 4 × 8 KB` battery-backed SRAM banks `0..3`)
* **CPU ISA Track (`core_z80/` Shared Subset):**
  * Built with **RGBDS (`rgbasm`, `rgblink`, `rgbfix`)** sharing the SM83-clean
    `core_z80/` game-logic track (avoiding Z80-only `IX`/`IY` indexed addressing,
    `EXX`, and raw `LDIR`/`EX DE,HL` in favor of shared `HL`/`DE` struct macros
    and `BLK_COPY`).

### 1.1 Four-Axis Banking Registers (`MBC5` ROM/SRAM + `CGB` WRAM/VRAM)

| Register | Address | Scope | Normal Gameplay State | Transient / Modal / Save State |
| --- | --- | --- | --- | --- |
| **MBC5 ROM Bank Low** | `$2000-$2FFF` | `$4000-$7FFF` (`16 KB` ROM) | Bank `1` (`GbcPlayRom`: core gameplay, combat, AI, LOS) | Bank `2` (`GbcAuxHuffRom` + `MONSTER.DB.1..4`); Banks `3..6` (`12` Overlays executing **directly in-place from ROM**); Bank `7` (`Title` + `CHR` Pixel-Art/ASCII Tile Banks) |
| **MBC5 RAM Enable** | `$0000-$1FFF` | `$A000-$BFFF` (`8 KB` SRAM) | `$00` (**Disabled / Write-Protected** during gameplay) | `$0A` (Unlocked only inside `save_game`, `load_game`, and `hiscore_save/load`) |
| **MBC5 SRAM Bank** | `$4000-$5FFF` | `$A000-$BFFF` (`8 KB` SRAM) | `$00` (Disabled) | Bank `0` (`SAVE0` + `HISCORE`); Bank `1` (`SAVE1`); Bank `2` (`SAVE2`); Bank `3` (`SAVE3`) |
| **CGB WRAM Bank (`SVBK`)** | `$FF70` | `$D000-$DFFF` (`4 KB` WRAM) | **`$01` (WRAM Bank 1: `MAP_BASE` `$D000-$DEFF` `3,840` B — permanently mapped during gameplay!)** | `$02` (WRAM Bank 2: `PLATFORM_TIER_NAME_POOL_BASE`, `GbcAuxRam` writable store/recall, `msg_history`); `$03` (WRAM Bank 3: `DUNGEON_GEN_SCAN_SCRATCH_BASE` + `4×8` text tile composition staging for VBlank `GDMA`) |
| **CGB VRAM Bank (`VBK`)** | `$FF4F` | `$8000-$9FFF` (`8 KB` VRAM) | `$00` (Tilemap `$9800` + Dynamic `4×8` Text Tiles `$8000`) | `$01` (CGB Attribute Map `$9800` + Static `8×8` World Tileset `$8000-$8FFF`) |

---

## 2. Critical Hardware Invariants

1. **Zero-Copy In-Place ROM Overlay Execution (`$4000-$7FFF`, `16 KB` Window) & Unbanked `ovl_vars` (`$CDA0-$CE7F` in `WRAM0`):**
   * Because the MBC5 switchable ROM window (`$4000-$7FFF`) is a full **16 KB**,
     all 12 Moria8 overlays (`max ~5.3 KB`) execute **directly from cartridge
     ROM** without copying code into RAM.
   * Because overlays frequently access `MAP_BASE` (`$D000-$DEFF` in `SVBK = 1`)
     while referencing their own mutable variables, all active overlay mutable
     variables share a **224-byte unbanked union (`ovl_vars` at `$CDA0-$CE7F` in
     Fixed `WRAM Bank 0`)**, never in `ROMX` and never in `SVBK = 2`. This
     guarantees zero `SVBK` bank-switching thrash and zero address aliasing when
     an overlay reads or modifies `MAP_BASE`.
2. **Permanent Mapping of `gbc_char_shadow` (`$C800-$CACF`), `gbc_color_shadow` (`$CAD0-$CD9F`), & `MAP_BASE` (`$D000-$DEFF` in WRAM Bank 1):**
   * **Fixed WRAM Bank 0 (`$C000-$CFFF`, `4 KB`)** is permanently mapped at all
     times and hosts `FLOOR_ITEM_BASE` (`$C000-$C3B5`), `MONSTER_LIST_BASE`
     (`$C3B6-$C65D`), `player_data`/`inv_*`/`equip_*` (`$C65E-$C79F`),
     `gbc_kbdbuf` (`$C7A0-$C7DF`), `gbc_char_shadow` (`40×18 = 720` B at
     `$C800-$CACF`), `gbc_color_shadow` (`40×18 = 720` B at `$CAD0-$CD9F`),
     `ovl_vars` (`$CDA0-$CE7F`), the CPU Hardware Stack (`$CE80-$CEFF`), and
     page-aligned `gbc_oam_shadow` (`$CF00-$CF9F`).
   * **Defensive 18-Row Bounds Guard (`cp 18; ret nc`):** Every character/string
     write entry point in `screen_cgb.asm` enforces a hard row clamp (`row < 18`)
     so no out-of-bounds row (`18..24`) can ever overwrite `gbc_color_shadow`
     (`$CAD0-$CD9F`), `ovl_vars`, or the CPU stack.
   * The headless MAME Lua test harness (`mame gbcolor -cart`) inspects
     `gbc_char_shadow` (`$C800 + row*40 + col`) directly in CPU memory at any
     cycle using standard 40-column C64 screen-code assertions without decoding
     `4×8` 2bpp VRAM tiles.
   * During normal gameplay, `SVBK` (`$FF70`) stays set to **`$01` (WRAM Bank 1)**,
     keeping `MAP_BASE` (`80×48 = 3,840` B at `$D000-$DEFF`) **permanently mapped
     in CPU address space** for zero-switch LOS, AI, dungeon generation, and
     viewport rendering.
3. **Dual-Bank VRAM Partitioning (`VBK = 0` Dynamic `4×8` Text vs. `VBK = 1` Static `8×8` World Tiles):**
   * **VRAM Bank 0 (`VBK = 0`, `$8000-$97FF`, `384` tiles):** Dedicated to the
     **`4×8` condensed font (`2 characters packed per 8×8 tile = 40 columns
     across 20 tiles`)**:
     * **Normal Exploration (`Start` Window Closed):** Only the 2-row Top Message
       Bar (`40` tiles, indices `0..39`) and 2-row Bottom HUD (`40` tiles,
       indices `40..79`) use dynamic text tiles (`80` tiles total `<= 256`), so
       all exploration text tiles reside in `$8000-$84FF` (`LCDC.4 = 1`, zero
       mid-frame scanline splits).
     * **Full-Screen `40×18` Text Modals & `Start` Pop-up Command Window (`360`
       tiles across rows `0..17`):** Rows `0..11` (`240` tiles, indices `0..239`
       at `$8000-$8EFF`) use `LCDC.4 = 1`, and a single **`LYC = 96` (Row 12)
       `STAT` IRQ** switches `LCDC.4 = 0` so rows `12..17` (`120` tiles,
       **strictly restricted to indices `0..119` at `$9000-$977F`**; tile indices
       `>= 128` are forbidden on rows `12..17` because signed `$8800` addressing
       maps `128..255` into `$8800-$8FFF`) read from `$9000-$977F`;
       `gbc_vblank_isr` restores `LCDC.4 = 1` at `LY = 144`.
   * **VRAM Bank 1 (`VBK = 1`, `$8000-$8FFF`, `256` tiles):** Holds the active
     `8×8` World Tileset (`256` bespoke Pixel-Art tiles in Pixel-Art Mode, or
     `256` Classic ASCII tiles in ASCII Mode, swapped in `1.95 ms` via CGB
     hardware `GDMA` when the player presses `Select`). Because text modals only
     write to `VRAM Bank 0`, `VRAM Bank 1`'s world tiles are **never overwritten
     by modal screens**.
4. **Strict CGB VRAM, `GDMA`, & `KEY1` Hardware Discipline (No `HDMA` During `HALT`):**
   * On real CGB hardware, CPU writes to VRAM (`$8000-$9FFF`) and Palette Data
     (`BCPD` `$FF69` / `OCPD` `$FF6B`) are blocked during `STAT` Mode 3, and
     **HBlank DMA (`HDMA`, `$FF55 bit 7 = 1`) freezes if the CPU executes
     `HALT`**.
   * Therefore, **HBlank DMA (`HDMA`) is never used alongside `HALT`**. Instead,
     `4×8` character pairs modified in `gbc_char_shadow` (`$C800-$CACF`) are
     composited into 16-byte 2bpp tile buffers in `WRAM Bank 3` (`$D400-$DFFF`)
     and transferred to `VRAM Bank 0` inside `gbc_vblank_isr` (or during forced
     blank `LCDC.7 = 0` on full-screen modal transitions) via **CGB General
     Purpose DMA (`GDMA`, `$FF55 bit 7 = 0`)**, which copies 16 bytes in just
     **`8` Double-Speed M-cycles (`3.81 µs`)** (`160` M-cycles for a full
     20-tile dirty row, or `< 7%` of the `2,280` M-cycle VBlank budget).
   * Dirty Tilemap (`$9800`, `VBK = 0`) and Attribute Map (`$9800`, `VBK = 1`)
     row flushes inside `gbc_vblank_isr` are batched by bank: flush all 20 tile
     indices under `VBK = 0`, then switch to `VBK = 1` once to flush all 20
     attribute bytes.
   * During cold boot, `boot_init` must write `ld a, $30; ldh [rP1], a` to
     deselect all joypad matrix lines prior to executing `STOP` for the `KEY1`
     (`$FF4D`) `8.388 MHz` Double-Speed switch.
5. **Dedicated 8 KB Battery SRAM Bank per Save Slot (`$0000` Write-Protect Guard) & Cold-Boot `HISCORE` Preservation:**
   * MBC5 External SRAM (`$A000-$BFFF`, `32 KB` across Banks `0..3`) remains
     **write-protected (`[$0000] = $00`)** throughout normal execution.
   * Each of the 4 save slots (`SAVE0..SAVE3`, `6,616` B each) owns its own
     dedicated 8 KB SRAM bank (`Bank 0..3` at `$A000-$B9D7`, with `HISCORE`
     `60` B + `"M8GBCSV1"` 8-byte magic at `$BF80-$BFFF` in Bank 0), eliminating
     all cross-bank save splitting.
   * At cold boot or reset, `boot_init` checks `"M8GBCSV1"` at `$BFF8-$BFFF` in
     SRAM Bank 0: if valid, `$BF80-$BFFF` **must be preserved untouched** so
     high scores survive console power cycles.

---

## 3. Complete CPU, WRAM, VRAM, SRAM, & ROM Memory Map

### 3.1 CPU Address Space (`$0000-$FFFF`)

| Address Range | Size | Hardware Region | Moria8 Ownership & Notes |
| --- | ---: | --- | --- |
| `$0000-$3FFF` | 16 KB | **Fixed ROM Bank 0 (`ROM0`)** | Reset/IRQ vectors (`$0000-$00FF`), Cartridge Header (`$0100-$014F`), SM83 HAL (`screen_cgb.asm`, `dungeon_render.asm`, `input_gbc.asm`, `sound_cgb.asm`, `storage_sram.asm`, `huffman.asm`, `math.asm`, dual pre-shifted `1 KB` `font_4x8_left`/`font_4x8_right` tables), and core resident foundation (`player`, `ui_messages`, `ui_status`, `item`, `monster`) |
| `$4000-$7FFF` | 16 KB | **Switchable ROM (`ROMX`, Banks `1..7`)** | **Bank 1:** `GbcPlayRom` (`combat`, `projectile`, `monster_ai`, `monster_attack`, `dungeon_los`, `player_move`, `player_run`, `turn`, `game_loop`, `save`); **Bank 2:** `GbcAuxRom` + `GbcHuffData` + `MONSTER.DB.1..4`; **Banks 3–6:** 12 Code Overlays (`OVL.START`..`OVL.TITLE`, `3` overlays per 16 KB bank); **Bank 7:** `TITLE` + `8×8` Pixel-Art & ASCII CHR Banks |
| `$8000-$97FF` | 6 KB × 2 | **VRAM Tile Data (`VBK = 0..1`)** | **`VBK = 0`:** `360` dynamic `4×8` dual-char text tiles (`$8000-$8EFF` rows `0..11` indices `0..239`, `$9000-$977F` rows `12..17` indices `0..119`); **`VBK = 1`:** `256` static `8×8` World Tiles (`$8000-$8FFF`) + `24` OAM Sprite Tiles (`$9000-$917F`) |
| `$9800-$9BFF` | 1 KB × 2 | **BG Tilemap (`VBK=0`) & CGB Attrs (`VBK=1`)** | `20×18` active screen (`rows 0..17, cols 0..19` of the `32×32` hardware map; `SCX = 0, SCY = 0`) |
| `$9C00-$9FFF` | 1 KB × 2 | **Window Tilemap (`VBK=0`) & Attrs (`VBK=1`)** | Hardware Window overlay (`WY = 16, WX = 7`) for `Start` Pop-up Command Menu + 6-Stat Mini-Card |
| `$A000-$BFFF` | 8 KB × 4 | **MBC5 Battery SRAM (`Banks 0..3`)** | **Bank 0:** `SAVE0` (`$A000-$B9D7`) + `HISCORE` & `"M8GBCSV1"` (`$BF80-$BFFF`); **Bank 1:** `SAVE1`; **Bank 2:** `SAVE2`; **Bank 3:** `SAVE3` |
| `$C000-$CFFF` | 4 KB | **Fixed WRAM Bank 0 (`WRAM0`)** | Always mapped: `$C000-$C3B5` `FLOOR_ITEM_BASE` (`950` B); `$C3B6-$C65D` `MONSTER_LIST_BASE` (`680` B); `$C65E-$C79F` core resident variables (`player_data`, `inv_*`, `equip_*`, `trap_*`, `door_*`, `game_flags` `322` B); `$C7A0-$C7DF` `gbc_kbdbuf` (`64` B test injection queue); `$C7E0-$C7FF` input/HAL state (`32` B); **`$C800-$CACF` `gbc_char_shadow` (`40×18 = 720` B)**; **`$CAD0-$CD9F` `gbc_color_shadow` (`40×18 = 720` B)**; **`$CDA0-$CE7F` `ovl_vars` (`224` B unbanked overlay mutable union)**; `$CE80-$CEFF` Hardware Stack (`128` B, `SP = $CF00`); `$CF00-$CF9F` page-aligned `gbc_oam_shadow` (`160` B); `$CFA0-$CFFF` VBlank/`GDMA`/Palette state (`96` B) |
| `$D000-$DFFF` | 4 KB × 7 | **Switchable WRAM (`WRAMX`, `SVBK = 1..7`)** | **`SVBK = 1` (Default):** **`MAP_BASE` (`$D000-$DEFF`, `80×48 = 3,840` B)** + `256` B slack (`$DF00-$DFFF`); **`SVBK = 2`:** `PLATFORM_TIER_NAME_POOL_BASE` (`$D000-$D3FF`, `1 KB`) + `GbcAuxRam` (`$D400-$D8FF`, `1,280` B writable store/recall) + `msg_history` (`$D900-$DA3F`, `320` B); **`SVBK = 3`:** `DUNGEON_GEN_SCAN_SCRATCH_BASE` (`$D000-$D3FF`, `1 KB`) + Dirty `4×8` Tile Composition Buffer (`$D400-$DFFF`, `3 KB`) |
| `$FE00-$FE9F` | 160 B | **Hardware OAM (`40` Sprites)** | Populated every VBlank from `$CF00-$CF9F` via `$FF46` OAM DMA (`160` M-cycles) |
| `$FF00-$FF7F` | 128 B | **CGB Hardware I/O Registers** | `P1` (`$FF00`), `TIMA`/`DIV` (`$FF04-$FF07`), APU (`$FF10-$FF3F`), `LCDC`/`STAT`/`SCY`/`SCX`/`LY`/`LYC`/`DMA` (`$FF40-$FF4B`), `KEY1` (`$FF4D`), `VBK` (`$FF4F`), `HDMA1..5` (`$FF51-$FF55` — used in `GDMA` mode `bit 7 = 0`), `BCPS`/`BCPD`/`OCPS`/`OCPD` (`$FF68-$FF6B`), `SVBK` (`$FF70`) |
| `$FF80-$FFFE` | 127 B | **High RAM (`HRAM` — Zero-Page Equivalent)** | `$FF80-$FF89` 10-byte OAM DMA wait routine; `$FF8A-$FFFE` hot core zero-page equivalents (`h_player_x/y`, `h_ptr0`, `h_ptr1`, `h_temp0..4`, `h_rom_bank`, `h_wram_bank`, `h_rng_state`) accessed via 1-byte offset `LDH` |
| `$FFFF` | 1 B | **Interrupt Enable (`IE`)** | `VBlank` (`bit 0`) + `LCD STAT` (`bit 1`, enabled during full-screen text modals & `Start` Window for `LYC = 96` split) |

---

## 4. Verification Checklist (`docs/GBC_MEMORY_CONTRACT.md`)

| # | Contract Row | Verification Method |
| --- | --- | --- |
| 1 | Cartridge header specifies `$0143 = $C0` (CGB-Only), `$0147 = $1B` (MBC5+RAM+BATTERY), `$0149 = $03` (`32 KB` SRAM), and passes `rgbfix -v -C` header checksums | `rgbfix` + `platforms/gbc/check_memory_contract.py` |
| 2 | `ROM0` fits in `$0000-$3FFF`, each `ROMX` bank (`1..7`) fits in `$4000-$7FFF`, zero mutable `.ds`/`.db` variables exist in `ROM0`/`ROMX`, and `ovl_vars` (`$CDA0-$CE7F`) resides in unbanked `WRAM0` | `rgblink` map check + `check_memory_contract.py` |
| 3 | `gbc_char_shadow` (`$C800-$CACF`, `720` B) and `gbc_color_shadow` (`$CAD0-$CD9F`, `720` B) stay fixed in `WRAM0`, and `screen_cgb.asm` clamps `row < 18` | Linker symbol assertions + `check_memory_contract.py` |
| 4 | All VRAM (`$8000-$9FFF`) and Palette (`$FF69`/`$FF6B`) writes occur inside `gbc_vblank_isr`, VBlank `GDMA` (`$FF55 bit 7 = 0`), or while `LCDC.7 == 0`; `HDMA` is never active during `HALT`; rows `12..17` under `LCDC.4 = 0` strictly use tile indices `0..119` | Code audit + `check_memory_contract.py` + headless MAME `gbcolor` runtime suite (`make testgbc-runtime`) |
| 5 | MBC5 SRAM remains write-protected (`[$0000] = $00`) outside `storage_sram.asm`, cold boot preserves `HISCORE` (`$BF80-$BFFF`) when `"M8GBCSV1"` is valid, and all 4 save slots (`Banks 0..3`) persist across MAME `.nv` restarts | `save_load_roundtrip` and `death_hiscore` scenarios in `platforms/gbc/harness_smoke.py` |
