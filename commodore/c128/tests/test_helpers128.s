#importonce
// test_helpers128.s — Mock labels for unit test isolation

#import "../hal/layout.s"

.label kernal_irq_vec_lo = $03fe
.label kernal_irq_vec_hi = $03ff
.label c128_kernal_irq_tail_runtime_owned = $03fd

// C128 unit tests often provide local input stubs instead of importing the
// product input backend. Keep those stubs on the same modal-input HAL policy.
.const hal_input_kbdbuf_count = $d0
.const hal_input_modal_dismiss_uses_fast_key = true
.const hal_input_modal_escape_primary = $ae
.const hal_input_modal_escape_secondary = $03
.const hal_input_flush_run_cancel_buffer = false

hal_input_followup_prepare:
    rts

msg_show_more:
    clc
    rts
