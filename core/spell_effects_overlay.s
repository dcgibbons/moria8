#importonce
#import "df_target_dir.s"
#import "df_target_row.s"
// spell_effects_overlay.s — Spell effects whose only product callers live in
// the spell-execution overlay (player_magic_execute_overlay.s) or the
// spell-overlay player_magic_utility.s.
// Owner: the spell overlay where it has room (C64 and Commander X16 OVL.SPELL);
// resident elsewhere, next to spell_effects.s (the Apple IIe keeps only
// eff_destroy_traps_doors in its spell overlay, EFF_DESTROY_TRAPS_DOORS_EXTERNAL;
// docs/CHEST_DESIGN.md step-8 notes). Lifetime: one cast. Callers: the spell
// dispatch tables only; nothing outside the spell overlay may call these.

#if !EFF_FIND_TRAPS_EXTERNAL
#import "eff_find_traps_cold.s"
#endif

#if EFF_DESTROY_TRAPS_DOORS_EXTERNAL
// Port-relocated: body lives in the port's cold overlay segment in main.s.
#else
#define EFF_DOORS_TRAPS_EMIT_DESTROY_ONLY
#import "eff_doors_traps_cold.s"
#undef EFF_DOORS_TRAPS_EMIT_DESTROY_ONLY
#endif
