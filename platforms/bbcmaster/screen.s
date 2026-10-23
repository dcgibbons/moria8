#importonce
// screen.s — BBC Master 128 80x24 Mode 0 display driver in 20 KB Shadow RAM LYNNE.
//
// Linked below $3000 so ACCCON bit X ($FE34 = $05) can map LYNNE at $3000-$7FFF
// without hiding the executing code or lookup tables.
//
// LYNNE layout ($3000-$7FFF when ACCCON = $05):
//   $3000-$33FF  beeb_font_table: 1 KB C64-screen-code-ordered RAM font (128 x 8 B)
//   $3400-$37FF  DUNGEON_GEN_SCAN_SCRATCH_BASE (1 KB generation scratch)
//   $3800-$3F7F  beeb_char_shadow: 80x24 = 1,920 B character shadow buffer
//   $4400-$7FFF  80x24 Mode 0 bitmap (24 rows x 640 B = 15,360 B, CRTC R12=$08, R13=$80)

#import "vic_palette_consts.s"
#import "memory.s"
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
.const hal_screen_full_clear_uses_blanked_bulk = true
#define HAL_SCREEN_FULL_CLEAR_USES_BLANKED_BULK
.const hal_screen_box_vertical_char = $7c
.const hal_screen_help_line_uses_api = true
.const hal_screen_help_line_uses_color_map = false
.const hal_screen_spell_bolt_flash_sets_color = false
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
.assert "BBC Master Mode 0 display has 24 rows", SCREEN_ROWS, 24

.const SC_SPACE = $20

// ============================================================
// HAL Exports
// ============================================================
.label hal_screen_init = screen_init
.label hal_screen_clear = screen_clear
.label hal_screen_clear_row = screen_clear_row
.label hal_screen_put_char = screen_put_char
.label hal_screen_put_string = screen_put_string
.label hal_screen_put_char_at = screen_put_char_at
.label hal_screen_set_cursor = screen_set_cursor
.label hal_screen_set_color = screen_set_color
.label hal_screen_blank = screen_noop
.label hal_screen_unblank = screen_noop
.label hal_screen_begin_bulk = screen_noop
.label hal_screen_end_bulk = screen_noop

beeb_wrch_noop:
screen_noop:
    rts

// ============================================================
// Row & Glyph Lookup Tables (< $3000)
// ============================================================
shadow_row_lo:
    .fill SCREEN_ROWS, <(BEEB_CHAR_SHADOW_BASE + i * SCREEN_COLS)
shadow_row_hi:
    .fill SCREEN_ROWS, >(BEEB_CHAR_SHADOW_BASE + i * SCREEN_COLS)

bitmap_row_lo:
    .fill SCREEN_ROWS, <(BEEB_BITMAP_BASE + i * 640)
bitmap_row_hi_m30:
    .fill SCREEN_ROWS, >(BEEB_BITMAP_BASE - BEEB_FONT_BASE + i * 640)

// Note: Because BEEB_FONT_BASE is $3000 (low byte $00), beeb_font_lo[i] == <(i * 8)
// and beeb_font_hi[i] == $30 + >(i * 8). Adding (bitmap_row - $3000) + beeb_font[col]
// yields bitmap_row + col * 8 without needing separate 160-byte col8 tables.
beeb_font_lo:
    .fill 128, <(BEEB_FONT_BASE + i * 8)
beeb_font_hi:
    .fill 128, >(BEEB_FONT_BASE + i * 8)

// 6845 CRTC register table for 80x24 Mode 0 starting at $4400 ((R12<<8|R13) = $0880)
beeb_crtc_regs:
    .byte $7f   // R0: horizontal total (127)
    .byte 80    // R1: horizontal displayed (80 chars = 640 bytes)
    .byte 98    // R2: horizontal sync position
    .byte $28   // R3: sync width
    .byte 38    // R4: vertical total (38)
    .byte 0     // R5: vertical total adjust
    .byte 24    // R6: vertical displayed (24 rows = 15,360 bytes)
    .byte 32    // R7: vertical sync position (centered for 24 rows)
    .byte $00   // R8: interlace & skew (normal)
    .byte 7     // R9: maximum scanline address (8 scanlines/row)
    .byte $20   // R10: cursor start (cursor disabled)
    .byte 8     // R11: cursor end
    .byte $08   // R12: start address high (>($4400 >> 3))
    .byte $80   // R13: start address low  (<($4400 >> 3))

