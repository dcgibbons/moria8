// screen_vdc.s — Screen output routines (80-column VDC)
//
// All output uses VDC register-indirect writes. Screen codes are written
// directly (no translation needed — C128 KERNAL initializes VDC char RAM
// with the same ordering as VIC-II). Colors are translated from VIC-II
// palette to RGBI via vic_to_vdc_color table.
//
// Screen layout (80-col, MVP — uses 40-col layout within 80-col screen):
//   Rows 0–1:    Message area (2 lines)
//   Rows 2–20:   Game viewport (38x19, columns 1–38)
//   Rows 21–23:  Status bar (3 lines)
//   Row  24:     Input prompt line
//   Cols 0, 39+: Border/unused

// ============================================================
// VDC Constants
// ============================================================
.const VDC_ADDR_REG    = $d600    // VDC address/status register
.const VDC_DATA_REG    = $d601    // VDC data register

.const VDC_SCREEN_BASE = $0000   // Screen chars in VDC RAM
.const VDC_ATTRIB_BASE = $0800   // Attributes in VDC RAM

// ============================================================
// Screen Constants
// ============================================================
.const SCREEN_COLS = 80
.const SCREEN_ROWS = 25
.const SCREEN_COL_OFFSET = 20   // Centers 40-col game area in 80-col VDC display
.const VIEWPORT_X  = 1      // Viewport starts at column 1
.const VIEWPORT_Y  = 2      // Viewport starts at row 2
.const VIEWPORT_W  = 38     // Viewport width (same as C64 for MVP)
.const VIEWPORT_H  = 19     // Viewport height
.const MSG_ROW     = 0      // Message line row
.const STATUS_ROW  = 21     // Status bar first row
.const INPUT_ROW   = 24     // Input prompt row

// Screen code for space
.const SC_SPACE     = $20

// ============================================================
// VDC Core Routines
// ============================================================

// vdc_wait — Spin until VDC is ready (status bit 7 = 1)
// Clobbers: flags only. Safe to call with interrupts disabled.
vdc_wait:
    bit VDC_ADDR_REG
    bpl vdc_wait
    rts

// vdc_select_reg — Wait for VDC ready, select register X, wait again
// After this returns, $D601 is ready for access.  For streaming (reg 31
// auto-increment): call once, then loop with [jsr vdc_wait; sta VDC_DATA_REG].
// Callers MUST hold sei for the duration of the address-set + data-stream.
vdc_select_reg:
    jsr vdc_wait            // Wait: VDC must be idle before selecting register
    stx VDC_ADDR_REG        // Select register
    jsr vdc_wait            // Wait: VDC has latched register number
    rts

// vdc_write_reg — Write A to VDC register X (wait-select-wait-write)
vdc_write_reg:
    jsr vdc_select_reg      // Wait, select X, wait
    sta VDC_DATA_REG        // Write data
    rts

// vdc_read_reg — Read VDC register X into A (wait-select-wait-read)
vdc_read_reg:
    jsr vdc_select_reg      // Wait, select X, wait
    lda VDC_DATA_REG        // Read data
    rts

// vdc_set_update_addr — Set VDC update address pointer (Regs 18 & 19)
// Input: A = high byte, Y = low byte
vdc_set_update_addr:
    pha                     // Save high byte
    ldx #18
    jsr vdc_select_reg      // Wait, select reg 18, wait
    pla                     // Restore high byte
    sta VDC_DATA_REG        // Write high byte

    tya                     // Low byte to A
    ldx #19
    jsr vdc_select_reg      // Wait, select reg 19, wait
    sta VDC_DATA_REG        // Write low byte
    rts

// vdc_write_data — Write A to VDC data register 31 (auto-increments)
vdc_write_data:
    ldx #31
    jsr vdc_write_reg
    rts

