#importonce
// CX16 bring-up entropy source.
//
// Use KERNAL jiffy-clock bytes for initial RNG seeding. This is not a hardware
// RNG; it is enough to mix user timing into the shared LFSR seed.

.label hal_entropy_timer0_lo = $a0
.label hal_entropy_timer0_hi = $a1
.label hal_entropy_timer1_lo = $a1
.label hal_entropy_timer1_hi = $a2
