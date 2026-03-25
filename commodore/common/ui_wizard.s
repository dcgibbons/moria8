#importonce
// ui_wizard.s — C128 Wizard Mode menu and command handlers

#import "ui_restore.s"

#if C128
.const UWIZ_TITLE_COL  = (SCREEN_COLS - 6) / 2
.const UWIZ_MENU_COL   = (SCREEN_COLS - 20) / 2
.const UWIZ_FOOTER_COL = (SCREEN_COLS - 13) / 2

ui_wizard_msg_lo: .byte 0
ui_wizard_msg_hi: .byte 0

ui_wizard_display:
    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    bne !wiz_menu+
    jsr ui_wizard_restore_gameplay_view
    lda #<wiz_confirm_str
    sta zp_ptr0
    lda #>wiz_confirm_str
    sta zp_ptr0_hi
    jsr msg_print
    jsr input_wait_release
    jsr input_get_key
    cmp #$59                    // Y
    beq !wiz_enable+
    cmp #$D9                    // SHIFT+Y fallback
    beq !wiz_enable+
    rts
!wiz_enable:
    lda zp_game_flags
    ora #GAME_FLAG_WIZARD
    sta zp_game_flags
    lda #<wiz_enabled_str
    sta zp_ptr0
    lda #>wiz_enabled_str
    sta zp_ptr0_hi
    jsr msg_print
    rts
!wiz_menu:
    jsr ui_wizard_draw_menu
    jsr input_wait_release
    jsr input_get_key
    cmp #$51                    // Q
    beq !wiz_cancel+
    cmp #$ae                    // ESC
    beq !wiz_cancel+
    cmp #$48                    // H
    beq !wiz_heal+
    cmp #$41                    // A
    beq !wiz_reveal+
    cmp #$49                    // I
    beq !wiz_identify+
    cmp #$58                    // X
    beq !wiz_gain+
    cmp #$54                    // T
    beq !wiz_teleport+
    cmp #$57                    // W
    beq !wiz_wall+
    cmp #$53                    // S
    beq !wiz_summon+
    cmp #$47                    // G
    beq !wiz_item+
    cmp #$4c                    // L
    beq !wiz_jump+
!wiz_cancel:
    jsr ui_wizard_restore_gameplay_view
    rts
!wiz_heal:
    jmp ui_wizard_cmd_heal_cure
!wiz_reveal:
    jmp ui_wizard_cmd_reveal
!wiz_identify:
    jmp ui_wizard_cmd_identify
!wiz_gain:
    jmp ui_wizard_cmd_gain_level
!wiz_teleport:
    jmp ui_wizard_cmd_teleport
!wiz_wall:
    jmp ui_wizard_cmd_wall_walk
!wiz_summon:
    jmp ui_wizard_cmd_summon
!wiz_item:
    jmp ui_wizard_cmd_generate_item
!wiz_jump:
    jmp ui_wizard_cmd_level_jump