// ============================================================
// Vector table — matches c64/screen.s interface
// ============================================================
screen_vectors:
    jmp screen_clear        // +0: clear entire screen
    jmp screen_put_char     // +3: put char at cursor
    jmp screen_put_string   // +6: put string at (row,col)
    jmp screen_set_color    // +9: set current text color
    jmp screen_clear_row    // +12: clear a single row

// ============================================================
// Row address lookup tables (80-column: row * 80)
// ============================================================
screen_row_lo:
    .fill SCREEN_ROWS, <(VDC_SCREEN_BASE + i * SCREEN_COLS)
screen_row_hi:
    .fill SCREEN_ROWS, >(VDC_SCREEN_BASE + i * SCREEN_COLS)
color_row_lo:
    .fill SCREEN_ROWS, <(VDC_ATTRIB_BASE + i * SCREEN_COLS)
color_row_hi:
    .fill SCREEN_ROWS, >(VDC_ATTRIB_BASE + i * SCREEN_COLS)

// ============================================================
// VIC-II → VDC RGBI color translation
// Index = VIC-II color (0–15), value = RGBI attribute
// ============================================================
// VDC attribute byte: bits 3-0 = RGBI color, bit 7 = Alternate Character Set
// Bit 6 ($40) = Reverse Video — do NOT set that.
// Bit 7 ($80) = Alternate Character Set: selects VDC Set 1 (Mixed Case font),
// which has uppercase A-Z at $41-$5A and lowercase a-z at $01-$1A.
vic_to_vdc_color:
    .byte  0|$80    // $00 black     → RGBI 0  | Set 1
    .byte 15|$80    // $01 white     → RGBI 15 | Set 1
    .byte  4|$80    // $02 red       → RGBI 4  | Set 1
    .byte 11|$80    // $03 cyan      → RGBI 11 | Set 1
    .byte  5|$80    // $04 purple    → RGBI 5  | Set 1
    .byte  2|$80    // $05 green     → RGBI 2  | Set 1
    .byte  1|$80    // $06 blue      → RGBI 1  | Set 1
    .byte 14|$80    // $07 yellow    → RGBI 14 | Set 1
    .byte 12|$80    // $08 orange    → RGBI 12 | Set 1
    .byte  6|$80    // $09 brown     → RGBI 6  | Set 1
    .byte 12|$80    // $0a lt red    → RGBI 12 | Set 1
    .byte  8|$80    // $0b dk grey   → RGBI 8  | Set 1
    .byte  7|$80    // $0c grey      → RGBI 7  | Set 1
    .byte 10|$80    // $0d lt green  → RGBI 10 | Set 1
    .byte  9|$80    // $0e lt blue   → RGBI 9  | Set 1
    .byte  7|$80    // $0f lt grey   → RGBI 7  | Set 1

// ============================================================
// Pre-translated VDC RGBI color constants
// ============================================================
// These match vic_to_vdc_color entries; use directly in VDC attribute
// writes to avoid a runtime table lookup in hot rendering paths.
// Bit 7 ($80) = Alternate Character Set (VDC Set 1 = mixed case font).
.const VDC_BLACK  =  0|$80   // COL_BLACK  ($00) → RGBI 0
.const VDC_WHITE  = 15|$80   // COL_WHITE  ($01) → RGBI 15
.const VDC_RED    =  4|$80   // COL_RED    ($02) → RGBI 4
.const VDC_CYAN   = 11|$80   // COL_CYAN   ($03) → RGBI 11
.const VDC_GREEN  =  2|$80   // COL_GREEN  ($05) → RGBI 2
.const VDC_BLUE   =  1|$80   // COL_BLUE   ($06) → RGBI 1
.const VDC_YELLOW = 14|$80   // COL_YELLOW ($07) → RGBI 14
.const VDC_ORANGE = 12|$80   // COL_ORANGE ($08) → RGBI 12
.const VDC_BROWN  =  6|$80   // COL_BROWN  ($09) → RGBI 6
.const VDC_DGREY  =  8|$80   // COL_DGREY  ($0b) → RGBI 8
.const VDC_GREY   =  7|$80   // COL_GREY   ($0c) → RGBI 7
.const VDC_LGREY  =  7|$80   // COL_LGREY  ($0f) → RGBI 7 (L3: same as GREY)
.const VDC_LGREEN = 10|$80   // COL_LGREEN ($0d) → RGBI 10
.const VDC_LBLUE  =  9|$80   // COL_LBLUE  ($0e) → RGBI 9

