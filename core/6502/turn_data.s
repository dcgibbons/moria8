#importonce
// turn_data.s — Tables and state for turn.s's HP regeneration and poison
// ticks. turn.s imports it; a platform whose turn.s segment is full imports
// it first, elsewhere (Apple IIe: resident main RAM).

// HP regeneration: VMS Moria constants.inc player$regen_*, scaled by 2^16 as
// in Umoria config.cpp PLAYER_REGEN_*
.const REGEN_NORMAL = 197       // 0.0030 x max HP per turn: full or hungry
.const REGEN_WEAK   = 98        // 0.0015: weak
.const REGEN_FAINT  = 33        // 0.0005: faint
.const REGEN_HPBASE = 1442      // 0.0220 HP per turn on top of the rate

// Poison damage by con_adj -4..4 (VMS moria.inc): HP every turn, or $80 + n
// for 1 HP on turns where turn mod n = 0.
poison_damage:
    .byte 4, 3, 3, 2, 1, $82, $82, $82, $83

// Regen rate x 2^16 per max HP by hunger state (VMS constants.inc
// player$regen_*; Umoria config.cpp PLAYER_REGEN_*). Hungry regenerates at
// the full rate.
regen_factor:
    .byte REGEN_NORMAL, REGEN_NORMAL, REGEN_WEAK, REGEN_FAINT
.assert "regen_factor follows HUNGER_*", HUNGER_FULL == 0 && HUNGER_HUNGRY == 1 && HUNGER_WEAK == 2 && HUNGER_FAINT == 3, true

// Low byte of the HP regeneration fraction; zp_regen_frac (saved with the
// game) holds the high byte. Cleared on new game and load.
regen_frac_lo: .byte 0
