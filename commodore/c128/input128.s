#importonce
// input128.s — Keyboard input and command parsing (C128)
//
// Reads CIA1 keyboard matrix directly — bypasses Screen Editor entirely.
// Does NOT call SCNKEY ($FF9F) or GETIN ($FFE4).

#import "../common/input_contract.s"
#import "../common/input_tables.s"
#import "../common/input_run_cancel.s"
//
// Problem: SCNKEY invokes the Screen Editor, which reinitializes
// $0314/$0315 to its own IRQ handler on every call. The Screen Editor's
// IRQ handler then follows $03xx indirect vectors that may point into
// game data (e.g., item tables at $5020), causing a JAM.
//
// Fix: Direct CIA1 scan
//   Drive each of 8 keyboard rows via CIA1 Port A ($DC00), read columns
//   via Port B ($DC01). Convert raw scan code to PETSCII via lookup table.
//   SHIFT state detected directly from the matrix.
//   No KERNAL calls → no Screen Editor → no $0314 corruption.
//
// Maps PETSCII key codes to internal command IDs.

// Keyboard buffer count ($D0 on C128 — written 0 in input_get_command to flush;
// not used for scanning with the CIA1 direct path)
.const KBDBUF_COUNT = $d0

// CIA1 keyboard hardware registers
.const CIA1_PORTA = $DC00   // Row drive (write): 0 in a bit selects that row
.const CIA1_PORTB = $DC01   // Column read: 0 = key pressed (active low)
.const CIA1_DDRA  = $DC02
.const CIA1_DDRB  = $DC03
.const C128_KBD_EXT = $D02F // Extended keyboard line drive (bit6=line8, bit7=line9)

// Virtual key codes for C128 extended keypad keys (rows 8/9).
// Chosen from currently-unused PETSCII range in this project path.
.const KEY_ALT      = $a0
.const KEY_KP0      = $a1
.const KEY_KP1      = $a2
.const KEY_KP2      = $a3
.const KEY_KP3      = $a4
.const KEY_KP4      = $a5
.const KEY_KP5      = $a6
.const KEY_KP6      = $a7
.const KEY_KP7      = $a8
.const KEY_KP8      = $a9
.const KEY_KP9      = $aa
.const KEY_KP_PLUS  = $ab
.const KEY_KP_MINUS = $ac
.const KEY_KP_DOT   = $ad
.const KEY_ESC      = $ae
.const KEY_LF       = $af

// C128 runtime MMU mode used by game loop (all RAM, I/O visible)
.const INPUT_MMU_ALL_RAM  = $3e

// ============================================================
// Subroutines
// ============================================================

// input_run_key_held — Non-blocking: returns nonzero if any non-modifier key is
// physically down. Running arming/cancel phase policy stays shared.
// Output: A = nonzero if key pressed, 0 if no key
// Destroys: A, X, Y
input_run_key_held:
    jmp input_run_scan_held_raw
input_run_key_check:
    jmp input_run_key_held

// input_run_cancel_check — Non-blocking: returns nonzero only on a new key-down edge
// after running cancel has been armed. This avoids cancelling on lingering held state.
// Output: A = 1 on new key-down edge, 0 otherwise
// Destroys: A, X, Y
input_run_cancel_check:
    jsr input_run_scan_held_raw
    jmp input_run_process_sample

// input_get_key — Wait for a keypress via direct CIA1 scan
// Does not invoke SCNKEY, GETIN, or the Screen Editor.
// Uses strict 2-sample press/release stabilization because this entry point is
// used primarily by secondary prompts and dismiss screens, where accidental
// phantom presses are worse UX than 1-sample latency.
// Output: A = PETSCII code of key pressed
// Preserves: X, Y
input_get_key:
#if C128_TEST_SCRIPTED_INPUT || C128_TEST_SCRIPTED_SPELL || C128_TEST_SCRIPTED_PRAYER || C128_TEST_SCRIPTED_SPELL_CANCEL || C128_TEST_SCRIPTED_BOOK_OVERLAY || C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY || C128_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    ldx c128_test_input_idx
    lda c128_test_input_script,x
    bne !igk_script_ok+
    brk                     // Script exhaustion is a hard test failure.
