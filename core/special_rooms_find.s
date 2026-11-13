#importonce
// special_rooms_find.s — find_special_room, apart from special_rooms.s
// (2026-11-08).
// Owner: wherever every caller can reach it. On the C64, Plus/4 and Atari
// 8-bit the rest of special_rooms.s runs in OVL.GEN, but item_spawn_level
// calls this after pick_item_type has loaded OVL.CHEST into the same $E000
// window (PICKER_IN_CHEST_OVERLAY), so there it lives outside that window
// (the C64 and Atari: resident; the Plus/4: RuntimeBanked). Elsewhere it is
// imported with special_rooms.s.
// Lifetime: the session. State: reads room_count and room_type (resident).

// ============================================================
// find_special_room — Find room with given type
// Input:  A = room type to find (RT_PIT, RT_VAULT, RT_NEST)
// Output: X = room index, carry set = found
//         carry clear = not found
// Clobbers: X
// ============================================================
find_special_room:
    ldx room_count
    beq !fsr_fail+
    dex
!fsr_loop:
    cmp room_type,x
    beq !fsr_found+
    dex
    bpl !fsr_loop-
!fsr_fail:
    clc
    rts
!fsr_found:
    sec
    rts
