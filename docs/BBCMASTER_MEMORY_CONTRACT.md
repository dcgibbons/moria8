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
   restore `$FE30` from `$00F4` before `RTI`. Therefore:
   * **Every** `SHEILA_ROMSEL` (`$FE30`) write across `platforms/bbcmaster/`
     (persistent bank switches in `EnterMos`/`ExitMos`,
     `hal_memory_restore_runtime`, `beeb_require_play`, `hal_platform_init_early`,
     `beeb_platform_runtime_resync`; transient switches in `save_zp`/`restore_zp`,
     `mmu_safe_huff_read_ptr0/1`, `mmu_safe_map_read_ptr0/1`,
     `mmu_safe_map_write_ptr0/1`, `mmu_safe_map_read_block`,
     `beeb_swr_copy_to_window`, `beeb_font_init`, `screen_init`, and
     `beeb_dfs_load_to_bank`; plus pre-runtime `boot.s` `$00F4` handoff) must
     update **both** `zp_mos_romsel_shadow` (`$00F4`) and `SHEILA_ROMSEL`
     (`$FE30`) immediately in sequence inside an `SEI` critical section
     (`PHP : SEI ... PLP` or `SEI ... CLI`) and restore `ROMSEL = $04`
     (`ROMSEL_BANK4`) on exit from transient runtime accesses before `PLP`.
     Enforced statically by `validate_romsel_sync` in
     `platforms/bbcmaster/check_memory_contract.py`.
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
| `$0E00-$2FFF` | 8,704 B | Low Always-Resident Code (`< $3000`) | Entry point (`$0E00`), `screen.s`, `dungeon_render.s`, `memory_bank.s`, `storage.s`, `save_stream.s`, `sound.s`, `input.s`, and `item_cat_beeb.s` (`low_helpers_end` = `$2353`, `5,459` B used, **`3,245` B free** below `$3000`; `zp_save_buf` relocated to `ANDY` `$8F00-$8FAD`) |
| `$3000-$7FFF` | 20,480 B | High Always-Resident Code (`MORIA8.RES` continuation) | Core resident modules & generated resident trampolines (`build/trampolines/bbcmaster_trampolines.inc`, `program_end` = `$7FDC`, **`36` B free** below `$8000`; total `$0E00-$7FFF` budget = `29,184` B, `29,148` B used) |

### 3.2 Shadow Screen RAM `LYNNE` (`$3000-$7FFF`, 20 KB — `ACCCON = $05`)

Because `beeb_font_table`, `DUNGEON_GEN_SCAN_SCRATCH_BASE`, `beeb_char_shadow`,
and `BeebLynneAux` all live in off-screen `LYNNE` (`$3000-$43FF`), they consume
**zero bytes of Main RAM**, and the `< $3000` helpers (`screen.s`,
`dungeon_render.s`, and `memory_bank.s`, running with `ACCCON = $05` under
`PHP : SEI ... PLP`) access the font, character shadow, persistent `LYNNE` aux
arrays, and screen bitmap in a single unified address space:

| `LYNNE` Address | Size | Owner & Lifecycle |
| --- | ---: | --- |
| `$3000-$33FF` | 1,024 B | **`beeb_font_table` (`128 × 8` B)** — C64-screen-code-ordered 8×8 glyph table initialized at boot from MOS 3.20 Sideways ROM Bank 15 (`$B900-$BBFF`). Read directly while `ACCCON = $05`. |
| `$3400-$37FF` | 1,024 B | **`DUNGEON_GEN_SCAN_SCRATCH_BASE`** — Page-aligned 1 KB dungeon-generation scan scratch (never touches the visible screen bitmap!). |
| `$3800-$3F7F` | 1,920 B | **`beeb_char_shadow` (`80 × 24` B)** — Screen-code character shadow buffer (`$3800 + row * 80 + col`). Enables instant dirty-cell skip in `dungeon_render` and direct RAM screen inspection by the MAME Lua harness without pixel decoding. |
| `$3F80-$43FF` | 1,152 B | **`BeebLynneAux` (`recall_data_start..recall_data_end`, virtual segment)** — Persistent off-screen aux storage below the Mode 0 bitmap (`$4400`). Hosts mutable 279-species monster-recall counters (`recall_kills`, `recall_deaths`, `recall_attacks`, `recall_spells`, **`1,116` B** at `$3F80-$43DB`, leaving **`36` B free** in `$43DC-$43FF`, 2026-11-15 Phase 4). Zero-initialized once at boot in `beeb_font_init` (never in `screen_clear`); accessed via `mmu_safe_map_read_ptr0/1` and `mmu_safe_map_write_ptr0/1` (`ACCCON = $05`, restored to `$01`). |
| `$4400-$7FFF` | 15,360 B | **Active `80×24` Mode 0 Screen Bitmap** (`640×192`, `24` rows × `640` B/row, CRTC `R12=$08, R13=$80`). |

### 3.3 Private 4 KB RAM `ANDY` (`$8000-$8FFF`, 4 KB — `ROMSEL = $84`)

| `ANDY` Address | Size | Link Address | Owner & Lifecycle |
| --- | ---: | --- | --- |
| `$8000-$8EDC` | 3,805 B | `$8000-$8EDC` | **`BeebHuffData` (`beeb.huffdata`)** — Preloaded at boot: Huffman trees and compressed string corpus (`ovl_huffdata_end = $8EDD <= $8F00`, **`35` B slack** below `zp_save_buf`). Read via `mmu_safe_huff_read_ptr0/1` (`ROMSEL = $84`) while keeping Bank 4 upper 12 KB (`$9000-$BFFF`) mapped. |
| `$8EDD-$8EFF` | 35 B | N/A | **Corpus Expansion Slack below `zp_save_buf`**. |
| `$8F00-$8FAD` | 174 B | `$8F00` (`BEEB_ZP_SAVE_BASE`) | **`zp_save_buf` (`ZP_SAVE_SIZE = 174` B)** — Zero-page save buffer (`$0002-$00AF`) managed by `save_zp` / `restore_zp` (`< $3000`) under `PHP : SEI ... PLP` with `ROMSEL_ANDY = $84`. `EnterMos` calls `save_zp` before switching to `beeb_boot_romsel`, and `ExitMos` restores `ROMSEL_BANK4` before calling `restore_zp`. |
| `$8FAE-$8FFF` | 82 B | N/A | **Free `ANDY` Top Slack** above `zp_save_buf`. |

