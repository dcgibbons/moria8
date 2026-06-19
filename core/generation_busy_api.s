#importonce
// generation_busy_api.s — startup-installable shim around the visible
// generation spinner.
//
// Default state is no-op so standalone tests can import gameplay modules
// without dragging in the full screen/UI helper stack. Shipping builds patch
// these entry points to JMP into generation_busy.s during startup.

generation_busy_begin_api:
    rts
    .byte 0, 0

generation_busy_tick_api:
    rts
    .byte 0, 0

generation_busy_end_api:
    rts
    .byte 0, 0

generation_busy_active_api:
    .byte 0

generation_busy_begin_if_dungeon_api:
    lda zp_player_dlvl
    beq !gbbd_done+
    jmp generation_busy_begin_api
!gbbd_done:
    rts

generation_busy_tick_if_dungeon_api:
    lda zp_player_dlvl
    beq !gbtd_done+
    jmp generation_busy_tick_api
!gbtd_done:
    rts

generation_busy_end_if_dungeon_api:
    lda zp_player_dlvl
    beq !gbed_done+
    jmp generation_busy_end_api
!gbed_done:
    rts
