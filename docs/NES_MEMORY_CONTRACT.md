# Nintendo Entertainment System (NES) Memory Contract

Placement, banking, PPU/APU register ownership, and hardware-safety source of
truth for the Nintendo Entertainment System port (`platforms/nes/`). Enforced at
link time by `.assert` guards in `platforms/nes/memory.s` and
`platforms/nes/main.s`, and at build time by
`platforms/nes/check_memory_contract.py`.

---

## 1. Machine Baseline & MMC5 Banking Model (`ExROM` / Mapper 5)

The NES port targets the stock **NTSC Nintendo Entertainment System** (Ricoh
2A03 CPU @ 1.789773 MHz, 2C02 PPU, 2 KB internal CPU RAM, 2 KB internal PPU
VRAM) paired with the **Nintendo MMC5 (`ExROM` / NES 2.0 Mapper 5)** cartridge
hardware:

* **PRG-ROM:** `128 KB` (`16 × 8 KB` banks, MMC5 bank IDs `$80..$8F`, bit 7 = `1`
  selecting ROM)
* **PRG-RAM (WRAM):** `64 KB` battery-backed SUPERRAM (`8 × 8 KB` banks, MMC5
  bank IDs `$00..$07`, bit 7 = `0` selecting RAM; **NES 2.0 header byte 10 = `$A0`**,
  encoding shift count `10` in the high NVRAM nibble: `64 << 10 = 65,536` B
  battery-backed NVRAM and `0` B volatile RAM, matching MAME `nes_ines.hxx`)
* **CHR-ROM:** `32 KB` (`8 × 4 KB` pattern tables, MMC5 4 KB CHR mode `$5101 = $00`)
* **MMC5 Internal ExRAM (`$5C00-$5FFF`):** `1 KB` configured in **Extended
  Attribute Mode (`$5104 = $01`)**, providing an independent 2-bit palette
  (`bits 7..6`) and 6-bit 4 KB CHR bank (`bits 5..0`) for every individual `8×8`
  tile across the `32×30` nametable (`960` tiles).

### 1.1 MMC5 PRG Banking Mode 3 (`$5100 = $03`)

Memory visibility across `$6000-$FFFF` is controlled by five 8 KB bank
registers (`$5113-$5117`) after unlocking PRG-RAM write-enable (`$5102 = $02`,
`$5103 = $01`):

| Register | CPU Window | Size | Normal Gameplay State | Transient Data / Decode / Load State |
| --- | --- | ---: | --- | --- |
| `$5113` | `$6000-$7FFF` | 8 KB | `$00` (**PRG-RAM Bank 0**: `NesResidentLow`) | `$04` (**PRG-RAM Bank 4**: `MAP_BASE` virt `$2000-$2EFF`, `NesAuxRam` virt `$4000-$44FF`, `msg_history`, `SAVE0` Part A); `$05..$07` (**PRG-RAM Banks 5–7**: `SAVE0` Part B..`SAVE3`) |
| `$5114` | `$8000-$9FFF` | 8 KB | `$01` (**PRG-RAM Bank 1**: `NesResidentMid`) | `$84` (**PRG-ROM Bank 4**: `NesAuxRom` virt `$4500-$56FF` + `MONSTER.DB.1..2`); `$85` (**PRG-ROM Bank 5**: `NesHuffData` + `MONSTER.DB.3..4`); `$86..$8D` (**PRG-ROM Banks 6–13**: Overlays & Boot Image) |
| `$5115` | `$A000-$BFFF` | 8 KB | `$02` (**PRG-RAM Bank 2**: `NesResidentHigh` + `NesPlay`) | Untouched (`$02`) during runtime |
| `$5116` | `$C000-$DFFF` | 8 KB | `$03` (**PRG-RAM Bank 3**: `nes_screen_shadow` `$C000-$C3BF`, `NES_HISCORE_SRAM` `$C3C0-$C3FF`, `PLATFORM_TIER_NAME_POOL_BASE` `$C400-$C7FF`, Active Overlay Window `$C800-$DFFF`) | **Permanently mapped (`$03`) — never switched** |
| `$5117` | `$E000-$FFFF` | 8 KB | `$8F` (**Fixed PRG-ROM Bank 15**: NES HAL, PPU/APU/Input/Storage drivers, bank switchers, and CPU vectors) | **Permanently mapped (`$8F`) — never switched** |

