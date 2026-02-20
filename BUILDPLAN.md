# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-02-19)

**All core phases complete.** The game is fully playable from title screen through dungeon exploration, combat, magic, stores, save/load, death, and high scores. Ranged combat (R1.1) added. OPT-1 code size optimizations applied (excluding OPT-1.1).

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
| OPT-3 | Town Overlay Optimization | ✅ Complete — 1,183 bytes saved (4,074→2,891), 1,204 bytes free |
| R7 | String Compression | ✅ Complete — R7.1-R7.7 all done. Tier 1: 155 strings Huffman-compressed, 888 bytes saved. Tier 2: string bank encoder/loader ($E000 overlay), monster recall system. |
| R2.5 | Tunneling + Treasure Veins | ✅ Complete — + command, STR-based digging, treasure in quartz/magma veins, wall-to-mud fix, 742 bytes |
| R11 | Lowercase/Uppercase Mode | ✅ Complete — 52 monster symbols (a-z + A-Z), '#' walls, screencode_mixed encoding, case-aware recall |
| 10 | C128 Enhancements | Not started |

### Build Stats

- **Test suites:** 22 (300 runtime tests)
- **Compile-time asserts:** 68
- **Source files:** ~46 .s files
- **Program size:** $BFD5 (program_end) — **43 bytes headroom** to MAP_BASE ($C000)
- **Banked code:** $F000-$FFF7 (3 bytes headroom to CPU vectors — very tight)
- **Banked payload:** $C002-$CFF9 (7 bytes headroom to I/O at $D000)
- **Town overlay:** 2,891 of 4,096 bytes (1,204 free)

### Known Remaining Issues

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| BUG-34 | MED | Monster recall only shows first match when multiple creatures share a display symbol. umoria cycles through all known creatures with that letter; moria8 finds the first match and stops. Fix: add a recall cycling loop similar to umoria's `recallMonsterAttributes()`. | Open |
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

### Priority Triage (updated 2026-02-19)

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
- **Size:** ~40-60 bytes for the prompt + ~20-30 bytes for reinit calls. Well within current headroom if an OPT-4 item is done first, or fits in the $F000 banked region.

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

---

## Codebase-Wide Size Optimization — OPT-4 (2026-02-18)

### Current State

Main segment: **$080E–$BFEF** (~46,049 bytes, ~17 bytes before $C000 MAP_BASE).
$F000 banked region: 3,369 of ~4,089 bytes used (~720 bytes free).
Town overlay: 4,074 of 4,096 bytes (22 free — covered by OPT-3).

The main segment has reasonable headroom but adding major features will require optimization. This section identifies cross-module duplication and data compression opportunities that collectively could save **~1,500–2,200 bytes** in the main segment.

### OPT-4.1 — Shared Projectile Trace Loop (~150-180 bytes saved)

Three files contain nearly identical projectile trace loops:

| File | Function | Lines | Pattern |
|------|----------|-------|---------|
| `ranged_fire.s` | `!rf_trace` | 112-161 | Step in direction → bounds check → walkability check → monster_find_at |
| `throw.s` | `!tw_trace` | 160-215 | Identical + saves last walkable position |
| `spell_effects.s` | `!eb_trace` | 562-683 | Identical + bolt animation overlay |

The core trace loop is ~50 bytes each: direction step (8 bytes), bounds check (12 bytes), map tile walkability via `walkable_table` (18 bytes), `monster_find_at` call (6 bytes). All three use the same variable pattern: `*_cx`, `*_cy`, `*_dir`, `*_steps`.

**Fix:** Create a shared `trace_projectile` routine:

```asm
// Input: proj_cx/cy = start, proj_dir = direction, proj_steps = max range
// Output: carry SET = hit monster (X = slot), carry CLEAR = blocked/OOB
//         proj_cx/cy = final position
proj_cx:    .byte 0
proj_cy:    .byte 0
proj_dir:   .byte 0
proj_steps: .byte 0
proj_last_x: .byte 0    // Last walkable position (for throw drop)
proj_last_y: .byte 0

trace_projectile:
    dec proj_steps
    beq !tp_oob+
    ldx proj_dir
    lda proj_cx
    clc
    adc dir_dx,x
    sta proj_cx
    lda proj_cy
    clc
    adc dir_dy,x
    sta proj_cy
    // Bounds + walkability + monster check...
    // ~50 bytes total
```

Each caller shrinks from ~50 bytes inline to ~15 bytes of setup + `jsr trace_projectile`. `throw.s` copies `proj_cx/cy → proj_last_x/y` after each step (4 bytes extra). `spell_effects.s` adds animation code after the walkability check via a callback flag or inline hook.

