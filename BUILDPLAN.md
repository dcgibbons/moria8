# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-02-20 — R14 complete)

**All core phases complete.** The game is fully playable from title screen through dungeon exploration, combat, magic, stores, save/load, death, and high scores. Ranged combat (R1.1) added. OPT-1 and OPT-4 code size optimizations complete.

### Phase Completion Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Skeleton and Infrastructure | ✅ Complete |
| 2 | Player and Character Creation | ✅ Complete |
| 3 | The Town Level | ✅ Complete |
| 4 | Dungeon Generation and Navigation | ✅ Complete |
| 5 | Monsters | ✅ Complete |
| 6 | Items and Inventory | ✅ Complete |
| 7 | Magic System | ✅ Complete (steps 7.0-7.10) |
| 8 | Stores | ✅ Complete |
| 9 | Save/Load and Game Polish | ✅ Complete (9.1-9.4, BUG-1 through BUG-18 fixed) |
| R3.5 | Creature Tier System + REU | ✅ Complete (R3.5.1-R3.5.12, 120 creatures across 5 tiers) |
| R1.1 | Ranged Combat | ✅ Complete — bows, crossbows, slings, 3 ammo types, fire command, ammo stacking |
| R3.4 | Monster Fleeing | ✅ Complete — flee threshold (HP/4) at spawn, reversed greedy movement |
| R2.1 | Special Rooms | ✅ Complete — pits, vaults, nests with $F000 banking |
| R4.1 | Ego Items | ✅ Complete — 7 enchanted weapon types with slay/elemental/AC bonuses |
| OPT-1 | Code Size Optimization | ✅ Complete — 182 bytes reclaimed (OPT-1.1 resolved by R7.6) |
| OPT-4 | Codebase-Wide Size Optimization | ✅ Complete — 1,098 bytes reclaimed across 9 items (huff_print_msg, kill/wake helpers, projectile msg dedup, tohit unification, shared trace+direction, adjacent-tile iterator, 16-bit HP damage, effect tick tables, Huffman strings) |
| OPT-3 | Town Overlay Optimization | ✅ Complete — 1,183 bytes saved (4,074→2,891), 1,204 bytes free |
| R7 | String Compression | ✅ Complete — R7.1-R7.7 all done. Tier 1: 155 strings Huffman-compressed, 888 bytes saved. Tier 2: string bank encoder/loader ($E000 overlay), monster recall system. |
| R2.5 | Tunneling + Treasure Veins | ✅ Complete — + command, STR-based digging, treasure in quartz/magma veins, wall-to-mud fix, 742 bytes |
| R11 | Lowercase/Uppercase Mode | ✅ Complete — 52 monster symbols (a-z + A-Z), '#' walls, screencode_mixed encoding, case-aware recall |
| R14 | Fix Tunneling Difficulty + Enchanted Tools | ✅ Complete — hardness rescaled, new (STR>>2)+base+(ego×12) formula, Gnomish/Orcish/Dwarven variants, bare-hands no-progress, rubble resistance, si_ego save/load |
| 10 | C128 Enhancements | Not started |

### Build Stats

- **Test suites:** 23 (308 runtime tests)
- **Compile-time asserts:** 70
- **Source files:** ~48 .s files (test_tunnel.s added by R14)
- **Program size:** $BDB5 (program_end) — **587 bytes headroom** to MAP_BASE ($C000)
- **Banked code:** $F000-$FF97 (98 bytes headroom to CPU vectors)
- **Banked payload:** $BDE2-$CD79 (646 bytes headroom to I/O at $D000)
- **Town overlay:** 3,014 of 4,096 bytes (1,082 free)

