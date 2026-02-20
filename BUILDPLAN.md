# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-02-20 — updated)

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
| 10 | C128 Enhancements | Not started |

### Build Stats

- **Test suites:** 22 (300 runtime tests)
- **Compile-time asserts:** 70
- **Source files:** ~47 .s files (projectile.s added by OPT-4)
- **Program size:** $BBBF (program_end) — **1,089 bytes headroom** to MAP_BASE ($C000)
- **Banked code:** $F000-$FFF7 (3 bytes headroom to CPU vectors — very tight)
- **Banked payload:** $C002-$CFF9 (7 bytes headroom to I/O at $D000)
- **Town overlay:** 2,891 of 4,096 bytes (1,204 free)

### Known Remaining Issues

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| BUG-34 | MED | Monster recall only shows first match when multiple creatures share a display symbol. umoria cycles through all known creatures with that letter; moria8 finds the first match and stops. Fix: add a recall cycling loop similar to umoria's `recallMonsterAttributes()`. | **Fixed** — pressing the same letter again cycles to the next known creature with that symbol (wraps around); state tracked in recall_last_sc/idx |
| BUG-41 | HIGH | Tunneling far too easy — hardness values scaled ~50× too low vs umoria but tool bonuses copied verbatim. Pick+STR18 = 100% success on granite (should be ~1%). Bare hands dig granite ~50% of the time. See R14 for fix plan. | Open |
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
| 1 | R14 | Fix tunneling difficulty (BUG-41) + enchanted digging tools | Medium |
| 2 | R12 | Game-over loop (restart/reboot prompt instead of exit to BASIC) | Low |
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
- R14 Fix tunneling difficulty (BUG-41) + enchanted digging tools (Gnomish/Orcish/Dwarven variants)
- R12 Game-over loop — after save/death/quit, prompt "Restart" or "Reboot" instead of exiting to BASIC

**Low priority (polish/completeness):**
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

## R14 — Fix Tunneling Difficulty + Enchanted Digging Tools (BUG-41)

Two changes: (A) fix the broken hardness/bonus scaling so digging difficulty matches umoria, and (B) add enchanted tool variants (Gnomish Shovel, Orcish Pick, Dwarven Shovel, Dwarven Pick) so deeper dungeon levels reward better tools — matching umoria's progression.

### Part A: Fix Hardness/Bonus Scaling

#### Root Cause

umoria uses 16-bit hardness (granite: 80–1280) compared against ability values typically 25–193. moria8 scaled hardness to fit 8 bits (granite: 8–27) but didn't scale the bonuses (Pick still +75), so ability always exceeds hardness. With a Pick + STR 18, every wall type is a guaranteed one-hit dig (should be ~1% for granite). Bare hands dig granite ~50% of the time (should be impossible).

#### New Digging Ability Formula

```
bare hands      → ability = 0, print "no progress" message, skip check
digging tool    → ability = (STR >> 2) + base_bonus + (enchant_level * 12)
regular weapon  → ability = (STR >> 2) + max(0, toDam >> 1)
```

STR >> 2 maps STR 3–18 to 0–4 (coarse, but tool bonus dominates — same as umoria where STR is a small fraction of total ability).

#### New Hardness Values

| Wall Type | Current | New | umoria reference |
|-----------|---------|-----|------------------|
| Granite | rng(20)+8 → 8–27 | **rng(240)+16** → 16–255 | rand(1200)+80 → 80–1280 |
| Magma | rng(12)+3 → 3–14 | **rng(120)+5** → 5–124 | rand(600)+10 → 10–610 |
| Quartz | rng(10)+2 → 2–11 | **rng(80)+3** → 3–82 | rand(400)+10 → 10–410 |
| Rubble | 0 (auto-succeed) | **rng(40)** → 0–39 | rand(180) → 1–180 |

#### Bare Hands

umoria prints "You dig with your hands, making no progress" and doesn't roll. moria8 should do the same — if no weapon equipped, set ability=0 and short-circuit before the resistance check. Needs a new Huffman string (HSTR_TUN_NO_TOOL).

#### Rubble

Changes from always-succeed to a resistance check (rng(40)), matching umoria. With a Pick it's ~60% per turn — still fast. Bare hands can't clear rubble, matching umoria.

### Part B: Enchanted Digging Tools

#### umoria Tool Progression

umoria has 6 digging tools across 4 effectiveness tiers, using the `misc_use` field:

