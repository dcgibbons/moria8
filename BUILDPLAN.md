# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-02-20 — R12 complete)

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
| R12 | Game-Over Loop | ✅ Complete — R)EBOOT / S)TART / Q)UIT prompt; reboot stuffs BASIC keyboard buffer with RUN; restart resets ZP+inventory+tier and jumps to restart_entry |
| 10 | C128 Enhancements | Not started |

### Build Stats

- **Test suites:** 23 (308 runtime tests)
- **Compile-time asserts:** 70
- **Source files:** ~48 .s files
- **Program size:** $BEED (program_end) — **275 bytes headroom** to MAP_BASE ($C000)
- **Banked code:** $F000-$FF98 (at limit)
- **Banked payload:** $BF1A-$CEB2
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
| BUG-43 | MED | Store-stocked items not identified — `store_restock_one` (store.s:154-163) sets `si_item_id`, `si_qty`, `si_p1` but never sets `IF_IDENTIFIED` in `si_flags`. umoria's `store_create()` calls `magicTreasure()` then `storeItemInsertIntoStock()` which sets `STR_IDENTIFIED`. Fix: `ora #IF_IDENTIFIED` on `si_flags,y` after stocking. | **Fixed** — `sro_store_p1` stores `#IF_IDENTIFIED` in `si_flags`; test 29 added to test_store.s |
| BUG-44 | MED | Save file not found shows wrong error and wrong recovery — when LOAD returns file-not-found, the game prints "Save game corrupt" and falls through to character creation instead of returning to the New/Load/Dual menu. Fix: check the KERNAL status after LOAD; on file-not-found ($42 or carry set with no data), print "Save file not found" and jump back to the title/game-start menu. | Open |
| BUG-45 | MED | Item generation uses flat uniform distribution — `pick_item_type` (item.s) rolls uniformly from items 2–63 and accepts any whose `min_level <= dlvl+2`. This means low-level items (torches, food, basic potions) perpetually dominate every drop because they are always valid. umoria's `itemGetRandomObjectId` uses a depth-weighted allocation table (`treasure_levels`): 50% flat pick from valid pool, 50% "best of 3" curve that picks the highest-depth of 3 random items then re-rolls within that exact depth tier — creating a pronounced curve that shifts drops toward the current dungeon level. Additionally, C64's great-item (1-in-12) check bypasses `min_level` entirely, giving equal odds to a torch vs. the best item in the game; umoria multiplies the generation level but still feeds it through the curved allocator. Fix: rewrite `pick_item_type` to use a `treasure_levels`-style depth-bucketed allocator with the 50/50 flat/best-of-3 algorithm. | Open |
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |

### What's Next

| Priority | # | What | Effort |
|----------|---|------|--------|
| 1 | BUG-44 | Save file not found → wrong error + wrong recovery path | Small |
| 2 | BUG-45 | Item generation flat distribution — rewrite pick_item_type with depth-bucketed 50/50 flat/best-of-3 curve | Medium |
| 3 | R16 | Save drive selection — any IEC device number (8–30) | Small |
| 4 | A4 | Separate binaries (BOOT.PRG + MORIA64 + MORIA128) | Major (Phase 10) |

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

**Small (gameplay polish):**
- R16 Save drive selection — replace hardcoded drive-9 option with free entry of any valid IEC device number

**Low priority (polish/completeness):**
- A4 Separate binaries — Phase 10 scope (BOOT.PRG + MORIA64 + MORIA128)
- A6 Large file split — opportunistic refactoring (dungeon_gen.s, item.s)
- BUG-45 Item generation flat distribution — rewrite pick_item_type (medium effort)

---

## R16 — Save Drive Selection (Any IEC Device Number)

### Why

R15 added multi-disk support but hardcoded two choices: device 8 (same or swap disk) or device 9 (dual drive). Real setups vary — SD2IEC users often put the save image on drive 10 or 11; CMD HD partitions commonly use 8–12. The fixed "9" option is also brittle: `probe_device_9` reports absent and the option is greyed out even when device 9 is present but slow to respond.

### What

Replace the `9)Drive 9` option in the title-screen disk sub-menu with `#)Drive #`, which prompts the player to type a 1–2-digit device number. Any value 8–30 is accepted. After entry, probe the device (reuse/extend `probe_device_9` into a generic `probe_device`). If the probe succeeds, set `save_device` and `disk_mode=2` (dual-drive, no swap prompts). If the probe fails, show an error and return to the disk menu.

### UI Change

Current menu row (disk_swap.s `ds_menu_str`):
```
S)ame W)swap 9)Drive 9
```
New:
```
S)ame W)swap #)Drive #
```

Pressing `#` (PETSCII `$23`) triggers the number-entry sub-flow on the next row:
```
Save drive (8-30):
```
The player types 1–2 digits and presses RETURN. Backspace/DEL corrects a digit. After RETURN, validate range (8–30) and probe.

### Implementation

1. **`ds_menu_str`** (disk_swap.s) — change `9)Drive 9` → `#)Drive #` (same byte count, no size change).

2. **Title-menu disk handler** (main.s ~line 220–308) — replace the `$39` ('9') branch with a `$23` ('#') branch that calls `disk_enter_device`.

3. **`disk_enter_device`** (disk_swap.s) — new routine (~60 bytes):
   - Print prompt `Save drive (8-30): ` on row 18.
   - Read 1–2 digit keypresses ($30–$39 = '0'–'9'). RETURN commits; DEL erases last digit. Non-digit ignored.
   - Convert ASCII digits to binary (tens × 10 + units).
   - Validate 8 ≤ value ≤ 30; if out of range, blink/redisplay.
   - Call `probe_device` with the entered number.
   - On success: `sta save_device`, `lda #2; sta disk_mode`, clear row, return to title menu.
   - On fail: print `Drive ## not found!`, wait for key, redisplay disk menu.

4. **`probe_device`** (disk_swap.s) — generalise `probe_device_9` to accept device# in X (~5 bytes delta, or just inline the change). `probe_device_9` becomes a wrapper `ldx #9; jmp probe_device`.

### Size Budget

With only 275 bytes of headroom in the main segment, placement matters:
- `disk_enter_device`: ~60 bytes — fits in `disk_swap.s` (loaded in main segment).
- Prompt string `Save drive (8-30): ` = 20 bytes — in `disk_swap.s`.
- `probe_device` refactor: net ~+5 bytes.
- Total delta: ~85 bytes — fits within the 275 byte main segment headroom.

If tight, the number-entry routine can move to the `$F000` banked region via a trampoline (pattern already used for `reu_show_status`, `store_enter`, etc.).

### Risks

- **Probe false-negative:** slow/busy devices may time out. Consider showing "Probing…" before the KERNAL OPEN call.
- **Mode 1 (swap) + arbitrary drive:** if the player later sets swap mode independently, `save_device` should already hold the right number. The swap/same options always set `save_device=8`, which is correct for those modes. The `#` option sets mode 2 (no swap prompts) so there is no conflict.

---


