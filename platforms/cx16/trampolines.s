#importonce
// trampolines.s - CX16 resident-call adapters for shared gameplay.

tramp_spawn_special_room_monsters:
    rts

tramp_spawn_nest_gold:
    rts

tramp_find_special_room:
    clc
    rts

tramp_roll_ego_type:
    jmp roll_ego_type

tramp_ego_append_suffix:
    cmp #0
    beq !done+
    jsr ego_get_suffix_ptr
    ldx cmb_buf_idx
    ldy #0
!loop:
    lda (zp_ptr0),y
    beq !end+
    sta combat_msg_buf,x
    inx
    iny
    cpx #PLATFORM_COMBAT_MSG_BUF_SIZE
    bcs !end+
    jmp !loop-
!end:
    stx cmb_buf_idx
!done:
    rts

overlay_invalidate:
    rts

platform_copy_tier_names_to_pool:
    rts

viewport_update:
    rts

render_viewport:
    rts

render_viewport_scroll_delta:
    rts