// ============================================================
// beeb_font_init — Build 1 KB C64-screen-code-ordered RAM font at $3000-$33FF
// ============================================================
// Permutes MOS 3.20 ROM font (Sideways ROM Bank 15 $B900-$BBFF) into LYNNE $3000-$33FF:
//   $00     -> '@' ($BA00-$BA07)
//   $01-$1A -> 'a'..'z' ($BB08-$BBD7)
//   $1B-$1F -> '['..'_' ($BAD8-$BAFF)
//   $20-$3F -> ' '..'?' ($B900-$B9FF)
//   $40     -> '-' ($B968-$B96F)
//   $41-$5A -> 'A'..'Z' ($BA08-$BAD7)
//   $5B-$5F -> '['..'_' ($BAD8-$BAFF)
//   $60-$7F -> '`'..DEL ($BB00-$BBFF; '|' at $7C from $BBE0-$BBE7)
beeb_font_init:
    php
    sei
    lda #$0f                // Sideways ROM Bank 15 (MOS 3.20 Terminal/Font ROM)
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda #ACCCON_LYNNE
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON

    ldx #0
!page_copy:
    // Screen codes $00-$1F ($3000-$30FF): base from MOS $60-$7F ($BB00-$BBFF, 'a'..'z' at $01-$1A)
    lda $bb00,x
    sta BEEB_FONT_BASE + $0000,x
    // Screen codes $20-$3F ($3100-$31FF): from MOS $20-$3F ($B900-$B9FF, ' '..'?', '0'..'9')
    lda $b900,x
    sta BEEB_FONT_BASE + $0100,x
    // Screen codes $40-$5F ($3200-$32FF): from MOS $40-$5F ($BA00-$BAFF, 'A'..'Z' at $41-$5A)
    lda $ba00,x
    sta BEEB_FONT_BASE + $0200,x
    // Screen codes $60-$7F ($3300-$33FF): from MOS $60-$7F ($BB00-$BBFF, '|' at $7C)
    lda $bb00,x
    sta BEEB_FONT_BASE + $0300,x
    inx
    bne !page_copy-

    // Patch screen code $00 ('@' from MOS $40 at $BA00-$BA07) and
    // screen code $40 ('-' horizontal bar from MOS $2D at $B968-$B96F)
    ldx #7
!patch_at_dash:
    lda $ba00,x
    sta BEEB_FONT_BASE + $0000,x
    lda $b968,x
    sta BEEB_FONT_BASE + $0200,x
    dex
    bpl !patch_at_dash-

    // Patch screen codes $1B-$1F ('[', '\', ']', '^', '_' from MOS $5B-$5F at $BAD8-$BAFF)
    ldx #39
!patch_punct:
    lda $bad8,x
    sta BEEB_FONT_BASE + $00d8,x
    dex
    bpl !patch_punct-

    lda #ROMSEL_BANK4
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    plp
    rts

// ============================================================
// screen_init — Disable MOS VDU cursor, silence WRCHV, and program
// Video ULA & 6845 CRTC for 80x24 Mode 0 in LYNNE
// ============================================================
screen_init:
    // Switch MOS VDU driver to Shadow Mode 0 (VDU 22, 128) BEFORE silencing WRCHV.
    // This updates MOS's Video ULA shadow ($0248 = $9C so the 50 Hz VSYNC IRQ
    // never reverts $FE20 to Mode 7 Teletext) and programs the System VIA IC32
    // hardware screen-wrap latch for 20 KB bitmap mode ($3000-$7FFF) in LYNNE
    // without touching Main RAM ($3000-$7FFF).
    lda #22
    jsr MOS_OSWRCH
    lda #128
    jsr MOS_OSWRCH

    // Disable MOS 100 Hz software cursor via VDU 23,1,0;0;0;0; before silencing WRCHV
    lda #23
    jsr MOS_OSWRCH
    lda #1
    jsr MOS_OSWRCH
    ldx #8
