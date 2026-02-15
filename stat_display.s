// stat_display.s — Stat value display helper
//
// Extracted from player_create.s so it remains in main RAM.
// Called by ui_character.s ($F000) and player_create.s ($E000 overlay)
// — both accessible since main RAM is always visible.

// put_stat_val — Display a stat value with 18/xx support
// Single-byte encoding: 3-18 literal, 19-118 = 18/01 through 18/100.
// Input:  A = stat value (3-118)
// If A <= 18: prints value right-justified in 2 chars
// If A == 118: prints "18/00" (18/100 convention)
// If A 19-117: prints "18/XX" where XX = A - 18
// Preserves: nothing
put_stat_val:
    cmp #19
    bcs !exceptional+
    // Normal stat 3-18
    jmp screen_put_decimal_rj2
!exceptional:
    // 18/xx display
    pha
    lda #18
    jsr screen_put_decimal  // Print "18"
    lda #$2f                // '/'
    jsr screen_put_char
    pla
    cmp #118                // 18/100?
    bne !not_100+
    lda #0                  // 18/100 displays as "00"
    jmp screen_put_decimal_lz2
!not_100:
    sec
    sbc #18                 // xx = stat - 18
    jmp screen_put_decimal_lz2