// ============================================================
// Screen Subroutines
// ============================================================

// screen_clear — Clear entire VDC screen (spaces) and attributes (current color)
// Reverted to streaming loop (Opt 5 revert) to resolve character creation crash.
screen_clear:
    sei                     // IRQ off: protect screen fill + attr fill as one atomic block

    // Fill screen RAM: 2000 bytes of SC_SPACE
    lda #>VDC_SCREEN_BASE
    ldy #<VDC_SCREEN_BASE
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_select_reg      // Select Data Register once

    lda #8                  // Clear 8 pages (2048 bytes) to cover 2000-byte screen
    sta sc_page_cnt
    ldy #0
    lda #SC_SPACE
!char_loop:
    jsr vdc_wait
    sta VDC_DATA_REG
    dey
    bne !char_loop-
    dec sc_page_cnt
    bne !char_loop-

    // Fill attribute RAM: 2000 bytes via streaming loop
    lda #>VDC_ATTRIB_BASE
    ldy #<VDC_ATTRIB_BASE
    jsr vdc_set_update_addr
    ldx zp_text_color
    lda vic_to_vdc_color,x
    sta sc_attr_val
    ldx #31
    jsr vdc_select_reg

    lda #8                  // Clear 8 pages (2048 bytes)
    sta sc_page_cnt
    ldy #0
    lda sc_attr_val
!attr_loop:
    jsr vdc_wait
    sta VDC_DATA_REG
    dey
    bne !attr_loop-
    dec sc_page_cnt
    bne !attr_loop-

    cli                     // IRQ on: screen + attr RAM fully cleared
    rts

sc_page_cnt: .byte 0
sc_attr_val: .byte 0

// screen_set_cursor — Set VDC addresses for (row, col)
// Input:  zp_cursor_row, zp_cursor_col
// Output: zp_screen_lo/hi = VDC screen address
//         zp_color_lo/hi  = VDC attribute address
// Preserves: Y
screen_set_cursor:
    ldx zp_cursor_row
    lda screen_row_lo,x
    clc
    adc zp_cursor_col
    sta zp_screen_lo
    lda screen_row_hi,x
    adc #0
    sta zp_screen_hi
    // Apply centering offset: shift game content +20 cols into 80-col display
    lda zp_screen_lo
    clc
    adc #SCREEN_COL_OFFSET
    sta zp_screen_lo
    bcc !ssc_s_done+
    inc zp_screen_hi
!ssc_s_done:

    lda color_row_lo,x
    clc
    adc zp_cursor_col
    sta zp_color_lo
    lda color_row_hi,x
    adc #0
    sta zp_color_hi
    // Apply centering offset to attribute address as well
    lda zp_color_lo
    clc
    adc #SCREEN_COL_OFFSET
    sta zp_color_lo
    bcc !ssc_c_done+
    inc zp_color_hi
!ssc_c_done:
    rts

// screen_translate_petscii — Convert PETSCII char to VDC Mixed Case (Set 1) screen code
// VDC Set 1 (attribute bit 7 set): UC A-Z at $41-$5A, LC a-z at $01-$1A.
// PETSCII UC $41-$5A passes through unchanged (already correct for Set 1 uppercase).
// PETSCII LC $61-$7A → AND #$1F → $01-$1A (lowercase in Set 1).
// VDC codes $01-$1A (title art, direct Set 1 encoding) pass through unchanged.
// Input:  A = PETSCII char OR direct VDC Set 1 screen code
// Output: A = VDC Set 1 screen code
// Preserves: X, Y
screen_translate_petscii:
    cmp #$61
    bcc !done+              // $00-$60: pass through (VDC codes + UC + numbers/symbols)
    cmp #$7b
    bcc !lower+             // $61-$7A: PETSCII LC → Set 1 LC ($01-$1A)
    // $7B+: pass through