### 1.2 MMC5 ExRAM (`$5104 = $01`) & CHR Banking (`$5101 = $00`)

In Extended Attribute Mode (`$5104 = $01`), each byte at `$5C00 + row*32 + col`
(`$5C00-$5FBF`) controls the corresponding `8×8` nametable cell at
`$2000 + row*32 + col`:

* **Bits `7..6` (`$C0`):** Selects 1 of the 4 NES Background Palettes (`0..3`).
* **Bits `5..0` (`$3F`):** Selects 1 of the 4 KB CHR-ROM banks (`0..7`), with
  upper CHR bits `$5130 = $00`:
  * **CHR Bank 0 (`$00`):** C64-ordered 8×8 ASCII font (`$00-$7F` normal,
    `$80-$FF` inverse) encoded in **Bitplane `01` (Palette Sub-color 1)**.
  * **CHR Bank 1 (`$01`):** C64-ordered 8×8 ASCII font (`$00-$7F` normal,
    `$80-$FF` inverse) encoded in **Bitplane `10` (Palette Sub-color 2)**.
  * **CHR Bank 2 (`$02`):** C64-ordered 8×8 ASCII font (`$00-$7F` normal,
    `$80-$FF` inverse) encoded in **Bitplane `11` (Palette Sub-color 3)**.
  * **CHR Bank 3 (`$03`):** **Bespoke 3-Color + Black 8×8 Pixel-Art Tileset**
    (`$00-$7F` terrain, town doors, traps, items, and player knight/`@`;
    `$80-$B5` all 54 unique monster species icons; `$B6-$FF` wall/floor lighting
    variants and warding glyphs).
  * **CHR Bank 4 (`$04`, Sprite Pattern Table `$1000-$1FFF` via `$5120-$5127`):**
    Hardware OAM sprites (menu selection cursor `>`, look/target reticle,
    ranged arrows/bolts/breath projectiles, and hit-splat overlays).

---

## 2. Critical Hardware Invariants

1. **Permanent Mapping of `nes_screen_shadow` (`$C000-$C3BF`) and ExRAM (`$5C00-$5FBF`) — Zero Bank Switching on Screen Writes:**
   * `nes_screen_shadow` (`$C000-$C3BF`, `960` B), `NES_HISCORE_SRAM`
     (`$C3C0-$C3FF`, `64` B), and `PLATFORM_TIER_NAME_POOL_BASE` (`$C400-$C7FF`,
     `1,024` B) reside in **PRG-RAM Bank 3 (`$C000-$DFFF`, `$5116 = $03`)**, which
     is **permanently mapped at all times**.
   * Extended attributes reside in **MMC5 Internal ExRAM (`$5C00-$5FBF`, `960` B)**,
     which is also **permanently mapped at all times**.
   * Consequently, `hal_screen_put_char`, `hal_screen_put_string`,
     `hal_screen_clear`, `hal_screen_clear_row`, `msg_print`, and `status_draw`
     **never modify `$5113` or `$5114`**. Callers in any bank (`$6000-$DFFF` or
     `$E000-$FFFF`) can pass string pointers in `zp_ptr0` without risk of
     unmapping the source string or the caller's code segment, and the MAME Lua
     test harness can inspect `nes_screen_shadow` at `$C000-$C3BF` directly at
     any CPU cycle.
