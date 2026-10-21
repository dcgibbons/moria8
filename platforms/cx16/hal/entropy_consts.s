#importonce
// Commander X16 entropy inputs: VIA1 free-running Timer 1 & Timer 2 registers
// ($9F04-$9F09), mixed with zp_entropy (ticked in the input polling loop) by
// core/rng.s::rng_seed.

.const hal_entropy_timer0_lo = $9f04
.const hal_entropy_timer0_hi = $9f05
.const hal_entropy_timer1_lo = $9f08
.const hal_entropy_timer1_hi = $9f09
