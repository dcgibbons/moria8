#importonce
// screen.s — Atari 8-bit 40x25 ANTIC Mode 2 display driver, C64-ordered 1 KB
// RAM font permuter, and self-healing VBI -> DLI horizontal zone color engine.
//
// Linked below $4000 so atari_font_init (which temporarily sets PORTB = $FF to
// read the Atari OS ROM font at $E000-$E3FF) and atari_nmi_handler (DLI/VBI/
// SYSTEM RESET) are always resident in unbanked low RAM.

#import "../commodore/common/vic_palette_consts.s"
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
.const hal_screen_full_clear_uses_blanked_bulk = false
.const hal_screen_box_vertical_char = $7c
.const hal_screen_help_line_uses_api = true
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

.const SC_SPACE = $20

// Horizontal zone colors (NTSC/PAL Atari GTIA hue+luminance)
// Uniform black ($00) background across all 25 rows matching all other Moria8 platforms.
.const ATARI_COL_MSG_BG  = $00
.const ATARI_COL_MSG_FG  = $0e
.const ATARI_COL_VIEW_BG = $00
.const ATARI_COL_VIEW_FG = $0c
.const ATARI_COL_STAT_BG = $00
.const ATARI_COL_STAT_FG = $0e
.const ATARI_COL_INP_BG  = $00
.const ATARI_COL_INP_FG = $0e
.assert "Uniform black background across all DLI zones", ATARI_COL_MSG_BG == $00 && ATARI_COL_VIEW_BG == $00 && ATARI_COL_STAT_BG == $00 && ATARI_COL_INP_BG == $00, true

// ============================================================
// Vector table & HAL aliases
// ============================================================
screen_vectors:
    jmp screen_clear        // +0: clear entire screen
    jmp screen_put_char     // +3: put char at cursor
    jmp screen_put_string   // +6: put string at (row,col)
    jmp screen_set_color    // +9: set current text color
    jmp screen_clear_row    // +12: clear a single row

#import "../../core/ui_equipment_wrap.s"

.label hal_screen_init = screen_init
.label hal_screen_clear = screen_clear
.label hal_screen_clear_row = screen_clear_row
#if HAL_LAYOUT_EQUIPMENT_WRAP
.label hal_screen_put_char = screen_vectors + 3
.label hal_screen_put_string = screen_vectors + 6
#else
.label hal_screen_put_char = screen_put_char
.label hal_screen_put_string = screen_put_string
#endif
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
// Row address lookup table (SCREEN_RAM = $0800, 40 cols x 25 rows)
// ============================================================
screen_row_lo:
    .fill SCREEN_ROWS, <(SCREEN_RAM + i * SCREEN_COLS)
screen_row_hi:
    .fill SCREEN_ROWS, >(SCREEN_RAM + i * SCREEN_COLS)

// ============================================================
// 40x25 ANTIC Mode 2 Display List Template (copied to $0380)
// ============================================================
atari_dl_template:
    .byte $70, $70                          // 16 blank scanlines (top overscan)
    .byte $42, <SCREEN_RAM, >SCREEN_RAM     // Mode 2 + LMS $0800 (Row 0: Message 0)
    .byte $82                               // Mode 2 + DLI (Row 1: Message 1 -> Viewport)
    .fill 18, $02                           // Mode 2 (Rows 2..19: Dungeon Viewport)
    .byte $82                               // Mode 2 + DLI (Row 20: Viewport -> Status)
    .byte $02, $02                          // Mode 2 (Rows 21..22: Status 1..2)
    .byte $82                               // Mode 2 + DLI (Row 23: Status 3 -> Input)
    .byte $02                               // Mode 2 (Row 24: Input Prompt)
    .byte $41, <ATARI_DISPLAY_LIST, >ATARI_DISPLAY_LIST // JVB to $0380
atari_dl_template_end:

.const ATARI_DISPLAY_LIST_LEN = atari_dl_template_end - atari_dl_template
.const ATARI_DISPLAY_LIST_END = ATARI_DISPLAY_LIST + ATARI_DISPLAY_LIST_LEN - 1
.assert "ATARI_DISPLAY_LIST fits in $0380-$03BF", ATARI_DISPLAY_LIST_END < $03c0, true
.assert "ATARI_DISPLAY_LIST does not cross a 1 KB boundary", ((>ATARI_DISPLAY_LIST) & $fc) == ((>ATARI_DISPLAY_LIST_END) & $fc), true