!igk_script_ok:
    inx
    stx c128_test_input_idx
    rts
#else
#if C128_REAL_BOOT_DIAG
    ldx #$81
    jsr c128_stack_guard_begin
#endif
    // Re-assert game MMU mode and keep Screen Editor blink disabled.
    // If any prior KERNAL path leaked MMU/ROM state, waiting for a key here
    // must not run the Screen Editor IRQ path that can touch VDC RAM.
    jsr c128_restore_runtime_vectors
#if C128_REAL_BOOT_DIAG
    ldx #$82
    jsr c128_stack_guard_check
#endif

    txa
    pha                     // Save X
    tya
    pha                     // Save Y

!igk_wait:
    inc zp_entropy
    jsr cia_scan_petscii
    jsr input_process_sample_strict
    beq !igk_wait-          // Wait for key-up -> key-down edge

!igk_return:
    sta igk_key
    pla
    tay                     // Restore Y
    pla
    tax                     // Restore X
    lda igk_key
    rts
#endif

igk_key: .byte 0
igk_last_sample: .byte 0
igk_stable: .byte 0
ips_raw_sample: .byte 0
csp_ctrl: .byte 0

// input_wait_release — Block until keyboard is released (C128 direct scan)
// Used before one-shot "press any key" prompts to avoid consuming
// a still-held selection key from the previous screen.
// Preserves: nothing
input_wait_release:
#if C128_TEST_SCRIPTED_INPUT || C128_TEST_SCRIPTED_SPELL || C128_TEST_SCRIPTED_PRAYER || C128_TEST_SCRIPTED_SPELL_CANCEL || C128_TEST_SCRIPTED_BOOK_OVERLAY || C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY || C128_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    rts
#else
#if C128_REAL_BOOT_DIAG
    ldx #$83
    jsr c128_stack_guard_begin
#endif
    // Same guard as input_get_key: release waits are long-lived and must
    // stay in game MMU mode with Screen Editor blink suppressed.
    jsr c128_restore_runtime_vectors
#if C128_REAL_BOOT_DIAG
    ldx #$84
    jsr c128_stack_guard_check
#endif
!iwr_wait:
    inc zp_entropy
    jsr cia_scan_petscii
    jsr input_process_sample
    lda igk_stable
    bne !iwr_wait-
    ora igk_last_sample
    bne !iwr_wait-
    sta igk_last_sample
    sta igk_stable
    rts
#endif

// input_poll_key_event — One CIA scan + edge processing
// Output: A = PETSCII on key-down edge, 0 otherwise
// Destroys: A, X, Y
input_poll_key_event:
    jsr cia_scan_petscii
    // Fall through into shared state machine for testability.

// input_process_sample — Edge/state machine step for one sampled key value
// Input:  A = sampled PETSCII (0 = no key)
// Output: A = PETSCII on key-down edge, 0 otherwise
input_process_sample:
    sta ips_raw_sample
    jsr input_normalize_fast_edge_sample
    cmp igk_last_sample
    beq !ips_stable+
    sta igk_last_sample
    beq !ips_none+          // first release sample (stabilize on next 0)
    lda igk_stable
    bne !ips_none+          // key change while another key stable: wait
    lda igk_last_sample
    sta igk_stable          // idle->press: accept immediately
    lda ips_raw_sample
    rts
!ips_none:
    lda #0
    rts

!ips_stable:
    cmp igk_stable
    beq !ips_none-          // No stable transition
    sta igk_stable
    beq !ips_none-          // Release edge (rearm only)
    lda ips_raw_sample
    rts                     // New stable key-down edge

// Normalize the two physical cursor-key families for the fast-path edge
// detector so a held cursor key does not retrigger when shift sampling jitters
// between shifted and unshifted PETSCII encodings.
input_normalize_fast_edge_sample:
    cmp #$91                // Cursor up shares the cursor-down key
    bne !infes_not_up+
    lda #$11
    rts
!infes_not_up:
    cmp #$9d                // Cursor left shares the cursor-right key
    bne !infes_done+
    lda #$1d
!infes_done:
    rts

// input_process_sample_strict — 2-sample stable press/release filter
// Input:  A = sampled PETSCII (0 = no key)
// Output: A = PETSCII on stable key-down edge, 0 otherwise
input_process_sample_strict:
    cmp igk_last_sample
    beq !ipss_repeat+
    sta igk_last_sample
    lda #0
    rts
