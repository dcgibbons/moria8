# CP/M 2.2 Z80 Memory Contract

Placement, CP/M Page Zero, BDOS, overlay-window, stack, shadow-screen, and
asset-container source of truth for the CP/M 2.2 Z80 port
(`platforms/z80/cpm/` and `core/z80/`). Enforced at assemble time by `ASSERT`
guards in `platforms/z80/cpm/memory.inc`, `main.asm`, and `ovl_*.asm`, and at
build time by `platforms/z80/cpm/check_memory_contract.py`.

---

## 1. Machine Baseline & CP/M 2.2 TPA Model

The CP/M Z80 port targets any **CP/M 2.2 (or compatible) system running on a
Zilog Z80 CPU** with an **80×24 ADM-3A (default) or ANSI / VT100 (`/V`, `/M`)
serial or console terminal** and a **minimum 52 KB Transient Program Area
(`0x0100–0xD0FF`, BDOS base ≥ `0xD100`)**:

| Property | Contract Value | Enforcement / Notes |
| --- | --- | --- |
| **CPU & ISA** | Zilog Z80 (idiomatic Z80: `LDIR`, `EXX`, `IX`/`IY`, `DJNZ`, `LD A,R`, `JR`) | Assembled with `sjasmplus` v1.24.0 (`DEVICE NOSLOT64K`, `0xNN` hex syntax) |
| **OS Baseline** | CP/M 2.2 (`BDOS 12` version ≥ `0x22`) | Compatible with RunCPM, `cpm_runner`, Kaypro II/4 CP/M 2.2, C128 CP/M Plus, CP/M 3, ZSDOS |
| **Minimum TPA** | `0x0100–0xD0FF` (`53,248` B = `52.0 KB`, `BDOS_MIN_TOP = 0xD100`) | Checked at startup via `LD HL, (0x0006)` before modifying BSS, stack, or map RAM |
| **Terminal Geometry** | `80 × 24` character cells (`80` cols × `24` rows, `198 × 66` dungeon map) | Matches C128 / Apple IIe / CX16 / BBC Master 128 (`VIEWPORT = 78×18`, msg `0–1`, input `20`, status `21–23`); ADM-3A (`0x1A` clear, `ESC = r+32 c+32`) default, `/V` VT100/ANSI Color, `/M` VT100/ANSI Mono, `/A` explicit ADM-3A |
| **Color & Monochrome** | ADM-3A default (no SGR) + `/V` 16-color ANSI SGR + `/M` ANSI mono + runtime `'M'` / `'='` 3-way cycle | `cpm_color_shadow` stores logical Moria8/C64 palette index `0..15` + bold/reverse/dirty |
| **Internal Character Set** | Pure **7-bit ASCII** (`0x20–0x7E`, zero PETSCII / C64 screencodes) | All assets, Huffman corpus, catalogs, and shadow buffers are native ASCII |
| **Console Input** | `BDOS 6` (`C_RAWIO`, `E = 0xFF` poll only) + ANSI CSI/SS3 parser | Never uses CP/M 3-only `BDOS 6` `E = 0xFE`/`0xFD` so stock CP/M 2.2 never prints them |
| **RNG Entropy** | `LD A, R` refresh register + 32-bit `BDOS 6` idle-poll counter | Seeded/mixed on boot and every blocking `input_get_key` poll |
| **Audio Alerts** | ASCII `BEL` (`0x07`) via `BDOS 6` output | Toggleable bell alert on errors, damage, or warnings |
| **Packed Assets** | Single random-access `MORIA8.DAT` (`BDOS 33` `F_READRAND`, `'M8CP'` TOC) | 2-record (`256` B) header; 19 overlays, catalogs, Huffman stream, title art, legal docs |
| **Save System** | Save Format V2 (`SAVE_VERSION = 0x22`), 4 slots `SAVE0.SAV`..`SAVE3.SAV` + `HISCORE.DAT` | `17,164` B stream (`135` CP/M records max) across selectable drives `A:`–`P:` |

### Startup TPA Verification & Clean Warm-Boot Exit (`0x0006–0x0007`)

CP/M stores the 16-bit BDOS entry address (the exclusive top of usable TPA) at
Page Zero `0x0006–0x0007` inside the `JP BDOS` vector at `0x0005`. On entry at
`0x0100`, `MORIA8.COM` **must** execute the following sequence before touching any
address at or above `0x5600` or moving `SP`:

1. Read the `$0080` CLI tail (`0x0080` length byte, `0x0081+` command line) into
   resident startup flags (e.g., `/A` ADM-3A default, `/V` ANSI color, `/M` ANSI
   monochrome, optional `[A-P]:` drive override) while the default DMA (`0x0080`)
   still holds the tail intact.
2. Load `LD HL, (0x0006)` (`CPM_BDOS_VEC`) and verify `HL >= 0xD100` (`BDOS_MIN_TOP`,
   i.e., `LD A, H : CP 0xD1`).
3. If `HL < 0xD100`, keep the CP/M CCP stack intact, print an informative message
   via `BDOS 9` (`"Insufficient TPA: requires 52K (0xD100+).\r\n$"`) and exit
   cleanly via `LD C, 0 : CALL 0x0005` (`BDOS 0`).
4. Once `HL >= 0xD100` is confirmed, switch `LD SP, STACK_TOP` (`0x8E00`), write
   the 4-byte stack canary at `STACK_BOTTOM` (`0x8C00–0x8C03`), zero-fill BSS
   (`0x6A00–0x8BFF`), initialize `z80_state`, record `abi_program_drive`, open
   `MORIA8.DAT` with `fcb_dat[0]` pinned to `abi_program_drive + 1`, clear
   `cpm_char_shadow` / `cpm_color_shadow`, and set BDOS DMA (`BDOS 26`) to
   `cpm_dma_buf` (`0xD080`).
5. **Mandatory Exit Rule (CCP Overwrite at `0x9D00–0xD0FF`):** On CP/M 2.2, the
   Console Command Processor (CCP) resides in high TPA immediately below BDOS.
   Initializing `MAP_BASE` (`0x9D00–0xD00B`), FCBs, and `cpm_dma_buf` overwrites
   the CCP image. Therefore, `MORIA8.COM` **must never exit via `RET`**; every
   program exit **must** invoke `BDOS 0` (`LD C, 0 : CALL 0x0005`) or `JP 0x0000`
   (warm boot) so BIOS reloads CCP cleanly from disk.

---

## 2. Complete 52 KB TPA Memory Map (`0x0000–0xD0FF`)

Every region inside the 52 KB baseline TPA has a single static owner. There is
zero dynamic heap allocation and zero bank switching in the CP/M 2.2 baseline.

