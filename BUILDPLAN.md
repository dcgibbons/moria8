# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-02-18)

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
| 10 | C128 Enhancements | Not started |

### Build Stats

- **Test suites:** 22 (300 runtime tests)
- **Compile-time asserts:** 68
- **Source files:** ~46 .s files
- **Program size:** $BFFF (program_end) — **1 byte headroom** to MAP_BASE ($C000)
- **Banked code:** $F000-$FFBC (62 bytes headroom to CPU vectors)
- **Banked payload:** $C01D-$CFE8 (24 bytes headroom to I/O at $D000)
- **Town overlay:** 2,891 of 4,096 bytes (1,204 free)

### Known Remaining Issues

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| BUG-32 | MED | Monster names/descriptions garbled for tier-loaded creatures from REU (death screen "KILLED BY A [garbage]", combat "HIT THE [garbage]") — repeat of BUG-30 pattern, not fully resolved | **Fixed** — Root cause: `load_tier_to_buffer` writes `$E0xx` pointers into `cr_name_lo/hi`, but `overlay_load` later sets `current_tier=0` and overwrites `$E000` with overlay code. The `!cgn_table` fallback in `creature_get_name` saw `cr_name_hi >= $E0`, went to `!cgn_banked`, and read executable code as string data. Fix: replaced `!cgn_banked` with safe fallback returning "?" to `creature_name_buf`. The `!cgn_banked` path was dead code for legitimate use — embedded names are always < `$C000`, and tier names use the dedicated tier path. Byte-neutral (15B → 15B). |
| BUG-33 | LOW | Secret door wall sometimes wrong orientation (renders as `+` on horizontal wall instead of `—`) — recurring | Open |
| BUG-34 | MED | Monster recall only shows first match when multiple creatures share a display symbol. umoria cycles through all known creatures with that letter (backward iteration, ESCAPE to advance); moria8 finds the first match and stops. On C64 this is worse than umoria because case-folding (no lowercase) merges symbols that are distinct in umoria (e.g. `j`=Jackal vs `J`=Jellies both become screen code $0A). Fix: add a recall cycling loop similar to umoria's `recallMonsterAttributes()`. | Open |
| R11 | MED | **Switch to lowercase/uppercase character mode.** Currently using uppercase/graphics mode solely for 6 box-drawing wall characters (─ │ ┌ ┐ └ ┘). Switching to lowercase mode gives 52 letter symbols (a-z + A-Z) instead of 26, fixing the root cause of BUG-34's symbol collisions and enabling mixed-case text throughout the game. Walls change from box-drawing to ASCII (`#` or `-`/`|`/`+`), which is genre-authentic (original VMS Moria used `#`-walls on standard terminals). Zero RAM cost. Changes: flip bit 1 of `$D018` init, remap 6 entries in `tile_char_table` (color.s), change `.text` encoding from `screencode_upper` to `screencode_mixed`, update creature `cr_display` values to use both cases, update recall key input to accept both cases. | Open |
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |

### What's Next

| Priority | # | What | Effort |
|----------|---|------|--------|
| 1 | A4 | Separate binaries (BOOT.PRG + MORIA64 + MORIA128) | Major (Phase 10) |

**Phase 10 — C128 Enhancements** (not started):

| # | What | Summary |
|---|------|---------|
| 10.1 | 80-column VDC mode | Second rendering backend for VDC 80x25 display |
| 10.2 | Extended memory | C128 128KB MMU bank-switch path (no disk tier loading) |
| 10.3 | Larger dungeon | Expand map to 120x80+, more rooms, up to 64 active monsters |
| 10.4 | Enhanced display | VDC color attributes for threat-coded monsters |

---

### Priority Triage (updated 2026-02-18)

**Remaining items:**

**Low priority (polish/completeness):**
- A4 Separate binaries — Phase 10 scope (BOOT.PRG + MORIA64 + MORIA128)
- A6 Large file split — opportunistic refactoring (dungeon_gen.s, item.s)
- A7 Item generation distribution review vs umoria curves

---

---

## Codebase-Wide Size Optimization — OPT-4 (2026-02-18)

### Current State

Main segment: **$080E–$B4CF** (44,225 bytes, ~2,833 bytes before $C000 MAP_BASE).
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