### Known Remaining Issues

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| BUG-34 | MED | Monster recall only shows first match when multiple creatures share a display symbol. umoria cycles through all known creatures with that letter; moria8 finds the first match and stops. Fix: add a recall cycling loop similar to umoria's `recallMonsterAttributes()`. | **Fixed** — pressing the same letter again cycles to the next known creature with that symbol (wraps around); state tracked in recall_last_sc/idx |
| BUG-41 | HIGH | Tunneling far too easy — hardness values scaled ~50× too low vs umoria but tool bonuses copied verbatim. Pick+STR18 = 100% success on granite (should be ~1%). Bare hands dig granite ~50% of the time. See R14 for fix plan. | **Fixed** — R14: hardness rescaled (granite 16–255, magma 5–124, quartz 3–82, rubble 0–39), new formula (STR>>2)+base+(ego×12), bare hands always fail |
| BUG-35 | HIGH | Help screen fills with 'p' characters and locks up — help_lines data crossed MAP_BASE ($C000), dungeon map overwrote tail of data | **Fixed** — Tab control code ($fc) replaced padding spaces, saving ~96 bytes |
| BUG-36 | MED | Monster recall shows blank name for town creatures — creature_get_name table path didn't populate creature_name_buf | **Fixed** — Table path now copies name to buffer |
| BUG-37 | MED | Recall/help screens flash and dismiss immediately — keyboard buffer contained repeat characters | **Fixed** — Clear $C6 before dismiss input_get_key |
| BUG-38 | HIGH | rng_range(0) causes infinite loop (game hang) — rejection sampling loops forever when N=0 | **Fixed** — Defensive guard in rng_range + guards in pick_creature_type and monster_cast_summon |
| BUG-39 | MED | Creature name shows "?" during combat — creature_get_name rejected valid $E0xx pointers when X >= active_dungeon_count but tier still loaded | **Fixed** — Four-path name resolution with shared copy loop |
| BUG-40 | MED | Creature name shows "?" in monster recall from town — after ascending from dungeon, current_tier=0 but cr_name_hi[] holds stale $E0xx pointers; recall command finds stale cr_display[] match and creature_get_name returns "?" | **Fixed** — cgn_no_tier path reloads the appropriate tier when stale $E0xx pointer found |
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |

### What's Next

| Priority | # | What | Effort |
|----------|---|------|--------|
| 1 | R12 | Game-over loop (restart/reboot prompt instead of exit to BASIC) | Low |
| 2 | R15 | Multi-disk support (dual-drive device 9, improved disk swap) | Low |
| 3 | A4 | Separate binaries (BOOT.PRG + MORIA64 + MORIA128) | Major (Phase 10) |

**Phase 10 — C128 Enhancements** (not started):

| # | What | Summary |
|---|------|---------|
| 10.1 | 80-column VDC mode | Second rendering backend for VDC 80x25 display |
| 10.2 | Extended memory | C128 128KB MMU bank-switch path (no disk tier loading) |
| 10.3 | Larger dungeon | Expand map to 120x80+, more rooms, up to 64 active monsters |
| 10.4 | Enhanced display | VDC color attributes for threat-coded monsters |

---

### Priority Triage (updated 2026-02-20)

**Remaining items:**

**Medium priority (gameplay polish):**
- R12 Game-over loop — after save/death/quit, prompt "Restart" or "Reboot" instead of exiting to BASIC

**Low priority (polish/completeness):**
- R15 Multi-disk support — dual-drive (device 9) eliminates swap prompts; also fixes missing disk_prompt_game calls after save/death
- A4 Separate binaries — Phase 10 scope (BOOT.PRG + MORIA64 + MORIA128)
- A6 Large file split — opportunistic refactoring (dungeon_gen.s, item.s)
- A7 Item generation distribution review vs umoria curves

---

---

## R12 — Game-Over Loop (Restart / Reboot Prompt)

After save, death, or voluntary quit, instead of returning to BASIC, present a prompt:

```
(R)estart new game  (Q)uit to BASIC
```

**Restart** reinitializes game state and jumps back to the title screen (character creation → dungeon). **Quit** exits cleanly to BASIC as today.

