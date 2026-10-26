# Acorn BBC Master 128 Memory Contract

Placement, banking, and hardware-ownership source of truth for the Acorn BBC
Master 128 port (`platforms/bbcmaster/`). Enforced at link time by `.assert`
guards in `platforms/bbcmaster/memory.s` and `platforms/bbcmaster/main.s`, and
at build time by `platforms/bbcmaster/check_memory_contract.py`.

## 1. Machine Baseline & Banking Model (`ROMSEL` `$FE30` & `ACCCON` `$FE34`)

The Acorn BBC Master 128 port targets the stock **128 KB BBC Master 128**
(2 MHz Rockwell/WDC 65C12 CPU, MOS 3.20, DFS 2.24, 32 KB Main RAM, 20 KB Shadow
Screen RAM `LYNNE`, 4 KB Private RAM `ANDY`, 8 KB Filing/System RAM `HAZEL`, and
64 KB Sideways RAM in slots 4–7).

Memory visibility is controlled through two write-only hardware registers in
`SHEILA` (`$FE00-$FEFF`) and two zero-page shadow bytes (`$00F4` MOS `ROMSEL`
shadow and `beeb_acccon_shadow` in platform ZP):

### `ROMSEL` (`$FE30`) & MOS Shadow `$00F4`

| Bits | Mask | Name | Gameplay State (`$04`) | Map / AuxData / Cache State (`$05`–`$07`) | `ANDY` HuffData Decode State (`$84`) |
| ---: | --- | --- | --- | --- | --- |
| `0..3` | `$0F` | Sideways Slot Select (`0..15`) | `4` (Bank 4: `BeebPlaySlot` + Tier Pool + Active Overlay Window) | `5` (Bank 5: Live Map + `OVL.UI`); `6` (Bank 6: `BeebAuxData` + `TOWN`/`MODAL`); `7` (Bank 7: `SPELL`/`ITEMS`/`GEN`) | `4` (Bank 4 upper 12 KB at `$9000-$BFFF` stays visible) |
| `4..6` | `$70` | Unused | `0` | `0` | `0` |
| `7` | `$80` | `ANDY` 4 KB RAM Enable (`$8000-$8FFF`) | `0` (Bank 4 lower 4 KB visible at `$8000-$8FFF`) | `0` (Bank 5–7 full 16 KB visible at `$8000-$BFFF`) | `1` (`ANDY` 4 KB mapped at `$8000-$8FFF` for direct `BeebHuffData` access) |

### `ACCCON` (`$FE34` — Write-Only, Tracked in `beeb_acccon_shadow`)

| Bit | Mask | Name | Gameplay State (`$01`) | `LYNNE` Screen / Font / Shadow Access State (`$05`) |
| ---: | --- | --- | --- | --- |
| `0` | `$01` | `D` — CRTC Displays Shadow RAM `LYNNE` (`$3000-$7FFF`) | `1` (CRTC displays `LYNNE`) | `1` (CRTC displays `LYNNE`) |
| `1` | `$02` | `E` — VDU Driver (`$C000-$DFFF`) Accesses `LYNNE` | `0` (`WRCHV` redirected to `rts`) | `0` |
| `2` | `$04` | `X` — All CPU Accesses to `$3000-$7FFF` Route to `LYNNE` | `0` (CPU sees Main RAM `$3000-$7FFF`) | `1` (CPU sees `LYNNE` `$3000-$7FFF`: font, char shadow, gen scratch, Mode 0 bitmap) |
| `3` | `$08` | `Y` — `HAZEL` 8 KB RAM Mapped at `$C000-$DFFF` | `0` (MOS VDU ROM visible; DFS manages `Y` during `OSFILE`/`OSGBPB`) | `0` |
| `4..5` | `$30` | `ITU` / `IFJ` | `0` | `0` |
| `6` | `$40` | `TST` — Hardware Test Mode | `0` (**Never set**) | `0` |
| `7` | `$80` | `IRR` — Generate CPU IRQ | `0` (**Never set**) | `0` |