!ipss_repeat:
    cmp igk_stable
    beq !ipss_none+
    sta igk_stable
    beq !ipss_none+
    rts
!ipss_none:
    lda #0
    rts

#if C128_TEST_SCRIPTED_INPUT || C128_TEST_SCRIPTED_SPELL || C128_TEST_SCRIPTED_PRAYER || C128_TEST_SCRIPTED_SPELL_CANCEL || C128_TEST_SCRIPTED_BOOK_OVERLAY || C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY || C128_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
c128_test_input_idx: .byte 0
c128_test_input_script:
#if C128_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    .byte $4c              // L = load from title
    .byte $59              // Y = accept Disk Setup drive-9 prompt if shown
    .byte $d3              // SHIFT+S = save in gameplay
#elif C128_TEST_SCRIPTED_SPELL
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $42              // B = mage
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $4d              // M = cast
    .byte $41              // A = first visible book in filtered prompt
    .byte $41              // A = Magic Missile
    .byte $4c              // L = east
    .byte $20              // SPACE = dismiss -MORE- / fizzle
    .byte $4d              // M = cast again
    .byte $41              // A = first visible book in filtered prompt
    .byte $41              // A = Magic Missile
    .byte $4c              // L = east
    .byte $20              // SPACE = dismiss -MORE- / fizzle
    .byte $4d              // M = cast again
    .byte $41              // A = first visible book in filtered prompt
    .byte $41              // A = Magic Missile
    .byte $4c              // L = east
    .byte $20              // SPACE = dismiss -MORE- / fizzle
    .byte $4d              // M = cast again
    .byte $41              // A = first visible book in filtered prompt
    .byte $41              // A = Magic Missile
    .byte $4c              // L = east
    .byte $20              // SPACE = dismiss -MORE- / fizzle
    .byte $4d              // M = cast again
    .byte $41              // A = first visible book in filtered prompt
    .byte $41              // A = Magic Missile
    .byte $4c              // L = east
    .byte $20              // SPACE = dismiss -MORE- / fizzle
    .byte $4d              // M = cast again
    .byte $41              // A = first visible book in filtered prompt
    .byte $41              // A = Magic Missile
    .byte $4c              // L = east
    .byte $20              // SPACE = dismiss -MORE- / fizzle
    .byte $4d              // M = cast again
    .byte $41              // A = first visible book in filtered prompt
    .byte $41              // A = Magic Missile
    .byte $4c              // L = east
    .byte $20              // SPACE = dismiss -MORE- / fizzle
    .byte $4d              // M = cast again
    .byte $41              // A = first visible book in filtered prompt
    .byte $41              // A = Magic Missile
    .byte $4c              // L = east
    .byte $20              // SPACE = dismiss -MORE- / fizzle
#elif C128_TEST_SCRIPTED_SPELL_CANCEL
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $42              // B = mage
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $4d              // M = cast
    .byte $41              // A = first visible book in filtered prompt
    .byte $3f              // ? = spell list
    .byte KEY_ESC          // ESC = cancel from list
#elif C128_TEST_SCRIPTED_BOOK_OVERLAY
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $42              // B = mage
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $4d              // M = cast
    .byte $3f              // ? = inventory overlay from book prompt
#elif C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $42              // B = mage
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $4d              // M = cast
    .byte $41              // A = first visible book in filtered prompt
    .byte $3f              // ? = spell list overlay
#elif C128_TEST_SCRIPTED_PRAYER
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $41              // A = priest
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $50              // P = pray
    .byte $41              // A = first visible prayer book
    .byte $43              // C = Bless
#elif C128_TEST_PERF_P1_TRACE_MODAL
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $41              // A = class
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $49              // I = inventory modal
    .byte $20              // SPACE = dismiss inventory
