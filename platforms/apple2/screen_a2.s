// screen_a2.s — Apple IIe 80-column text screen backend
//
// All 12 hal_screen_* exports. The 80-column store interleaves aux and main
// text pages: even columns live in aux $0400-$07FF, odd columns in main
// $0400-$07FF. With 80STORE on (set at init, never turned off), PAGE2
// ($C054/$C055) selects which half is addressed at $0400-$07FF.
//
// Row addressing: base = $0400 + (row&7)*$80 + (row>>3)*$28. Each 128-byte
// block holds three 40-byte row-halves at offsets $00/$28/$50, so writing at
// most 40 bytes per half-row can never touch the firmware/ProDOS screen
// holes at $x78-$x7F.
//
// Colorless policy: set_color records the logical color (core/color.s IDs)
// and nothing else; inverse video is reserved for the title reverse-space
// attribute. Display codes come from a2_char_map (C64 screen code -> Apple):
//   sc $00-$1F -> (sc+$40)|$80   ('@', A-Z, ...)
//   sc $20-$3F -> sc|$80         (space, digits, punctuation)
//   sc $40-$5F -> (sc+$20)|$80   (a-z)
//   sc $60-$FF -> $A0            (graphics/reverse -> space)
//
// Blank/unblank: hires page 1 is zeroed at boot; blank switches to full
// graphics hires page 1 (black), unblank returns to text. Text buffers are
// never modified.

#import "vic_palette_consts.s"
#import "hal/layout.s"

// ============================================================
// Constants
// ============================================================
.const SCREEN_COLS = hal_layout_screen_cols
.const SCREEN_ROWS = hal_layout_screen_rows
.const VIEWPORT_X  = hal_layout_viewport_x
.const VIEWPORT_Y  = hal_layout_viewport_y
.const VIEWPORT_W  = hal_layout_viewport_w
.const VIEWPORT_H  = hal_layout_viewport_h
.const MSG_ROW     = hal_layout_msg_row
.const STATUS_ROW  = hal_layout_status_row
.const INPUT_ROW   = hal_layout_input_row
.const hal_screen_full_clear_uses_bulk = false
.const hal_screen_box_vertical_char = $21
.const hal_screen_help_line_uses_api = false
.const hal_screen_help_line_uses_color_map = false
.const hal_screen_spell_bolt_flash_sets_color = false

.assert "HAL layout screen cols", SCREEN_COLS, hal_layout_screen_cols
.assert "HAL layout screen rows", SCREEN_ROWS, hal_layout_screen_rows
.assert "HAL layout viewport x", VIEWPORT_X, hal_layout_viewport_x
.assert "HAL layout viewport y", VIEWPORT_Y, hal_layout_viewport_y
.assert "HAL layout viewport width", VIEWPORT_W, hal_layout_viewport_w
.assert "HAL layout viewport height", VIEWPORT_H, hal_layout_viewport_h
.assert "HAL layout message row", MSG_ROW, hal_layout_msg_row
.assert "HAL layout status row", STATUS_ROW, hal_layout_status_row
.assert "HAL layout input row", INPUT_ROW, hal_layout_input_row
.assert "Apple II text display has 24 rows", SCREEN_ROWS, 24
.assert "Input row is on screen", INPUT_ROW < SCREEN_ROWS, true
.assert "Viewport ends before input", VIEWPORT_Y + VIEWPORT_H <= INPUT_ROW, true
.assert "Input ends before status", INPUT_ROW < STATUS_ROW, true
.assert "Three status rows fit", STATUS_ROW + 2 < SCREEN_ROWS, true

// Apple display code for a normal-video space; half-row width in bytes
.const A2_SPACE     = $a0
.const A2_HALF_ROW  = SCREEN_COLS / 2

// Soft switches
.const A2_PAGE2_OFF = $c054   // main text half (odd columns)
.const A2_PAGE2_ON  = $c055   // aux text half (even columns)
.const A2_TEXT_OFF  = $c050
.const A2_TEXT_ON   = $c051
.const A2_MIX_OFF   = $c052
.const A2_HIRES_OFF = $c056
.const A2_HIRES_ON  = $c057

.label hal_screen_init = screen_noop
.label hal_screen_clear = screen_clear
.label hal_screen_clear_row = screen_clear_row
.label hal_screen_put_char = screen_put_char
.label hal_screen_put_string = screen_put_string
.label hal_screen_put_char_at = screen_put_char_at
.label hal_screen_set_cursor = screen_set_cursor
.label hal_screen_set_color = screen_set_color
.label hal_screen_blank = screen_blank
.label hal_screen_unblank = screen_unblank
.label hal_screen_begin_bulk = screen_noop
.label hal_screen_end_bulk = screen_noop

