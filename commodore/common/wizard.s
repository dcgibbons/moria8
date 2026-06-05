#importonce
// wizard.s — Wizard Mode shared state and non-UI helpers

#import "ui_restore.s"

.const WIZARD_MAX_DLVL  = 99
.const WIZARD_MAX_ITEM  = ITEM_TYPE_COUNT - 1

wizard_wall_walk_enabled: .byte 0
wizard_num_digits:        .byte 0
wizard_num_buf0:          .byte 0
wizard_num_buf1:          .byte 0
wizard_prompt_max:        .byte 0
wizard_prompt_value:      .byte 0
wizard_target_depth:      .byte 0
wizard_entry_dir:         .byte 0

// wizard_execute_level_jump — Shared main-resident execution tail for Wizard
// level jumps. This must live outside OVL.UI on C128 because it loads the
// dungeon-generation overlay into the same $E000 window.
wizard_execute_level_jump:
    lda zp_player_dlvl
    cmp wizard_target_depth
    bcc !wiz_jump_descend+
    lda #1
    sta wizard_entry_dir
    bne !wiz_jump_go+
!wiz_jump_descend:
    lda #0
    sta wizard_entry_dir
!wiz_jump_go:
    lda wizard_target_depth
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    cmp player_data + PL_MAX_DLVL
    bcc !wiz_max_ok+
    beq !wiz_max_ok+
    sta player_data + PL_MAX_DLVL
!wiz_max_ok:
    lda wizard_target_depth
    bne !wiz_not_town+
    jsr tramp_store_restock_all
!wiz_not_town:
    lda wizard_entry_dir
    sta level_entry_dir
    jsr level_change_generate_current
    jmp main_loop

wizard_reset_session_state:
    lda #0
    sta wizard_wall_walk_enabled
    rts

wizard_wall_walk_active:
    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    beq !inactive+
    lda wizard_wall_walk_enabled
    rts
!inactive:
    lda #0
    rts

// wizard_generate_item_execute — Create a usable item for Wizard mode.
// Non-gold items prefer inventory placement so the item is immediately usable.
// Gold and inventory-overflow cases fall back to floor placement at the
// player's current tile.
// Input: fi_add_id = item type
//        fi_add_x / fi_add_y = desired floor position for fallback
// Output: carry set = success, carry clear = failure
wizard_generate_item_execute:
    lda fi_add_id
    tax
    lda it_category,x
    cmp #ICAT_GOLD
    beq !wiz_make_gold+

    // Roll the normal item fields so Wizard-generated items are usable.
    lda fi_add_id
    jsr roll_enchantment
    sta fi_add_p1
    lda fi_add_id
    jsr tramp_roll_ego_type
    sta fi_add_ego

    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_qty_hi

    ldx fi_add_id
    jsr item_get_missile
    bpl !wiz_try_inv+
    lda #6
    jsr rng_range
    clc
    adc #5
    sta fi_add_qty

!wiz_try_inv:
    jsr inv_add_item
    bcs !wiz_item_ok+
    jmp !wiz_try_floor+

!wiz_make_gold:
    lda fi_add_id
    bne !wiz_large_gold+
    lda #25
    bne !wiz_gold_qty+
!wiz_large_gold:
    lda #100
!wiz_gold_qty:
    sta fi_add_qty
    jsr fi_add_clear_plain_meta

!wiz_try_floor:
    jsr floor_item_add
    bcs !wiz_item_ok+
    clc
    rts

!wiz_item_ok:
    sec
    rts

// wizard_reveal_level — Reveal a floor-plan view of the current level without
// marking every solid-rock tile as explored. Reveals lit room geometry plus
// traversable/special features, then exposes hidden doors.
wizard_reveal_level:
#if HAL_PLATFORM_WIZARD_REVEAL_TRAMPOLINE
    jmp tramp_reveal_floorplan
#else
    ldx #0
!wrl_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
!wrl_col:
    :MapRead_ptr0_y()
    sta zp_temp0
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !wrl_visit+
    cmp #TILE_DOOR_OPEN
    bcs !wrl_visit+
    lda zp_temp0
    and #FLAG_LIT
    beq !wrl_next+
!wrl_visit:
    lda zp_temp0
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
!wrl_next:
    iny
    cpy #MAP_COLS
    bcc !wrl_col-
    inx
    cpx #MAP_ROWS
    bcc !wrl_row-
!wrl_done:
    jmp eff_find_doors
#endif

cmd_wizard_entry:
#if HAL_PLATFORM_WIZARD_ENTRY_OVERLAY
    jsr tramp_ui_wizard_display
    jmp main_loop
#else
    lda zp_game_flags
    and #GAME_FLAG_WIZARD
    bne !wizard_open+

    lda #<wiz_confirm_str
    sta zp_ptr0
    lda #>wiz_confirm_str
    sta zp_ptr0_hi
    jsr msg_print
    jsr hal_input_get_key
    cmp #$59                    // Y
    beq !wiz_enable+
    cmp #$D9                    // SHIFT+Y fallback
    beq !wiz_enable+
    jmp main_loop
