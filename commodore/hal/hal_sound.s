#importonce
// Sound contract.
//
// Required exports per platform:
//   hal_sound_init
//   hal_sound_play
//   hal_sound_stop
//   hal_sound_update
//
// A = semantic sound effect ID on hal_sound_play. Platform code owns SID/TED
// register programming and any stuck-tone cleanup.