| Tool | misc_use | umoria ability (STR 18) | Min DL | Cost |
|------|----------|------------------------|--------|------|
| Shovel | 0 | STR + 25 = 43 | 0 | 0 |
| Pick | 1 | STR + 75 = 93 | 1 | 0 |
| Gnomish Shovel | 1 | STR + 75 = 93 | 20 | 100 |
| Orcish Pick | 2 | STR + 125 = 143 | 20 | 500 |
| Dwarven Shovel | 2 | STR + 125 = 143 | 40 | 250 |
| Dwarven Pick | 3 | STR + 175 = 193 | 50 | 1200 |

Formula: `ability = STR + 25 + (misc_use × 50)`

#### moria8 Enchanted Tool Design

Reuse existing item types 62 (Shovel) and 63 (Pick) — no new item type slots needed (table is full at 64/64). Differentiate via the `inv_ego`/`fi_ego` byte, which already exists on every item instance and is already saved/loaded.

**Ego byte interpretation for ICAT_DIGGING:**

| ego | Shovel name | Pick name | Enchant bonus |
|-----|-------------|-----------|---------------|
| 0 | Shovel | Pick | +0 |
| 1 | Gnomish Shovel | Orcish Pick | +12 |
| 2 | Dwarven Shovel | Dwarven Pick | +12 more |

**Dig ability with enchantment:** `(STR >> 2) + base_bonus + (ego × 12)`

| Tool | ego | Base | Total bonus | Ability (STR 18) |
|------|-----|------|-------------|------------------|
| Shovel | 0 | 6 | 6 | 10 |
| Gnomish Shovel | 1 | 6 | 18 | 22 |
| Dwarven Shovel | 2 | 6 | 30 | 34 |
| Pick | 0 | 20 | 20 | 24 |
| Orcish Pick | 1 | 20 | 32 | 36 |
| Dwarven Pick | 2 | 20 | 44 | 48 |

#### Resulting Success Rates

**vs Granite (rng(240)+16 → 16–255):**

| Tool | Ability (STR18) | moria8 P(success) | umoria P(success) |
|------|-----------------|-------------------|-------------------|
| Shovel | 10 | 0% | 0% |
| Pick | 24 | 3.3% | 1.0% |
| Gnomish Shovel | 22 | 2.5% | 1.0% |
| Orcish Pick | 36 | 8.3% | 5.3% |
| Dwarven Shovel | 34 | 7.5% | 5.3% |
| Dwarven Pick | 48 | 13.3% | 9.4% |
| Bare hands | 0 | 0% | 0% |

**vs Magma (rng(120)+5 → 5–124):**

| Tool | moria8 P | umoria P |
|------|----------|----------|
| Shovel | 4.2% | 5.5% |
| Pick | 15.8% | 13.8% |
| Gnomish Shovel | 14.2% | 13.8% |
| Orcish Pick | 25.8% | 22.2% |
| Dwarven Shovel | 24.2% | 22.2% |
| Dwarven Pick | 35.8% | 30.5% |

**vs Quartz (rng(80)+3 → 3–82):**

| Tool | moria8 P | umoria P |
|------|----------|----------|
| Shovel | 8.8% | 8.3% |
| Pick | 26.3% | 20.8% |
| Orcish Pick | 41.3% | 33.3% |
| Dwarven Pick | 56.3% | 45.8% |

All rates are close to umoria. Moria8 is consistently slightly easier, which compensates for C64's slower gameplay pace.

#### Tool Enchantment Roll

Extend `roll_ego_type` (in `ego_items.s`, lives at $F000) to also handle `ICAT_DIGGING`:

```
roll_ego_type:
    tax
    lda it_category,x
    cmp #ICAT_WEAPON
    beq !ret_weapon_ego+
    cmp #ICAT_DIGGING
    beq !ret_tool_ego+
    lda #0
    rts

!ret_tool_ego:
    // Chance based on dungeon level:
    //   DL < 10: always ego=0 (basic tools only)
    //   DL 10-19: 25% chance ego=1
    //   DL 20+: 25% chance ego=1, 10% chance ego=2
    lda zp_player_dlvl
    cmp #10
    bcc !ret_zero+          // DL < 10 → basic only
    lda #100
    jsr rng_range
    cmp #10
    bcc !ret_ego2+          // 10% → Dwarven (ego=2)
    cmp #35
    bcc !ret_ego1+          // 25% → Gnomish/Orcish (ego=1)
    lda #0                  // 65% → basic
    rts
!ret_ego2:
    lda zp_player_dlvl
    cmp #20
    bcc !ret_ego1+          // DL 10-19 can't get ego=2
    lda #2
    rts
!ret_ego1:
    lda #1
    rts
```

This is ~35 bytes in the $F000 banked region (720 bytes free there).

#### Name Display: Prefix Instead of Suffix

