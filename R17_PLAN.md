# R1.7 Bash Command — Design Plan

## Reference

- **umoria source:** `~/Projects/thirdparty/umoria/src/player_bash.cpp`
- **umoria bash behavior:** Direction prompt, then: bash monster (melee attack + stun chance), bash closed door (chance to break open), bash chest (chance to unlock/destroy). Off-balance penalty (paralysis 1-2 turns) on miss/fail.

---

## 1. Architecture Overview

### New file: `bash.s`

Contains all bash logic. Follows the pattern established by `throw.s`: scratch variables at top, main entry point `bash_command`, helper subroutines below. Approximately 400-500 bytes of code.

### Changes to existing files

| File | Change |
|------|--------|
| `input.s` | Add `CMD_BASH = $31`, add SHIFT+B ($c2 is currently mapped to CMD_RUN_SW!) — **conflict resolution needed**, see Section 5 |
| `main.s` | Add CMD_BASH dispatch block after CMD_REFUEL (pattern: msg_clear, jsr bash_command, bcc no_turn, jsr turn_post_action, death check, jmp vp_render_status_loop) |
| `monster_ai.s` | Already handles MX_STUN — no changes needed (stun decrement is already at lines 124-130) |
| `ui_help_data.s` | Add "SHIFT+B BASH" to help screen (see Section 6) |
| `huffman_data.s` | Add 7 new Huffman string constants (HSTR_BASH_*) and encoded strings |
| `main.s` (import) | Add `#import "bash.s"` near other combat-related imports |

### No changes needed

- `monster.s` — MX_STUN field already exists at offset 8, MONSTER_ENTRY_SIZE is already 12. No struct change needed.
- `monster_ai.s` — Stun check is already implemented (lines 124-130: decrements MX_STUN, skips turn if > 0).
- `item_defs.s` — No ICAT_CHEST exists. Skip chest bash entirely.
- `combat.s` — Reuse `combat_apply_damage`, `combat_award_xp`, `combat_check_levelup`, `msg_build_action`, `cmb_print_buf`, `combat_roll_tohit`, `combat_append_str`, `combat_append_monster_name`, `combat_append_decimal`.

---

## 2. Simplified Bash Formulas for 8-bit

### 2a. Door Bash

**umoria formula:**
```
chance = STR + weight/2
abs_misc_use = abs(door.misc_use)  // lock/stuck difficulty
if rng(chance * (20 + abs_misc_use)) < 10 * (chance - abs_misc_use):
    door opens
```

**Problem:** `chance * (20 + diff)` can reach `118 * 275 = 32,450` — needs 16-bit multiply and 16-bit random.

**Simplified 8-bit formula:**
```
// Doors in moria8 have no lock/stuck difficulty value stored, so diff=0.
// Simplify: rng(chance * 20) < 10 * chance
// Which reduces to: rng(20) < 10, i.e., 50% base chance.
// Scale by STR: rng(STR + 10) >= 5
// This gives ~50% at STR 3, ~67% at STR 10, ~82% at STR 18.

roll = rng_range(STR + 10)  // [0, STR+9]
if roll >= 5:
    door opens (convert to TILE_DOOR_OPEN, broken 50% of time)
else:
    "THE DOOR HOLDS FIRM."
```

**Pseudocode:**
```asm
bash_door:
    ; Print "YOU SMASH INTO THE DOOR!"
    lda zp_player_str
    clc
    adc #10
    jsr rng_range           ; [0, STR+9]
    cmp #5
    bcs !bash_success+
    ; Failed — off-balance check
    jsr bash_off_balance
    ; "THE DOOR HOLDS FIRM."
    rts
!bash_success:
    ; "THE DOOR CRASHES OPEN!"
    ; Convert tile to TILE_DOOR_OPEN
    ; 50% chance door is broken (cosmetic in moria8)
    ; Move player into doorway if not confused
    rts
```

### 2b. Monster Bash — To-Hit

**umoria formula:**
```
base_to_hit = STR + shield_weight/2 + body_weight/10
if not visible: halve base_to_hit, subtract DEX*(BTH_adjust-1), subtract level*class_bth/2
test_being_hit(base_to_hit, level, DEX, creature_AC, BTH)
```

