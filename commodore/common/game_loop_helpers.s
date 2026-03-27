// game_loop_helpers.s — Shared UI/result helper routines extracted from game_loop.s
//
// Imported in-place from game_loop.s to preserve segment placement while
// narrowing the main loop file to orchestration and command bodies.

.const HELP_KEY_Q = $51
.const HELP_KEY_SPACE = $20
.const HELP_KEY_RETURN = $0d
#if C128
.const HELP_KEY_ESC = KEY_ESC
#else
.const HELP_KEY_ESC = $1b
#endif

// ============================================================
// Shared UI-only command flows
// ============================================================
cmd_show_character_view:
    jsr tramp_ui_char_display
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key
    jsr screen_clear
    jmp vp_render_status_loop

cmd_show_help_view:
    lda #0
    sta help_page_idx
!help_page_loop:
    jsr tramp_ui_help_display
!help_key_loop:
#if C128
    jsr input_wait_release
#else
    lda #0
    sta KBDBUF_COUNT
    jsr input_wait_release
#endif
    jsr input_get_key
    cmp #HELP_KEY_Q
    beq !help_done+
    cmp #HELP_KEY_ESC
    beq !help_done+
    cmp #HELP_KEY_SPACE
    beq !help_advance+
    cmp #HELP_KEY_RETURN
    beq !help_advance+
    jmp !help_key_loop-
!help_advance:
    lda help_page_idx
    clc
    adc #1
    cmp help_page_count
    bcs !help_done+
    inc help_page_idx
    jmp !help_page_loop-
!help_done:
    jmp ui_view_return_to_gameplay_view

cmd_show_inventory_view:
    jsr tramp_ui_inv_display
#if C128
    jsr input_wait_release
#else
    lda #0
    sta KBDBUF_COUNT
    jsr input_wait_release
#endif
    jsr input_get_key
    jmp ui_view_return_to_gameplay_view

cmd_show_equipment_view:
    jsr tramp_ui_equip_display
#if C128
    jsr input_wait_release
#else
    lda #0
    sta KBDBUF_COUNT
    jsr input_wait_release
#endif
    jsr input_get_key
    jmp ui_view_return_to_gameplay_view

cmd_recall_view:
    jsr msg_clear
    lda #0
    sta zp_cursor_row
    sta zp_cursor_col
    lda #<recall_prompt_str
    sta zp_ptr0
    lda #>recall_prompt_str
    sta zp_ptr0_hi
    jsr screen_put_string
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key
    jsr recall_key_to_screen_code
    bcc !recall_done+
    jsr recall_show_matching_entry
!recall_done:
    jsr screen_clear
    jmp vp_render_status_loop

recall_key_to_screen_code:
    cmp #$41
    bcc !recall_try_shifted+
    cmp #$5b
    bcs !recall_try_shifted+
    sec
    sbc #$40
    sta recall_query_sc
    sec
    rts
!recall_try_shifted:
    cmp #$c1
    bcc !invalid+
    cmp #$db
    bcs !invalid+
    and #$3f
    clc
    adc #$40
    sta recall_query_sc
    sec
    rts
!invalid:
    clc
    rts

recall_show_matching_entry:
    lda recall_query_sc
    cmp recall_last_sc
    bne !recall_new_char+
    lda recall_last_idx
    clc
    adc #1
    cmp #MAX_CREATURES
    bcc !recall_set_start+
    lda #0
    jmp !recall_set_start+
!recall_new_char:
    lda #0
!recall_set_start:
    tax
    lda #MAX_CREATURES
    sta zp_temp1
!recall_search:
    lda cr_display,x
    cmp recall_query_sc
    bne !recall_next+
    lda recall_kills,x
    ora recall_deaths,x
    ora recall_attacks,x
    ora recall_spells,x
    bne !recall_found+
!recall_next:
    inx
    cpx #MAX_CREATURES
    bcc !recall_no_wrap+
    ldx #0
!recall_no_wrap:
    dec zp_temp1
    bne !recall_search-
    lda #0
    sta recall_last_sc
    rts
!recall_found:
    stx recall_found_type
    lda recall_query_sc
    sta recall_last_sc
    stx recall_last_idx
    jsr creature_get_name
    jsr tramp_ui_recall
    lda #0
    sta KBDBUF_COUNT
#if C128
    jsr input_wait_release
#endif
    jsr input_get_key
    rts

// ============================================================
// Shared command-result helpers
// ============================================================
command_result_main_or_redraw_full:
    bcc !crrf_no_turn+
    jmp post_turn_redraw_full_or_die
!crrf_no_turn:
    jmp main_loop

command_result_main_or_status_only:
    bcc !crso_no_turn+
    jmp post_turn_status_only_or_die
!crso_no_turn:
    jmp main_loop

command_result_main_or_update_visibility:
    bcc !cruv_no_turn+
    jmp post_turn_update_visibility_or_die
!cruv_no_turn:
    jmp main_loop

command_result_restore_view_or_update_visibility:
    bcc !crrv_no_turn+
    jmp post_turn_update_visibility_or_die
!crrv_no_turn:
    jsr screen_clear
    jmp vp_render_status_loop

// ============================================================
// Shared post-turn tails and gameplay-view restore
// ============================================================
post_turn_redraw_full_or_die:
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !ptfd_alive+
    jmp player_died
!ptfd_alive:
    jmp vp_render_status_loop

post_turn_status_only_or_die:
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !ptso_alive+
    jmp player_died
!ptso_alive:
    lda turn_scene_dirty
    bne vp_render_status_loop
    jsr status_draw
    jmp main_loop

post_turn_update_visibility_or_die:
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !ptuv_alive+
    jmp player_died
!ptuv_alive:
    jsr update_visibility
    jsr viewport_update
    lda zp_view_x
    cmp old_view_x
    bne !ptuv_full+
    lda zp_view_y
    cmp old_view_y
    bne !ptuv_full+
    lda vis_room_revealed
    bne !ptuv_full+
    lda turn_scene_dirty
    bne !ptuv_full+
    jsr render_local_area
    jsr status_draw
    jmp main_loop
!ptuv_full:
    lda #INPUT_ROW
    jsr screen_clear_row
    jsr render_viewport
    jsr status_draw
    jmp main_loop

ui_view_return_to_gameplay_view:
    jsr ui_view_restore_modal_overlay
    lda #INPUT_ROW
    jsr screen_clear_row
    jmp main_loop

// ============================================================
// Shared tail — viewport update + render + status + main loop
// ============================================================
vp_render_status_loop:
    lda #INPUT_ROW
    jsr screen_clear_row
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp main_loop
