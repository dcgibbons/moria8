# Texas Instruments TI-99/4A (`TMS9900`) Memory Contract

Placement, cartridge banking, 16-bit Scratchpad workspace ownership, `TMS9918A`
VDP VRAM partitioning, and `DSRLNK` hardware-safety source of truth for the
Texas Instruments TI-99/4A port (`platforms/ti99/`). Enforced at assembly/link
time by `xas99.py` (`xdt99`) assertions in `platforms/ti99/memory.inc` and at
build time by `platforms/ti99/check_memory_contract.py`.

---

## 1. Machine Baseline & `32 KB` RAM + `128 KB` `378` Cartridge Model

The TI-99/4A port targets a stock **Texas Instruments TI-99/4A** (`3.0 MHz`
16-bit `TMS9900` CPU, `256 B` 16-bit zero-wait-state Scratchpad RAM at
`$8300-$83FF`, `TMS9918A` VDP with `16 KB` dedicated VRAM, `TMS9919`/`SN76489`
PSG audio, and `TMS9901` CRU keyboard/joystick interface) equipped with:

1. **Standard `32 KB` Memory Expansion:**
   * **Low Expansion RAM (`$2000-$3FFF`, `8 KB`):** Permanently mapped unbanked
     data RAM holding `MAP_BASE` (`$2000-$2EFF`, `3,840` B), `FLOOR_ITEM_BASE`,
     `MONSTER_LIST_BASE`, `ti99_char_shadow` (`$355E-$391D`, `40×24 = 960` B),
     `ti99_color_shadow` (`$391E-$3CDD`, `960` B), `ti99_kbdbuf` (`$3CE0-$3D1F`,
     `64` B), `msg_history` (`320` B), and `ovl_vars` (`256` B).
   * **High Expansion RAM (`$A000-$FFFF`, `24 KB`):** Permanently mapped
     unbanked code/data RAM holding the entire Always-Resident Core + Play
     Engine (`$A000-$EFFF`, `20 KB`), `PLATFORM_TIER_NAME_POOL_BASE` (`$F000-$F3FF`),
     `DUNGEON_GEN_SCAN_SCRATCH_BASE` (`$F400-$F7FF`), `Ti99AuxRam` (`$F800-$FCFF`),
     and resident player/inventory/equipment state + return stack (`$FD00-$FFFF`).
2. **`128 KB` Non-Inverted (`378` / `FinalGROM99`) Banked ROM Cartridge (`$6000-$7FFF`):**
   * `16 × 8 KB` switchable ROM banks (`Banks 0..15`) mapped at `$6000-$7FFF` by
     writing to `$6000 + (bank_id * 2)` (`$6000, $6002, ..., $601E`, e.g.
     `CLR @$6000(R1)` with `R1 = bank_id << 1`).
   * **Mandatory `$6000-$601F` Boot Trampoline Header in All 16 Banks (`TI-01`):**
     Because the hardware 74LS378 latch powers up in an indeterminate bank
     (`0..15`), **every one of the 16 banks (`Banks 0..15`)** contains an
     identical 32-byte TI Cartridge Header (`>AA01`) and boot trampoline at
     `$6000-$601F` (`CLR @$601C; B @real_boot`), guaranteeing 100% deterministic
     power-on boot into Bank 14 regardless of initial latch state.
   * **Banks `0..11` (`12 × 8 KB`, payloads linked at `$6020-$7FFF` = `8,160` B/bank):**
     Dedicated 1-to-1 to the 12 Moria8 Code Overlays (`OVL.START`..`OVL.TITLE`,
     max `~5.3 KB` each), executing **directly in-place from `$6020-$7FFF`
     cartridge ROM** with zero RAM copy, zero wait-state difference vs.
     Expansion RAM (`6` clocks/word on the 8-bit multiplexed bus), and zero
     floppy seeks during gameplay.
   * **Banks `12..13` (`2 × 8 KB`, payloads at `$6020-$7FFF`):** `Ti99AuxRom`
     (read-only item/spell/store templates), `Ti99HuffData`, and
     `MONSTER.DB.1..4`.
   * **Banks `14..15` (`2 × 8 KB`, payloads at `$6020-$7FFF`):** `real_boot`
     loader (copying the `20 KB` Resident+Play payload into `$A000-$EFFF`),
     `TITLE` screen, `8×8` Pixel-Art & Classic ASCII tilesets, and the `6×8`
     `40×24` Text Mode font.