---

## 2. Critical Hardware Invariants

1. **MOS IRQ `ROMSEL` Shadow Restoration (`$00F4`) & Fast Transient Switching:**
   Acorn MOS 3.20 maintains a zero-page shadow of `ROMSEL` at `$00F4`. Whenever
   a hardware IRQ occurs (100 Hz System VIA Timer 1, VSYNC, keyboard, or
   SN76489 sound/envelope processing), the MOS IRQ dispatcher restores `$FE30`
   from `$00F4` before `RTI`. Therefore:
   * Persistent bank changes must update **both** `$00F4` and `$FE30` under
     `PHP : SEI ... PLP`.
   * Transient bank switches inside `mmu_safe_map_read_ptr0/1`,
     `mmu_safe_map_write_ptr0/1`, `mmu_safe_map_read_block`,
     `mmu_safe_huff_read_ptr0/1`, and Sideways RAM cache copy routines
     (`beeb_swr_copy_to_window`) execute with interrupts masked
     (`PHP : SEI ... PLP`) and restore `$FE30 = $04` (`ROMSEL_BANK4`) before `PLP`.
2. **Low-RAM Execution Requirement (`< $3000`) for All `ACCCON` and `ROMSEL` Switchers:**
   * Setting `ACCCON` (`$FE34`) bit 2 (`X = 1`, `ACCCON = $05`) replaces Main RAM
     across `$3000-$7FFF` with Shadow Screen RAM (`LYNNE`).
   * Setting `ROMSEL` (`$FE30`) to `$05`, `$06`, or `$07` replaces Sideways Bank 4
     (`$8000-$BFFF`, which hosts `BeebPlaySlot` at `$8000-$A3FF` and the active
     overlay at `$A800-$BFFF`).
   * Therefore, **every routine that touches `ACCCON` or `ROMSEL`** (`screen.s`,
     `dungeon_render.s`, `memory_bank.s`, `overlay_storage.s`, `storage.s`, and
     `save_stream.s`) **must link and execute strictly below `$3000`**
     (`$0E00-$2FFF`), enforced at link time by
     `.assert "Low helpers stay below $3000", low_helpers_end <= $3000, true`
     and at build time by `platforms/bbcmaster/check_memory_contract.py`.
3. **MOS VDU Silencing (`WRCHV` `$020E-$020F` & Software Cursor Disable):**
   With `ACCCON = $01` (`E = 0`), any call into the MOS VDU driver (`$C000-$DFFF`)
   via `OSWRCH` would write screen pixels into **Main RAM `$3000-$7FFF`**,
   corrupting `MORIA8.RES`, and the MOS 100 Hz software cursor timer would XOR
   bytes at `$3000+`. Therefore, `screen_init` (`< $3000`):
   * Disables the MOS 100 Hz software cursor and hardware cursor via `VDU 23,1,0;0;0;0;`
     and CRTC `R10 = $20`.
   * Redirects `WRCHV` (`$020E-$020F`) to `beeb_wrch_noop` (`rts` in `< $3000`)
     so no stray `OSWRCH` call from MOS or DFS can ever write to `$3000-$7FFF`.