#elif C128_TEST_PERF_P1_TRACE_COMMAND
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $41              // A = class
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $53              // S = search; consumes a turn and forces redraw
#else
    .byte $4e              // N = New
    .byte $41              // A = race
    .byte $0d              // RETURN = accept stats
    .byte $41              // A = class
    .byte $41              // A = first name character
    .byte $0d              // RETURN = finish name
    .byte $42              // B = female
    .byte $20              // SPACE = dismiss summary
    .byte $4c              // L = move east toward store
    .byte $4c
    .byte $4c
    .byte $4c
    .byte $4c
    .byte $4c
    .byte $4c
    .byte $4c
#endif
    .byte $00
#endif

// cia_scan_petscii — Single CIA1 keyboard matrix scan
// Drives each of 8 rows via $DC00, reads columns from $DC01.
// Detects SHIFT (LSHIFT=row1/bit7, RSHIFT=row6/bit4) separately.
// Output: A = PETSCII code of pressed key, $00 if no key or unmapped
// Destroys: A, X, Y
cia_scan_petscii:
    php
    sei
    // Ensure CIA1 DDR is set for keyboard scanning.
    // Port A ($DC02) = $FF (all outputs — drives row select lines)
    // Port B ($DC03) = $00 (all inputs — reads column key state)
    // On C128, boot sequence or KERNAL calls may leave DDR in wrong state,
    // causing phantom key readings if Port B bits are set as outputs.
    lda #$ff
    sta CIA1_DDRA
    lda #$00
    sta CIA1_DDRB

    // Save extended keyboard drive register and force lines 8/9 idle-high.
    // We must always restore this register before returning.
    lda C128_KBD_EXT
    sta csp_ext_save
    ora #%11000000
    sta C128_KBD_EXT

    // Default shift state: unshifted ($80). Updated inline during row scan.
    lda #$80
    sta csp_shift
    lda #0
    sta csp_ctrl

    // Pre-detect shift state so both LSHIFT (row 1) and RSHIFT (row 6)
    // are known before scanning rows that contain movement letters (HJKL on row 4).
    // Without this pre-pass, right-shifted vi movement can decode as unshifted.
    lda #$FD            // Row 1 drive mask
    sta CIA1_PORTA
    nop
    nop
    lda CIA1_PORTB
    and #$80            // Active low: 0 = LSHIFT pressed
    bne !csp_shift_l_done+
    lda #$00
    sta csp_shift
!csp_shift_l_done:

    lda #$BF            // Row 6 drive mask
    sta CIA1_PORTA
    nop
    nop
    lda CIA1_PORTB
    and #$10            // Active low: 0 = RSHIFT pressed
    bne !csp_shift_r_done+
    lda #$00
    sta csp_shift
!csp_shift_r_done:

    // Pre-detect Ctrl so command normalization can use the same sampled
    // matrix state that produced the key edge, instead of racing a later
    // physical-key probe in input_get_command.
    lda #$7F            // Row 7 drive mask
    sta CIA1_PORTA
    nop
    nop
    lda CIA1_PORTB
    and #$04            // Active low: 0 = CTRL pressed
    bne !csp_ctrl_done+
    lda #1
    sta csp_ctrl
!csp_ctrl_done:

    // --- Scan all 8 rows for a non-shift key ---
    lda #$FE            // Row 0: bit 0 driven low
    ldx #0              // Row index (0–7)
!csp_row:
    sta CIA1_PORTA
    nop
    nop
    pha                 // Save drive mask (for SEC/ROL rotation below)
    lda CIA1_PORTB
    sta csp_row_raw
    // Detect/mask LSHIFT inline (row 1, bit 7)
    cpx #1
    bne !csp_mask1_done+
    lda csp_row_raw
    and #$80            // Active low: 0 = LSHIFT pressed
    bne !csp_no_lshift+
    lda #$00
    sta csp_shift
!csp_no_lshift:
    lda csp_row_raw
    ora #$80            // Force LSHIFT bit to unpressed (raw active-low domain)
    sta csp_row_raw
!csp_mask1_done:
    // Detect/mask RSHIFT inline (row 6, bit 4)
    cpx #6
    bne !csp_mask6_done+
    lda csp_row_raw
    and #$10            // Active low: 0 = RSHIFT pressed
    bne !csp_no_rshift+
    lda #$00
    sta csp_shift
!csp_no_rshift:
    lda csp_row_raw
    ora #$10            // Force RSHIFT bit to unpressed (raw active-low domain)
    sta csp_row_raw
