# Atari 8-Bit Memory Contract

Placement, banking, and hardware-ownership source of truth for the Atari 8-bit
port (`platforms/atari8/`). Enforced at link time by `.assert` guards in
`platforms/atari8/memory.s` and `platforms/atari8/main.s`, and at build time by
`platforms/atari8/check_memory_contract.py`.

## 1. Machine Baseline & Banking Model (`PORTB` / `$D301`)

The Atari 8-bit port targets the stock **64 KB Atari 800XL / 65XE** as its
mandatory baseline and automatically detects **128 KB Atari 130XE** extended
RAM at boot to cache overlays, monster tiers, and title artwork.

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
     `Default` in `$0C00-$1FA1`), enforced by link-time `.assert` guards and
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
| `$03C0-$03FF` | 64 B | Spare / Untouched OS Cassette Buffer | Left unused; keyboard ring buffer (`atari_kbdbuf`), self-healing DLI vector (`dli_vector`), and POKEY SFX state (`sfx_timer`) reside in low resident RAM (`$0C00-$1FA1`). |
| `$0400-$07FF` | 1,024 B | `ATARI_CHARSET_BASE` (`CHBASE = $04`) | 1 KB RAM character set ordered by Moria8/C64 screen codes (`$00-$7F`), built at boot by `atari_font_init` (executing in `< $4000`) from the Atari OS ROM font (`$E000-$E3FF`). 1 KB-aligned as required by ANTIC. |
| `$0800-$0BFF` | 1,024 B | `SCREEN_RAM` & `DUNGEON_GEN_SCAN_SCRATCH_BASE` | During OS disk boot, `boot.s` (`384` B) loads at `$0800-$097F` (`boot_entry` at `$0806` runs `SEI : CLD : LDX #$FF : TXS : LDA #$FF : STA $D301` to disable BASIC ROM at `$A000-$BFFF` while keeping OS ROM visible), activates a minimal ANTIC Mode 6 banner (`"LOADING MORIA8..."`) at `$0380` using the OS ROM font (`$E000`), stages 128-byte sectors at `$0980-$09FF` to strip the 2-byte PRG header (`$00, $0C`) and 3-byte DOS 2.5 sector trailers (`$7D..$7F`), and streams `MORIA8.RES` into `$0C00-$C0FF` (keeping `PORTB = $FF` until `atari_io_dst_hi >= $BF` so the OS ROM font never flickers, and toggling `PORTB = $FE` only for the final pages `$BF00-$C0FF`) before jumping directly to `entry_main` (never returning via `RTS`). Once `entry_main` activates the custom Display List, `$0800-$0BE7` (`1,000` B) is the 40×25 ANTIC Mode 2 screen buffer (single LMS at `$0800`), and `$0800-$0BFF` (`1,024` B) doubles as page-aligned `DUNGEON_GEN_SCAN_SCRATCH_BASE` during level generation prior to viewport redraw (matching C64). |
| `$0C00-$1FA1` | 5,026 B | Low Resident Banking, Boot Init, Interrupt, & I/O Helpers (`< $4000`) | Guaranteed below `$4000`: `entry_main` boot init (executes `SEI : LDA #$00 : STA NMIEN : STA DMACTL` before `atari_font_init`), `atari_font_init`, `EnterSio`/`ExitSio`, `save_zp`/`restore_zp`, `sio_sector_buf` (`128` B), `hal_asset_load_prg_header`, `hal_asset_load_title`, `hal_storage_probe_media`, `atari_write_sio_sector`, `hal_storage_open`/`chrin`/`chrout`/`close`, `xe_detect`, `xe_cache_stash`/`xe_cache_fetch`, `xe_slot_populated` (`16` B), `exit_trampoline` (sets `SEI`, `NMIEN = $00`, `WARMST` `$0008 = $00`, `PORTB = $FF`, and jumps to OS coldstart `COLDSV` `$E477` so `WARMSV` never jumps through `DOSINI` `$000C` / `zp_temp4`), `atari_nmi_handler` (saves `A/X/Y`, checks `NMIST` bit 5 `SYSTEM RESET` -> `exit_trampoline`, checks both DLI bit 7 and VBI bit 6, and clears `STA NMIRES`), `atari_irq_handler`, and overlay/banked trampolines. |
| `$1FA2-$C0FF` | 41,310 B | Resident `Default` Segment (`program_end <= $C100`) | Core gameplay, UI, item catalog, town roster, and shared save engine (`46,336` B total span in `$0C00-$C0FF`, `~365` sectors on disk). Ends strictly at or below `$C100`. |
| `$C100-$CFFF` | 3,840 B | `MAP_BASE` (`$C100-$CFFF`) | Live 80×48 dungeon map (`15` pages = `3,840` B = `$0F00` B), ending immediately below the `$D000` hardware I/O window. `CREATURE_BASE` (`$C120-$C1FF`) aliases map scratch during save/game-over, matching C64/Plus/4. `TITLE.DAT` links at `.pc = $C100` (`platforms/atari8/title_data.s`) and copies `3` pages (`768` B) into `$C100-$C3FF`. No executable code is ever linked into `$C100-$CFFF`. |
| `$D000-$D7FF` | 2,048 B | **Hardware I/O Hole (Forbidden to Code/Data)** | `GTIA` (`$D000-$D0FF`), `POKEY` (`$D200-$D2FF`), `PIA` (`$D300-$D3FF`), `ANTIC` (`$D400-$D4FF`). |
| `$D800-$DBFF` | 1,024 B | `PLATFORM_TIER_NAME_POOL_BASE` | Active monster tier name pool in RAM under OS ROM (`808` B max tier-4 name blob; `216` B margin). |
| `$DC00-$DCFF` | 256 B | `FLOOR_ITEM_BASE` | Active level floor-item table (`256` B). |
| `$DD00-$DD3F` | 64 B | `PLATFORM_HD_DECODE_BUF_BASE` | Huffman decode buffer (`HD_DECODE_BUF_SIZE = 64` B in `core/huffman.s`). |
| `$DD40-$DDCD` | 142 B | `zp_save_buf` | Saved game ZP (`$02-$8F`) accessed only while `PORTB = $FE`. |
| `$DDCE-$DF0D` | 320 B | `msg_history` (`HighResident` `virtual` BSS) | 8-message × 40-byte ring buffer (`core/ui_messages.s`, cleared at startup by `msg_log_clear`), funding resident headroom below `$C100`. |
| `$DF0E-$DFFF` | 242 B | `HighResident` Uninitialized BSS Spare | Uninitialized RAM under OS ROM (`PORTB = $FE`; `virtual` segment, never emitted to `MORIA8.RES`). |
| `$E000-$EFFF` | 4,096 B | `BANKED_DATA_BASE` (Overlay & Tier Window) | Shared 4 KB execution/staging window for the 10 code overlays (`OVL.STA`..`OVL.GEN`) and 4 monster tiers (`MONSTER.DB1..4`), identical to C64 and Plus/4. |
| `$F000-$FFF9` | 4,090 B | `RuntimeBanked` Segment | Load-once banked runtime (`generation_busy.s`, `run_initialize_impl`, `store_data.s`, `runtime_ui_strings.s`, `special_rooms.s`, `ego_items.s`, `ui_home.s`, `item_desc_banked.s`, `ui_help_clear.s`, `stat_display.s`, `disk_prompt_save`/`disk_prompt_game`/`disk_prompt_game_required`, and `player_magic_learn_op.s`; `ui_recall.s` lives in `DeathOverlay`, and `disk_setup_atari.s` + `save_slot_menu.s` live in `HelpOverlay` `OVL.HLP`). Any storage call from `RuntimeBanked` vectors through `< $4000` helpers in `Default` so `PORTB = $FE` is restored before `RTS`. |
| `$FFFA-$FFFF` | 6 B | Hardware CPU Vectors (`NMI`, `RESET`, `IRQ`) | Installed in RAM under OS ROM (`$FFFA` -> `atari_nmi_handler`, `$FFFC` -> `exit_trampoline` in `< $4000`, `$FFFE` -> `atari_irq_handler`) for execution while `PORTB = $FE`. |

