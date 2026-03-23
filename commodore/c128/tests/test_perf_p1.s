#importonce
// test_perf_p1.s — P1 movement responsiveness instrumentation checks (C128)

#if !PERF_P1
.error "test_perf_p1.s requires -define PERF_P1"
#endif

#import "../../common/zeropage.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

// Minimal UI stubs/constants so perf_p1.s assembles in this unit-test context.
.const MSG_ROW = 0
.const COL_WHITE = 1
msg_clear:       rts
screen_clear_row:rts
screen_put_string:rts
screen_put_hex:  rts
screen_put_char: rts

#import "../../common/perf_p1.s"

.macro assert_mem_eq_imm(mem, imm) {
    lda mem
    cmp #imm
    beq !ok+
    jmp test_fail
!ok:
}

test_start:
    sei
    cld
    ldx #$ff
    txs

    jsr perf_p1_reset

    // Verify reset cleared counters.
    lda perf_p1_hist_0
    ora perf_p1_hist_1
    ora perf_p1_hist_2
    ora perf_p1_hist_3p
    ora perf_p1_local_lo
    ora perf_p1_full_lo
    ora perf_p1_scroll_lo
    ora perf_p1_scroll_delta_lo
    ora perf_p1_scroll_fallback_lo
    ora perf_p1_moves
    ora perf_p1_max_delta
    beq !reset_ok+
    jmp test_fail
!reset_ok:

    // Case 1: delta=0, local render.
    lda #$10
    sta $a2
    jsr perf_p1_move_start
    jsr perf_p1_mark_local
    jsr perf_p1_move_end

    :assert_mem_eq_imm(perf_p1_hist_0, 1)
    :assert_mem_eq_imm(perf_p1_local_lo, 1)
    :assert_mem_eq_imm(perf_p1_moves, 1)

    // Case 2: delta=1, scroll handled by delta renderer.
    lda #$20
    sta $a2
    jsr perf_p1_move_start
    jsr perf_p1_mark_scroll
    jsr perf_p1_mark_scroll_delta
    lda #$21
    sta $a2
    jsr perf_p1_move_end

    :assert_mem_eq_imm(perf_p1_hist_1, 1)
    :assert_mem_eq_imm(perf_p1_scroll_delta_lo, 1)
    :assert_mem_eq_imm(perf_p1_full_lo, 0)
    :assert_mem_eq_imm(perf_p1_scroll_lo, 0)
    :assert_mem_eq_imm(perf_p1_max_delta, 1)

    // Case 3: delta=2, scroll fallback to full redraw.
    lda #$30
    sta $a2
    jsr perf_p1_move_start
    jsr perf_p1_mark_scroll
    jsr perf_p1_mark_scroll_fallback
    jsr perf_p1_mark_full
    lda #$32
    sta $a2
    jsr perf_p1_move_end

    :assert_mem_eq_imm(perf_p1_hist_2, 1)
    :assert_mem_eq_imm(perf_p1_full_lo, 1)
    :assert_mem_eq_imm(perf_p1_scroll_lo, 1)
    :assert_mem_eq_imm(perf_p1_scroll_fallback_lo, 1)

    // Case 4: delta=5, full redraw without scroll.
    lda #$40
    sta $a2
    jsr perf_p1_move_start
    jsr perf_p1_mark_full
    lda #$45
    sta $a2
    jsr perf_p1_move_end

    :assert_mem_eq_imm(perf_p1_hist_3p, 1)
    :assert_mem_eq_imm(perf_p1_full_lo, 2)
    :assert_mem_eq_imm(perf_p1_scroll_lo, 1)
    :assert_mem_eq_imm(perf_p1_scroll_delta_lo, 1)
    :assert_mem_eq_imm(perf_p1_scroll_fallback_lo, 1)
    :assert_mem_eq_imm(perf_p1_local_lo, 1)
    :assert_mem_eq_imm(perf_p1_moves, 4)
    :assert_mem_eq_imm(perf_p1_max_delta, 5)

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
