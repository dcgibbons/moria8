#importonce
// title_data.s — Title screen art data (standalone PRG)
//
// Assembles to out/title, loaded into MAP_BASE at startup.
// Format: segments of [row, col, color, screen_codes..., $00]
// Terminated by $FF end-of-data marker.
//
// Screen codes reference (C64 lowercase/uppercase charset):
//   $20 = space, $A0 = solid block (reverse space)
//   $2D = '-', $21 = '!', $2B = '+'
//   Box borders: + for corners, - for horizontal, ! for vertical

#if C128
.pc = $4000 "Title Art"
#else
.pc = $C000 "Title Art"
#endif
.encoding "screencode_mixed"

#import "../out/version_strings.inc"

.const TITLE_BORDER_COL = 1
.const TITLE_INNER_COL = TITLE_BORDER_COL + 1
.const TITLE_INNER_WIDTH = 36

// Color constants (must match screen.s — standalone file)
.const TC_BLACK  = $00
.const TC_WHITE  = $01
.const TC_CYAN   = $03
.const TC_YELLOW = $07
.const TC_DGREY  = $0b
.const TC_LGREY  = $0f

// ── Border top: row 1, col 1 ──
.byte 1, 1, TC_LGREY
.byte $2b  // +
.fill 36, $2d  // - × 36
.byte $2b  // +
.byte $00

// ── Left/right border for rows 2-18 ──
// Row 2
.byte 2, 1, TC_LGREY
.byte $21  // !
.byte $00
.byte 2, 38, TC_LGREY
.byte $21
.byte $00

// ── MORIA8 block letters: rows 3-7 (5 rows tall) ──
// Letters: M(5w) O(3w) R(4w) I(3w) A(4w) 8(3w) = 22 + 5 gaps of 2 = 32 wide
// Centered in 36-char interior: col = (36-32)/2 + 2 = 4 → col 4

// Row 3 (letter row 1)
.byte 3, 1, TC_LGREY
.byte $21  // !
.byte $00
.byte 3, 4, TC_WHITE
.byte $a0, $20, $20, $20, $a0  // M: █   █
.byte $20, $20                  // gap
.byte $a0, $a0, $a0             // O: ███
.byte $20, $20                  // gap
.byte $a0, $a0, $a0, $a0        // R: ████
.byte $20, $20                  // gap
.byte $a0, $a0, $a0             // I: ███
.byte $20, $20                  // gap
.byte $20, $a0, $a0, $20        // A:  ██
.byte $20, $20                  // gap
.byte $a0, $a0, $a0             // 8: ███
.byte $00
.byte 3, 38, TC_LGREY
.byte $21
.byte $00

// Row 4 (letter row 2)
.byte 4, 1, TC_LGREY
.byte $21
.byte $00
.byte 4, 4, TC_WHITE
.byte $a0, $a0, $20, $a0, $a0  // M: ██ ██
.byte $20, $20                  // gap
.byte $a0, $20, $a0             // O: █ █
.byte $20, $20                  // gap
.byte $a0, $20, $20, $a0        // R: █  █
.byte $20, $20                  // gap
.byte $20, $a0, $20             // I:  █
.byte $20, $20                  // gap
.byte $a0, $20, $20, $a0        // A: █  █
.byte $20, $20                  // gap
.byte $a0, $20, $a0             // 8: █ █
.byte $00
.byte 4, 38, TC_LGREY
.byte $21
.byte $00

// Row 5 (letter row 3)
.byte 5, 1, TC_LGREY
.byte $21
.byte $00
.byte 5, 4, TC_WHITE
.byte $a0, $20, $a0, $20, $a0  // M: █ █ █
.byte $20, $20                  // gap
.byte $a0, $20, $a0             // O: █ █
.byte $20, $20                  // gap
.byte $a0, $a0, $a0, $a0        // R: ████
.byte $20, $20                  // gap
.byte $20, $a0, $20             // I:  █
.byte $20, $20                  // gap
.byte $a0, $a0, $a0, $a0        // A: ████
.byte $20, $20                  // gap
.byte $a0, $a0, $a0             // 8: ███
.byte $00
.byte 5, 38, TC_LGREY
.byte $21
.byte $00

