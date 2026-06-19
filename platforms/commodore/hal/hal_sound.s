#importonce
// Sound contract.
//
// Required exports per platform:
//   hal_sound_init
//   hal_sound_play
//   hal_sound_stop
//   hal_sound_update
//
// Required sound constants per SID platform:
//   hal_sound_sid_base
//
// A = semantic sound effect ID on hal_sound_play. Platform code owns SID/TED
// register programming and any stuck-tone cleanup.
//
// Service contracts:
// - hal_sound_init: input none; output C=0 success/C=1 A=status; clobbers
//   A/X/Y allowed; silences hardware and initializes runtime sound state.
// - hal_sound_play: input A=semantic sound effect ID; output C=status; clobbers
//   A/X/Y allowed; maps effect to platform sound hardware.
// - hal_sound_stop: input none; output C=status; clobbers A/X/Y allowed;
//   silences all active voices/timers owned by the platform.
// - hal_sound_update: input none; output C=status; clobbers A/X/Y allowed;
//   advances any platform sound envelope/duration state.