!csp_mask6_done:
    // Mask CTRL inline (row 7, bit 2) so a stuck or phantom modifier sample
    // cannot become the "pressed key" the command loop rescans.
    cpx #7
    bne !csp_mask7_done+
    lda csp_row_raw
    ora #$04            // Force CTRL bit to unpressed in raw active-low domain
    sta csp_row_raw
!csp_mask7_done:
    lda csp_row_raw
    eor #$FF            // Active low -> 1=pressed
    // EOR refreshed the row state in A after CPX clobbered Z.
    bne !csp_key_found+ // Nonzero: at least one non-shift key in this row
    pla                 // No key: restore drive mask
    sec
    rol                 // Rotate 0-bit left: $FE→$FD→$FB→$F7→$EF→$DF→$BF→$7F
    inx
    cpx #8
    bcc !csp_row-

    // No key in CIA rows 0-7; scan extended C128 row 8 (line 8).
    lda #$ff
    sta CIA1_PORTA
    lda csp_ext_save
    ora #%11000000
    and #%10111111      // Drive line 8 low, keep line 9 high
    sta C128_KBD_EXT
    nop
    nop
    lda CIA1_PORTB
    eor #$FF            // Active low -> 1=pressed
    bne !csp_key_row8+

    // No key in row 8; scan extended row 9 (line 9).
    lda csp_ext_save
    ora #%11000000
    and #%01111111      // Drive line 9 low, keep line 8 high
    sta C128_KBD_EXT
    nop
    nop
    lda CIA1_PORTB
    eor #$FF            // Active low -> 1=pressed
    bne !csp_key_row9+

    // No key found in any row — restore state and return 0.
    lda #$FF
    sta CIA1_PORTA      // Deselect all rows (neutral state)
    lda csp_ext_save
    sta C128_KBD_EXT
    lda #0
    jmp !csp_return+

!csp_key_row8:
    sta csp_col_bits
    ldx #8
    jmp !csp_key_post_scan+

!csp_key_row9:
    sta csp_col_bits
    ldx #9
    jmp !csp_key_post_scan+

!csp_key_found:
    // A = column bits (1=pressed), X = row index
    sta csp_col_bits
    pla                 // Discard saved drive mask (done with row loop)

!csp_key_post_scan:
    // Restore CIA1 to neutral
    lda #$FF
    sta CIA1_PORTA
    lda csp_ext_save
    sta C128_KBD_EXT

    // Find lowest set bit → column index in Y
    ldy #0
!csp_find_col:
    lsr csp_col_bits    // Shift right; carry ← old bit 0
    bcs !csp_col_done+  // Carry set = this was the pressed column bit
    iny
    bne !csp_find_col-  // (loops; we know a bit is set so always terminates)
!csp_col_done:
    // Scan code = row * 8 + column (range 0–63)
    txa
    asl
    asl
    asl                 // A = row * 8
    sty csp_col_bits
    clc
    adc csp_col_bits    // A = scan code

    // Look up unshifted PETSCII in table
    tax
    lda cia_scancode_table,x
    beq !csp_return+    // 0 = key not used by game → return 0

    // Apply shift modifier
    ldy csp_shift
    bne !csp_ctrl_normalize+    // $80 = unshifted

    // Shifted: handle special cases for symbols that don't follow +$80 rule
    cmp #$2E            // unshifted . → shifted > ($3E)
    bne !csp_shift_not_dot+
    lda #$3E
    bne !csp_ctrl_normalize+    // (always taken)
!csp_shift_not_dot:
    cmp #$2C            // unshifted , → shifted < ($3C)
    bne !csp_shift_not_comma+
    lda #$3C
    bne !csp_ctrl_normalize+
!csp_shift_not_comma:
    cmp #$2F            // unshifted / → shifted ? ($3F)
    bne !csp_shift_not_hash+
    lda #$3F
    bne !csp_ctrl_normalize+
!csp_shift_not_hash:
    cmp #$33            // unshifted 3 → shifted # ($23)
    bne !csp_shift_default+
    lda #$23
    bne !csp_ctrl_normalize+
!csp_shift_default:
    ora #$80            // Letters ($41–$5A) + cursor keys ($11,$1D): add $80
