// title_data.s — Title screen art data (standalone PRG)
//
// Assembles to out/title, loaded into MAP_BASE ($C000) at startup.
// Format: segments of [row, col, color, screen_codes..., $00]
// Terminated by $FF end-of-data marker.
//
// Screen codes reference (C64 unshifted charset):
//   $20 = space, $A0 = solid block (reverse space)
//   $40 = ─, $5d = │
//   $70 = ┌, $6e = ┐, $6d = └, $7d = ┘
//   $6b = ├, $73 = ┤

.pc = $C000 "Title Art"
.encoding "screencode_upper"

// Color constants (must match screen.s — standalone file)
.const TC_BLACK  = $00
.const TC_WHITE  = $01
.const TC_CYAN   = $03
.const TC_YELLOW = $07
.const TC_DGREY  = $0b
.const TC_LGREY  = $0f

// ── Border top: row 1, col 1 ──
.byte 1, 1, TC_LGREY
.byte $70  // ┌
.fill 36, $40  // ─ × 36
.byte $6e  // ┐
.byte $00

// ── Left/right border for rows 2-18 ──
// Row 2
.byte 2, 1, TC_LGREY
.byte $5d  // │
.byte $00
.byte 2, 38, TC_LGREY
.byte $5d
.byte $00

// ── MORIA block letters: rows 3-5 ──
// Letters: M(5w) O(3w) R(4w) I(3w) A(4w) = 19 + 4 gaps of 2 = 27 wide
// Centered in 36-char interior: col = (36-27)/2 + 2 = 6.5 → col 7
// Row 3 (top)
.byte 3, 1, TC_LGREY
.byte $5d  // │
.byte $00
.byte 3, 7, TC_WHITE
.byte $a0, $a0, $20, $a0, $a0  // M: ██ ██
.byte $20, $20                  // gap
.byte $a0, $a0, $a0             // O: ███
.byte $20, $20                  // gap
.byte $a0, $a0, $a0, $a0        // R: ████
.byte $20, $20                  // gap
.byte $a0, $a0, $a0             // I: ███
.byte $20, $20                  // gap
.byte $20, $a0, $a0, $20        // A:  ██
.byte $00
.byte 3, 38, TC_LGREY
.byte $5d
.byte $00

// Row 4 (middle)
.byte 4, 1, TC_LGREY
.byte $5d
.byte $00
.byte 4, 7, TC_WHITE
.byte $a0, $20, $a0, $20, $a0  // M: █ █ █
.byte $20, $20                  // gap
.byte $a0, $20, $a0             // O: █ █
.byte $20, $20                  // gap
.byte $a0, $a0, $20, $20        // R: ██
.byte $20, $20                  // gap
.byte $20, $a0, $20             // I:  █
.byte $20, $20                  // gap
.byte $a0, $a0, $a0, $a0        // A: ████
.byte $00
.byte 4, 38, TC_LGREY
.byte $5d
.byte $00

// Row 5 (bottom)
.byte 5, 1, TC_LGREY
.byte $5d
.byte $00
.byte 5, 7, TC_WHITE
.byte $a0, $20, $20, $20, $a0  // M: █   █
.byte $20, $20                  // gap
.byte $a0, $a0, $a0             // O: ███
.byte $20, $20                  // gap
.byte $a0, $20, $a0, $a0        // R: █ ██
.byte $20, $20                  // gap
.byte $a0, $a0, $a0             // I: ███
.byte $20, $20                  // gap
.byte $a0, $20, $20, $a0        // A: █  █
.byte $00
.byte 5, 38, TC_LGREY
.byte $5d
.byte $00

// ── Row 6: empty with borders ──
.byte 6, 1, TC_LGREY
.byte $5d
.byte $00
.byte 6, 38, TC_LGREY
.byte $5d
.byte $00

// ── Row 7: "THE DUNGEONS OF MORIA" ──
.byte 7, 1, TC_LGREY
.byte $5d
.byte $00
.byte 7, 10, TC_YELLOW
.text "THE DUNGEONS OF MORIA"
.byte $00
.byte 7, 38, TC_LGREY
.byte $5d
.byte $00

// ── Row 8: empty with borders ──
.byte 8, 1, TC_LGREY
.byte $5d
.byte $00
.byte 8, 38, TC_LGREY
.byte $5d
.byte $00

// ── Row 9: divider ──
.byte 9, 1, TC_LGREY
.byte $6b  // ├
.fill 36, $40  // ─ × 36
.byte $73  // ┤
.byte $00

// ── Row 10: empty with borders ──
.byte 10, 1, TC_LGREY
.byte $5d
.byte $00
.byte 10, 38, TC_LGREY
.byte $5d
.byte $00

// ── Row 11: "COMMODORE 64 EDITION" ──
.byte 11, 1, TC_LGREY
.byte $5d
.byte $00
.byte 11, 10, TC_CYAN
.text "COMMODORE 64 EDITION"
.byte $00
.byte 11, 38, TC_LGREY
.byte $5d
.byte $00

// ── Row 12: empty with borders ──
.byte 12, 1, TC_LGREY
.byte $5d
.byte $00
.byte 12, 38, TC_LGREY
.byte $5d
.byte $00

// ── Row 13: credits ──
.byte 13, 1, TC_LGREY
.byte $5d
.byte $00
.byte 13, 4, TC_DGREY
.text "BASED ON UMORIA BY R.A. KOENEKE"
.byte $00
.byte 13, 38, TC_LGREY
.byte $5d
.byte $00

// ── Row 14: empty with borders ──
.byte 14, 1, TC_LGREY
.byte $5d
.byte $00
.byte 14, 38, TC_LGREY
.byte $5d
.byte $00

// ── Row 15: divider ──
.byte 15, 1, TC_LGREY
.byte $6b  // ├
.fill 36, $40  // ─ × 36
.byte $73  // ┤
.byte $00

// ── Rows 16-18: menu area (left empty for main.s to fill) ──
.byte 16, 1, TC_LGREY
.byte $5d
.byte $00
.byte 16, 38, TC_LGREY
.byte $5d
.byte $00

.byte 17, 1, TC_LGREY
.byte $5d
.byte $00
.byte 17, 38, TC_LGREY
.byte $5d
.byte $00

.byte 18, 1, TC_LGREY
.byte $5d
.byte $00
.byte 18, 38, TC_LGREY
.byte $5d
.byte $00

// ── Row 19: border bottom ──
.byte 19, 1, TC_LGREY
.byte $6d  // └
.fill 36, $40  // ─ × 36
.byte $7d  // ┘
.byte $00

// ── End of data ──
.byte $ff
