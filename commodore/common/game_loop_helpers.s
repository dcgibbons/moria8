// game_loop_helpers.s — Shared UI/result helper routines extracted from game_loop.s
//
// Imported in-place from game_loop.s to preserve segment placement while
// narrowing the main loop file to orchestration and command bodies.

#import "input_ui_helpers.s"

.const HELP_KEY_Q = $51
.const HELP_KEY_SPACE = $20
.const HELP_KEY_RETURN = $0d

// ============================================================
// Shared UI-only command flows
// ============================================================
cmd_show_character_view:
    jsr tramp_ui_char_display
    jsr input_prepare_followup_key
    jsr input_get_key
#if !C128
    // C64 character view is overlay-backed and returns through a custom
    // full-screen redraw path, so it must also re-establish the active tier.
    jsr tier_restore_after_overlay
#endif
	    jsr hal_screen_clear
#if C128
#if PERF_P1
    jsr perf_p1_set_reason_modal_restore
#endif
#endif
	    jmp vp_render_status_loop

cmd_show_help_view:
    lda #0
    sta help_page_idx
!help_page_loop:
    jsr tramp_ui_help_display
!help_key_loop:
    jsr input_prepare_modal_dismiss_key
    jsr input_get_key
    cmp #HELP_KEY_Q
    beq !help_done+
    jsr input_is_modal_escape_key
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
    jsr input_prepare_modal_dismiss_key
    jsr input_get_key
    jmp ui_view_return_to_gameplay_view

cmd_show_equipment_view:
    jsr tramp_ui_equip_display
    jsr input_prepare_modal_dismiss_key
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
    jsr hal_screen_put_string
    jsr input_prepare_followup_key
    jsr input_get_key
    jsr recall_key_to_screen_code
    bcc !recall_done+
    jsr recall_show_matching_entry
!recall_done:
	    jsr hal_screen_clear
#if C128
#if PERF_P1
    jsr perf_p1_set_reason_modal_restore
#endif
#endif
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
    jsr input_prepare_modal_dismiss_key
    jsr input_get_key
    rts

// ============================================================
// Shared command-result helpers
// ============================================================
command_result_main_or_redraw_full:
	    bcc !crrf_no_turn+
#if C128
#if PERF_P1
    jsr perf_p1_set_reason_command_forced
#endif
#endif
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
	    jsr hal_screen_clear
#if C128
#if PERF_P1
    jsr perf_p1_set_reason_modal_restore
#endif
#endif
	    jmp vp_render_status_loop

// ============================================================
// Shared post-turn tails and gameplay-view restore
// ============================================================
turn_post_action_searchable_or_die:
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    bne !dead+

    lda turn_scene_dirty
    sta ghl_saved_scene_dirty

    lda player_data + PL_FLAGS
    and #PLF_SEARCHING
    beq !alive+

    jsr search_scan_effective_silent
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    bne !dead+

    lda turn_scene_dirty
    ora ghl_saved_scene_dirty
    sta turn_scene_dirty
!alive:
    clc
    rts
!dead:
    sec
    rts

post_turn_redraw_full_or_die:
	    jsr turn_post_action_searchable_or_die
	    bcc !ptfds_alive+
	    jmp player_died
!ptfds_alive:
#if C128
#if PERF_P1
    jsr perf_p1_set_reason_command_forced_if_none
#endif
#endif
	    jmp vp_render_status_loop

post_turn_status_only_or_die:
    jsr turn_post_action_searchable_or_die
    bcc !ptsos_alive+
    jmp player_died
!ptsos_alive:
	    lda turn_scene_dirty
	    beq !ptsos_status_only+
#if C128
#if PERF_P1
    jsr perf_p1_set_reason_scene_dirty
#endif
#endif
	    jmp vp_render_status_loop
!ptsos_status_only:
    jsr status_draw
    jmp main_loop

post_turn_update_visibility_or_die:
    jsr turn_post_action_searchable_or_die
    bcc !ptuvs_alive+
    jmp player_died
!ptuvs_alive:
    lda vis_room_revealed
    pha
    jsr update_visibility
    pla
    ora vis_room_revealed
    sta vis_room_revealed
	    jsr viewport_update
	    lda zp_view_x
	    cmp old_view_x
    beq !ptuvs_chk_y+
#if C128
#if PERF_P1
    jsr perf_p1_set_reason_scroll_fallback
#endif
#endif
	    jmp !ptuvs_full+
!ptuvs_chk_y:
	    lda zp_view_y
	    cmp old_view_y
    beq !ptuvs_chk_reveal+
#if C128
#if PERF_P1
    jsr perf_p1_set_reason_scroll_fallback
#endif
#endif
	    jmp !ptuvs_full+
!ptuvs_chk_reveal:
	    lda vis_room_revealed
    beq !ptuvs_chk_scene+
#if C128
#if PERF_P1
    jsr perf_p1_set_reason_room_reveal
#endif
#endif
	    jmp !ptuvs_full+
!ptuvs_chk_scene:
	    lda turn_scene_dirty
    beq !ptuvs_local+
#if C128
#if PERF_P1
    jsr perf_p1_set_reason_scene_dirty
#endif
#endif
	    jmp !ptuvs_full+
!ptuvs_local:
	    jsr render_local_area
#if C128
#if PERF_P1
    jsr perf_p1_mark_local
#endif
#endif
	    jsr status_draw
	    jmp main_loop
!ptuvs_full:
	    lda #INPUT_ROW
	    jsr hal_screen_clear_row
#if C128
#if PERF_P1
    jsr perf_p1_mark_full_reason_update_visibility
#endif
#endif
	    jsr render_viewport
	    jsr status_draw
    jmp main_loop

ui_view_return_to_gameplay_view:
    jsr ui_view_restore_modal_overlay
    lda #INPUT_ROW
    jsr hal_screen_clear_row
    jmp main_loop

// ============================================================
// Shared tail — viewport update + render + status + main loop
// ============================================================
vp_render_status_loop:
	    lda #INPUT_ROW
	    jsr hal_screen_clear_row
	    jsr viewport_update
#if C128
#if PERF_P1
    jsr perf_p1_mark_full_default_transition
#endif
#endif
	    jsr render_viewport
	    jsr status_draw
#if C128_TEST_PERF_P1_TRACE_COMMAND
    jmp c128_test_perf_p1_trace_capture_sym
#endif
    jmp main_loop
ghl_saved_scene_dirty: .byte 0