!done:
    rts
!lower:
    and #$1f                // $61-$7A → $01-$1A (lowercase in VDC Set 1)
    rts

// screen_put_char — Write one PETSCII char at current cursor position via VDC
// Input:  A = PETSCII char
//         zp_cursor_row, zp_cursor_col = position
//         zp_text_color = color (VIC-II palette)
// Output: cursor advances right by 1
// Preserves: X
screen_put_char:
    pha                     // Save screen code
    stx spc_save_x          // Save original X
    jsr screen_set_cursor   // Compute VDC addresses (no VDC access)

    sei                     // IRQ off: protect char write + attr write as one atomic block
    // Set VDC address to screen position
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr

    // Translate PETSCII → VDC Set 1, write char
    pla                     // Restore char
    jsr screen_translate_petscii
    jsr vdc_write_data

    // Set VDC address to attribute position
    lda zp_color_hi
    ldy zp_color_lo
    jsr vdc_set_update_addr

    // Write translated color
    ldx zp_text_color
    lda vic_to_vdc_color,x
    jsr vdc_write_data
    cli                     // IRQ on: VDC state is now consistent

    ldx spc_save_x          // Restore original X
    inc zp_cursor_col
    rts
spc_save_x: .byte 0

// screen_put_string — Write a null-terminated string of PETSCII chars via VDC
// Input:  zp_ptr0/zp_ptr0_hi = pointer to string (PETSCII, $00 terminated)
//         zp_cursor_row = row
//         zp_cursor_col = starting column
//         zp_text_color = color
// Preserves: nothing
screen_put_string:
    jsr screen_set_cursor   // Compute VDC addresses (no VDC access)

    // Clamp max chars to viewport width (computed before sei to minimize IRQ-off window)
    lda #(SCREEN_COLS - SCREEN_COL_OFFSET)
    sec
    sbc zp_cursor_col
    bcs !sps_clamp_ok+
    lda #0
!sps_clamp_ok:
    sta sps_max_chars

    sei                     // IRQ OFF: Prevent KERNAL from moving VDC pointer

    // --- Character Pass ---
    lda zp_screen_hi
    ldy zp_screen_lo
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_select_reg      // Select Data Register ONCE

    ldy #0
!char_loop:
    lda (zp_ptr0),y
    beq !chars_done+
    jsr screen_translate_petscii    // PETSCII → VDC Set 1 screen code
    pha
    jsr vdc_wait            // WAIT before every data write
    pla
    sta VDC_DATA_REG        // Stream directly to port
    iny
    cpy sps_max_chars
    bcc !char_loop-
!chars_done:
    sty sps_str_len

    // --- Attribute Pass ---
    lda sps_str_len
    beq !sps_done+          // Skip if length is 0

    lda zp_color_hi
    ldy zp_color_lo
    jsr vdc_set_update_addr
    ldx zp_text_color
    lda vic_to_vdc_color,x
    sta sps_attr
    ldx #31
    jsr vdc_select_reg      // Select Data Register ONCE

    ldy #0
!attr_loop:
    jsr vdc_wait            // WAIT before every color write
    lda sps_attr
    sta VDC_DATA_REG
    iny
    cpy sps_str_len
    bcc !attr_loop-

!sps_done:
    cli                     // IRQ ON: Operation complete

    lda sps_str_len
    clc
    adc zp_cursor_col
    sta zp_cursor_col
    rts

sps_str_len:  .byte 0
sps_max_chars:.byte 0
sps_attr:     .byte 0

// screen_set_color — Set current text color
// Input: A = color value (VIC-II palette 0–15)
// Preserves: X, Y
screen_set_color:
    sta zp_text_color
    rts

