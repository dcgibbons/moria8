#importonce
// title_data_cx16.s — Commander X16 title screen art data (standalone PRG at $A000)

.pc = $A000 "Title Art"
.encoding "screencode_mixed"

#import "../../build/version_strings.inc"

.const TITLE_BORDER_COL = 1
.const TITLE_INNER_COL = TITLE_BORDER_COL + 1
.const TITLE_INNER_WIDTH = 36

.const TC_BLACK  = $00
.const TC_WHITE  = $01
.const TC_CYAN   = $03
.const TC_YELLOW = $07
.const TC_DGREY  = $0b
.const TC_LGREY  = $0f

// ── Border top: row 1, col 1 ──
.byte 1, 1, TC_LGREY
.byte $2b
.fill 36, $2d
.byte $2b
.byte $00

// Row 2
.byte 2, 1, TC_LGREY
.byte $21
.byte $00
.byte 2, 38, TC_LGREY
.byte $21
.byte $00

// Row 3 (letter row 1)
.byte 3, 1, TC_LGREY
.byte $21
.byte $00
.byte 3, 4, TC_WHITE
.byte $a0, $20, $20, $20, $a0
.byte $20, $20
.byte $a0, $a0, $a0
.byte $20, $20
.byte $a0, $a0, $a0, $a0
.byte $20, $20
.byte $a0, $a0, $a0
.byte $20, $20
.byte $20, $a0, $a0, $20
.byte $20, $20
.byte $a0, $a0, $a0
.byte $00
.byte 3, 38, TC_LGREY
.byte $21
.byte $00

// Row 4 (letter row 2)
.byte 4, 1, TC_LGREY
.byte $21
.byte $00
.byte 4, 4, TC_WHITE
.byte $a0, $a0, $20, $a0, $a0
.byte $20, $20
.byte $a0, $20, $a0
.byte $20, $20
.byte $a0, $20, $20, $a0
.byte $20, $20
.byte $20, $a0, $20
.byte $20, $20
.byte $a0, $20, $20, $a0
.byte $20, $20
.byte $a0, $20, $a0
.byte $00
.byte 4, 38, TC_LGREY
.byte $21
.byte $00

// Row 5 (letter row 3)
.byte 5, 1, TC_LGREY
.byte $21
.byte $00
.byte 5, 4, TC_WHITE
.byte $a0, $20, $a0, $20, $a0
.byte $20, $20
.byte $a0, $20, $a0
.byte $20, $20
.byte $a0, $a0, $a0, $a0
.byte $20, $20
.byte $20, $a0, $20
.byte $20, $20
.byte $a0, $a0, $a0, $a0
.byte $20, $20
.byte $a0, $a0, $a0
.byte $00
.byte 5, 38, TC_LGREY
.byte $21
.byte $00

// Row 6 (letter row 4)
.byte 6, 1, TC_LGREY
.byte $21
.byte $00
.byte 6, 4, TC_WHITE
.byte $a0, $20, $20, $20, $a0
.byte $20, $20
.byte $a0, $20, $a0
.byte $20, $20
.byte $a0, $a0, $20, $20
.byte $20, $20
.byte $20, $a0, $20
.byte $20, $20
.byte $a0, $20, $20, $a0
.byte $20, $20
.byte $a0, $20, $a0
.byte $00
.byte 6, 38, TC_LGREY
.byte $21
.byte $00

// Row 7 (letter row 5)
.byte 7, 1, TC_LGREY
.byte $21
.byte $00
.byte 7, 4, TC_WHITE
.byte $a0, $20, $20, $20, $a0
.byte $20, $20
.byte $a0, $a0, $a0
.byte $20, $20
.byte $a0, $20, $a0, $a0
.byte $20, $20
.byte $a0, $a0, $a0
.byte $20, $20
.byte $a0, $20, $20, $a0
.byte $20, $20
.byte $a0, $a0, $a0
.byte $00
.byte 7, 38, TC_LGREY
.byte $21
.byte $00

// Row 8: empty with borders
.byte 8, 1, TC_LGREY
.byte $21
.byte $00
.byte 8, 38, TC_LGREY
.byte $21
.byte $00

// Row 9: "THE DUNGEONS OF MORIA"
.byte 9, 1, TC_LGREY
.byte $21
.byte $00
.byte 9, 10, TC_YELLOW
.text "The Dungeons of Moria"
.byte $00
.byte 9, 38, TC_LGREY
.byte $21
.byte $00

// Row 10: divider
.byte 10, 1, TC_LGREY
.byte $2b
.fill 36, $2d
.byte $2b
.byte $00

// Row 11: empty with borders
.byte 11, 1, TC_LGREY
.byte $21
.byte $00
.byte 11, 38, TC_LGREY
.byte $21
.byte $00

// Row 12: platform edition
.byte 12, 1, TC_LGREY
.byte $21
.byte $00
.byte 12, 9, TC_CYAN
.text "Commander X16 Edition"
.byte $00
.byte 12, 38, TC_LGREY
.byte $21
.byte $00

// Row 13: version
.byte 13, 1, TC_LGREY
.byte $21
.byte $00
.byte 13, TITLE_INNER_COL + ((TITLE_INNER_WIDTH - TITLE_VERSION_LEN) / 2), TC_DGREY
:EmitTitleVersion()
.byte $00
.byte 13, 38, TC_LGREY
.byte $21
.byte $00

// Row 14: credits
.byte 14, 1, TC_LGREY
.byte $21
.byte $00
.byte 14, 5, TC_DGREY
.text "Based on Moria by R.A. Koeneke"
.byte $00
.byte 14, 38, TC_LGREY
.byte $21
.byte $00

// Row 15: port credit
.byte 15, 1, TC_LGREY
.byte $21
.byte $00
.byte 15, 7, TC_DGREY
.text "CX16 port by Chad Gibbons"
.byte $00
.byte 15, 38, TC_LGREY
.byte $21
.byte $00

// Row 16: divider
.byte 16, 1, TC_LGREY
.byte $2b
.fill 36, $2d
.byte $2b
.byte $00

// Rows 17-18: menu area
.byte 17, 1, TC_LGREY
.byte $21
.byte $00
.byte 17, 38, TC_LGREY
.byte $21
.byte $00

.byte 18, 1, TC_LGREY
.byte $21
.byte $00
.byte 18, 38, TC_LGREY
.byte $21
.byte $00

// Row 19: border bottom
.byte 19, 1, TC_LGREY
.byte $2b
.fill 36, $2d
.byte $2b
.byte $00

// End of data
.byte $ff