ui_wizard_draw_menu:
    lda #COL_WHITE
    sta zp_text_color
    jsr ui_help_clear_all

    lda #0
    sta zp_cursor_row
    lda #UWIZ_TITLE_COL
    sta zp_cursor_col
    lda #<wiz_title_str
    sta zp_ptr0
    lda #>wiz_title_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_LGREY
    sta zp_text_color

    lda #2
    sta zp_cursor_row
    lda #UWIZ_MENU_COL
    sta zp_cursor_col
    lda #<wiz_l_str
    sta zp_ptr0
    lda #>wiz_l_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #3
    sta zp_cursor_row
    lda #UWIZ_MENU_COL
    sta zp_cursor_col
    lda #<wiz_a_str
    sta zp_ptr0
    lda #>wiz_a_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #4
    sta zp_cursor_row
    lda #UWIZ_MENU_COL
    sta zp_cursor_col
    lda #<wiz_h_str
    sta zp_ptr0
    lda #>wiz_h_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #5
    sta zp_cursor_row
    lda #UWIZ_MENU_COL
    sta zp_cursor_col
    lda #<wiz_i_str
    sta zp_ptr0
    lda #>wiz_i_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #6
    sta zp_cursor_row
    lda #UWIZ_MENU_COL
    sta zp_cursor_col
    lda #<wiz_x_str
    sta zp_ptr0
    lda #>wiz_x_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #7
    sta zp_cursor_row
    lda #UWIZ_MENU_COL
    sta zp_cursor_col
    lda #<wiz_g_str
    sta zp_ptr0
    lda #>wiz_g_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #8
    sta zp_cursor_row
    lda #UWIZ_MENU_COL
    sta zp_cursor_col
    lda #<wiz_s_str
    sta zp_ptr0
    lda #>wiz_s_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #9
    sta zp_cursor_row
    lda #UWIZ_MENU_COL
    sta zp_cursor_col
    lda #<wiz_t_str
    sta zp_ptr0
    lda #>wiz_t_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #10
    sta zp_cursor_row
    lda #UWIZ_MENU_COL
    sta zp_cursor_col
    lda #<wiz_w_str
    sta zp_ptr0
    lda #>wiz_w_str
    sta zp_ptr0_hi
    jsr screen_put_string

    lda #COL_WHITE
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #UWIZ_FOOTER_COL
    sta zp_cursor_col
    lda #<wiz_footer_str
    sta zp_ptr0
    lda #>wiz_footer_str
    sta zp_ptr0_hi
    jsr screen_put_string
    rts

ui_wizard_cmd_heal_cure:
    lda player_data + PL_MHP_LO
    sta player_data + PL_HP_LO
    sta zp_player_hp_lo
    lda player_data + PL_MHP_HI
    sta player_data + PL_HP_HI
    sta zp_player_hp_hi
    lda player_data + PL_MHP_LO
    sta zp_player_mhp_lo
    lda player_data + PL_MHP_HI
    sta zp_player_mhp_hi
    lda player_data + PL_MAX_MANA
    sta player_data + PL_MANA
    lda #0
    sta zp_eff_poison
    sta zp_eff_blind
    sta zp_eff_confuse
    sta zp_eff_paralyze
    sta zp_eff_speed
    sta zp_eff_word_recall
    sta eff_fear_timer
    jmp ui_wizard_done_message

ui_wizard_cmd_reveal:
    jsr wizard_reveal_level
    jmp ui_wizard_done_message

ui_wizard_cmd_identify:
    ldx #TOTAL_INV_SLOTS - 1
!wiz_ident_loop:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !wiz_ident_next+
    lda inv_flags,x
    ora #IF_IDENTIFIED
    sta inv_flags,x
    lda inv_item_id,x
    tay
    lda #1
    sta id_known,y
!wiz_ident_next:
    dex
    bpl !wiz_ident_loop-
    jmp ui_wizard_done_message

ui_wizard_cmd_gain_level:
    lda zp_player_lvl
    cmp #40
    bcc !wiz_gain_ok+
    lda #<wiz_max_level_str
    sta zp_ptr0
    lda #>wiz_max_level_str
    sta zp_ptr0_hi
    jmp ui_wizard_restore_gameplay_with_message
!wiz_gain_ok:
    jsr combat_compute_level_threshold
    lda player_data + PL_XP_2
    cmp ccl_adj_2
    bcc !wiz_set_xp+
    bne !wiz_do_level+
    lda player_data + PL_XP_1
    cmp ccl_adj_1
    bcc !wiz_set_xp+
    bne !wiz_do_level+
    lda player_data + PL_XP_0
    cmp ccl_adj_0
    bcs !wiz_do_level+
!wiz_set_xp:
    lda ccl_adj_0
    sta player_data + PL_XP_0
    lda ccl_adj_1
    sta player_data + PL_XP_1
    lda ccl_adj_2
    sta player_data + PL_XP_2
    lda #0
    sta player_data + PL_XP_FRAC_LO
    sta player_data + PL_XP_FRAC_HI
!wiz_do_level:
    jsr ui_wizard_restore_gameplay_view
    jsr combat_apply_levelup
    jsr status_draw
    rts