**Simplified 8-bit formula:**
```
// Shield weight: item 9 (Small Shield) has it_weight=50.
// body_weight (PL_WEIGHT) is aesthetic (60-250), /10 = 6-25.
// Simplify: use STR + shield_weight/2 as base.
// PL_WEIGHT/10 is small relative to STR, include it as a constant +5.
// This avoids 16-bit division of body weight.

base_to_hit = STR
if EQUIP_SHIELD has an item:
    base_to_hit += it_weight[shield_type] / 2   // 50/2 = 25 for small shield
base_to_hit += 5  // approximate body weight contribution

// Use existing combat_roll_tohit which rolls rng(tohit) >= AC
// Store base_to_hit in zp_combat_tohit, monster AC in zp_combat_atk
```

**Pseudocode:**
```asm
bash_calc_tohit:
    lda zp_player_str
    sta zp_combat_tohit
    ; Add shield weight / 2
    ldx #EQUIP_SHIELD
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !no_shield+
    tax
    lda it_weight,x
    lsr                     ; /2
    clc
    adc zp_combat_tohit
    bcc !no_overflow+
    lda #255
!no_overflow:
    sta zp_combat_tohit
!no_shield:
    ; Add body weight approximation (+5)
    lda zp_combat_tohit
    clc
    adc #5
    bcc !ok+
    lda #255
!ok:
    sta zp_combat_tohit
    rts
```

### 2c. Monster Bash — Damage

**umoria formula:**
```
damage = dice_roll(shield.damage)
damage = critical_blow(shield_weight/4 + STR, 0, damage)
damage += body_weight/60 + 3
```

**Simplified 8-bit formula:**
```
// Shield dice: Small Shield has no damage dice in moria8 item table
// (it_dmg_dice[9] = 0, it_dmg_sides[9] = 0).
// Use fixed 1d4 base damage for bash (reasonable for shield slam).
// Skip critical blow (bash crits are rare and complex).
// Add STR damage bonus + flat 3.

damage = rng_range(4) + 1          // 1d4
damage += str_damage_bonus[STR-3]  // from tables.s
damage += 3                        // flat bonus (body weight approx)
clamp damage to [0, 255]
```

### 2d. Monster Bash — Stun Check

**umoria formula:**
```
if (creature.defenses & CD_MAX_HP):
    avg_max_hp = max_dice_roll(creature.hit_die)
else:
    avg_max_hp = dice * (sides + 1) / 2

if 100 + rng(400) + rng(400) > monster.hp + avg_max_hp:
    monster.stunned += rng(3) + 1   // 2-4 turns
    cap at 24
```

**Problem:** `100 + rng(400) + rng(400)` ranges 100-900, and `monster.hp + avg_max_hp` can be up to ~500 for early creatures. All values exceed 8-bit range.

**Simplified 8-bit formula:**
```
// Scale everything down by 4 to fit 8-bit:
// bash_power = 25 + rng(100) + rng(100)   // range 25-225
// mon_tough = (monster_hp / 4) + (avg_max_hp / 4)
// avg_max_hp = dice * (sides + 1) / 2
// avg_max_hp/4 = dice * (sides + 1) / 8
//
// For early monsters (e.g., 3d6 = avg 10.5):
//   avg/4 = ~3, typical HP/4 = ~3, total = ~6
//   bash_power avg = ~125, so stun is very likely (good — matches umoria)
//
// CD_MAX_HP flag doesn't exist in moria8. All monsters use average.

bash_power = 25 + rng_range(100) + rng_range(100)
// This needs a carry-safe add (result can be 225, fits in 8 bits)

mon_hp_quarter:
    ; 16-bit HP / 4
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    sta hi
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    lsr hi
    ror A
    lsr hi
    ror A
    ; If hi is still non-zero, monster is massive — no stun possible
    ; (this handles 16-bit HP monsters gracefully)

avg_max_quarter:
    ; cr_hd_num[type] * (cr_hd_sides[type] + 1) / 8
    ldx cmb_type
    lda cr_hd_num,x
    ldx cr_hd_sides,x
    inx                     ; sides + 1
    jsr math_multiply       ; zp_math_a = lo
    lda zp_math_a
    lsr
    lsr
    lsr                     ; /8

mon_tough = mon_hp_quarter + avg_max_quarter
if bash_power > mon_tough:
    stun = rng_range(3) + 2   // 2-4 turns
    cap MX_STUN at 24
    print "<NAME> APPEARS STUNNED!"
else:
    print "<NAME> IGNORES YOUR BASH!"
```

