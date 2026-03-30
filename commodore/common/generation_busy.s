#importonce
// generation_busy.s — shared visible progress indicator for level generation
//
// Draws a centered "GENERATING..." message with a 4-frame spinner.
// Intended for long-running dungeon generation on both C64 and C128.

#import "generation_busy_api.s"
#import "ui_help_clear.s"

.encoding "screencode_mixed"

.const GEN_BUSY_MSG_LEN = 13
.const GEN_BUSY_TOTAL_LEN = 13
.const GEN_BUSY_ROW = 12
.const GEN_BUSY_COL = (SCREEN_COLS - GEN_BUSY_TOTAL_LEN) / 2
.const GEN_BUSY_BEGIN_HOLD = 16

generation_busy_begin:
    lda zp_text_color
    sta gen_busy_saved_color
    lda #1
    sta generation_busy_active_api
    // Hide the current gameplay/title frame before preparing the busy UI so
    // the player never sees partially cleared stale contents.
    jsr screen_blank
    lda #COL_WHITE
    sta zp_text_color
    jsr ui_clear_full_screen_safe
    jsr generation_busy_draw_frame
    jsr screen_unblank
    ldx #GEN_BUSY_BEGIN_HOLD
    jmp generation_busy_hold

generation_busy_tick:
    rts

generation_busy_end:
    lda #0
    sta generation_busy_active_api
    lda gen_busy_saved_color
    sta zp_text_color
    rts

// generation_busy_install — Patch the shared API shims to JMP into the
// real busy UI and reset the active flag.
generation_busy_install:
    lda #$4c
    sta generation_busy_begin_api
    sta generation_busy_tick_api
    sta generation_busy_end_api

    lda #<generation_busy_begin
    sta generation_busy_begin_api + 1
    lda #>generation_busy_begin
    sta generation_busy_begin_api + 2

    lda #<generation_busy_tick
    sta generation_busy_tick_api + 1
    lda #>generation_busy_tick
    sta generation_busy_tick_api + 2

    lda #<generation_busy_end
    sta generation_busy_end_api + 1
    lda #>generation_busy_end
    sta generation_busy_end_api + 2

    lda #0
    sta generation_busy_active_api
    rts

generation_busy_draw_frame:
    lda #GEN_BUSY_ROW
    sta zp_cursor_row
    lda #GEN_BUSY_COL
    sta zp_cursor_col
    lda #<gen_busy_text
    sta zp_ptr0
    lda #>gen_busy_text
    sta zp_ptr0_hi
    jsr screen_put_string
    rts

generation_busy_hold:
!gbh_outer:
    ldy #0
!gbh_inner:
    dey
    bne !gbh_inner-
    dex
    bne !gbh_outer-
    rts

gen_busy_saved_color:
    .byte 0

gen_busy_text:
    .text "GENERATING..."
    .byte 0
