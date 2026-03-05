// input128.s — Keyboard input and command parsing (C128)
//
// Reads CIA1 keyboard matrix directly — bypasses Screen Editor entirely.
// Does NOT call SCNKEY ($FF9F) or GETIN ($FFE4).
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
// Command IDs — internal constants, not key codes
// ============================================================
.const CMD_NONE      = $00
.const CMD_MOVE_N    = $01
.const CMD_MOVE_S    = $02
.const CMD_MOVE_W    = $03
.const CMD_MOVE_E    = $04
.const CMD_MOVE_NW   = $05
.const CMD_MOVE_NE   = $06
.const CMD_MOVE_SW   = $07
.const CMD_MOVE_SE   = $08
.const CMD_STAIRS_DN = $09
.const CMD_STAIRS_UP = $0a
.const CMD_REST      = $0b
.const CMD_SEARCH    = $0c
.const CMD_OPEN      = $0d
.const CMD_CLOSE     = $0e
.const CMD_PICKUP    = $0f
.const CMD_DROP      = $10
.const CMD_INVENTORY = $11
.const CMD_EQUIPMENT = $12
.const CMD_WEAR      = $13
.const CMD_TAKEOFF   = $14
.const CMD_EAT       = $15
.const CMD_QUAFF     = $16
.const CMD_READ      = $17
.const CMD_AIM       = $18
.const CMD_USE       = $19
.const CMD_CAST      = $1a
.const CMD_PRAY      = $1b
.const CMD_CHAR_INFO = $1c
.const CMD_MAP       = $1d
.const CMD_RECALL    = $1e
.const CMD_LOOK      = $1f
.const CMD_RUN       = $20
.const CMD_SAVE      = $21
.const CMD_QUIT      = $22
.const CMD_HELP      = $23
.const CMD_VERSION   = $24
.const CMD_RUN_N     = $25
.const CMD_RUN_S     = $26
.const CMD_RUN_W     = $27
.const CMD_RUN_E     = $28
.const CMD_RUN_NW    = $29
.const CMD_RUN_NE    = $2a
.const CMD_RUN_SW    = $2b
.const CMD_RUN_SE    = $2c
.const CMD_GAIN      = $2d
.const CMD_FIRE      = $2e
.const CMD_THROW     = $2f
.const CMD_REFUEL    = $30
.const CMD_BASH      = $31
.const CMD_TUNNEL    = $32

// Direction offsets: dx, dy for each movement command
dir_dx: .byte  0,  0, -1, 1, -1, 1, -1, 1  // N S W E NW NE SW SE
dir_dy: .byte -1,  1,  0, 0, -1,-1,  1, 1
dir_opposite: .byte 1, 0, 3, 2, 7, 6, 5, 4

// ============================================================
// Subroutines
// ============================================================

// input_run_key_check — Non-blocking: returns nonzero if any key is currently pressed
// Used by run-cancel check in game_loop.s. C128 polls CIA directly (no KERNAL buffer).
// Output: A = nonzero (PETSCII) if key pressed, 0 if no key
// Destroys: A, X, Y
input_run_key_check:
    jsr cia_scan_petscii
    rts

// input_get_key — Wait for a keypress via direct CIA1 scan
// Does not invoke SCNKEY, GETIN, or the Screen Editor.
// Uses edge-transition detection with a 2-sample stability filter:
// - sample must appear twice consecutively before being considered stable.
// - returns on stable key-up -> key-down transitions only.
// This improves responsiveness versus strict release-then-press loops while
// avoiding single-scan phantom transitions.
// Output: A = PETSCII code of key pressed
// Preserves: X, Y
input_get_key:
    // Re-assert game MMU mode and keep Screen Editor blink disabled.
    // If any prior KERNAL path leaked MMU/ROM state, waiting for a key here
    // must not run the Screen Editor IRQ path that can touch VDC RAM.
    lda #INPUT_MMU_ALL_RAM
    sta $ff00
    lda #$ff
    sta $cc

    txa
    pha                     // Save X
    tya
    pha                     // Save Y

!igk_wait:
    inc zp_entropy
    jsr input_poll_key_event
    beq !igk_wait-          // Wait for key-up -> key-down edge

!igk_return:
    sta igk_key
    pla
    tay                     // Restore Y
    pla
    tax                     // Restore X
    lda igk_key
    rts
