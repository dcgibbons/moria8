# Atari 8-Bit Memory Contract

Placement, banking, and hardware-ownership source of truth for the Atari 8-bit
port (`platforms/atari8/`). Enforced at link time by `.assert` guards in
`platforms/atari8/memory.s` and `platforms/atari8/main.s`, and at build time by
`platforms/atari8/check_memory_contract.py`.

## 1. Machine Baseline & Banking Model (`PORTB` / `$D301`)

The Atari 8-bit port targets the stock **64 KB Atari 800XL / 65XE** as its
mandatory baseline and automatically detects **128 KB Atari 130XE** extended
RAM at boot to cache overlays, the monster catalog's records, and title artwork.

Memory visibility is controlled through PIA `PORTB` (`$D301`):

| Bit | Mask | Name | Gameplay State (`$FE`) | OS `SIOV` Call State (`$FF`) | 130XE Cache Copy State (`$E2`/`$E6`/`$EA`/`$EE`) |
| ---: | --- | --- | --- | --- | --- |
| `0` | `$01` | OS ROM Enable (`$C000-$CFFF`, `$D800-$FFFF`) | `0` (RAM visible) | `1` (OS ROM visible) | `0` (RAM visible) |
| `1` | `$02` | BASIC Disable (`$A000-$BFFF`) | `1` (RAM visible) | `1` (RAM visible) | `1` (RAM visible) |
| `2..3` | `$0C` | 130XE Bank Select (`0..3`) | `11` (Bank 3 idle) | `11` (Bank 3 idle) | `00..11` (Active 16 KB bank `0..3`) |
| `4` | `$10` | 130XE CPU Extended Enable (`$4000-$7FFF`) | `1` (Main RAM) | `1` (Main RAM) | `0` (Extended bank at `$4000-$7FFF`) |
| `5` | `$20` | 130XE ANTIC Extended Enable (`$4000-$7FFF`) | `1` (Main RAM) | `1` (Main RAM) | `1` (ANTIC always sees Main RAM) |
| `6` | `$40` | Unused | `1` | `1` | `1` |
| `7` | `$80` | Self-Test ROM Disable (`$5000-$57FF`) | `1` (RAM visible) | `1` (RAM visible) | `1` (RAM visible) |

### Critical Hardware Invariants

1. **Immovable `$D000-$D7FF` Hardware I/O Window (2 KB):**
   Unlike the C64, the 2 KB hardware register window at `$D000-$D7FF` (`GTIA`
   `$D000-$D0FF`, `POKEY` `$D200-$D2FF`, `PIA` `$D300-$D3FF`, `ANTIC`
   `$D400-$D4FF`) is permanently mapped and cannot be banked out. No executable
   code or runtime data may ever link into `$D000-$D7FF`, and no block copy into
   `MAP_BASE` (`$C100-$CFFF`, `15` pages = `3,840` B) may ever write a 16th
   page into `$D000-$D0FF`.
2. **No Write-Through Under Atari XL/XE OS ROM (`CO61618` MMU) & Simultaneous `$C000-$CFFF`/`$D800-$FFFF` Banking:**
   When `PORTB` bit 0 is `1` (OS ROM visible at `$C000-$CFFF` and `$D800-$FFFF`),
   the Atari XL/XE MMU disables RAM `CAS` in both ranges simultaneously: CPU
   writes to `$C000-$CFFF` and `$D800-$FFFF` are **discarded**, and reads return
   OS/FP ROM bytes. Consequently:
   * No code at or above `$C000` may ever set `PORTB` bit 0 = `1` (which would
     unmap its own instruction stream); all routines that touch `PORTB` or read
     OS ROM (`EnterSio`, `ExitSio`, `atari_font_init`) **must execute below
     `$4000`**.
   * `SIOV` (`$E459`) can **never** read or write directly to `$C000-$CFFF` or
     `$D800-$FFFF`; all `SIOV` transfers target `sio_sector_buf` (`128` B in low
     RAM `< $4000`), and the low-RAM loader switches `PORTB = $FE` before
     copying into `$E000-$EFFF`, `$F000-$FFF9`, or `$C000-$CFFF`.
   * `save_zp` and `restore_zp` (`zp_save_buf` at `$DD40-$DDCD`) **must**
     execute while `PORTB = $FE` (RAM visible), never while `PORTB = $FF`.
   * `$0090` is reserved as `zp_kernal_status` (because
     `platforms/commodore/common/title_screen.s` clears `zp_kernal_status` at
     `$90`), and all `SIOV` sector-linking, directory parsing, and bounce-copy
     pointers (`atari_io_src`, `atari_io_dst`, `atari_io_sec`, `atari_file_idx`)
     **must** reside in platform-owned ZP at `$0092-$00AF` using named `.label`
     symbols in `platforms/atari8/memory.s` (never raw `$90-$FF` hex literals, as
     enforced by `tools/check_zp_usage.py`), so copying from `sio_sector_buf`
     after `restore_zp` never clobbers active core pointers (`zp_ptr0`/`zp_ptr1`).
3. **ANTIC Visibility During OS ROM and 130XE Banking:**
   `PORTB` bit 0 controls OS ROM visibility for **both** the CPU and ANTIC DMA.
   Because `SIOV` sets `PORTB = $FF`, all ANTIC-fetched display structures
   (`ATARI_DISPLAY_LIST` at `$0380`, `ATARI_CHARSET_BASE` at `$0400`, and
   `SCREEN_RAM` at `$0800-$0BE7`) **must reside below `$4000`** so neither OS
   ROM activation (`$C000+`) nor 130XE CPU banking (`$4000-$7FFF`, with `PORTB`
   bit 5 = `1`) ever alters ANTIC's view of the screen.
4. **130XE `$4000-$7FFF` CPU Window, Non-Maskable Interrupt (`NMI`) Hazard, & `NMIRES` (`$D40F`) Reset:**
   Setting `PORTB` bit 4 = `0` replaces Main RAM at `$4000-$7FFF` with one of
   the four 16 KB extended banks. Because 6502 `SEI` masks only `IRQ` and **does
   not mask `NMI`** (ANTIC DLI/VBI/RESET), and because ANTIC Mode 2 DMA
   (`SDMCTL = $22`) leaves `18,485` available CPU cycles per NTSC frame (`61.8%`
   of `29,868`), a 16-page (`4,096` B) copy (`~57,500–65,700` CPU cycles) spans
   `~3.1–3.5` NTSC video frames (`52–59 ms`). Leaving `NMIEN` enabled during a
   130XE bank copy would allow VBI to fire and call `hal_sound_update` (`sound.s`,
   in `$1400-$C0FF`) while `$4000-$7FFF` is banked to extended overlay data,
   crashing the CPU. Furthermore, ANTIC latches DLI/VBI/RESET events in `NMIST`
   (`$D40F`, which does **not** auto-clear on read) even while `NMIEN` is `$00`.
   Therefore:
   * All low-level banking, `atari_font_init`, `SIOV` bounce (`EnterSio`,
     `ExitSio`, `save_zp`, `restore_zp`, `hal_storage_*`,
     `atari_write_sio_sector`), `exit_trampoline`, interrupt (`atari_nmi_handler`,
     `atari_irq_handler`), and 130XE routines (`xe_detect`, `xe_cache_stash`,
     `xe_cache_fetch`) **must link and execute below `$4000`** (at the start of
     `Default` in `$0C00-$225A`, `low_helpers_end = $225B`), enforced by link-time `.assert` guards and
     `platforms/atari8/check_memory_contract.py`.
   * `atari_nmi_handler` preserves `A`, `X`, and `Y` (`PHA/TXA/PHA/TYA/PHA`) and
     inspects `NMIST` (`$D40F`): if bit 5 (`$20`, physical `SYSTEM RESET` button
     NMI on XL/XE) is set, it jumps directly to `exit_trampoline`; otherwise it
     checks bit 7 (`$80`, DLI) and bit 6 (`$40`, VBI) independently and writes
     `STA NMIRES ($D40F)` once before restoring registers and `RTI` (because
     `NMIRES` is a strobe that clears all `NMIST` flip-flops simultaneously).
   * `xe_cache_stash` and `xe_cache_fetch` **must** set `SEI` **and** write
     `LDA #$00 : STA NMIEN ($D40E)` before switching `PORTB` to
     `$E2`/`$E6`/`$EA`/`$EE`, and on exit restore `PORTB = $FE`, clear latched
     ANTIC NMI flags via `STA NMIRES ($D40F)`, and then write
     `LDA #$C0 : STA NMIEN ($D40E)` before restoring caller `P`.
5. **Mandatory `EnterSio` / `ExitSio` Protocol (`$E459`):**
   Calling Atari OS ROM `SIOV` (`$E459`) requires strict zero-page, shadow
   register, DCB timeout, POKEY audio, `NMIRES`, `NMIEN`, and Carry-flag
   discipline to prevent Error `$80` (Break abort), Error `$8A`/`$8C`
   (19,200-baud DLI `WSYNC` serial overrun or uninitialized timeout), OS Stage 2
   VBI crashes, mid-SIO `SYSTEM RESET` wild jumps, phantom DLI glitches,
   post-SIO POKEY audio droning, and lost error flags:
   * **`EnterSio` (in low RAM `< $4000`):**
     1. Save caller `I` interrupt mask, then execute `SEI`,
        `LDA #$00 : STA NMIEN ($D40E)`, and `STA $D20E` (`IRQEN = $00`) while
        `PORTB = $FE`.
     2. Call `save_zp` (copies `$02-$8F` to `zp_save_buf` at `$DD40-$DDCD` while
        `PORTB = $FE`).
     3. Initialize OS ZP and DCB fields required by `SIOV`:
        * `WARMST` (`$0008`) = `$00` (so pressing physical `SYSTEM RESET` while
          `PORTB = $FF` falls through OS `WARMSV` `$E474` cleanly to `COLDSV`
          `$E477` instead of jumping through `DOSINI` `$000C` / `zp_temp4`)
        * `POKMSK` (`$0010`) = `$00` (prevents `SIOV` from enabling stray timer
          IRQs from game `zp_screen_hi`)
        * `BRKKEY` (`$0011`) = `$FF` (`0` in `$11` [`zp_color_lo`] causes `SIOV`
          to abort immediately with Error `$80` Break!)
        * `SOUNDR` (`$0041`) = `$00` (silences noisy OS `SIOV` sector-read
          beeps during boot and runtime disk I/O)
        * `CRITIC` (`$0042`) = `$01` (inhibits OS Stage 2 VBI so `SIOV` only
          runs lightweight OS Stage 1 VBI for `CDTMV1` timeout decrementing and
          never vectors through `VVBLKD` `$0224`)
        * `ATRACT` (`$004D`) = `$00` (prevents OS Stage 1 VBI attract-mode color
          cycling if `zp_equip_idx >= $80`)
        * `DDEVIC` (`$0300`) = `$31`, `DUNIT` (`$0301`) = `device - 7` (`1..4`
          for HAL devices `8..11`), and `DTIMLO` (`$0306`, `DCB + 6`) = `$07`
          (`7`-second timeout copied by `SIOV` into `CDTMV1` `$0218-$0219`).
     4. Synchronize OS Page 2 display shadow registers (`SDMCTL` `$022F = $22`,
        `SDLSTL/H` `$0230/$0231 = $0380`, `GPRIOR` `$026F = $00`, `COLOR1`
        `$02C5 = $0E`, `COLOR2` `$02C6 = $00`, `COLOR4` `$02C8 = $00`, `CHACT`
        `$02F3 = $02`, `CHBAS` `$02F4 = $04`) so the screen renders cleanly in
        monochrome while DLIs are disabled during disk I/O.
     5. Set `PORTB = $FF` (OS ROM visible), clear `STA NMIRES ($D40F)`, and set
        `LDA #$40 : STA NMIEN ($D40E)` (**VBI enabled** so OS Stage 1 VBI
        decrements `CDTMV1` `$0218-$0219` for `SIOV` timeout tracking; **DLI
        disabled** so `STA WSYNC` never stalls POKEY serial IRQs or vectors
        through OS `VDSLST` `$0200`).
     6. `JSR $E459` (`SIOV`).
   * **`ExitSio` (in low RAM `< $4000`):**
     1. `SEI` and `LDA #$00 : STA NMIEN ($D40E)`.
     2. Set `PORTB = $FE` (RAM visible at `$C000-$CFFF` and `$D800-$FFFF`).
     3. Call `restore_zp` (copies `zp_save_buf` at `$DD40-$DDCD` back to
        `$02-$8F` while `PORTB = $FE`).
     4. Silence POKEY audio channels (`LDA #$00 : STA $D201 : STA $D203 : STA $D205 : STA $D207`,
        clearing the serial clock/tone state left in Channels 3 & 4 by `SIOV`),
        re-initialize POKEY keyboard scan + BREAK/Keyboard IRQs (`AUDCTL = $00`,
        `SKCTL = $03`, `IRQEN = $00` then `$C0`), clear `STA NMIRES ($D40F)`, and
        restore `NMIEN = $C0` (DLI + VBI).
     5. Restore caller `I` interrupt mask (via `CLI` if interrupts were enabled,
        **never** via blind `PLP`), and set Carry from `DSTAT` (`$0303`: `CLC` if
        `DSTAT == $01`, `SEC` if `DSTAT != $01`) so callers (`bcs sio_error`)
        receive the exact `SIOV` completion status.