### Why

Exiting to BASIC after every death or save forces the player to re-type `LOAD` and `RUN`. On real hardware with disk loading this is especially painful. Every other Moria port loops back to "play again?" — this matches that expectation.

### Implementation

All game-ending paths currently converge on an `rts` or `jmp` back to BASIC (via the KERNAL warm-start vector or the original return address). The fix:

1. **Identify exit points:** save-and-quit, death/score screen, and voluntary quit (`Q` command) — each currently ends the program.
2. **Add `game_over_prompt`:** a small routine (~40-60 bytes) that clears the screen, prints the restart/quit prompt, and waits for a keypress.
   - `R` → call a `game_restart` entry point that reinitializes ZP state, clears the monster/item tables, resets the map, and `jmp`s to the title screen.
   - `Q` → existing clean exit to BASIC.
3. **State reinit:** the restart path must reset all mutable global state (ZP variables, map buffer at $C000, monster slots, item slots, effect timers, RNG seed). Static tables and code don't need reinit. Audit all `.byte 0` / `.fill` variables for anything that assumes fresh-load state.
4. **Tier system:** reset `current_tier` to 0 and reload tier 0 creature data (town creatures) as part of restart.

### Risks

- **Stale state bugs:** if any module assumes one-time init from fresh load, restart will expose it. Thorough testing required.
- **Size:** ~40-60 bytes for the prompt + ~20-30 bytes for reinit calls. Fits comfortably in main segment headroom (1,141 bytes free) or the $F000 banked region.

---

## R15 — Multi-Disk Support (Dual-Drive + Improved Disk Swap)

