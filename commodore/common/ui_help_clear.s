#importonce
// ui_help_clear.s — Screen clearing utility (always in main RAM)
//
// Separated from ui_help.s so it stays in main RAM while the
// help/character/inventory display code moves to $F000.
// Used by stores, player_magic, player_items, and UI screens.

// ui_clear_full_screen_safe — Clear the full text area using the proven-safe
// primitive for the active platform.
// - C64: keep the row-by-row clear that avoids the known residue paths.
// - C128: use the existing bulk screen_clear path for the large VDC win.
// Input: zp_text_color must be set to desired clear color
// Clobbers: A, X, Y, zp_screen_lo/hi, zp_color_lo/hi
ui_clear_full_screen_safe:
#if C128
    jmp screen_clear
#else
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
#endif

// ui_help_clear_all — legacy alias used by the help/inventory-style overlays
ui_help_clear_all:
    jmp ui_clear_full_screen_safe

uh_title_str: .text "Command Reference" ; .byte 0
help_line_idx: .byte 0
help_page_idx: .byte 0
help_page_count: .byte 1
help_pages_src_lo: .byte <uh_help_pages_fallback
help_pages_src_hi: .byte >uh_help_pages_fallback

uh_help_lines_fallback:
    .for (var i = 0; i < 23; i++) {
        .byte 2, $00
    }

uh_help_pages_fallback:
    .byte 1
    .word uh_help_lines_fallback