| Address Range | Size | Owner / Symbol | Lifecycle & `ASSERT` Guard |
| --- | ---: | --- | --- |
| `0x0000–0x00FF` | `256` B | **CP/M Page Zero** | `0x0000` warm boot (`JP BIOS+3`), `0x0003` IOBYTE, `0x0004` current disk/user, `0x0005–0x0007` BDOS vector (`>= 0xD100`), `0x005C–0x007F` default FCB, `0x0080–0x00FF` CLI tail / initial DMA (saved/parsed at startup, then DMA moves to `0xD080`). |
| `0x0100–0x55FF` | `21,760` B | **`MORIA8.COM` Resident Code & RO Data** | Loaded by CP/M CCP from `0x0100` (measured M5 build: **`21,598` B**, `0x0100–0x555E`, **`162` B headroom**). Hosts boot/TPA guard, BDOS HAL, ADM-3A/ANSI diff renderer, CSI input, RNG, `MORIA8.DAT` loader, Huffman & `ITEM.CAT` decoders + `item_desc` core, hot walk/turn/LOS/combat/monster AI engine, measured built RO tables (`2,403` B incl. `ALIGN 256` page-tail), and 6-byte inline-descriptor `tramp_*` dispatchers (§2.2). **Guard:** `ASSERT resident_end <= OVL_WINDOW_BASE` (`<= 0x5600`). |
| `0x5600–0x69FF` | `5,120` B | **`OVL_WINDOW_BASE` (Shared Overlay Slot)** | `40 × 128` B CP/M records (`OVL_WINDOW_SIZE = 0x1400`). Uninitialized in `MORIA8.COM` (never padded into `.COM`). All `19` overlays link with `ORG 0x5600` (`626`–`4,810` B built; largest `ovl_modal.ovl` = `4,810` B) and stream directly on demand from `MORIA8.DAT` via `BDOS 33`, resolving Finding 1 (`+1,024` B over 4 KB 6502 overlays, §2.2). **Guard:** `ASSERT ovl_start == 0x5600 && ovl_end <= 0x6A00`. |
| `0x6A00–0x8BFF` | `8,704` B | **Resident BSS & Game State** | Zeroed at boot after TPA check (`BSS_BASE = 0x6A00`, `BSS_LIMIT = 0x8C00`). Starts with the fixed 64-byte ABI block `z80_state` at `0x6A00–0x6A3F`, followed by `8,332` B static game state and caches (**`8,396` B** total measured M5 BSS allocated, `0x6A00–0x8ACC`, **`308` B slack**, §2.1). **Guard:** `ASSERT bss_end <= STACK_BOTTOM` (`<= 0x8C00`). |
| `0x8C00–0x8DFF` | `512` B | **Application & BDOS Stack** | `STACK_BOTTOM = 0x8C00`, `STACK_TOP = 0x8E00`. Bottom 4 bytes (`0x8C00–0x8C03`) hold `stack_canary` (`'M','8','S','K'` / `0x4D, 0x38, 0x53, 0x4B`), leaving `508` B (`254` words) for game call frames + BDOS/BIOS calls. |
| `0x8E00–0x957F` | `1,920` B | **`cpm_char_shadow` (`80 × 24` ASCII)** | `CPM_CHAR_SHADOW_BASE = 0x8E00 .. 0x957F`. Stores 7-bit ASCII screen cells (`row * 80 + col`). **Dual-use:** temporarily reused as `OVL_GEN` scan scratch during dungeon generation (§2.3). |
| `0x9580–0x9CFF` | `1,920` B | **`cpm_color_shadow` (`80 × 24` Attr/Dirty)** | `CPM_COLOR_SHADOW_BASE = 0x9580 .. 0x9CFF`. Bits `0–3`: logical Moria8/C64 palette index `0–15`; bit `4`: reserved (`0`); bit `5`: bold (`0x20`); bit `6`: reverse (`0x40`); bit `7`: dirty (`0x80`). |
| `0x9D00–0xD00B` | `13,068` B | **`MAP_BASE` (`198 × 66` Dungeon Map)** | `MAP_BASE = 0x9D00 .. 0xD00B`. Direct 1:1 byte-per-tile dungeon map (`row * 198 + col`), zero banking overhead. Overwrites CCP cleanly (§1 warm-boot exit invariant). |
| `0xD00C–0xD07F` | `116` B | **CP/M File Control Blocks (FCBs)** | `fcb_dat` (`0xD00C–0xD02F`, `36` B, `DR` pinned to `abi_program_drive + 1`), `fcb_save` (`0xD030–0xD053`, `36` B), `fcb_tmp` (`0xD054–0xD077`, `36` B), plus `8` B reserved alignment (`0xD078–0xD07F`). |
| `0xD080–0xD0FF` | `128` B | **`cpm_dma_buf` (BDOS DMA Buffer)** | `CPM_DMA_BUF_BASE = 0xD080 .. 0xD0FF`. 128-byte aligned (`(addr & 0x7F) == 0`) BDOS transfer buffer immediately below `BDOS_MIN_TOP = 0xD100`. |
| `0xD100–0xFFFF` | — | **CP/M BDOS / BIOS / High TPA Slack** | Owned by CP/M 2.2 (or higher TPA on 56K–64K CP/M systems). Never accessed directly by Moria8. |

### 2.1 Resident BSS Budget Breakdown (`0x6A00–0x8BFF`, `8,704` B Capacity)

