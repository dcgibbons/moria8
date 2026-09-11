#importonce
// ui_help_page2_data.s — C64/Plus4 40-column second help page payload
//
// Page 2 carries no page-1 command duplicates: movement-key diagrams,
// prompt/selection keys, and the wizard-mode key (unique to this page).

// ============================================================
// Page 2: movement diagrams + prompt notes (rows 1-23)
// ============================================================
help_more_lines:

// Row 1: headers
    .byte 1
    .text "Keypad" ; .byte $fc, 20 ; .text "Letters" ; .byte 0

// Row 2
    .byte 0
    .text "   7 8 9"
    .byte $fc, 20
    .text "   Y K U"
    .byte 0

// Row 3
    .byte 0
    .text "   4 5 6"
    .byte $fc, 20
    .text "   H   L"
    .byte 0

// Row 4
    .byte 0
    .text "   1 2 3"
    .byte $fc, 20
    .text "   B J N"
    .byte 0

// Row 5
    .byte 0
    .text "   5 = Rest"
    .byte $fc, 20
    .text "   Cursors move"
    .byte 0

// Row 6: blank
    .byte 2
    .byte 0

// Row 7: headers
    .byte 1
    .text "Prompts" ; .byte $fc, 20 ; .text "Selection" ; .byte 0

// Row 8
    .byte 0
    .byte $fe
    .text "STOP/Q"
    .byte $ff
    .text " Cancel"
    .byte $fc, 20
    .text "Letters Pick"
    .byte 0

// Row 9
    .byte 0
    .byte $fe
    .text "SPACE"
    .byte $ff
    .text " Continue"
    .byte $fc, 20
    .text "RETURN Accept"
    .byte 0

// Row 10
    .byte 0
    .byte $fe
    .text "/"
    .byte $ff
    .text " Identify"
    .byte $fc, 20
    .text "then symbol"
    .byte 0

// Row 11: wizard mode (only listed on this page)
    .byte 0
    .byte $fe
    .text "CTRL+W"
    .byte $ff
    .text " Wizard"
    .byte 0

// Rows 12-23: reserved blank lines to keep the frame layout fixed
    .for (var i = 0; i < 12; i++) {
        .byte 2
        .byte 0
    }

help_pages:
    .byte 2
    .word help_lines
    .word help_more_lines