screen_noop:
    rts

// ============================================================
// a2_map_char — C64 screen code -> Apple display code (computed)
//
// Kick "screencode_mixed" layout: $00='@'->$C0, $01-$1A lowercase->$E1-$FA,
// $1B-$1F->$DB-$DF, $20-$3F->$A0-$BF, $41-$5A uppercase->$C1-$DA,
// $5B-$5F->$DB-$DF, $60-$7F graphics->space. High half ($80-$FF) mirrors
// the low half except $A0 (reverse space) -> Apple inverse-video space $20.
// Input: X = C64 screen code. Output: A = Apple display code. Clobbers: A.
// ============================================================
a2_map_char:
    cpx #$a0
    beq !mc_inverse+
    txa
    and #$7f                    // high half mirrors the low half
    tax
    cpx #$60
    bcs !mc_space+
    cpx #$41
    bcs !mc_upper+
    cpx #$20
    bcs !mc_punct+
    cpx #$1b
    bcs !mc_brackets+
    cpx #$01
    bcs !mc_lower+
    lda #$c0                    // $00 -> '@'
    rts
!mc_lower:
    txa
    clc
    adc #$60                    // $01-$1A -> $E1-$FA
    ora #$80
    rts
!mc_brackets:
    txa
    clc
    adc #$40                    // $1B-$1F, $5B-$5F -> $DB-$DF
    ora #$80
    rts
!mc_punct:
    txa                         // $20-$3F -> $A0-$BF
    ora #$80
    rts
!mc_upper:
    cpx #$5b
    bcs !mc_brackets-
    txa                         // $41-$5A -> $C1-$DA
    ora #$80
    rts
!mc_space:
    lda #A2_SPACE               // $60-$7F graphics
    rts
!mc_inverse:
    lda #$20                    // $A0 reverse space -> inverse space
    rts

// ============================================================
// Row base tables (main-half addresses; aux half shares the base)
// ============================================================
a2_row_lo:
    .fill SCREEN_ROWS, <($0400 + (i & 7) * $80 + (i >> 3) * $28)
a2_row_hi:
    .fill SCREEN_ROWS, >($0400 + (i & 7) * $80 + (i >> 3) * $28)

// ============================================================
// Subroutines
// ============================================================

// screen_clear — Clear both text halves to spaces; force status repaint.
// Preserves: nothing
screen_clear:
    lda #A2_SPACE
    ldx #0
!rows:
    lda a2_row_lo,x
    sta zp_screen_lo
    lda a2_row_hi,x
    sta zp_screen_hi
    lda #A2_SPACE
    sta A2_PAGE2_ON         // aux half (even columns)
    ldy #A2_HALF_ROW - 1
!aux:
    sta (zp_screen_lo),y
    dey
    bpl !aux-
    sta A2_PAGE2_OFF        // main half (odd columns)
    ldy #A2_HALF_ROW - 1
!main:
    sta (zp_screen_lo),y
    dey
    bpl !main-
    inx
    cpx #SCREEN_ROWS
    bne !rows-
    // Full clear wipes status rows; force next status_draw to repaint.
    lda zp_ui_dirty
    ora #%10000001          // bit7=force status redraw, bit0=status dirty
    sta zp_ui_dirty
    rts

// screen_blank — Switch to the (boot-zeroed) hires page 1. Preserves: nothing
screen_blank:
    sta A2_HIRES_ON
    sta A2_MIX_OFF
    sta A2_TEXT_OFF
    rts

// screen_unblank — Return to 80-column text. Preserves: nothing
screen_unblank:
    sta A2_HIRES_OFF
    sta A2_TEXT_ON
    rts

// screen_set_cursor — Point zp_screen_lo/hi at the half-row for zp_cursor_row
// Input:  zp_cursor_row (col comes in via zp_cursor_col)
// Output: zp_screen_lo/hi = row base; column handled per write
// Preserves: Y
screen_set_cursor:
    ldx zp_cursor_row
    lda a2_row_lo,x
    sta zp_screen_lo
    lda a2_row_hi,x
    sta zp_screen_hi
    rts

// a2_write_cell — Write Apple char A at (zp_screen_lo/hi row, X = column)
// Internal. Clobbers: flags only (X/Y preserved via stack)
a2_write_cell:
#if A2_DEBUG_WRITELOG
    pha
    pha
    lda a2_wlog_idx
    tay
    pla
    sta $2000,y
    iny
    sty a2_wlog_idx
    pla
#endif
    pha                     // save display code
    txa                     // column -> Y = col>>1, carry = parity
    lsr
    tay
    pla                     // restore display code
    bcs !odd+
    sta A2_PAGE2_ON         // even column -> aux half
    sta (zp_screen_lo),y
    sta A2_PAGE2_OFF
    rts