3. **Standard TI Disk Controller (`DSK1`, `90 KB` / `180 KB` `.dsk` Floppy):**
   * Used exclusively for persistent save slots (`DSK1.SAVE0`..`DSK1.SAVE3`),
     `DSK1.HISCORE`, and `DSK1.MORIAID` (plus `DSK1.LICENSE` and `DSK1.SRCOFFR`
     for `AGENTS.md` Rule 7 compliance) via standard TI `DSRLNK` **Level 3
     chunked record I/O** (`INTERNAL, FIXED 128` records: `OPEN` Opcode `0`,
     `READ` Opcode `2`, `WRITE` Opcode `3`, `CLOSE` Opcode `1`, staging `52 ×
     128 B` records through VDP `$3020-$309F`; single-shot `SAVE`/`LOAD` Opcodes
     `5`/`6` are prohibited so transfers never approach `MEMTOP = $37D7`).

---

## 2. Critical Hardware Invariants

1. **`TMS9900` Big-Endian Word Alignment (`EVEN` Rule) & Register MSB Byte Rule (`MOVB`):**
   * The `TMS9900` is a **16-bit big-endian** architecture where word operations
     (`MOV`, `A`, `C`, `S`, `CLR`, `SETO`, `INC`, `DEC`, `SWPB`, `BL`, `B`,
     `BLWP`, `MPY`, `DIV`) force `A15 = 0` (even word boundary).
   * Every 16-bit variable, pointer, return stack frame (`R10`), workspace
     (`WP`), and word lookup table **must** be aligned to an even address via
     `EVEN`.
   * **Register MSB Rule (`TI-04`):** On the `TMS9900`, all byte instructions
     (`MOVB`, `AB`, `CB`, `SB`, `SOCB`, `SZCB`) operate exclusively on the
     **Most Significant Byte (`MSB`, bits `0..7`)** of workspace registers
     (`R0..R15`). Byte values in bits `8..15` (`LSB`) must be swapped via `SWPB`
     (or shifted via `SLA R0, 8`) before `MOVB R0, @addr` or VDP port writes.
2. **`$8300-$83FF` Scratchpad RAM Ownership, `R10` Stack Boundary, & `DSRLNK` Preservation:**
   * The `256` bytes at `$8300-$83FF` are the only 16-bit zero-wait-state RAM in
     the TI-99/4A (`2` clocks/word vs. `6` clocks/word on the 8-bit multiplexed
     expansion/cartridge bus).
   * **Moria8 Workspaces (`$8300-$833F`, `64` B):**
     * `$8300-$831F` (`32` B): **Primary Gameplay Workspace (`WP = $8300`,
       `R0..R15`)**, where `R10` is the software subroutine return stack pointer
       (**initialized to `$0000`** so the first pre-decrement push `DECT R10;
       MOV R11, *R10` lands at `$FFFE-$FFFF` and grows downward to `$FE80`,
       using all `384` bytes / `192` words), `R11` is the hardware `BL` link
       register, and `R12` is the `CRU` base register.
     * `$8320-$833F` (`32` B): **Fast VDP / Audio / Decompression Helper
       Workspace (`WP = $8320`)**.
   * **`DSRLNK` & System Reserved Scratchpad (`$834A-$83FF`):**
     * **`$8370-$8371` (`MEMTOP`)** holds the top-of-free-VDP-VRAM pointer
       (initialized to `$37D7` by the TI Disk Controller at boot) and **must
       never be modified**.
     * `$834A-$836D` (`FAC`), `$8372-$837F` (GPL stacks & status byte `$837C`),
       `$83C0-$83DF` (`ISRWS`), and `$83E0-$83FF` (`GPLWS`) are preserved for
       `DSRLNK` floppy save/load calls.
     * During normal gameplay, CPU interrupts stay masked (`LIMI 0`); VBlank
       pacing polls the active-low VDP interrupt pin on the `TMS9901` (`CLR R12;
       !wait: TB 2; JNE !wait; MOVB @$8802, R0`) without invoking the console
       ROM ISR.
     * **Alpha Lock Diode Isolation (`TI-03`):** When scanning Joystick 1 on
       `CRU` Column 6 (`$0024`), `input_cru.asm` must isolate/mask Keyboard Row
       5 (`Alpha Lock`) so a latched Alpha Lock key never back-feeds phantom
       Joystick UP/Fire signals, and must bypass console uppercase translation
       so lowercase `hjklyubn` keys always register cleanly.
