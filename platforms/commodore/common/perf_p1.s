#importonce
#import "perf_p1_defs.s"
// perf_p1.s — C128 movement responsiveness instrumentation (P1)
//
// Compile-time guarded by PERF_P1. When disabled, this file contributes no
// code/data and game behavior is unchanged.

#if PERF_P1

// perf_p1_reset — Clear all counters/histograms.
// Clobbers: A, X
perf_p1_reset:
    lda #0
    ldx #perf_p1_full_reason - perf_p1_data_start - 1
!clear:
    sta perf_p1_data_start,x
    dex
    bpl !clear-
    lda #PERF_P1_REASON_NONE
    sta perf_p1_full_reason
#if C128_TEST_PERF_P1_TRACE
    lda #PERF_P1_DECISION_NONE
    sta perf_p1_decision
#endif
    rts

// perf_p1_move_start — Mark movement command start frame.
// Preserves: A
perf_p1_move_start:
    pha
    lda PERF_P1_JIFFY_LO
    sta perf_p1_start_frame
    inc perf_p1_moves
    lda #0
    sta perf_p1_scroll_flag
    lda #PERF_P1_REASON_NONE
    sta perf_p1_full_reason
#if C128_TEST_PERF_P1_TRACE
    lda #PERF_P1_DECISION_NONE
    sta perf_p1_decision
#endif
    pla
    rts

// perf_p1_mark_scroll — Mark current movement redraw as scroll-driven.
// Clobbers: A
perf_p1_mark_scroll:
    lda #1
    sta perf_p1_scroll_flag
    rts

perf_p1_mark_scroll_reason_fallback:
    lda #PERF_P1_REASON_SCROLL_FALLBACK
    sta perf_p1_full_reason
#if C128_TEST_PERF_P1_TRACE
    lda #PERF_P1_DECISION_SCROLL_FALLBACK
    sta perf_p1_decision
#endif
    jmp perf_p1_mark_scroll

// perf_p1_mark_scroll_delta — Count one scroll handled via delta renderer.
// Clobbers: A
perf_p1_mark_scroll_delta:
    lda perf_p1_scroll_flag
    beq !done+
#if C128_TEST_PERF_P1_TRACE
    lda #PERF_P1_DECISION_SCROLL_DELTA
    sta perf_p1_decision
#endif
    inc perf_p1_scroll_delta_lo
    bne !done+
    inc perf_p1_scroll_delta_hi
!done:
    rts

// perf_p1_mark_scroll_fallback — Count one scroll that fell back to full redraw.
// Clobbers: A
perf_p1_mark_scroll_fallback:
    lda perf_p1_scroll_flag
    beq !done+
    inc perf_p1_scroll_fallback_lo
    bne !done+
    inc perf_p1_scroll_fallback_hi
!done:
    rts

perf_p1_mark_full_scroll_fallback_current_reason:
    jsr perf_p1_mark_scroll_fallback
    jmp perf_p1_mark_full_current_reason

// perf_p1_mark_local — Count one local-area render.
// Clobbers: A
perf_p1_mark_local:
#if C128_TEST_PERF_P1_TRACE
    lda #PERF_P1_DECISION_LOCAL
    sta perf_p1_decision
#endif
    inc perf_p1_local_lo
    bne !done+
    inc perf_p1_local_hi
!done:
    rts

// perf_p1_mark_full — Count one full redraw. If scroll flag is set, count it too.
// Clobbers: A
perf_p1_mark_full:
    inc perf_p1_full_lo
    bne !maybe_scroll+
    inc perf_p1_full_hi
!maybe_scroll:
    lda perf_p1_scroll_flag
    beq !done+
    inc perf_p1_scroll_lo
    bne !done+
    inc perf_p1_scroll_hi
!done:
    rts

// perf_p1_set_full_reason — Set the pending reason for the next full redraw.
// Input: A = PERF_P1_REASON_*
// Clobbers: none
perf_p1_set_full_reason:
    sta perf_p1_full_reason
    rts

// perf_p1_set_full_reason_if_none — Set pending reason only when no reason exists.
// Input: A = PERF_P1_REASON_*
// Clobbers: X
perf_p1_set_full_reason_if_none:
    ldx perf_p1_full_reason
    cpx #PERF_P1_REASON_NONE
    bne !done+
    sta perf_p1_full_reason
!done:
    rts

perf_p1_set_reason_scroll_fallback:
    lda #PERF_P1_REASON_SCROLL_FALLBACK
    jmp perf_p1_set_full_reason

perf_p1_set_reason_room_reveal:
    lda #PERF_P1_REASON_ROOM_REVEAL
#if C128_TEST_PERF_P1_TRACE
    ldx #PERF_P1_DECISION_ROOM_REVEAL
    stx perf_p1_decision
#endif
    jmp perf_p1_set_full_reason

perf_p1_set_reason_scene_dirty:
    lda #PERF_P1_REASON_SCENE_DIRTY
