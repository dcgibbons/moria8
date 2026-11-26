#importonce
// Shared runtime string for Slow Monster. Kept out of the spell overlay
// because C64/C128 death overlays are byte-tight.

pmx_slow_monster_msg:
    .text "It slows." ; .byte 0