- 3 × ~50 = 150 bytes inline → 50 byte helper + 3 × 15 = 95 bytes
- **Net savings: ~55 bytes** (conservative, more with the direction-finding code below)

### OPT-4.2 — Shared Direction-Finding from Target (~80-100 bytes saved)

Three files contain identical direction-finding code that converts `df_target_x/y` delta into a `dir_dx/dir_dy` table index:

```asm
    lda df_target_x
    sec
    sbc zp_player_x
    sta zp_temp0            // dx
    lda df_target_y
    sec
    sbc zp_player_y
    sta zp_temp1            // dy
    ldx #0
!find_dir:
    lda dir_dx,x
    cmp zp_temp0
    bne !dir_next+
    lda dir_dy,x
    cmp zp_temp1
    beq !dir_found+
!dir_next:
    inx
    cpx #8
    bcc !find_dir-
```

This ~30-byte pattern appears in `ranged_fire.s` (lines 78-101), `throw.s` (lines 97-121), and `spell_effects.s` (lines 526-549).

**Fix:** Extract a shared `calc_direction_index` utility:

```asm
// Input: df_target_x/y (adjacent to player)
// Output: X = direction index 0-7, carry SET = found
calc_direction_index:
    lda df_target_x
    sec
    sbc zp_player_x
    sta zp_temp0
    lda df_target_y
    sec
    sbc zp_player_y
    sta zp_temp1
    ldx #0
!:  lda dir_dx,x
    cmp zp_temp0
    bne !next+
    lda dir_dy,x
    cmp zp_temp1
    beq !found+
!next:
    inx
    cpx #8
    bcc !-
    clc
    rts
!found:
    sec
    rts
```

~35 byte helper, each call site becomes `jsr calc_direction_index; bcc cancel; stx *_dir` (~8 bytes).

- 3 × ~30 = 90 bytes → 35 + 3 × 8 = 59 bytes
- **Net savings: ~30 bytes**

Combined with OPT-4.1 (shared trace loop, shared direction finding, shared scratch vars), total savings ~**150-180 bytes**.

### OPT-4.3 — Unify Adjacent-Tile Iteration (~120-150 bytes saved)

`spell_effects.s` has **four** separate 8-direction adjacent-tile loops with identical structure:

| Function | Lines | Action per direction |
|----------|-------|---------------------|
| `eff_sleep_adjacent` | 420-455 | find_at → set MX_SLEEP_CUR |
| `eff_confuse_adjacent` | 463-497 | find_at → set MX_CONFUSE |
| `eff_damage_adjacent` | 775-836 | find_at → roll dice → subtract HP → death check |
| `eff_destroy_traps_doors` | 864-980 | read tile → modify tile (TWO separate 8-dir loops!) |

Each loop follows the identical skeleton (~35 bytes):

```asm
    lda #0
    sta *_dir
!loop:
    lda *_dir
    cmp #8
    bcs !done+
    tax
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    ...action...
    inc *_dir
    jmp !loop-
!done:
    rts
```

**Fix:** Create `for_each_adjacent(callback)` using a function pointer or inline dispatch:

```asm
// Iterates 8 directions, for each: sets df_target_x/y, calls callback via JMP indirect
adj_callback: .word 0   // Function pointer

for_each_adjacent:
    lda #0
    sta adj_dir_idx
!fea_loop:
    lda adj_dir_idx
    cmp #8
    bcs !fea_done+
    tax
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y
    jsr !fea_dispatch+
    inc adj_dir_idx
    jmp !fea_loop-
!fea_done:
    rts
!fea_dispatch:
    jmp (adj_callback)
```

Helper: ~40 bytes. Each call site becomes: set callback pointer (6 bytes) + `jsr for_each_adjacent` (3 bytes) + callback body (varies, ~10-15 bytes). The 5 loops of ~35 bytes each become 5 × 9 + 40 = 85 bytes.

- 5 × ~35 = 175 bytes → ~85 bytes
- **Net savings: ~90 bytes**

Alternative (simpler, no function pointers): factor out only the "find monster at adjacent direction" pattern shared by sleep/confuse/damage into a single `for_each_adjacent_monster` that provides X=slot for each found monster. Saves ~70 bytes from just those three.

### OPT-4.4 — Inline Monster HP Damage + Death Check → Shared Subroutine (~80-100 bytes saved)

