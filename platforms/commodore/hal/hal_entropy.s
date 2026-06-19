#importonce
// Entropy/timer contract.
//
// Required constants per platform:
//   hal_entropy_timer0_lo
//   hal_entropy_timer0_hi
//   hal_entropy_timer1_lo
//   hal_entropy_timer1_hi
//
// Common RNG code owns the deterministic LFSR algorithm. Platform code owns
// which free-running timer bytes are safe entropy inputs on that target.
