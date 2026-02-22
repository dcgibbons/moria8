// ui_help_clear.s — Screen clearing utility (always in main RAM)
//
// Separated from ui_help.s so it stays in main RAM while the
// help/character/inventory display code moves to $F000.
// Used by stores, player_magic, player_items, and UI screens.

// ui_help_clear_all — Clear all 25 rows using screen_clear_row
// Input: zp_text_color must be set to desired clear color
// Clobbers: A, X, Y, zp_screen_lo/hi, zp_color_lo/hi
ui_help_clear_all:
    lda #0
    sta help_line_idx
!hca_loop:
    lda help_line_idx
    jsr screen_clear_row
    inc help_line_idx
    lda help_line_idx
    cmp #SCREEN_ROWS
    bcc !hca_loop-
    rts
help_line_idx: .byte 0