// ============================================================
// atari_font_init — Build 1 KB C64-ordered RAM font at $0400-$07FF
// ============================================================
// Must be called from < $4000 with SEI, NMIEN = $00, DMACTL = $00.
// Temporarily maps OS ROM ($E000-$E3FF) via PORTB = $FF, permutes glyphs
// into C64 screen-code order at $0400-$07FF, and restores PORTB = $FE.
atari_font_init:
    lda #PORTB_OS_ROM
    sta PORTB

    ldx #0
!page_copy:
    // Screen codes $00-$1F ($0400-$04FF): base from OS $60-$7F ($E300-$E3FF, 'a'..'z' at $01-$1A)
    lda $e300,x
    sta ATARI_CHARSET_BASE + $0000,x
    // Screen codes $20-$3F ($0500-$05FF): from OS $00-$1F ($E000-$E0FF, ' '..'?', '0'..'9')
    lda $e000,x
    sta ATARI_CHARSET_BASE + $0100,x
    // Screen codes $40-$5F ($0600-$06FF): from OS $20-$3F ($E100-$E1FF, 'A'..'Z' at $41-$5A)
    lda $e100,x
    sta ATARI_CHARSET_BASE + $0200,x
    // Screen codes $60-$7F ($0700-$07FF): from OS $60-$7F ($E300-$E3FF, '|' at $7C)
    lda $e300,x
    sta ATARI_CHARSET_BASE + $0300,x
    inx
    bne !page_copy-

    // Patch screen code $00 ('@' from OS $20 at $E100-$E107) and
    // screen code $40 ('-' horizontal bar from OS $0D at $E068-$E06F)
    ldx #7
!patch_at_dash:
    lda $e100,x
    sta ATARI_CHARSET_BASE + $0000,x
    lda $e068,x
    sta ATARI_CHARSET_BASE + $0200,x
    dex
    bpl !patch_at_dash-

    // Patch screen codes $1B-$1F ('[', '\', ']', '^', '_' from OS $3B-$3F at $E1D8-$E1FF)
    ldx #39
!patch_punct:
    lda $e1d8,x
    sta ATARI_CHARSET_BASE + $00d8,x
    dex
    bpl !patch_punct-

    lda #PORTB_GAME_RAM
    sta PORTB
    rts

// ============================================================
// screen_init — Install 40x25 Display List, DLI vector, and ANTIC registers
// ============================================================
screen_init:
    ldx #ATARI_DISPLAY_LIST_LEN - 1
!dl_copy:
    lda atari_dl_template,x
    sta ATARI_DISPLAY_LIST,x
    dex
    bpl !dl_copy-

    lda #<dli_row1
    sta dli_vector
    lda #>dli_row1
    sta dli_vector + 1

    lda #<ATARI_DISPLAY_LIST
    sta DLISTL
    sta OS_SDLSTL
    lda #>ATARI_DISPLAY_LIST
    sta DLISTH
    sta OS_SDLSTH

    lda #>ATARI_CHARSET_BASE
    sta CHBASE
    sta OS_CHBAS

    lda #2
    sta CHACTL
    sta OS_CHACT
    lda #0
    sta PRIOR
    sta OS_GPRIOR
    sta COLBK
    sta OS_COLOR4
    sta COLPF2
    sta OS_COLOR2
    lda #$0e
    sta COLPF1
    sta OS_COLOR1

    jsr screen_clear

    lda #$22
    sta OS_SDMCTL
    sta DMACTL
    rts

// ============================================================
// Self-Healing VBI + DLI Handler (< $4000)
// ============================================================
dli_vector:
    .word dli_row1

atari_nmi_handler:
    pha
    txa
    pha
    tya
    pha

    // Check physical SYSTEM RESET key NMI (NMIST bit 5 = $20)
    lda NMIST
    and #$20
    beq !not_reset+
    jmp exit_trampoline
!not_reset:
    // Check DLI (NMIST bit 7 = $80)
    bit NMIST
    bpl !check_vbi+
    jmp (dli_vector)
dli_return:
!check_vbi:
    // Check VBI (NMIST bit 6 = $40)
    bit NMIST
    bvc !nmi_done+
    lda #<dli_row1
    sta dli_vector
    lda #>dli_row1
    sta dli_vector + 1
    lda #ATARI_COL_MSG_BG
    sta COLPF2
    lda #0
    sta COLBK
    lda #ATARI_COL_MSG_FG
    sta COLPF1
    jsr hal_sound_update
!nmi_done:
    sta NMIRES
    pla
    tay
    pla
    tax
    pla
    rti

