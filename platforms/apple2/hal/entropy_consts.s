#importonce
// Apple IIe entropy inputs: platform zero-page counters ticked in the input
// wait loop (seeded from keypress timing). Plain RAM reads for core/rng.s.

.label hal_entropy_timer0_lo = $90
.label hal_entropy_timer0_hi = $91
.label hal_entropy_timer1_lo = $92
.label hal_entropy_timer1_hi = $93
