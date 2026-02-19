#importonce
// ui_help_data.s — Help screen string data (main RAM)
//
// Separated from ui_help.s so string data lives in main RAM
// while the rendering code stays in the banked $F000 region.
// Data is read via indirect addressing from banked code.

// Uses raw hex values for constants defined in ui_help.s:
//   BOX: $70=TL $6e=TR $6d=BL $7d=BR $40=H $5d=V
//   Color toggles: $fd=CH(cyan) $fe=CK(white) $ff=CD(lgrey)
//   Line types: 0=CONTENT 1=HEADER 2=BLANK

// ============================================================
// Border strings (full 40-char rows)
// ============================================================
help_border_top:
    .byte $70                       // BOX_TL
    .fill 8, $40                    // BOX_H
    .byte $20
    .text "COMMAND REFERENCE"
    .byte $20
    .fill 11, $40                   // BOX_H
    .byte $6e                       // BOX_TR
    .byte 0

help_border_bot:
    .byte $6d                       // BOX_BL
    .fill 8, $40                    // BOX_H
    .byte $20
    .text "PRESS ANY KEY"
    .byte $20
    .fill 15, $40                   // BOX_H
    .byte $7d                       // BOX_BR
    .byte 0

help_title_str:
    .text "COMMAND REFERENCE" ; .byte 0

// ============================================================
// Content strings (rows 1-23)
// ============================================================

// Row 1: Section headers (HTYPE_HEADER — drawn in CYAN)
help_l1:
    .text "MOVEMENT          ACTIONS" ; .byte 0

// Row 2: Movement keys + Open door
help_l2:
    .byte $fe
    .text "H"
    .byte $ff
    .text " LEFT  "
    .byte $fe
    .text "L"
    .byte $ff
    .text " RIGHT   "
    .byte $fe
    .text "O"
    .byte $ff
    .text " OPEN DOOR"
    .byte 0

// Row 3: Movement keys + Close door
help_l3:
    .byte $fe
    .text "K"
    .byte $ff
    .text " UP    "
    .byte $fe
    .text "J"
    .byte $ff
    .text " DOWN    "
    .byte $fe
    .text "C"
    .byte $ff
    .text " CLOSE DOOR"
    .byte 0

// Row 4: Diagonal movement + Search
help_l4:
    .byte $fe
    .text "Y"
    .byte $ff
    .text " NW    "
    .byte $fe
    .text "U"
    .byte $ff
    .text " NE      "
    .byte $fe
    .text "S"
    .byte $ff
    .text " SEARCH"
    .byte 0

// Row 5: Diagonal movement + Rest
help_l5:
    .byte $fe
    .text "B"
    .byte $ff
    .text " SW    "
    .byte $fe
    .text "N"
    .byte $ff
    .text " SE      "
    .byte $fe
    .text "."
    .byte $ff
    .text " REST"
    .byte 0

// Row 6: Cursor info + Stairs
help_l6:
    .text "CURSORS ALSO WORK "
    .byte $fe
    .text ">"
    .byte $ff
    .text " DOWN "
    .byte $fe
    .text "<"
    .byte $ff
    .text " UP"
    .byte 0

// Row 7: Running header + Go up stairs
help_l7:
    .byte $fd
    .text "RUNNING"
    .byte $ff
    .text "           "
    .byte $fe
    .text "<"
    .byte $ff
    .text " GO UP STAIRS"
    .byte 0

// Row 8: Running instruction
help_l8:
    .byte $fe
    .text "SHIFT+DIRECTION"
    .byte 0

// Row 9: blank (HTYPE_BLANK)
help_l9:
    .byte 0

// Row 10: Section headers (HTYPE_HEADER)
help_l10:
    .text "COMMANDS          COMBAT" ; .byte 0

// Row 11: Get item + Walk into monster
help_l11:
    .byte $fe
    .text "G"
    .byte $ff
    .text " GET ITEM        WALK INTO MON"
    .byte 0

// Row 12: Drop item + Fire
help_l12:
    .byte $fe
    .text "D"
    .byte $ff
    .text " DROP ITEM       "
    .byte $fe
    .text "SHIFT+F"
    .byte $ff
    .text " FIRE"
    .byte 0

// Row 13: Inventory + Throw
help_l13:
    .byte $fe
    .text "I"
    .byte $ff
    .text " INVENTORY       "
    .byte $fe
    .text "SHIFT+T"
    .byte $ff
    .text " THROW"
    .byte 0

