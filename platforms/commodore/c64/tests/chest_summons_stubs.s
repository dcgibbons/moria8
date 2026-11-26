#importonce
// Minimal chest summoning trap handoff stubs for C64 unit tests that import
// core/6502/dungeon_features.s without core/6502/chest_summons.s.

chest_pending_summons: .byte 0
chest_summon_x:        .byte 0
chest_summon_y:        .byte 0

chest_run_pending_summons:
    rts