The pattern "subtract damage from monster HP via `(zp_ptr0),y` + check dead" appears **three times** inline in `spell_effects.s` (eff_bolt line 704-720, eff_damage_adjacent line 810-825, eff_dispel_undead line 1084-1100) and once as the existing `combat_apply_damage` in `combat.s` (line 671-703).

The inline versions duplicate ~25 bytes each and differ only in the damage source register (zp_math_a/b vs A):

```asm
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sec
    sbc zp_math_a
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    sbc zp_math_b
    sta (zp_ptr0),y
    bmi !dead+
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    ldy #MX_HP_HI
    ora (zp_ptr0),y
    bne !alive+
```

**Fix:** Extend `combat_apply_damage` to accept 16-bit damage (currently only 8-bit via A register). Or create a `combat_apply_damage_16` variant that reads from zp_math_a/b. The inline code in spell_effects.s then becomes `jsr combat_apply_damage_16` (3 bytes each).

- 3 × ~25 = 75 bytes inline → 25 byte helper + 3 × 3 = 34 bytes
- **Net savings: ~40 bytes** (plus cleaner code)

### OPT-4.5 — Unify combat_calc_tohit / throw_calc_tohit (~100-120 bytes saved)

`combat.s:combat_calc_tohit` (lines 168-257, ~90 bytes) and `throw.s:throw_calc_tohit` (lines 417-516, ~100 bytes) are structurally identical. The only differences:

| Aspect | combat_calc_tohit | throw_calc_tohit |
|--------|------------------|-----------------|
| Class property offset | BTH (offset 3) | BTH_BOW (offset 4) |
| Level adj offset | class_level_adj+0 | class_level_adj+1 |
| Post-processing | None | × 75% (×3 >> 2) |

**Fix:** Parameterize with a "BTH offset" passed in A or a ZP var:

```asm
// Input: A = class property offset (3=melee, 4=bow)
//        X = level adj offset (0=melee, 1=bow)
combat_calc_tohit_common:
    sta cct_prop_offset
    stx cct_lvl_offset
    // ... shared code (~90 bytes) ...
    rts

// throw_calc_tohit wrapper: calls common then applies 75%
throw_calc_tohit:
    lda #4
    ldx #1
    jsr combat_calc_tohit_common
    // 75% = *3/4
    lda zp_combat_tohit
    sta zp_temp0
    asl
    bcs !cap+
    clc
    adc zp_temp0
    bcc !div+
!cap: lda #255
!div: lsr
    lsr
    sta zp_combat_tohit
    rts
```

The 75% wrapper is ~20 bytes. The shared routine is ~90 bytes. Eliminates ~100 bytes of throw.s duplication.

- 90 + 100 bytes → 90 + 20 = 110 bytes
- **Net savings: ~80 bytes**

### OPT-4.6 — Table-Driven Effect Timer Ticks (~60-80 bytes saved)

`turn.s:turn_tick_effects` (lines 20-208) has 13 individual effect timers. Most follow one of two patterns:

**Pattern A — Simple decrement (7 timers: speed, protect, invis, infra, bless, hero, regen):**
```asm
    lda zp_eff_xxx
    beq !no_xxx+
    dec zp_eff_xxx
!no_xxx:
```
6 bytes each × 7 = 42 bytes. (Speed is slightly different — signed decrement — but the rest are identical.)

**Pattern B — Decrement with expiry message (5 timers: poison, blind, confuse, paralyze, fear):**
```asm
    lda zp_eff_xxx
    beq !no_xxx+
    dec zp_eff_xxx
    bne !no_xxx+   // or bne !still_xxx+
    ldx #HSTR_EFF_XXX_END
    jsr huff_decode_string
    jsr msg_print
!no_xxx:
```
~15 bytes each × 4 = 60 bytes (poison has extra HP damage logic, excluded).

**Fix for Pattern A:** Loop through a table of ZP addresses:

```asm
simple_effect_addrs:
    .byte zp_eff_protect, zp_eff_invis, zp_eff_infra
    .byte zp_eff_bless, zp_eff_hero, zp_eff_regen
.const SIMPLE_EFFECT_COUNT = 6

tick_simple_effects:
    ldx #SIMPLE_EFFECT_COUNT - 1
!loop:
    ldy simple_effect_addrs,x
    lda $00,y               // ZP indirect read
    beq !skip+
    dec $00,y               // ZP indirect decrement
!skip:
    dex
    bpl !loop-
    rts
```

~20 bytes replaces 36 bytes (6 × 6). Savings: ~16 bytes.

**Fix for Pattern B:** Loop through paired table (address, huff ID):