!wiz_enable:
    lda zp_game_flags
    ora #GAME_FLAG_WIZARD
    sta zp_game_flags
    lda #<wiz_enabled_str
    sta zp_ptr0
    lda #>wiz_enabled_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp main_loop

!wizard_open:
    jsr wizard_40col_menu_display
    jsr hal_input_get_key
    cmp #$51                    // Q
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
    jmp ui_view_return_to_gameplay_view
!wiz_heal:
    jmp wizard_cmd_heal_cure
!wiz_reveal:
    jmp wizard_cmd_reveal
!wiz_identify:
    jmp wizard_cmd_identify
!wiz_gain:
    jmp wizard_cmd_gain_level
!wiz_teleport:
    jmp wizard_cmd_teleport
!wiz_wall:
    jmp wizard_cmd_wall_walk
!wiz_summon:
    jmp wizard_cmd_summon
!wiz_item:
    jmp wizard_cmd_generate_item
!wiz_jump:
    jmp wizard_cmd_level_jump
#endif

#if HAL_PLATFORM_WIZARD_40COL_RESIDENT
wizard_cmd_heal_cure:
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
    sta zp_player_mp
    sta zp_player_mmp
    lda #0
    sta zp_eff_poison
    sta zp_eff_blind
    sta zp_eff_confuse
    sta zp_eff_paralyze
    sta zp_eff_speed
    sta zp_eff_word_recall
    sta eff_fear_timer
    jmp wizard_done_message

wizard_cmd_reveal:
    jsr wizard_reveal_level
    jmp wizard_done_message

wizard_cmd_identify:
    ldx #TOTAL_INV_SLOTS - 1
!wiz_ident_loop:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !wiz_ident_next+
    lda inv_flags,x
    and #~IF_SENSED & $ff
    ora #IF_IDENTIFIED
    sta inv_flags,x
    lda inv_item_id,x
    tay
    lda #1
    sta id_known,y
!wiz_ident_next:
    dex
    bpl !wiz_ident_loop-
    jmp wizard_done_message

wizard_cmd_gain_level:
    lda zp_player_lvl
    cmp #40
    bcc !wiz_gain_ok+
    lda #<wiz_max_level_str
    sta zp_ptr0
    lda #>wiz_max_level_str
    sta zp_ptr0_hi
    jmp wizard_restore_gameplay_with_message
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
    jsr wizard_restore_gameplay_view
    jsr combat_apply_levelup
    jsr status_draw
    jmp main_loop

wizard_cmd_teleport:
    jsr eff_teleport_self
    jmp wizard_done_visibility_message

wizard_cmd_wall_walk:
    lda wizard_wall_walk_enabled
    eor #1
    sta wizard_wall_walk_enabled
    beq !wiz_wall_off+
    lda #<wiz_wall_on_str
    sta zp_ptr0
    lda #>wiz_wall_on_str
    sta zp_ptr0_hi
    jmp wizard_restore_gameplay_with_message
!wiz_wall_off:
    lda #<wiz_wall_off_str
    sta zp_ptr0
    lda #>wiz_wall_off_str
    sta zp_ptr0_hi
    jmp wizard_restore_gameplay_with_message

wizard_cmd_summon:
    lda zp_player_x
    sta fae_cx
    lda zp_player_y
    sta fae_cy
    jsr find_adjacent_empty
    bcs !wiz_adj_ok+
    jmp wizard_fail_message
!wiz_adj_ok:
    jsr tier_check_transition
    jsr pick_wizard_summon_creature_type
    jsr monster_spawn_one
    bcs !wiz_summon_ok+
    jmp wizard_fail_message
!wiz_summon_ok:
    jmp wizard_done_visibility_message

wizard_cmd_generate_item:
    lda #<wiz_item_prompt_str
    sta zp_ptr0
    lda #>wiz_item_prompt_str
    sta zp_ptr0_hi
    lda #WIZARD_MAX_ITEM
    jsr wizard_prompt_two_digit
    bcs !wiz_item_have+
    jmp ui_view_return_to_gameplay_view
!wiz_item_have:
    lda zp_player_x
    sta fi_add_x
    lda zp_player_y
    sta fi_add_y
    lda wizard_prompt_value
    sta fi_add_id
    jsr fi_add_clear_plain_meta
    jsr wizard_generate_item_execute
    bcs !wiz_item_ok+
    jmp wizard_fail_message
!wiz_item_ok:
    jmp wizard_done_visibility_message

wizard_cmd_level_jump:
    lda #<wiz_jump_prompt_str
    sta zp_ptr0
    lda #>wiz_jump_prompt_str
    sta zp_ptr0_hi
    lda #WIZARD_MAX_DLVL
    jsr wizard_prompt_two_digit
    bcs !wiz_jump_have+
    jmp ui_view_return_to_gameplay_view