ui_wizard_cmd_teleport:
    jsr eff_teleport_self
    jmp ui_wizard_done_visibility_message

ui_wizard_cmd_wall_walk:
    lda wizard_wall_walk_enabled
    eor #1
    sta wizard_wall_walk_enabled
    beq !wiz_wall_off+
    lda #<wiz_wall_on_str
    sta zp_ptr0
    lda #>wiz_wall_on_str
    sta zp_ptr0_hi
    jmp ui_wizard_restore_gameplay_with_message
!wiz_wall_off:
    lda #<wiz_wall_off_str
    sta zp_ptr0
    lda #>wiz_wall_off_str
    sta zp_ptr0_hi
    jmp ui_wizard_restore_gameplay_with_message

ui_wizard_cmd_summon:
    lda zp_player_x
    sta fae_cx
    lda zp_player_y
    sta fae_cy
    jsr find_adjacent_empty
    bcs !wiz_adj_ok+
    jmp ui_wizard_fail_message
!wiz_adj_ok:
    jsr pick_creature_type
    jsr monster_spawn_one
    bcs !wiz_summon_ok+
    jmp ui_wizard_fail_message
!wiz_summon_ok:
    jmp ui_wizard_done_visibility_message

ui_wizard_cmd_generate_item:
    lda #<wiz_item_prompt_str
    sta zp_ptr0
    lda #>wiz_item_prompt_str
    sta zp_ptr0_hi
    lda #WIZARD_MAX_ITEM
    jsr ui_wizard_prompt_two_digit
    bcs !wiz_item_have+
    jsr ui_view_return_to_gameplay_view
    rts
!wiz_item_have:
    lda zp_player_x
    sta fi_add_x
    lda zp_player_y
    sta fi_add_y
    lda wizard_prompt_value
    sta fi_add_id
    lda #0
    sta fi_add_p1
    sta fi_add_flags
    sta fi_add_ego
    jsr wizard_generate_item_execute
    bcs !wiz_item_ok+
    jmp ui_wizard_fail_message
!wiz_item_ok:
    jmp ui_wizard_done_visibility_message

ui_wizard_cmd_level_jump:
    lda #<wiz_jump_prompt_str
    sta zp_ptr0
    lda #>wiz_jump_prompt_str
    sta zp_ptr0_hi
    lda #WIZARD_MAX_DLVL
    jsr ui_wizard_prompt_two_digit
    bcs !wiz_jump_have+
    jsr ui_view_return_to_gameplay_view
    rts
!wiz_jump_have:
    lda wizard_prompt_value
    sta wizard_target_depth
    jmp wizard_execute_level_jump

ui_wizard_prompt_two_digit:
    sta wizard_prompt_max
    jsr screen_clear
    lda #COL_WHITE
    sta zp_text_color
    lda #5
    sta zp_cursor_row
    lda #(SCREEN_COLS - 24) / 2
    sta zp_cursor_col
    jsr screen_put_string
    lda #0
    sta wizard_num_digits
!wiz_num_loop:
    jsr input_wait_release
    jsr input_get_key
    cmp #$0d
    bne !wiz_num_not_ret+
    lda wizard_num_digits
    beq !wiz_num_loop-
    jsr ui_wizard_parse_two_digit
    bcs !wiz_num_ok+
    lda #<wiz_bad_value_str
    sta zp_ptr0
    lda #>wiz_bad_value_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp !wiz_num_loop-
!wiz_num_ok:
    sec
    rts
!wiz_num_not_ret:
    cmp #$51
    beq !wiz_num_cancel+
    cmp #$20
    beq !wiz_num_cancel+
    cmp #$ae
    beq !wiz_num_cancel+
    cmp #$14
    bne !wiz_num_not_del+
    lda wizard_num_digits
    beq !wiz_num_loop-
    dec wizard_num_digits
    dec zp_cursor_col
    lda #$20
    jsr screen_put_char
    dec zp_cursor_col
    jmp !wiz_num_loop-
