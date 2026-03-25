#importonce
// ui_help_data.s — Help screen string data (main RAM)
//
// Packed format: [type_byte] [string_data...] [$00] per line, 23 lines.
// The banked renderer walks this data sequentially.
// Border strings are drawn procedurally by ui_help.s.
//
// Type bytes: 0=CONTENT 1=HEADER 2=BLANK
// Control codes: $fc=TAB(col) $fd=CH(cyan) $fe=CK(white) $ff=CD(lgrey)

// Title string (stays in main RAM, referenced from banked code)
help_title_str:
    .text "Command Reference" ; .byte 0

// ============================================================
// Packed content lines (rows 1-23, type byte + string + null)
// ============================================================
help_lines:

// Row 1: Section headers (HEADER)
    .byte 1
    .text "Movement" ; .byte $fc, 20 ; .text "Actions" ; .byte 0

// Row 2: Movement keys + Open door (CONTENT)
    .byte 0
    .byte $fe
    .text "H"
    .byte $ff
    .text " Left  "
    .byte $fe
    .text "L"
    .byte $ff
    .text " Right   "
    .byte $fe
    .text "O"
    .byte $ff
    .text " Open Door"
    .byte 0

// Row 3: Movement keys + Close door
    .byte 0
    .byte $fe
    .text "K"
    .byte $ff
    .text " Up"
    .byte $fc, 10
    .byte $fe
    .text "J"
    .byte $ff
    .text " Down"
    .byte $fc, 20
    .byte $fe
    .text "C"
    .byte $ff
    .text " Close Door"
    .byte 0

// Row 4: Diagonal movement + Search
    .byte 0
    .byte $fe
    .text "Y"
    .byte $ff
    .text " NW"
    .byte $fc, 10
    .byte $fe
    .text "U"
    .byte $ff
    .text " NE"
    .byte $fc, 20
    .byte $fe
    .text "S"
    .byte $ff
    .text " Search"
    .byte 0

// Row 5: Diagonal movement + Rest
    .byte 0
    .byte $fe
    .text "B"
    .byte $ff
    .text " SW"
    .byte $fc, 10
    .byte $fe
    .text "N"
    .byte $ff
    .text " SE"
    .byte $fc, 20
    .byte $fe
    .text "."
    .byte $ff
    .text " Rest"
    .byte 0

// Row 6: Cursor info + Stairs
    .byte 0
    .text "Cursors also work "
    .byte $fe
    .text ">"
    .byte $ff
    .text " Down "
    .byte $fe
    .text "<"
    .byte $ff
    .text " Up"
    .byte 0

// Row 7: Running header + Go up stairs
    .byte 0
    .byte $fd
    .text "Running"
    .byte $ff
    .byte $fc, 20
    .byte $fe
    .text "<"
    .byte $ff
    .text " Go Up Stairs"
    .byte 0

// Row 8: Running instruction + Recall
    .byte 0
    .byte $fe
    .text "SHIFT+DIRECTION"
    .byte $ff
    .text "  "
    .byte $fe
    .text "/"
    .byte $ff
    .text " Recall"
    .byte 0

// Row 9: blank
    .byte 2
    .byte 0

// Row 10: Section headers (HEADER)
    .byte 1
    .text "Commands" ; .byte $fc, 20 ; .text "Combat" ; .byte 0

// Row 11: Get item + Walk into monster
    .byte 0
    .byte $fe
    .text "G"
    .byte $ff
    .text " Get Item"
    .byte $fc, 20
    .text "Walk into Mon"
    .byte 0

// Row 12: Drop item + Fire
    .byte 0
    .byte $fe
    .text "D"
    .byte $ff
    .text " Drop Item"
    .byte $fc, 20
    .byte $fe
    .text "SHIFT+F"
    .byte $ff
    .text " Fire"
    .byte 0

// Row 13: Inventory + Throw
    .byte 0
    .byte $fe
    .text "I"
    .byte $ff
    .text " Inventory"
    .byte $fc, 20
    .byte $fe
    .text "SHIFT+T"
    .byte $ff
    .text " Throw"
    .byte 0

// Row 14: Equipment + Eat
    .byte 0
    .byte $fe
    .text "E"
    .byte $ff
    .text " Equipment"
    .byte $fc, 20
    .byte $fe
    .text "SHIFT+E"
    .byte $ff
    .text " Eat"
    .byte 0

// Row 15: Wear/Wield + Refuel
    .byte 0
    .byte $fe
    .text "W"
    .byte $ff
    .text " Wear/Wield"
    .byte $fc, 20
    .byte $fe
    .text "SHIFT+R"
    .byte $ff
    .text " Refuel"
    .byte 0

// Row 16: Take off + Information header
    .byte 0
    .byte $fe
    .text "T"
    .byte $ff
    .text " Take Off"
    .byte $fc, 20
    .byte $fd
    .text "Information"
    .byte 0

// Row 17: Quaff potion + Character
    .byte 0
    .byte $fe
    .text "Q"
    .byte $ff
    .text " Quaff Potion"
    .byte $fc, 20
    .byte $fe
    .text "SHIFT+C"
    .byte $ff
    .text " Char"
    .byte 0

// Row 18: Read scroll + Look
    .byte 0
    .byte $fe
    .text "R"
    .byte $ff
    .text " Read Scroll"
    .byte $fc, 20
    .byte $fe
    .text "X"
    .byte $ff
    .text " Look"
    .byte 0

// Row 19: Aim wand + This help
    .byte 0
    .byte $fe
    .text "A"
    .byte $ff
    .text " Aim Wand"
    .byte $fc, 20
    .byte $fe
    .text "?"
    .byte $ff
    .text " This Help"
    .byte 0

// Row 20: Use staff + Other header
    .byte 0
    .byte $fe
    .text "Z"
    .byte $ff
    .text " Use Staff"
    .byte $fc, 20
    .byte $fd
    .text "Other"
    .byte 0

// Row 21: Cast spell + Pray
    .byte 0
    .byte $fe
    .text "M"
    .byte $ff
    .text " Cast Spell"
    .byte $fc, 20
    .byte $fe
    .text "P"
    .byte $ff
    .text " Pray"
    .byte 0

// Row 22: Study book + Save
    .byte 0
    .byte $fe
    .text "F"
    .byte $ff
    .text " Study Book"
    .byte $fc, 20
    .byte $fe
    .text "SHIFT+S"
    .byte $ff
    .text " Save"
    .byte 0

// Row 23: Bash + Tunnel + Quit
    .byte 0
    .byte $fe
    .text "SHIFT+D"
    .byte $ff
    .text " Bash/Dig "
    .byte $fe
    .text "+"
    .byte $ff
    .text " Tunnel "
    .byte $fe
    .text "SHIFT+Q"
    .byte $ff
    .text " Quit"
    .byte 0
