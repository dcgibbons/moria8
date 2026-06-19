#importonce
// ui_help_page2_data.s — C64/40-column second help page payload

// ============================================================
// Page 2: compact overflow / prompt notes + movement diagram
// ============================================================
help_more_lines:

// Row 1: headers
    .byte 1
    .text "More Keys" ; .byte $fc, 20 ; .text "Notes" ; .byte 0

// Row 2
    .byte 0
    .byte $fe
    .text "SHIFT+C"
    .byte $ff
    .text " Char"
    .byte $fc, 20
    .byte $fe
    .text "SHIFT+DIR"
    .byte $ff
    .text " Run"
    .byte 0

// Row 3
    .byte 0
    .byte $fe
    .text "SHIFT+S"
    .byte $ff
    .text " Save"
    .byte $fc, 20
    .text "Cursors Move"
    .byte 0

// Row 4
    .byte 0
    .byte $fe
    .text "SHIFT+Q"
    .byte $ff
    .text " Quit"
    .byte $fc, 20
    .text "Walk into Mon"
    .byte 0

// Row 5
    .byte 0
    .byte $fe
    .text "/"
    .byte $ff
    .text " Identify"
    .byte $fc, 20
    .byte $fe
    .text "CTRL+W"
    .byte $ff
    .text " Wizard"
    .byte 0

// Row 6
    .byte 0
    .byte $fe
    .text "CTRL+B"
    .byte $ff
    .text " Bash"
    .byte $fc, 20
    .byte $fe
    .text "SHIFT+D"
    .byte $ff
    .text " Disarm"
    .byte 0

// Row 7: blank
    .byte 2
    .byte 0

// Row 8: movement diagram header
    .byte 1
    .text "Movement Keys"
    .byte 0

// Row 9
    .byte 0
    .text "     Y K U"
    .byte 0

// Row 10
    .byte 0
    .text "     H . L"
    .byte 0

// Row 11
    .byte 0
    .text "     B J N"
    .byte 0

// Row 12
    .byte 0
    .text "     . = stay"
    .byte 0

// Row 13
    .byte 0
    .text "   Y=NW U=NE"
    .byte 0

// Row 14
    .byte 0
    .text "   B=SW N=SE"
    .byte 0

// Row 15: blank
    .byte 2
    .byte 0

// Row 16: headers
    .byte 1
    .text "Prompts" ; .byte $fc, 20 ; .text "Selection" ; .byte 0

// Row 17
    .byte 0
    .byte $fe
    .text "ESC/Q"
    .byte $ff
    .text " Cancel"
    .byte $fc, 20
    .text "Letters Pick"
    .byte 0

// Row 18
    .byte 0
    .byte $fe
    .text "SPACE"
    .byte $ff
    .text " Continue"
    .byte $fc, 20
    .text "RETURN Accept"
    .byte 0

// Row 19
    .byte 0
    .byte $fe
    .text "/"
    .byte $ff
    .text " Identify"
    .byte $fc, 20
    .text "then symbol"
    .byte 0

// Rows 20-23: reserved blank lines to keep the frame layout fixed
    .for (var i = 0; i < 4; i++) {
        .byte 2
        .byte 0
    }

help_pages:
    .byte 2
    .word help_lines
    .word help_more_lines
