#importonce
// player_save.s — Player saving throw (VMS Moria player_saves).
//
// VMS misc.inc player_saves(adjust): randint(100) <= py.misc.save + adjust,
// where py.misc.save is the race base plus the class base. Moria8 uses its
// own race/class save values (core/tables.s) by maintainer decision (MON-011).
// Callers pass the VMS adjustment: monster spells use wis_adj + level
// (creature.inc cast_spell); the paralysis touch uses con_adj.
//
// Imported by monster_magic.s and monster_attack.s (#importonce); no state.

.const RACE_PROP_SAVE  = 9      // race_properties save column
.const CLASS_PROP_SAVE = 6      // class_properties save column

// player_saving_throw — Roll a VMS saving throw.
// Input:  A = signed adjustment
// Output: carry clear = the player saves (resists), carry set = fails
// Clobbers: A, X, Y, zp_temp0, zp_math_*
player_saving_throw:
    jsr player_save_value
    sta zp_temp0
    lda #100
    jsr rng_range               // 0..99; roll < save == randint(100) <= save
    cmp zp_temp0
    rts

// player_save_value — Save target: race save + class save + adjustment.
// Input:  A = signed adjustment
// Output: A = target, negative sums clamped to 0. Shipped tables keep the
//         sum within -8..18 + 18..36 + (wis 0..7 + level 1..40) <= 101, so
//         the signed byte never overflows.
// Clobbers: A, X, Y, zp_temp0, zp_math_*
player_save_value:
    sta zp_temp0
    lda player_data + PL_RACE
    ldx #RACE_PROP_SIZE
    jsr math_multiply
    ldx zp_math_a
    lda race_properties + RACE_PROP_SAVE,x
    clc
    adc zp_temp0
    sta zp_temp0
    lda player_data + PL_CLASS
    ldx #CLASS_PROP_SIZE
    jsr math_multiply
    ldx zp_math_a
    lda class_properties + CLASS_PROP_SAVE,x
    clc
    adc zp_temp0
    bpl !done+
    lda #0
!done:
    rts

// player_wis_save_adj — VMS wis_adj (misc.inc): 0..7 from wisdom.
// Input:  A = wisdom (3-118, 18/xx encoded as 19-118)
// Output: A = adjustment
// Clobbers: A, X
player_wis_save_adj:
    ldx #$ff
!loop:
    inx
    cmp ps_wis_floor,x
    bcs !loop-
    txa
    rts

// Lowest wisdom earning each step: VMS >7, >14, >17, >67, >87, >107, >117.
// The $ff sentinel ends the scan (wisdom never exceeds 118).
ps_wis_floor:
    .byte 8, 15, 18, 68, 88, 108, 118, $ff
