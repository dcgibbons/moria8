#importonce
// BBC Master 128 entropy inputs: platform zero-page counters at $90-$93
// mixed with System VIA T1 ($FE44-$FE45) in input wait loops.

.label hal_entropy_timer0_lo = $90
.label hal_entropy_timer0_hi = $91
.label hal_entropy_timer1_lo = $92
.label hal_entropy_timer1_hi = $93
