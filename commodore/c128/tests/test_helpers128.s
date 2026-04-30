#importonce
// test_helpers128.s — Mock labels for unit test isolation

.label kernal_irq_vec_lo = $03fe
.label kernal_irq_vec_hi = $03ff
.label c128_kernal_irq_tail_runtime_owned = $03fd

msg_show_more:
    clc
    rts