```asm
msg_effect_addrs:
    .byte zp_eff_blind, zp_eff_confuse, zp_eff_paralyze
msg_effect_hstr:
    .byte HSTR_EFF_BLIND_END, HSTR_EFF_CONFUSE_END, HSTR_EFF_PARALYZE_END
.const MSG_EFFECT_COUNT = 3

tick_msg_effects:
    ldx #MSG_EFFECT_COUNT - 1
!loop:
    stx tte_save_x
    ldy msg_effect_addrs,x
    lda $00,y
    beq !skip+
    dec $00,y
    bne !skip+
    ldx tte_save_x
    lda msg_effect_hstr,x
    tax
    jsr huff_decode_string
    jsr msg_print
    ldx tte_save_x
!skip:
    dex
    bpl !loop-
    rts
```

~35 bytes replaces 45 bytes (3 × 15). Savings: ~10 bytes.

Fear and speed have special behavior (fear uses non-ZP `eff_fear_timer`; speed has signed increment logic) — keep those inline.

- **Total savings: ~26 bytes** (modest, but reduces maintenance burden for adding new effects)

### OPT-4.7 — Huffman-Encode Item Name Strings (~300-400 bytes saved)

`item.s` contains **110 raw `.text` strings** for item names totaling ~806 bytes (names only) + 124 bytes of pointer tables = **~930 bytes**. These are looked up via `it_name_lo/hi` tables.

The Huffman infrastructure already exists in main RAM. Item names are short uppercase English strings — the same character distribution as existing Huffman data. At ~55% compression:

- 806 bytes raw → ~445 bytes compressed
- Pointer tables (110 × 2 = 220 bytes) become index entries in the Huffman string table
- Decode call overhead: name lookup changes from pointer dereference to `huff_decode_string` call

The `item_get_name_ptr` function currently returns a raw pointer. After Huffman encoding, it would decode to `hd_decode_buf` and return a pointer to that. Callers already use the returned pointer with `screen_put_string` — no change needed.

- 930 bytes → ~445 compressed + ~220 index entries (already absorbed by Huffman table)
- **Net savings in main segment: ~300-400 bytes**

Note: Since `hd_decode_buf` is reused, callers that need to retain the name across another decode call would need to copy it first. Audit all `item_get_name_ptr` call sites.

### OPT-4.8 — Remaining Raw Strings to Huffman (~100-120 bytes saved)

Several modules still contain small raw strings that could be Huffman-encoded:

| File | Strings | Bytes |
|------|---------|-------|
| `turn.s` | pid_w_terrible/bad/average/good/excellent + pid_sense_str | 50 |
| `combat.s` | cmb_you_str, cmb_the_str, cmb_hit_str, cmb_miss_str, cmb_kill_str, cmb_period | 33 |

The `combat.s` strings are heavily used by `combat_append_str` which needs raw pointers for inline assembly into `combat_msg_buf`. These are poor Huffman candidates — the decode overhead would exceed the savings for 3-4 byte strings.

The `turn.s` pseudo-ID quality words (50 bytes + 10 bytes pointer tables = 60 bytes) are a better candidate — they're only used in one place. Encoding them saves ~30 bytes.

- **Net savings: ~30 bytes** (only pseudo-ID strings worth converting)

### OPT-4.9 — Deduplicate "Hit Alive / Dead" Message Patterns (~60-80 bytes saved)

After a monster takes damage, four modules repeat the same "dead or alive" message dispatch:

```asm
// Dead path:
    ldx slot
    jsr eff_kill_monster
    lda #<cmb_kill_str
    ldy #>cmb_kill_str
    jsr msg_build_action    // "YOU HAVE SLAIN THE <name>."
    jsr cmb_print_buf
    lda #SFX_HIT
    jsr sound_play
    rts

// Alive path:
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_AWAKE
    sta (zp_ptr0),y
    // Build "VERB THE <name>." message
    ...
```

This ~40-byte dead path appears in `combat.s` (line 111-134), `ranged_fire.s` (line 217-225), `throw.s` (line 296-304), and `spell_effects.s` (line 722-732).

**Fix:** Create `combat_kill_message`:
```asm
// Input: cmb_slot, cmb_type already set
// Prints "YOU HAVE SLAIN THE <name>.", plays SFX, awards XP
combat_kill_message:
    ldx cmb_slot
    jsr eff_kill_monster
    lda #<cmb_kill_str
    ldy #>cmb_kill_str
    jsr msg_build_action
    jsr cmb_print_buf
    lda #SFX_HIT
    jmp sound_play         // Tail call
```