---

## 2. 64 KB Main Memory Map (`$0000-$FFFF`)

| Address Range | Size | Owner | Notes |
| --- | ---: | --- | --- |
| `$0000-$0001` | 2 B | System / Boot Flags | Preserved for OS compatibility |
| `$0002-$008F` | 142 B | Shared Core ZP (`core/zeropage.s`) | Game-owned during normal execution (`PORTB = $FE`). Saved to `zp_save_buf` (`$DD40-$DDCD`) and restored across ROM `SIOV` calls via `EnterSio`/`ExitSio`. |
| `$0090-$00FF` | 112 B | Platform Storage / Bounce / OS ZP | `$0090` is reserved as `zp_kernal_status` (cleared by `title_screen.s`). `$0092-$00AF` holds named Atari platform storage/bounce pointers (`atari_io_src`, `atari_io_dst`, `atari_io_sec`, `atari_file_idx`, `save_stream` state) so `SIOV` bounce copies never touch core ZP `$02-$8F`. |
| `$0100-$01FF` | 256 B | Hardware Stack | Standard 6502 stack |
| `$0200-$031A` | 283 B | Atari OS Vectors, Page 2 Shadows, & DCB | **Untouched by game code/data.** Preserves OS interrupt vectors (`$0200-$0229`), display/timer shadows (`$022F-$02F4`), `DVSTAT` (`$02EA`), and `SIOV` DCB (`$0300-$030B`). |
| `$031B-$033B` | 33 B | SIO Sector Link / Directory Scratch | Platform storage state |
| `$033C-$037F` | 68 B | `DUNGEON_GEN_DOOR_SCAN_BASE` | Door-scan scratch (`65` B required; matches C64/Plus/4/Apple IIe `$033C` base) |
| `$0380-$03BF` | 64 B | `ATARI_DISPLAY_LIST` | Custom 40×25 ANTIC Mode 2 Display List (`32` B active). Contained within `$0000-$03FF` 1 KB boundary and untouched by `SIOV`. |
| `$03C0-$03E7` | 40 B | OS printer buffer `PRNBUF` (game-owned) | Only the `P:` handler uses it and the game never opens `P:`; SIOV never touches it (2026-11-11, out of a full `Default`): `atari_fn_83` (11 B, every writer fills all 11), `atari_kbdbuf_len` + `atari_kbdbuf` (9 B, `input_init` clears the length before the IRQ runs), `atari_dir_count_lo/hi`, `xe_present`, `xe_saved_main` (4 B, each written before it is read); 16 B spare. `xe_slot_populated` (`18` B) stays in low resident (`check_memory_contract.py` requires `$0C00-$3FFF`). |
| `$03E8-$03FF` | 24 B | XL OS variables | **Never touch:** `GINTLK` (`$03FA`), `BASICF` (`$03F8`) and others the OS reads (the cartridge check); the file name there broke the `a800xl` save (2026-11-11). |
| `$0400-$07FF` | 1,024 B | `ATARI_CHARSET_BASE` (`CHBASE = $04`) | 1 KB RAM character set ordered by Moria8/C64 screen codes (`$00-$7F`), built at boot by `atari_font_init` (executing in `< $4000`) from the Atari OS ROM font (`$E000-$E3FF`). 1 KB-aligned as required by ANTIC. |
| `$0800-$0BFF` | 1,024 B | `SCREEN_RAM` & `DUNGEON_GEN_SCAN_SCRATCH_BASE` | During OS disk boot, 3-sector `boot.s` (`<= $0980`, `384` B) loads at `$0800-$097F` (`boot_entry` at `$0806` runs `SEI : CLD : LDX #$FF : TXS : STX $D301` to disable BASIC ROM at `$A000-$BFFF` while keeping OS ROM visible), activates a centered black-screen ANTIC Mode 6 banner (`"  LOADING MORIA8... "`), stages 128-byte sectors at `$0980-$09FF`, and streams & **PackBits-unpacks** `MORIA8.RES` (`MORIA8.PKB`, `45,886 -> 40,776 B` payload, `-5,110 B`) into `$0C00-$C0FF` (keeping `PORTB = $FF` until `atari_io_dst_hi >= $BF` and switching `PORTB = $FE` for `$BF00-$C0FF` and handoff) before jumping to `entry_main` (`$0C00`). On `.car`, `cartridge_boot.s` (`Bank 0` `$A000`, copied to `$0800` with 256-byte ROM page prefetch at `$0900-$09FF` and `$D510` cart disable between pages) PackBits-unpacks `MORIA8.PKB` directly into `$0C00-$C0FF`. Once `entry_main` activates the custom Display List, `$0800-$0BE7` (`1,000` B) is the 40×25 ANTIC Mode 2 screen buffer, and `$0800-$0BFF` (`1,024` B) doubles as page-aligned `DUNGEON_GEN_SCAN_SCRATCH_BASE` during level generation. |
| `$0C00-$23C4` | 6,085 B | Low Resident Banking, Boot Init, Interrupt, & I/O Helpers (`< $4000`) | Guaranteed below `$4000` (`low_helpers_end = $23C5` disk [`7,227 B` free] / `$213D` cart [`7,875 B` free]): `entry_main` boot init, `atari_font_init`, `EnterSio`/`ExitSio`, `save_zp`/`restore_zp`, `sio_sector_buf` (`128` B), `hal_asset_load_prg_header` (caches overlays via `atari_ovl_xe_slot` across Slots `0..17`, `OVL.TTL` `$FF` uncached), `hal_asset_load_title`, `hal_storage_probe_media`, `atari_write_sio_sector`, `hal_storage_open`/`chrin`/`chrout`/`close`, legal DOS 8.3 filenames, Help controller `cmd_show_help_view`, **57-byte/record `MONSTER.CAT` reader + `catalog_fetch_ext`** (`monster_catalog_a8.s`, `cat_record[57]` with `cat_ext_record` at `+49`), `'ITM2'` item-catalog (`item_catalog_a8.s`), `find_special_room`, `xe_detect`, `xe_cache_stash`/`xe_cache_fetch`, `xe_slot_populated` (`18` B), `exit_trampoline`, `atari_nmi_handler`, `atari_irq_handler`, and banked/exit trampolines. |
| `$23C5-$C038` | 40,052 B | Resident `Default` Segment (`program_end = $C039 <= $C100`) | Core gameplay (`29` SoA `cr_*` fields, `4` attacks, `19` `ADESC_*` verbs, hot `ATK_*` effects, `5` `MSF2_*` spells, `CD_*`/`CM2_*`), resident `player_cast_spell`/`player_pray` selection shell + `player_magic_cast_cold.s` (`PLAYER_CAST_RESIDENT`), UI, `40`-col recall tables (`recall_defs.s`), `item_hot_tables.s`, `recall[279]` (`1,116` B), `id_known_bits[47]`, `potion_shuffle..staff_shuffle` (`174` B), `si_meta_hi[128]`, `fi_meta_hi[42]`, town roster, shared save-state arrays/magic, `hal_overlay_post_reload`, generated overlay trampolines (`build/trampolines/atari8_trampolines.inc`), and custom resident trampolines. `46,137` B total span in `$0C00-$C038` (**`199` B free** below `$C100` on disk; `$0C00-$BCF1`, `45,298` B, **`1,038` B free** on cartridge). |
| `$C100-$CFFF` | 3,840 B | `MAP_BASE` (`$C100-$CFFF`) | Live 80×48 dungeon map (`15` pages = `3,840` B = `$0F00` B), ending immediately below the `$D000` hardware I/O window. `CREATURE_BASE` (`$C120-$C1FF`) aliases map scratch during save/game-over, matching C64/Plus/4. `TITLE.DAT` links at `.pc = $C100` (`platforms/atari8/title_data.s`) and copies `3` pages (`768` B) into `$C100-$C3FF`. No executable code is ever linked into `$C100-$CFFF`. |
| `$D000-$D7FF` | 2,048 B | **Hardware I/O Hole (Forbidden to Code/Data)** | `GTIA` (`$D000-$D0FF`), `POKEY` (`$D200-$D2FF`), `PIA` (`$D300-$D3FF`), `ANTIC` (`$D400-$D4FF`). |
| `$D800-$DBFF` | 1,024 B | `PLATFORM_TIER_NAME_POOL_BASE` | The level's monster catalog names, 32 B per species slot (asserted in `core/monster_catalog.s`), in RAM under OS ROM. |
| `$DC00-$DCFF` | 256 B | `FLOOR_ITEM_BASE` | Active level floor-item table (`252` B + `4` B spare). |
| `$DD00-$DD3F` | 64 B | `PLATFORM_HD_DECODE_BUF_BASE` | Huffman decode buffer (`HD_DECODE_BUF_SIZE = 64` B in `core/huffman.s`). |
| `$DD40-$DDCD` | 142 B | `zp_save_buf` | Saved game ZP (`$02-$8F`) accessed only while `PORTB = $FE`. |
| `$DDCE-$DF0D` | 320 B | `msg_history` (`HighResident` `virtual` BSS) | 8-message × 40-byte ring buffer (`core/ui_messages.s`, cleared at startup by `msg_log_clear`), funding resident headroom below `$C100`. |
| `$DF0E-$DF3D` | 48 B | `item_name_decode_buf` (`HighResident` `virtual` BSS) | Item-name decode buffer (`PLATFORM_ITEM_NAME_BUF_LOW`). |
| `$DF3E-$DFC3` | 134 B | Scratch buffers, `nf_digit_buf`, `consol_released` (`HighRAM Tail`) | `combat_msg_buf`, the creature-name buffer, `pm_spell_list`, the tier-loader counters, the inventory picker's visible slots, the monster-death queue, the chest-loot scratch, `nf_digit_buf` (`8` B), and `consol_released` (`1` B at `$DFC3`). `potion_shuffle..staff_shuffle` (`174` B) and `id_known_bits` (`47` B) moved back to `Default` in Phase 4 (`2026-11-15`), leaving **`60` B free** in `$DFC4-$DFFF`. |
| `$DFC4-$DFFF` | 60 B | `HighRAM Tail` Uninitialized BSS Spare | Uninitialized RAM under OS ROM (`PORTB = $FE`; `virtual` segment, never emitted to `MORIA8.RES`). |
| `$E000-$EFFF` | 4,096 B | `BANKED_DATA_BASE` (Overlay & Tier Window) | Shared 4 KB execution/staging window for the 13 code overlays (`OVL.STA`..`OVL.GEN`, `OVL.HOM`, `OVL.STO`, cold `OVL.TTL`), uncached `LEGALUI`, and, at 130XE boot only, the staging of `MONSTER.CAT` sectors, identical to C64 and Plus/4. |
| `$F000-$FFF9` | 4,090 B | `RuntimeBanked` Segment | Load-once banked runtime (`$F000-$FFA0` used = `4,001` B, **`89` B free** on disk; `$F000-$FEBE` = `3,775` B, **`315` B free** on cartridge): `generation_busy.s`, `catalog_index.s` (including `cat_undead[35]`), `pick_undead_creature_type` (`core/monster_magic.s` `:UndeadPickSegment()`, beside `cat_undead`; 2026-11-20, MON-041), `mae_cold_body` (zero-HP cold melee attack effects), `run_initialize_impl`, `store_data.s`, `runtime_ui_strings.s`, `ego_items.s`, `item_desc_banked.s`, `ui_help_clear.s`, `legal.s` (`tramp_ui_legal_display`), `ui_status.s` (`:StatusTextSegment()`), equipment flags (`player.s` `:PflagsSegment()`), `disk_prompt_save`/`disk_prompt_game`/`disk_prompt_game_required`, and `eff_gain_stat.s`. |
| `$FFFA-$FFFF` | 6 B | Hardware CPU Vectors (`NMI`, `RESET`, `IRQ`) | Installed in RAM under OS ROM (`$FFFA` -> `atari_nmi_handler`, `$FFFC` -> `exit_trampoline` in `< $4000`, `$FFFE` -> `atari_irq_handler`) for execution while `PORTB = $FE`. |

