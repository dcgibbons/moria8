#importonce
// trap_effects.s — Shared floor-trap runtime effects.

// ============================================================
// trap_trigger — Execute a trap's effect
// Input: X = trap table index (trap_type[X] has the type)
// ============================================================
trap_trigger:
    #import "trap_effects_body.s"