| Subsystem | Bytes | Placement Notes |
| --- | ---: | --- |
| `z80_state` fixed ABI block | `64` | Locked at `0x6A00–0x6A3F` (`Z80_STATE_BASE`) for harness & playtest inspection (§3) |
| `ovl_stack` + cursor/SGR + `sound_enabled` | `13` | Nested overlay stack (`8` B), cursor/SGR tracking (`4` B), `sound_enabled` (`0x6A40–0x6A4C`) |
| `HUFF` 2-Record LRU Cache + State | `262` | `256` B (`2 × 128` B CP/M record bitstream cache) + `6` B tag/offset state (`0x6A4D–0x6B52`; trees page-aligned in `MORIA8.COM`) |
| `ITEM.CAT` 3-Record LRU + State | `393` | `384` B (`3 × 128` B CP/M record cache) + `9` B LRU tags/state (`0x6B53–0x6CDB`; RO metadata `367` B pinned in `MORIA8.COM`) |
| `DAT` TOC Cache | `127` | Compact `41`-slot `MORIA8.DAT` cache (`0x6CDC–0x6D5A`: `41 × 3` B `(u16 start_rec, u8 rec_count)` + `4` B header, covering spare slots `25..40` natively; `u8 rec_count <= 255` enforced). Cold RO streams (`DAT_ID_TITLE_ART = 17`, `DAT_ID_LICENSE = 18`, `DAT_ID_SRCOFFR = 19`) read exact `u16 byte_len` directly from TOC record `0` via `BDOS 33` on open. |
| `player_data` + `player_background` | `274` | `114` B player struct (`PL_STRUCT_SIZE`) + `160` B 4×40 background lines (`0x6D5B–0x6E6C`) |
| `zp_state` + `eff_fear_timer` | `33` | Core 32-B ZP-equivalent state + `eff_fear_timer` (`0x6E6D–0x6E8D`) |
| Inventory & Equipment (`inv_*`, `34` slots) | `272` | `8 × 34` B (`0x6E8E–0x6F9D`: `inv_item_id..inv_ego` with `ITEM_PAGE_BIT` + Cloak + Secondary) |
| `id_known_bits` + flavour shuffles | `221` | `47` B `id_known_bits` (`376` bits for `361` items) + `174` B `potion_shuffle..staff_shuffle` (`0x6F9E–0x707A`) |
| Store Inventory (`8 × 16 = 128` slots) | `1,024` | `8 × 128` B contiguous SoA (`0x707B–0x747A`: `si_item_id..si_meta_hi`) |
| Dungeon Metadata (Stairs, Rooms, Traps, Doors) | `232` | `stairs` (`7` B at `0x747B`), `room_count + 6×21` (`127` B at `0x7482`), `trap_count + 3×16` (`49` B at `0x7501`), `door_state_count + 3×16` (`49` B at `0x76B2`) |
| `monster_table` (`32 × 12` B) | `384` | Active monster instances on level (`0x7532–0x76B1`) |
| Creature SoA (`cr_*`, `40 × 29` B) | `1,160` | `32` dungeon + `8` town creature species fields (`0x76E3–0x7B6A`; `230` B shared with `OVL_DEATH` `hiscore_table` when death/high-score overlay runs) |
| `cat_slot_id` (`32 × 2` B) | `64` | 16-bit catalog species IDs for active dungeon slots (`0x7B6B–0x7BAA`) |
| `tier_name_pool` (`32 × 26` B) + `town_name_pool` (`8 × 26` B) | `1,040` | Active level species ASCII names (`832` B at `0x7BAB`) + resident town species names (`208` B at `0x7EEB`) |
| Floor Items (`42` slots) + Glyphs (`4`) | `432` | `0x7FBB–0x816A`: `420` B floor items (`fi_item_id..fi_meta_hi`) + `12` B glyphs |
| Monster Recall (`279 × 4` B) | `1,116` | Interleaved `[kills, deaths, attacks, spells]` for all `279` VMS species (`0x816B–0x85C6`) |
| `msg_history` (`8 × 80` B) + message/staged tail | `669` | Full `8`-line × `80`-char message history ring buffer (`640` B) + `29` B `fi_add_*`/message cursors (`0x85C7–0x8863`) |
| Core Decode / Combat / Turn / UI Buffers | `616` | `item_name_decode_buf..chest_loot_flags` (`0x8864–0x8ACB`): line/temp formatting, `icat_*` decode, `player_pflags`, status cache, turn/LOS/combat/AI/`me_any_hit`/`me_hit_verb`/spell/chest scalars |
| **Total M5 BSS Allocated** | **`8,396` B** | **`0x6A00–0x8ACC`**; leaves **`308` B free slack** below `STACK_BOTTOM` (`0x8C00`) |

### 2.2 Resident Ownership, Built RO Tables, & `5,120` B Overlay Sizing (`0x0100–0x555E`, `21,598` B Measured M5)

To keep `MORIA8.COM` within `21,760` B (`0x5600`) while keeping the hot turn/walk path free of disk I/O and giving overlays generous `5,120` B (`40`-record) headroom, resident and overlay ownership are partitioned cleanly:

| Resident Subsystem (`MORIA8.COM`) | Measured M5 Size | Contents (`0x0100–0x555E`) |
| --- | ---: | --- |
| **Built RO Data Tables (`build/cpm/*.inc`)** | **`2,403` B** (`2.35 KB`) | `256` B `ALIGN 256` `huff_tree_page` (`0x0E00–0x0EFF`: `120` B `huff_tree` + `117` B `monster_idx_z80` + `16` B `sgr_lut` + `3` B pad) + `496` B `huff_str_index` + `367` B `item_cat_pinned_z80` + `1,284` B `item_hot_tables_z80` |
| **Boot, HAL, Core Engine & Huffman/Catalog Code** | **`18,667` B** | Boot/TPA guard, `bdos_io`, `screen_ansi` (ADM-3A/ANSI), `input_csi`, `sound_bel`, `rng`, `dat_loader`, Huffman & `ITEM.CAT` LRU decoders, `item_desc`, `game_loop`, LOS, viewport, combat, monster AI, math, `player_core`, `status_bar`, `messages`, plus final exit/error tail strings |
| **Compact `tramp_*` Dispatchers (`0x5312–0x5521`)** | **`528` B** | `88` 6-byte inline-descriptor `tramp_*` entry stubs (`CALL overlay_trampoline : DB ovl_id : DW target`) ending at `0x5522`, before final code/string tail (`resident_end = 0x555E`) |
| **Total M5 Resident Footprint (`MORIA8.COM`)** | **`21,598` B** | **`0x0100–0x555E`**; leaves **`162` B free slack** below `OVL_WINDOW_BASE` (`0x5600`) |

* **CX16 `Default` Cold-Code Eviction & Platform-Elimination Accounting:**
  Compared against Commander X16 `Default` resident code, the CP/M hot core reaches `~12.2 KB` (`~12,500` B) by placing `~12.5 KB` of cold subsystems cleanly into overlays while already accounting for `~2.7 KB` of CX16 BSS (`0x6A00–0x8BFF`) and eliminating `~3 KB` of VERA/PETSCII/bank-switching logic:
  * `monster_catalog_tier` + `monster_magic` + `monster_atk_effects` -> `OVL_MON_EXT`
  * `eff_*` (potion/scroll/wand/staff & spell effects) -> `OVL_ITEMS_EFF` / `OVL_SPELL_EFF`
  * `inven_calc` / `inv_add` / `roll_enchant` -> `OVL_ITEM_MGT` / `OVL_GEN` / `OVL_CHEST`
  * `door` / `trap` / `search` commands -> `OVL_ACTIONS`
  * `race` / `class` creation tables -> `OVL_START` / `OVL_UI`
* **Resident Ceiling Policy (`0x5600`):** Post-M5 `MORIA8.COM` stands at `21,598` B (`162` B below `0x5600`). If future features pressure the `0x5600` ceiling, move cold helpers into the `5,120` B overlays or spare TOC slots `25..40` at only **`6` B** per resident `tramp_*` stub.
* **Why `5,120` B (`40` Records) Resolves Finding 1:** Expanding `OVL_WINDOW_SIZE` from `4,096` B / `4,608` B to **`5,120` B (`40 × 128` B records)** adds **`+1,024` B** over C64/Plus4/C128/Atari8 `4,096` B overlays (where all 13 fit `<= 4,048` B). With Z80 code density, `5,120` B holds **`~5.7–6.0 KB` of 6502 code**, fitting unsplit 80-column overlays cleanly without floppy double-reload thrashing.

* **`huff_ascii` `ALIGN 256` Page-Tail Packing (`253 / 256` B usable inside `256` B page):**
  Because `huff_tree_left..huff_tree_right` requires a `256`-byte-aligned base
  (`ALIGN 256`, `+64` byte stride so `SET 6, L` steps right children cleanly)
  while occupying only `120` B (`64 + 56`), the remaining `136` bytes of that
  256-byte page host `monster_idx_z80` (`117` B: `cat_level_raw[41]` +
  `cat_level_playable[41]` + `cat_undead[35]`) and `sgr_lut` (`16` B) with zero
  wasted alignment padding:
  * `page + 0x00 .. 0x77` (`120` B): `huff_tree_left..huff_tree_right` (`64 + 56` B)
  * `page + 0x78 .. 0xEC` (`117` B): `monster_idx_z80` (`cat_level_raw`, `cat_level_playable`, `cat_undead`)
  * `page + 0xED .. 0xFC` (`16` B): `sgr_lut` (16-color Moria8/C64 -> ANSI SGR lookup table)
  * `page + 0xFD .. 0xFF` (`3` B): pad (included in the `256` B page subtotal above)