// screen_clear_row — Clear a single VDC row to spaces
// Reverted to streaming loop (Opt 5 revert) to resolve character creation crash.
// Input: A = row number (0–24)
// Preserves: nothing
screen_clear_row:
    tax
    sei                     // IRQ off: protect char fill + attr fill for this row
    stx scr_save_row

    // Clear char row: 80 spaces
    lda screen_row_lo,x
    tay
    lda screen_row_hi,x
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_select_reg
    lda #SC_SPACE
    ldy #80
!loop:
    jsr vdc_wait
    sta VDC_DATA_REG
    dey
    bne !loop-

    // Clear attr row: 80 bytes of current color
    ldx scr_save_row
    lda color_row_lo,x
    tay
    lda color_row_hi,x
    jsr vdc_set_update_addr
    ldx zp_text_color
    lda vic_to_vdc_color,x
    ldx #31
    jsr vdc_select_reg
    ldy #80
!col:
    jsr vdc_wait
    sta VDC_DATA_REG
    dey
    bne !col-

    ldx scr_save_row
    cli                     // IRQ on: row char+attr fill complete
    rts

scr_save_row: .byte 0
scr_attr:     .byte 0

// screen_put_char_at — Write one char at specific (row, col) without moving cursor
// Input:  A = screen code
//         X = column
//         Y = row
//         zp_text_color = color
// Preserves: cursor position
screen_put_char_at:
    sta spca_char
    lda zp_cursor_row
    pha
    lda zp_cursor_col
    pha
    sty zp_cursor_row
    stx zp_cursor_col
    lda spca_char
    jsr screen_put_char
    pla
    sta zp_cursor_col
    pla
    sta zp_cursor_row
    rts
spca_char: .byte 0

// screen_flash_at — Flash '*' white at screen position, restore after delay (VDC)
// Input:  X = screen row (absolute), Y = screen column (absolute)
// Clobbers: A, X, Y
screen_flash_at:
    stx sfa_row
    tya                     // Apply centering offset so flash lands in the game area
    clc
    adc #SCREEN_COL_OFFSET
    sta sfa_col
    sei                     // IRQ off: protect all VDC read/write/restore operations

    // Read current character at position
    lda screen_row_lo,x
    clc
    adc sfa_col
    tay
    lda screen_row_hi,x
    adc #0
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    sta sfa_save_char

    // Read current attribute
    ldx sfa_row
    lda color_row_lo,x
    clc
    adc sfa_col
    tay
    lda color_row_hi,x
    adc #0
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    sta sfa_save_attr

    // Write '*' at screen position
    ldx sfa_row
    lda screen_row_lo,x
    clc
    adc sfa_col
    tay
    lda screen_row_hi,x
    adc #0
    jsr vdc_set_update_addr
    lda #$2a                    // '*'
    jsr vdc_write_data

    // Write white attribute
    ldx sfa_row
    lda color_row_lo,x
    clc
    adc sfa_col
    tay
    lda color_row_hi,x
    adc #0
    jsr vdc_set_update_addr
    lda #15                     // RGBI white
    jsr vdc_write_data

    // Delay (~10ms)
    ldx #$08
!sfa_delay_o:
    ldy #$00
!sfa_delay_i:
    dey
    bne !sfa_delay_i-
    dex
    bne !sfa_delay_o-

    // Restore original character
    ldx sfa_row
    lda screen_row_lo,x
    clc
    adc sfa_col
    tay
    lda screen_row_hi,x
    adc #0
    jsr vdc_set_update_addr
    lda sfa_save_char
    jsr vdc_write_data

    // Restore original attribute
    ldx sfa_row
    lda color_row_lo,x
    clc
    adc sfa_col
    tay
    lda color_row_hi,x
    adc #0
    jsr vdc_set_update_addr
    lda sfa_save_attr
    jsr vdc_write_data
    cli                     // IRQ on: flash complete, char+attr restored
    rts