---

## 3. 130XE Extended RAM Cache Contract (`64 KB` = 4 × 16 KB Banks at `$4000-$7FFF`)

When `xe_detect` (linked and executed strictly below `$4000` in `$0C00-$225D`)
confirms 130XE extended RAM at boot (non-aliasing probe across banks `0..3` at
`$4000` with Main RAM preserved), the `64 KB` extended-RAM pool (`4` banks ×
`64` pages/bank = `256` pages total, defined by `XE_WIN_BASE_HI = $40`,
`XE_WIN_LIMIT_HI = $80`, `XE_BANK_PAGES = 64`, `XE_TOTAL_PAGES = 256` in
`platforms/atari8/memory.s`) uses **page-packed allocation** across Banks `0..3`
(`platforms/atari8/storage.s`: `xe_slot_portb`, `xe_slot_win_hi`,
`xe_slot_ram_hi`, `xe_slot_pages`, indexed for overlays via `atari_ovl_xe_slot`)
instead of fixed 16-page (`4 KB`) slots.
Each slot (`0..17`) is sized to its payload's exact page-ceiled page count,
packed contiguously inside one 16 KB bank without crossing `$7FFF`, and
tracked in low RAM by `xe_slot_populated` (`$00` = cold [bit 7 = `0`];
`$E2`/`$E6`/`$EA`/`$EE` = populated `PORTB` byte [bit 7 = `1`]); cold `OVL.TTL`
(`atari_ovl_xe_slot[12] = $FF`) loads on demand at title/new-game so 100% of
gameplay overlays, `57 B/record` `MONSTER.CAT`, and `TITLE.DAT` stay RAM-cached:

### Bank-Order Packed Layout (`256/256` Pages Used, `0` Pages Free, Slots `0..17`)

| 130XE Bank | `PORTB` | Slot ID | Window Range | Pages (Bytes) | Cached Payload | Copy Span / Dest | Boot Policy |
| --- | --- | ---: | --- | ---: | --- | --- | --- |
| Bank 0 (`64/64` p, `0` free) | `$E2` | `0` | `$4000-$4FFF` | `16` (`4,096` B max; `4,024` B) | `OVL.STA` (`OVL_STARTUP = 1`) | `16` pages -> `$E000` | Preloaded |
| Bank 0 | `$E2` | `5` | `$5000-$5FFF` | `16` (`4,096` B max; `3,795` B) | `OVL.UI` (`OVL_UI = 6`, owns `ui_inventory.s` + spell names/list/study) | `16` pages -> `$E000` | Preloaded |
| Bank 0 | `$E2` | `9` | `$6000-$6FFF` | `16` (`4,096` B max; `4,024` B) | `OVL.CHS` (`OVL_CHEST = 10`) | `16` pages -> `$E000` | Preloaded |
| Bank 0 | `$E2` | `10` | `$7000-$7FFF` | `16` (`4,096` B) | `MONSTER.CAT` secs 0–31 (cat slot 0) | `32 × 128` B secs, **57 B** -> `cat_record` | Preloaded |
| Bank 1 (`64/64` p, `0` free) | `$E6` | `11` | `$4000-$4FFF` | `16` (`4,096` B) | `MONSTER.CAT` secs 32–63 (cat slot 1) | `32 × 128` B secs, **57 B** -> `cat_record` | Preloaded |
| Bank 1 | `$E6` | `12` | `$5000-$5FFF` | `16` (`4,096` B) | `MONSTER.CAT` secs 64–95 (cat slot 2) | `32 × 128` B secs, **57 B** -> `cat_record` | Preloaded |
| Bank 1 | `$E6` | `13` | `$6000-$6FFF` | `16` (`4,096` B) | `MONSTER.CAT` secs 96–127 (cat slot 3) | `32 × 128` B secs, **57 B** -> `cat_record` | Preloaded |
| Bank 1 | `$E6` | `16` | `$7000-$7FFF` | `16` (`4,096` B max; `3,856` B) | `OVL.HOM` (`OVL_HOME = 11`) | `16` pages -> `$E000` | Preloaded |
| Bank 2 (`64/64` p, `0` free) | `$EA` | `1` | `$4000-$4EFF` | `15` (`3,840` B max; `3,807` B) | `OVL.TWN` (`OVL_TOWN = 2`) | `15` pages -> `$E000` | Preloaded |
| Bank 2 | `$EA` | `3` | `$4F00-$5DFF` | `15` (`3,840` B max; `3,838` B) | `OVL.GEN` (`OVL_DUNGEON_GEN = 4`) | `15` pages -> `$E000` | Preloaded |
| Bank 2 | `$EA` | `7` | `$5E00-$6DFF` | `16` (`4,096` B max; `3,962` B) | `OVL.SPL` (`OVL_SPELL = 8`, owns `calc_spell_failure` + `spell_execute_selected`) | `16` pages -> `$E000` | Preloaded |
| Bank 2 | `$EA` | `17` | `$6E00-$7CFF` | `15` (`3,840` B max; `3,641` B disk) | `OVL.STO` (`OVL_STORAGE = 12`) | `15` pages -> `$E000` | Preloaded |
| Bank 2 | `$EA` | `14` | `$7D00-$7FFF` | `3` (`768` B max; `621` B) | `TITLE.DAT` (Title Artwork) | **3 pages (`768` B) -> `MAP_BASE` (`$C100`)** | Cached on title draw |
| Bank 3 (`64/64` p, `0` free) | `$EE` | `2` | `$4000-$4DFF` | `14` (`3,584` B max; `3,527` B) | `OVL.DTH` (`OVL_DEATH = 3`, owns `ui_recall.s`) | `14` pages -> `$E000` | Preloaded |
| Bank 3 | `$EE` | `4` | `$4E00-$5CFF` | `15` (`3,840` B max; `3,748` B) | `OVL.HLP` (`OVL_HELP = 5`, owns `ui_character.s` + `ui_equipment.s` + `player_item_commands.s`) | `15` pages -> `$E000` | Preloaded |
| Bank 3 | `$EE` | `6` | `$5D00-$6BFF` | `15` (`3,840` B max; `3,281` B) | `OVL.ITM` (`OVL_ITEMS = 7`) | `15` pages -> `$E000` | Preloaded |
| Bank 3 | `$EE` | `8` | `$6C00-$79FF` | `14` (`3,584` B max; `3,317` B) | `OVL.MDL` (`OVL_MODAL_MISC = 9`) | `14` pages -> `$E000` | Preloaded |
| Bank 3 | `$EE` | `15` | `$7A00-$7FFF` | `6` (`1,536` B) | `MONSTER.CAT` secs 128–139 (cat slot 4) | `12 × 128` B secs, **57 B** -> `cat_record` | Preloaded |

- **Slot-ID Reference Order:** `0..9` remain `OVL.STA`..`OVL.CHS`, `10..13` and `15` hold `MONSTER.CAT` (`a8_cat_xe_slots = [10, 11, 12, 13, 15]`, `140` sectors @ `57 B/record`), `14` holds `TITLE.DAT`, and `16..17` hold `OVL.HOM` and `OVL.STO` (`atari_ovl_xe_slot = [0..9, 16, 17, $FF]` in `platforms/atari8/storage.s`; cold `OVL.TTL` is `$FF` uncached).
- **Boundary Constants:** `platforms/atari8/storage.s` exports `XE_BANK0..3_USED_PAGES` (`64` each), `XE_BANK0..3_FREE_HI` (`$80`), `XE_BANK0..3_FREE_PAGES` (`0`), `XE_TOTAL_USED_PAGES` (`256`), and `XE_TOTAL_FREE_PAGES` (`0`).

### 130XE Cache Execution Rules

* `xe_detect`, `xe_cache_stash`, and `xe_cache_fetch` must link and execute
  below `$4000` (enforced by `.assert "Low helpers stay below $4000", low_helpers_end <= $4000, true`)
  and use named platform ZP pointers in `$0092-$00AF`.