igk_key: .byte 0
igk_last_sample: .byte 0
igk_stable: .byte 0

// input_wait_release — Block until keyboard is released (C128 direct scan)
// Used before one-shot "press any key" prompts to avoid consuming
// a still-held selection key from the previous screen.
// Preserves: nothing
input_wait_release:
    // Same guard as input_get_key: release waits are long-lived and must
    // stay in game MMU mode with Screen Editor blink suppressed.
    lda #INPUT_MMU_ALL_RAM
    sta $ff00
    lda #$ff
    sta $cc
!iwr_wait:
    inc zp_entropy
    jsr cia_scan_petscii
    bne !iwr_wait-
    jsr cia_scan_petscii
    bne !iwr_wait-
    lda #0
    sta igk_last_sample
    sta igk_stable
    rts

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
    cmp igk_last_sample
    beq !ips_stable+
    sta igk_last_sample
!ips_none:
    lda #0
    rts

!ips_stable:
    cmp igk_stable
    beq !ips_none-          // No stable transition
    sta igk_stable
    beq !ips_none-          // Release edge (rearm only)
    rts                     // New stable key-down edge

// cia_scan_petscii — Single CIA1 keyboard matrix scan
// Drives each of 8 rows via $DC00, reads columns from $DC01.
// Detects SHIFT (LSHIFT=row1/bit7, RSHIFT=row6/bit4) separately.
// Output: A = PETSCII code of pressed key, $00 if no key or unmapped
// Destroys: A, X, Y
cia_scan_petscii:
    // Ensure CIA1 DDR is set for keyboard scanning.
    // Port A ($DC02) = $FF (all outputs — drives row select lines)
    // Port B ($DC03) = $00 (all inputs — reads column key state)
    // On C128, boot sequence or KERNAL calls may leave DDR in wrong state,
    // causing phantom key readings if Port B bits are set as outputs.
    lda #$ff
    sta $dc02
    lda #$00
    sta $dc03

    // Save extended keyboard drive register and force lines 8/9 idle-high.
    // We must always restore this register before returning.
    lda C128_KBD_EXT
    sta csp_ext_save
    ora #%11000000
    sta C128_KBD_EXT

    // Default shift state: unshifted ($80). Updated inline during row scan.
    lda #$80
    sta csp_shift

    // --- Scan all 8 rows for a non-shift key ---
    lda #$FE            // Row 0: bit 0 driven low
    ldx #0              // Row index (0–7)
!csp_row:
    sta CIA1_PORTA
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
    lda csp_row_raw
    eor #$FF            // Active low -> 1=pressed
    // CPX #6 above corrupted Z; re-test A to get actual key state.
    cmp #0
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
    lda CIA1_PORTB
    eor #$FF            // Active low -> 1=pressed
    cmp #0
    bne !csp_key_row8+

    // No key in row 8; scan extended row 9 (line 9).
    lda csp_ext_save
    ora #%11000000
    and #%01111111      // Drive line 9 low, keep line 8 high
    sta C128_KBD_EXT
    lda CIA1_PORTB
    eor #$FF            // Active low -> 1=pressed
    cmp #0
    bne !csp_key_row9+

    // No key found in any row — restore state and return 0.
    lda #$FF
    sta CIA1_PORTA      // Deselect all rows (neutral state)
    lda csp_ext_save
    sta C128_KBD_EXT
    lda #0
    rts

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
    bne !csp_return+    // $80 = unshifted → return as-is

    // Shifted: handle special cases for symbols that don't follow +$80 rule
    cmp #$2E            // unshifted . → shifted > ($3E)
    bne !csp_shift_not_dot+
    lda #$3E
    bne !csp_return+    // (always taken)
!csp_shift_not_dot:
    cmp #$2C            // unshifted , → shifted < ($3C)
    bne !csp_shift_not_comma+
    lda #$3C
    bne !csp_return+
!csp_shift_not_comma:
    cmp #$2F            // unshifted / → shifted ? ($3F)
    bne !csp_shift_default+
    lda #$3F
    bne !csp_return+
!csp_shift_default:
    ora #$80            // Letters ($41–$5A) + cursor keys ($11,$1D): add $80
!csp_return:
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
    .byte $37,  $59,  $47,  $38, $42, $48, $55, 0
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
    lda #0
    sta KBDBUF_COUNT        // Zero KERNAL buffer (harmless, not used for scan)

    lda #1
    sta zp_input_count      // Default repeat count = 1