!vdu_z:
    lda #0
    jsr MOS_OSWRCH
    dex
    bne !vdu_z-

    // Redirect WRCHV ($020E-$020F) to beeb_wrch_noop so no stray OSWRCH call
    // from MOS or DFS can ever write into Main RAM $3000-$7FFF
    php
    sei
    lda #<beeb_wrch_noop
    sta MOS_WRCHV
    lda #>beeb_wrch_noop
    sta MOS_WRCHV + 1
    plp

    // Video ULA: Mode 0 (80 chars/line, 2-color high bandwidth = $9C)
    lda #$9c
    sta VIDEO_ULA_CTRL

    // Video ULA palette: logical color 0 (slots 0..7) = black ($x7),
    // logical color 1 (slots 8..15) = white ($x0).
    ldx #0
!pal_loop:
    txa
    asl
    asl
    asl
    asl
    cpx #8
    bcs !pal_white+
    ora #$07                // physical black (0 EOR 7)
!pal_white:
    sta VIDEO_ULA_PAL
    inx
    cpx #16
    bcc !pal_loop-

    // Program 6845 CRTC registers R0..R13
    ldx #13
!crtc_loop:
    stx CRTC_ADDR
    lda beeb_crtc_regs,x
    sta CRTC_DATA
    dex
    bpl !crtc_loop-

    // Display Shadow RAM LYNNE (D=1, X=0)
    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON

    jsr beeb_font_init
    jmp screen_clear

// ============================================================
// Screen Output Subroutines (< $3000)
// ============================================================

// screen_set_cursor — Set zp_screen_lo/hi to shadow row base for zp_cursor_row.
// Preserves: Y
screen_set_cursor:
    ldx zp_cursor_row
    lda shadow_row_lo,x
    sta zp_screen_lo
    lda shadow_row_hi,x
    sta zp_screen_hi
    rts

// beeb_write_cell — Write C64 screen code A at (row = zp_cursor_row, col = X).
// Expects zp_screen_lo/hi = shadow row base for zp_cursor_row.
// Updates both beeb_char_shadow ($3800+) and Mode 0 bitmap ($4400+) in LYNNE.
// Preserves: X
beeb_write_cell:
    phx
    php
    sei
    pha
    lda #ACCCON_LYNNE
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON

    txa
    tay
    pla
    sta (zp_screen_lo),y

    // Compute bitmap cell pointer: (bitmap_row[row] - $3000) + ($3000 + col * 8)
    pha
    ldx zp_cursor_row
    lda bitmap_row_lo,x
    clc
    adc beeb_font_lo,y
    sta beeb_bmp_ptr
    lda bitmap_row_hi_m30,x
    adc beeb_font_hi,y
    sta beeb_bmp_ptr + 1
    pla

    // Decode bit 7 inverse-video flag and 7-bit font index
    ldx #$00
    stx beeb_inv_mask
    cmp #$80
    bcc !norm_char+
    dec beeb_inv_mask       // $ff inverse mask
    and #$7f
!norm_char:
    tax
    lda beeb_font_lo,x
    sta beeb_fnt_ptr
    lda beeb_font_hi,x
    sta beeb_fnt_ptr + 1
    ldy #7
!glyph_copy:
    lda (beeb_fnt_ptr),y
    eor beeb_inv_mask
    sta (beeb_bmp_ptr),y
    dey
    bpl !glyph_copy-
    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    plp
    plx
    rts

// beeb_read_cell — Read C64 screen code at (zp_screen_lo/hi row, X = column) -> A.
// Preserves: X
beeb_read_cell:
    php
    sei
    lda #ACCCON_LYNNE
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    txa
    tay
    lda (zp_screen_lo),y
    ldy #ACCCON_NORMAL
    sty beeb_acccon_shadow
    sty SHEILA_ACCCON
    sta beeb_mmu_byte
    plp
    lda beeb_mmu_byte
    rts

