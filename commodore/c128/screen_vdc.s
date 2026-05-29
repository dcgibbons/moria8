#importonce
// screen_vdc.s — Screen output routines (80-column VDC)
//
// All output uses VDC register-indirect writes. Public text entry points take
// PETSCII and translate to VDC Set 1 screen codes inside this backend so the
// shared UI layer does not carry a separate VDC-only text contract. Colors are
// translated from VIC-II palette to RGBI via vic_to_vdc_color table.
//
// Screen layout (80-col):
//   Rows 0–1:    Message area (2 lines)
//   Rows 2–20:   Game viewport (78x19)
//   Rows 21–23:  Status bar (3 lines)
//   Row  24:     Input prompt line
// Placement is explicit by caller constants (no implicit global centering).

// ============================================================
// VDC Constants
// ============================================================
#import "hal/layout.s"
#import "hal/entropy_consts.s"

.const VDC_ADDR_REG    = $d600    // VDC address/status register
.const VDC_DATA_REG    = $d601    // VDC data register

.const VDC_SCREEN_BASE = $0000   // Screen chars in VDC RAM
.const VDC_ATTRIB_BASE = $0800   // Attributes in VDC RAM

// ============================================================
// Screen Constants
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
.const hal_screen_full_clear_uses_bulk = true
.const hal_screen_box_vertical_char = $21
.const hal_screen_help_line_uses_api = true
.const hal_screen_help_line_uses_color_map = false
.const hal_screen_spell_bolt_flash_sets_color = true
#define HAL_SCREEN_HELP_LINE_USES_API

.assert "HAL layout screen cols", SCREEN_COLS, hal_layout_screen_cols
.assert "HAL layout screen rows", SCREEN_ROWS, hal_layout_screen_rows
.assert "HAL layout viewport x", VIEWPORT_X, hal_layout_viewport_x
.assert "HAL layout viewport y", VIEWPORT_Y, hal_layout_viewport_y
.assert "HAL layout viewport width", VIEWPORT_W, hal_layout_viewport_w
.assert "HAL layout viewport height", VIEWPORT_H, hal_layout_viewport_h
.assert "HAL layout message row", MSG_ROW, hal_layout_msg_row
.assert "HAL layout status row", STATUS_ROW, hal_layout_status_row
.assert "HAL layout input row", INPUT_ROW, hal_layout_input_row

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

// vdc_set_block_src_addr — Fill VDC block-copy source pointer (Regs 32/33)
// Input: A = high byte, Y = low byte
vdc_set_block_src_addr:
    pha
    ldx #32
    jsr vdc_select_reg
    pla
    sta VDC_DATA_REG

    tya
    ldx #33
    jsr vdc_select_reg
    sta VDC_DATA_REG
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
// VDC attribute byte: bits 3-0 are encoded as R,G,B,I on this runtime.
// Keep game colors in canonical RGBI form and convert here once.
// Bit 6 ($40) = Reverse Video — do NOT set that.
// Bit 7 ($80) = Alternate Character Set: selects VDC Set 1 (Mixed Case font),
// which has uppercase A-Z at $41-$5A and lowercase a-z at $01-$1A.
.const VDC_ATTR_MODE = $80
.function vdc_encode_rgbi(rgbi) {
    // Convert canonical RGBI nibble (I,R,G,B in bits 3..0) to runtime nibble
    // layout (R,G,B,I in bits 3..0).
    .return (((rgbi & $07) << 1) | ((rgbi & $08) >> 3))
}
vic_to_vdc_color:
    .byte  0|VDC_ATTR_MODE    // $00 black
    .byte 15|VDC_ATTR_MODE    // $01 white
    .byte vdc_encode_rgbi(4)|VDC_ATTR_MODE    // $02 red
    .byte vdc_encode_rgbi(11)|VDC_ATTR_MODE   // $03 cyan
    .byte vdc_encode_rgbi(5)|VDC_ATTR_MODE    // $04 purple
    .byte vdc_encode_rgbi(2)|VDC_ATTR_MODE    // $05 green
    .byte vdc_encode_rgbi(1)|VDC_ATTR_MODE    // $06 blue
    .byte vdc_encode_rgbi(14)|VDC_ATTR_MODE   // $07 yellow
    .byte vdc_encode_rgbi(12)|VDC_ATTR_MODE   // $08 orange
    .byte vdc_encode_rgbi(6)|VDC_ATTR_MODE    // $09 brown
    .byte vdc_encode_rgbi(12)|VDC_ATTR_MODE   // $0a lt red
    .byte vdc_encode_rgbi(8)|VDC_ATTR_MODE    // $0b dk grey
    .byte vdc_encode_rgbi(8)|VDC_ATTR_MODE    // $0c grey → fallback to VDC dark grey
    .byte vdc_encode_rgbi(10)|VDC_ATTR_MODE   // $0d lt green
    .byte vdc_encode_rgbi(9)|VDC_ATTR_MODE    // $0e lt blue
    .byte vdc_encode_rgbi(7)|VDC_ATTR_MODE    // $0f lt grey