!odd:
    sta (zp_screen_lo),y    // odd column -> main half
    rts
#if A2_DEBUG_WRITELOG
a2_wlog_idx: .byte 0
#endif

// a2_read_cell — Read Apple char at (zp_screen_lo/hi row, X = column) -> A
// Internal. Preserves X.
a2_read_cell:
    txa
    lsr                     // A = col>>1, carry = parity
    tay
    txa
    lsr                     // carry = parity (tay does not affect carry)
    bcs !odd+
    sta A2_PAGE2_ON         // even column -> aux half
    lda (zp_screen_lo),y
    sta A2_PAGE2_OFF
    rts
!odd:
    lda (zp_screen_lo),y    // odd column -> main half
    rts

// screen_put_char — Write one screen code at cursor, advance right
// Input:  A = C64 screen code; zp_cursor_row, zp_cursor_col
// Clobbers: A, Y (per contract; X preserved: core loops such as
// numeric_format_emit_screen keep their buffer index in X across put_char,
// matching how the Commodore implementations behave in practice)
screen_put_char:
    stx a2_zp_scratch
    tax
    jsr a2_map_char       // display code
    pha
    jsr screen_set_cursor   // clobbers X
    lda zp_cursor_col
    tax
    pla
    jsr a2_write_cell
    inc zp_cursor_col
    ldx a2_zp_scratch
    rts

// screen_put_string — Write null-terminated screen codes at cursor
// Input:  zp_ptr0/zp_ptr0_hi = string; zp_cursor_row, zp_cursor_col
// Clobbers: A, X, Y, zp_temp4
screen_put_string:
    jsr screen_set_cursor
    ldy #0
!loop:
    sty zp_temp4            // string index (a2_write_cell clobbers Y)
    lda (zp_ptr0),y
    beq !done+
    tax                     // screen code
    jsr a2_map_char       // display code
    ldx zp_cursor_col       // column
    jsr a2_write_cell       // preserves X
    inc zp_cursor_col
    ldy zp_temp4
    iny
    lda zp_cursor_col
    cmp #SCREEN_COLS        // stop at row edge (C64 behavior)
    bne !loop-
!done:
    rts

// screen_clear_row — Clear row A to spaces (both halves)
// Input:  A = row (0-23)
// Preserves: nothing
screen_clear_row:
    tax
    lda a2_row_lo,x
    sta zp_screen_lo
    lda a2_row_hi,x
    sta zp_screen_hi
    lda #A2_SPACE
    sta A2_PAGE2_ON
    ldy #A2_HALF_ROW - 1
!aux:
    sta (zp_screen_lo),y
    dey
    bpl !aux-
    sta A2_PAGE2_OFF
    ldy #A2_HALF_ROW - 1
!main:
    sta (zp_screen_lo),y
    dey
    bpl !main-
    rts

// screen_put_char_at — Write screen code A at (X = column, Y = row)
// Preserves: cursor position
screen_put_char_at:
    sta zp_temp4
    lda zp_cursor_row
    pha
    lda zp_cursor_col
    pha
    sty zp_cursor_row
    stx zp_cursor_col
    jsr screen_set_cursor
    ldx zp_temp4
    jsr a2_map_char
    ldx zp_cursor_col
    jsr a2_write_cell
    pla
    sta zp_cursor_col
    pla
    sta zp_cursor_row
    rts

// screen_set_color — Record logical color (colorless display). Preserves X, Y
screen_set_color:
    sta zp_text_color
    rts

#import "../../../core/numeric_format.s"

// screen_flash_at — Briefly flash '*' at (X = row, Y = column), then restore
// Used by bolt animation in spell_effects.s.
// Clobbers: A, X, Y
screen_flash_at:
    stx sfa_save_row
    lda a2_row_lo,x
    sta zp_screen_lo
    lda a2_row_hi,x
    sta zp_screen_hi
    sty sfa_save_col

    ldx sfa_save_col
    jsr a2_read_cell
    sta sfa_save_char

    lda #$aa                // '*' normal video
    ldx sfa_save_col
    jsr a2_write_cell

    ldx #$10                // delay (~20 ms at 1 MHz)
!d_o:
    ldy #$00
!d_i:
    dey
    bne !d_i-
    dex
    bne !d_o-

    lda sfa_save_char
    ldx sfa_save_col
    jsr a2_write_cell
    rts

sfa_save_row:   .byte 0
sfa_save_col:   .byte 0
sfa_save_char:  .byte 0

// ============================================================
// Compile-time validation
// ============================================================
.assert "Row lo table size", a2_row_hi - a2_row_lo, SCREEN_ROWS