~20 bytes. Each of 4 call sites becomes `jsr combat_kill_message` (3 bytes) instead of ~20 bytes inline.

- 4 × 20 = 80 bytes → 20 + 4 × 3 = 32 bytes
- **Net savings: ~48 bytes**

Similarly, the "wake monster" pattern (get_ptr, load flags, ora MF_AWAKE, store) is ~12 bytes and appears 3 times. A `monster_wake` helper saves ~20 bytes.

- **Combined savings: ~68 bytes**

### OPT-4.10 — Projectile Hit/Miss Message Deduplication (~50-60 bytes saved)

`ranged_fire.s` and `throw.s` both build identical hit/miss messages:

```asm
// "THE <item> HITS THE <name>."
    jsr *_msg_item_prefix       // "THE <item>"
    ldx #HSTR_RF_HITS
    jsr huff_append_combat      // " HITS"
    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str       // " THE "
    jsr combat_append_monster_name
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str       // "."
    jsr *_print_msg
```

This ~30-byte "append VERB THE name." suffix appears 4 times across the two files (hit + miss for both ranged and throw). The `*_msg_item_prefix` functions are also nearly identical (both build "THE <item>" — differ only in the item ID source).

**Fix:** Create `projectile_msg_suffix(verb_hstr_id)`:
```asm
// Appends " VERB THE <name>." to combat_msg_buf and prints
projectile_msg_suffix:
    jsr huff_append_combat      // VERB
    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str
    jsr combat_append_monster_name
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
    jmp cmb_term_and_print
```

~25 bytes. Replaces 4 × ~25 = 100 bytes with 25 + 4 × 5 = 45 bytes.

- **Net savings: ~55 bytes**

### OPT-4.11 — Huff-Decode-and-Print Helper (~30-40 bytes saved)

The two-line pattern:
```asm
    ldx #HSTR_xxx
    jsr huff_decode_string
    jsr msg_print
```
appears **10 times** across 10 files (turn.s, spell_effects.s, throw.s, bash.s, player_items.s, player_move.s, ranged_fire.s, monster_attack.s, dungeon_features.s, player_magic.s). Each instance is 8 bytes (2 + 3 + 3).

**Fix:** Create `huff_print_msg`:
```asm
// Input: X = Huffman string ID
huff_print_msg:
    jsr huff_decode_string
    jmp msg_print          // 6 bytes
```

Each call site becomes 5 bytes (`ldx #ID; jsr huff_print_msg`) instead of 8 bytes.

- 10 × 8 = 80 bytes → 6 + 10 × 5 = 56 bytes
- **Net savings: ~24 bytes** (trivial to implement)

### Priority and Implementation Order

| Priority | Item | Effort | Est. Savings | Files Affected |
|----------|------|--------|-------------|----------------|
| 1 | OPT-4.11 Huff-print helper | Trivial | ~24 | 10 files |
| 2 | OPT-4.9 Kill/wake message helpers | Low | ~68 | combat.s, ranged_fire.s, throw.s, spell_effects.s |
| 3 | OPT-4.10 Projectile msg dedup | Low | ~55 | ranged_fire.s, throw.s |
| 4 | OPT-4.5 Unify tohit calc | Medium | ~80 | combat.s, throw.s |
| 5 | OPT-4.1+4.2 Shared trace + direction | Medium | ~150-180 | ranged_fire.s, throw.s, spell_effects.s |
| 6 | OPT-4.3 Adjacent-tile iterator | Medium | ~90-120 | spell_effects.s |
| 7 | OPT-4.4 Shared 16-bit HP damage | Low | ~40 | spell_effects.s, combat.s |
| 8 | OPT-4.6 Table-driven effect ticks | Medium | ~26 | turn.s |
| 9 | OPT-4.7 Huffman item names | High | ~300-400 | item.s, huffman_data.s, tools/ |
| 10 | OPT-4.8 Remaining raw strings | Low | ~30 | turn.s |

### Summary

| Category | Items | Total Savings |
|----------|-------|--------------|
| Code deduplication (OPT-4.1–4.6, 4.9–4.11) | 8 items | ~550-650 bytes |
| String compression (OPT-4.7–4.8) | 2 items | ~330-430 bytes |
| **Total** | **10 items** | **~880-1,080 bytes** |

Combined with OPT-3 (town overlay, ~500-700 bytes saved there), the project can reclaim substantial headroom in both the main segment and the overlay without losing any features. The code deduplication items (OPT-4.1–4.6, 4.9–4.11) are recommended first since they also improve maintainability. OPT-4.7 (Huffman item names) is the single largest main-segment win but requires tooling changes.