sfa_row:       .byte 0
sfa_col:       .byte 0
sfa_save_char: .byte 0
sfa_save_attr: .byte 0

// ============================================================
// Numeric display functions — call screen_put_char internally
// (Identical logic to c64/screen.s, just using VDC screen_put_char)
// ============================================================

// screen_put_hex — Write a byte as 2-digit hex at cursor
screen_put_hex:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr !hex_digit+
    jsr screen_put_char
    pla
    and #$0f
    jsr !hex_digit+
    jmp screen_put_char
!hex_digit:
    cmp #$0a
    bcc !digit+
    sbc #$09
    rts
!digit:
    ora #$30
    rts

// screen_put_decimal — Write an 8-bit value as decimal at cursor
screen_put_decimal:
    sta zp_temp4
    lda #0
    sta zp_temp2            // Leading zero suppression flag

    ldx #0
    lda zp_temp4
!hundreds:
    cmp #100
    bcc !tens+
    sbc #100
    inx
    bne !hundreds-
!tens:
    sta zp_temp4
    txa
    beq !skip_h+
    ora #$30
    jsr screen_put_char
    inc zp_temp2
    jmp !do_tens+
!skip_h:
    lda zp_temp2
    bne !print_zero_h+
    jmp !do_tens+
!print_zero_h:
    lda #$30
    jsr screen_put_char
!do_tens:
    ldx #0
    lda zp_temp4
!tens_loop:
    cmp #10
    bcc !ones+
    sbc #10
    inx
    bne !tens_loop-
!ones:
    sta zp_temp4
    txa
    beq !skip_t+
    ora #$30
    jsr screen_put_char
    inc zp_temp2
    jmp !do_ones+
!skip_t:
    lda zp_temp2
    beq !do_ones+
    lda #$30
    jsr screen_put_char
!do_ones:
    lda zp_temp4
    ora #$30
    jmp screen_put_char

// screen_put_decimal_rj2 — Print 8-bit value right-justified in 2-char field
screen_put_decimal_rj2:
    cmp #10
    bcs screen_put_decimal
    pha
    lda #$20
    jsr screen_put_char
    pla
    jmp screen_put_decimal

// screen_put_decimal_lz2 — Print 8-bit value with leading zero in 2-char field
screen_put_decimal_lz2:
    cmp #10
    bcs screen_put_decimal
    pha
    lda #$30
    jsr screen_put_char
    pla
    jmp screen_put_decimal

// screen_put_decimal_16 — Write a 16-bit value as decimal at cursor
screen_put_decimal_16:
    lda #0
    sta zp_temp2            // Leading zero flag
    ldx #4                  // 5 digits (10000s..1s), index 4..0
!digit_loop:
    lda #0
    sta zp_temp3            // Digit counter
!sub_loop:
    lda zp_temp0
    sec
    sbc decimal_powers_lo,x
    tay
    lda zp_temp1
    sbc decimal_powers_hi,x
    bcc !digit_done+
    sta zp_temp1
    sty zp_temp0
    inc zp_temp3
    jmp !sub_loop-
!digit_done:
    lda zp_temp3
    bne !print_digit+
    lda zp_temp2
    beq !next_digit+
!print_digit:
    lda #1
    sta zp_temp2
    lda zp_temp3
    ora #$30
    jsr screen_put_char
!next_digit:
    dex
    bne !digit_loop-
    // Always print ones digit
    lda zp_temp0
    ora #$30
    jmp screen_put_char

decimal_powers_lo:
    .byte <1, <10, <100, <1000, <10000
decimal_powers_hi:
    .byte >1, >10, >100, >1000, >10000

// ============================================================
// Compile-time validation
// ============================================================
.assert "Row table size", screen_row_hi - screen_row_lo, SCREEN_ROWS
.assert "Color table size", color_row_hi - color_row_lo, SCREEN_ROWS
