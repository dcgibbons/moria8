#importonce
// monster_flags.s — Shared creature classification flag constants.

.const CF_ATTACK_ONLY = $01
.const CF_UNDEAD      = $02
.const CF_EVIL        = $04
.const CF_ANIMAL      = $08
.const CF_DRAGON      = $10
.const CF_GROUP       = $20   // Pack creature: spawns extras, wakes neighbors
.const CF_BREEDER     = $40   // Multiplying creature: chance to clone each turn
.const CF_INFRA       = $80   // Warm creature: visible to player infravision
