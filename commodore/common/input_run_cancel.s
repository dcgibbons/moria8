#importonce
// input_run_cancel.s — shared debounced run-cancel state machine

// input_run_cancel_reset — Reset run-cancel state
input_run_cancel_reset:
    lda #0
    sta irk_last_sample
    sta irk_stable
    rts

// input_run_process_sample — Debounced edge/state machine for running cancel
// Input: A = sampled held-state (0 = no key, nonzero = key held)
// Output: A = 1 on a newly-stable key-down edge, 0 otherwise
input_run_process_sample:
    beq !irps_norm_done+
    lda #1
!irps_norm_done:
    cmp irk_last_sample
    beq !irps_confirm+
    sta irk_last_sample
    lda #0
    rts

!irps_confirm:
    cmp irk_stable
    beq !irps_none+
    sta irk_stable
    beq !irps_none+
    rts
!irps_none:
    lda #0
    rts

irk_last_sample: .byte 0
irk_stable: .byte 0
