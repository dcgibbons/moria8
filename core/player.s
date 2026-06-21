#importonce
// player.s — Player data structure and accessors
//
// The player struct is stored in a contiguous block in main RAM.
// Hot fields are mirrored in ZP (zeropage.s) for fast access.
// This module provides the full struct and sync routines between
// ZP and the main struct.

#import "player_state.s"
#import "platform_services_api.s"
#import "player_search.s"
//
// Total struct size: ~128 bytes

// Character sheet strings (main RAM — referenced by $F000 banked code)
char_sex_label:
    .text "Sex: " ; .byte 0
char_sex_male:
    .text "Male" ; .byte 0
char_sex_female:
    .text "Female" ; .byte 0
char_sc_label:
    .text "  SC: " ; .byte 0

// ============================================================
// Subroutines
// ============================================================

// player_init — Zero out player struct
// Preserves: nothing
player_init:
    lda #0
    ldx #PL_STRUCT_SIZE - 1
!loop:
    sta player_data,x
    dex
    bpl !loop-
    lda #99
    ldx #31
!spell_order_loop:
    sta player_data + PL_SPELL_ORDER,x
    dex
    bpl !spell_order_loop-
    // Clear player_background (160 bytes = 2 x 80)
    lda #0
    ldx #79
!bg_loop:
    sta player_background,x
    sta player_background + 80,x
    dex
    bpl !bg_loop-
    rts

// player_sync_to_zp — Copy hot fields from struct to ZP
// Called after loading a save or modifying the struct directly.
// Preserves: nothing
player_sync_to_zp:
    lda player_data + PL_MAP_X
    sta zp_player_x
    lda player_data + PL_MAP_Y
    sta zp_player_y
    lda player_data + PL_HP_LO
    sta zp_player_hp_lo
    lda player_data + PL_HP_HI
    sta zp_player_hp_hi
    lda player_data + PL_MHP_LO
    sta zp_player_mhp_lo
    lda player_data + PL_MHP_HI
    sta zp_player_mhp_hi
    lda player_data + PL_MANA
    sta zp_player_mp
    lda player_data + PL_MAX_MANA
    sta zp_player_mmp
    lda player_data + PL_LEVEL
    sta zp_player_lvl
    lda player_data + PL_DLEVEL
    sta zp_player_dlvl
    lda player_data + PL_AC
    sta zp_player_ac
    lda player_data + PL_STR_CUR
    sta zp_player_str
    lda player_data + PL_INT_CUR
    sta zp_player_int
    lda player_data + PL_WIS_CUR
    sta zp_player_wis
    lda player_data + PL_DEX_CUR
    sta zp_player_dex
    lda player_data + PL_CON_CUR
    sta zp_player_con
    lda player_data + PL_CHR_CUR
    sta zp_player_chr
    lda player_data + PL_RACE
    sta zp_player_race
    lda player_data + PL_CLASS
    sta zp_player_class
    lda player_data + PL_FOOD_LO
    sta zp_player_food
    lda player_data + PL_FOOD_HI
    sta zp_player_food_hi
    lda player_data + PL_LIGHT_RAD
    sta zp_light_radius
    lda player_data + PL_RESERVED
    sta zp_pseudo_id_timer
    rts

// player_sync_from_zp — Copy ZP hot fields back to struct
// Called before saving.
// Note: intentionally does NOT sync STR/INT/WIS/DEX/CON/CHR (recalculated
// by player_calc_stats) or race/class (immutable after creation).
// light_radius IS synced because it's mutable (torch/lamp/spell).
// Preserves: nothing
player_sync_from_zp:
    lda zp_player_x
    sta player_data + PL_MAP_X
    lda zp_player_y
    sta player_data + PL_MAP_Y
    lda zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda zp_player_mhp_lo
    sta player_data + PL_MHP_LO
    lda zp_player_mhp_hi
    sta player_data + PL_MHP_HI
    lda zp_player_mp
    sta player_data + PL_MANA
    lda zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda zp_player_lvl
    sta player_data + PL_LEVEL
    lda zp_player_dlvl
    sta player_data + PL_DLEVEL
    lda zp_player_ac
    sta player_data + PL_AC
    lda zp_player_food
    sta player_data + PL_FOOD_LO
    lda zp_player_food_hi
    sta player_data + PL_FOOD_HI
    lda zp_light_radius
    sta player_data + PL_LIGHT_RAD
    rts