2. **Real-Hardware MMC5 ExRAM (`$5C00-$5FBF`) Write Timing Rule (In-Frame vs. Forced Blank):**
   * On real MMC5 silicon in Extended Attribute Mode (`$5104 = %01`), ExRAM
     write arbitration is clocked by the PPU's active background fetch pipeline
     (scanlines `0..239`). Attempting CPU writes to `$5C00-$5FBF` during **VBlank**
     while `$5104 = %01` fails or writes `$00`.
   * Therefore:
     * During normal gameplay (rendering enabled), CPU writes to `$5C00-$5FBF`
       are performed **directly inside `screen_ppu.s` and `dungeon_render.s`
       during active rendering scanlines `0..239`** (consuming **zero VBlank NMI
       cycles**!).
     * During full-screen clears/loads with rendering disabled (`PPUMASK == $00`),
       `screen_ppu.s` temporarily sets `$5104 = $02` (Ordinary RAM mode) while
       writing `$5C00-$5FBF`, then restores `$5104 = $01` before re-enabling
       `PPUMASK`.
     * `nes_nmi_handler` **never** writes to `$5C00-$5FBF` during VBlank; it
       flushes only PPU `$2007` nametable bytes from permanently mapped
       `nes_screen_shadow` (`$C000-$C3BF`), runs `$4014` OAM DMA, and resets
       scroll registers.
3. **VBlank NMI Cycle Budget (`2,273` Cycles Ceiling, 4-Page Sled Dispatcher, Max 5 Rows/Frame):**
   * NTSC VBlank spans 20 scanlines (`2,273` CPU cycles). Fixed NMI overhead
     (`$4014` OAM DMA `514` cycles + prologue/epilogue/scroll `72` cycles) leaves
     **`1,687` CPU cycles** for `$2007` nametable updates.
   * Because an 8-bit `X` index (`X = (row & 7) << 5`) spans 8 rows (`256` B)
     with zero page-crossing penalty, `NesFixedRom` implements four 192-byte page
     sleds (`flush_sled_c0..c3` for `$C000,x`..`$C300,x`, `780` B total)
     taking **`290` CPU cycles per row** (`16` cycles `$2006` latch + `12` cycles
     jump-table dispatch + `256` cycles transfer + `6` cycles return).
   * `nes_nmi_handler` flushes at most **5 dirty rows per VBlank**
     (`5 × 290 = 1,450` cycles, leaving a **237-cycle safety margin**).
4. **Virtual Address Disambiguation (`MAP_BASE` `$2000`, `NesAuxRam` `$4000`, `NesAuxRom` `$4500`), Register Preservation, & Aux Persistence Hooks:**
   * All routines that modify `$5113` (`$6000-$7FFF`) or `$5114` (`$8000-$9FFF`)
     link and execute inside `NesFixedRom` (`$E000-$FFF9`), and
     `mmu_safe_map_read_ptr0/1` and `mmu_safe_map_write_ptr0/1` **preserve CPU
     registers `X` and `Y`** (and `A` on writes).
   * To prevent any address alias between `NesResidentLow` (`$6000-$7FFF`) and
     banked data, banked data segments use distinct virtual high-byte ranges:
     * **`$2000-$2EFF` (`zp_ptr_hi` in `$20..$2E`):** `MAP_BASE` (`3,840` B),
       mapped to physical `$6000-$6EFF` in **PRG-RAM Bank 4 (`$5113 = $04`)** via
       `phys_hi = virt_hi | $40`.
     * **`$4000-$44FF` (`zp_ptr_hi` in `$40..$44`):** `NesAuxRam` (`1,280` B:
       writable `store_inventory_data.s`, `recall_array_data.s`, and
       `store_runtime_data.s`), mapped to physical `$6F00-$73FF` in **PRG-RAM
       Bank 4 (`$5113 = $04`)** via `phys_hi = virt_hi + $2F`.
     * **`$4500-$56FF` (`zp_ptr_hi` in `$45..$56`):** `NesAuxRom` (`4,608` B:
       read-only `spell_class_data.s`, `spell_helper_tables.s`, `spell_names.s`,
       `ego_suffix_slots`, and navigation strings), mapped to physical
       `$8500-$96FF` in **PRG-ROM Bank 4 (`$5114 = $84`)** via
       `phys_hi = virt_hi + $40`.
     * **All other addresses (`< $20` or `>= $60`):** Normal mapped RAM/ROM —
       accessed directly with zero bank switching!
   * `platforms/nes/hal/lifecycle_policy.s` and `storage_policy.s` define
     `HAL_PLATFORM_AUX_PERSISTENT_DATA = 1`, `HAL_STORAGE_SAVE_BLOCK_MODE_HOOK = 1`,
     and `HAL_STORAGE_MAP_BANKED = 1` so `core/` and `platforms/shared/save.s`
     never dereference virtual `$4000-$44FF` directly (which would hit hardware
     2A03 APU registers `$4000-$4017`), and `platforms/nes/memory.s` defines
     `.const SCREEN_RAM = nes_ss_buf` (`$0700`) so `HAL_LAYOUT_DUNGEON_GEN_ROW_BATCHED_MAP = 1`
     never writes into `nes_screen_shadow` (`$C000-$C3BF`).
