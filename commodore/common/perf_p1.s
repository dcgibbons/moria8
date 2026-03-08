// perf_p1.s — C128 movement responsiveness instrumentation (P1)
//
// Compile-time guarded by PERF_P1. When disabled, this file contributes no
// code/data and game behavior is unchanged.

#if PERF_P1

// KERNAL jiffy clock low byte (increments at video refresh rate: 50/60 Hz).
.const PERF_P1_JIFFY_LO = $a2

// Frame-delta histogram buckets: 0, 1, 2, >=3 frames.
perf_p1_hist_0:  .byte 0
perf_p1_hist_1:  .byte 0
perf_p1_hist_2:  .byte 0
perf_p1_hist_3p: .byte 0

// Path counters (16-bit): local renders, full redraws, full redraws due to scroll.
perf_p1_local_lo:  .byte 0
perf_p1_local_hi:  .byte 0
perf_p1_full_lo:   .byte 0
perf_p1_full_hi:   .byte 0
perf_p1_scroll_lo: .byte 0
perf_p1_scroll_hi: .byte 0

// Move transaction tracking.
perf_p1_moves:       .byte 0
perf_p1_start_frame: .byte 0
perf_p1_max_delta:   .byte 0
perf_p1_scroll_flag: .byte 0

// perf_p1_reset — Clear all counters/histograms.
// Clobbers: A
perf_p1_reset:
    lda #0
    sta perf_p1_hist_0
    sta perf_p1_hist_1
    sta perf_p1_hist_2
    sta perf_p1_hist_3p
    sta perf_p1_local_lo
    sta perf_p1_local_hi
    sta perf_p1_full_lo
    sta perf_p1_full_hi
    sta perf_p1_scroll_lo
    sta perf_p1_scroll_hi
    sta perf_p1_moves
    sta perf_p1_start_frame
    sta perf_p1_max_delta
    sta perf_p1_scroll_flag
    rts

// perf_p1_move_start — Mark movement command start frame.
// Clobbers: A
perf_p1_move_start:
    lda PERF_P1_JIFFY_LO
    sta perf_p1_start_frame
    inc perf_p1_moves
    lda #0
    sta perf_p1_scroll_flag
    rts

// perf_p1_mark_scroll — Mark current movement redraw as scroll-driven.
// Clobbers: A
perf_p1_mark_scroll:
    lda #1
    sta perf_p1_scroll_flag
    rts

// perf_p1_mark_local — Count one local-area render.
// Clobbers: A
perf_p1_mark_local:
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
    beq !b0+
    cmp #1
    beq !b1+
    cmp #2
    beq !b2+
    inc perf_p1_hist_3p
    rts
!b0:
    inc perf_p1_hist_0
    rts
!b1:
    inc perf_p1_hist_1
    rts
!b2:
    inc perf_p1_hist_2
    rts

#endif