---

## 3. 130XE Extended RAM Cache Contract (`64 KB` = 4 × 16 KB Banks at `$4000-$7FFF`)

When `xe_detect` (linked and executed strictly below `$4000` in `$0C00-$13FF`)
confirms 130XE extended RAM at boot (non-aliasing probe across banks `0..3` at
`$4000` with Main RAM preserved), the 16 available 4 KB slots (`4 banks × 4
slots/bank = 64 KB`) are assigned as follows and tracked via a 16-byte
`xe_slot_populated` table in low RAM (`$00` = unpopulated cold slot [bit 7 = 0];
`$E2`/`$E6`/`$EA`/`$EE` = populated with the exact `PORTB` bank byte [bit 7 = 1]):

| Slot ID | 130XE Bank (`0..3`) | `PORTB` Value | Window Address | Cached Payload | Copy Span | Boot Policy |
| ---: | ---: | --- | --- | --- | ---: | --- |
| `0` | Bank 0 | `$E2` | `$4000-$4FFF` | `OVL.STA` (`OVL_STARTUP = 1`) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`5/14`) |
| `1` | Bank 0 | `$E2` | `$5000-$5FFF` | `OVL.TWN` (`OVL_TOWN = 2`) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`6/14`) |
| `2` | Bank 0 | `$E2` | `$6000-$6FFF` | `OVL.DTH` (`OVL_DEATH = 3`) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`7/14`) |
| `3` | Bank 0 | `$E2` | `$7000-$7FFF` | `OVL.GEN` (`OVL_DUNGEON_GEN = 4`) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`8/14`) |
| `4` | Bank 1 | `$E6` | `$4000-$4FFF` | `OVL.HLP` (`OVL_HELP = 5`) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`9/14`) |
| `5` | Bank 1 | `$E6` | `$5000-$5FFF` | `OVL.UI` (`OVL_UI = 6`) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`10/14`) |
| `6` | Bank 1 | `$E6` | `$6000-$6FFF` | `OVL.ITM` (`OVL_ITEMS = 7`) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`11/14`) |
| `7` | Bank 1 | `$E6` | `$7000-$7FFF` | `OVL.SPL` (`OVL_SPELL = 8`) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`12/14`) |
| `8` | Bank 2 | `$EA` | `$4000-$4FFF` | `OVL.MDL` (`OVL_MODAL_MISC = 9`) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`13/14`) |
| `9` | Bank 2 | `$EA` | `$5000-$5FFF` | `OVL.CHS` (`OVL_CHEST = 10`) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`14/14`) |
| `10` | Bank 2 | `$EA` | `$6000-$6FFF` | `MONSTER.DB1` (Tier 1) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`1/14`) |
| `11` | Bank 2 | `$EA` | `$7000-$7FFF` | `MONSTER.DB2` (Tier 2) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`2/14`) |
| `12` | Bank 3 | `$EE` | `$4000-$4FFF` | `MONSTER.DB3` (Tier 3) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`3/14`) |
| `13` | Bank 3 | `$EE` | `$5000-$5FFF` | `MONSTER.DB4` (Tier 4) | 16 pages (`4,096` B) to `$E000` | Preloaded at boot (`4/14`) |
| `14` | Bank 3 | `$EE` | `$6000-$6FFF` | `TITLE.DAT` (Title Artwork) | **3 pages (`768` B) to `MAP_BASE` (`$C100`)** | Loaded & cached on title draw |
| `15` | Bank 3 | `$EE` | `$7000-$7FFF` | Unused / Free (`4 KB` spare) | — | Unused |

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
  Because copying 16 pages (`4,096` B) takes `~57,500–65,700` CPU cycles
  (`~3.1–3.5` NTSC video frames = `52–59 ms` under ANTIC Mode 2 DMA), and
  because 6502 `NMI` is non-maskable by `SEI`, `xe_cache_stash` and
  `xe_cache_fetch` **must** disable ANTIC NMIs via `LDA #$00 : STA NMIEN ($D40E)`
  in addition to `SEI` before switching `PORTB` to extended RAM (`$E2`/`$E6`/`$EA`/`$EE`).
  During the copy, ANTIC DMA continues displaying Main RAM seamlessly (`Bit 5 = 1`);
  on completion, `PORTB` is restored to `$FE`, `STA NMIRES ($D40F)` clears any
  DLI/VBI flags latched during the copy, and `NMIEN` is restored to `$C0` (DLI +
  VBI) before `PLP` and `RTS`.