!wiz_num_not_del:
    cmp #$30
    bcc !wiz_num_loop-
    cmp #$3a
    bcs !wiz_num_loop-
    ldx wizard_num_digits
    cpx #2
    bcs !wiz_num_loop-
    sta wizard_num_buf0,x
    jsr screen_put_char
    inc wizard_num_digits
    jmp !wiz_num_loop-
!wiz_num_cancel:
    clc
    rts

ui_wizard_parse_two_digit:
    lda #0
    sta wizard_prompt_value
    lda wizard_num_digits
    cmp #1
    bne !wiz_two_digits+
    lda wizard_num_buf0
    sec
    sbc #$30
    sta wizard_prompt_value
    jmp !wiz_range_check+
!wiz_two_digits:
    lda wizard_num_buf0
    sec
    sbc #$30
    asl
    sta zp_temp0
    asl
    asl
    clc
    adc zp_temp0
    sta wizard_prompt_value
    lda wizard_num_buf1
    sec
    sbc #$30
    clc
    adc wizard_prompt_value
    sta wizard_prompt_value
!wiz_range_check:
    cmp wizard_prompt_max
    beq !wiz_parse_ok+
    bcs !wiz_parse_fail+
!wiz_parse_ok:
    sec
    rts
!wiz_parse_fail:
    clc
    rts

ui_wizard_restore_gameplay_with_visibility_message:
    jsr update_visibility
ui_wizard_done_visibility_message:
    lda #<wiz_done_str
    sta zp_ptr0
    lda #>wiz_done_str
    sta zp_ptr0_hi
    jmp ui_wizard_restore_gameplay_with_message

ui_wizard_fail_message:
    lda #<wiz_fail_str
    sta zp_ptr0
    lda #>wiz_fail_str
    sta zp_ptr0_hi
    jmp ui_wizard_restore_gameplay_with_message

ui_wizard_done_message:
    lda #<wiz_done_str
    sta zp_ptr0
    lda #>wiz_done_str
    sta zp_ptr0_hi

ui_wizard_restore_gameplay_with_message:
    lda zp_ptr0
    sta ui_wizard_msg_lo
    lda zp_ptr0_hi
    sta ui_wizard_msg_hi
    jsr ui_view_redraw_gameplay_view
    lda ui_wizard_msg_lo
    sta zp_ptr0
    lda ui_wizard_msg_hi
    sta zp_ptr0_hi
    jsr msg_print
    rts

ui_wizard_restore_gameplay_view:
    jsr ui_view_redraw_gameplay_view
    rts

wiz_title_str:
    .text "WIZARD" ; .byte 0
wiz_l_str:
    .text "L) Jump" ; .byte 0
wiz_a_str:
    .text "A) Reveal" ; .byte 0
wiz_h_str:
    .text "H) Heal" ; .byte 0
wiz_i_str:
    .text "I) Identify" ; .byte 0
wiz_x_str:
    .text "X) Gain lvl" ; .byte 0
wiz_g_str:
    .text "G) Item by id" ; .byte 0
wiz_s_str:
    .text "S) Summon" ; .byte 0
wiz_t_str:
    .text "T) Teleport" ; .byte 0
wiz_w_str:
    .text "W) Wall walk" ; .byte 0
wiz_footer_str:
    .text "Q cancels" ; .byte 0
wiz_max_level_str:
    .text "MAX" ; .byte 0
wiz_confirm_str:
    .text "WIZARD? (Y/N)" ; .byte 0
wiz_enabled_str:
    .text "WIZARD ON" ; .byte 0
wiz_wall_on_str:
    .text "WALL ON" ; .byte 0
wiz_wall_off_str:
    .text "WALL OFF" ; .byte 0
wiz_done_str:
    .text "OK" ; .byte 0
wiz_fail_str:
    .text "FAIL" ; .byte 0
wiz_item_prompt_str:
    .text "ITEM 0-63: " ; .byte 0
wiz_jump_prompt_str:
    .text "DLVL 0-99: " ; .byte 0
wiz_bad_value_str:
    .text "BAD" ; .byte 0
#endif
