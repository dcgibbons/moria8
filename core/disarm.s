#import "df_target_row.s"
// disarm.s — C128 resident-play copy of direct trap disarm command.

trap_difficulty:
    .byte 5, 15, 10, 20, 20, 25, 10, 20, 20, 30, 30, 30, 15, 20, 20, 0, 25, 20
trap_difficulty_end:
.assert "disarm trap_difficulty covers TRAP_TYPE_COUNT", trap_difficulty_end - trap_difficulty, TRAP_TYPE_COUNT

trap_disarm_xp:
    .byte 1, 3, 2, 5, 6, 8, 2, 6, 5, 10, 10, 10, 3, 5, 5, 0, 8, 5
trap_disarm_xp_end:
.assert "disarm trap_disarm_xp covers TRAP_TYPE_COUNT", trap_disarm_xp_end - trap_disarm_xp, TRAP_TYPE_COUNT

disarm_no_visible_str:
    .text "I do not see anything to disarm there." ; .byte 0
disarm_success_str:
    .text "You have disarmed the trap." ; .byte 0
disarm_fail_str:
    .text "You failed to disarm the trap." ; .byte 0
disarm_bad_fail_str:
    .text "You set the trap off!" ; .byte 0

disarm_command:
    jsr get_direction_target
    bcc !no_turn+
    // Chest at the target tile dispatches to the chest overlay via the
    // resident chest_dispatch; never returns here (docs/CHEST_DESIGN.md).
    jsr chest_find_at_df_target
    bcc !not_chest+
    lda #<chest_disarm_command
    ldy #>chest_disarm_command
    jmp chest_dispatch
!not_chest:
    jsr trap_find_target_visible
    bcs !has_trap+
    lda #<disarm_no_visible_str
    ldy #>disarm_no_visible_str
    jsr msg_print_ay
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
    ldy #>disarm_fail_str
    bne !msg_turn+

!success:
    ldx df_disarm_trap_idx
    lda trap_type,x
    pha
    jsr trap_remove_at_index
    jsr disarm_move_player_to_target
    jsr df_target_row_ptr
    :MapRead_ptr0_y()
    and #TILE_FLAG_MASK
    ora #TILE_FLOOR | FLAG_VISITED
    :MapWrite_ptr0_y()
    pla
    tax
    lda trap_disarm_xp,x
    jsr player_award_xp_a
    txa
    cmp #TRAP_HIDDEN_OBJECT
    bne !normal_ok+
    jsr df_stage_hidden_drop
    sec
    rts
!normal_ok:
    lda #<disarm_success_str
    ldy #>disarm_success_str
!msg_turn:
    jsr msg_print_ay
    sec
    rts

!bad_fail:
    lda #<disarm_bad_fail_str
    ldy #>disarm_bad_fail_str
    jsr msg_print_ay
    jsr disarm_move_player_to_target
    ldx df_disarm_trap_idx
    jsr trap_trigger
    sec
    rts

disarm_move_player_to_target:
    lda df_target_x
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda df_target_y
    sta zp_player_y
    sta player_data + PL_MAP_Y
    rts