3. **Permanent Unbanked Mapping of `MAP_BASE` (`$2000-$2EFF`), `ti99_char_shadow` (`$355E-$391D`), & `ovl_vars` (`$3E60-$3F5F`):**
   * Because the `32 KB` Memory Expansion (`$2000-$3FFF` and `$A000-$FFFF`) is
     permanently mapped in CPU address space at all times:
     * `MAP_BASE` (`$2000-$2EFF`, `80×48 = 3,840` B), `FLOOR_ITEM_BASE`
       (`$2F00-$32B5`, `950` B), and `MONSTER_LIST_BASE` (`$32B6-$355D`, `680` B)
       require **zero bank switches** during LOS, AI, dungeon generation, or
       overlay execution.
     * `ovl_vars` (`$3E60-$3F5F`, `256` B shared overlay mutable union) lives in
       unbanked Low RAM so overlays executing in `$6020-$7FFF` Cartridge ROM
       never attempt to write to ROM and never conflict with `MAP_BASE`.
     * `ti99_char_shadow` (`$355E-$391D`, `40×24 = 960` B, guarded by a hard
       defensive `CI row, 24; JHE` bounds clamp) and `ti99_kbdbuf` (`$3CE0-$3D1F`,
       `64` B) remain permanently visible to the headless MAME Lua test harness
       (`manager.machine.devices[":maincpu"].spaces["program"]:read_u8/write_u8`).
4. **Dual-Mode `16 KB` VDP VRAM Partitioning (`$0000-$3FFF`), VDP Write Cadence, & `$37D7-$3FFF` Disk Workspace Guard:**
   * **VDP Write Cadence (`TI-02`):** Standard looped writes to `$8C00`
     (`MOVB *R1+, @$8C00; DEC R2; JNE`, `50` clocks = `16.67 µs/byte`) are 100%
     safe during active display (`> 8.0 µs` VDP active window). Unrolled
     `MOVB *R1+, *R2` burst streams (`22` clocks = `7.33 µs/byte`) **must only
     execute during VBlank or while the screen is blanked (`VR1 bit 6 = 0`,
     where the VDP write window is `2.0 µs`)**.
   * All VDP tables for **both** `32×24` Graphics II Exploration Mode (`M3 = 1`)
     and `40×24` Hardware Text Modal Mode (`M1 = 1`) reside simultaneously in
     `$0000-$287F` of the `16 KB` VDP VRAM:
     * **`$0000-$07FF` (`2 KB`):** Active `256`-tile `8×8` Exploration Pattern
       Table (`VR4 = $00` in Masked 1-Bank Graphics II Mode).
     * **`$0800-$0FFF` (`2 KB`):** Permanent `256`-glyph `6×8` Font Pattern Table
       for `40×24` Hardware Text Mode (`VR4 = $01` in Text Mode).
     * **`$1000-$12FF` (`768` B):** `32×24` Exploration Screen Image Table
       (`VR2 = $04` in Graphics II Mode).
     * **`$1400-$17BF` (`960` B):** `40×24` Modal Text Screen Image Table
       (`VR2 = $05` in Text Mode).
     * **`$1800-$1FFF` (`2 KB`):** Sprite Pattern Table (`VR6 = $03`). **Hardware
       Silicon Rule:** All active hardware sprites must use **Sprite Pattern
       indices `0..63` (`$1800-$19FF`)** so that `VR4 = $00` (`bits 1..0 = 00`)
       in Masked Graphics II Mode never masks sprite pattern bits `4..3` on real
       `TMS9918A` silicon.
     * **`$2000-$27FF` (`2 KB`):** Active `256`-tile `8×8` Exploration
       Per-Scanline Color Table (`VR3 = $9F` in Masked 1-Bank Graphics II Mode —
       8 color bytes per tile = 2 independent colors per `8×1` scanline row!).
     * **`$2800-$287F` (`128` B):** Sprite Attribute Table (`VR5 = $50`;
       in Text Mode, hardware sprites are automatically disabled by the VDP).
     * **`$3000-$37CF` (`2,000` B):** `DSRLNK` Program Attribute Block (`PAB` at
       `$3000-$301F`) and Level 3 `FIXED 128` Record Bounce Buffer (`$3020-$309F`,
       with `$30A0-$37CF` spare buffer space).
     * **`$37D7-$3FFF` (`2,089` B):** **Strictly Reserved for TI Disk Controller
       (`DSK1`) DSR Workspace (`MEMTOP = $37D7`).** No Moria8 table or buffer may
       ever touch `>= $37D0`.