// Row 6 (letter row 4)
.byte 6, 1, TC_LGREY
.byte $21
.byte $00
.byte 6, 4, TC_WHITE
.byte $a0, $20, $20, $20, $a0  // M: █   █
.byte $20, $20                  // gap
.byte $a0, $20, $a0             // O: █ █
.byte $20, $20                  // gap
.byte $a0, $a0, $20, $20        // R: ██
.byte $20, $20                  // gap
.byte $20, $a0, $20             // I:  █
.byte $20, $20                  // gap
.byte $a0, $20, $20, $a0        // A: █  █
.byte $20, $20                  // gap
.byte $a0, $20, $a0             // 8: █ █
.byte $00
.byte 6, 38, TC_LGREY
.byte $21
.byte $00

// Row 7 (letter row 5)
.byte 7, 1, TC_LGREY
.byte $21
.byte $00
.byte 7, 4, TC_WHITE
.byte $a0, $20, $20, $20, $a0  // M: █   █
.byte $20, $20                  // gap
.byte $a0, $a0, $a0             // O: ███
.byte $20, $20                  // gap
.byte $a0, $20, $a0, $a0        // R: █ ██
.byte $20, $20                  // gap
.byte $a0, $a0, $a0             // I: ███
.byte $20, $20                  // gap
.byte $a0, $20, $20, $a0        // A: █  █
.byte $20, $20                  // gap
.byte $a0, $a0, $a0             // 8: ███
.byte $00
.byte 7, 38, TC_LGREY
.byte $21
.byte $00

// ── Row 8: empty with borders ──
.byte 8, 1, TC_LGREY
.byte $21
.byte $00
.byte 8, 38, TC_LGREY
.byte $21
.byte $00

// ── Row 9: "THE DUNGEONS OF MORIA" ──
.byte 9, 1, TC_LGREY
.byte $21
.byte $00
.byte 9, 10, TC_YELLOW
.text "The Dungeons of Moria"
.byte $00
.byte 9, 38, TC_LGREY
.byte $21
.byte $00

// ── Row 10: divider ──
.byte 10, 1, TC_LGREY
.byte $2b  // +
.fill 36, $2d  // - × 36
.byte $2b  // +
.byte $00

// ── Row 11: empty with borders ──
.byte 11, 1, TC_LGREY
.byte $21
.byte $00
.byte 11, 38, TC_LGREY
.byte $21
.byte $00

// ── Row 12: platform edition ──
.byte 12, 1, TC_LGREY
.byte $21
.byte $00
#if C128
.byte 12, 9, TC_CYAN
.text "Commodore 128 Edition"
#elif PLUS4
.byte 12, 8, TC_CYAN
.text "Commodore Plus/4 Edition"
#else
.byte 12, 10, TC_CYAN
.text "Commodore 64 Edition"
#endif
.byte $00
.byte 12, 38, TC_LGREY
.byte $21
.byte $00

// ── Row 13: empty with borders ──
.byte 13, 1, TC_LGREY
.byte $21
.byte $00
.byte 13, TITLE_INNER_COL + ((TITLE_INNER_WIDTH - TITLE_VERSION_LEN) / 2), TC_DGREY
:EmitTitleVersion()
.byte $00
.byte 13, 38, TC_LGREY
.byte $21
.byte $00

// ── Row 14: credits ──
.byte 14, 1, TC_LGREY
.byte $21
.byte $00
.byte 14, 5, TC_DGREY
.text "Based on Moria by R.A. Koeneke"
.byte $00
.byte 14, 38, TC_LGREY
.byte $21
.byte $00

// ── Row 15: port credit ──
.byte 15, 1, TC_LGREY
.byte $21
.byte $00
#if C128
.byte 15, 7, TC_DGREY
.text "C128 port by Chad Gibbons"
#elif PLUS4
.byte 15, 6, TC_DGREY
.text "Plus/4 port by Chad Gibbons"
#else
.byte 15, 8, TC_DGREY
.text "C64 port by Chad Gibbons"
#endif
.byte $00
.byte 15, 38, TC_LGREY
.byte $21
.byte $00

// ── Row 16: divider ──
.byte 16, 1, TC_LGREY
.byte $2b  // +
.fill 36, $2d  // - × 36
.byte $2b  // +
.byte $00

// ── Rows 17-18: menu area (left empty for main.s to fill) ──
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

// ── Row 19: border bottom ──
.byte 19, 1, TC_LGREY
.byte $2b  // +
.fill 36, $2d  // - × 36
.byte $2b  // +
.byte $00

// ── End of data ──
.byte $ff