### 2e. Off-Balance Check

**umoria formula:**
```
if rng(150) > DEX:
    paralysis = 1 + rng(2)   // 1-2 turns
    print "YOU ARE OFF BALANCE."
```

**Simplified (identical — fits 8-bit):**
```asm
bash_off_balance:
    lda #150
    jsr rng_range           ; [0, 149]
    cmp zp_player_dex       ; DEX (3-18 in early game)
    bcc !no_penalty+        ; rng < DEX → safe
    beq !no_penalty+
    ; Off balance
    lda #2
    jsr rng_range           ; [0, 1]
    clc
    adc #1                  ; [1, 2]
    sta zp_eff_paralyze
    ; Print "YOU ARE OFF BALANCE."
!no_penalty:
    rts
```

---

## 3. Data Structure Changes

### Monster entry: NO CHANGE

MX_STUN already exists at offset 8 in the 12-byte monster entry. The `monster_ai.s` code at lines 124-130 already decrements it and skips the monster's turn when stunned. No struct changes, no memory impact.

### No chest support

`ICAT_CHEST` does not exist in `item.s`. The 16 item categories are fully allocated (0-15). Chest bash is skipped entirely. This matches the current game state — chests would need an entire item subsystem to support.

### No door difficulty value

Doors in moria8 are simple tile types (TILE_DOOR_CLOSED / TILE_DOOR_OPEN) with no per-door lock/stuck metadata. The simplified bash formula ignores difficulty (equivalent to difficulty=0 in umoria).

### New constants in `bash.s`

```asm
// No new struct constants needed — all existing
```

---

## 4. New Huffman Strings

**Current highest HSTR ID:** `HSTR_CMB_LVLUP = 159`

**New string IDs (starting at 160):**

| ID | Constant | Text | Usage |
|----|----------|------|-------|
| 160 | `HSTR_BASH_SMASH_DOOR` | `"YOU SMASH INTO THE DOOR!"` | Door bash attempt |
| 161 | `HSTR_BASH_DOOR_OPEN` | `"THE DOOR CRASHES OPEN!"` | Door bash success |
| 162 | `HSTR_BASH_DOOR_HOLDS` | `"THE DOOR HOLDS FIRM."` | Door bash failure |
| 163 | `HSTR_BASH_OFF_BALANCE` | `"YOU ARE OFF BALANCE."` | Failed DEX check |
| 164 | `HSTR_BASH_AFRAID` | `"YOU ARE AFRAID!"` | Fear blocks bash |
| 165 | `HSTR_BASH_STUNNED` | `" APPEARS STUNNED!"` | Monster stunned (appended to combat_msg_buf after name) |
| 166 | `HSTR_BASH_IGNORES` | `" IGNORES YOUR BASH!"` | Monster resists stun (appended after name) |

**Implementation in `huffman_data.s`:**
- Add 7 `.const HSTR_BASH_*` definitions after HSTR_CMB_LVLUP
- Add 7 encoded string entries to `hd_strings` table
- Update `hd_string_count` (or equivalent table size)

**Estimated Huffman data cost:** ~70 bytes (7 strings averaging 10 bytes encoded each)

---

## 5. Command Dispatch Integration

### Key Binding Conflict: SHIFT+B

In C64 unshifted mode, SHIFT+B produces PETSCII `$C2`. This is **currently mapped** to `CMD_RUN_SW` (run southwest) in `input.s` line 214.

**Resolution options:**

1. **Use a different key for Bash.** In umoria, bash is lowercase 'b'. But lowercase 'b' (`$42`) is already mapped to `CMD_MOVE_SW` (move southwest). The C64 in unshifted mode cannot distinguish case for letters.

2. **Reassign SHIFT+B from run-SW to bash.** Running southwest would then only work via shifted cursor keys (if supported) or by using the 'B' vi-key with the run prefix. **However**, shifted vi-keys are the ONLY way to run diagonally, so removing SHIFT+B for running would eliminate the ability to run southwest entirely.

3. **Use CTRL+B or a different modifier.** C64 CTRL+B produces PETSCII $02 (currently unmapped). This is viable but unconventional.

4. **Use a completely different letter.** For example, SHIFT+D ($C4) — but D is DROP and SHIFT+D is unused. Or use '#' ($23) which is unused.