* **9-Cycle Direct `PORTB` Hit Test:** Because `xe_slot_populated[slot]` stores
  `$00` when unpopulated and the target `PORTB` value (`$E2`, `$E6`, `$EA`, or
  `$EE`, all having bit 7 = `1`) when populated, cache lookup (`ldx slot_idx :
  lda xe_slot_populated,x : bpl miss`) resolves in 9 cycles and yields the exact
  `PORTB` value in `A`.
* **Atomic NMI & IRQ Masking + `NMIRES` Clear During 130XE Bank Swaps:**
  Because copying up to 16 pages (`4,096` B) takes up to `~57,500–65,700` CPU
  cycles (`~3.1–3.5` NTSC video frames = `52–59 ms` under ANTIC Mode 2 DMA), and
  because 6502 `NMI` is non-maskable by `SEI`, `xe_cache_stash` and
  `xe_cache_fetch` **must** disable ANTIC NMIs via `LDA #$00 : STA NMIEN ($D40E)`
  in addition to `SEI` before switching `PORTB` to extended RAM (`$E2`/`$E6`/`$EA`/`$EE`).
  During the copy, ANTIC DMA continues displaying Main RAM seamlessly (`Bit 5 = 1`);
  on completion, `PORTB` is restored to `$FE`, `STA NMIRES ($D40F)` clears any
  DLI/VBI flags latched during the copy, and `NMIEN` is restored to `$C0` (DLI +
  VBI) before `PLP` and `RTS`.
* **Copy-Span Safety:** Every slot `0..17` transfers strictly `xe_slot_pages[slot]`
  pages (never fixed 16 pages). In particular, Slot 14 (`TITLE.DAT` -> `MAP_BASE`
  at `$C100`) copies **only 3 pages (`768` B)** (`$C100 + $0300 <= $D000`),
  preventing both `$7FFF` bank overflow in Bank 2 (`$7700 + $0300 = $7A00`) and
  `$CFFF` -> `$D000` GTIA clobbering; all `OVL.*` (`0..9, 16..17`; cold `OVL.TTL` uncached `$FF`) and `MONSTER.CAT`
  (`10..13, 15`) spans are link-time `.assert`-checked and checker-validated so
  `actual_pages <= xe_slot_pages[slot]`.

---

## 4. Verification Gates

1. **Link-Time Assertions (`platforms/atari8/memory.s`, `storage.s`, `monster_catalog_a8.s`, & `main.s`):**
   * `low_helpers_end <= $4000` (`entry_main` boot init, `atari_font_init`, `EnterSio`, `ExitSio`, `sio_sector_buf`, `hal_asset_load_prg_header`, `xe_detect`, `xe_cache_*`, `exit_trampoline`, `atari_nmi_handler`, `atari_irq_handler`)
   * `program_end <= MAP_BASE` (`$C100`)
   * `MAP_END == $CFFF` (`3,840` B exact fit below `$D000`)
   * Every overlay (`StartupOverlay`..`DungeonGenOverlay`, `HomeOverlay`, `StorageOverlay`, `TitleOverlay`) fits within `$E000-$EFFF` and fits its exact `XE_SLOT*_PAGES * 256` budget (`#if !ATARI8_CARTRIDGE`)
   * 130XE window/bank/slot assertions: `XE_WIN_LIMIT_HI - XE_WIN_BASE_HI == XE_BANK_PAGES`, `XE_TOTAL_PAGES == XE_BANK_PAGES * 4`, each Bank `0..3` `XE_BANK*_FREE_HI <= XE_WIN_LIMIT_HI`, `XE_TOTAL_USED_PAGES + XE_TOTAL_FREE_PAGES == XE_TOTAL_PAGES`, `XE_SLOT14_RAM_HI + XE_SLOT14_PAGES <= >$D000`, `XE_SLOT10..13_PAGES == 16`, and `(A8_CATALOG_SECTORS - 128 + 1) / 2 <= XE_SLOT15_PAGES`
   * `banked_code_end <= $FFFA` (below hardware vectors `$FFFA-$FFFF`)
   * `ATARI_DISPLAY_LIST` does not cross a 1 KB boundary (`((>ATARI_DISPLAY_LIST) & $fc) == ((>ATARI_DISPLAY_LIST_END) & $fc)`)
   * `ATARI_CHARSET_BASE` is 1 KB aligned (`(<ATARI_CHARSET_BASE) == 0 && ((>ATARI_CHARSET_BASE) & 3) == 0`)
   * Serialized Save Format V2 size (`7,858` B stream, `ATARI_SAVE_SERIALIZED_MAX` conservative bound) fits within `ATARI_SAVE_SLOT_SECTORS * 125` (`68 * 125 = 8,500` B); `SAVE_VERSION = $22` (`hal_storage_save_version = $22`, exact match required)
2. **Static Contract Checker (`platforms/atari8/check_memory_contract.py`):**
   * `make testatari8-memory-contract` and `make testatari8-memory-contract-selftest` (13 tests including 8 negative 130XE slot-packing/bounds/overflow tests)
   * Verifies symbol extents from `build/atari8/main.sym` (and `build/atari8-cart/main.sym` when built), rejects any symbol or segment overlap with `$0200-$031A` (OS Page 2 / DCB), `$C100-$CFFF` (`MAP_BASE`), or `$D000-$D7FF` (Hardware I/O), verifies `< $4000` residency of all banking/SIO/130XE/interrupt/exit/font helpers, checks all PRG payload spans, and reads `xe_slot_portb`/`xe_slot_win_hi`/`xe_slot_ram_hi`/`xe_slot_pages` directly from `MORIA8.RES` to assert valid `PORTB` banks, `$4000-$7FFF` bounds, per-bank non-overlap, `TITLE.DAT` `$D000` safety, and `actual_pages <= xe_slot_pages[slot]` against built `OVL.*`, `TITLE.DAT`, and `MONSTER.CAT` payloads.
3. **Runtime MAME Verification (`platforms/atari8/harness_smoke.py`):**
   * `make testatari8-runtime` runs headless MAME across the 16-scenario behavioral suite on `a800xl` (64 KB disk-overlay baseline) plus 5 130XE cache/SIO/legal scenarios on `a130xe` (checking `xe_all_18_slots_preloaded` for slots `0..17`) when `ATARI8ROMS` is set (and warns/skips gracefully when `ATARI8ROMS` is unset); `make testatari8-cartridge` runs the 4-scenario (`6`-MAME-run) AtariMax `.car` (`ATARI8_CARTRIDGE`) suite across `a800xl` and `a130xe`.

## AtariMax 128 KB Cartridge Mode (`ATARI8_CARTRIDGE`, 2026-11-12)

`make cartridgeatari8` builds the optional `-define ATARI8_CARTRIDGE` edition (`build/moria8-atari8.car`, `.car` Type `41`, `16 × 8 KB` ROM banks at `$A000-$BFFF` via `$D500-$D50F` bank select / `$D510` disable) without altering the standard `ATARI8` disk build (`build/moria8-atari8.atr`).
- Bank 0 copies a relocatable `boot_copier` into `SCREEN_RAM` (`$0800`) and bounces `MORIA8.RES` (`$0C00–$B53F`) through `$0900-$09FF` with `$D510` disabled so writes beneath `$A000-$BFFF` hit Main RAM, then syncs `OS_GINTLK` (`$03FA`) to `TRIG3` (`$D013`).
- Runtime `cart_read` (`platforms/atari8/cartridge_copy.s`) executes strictly below `$4000`, disables NMIs and IRQs, rejects post-boot RAM destinations inside `$A000-$BFFF`, copies overlays (`$E000-$EFFF`), `RuntimeBanked` (`$F000`), `TITLE.DAT` (`$C100`), `279 × 57` B catalog records (`cartridge_catalog.s`), `'ITM2'` `ITEM.CAT` pages (`item_catalog_a8.s`), and `LICENSE`/`SOURCE-OFFER` (`legal_stream.s`), then disables the cartridge (`$D510`), re-syncs `$03FA = $D013`, and restores `NMIEN`/`IRQ`.
- Saves, loads, and high scores remain on DOS 2.5 floppy images (`D1:` default on cartridge, `D1:`–`D4:` configurable); see [ATARI8_CARTRIDGE_EXPERIMENT.md](ATARI8_CARTRIDGE_EXPERIMENT.md).

## License/source modal ownership (2026-11-10)

`LEGALUI` is an uncached modal loaded on title `A` (About) or Help `L`: $E000-$EFFF; legal controller (`legal.s`) in RuntimeBanked, Help controller (`ui_help_command.s`) in Default, and canonical 8.3 filename constants/matcher (`atari_legal_filename`) in low-resident Default (< $4000) parsed before SIO mapping.
Code ends before overlay base+$600; a 142-byte core-ZP snapshot starts there,
and the disk/ROM input cache occupies base+$700..+$7FF. Both are modal
workspace, never game-data loans or emitted PRG padding. The resident entry saves core ZP before asset loading, after any media
handler that may itself load an overlay.
The viewer reads existing documents through the storage HAL, closes every
channel, retains live sound/redraw state, and restores the caller snapshot.
Linked payload bounds and production-path modal entry/return tests enforce
this ownership. See `docs/LEGAL_VIEWER.md` for the change and verification record.

Verification (2026-11-10): `make -j7 -O test` passed, including the memory-
contract self-tests, linked payload bounds, the a800xl title/Help legal-viewer
scenario, and the existing a130xe cache/SIO regressions. Low SIO helpers and
RuntimeBanked remain inside their asserted limits.

Review repair: legal names use the canonical DOS 8.3 tables in RuntimeBanked;
the low stream adapter matches the complete read-only name before SIO.
No L*/S* prefix aliasing or duplicate legal filename strings remain.
The 130XE runtime suite includes the Help/legal modal and missing-file path.

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

## Phase 1: 130XE Page-Packed Bank Allocation (2026-11-14)

Replaces fixed `4 KB` (`16`-page) slot rounding across 130XE Extended Banks `0..3`
(`$4000-$7FFF`) with contiguous page-packed allocation per bank (`221/256` pages
used, `35` contiguous free pages = `8,960` B reclaimed at Bank 3 `$5D00-$7FFF`).

### Change Record (`docs/BEHAVIOR_CHANGE_PROTOCOL.md`)

