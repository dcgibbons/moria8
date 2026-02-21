# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-02-21 — R17 complete)

**All core phases complete.** The game is fully playable from title screen through dungeon exploration, combat, magic, stores, save/load, death, and high scores. Ranged combat (R1.1) added. OPT-1, OPT-4, OPT-5 code size optimizations complete. R17 character background history, gender, social class, and variable starting gold implemented.

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
| OPT-5 | Overlay Expansion (dungeon gen) | ✅ Complete — dungeon_gen.s → $E000 overlay; 3,490 bytes reclaimed ($B201 program_end, 3,583 bytes headroom) |
| R7 | String Compression | ✅ Complete — R7.1-R7.7 all done. Tier 1: 155 strings Huffman-compressed, 888 bytes saved. Tier 2: string bank encoder/loader ($E000 overlay), monster recall system. |
| R2.5 | Tunneling + Treasure Veins | ✅ Complete — + command, STR-based digging, treasure in quartz/magma veins, wall-to-mud fix, 742 bytes |
| R11 | Lowercase/Uppercase Mode | ✅ Complete — 52 monster symbols (a-z + A-Z), '#' walls, screencode_mixed encoding, case-aware recall |
| R14 | Fix Tunneling Difficulty + Enchanted Tools | ✅ Complete — hardness rescaled, new (STR>>2)+base+(ego×12) formula, Gnomish/Orcish/Dwarven variants, bare-hands no-progress, rubble resistance, si_ego save/load |
| R15 | Multi-Disk Support | ✅ Complete — save_device variable, 7 SETLFS sites parameterized, mode 2 no-ops, probe_device_9, disk setup sub-menu (S/W/9), missing disk_prompt_game calls fixed, rundual Makefile target |
| R16 | Save Drive Selection | ✅ Complete — `#)Drive #` menu option; disk_enter_device reads 1–2 digit device# (8–30), validates, probes via generic probe_device; shows "[Drive N]" indicator |
| R17 | Background History + Gender + Gold | ✅ Complete — 72-entry background table, chain walker, gender prompt, social class 1–100, umoria gold formula, word-wrap char sheet display, save/load v$0b |
| BUG-42 | Fix Save/Load Corruption | ✅ Complete — streaming RLE decompressor overflow fixed by replacing with raw map I/O (3840 bytes); LOAD_SEC_ADDR fixed; title screen KERNAL LOAD cleanup (CLOSE file, clear $90) |
| R12 | Game-Over Loop | ✅ Complete — R)EBOOT / S)TART / Q)UIT prompt; reboot stuffs BASIC keyboard buffer with RUN; restart resets ZP+inventory+tier and jumps to restart_entry |
| 10 | C128 Enhancements | Not started |

### Build Stats

