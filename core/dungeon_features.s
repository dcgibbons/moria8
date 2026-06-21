#importonce
// dungeon_features.s — Doors, traps, secret doors, search
//
// Phase 4.2: Explicit open/close door commands, stuck door mechanics,
// hidden trap placement and triggering, secret doors found by searching.

#import "input_ui_helpers.s"
#import "dungeon_feature_gen.s"
#import "dungeon_feature_actions.s"
#import "trap_table.s"
#import "trap_detection.s"

// ============================================================
// Trap name Huffman indices (indexed by trap type 0-5)
// ============================================================
trap_name_huff_idx:
    .byte HSTR_DF_TRAP_0, HSTR_DF_TRAP_1, HSTR_DF_TRAP_2
    .byte HSTR_DF_TRAP_3, HSTR_DF_TRAP_4, HSTR_DF_TRAP_5

#if PLATFORM_DISARM_COMMAND_INLINE || !DISARM_HELPERS_EXTERNAL
trap_difficulty:
    .byte 5, 15, 10, 20, 20, 25
#endif

#if PLATFORM_DISARM_COMMAND_INLINE || !DISARM_COMMAND_EXTERNAL
trap_disarm_xp:
    .byte 1, 3, 2, 5, 6, 8

disarm_no_visible_str:
    .text "I do not see anything to disarm there." ; .byte 0
disarm_success_str:
    .text "You have disarmed the trap." ; .byte 0
disarm_fail_str:
    .text "You failed to disarm the trap." ; .byte 0
disarm_bad_fail_str:
    .text "You set the trap off!" ; .byte 0
#endif

#if PLATFORM_DISARM_COMMAND_INLINE || !DISARM_COMMAND_EXTERNAL
// disarm_command — Direct visible floor-trap disarm command.
// Output: carry set = turn consumed, carry clear = no turn.
disarm_command:
    jsr get_direction_target
    bcc !no_turn+
    jsr trap_find_target_visible
    bcs !has_trap+
    lda #<disarm_no_visible_str
    sta zp_ptr0
    lda #>disarm_no_visible_str
    sta zp_ptr0_hi
    jsr msg_print
!no_turn:
    clc
    rts

!has_trap:
    jsr player_disarm_get_effective_chance
    sta df_disarm_total
    ldx df_disarm_trap_idx
    lda trap_type,x
    tax
    lda df_disarm_total
    jsr disarm_calc_success_threshold
    sta df_disarm_chance
    lda #100
    jsr rng_range
    cmp df_disarm_chance
    bcc !success+

    lda df_disarm_total
    jsr disarm_roll_bad_fail
    bcs !bad_fail+
    lda #<disarm_fail_str
    sta zp_ptr0
    lda #>disarm_fail_str
    sta zp_ptr0_hi
    jsr msg_print
    sec
    rts

!success:
    lda #<disarm_success_str
    sta zp_ptr0
    lda #>disarm_success_str
    sta zp_ptr0_hi
    jsr msg_print
    jsr disarm_award_trap_xp
    jsr disarm_restore_target_floor
    ldx df_disarm_trap_idx
    jsr trap_remove_at_index
    jsr disarm_move_player_to_target
    sec
    rts

!bad_fail:
    lda #<disarm_bad_fail_str
    sta zp_ptr0
    lda #>disarm_bad_fail_str
    sta zp_ptr0_hi
    jsr msg_print
    jsr disarm_move_player_to_target
    ldx df_disarm_trap_idx
    jsr trap_trigger
    sec
    rts

disarm_restore_target_floor:
    ldx df_target_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy df_target_x
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_FLOOR
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
    rts

disarm_move_player_to_target:
    lda df_target_x
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda df_target_y
    sta zp_player_y
    sta player_data + PL_MAP_Y
    rts

disarm_award_trap_xp:
    ldx df_disarm_trap_idx
    lda trap_type,x
    tax
    lda player_data + PL_XP_0
    clc
    adc trap_disarm_xp,x
    sta player_data + PL_XP_0
    bcc !done+
    inc player_data + PL_XP_1
    bne !done+
    inc player_data + PL_XP_2
!done:
    rts

#endif

#if !DISARM_HELPERS_EXTERNAL
#import "disarm_helpers.s"
#endif

#import "trap_effects.s"

// ============================================================
// Compile-time validation
// ============================================================