---

## 3. Complete CPU (`$0000-$FFFF`) & VDP VRAM (`$0000-$3FFF`) Memory Map

### 3.1 `TMS9900` CPU Address Space (`$0000-$FFFF`)

| Address Range | Size | Hardware Region | Moria8 Ownership & Notes |
| --- | ---: | --- | --- |
| `$0000-$1FFF` | 8 KB | **TI Console System ROM** | Hardware reset vector (`$0000`), GPL interpreter, console math/interrupt tables |
| `$2000-$2EFF` | 3,840 B | **Low Expansion RAM (`MAP_BASE`)** | **`MAP_BASE` (`80×48 = 3,840` B live dungeon map — permanently mapped!)** |
| `$2F00-$32B5` | 950 B | **Low Expansion RAM** | **`FLOOR_ITEM_BASE` (`950` B active floor item table)** |
| `$32B6-$355D` | 680 B | **Low Expansion RAM** | **`MONSTER_LIST_BASE` (`680` B active monster arrays)** |
| `$355E-$391D` | 960 B | **Low Expansion RAM (`ti99_char_shadow`)** | **Authoritative `40×24` C64 screen-code shadow buffer** (inspected by headless MAME Lua harness; guarded by `row < 24` clamp) |
| `$391E-$3CDD` | 960 B | **Low Expansion RAM (`ti99_color_shadow`)** | Authoritative `40×24` logical `COL_*` color shadow buffer |
| `$3CDE-$3CDF` | 2 B | **Low Expansion RAM** | Cursor / VDP mode state (`0 = 32×24 Graphics II`, `1 = 40×24 Text Mode`) |
| `$3CE0-$3D1F` | 64 B | **Low Expansion RAM (`ti99_kbdbuf`)** | **Unbanked PETSCII key injection ring buffer** for headless MAME Lua harness |
| `$3D20-$3E5F` | 320 B | **Low Expansion RAM (`msg_history`)** | `4 × 80` B message history ring buffer (`Ctrl-P` / `FCTN-P`) |
| `$3E60-$3F5F` | 256 B | **Low Expansion RAM (`ovl_vars`)** | **Shared mutable variable union for active `$6000` ROM overlay** |
| `$3F60-$3FFF` | 160 B | **Low Expansion RAM** | Keyboard/Joystick debounce state, RNG seed, and alignment slack |
| `$4000-$5FFF` | 8 KB | **PEB DSR ROM Space** | Switched in by `CRU` (`R12 = $1100`) only inside `storage_dsr.asm` (`DSRLNK`) |
| `$6000-$7FFF` | 8 KB × 16 | **`128 KB` `378` Banked Cart ROM** | **`$6000-$601F` (All Banks `0..15`):** 32 B TI Cartridge Header (`>AA01`) + Bank 14 Boot Trampoline (`CLR @$601C; B @real_boot`); **Banks `0..11` (`$6020-$7FFF`):** 12 Code Overlays (`OVL.START`..`OVL.TITLE`, direct in-place ROM execution); **Banks `12..13` (`$6020-$7FFF`):** `Ti99AuxRom` + `Ti99HuffData` + `MONSTER.DB.1..4`; **Banks `14..15` (`$6020-$7FFF`):** `real_boot`, `TITLE`, `8×8` Pixel-Art/ASCII & `6×8` Font VDP tables |
| `$8000-$83FF` | 256 B | **16-Bit Zero-Wait Scratchpad** | `$8300-$831F`: Main Workspace (`WP = $8300`); `$8320-$833F`: Fast Helper Workspace (`WP = $8320`); `$8340-$8349`: Hot scalars; `$834A-$83FF`: Preserved for `DSRLNK` (`MEMTOP` at `$8370 = $37D7`) |
| `$8400-$8FFF` | — | **Memory-Mapped Hardware Ports** | `$8400`: `TMS9919`/`SN76489` Sound Write; `$8800`: VDP Data Read; `$8802`: VDP Status Read; `$8C00`: VDP Data Write; `$8C02`: VDP Address/Register Write |
| `$A000-$EFFF` | 20 KB | **High Expansion RAM (`Resident+Play`)** | Always-resident `core_tms9900/` foundation, `Ti99Play` (combat, AI, LOS, move, turn, save), and TI-99 HAL (`screen_vdp`, `dungeon_render`, `input_cru`, `sound_sn76489`, `storage_dsr`, `huffman`, `math`) |
| `$F000-$F3FF` | 1 KB | **High Expansion RAM** | `PLATFORM_TIER_NAME_POOL_BASE` (`1,024` B active monster tier strings) |
| `$F400-$F7FF` | 1 KB | **High Expansion RAM** | `DUNGEON_GEN_SCAN_SCRATCH_BASE` (`1,024` B dungeon generation & LOS scratch) |
| `$F800-$FCFF` | 1,280 B | **High Expansion RAM (`Ti99AuxRam`)** | Writable store inventory (`6` stores) & monster recall knowledge arrays |
| `$FD00-$FE7F` | 384 B | **High Expansion RAM** | Resident `player_data`, `inv_*` (`22` slots), `equip_*` (`12` slots), `trap_*`, `door_*`, `game_flags` |
| `$FE80-$FFFF` | 384 B | **High Expansion RAM (`Call Stack`)** | Software subroutine return stack (`R10` initialized to `$0000` so first `DECT R10` lands at `$FFFE`, growing downward to `$FE80`; `192` words = `96` nested call frames) |

