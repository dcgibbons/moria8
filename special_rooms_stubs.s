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

// Ego item trampoline stubs — ego_items.s is in normal program space in tests
tramp_roll_ego_type:           jmp roll_ego_type
tramp_ego_apply_damage:        jmp ego_apply_damage
tramp_ego_get_ac_bonus:        jmp ego_get_ac_bonus
// tramp_ego_append_suffix — Copy suffix string to combat_msg_buf (no banking needed in test)
tramp_ego_append_suffix:
    cmp #0
    beq !teas_stub_done+
    jsr ego_get_suffix_ptr      // zp_ptr0 = suffix string
    ldx cmb_buf_idx
    ldy #0
!teas_stub_loop:
    lda (zp_ptr0),y
    beq !teas_stub_end+
    sta combat_msg_buf,x
    inx
    iny
    cpx #41
    bcs !teas_stub_end+
    jmp !teas_stub_loop-
!teas_stub_end:
    stx cmb_buf_idx
!teas_stub_done:
    rts
// tramp_ego_put_suffix — Write suffix to screen (no banking needed in test)
// Home UI stub — home_enter is at $F000 in main build, just RTS in tests
home_enter:                        rts

tramp_ego_put_suffix:
    cmp #0
    beq !teps_stub_done+
    jsr ego_get_suffix_ptr
    ldy #0
!teps_stub_loop:
    lda (zp_ptr0),y
    beq !teps_stub_done+
    sty teps_stub_y
    jsr screen_put_char
    ldy teps_stub_y
    iny
    jmp !teps_stub_loop-
!teps_stub_done:
    rts
teps_stub_y: .byte 0