// screen_clear — Clear all 24 rows (shadow + Mode 0 bitmap) and force status redraw.
screen_clear:
    php
    sei
    lda #ACCCON_LYNNE
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON

    // 1. Fill beeb_char_shadow ($3800-$3F7F, 1,920 bytes = 7 pages + 128 bytes) with SC_SPACE ($20)
    lda #<BEEB_CHAR_SHADOW_BASE
    sta beeb_bmp_ptr
    lda #>BEEB_CHAR_SHADOW_BASE
    sta beeb_bmp_ptr + 1
    lda #SC_SPACE
    ldx #7
    ldy #0
!sh_page:
    sta (beeb_bmp_ptr),y
    iny
    bne !sh_page-
    inc beeb_bmp_ptr + 1
    dex
    bne !sh_page-
    ldy #127
!sh_tail:
    sta (beeb_bmp_ptr),y
    dey
    bpl !sh_tail-

    // 2. Zero Mode 0 bitmap ($4400-$7FFF, 60 pages = 15,360 bytes)
    lda #>BEEB_BITMAP_BASE
    sta beeb_bmp_ptr + 1
    lda #0
    sta beeb_bmp_ptr
    ldx #60
    ldy #0
!bmp_page:
    sta (beeb_bmp_ptr),y
    iny
    bne !bmp_page-
    inc beeb_bmp_ptr + 1
    dex
    bne !bmp_page-

    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    plp

    lda zp_ui_dirty
    ora #%10000001
    sta zp_ui_dirty
    rts

// screen_clear_row — Clear row A (0..23) in shadow ($20) and Mode 0 bitmap ($00).
screen_clear_row:
    tax
    lda shadow_row_lo,x
    sta zp_screen_lo
    lda shadow_row_hi,x
    sta zp_screen_hi
    lda bitmap_row_lo,x
    sta beeb_bmp_ptr
    lda bitmap_row_hi_m30,x
    clc
    adc #>BEEB_FONT_BASE
    sta beeb_bmp_ptr + 1

    php
    sei
    lda #ACCCON_LYNNE
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON

    // Clear 80 bytes in beeb_char_shadow
    lda #SC_SPACE
    ldy #SCREEN_COLS - 1
!clr_sh:
    sta (zp_screen_lo),y
    dey
    bpl !clr_sh-

    // Clear 640 bytes (2 pages + 128 bytes) in Mode 0 bitmap
    lda #0
    ldy #0
!clr_b0:
    sta (beeb_bmp_ptr),y
    iny
    bne !clr_b0-
    inc beeb_bmp_ptr + 1
!clr_b1:
    sta (beeb_bmp_ptr),y
    iny
    bne !clr_b1-
    inc beeb_bmp_ptr + 1
    ldy #127
!clr_b2:
    sta (beeb_bmp_ptr),y
    dey
    bpl !clr_b2-

    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    plp
    rts

// screen_put_char — Write screen code A at cursor, advance zp_cursor_col.
// Preserves: X (required by core numeric_format_emit_screen and UI loops).
screen_put_char:
    stx beeb_zp_scratch
    pha
    jsr screen_set_cursor
    ldx zp_cursor_col
    pla
    jsr beeb_write_cell
    inc zp_cursor_col
    ldx beeb_zp_scratch
    rts

// screen_put_string — Write null-terminated string at (zp_ptr0) from cursor.
// Clobbers: A, X, Y
screen_put_string:
    jsr screen_set_cursor
    ldy #0
!loop:
    sty beeb_zp_scratch
    lda (zp_ptr0),y
    beq !done+
    ldx zp_cursor_col
    jsr beeb_write_cell
    inc zp_cursor_col
    ldy beeb_zp_scratch
    iny
    lda zp_cursor_col
    cmp #SCREEN_COLS
    bne !loop-
!done:
    rts

// screen_put_char_at — Write screen code A at (X = col, Y = row), preserving cursor.
screen_put_char_at:
    sta beeb_zp_scratch
    lda zp_cursor_row
    pha
    lda zp_cursor_col
    pha
    sty zp_cursor_row
    stx zp_cursor_col
    jsr screen_set_cursor
    lda beeb_zp_scratch
    ldx zp_cursor_col
    jsr beeb_write_cell
    pla
    sta zp_cursor_col
    pla
    sta zp_cursor_row
    rts

