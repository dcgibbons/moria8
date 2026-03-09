// test_status_coherence128.s — Status redraw coherence guards (C128 VDC)
//
// Ensures screen clear paths set UI dirty bits needed for status repaint:
// - full screen clear must request forced status redraw
// - status-row clear must request forced status redraw
// - non-status row clear must not set status redraw bits

#import "../../common/zeropage.s"
#import "../screen_vdc.s"

.const COL_WHITE = 1

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $4000 "Test Code"

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #COL_WHITE
    sta zp_text_color

    // Non-status row clear should not force status redraw.
    lda #0
    sta zp_ui_dirty
    lda #5
    jsr screen_clear_row
    lda zp_ui_dirty
    and #%10000001
    beq !row_nonstatus_ok+
    jmp test_fail
!row_nonstatus_ok:

    // Status row clear must force status redraw.
    lda #0
    sta zp_ui_dirty
    lda #STATUS_ROW + 1
    jsr screen_clear_row
    lda zp_ui_dirty
    and #%10000001
    cmp #%10000001
    beq !row_status_ok+
    jmp test_fail
!row_status_ok:

    // Full screen clear must force status redraw.
    lda #0
    sta zp_ui_dirty
    jsr screen_clear
    lda zp_ui_dirty
    and #%10000001
    cmp #%10000001
    beq !screen_clear_ok+
    jmp test_fail
!screen_clear_ok:

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