Weapons use ego as a suffix: "Long Sword (Flame)". Tools use ego as a **prefix**: "Dwarven Pick".

**Display path change:** In `ui_inventory.s`, the current flow is:
1. `item_get_name_ptr` → get base name
2. `screen_put_string` → print name
3. `banked_ego_put_suffix` → append suffix

For tools with ego > 0, insert a prefix **before** the base name:
1. Check if `ICAT_DIGGING` AND `ego > 0`
2. If yes: print prefix string ("Gnomish ", "Orcish ", "Dwarven ") **first**
3. Then print base name ("Shovel" / "Pick")
4. Skip suffix (tool egos don't use suffixes)

**Prefix strings** (3 unique, in $F000 banked region):
```
ego_tool_prefix_gnomish: .text "Gnomish " ; .byte 0   // 9 bytes
ego_tool_prefix_orcish:  .text "Orcish " ; .byte 0    // 8 bytes
ego_tool_prefix_dwarven: .text "Dwarven " ; .byte 0   // 9 bytes
```

**Lookup:** Indexed by (tool_type - 62) × 2 + ego - 1:

| Index | Tool + ego | Prefix |
|-------|-----------|--------|
| 0 | Shovel ego=1 | Gnomish |
| 1 | Shovel ego=2 | Dwarven |
| 2 | Pick ego=1 | Orcish |
| 3 | Pick ego=2 | Dwarven |

```
tool_ego_prefix_lo: .byte <ego_tool_prefix_gnomish, <ego_tool_prefix_dwarven
                    .byte <ego_tool_prefix_orcish,  <ego_tool_prefix_dwarven
tool_ego_prefix_hi: (matching high bytes)
```

~30 bytes for strings + ~8 bytes for tables = ~38 bytes in $F000.

#### Store Availability

- **General Store:** sells basic Shovel and Pick only (no change).
- **Dungeon floor:** enchanted variants spawn via ego roll at DL 10+.
- **Home storage:** enchanted tools can be stashed (ego byte already saved/loaded).

#### Pricing

Enchanted tools should be worth more when sold. The existing `item_get_value` function can check the ego byte for ICAT_DIGGING and multiply:
- ego=0: base price (Shovel 15g, Pick 50g)
- ego=1: base × 5 (Gnomish 75g, Orcish 250g)
- ego=2: base × 15 (Dwarven Shovel 225g, Dwarven Pick 750g)

### Implementation Summary

#### Files Changed

1. **`tunnel.s`** — Change 4 hardness calculations, add rubble resistance check
2. **`main.s:banked_dig_ability`** — New formula: `(STR >> 2) + base + (ego × 12)`, bare-hands short-circuit, read `inv_ego` for equipped tool
3. **`ego_items.s`** ($F000) — Add `ICAT_DIGGING` branch to `roll_ego_type`, add tool prefix strings + lookup table
4. **`ui_inventory.s`** — Add tool ego prefix display path (check ICAT_DIGGING before name, print prefix, skip suffix)
5. **`item.s`** — Adjust `item_get_value` for tool ego pricing multiplier
6. **Huffman string table** — Add HSTR_TUN_NO_TOOL ("You dig with your hands, making no progress.")

#### Size Impact

| Region | Change | Bytes |
|--------|--------|-------|
| Main segment | tunnel.s hardness changes | ~net zero |
| Main segment | dig_ability formula + bare-hands | ~+10 |
| Main segment | ui_inventory prefix path | ~+25 |
| Main segment | item_get_value ego pricing | ~+15 |
| Main segment | Huffman string | ~+25 |
| $F000 banked | roll_ego_type tool branch | ~+35 |
| $F000 banked | prefix strings + tables | ~+38 |
| **Total main** | | **~+75 bytes** |
| **Total $F000** | | **~+73 bytes** (of 720 free) |

#### Testing

- Bare hands → always fails (ability = 0)
- Basic Pick + STR 18 → ability = 24 (4 + 20)
- Basic Shovel + STR 18 → ability = 10 (4 + 6)
- Orcish Pick (ego=1) + STR 18 → ability = 36 (4 + 20 + 12)
- Dwarven Pick (ego=2) + STR 18 → ability = 48 (4 + 20 + 24)
- Granite minimum resistance = 16 (shovel can never dig granite)
- Rubble max resistance = 39 (basic pick almost always clears it)
- Tool ego roll: returns 0 at DL < 10, returns 0-1 at DL 10-19, returns 0-2 at DL 20+
- Name display: "Dwarven Pick" not "Pick (Dwarven)"
- Enchanted tools save/load correctly (ego byte already in save format)