```text
Problem and success criteria: Fixed 16-page (4 KB) rounding across 130XE Slots 0..15 wasted 35 pages (8,960 B) across underfilled overlays (OVL.GEN, OVL.HLP, OVL.MDL, OVL.DTH, OVL.CHS), MONSTER.CAT slot 4 (Slot 15, 6 pages), and TITLE.DAT (Slot 14, 3 pages), leaving 0 free pages in Banks 0..3. Success criteria: size every slot to its exact page-ceiled payload without silent truncation or crossing $7FFF, preserve Slots 0..15 IDs and copy semantics, reclaim contiguous extended-RAM headroom at Bank 3 tail (XE_BANK3_FREE_HI = $5D, XE_BANK3_FREE_PAGES = 35), keep low_helpers_end < $4000, program_end <= $C100, HighResident ($D800-$DFFF), and ATARI8_CARTRIDGE unchanged, and enforce non-overlap/bounds/payload fit via link-time .asserts and check_memory_contract.py.
State being changed: 130XE static slot descriptor tables xe_slot_portb, xe_slot_win_hi, and xe_slot_pages in platforms/atari8/storage.s (re-packed across $4000-$7FFF Banks 0..3), plus new link-time boundary constants XE_WIN_BASE_HI/XE_WIN_LIMIT_HI/XE_BANK_PAGES/XE_TOTAL_PAGES (platforms/atari8/memory.s) and XE_SLOT*_PAGES/XE_SLOT*_WIN_HI/XE_BANK*_FREE_HI/XE_BANK*_FREE_PAGES (platforms/atari8/storage.s).
Search scope and terms: Searched platforms/atari8/, core/, platforms/commodore/, and tools/ for xe_slot_, xe_cache_, a8_cat_xe_, $E2/$E6/$EA/$EE, and $4000-$7FFF references across .s, .py, and Makefile build rules.
Relevant readers/writers found and known exclusions: Readers of xe_slot_portb/win_hi/ram_hi/pages are xe_cache_stash, xe_cache_fetch, and hal_asset_load_prg_header (cpx #15 skips only Slot 15, which is preloaded by a8_catalog_xe_preload) in platforms/atari8/storage.s, plus a8_cat_xe_copy/a8_catalog_xe_preload in platforms/atari8/monster_catalog_a8.s (using a8_cat_xe_slots = [10,11,12,13,15]); harness_smoke.py (xe_cache_verify) reads xe_slot_populated[0..15] bit 7. Known exclusions: ATARI8_CARTRIDGE (cartridge_copy.s / GINTLK / TRIG3) does not use 130XE extended slots; a800xl (64 KB) leaves xe_present = 0 and never reads xe_slot_*.
Initialization, reset and persistence points: xe_slot_portb/win_hi/ram_hi/pages are read-only tables in low resident (< $4000, low_helpers_end = $220B); xe_slot_populated[0..15] is cleared at xe_detect boot probe, populated during init_xe_preload (Slots 10..13, 15 then 0..9) and title draw (Slot 14), and unchanged across game save/load. exit_trampoline continues to restore PORTB = $FF before COLDSV.
Affected production sequence through the changed transition: Boot (a8_catalog_xe_preload -> xe_cache_stash for Slots 10..13, 15; overlay preload -> hal_asset_load_prg_header -> xe_cache_stash for Slots 0..9) and runtime overlay/title/catalog fetches (xe_cache_fetch / a8_cat_xe_copy) index Slots 0..15 identically and look up the new packed xe_slot_portb[slot], xe_slot_win_hi[slot], xe_slot_ram_hi[slot], and exact xe_slot_pages[slot] page count under SEI + NMIEN=$00 + NMIRES + PORTB restore ($FE).
Contract decision or selected upstream oracle with source locations: 130XE hardware MMU contract in docs/ATARI8_MEMORY_CONTRACT.md Section 1 & 3 (PORTB bits 2..3 = bank 0..3 -> $E2/$E6/$EA/$EE at $4000-$7FFF, bit 5 = 1 keeping ANTIC in Main RAM) and Phase 1 roadmap (zero core/ churn, keep all 16 slots 0..15 exact page-ceil without payload truncation). Note: keeping exact page-ceil sizes for existing built payloads recovers 35 contiguous pages (8,960 B) rather than the ~10.2 KB unrounded byte-sum estimate because intra-page remainders across 16 slots account for 5 pages.
Intentional Moria8 deviations: N/A (130XE caching is an Atari 8-bit hardware-specific feature; gameplay semantics and VMS Moria 4.8 / Umoria 5.7.15 rules are unchanged).
Input/intermediate widths, signedness, carry, range and overflow policy: Unsigned 8-bit slot index (0..15), unsigned 8-bit page high bytes ($40..$80) and page counts (1..16). All page sums and end-of-window checks ($40 <= win_hi < win_hi + pages <= $80) plus Slot 14 RAM destination check ($C1 + 3 <= $D0) and actual payload page ceilings (actual_pages <= xe_slot_pages[slot]) are verified at assembly time via KickAssembler .assert and post-build by platforms/atari8/check_memory_contract.py.
RNG reduction and bias, if applicable: N/A (storage/130XE banking layout touches zero RNG state or calls).
Affected platforms, overlays, banks and owners: platforms/atari8/ exclusively (memory.s, storage.s, monster_catalog_a8.s, main.s, check_memory_contract.py) and docs/ATARI8_MEMORY_CONTRACT.md; affects 130XE Extended Banks 0..3 for Slots 0..15 (overlays OVL.STA..OVL.CHS, MONSTER.CAT sectors 0..139, TITLE.DAT). a800xl (64 KB), ATARI8_CARTRIDGE, core/, platforms/shared/, and all other platforms untouched.
Required production-path tests: make testatari8-memory-contract-selftest (12 checker unit tests including 7 negative 130XE slot-packing/bounds/overflow fixtures), make testatari8-memory-contract, make diskatari8, make cartridgeatari8, make testatari8 (headless MAME a800xl 16 scenarios + a130xe 5 cache/SIO/legal scenarios + 6 cartridge scenarios), and make testatari8-cartridge.
Known behavior explicitly out of scope: Allocating Bank 3 $5D00-$7FFF free pages to Phase 2/4/5 payloads (OVL.HOM, OVL.SAV, OVL.TTL, ITEM.CAT cache) and splitting Slot 14/OVL.CHS across banks; core/ edits; non-Atari platforms.
Unresolved uncertainty and risk: OVL.GEN (Slot 3) is 3,838 B inside a 15-page (3,840 B) slot with 2 B intra-page headroom, and Bank 0/1/2 have 0 free pages left. Risk is low and strictly fail-closed: any payload growth exceeding its allocated xe_slot_pages[slot] fails immediately at KickAssembler link time (#if !ATARI8_CARTRIDGE .assert) and in check_memory_contract.py (make testatari8-memory-contract).
```

### Section 4 Verification Coverage (`2026-11-14`)

- **Gate 1 (Link-Time Assertions):** KickAssembler passed all assertions across `memory.s`, `storage.s`, `monster_catalog_a8.s`, and `main.s`: `low_helpers_end = $220B <= $4000`, `program_end = $C0AF <= $C100`, `high_resident_end = $DF3E <= $E000`, `banked_code_end = $FFF8 <= $FFFA`, all 10 overlays `<= XE_SLOT*_PAGES * 256`, Banks 0..3 `<= $80` (`221/256` pages used, `XE_BANK3_FREE_HI = $5D`, `XE_BANK3_FREE_PAGES = 35`), and `ATARI8_CARTRIDGE` untouched (`110,848/131,072` B).
- **Gate 2 (Static Contract Checker):** `make testatari8-memory-contract-selftest` (12/12 unit tests) and `make testatari8-memory-contract` passed, confirming `MORIA8.RES` `xe_slot_*` table alignment, non-overlap, `$4000-$7FFF` bounds, Slot 14 `$D000` safety, and built payload fit (`OVL.*`, `TITLE.DAT`, `MONSTER.CAT`) plus `LICENSE.TXT`/`SRCOFFER.TXT` disk/CAR legal payloads.
- **Gate 3 (Runtime MAME Verification):** `make testatari8` and `make testatari8-cartridge` passed after the final implementation (`16/16` `a800xl` disk scenarios, `5/5` `a130xe` cache/SIO/legal scenarios including `xe_cache_verify`, and `6/6` `.car` cartridge scenarios).

---

## Phase 2: Cold Code Eviction (`OVL.HOM`, `OVL.STO`, `OVL.TTL`, `2026-11-14`)

### Change Record (`docs/BEHAVIOR_CHANGE_PROTOCOL.md`)