**Recommended: Option 4 — Map Bash to SHIFT+D ($C4).**
- 'D' for "Door-bash" / "Dash" is reasonably mnemonic
- SHIFT+D is currently unmapped
- Preserves all diagonal running
- Help screen shows "SHIFT+D BASH"

**Alternative: If the user prefers SHIFT+B, option 2 is acceptable** since running SW can be done via open+close direction sequences, but the loss is real.

### Changes to `input.s`

```asm
// Add new command constant:
.const CMD_BASH = $31      // Bash (SHIFT+D)

// Add to key_map_petscii (after SHIFT+R entry at line 206):
    .byte $c4              // SHIFT+D — bash

// Add to key_map_cmd (matching position):
    .byte CMD_BASH
```

### Changes to `main.s`

Add dispatch block after the CMD_REFUEL section (around line 1013), following the exact pattern used by CMD_THROW and CMD_FIRE:

```asm
    // Bash?
    cmp #CMD_BASH
    bne !not_bash+
    jsr msg_clear
    jsr bash_command
    bcc !bash_no_turn+
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jmp vp_render_status_loop
!bash_no_turn:
    jmp !main_loop-
!not_bash:
```

---

## 6. Help Screen Changes

### Current layout analysis

The help screen has 23 content rows (rows 1-23). Row 23 currently shows only SHIFT+Q QUIT in the right column, with 18 spaces of padding on the left. The left column on row 22 has "F STUDY BOOK".

**Option A: Add BASH to row 23 left column** (currently blank padding).

Change `help_l23` in `ui_help_data.s` from:
```
help_l23:
    .text "                  "
    .byte $fe
    .text "SHIFT+Q"
    .byte $ff
    .text " QUIT"
    .byte 0
```

To:
```
help_l23:
    .byte $fe
    .text "SHIFT+D"
    .byte $ff
    .text " BASH       "
    .byte $fe
    .text "SHIFT+Q"
    .byte $ff
    .text " QUIT"
    .byte 0
```

