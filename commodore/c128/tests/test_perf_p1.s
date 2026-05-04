#importonce
// test_perf_p1.s — P1 movement responsiveness instrumentation checks (C128)

#if !PERF_P1
.error "test_perf_p1.s requires -define PERF_P1"
#endif
#define C128_TEST_PERF_P1_TRACE

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
render_viewport: rts

#import "../../common/perf_p1_data.s"
perf_p1_decision: .byte PERF_P1_DECISION_NONE
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
    ora perf_p1_reason_lo + PERF_P1_REASON_SCROLL_FALLBACK
    ora perf_p1_reason_lo + PERF_P1_REASON_ROOM_REVEAL
    ora perf_p1_reason_lo + PERF_P1_REASON_SCENE_DIRTY
    ora perf_p1_reason_lo + PERF_P1_REASON_COMMAND_FORCED
    ora perf_p1_reason_lo + PERF_P1_REASON_UPDATE_VISIBILITY
    ora perf_p1_reason_lo + PERF_P1_REASON_MODAL_RESTORE
    ora perf_p1_reason_lo + PERF_P1_REASON_TRANSITION
    ora perf_p1_reason_lo + PERF_P1_REASON_EFFECT_DIRECT
    ora perf_p1_moves
    ora perf_p1_max_delta
    beq !reset_ok+
    jmp test_fail
!reset_ok:
    lda perf_p1_full_reason
    cmp #PERF_P1_REASON_NONE
    beq !reset_reason_ok+
    jmp test_fail
!reset_reason_ok:

    // Case 1: delta=0, local render.
    lda #$10
    sta $a2
    jsr perf_p1_move_start
    jsr perf_p1_mark_local
    jsr perf_p1_move_end

    :assert_mem_eq_imm(perf_p1_hist_0, 1)
    :assert_mem_eq_imm(perf_p1_local_lo, 1)
    :assert_mem_eq_imm(perf_p1_moves, 1)
    :assert_mem_eq_imm(perf_p1_decision, PERF_P1_DECISION_LOCAL)

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
    :assert_mem_eq_imm(perf_p1_decision, PERF_P1_DECISION_SCROLL_DELTA)

    // Case 3: delta=2, scroll fallback to full redraw.
    lda #$30
    sta $a2
    jsr perf_p1_move_start
    jsr perf_p1_mark_scroll
    jsr perf_p1_mark_scroll_fallback
    lda #PERF_P1_REASON_SCROLL_FALLBACK
    jsr perf_p1_set_full_reason
    jsr perf_p1_mark_full_current_reason
    lda #$32
    sta $a2
    jsr perf_p1_move_end

    :assert_mem_eq_imm(perf_p1_hist_2, 1)
    :assert_mem_eq_imm(perf_p1_full_lo, 1)
    :assert_mem_eq_imm(perf_p1_scroll_lo, 1)
    :assert_mem_eq_imm(perf_p1_scroll_fallback_lo, 1)
    :assert_mem_eq_imm(perf_p1_reason_lo + PERF_P1_REASON_SCROLL_FALLBACK, 1)
    :assert_mem_eq_imm(perf_p1_decision, PERF_P1_DECISION_SCROLL_FALLBACK)

    // Case 4: delta=5, full redraw without scroll.
    lda #$40
    sta $a2
    jsr perf_p1_move_start
    lda #PERF_P1_REASON_SCENE_DIRTY
    jsr perf_p1_set_full_reason
    jsr perf_p1_mark_full_current_reason
    lda #$45
    sta $a2
    jsr perf_p1_move_end

    :assert_mem_eq_imm(perf_p1_hist_3p, 1)
    :assert_mem_eq_imm(perf_p1_full_lo, 2)
    :assert_mem_eq_imm(perf_p1_scroll_lo, 1)
    :assert_mem_eq_imm(perf_p1_scroll_delta_lo, 1)
    :assert_mem_eq_imm(perf_p1_scroll_fallback_lo, 1)
    :assert_mem_eq_imm(perf_p1_reason_lo + PERF_P1_REASON_SCENE_DIRTY, 1)
    :assert_mem_eq_imm(perf_p1_local_lo, 1)
    :assert_mem_eq_imm(perf_p1_moves, 4)
    :assert_mem_eq_imm(perf_p1_max_delta, 5)
    :assert_mem_eq_imm(perf_p1_decision, PERF_P1_DECISION_NONE)

    // Case 5: default transition classification only applies when unset.
    lda #PERF_P1_REASON_MODAL_RESTORE
    jsr perf_p1_set_full_reason
    jsr perf_p1_mark_full_default_transition

    :assert_mem_eq_imm(perf_p1_full_lo, 3)
    :assert_mem_eq_imm(perf_p1_reason_lo + PERF_P1_REASON_MODAL_RESTORE, 1)
    :assert_mem_eq_imm(perf_p1_reason_lo + PERF_P1_REASON_TRANSITION, 0)

    jsr perf_p1_mark_full_default_transition
    :assert_mem_eq_imm(perf_p1_full_lo, 4)
    :assert_mem_eq_imm(perf_p1_reason_lo + PERF_P1_REASON_TRANSITION, 1)

    // Case 6: direct trace decisions for explicit full-redraw helpers.
    jsr perf_p1_reset
    jsr perf_p1_mark_full_reason_transition
    :assert_mem_eq_imm(perf_p1_decision, PERF_P1_DECISION_TRANSITION)

    jsr perf_p1_reset
    jsr perf_p1_mark_full_reason_modal_restore
    :assert_mem_eq_imm(perf_p1_decision, PERF_P1_DECISION_MODAL_RESTORE)

    jsr perf_p1_reset
    jsr perf_p1_mark_full_reason_update_visibility
    :assert_mem_eq_imm(perf_p1_decision, PERF_P1_DECISION_UPDATE_VISIBILITY)

    jsr perf_p1_reset
    jsr perf_p1_set_reason_room_reveal
    :assert_mem_eq_imm(perf_p1_decision, PERF_P1_DECISION_ROOM_REVEAL)

    jsr perf_p1_reset
    jsr perf_p1_set_reason_scene_dirty
    :assert_mem_eq_imm(perf_p1_decision, PERF_P1_DECISION_SCENE_DIRTY)

    jsr perf_p1_reset
    jsr perf_p1_set_reason_command_forced
    :assert_mem_eq_imm(perf_p1_decision, PERF_P1_DECISION_COMMAND_FORCED)

    jsr perf_p1_reset
    jsr perf_p1_render_viewport_effect_direct
    :assert_mem_eq_imm(perf_p1_decision, PERF_P1_DECISION_EFFECT_DIRECT)

    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