### 2.3 `OVL_GEN` Dual-Use Policy for `cpm_char_shadow` (`0x8E00–0x957F`)

`OVL_GEN` (`0x5600–0x69FF`) requires temporary scan/BFS scratch during cavern,
room-connectivity, and door-scan passes without consuming permanent resident
BSS. Therefore:

1. While inside `OVL_GEN`, the generator may reuse **`cpm_char_shadow`
   (`0x8E00–0x957F`, `1,920` B)** as temporary scan scratch (`GEN_SCAN_SCRATCH_BASE = 0x8E00`,
   `GEN_SCAN_SCRATCH_SIZE = 1920`).
2. During `OVL_GEN` execution, no screen flush (`screen_flush`) may be called
   while `cpm_char_shadow` holds scratch bytes.
3. **Mandatory Exit Cleanliness (Terminal Clear + Clean Shadows):** before
   returning to gameplay, `OVL_GEN`'s exit path **must**:
   * Call `screen_clear_hw` via `BDOS 6` so the physical terminal resets cleanly
     without a slow 1,920-space serial flood: ADM-3A mode (`abi_term_mode == 0`)
     emits `0x1A` (`SUB`), while VT100/ANSI modes (`/V`, `/M`) emit **`ESC[0m`
     followed by `ESC[2J`** so terminal SGR color / reverse-video state is
     explicitly cleared.
   * Fill `cpm_char_shadow` (`0x8E00–0x957F`) with `' '` (`0x20`) and clear
     `cpm_color_shadow` (`0x9580–0x9CFF`) to clean default state (**`dirty = 0`**,
     not `0x80`), invalidating `screen_flush`'s tracked cursor/SGR state.
   * Trigger a forced full gameplay redraw (`hal_layout_visibility_force_redraw = 1`)
     so the next `render_viewport` + `draw_status` writes only the active
     viewport/status/message cells as dirty (`0x80`).

### 2.4 `cpm_color_shadow` Logical Palette & `screen_flush` Policy (`0x9580–0x9CFF`)

Every screen cell `(row, col)` at `0x9580 + row * 80 + col` packs its visual
attributes and dirty state into one byte:

| Bit(s) | Mask | Name | Semantics |
| --- | --- | --- | --- |
| `0..3` | `0x0F` | `CPM_ATTR_COLOR_MASK` | **Logical Moria8 / C64 palette index (`0..15`)**. Zero write-time conversion: gameplay/render code stores the logical Moria8 color index directly, and `screen_flush` translates each dirty cell **once** through `sgr_lut` (`16` B at page tail `0xED..0xFC`) into ANSI SGR (`30–37` / `90–97`). Ignored when `/M` monochrome (`abi_monochrome != 0`). |
| `4` | `0x10` | Reserved | Always `0`. |
| `5` | `0x20` | `CPM_ATTR_BOLD` | Bold / intensity (`SGR 1`). |
| `6` | `0x40` | `CPM_ATTR_REVERSE` | Reverse video (`SGR 7`; preserved in `/M` monochrome mode for player/cursor/status bar highlights). |
| `7` | `0x80` | `CPM_ATTR_DIRTY` | `1` = cell changed since last `screen_flush`; cleared to `0` once emitted over `BDOS 6`. |

* **VT100 Deferred Wrap Invalidation:** After writing column `79` (the last
  column on a row), VT100/ANSI terminals enter deferred-wrap (`xenl`) state
  rather than wrapping consistently across hardware/emulators. Therefore,
  whenever `screen_flush` emits a cell at `col == 79`, it **must** invalidate
  its tracked `(emit_row, emit_col)` cursor position so the next dirty cell
  emits an explicit `ESC[row;colH` positioning sequence.

---

## 3. Fixed ABI Block (`z80_state` at `0x6A00`)

`z80_state` is pinned at the exact start of BSS (`0x6A00`, `Z80_STATE_SIZE = 64`
B) so `cpm_runner` tests, `harness_smoke.py`, and `playtest` can read game state
and inject deterministic RNG seeds directly via 64 KB RAM reads/writes without
chasing shifting symbol addresses across builds.

| Offset | Address | Size | Field | Description |
| ---: | --- | ---: | --- | --- |
| `+0x00` | `0x6A00` | `4` B | `abi_magic` | ASCII `'M','8','Z','0'` written after BSS zero-fill |
| `+0x04` | `0x6A04` | `1` B | `abi_version` | ABI struct version (`0x01`) |
| `+0x05` | `0x6A05` | `1` B | `abi_monochrome` | `0` = 16-color ANSI SGR (`/V`), `1` = monochrome (`/M` ANSI mono or `/A` ADM-3A default) |
| `+0x06` | `0x6A06` | `1` B | `abi_current_overlay` | Currently loaded overlay ID (`0` = `OVL_NONE`, `1..19` = `OVL_START..OVL_ITEM_MGT`) |
| `+0x07` | `0x6A07` | `1` B | `abi_overlay_depth` | Current nested overlay trampoline stack depth (`0..8`) |
| `+0x08` | `0x6A08` | `4` B | `abi_rng_seed` | 32-bit PRNG state (`rng_0..rng_3`, little-endian) |
| `+0x0C` | `0x6A0C` | `4` B | `abi_entropy_poll` | 32-bit `BDOS 6` idle-poll counter incremented while awaiting key input |
| `+0x10` | `0x6A10` | `2` B | `abi_turn` | 16-bit game turn counter (little-endian) |
| `+0x12` | `0x6A12` | `1` B | `abi_game_flags` | `bit 0` = `GAME_FLAG_OVER`, `bit 1` = `WIZARD`, `bit 2` = `WINNER` |
| `+0x13` | `0x6A13` | `1` B | `abi_player_x` | Player map X coordinate (`0..197`) |
| `+0x14` | `0x6A14` | `1` B | `abi_player_y` | Player map Y coordinate (`0..65`) |
| `+0x15` | `0x6A15` | `1` B | `abi_player_dlvl` | Current dungeon level (`0` = town, `1..50+` dungeon) |
| `+0x16` | `0x6A16` | `1` B | `abi_player_lvl` | Player character level (`1..40`) |
| `+0x17` | `0x6A17` | `2` B | `abi_player_hp` | Current HP (16-bit LE) |
| `+0x19` | `0x6A19` | `2` B | `abi_player_mhp` | Max HP (16-bit LE) |
| `+0x1B` | `0x6A1B` | `1` B | `abi_player_mp` | Current mana |
| `+0x1C` | `0x6A1C` | `1` B | `abi_player_mmp` | Max mana |
| `+0x1D` | `0x6A1D` | `1` B | `abi_hunger_state` | Hunger state (`0..3`) |
| `+0x1E` | `0x6A1E` | `1` B | `abi_mon_count` | Active monsters on level (`0..32`) |
| `+0x1F` | `0x6A1F` | `1` B | `abi_item_count` | Floor items on level (`0..42`) |
| `+0x20` | `0x6A20` | `1` B | `abi_view_x` | Viewport top-left map X |
| `+0x21` | `0x6A21` | `1` B | `abi_view_y` | Viewport top-left map Y |
| `+0x22` | `0x6A22` | `1` B | `abi_light_rad` | Player light radius |
| `+0x23` | `0x6A23` | `1` B | `abi_death_source` | Death cause code (`0` while alive) |
| `+0x24` | `0x6A24` | `1` B | `abi_save_drive` | Active save drive (`0..15` = `A:`..`P:`) |
| `+0x25` | `0x6A25` | `1` B | `abi_program_drive` | Program/data drive (`0..15` = `A:`..`P:`) |
| `+0x26` | `0x6A26` | `1` B | `abi_last_bdos_err` | Last non-zero BDOS/storage error code (`0` = OK) |
| `+0x27` | `0x6A27` | `1` B | `abi_esc_pending` | CSI pushback buffer state (`0` = empty, `0x01–0xFF` = pending byte) |
| `+0x28` | `0x6A28` | `1` B | `abi_term_mode` | Terminal output mode (`0` = ADM-3A default, `1` = VT100/ANSI) |
| `+0x29` | `0x6A29` | `23` B | `abi_reserved` | Zero-reserved expansion fields (`0x6A29–0x6A3F`) |

