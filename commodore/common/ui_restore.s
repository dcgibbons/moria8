#importonce
// ui_restore.s — Shared gameplay-view restore helpers for modal UI flows

ui_reset_message_state:
    lda #0
    sta zp_msg_flags
    sta msg_row1_col
    rts

#if C128
// ui_prepare_fullscreen_transition — clear the screen and reset message-row
// state before a full-screen prompt or status transition.
ui_prepare_fullscreen_transition:
    jsr hal_screen_clear
    jsr ui_reset_message_state
    rts
#endif

// ui_view_restore_modal_overlay — dismiss a read-only overlay and redraw gameplay
// Used by help/inventory/spell-pick flows that return to the caller for more UI.
// Preserves: nothing
ui_view_restore_modal_overlay:
    jsr ui_reset_message_state
#if !C128
    // C64 overlays overwrite the live tier window at $E000, so gameplay-view
    // restore must re-establish the current dungeon tier before redraw.
    jsr tier_restore_after_overlay
#endif
    lda #COL_BLACK
    sta zp_text_color
	    jsr ui_help_clear_all
	    jsr viewport_update
#if C128
#if PERF_P1
    jsr perf_p1_mark_full_reason_modal_restore
#endif
#endif
	    jsr render_viewport
	    jsr status_draw
#if C128_TEST_PERF_P1_TRACE_MODAL
    jmp c128_test_perf_p1_trace_capture_sym
#endif
    rts

// ui_view_redraw_gameplay_view — rebuild the gameplay view after a full-screen modal
// Used by wizard/menu-style flows that replace the whole screen.
// Preserves: nothing
ui_view_redraw_gameplay_view:
    jsr ui_reset_message_state
#if !C128
    // C64 overlays overwrite the live tier window at $E000, so gameplay-view
    // restore must re-establish the current dungeon tier before redraw.
    jsr tier_restore_after_overlay
#endif
	    jsr hal_screen_clear
	    jsr viewport_update
#if C128
#if PERF_P1
    jsr perf_p1_mark_full_reason_modal_restore
#endif
#endif
	    jsr render_viewport
	    jsr status_draw
    rts