#if C128_TEST_PERF_P1_TRACE
    ldx #PERF_P1_DECISION_SCENE_DIRTY
    stx perf_p1_decision
#endif
    jmp perf_p1_set_full_reason

perf_p1_set_reason_command_forced:
    lda #PERF_P1_REASON_COMMAND_FORCED
#if C128_TEST_PERF_P1_TRACE
    ldx #PERF_P1_DECISION_COMMAND_FORCED
    stx perf_p1_decision
#endif
    jmp perf_p1_set_full_reason

perf_p1_set_reason_modal_restore:
    lda #PERF_P1_REASON_MODAL_RESTORE
#if C128_TEST_PERF_P1_TRACE
    ldx #PERF_P1_DECISION_MODAL_RESTORE
    stx perf_p1_decision
#endif
    jmp perf_p1_set_full_reason

perf_p1_set_reason_command_forced_if_none:
    lda #PERF_P1_REASON_COMMAND_FORCED
    jmp perf_p1_set_full_reason_if_none

perf_p1_mark_full_reason_transition:
    lda #PERF_P1_REASON_TRANSITION
#if C128_TEST_PERF_P1_TRACE
    ldx #PERF_P1_DECISION_TRANSITION
    stx perf_p1_decision
#endif
    jsr perf_p1_set_full_reason
    jmp perf_p1_mark_full_current_reason

perf_p1_mark_full_reason_modal_restore:
    lda #PERF_P1_REASON_MODAL_RESTORE
#if C128_TEST_PERF_P1_TRACE
    ldx #PERF_P1_DECISION_MODAL_RESTORE
    stx perf_p1_decision
#endif
    jsr perf_p1_set_full_reason
    jmp perf_p1_mark_full_current_reason

perf_p1_mark_full_reason_update_visibility:
    lda #PERF_P1_REASON_UPDATE_VISIBILITY
    jsr perf_p1_set_full_reason_if_none
#if C128_TEST_PERF_P1_TRACE
    lda #PERF_P1_DECISION_UPDATE_VISIBILITY
    sta perf_p1_decision
#endif
    jmp perf_p1_mark_full_current_reason

// perf_p1_mark_reason — Count one full-redraw reason bucket.
// Input: A = PERF_P1_REASON_* or PERF_P1_REASON_NONE
// Clobbers: A, X
perf_p1_mark_reason:
    cmp #PERF_P1_REASON_COUNT
    bcs !done+
    tax
    inc perf_p1_reason_lo,x
!done:
    rts

// perf_p1_mark_full_current_reason — Count a full redraw and its pending reason.
// Clobbers: A, X
perf_p1_mark_full_current_reason:
    jsr perf_p1_mark_full
    lda perf_p1_full_reason
    jsr perf_p1_mark_reason
    lda #PERF_P1_REASON_NONE
    sta perf_p1_full_reason
    rts

// perf_p1_mark_full_default_transition — Count a full redraw; classify untagged
// redraws as transitions.
// Clobbers: A, X
perf_p1_mark_full_default_transition:
    lda #PERF_P1_REASON_TRANSITION
    jsr perf_p1_set_full_reason_if_none
    jmp perf_p1_mark_full_current_reason

// perf_p1_render_viewport_effect_direct — PERF-only tail for overlay effects
// that already end by redrawing the whole viewport.
perf_p1_render_viewport_effect_direct:
    lda #PERF_P1_REASON_EFFECT_DIRECT
    jsr perf_p1_set_full_reason
#if C128_TEST_PERF_P1_TRACE
    lda #PERF_P1_DECISION_EFFECT_DIRECT
    sta perf_p1_decision
#endif
    jsr perf_p1_mark_full_current_reason
    jmp render_viewport

// perf_p1_move_end — Bucket frame delta and track max delta.
// Clobbers: A, X
perf_p1_move_end:
    lda PERF_P1_JIFFY_LO
    sec
    sbc perf_p1_start_frame
    tax

    // Track max observed delta.
    cmp perf_p1_max_delta
    bcc !bucket+
    sta perf_p1_max_delta

!bucket:
    txa
    cmp #3
    bcc !hist_index_ok+
    lda #3
!hist_index_ok:
    tax
    inc perf_p1_hist_0,x
perf_p1_move_end_sample_done:
perf_p1_sample_after_move:
    rts

#if C128_TEST_PERF_P1_TRACE
perf_p1_trace_reset_move_start:
    pha
    txa
    pha
    tya
    pha
    jsr perf_p1_reset
    jsr perf_p1_move_start
    pla
    tay
    pla
    tax
    pla
    rts
#endif

// perf_p1_dump_overlay — reserved debug key entrypoint.
// Counters are read through symbols/monitor for this audit to avoid growing the
// runtime-low payload into the floor-item table.
perf_p1_dump_overlay:
    rts

#endif