This uses the same format as other rows (e.g., row 15's SHIFT+R REFUEL). The left column takes 18 characters: "SHIFT+D BASH" = 12 chars + 6 padding = 18.

**Option B: Add to COMBAT section.** Move BASH between FIRE and THROW (rows 12-13). This would require shifting all subsequent lines down by one, which won't fit (already using all 23 lines).

**Recommended: Option A.** Row 23's left column is blank and BASH fits naturally as a combat-adjacent command.

---

## 7. Monster AI Stun Integration

### Already implemented

The stun check in `monster_ai.s` (lines 124-130) already handles MX_STUN correctly:

```asm
    // Check stun timer
    ldy #MX_STUN
    lda (zp_ptr0),y
    beq !mpo_not_stunned+
    sec
    sbc #1
    sta (zp_ptr0),y
    jmp !mpo_writeback+         // Stunned — skip entire turn
!mpo_not_stunned:
```

This decrements MX_STUN by 1 each turn and skips the monster's action when stunned. Bash just needs to SET MX_STUN (2-4 turns, capped at 24) — the AI handles the rest.

### Stun cap of 24

umoria caps stun at 24 turns. With bash adding 2-4 per successful stun, and decrementing 1 per monster turn, this prevents permanently stunlocking a monster with repeated bashes.

---

## 8. Test Strategy

### Test file: `test_bash.s`

Tests should use the `.assert` compile-time pattern where possible, with VICE headless runtime tests for RNG-dependent behavior.

**Compile-time asserts:**
1. `CMD_BASH` constant value = $31
2. Key map tables remain same size (assert already exists at line 276)
3. HSTR_BASH_* IDs are sequential from 160

**Runtime tests (VICE headless):**

| Test | Description | Method |
|------|-------------|--------|
| `test_bash_door_success` | Bash opens a closed door | Set up TILE_DOOR_CLOSED adjacent to player, set STR=18 (high chance), call bash_door, verify tile changed to TILE_DOOR_OPEN |
| `test_bash_door_fail` | Bash fails to open door | Set STR=3 (low chance), run many iterations, verify door stays closed at least sometimes |
| `test_bash_monster_hit` | Bash hits and damages monster | Place monster adjacent, set high STR, call bash_attack, verify monster HP decreased |
| `test_bash_monster_stun` | Bash stuns a weak monster | Place low-HP monster, bash it, verify MX_STUN > 0 |
| `test_bash_monster_kill` | Bash kills monster | Place 1-HP monster, bash with high damage, verify monster removed |
| `test_bash_off_balance` | Off-balance sets paralysis | Mock rng to return high value, call bash_off_balance with low DEX, verify zp_eff_paralyze > 0 |
| `test_bash_afraid` | Fear blocks bash | Set eff_fear_timer > 0, call bash_command, verify carry clear (no turn consumed) |
| `test_bash_empty_space` | Bashing empty space | No monster or door in direction, verify message "YOU BASH AT EMPTY SPACE." and turn consumed |
| `test_bash_tohit_with_shield` | Shield weight affects to-hit | Equip shield, verify zp_combat_tohit includes shield weight/2 |

**Test bootstrap:** If assembled code crosses $A000, use the trampoline pattern from `test_item.s` (per CLAUDE.md).

---

## 9. Code Size Estimate and Headroom Check

### Current memory usage

```
Program segment: $080E - $C224 = 47,638 bytes
Available before MAP_BASE ($C000): already exceeded! Program extends to $C224.
```

Wait — the program extends to $C224, which is PAST $C000 (MAP_BASE). This means the map data at $C000 is overlapping with program code, which is expected: the map is allocated AT $C000 and the program includes it. Looking at `memory.s`, MAP_BASE = $C000 is the map's address but it's part of the program segment. The real limit is $CFFF (end of floor items) for main RAM data, with $D000+ being I/O registers.

**Actual headroom:** The program segment ends at $C224. The map tiles end at $CEFF and floor items at $CFFF. Since the map and floor items are included within the program segment's assembled output, the assembler manages this. The true ceiling for code is the last address before the I/O window at $D000, minus the space reserved for map ($C000-$CEFF) and floor items ($CF00-$CFFF).

Looking at it differently: the Program segment $080E-$C224 includes everything. If code grows, it pushes data later. As long as everything stays below $D000 (I/O), we're fine. Current end is $C224, giving **$D000 - $C225 = 3,547 bytes** of remaining space before I/O.

### Bash code size estimate

| Component | Estimated bytes |
|-----------|----------------|
| `bash.s` — main entry + door bash + monster bash + stun + off-balance + helpers | 400 |
| Scratch variables (8-10 bytes) | 10 |
| Huffman string data (7 strings) | 70 |
| `main.s` dispatch block | 30 |
| `input.s` key map entries (2 bytes) | 2 |
| `ui_help_data.s` changes | 20 |
| **Total** | **~532 bytes** |

### Headroom verdict

With ~3,547 bytes free before $D000 and an estimated 532 bytes for bash, there is **ample headroom** (using ~15% of remaining space). This leaves ~3,000 bytes for future features.

---

## Appendix A: Complete `bash.s` Pseudocode

```
bash_command:
    // Fear check (same as player_move.s)
    if eff_fear_timer > 0:
        print HSTR_BASH_AFRAID
        clc / rts                   // No turn consumed

    // Direction prompt (reuse get_direction_target)
    jsr get_direction_target
    if carry clear: clc / rts       // Cancelled

    // Confusion randomizes direction (same as umoria)
    if zp_eff_confuse > 0:
        randomize direction (rng_range(8) for dir, recompute target)

    // Check what's at the target tile
    // 1. Monster?
    lda df_target_x / ldy df_target_y
    jsr monster_find_at
    if carry set: jmp bash_monster

    // 2. Closed door?
    read map tile at (df_target_x, df_target_y)
    if tile_type == TILE_DOOR_CLOSED: jmp bash_door

    // 3. Wall or secret door?
    if tile_type >= MIN_CAVE_WALL:
        print "YOU BASH IT, BUT NOTHING INTERESTING HAPPENS."
        sec / rts

    // 4. Empty space
    print "YOU BASH AT EMPTY SPACE."
    sec / rts                       // Turn consumed (matches umoria)


bash_monster:
    // Wake the monster
    set MF_AWAKE in MX_FLAGS

    // Calculate to-hit (STR + shield_weight/2 + 5)
    jsr bash_calc_tohit

    // Load monster AC
    ldx cmb_type
    lda cr_ac,x
    sta zp_combat_atk

    // Roll to hit (reuse combat_roll_tohit)
    jsr combat_roll_tohit
    if miss: goto bash_miss_monster

    // Hit! Roll damage: 1d4 + str_damage_bonus + 3
    lda #1 / ldx #4 / ldy #0
    jsr math_dice
    add str_damage_bonus[STR-3]
    add 3
    clamp to [0, 255]
    sta cmb_damage

    // Apply damage (reuse combat_apply_damage)
    jsr combat_apply_damage
    if dead: goto bash_killed

    // Stun check
    jsr bash_stun_check

    // Print "YOU HIT THE <name>."
    // (followed by stun message from bash_stun_check)
    jsr bash_off_balance
    sec / rts

bash_killed:
    // Print "YOU HAVE SLAIN THE <name>."
    jsr combat_award_xp
    jsr combat_check_levelup
    jsr bash_off_balance
    sec / rts

bash_miss_monster:
    // Print "YOU MISS THE <name>."
    jsr bash_off_balance
    sec / rts


bash_door:
    // Print HSTR_BASH_SMASH_DOOR
    // Roll: rng_range(STR + 10) >= 5?
    if success:
        // Print HSTR_BASH_DOOR_OPEN
        // Convert tile to TILE_DOOR_OPEN
        // Move player into doorway if not confused
        sec / rts
    else:
        // Print HSTR_BASH_DOOR_HOLDS
        jsr bash_off_balance
        sec / rts


bash_stun_check:
    // bash_power = 25 + rng_range(100) + rng_range(100)
    // mon_hp_q = monster_hp / 4 (16-bit shift)
    // avg_max_q = cr_hd_num * (cr_hd_sides + 1) / 8
    // mon_tough = mon_hp_q + avg_max_q (clamp at 255)
    // if bash_power > mon_tough:
    //     MX_STUN += rng_range(3) + 2, cap at 24
    //     print "<NAME> APPEARS STUNNED!"
    // else:
    //     print "<NAME> IGNORES YOUR BASH!"


bash_off_balance:
    // rng_range(150)
    // if result > DEX:
    //     zp_eff_paralyze = 1 + rng_range(2)
    //     print HSTR_BASH_OFF_BALANCE
```

---

## Appendix B: Key Binding Decision Matrix

| Key | PETSCII | Current Use | Bash Candidate? |
|-----|---------|-------------|-----------------|
| SHIFT+B | $C2 | CMD_RUN_SW | Conflict: loses diagonal run |
| SHIFT+D | $C4 | unmapped | Best option: no conflict |
| CTRL+B | $02 | unmapped | Viable but unconventional |
| # | $23 | unmapped | Not mnemonic |

**Final recommendation: SHIFT+D** unless user explicitly prefers SHIFT+B and accepts losing the run-southwest shortcut.

---

## Appendix C: Reusable Subroutines from Existing Code

| Subroutine | Source | Used for |
|------------|--------|----------|
| `get_direction_target` | `dungeon_features.s` | Direction prompt + target tile calculation |
| `monster_find_at` | `monster.s` | Check for monster at bash target |
| `monster_get_ptr` | `monster.s` | Get monster entry pointer |
| `combat_roll_tohit` | `combat.s` | To-hit roll (d20 + chance vs AC) |
| `combat_apply_damage` | `combat.s` | Subtract damage from monster HP |
| `combat_award_xp` | `combat.s` | XP award on kill |
| `combat_check_levelup` | `combat.s` | Level-up check after XP gain |
| `msg_build_action` | `combat.s` | Build "YOU <verb> THE <name>." messages |
| `cmb_print_buf` | `combat.s` | Print combat message buffer |
| `combat_append_str` | `combat.s` | Append string to message buffer |
| `combat_append_monster_name` | `combat.s` | Append monster name to buffer |
| `huff_decode_string` | `huffman.s` | Decode Huffman-compressed strings |
| `huff_append_combat` | `huffman.s` | Decode and append to combat buffer |
| `math_dice` | `math.s` | Roll NdS+bonus |
| `math_multiply` | `math.s` | 8x8 multiply |
| `rng_range` | `rng.s` | Random number in [0, N-1] |
| `monster_remove` | `monster.s` | Remove dead monster from table |
| `eff_kill_monster` | `effects.s` | Kill monster (remove + clear occupied) |