5. **Cold-Boot Preservation of `NES_HISCORE_SRAM` (`$C3C0-$C3FF`):**
   * At cold boot or reset, `boot_init` checks the 4-byte magic signature
     `"M8SV"` at `$C3FC-$C3FF` before initializing PRG-RAM Bank 3 (`$C000-$DFFF`).
   * If `"M8SV"` is valid, `boot_init` **preserves `$C3C0-$C3FF` untouched** so
     battery-backed high scores survive console resets and power cycles; only on
     unformatted SRAM does `boot_init` zero `$C3C0-$C3FB` and write `"M8SV"`.
6. **Viewport Bank-Hoisting & Resident Placement of `item.s` / `monster.s`:**
   * `dungeon_render.s` (in `NesFixedRom` `$E000-$FFFF`) switches `$5113 = $04`
     **once at viewport entry**, reads `MAP_BASE` (`$6000-$6EFF`) and writes
     `nes_screen_shadow` (`$C000-$C3BF`) and ExRAM (`$5C00-$5FBF`) across all
     viewport cells with zero per-tile bank switches (comparing each tile
     against `nes_screen_shadow` to mark only changed rows dirty), and restores
     `$5113 = $00` **once at viewport exit**.
   * Therefore, **every helper called inside `render_viewport`** (specifically
     `floor_item_find_at` in `core/item.s` and `monster_find_at` in
     `core/monster.s`) **must link in `NesResidentMid` (`$8000-$9FFF`) or
     `NesResidentHigh` (`$A000-$BFFF`) — never in `NesResidentLow`
     (`$6000-$7FFF`)**, enforced by `check_memory_contract.py`.
7. **ROM-Safe `core/huffman.s` (`HAL_HUFFMAN_NO_SMC = 1`) & Ricoh 2A03 Binary Arithmetic:**
   * Because `NesFixedRom` (`$E000-$FFFF`) is read-only ROM, `core/huffman.s`
     is compiled with `HAL_HUFFMAN_NO_SMC = 1`, storing the tree-walk node index
     in `zp_hd_cur_node` (in platform ZP `$0090-$00BF`) instead of self-modifying
     an immediate operand.
   * The Ricoh 2A03 lacks hardware BCD (`SED`/`CLD`); all arithmetic in
     `platforms/nes/` is pure binary, and `math_multiply` / `math_mul_16x8` use
     the **MMC5 hardware 8×8->16 unsigned multiplier (`$5205`/`$5206`)**.

---

## 3. Complete CPU & Cartridge Memory Map

### 3.1 Internal CPU RAM (`$0000-$07FF`, 2 KB — Always Unbanked)

