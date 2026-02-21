# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-02-20 — R15 + BUG-42 complete)

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
| R15 | Multi-Disk Support | ✅ Complete — save_device variable, 7 SETLFS sites parameterized, mode 2 no-ops, probe_device_9, disk setup sub-menu (S/W/9), missing disk_prompt_game calls fixed, rundual Makefile target |
| BUG-42 | Fix Save/Load Corruption | ✅ Complete — streaming RLE decompressor overflow fixed by replacing with raw map I/O (3840 bytes); LOAD_SEC_ADDR fixed; title screen KERNAL LOAD cleanup (CLOSE file, clear $90) |
| 10 | C128 Enhancements | Not started |

### Build Stats

- **Test suites:** 23 (308 runtime tests)
- **Compile-time asserts:** 70
- **Source files:** ~48 .s files
- **Program size:** $BE48 (program_end) — **1,464 bytes headroom** to MAP_BASE ($C000)
- **Banked code:** $F000-$FF98 (at limit)
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
| BUG-43 | MED | Store-stocked items not identified — `store_restock_one` (store.s:154-163) sets `si_item_id`, `si_qty`, `si_p1` but never sets `IF_IDENTIFIED` in `si_flags`. umoria's `store_create()` calls `magicTreasure()` then `storeItemInsertIntoStock()` which sets `STR_IDENTIFIED`. Fix: `ora #IF_IDENTIFIED` on `si_flags,y` after stocking. | Open |
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |

### What's Next

| Priority | # | What | Effort |
|----------|---|------|--------|
| 1 | R12 | Game-over loop (reboot/restart/quit prompt instead of exit to BASIC) | Low-Med |
| 2 | A4 | Separate binaries (BOOT.PRG + MORIA64 + MORIA128) | Major (Phase 10) |

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
- R12 Game-over loop — after save/death/quit, prompt "Reboot" / "Restart" / "Quit" instead of exiting to BASIC

**Low priority (polish/completeness):**
- A4 Separate binaries — Phase 10 scope (BOOT.PRG + MORIA64 + MORIA128)
- A6 Large file split — opportunistic refactoring (dungeon_gen.s, item.s)
- A7 Item generation distribution review vs umoria curves

---

---

## R12 — Game-Over Loop (Reboot / Restart / Quit Prompt)

After save, death, or voluntary quit, instead of returning to BASIC, present a prompt:

```
R)eboot  Res)tart  Q)uit to BASIC
```

- **Reboot** (`R`) — cold restart: reload the program from disk and run it from scratch, as if the player typed `LOAD` + `RUN`. Equivalent to a fresh boot with no stale state concerns.
- **Restart** (`S`) — warm restart: reinitialize game state in memory and jump back to the title screen (character creation → dungeon). Faster than reboot since it skips disk loading, but requires careful state reinit.
- **Quit** (`Q`) — exit cleanly to BASIC as today.

### Why

Exiting to BASIC after every death or save forces the player to re-type `LOAD` and `RUN`. On real hardware with disk loading this is especially painful. Every other Moria port loops back to "play again?" — this matches that expectation. Offering both reboot and restart gives the player a safe option (reboot) and a fast option (restart).

### Implementation

All game-ending paths currently converge on an `rts` or `jmp` back to BASIC (via the KERNAL warm-start vector or the original return address). The fix:

1. **Identify exit points:** save-and-quit, death/score screen, and voluntary quit (`Q` command) — each currently ends the program.
2. **Add `game_over_prompt`:** a small routine (~60-80 bytes) that clears the screen, prints the reboot/restart/quit prompt, and waits for a keypress.
   - `R` → **Reboot:** issue KERNAL LOAD + RUN sequence to reload the program from disk (e.g., set up the BASIC input buffer with `LOAD"*",8,1` + `RUN` and jump to the BASIC warm-start vector, or use an equivalent KERNAL LOAD/JMP approach).
   - `S` → **Restart:** call a `game_restart` entry point that reinitializes ZP state, clears the monster/item tables, resets the map, and `jmp`s to the title screen.
   - `Q` → existing clean exit to BASIC.
3. **State reinit (restart path):** the restart path must reset all mutable global state (ZP variables, map buffer at $C000, monster slots, item slots, effect timers, RNG seed). Static tables and code don't need reinit. Audit all `.byte 0` / `.fill` variables for anything that assumes fresh-load state.
4. **Tier system (restart path):** reset `current_tier` to 0 and reload tier 0 creature data (town creatures) as part of restart.
5. **Reboot path:** stuff the BASIC input buffer with the LOAD+RUN command string and jump to the BASIC warm-start routine. This avoids any stale-state concerns since the entire program is reloaded from disk.

### Risks

- **Stale state bugs (restart only):** if any module assumes one-time init from fresh load, restart will expose it. Thorough testing required. The reboot option sidesteps this entirely.
- **Reboot disk dependency:** reboot requires the program disk to be in the drive. If the player has swapped to the save disk, the reboot will fail or load the wrong file. May need a "insert game disk" prompt.
- **Size:** ~60-80 bytes for the prompt + ~20-30 bytes for reinit calls + ~20-30 bytes for reboot logic. Fits comfortably in main segment headroom (811 bytes free) or the $F000 banked region.