- **Test suites:** 24 (320 runtime tests)
- **Compile-time asserts:** 71
- **Source files:** ~51 .s files
- **Program size:** $B47C (program_end) — **2,948 bytes headroom** to MAP_BASE ($C000)
- **Banked code:** $F000-$FF98 (at limit)
- **Banked payload:** $B4A9-$C444
- **Town overlay:** 3,016 of 4,096 bytes (1,080 free)
- **Startup overlay:** 4,017 of 4,096 bytes (79 free)
- **DungeonGen overlay:** 3,530 of 4,096 bytes (566 free)

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
| BUG-43 | MED | Store-stocked items not identified — `store_restock_one` (store.s:154-163) sets `si_item_id`, `si_qty`, `si_p1` but never sets `IF_IDENTIFIED` in `si_flags`. umoria's `store_create()` calls `magicTreasure()` then `storeItemInsertIntoStock()` which sets `STR_IDENTIFIED`. Fix: `ora #IF_IDENTIFIED` on `si_flags,y` after stocking. | **Fixed** — `sro_store_p1` stores `#IF_IDENTIFIED` in `si_flags`; test 29 added to test_store.s |
| BUG-44 | MED | Save file not found shows wrong error and wrong recovery — when LOAD returns file-not-found, the game prints "Save game corrupt" and falls through to character creation instead of returning to the New/Load/Dual menu. Fix: check the KERNAL status after LOAD; on file-not-found ($42 or carry set with no data), print "Save file not found" and jump back to the title/game-start menu. | **Fixed** — OPEN-fail path now shows "Save file not found."; `!title_load_fail` in main.s jumps back to `!title_menu_loop-` instead of `!title_new+` |
| BUG-45 | MED | Item generation uses flat uniform distribution — `pick_item_type` (item.s) rolls uniformly from items 2–63 and accepts any whose `min_level <= dlvl+2`. This means low-level items (torches, food, basic potions) perpetually dominate every drop because they are always valid. umoria's `itemGetRandomObjectId` uses a depth-weighted allocation table (`treasure_levels`): 50% flat pick from valid pool, 50% "best of 3" curve that picks the highest-depth of 3 random items then re-rolls within that exact depth tier — creating a pronounced curve that shifts drops toward the current dungeon level. Additionally, C64's great-item (1-in-12) check bypasses `min_level` entirely, giving equal odds to a torch vs. the best item in the game; umoria multiplies the generation level but still feeds it through the curved allocator. Fix: rewrite `pick_item_type` to use a `treasure_levels`-style depth-bucketed allocator with the 50/50 flat/best-of-3 algorithm. | **Fixed** — depth-bucketed 50/50 flat/best-of-3 allocator with 62-item sorted table and 13-level cumulative bounds; great items (1/12) access full pool |
| BUG-46 | MED | Monster melee attack from non-adjacent position — observed a Jackal killing the player while appearing 2+ tiles away on screen. Root cause: all `turn_post_action` death paths skip the post-AI render (`jmp !player_died+` before `render_viewport`), so the death screen shows the last pre-AI frame with stale monster positions. Fix: call `viewport_update` + `render_viewport` at the top of `!player_died:` so the accurate final state is visible when "YOU HAVE BEEN SLAIN." appears. | **Fixed** — `!player_died:` now renders viewport before showing death message (main.s:1389) |
| BUG-47 | HIGH | OPT-5 overlay IRQ lockup — dungeon descent hung every time. `verify_connectivity`, `tramp_assign_special_room`, and `tramp_vault_seal_entrance` each called `cli` unconditionally at return. When invoked while `$01=$34` (KERNAL ROM off, KERNAL IRQ vector missing), CIA1 timer IRQ fires into garbage RAM → wild jump → hang. Fix: `php` at entry / `plp` at exit in all three functions preserves caller's interrupt state. Also added 3 interrupt-preservation unit tests to `test_dungeon.s` (tests 33–35). | **Fixed** — `php`/`plp` in verify_connectivity (dungeon_gen.s) and both trampolines (main.s); 35/35 dungeon tests pass |
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |

### What's Next

**Phase 10 — C128 Enhancements** (not started):

| # | What | Summary |
|---|------|---------|
| 10.0 | Separate binaries | BOOT.PRG + MORIA64 + MORIA128 — prerequisite for all C128 work |
| 10.1 | 80-column VDC mode | Second rendering backend for VDC 80x25 display |
| 10.2 | Extended memory | C128 128KB MMU bank-switch path (no disk tier loading) |
| 10.3 | Larger dungeon | Expand map to 120x80+, more rooms, up to 64 active monsters |
| 10.4 | Enhanced display | VDC color attributes for threat-coded monsters |

---

### Priority Triage (updated 2026-02-21)

**Remaining items:**

**Small (gameplay polish):**
- _(none pending)_

**Low priority (polish/completeness):**
- A6 Large file split — opportunistic refactoring (item.s)
- OPT-5 (Options 2+3) — further overlays for magic/spells and UI screens if main segment tightens again

---