!csp_ctrl_normalize:
    ldy csp_ctrl
    jsr input_normalize_ctrl_chords_with_state
!csp_return:
    plp
    rts

csp_shift:    .byte $80   // 0=shifted, $80=unshifted (initialized to unshifted)
csp_col_bits: .byte 0
csp_ext_save: .byte 0
csp_row_raw:  .byte 0

// ============================================================
// CIA1/C128 scan code (0–79) → unshifted PETSCII/virtual-key lookup table
// Scan code = row_index * 8 + column_bit_index
// 0 = key not used by game (will be ignored)
// C64/C128 keyboard matrix layout (row, col):
//   Row 0 (drive $FE): DEL RET  CRSR-R F7 F1 F3 F5 CRSR-D
//   Row 1 (drive $FD): 3   W    A      4  Z  S  E  LSHIFT
//   Row 2 (drive $FB): 5   R    D      6  C  F  T  X
//   Row 3 (drive $F7): 7   Y    G      8  B  H  U  V
//   Row 4 (drive $EF): 9   I    J      0  M  K  O  N
//   Row 5 (drive $DF): +   P    L      -  .  :  @  ,
//   Row 6 (drive $BF): £   *    ;   HOME  RSHIFT = ↑  /
//   Row 7 (drive $7F): 1   ←  CTRL     2  SPC C= Q  STOP
//   Row 8 (line8):     ALT KP8  KP5   KP2  KP4 KP7 KP1 KP0
//   Row 9 (line9):     ESC KP+  KP-   LF   KP9 KP6 KP3 KP.
// ============================================================
cia_scancode_table:
    // Row 0 (scan  0– 7): DEL RET CRSR-R F7 F1 F3 F5 CRSR-D
    .byte $14,  $0D,  $1D,  0,   0,   0,   0,   $11
    // Row 1 (scan  8–15): 3  W     A    4    Z    S    E   LSHIFT
    .byte $33,  $57,  $41,  $34, $5A, $53, $45, 0
    // Row 2 (scan 16–23): 5  R     D    6    C    F    T    X
    .byte $35,  $52,  $44,  $36, $43, $46, $54, $58
    // Row 3 (scan 24–31): 7  Y     G    8    B    H    U    V
    .byte $37,  $59,  $47,  $38, $42, $48, $55, $56
    // Row 4 (scan 32–39): 9  I     J    0    M    K    O    N
    .byte $39,  $49,  $4A,  $30, $4D, $4B, $4F, $4E
    // Row 5 (scan 40–47): +  P     L    -    .    :    @    ,
    .byte $2B,  $50,  $4C,  $2D, $2E, 0,   0,   $2C
    // Row 6 (scan 48–55): £  *     ;  HOME RSHIFT = ↑   /
    .byte 0,    0,    0,    0,   0,   0,   0,   $2F
    // Row 7 (scan 56–63): 1  ←  CTRL   2  SPC  C=   Q  STOP
    .byte $31,  0,    0,    $32, $20, 0,   $51, $03
    // Row 8 (scan 64–71): ALT KP8  KP5  KP2  KP4  KP7  KP1  KP0
    .byte KEY_ALT, KEY_KP8, KEY_KP5, KEY_KP2, KEY_KP4, KEY_KP7, KEY_KP1, KEY_KP0
    // Row 9 (scan 72–79): ESC KP+  KP-  LF   KP9  KP6  KP3  KP.
    .byte KEY_ESC, KEY_KP_PLUS, KEY_KP_MINUS, KEY_LF, KEY_KP9, KEY_KP6, KEY_KP3, KEY_KP_DOT

// input_get_command — Wait for a keypress, return command ID
// Output: A = command ID, zp_input_cmd = same, zp_input_count = 1
input_get_command:
    lda #1
    sta zp_input_count      // Default repeat count = 1

!get_key:
    jsr input_get_key_fast
!igc_got_key:
    jsr petscii_to_command
    cmp #CMD_NONE
    bne !got_cmd+
    jmp !get_key-           // Unknown key, try again

!got_cmd:
    sta zp_input_cmd
    rts

