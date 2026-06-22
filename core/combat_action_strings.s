#importonce
// Shared combat action words used by the full combat engine and compact
// platform overlays that cannot import the full combat implementation.

cmb_you_str:        .text "You " ; .byte 0
cmb_the_str:        .text " the " ; .byte 0
cmb_the_cap_str:    .text "The " ; .byte 0
cmb_hit_str:        .text "hit" ; .byte 0
cmb_miss_str:       .text "miss" ; .byte 0
cmb_kill_str:       .text "have slain" ; .byte 0
cmb_hits_you_str:   .text " hits you." ; .byte 0
cmb_misses_you_str: .text " misses you." ; .byte 0
cmb_period:         .byte $2e, 0