MOS 3.20 keeps VDU workspace in `ANDY` too: a mode change (`VDU 22`) writes
its default ECF patterns (`VDU 23,2-5`) at `$8800-$882F`, inside the corpus.
`screen_init` (`screen.s`) issues the game's only mode change after boot has
loaded the corpus, so it keeps those 48 bytes across its MOS calls
(`beeb_andy_mos_keep`) and then silences `WRCHV`, so no later VDU call reaches
`ANDY` (2026-11-06: strings there, "Identify which item" among them, decoded
wrong). `item_actions` checks the bytes against `beeb.huffdata` in town.

### 3.4 Sideways RAM Banks 4–7 (`$8000-$BFFF`, 4 × 16 KB = 64 KB — `ROMSEL = $04..$07`)

| Bank | Physical Range | Pages / Size | Virtual / Link Address | Owner & Headroom |
| ---: | --- | ---: | --- | --- |
| **Bank 4** (`$04`) | `$8000-$A3FF` | 36p (`9,216` B) | `$8000-$A3FF` | **`BeebPlaySlot` (`BEEB.PLAY`)** — Preloaded at boot; permanently resident in Bank 4 (`9,210` B used, **`6` B slack**, 2026-11-15 Phase 4). |
| **Bank 4** (`$04`) | `$A400-$A7FF` | 4p (`1,024` B) | `$A400-$A7FF` | **`PLATFORM_TIER_NAME_POOL_BASE`** — The monster catalog's 32 species names (32 B each, 2026-11-05). |
| **Bank 4** (`$04`) | `$A800-$BFFF` | 24p (`6,144` B) | `$A800-$BFFF` | **Active Overlay & Monster Tier Window (`BANKED_DATA_BASE = $A800`, `BANKED_DATA_END = $BFFF`)** — All 13 overlays (`<= 5,721` B, incl. `OVL.HOME` `5,315` B) link at `$A800` (**`423` B slack** over largest overlay `OVL.ITEMS`). |
| **Bank 5** (`$05`) | `$8000-$B30B` | 52p (`13,068` B) | `$8000-$B30B` | **Live 198×66 Dungeon Map (`MAP_BASE = $8000`, `MAP_END = $B30B`)** — Direct 1:1 addressing inside Bank 5 (`$B30C-$B3FF` = `244` B map guard). |
| **Bank 5** (`$05`) | `$B400-$BFFF` | 12p (`3,072` B) | Cache Slot | **Cached `OVL.MODAL`** (`2,429` B used, **`643` B slack**, 2026-11-15 Phase 4). |
| **Bank 6** (`$06`) | `$8000-$92FF` | 19p (`4,864` B) | `$6000-$72FF` | **`BeebAuxData` (`BEEB.AUXDATA`)** — Preloaded at boot: `msg_history`, store inventory/runtime (`si_meta_hi[128]`), `id_known_bits[47]`, `potion_shuffle..staff_shuffle` (`174` B), spell tables/names, and Bank 6 strings (`4,824` B used, **`40` B free slack**; item-name streams replaced by `'ITM2'` `ITEMCAT`, 2026-11-15 Phase 4). |
| **Bank 6** (`$06`) | `$9300-$94FF` | 2p (`512` B) | Cache Slot | **`BEEB_ICAT_B6`** — Preloaded `'ITM2'` `ITEMCAT` header/directory pages (`512` B, 2026-11-15 Phase 4). |
| **Bank 6** (`$06`) | `$9500-$B9FF` | 37p (`9,472` B) | `$9500-$B916` | **The monster catalog (`BEEB.CATALOG`)** — its fields, then its Huffman names (`9,239` B, **`233` B slack**); read through `mmu_safe_huff_read_ptr0/1`, which select Bank 6 for a pointer at `$9000` and up. |
| **Bank 6** (`$06`) | `$BA00-$BFFF` | 6p (`1,536` B) | Cache Slot | **Cached `OVL.UI`** (`1,467` B used, **`69` B slack**). |
| **Bank 7** (`$07`) | `$8000-$94FF` | 21p (`5,376` B) | Cache Slot | **Cached `OVL.SPELL`** (`5,270` B used, **`106` B slack**). |
| **Bank 7** (`$07`) | `$9500-$ABFF` | 23p (`5,888` B) | Cache Slot | **Cached `OVL.ITEMS`** (`5,721` B used, **`167` B slack**; expanded from 22p to 23p in Phase 4, 2026-11-15). |
| **Bank 7** (`$07`) | `$AC00-$BBFF` | 16p (`4,096` B) | Cache Slot | **Cached `OVL.GEN`** (`3,922` B used, **`174` B slack**; resized from 21p to 16p in Phase 4, 2026-11-15). |
| **Bank 7** (`$07`) | `$BC00-$BFFF` | 4p (`1,024` B) | Cache Slot | **`BEEB_ICAT_CACHE`** — 4-page (`1,024` B) LRU sector cache in SWR Bank 7 for `'ITM2'` `ITEMCAT` (`item_cat_beeb.s`, 2026-11-15 Phase 4). |

* **Disk-Backed Cold Assets (Loaded on Demand via `OSFILE`):**
  `OVL.START` (`OVLSTA`), `OVL.TOWN` (`OVLTWN`, since the monster catalog,
  2026-11-05), `OVL.DEATH` (`OVLDTH`), `OVL.HELP` (`OVLHLP`, including
  `ui_help_title.s`), `OVL.CHEST` (`OVLCHS`), `OVL.HOME` (`OVLHOM`, Phase 2
  `HOME_OVERLAY_SEPARATE`, 2026-11-14), `OVL.STORAGE` (`OVLSTO`),
  `OVL.TITLE` (`OVLTTL`), `LEGALUI` (`LEGALUI`),
  and `TITLE` (`TITLE`) load on demand (the monster tiers `MONDB1`..`MONDB4` left
  the disk for the catalog, 2026-11-05)
  from the DFS disk into `$A800-$BFFF` (or `MAP_BASE` `$8000` in Bank 5 for
  `TITLE`), matching the proven Apple IIe partial-cache architecture. Following
  Phase 2 eviction (2026-11-14), Bank 5's `OVL.MODAL` cache slot has `311` B
  spare and Bank 6's catalog span `233` B (the table above).

---

## 4. Three-Way Banked Data Dispatch & Fast Row Helpers (`< $3000`)