* **Copy-Span Safety:** Slot 14 (`TITLE.DAT` -> `MAP_BASE` at `$C100`) copies
  **only 3 pages (`768` B)**, never 16 pages (`$C100 + $1000` would cross
  `$CFFF` into `$D000` GTIA!).

---

## 4. Verification Gates

1. **Link-Time Assertions (`platforms/atari8/memory.s` & `main.s`):**
   * `low_helpers_end <= $4000` (`entry_main` boot init, `atari_font_init`, `EnterSio`, `ExitSio`, `sio_sector_buf`, `hal_asset_load_prg_header`, `xe_detect`, `xe_cache_*`, `exit_trampoline`, `atari_nmi_handler`, `atari_irq_handler`)
   * `program_end <= MAP_BASE` (`$C100`)
   * `MAP_END == $CFFF` (`3,840` B exact fit below `$D000`)
   * Every overlay (`StartupOverlay`..`DungeonGenOverlay`) fits within `$E000-$EFFF`
   * `banked_code_end <= $FFFA` (below hardware vectors `$FFFA-$FFFF`)
   * `ATARI_DISPLAY_LIST` does not cross a 1 KB boundary (`((>ATARI_DISPLAY_LIST) & $fc) == ((>ATARI_DISPLAY_LIST_END) & $fc)`)
   * `ATARI_CHARSET_BASE` is 1 KB aligned (`(<ATARI_CHARSET_BASE) == 0 && ((>ATARI_CHARSET_BASE) & 3) == 0`)
   * Serialized save size (`6,616` B) fits within `ATARI_SAVE_SLOT_SECTORS * 125` (`56 * 125 = 7,000` B)
2. **Static Contract Checker (`platforms/atari8/check_memory_contract.py`):**
   * `make testatari8-memory-contract` and `make testatari8-memory-contract-selftest`
   * Verifies symbol extents from `build/atari8/main.sym`, rejects any symbol or segment overlap with `$0200-$031A` (OS Page 2 / DCB), `$C100-$CFFF` (`MAP_BASE`), or `$D000-$D7FF` (Hardware I/O), verifies `< $4000` residency of all banking/SIO/130XE/interrupt/exit/font helpers, and checks all PRG payload spans.
3. **Runtime MAME Verification (`platforms/atari8/harness_smoke.py`):**
   * `make testatari8-runtime` runs headless MAME across the 15-scenario behavioral suite on `a800xl` (64 KB disk-overlay baseline) plus 3 dedicated 130XE cache/SIO coexistence scenarios on `a130xe` when `ATARI8ROMS` is set (and warns/skips gracefully when `ATARI8ROMS` is unset).
