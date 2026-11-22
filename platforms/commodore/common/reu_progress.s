#importonce
// reu_progress.s — REU boot preload overlay-progress counter and banner,
// for reu.s. Separated so C64 disk builds can park it in the init-only tail
// past program_end, where the map later overwrites it.

// Scratch for overlay stashing
reu_ovl_idx: .byte 0

// ============================================================
// REU loading display
// ============================================================

// reu_show_file — Advance the centered REU loading progress display.
reu_show_file:
    inc reu_loading_count
    jmp reu_render_progress

reu_render_progress:
    lda #12
    jsr hal_screen_clear_row
    lda #12
    sta zp_cursor_row
    lda #4
    sta zp_cursor_col
    lda #<reu_loading_prefix
    sta zp_ptr0
    lda #>reu_loading_prefix
    sta zp_ptr0_hi
    jsr hal_screen_put_string
    lda reu_loading_count
    jsr screen_put_decimal
    lda #$2f
    jsr hal_screen_put_char
    lda #(4 + REU_OVERLAY_COUNT)    // tiers + overlays (chest overlay included)
    jsr screen_put_decimal
    lda #<reu_loading_suffix
    sta zp_ptr0
    lda #>reu_loading_suffix
    sta zp_ptr0_hi
    jmp hal_screen_put_string

reu_loading_count: .byte 0

// Progress message parts (reassembled by reu_render_progress)
reu_loading_prefix: .text "MORIA8 LOADING " ; .byte 0
reu_loading_suffix: .text " PLEASE WAIT" ; .byte 0