!wiz_jump_have:
    lda wizard_prompt_value
    sta wizard_target_depth
    jmp wizard_execute_level_jump

wizard_prompt_two_digit:
    sta wizard_prompt_max
    jsr ui_help_clear_all
    lda #COL_WHITE
    sta zp_text_color
    lda #5
    sta zp_cursor_row
    lda #8
    sta zp_cursor_col
    jsr hal_screen_put_string
    lda #0
    sta wizard_num_digits
!wiz_num_loop:
    jsr hal_input_get_key
    cmp #$0d
    bne !wiz_num_not_ret+
    lda wizard_num_digits
    beq !wiz_num_loop-
    jsr wizard_parse_two_digit
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
    cmp #$14
    bne !wiz_num_not_del+
    lda wizard_num_digits
    beq !wiz_num_loop-
    dec wizard_num_digits
    dec zp_cursor_col
    lda #$20
    jsr hal_screen_put_char
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
    jsr hal_screen_put_char
    inc wizard_num_digits
    jmp !wiz_num_loop-
!wiz_num_cancel:
    clc
    rts

wizard_parse_two_digit:
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

wizard_restore_gameplay_with_visibility_message:
    jsr update_visibility
wizard_done_visibility_message:
    lda #<wiz_done_str
    sta zp_ptr0
    lda #>wiz_done_str
    sta zp_ptr0_hi
    jmp wizard_restore_gameplay_with_visibility_message_core
wizard_fail_message:
    lda #<wiz_fail_str
    sta zp_ptr0
    lda #>wiz_fail_str
    sta zp_ptr0_hi
    jmp wizard_restore_gameplay_with_message
wizard_done_message:
    lda #<wiz_done_str
    sta zp_ptr0
    lda #>wiz_done_str
    sta zp_ptr0_hi
wizard_restore_gameplay_with_visibility_message_core:
wizard_restore_gameplay_with_message:
    lda zp_ptr0
    sta wizard_num_buf0
    lda zp_ptr0_hi
    sta wizard_num_buf1
    jsr ui_view_redraw_gameplay_view
    lda wizard_num_buf0
    sta zp_ptr0
    lda wizard_num_buf1
    sta zp_ptr0_hi
    jsr msg_print
    jmp main_loop

wizard_restore_gameplay_view:
    jsr ui_view_redraw_gameplay_view
    rts

wizard_40col_menu_display:
    lda #COL_WHITE
    sta zp_text_color
    jsr ui_help_clear_all
    lda #0
    sta zp_cursor_row
    lda #14
    sta zp_cursor_col
    lda #<wiz_title_str
    sta zp_ptr0
    lda #>wiz_title_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda #COL_LGREY
    sta zp_text_color
    lda #2
    sta zp_cursor_row
    lda #4
    sta zp_cursor_col
    lda #<wiz_row1_str
    sta zp_ptr0
    lda #>wiz_row1_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda #3
    sta zp_cursor_row
    lda #4
    sta zp_cursor_col
    lda #<wiz_row2_str
    sta zp_ptr0
    lda #>wiz_row2_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda #4
    sta zp_cursor_row
    lda #4
    sta zp_cursor_col
    lda #<wiz_row3_str
    sta zp_ptr0
    lda #>wiz_row3_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda #5
    sta zp_cursor_row
    lda #4
    sta zp_cursor_col
    lda #<wiz_row4_str
    sta zp_ptr0
    lda #>wiz_row4_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda #18
    sta zp_cursor_row
    lda #14
    sta zp_cursor_col
    lda #<wiz_footer_str
    sta zp_ptr0
    lda #>wiz_footer_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    rts

.encoding "screencode_mixed"
wiz_confirm_str:
    .text "WIZARD? (Y/N)" ; .byte 0
wiz_enabled_str:
    .text "WIZARD ON" ; .byte 0
wiz_max_level_str:
    .text "MAX" ; .byte 0
wiz_wall_on_str:
    .text "WALL ON" ; .byte 0
wiz_wall_off_str:
    .text "WALL OFF" ; .byte 0
wiz_done_str:
    .text "OK" ; .byte 0
wiz_fail_str:
    .text "FAIL" ; .byte 0
wiz_item_prompt_str:
    .text "ITEM 0-77: " ; .byte 0
wiz_jump_prompt_str:
    .text "DLVL 0-99: " ; .byte 0
wiz_bad_value_str:
    .text "BAD" ; .byte 0
wiz_title_str:
    .text "WIZARD MODE" ; .byte 0
wiz_row1_str:
    .text "L jump    A reveal    H heal" ; .byte 0
wiz_row2_str:
    .text "I ident   X level     G item" ; .byte 0
wiz_row3_str:
    .text "S summon  T tele      W wall" ; .byte 0
wiz_row4_str:
    .text "Q to cancel" ; .byte 0
wiz_footer_str:
    .text "Q to cancel" ; .byte 0
#endif