Support three disk configurations transparently:
1. **Single disk** (mode 0) — save + program on same disk (today's default, device 8)
2. **Swap disks** (mode 1) — physical disk swap on device 8 (today's 'D' mode, improved)
3. **Dual drive** (mode 2) — game on device 8, save on device 9 (no swaps needed)

### Why

Users with two 1541 drives (or a dual-drive unit like the 4040/MSD) can eliminate all disk-swap prompts by putting the save disk in drive 9. This is a common C64 setup and many games from the era supported it. The existing mode 1 (swap) code works but has two bugs: missing `disk_prompt_game` calls after save-and-quit and after death, which will break R12's restart loop.

### Current State

`disk_swap.s` already provides mode 0/1 infrastructure:
- `disk_mode` byte (0=single, 1=dual)
- `disk_prompt_save` / `disk_prompt_game` — show swap prompt + `I0` reinit (no-op when mode=0)
- Title menu 'D' key sets `disk_mode=1`

All save/load/hiscore I/O hardcodes `ldx #SAVE_DEVICE` (device 8).

### Design

#### New variable: `save_device`

```
disk_mode:    .byte 0    // 0=single, 1=swap (1 drive), 2=dual-drive (dev 8+9)
save_device:  .byte 8    // device# for save/score I/O (8 or 9)
```

- Mode 0: `save_device=8`, prompts are no-ops
- Mode 1: `save_device=8`, prompts trigger swap + `I0`
- Mode 2: `save_device=9`, prompts are no-ops (no swap needed)

#### Parameterize device number

Replace all `ldx #SAVE_DEVICE` with `ldx save_device` in save/score/scratch I/O. Tier loading and overlay loading continue using device 8 (game disk).

Affected SETLFS call sites (7 total):

| File | Line | Operation |
|------|------|-----------|
| `save.s` | 188 | save_game open |
| `save.s` | 372 | load_game open |
| `save.s` | 733 | delete_savefile scratch |
| `score_io.s` | 45 | hiscore_load open |
| `score_io.s` | 134 | hiscore_save scratch |
| `score_io.s` | 148 | hiscore_save write |
| `disk_swap.s` | 92 | disk_init_drive `I0` |

Each change is +1 byte (absolute addressing vs immediate).

#### Mode-aware prompts

```
disk_prompt_save:
    lda disk_mode
    beq !done+         // mode 0: no-op
    cmp #2
    beq !done+         // mode 2: no-op (separate drive)
    // mode 1: show swap prompt + I0
    ...
!done: rts
```

`disk_prompt_game` gets the same treatment.

#### Title menu — Disk setup sub-menu

Expand 'D' handler. Pressing 'D' at the title enters a sub-menu:

```
Save disk:  S)ame  W)swap  9) Drive 9
```

- **S** → mode 0, `save_device=8` (reset to default)
- **W** → mode 1, `save_device=8` (existing swap behavior)
- **9** → probe device 9; if present → mode 2, `save_device=9`; if absent → error message, stay on menu

Device 9 probe: open command channel 15 on device 9, send `I0`, check KERNAL status. ~30 bytes.

#### Fix missing `disk_prompt_game` calls

Two bugs in current code:

1. **Save-and-quit** (`main.s:446-448`): calls `disk_prompt_save` → `save_game` → `jmp !quit+` — never swaps back to game disk. Add `jsr disk_prompt_game` before quit.

2. **Death** (`main.s:1309-1314`): calls `disk_prompt_save` → `delete_savefile` → `tramp_game_over` (hiscore I/O) → `jmp !quit+` — never swaps back. Add `jsr disk_prompt_game` before quit. (Critical for R12 restart loop which needs game disk in drive.)

These are no-ops in mode 0, so adding them is safe regardless of disk configuration.

### Implementation Steps

| Step | What | Bytes |
|------|------|-------|
| R15.1 | Add `save_device` variable; replace 7 `ldx #SAVE_DEVICE` → `ldx save_device` | +8 |
| R15.2 | Add mode 2 check to `disk_prompt_save` and `disk_prompt_game` | +6 |
| R15.3 | Add missing `jsr disk_prompt_game` after save-and-quit and after death | +6 |
| R15.4 | Device 9 probe routine (`probe_device_9`) | +35 |
| R15.5 | Disk setup sub-menu (strings + handler in title screen) | +60 |
| R15.6 | Makefile: add `rundual` target (VICE with two drives, `-9 $(SAVE_IMAGE)`) | 0 (build only) |
| R15.7 | Test all three modes: single, swap, dual-drive | 0 |
| **Total** | | **~115 bytes** |

### Makefile Changes

**New `rundual` target:**
```makefile
rundual: disk savedisk
	$(VICE) -drive8truedrive -drive8type 1541 +iecdevice8 \
	        -drive9truedrive -drive9type 1541 +iecdevice9 \
	        -8 $(DISK_IMAGE) -9 $(SAVE_IMAGE) \
	        -sound -sounddev coreaudio -autostart $(DISK_IMAGE)
```

### Size Impact

~115 bytes total in main segment. Current headroom: 1,089 bytes. Fits easily.

### Interaction with Other Systems

- **Tier loading / overlays:** Unchanged — always use device 8 (game disk). `tier_manager.s` and `overlay.s` don't touch `save_device`.
- **R12 game-over loop:** R15.3 adds the missing `disk_prompt_game` calls that R12 will need. Implementing R15.3 before R12 is ideal.
- **REU:** No interaction — REU tier caching is orthogonal to save disk location.
- **Boot loader:** No change — boot always loads from device 8.
- **C128 (Phase 10):** Dual-drive is even more common on C128 setups. This infrastructure carries forward directly.

### Testing

- Mode 0 (default): save/load/hiscore all work on device 8, no prompts
- Mode 1 (swap): prompts appear before save, load, death; `I0` sent after swap
- Mode 2 (dual-drive): save/load/hiscore use device 9, no prompts, tiers still load from device 8
- Device 9 not present: probe fails gracefully, error message, stays on menu
- Save-and-quit: game disk back in drive (or device 8 active) after save completes
- Death: game disk back in drive after hiscore save completes