// player_calc_stats — Recalculate current stats from base + modifiers
// Uses umoria's incrementStat/decrementStat for race and class modifiers.
// Stats use single-byte encoding: 3-18 literal, 19-118 = 18/01 to 18/100.
// Preserves: nothing
player_calc_stats:
    // Precompute race*6 into zp_temp0 (safe across math_dice)
    lda player_data + PL_RACE
    asl
    sta zp_temp0
    asl
    clc
    adc zp_temp0
    sta zp_temp0            // zp_temp0 = race * 6

    // Precompute class*6 into zp_temp2 (safe across math_dice)
    lda player_data + PL_CLASS
    asl
    sta zp_temp2
    asl
    clc
    adc zp_temp2
    sta zp_temp2            // zp_temp2 = class * 6

    ldy #0                  // Stat index
!stat_loop:
    sty zp_temp1            // Save stat index (safe across math_dice)

    // Start with base stat
    lda player_data + PL_STR_BASE,y
    sta stat_work

    // Apply race modifier via increment/decrement
    lda zp_temp0            // race*6
    clc
    adc zp_temp1            // + stat_index
    tax
    lda race_stat_adj,x
    jsr apply_modifier

    // Apply class modifier via increment/decrement
    lda zp_temp2            // class*6
    clc
    adc zp_temp1            // + stat_index
    tax
    lda class_stat_adj,x
    jsr apply_modifier

    // Store result
    ldy zp_temp1
    lda stat_work
    sta player_data + PL_STR_CUR,y

    iny
    cpy #STAT_COUNT
    bne !stat_loop-

    // Ring of Strength uses p1 as a signed STR modifier.
    ldx #EQUIP_RING
    lda inv_item_id,x
    cmp #24
    bne !pcs_no_str_ring+
    lda player_data + PL_STR_CUR
    sta stat_work
    lda inv_p1,x
    jsr apply_modifier
    lda stat_work
    sta player_data + PL_STR_CUR
!pcs_no_str_ring:

    // Update combat bonuses from stats
    jsr player_calc_combat
    rts

// Working byte for stat modification (survives across increment/decrement calls)
stat_work: .byte 0

// apply_modifier — Apply a signed modifier to stat_work using increment/decrement
// Each +1 or -1 is applied individually via incrementStat/decrementStat (umoria).
// Input: A = signed modifier (-128 to +127)
//        stat_work = current stat value
// Output: stat_work = modified stat
// Clobbers: X, zp_temp3, zp_temp4, zp_math*
// Note: Uses am_count instead of X for loop counter because
//       increment_stat/decrement_stat clobber X via math_dice.
apply_modifier:
    cmp #0
    beq !done+
    bpl !positive+
    // Negative modifier: negate to get count
    eor #$ff
    clc
    adc #1
    sta am_count
!dec_loop:
    lda stat_work
    jsr decrement_stat
    sta stat_work
    dec am_count
    bne !dec_loop-
    rts
!positive:
    sta am_count
!inc_loop:
    lda stat_work
    jsr increment_stat
    sta stat_work
    dec am_count
    bne !inc_loop-
!done:
    rts

am_count: .byte 0  // Loop counter for apply_modifier (safe from X clobber)

// increment_stat — Increment a stat using umoria's randomized step logic
// Input: A = current stat value (3-118)
// Output: A = new stat value
// Clobbers: zp_temp3, zp_temp4, zp_math* (via math_dice)
increment_stat:
    cmp #18
    bcs !above_17+
    // stat < 18: simple +1
    clc
    adc #1
    rts
!above_17:
    cmp #88
    bcs !above_87+
    // stat 18-87: add rng(15)+5 = add 6-20
    pha
    lda #1
    ldx #15
    ldy #5
    jsr math_dice           // 1d15+5 = 6..20
    pla
    clc
    adc zp_math_a
    cmp #119
    bcc !inc_ok+
    lda #118                // Cap at 118 (18/100)
!inc_ok:
    rts