// DLI 1 (end of Row 1): switch to Dungeon Viewport colors (Rows 2..20)
dli_row1:
    sta WSYNC
    lda #ATARI_COL_VIEW_BG
    sta COLPF2
    lda #ATARI_COL_VIEW_FG
    sta COLPF1
    lda #<dli_row20
    sta dli_vector
    lda #>dli_row20
    sta dli_vector + 1
    jmp dli_return

// DLI 2 (end of Row 20): switch to Status Bar colors (Rows 21..23)
dli_row20:
    sta WSYNC
    lda #ATARI_COL_STAT_BG
    sta COLPF2
    lda #ATARI_COL_STAT_FG
    sta COLPF1
    lda #<dli_row23
    sta dli_vector
    lda #>dli_row23
    sta dli_vector + 1
    jmp dli_return

// DLI 3 (end of Row 23): switch to Input Prompt colors (Row 24)
dli_row23:
    sta WSYNC
    lda #ATARI_COL_INP_BG
    sta COLPF2
    lda #ATARI_COL_INP_FG
    sta COLPF1
    lda #<dli_row1
    sta dli_vector
    lda #>dli_row1
    sta dli_vector + 1
    jmp dli_return

// ============================================================
// Screen Output Subroutines
// ============================================================

// screen_clear — Fill 40x25 SCREEN_RAM (1,000 bytes) with spaces
screen_clear:
    lda #SC_SPACE
    ldx #0
!loop:
    sta SCREEN_RAM,x
    sta SCREEN_RAM + $100,x
    sta SCREEN_RAM + $200,x
    inx
    bne !loop-
    ldx #232
!last:
    sta SCREEN_RAM + $300 - 1,x
    dex
    bne !last-
    lda zp_ui_dirty
    ora #%10000001
    sta zp_ui_dirty
    rts

// screen_blank / screen_unblank — Keep ANTIC display active across short transitions
screen_blank:
screen_unblank:
    rts

// screen_set_cursor — Set zp_screen_lo/hi for (zp_cursor_row, zp_cursor_col)
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
    rts

// screen_put_char — Write one screen code at current cursor position
// Preserves: X
screen_put_char:
    pha
    txa
    pha
    jsr screen_set_cursor
    pla
    tax
    pla
    ldy #0
    sta (zp_screen_lo),y
    inc zp_cursor_col
    rts

// screen_put_string — Write null-terminated string of screen codes
screen_put_string:
    jsr screen_set_cursor
    ldy #0
    ldx zp_cursor_col
!loop:
    lda (zp_ptr0),y
    beq !done+
    sta (zp_screen_lo),y
    iny
    inx
    cpx #SCREEN_COLS
    bne !loop-
!done:
    tya
    clc
    adc zp_cursor_col
    sta zp_cursor_col
    rts

// screen_set_color — Record logical text color in zp_text_color
// Preserves: X, Y
screen_set_color:
    sta zp_text_color
    rts

// screen_clear_row — Clear a single row (A = 0..24) to spaces
screen_clear_row:
    tax
    lda screen_row_lo,x
    sta zp_screen_lo
    lda screen_row_hi,x
    sta zp_screen_hi
    lda #SC_SPACE
    ldy #SCREEN_COLS - 1
!loop:
    sta (zp_screen_lo),y
    dey
    bpl !loop-
    rts

// screen_put_char_at — Write one char at (X = col, Y = row) preserving cursor
screen_put_char_at:
    sta zp_temp4
    lda zp_cursor_row
    pha
    lda zp_cursor_col
    pha
    sty zp_cursor_row
    stx zp_cursor_col
    jsr screen_set_cursor
    lda zp_temp4
    ldy #0
    sta (zp_screen_lo),y
    pla
    sta zp_cursor_col
    pla
    sta zp_cursor_row
    rts

#import "../../core/numeric_format.s"

// screen_flash_at — Flash inverse-video '*' ($AA) at (X = row, Y = col)
screen_flash_at:
    stx sfa_save_row
    lda screen_row_lo,x
    sta zp_ptr0
    lda screen_row_hi,x
    sta zp_ptr0_hi
    sty sfa_save_col

    lda (zp_ptr0),y
    sta sfa_save_char

    lda #$aa                // '*' ($2A) | $80 inverse video
    sta (zp_ptr0),y

    ldx #$18
!sfa_delay_o:
    ldy #$00
!sfa_delay_i:
    dey
    bne !sfa_delay_i-
    dex
    bne !sfa_delay_o-

    ldy sfa_save_col
    lda sfa_save_char
    sta (zp_ptr0),y
    rts

sfa_save_row:  .byte 0
sfa_save_col:  .byte 0
sfa_save_char: .byte 0

.assert "Row table size", screen_row_hi - screen_row_lo, SCREEN_ROWS