```text
Problem and success criteria: Atari 8-bit disk Default ($0C00-$C0AF, 46,255 B, 81 B free), RuntimeBanked ATARI.BNK ($F000-$FFF7, 4,088 B, 2 B free), TownOverlay OVL.TWN (4,088 B, 8 B free), and HelpOverlay OVL.HLP (3,683 B, 413 B free) were critically tight against hard hardware ceilings while Bank 3 extended RAM held 35 unallocated free pages. Success criteria: enable HOME_OVERLAY_SEPARATE and SAVE_IN_STORAGE_OVERLAY in platforms/atari8/main.s, evict ui_home.s/ui_home_text.s to OVL.HOM (OVL_HOME = 11), evict platforms/shared/save.s/save_slot_menu.s/disk_setup_atari.s to OVL.STO (OVL_STORAGE = 12) while keeping shared save state/probe descriptors/no-op restoration hooks in resident RAM, evict title_screen.s/title_str/title_show_sysinfo to OVL.TTL (OVL_TITLE = 13) with resident tramp_title_draw_screen, keep title_menu_loop/title_load_game resident so legal Cancel redraw works without loading TITLE.DAT or OVL.TTL, expand 130XE extended RAM to 19 slots (0..18) and ATR/CAR packaging to 13 overlays, preserve SIOV PORTB=$FE return discipline and Carry semantics across save_game/load_game, and pass all link-time .asserts, static checkers, HAL checks, and MAME disk + 130XE + CAR suites.
State being changed: platforms/atari8/main.s (defines HOME_OVERLAY_SEPARATE, SAVE_IN_STORAGE_OVERLAY; segments HomeOverlay/StorageOverlay/TitleOverlay; resident trampolines save_game, load_game, tramp_title_draw_screen, tramp_store_enter #STORE_HOME dispatch; SaveState*Segment/SaveProbe*Segment; init_xe_preload count), platforms/atari8/hal/lifecycle_policy.s (hal_platform_overlay_count = 13), platforms/atari8/hal/storage.s (13 overlay names), platforms/atari8/cartridge_contract.s (CART_OVERLAY_COUNT = 13, CART_ASSET_HOME/STORAGE/TITLE_OVL, total 20 assets), platforms/atari8/storage.s (19 XE slots, atari_ovl_xe_slot indirection, Bank 2 packed 64/64p with Slots 16+18 and Bank 3 leaving 21 contiguous free pages at $6B00-$7FFF, hal_asset_load_prg_header cpx #19), platforms/atari8/Makefile, tools/make_atr.py, tools/make_atari8_car.py, platforms/atari8/check_memory_contract.py, platforms/atari8/harness_smoke.py, and platforms/atari8/test_cartridge.py.
Search scope and terms: Searched platforms/atari8/, tools/, core/, and platforms/shared/save.s for HOME_OVERLAY_SEPARATE, SAVE_IN_STORAGE_OVERLAY, OVL_HELP, OVL_HOME, OVL_STORAGE, OVL_TITLE, save_game, load_game, save_slot_menu, disk_setup_atari, title_load_and_draw, xe_slot_, CART_ASSET_, hal_platform_overlay_count, and UI_HOME_TEXT_MACROS_ONLY.
Relevant readers/writers found and known exclusions: Resident game_loop/store callers invoke save_game, load_game, tramp_store_enter, save_prepare_slot_prompt, save_select_slot_prompt, tramp_disk_setup, tramp_disk_prepare_selected, and tramp_title_draw_screen; platforms/shared/save.s reads/writes save_block_* state in SaveState*Segment and SaveProbe*Segment (Default) and invokes save_restore_channels and c64_restore_vic_bank0_after_serial (both Atari macros/no-op stubs in Default); disk_setup_atari.s/save_slot_menu.s and save_stream.s callbacks run together inside StorageOverlay with SIOV bounce remaining < $4000 in LowHelpers (restoring PORTB=$FE before returning to $E000-$EFFF). Known exclusions: core/, platforms/shared/, tools/check_hal_*.py, tools/report_memory_budgets.py, and docs/MEMORY_REDESIGN_PLAN.md untouched.
Initialization, reset and persistence points: xe_slot_populated (19 B in LowHelpers < $4000) is zeroed in xe_detect and populated in init_xe_preload (slots 10..13, 15 then all 13 overlays via atari_ovl_xe_slot -> slots 0..9, 16..18); title_draw_overlay_screen caches TITLE.DAT (Slot 14). On 64 KB a800xl and CAR, OVL.HOM/OVL.STO/OVL.TTL load on demand into $E000-$EFFF; title_menu_loop and title_load_game remain resident in Default so legalui ESC restore never relies on OVL.TTL.
Affected production sequence through the changed transition: (1) Title boot: title_enter_menu (Default) -> tramp_title_draw_screen -> hal_overlay_load #OVL_TITLE -> OVL.TTL title_draw_overlay_screen ($E000-$E11C) -> title_load_and_draw + title_show_sysinfo -> restore caller overlay -> title_menu_loop (Default). (2) Home visit: try_store_entry -> tramp_store_enter (Default) sees zp_store_idx == #STORE_HOME -> saves caller overlay, hal_overlay_load #OVL_HOME -> OVL.HOM home_enter ($E000-$E396) -> tramp_sr_epilogue restores caller overlay. (3) Save/load/disk-setup: resident save_game/load_game trampolines save caller overlay, load #OVL_STORAGE (OVL.STO $E000-$EDE7, failing closed with C=0 / + LOAD_RESULT_IOERR on load failure), call save_game_impl/load_game_impl (with save_slot_menu.s and disk_setup_atari.s resident inside the same OVL.STO overlay, calling LowHelpers EnterSio/ExitSio SIOV bounce < $4000 which restores PORTB=$FE on return), then restore caller overlay via atari_platform_runtime_resync while preserving Carry.
Contract decision or selected upstream oracle with source locations: Phase 2 architecture from docs/MEMORY_REDESIGN_PLAN.md §4.2, §5, §6 and Wave 1 shared-p2 contract (HOME_OVERLAY_SEPARATE, SAVE_IN_STORAGE_OVERLAY, SaveState*/SaveProbe* segment hooks); Atari8 hardware PORTB ($FE/$FF/$EA/$EE) and SIOV (< $4000) invariants in Sections 1-3 above.
Intentional Moria8 deviations: Evicting ui_home_text/ui_home, save/disk-setup/slot-menu, and title_screen into Atari 8-bit $E000-$EFFF overlays preserves 100% identical player-facing strings and VMS Moria 4.8 / Umoria 5.7.15 gameplay semantics. Placing disk_setup_atari.s alongside save.s and save_slot_menu.s inside OVL.STO avoids cross-overlay swaps between save_game_impl/load_game_impl and disk setup prompts while shrinking OVL.HLP to 9 pages.
Input/intermediate widths, signedness, carry, range and overflow policy: Unsigned 8-bit overlay IDs 1..13 mapped to 0..12 then via atari_ovl_xe_slot to 19-entry slot IDs 0..18 (cpx #19 guard in hal_asset_load_prg_header). Carry flag preserved across save_game/load_game overlay reload/restore epilogue via php/plp around atari_platform_runtime_resync; load failure returns CLC + A=#LOAD_RESULT_IOERR; overlay failure before save sets CLC. SaveState*Segment/SaveProbe*Segment state remains permanently in Default ($0C00-$B843) and never resides in swapped $E000-$EFFF.
RNG reduction and bias, if applicable: N/A (cold code eviction and 130XE slot indexing touch zero RNG state or reduction logic).
Affected platforms, overlays, banks and owners: platforms/atari8/ (main.s, storage.s, Makefile, cartridge_contract.s, hal/lifecycle_policy.s, hal/storage.s, check_memory_contract.py, harness_smoke.py, test_cartridge.py), tools/make_atr.py, tools/make_atari8_car.py, docs/ATARI8_MEMORY_CONTRACT.md. Overlays OVL.TWN, OVL.HLP, new OVL.HOM (11), OVL.STO (12), OVL.TTL (13); Default ($0C00-$B843), ATARI.BNK ($F000-$FDCF), 130XE Banks 2 & 3, .atr, and .car.
Required production-path tests: make -C platforms/atari8 build disk cartridge test-memory-contract, python3 tools/check_atari8_car.py --selftest, make check-hal-boundaries check-6502-lint, and ./tools/isolated.sh make -C platforms/atari8 test-runtime test-cartridge (a800xl disk, a130xe cached, and Type 41 CAR including OVL.HOM, OVL.STO, OVL.TTL paths).
Known behavior explicitly out of scope: Non-Atari ports, core/ edits, platforms/shared/ edits, Item/Catalog Tier evictions (Phase 4/5 targeting Bank 3's 21 contiguous free pages at $6B00-$7FFF).
Unresolved uncertainty and risk: OVL.STO sits at 3,560 B on disk (3,584 B 14-page cap, 24 B slack inside page 14) and OVL.GEN stays at 3,838 B inside 15 pages (2 B slack). Future growth in either overlay past its slot page ceiling is fail-closed via KickAssembler .asserts and check_memory_contract.py.
```

### Section 4 Verification Coverage (`2026-11-14`, Phase 2)

- **Gate 1 (Link-Time Assertions & Budgets):** KickAssembler passed all assertions (411 disk asserts, 396 cartridge asserts, 0 failed): `low_helpers_end = $225E <= $4000` (`5,726` B), `Default` `program_end = $B844 <= $C100` (`44,100` B, **`2,236` B free**, up from `81` B), `ATARI.BNK` `banked_code_end = $FDD0 <= $FFFA` (`3,536` B, **`554` B free**, up from `2` B), `OVL.TWN` = `3,973` B (`123` B free, down from `4,088` B), `OVL.HLP` = `2,159` B (`9` p, down from `3,683` B / `15` p), `OVL.HOM` = `919` B (`4` p), `OVL.STO` = `3,560` B (`14` p), `OVL.TTL` = `285` B (`2` p; `252` B / `1` p on cart), `130XE` `235/256` pages used (`21` contiguous free = `5,376` B at Bank 3 `$6B00-$7FFF`), `.atr` `883/1,023` sectors (`140` free, `20/64` DOS 2.5 files including `LICENSE.TXT`/`SRCOFFER.TXT`), `.car` `20` assets `111,360/131,072` ROM bytes (`19,712` B free, checksum `$00f25929`).
- **Gate 2 (Static Checkers & HAL Audits):** `make -C platforms/atari8 test-memory-contract` passed (`check_memory_contract.py --selftest`, `make_atr.py --selftest`, `harness_smoke.py --selftest`, `check_atari8_car.py --selftest`, `test_cartridge.py --selftest`, and live `build/atari8` contract + `.car` check); `make check-hal-boundaries check-6502-lint` passed with `0` errors.
- **Gate 3 (Runtime MAME Verification):** `./tools/isolated.sh make -C platforms/atari8 test-runtime test-cartridge` runs `16/16` `a800xl` disk scenarios, `5/5` `a130xe` cache/SIO/legal scenarios (`xe_all_19_slots_preloaded` for slots `0..18` at Phase 2; updated to `xe_all_18_slots_preloaded` for slots `0..17` in Phase 5), and `4/4` `.car` cartridge scenarios across `6` MAME runs (including `OVL.HOM` Home entry/exit in `ui_modals`, `town_to_dungeon_130xe`, and `cold_boot_gameplay_legal_a800xl`, `OVL.STO` save/load/disk-setup/interchange, and `OVL.TTL` title/legal restore).

---

## Phase 3: `hal_overlay_post_reload` & Generated Overlay Trampolines (`2026-11-14`)

### Change Record (`docs/BEHAVIOR_CHANGE_PROTOCOL.md`)