---

## 4. Verification Checklist (`docs/TI99_MEMORY_CONTRACT.md`)

| # | Contract Row | Verification Method |
| --- | --- | --- |
| 1 | All 16-bit symbols, workspaces (`$8300`, `$8320`), and return stack (`R10 = $0000` pre-decrement) are `EVEN`-aligned; Low RAM fits in `$2000-$3FFF`; High RAM fits in `$A000-$FFFF`; every `378` cartridge bank (`0..15`) carries the `$6000-$601F` `>AA01` boot trampoline and fits in `$6000-$7FFF` with zero mutable variables in ROM | `xas99.py` symbol/listing check + `platforms/ti99/check_memory_contract.py` |
| 2 | `$834A-$83FF` Scratchpad (`FAC`, `MEMTOP = $37D7` at `$8370`, `GPLWS`) and VDP VRAM `$37D7-$3FFF` are never modified by gameplay/UI code, and `DSRLNK` saves use chunked Level 3 `FIXED 128` records in `$3020-$309F` | Static symbol bounds check in `check_memory_contract.py` + `save_load_roundtrip` MAME scenario |
| 3 | `ti99_char_shadow` (`$355E-$391D`, `960` B) and `ti99_kbdbuf` (`$3CE0-$3D1F`, `64` B) stay fixed in unbanked Low RAM (`$2000-$3FFF`), and `screen_vdp.asm` clamps `row < 24` | Symbol assertions + headless MAME `ti99_4a` runtime suite (`make testti99-runtime`) |
| 4 | Hardware sprites strictly use Sprite Pattern indices `0..63` (`$1800-$19FF` of `VR6 = $03`) so `VR4 = $00` in Masked Graphics II Mode (`M3 = 1`) never masks sprite pattern bits on real `TMS9918A` silicon, and unrolled VDP bursts run only during VBlank or `VR1 bit 6 = 0` | Asset builder assertion in `tools/make_ti99_assets.py --selftest` + `check_memory_contract.py` |
| 5 | All 4 save slots (`DSK1.SAVE0`..`DSK1.SAVE3`), `DSK1.HISCORE`, `DSK1.LICENSE`, and `DSK1.SRCOFFR` persist cleanly on `moria8-ti99-saves.dsk` across MAME `ti99_4a` restarts | `save_load_roundtrip` and `death_hiscore` scenarios in `platforms/ti99/harness_smoke.py` |