Because `BeebHuffData` (`$8000-$8EDC`) and `zp_save_buf` (`$8F00-$8FAD`) live in
`ANDY` (`ROMSEL = $84`) — with `BeebHuffData` read via `mmu_safe_huff_read_ptr0/1`
(which select Bank 6 instead for a pointer at `$9000` and up: the monster
catalog's fields and names, 2026-11-05) and `zp_save_buf` accessed by `save_zp` /
`restore_zp` — `mmu_safe_map_read_ptr0/1` and `mmu_safe_map_write_ptr0/1`
service three banked regions plus Main RAM fallthrough:

1. **Fast Path — Live 198×66 Map (`zp_ptr_hi >= $80`, tested via `LDA zp_ptr_hi : BPL`):**
   * Under `PHP : SEI ... PLP`, maps Sideways Bank 5 (`ROMSEL = $05`, synced to
     `$00F4`), accesses `(zp_ptr),y` directly with **zero address math**,
     restores `ROMSEL = $04` (synced to `$00F4`), and returns with `N`/`Z`
     reflecting reads and `A` preserved on writes.
   * Bulk helper `mmu_safe_map_read_block` switches `ROMSEL = $05` once per
     78-byte viewport row in `render_viewport`.
2. **`BeebAuxData` Path (`$60 <= zp_ptr_hi < $80` in Sideways Bank 6):**
   * Checks `zp_ptr_hi >= $60`, adds `$20` (`BEEB_AUXDATA_PHYS_OFFSET`) into the
     dedicated platform zero-page pointer `beeb_aux_ptr` (`$a2-$a3`, never
     mutating `zp_ptr0`/`zp_ptr1` in place), switches `ROMSEL = $06` (synced to
     `$00F4`) under `PHP : SEI ... PLP`, reads/writes `(beeb_aux_ptr),y` in Bank 6,
     and restores `ROMSEL = $04`.
3. **`BeebLynneAux` Path (`$3F80-$43FF` in Shadow RAM `LYNNE`):**
   * Checks `[BEEB_LYNNE_AUX_BASE, BEEB_LYNNE_AUX_LIMIT)` (`$3F80-$43FF`),
     switches `SHEILA_ACCCON` + `beeb_acccon_shadow` to `ACCCON_LYNNE` (`$05`)
     under `PHP : SEI ... PLP`, reads/writes `(beeb_aux_ptr),y` in `LYNNE`, and
     restores `ACCCON_NORMAL` (`$01`) before `PLP`.
4. **Main RAM Fallthrough (otherwise):**
   * Restores caller flags via `PLP` and accesses `(beeb_aux_ptr),y` in Main RAM.

---

## 5. Verification Gates

| Gate | Command | Scope |
| --- | --- | --- |
| **Memory Contract Self-Test** | `make testbbcmaster-memory-contract-selftest` | Unit-tests `check_memory_contract.py` and `tools/make_ssd.py` |
| **Static Memory Contract Gate** | `make testbbcmaster-memory-contract` | Verifies every emitted PRG extent, `< $3000` low-helper ceiling, `$8000` resident ceiling, Bank 4/5/6/7 cache slot bounds, and absence of foreign platform symbols |
| **Runtime MAME Smoke Suite** | `make testbbcmaster-runtime` | Runs headless MAME `bbcm` (`platforms/bbcmaster/harness_smoke.py`, gated by `BBCMROMS`) across the behavioral scenario suite within the 30s timeout cap. `boot_title` boots from the disk (about 75 emulated seconds of DFS reads); every other scenario fast-boots, putting the disk's own `MORIA8P` entries where `boot.s`'s tables put them and finishing as the loader does from a stub at `&900` (`--real-boot` boots each from the disk) |

## License/source modal ownership (2026-11-10)

`LEGALUI` is an uncached modal loaded on title `A` (About) or Help `L`: Sideways Bank 4 $A800-$BFFF; no persistent cache allocation.
Code ends before overlay base+$600; a 142-byte core-ZP snapshot starts there,
and the disk/ROM input cache occupies base+$700..+$7FF. Both are modal
workspace, never game-data loans or emitted PRG padding. The resident entry saves core ZP before asset loading, after any media
handler that may itself load an overlay.
The viewer reads existing documents through the storage HAL, closes every
channel, retains live sound/redraw state, and restores the caller snapshot.
Linked payload bounds and production-path modal entry/return tests enforce
this ownership. See `docs/LEGAL_VIEWER.md` for the change and verification record.

Verification (2026-11-10): `make -j7 -O test` passed, including the memory-
contract self-tests, emitted payload/disk checks, and MAME title/Help legal-
viewer and save/load scenarios. No ANDY, LYNNE or persistent Sideways cache
allocation changes.

Optional legal loads retain bounded asset retries, then offer Escape at the
resident program-disk prompt. One caller snapshot survives every retry. Escape
restores ZP after the prompt and returns with carry set; Help exits directly to
gameplay, and Title redraws only its resident menu. Neither return reloads the
invalidated overlay while the program disk is absent. No Storage overlay or
unavailable play-slot verifier is called. See the Pass 3 record in
`docs/LEGAL_VIEWER.md` for the save-disk, retry and cancel-boundary tests.

Repair verification (2026-11-11): `make -j7 -O test` passed. Applicable payload
bounds, header/load/execution ownership, missing-file cleanup and production
modal-return rows are complete; see `docs/LEGAL_VIEWER.md` for linked spans and
coverage. Existing banking configurations and persistent cache owners remain;
physical display-layout changes are N/A.


Pass 3 verification (2026-11-11): `make -j7 -O test` passed. The added
save-disk fixtures verify cold Title cancellation to its resident menu,
Help cancellation to gameplay without a cold reload, failed/successful retry
snapshot survival and restored core ZP at the cancel-return boundary. All
linked bounds and the existing bank/cache owners remain enforced. See
`docs/LEGAL_VIEWER.md` for the carry contract and physical media preconditions.

---

## Phase 1 Port-Local Memory Unlocks (2026-11-14)

### Change Record

```text
Problem and success criteria:
  Default Main RAM (< $8000) had 17 B free ($7FEF) and Bank 6 BeebAuxData had 34 B free ($74DE), while ANDY ($8F00-$8FFF) and LYNNE ($3F80-$43FF, 1,152 B below Mode 0 bitmap $4400) had unused capacity, and several runtime SHEILA_ROMSEL writes skipped syncing $00F4 or lacked SEI masking. Relocate zp_save_buf (174 B) into ANDY ($8F00-$8FAD), relocate recall_* (160 B, reserving 1,116 B room) into LYNNE ($3F80-$43FF) via virtual segment BeebLynneAux with zero core/ edits, enforce SEI+$00F4 sync on every SHEILA_ROMSEL write, and keep all BBC Master build/contract/runtime gates green.
State being changed:
  - zp_save_buf moved from Main RAM (< $3000) to ANDY $8F00-$8FAD under save_zp/restore_zp (ROMSEL_ANDY under PHP:SEI..PLP).
  - recall_data_start..recall_data_end moved from Bank 6 BeebAuxData to virtual segment BeebLynneAux ($3F80-$401F inside LYNNE $3F80-$43FF), zeroed once at boot in beeb_font_init and dispatched through mmu_safe_map_read_ptr0/1 & mmu_safe_map_write_ptr0/1 (ACCCON_LYNNE -> ACCCON_NORMAL under PHP:SEI..PLP).
  - beeb_ego_suffix_slots moved to start of BeebAuxData ($6000-$60FF) eliminating mid-segment .align $100 padding waste.
  - Every SHEILA_ROMSEL write in platforms/bbcmaster/ updates zp_mos_romsel_shadow/$00F4 under SEI.
Search scope and terms:
  platforms/bbcmaster/ and core/ searched for SHEILA_ROMSEL, zp_save_buf, save_zp, restore_zp, EnterMos, ExitMos, beeb_andy_, recall_data, MapRead_/AuxRead*/AuxWrite*/AuxIncX/SaveByte*, msg_history, beeb_ego_suffix_slots, beeb_font_init, screen_init.
Relevant readers/writers found and known exclusions:
  - save_zp/restore_zp only called at boot/EnterMos/ExitMos; zp_mos_romsel_shadow ($00F4) sits outside $02-$AF ZP snapshot; beeb_acccon_shadow ($9D) is restored to ACCCON_NORMAL before save_zp and reasserted after restore_zp.
  - All AuxRead*/AuxWrite*/AuxIncX and SaveByteRead/Write (when beeb_save_aux_mode_flag bit 7 = 1, set in disk_setup_beeb.s:hal_storage_save_block_mode dynamically for recall_data_start) route through mmu_safe_map_read/write_ptr0/1. No Main RAM caller passes [$3F80, $4400) to mmu_safe_map_*.
  - UI/game code outside platforms/bbcmaster/ was excluded and left untouched.
Initialization, reset and persistence points:
  - beeb_font_init zeroes LYNNE $3F80-$43FF once at boot under PHP:SEI with ACCCON_LYNNE; screen_clear does not touch $3F80-$43FF so recall counters persist in-game and across save/load.
Affected production sequence through the changed transition:
  - EnterMos (PHP:SEI, ACCCON_NORMAL, save_zp -> ANDY $8F00-$8FAD, restore ROMSEL_BANK4, switch beeb_boot_romsel) -> MOS/DFS call -> ExitMos (PHP:PHA:SEI, ROMSEL_BANK4, restore_zp <- ANDY $8F00-$8FAD, ACCCON_NORMAL, PLA:PLP).
  - Aux/Save recall access -> mmu_safe_map_read/write_ptr0/1 -> $3F80-$43FF check -> ACCCON_LYNNE ($05) -> access (beeb_aux_ptr),y -> ACCCON_NORMAL ($01) -> PLP.
Contract decision or selected upstream oracle with source locations:
  - BBC Master 128 hardware banking rules in Sections 1-2 above and platforms/bbcmaster/memory.s.
Intentional Moria8 deviations:
  - N/A (platform-local memory placement; game semantics unchanged).
Input/intermediate widths, signedness, carry, range and overflow policy:
  - 16-bit half-open range check [$3F80, $4400) on zp_ptr0/1; ExitMos preserves caller A, P (Carry), and Y; mmu_safe_map_* preserve X, Y, C, I, D, V (and A on writes; N/Z set on reads); boot clear asserts $3F80 + $0480 == $4400.
RNG reduction and bias, if applicable:
  - N/A (memory banking/layout change only).
Affected platforms, overlays, banks and owners:
  - Acorn BBC Master 128 only: LowHelpers (< $3000), Default (< $8000), ANDY ($8000-$8FFF), LYNNE ($3F80-$43FF), Bank 6 BeebAuxData ($6000-$74FF). Zero core/ or sibling platform changes.
Required production-path tests:
  - make testbbcmaster-memory-contract-selftest
  - make testbbcmaster-memory-contract
  - make diskbbcmaster
  - make testbbcmaster (MAME bbcm runtime scenarios: boot_title, save_load, disk_setup, help_overlay, item_actions, death_flow, balrog_victory, catalog_spawn, etc.)
Known behavior explicitly out of scope:
  - Future expansion of recall[279] (Phase 5) or BeebPlaySlot/OVL.ITEMS headroom work; no core/ modifications.
Unresolved uncertainty and risk:
  - None open after static and MAME runtime verification.
```

### Verification Coverage

| Contract Row / Check | Enforcement & Evidence | Status |
| --- | --- | --- |
| LowHelpers (`< $3000`) & Default (`<= $8000`) ceilings | `memory.s`/`main.s` `.assert`s + `check_memory_contract.py` (`low_helpers_end = $2437`, `program_end = $7F80`, 128 B free) | Verified |
| `ANDY` `zp_save_buf` (`$8F00-$8FAD`) vs `BeebHuffData` (`< $8F00`) | `.assert`s in `memory.s`/`main.s` (`ovl_huffdata_end = $8EDD`) + `check_memory_contract.py` positive & negative tests | Verified |
| `LYNNE` `BeebLynneAux` (`$3F80-$43FF < $4400`) & non-emission into `moria8.res.prg` | `[virtual]` segment + `.assert`s (`recall_data_start = $3F80`, `recall_data_end = $4020`) + `moria8.res.prg` PRG span check | Verified |
| All `SHEILA_ROMSEL` writes sync `$00F4` under `SEI` | Static CFG + adjacent-store check `validate_romsel_sync` + negative `--selftest` cases | Verified |
| `BeebAuxData` & DFS media integrity (`LICENSE`/`SRCOFFR`) | `check_memory_contract.py --disk` on `build/moria8-bbcmaster.ssd` | Verified |
| Live MOS/DFS/ANDY/LYNNE/recall/save-load behavior on MAME `bbcm` | `make testbbcmaster` (all 17 MAME scenarios passed) | Verified |

---

## Phase 2 Cold Code Eviction (2026-11-14)

### Change Record

```text
Problem and success criteria:
  Resident Default (< $8000) had 128 B free ($7F80), BeebPlaySlot (< $A400) had 44 B free ($A3D4), and TownOverlay (ovl.town) had 795 B free, blocking Phase 3+ shared gameplay growth. Enable HOME_OVERLAY_SEPARATE (OVL_HOME = 11 / OVLHOM, standardized IDs 0..13), separate Player Home from TownOverlay, move cold royal/run/re-equip/pflags/title/load code into overlays (Death, Bank 5 SWR-cached Modal, Title, Storage) while relocating potion heal/cure helpers to Default, and recover >= 250 B free in both Default (< $8000) and BeebPlaySlot (< $A400) with zero SWR cache overflow and all contract/runtime checks passing.
State being changed:
  - Standardized BBC Master overlay IDs to match shared Phase 2 numbering: OVL_HOME = 11, OVL_STORAGE = 12, OVL_TITLE = 13 (hal_platform_overlay_count = 13; 14 IDs 0..13 incl. OVL_NONE). Added HomeOverlay (ovl.home -> DFS OVLHOM, 1,294 B) and updated overlay_storage.s cache tables (13 entries) and hal/storage.s name tables.
  - Enabled #define HOME_OVERLAY_SEPARATE; moved core/ui_home.s and core/ui_home_text.s (incl. home_inv_add_carried) from TownOverlay to HomeOverlay while keeping inv_add_carried in TownOverlay; updated tramp_store_enter to dispatch #STORE_HOME to OVL_HOME / home_enter and stores 0..6 to OVL_TOWN / store_enter.
  - Moved core/royal.s (564 B) from SWR-cached ModalMiscOverlay to DeathOverlay and removed the OVL_MODAL_MISC switch from tramp_winner_royal.
  - Moved PlayerRunInitializeSegment (run_initialize_impl, 166 B) from BeebPlaySlot to SWR-cached ModalMiscOverlay behind resident run_initialize, and moved core/player_heal_feedback.s + core/eff_potion_cure.s (113 B) from BeebPlaySlot into Default (directly visible to both OVL.ITEMS and OVL.SPELL).
  - Evicted ReEquipSegment (RE_EQUIP_SEGMENT_CUSTOM, re_equip..re_negate_a, 230 B) and PflagsSegment (PFLAGS_SEGMENT_CUSTOM + PLAYER_RECALC_PFLAGS_EXTERNAL, player_recalc_pflags_equipment + tables, 82 B) from Default into SWR-cached ModalMiscOverlay behind shared overlay-preserving modal_swap_dispatch (tramp_re_equip, hal_player_recalc_pflags).
  - Evicted cold title paths from Default: title_enter_menu_ovl + title_str (+ eliminated redundant title_show_sysinfo wrapper) -> TitleOverlay; title_load_game_ovl -> StorageOverlay.
Search scope and terms:
  platforms/bbcmaster/ and core/ searched for HOME_OVERLAY_SEPARATE, OVL_STORAGE, OVL_TITLE, STORE_HOME, tramp_store_enter, royal_screen, run_initialize, re_equip, roll_enchantment, hal_player_recalc_pflags, PFLAGS_SEGMENT_CUSTOM, eff_potion_healing, eff_potion_heal_cure, pmx_heal_and_report, title_enter_menu, title_load_game, title_show_sysinfo, title_str, current_overlay.
Relevant readers/writers found and known exclusions:
  - current_overlay is updated solely by overlay_load / legal.s and read by modal_swap_dispatch to restore non-zero caller overlays (e.g. OVL_DUNGEON_GEN across re_equip; OVL_ITEMS / OVL_SPELL / OVL_STARTUP across hal_player_recalc_pflags).
  - run_initialize is called only from resident core/game_loop.s:cmd_run and leaves OVL_MODAL_MISC cached-loaded cleanly.
  - title_draw_menu remains resident in Default so Legal 'A' cancel on 1-drive swaps (C=1) still redraws the title menu without requiring the program disk.
  - core/, platforms/shared/, tools/check_hal_*.py, tools/report_memory_budgets.py, and docs/MEMORY_REDESIGN_PLAN.md were left completely untouched.
Initialization, reset and persistence points:
  - Boot MORIA8P preload still caches OVL.MODAL (Bank 5), OVL.UI (Bank 6), and OVL.SPELL/ITEMS/GEN (Bank 7); OVLHOM loads on demand from DFS alongside OVLTWN, OVLSTO, OVLTTL.
  - beeb_ovl_cache_{bank,hi,pages} carry 13 entries matching hal_platform_overlay_count (asserted by BEEB_OVERLAY_TABLE_COUNT == hal_platform_overlay_count).
Affected production sequence through the changed transition:
  - Store/Home entry: try_store_entry -> zp_store_idx -> tramp_store_enter -> STORE_HOME ? overlay_load(OVL_HOME) + home_enter : overlay_load(OVL_TOWN) + store_enter.
  - Wizard/gen/equip calls into OVL.MODAL: caller -> tramp_re_equip / hal_player_recalc_pflags -> modal_swap_dispatch (fast jmp if current_overlay == OVL_MODAL_MISC; else push caller, overlay_load(OVL_MODAL_MISC), jsr target, tay, restore caller if != 0, tya, rts).
  - Victory screen: tramp_winner_royal -> overlay_load(OVL_DEATH) -> jsr winner_apply_retirement_bonus_overlay -> jmp royal_screen (no OVL_MODAL_MISC swap).
  - Running init: cmd_run -> jsr run_initialize -> overlay_load(OVL_MODAL_MISC) -> jmp run_initialize_impl.
Contract decision or selected upstream oracle with source locations:
  - Phase 2 overlay ID standardization and cold eviction plan (docs/MEMORY_REDESIGN_PLAN.md §4.2, §5, §6; shared core/ui_home.s under HOME_OVERLAY_SEPARATE).
Intentional Moria8 deviations:
  - N/A (code/overlay placement and trampolines only; game mechanics and player-visible strings unchanged).
Input/intermediate widths, signedness, carry, range and overflow policy:
  - modal_swap_dispatch preserves return A across restore (tay/tya) and skips restore when caller current_overlay == 0 (OVL_NONE); overlay_load failure on OVL_MODAL_MISC pops saved overlay byte and returns A=0.
  - Overlay IDs stay 1..13; DFS catalog fits 15/31 entries and 416/800 sectors on moria8-bbcmaster.ssd (retaining LICENSE and SRCOFFR).
RNG reduction and bias, if applicable:
  - N/A (re_equip and run_initialize continue calling the unchanged resident RNG routines).
Affected platforms, overlays, banks and owners:
  - Acorn BBC Master 128 only: Default ($0E00-$7EBD, 323 B free), BeebPlaySlot ($8000-$A2BD, 323 B free), LowHelpers ($0E00-$2446, 3,002 B free), Bank 5 cache.ovl.modal ($0000-$0AC9, 311 B free), ovl.death (4,543 B, 1,601 B free), ovl.town (4,438 B, 1,706 B free), ovl.home (1,294 B, 4,850 B free), ovl.storage (3,800 B, 2,344 B free), ovl.title (278 B, 5,866 B free).
Required production-path tests:
  - make -C platforms/bbcmaster build disk test-memory-contract
  - make check-hal-boundaries check-6502-lint
  - ./tools/isolated.sh make -C platforms/bbcmaster test-runtime (MAME bbcm full runtime suite)
Known behavior explicitly out of scope:
  - OVL.ITEMS (38 B SWR slack) and BeebHuffData (35 B ANDY slack) were not modified; harness_smoke.py was left unchanged (no MAME Home door walkthrough scenario exists yet).
Unresolved uncertainty and risk:
  - None open for the implemented changes after static contract checks and MAME bbcm verification; Home entry runtime path is guarded by static placement .asserts and shared core/ui_home.s contract, while interactive MAME Home entry awaits Phase 3+ harness additions.
```

### Verification Coverage

| Contract Row / Check | Enforcement & Evidence | Status |
| --- | --- | --- |
| Default (`< $8000`) & BeebPlaySlot (`< $A400`) headroom (`>= 250+ B` free) | `main.s` `.assert`s + `report_memory_budgets.py --port bbcmaster`: Default `28,861 B` (`323 B` free), BeebPlaySlot `8,893 B` (`323 B` free) | Verified |
| `HOME_OVERLAY_SEPARATE` & `OVL.HOM` ownership/IDs (`11..13`, count `13`) | `main.s` `.assert`s (`home_enter`/`home_inv_add_carried` in `HomeOverlay` `1,294 B`, `store_enter`/`inv_add_carried` in `TownOverlay` `4,438 B`), `BEEB_OVERLAY_TABLE_COUNT == 13`, `check_memory_contract.py --selftest` (`OVLHOM`) | Verified |
| Evicted target & resident trampoline ownership (`ModalMiscOverlay` / `DeathOverlay` / `StorageOverlay` / `TitleOverlay`) | `main.s` `.assert`s for `re_equip`, `player_recalc_pflags_equipment`, `run_initialize_impl`, `royal_screen`, `title_load_game_ovl`, `title_enter_menu_ovl`; Bank 5 `cache.ovl.modal` `2,761 / 3,072 B` (`311 B` free) | Verified |
| Shipping `.ssd` catalog & release compliance (`LICENSE` / `SRCOFFR` / `OVLHOM`) | `make -C platforms/bbcmaster disk` (`15/31` files, `416/800` sectors used, `384` free) + `check_memory_contract.py --disk` | Verified |
| Cross-port HAL boundaries & 6502 lint | `make check-hal-boundaries check-6502-lint` (`0` errors across `386` files) | Verified |
| MAME `bbcm` runtime suite | `./tools/isolated.sh make -C platforms/bbcmaster test-runtime` (all 17 scenarios incl. `boot_title`, `chargen_town`, `wizard_flow`, `balrog_victory`, `death_flow`, `save_load`, `acid_armour`, `catalog_spawn`) | Verified |

---

## Phase 3 Wave 2 Trampoline Manifest Migration (2026-11-14)

### Change Record

```text
Problem and success criteria:
  BBC Master 128 hand-maintained 65 generated tramp_* overlay stubs in platforms/bbcmaster/main.s alongside 15 custom trampolines across main.s and legal.s, duplicating boilerplate and lagging Wave 1's tramp_spell_execute_selected ovl_spell_restore fix for Mage Spell #20 (Identify '?' eviction). Wire build/trampolines/bbcmaster_trampolines.inc generation into platforms/bbcmaster/Makefile, replace the 65 generated definitions in platforms/bbcmaster/main.s with a single #import in resident Default (< $8000, outside BeebPlaySlot) while preserving all 15 custom trampolines, dispatchers, and shared byte-saving fallthrough blocks, and pass all build, disk, static memory-contract, and MAME bbcm runtime gates within tight Default (< $8000), BeebPlaySlot (< $A400), and cache.ovl.items (33 B free) margins.
State being changed:
  - platforms/bbcmaster/Makefile adds TRAMPOLINES_INC = $(OUT)/trampolines/bbcmaster_trampolines.inc generated by python3 -B ../../tools/gen_trampolines.py --port bbcmaster --output "$@" (depending on ../../tools/gen_trampolines.py and ../../tools/trampoline_manifest.py) and adds $(TRAMPOLINES_INC) to $(BEEB_MAIN_STAMP) prerequisites.
  - platforms/bbcmaster/main.s removes the 65 generated tramp_* definitions (including tramp_dig_ability, tramp_sr_epilogue, ay_dispatch stubs, ovl_direct stubs, ovl_death_restore_spell stubs, tramp_spell_execute_selected, store/game-over/ego wrappers) and imports "../../build/trampolines/bbcmaster_trampolines.inc" inside resident Default ($3000-$7FFF, after core/store_data_defs.s so STORE_HOME resolves during KickAssembler parsing, and outside BeebPlaySlot).
  - Keeps all 15 custom trampolines (14 in main.s incl. BeebPlaySlot tramp_do_look / tramp_inv_add_carried / tramp_ego_append_suffix, DeathOverlay tramp_game_over_run, shared !restore_overlay / !roll_ego_common blocks, tramp_items_dispatch/jmp, tramp_spell_call_items, tramp_winner_royal; plus legal.s tramp_ui_legal_display), all shared dispatchers (gen_dispatch, ui_dispatch, chest_dispatch, spell_dispatch, modal_swap_dispatch), and non-tramp_* helpers (item_spawn_level, run_initialize, hal_player_recalc_pflags, overlay_load_no_kernal, irs_p3_swap_exec, disk_prompt_*, game_over_prompt) intact.
Search scope and terms:
  platforms/bbcmaster/, tools/trampoline_manifest.py, tools/gen_trampolines.py, and core/ searched for tramp_, BBCMASTER_ENTRIES, STORE_HOME, gen_dispatch, ui_dispatch, spell_dispatch, chest_dispatch, tramp_items_dispatch, modal_swap_dispatch, low_helpers_end, program_end, beeb_play_end.
Relevant readers/writers found and known exclusions:
  - All 65 generated and 15 custom tramp_* symbols are resident in Default ($0E00-$7EB6) or BeebPlaySlot ($8000-$A2BD) / DeathOverlay ($A800+) and resolve cleanly across KickAssembler passes once #import "../../build/trampolines/bbcmaster_trampolines.inc" follows core/store_data_defs.s (which defines .const STORE_HOME = 7).
  - No SHEILA_ROMSEL writes live in bbcmaster_trampolines.inc; low_helpers_end (< $3000) keeps only hardware-critical ACCCON/ROMSEL/MOS/screen/storage code.
  - core/, tools/, platforms/shared/, and sibling platform directories were excluded and left untouched.
Initialization, reset and persistence points:
  - Boot MORIA8P preload streams MORIA8.RES ($0E00-$7EB5), BEEB.PLAY ($8000-$A2BC), BEEB.HUFFDATA, BEEB.AUXDATA, BEEB.CATALOG, and cached Bank 5/6/7 overlays identically; generated trampolines require no runtime initialization.
Affected production sequence through the changed transition:
  - Caller -> generated resident trampoline in Default (bbcmaster_trampolines.inc) -> shared resident dispatcher (gen_dispatch / ui_dispatch / chest_dispatch / spell_dispatch / tramp_items_dispatch / modal_swap_dispatch) or direct overlay_load -> overlay routine -> rts or tramp_restore_spell_overlay (incl. tramp_spell_execute_selected -> OVL_SPELL -> spell_execute_selected -> tramp_restore_spell_overlay).
Contract decision or selected upstream oracle with source locations:
  - tools/trampoline_manifest.py (BBCMASTER_ENTRIES: 80 total = 65 generated + 15 custom) and tools/gen_trampolines.py; BBC Master 128 memory ownership rules in Sections 2-3 above.
Intentional Moria8 deviations:
  - N/A (code-generation migration of existing resident overlay trampolines; gameplay semantics unchanged, Mage Spell #20 OVL_SPELL restoration now matches Wave 1 ovl_spell_restore contract).
Input/intermediate widths, signedness, carry, range and overflow policy:
  - Identical register/flag contracts across all 80 tramp_* entry points; tramp_find_special_room, tramp_ui_equip_select_display, and tramp_player_pray now emit explicit 3-byte jmp to their dispatchers instead of fallthrough (+3 B each), tramp_spell_execute_selected uses ovl_spell_restore (+6 B), and tramp_dig_ability moves from < $3000 into Default $3000-$7FFF (-3 B in LowHelpers).
RNG reduction and bias, if applicable:
  - N/A (no RNG state or formulas modified).
Affected platforms, overlays, banks and owners:
  - Acorn BBC Master 128 only: LowHelpers ($0E00-$2443, 5,699 B used, 3,005 B free below $3000), Default ($0E00-$7EB6, 28,854 B used, 330 B free below $8000), BeebPlaySlot ($8000-$A2BD, 8,893 B used, 323 B free below $A400), cache.ovl.items ($0000-$15DF, 5,599 B used, 33 B free below $1600), and all 13 overlay/legal payloads unchanged in bounds.
Required production-path tests:
  - make -C platforms/bbcmaster build disk test-memory-contract test-memory-contract-selftest
  - python3 -B tools/gen_trampolines.py validation for bbcmaster (80 entries: 65 generated, 15 custom; 0 errors)
  - make check-hal-boundaries check-6502-lint
  - ./tools/isolated.sh make testbbcmaster (MAME bbcm full runtime suite)
Known behavior explicitly out of scope:
  - Non-BBC-Master platform migrations, tools/trampoline_manifest.py or tools/gen_trampolines.py edits, and core/ gameplay edits.
Unresolved uncertainty and risk:
  - None open after static contract verification and full 17-scenario MAME bbcm verification.
```

### Verification Coverage

| Contract Row / Check | Enforcement & Evidence | Status |
| --- | --- | --- |
| `LowHelpers` (`< $3000`), `Default` (`<= $8000`), & `BeebPlaySlot` (`<= $A400`) ceilings | `main.s` `.assert`s (`406` passed, `0` failed) + `report_memory_budgets.py --port bbcmaster`: `LowHelpers` `$0E00-$2443` (`3,005 B` free), `Default` `$0E00-$7EB6` (`28,854 B` used, `330 B` free), `BeebPlaySlot` `$8000-$A2BD` (`8,893 B` used, `323 B` free) | Verified |
| Tight SWR/ANDY ceilings (`cache.ovl.items` Bank 7, `ANDY` `beeb.huffdata`) | `check_memory_contract.py --build-dir ../../build/bbcmaster` + `report_memory_budgets.py`: `cache.ovl.items` `5,599 / 5,632 B` (`33 B` free), `ANDY` `3,805 / 3,840 B` (`35 B` free), Banks 4–7 `256/256` pages fit | Verified |
| `bbcmaster` trampoline manifest bijection (`80` total: `65` generated, `15` custom) & build regen | Regenerated `build/trampolines/bbcmaster_trampolines.inc` via `Makefile`; `gen_trampolines.validate_manifest_and_sources(..., strict_migrated=True)` returned `0` errors for `bbcmaster` | Verified |
| Static contract & selftests (`make_ssd.py`, `check_memory_contract.py`, `harness_smoke.py`) | `make -C platforms/bbcmaster build disk test-memory-contract test-memory-contract-selftest` (`15/31` DFS entries, `416/800` sectors used, `LICENSE`/`SRCOFFR` verified) | Verified |
| Cross-port HAL boundaries & 6502 lint | `make check-hal-boundaries check-6502-lint` (`0` errors across `386` files) | Verified |
| MAME `bbcm` runtime suite | `./tools/isolated.sh make testbbcmaster` (`17/17` scenarios passed: `boot_title` [9], `chargen_town` [2], `dungeon_descend` [5], `help_overlay` [33], `ui_modals` [8], `item_actions` [49], `mage_list` [5], `priest_pray` [6], `priest_map_area` [3], `scroll_map` [5], `wizard_flow` [3], `balrog_victory` [9], `death_flow` [10], `save_load` [8], `disk_setup` [13], `acid_armour` [7], `catalog_spawn` [12]) | Verified |

---

## Phase 4 `'ITM2'` `ITEMCAT`, SWR Bank 6/7 Rebalance, & `LYNNE` `recall[279]` (2026-11-15)

- **Main Resident & `BeebPlaySlot`:** `LowHelpers` `$0E00-$2353` (`5,459 / 8,704 B`, **`3,245 B` free** `< $3000`); `Default` (`moria8.res`) `$0E00-$7FDC` (`29,148 / 29,184 B`, **`36 B` free** `< $8000`); `BeebPlaySlot` (`beeb.play`) `$8000-$A3FA` (`9,210 / 9,216 B`, **`6 B` free** `< $A400`).
- **`LYNNE` (`$3F80-$43FF`) & `ANDY` (`$8000-$8FFF`):** `BeebLynneAux` hosts full 279-species `recall[279]` (`1,116 / 1,152 B` at `$3F80-$43DB`, **`36 B` free**); `ANDY` `beeb.huffdata` (`$8000-$8EDD`, `3,805 / 3,840 B`, **`35 B` free**) and `zp_save_buf` (`$8F00-$8FAE`, `174 / 256 B`, **`82 B` free**) are unchanged.
- **SWR Banks 6 & 7 (`256/256` Pages Across Banks 4–7):**
  - **Bank 6 (`64/64p`):** `BeebAuxData` (`19p` `$8000-$92FF`, `4,824 / 4,864 B`, **`40 B` free**), `BEEB_ICAT_B6` (`2p` `$9300-$94FF`, `512 B` preloaded `ITEMCAT` header/index), `BeebCatalog` (`37p` `$9500-$B9FF`, `9,239 / 9,472 B`, **`233 B` free**), and `cache.ovl.ui` (`6p` `$BA00-$BFFF`, `1,467 / 1,536 B`, **`69 B` free**).
  - **Bank 7 (`64/64p`):** `cache.ovl.spell` (`21p` `$8000-$94FF`, `5,270 / 5,376 B`, **`106 B` free**), `cache.ovl.items` (`23p` `$9500-$ABFF`, `5,721 / 5,888 B`, **`167 B` free**), `cache.ovl.gen` (`16p` `$AC00-$BBFF`, `3,922 / 4,096 B`, **`174 B` free**), and `BEEB_ICAT_CACHE` (`4p` `$BC00-$BFFF`, `1,024 B` 4-sector LRU cache for `ITEMCAT`).
- **Shipping `.ssd` (`build/moria8-bbcmaster.ssd`):** `16 / 31` DFS catalog entries (adds `ITEMCAT` `7,573 B`), `467 / 800` sectors used (**`333` free**). Save Disk slots use `68` sectors (`17,408 B` capacity) for the `17,161 B` V2 save stream (`SAVE_VERSION = $20`).


## Overlay Cache Leaves `zp_temp0`/`zp_temp1` to the Caller (2026-11-16)

### Change Record

```text
Problem and success criteria:
  Every BBC Master character since 708f3df started with 135 max HP (other ports:
  race + class hit dice, median 14) and gained about 100 a level. Phase 0-4
  moved player_con_hp_adj and the four STR/DEX adjusters into OVL.UI behind the
  items_swap_dispatch_a trampoline (main.s). When OVL.UI is not loaded, that
  trampoline reloads OVL.UI and then the caller's overlay through
  overlay_load -> hal_asset_load_prg_header -> beeb_overlay_try_cache, which
  kept the filename pointer in zp_temp0/zp_temp1. player_calc_hp
  (core/player.s) keeps the combined hit dice in zp_temp0 across
  jsr player_con_hp_adj: at character creation the start overlay's name
  pointer ($1B87) left $87 = 135. Success: a new character's max HP equals its
  race and class hit dice (chargen_town), and no overlay load changes
  zp_temp0/zp_temp1.
State being changed:
  - beeb_overlay_try_cache (overlay_storage.s, LowHelpers) compares the name
    pointer through self-modified immediates btc_name_lo/btc_name_hi instead
    of zp_temp0/zp_temp1. Clobbers: A, X, Y, zp_ptr0, zp_ptr1 (unchanged
    otherwise).
Search scope and terms:
  platforms/bbcmaster/*.s for zp_temp0/zp_temp1, overlay_load,
  hal_asset_load_prg_header, beeb_overlay_try_cache, beeb_dfs_load_to_bank,
  items_swap_dispatch_a; core/player.s player_calc_hp.
Relevant readers/writers found and known exclusions:
  - The DFS miss path (beeb_dfs_load_to_bank) does not touch zp_temp0/1.
  - hal_memory_copy (memory_bank.s) takes its length in zp_temp0/1 by
    contract and is not on the overlay path.
  - Fixing the loader covers every trampoline that swaps overlays, not only
    items_swap_dispatch_a.
Initialization, reset and persistence points:
  - N/A: the compare operands are written on each call before use.
Affected production sequence through the changed transition:
  - player_calc_hp -> player_con_hp_adj (resident) -> items_swap_dispatch_a
    -> overlay_load(OVL_UI) -> try_cache -> bbcm_player_con_hp_adj ->
    overlay_load(caller's) -> return with zp_temp0 intact.
Contract decision or selected upstream oracle with source locations:
  - Max HP: core/player.s player_calc_hp (race HD + class HD at level 1).
Intentional Moria8 deviations:
  - N/A (restores the shared formula on the BBC Master).
Input/intermediate widths, signedness, carry, range and overflow policy:
  - N/A (8-bit pointer compare, as before).
RNG reduction and bias, if applicable:
  - N/A.
Affected platforms, overlays, banks and owners:
  - Acorn BBC Master 128 only: LowHelpers grows 2 B (low_helpers_end $2355,
    program_end $7FDE, 34 B free below $8000).
Required production-path tests:
  - make testbbcmaster (chargen_town asserts chargen_max_hp_is_hit_dice; it
    failed before the fix).
Known behavior explicitly out of scope:
  - The BBC hal_platform_panic hang (PC $233D) on the same 4457e20 run is
    diagnosed separately.
Unresolved uncertainty and risk:
  - BBC build-queue results since 708f3df were played at about ten times the
    intended HP and do not reflect BBC balance.
```

### Verification Coverage

| Contract Row / Check | Enforcement & Evidence | Status |
| --- | --- | --- |
| LowHelpers (`< $3000`) & Default (`<= $8000`) ceilings | `make testbbcmaster` memory-contract gate (`low_helpers_end = $2355`, `program_end = $7FDE`) | Verified |
| New character max HP = race + class hit dice | `chargen_town` `chargen_max_hp_is_hit_dice` (FAIL before, PASS after) | Verified |
| Live MAME `bbcm` behaviour | `make testbbcmaster` (all 17 scenarios pass with the queue paused; `item_actions` timed out at load 38 on 32 cores and passed alone on a quiet machine) | Verified |
