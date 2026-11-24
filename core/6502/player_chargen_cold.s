#importonce
// player_chargen_cold.s — Cold character-creation stat initialization and baking
//
// Module ownership:
//   owner: StartupOverlay when PLAYER_CHARGEN_EXTERNAL is defined; TestUnused
//     in C64 unit tests that park chargen; Default resident otherwise (imported
//     by core/player.s).
//   lifetime: one character-creation session per New Game (or restart).
//   callers: core/player_create.s (StartupOverlay) exclusively; zero runtime
//     gameplay or overlay callees.

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

// player_bake_creation_stats — Character-creation entry: fold race/class
// modifiers into base stats with the upstream randomized exceptional stepping
// for the 18+ band, mirroring the result into current stats and making the
// roll permanent.
// Preserves: nothing
player_bake_creation_stats:
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
!bake_loop:
    sty zp_temp1            // Save stat index (safe across math_dice)

    // Start with base stat
    lda player_data + PL_STR_BASE,y
    sta stat_work

    // Apply race modifier
    lda zp_temp0            // race*6
    clc
    adc zp_temp1            // + stat_index
    tax
    lda race_stat_adj,x
    jsr apply_modifier

    // Apply class modifier
    lda zp_temp2            // class*6
    clc
    adc zp_temp1            // + stat_index
    tax
    lda class_stat_adj,x
    jsr apply_modifier

    // Bake result into base and current
    ldy zp_temp1
    lda stat_work
    sta player_data + PL_STR_BASE,y
    sta player_data + PL_STR_CUR,y

    iny
    cpy #STAT_COUNT
    bne !bake_loop-
    rts

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
    lda stat_work
!dec_loop:
    jsr chargen_decrement_stat
    dec am_count
    bne !dec_loop-
    beq !store+
!positive:
    sta am_count
    lda stat_work
!inc_loop:
    jsr increment_stat
    dec am_count
    bne !inc_loop-
!store:
    sta stat_work
!done:
    rts

am_count: .byte 0  // Loop counter for apply_modifier (safe from X clobber)

// chargen_decrement_stat — Decrement a stat using create.inc / Umoria
// character-creation bands (separate from runtime de_statp in decrement_stat).
// Input: A = current stat value (3-118)
// Output: A = new stat value
// Clobbers: X, Y, zp_temp3, zp_temp4, zp_math* (via math_dice)
chargen_decrement_stat:
    cmp #109
    bcs !cdec_sub1+
    cmp #88
    bcs !cdec_88_108+
    cmp #19
    bcs !cdec_19_87+
    cmp #4
    bcc !cdec_done+
!cdec_sub1:
    sbc #1
    rts
!cdec_88_108:
    ldx #6
    ldy #2
    bne !cdec_roll+
!cdec_19_87:
    ldx #15
    ldy #5
!cdec_roll:
    pha
    lda #1
    jsr math_dice
    pla
    sec
    sbc zp_math_a
    cmp #19
    bcs !cdec_done+
    lda #18
!cdec_done:
    rts

// increment_stat — Increment a stat using umoria's randomized step logic
// Input: A = current stat value (3-118)
// Output: A = new stat value
// Clobbers: zp_temp3, zp_temp4, zp_math* (via math_dice)
increment_stat:
    cmp #108
    bcs !inc_add1+
    cmp #88
    bcs !inc_88_107+
    cmp #18
    bcs !inc_18_87+
!inc_add1:
    clc
    adc #1
    bne !inc_cap+
!inc_88_107:
    ldx #6
    ldy #2
    bne !inc_roll+
!inc_18_87:
    ldx #15
    ldy #5
!inc_roll:
    pha
    lda #1
    jsr math_dice           // 1d15+5 (6..20) or 1d6+2 (3..8)
    pla
    clc
    adc zp_math_a
!inc_cap:
    cmp #119
    bcc !inc_done+
    lda #118                // Cap at 118 (18/100)
!inc_done:
    rts