```text
Problem and success criteria: Hand-maintained overlay trampolines in platforms/atari8/main.s duplicated boilerplate across 45 manifest entries, left the obsolete plus4_install_ram_irq_vectors alias in main.s after Wave 1 replaced core/player_items.s's $0102/$0104 stack-probing reload with jsr hal_overlay_post_reload, and lacked a Makefile build rule regenerating build/trampolines/atari8_trampolines.inc from tools/trampoline_manifest.py. Success criteria: wire build/trampolines/atari8_trampolines.inc into platforms/atari8/Makefile for both disk and cartridge builds, define hal_overlay_post_reload in Default resident RAM, remove unused plus4_install_ram_irq_vectors, replace all 45 generated tramp_* definitions in main.s with #import "build/trampolines/atari8_trampolines.inc" while preserving all 17 custom tramp_* labels (16 in main.s + tramp_ui_legal_display in legal.s) and chest_dispatch, confirm 0 duplicate/missing labels, and pass all link-time .asserts, check_memory_contract.py, check_overlay_calls.py, HAL checks, and MAME a800xl + a130xe + .car suites.
State being changed: platforms/atari8/Makefile (adds TRAMPOLINES_INC_TOOL, TRAMPOLINE_MANIFEST, TRAMPOLINES_INC = $(OUT)/trampolines/atari8_trampolines.inc rule using python3 -B ../../tools/gen_trampolines.py --port atari8 --output "$@", and prerequisites on ATARI8_MAIN_STAMP and ATARI8_CART_STAMP), platforms/atari8/main.s (defines hal_overlay_post_reload: sei / jsr atari_install_vectors / jmp plus4_bank_ram in Default, removes dead .label plus4_install_ram_irq_vectors = atari_install_vectors, migrates 45 generated tramp_* definitions including low tramp_dig_ability, tramp_reu_show_status, 8 .label aliases, 2 a8_ovl_gen_loaded wrappers, tramp_ui_help_display, 31 ovl_sr stubs, and 2 ovl_death_restore_spell_fatal wrappers into #import "build/trampolines/atari8_trampolines.inc", leaving all 16 custom main.s tramp_* handlers and chest_dispatch intact), and docs/ATARI8_MEMORY_CONTRACT.md.
Search scope and terms: Searched core/, platforms/atari8/, platforms/shared/, and platforms/commodore/common/ for plus4_install_ram_irq_vectors, hal_overlay_post_reload, tramp_dig_ability, calc_dig_ability, tramp_sr_epilogue, and all 62 ATARI8_ENTRIES names in tools/trampoline_manifest.py.
Relevant readers/writers found and known exclusions: core/player_items.s (!sias_overlay_loaded:) calls jsr hal_overlay_post_reload under #if !HAL_PLATFORM_AUX_PERSISTENT_DATA; zero callers of plus4_install_ram_irq_vectors remain outside platforms/commodore/plus4/; build/atari8/main.sym and build/atari8-cart/main.sym define 62/62 ATARI8_ENTRIES (0 duplicates, 0 missing, 0 extra); legal.s keeps custom tramp_ui_legal_display. Known exclusions: core/, tools/, platforms/commodore/, and all other port files untouched.
Initialization, reset and persistence points: No boot or save persistence state changed; hal_overlay_post_reload executes in Default resident RAM ($B4AE disk / $B1AA cart), invoking atari_install_vectors (< $4000) which installs RAM CPU vectors ($FFFA-$FFFF) and sets PORTB=$FE before tail-jumping plus4_bank_ram (re-affirming PORTB=$FE).
Affected production sequence through the changed transition: (1) Inventory/item action reload: core/player_items.s show_inv_and_select returns via !sias_overlay_loaded -> jsr hal_overlay_post_reload -> sei, atari_install_vectors (RAM vectors + PORTB=$FE), plus4_bank_ram -> caller continues with PORTB=$FE and active NMI/IRQ vectors. (2) Generated overlay calls: core/Default callers jump to generated tramp_* in Default (build/trampolines/atari8_trampolines.inc), loading the target overlay via overlay_load_no_kernal or tramp_sr_gen_loaded and exiting via tramp_sr_epilogue (= atari_platform_runtime_resync) or Spell reload with !fatal: jmp entry_main.
Contract decision or selected upstream oracle with source locations: tools/trampoline_manifest.py ATARI8_ENTRIES (45 generated + 17 custom = 62 entries) and Wave 1 core/player_items.s hal_overlay_post_reload contract; Atari8 PORTB=$FE / < $4000 vector-installation discipline in Section 1 above.
Intentional Moria8 deviations: Generated tramp_eff_earthquake and tramp_eff_destroy_area emit independent !fatal: jmp entry_main tails instead of sharing one local !fatal label across the two stubs (+2 B vs -35 B net in Default from removing unused plus4_install_ram_irq_vectors / moving tramp_dig_ability and consolidating stubs, saving 33 B net overall); gameplay and VMS Moria 4.8 / Umoria 5.7.15 semantics are unchanged.
Input/intermediate widths, signedness, carry, range and overflow policy: Carry failure paths across overlay_load_no_kernal (bcs !done+ / bcs !fatal+) and hal_overlay_post_reload vector/PORTB preservation match pre-Phase 3 hand-written trampolines; atari8_trampolines.inc lives in Default (< $C100) while atari_install_vectors stays < $4000.
RNG reduction and bias, if applicable: N/A (trampoline generation and post-reload vector/bank restoration touch no RNG state or reduction).
Affected platforms, overlays, banks and owners: platforms/atari8/ (Makefile, main.s) and docs/ATARI8_MEMORY_CONTRACT.md; build/trampolines/atari8_trampolines.inc consumed during disk and cartridge assembly; Low Resident ($0C00-$225A), Default ($225B-$B822 disk / $2016-$B51E cart), all 13 overlays, ATARI.BNK, and 130XE Bank 0..3 slots unchanged in layout.
Required production-path tests: make -C platforms/atari8 build disk test-memory-contract test-memory-contract-selftest, python3 -B tools/gen_trampolines.py --selftest --check-manifest (0 atari8 issues under --check), python3 -B tools/check_overlay_calls.py --port atari8 --check-sym --selftest, make check-hal-boundaries check-6502-lint, and ./tools/isolated.sh make testatari8.
Known behavior explicitly out of scope: Remaining manual generated trampolines on non-Atari ports (e.g., c64/plus4 reported by global tools/gen_trampolines.py --check), core/ edits, and Phase 4/5 Bank 3 catalog/tier evictions.
Unresolved uncertainty and risk: None in the Atari 8-bit trampoline migration: every generated entry in tools/trampoline_manifest.py matches the prior main.s stub semantics, and build/test gates fail closed on missing/duplicate labels or cross-overlay boundary violations. Risk remains unchanged on pre-existing tight slots OVL.GEN (2 B intra-slot slack in 15 p) and OVL.STO (24 B intra-slot slack in 14 p).
```

### Section 4 Verification Coverage (`2026-11-14`, Phase 3)

- **Gate 1 (Link-Time Assertions & Budgets):** KickAssembler passed all assertions (`411` disk asserts, `396` cartridge asserts, `2` `catalog-test.prg` asserts, `0` failed): disk `low_helpers_end = $225B <= $4000` (`5,723` B, `7,589` B free), `Default` `program_end = $B823 <= $C100` (`38,344` B in `Default`, `44,067` B total span, **`2,269` B free**, up `33` B from `2,236` B), `ATARI.BNK` `banked_code_end = $FDD0 <= $FFFA` (`3,536` B, **`554` B free**); cartridge `low_helpers_end = $2016 <= $4000` (`5,142` B, `8,170` B free), `Default` `program_end = $B51F <= $C100` (`43,295` B total span, **`3,041` B free**, up `33` B from `3,008` B), `ATARI.BNK` `banked_code_end = $FCEE <= $FFFA` (`3,310` B, **`780` B free**); overlays unchanged (`OVL.STA` `4,024` B / `72` B free, `OVL.TWN` `3,973` B / `123` B free, `OVL.DTH` `3,021` B / `1,075` B free, `OVL.MDL` `3,454` B / `642` B free, `legalui` `989` B / `3,107` B free, `OVL.HLP` `2,159` B / `1,937` B free, `OVL.UI` `4,024` B / `72` B free, `OVL.ITM` `3,953` B / `143` B free, `OVL.SPL` `3,897` B / `199` B free, `OVL.CHS` `3,050` B / `1,046` B free, `OVL.GEN` `3,838` B / `258` B free in `$E000-$EFFF` / `15` p, `OVL.HOM` `919` B / `3,177` B free / `4` p, `OVL.STO` `3,560` B / `536` B free / `14` p, `OVL.TTL` `285` B / `3,811` B free / `2` p [`252` B / `1` p on cart]); `130XE` `235/256` pages used (`21` contiguous free = `5,376` B at Bank 3 `$6b00-$7FFF`); `.atr` `133,136` B (`883/1,023` sectors, `140` free, `20/64` DOS 2.5 files); `.car` `20` exact assets `111,104/131,072` ROM bytes (`19,968` B free, checksum `$00f249ca`, zero `$A000-$BFFF` post-boot overlaps).
- **Gate 2 (Static Checkers & HAL Audits):** `make -C platforms/atari8 test-memory-contract test-memory-contract-selftest` passed; `build/atari8/main.sym` and `build/atari8-cart/main.sym` both verify `62/62` manifest `tramp_*` labels (`0` duplicates, `0` missing, `0` extra), `hal_overlay_post_reload` (`$B4AE` disk / `$B1AA` cart), and removal of `plus4_install_ram_irq_vectors`; `python3 -B tools/check_overlay_calls.py --port atari8 --check-sym` passed (`0` cross-overlay violations); `python3 -B tools/gen_trampolines.py --selftest --check-manifest` passed (`--check` reports `0` `atari8:` issues); `make check-hal-boundaries check-6502-lint` passed (`0` errors).
- **Gate 3 (Runtime MAME Verification):** `./tools/isolated.sh make testatari8` passed after all code edits: `16/16` `a800xl` disk scenarios, `5/5` `a130xe` disk/cache scenarios, and `6/6` `.car` cartridge scenarios (`a800xl` + `a130xe`).

---

## Phase 4: `'ITM2'` `ITEM.CAT`, 130XE Bank 3 Preload, & 68-Sector Save Format V2 (`2026-11-15`)

- **Main Memory & Overlays:** Disk `LowHelpers` `$0C00-$23DA` (`6,107 B`, `7,205 B` free `< $4000`), `Default` `program_end = $C081 <= $C100` (`46,209 / 46,336 B`, **`127 B` free**; Cart `$0C00-$BD34`, `45,365 B`, **`971 B` free**), `HighResident` `$DDCE-$DF3D` (`368 / 368 B`, `0 B` free), `HighRAM Tail` `$DF3E-$DFC3` (`134 / 194 B`, **`60 B` free** `< $E000`), and `ATARI.BNK` `$F000-$FFF3` (`4,084 / 4,090 B`, **`6 B` free** on disk; `$F000-$FF11`, `3,858 B`, **`232 B` free** on cartridge). Overlays (`$E000-$EFFF`): `OVL.STA` `4,024 B` (`72 B` free), `OVL.TWN` `3,712 B` (`384 B` free), `OVL.DTH` `2,464 B` (`1,632 B` free), `OVL.MDL` `2,803 B` (`1,293 B` free), `OVL.GEN` `3,838 B` (`258 B` free), `OVL.HLP` `2,159 B` (`1,937 B` free), `OVL.UI` `4,040 B` (**`56 B` free**), `OVL.ITM` `3,980 B` (`116 B` free), `OVL.SPL` `3,729 B` (`367 B` free), `OVL.CHS` `3,385 B` (`711 B` free), `OVL.HOM` `3,659 B` (`437 B` free), `OVL.STO` `3,149 B` (`947 B` free disk / `3,145 B` cart), `OVL.TTL` `2,978 B` (`1,118 B` free disk / `2,945 B` cart).
- **130XE Extended RAM (`256/256` Pages Used, `0` Free):** Packs all `19` overlay/catalog/title slots (`Slots 0..18`, later refined to `18` slots `0..17` in Phase 5) across Banks `0..3` (`64/64/64/64` pages, `XE_BANK3_FREE_PAGES = 0`). `'ITM2'` `ITEM.CAT` (`7,478 B` in current 361-item catalog; `7,573 B` at Phase 4) streams via `item_catalog_a8.s` (`< $4000`), using a dedicated 128-byte DOS 2.5 sector cache (`icat_sec_buf`) on disk and a 256-byte page cache (`icat_cache_buf`, `CART_ASSET_ITEM_CATALOG`) on `.car`.
- **Shipping Media & Save Disk (`SAVE_VERSION = $19` at Phase 4, now `$22`):** `build/moria8-atari8.atr` uses `1,006 / 1,023` allocatable sectors (**`17` free**) across `21 / 64` DOS 2.5 files (`ITEM.CAT` added); `build/moria8-atari8.car` packs `21` assets (`118,479 B` payload, `126,869 / 131,072 B` used, **`4,203 B` free**); Save Disk pre-allocates `ATARI_SAVE_SLOT_SECTORS = 68` sectors (`8,500 B`) per `SAVE0..3.SAV` slot for the V2 stream (`7,858 B` current; `7,855 B` / `hal_storage_save_version = $19` at Phase 4, now `$22`).

---

## Phase 5: `57 B/record` `MONSTER.CAT`, PackBits `MORIA8.RES` Boot (`MORIA8.PKB`), & Cold Evictions (`2026-11-16`)

### 1. Summary of Phase 5 Memory, Boot, & Media Layout