// ============================================================
// Pre-translated VDC RGBI color constants
// ============================================================
// These match vic_to_vdc_color entries; use directly in VDC attribute writes
// to avoid a runtime table lookup in hot rendering paths.
.const VDC_BLACK  =  0|VDC_ATTR_MODE   // COL_BLACK  ($00) → RGBI 0
.const VDC_WHITE  = 15|VDC_ATTR_MODE   // COL_WHITE  ($01) → RGBI 15
.const VDC_RED    =  vdc_encode_rgbi(4)|VDC_ATTR_MODE   // COL_RED
.const VDC_CYAN   =  vdc_encode_rgbi(11)|VDC_ATTR_MODE  // COL_CYAN
.const VDC_GREEN  =  vdc_encode_rgbi(2)|VDC_ATTR_MODE   // COL_GREEN
.const VDC_BLUE   =  vdc_encode_rgbi(1)|VDC_ATTR_MODE   // COL_BLUE
.const VDC_YELLOW =  vdc_encode_rgbi(14)|VDC_ATTR_MODE  // COL_YELLOW
.const VDC_ORANGE =  vdc_encode_rgbi(12)|VDC_ATTR_MODE  // COL_ORANGE
.const VDC_BROWN  =  vdc_encode_rgbi(6)|VDC_ATTR_MODE   // COL_BROWN
.const VDC_DGREY  =  vdc_encode_rgbi(8)|VDC_ATTR_MODE   // COL_DGREY
.const VDC_GREY   =  vdc_encode_rgbi(8)|VDC_ATTR_MODE   // COL_GREY fallback on VDC
.const VDC_LGREY  =  vdc_encode_rgbi(7)|VDC_ATTR_MODE   // COL_LGREY
.const VDC_LGREEN =  vdc_encode_rgbi(10)|VDC_ATTR_MODE  // COL_LGREEN
.const VDC_LBLUE  =  vdc_encode_rgbi(9)|VDC_ATTR_MODE   // COL_LBLUE

// ============================================================
// Screen Subroutines
// ============================================================

// screen_clear — Clear entire VDC screen (spaces) and attributes (current color)
// Reverted to streaming loop (Opt 5 revert) to resolve character creation crash.
screen_clear:
    php
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

    plp                     // Restore caller IRQ state
    // Full clear wipes status rows; force next status_draw to repaint.
    lda zp_ui_dirty
    ora #%10000001          // bit7=force status redraw, bit0=status dirty
    sta zp_ui_dirty
    rts

// screen_clear_for_font_restore — hide stale custom-charset contents before
// switching back to the ROM font.  Attribute RAM is cleared first so any
// intermediate character bytes are black-on-black while the VDC is live.
screen_clear_for_font_restore:
    php
    sei

    lda #>VDC_ATTRIB_BASE
    ldy #<VDC_ATTRIB_BASE
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_select_reg

    lda #8
    sta sc_page_cnt
    ldy #0
    lda #VDC_BLACK
