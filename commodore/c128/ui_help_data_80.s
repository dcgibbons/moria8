#importonce
// ui_help_data_80.s — C128-specific 80-column help content
//
// The C128 help screen has a dedicated overlay, so use a real 80-column
// two-page layout instead of stretching the compact 40-column help data.

// Packed page format:
//   help_pages = [page_count] [page_ptr_lo/hi]...
//   each page  = [type_byte] [string_data...] [$00] repeated for 23 lines.
// Type bytes: 0=CONTENT 1=HEADER 2=BLANK
// Control codes: $fc=TAB(col) $fd=CH(cyan) $fe=CK(white) $ff=CD(lgrey)

.const HELP80_COL2 = 44

help_title_str:
    .text "Command Reference" ; .byte 0

help_lines:
    .byte 1
    .text "Movement" ; .byte $fc, HELP80_COL2 ; .text "Actions" ; .byte 0

    .byte 0
    .byte $fe ; .text "H" ; .byte $ff ; .text " Left"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "O" ; .byte $ff ; .text " Open Door"
    .byte 0

    .byte 0
    .byte $fe ; .text "L" ; .byte $ff ; .text " Right"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "C" ; .byte $ff ; .text " Close Door"
    .byte 0

    .byte 0
    .byte $fe ; .text "K" ; .byte $ff ; .text " Up"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "S" ; .byte $ff ; .text " Search"
    .byte 0

    .byte 0
    .byte $fe ; .text "J" ; .byte $ff ; .text " Down"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "." ; .byte $ff ; .text " Rest"
    .byte 0

    .byte 0
    .byte $fe ; .text "Y" ; .byte $ff ; .text " NW"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "<" ; .byte $ff ; .text " Go Up"
    .byte 0

    .byte 0
    .byte $fe ; .text "U" ; .byte $ff ; .text " NE"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text ">" ; .byte $ff ; .text " Go Down"
    .byte 0

    .byte 0
    .byte $fe ; .text "B" ; .byte $ff ; .text " SW"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "/" ; .byte $ff ; .text " Recall"
    .byte 0

    .byte 0
    .byte $fe ; .text "N" ; .byte $ff ; .text " SE"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "X" ; .byte $ff ; .text " Look"
    .byte 0

    .byte 0
    .text "Cursors also move"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "SHIFT+DIR" ; .byte $ff ; .text " Run"
    .byte 0

    .byte 2 ; .byte 0

    .byte 1
    .text "Items" ; .byte $fc, HELP80_COL2 ; .text "Combat" ; .byte 0

    .byte 0
    .byte $fe ; .text "G" ; .byte $ff ; .text " Get Item"
    .byte $fc, HELP80_COL2
    .text "Walk into monster"
    .byte 0

    .byte 0
    .byte $fe ; .text "D" ; .byte $ff ; .text " Drop Item"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "SHIFT+F" ; .byte $ff ; .text " Fire"
    .byte 0

    .byte 0
    .byte $fe ; .text "I" ; .byte $ff ; .text " Inventory"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "SHIFT+T" ; .byte $ff ; .text " Throw"
    .byte 0

    .byte 0
    .byte $fe ; .text "E" ; .byte $ff ; .text " Equipment"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "SHIFT+D" ; .byte $ff ; .text " Bash"
    .byte 0

    .byte 0
    .byte $fe ; .text "W" ; .byte $ff ; .text " Wear/Wield"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "+" ; .byte $ff ; .text " Tunnel"
    .byte 0

    .byte 0
    .byte $fe ; .text "T" ; .byte $ff ; .text " Take Off"
    .byte 0

    .byte 0
    .byte $fe ; .text "Q" ; .byte $ff ; .text " Quaff Potion"
    .byte 0

    .byte 0
    .byte $fe ; .text "R" ; .byte $ff ; .text " Read Scroll"
    .byte 0

    .byte 0
    .byte $fe ; .text "A" ; .byte $ff ; .text " Aim Wand"
    .byte 0

help_more_lines:
    .byte 1
    .text "Magic" ; .byte $fc, HELP80_COL2 ; .text "Other" ; .byte 0

    .byte 0
    .byte $fe ; .text "M" ; .byte $ff ; .text " Cast Spell"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "SHIFT+C" ; .byte $ff ; .text " Character"
    .byte 0

    .byte 0
    .byte $fe ; .text "P" ; .byte $ff ; .text " Pray"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "?" ; .byte $ff ; .text " Help"
    .byte 0

    .byte 0
    .byte $fe ; .text "F" ; .byte $ff ; .text " Study Book"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "SHIFT+S" ; .byte $ff ; .text " Save"
    .byte 0

    .byte 0
    .byte $fe ; .text "SHIFT+E" ; .byte $ff ; .text " Eat"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "SHIFT+Q" ; .byte $ff ; .text " Quit"
    .byte 0

    .byte 0
    .byte $fe ; .text "SHIFT+R" ; .byte $ff ; .text " Refuel"
    .byte $fc, HELP80_COL2
    .byte $fe ; .text "CTRL+W" ; .byte $ff ; .text " Wizard"
    .byte 0

    .byte 2 ; .byte 0

    .byte 1
    .text "Keypad" ; .byte $fc, HELP80_COL2 ; .text "Letters" ; .byte 0

    .byte 0
    .text "    7   8   9"
    .byte $fc, HELP80_COL2
    .text "    Y   K   U"
    .byte 0

    .byte 0
    .text "    4   5   6"
    .byte $fc, HELP80_COL2
    .text "    H   .   L"
    .byte 0

    .byte 0
    .text "    1   2   3"
    .byte $fc, HELP80_COL2
    .text "    B   J   N"
    .byte 0

    .byte 2 ; .byte 0

    .byte 0
    .text "    5 = stay"
    .byte $fc, HELP80_COL2
    .text "    . = stay"
    .byte 0

    .byte 0
    .text "   7=NW    9=NE"
    .byte $fc, HELP80_COL2
    .text "   Y=NW    U=NE"
    .byte 0

    .byte 0
    .text "   1=SW    3=SE"
    .byte $fc, HELP80_COL2
    .text "   B=SW    N=SE"
    .byte 0

    .byte 2 ; .byte 0

    .byte 1
    .text "Prompts" ; .byte $fc, HELP80_COL2 ; .text "Notes" ; .byte 0

    .byte 0
    .text "ESC or Q Cancel"
    .byte $fc, HELP80_COL2
    .text "SPACE/RETURN advance"
    .byte 0

    .byte 0
    .text "SPACE Continue"
    .byte $fc, HELP80_COL2
    .text "Walk into monsters to attack"
    .byte 0

    .byte 0
    .text "RETURN Accept"
    .byte $fc, HELP80_COL2
    .text "Inventory letters act directly"
    .byte 0

    .byte 0
    .text "/ Recall then letter"
    .byte $fc, HELP80_COL2
    .text "Search is the one-turn S command"
    .byte 0

    .for (var i = 0; i < 5; i++) {
        .byte 2
        .byte 0
    }

help_pages:
    .byte 2
    .word help_lines
    .word help_more_lines