// screen_set_color — Record logical color in zp_text_color. Preserves X, Y.
screen_set_color:
    sta zp_text_color
    rts

#import "../../core/numeric_format.s"

// screen_flash_at — Briefly flash inverse-video '*' ($AA) at (X = row, Y = col).
screen_flash_at:
    lda zp_cursor_row
    pha
    lda zp_cursor_col
    pha
    stx zp_cursor_row
    sty sfa_save_col
    jsr screen_set_cursor

    ldx sfa_save_col
    jsr beeb_read_cell
    sta sfa_save_char

    lda #$aa                // '*' ($2A) | $80 inverse video
    ldx sfa_save_col
    jsr beeb_write_cell

    ldx #$20                // ~20 ms delay at 2 MHz
!d_o:
    ldy #$00
!d_i:
    dey
    bne !d_i-
    dex
    bne !d_o-

    lda sfa_save_char
    ldx sfa_save_col
    jsr beeb_write_cell
    pla
    sta zp_cursor_col
    pla
    sta zp_cursor_row
    rts

sfa_save_col:  .byte 0
sfa_save_char: .byte 0

// ============================================================
// beeb_flush_row_buf — Diff-flush rv_row_scr_buf[0..79] to LYNNE row X (< $3000)
// ============================================================
// Input: X = screen row (0..23), rv_row_scr_buf[0..79] populated.
// Switches ACCCON = $05 once, compares each cell against beeb_char_shadow,
// and blits the 8-byte Mode 0 glyph only when the cell changed.
beeb_flush_row_buf:
    lda shadow_row_lo,x
    sta zp_screen_lo
    lda shadow_row_hi,x
    sta zp_screen_hi
    lda bitmap_row_lo,x
    sta bfr_bmp_row_lo
    lda bitmap_row_hi_m30,x
    sta bfr_bmp_row_hi

    php
    sei
    lda #ACCCON_LYNNE
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON

    ldy #0
!cell_loop:
    lda rv_row_scr_buf,y
    cmp (zp_screen_lo),y
    beq !next_cell+
    sta (zp_screen_lo),y

    // Compute glyph pointer for 7-bit screen code A (viewport glyphs are $00-$7F)
    and #$7f
    tax
    lda beeb_font_lo,x
    sta beeb_fnt_ptr
    lda beeb_font_hi,x
    sta beeb_fnt_ptr + 1

    // Compute bitmap cell pointer: (bfr_bmp_row - $3000) + ($3000 + col * 8)
    lda bfr_bmp_row_lo
    clc
    adc beeb_font_lo,y
    sta beeb_bmp_ptr
    lda bfr_bmp_row_hi
    adc beeb_font_hi,y
    sta beeb_bmp_ptr + 1

    phy
    ldy #7
!blit8:
    lda (beeb_fnt_ptr),y
    sta (beeb_bmp_ptr),y
    dey
    bpl !blit8-
    ply

!next_cell:
    iny
    cpy #SCREEN_COLS
    bcc !cell_loop-

    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    plp
    rts

bfr_bmp_row_lo: .byte 0
bfr_bmp_row_hi: .byte 0

// bsd_stage_shadow_row — Copy 80 shadow bytes of row X from LYNNE into rv_row_scr_buf (< $3000).
bsd_stage_shadow_row:
    lda shadow_row_lo,x
    sta zp_ptr0
    lda shadow_row_hi,x
    sta zp_ptr0_hi
    php
    sei
    lda #ACCCON_LYNNE
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    ldy #SCREEN_COLS - 1
!cp:
    lda (zp_ptr0),y
    sta rv_row_scr_buf,y
    dey
    bpl !cp-
    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    plp
    rts

.assert "Shadow row table size", shadow_row_hi - shadow_row_lo, SCREEN_ROWS
.assert "Bitmap row table size", bitmap_row_hi_m30 - bitmap_row_lo, SCREEN_ROWS