---

## 4. Critical CP/M 2.2 & Z80 Runtime Invariants

### 4.1 BDOS Clobbering, `IX`/`IY` Preservation, Drive Pinning, `BDOS 13` Recovery, & DMA Reset Discipline

Under Digital Research CP/M 2.2 and vendor BIOS implementations (Kaypro,
Osborne, C128 CP/M Plus), `CALL 0x0005` (`CPM_BDOS_ENTRY`):

* **May freely clobber `AF`, `BC`, `DE`, `HL`, `IX`, `IY`**, and on some
  machines BIOS disk/console hooks use `IX`/`IY` or switch onto a small BDOS
  internal stack (~24 levels = 48 B) while preserving only `SP`.
* **Never guarantees preservation of the caller's DMA pointer** across high-level
  helpers unless explicitly managed, and starts every `.COM` with DMA at `0x0080`.
* **Diverts `DR == 0` FCB operations to whatever `BDOS 14` (`SELDSK`) last selected.**

Therefore, **all BDOS access must follow this contract**:

1. **Wrapper Isolation & `IX`/`IY` Preservation:**
   Every BDOS wrapper (`bdos_call`, `bdos_rawio_poll`, `bdos_rawio_putc`,
   `bdos_file_op`) saves `IX` and `IY` around `CALL 0x0005`:
   ```z80
   ; Input: C = BDOS function, DE = argument
   ; Output: A/HL = BDOS return; IX, IY preserved
   bdos_call:
       PUSH IX
       PUSH IY
       CALL CPM_BDOS_ENTRY
       POP  IY
       POP  IX
       RET
   ```
   No game module in `core/z80/` or overlays may issue a bare `CALL 0x0005`
   without going through the platform BDOS HAL wrapper (except the startup TPA
   check prior to BSS/stack setup).
2. **`fcb_dat[0]` Explicit Program-Drive Pinning:**
   At boot, `MORIA8.COM` records the startup default drive (`BDOS 25` `CURDSK`,
   or explicit program drive override) in `abi_program_drive` (`0..15`), and
   pins **`fcb_dat[0]` (`DR` byte at `0xD00C`) to `abi_program_drive + 1`**
   (`1..16`, **never `0`**) before opening `MORIA8.DAT`. Consequently, subsequent
   `BDOS 14` (`SELDSK`) switches for saving/loading on another drive (`B:`–`P:`)
   can never redirect `BDOS 33` overlay/catalog reads away from `MORIA8.DAT`'s
   origin drive.
3. **`BDOS 13` (`Reset Disk System`) Recovery Rule:**
   On real CP/M 2.2 hardware (such as Kaypro 4 / C128 CP/M floppies), swapping
   a diskette or recovering from a read-only (`R/O`) or media-change disk error
   requires **`BDOS 13` (`BDOS_RESETDSK`)** to re-log the drive allocation vector.
   Because `BDOS 13` resets BDOS's current disk to `A:` (`0`), resets the
   active DMA address back to `0x0080`, and invalidates cached directory/login
   state for open disks, any routine invoking `BDOS 13` **must** execute the
   following full recovery sequence immediately afterward:
   1. Re-assert `BDOS 26` (`SETDMA`) to `cpm_dma_buf` (`0xD080`).
   2. Re-select the intended target drive via `BDOS 14` (`SELDSK`, if not `A:`).
   3. Re-initialize/re-open `MORIA8.DAT` on `fcb_dat` (clearing `EX/S1/S2/CR`
      with `DR = abi_program_drive + 1`, calling `BDOS 15` `F_OPEN`) before any
      subsequent `overlay_load` or `BDOS 33` read.
   * **Safe Drive Probing (`BIOS SELDSK`, Never `BDOS 14`):** Real CP/M 2.2
     BDOS (and `RunCPM`) traps an unmounted `BDOS 14` (`SELDSK`) by printing
     `"Bdos Err on X: Select"` and warm-booting instead of returning `A = 0xFF`.
     Drive readiness checks (`bdos_probe_drive`) must probe via **BIOS
     `SELDSK`** at `(CPM_WARM_BOOT + 1) + 24` (`C = drive 0..15`, `E = 0`),
     verify `HL != 0`, immediately restore `abi_program_drive` via BIOS
     `SELDSK` (`E = 1`), and invoke `bdos_reset_disk_recover(abi_program_drive)`
     whenever probing a mounted drive altered BIOS drive state.
4. **DMA Reset Guarantee (`0xD080`):**
   * After reading `$0080` CLI arguments at startup, initialization calls
     `BDOS 26` (`SETDMA`) with `DE = cpm_dma_buf` (`0xD080`).
   * The canonical BDOS DMA address is **`0xD080`** (`cpm_dma_buf`).
   * Whenever `overlay_load` (or any bulk loader) temporarily sets DMA directly
     to `OVL_WINDOW_BASE + offset` (`0x5600..0x69FF`) to avoid extra 128-byte
     `LDIR` copies during `BDOS 33`, it **must** re-issue `BDOS 26` (`SETDMA`)
     with `DE = cpm_dma_buf` (`0xD080`) on **both** the success and error paths
     before returning.
   * Directory searches (`BDOS 17`/`18`) and sequential/random file calls (`BDOS
     20`/`21`/`33`/`34`) assume DMA is `cpm_dma_buf` (`0xD080`) and never target
     `0x0080`.