!above_87:
    cmp #108
    bcs !above_107+
    // stat 88-107: add rng(6)+2 = add 3-8
    pha
    lda #1
    ldx #6
    ldy #2
    jsr math_dice           // 1d6+2 = 3..8
    pla
    clc
    adc zp_math_a
    cmp #119
    bcc !inc_ok2+
    lda #118
!inc_ok2:
    rts
!above_107:
    // stat > 107: +1
    clc
    adc #1
    cmp #119
    bcc !inc_ok3+
    lda #118
!inc_ok3:
    rts

// decrement_stat — Decrement a stat using umoria's randomized step logic
// Input: A = current stat value (3-118)
// Output: A = new stat value
// Clobbers: zp_temp3, zp_temp4, zp_math* (via math_dice)
decrement_stat:
    cmp #109
    bcs !above_108+
    cmp #88
    bcs !range_88_108+
    cmp #19
    bcs !range_19_87+
    // stat <= 18
    cmp #4
    bcc !dec_done+          // stat <= 3: no change
    // stat 4-18: simple -1
    sec
    sbc #1
    rts
!above_108:
    // stat > 108: -1
    sec
    sbc #1
    rts
!range_88_108:
    // stat 88-108: subtract rng(6)+2 = 3-8
    pha
    lda #1
    ldx #6
    ldy #2
    jsr math_dice           // 1d6+2 = 3..8
    pla
    sec
    sbc zp_math_a
    rts
!range_19_87:
    // stat 19-87: subtract rng(15)+5 = 6-20
    pha
    lda #1
    ldx #15
    ldy #5
    jsr math_dice           // 1d15+5 = 6..20
    pla
    sec
    sbc zp_math_a
    // If result < 19, clamp to 18
    cmp #19
    bcs !dec_done+
    lda #18
!dec_done:
    rts

// stat_bonus_index — Convert stat value to bonus table index (0-15)
// Stats above 18 (18/xx encoded as 19-118) use index 15 (stat 18 bonus).
// Input: A = stat value (3-118)
// Output: X = bonus table index (0-15)
// Preserves: Y
stat_bonus_index:
    cmp #19
    bcc !normal+
    ldx #15                 // 18/xx → use same bonus as stat 18
    rts
!normal:
    cmp #3
    bcs !above_min+
    lda #3                  // Clamp stat minimum to 3
!above_min:
    sec
    sbc #3                  // index = stat - 3
    tax
    rts

#import "player_combat_calc.s"

// player_calc_hp — Calculate max HP based on level, class HD, CON bonus
// Preserves: nothing
player_calc_hp:
    // Max HP = class_hit_die + (level-1) * (class_hit_die/2 + CON_bonus)
    // Simplified: at level 1, HP = hit die. Each level adds hit_die/2 + CON bonus.
    lda player_data + PL_CLASS
    tax
    // Get class properties — hp die is first byte
    lda #CLASS_PROP_SIZE
    jsr mul_x_by_a          // A = class * CLASS_PROP_SIZE
    tax
    lda class_properties,x  // Class hit die
    sta zp_temp0            // Save class HD

    // Add race hit die (umoria: combined HD = race_HD + class_HD)
    lda player_data + PL_RACE
    tax
    lda #RACE_PROP_SIZE
    jsr mul_x_by_a          // A = race * RACE_PROP_SIZE
    tax
    lda race_properties,x   // Race HD (offset 0)
    clc
    adc zp_temp0
    sta zp_temp0            // Combined HD

    // CON HP bonus
    lda player_data + PL_CON_CUR
    jsr player_con_hp_adj
    sta zp_temp1            // CON bonus per level

    // HP per level = hit_die/2 + CON bonus (min 1)
    lda zp_temp0
    lsr                     // hit_die / 2
    clc
    adc zp_temp1            // + CON bonus
    bpl !min_check+
    lda #1                  // Minimum 1 HP per level
!min_check:
    cmp #1
    bcs !ok+
    lda #1
!ok:
    sta zp_temp1            // HP per additional level

    // Total max HP = hit_die + (level-1) * hp_per_level
    lda player_data + PL_LEVEL
    sec
    sbc #1                  // level - 1
    tax
    lda zp_temp1            // HP per level
    jsr math_multiply       // result in zp_math_a (lo), zp_math_b (hi)
    lda zp_math_a
    clc
    adc zp_temp0            // + base hit die
    sta player_data + PL_MHP_LO
    lda zp_math_b
    adc #0
    sta player_data + PL_MHP_HI
    rts