!attr_loop:
    jsr vdc_wait
    sta VDC_DATA_REG
    dey
    bne !attr_loop-
    dec sc_page_cnt
    bne !attr_loop-

    lda #>VDC_SCREEN_BASE
    ldy #<VDC_SCREEN_BASE
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_select_reg

    lda #8
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

    plp
    rts

// screen_blank / screen_unblank — C128 VDC policy hooks
// VDC has no VIC-II DEN equivalent on $D011. These hooks keep the shared
// interface platform-correct and intentionally no-op on C128 for now.
screen_blank:
    rts

screen_unblank:
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

    lda color_row_lo,x
    clc
    adc zp_cursor_col
    sta zp_color_lo
    lda color_row_hi,x
    adc #0
    sta zp_color_hi
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
    php
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
    plp                     // Restore caller IRQ state

    ldx spc_save_x          // Restore original X
    inc zp_cursor_col
    rts
spc_save_x: .byte 0

// screen_put_string — Write a null-terminated string via VDC
// Input:  zp_ptr0/zp_ptr0_hi = pointer to string (PETSCII, $00 terminated)
//         zp_cursor_row = row
//         zp_cursor_col = starting column
//         zp_text_color = color
// Notes:  direct VDC/control bytes already used by packed UI data still pass
//         through unchanged; only PETSCII lowercase is translated.
// Preserves: nothing
screen_put_string:
    // Lock IRQs before any cursor/address setup so zp_ptr0 can't be
    // clobbered between caller handoff and first character fetch.
    php
    sei
    jsr screen_set_cursor   // Compute VDC addresses (no VDC access)

    // Clamp max chars to screen width.
    lda #SCREEN_COLS
    sec
    sbc zp_cursor_col
    bcs !sps_clamp_ok+
    lda #0
!sps_clamp_ok:
    sta sps_max_chars

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
    jsr screen_translate_petscii
    jsr vdc_wait            // WAIT before every data write
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
    plp                     // Restore caller IRQ state

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
    php
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
    plp                     // Restore caller IRQ state
    // If one of the status rows was cleared, force status repaint.
    cpx #STATUS_ROW
    beq !invalidate_status+
    cpx #STATUS_ROW + 1
    beq !invalidate_status+
    cpx #STATUS_ROW + 2
    bne !done+
!invalidate_status:
    lda zp_ui_dirty
    ora #%10000001          // bit7=force status redraw, bit0=status dirty
    sta zp_ui_dirty
!done:
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

// screen_flash_set_color — Set the transient VDC flash color from a VIC color
// Input: A = VIC color
screen_flash_set_color:
    stx sfc_save_x
    tax
    lda vic_to_vdc_color,x
    sta sfa_flash_attr
    ldx sfc_save_x
    rts
sfc_save_x: .byte 0

// screen_flash_reset_color — Restore the default transient flash color
screen_flash_reset_color:
    lda #VDC_WHITE
    sta sfa_flash_attr
    rts

// screen_flash_at — Flash '*' at screen position, restore after delay (VDC)
// Input:  X = screen row (absolute), Y = screen column (absolute)
// Clobbers: A, X, Y
screen_flash_at:
    stx sfa_row
    sty sfa_col
    php
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

    // Write transient effect attribute
    ldx sfa_row
    lda color_row_lo,x
    clc
    adc sfa_col
    tay
    lda color_row_hi,x
    adc #0
    jsr vdc_set_update_addr
    lda sfa_flash_attr
    jsr vdc_write_data

    // Delay (~20ms)
    ldx #$10
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
    plp                     // Restore caller IRQ state
    rts

sfa_row:       .byte 0
sfa_col:       .byte 0
sfa_save_char: .byte 0
sfa_save_attr: .byte 0
sfa_flash_attr: .byte VDC_WHITE

// ============================================================
// Shared numeric display functions — call backend screen_put_char internally
// ============================================================
#import "../common/numeric_format.s"

// ============================================================
// Compile-time validation
// ============================================================
.assert "Row table size", screen_row_hi - screen_row_lo, SCREEN_ROWS
.assert "Color table size", color_row_hi - color_row_lo, SCREEN_ROWS
