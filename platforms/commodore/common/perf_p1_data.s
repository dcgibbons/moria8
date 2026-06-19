#importonce
#import "perf_p1_defs.s"
// perf_p1_data.s — PERF_P1 counter storage.

#if PERF_P1

// Frame-delta histogram buckets: 0, 1, 2, >=3 frames.
perf_p1_data_start:
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
perf_p1_scroll_delta_lo:    .byte 0
perf_p1_scroll_delta_hi:    .byte 0
perf_p1_scroll_fallback_lo: .byte 0
perf_p1_scroll_fallback_hi: .byte 0
perf_p1_reason_lo: .fill PERF_P1_REASON_COUNT, 0

// Move transaction tracking.
perf_p1_moves:       .byte 0
perf_p1_start_frame: .byte 0
perf_p1_max_delta:   .byte 0
perf_p1_scroll_flag: .byte 0
perf_p1_full_reason: .byte PERF_P1_REASON_NONE
perf_p1_data_end:

.assert "PERF P1 data block stays small", perf_p1_data_end - perf_p1_data_start < $40, true

#endif