4. **MOS Filing System `BRKV` (`$0202-$0203`) Fault Trapping, `Y=0` Error Byte, & `HAZEL` Cleanup:**
   Acorn MOS filing systems (DFS 2.24 / ADFS) report disk errors (`File not found`
   `$D6`, `Disc full` `$C6`, `Write protect` `$C8`/`$C9`, `Drive fault` `$C7`) by
   executing a software `BRK`, vectoring through `BRKV` (`$0202-$0203`) with the
   fault pointer at `$00FD-$00FE` (**where `Y = 0` is the error number byte and
   `Y >= 1` is the ASCII error string**) while DFS may still have `HAZEL`
   (`ACCCON` bit `Y = $08`) and the DFS ROM paged in. Therefore:
   * All filenames passed to `OSFILE` / `OSFIND` must be **`$0D` (CR) terminated**.
   * `EnterMos` / `ExitMos` (in `< $3000`) save and restore `$0002-$00AF`
     (`ZP_SAVE_SIZE = 174` B via `save_zp`/`restore_zp`), and the storage wrappers
     (`beeb_call_osfile`/`beeb_call_osfind`/`beeb_call_osgbpb`/`beeb_call_osword7f`)
     record the CPU stack pointer (`TSX : STX beeb_mos_saved_sp`) with `BRKV`
     (`$0202-$0203`) pointing to `beeb_brk_handler` (in `< $3000`).
   * If DFS triggers a `BRK`, `beeb_brk_handler` reads the error code via
     **`LDY #$00 : LDA ($FD),Y`**, forces `ACCCON = $01` (clearing `HAZEL` bit `Y`
     and `LYNNE` bit `X`), unwinds `SP` to `beeb_mos_saved_sp`, and returns `SEC`
     to the wrapper, which then exits cleanly through `ExitMos` (`ROMSEL = $04`,
     `restore_zp`).
5. **Separate Save Disk Enforcement & In-Place Update (`OSFIND A=$C0`) for Pre-Allocated 64-Sector DFS Save Slots:**
   Saves are **strictly forbidden on the Program Disk** (`build/moria8-bbcmaster.ssd`
   never carries `MORIAID`, `HISCORE`, or `SAVE0`..`SAVE3`). Whenever a save,
   load, or high-score write targets `save_device`, `disk_require_save_media`,
   `disk_prepare_selected_save_media`, and `hal_storage_open` (`!open_write`)
   reject any disk containing `TITLE` (`disk_program_media_present` ->
   `"Program disk cannot hold saves."`, `HAL_STORAGE_STATUS_WRONG_MEDIA`,
   `disk_status = 3`) and require a dedicated Save Disk carrying `MORIAID`
   (`"M8SAVE"`).
   Acorn DFS stores files as contiguous sector extents and does not compact
   free gaps automatically when `OSFIND A=$80` deletes an existing file in the
   middle of the catalog. To prevent `Can't extend` / `Disc full` fragmentation
   on the Save Disk:
   * `disk_marker_init` (and `tools/make_ssd.py --blank-disk` for uninitialized
     media) initializes a Save Disk on `save_device` (`:0`..`:3`) with `MORIAID`
     (`"M8SAVE"`), and `hal_storage_open` pre-allocates a 1-sector (`256` B,
     `$0100`) `HISCORE` file and contiguous 64-sector (`16,384` B, `$4000`) save
     slot files (`SAVE0`..`SAVE3`) via `OSFILE A=$07` on first write.
   * When opening an existing save slot for writing, `save_stream.s` opens it
     with **`OSFIND A=$C0` (open for random-access read/write update)** and
     writes sequential chunks at `stream_off0..2` (`OSGBPB A=$01`) so saves
     overwrite the pre-allocated contiguous sectors in place.

---

## 3. Complete 128 KB Memory Map

### 3.1 Unbanked Main RAM (`$0000-$7FFF`, 32 KB)

