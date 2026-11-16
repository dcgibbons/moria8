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
// modifiers into base stats with the upstream randomized exceptional
// stepping, making the roll permanent. The only randomizing stat path.
player_bake_creation_stats:
    lda #1
    sta stat_bake_mode
    jmp player_bake_stat_modifiers

// player_bake_stat_modifiers — Fold race/class modifiers into base stats and
// mirror the result into current stats, making the roll permanent.
// stat_bake_mode nonzero (character creation): upstream randomized stepping
// for the 18+ band — the only place stats may randomize.
// stat_bake_mode zero (legacy-save migration): exact signed arithmetic, so
// pre-baked saves convert deterministically.
// Preserves: nothing
stat_bake_mode: .byte 0

player_bake_stat_modifiers:
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
    jsr player_bake_apply_one

    // Apply class modifier
    lda zp_temp2            // class*6
    clc
    adc zp_temp1            // + stat_index
    tax
    lda class_stat_adj,x
    jsr player_bake_apply_one

    // Bake result into base and current
    ldy zp_temp1
    lda stat_work
    sta player_data + PL_STR_BASE,y
    sta player_data + PL_STR_CUR,y

    iny
    cpy #STAT_COUNT
    bne !bake_loop-
    rts

// player_bake_apply_one — Apply modifier A to stat_work per stat_bake_mode.
player_bake_apply_one:
    ldx stat_bake_mode
    bne !pbao_roll+
    clc
    adc stat_work
    sta stat_work
    rts
!pbao_roll:
    jmp apply_modifier

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
