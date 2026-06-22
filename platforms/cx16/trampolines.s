#importonce
// trampolines.s - CX16 resident-call adapters for shared gameplay.

tramp_spawn_special_room_monsters:
    rts

tramp_spawn_nest_gold:
    rts

tramp_find_special_room:
    clc
    rts

tramp_assign_special_room:
    jmp assign_special_room

tramp_vault_seal_entrance:
    jmp vault_seal_entrance

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

tramp_ego_get_ac_bonus:
    jmp ego_get_ac_bonus

tramp_ego_apply_damage:
#if HAL_PLATFORM_NO_EGO_DAMAGE
    rts
#else
    jmp ego_apply_damage
#endif

tramp_ui_inv_select_display:
    jmp ui_inv_select_display

tramp_ui_equip_select_display:
    jmp ui_equip_select_display

#if CX16_IMPORT_SHARED_GAME_LOOP
tramp_ui_wizard_display:
    rts

tramp_ui_char_display:
    rts

tramp_ui_help_display:
    rts

tramp_ui_inv_display:
    jmp ui_inv_display

tramp_ui_equip_display:
tramp_ui_recall:
    rts

tramp_spell_list_display:
    rts

screen_flash_at:
    rts

tramp_spell_execute_selected:
    sec
    rts

tramp_store_restock_all:
    rts

tramp_store_init_all:
    rts

tramp_disk_setup:
    lda #1
    sta disk_setup_done
    rts

tramp_player_create:
    sec
    rts
#endif

tramp_level_generate:
    jmp level_generate

overlay_load:
    cmp #OVL_NONE
    beq !none+
    cmp #(CX16_OVERLAY_PRELOAD_COUNT + 1)
    bcs !invalid+
    sta cx16_overlay_requested
    tax
    lda cx16_overlay_common_to_slot,x
    beq !invalid+
    sta cx16_overlay_target
    tax
    lda cx16_overlay_ready,x
    bne !ready+
    lda cx16_overlay_target
    jsr cx16_load_overlay_to_bank
    bcs !fail+
!ready:
    lda cx16_overlay_requested
    sta current_overlay
!none:
    clc
    rts
!fail:
!invalid:
    lda #OVL_NONE
    sta current_overlay
    sec
    rts

#if CX16_IMPORT_SHARED_GAME_LOOP
disk_prompt_game:
    clc
    rts

disk_prompt_save:
    clc
    rts

save_game:
    sec
    rts

entry_main:
    rts
#endif

overlay_invalidate:
    lda #OVL_NONE
    sta current_overlay
    rts

platform_copy_tier_names_to_pool:
    rts

#if CX16_IMPORT_SHARED_GAME_LOOP
viewport_update:
    rts

render_viewport:
    rts

render_viewport_scroll_delta:
    rts

render_local_area:
    rts

tramp_item_read_scroll:
tramp_item_aim_wand:
tramp_item_use_staff:
tramp_item_refuel:
tramp_item_gain_spell:
tramp_ranged_fire:
tramp_throw_item:
tramp_bash_command:
tramp_disarm_command:
tramp_player_tunnel:
    sec
    rts

tramp_store_enter:
    rts

tramp_game_over_disk_setup_failed:
tramp_game_over_prepare:
tramp_game_over:
tramp_game_over_run:
    rts

tramp_game_over_disk_setup:
    jmp tramp_disk_setup

game_over_prompt:
    rts

winner_apply_retirement_bonus:
tramp_winner_royal:
    rts

old_view_x: .byte 0
old_view_y: .byte 0
old_player_x: .byte 0
old_player_y: .byte 0
disk_setup_done: .byte 0
#endif
