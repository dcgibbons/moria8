// special_rooms_stubs.s — Direct-call trampoline stubs for test context
//
// In main.s, the real trampolines (tramp_*) do SEI + bank out KERNAL
// to call functions at $F000. In test builds, special_rooms.s is
// imported into normal program space, so we just forward directly.

tramp_assign_special_room:     jmp assign_special_room
tramp_vault_seal_entrance:     jmp vault_seal_entrance
tramp_spawn_special_room_monsters: jmp spawn_special_room_monsters
tramp_spawn_nest_gold:         jmp spawn_nest_gold
tramp_find_special_room:       jmp find_special_room