| Address Range | Size | Owner | Notes |
| --- | ---: | --- | --- |
| `$0000-$0001` | 2 B | Scratch / Reserved | Unused |
| `$0002-$008F` | 142 B | Shared Core ZP (`core/zeropage.s`) | Application zero-page owned by game logic |
| `$0090-$00BF` | 48 B | Platform ZP (`platforms/nes/memory.s`) | `$0090` = `zp_kernal_status`; `$0091-$00BF` = `nes_prg_bank_6000`, `nes_prg_bank_8000`, `nes_nmi_ready`, `nes_gfx_mode`, `zp_hd_cur_node`, `nes_map_ptr`, `nes_aux_ptr`, PPU/APU/pad shadows |
| `$00C0-$00FF` | 64 B | Fast NMI / Render ZP | Row-flush pointers and viewport inner-loop temporaries |
| `$0100-$01FF` | 256 B | Hardware Stack | Standard 6502 call stack |
| `$0200-$02FF` | 256 B | `NES_OAM_SHADOW` | 64-sprite OAM DMA buffer (`$4014 <- #$02` every VBlank) |
| `$0300-$038D` | 142 B | `zp_save_buf` | Saved core ZP buffer for `save_zp` / `restore_zp` |
| `$038E-$03BF` | 50 B | `nes_kbdbuf` & `nes_kbdbuf_len` | Unbanked PETSCII key injection queue for deterministic MAME Lua harness & controller translation |
| `$03C0-$03FF` | 64 B | NES HAL Runtime State | 30-row dirty bitmask (`nes_dirty_rows_0..3`), APU 4-channel SFX state, controller debounce |
| `$0400-$04FF` | 256 B | `FLOOR_ITEM_BASE` | Active level floor-item table (unbanked) |
| `$0500-$05FF` | 256 B | `CREATURE_BASE` | Active monster tier records & RLE scratch (unbanked) |
| `$0600-$063F` | 64 B | `PLATFORM_HD_DECODE_BUF_BASE` | Huffman string decode buffer |
| `$0640-$0680` | 65 B | `DUNGEON_GEN_DOOR_SCAN_BASE` | Dungeon-generator door-scan scratch |
| `$0681-$06FF` | 127 B | Controller UI & Save Stream State | Pop-up command menu state, list cursor index, haggle spinner, SRAM stream state (`stream_slot`, `stream_off_lo/hi`) |
| `$0700-$077F` | 128 B | `nes_ss_buf` | Unbanked 128-byte save/load stream & row-batch bounce buffer |
| `$0780-$07FF` | 128 B | Unbanked Scratch / Overlay State | Shared unbanked scratch |

### 3.2 Hardware I/O & MMC5 ExRAM (`$2000-$5FFF`)

| Address Range | Size | Owner | Notes |
| --- | ---: | --- | --- |
| `$2000-$2007` | 8 B | 2C02 PPU Registers | `PPUCTRL`, `PPUMASK`, `PPUSTATUS`, `OAMADDR`, `OAMDATA`, `PPUSCROLL`, `PPUADDR`, `PPUDATA` |
| `$4000-$4017` | 24 B | 2A03 APU, OAM DMA (`$4014`), & Joypads (`$4016`/`$4017`) | 2 Pulse, 1 Triangle, 1 Noise, OAM DMA, and controller strobe/serial read |
| `$5000-$5206` | 519 B | MMC5 Mapper Registers | `$5100=$03` (8 KB PRG), `$5101=$00` (4 KB CHR), `$5102=$02`/`$5103=$01` (WRAM write enable), `$5104=$01` (Extended Attributes), `$5105=$44` (vertical mirroring), `$5113-$5117` (PRG banks), `$5205/$5206` (hardware 8×8 unsigned multiplier) |
| `$5C00-$5FBF` | 960 B | MMC5 Extended Attribute Table | `32×30` per-tile palette (`bits 7..6`) + 4 KB CHR bank (`bits 5..0`), written during active rendering (`$5104=$01`) or forced blank (`$5104=$02`) |
| `$5FC0-$5FFF` | 64 B | ExRAM Tail | Unused guard slack |

### 3.3 Active Gameplay RAM Windows (`$6000-$DFFF`, 32 KB — PRG-RAM Banks 0..3)

