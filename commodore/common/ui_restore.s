#importonce
// ui_restore.s — Shared gameplay-view restore helpers for modal UI flows

#if C128
// ui_prepare_fullscreen_transition — clear the screen and reset message-row
// state before a full-screen prompt or status transition.
ui_prepare_fullscreen_transition:
    jsr screen_clear
    lda #0
    sta zp_msg_flags
    sta msg_row1_col
    rts
#endif

// ui_view_restore_modal_overlay — dismiss a read-only overlay and redraw gameplay
// Used by help/inventory/spell-pick flows that return to the caller for more UI.
// Preserves: nothing
ui_view_restore_modal_overlay:
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    rts

// ui_view_redraw_gameplay_view — rebuild the gameplay view after a full-screen modal
// Used by wizard/menu-style flows that replace the whole screen.
// Preserves: nothing
ui_view_redraw_gameplay_view:
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    rts