5. **CP/M 2.2 FCB Discipline:**
   * FCBs live statically in `0xD00C–0xD077` (`fcb_dat`, `fcb_save`, `fcb_tmp`).
   * Before every `BDOS 15` (`F_OPEN`) or `BDOS 22` (`F_MAKE`), zero FCB bytes
     `12..35` (`EX`, `S1`, `S2`, `RC`, `D0..D15`, `CR`, `R0..R2`), set byte `0`
     (`DR`: `1..16` for explicit `A:`–`P:` pinning, or `0` only for current
     drive probes), and space-pad filename (`8` B) + extension (`3` B) in
     uppercase 7-bit ASCII.
   * Because CP/M 2.2 `BDOS 22` (`F_MAKE`) fails (`A = 0xFF`) when a file
     already exists and leaves `FCB+32` (`CR`) dirty, callers rewriting a save
     or high-score file must write atomically via a temporary `.TMP` file:
     delete any stale `.TMP`, `BDOS 22` make `.TMP`, write all records,
     `BDOS 16` close `.TMP`, then `BDOS 19` delete the destination (`.SAV`/`.DAT`)
     and `BDOS 23` (`bdos_rename`) `.TMP` -> destination. On any write or close
     error, close and delete `.TMP` and run `bdos_reset_disk_recover` so any
     prior valid `.SAV`/`.DAT` remains intact.
6. **Stack Budget (`0x8C00–0x8DFF`, `512` B):**
   * `SP` starts at `STACK_TOP` (`0x8E00`) and grows downward toward `0x8C04`
     (above the 4-byte `stack_canary` at `0x8C00–0x8C03`).
   * `check_memory_contract.py` enforces `bss_end <= 0x8C00`, and `cpm_runner` /
     runtime checks verify `0x8C00–0x8C03` stays intact across deep call chains
     and BDOS calls.

### 4.2 Nested Overlay Trampoline Stack Discipline (`current_overlay` Push/Reload)

All 19 overlays (`OVL_START = 1 .. OVL_ITEM_MGT = 19`; `OVL_NONE = 0`) link at
`0x5600` and occupy the single mutual-exclusion `0x5600–0x69FF` (`5,120` B = `40`
records) window. Spare TOC slots `25..40` (up to `DAT_MAX_ENTRIES = 41`) remain
available if any overlay later needs further splitting below `5,120` B:

| Overlay ID | Constant | `MORIA8.DAT` Slot (`DAT_ID_*`) | Binary Filename | Measured Size (`< 5,120` B) | End Address (`< 0x6A00`) | Free Slack | Role |
| ---: | --- | ---: | --- | ---: | ---: | ---: | --- |
| `0` | `OVL_NONE` | — | — | — | — | — | No overlay mapped (startup/initial BSS state) |
| `1` | `OVL_START` | `0` (`DAT_ID_OVL_START`) | `ovl_start.ovl` | `3,819` B | `0x64EB` | `1,301` B | Character creation & new-game startup |
| `2` | `OVL_TOWN` | `1` (`DAT_ID_OVL_TOWN`) | `ovl_town.ovl` | `4,662` B | `0x6836` | `458` B | Town stores 0–6 & town services |
| `3` | `OVL_DEATH` | `2` (`DAT_ID_OVL_DEATH`) | `ovl_death.ovl` | `3,311` B | `0x62EF` | `1,809` B | Death/victory/royal/monster recall & high-score UI |
| `4` | `OVL_GEN` | `3` (`DAT_ID_OVL_GEN`) | `ovl_gen.ovl` | `4,451` B | `0x6763` | `669` B | Town & dungeon level generation (`cpm_char_shadow` reuse) |
| `5` | `OVL_HELP` | `4` (`DAT_ID_OVL_HELP`) | `ovl_help.ovl` | `3,029` B | `0x61D5` | `2,091` B | In-game help & wizard screens |
| `6` | `OVL_UI` | `5` (`DAT_ID_OVL_UI`) | `ovl_ui.ovl` | `3,061` B | `0x61F5` | `2,059` B | Character sheet, equipment/inventory view, look/inspect, `+15` `tramp_ui_select_display` (`OVL_ENTRY_VEC_5`) |
| `7` | `OVL_ITEMS` | `6` (`DAT_ID_OVL_ITEMS`) | `ovl_items.ovl` | `3,433` B | `0x6369` | `1,687` B | Consumables dispatch, 45 potion handlers, `+18` `tramp_items_world_cold` (`OVL_ENTRY_VEC_6`: Word of Destruction & Earthquake) |
| `8` | `OVL_SPELL` | `7` (`DAT_ID_OVL_SPELL`) | `ovl_spell.ovl` | `3,462` B | `0x6386` | `1,658` B | Mage/priest spell selection (`?` modal), study (`f`) & casting core |
| `9` | `OVL_MODAL` | `8` (`DAT_ID_OVL_MODAL`) | `ovl_modal.ovl` | `4,810` B | `0x68CA` | `310` B | Modal helpers (`re_equip`, `pflags`, `run_init`, melee, XP, level pop) |
| `10` | `OVL_CHEST` | `9` (`DAT_ID_OVL_CHEST`) | `ovl_chest.ovl` | `2,670` B | `0x606E` | `2,450` B | Chest disarm, unlock, loot generation |
| `11` | `OVL_HOME` | `10` (`DAT_ID_OVL_HOME`) | `ovl_home.ovl` | `855` B | `0x5957` | `4,265` B | Player Home storage (`STORE_HOME`) |
| `12` | `OVL_STORAGE` | `11` (`DAT_ID_OVL_STORAGE`) | `ovl_storage.ovl` | `3,089` B | `0x6211` | `2,031` B | Save/load menus & Disk Setup (`A:`–`P:`) |
| `13` | `OVL_TITLE` | `12` (`DAT_ID_OVL_TITLE`) | `ovl_title.ovl` | `626` B | `0x5872` | `4,494` B | Title menu & artwork streaming |
| `14` | `OVL_LEGAL` | `13` (`DAT_ID_OVL_LEGAL`) | `ovl_legal.ovl` | `1,770` B | `0x5CEA` | `3,350` B | License & source-offer viewer (Title `A` / Help `L` / `v`) |
| `15` | `OVL_ITEMS_EFF` | `20` (`DAT_ID_OVL_ITEMS_EFF`) | `ovl_items_eff.ovl` | `4,805` B | `0x68C5` | `315` B | Scroll/wand/staff effects, level spawn, identify, teleport & summon |
| `16` | `OVL_SPELL_EFF` | `21` (`DAT_ID_OVL_SPELL_EFF`) | `ovl_spell_eff.ovl` | `4,735` B | `0x687F` | `385` B | All 62 spell/prayer effects & area/bolt/ball magic |
| `17` | `OVL_ACTIONS` | `22` (`DAT_ID_OVL_ACTIONS`) | `ovl_actions.ovl` | `4,648` B | `0x6828` | `472` B | Dungeon feature/door/trap/bash/tunnel actions & 18 traps |
| `18` | `OVL_MON_EXT` | `23` (`DAT_ID_OVL_MON_EXT`) | `ovl_mon_ext.ovl` | `3,838` B | `0x64FE` | `1,282` B | Monster multi-attack (`19` verbs, `24` effects) & `18` `CSPELL` spells/breaths |
| `19` | `OVL_ITEM_MGT` | `24` (`DAT_ID_OVL_ITEM_MGT`) | `ovl_item_mgt.ovl` | `4,732` B | `0x687C` | `388` B | Equipment/pack select, wear, takeoff, drop, fire (`_im_fire`), throw, enchant |