Copied from PRG-ROM into PRG-RAM Banks `0..3` once at cold boot by `boot_init`:

| Window | MMC5 Reg | Address Range | Size | Segment / Owner | Notes |
| --- | --- | --- | ---: | --- | --- |
| Window 0 | `$5113 = $00` | `$6000-$7FFF` | 8,192 B | `NesResidentLow` | Core resident modules Part 1 (must **not** contain `item.s` or `monster.s`) |
| Window 1 | `$5114 = $01` | `$8000-$9FFF` | 8,192 B | `NesResidentMid` | Core resident modules Part 2 (includes `item.s` and `monster.s` for viewport safety) |
| Window 2 | `$5115 = $02` | `$A000-$BFFF` | 8,192 B | `NesResidentHigh` + `NesPlay` | Core resident tail + gameplay modules (`program_end <= $C000`, `24,576` B resident/play budget across `$6000-$BFFF`) |
| Window 3 | `$5116 = $03` | `$C000-$C3BF` | 960 B | **`nes_screen_shadow`** | **Permanently mapped** `32×30` C64 screen-code shadow buffer (flushed to PPU in NMI; read directly by MAME Lua harness) |
| Window 3 | `$5116 = $03` | `$C3C0-$C3FF` | 64 B | **`NES_HISCORE_SRAM`** | **Permanently mapped** 60-byte battery-backed high-score table + 4-byte `"M8SV"` magic |
| Window 3 | `$5116 = $03` | `$C400-$C7FF` | 1,024 B | **`PLATFORM_TIER_NAME_POOL_BASE`** | **Permanently mapped** active monster tier name pool (`1,024` B) |
| Window 3 | `$5116 = $03` | `$C800-$DFFF` | 6,144 B | **`OVERLAY_BASE` / `BANKED_DATA_BASE`** | **Permanently mapped** Active Overlay execution window (`6,144` B; `$DC00-$DFFF` also serves as `DUNGEON_GEN_SCAN_SCRATCH_BASE` during `OVL.GEN`) |

### 3.4 Fixed PRG-ROM Window (`$E000-$FFFF`, 8 KB — PRG-ROM Bank 15 `$8F`)

| Address Range | Size | Owner | Notes |
| --- | ---: | --- | --- |
| `$E000-$FFF9` | 8,186 B | `NesFixedRom` | Cold boot init (`entry_main`), `screen_ppu.s`, `dungeon_render.s`, `memory_mmc5.s`, `huffman.s` (`HAL_HUFFMAN_NO_SMC`), `math.s` (`$5205/$5206`), `input_nes.s`, `sound_apu.s`, `storage_sram.s`, `save_stream_sram.s`, and NMI/IRQ handlers |
| `$FFFA-$FFFF` | 6 B | CPU Vectors | `$FFFA` = `nes_nmi_handler`, `$FFFC` = `entry_main`, `$FFFE` = `nes_irq_handler` |

### 3.5 Extended PRG-RAM Allocation (`64 KB = 8 × 8 KB` Battery-Backed Banks `$00..$07`)

Full `80×48`-map saves generated by `platforms/shared/save.s` are `6,616` bytes.
Each of the 4 save slots (`SAVE0..SAVE3`) is allocated **`6,760` bytes** (`144` B
of safety margin above `6,616` B), accessed in 128-byte chunks via `nes_ss_buf`
(`$0700-$077F`):