!get_key:
    jsr input_get_key
    jsr petscii_to_command
    cmp #CMD_NONE
    beq !get_key-           // Unknown key, try again

!got_cmd:
    sta zp_input_cmd
    rts

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
    // Vi-keys (movement)
    .byte $4b   // K — north
    .byte $4a   // J — south
    .byte $48   // H — west
    .byte $4c   // L — east
    .byte $59   // Y — northwest
    .byte $55   // U — northeast
    .byte $42   // B — southwest
    .byte $4e   // N — southeast
    // Cursor keys
    .byte $91   // Cursor up — north
    .byte $11   // Cursor down — south
    .byte $9d   // Cursor left — west
    .byte $1d   // Cursor right — east
    // Game commands
    .byte $3e   // > — stairs down
    .byte $3c   // < — stairs up
    .byte $2e   // . — rest
    .byte $53   // S — search
    .byte $4f   // O — open
    .byte $43   // C — close
    .byte $47   // G — pick up
    .byte $2c   // , — pick up (alt)
    .byte $44   // D — drop
    .byte $49   // I — inventory
    .byte $45   // E — equipment / eat
    .byte $57   // W — wear/wield
    .byte $54   // T — take off
    .byte $51   // Q — quaff
    .byte $52   // R — read scroll
    .byte $41   // A — aim wand
    .byte $5a   // Z — use staff
    .byte $4d   // M — cast spell
    .byte $50   // P — pray
    .byte $3f   // ? — help
    // Special
    .byte $58   // X — look / examine
    .byte $46   // F — gain spell from book
    // Shifted keys
    .byte $c3   // SHIFT+C — character info
    .byte $d1   // SHIFT+Q — quit
    .byte $c5   // SHIFT+E — eat
    .byte $d3   // SHIFT+S — save and quit
    .byte $c6   // SHIFT+F — fire ranged weapon
    .byte $d4   // SHIFT+T — throw item
    .byte $d2   // SHIFT+R — refuel lamp
    .byte $c4   // SHIFT+D — bash
    .byte $2b   // + — tunnel
    .byte $2f   // / — monster recall
    // Shifted vi-keys (running)
    .byte $cb   // SHIFT+K — run north
    .byte $ca   // SHIFT+J — run south
    .byte $c8   // SHIFT+H — run west
    .byte $cc   // SHIFT+L — run east
    .byte $d9   // SHIFT+Y — run northwest
    .byte $d5   // SHIFT+U — run northeast
    .byte $c2   // SHIFT+B — run southwest
    .byte $ce   // SHIFT+N — run southeast
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
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_MOVE_NW, CMD_MOVE_NE, CMD_MOVE_SW, CMD_MOVE_SE
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_STAIRS_DN, CMD_STAIRS_UP, CMD_REST, CMD_SEARCH
    .byte CMD_OPEN, CMD_CLOSE, CMD_PICKUP, CMD_PICKUP
    .byte CMD_DROP, CMD_INVENTORY, CMD_EQUIPMENT, CMD_WEAR
    .byte CMD_TAKEOFF, CMD_QUAFF, CMD_READ, CMD_AIM
    .byte CMD_USE, CMD_CAST, CMD_PRAY, CMD_HELP
    .byte CMD_LOOK, CMD_GAIN
    .byte CMD_CHAR_INFO, CMD_QUIT, CMD_EAT, CMD_SAVE
    .byte CMD_FIRE, CMD_THROW, CMD_REFUEL, CMD_BASH
    .byte CMD_TUNNEL, CMD_RECALL
    .byte CMD_RUN_N, CMD_RUN_S, CMD_RUN_W, CMD_RUN_E
    .byte CMD_RUN_NW, CMD_RUN_NE, CMD_RUN_SW, CMD_RUN_SE
    // C128 keypad/extended key command mappings
    .byte CMD_MOVE_N, CMD_MOVE_S, CMD_MOVE_W, CMD_MOVE_E
    .byte CMD_MOVE_NW, CMD_MOVE_NE, CMD_MOVE_SW, CMD_MOVE_SE
    .byte CMD_REST, CMD_TUNNEL, CMD_QUIT

key_map_end:
.label key_map_count = key_map_cmd - key_map_petscii
.assert "Key map tables same size", key_map_count, key_map_end - key_map_cmd