*(Note: `MORIA8.DAT` slots `14..19` hold non-overlay read-only assets:
`MONSTER_CAT`, `ITEM_CAT`, `HUFF_STREAM`, `TITLE_ART`, `LICENSE`, `SRCOFFR`;
slots `25..40` are spare TOC capacity. `overlay_load` maps `ovl_id` `1..14 ->
slot id - 1` and `15..19 -> slot id + 5` via a resident `ovl_to_dat_slot`
table.)*

Mandatory trampoline and overlay-calling discipline:

1. **No Direct Cross-Overlay Calls:**
   Code inside overlay `A` may **never** execute `CALL`, `JP`, or `JR` directly
   to any symbol defined inside another overlay `B != A`. Similarly, resident
   code outside `trampolines.asm` / `tramp_*` dispatchers may **never** jump or
   call directly into an overlay address. Additionally, any `.asm` module in
   `core/z80/` or `platforms/z80/cpm/` may only be `INCLUDE`d by one owner
   (`main.asm` or a single `ovl_*.asm`; shared macros/constants belong in `.inc`
   headers). Enforced statically by `check_memory_contract.py`.
2. **6-Byte Inline-Descriptor Resident Trampoline Protocol (`tramp_*` -> `overlay_trampoline`):**
   Every cross-overlay call enters a compact **6-byte** resident `tramp_*` stub
   (`0x0100–0x55FF`; `528` B total for `88` stubs vs `~1.9 KB` on 6502):
   ```z80
   tramp_town_enter:
       CALL overlay_trampoline
       DB   OVL_TOWN
       DW   ovl_town_entry
   ```
   `overlay_trampoline` pops the inline 3-byte descriptor address off the stack
   (leaving the caller's original return address on `(SP)`), reads `(ovl_id,
   target_addr)`, and preserves `AF`, `BC`, `DE`, `HL`, `IX`, and `IY` across
   dispatch and return:
   * **Same-Overlay Fast Path:** Compare `ovl_id` with `(abi_current_overlay)`.
     If already resident at `0x5600`, restore saved caller registers and jump
     straight to `target_addr` (`JP (HL)` so `target_addr`'s `RET` returns
     directly to the original caller) with zero `MORIA8.DAT` I/O and zero
     overlay stack push.
   * **Cross-Overlay Push/Load/Restore Path:**
     1. Push `(abi_current_overlay)` onto the bounded resident overlay stack
        `ovl_stack[abi_overlay_depth]` (max depth `OVL_STACK_MAX = 8`; overflow
        panics cleanly rather than corrupting BSS).
     2. Preserve caller argument registers (`AF`, `BC`, `DE`, `HL`, `IX`, `IY`),
        call `overlay_load` for `ovl_id` (reading `rec_count <= 40` records
        via `BDOS 33` from `MORIA8.DAT` into `0x5600..0x69FF`), and set
        `abi_current_overlay = ovl_id`.
     3. If `overlay_load` fails (`C` set): decrement `abi_overlay_depth`
        (leaving `abi_current_overlay = OVL_NONE` because `0x5600+` may be
        partially overwritten), report the storage error, and return failure.
     4. Restore caller argument registers (`AF`, `BC`, `DE`, `HL`, `IX`, `IY`)
        and `CALL` `target_addr` inside `0x5600–0x69FF`.
     5. Preserve target return registers (`AF`, `BC`, `DE`, `HL`, `IX`, `IY`),
        pop `prev_ovl` from `ovl_stack`, and if `prev_ovl != OVL_NONE`, reload
        `prev_ovl` via `overlay_load` and restore `abi_current_overlay = prev_ovl`;
        otherwise set `abi_current_overlay = OVL_NONE`.
     6. Restore target return registers (`AF`, `BC`, `DE`, `HL`, `IX`, `IY`) and
        `RET` to the original caller (whose code at `0x5600+` is guaranteed
        resident again!).

### 4.3 ANSI `ESC` vs CSI Disambiguation Contract (`BDOS 6`)

On CP/M 2.2 serial terminals, physical Escape (`0x1B`) and multi-byte arrow /
navigation sequences (`ESC [ A`, `ESC O A`, etc.) share the `0x1B` prefix:

1. **Portable CP/M 2.2 Polling:**
   All console input uses `BDOS 6` with `E = 0xFF` only. Blocking key waits loop
   calling `BDOS 6 E = 0xFF` while incrementing the 32-bit `abi_entropy_poll`
   counter until `A != 0`. (Never call `E = 0xFE` or `E = 0xFD`, which print raw
   characters under authentic CP/M 2.2.)
2. **1-Byte Lookahead (`abi_esc_pending`):**
   `input_get_key` checks `abi_esc_pending` first. If non-zero, it clears
   `abi_esc_pending` and returns that byte immediately without calling BDOS.
3. **`0x1B` Disambiguation State Machine:**
   When `BDOS 6 E = 0xFF` yields `0x1B`:
   * Poll `BDOS 6 E = 0xFF` in a bounded loop (`ESC_CSI_POLL_ITERS = 255`,
     safe down to **2400 baud** on a 4–8 MHz Z80; `cpm_runner` defaults
     `run_idle` threshold to `512 > 255` so bare `ESC` finishes its poll loop
     before `run_idle` pauses, while queued CSI sequences succeed on poll 1).
   * **Timeout (all 255 polls return `0`):** Return `KEY_ESC` (`0x1B`).
   * **Next byte `b == '['` (CSI):** Read follow-up bytes (with bounded poll):
     accumulate optional numeric parameter digits (`'0'..'9'`) and `';'` until
     a final byte in `0x40..0x7E` arrives (or timeout). Map:
     - `'A'` -> `KEY_UP`
     - `'B'` -> `KEY_DOWN`
     - `'C'` -> `KEY_RIGHT`
     - `'D'` -> `KEY_LEFT`
     - `'H'` -> `KEY_HOME` / `'F'` -> `KEY_END`
     - `'~'` with param `1`/`7` -> `KEY_HOME`, `4`/`8` -> `KEY_END`, `5` -> `KEY_PGUP`, `6` -> `KEY_PGDN`, `3` -> `KEY_DEL`
     - Unknown CSI final byte -> discard sequence cleanly and continue waiting
       (never leak `'['` or parameter digits as gameplay commands!).
   * **Next byte `b == 'O'` (SS3 VT100 application mode):** Poll next byte; map
     `'A'..'D'` to `KEY_UP..KEY_LEFT`; ignore unknown SS3 codes.
   * **Any other byte `b` (e.g. rapid `ESC` + `'q'`):** Store `b` in
     `abi_esc_pending` and return `KEY_ESC` (`0x1B`), so no fast-typed command
     following Escape is ever dropped.

### 4.4 `MORIA8.DAT` `'M8CP'` Packed Random-Access Container

`MORIA8.DAT` packs all 19 overlays and 6 read-only binary assets into one
contiguous record-aligned file opened once on `fcb_dat` (pinned to
`abi_program_drive + 1`) and queried via `BDOS 33` (`F_READRAND`):

* **Header (`256` B = records `0..1`):**
  * Bytes `0..3`: `"M8CP"` magic
  * Byte `4`: `version = 1`
  * Byte `5`: `entry_count` (`20..41`, `25` for full 19-overlay release)
  * Bytes `6..251`: up to `41 × 6 B` little-endian descriptors `(u16 start_rec, u16 rec_count, u16 byte_len)`
  * Bytes `252..255`: `0x00` padding
* **Invariant Rules:**
  * Every active entry starts at `start_rec >= 2` (never overlaps header).
  * `byte_len > 0` whenever `rec_count != 0`, and `rec_count == (byte_len + 127) // 128`;
    **all active slots satisfy `rec_count <= 255` (`DAT_MAX_REC_COUNT`)** so the
    3-byte `(u16 start_rec, u8 rec_count)` in-RAM TOC cache never truncates, and
    all 19 overlay slots (`0..13`, `20..24`) satisfy `byte_len <= 5,120`
    (`rec_count <= 40`).
  * RO asset slots `14..19` are mandatory across all milestones (`m0..all`).
  * **Measured M5 `MORIA8.DAT` Container (`build/cpm/MORIA8.DAT`):** **`97,280` B**
  (`760 × 128` B CP/M records: `2` header records + `758` payload records across
  `25/25` active slots; `16/41` TOC slots free). Data asset slots `14..19`:
  `14` `MONSTER.CAT` (`17,920` B / `140` recs), `15` `ITEM.CAT` (`7,478` B / `59` recs),
  `16` `HUFF_STREAM` (`3,216` B / `26` recs), `17` `TITLE.ART` (`617` B / `5` recs),
  `18` `LICENSE` (`359` B / `3` recs), `19` `SRCOFFR` (`521` B / `5` recs).

### 4.5 Shipping Release Packaging (`make diskcpm`, `tools/make_cpm_disk.py`, `tools/ensure_ctools.sh`)

`make diskcpm` (`make -C platforms/z80/cpm disk`) runs `tools/make_cpm_disk.py`
and produces four verified release media images from `build/cpm/MORIA8.COM`
(`21,598` B), `build/cpm/MORIA8.DAT` (`97,280` B), `data/LICENSE`,
`data/SOURCE-OFFER`, and `version.json['cpm']`:

| Deliverable | Format / Target | Measured M5 Size | Contents & Free Space | Round-Trip Verification |
| --- | --- | ---: | --- | --- |
| `build/moria8-cpm.zip` | RunCPM / generic CP/M 2.2 bundle | **`79,562` B** (`121,341` B raw) | `5` files: `MORIA8.COM` (`21,598` B), `MORIA8.DAT` (`97,280` B), CRLF `LICENSE` (`359` B), CRLF `SOURCE-OFFER` (`521` B), CRLF `README.TXT` (`1,583` B) | CRC (`testzip`) + byte-for-byte extraction check |
| `build/moria8-cpm-kaypro2.dsk` | Kaypro II SS/DD CP/M 2.2 (`kpii`: 40 tracks × 10×512 B, zero Track 0, 1 KB blocks, 64 dir entries) | **`204,800` B** | `4` files (`10/64` dir entries): `MORIA8.COM`, `MORIA8.DAT`, CRLF+`0x1A` `LICENSE.TXT`, `SRCOFFR.TXT`; `121/195` blocks used, **`74` blocks (`75,776` B) free** | Pure-Python independent `kpii` reader checks extents, zeroed Track 0, directory blocks 0–1 (`0xE5`), no duplicate blocks, `>= 60` free blocks |
| `build/moria8-cpm-kaypro4.dsk` | Kaypro 4 DS/DD CP/M 2.2 (`kpiv`: 80 tracks × 10×512 B, zero Track 0, 2 KB blocks, 64 dir entries) | **`409,600` B** | `4` files (`6/64` dir entries): `MORIA8.COM`, `MORIA8.DAT`, CRLF+`0x1A` `LICENSE.TXT`, `SRCOFFR.TXT`; `63/197` blocks used, **`134` blocks (`274,432` B) free** | Pure-Python independent `kpiv` reader checks extents, zeroed Track 0, directory block 1 (`0xE5`), no duplicate blocks, `>= 120` free blocks |
| `build/moria8-cpm-c128.d71` | Commodore 128 CP/M Plus 1571 DS/DD | **`349,696` B** | `4` files (`6` dir entries): `MORIA8.COM`, `MORIA8.DAT`, CRLF+`0x1A` `LICENSE.TXT`, `SRCOFFR.TXT`; `63/170` 2 KB blocks used, **`107` blocks (`214 KB`) free** | Formatted with `cformat -2`, populated with pinned `mist64/ctools` (`tools/ensure_ctools.sh` sha256 `317f84c4...`), and verified via `ctools g` byte extraction |

---

## 5. Verification Gates

| Gate | Command | Scope |
| --- | --- | --- |
| **Memory Contract & Packaging Self-Tests** | `make testcpm-memory-contract-selftest` (`make -C platforms/z80/cpm test-memory-contract-selftest`) | Runs `build_z80_assets.py --selftest`, `make_cpm_dat.py --selftest`, `make_cpm_disk.py --selftest`, and `check_memory_contract.py --selftest` (`sjasmplus` + resident/overlay/BSS/ABI/shadow/map/DMA/`INCLUDE` + `'M8CP'`/`kpii`/`kpiv` verification) |
| **Built Memory Contract Gate** | `make testcpm-memory-contract` (`make -C platforms/z80/cpm test-memory-contract`) | Verifies `MORIA8.COM`, `main.sym`, all `19` built `ovl_*.ovl` + `ovl_*.sym`, `MORIA8.DAT` 25-slot TOC parity, and Z80 `INCLUDE` / cross-overlay rules for `CPM_MILESTONE ?= m5` |
| **Shipping Packaging Gate** | `make diskcpm` (`make -C platforms/z80/cpm disk`) | Builds `MORIA8.COM` + `MORIA8.DAT`, ensures `ctools`/`cformat`, packages `.zip` / `kaypro2.dsk` / `kaypro4.dsk` / `c128.d71`, and verifies all four round-trips |
| **Headless Runner & 27-Scenario Suite** | `make testcpm` (`make testcpm-runtime`, `make testcpm-smoke`) | Runs `testcpm-memory-contract`, `make -C tools/cpm_runner test` (`sjasmplus` + `RunCPM` + `cpm_runner` dual parity, strict BDOS `IX`/`IY` clobber + stack probe, `0xD100` TPA guard, ADM-3A screen parser), and all `27` scenarios in `platforms/z80/cpm/harness_smoke.py` |
| **Catalog & Memory Budget Reports** | `python3 -B tools/check_item_catalog_ports.py --port cpm`<br>`python3 -B tools/report_memory_budgets.py --port cpm` | Verifies all `361/361` `'ITM2'` items in `MORIA8.DAT` (`ITEM.CAT`) + built resident tables and reports TPA/overlay/media headroom (`MORIA8.COM` `162` B free; `Resident BSS` `308` B free; zero tight-budget `< 64` B watchlist warnings) |
| **Root Full Regression & Playtest** | `make test` (`test-stage-cpm`), `make playtest-check`, `make playtest-gate TARGETS=cpm` | Includes CP/M contract + runtime (`testcpm`) alongside the 7 6502 ports in `make test`, ABI/unit parity in `playtest-check`, and live Z80 bot runs over `cpm_runner --control` in `playtest-gate TARGETS=cpm` |