// Row 14: Equipment + Eat
help_l14:
    .byte $fe
    .text "E"
    .byte $ff
    .text " EQUIPMENT       "
    .byte $fe
    .text "SHIFT+E"
    .byte $ff
    .text " EAT"
    .byte 0

// Row 15: Wear/Wield + Refuel
help_l15:
    .byte $fe
    .text "W"
    .byte $ff
    .text " WEAR/WIELD      "
    .byte $fe
    .text "SHIFT+R"
    .byte $ff
    .text " REFUEL"
    .byte 0

// Row 16: Take off + Information header
help_l16:
    .byte $fe
    .text "T"
    .byte $ff
    .text " TAKE OFF        "
    .byte $fd
    .text "INFORMATION"
    .byte 0

// Row 17: Quaff potion + Character
help_l17:
    .byte $fe
    .text "Q"
    .byte $ff
    .text " QUAFF POTION    "
    .byte $fe
    .text "SHIFT+C"
    .byte $ff
    .text " CHAR"
    .byte 0

// Row 18: Read scroll + Look
help_l18:
    .byte $fe
    .text "R"
    .byte $ff
    .text " READ SCROLL     "
    .byte $fe
    .text "X"
    .byte $ff
    .text " LOOK"
    .byte 0

// Row 19: Aim wand + This help
help_l19:
    .byte $fe
    .text "A"
    .byte $ff
    .text " AIM WAND        "
    .byte $fe
    .text "?"
    .byte $ff
    .text " THIS HELP"
    .byte 0

// Row 20: Use staff + Other header
help_l20:
    .byte $fe
    .text "Z"
    .byte $ff
    .text " USE STAFF       "
    .byte $fd
    .text "OTHER"
    .byte 0

// Row 21: Cast spell + Pray
help_l21:
    .byte $fe
    .text "M"
    .byte $ff
    .text " CAST SPELL      "
    .byte $fe
    .text "P"
    .byte $ff
    .text " PRAY"
    .byte 0

// Row 22: Study book + Save
help_l22:
    .byte $fe
    .text "F"
    .byte $ff
    .text " STUDY BOOK      "
    .byte $fe
    .text "SHIFT+S"
    .byte $ff
    .text " SAVE"
    .byte 0

// Row 23: Bash + Quit
help_l23:
    .byte $fe
    .text "SHIFT+D"
    .byte $ff
    .text " BASH       "
    .byte $fe
    .text "SHIFT+Q"
    .byte $ff
    .text " QUIT"
    .byte 0

// ============================================================
// Line type table (23 entries, rows 1-23)
// ============================================================
help_line_type:
    .byte 1                                     // row 1:  MOVEMENT / ACTIONS (HEADER)
    .byte 0, 0                                  // rows 2-3  (CONTENT)
    .byte 0, 0                                  // rows 4-5
    .byte 0, 0                                  // rows 6-7
    .byte 0                                     // row 8
    .byte 2                                     // row 9:  (BLANK)
    .byte 1                                     // row 10: COMMANDS / COMBAT (HEADER)
    .byte 0, 0                                  // rows 11-12
    .byte 0, 0                                  // rows 13-14
    .byte 0, 0                                  // rows 15-16
    .byte 0, 0                                  // rows 17-18
    .byte 0, 0                                  // rows 19-20
    .byte 0, 0                                  // rows 21-22
    .byte 0                                     // row 23

// ============================================================
// Pointer tables (lo/hi split, 23 entries)
// ============================================================
help_line_ptrs_lo:
    .byte <help_l1,  <help_l2,  <help_l3,  <help_l4,  <help_l5
    .byte <help_l6,  <help_l7,  <help_l8,  <help_l9,  <help_l10
    .byte <help_l11, <help_l12, <help_l13, <help_l14, <help_l15
    .byte <help_l16, <help_l17, <help_l18, <help_l19, <help_l20
    .byte <help_l21, <help_l22, <help_l23

help_line_ptrs_hi:
    .byte >help_l1,  >help_l2,  >help_l3,  >help_l4,  >help_l5
    .byte >help_l6,  >help_l7,  >help_l8,  >help_l9,  >help_l10
    .byte >help_l11, >help_l12, >help_l13, >help_l14, >help_l15
    .byte >help_l16, >help_l17, >help_l18, >help_l19, >help_l20
    .byte >help_l21, >help_l22, >help_l23