// mul_x_by_a — Helper: multiply X by A, result in A
// Only works for small products (<256)
// Preserves: Y
mul_x_by_a:
    sta zp_temp3
    txa
    ldx zp_temp3
    jsr math_multiply
    lda zp_math_a
    rts

// player_get_stat_bonus — Get stat bonus for a given stat index and table
// Input: X = stat value (3–18), Y = bonus table offset
// Output: A = bonus value (signed)
// Table pointers are pre-set by caller.
player_get_stat_bonus:
    txa
    sec
    sbc #3                  // Index = stat - 3
    tax
    lda (zp_ptr0),y         // Read from bonus table
    rts

// ============================================================
// Search mode and derived search/perception helpers
// ============================================================

// player_search_mode_on — Enable persistent search mode
// Preserves: nothing
player_search_mode_on:
    lda player_data + PL_FLAGS
    ora #PLF_SEARCHING
    cmp player_data + PL_FLAGS
    beq !done+
    sta player_data + PL_FLAGS
    lda zp_ui_dirty
    ora #$01
    sta zp_ui_dirty
!done:
    rts

// player_search_mode_off — Disable persistent search mode
// Preserves: nothing
player_search_mode_off:
    lda player_data + PL_FLAGS
    and #($ff - PLF_SEARCHING)
    cmp player_data + PL_FLAGS
    beq !done+
    sta player_data + PL_FLAGS
    lda zp_ui_dirty
    ora #$01
    sta zp_ui_dirty
!done:
    rts

// player_search_clear_transient_state — Reset non-persistent search runtime state
player_search_clear_transient_state:
    jsr player_search_mode_off
    lda #0
    sta zp_search_count
    rts

// ============================================================
// ui_char_draw_background — Draw sex, social class, background on char sheet
// Called from ui_char_display in OVL.UI on C64 and C128.
// Main RAM so no banking issues.
// Renders rows 12-16 of the character sheet.
// Preserves: nothing
// ============================================================
.const UDBG_COL = hal_layout_character_background_col

ui_char_draw_background:
#if hal_platform_character_background_resync
    jsr hal_platform_runtime_resync
#endif
    // --- Sex / Social Class (row 12) ---
    lda #12
    sta zp_cursor_row
    lda #UDBG_COL
    sta zp_cursor_col
    lda #COL_LGREY
    sta zp_text_color
    lda #<char_sex_label
    sta zp_ptr0
    lda #>char_sex_label
    sta zp_ptr0_hi
    jsr hal_screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_FLAGS
    and #PLF_MALE
    beq !udb_female+
    lda #<char_sex_male
    sta zp_ptr0
    lda #>char_sex_male
    sta zp_ptr0_hi
    jmp !udb_print_sex+
!udb_female:
    lda #<char_sex_female
    sta zp_ptr0
    lda #>char_sex_female
    sta zp_ptr0_hi
!udb_print_sex:
    jsr hal_screen_put_string

    lda #COL_LGREY
    sta zp_text_color
    lda #<char_sc_label
    sta zp_ptr0
    lda #>char_sc_label
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda #COL_WHITE
    sta zp_text_color
    lda player_data + PL_SOCIAL_CLASS
    jsr screen_put_decimal

    // --- Background text (rows 13-16) ---
    lda #COL_LGREY
    sta zp_text_color
    ldx #0
!udb_line_loop:
    txa
    pha
    clc
    adc #13
    sta zp_cursor_row
    lda #UDBG_COL
    sta zp_cursor_col
    pla
    tax
    pha
    lda udb_line_lo,x
    sta zp_ptr0
    lda udb_line_hi,x
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    pla
    tax
    inx
    cpx #4
    bcc !udb_line_loop-
    rts

// Background line pointer lookup table
udb_line_lo:
    .byte <player_background, <(player_background + 40)
    .byte <(player_background + 80), <(player_background + 120)
udb_line_hi:
    .byte >player_background, >(player_background + 40)
    .byte >(player_background + 80), >(player_background + 120)

// ============================================================
// Compile-time validation
// ============================================================
