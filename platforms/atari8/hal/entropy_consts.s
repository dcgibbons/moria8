#importonce
// Atari 8-bit hardware entropy sources (POKEY RANDOM $D20A and ANTIC VCOUNT $D40B).

.label hal_entropy_timer0_lo = $d20a
.label hal_entropy_timer0_hi = $d40b
.label hal_entropy_timer1_lo = $d20a
.label hal_entropy_timer1_hi = $d20a