| PRG-RAM Bank | `$5113` Value | Physical Range (`$6000-$7FFF`) | Size | Allocation |
| --- | --- | --- | ---: | --- |
| **Bank 0** | `$00` | `$6000-$7FFF` | 8,192 B | Active Gameplay RAM: `NesResidentLow` |
| **Bank 1** | `$01` | `$8000-$9FFF` (via `$5114`) | 8,192 B | Active Gameplay RAM: `NesResidentMid` (`item.s`, `monster.s`) |
| **Bank 2** | `$02` | `$A000-$BFFF` (via `$5115`) | 8,192 B | Active Gameplay RAM: `NesResidentHigh` + `NesPlay` |
| **Bank 3** | `$03` | `$C000-$DFFF` (via `$5116`) | 8,192 B | Permanently Mapped: `nes_screen_shadow` (`$C000`), `HISCORE` (`$C3C0`), Tier Pool (`$C400`), Overlay Window (`$C800-$DFFF`) |
| **Bank 4** | `$04` | `$6000-$6EFF` | 3,840 B | **`MAP_BASE`** (virtual `$2000-$2EFF`, `80×48` dungeon map) |
| | `$04` | `$6F00-$73FF` | 1,280 B | **`NesAuxRam`** (virtual `$4000-$44FF`: writable `store_inventory_data`, `recall_array_data`, `store_runtime_data`) |
| | `$04` | `$7400-$753F` | 320 B | **`msg_history`** (`8 × 40` B ring buffer via `MSG_HISTORY_IN_AUX = 1`, `hal_layout_msg_hist_len = 40`) |
| | `$04` | `$7540-$7FFF` | 2,752 B | **`SAVE0` (Part A)** (`2,752` B) |
| **Bank 5** | `$05` | `$6000-$6FA7` | 4,008 B | **`SAVE0` (Part B)** (`2,752 + 4,008 = 6,760` B total for Slot 0) |
| | `$05` | `$6FA8-$7FFF` | 4,184 B | **`SAVE1` (Part A)** (`4,184` B) |
| **Bank 6** | `$06` | `$6000-$6A0F` | 2,576 B | **`SAVE1` (Part B)** (`4,184 + 2,576 = 6,760` B total for Slot 1) |
| | `$06` | `$6A10-$7FFF` | 5,616 B | **`SAVE2` (Part A)** (`5,616` B) |
| **Bank 7** | `$07` | `$6000-$6477` | 1,144 B | **`SAVE2` (Part B)** (`5,616 + 1,144 = 6,760` B total for Slot 2) |
| | `$07` | `$6478-$7EDF` | 6,760 B | **`SAVE3`** (`6,760` B contiguous in Bank 7 for Slot 3) |
| | `$07` | `$7EE0-$7FFF` | 288 B | Free slack + `NES_SRAM_MAGIC` (`"M8NESSV1"` at `$7FF0-$7FFF`) |

### 3.6 PRG-ROM Allocation (`128 KB = 16 × 8 KB` Banks `$80..$8F`)