- **`57 B/record` `MONSTER.CAT` (`140` `.atr` Sectors, Zero Extra Files/Sectors):**
  - Widens each `MONSTER.CAT` record from `49 B` (`CATALOG_RECORD_SIZE`) to **`57 B`** (`A8_CATALOG_RECORD_SIZE = 49 + 8`), appending the 8 Phase 5 extended bytes (`cat_atk2_*`, `cat_atk3_*`, `cat_spell_flags2`, `cat_cdefense`) directly to each record. Because `2 × 57 = 114 <= 125 B` DOS 2.5 sector payload (`A8_CATALOG_RECORDS_PER_SECTOR = 2`), `MONSTER.CAT` stays at **exact `140` DOS 2.5 sectors** (`ceil(279 / 2)` = `17,432 B` file) and fits the existing 5 preloaded 130XE catalog slots (`Slots 10..13, 15` = `70` pages) with zero extra `.atr` directory entries or runtime sector seeks!
  - `cat_record` (`57 B` in `< $4000` `LowHelpers`, initialized with cold sentinel `$FFFF`) exposes `.label cat_ext_record = cat_record + 49`, so `catalog_fetch_ext` (`platforms/atari8/monster_catalog_a8.s`) returns in 14 cycles with **zero disk/ROM I/O** whenever `cat_record` already holds `cat_id`, and falls through to `catalog_fetch_record` on a miss (`/` recall or save refetch). On `.car`, `CART_ASSET_CATALOG` holds `279 × 57 = 15,903 B` (`cartridge_catalog.s`).
- **PackBits-Compressed `MORIA8.RES` (`MORIA8.PKB` `45,886 -> 40,776 B`, `-5,110 B`):**
  - On `.atr`, `MORIA8.RES` stores the PackBits stream `MORIA8.PKB` (`40,778 B` = `327` DOS 2.5 sectors instead of `368`, saving **`41` `.atr` sectors**). The 3-sector DOS 2.5 bootstrap `platforms/atari8/boot.s` (`$0800-$097F`, asserted `<= $0980`) locates `"MORIA8  RES"` in Sectors `361..368`, streams 125-byte DOS 2.5 sector payloads into `$0980`, and PackBits-unpacks in place into `$0C00-$C0FF` (`PORTB = $FF` below `$BF00`, switching `PORTB = $FE` for `$BF00-$C0FF` before `jmp $0C00`).
  - On `.car` (`build/moria8-atari8.car`), `CART_DIRECTORY` slot `0` stores page-padded `MORIA8.PKB`, and `platforms/atari8/cartridge_boot.s` (`Bank 0` `$A000`, copied to `$0800` with 256-byte ROM page bounce at `$0900-$09FF` and `STA CART_DISABLE` `$D510` before writing Main RAM) PackBits-unpacks into `$0C00-$C0FF`, syncs `OS_GINTLK` (`$03FA`) from `TRIG3` (`$D013`), and jumps to `$0C00`.
- **Wave 5.2 Cold Evictions, `ui_recall.s` in `OVL.DTH`, & 18-Slot 130XE Cache:**
  - `core/ui_recall.s` moves to `DeathOverlay` (`OVL.DTH`, `3,221 B` / `14p`; 40-col label/tag strings stay in `Default` `recall_defs.s`), `mae_cold_body` + `catalog_index.s` (`cat_undead[35]`) live in `ATARI.BNK` (`$F000-$FFA1`), Wave 5.2 cold modules evict to `OVL.STA` (`player_chargen_cold.s`), `OVL.CHS` (`trap_trigger_cold.s`, `trap_damage_cold.s`, `4,036 B`, `60 B` free), `OVL.HLP` (`door_open_close_cold.s`, `item_drop_cold.s`, `ui_help_cmd_cold.s`), `OVL.TTL` (`store_restock_overlay.s`, `starting_kit_cold.s`), and `OVL.STO` (`item_refresh_known_cold.s`, `load_resume_reset_cold.s`).
  - 130XE Extended RAM packs `18` slots (`Slots 0..17`, `256/256` pages used; cold `OVL.TTL` uncached `$FF`) so widened `OVL.CHS` (`16p`), `OVL.HOM` (`16p`), `OVL.STO` (`16p`), and `OVL.HLP` (`15p`) stay 100% RAM-cached during gameplay.
  - Measured headroom (`42f8f7e7`): `LowHelpers` `$0C00-$23C5` (`6,085 B`, **`7,227 B` free** `< $4000`) disk / `$0C00-$213D` (`5,437 B`, **`7,875 B` free**) cart; `Default` (`MORIA8.RES`) `$0C00-$BF3E` (`45,886 B`, **`450 B` free** `< $C100`) disk / `$0C00-$BBF7` (`45,047 B`, **`1,289 B` free**) cart; `ATARI.BNK` `$F000-$FFA1` (`4,001 B`, **`89 B` free** `< $FFFA`) disk / `$F000-$FEBF` (`3,775 B`, **`315 B` free**) cart; `HighResident` `368/368 B` (`0 B` free); `HighRAM Tail` `134/194 B` (**`60 B` free**); tightest overlays: `OVL.UI` `56 B`, `OVL.CHS` `60 B`, `OVL.STA` `72 B`, `OVL.STO` `122 B` disk / `126 B` cart, `OVL.HOM` `203 B`, `OVL.GEN` `258 B`, `OVL.ITM` `699 B` (`3,397 B`); Media: `.atr` `988 / 1,023` sectors (**`35` sectors free**, `21/64` files), `.car` `126,357 / 131,072 B` (**`4,715 B` free**, `21` assets `118,116 B`).

### 2. Change Record (`docs/BEHAVIOR_CHANGE_PROTOCOL.md`)

```text
Problem and success criteria: Fit Phase 5's 29-field cr_* buffers (+320 B), 279/279 species (57 B/record MONSTER.CAT), cat_undead[35], 15-field '/' recall, 4-attack loop, 19 ADESC_* verbs, 24 ATK_* effects, 5 MSF2_* spells, and CD_*/CM2_* behaviors into Atari 8-bit Default (< $C100), ATARI.BNK (< $FFFA), $E000-$EFFF overlays, 256-page 130XE cache, 1,023-sector DOS 2.5 .atr, and 128 KB AtariMax .car while keeping boot.s <= $0980 (384 B).
State being changed: platforms/atari8/{boot.s,cartridge_boot.s,main.s,memory.s,storage.s,monster_catalog_a8.s,cartridge_catalog.s,Makefile,check_memory_contract.py} — A8_CATALOG_RECORD_SIZE = 57 (cat_ext_record = cat_record + 49, 2 records/sector = 140 sectors); PackBits MORIA8.PKB unpackers in 3-sector boot.s and Bank 0 cartridge_boot.s; 18-slot 130XE layout (OVL.TTL $FF uncached); ui_recall.s in OVL.DTH; mae_cold_body in ATARI.BNK; Wave 5.2 cold evictions.
Search scope and terms: rg across platforms/atari8/, core/, and tools/ for A8_CATALOG_RECORD_SIZE, cat_record, catalog_fetch_ext, BOOT_STAGE_BUF, CART_DIRECTORY, xe_slot_, atari_ovl_xe_slot, mae_cold_body.
Relevant readers/writers found and known exclusions: catalog_fetch_record (< $4000) populates all 57 B of cat_record on both 64 KB disk (SIOV), 130XE cache (a8_cat_xe_copy), and .car (cartridge_catalog.s); catalog_fetch_ext fast-paths when cat_record[0..1] == cat_id ($FFFF initial sentinel avoids false hit on ID 0); boot.s switches PORTB=$FE before writing $BF00-$C0FF; cartridge_boot.s disables $D510 before writing $0C00-$C0FF so $A000-$BFFF hits Main RAM.
Initialization, reset and persistence points: cat_record initializes to $FFFF sentinel at load; xe_slot_populated[0..17] zeroed in xe_detect and preloaded at boot; Save V2 (68 sectors, SAVE_VERSION = $22).
Affected production sequence through the changed transition: Cold boot (.atr 3-sector boot.s or .car Bank 0 cartridge_boot.s) PackBits-unpacks MORIA8.PKB -> $0C00-$BF3D -> entry_main -> xe_detect / 18-slot preload -> gameplay cat_fetch reads 57 B into cat_record and catalog_fetch_ext reads cat_record+49 with 0 extra I/O -> '/' recall loads OVL.DTH -> ui_recall_display.
Contract decision or selected upstream oracle with source locations: Atari XL/XE PORTB ($FE/$FF/$E2..$EE), < $4000 SIOV/130XE execution, GINTLK ($03FA) sync, and 3-sector $0980 boot limit in Sections 1-3 above.
Intentional Moria8 deviations: Cold OVL.TTL loads from disk on 130XE (title entry & new-game restock/kit only) so all gameplay overlays and 140-sector MONSTER.CAT fit 256/256 130XE pages.
Input/intermediate widths, signedness, carry, range and overflow policy: 9-bit catalog ID / 2 -> sector 0..139, odd record offset 57 (2 * 57 = 114 <= 125 B asserted); PackBits unpackers guard destination < MAP_BASE ($C100) and halt fail-closed on corrupt streams.
RNG reduction and bias, if applicable: N/A for Atari 8-bit loader/banking/storage.
Affected platforms, overlays, banks and owners: Atari 8-bit Default ($BF3E disk [450 B free] / $BBF7 cart [1,289 B free]), ATARI.BNK ($FFA1 disk [89 B free] / $FEBF cart [315 B free]), 130XE Slots 0..17 (256/256p), .atr (988/1,023 secs, 35 free), .car (126,357/131,072 B, 4,715 B free).
Required production-path tests: make testatari8-memory-contract, tools/report_memory_budgets.py --port atari8, make testatari8-runtime, make testatari8-cartridge, and make playtest-gate.
Known behavior explicitly out of scope: Caching ITEM.CAT or OVL.TTL in 130XE (0 free pages).
Unresolved uncertainty and risk: HighResident has 0 B free ($DDCE-$DF3E exact 368 B), OVL.UI 56 B, OVL.CHS 60 B, and .atr 35 sectors free; all enforced fail-closed at build time.
```

### 3. Section 4 Verification Coverage (`2026-11-16`, Phase 5)

- **Gate 1 (Link-Time Assertions & Budgets):** `boot.s <= $0980` (`384 B`), `low_helpers_end = $23C5` disk / `$213D` cart (`< $4000`), `Default` `$0C00-$BF3E` (`450 B` free) disk / `$0C00-$BBF7` (`1,289 B` free) cart, `ATARI.BNK` `$F000-$FFA1` (`89 B` free) disk / `$F000-$FEBF` (`315 B` free) cart, `130XE` `256/256` pages (`Slots 0..17`), `.atr` **`35` free sectors** (`988/1,023`, `LICENSE.TXT` & `SRCOFFER.TXT` intact), `.car` **`4,715 B` free** (`21` assets).
- **Gate 2 (Static Checkers & HAL Audits):** `make testatari8-memory-contract`, `check_atari8_car.py`, `make check-hal-boundaries`, and `report_memory_budgets.py` (`0` overflows) all PASS.
- **Gate 3 (Runtime MAME & Playtest Verification):** `make testatari8` (`a800xl` + `a130xe` + `.car`) and `make playtest-gate` (`atari8` + `atari8-cart`) PASS (`0` findings).