#if C128
// input_normalize_ctrl_chords_with_state — Pure normalization helper used by
// the unit test to cover the Ctrl+W chord rescue without requiring live CIA
// state.
// Input: A = PETSCII candidate, Y = 0 if Ctrl not held, nonzero if held
// Output: A = normalized PETSCII
input_normalize_ctrl_chords_with_state:
    cpy #0
    beq !inct_done+
    cmp #$57
    beq !inct_ctrl_w+
    cmp #$d7
    bne !inct_done+
!inct_ctrl_w:
    lda #$17
!inct_done:
    rts
#endif

#if C128_INPUT_TEST
// input_normalize_shifted_symbols_with_state — Pure helper for the test suite
// to cover C128 shifted-symbol normalization without a live CIA scan.
// Input: A = unshifted PETSCII, Y = 0 if unshifted, nonzero if shifted
// Output: A = normalized PETSCII
input_normalize_shifted_symbols_with_state:
    cpy #0
    beq !inss_done+
    cmp #$2E
    bne !inss_not_dot+
    lda #$3E
    rts
!inss_not_dot:
    cmp #$2C
    bne !inss_not_comma+
    lda #$3C
    rts
!inss_not_comma:
    cmp #$2F
    bne !inss_not_three+
    lda #$3F
    rts
!inss_not_three:
    cmp #$33
    bne !inss_default+
    lda #$23
    rts
!inss_default:
    ora #$80
!inss_done:
    rts
#endif

// input_get_key_fast — low-latency command-entry variant
// Uses the existing asymmetric edge policy for snappy primary gameplay input.
// Output: A = PETSCII code of key pressed
// Preserves: X, Y
input_get_key_fast:
#if C128_TEST_SCRIPTED_INPUT || C128_TEST_SCRIPTED_SPELL || C128_TEST_SCRIPTED_PRAYER || C128_TEST_SCRIPTED_SPELL_CANCEL || C128_TEST_SCRIPTED_BOOK_OVERLAY || C128_TEST_SCRIPTED_SPELL_LIST_OVERLAY || C128_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    jmp input_get_key
#else
#if C128_REAL_BOOT_DIAG
    ldx #$81
    jsr c128_stack_guard_begin
#endif
    jsr c128_restore_runtime_vectors
#if C128_REAL_BOOT_DIAG
    ldx #$82
    jsr c128_stack_guard_check
#endif

    txa
    pha
    tya
    pha

!igkf_wait:
    inc zp_entropy
    jsr input_poll_key_event
    beq !igkf_wait-

    sta igk_key
    pla
    tay
    pla
    tax
    lda igk_key
    rts
#endif

// petscii_to_command — Convert PETSCII key code to command ID
// Input:  A = PETSCII code
// Output: A = command ID
// Preserves: X, Y
petscii_to_command:
    ldx #0
!loop:
    cmp key_map_petscii,x
    beq !found+
    inx
    cpx #key_map_count
    bcc !loop-
    lda #CMD_NONE
    rts
!found:
    lda key_map_cmd,x
    rts

// ============================================================
// Key mapping table — identical to C64 (PETSCII is same on C128)
// ============================================================

key_map_petscii:
    :EmitBasePetsciiKeyMap()
    // C128 keypad/extended keys (virtual codes from cia_scancode_table rows 8/9)
    .byte KEY_KP8      // keypad 8 — north
    .byte KEY_KP2      // keypad 2 — south
    .byte KEY_KP4      // keypad 4 — west
    .byte KEY_KP6      // keypad 6 — east
    .byte KEY_KP7      // keypad 7 — northwest
    .byte KEY_KP9      // keypad 9 — northeast
    .byte KEY_KP1      // keypad 1 — southwest
    .byte KEY_KP3      // keypad 3 — southeast
    .byte KEY_KP5      // keypad 5 — rest
    .byte KEY_KP_PLUS  // keypad + — tunnel
    .byte KEY_ESC      // ESC — quit shortcut

key_map_cmd:
    :EmitBaseCommandKeyMap()
    // C128 keypad/extended key command mappings
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_MOVE_NW, CMD_MOVE_NE, CMD_MOVE_SW, CMD_MOVE_SE
    .byte CMD_REST, CMD_TUNNEL, CMD_QUIT

key_map_end:
.label key_map_count = key_map_cmd - key_map_petscii
.assert "Key map tables same size", key_map_count, key_map_end - key_map_cmd