| PRG-ROM Bank | `$5114` Value | Contents | Approx Size | Slack |
| --- | --- | --- | ---: | ---: |
| **Bank 0** | `$80` | Initial RAM Image: `$6000-$7FFF` (`NesResidentLow`) | 8,192 B | — |
| **Bank 1** | `$81` | Initial RAM Image: `$8000-$9FFF` (`NesResidentMid`) | 8,192 B | — |
| **Bank 2** | `$82` | Initial RAM Image: `$A000-$BFFF` (`NesResidentHigh` + `NesPlay`) | 8,192 B | — |
| **Bank 3** | `$83` | Initial `NesAuxRam` Image (`1,280` B) + `TITLE` Art (`960` B) | ~2,240 B | ~5.9 KB |
| **Bank 4** | `$84` | **`NesAuxRom`** (`$8500-$96FF`, virt `$4500-$56FF`: read-only spell/ego/store tables) + **`MONSTER.DB.1..2`** (`$8000-$84FF` / `$9700-$9BFF`, read directly from PRG-ROM!) | ~6,912 B | ~1.2 KB |
| **Bank 5** | `$85` | **`NesHuffData`** (linked at physical `$8000-$8D93`, direct decode via `$5114 = $85`) + **`MONSTER.DB.3..4`** (`$9000-$98FF`, read directly from PRG-ROM!) | ~5,780 B | ~2.4 KB |
| **Bank 6** | `$86` | **`OVL.START`** (`~4.3` KB) + **`OVL.HELP`** (`~3.2` KB) | ~7,680 B | ~512 B |
| **Bank 7** | `$87` | **`OVL.TOWN`** (`~5.3` KB) + **`OVL.CHEST`** (`~2.1` KB) | ~7,580 B | ~612 B |
| **Bank 8** | `$88` | **`OVL.DEATH`** (`~4.2` KB) + **`OVL.TITLE`** (`~0.6` KB) | ~4,920 B | ~3.2 KB |
| **Bank 9** | `$89` | **`OVL.MODAL`** (`~3.3` KB) + **`OVL.UI`** (`~2.5` KB) | ~5,940 B | ~2.2 KB |
| **Bank 10** | `$8A` | **`OVL.SPELL`** (`~5.3` KB) | ~5,400 B | ~2.8 KB |
| **Bank 11** | `$8B` | **`OVL.ITEMS`** (`~5.3` KB) | ~5,400 B | ~2.8 KB |
| **Bank 12** | `$8C` | **`OVL.GEN`** (`~4.1` KB, `<= $DC00` so `$DC00-$DFFF` is free for `DUNGEON_GEN_SCAN_SCRATCH_BASE`) + `special_rooms.s` (`~1.0` KB) | ~5,120 B | ~3.0 KB |
| **Bank 13** | `$8D` | Reserved / Expansion Overlay (`OVL.STORAGE` / Controller Help) | ~2,000 B | ~6.2 KB |
| **Bank 14** | `$8E` | Reserved Free PRG-ROM Bank | 0 B | 8.0 KB |
| **Bank 15** | `$8F` | **`NesFixedRom` (`$E000-$FFFF`)**: NES HAL, PPU/APU/Input/Storage drivers, bank switchers, and CPU vectors | ~7,400 B | ~800 B |

---

## 4. Verification Checklist (`docs/NES_MEMORY_CONTRACT.md`)

Before declaring any NES memory, banking, PPU, or storage change complete,
confirm each applicable row:

| # | Contract Row | Verification Method |
| --- | --- | --- |
| 1 | NES 2.0 header byte 10 equals `$A0` (`64 KB` battery-backed NVRAM, `0` volatile RAM) | `tools/make_nes_rom.py --selftest` + `check_memory_contract.py` |
| 2 | `NesResident` + `NesPlay` ends at or below `$C000`, and `core/item.s` + `core/monster.s` link in `>= $8000` (`NesResidentMid` / `NesResidentHigh`) | Assembler `.assert` in `platforms/nes/main.s` + `check_memory_contract.py` |
| 3 | Every overlay segment fits within `$C800-$DFFF` (`6,144` B), and `OVL.GEN` ends at or below `$DC00` (`DUNGEON_GEN_SCAN_SCRATCH_BASE`) | Assembler `.assert` on every overlay end label + `check_memory_contract.py` |
| 4 | `NesFixedRom` fits within `$E000-$FFF9` below CPU vectors (`$FFFA-$FFFF`), contains zero mutable inline state, and compiles `huffman.s` with `HAL_HUFFMAN_NO_SMC = 1` | Assembler `.assert` + `check_memory_contract.py` |
| 5 | All routines writing `$5113` or `$5114` link in `NesFixedRom` (`$E000-$FFF9`) and update `nes_prg_bank_6000` / `nes_prg_bank_8000` before switching | Static check in `check_memory_contract.py` |
| 6 | PPU `$2006`/`$2007` writes occur only in `nes_nmi_handler` (max 5 rows/frame) or under forced blank (`PPUMASK == $00`), and ExRAM (`$5C00-$5FBF`) is written only during active rendering (`$5104 = $01`) or forced blank (`$5104 = $02`) | Code review + MAME runtime smoke suite (`make testnes`) |
| 7 | Battery SRAM save slots `SAVE0..SAVE3` (`6,760` B each) and `HISCORE` persist across MAME `.nv` restarts in isolated per-test `-nvram_directory` | `save_load_roundtrip` scenario in `platforms/nes/harness_smoke.py` |