| Address Range | Size | Owner | Notes |
| --- | ---: | --- | --- |
| `$0000-$0001` | 2 B | Scratch / Reserved | Unused by MOS during application execution |
| `$0002-$008F` | 142 B | Shared Core ZP (`core/zeropage.s`) | Application zero-page owned by game logic |
| `$0090-$00AF` | 32 B | Platform ZP (`platforms/bbcmaster/memory.s`) | `$0090` = `zp_kernal_status`; `$0091-$00AF` = named bank/blit/stream pointers (saved around MOS storage calls) |
| `$00B0-$00FF` | 80 B | Acorn MOS 3.20 & DFS 2.24 ZP | Untouched by game (`$00F4` = MOS `ROMSEL` shadow, `$00FD-$00FE` = MOS `BRK` fault pointer) |
| `$0100-$01FF` | 256 B | Hardware Stack | Always unbanked |
| `$0200-$03FF` | 512 B | Acorn MOS Vectors, Event/Timer State, & Sound/Keyboard Buffers | `WRCHV` (`$020E`) -> `beeb_wrch_noop`; `BRKV` (`$0202`) hooked during storage I/O |
| `$0400-$04FF` | 256 B | `FLOOR_ITEM_BASE` | Active level floor-item table (Language Workspace page 0) |
| `$0500-$05FF` | 256 B | `CREATURE_BASE` | Runtime creature/RLE/high-score scratch (Language Workspace page 1) |
| `$0600-$063F` | 64 B | `PLATFORM_HD_DECODE_BUF_BASE` | Huffman decode scratch buffer |
| `$0640-$0680` | 65 B | `DUNGEON_GEN_DOOR_SCAN_BASE` | Dungeon-generator door-scan scratch (`$0640-$0680`) |
| `$0681-$06FF` | 127 B | MOS Control Blocks (`OSFILE` 18 B, `OSGBPB` 13 B, `OSWORD` 8 B, `OSARGS` 4 B) & Platform State | Unbanked low-RAM parameter blocks |
| `$0700-$07FF` | 256 B | `beeb_ss_buf` | Shared 256-byte save/load stream buffer & `beeb_swr_copy_to_window` page-bounce buffer |
| `$0800-$0DFF` | 1,536 B | Acorn MOS Sound/Envelope/Serial/CFS Workspace (`PAGE = $0E00`) | Preserved untouched for MOS `OSWORD A=7/8` and `OSBYTE` |
| `$0E00-$2FFF` | 8,704 B | Low Always-Resident Code (`< $3000`) | Entry point (`$0E00`), `screen.s`, `dungeon_render.s`, `memory_bank.s`, `storage.s`, `save_stream.s`, `sound.s`, `input.s`, and `zp_save_buf` (174 B) |
| `$3000-$7FFF` | 20,480 B | High Always-Resident Code (`MORIA8.RES` continuation) | Core resident modules (`program_end <= $8000`; total `$0E00-$7FFF` budget = `29,184` B) |

### 3.2 Shadow Screen RAM `LYNNE` (`$3000-$7FFF`, 20 KB — `ACCCON = $05`)

Because `beeb_font_table`, `DUNGEON_GEN_SCAN_SCRATCH_BASE`, and `beeb_char_shadow`
all live in off-screen `LYNNE` (`$3000-$43FF`), they consume **zero bytes of Main
RAM**, and the Mode 0 blitter (`< $3000`, running with `ACCCON = $05`) accesses
the font, character shadow, and screen bitmap in a single unified address space:

| `LYNNE` Address | Size | Owner & Lifecycle |
| --- | ---: | --- |
| `$3000-$33FF` | 1,024 B | **`beeb_font_table` (`128 × 8` B)** — C64-screen-code-ordered 8×8 glyph table initialized at boot from MOS 3.20 Sideways ROM Bank 15 (`$B900-$BBFF`). Read directly while `ACCCON = $05`. |
| `$3400-$37FF` | 1,024 B | **`DUNGEON_GEN_SCAN_SCRATCH_BASE`** — Page-aligned 1 KB dungeon-generation scan scratch (never touches the visible screen bitmap!). |
| `$3800-$3F7F` | 1,920 B | **`beeb_char_shadow` (`80 × 24` B)** — Screen-code character shadow buffer (`$3800 + row * 80 + col`). Enables instant dirty-cell skip in `dungeon_render` and direct RAM screen inspection by the MAME Lua harness without pixel decoding. |
| `$3F80-$43FF` | 1,152 B | **Unassigned Guard / Slack** — `1,152` B safety buffer below the active screen bitmap. |
| `$4400-$7FFF` | 15,360 B | **Active `80×24` Mode 0 Screen Bitmap** (`640×192`, `24` rows × `640` B/row, CRTC `R12=$08, R13=$80`). |

### 3.3 Private 4 KB RAM `ANDY` (`$8000-$8FFF`, 4 KB — `ROMSEL = $84`)

