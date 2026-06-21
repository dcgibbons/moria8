#importonce
// dungeon_direction.s — Shared direction prompt and target calculation.

#import "input_ui_helpers.s"

// get_direction_target — Prompt for direction and compute target.
// Output: df_target_x/df_target_y = adjacent tile coordinates
//         carry set = valid direction entered
//         carry clear = invalid key
get_direction_target:
    ldx #HSTR_DF_DIRECTION
    jsr huff_print_msg

    lda zp_player_x
    pha
    lda zp_player_y
    pha
    jsr input_prepare_followup_key
    jsr hal_input_get_key
    jsr petscii_to_command
    sta df_dir_idx
    pla
    sta zp_player_y
    pla
    sta zp_player_x

    lda df_dir_idx
    cmp #CMD_MOVE_N
    bcc !gdt_invalid+
    cmp #CMD_MOVE_SE + 1
    bcs !gdt_invalid+

    sec
    sbc #CMD_MOVE_N
    tax

    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x

    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y

    sec
    rts

!gdt_invalid:
    clc
    rts