| `ANDY` Address | Size | Link Address | Owner & Lifecycle |
| --- | ---: | --- | --- |
| `$8000-$8D93` | 3,476 B | `$8000-$8D93` | **`BeebHuffData` (`beeb.huffdata`)** — Preloaded at boot: Huffman trees and compressed string corpus. Linked directly at physical `$8000-$8D93` (`620` B slack below `$9000`) and read via `mmu_safe_huff_read_ptr0/1` (`ROMSEL = $84`) with zero address arithmetic while keeping Bank 4 upper 12 KB (`$9000-$BFFF`) mapped. |
| `$8D94-$8FFF` | 620 B | N/A | **Free `ANDY` Slack** (`620` B headroom for Huffman corpus expansion). |

### 3.4 Sideways RAM Banks 4–7 (`$8000-$BFFF`, 4 × 16 KB = 64 KB — `ROMSEL = $04..$07`)

| Bank | Physical Range | Pages / Size | Virtual / Link Address | Owner & Headroom |
| ---: | --- | ---: | --- | --- |
| **Bank 4** (`$04`) | `$8000-$A3FF` | 36p (`9,216` B) | `$8000-$A3FF` | **`BeebPlaySlot` (`BEEB.PLAY`)** — Preloaded at boot; permanently resident in Bank 4 (`~8,500` B used, **`~700` B slack**). |
| **Bank 4** (`$04`) | `$A400-$A7FF` | 4p (`1,024` B) | `$A400-$A7FF` | **`PLATFORM_TIER_NAME_POOL_BASE`** — Active monster tier name pool (`808` B max used, **`216` B slack**). |
| **Bank 4** (`$04`) | `$A800-$BFFF` | 24p (`6,144` B) | `$A800-$BFFF` | **Active Overlay & Monster Tier Window (`BANKED_DATA_BASE = $A800`, `BANKED_DATA_END = $BFFF`)** — All 12 overlays (`<= 5,337` B) and 4 tiers (`<= 2,062` B) link at `$A800` (**`807` B slack** over largest overlay). |
| **Bank 5** (`$05`) | `$8000-$B30B` | 52p (`13,068` B) | `$8000-$B30B` | **Live 198×66 Dungeon Map (`MAP_BASE = $8000`, `MAP_END = $B30B`)** — Direct 1:1 addressing inside Bank 5 (`$B30C-$B3FF` = `244` B map guard). |
| **Bank 5** (`$05`) | `$B400-$BDFF` | 10p (`2,560` B) | Cache Slot | **Cached `OVL.UI`** (`1,387` B used — Character Sheet, Inventory, Equipment; **`1,173` B slack**) + **`$BE00-$BFFF` (`2` pages = `512` B) free Bank 5 slack**. |
| **Bank 6** (`$06`) | `$8000-$96FF` | 23p (`5,888` B) | `$6000-$76FF` | **`BeebAuxData` (`BEEB.AUX`)** — Preloaded at boot: `hal_ego_suffix_slots` (page-aligned at `$6000`), item-name streams, store inventory/runtime, recall arrays, spell tables/names, `msg_history` (`~5,170` B used, **`718` B free slack**). |
| **Bank 6** (`$06`) | `$9700-$ACFF` | 22p (`5,632` B) | Cache Slot | **Cached `OVL.TOWN`** (`5,328` B used, **`304` B slack**). |
| **Bank 6** (`$06`) | `$AD00-$B9FF` | 13p (`3,328` B) | Cache Slot | **Cached `OVL.MODAL`** (`3,072` B used, **`256` B slack**). |
| **Bank 6** (`$06`) | `$BA00-$BFFF` | 6p (`1,536` B) | free | **Free Bank 6 slack.** `MONSTER.DB1` was cached here until 2026-10-25, when tier 1 gained 30 DL 1-5 creatures (about 2,000 B, past bank 6's free pages): all four monster tiers now load from DFS into the Bank 4 window. |
| **Bank 7** (`$07`) | `$8000-$94FF` | 21p (`5,376` B) | Cache Slot | **Cached `OVL.SPELL`** (`5,112` B used, **`264` B slack**). |
| **Bank 7** (`$07`) | `$9500-$A9FF` | 21p (`5,376` B) | Cache Slot | **Cached `OVL.ITEMS`** (`5,106` B used, **`270` B slack**). |
| **Bank 7** (`$07`) | `$AA00-$BEFF` | 21p (`5,376` B) | Cache Slot | **Cached `OVL.GEN`** (`5,320` B used, **`56` B slack**; holds `item_spawn_level` since item stacking left the resident image no room) + **`$BF00-$BFFF` (`1` page = `256` B) free Bank 7 slack**. |

* **Disk-Backed Cold Assets (Loaded on Demand via `OSFILE`):**
  `OVL.START` (`OVLSTA`), `OVL.DEATH` (`OVLDTH`), `OVL.HELP` (`OVLHLP`),
  `OVL.CHEST` (`OVLCHS`), `OVL.STORAGE` (`OVLSTO`), `OVL.TITLE` (`OVLTTL`),
  `MONSTER.DB.2..4` (`MONDB2`..`MONDB4`), and `TITLE` (`TITLE`) load on demand
  from the DFS disk into `$A800-$BFFF` (or `MAP_BASE` `$8000` in Bank 5 for
  `TITLE`), matching the proven Apple IIe partial-cache architecture while
  leaving **`512`–`880` bytes of free growth slack in every single RAM bank**.

---

## 4. Two-Way Banked Data Dispatch & Fast Row Helpers (`< $3000`)

Because `BeebHuffData` is accessed at `$8000-$8D93` in `ANDY` (`ROMSEL = $84`)
via `mmu_safe_huff_read_ptr0/1`, `mmu_safe_map_read_ptr0/1` and
`mmu_safe_map_write_ptr0/1` only ever service two banked regions:

1. **Fast Path — Live 198×66 Map (`zp_ptr_hi >= $80`, tested via `LDA zp_ptr_hi : BPL`):**
   * Under `PHP : SEI ... PLP`, maps Sideways Bank 5 (`ROMSEL = $05`), accesses
     `(zp_ptr),y` directly with **zero address math**, restores `ROMSEL = $04`,
     and returns with `N`/`Z` reflecting the loaded byte (`43` cycles total).
   * Bulk helper `mmu_safe_map_read_block` switches `ROMSEL = $05` once per
     78-byte viewport row in `render_viewport`.
2. **`BeebAuxData` Path (`$60 <= zp_ptr_hi < $77` in Sideways Bank 6):**
   * Checks `zp_ptr_hi >= $60`, adds `$20` (`BEEB_AUXDATA_PHYS_OFFSET`) into the
     dedicated platform zero-page pointer `beeb_aux_ptr` (`$a2-$a3`, never
     mutating `zp_ptr0`/`zp_ptr1` in place), switches `ROMSEL = $06` under
     `PHP : SEI ... PLP`, reads/writes `(beeb_aux_ptr),y` in Bank 6, and restores
     `ROMSEL = $04`.

---

## 5. Verification Gates

| Gate | Command | Scope |
| --- | --- | --- |
| **Memory Contract Self-Test** | `make testbbcmaster-memory-contract-selftest` | Unit-tests `check_memory_contract.py` and `tools/make_ssd.py` |
| **Static Memory Contract Gate** | `make testbbcmaster-memory-contract` | Verifies every emitted PRG extent, `< $3000` low-helper ceiling, `$8000` resident ceiling, Bank 4/5/6/7 cache slot bounds, and absence of foreign platform symbols |
| **Runtime MAME Smoke Suite** | `make testbbcmaster-runtime` | Runs headless MAME `bbcm` (`platforms/bbcmaster/harness_smoke.py`, gated by `BBCMROMS`) across the behavioral scenario suite within the 30s timeout cap |
