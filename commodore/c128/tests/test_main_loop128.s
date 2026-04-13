#importonce
// test_main_loop128.s — Focused dispatch tests for common/game_loop.s on C128

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0300 "Test Stub"

test_start:
    jmp test_entry

.pc = $3000 "Test Code"

.encoding "screencode_mixed"

.const TILE_STAIRS_DN = $90

.macro MapRead_ptr0_y() {
    jsr mmu_safe_map_read_ptr0
}

c128_restore_runtime_vectors:
    rts

c128_restore_runtime_state_core:
    rts

c128_restore_runtime_state:
    rts

c128_restore_saved_banking:
    rts

c128_restore_runtime_guards:
    rts

rng_seed:
    rts

sound_play:
    rts

msg_init:
    rts

eff_fear_timer:
    .byte 0

safe_setbnk:
    rts

w_readst:
    rts

w_setlfs:
    rts

w_setnam:
    rts

w_open:
    rts

w_close:
    rts

w_chkin:
    rts

w_clrchn:
    rts

w_chrout:
    rts

w_load:
    rts

c128_stack_guard_begin:
    rts

c128_stack_guard_check:
    rts

c128_stack_guard_snapshot_banking:
    rts

entry_main:
    rts

exit_trampoline:
    inc test_exit_calls
    rts

game_over_prompt:
    inc test_game_over_prompt_calls
    rts

tramp_level_generate:
    rts

generation_busy_begin:
    rts

generation_busy_tick:
    rts

generation_busy_end:
    rts

tramp_game_over:
    inc test_tramp_game_over_calls
    rts

wizard_reset_session_state:
    rts

wizard_wall_walk_active:
    lda #0
    rts

disk_setup_done:
    .byte 0
disk_mode:
    .byte 0

cmd_wizard_entry:
    inc test_wizard_calls
    rts

save_game:
    inc test_save_game_calls
    lda test_save_success
    beq !save_fail+
    sec
    rts
!save_fail:
    clc
    rts

disk_prompt_save:
    lda disk_mode
    cmp #1
    bne !dps_count+
    lda disk_setup_done
    bne !dps_skip+
!dps_count:
    inc test_disk_prompt_save_calls
!dps_skip:
    rts

disk_prompt_game:
    inc test_disk_prompt_game_calls
    rts

tramp_disk_setup:
    inc test_tramp_disk_setup_calls
    lda test_disk_setup_success
    beq !tds_fail+
    lda #1
    sta disk_setup_done
    clc
    rts
!tds_fail:
    sec
    rts

delete_savefile:
    inc test_delete_savefile_calls
    rts

tramp_ui_help_display:
    inc test_help_calls
    inc test_help_clear_calls
    lda #2
    sta help_page_count
    lda test_help_calls
    cmp #3
    bcc *+5
    jmp test_fail
    rts

tramp_ui_inv_display:
    inc test_inventory_calls
    rts

tramp_ui_char_display:
    inc test_char_calls
    rts

tramp_ui_equip_display:
    inc test_equipment_calls
    rts

tramp_ego_put_suffix:
    rts

tramp_store_init_all:
    rts

tramp_store_restock_all:
    rts

tramp_store_enter:
    rts

tramp_player_create:
    rts

player_recalc_equipment:
    rts

overlay_load:
    sta current_overlay
    inc test_overlay_load_calls
    lda test_force_overlay_tier_reset
    beq !done+
    lda test_overlay_load_calls
    cmp #1
    bne !done+
    jsr tier_invalidate_state
    lda #0
    sta current_overlay
!done:
    clc
    rts

monster_spawn_level:
    lda current_tier
    sta test_spawn_tier_seen
    lda current_overlay
    sta test_spawn_overlay_seen
    rts

item_spawn_level:
    rts

level_entry_dir:
    .byte 0
current_tier:
    .byte 0
tier_loaded:
    .byte 0

screen_blank:
    rts

screen_clear:
    jmp test_screen_clear

item_init_identification:
    rts

player_try_move:
    jmp test_player_try_move

update_visibility:
    jmp test_update_visibility

trap_check_at_player:
    jmp test_trap_check

check_player_on_store_door:
    jmp test_check_store_door

check_stairs_at_player:
    lda test_stairs_tile
    lsr
    lsr
    lsr
    lsr
    rts

door_try_close:
    rts

do_search:
    rts

item_pickup:
    rts

item_drop:
    rts

item_wear:
    rts

item_takeoff:
    rts

item_eat:
    rts

item_quaff:
    rts

item_read_scroll:
    rts

item_aim_wand:
    rts

item_use_staff:
    rts

item_gain_spell:
    rts

item_refuel:
    rts

player_tunnel:
    rts

do_look:
    jmp test_do_look

run_check_stop:
    lda test_run_should_stop
    beq !continue+
    sec
    rts
!continue:
    clc
    rts

msg_show_more:
    rts

player_sync_from_zp:
    rts

rng_range:
    lda #0
    rts

ego_get_suffix_ptr:
    lda #0
    tay
    rts

item_get_name_ptr:
    lda #0
    tay
    rts

sound_init:
    rts

viewport_update:
    jmp test_viewport_update

render_local_area:
    jmp test_render_local_area

render_viewport:
    jmp test_render_viewport

render_viewport_scroll_delta:
    inc test_render_scroll_delta_calls
    lda test_scroll_delta_success
    beq !fail+
    sec
    rts
!fail:
    clc
    rts

screen_unblank:
    rts

status_draw:
    jmp test_status_draw

msg_print:
    rts

tier_invalidate_state:
    lda #0
    sta current_tier
    sta tier_loaded
    rts

tier_check_transition:
    inc test_tier_transition_calls
    lda zp_player_dlvl
    beq !town+
    cmp #9
    bcc !tier1+
    cmp #16
    bcc !tier2+
    cmp #26
    bcc !tier3+
    lda #4
    bne !store+
!tier3:
    lda #3
    bne !store+
!tier2:
    lda #2
    bne !store+
!tier1:
    lda #1
!store:
    sta current_tier
    lda #1
    sta tier_loaded
    rts
!town:
    lda #0
    sta current_tier
    sta tier_loaded
    rts

player_calc_stats:
    rts

player_calc_hp:
    rts

msg_clear:
    rts

turn_post_action:
    jmp test_turn_post_action

ui_help_clear_all:
    jmp test_ui_help_clear_all
help_page_idx: .byte 0
help_page_count: .byte 1

tramp_ui_recall:
    inc test_recall_calls
    rts

tramp_item_gain_spell:
    rts

creature_get_name:
    rts

tramp_dig_ability:
    rts

tramp_player_cast_spell:
    jmp test_tramp_player_cast_spell

tramp_player_pray:
    rts

tramp_magic_check_new_spells:
    rts

tramp_ranged_fire:
    rts

tramp_player_tunnel:
    jmp player_tunnel

tramp_throw_item:
    rts

tramp_bash_command:
    rts

player_search_mode_off:
    lda player_data + 54
    and #$ef
    sta player_data + 54
    rts

player_search_mode_on:
    lda player_data + 54
    ora #$10
    sta player_data + 54
    rts

player_search_clear_transient_state:
    jsr player_search_mode_off
    lda #0
    sta zp_search_count
    rts

player_move_maybe_passive_search:
    rts

search_scan_effective_silent:
    inc test_search_scan_calls
    clc
    rts

c128_preload_fn_len: .byte 0
c128_kernal_return_mmu: .byte 0
c128_kernal_return_port0: .byte 0
c128_kernal_return_port1: .byte 0
kernal_irq_vec_lo: .byte 0
kernal_irq_vec_hi: .byte 0
safe_irq_restore: rts
kernal_hw_irq_vec_lo: .byte 0
kernal_hw_irq_vec_hi: .byte 0
kernal_hw_nmi_vec_lo: .byte 0
kernal_hw_nmi_vec_hi: .byte 0
c128_preload_status: .byte 0
c128_stack_guard_canary_lo: .byte $a5
c128_stack_guard_expected: .byte 0
c128_stack_guard_actual: .byte 0
c128_stack_guard_stage: .byte 0
c128_stack_guard_canary_hi: .byte $5a
c128_stack_guard_port0: .byte 0
c128_stack_guard_port1: .byte 0
c128_stack_guard_mmu: .byte 0
c128_stack_guard_ret_lo: .byte 0
c128_stack_guard_ret_hi: .byte 0
c128_stack_guard_fail_code: .byte 0
c128_stack_guard_substage: .byte 0
c128_cache_enabled: .byte 0
c128_cache_tiers_ready: .byte 0
c128_cache_overlays_ready: .byte 0
c128_cache_failed: .byte 0
c128_cache_tier_bits: .byte 0
c128_cache_overlay_bits: .byte 0
c128_cache_test_skip_tier: .byte 0
c128_cache_test_skip_overlay: .byte 0
ovl_cache_base_lo: .byte 0
ovl_cache_base_hi: .byte 0
ovl_ready_mask:
    .byte 0, %00000001, %00000010, %00000100, %00001000, %00010000, %00100000
.const SFX_PICKUP = 0
.const SPELL_MAGE = 1
.const OVL_DUNGEON_GEN = 4
.const EQUIP_WEAPON = 22
.const EQUIP_BODY = 23
.const EQUIP_LIGHT = 28
.const ICAT_DIGGING = 0
.const INPUT_ROW = 24
.const FLAG_LIT = $08
.const MAX_CREATURES = 65
.const PL_FLAGS = 54
.const PL_DLEVEL = 20
.const PL_MAX_DLVL = 56
.const PL_LIGHT_RAD = 55
.const PL_SPELL_TYPE = 60
.const PL_TODMG = 41
.const PLF_SEARCHING = $10
current_overlay: .byte 0
ovl_fn_addr_lo: .byte 0, 0, 0, 0, 0, 0
ovl_fn_addr_hi: .byte 0, 0, 0, 0, 0, 0
ovl_fn_len:     .byte 0, 0, 0, 0, 0, 0
ovl_reu_start_lo: .byte 0, 0, 0, 0, 0, 0, 0
ovl_reu_start_hi: .byte 0, 0, 0, 0, 0, 0, 0
ovl_reu_size_lo:  .byte 0, 0, 0, 0, 0, 0, 0
ovl_reu_size_hi:  .byte 0, 0, 0, 0, 0, 0, 0
ol_target:        .byte 0
// Local test map stub: keep the synthetic map below $C000 so it stays in plain RAM
// even with C128 I/O visible. Width/height must match live MAP_COLS/MAP_ROWS.
.const TEST_MAP_COLS = 198
.const TEST_MAP_ROWS = 66
map_row_lo: .fill TEST_MAP_ROWS, <($8000 + i * TEST_MAP_COLS)
map_row_hi: .fill TEST_MAP_ROWS, >($8000 + i * TEST_MAP_COLS)
player_data: .fill 80, 0
player_move_relocated: .byte 0
it_category: .fill 256, 0
inv_item_id: .fill 30, 0
inv_ego: .fill 30, 0
inv_qty: .fill 30, 0
inv_p1: .fill 30, 0
inv_flags: .fill 30, 0
uinv_filter: .byte $ff
tun_dig_ability: .byte 0
old_player_x: .byte 0
old_player_y: .byte 0
old_view_x: .byte 0
old_view_y: .byte 0
run_was_lit: .byte 0
cr_display: .fill MAX_CREATURES, 0
recall_kills: .fill MAX_CREATURES, 0
recall_deaths: .fill MAX_CREATURES, 0
recall_attacks: .fill MAX_CREATURES, 0
recall_spells: .fill MAX_CREATURES, 0

#import "../../common/zeropage.s"
#import "../memory128.s"
#import "../input128.s"
#import "../../common/game_loop.s"

save_welcome_str:
    .text "WELCOME BACK" ; .byte 0

test_cmd_idx: .byte 0
test_cmd_len: .byte 0
test_cmd_budget: .byte 0
test_cmd_script: .fill 4, 0
test_turn_calls: .byte 0
test_status_calls: .byte 0
test_render_local_calls: .byte 0
test_render_full_calls: .byte 0
test_viewport_calls: .byte 0
test_render_scroll_delta_calls: .byte 0
test_do_look_calls: .byte 0
test_player_try_move_calls: .byte 0
test_last_move_cmd: .byte 0
test_get_dir_calls: .byte 0
test_door_open_calls: .byte 0
test_move_ok: .byte 0
test_dir_ok: .byte 0
test_open_ok: .byte 0
vis_room_revealed: .byte 0
test_wait_release_calls: .byte 0
test_get_key_calls: .byte 0
test_help_calls: .byte 0
test_inventory_calls: .byte 0
test_char_calls: .byte 0
test_equipment_calls: .byte 0
test_recall_calls: .byte 0
test_screen_clear_calls: .byte 0
test_help_clear_calls: .byte 0
test_game_over_prompt_calls: .byte 0
test_exit_calls: .byte 0
test_case_id: .byte 0
test_cast_spell_calls: .byte 0
test_search_scan_calls: .byte 0
test_wizard_calls: .byte 0
test_save_game_calls: .byte 0
test_disk_prompt_save_calls: .byte 0
test_disk_prompt_game_calls: .byte 0
test_tramp_disk_setup_calls: .byte 0
test_tramp_game_over_calls: .byte 0
test_delete_savefile_calls: .byte 0
msg_row1_col: .byte 0
test_cast_ok: .byte 0
test_save_success: .byte 0
test_disk_setup_success: .byte 0
test_move_relocated: .byte 0
test_move_disturbs_search: .byte 0
test_scene_dirty: .byte 0
test_scroll_delta_success: .byte 0
test_force_view_scroll_y: .byte 0
test_stairs_tile: .byte 0
test_run_should_stop: .byte 0
test_tier_transition_calls: .byte 0
test_force_overlay_tier_reset: .byte 0
test_overlay_load_calls: .byte 0
test_spawn_tier_seen: .byte 0
test_spawn_overlay_seen: .byte 0
test_key_script: .fill 4, 0
test_key_len: .byte 0
test_key_idx: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

install_jump_patch:
    :PatchJump(platform_main_loop_begin_api, test_platform_main_loop_begin_api)
    :PatchJump(platform_runtime_resync_api, test_platform_runtime_resync_api)
    :PatchJump(input_get_command, test_input_get_command)
    :PatchJump(input_wait_release, test_input_wait_release)
    :PatchJump(input_get_key, test_input_get_key)
    :PatchJump(input_get_key_fast, test_input_get_key)
    rts

reset_state:
    lda #0
    sta test_cmd_idx
    sta test_cmd_len
    sta test_turn_calls
    sta test_status_calls
    sta test_render_local_calls
    sta test_render_full_calls
    sta test_viewport_calls
    sta test_render_scroll_delta_calls
    sta test_do_look_calls
    sta test_player_try_move_calls
    sta test_last_move_cmd
    sta test_get_dir_calls
    sta test_door_open_calls
    sta test_move_ok
    sta test_dir_ok
    sta test_open_ok
    sta test_wait_release_calls
    sta test_get_key_calls
    sta test_help_calls
    sta test_inventory_calls
    sta test_char_calls
    sta test_equipment_calls
    sta test_recall_calls
    sta test_screen_clear_calls
    sta test_help_clear_calls
    sta test_game_over_prompt_calls
    sta test_exit_calls
    sta test_cast_spell_calls
    sta test_search_scan_calls
    sta test_wizard_calls
    sta test_save_game_calls
    sta test_disk_prompt_save_calls
    sta test_disk_prompt_game_calls
    sta test_tramp_disk_setup_calls
    sta test_tramp_game_over_calls
    sta test_delete_savefile_calls
    sta test_cast_ok
    sta test_save_success
    sta test_disk_setup_success
    sta test_move_relocated
    sta test_move_disturbs_search
    sta test_scene_dirty
    sta test_scroll_delta_success
    sta test_force_view_scroll_y
    sta test_stairs_tile
    sta test_run_should_stop
    sta test_tier_transition_calls
    sta test_force_overlay_tier_reset
    sta test_overlay_load_calls
    sta test_spawn_tier_seen
    sta test_spawn_overlay_seen
    sta test_key_len
    sta test_key_idx
    sta current_overlay
    sta player_move_relocated
    sta zp_search_count
    sta disk_setup_done
    sta disk_mode
    sta player_data + PL_FLAGS
    sta zp_game_flags
    sta zp_msg_flags
    sta msg_row1_col
    sta zp_eff_confuse
    sta zp_eff_paralyze
    sta vis_room_revealed
    lda #$ff
    sta zp_run_dir
    lda #10
    sta zp_player_x
    sta zp_player_y
    sta zp_view_x
    sta zp_view_y
    lda #1
    sta zp_player_dlvl
    rts

run_case:
    lda #8
    sta test_cmd_budget
    jsr main_loop
    rts

test_input_get_command:
    dec test_cmd_budget
    bne !budget_ok+
    jmp test_fail
!budget_ok:
    ldx test_cmd_idx
    cpx test_cmd_len
    bcc !script_ok+
    lda #CMD_QUIT
    sta zp_input_cmd
    rts
!script_ok:
    lda test_cmd_script,x
    inx
    stx test_cmd_idx
    sta zp_input_cmd
    rts

test_platform_main_loop_begin_api:
    rts

test_platform_runtime_resync_api:
    rts

test_turn_post_action:
    inc test_turn_calls
    lda test_scene_dirty
    sta turn_scene_dirty
    rts

test_status_draw:
    inc test_status_calls
    rts

test_viewport_update:
    inc test_viewport_calls
    lda test_force_view_scroll_y
    beq !done+
    inc zp_view_y
!done:
    rts

test_update_visibility:
    rts

test_render_local_area:
    inc test_render_local_calls
    rts

test_render_viewport:
    inc test_render_full_calls
    rts

test_player_try_move:
    sta test_last_move_cmd
    inc test_player_try_move_calls
    lda #0
    sta player_move_relocated
    lda test_move_ok
    beq !blocked+
    lda test_move_relocated
    beq !no_relocate+
    lda #1
    sta player_move_relocated
!no_relocate:
    lda test_move_disturbs_search
    beq !ok+
    jsr player_search_mode_off
!ok:
    sec
    rts
!blocked:
    clc
    rts

test_trap_check:
    clc
    rts

test_check_store_door:
    clc
    rts

test_do_look:
    inc test_do_look_calls
    rts

test_get_direction_target:
    inc test_get_dir_calls
    lda test_dir_ok
    beq !bad+
    sec
    rts
!bad:
    clc
    rts

test_door_try_open:
    inc test_door_open_calls
    lda test_open_ok
    beq !fail+
    sec
    rts
!fail:
    clc
    rts

test_input_wait_release:
    inc test_wait_release_calls
    rts

test_input_get_key:
    inc test_get_key_calls
    ldx test_key_idx
    cpx test_key_len
    bcs !default+
    lda test_key_script,x
    inx
    stx test_key_idx
    rts
!default:
    lda #$20
    rts

test_tramp_player_cast_spell:
    inc test_cast_spell_calls
    lda test_cast_ok
    beq !fail+
    sec
    rts
!fail:
    clc
    rts

test_screen_clear:
    inc test_screen_clear_calls
    rts

screen_clear_row:
    rts

test_ui_help_clear_all:
    inc test_help_clear_calls
    rts

mmu_safe_map_read_ptr0:
    lda (zp_ptr0),y
    rts

get_direction_target:
    jmp test_get_direction_target

door_try_open:
    jmp test_door_try_open

screen_put_string:
    rts

screen_put_char:
    rts

test_entry:
    sei
    cld
    ldx #$ff
    txs
    lda #MMU_ALL_RAM
    sta $ff00
    jsr install_jump_patch

    // Test 1: MOVE_N routes through player_try_move and consumes a turn.
    lda #1
    sta test_case_id
    jsr reset_state
    lda #1
    sta test_move_ok
    lda #CMD_MOVE_N
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_player_try_move_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_last_move_cmd
    cmp #CMD_MOVE_N
    beq *+5
    jmp test_fail
    lda test_turn_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_render_local_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_status_calls
    cmp #1
    beq *+5
    jmp test_fail

    // Test 2: REST consumes one turn and redraws status.
    lda #2
    sta test_case_id
    jsr reset_state
    lda #CMD_REST
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_turn_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_status_calls
    cmp #1
    beq *+5
    jmp test_fail

    // Test 3: LOOK dispatches helper and consumes no turn.
    lda #3
    sta test_case_id
    jsr reset_state
    lda #CMD_LOOK
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_do_look_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_turn_calls
    beq *+5
    jmp test_fail

    // Test 4: OPEN success consumes a turn and redraws.
    lda #4
    sta test_case_id
    jsr reset_state
    lda #1
    sta test_dir_ok
    sta test_open_ok
    lda #CMD_OPEN
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_get_dir_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_door_open_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_turn_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_viewport_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_render_full_calls
    cmp #1
    beq *+5
    jmp test_fail

    // Test 5: HELP waits for key release and redraws via help clear.
    lda #5
    sta test_case_id
    jsr reset_state
    lda #CMD_HELP
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    lda #2
    sta test_key_len
    lda #$20
    sta test_key_script + 0
    sta test_key_script + 1
    jsr run_case
    lda test_help_calls
    cmp #2
    beq *+5
    jmp test_fail
    lda test_wait_release_calls
    cmp #2
    beq *+5
    jmp test_fail
    lda test_get_key_calls
    cmp #2
    beq *+5
    jmp test_fail
    lda test_help_clear_calls
    cmp #3
    beq *+5
    jmp test_fail
    lda test_status_calls
    cmp #1
    beq *+5
    jmp test_fail

    // Test 6: INVENTORY uses dismiss gating and redraws via help-clear.
    lda #6
    sta test_case_id
    jsr reset_state
    lda #CMD_INVENTORY
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_inventory_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_wait_release_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_get_key_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_help_clear_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_status_calls
    cmp #1
    beq *+5
    jmp test_fail

    // Test 7: CHAR INFO dismisses with a key and restores gameplay via screen clear.
    lda #7
    sta test_case_id
    jsr reset_state
    lda #CMD_CHAR_INFO
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_char_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_wait_release_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_get_key_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_screen_clear_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_status_calls
    cmp #1
    beq *+5
    jmp test_fail

    // Test 8: CAST no-turn restores gameplay view without consuming a turn.
    lda #8
    sta test_case_id
    jsr reset_state
    lda #CMD_CAST
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_cast_spell_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_turn_calls
    beq *+5
    jmp test_fail
    lda test_screen_clear_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_viewport_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_render_full_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_status_calls
    cmp #1
    beq *+5
    jmp test_fail

    // Test 9: REST redraws viewport when the turn changed the scene.
    lda #9
    sta test_case_id
    jsr reset_state
    lda #1
    sta test_scene_dirty
    lda #CMD_REST
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_turn_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_viewport_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_render_full_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_render_local_calls
    beq *+5
    jmp test_fail
    lda test_status_calls
    cmp #1
    beq *+5
    jmp test_fail

    // Test 10: MOVE with remote scene change falls back to full redraw.
    lda #10
    sta test_case_id
    jsr reset_state
    lda #1
    sta test_move_ok
    sta test_scene_dirty
    lda #CMD_MOVE_E
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_turn_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_viewport_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_render_full_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_render_local_calls
    beq *+5
    jmp test_fail
    lda test_status_calls
    cmp #1
    beq *+5
    jmp test_fail

    // Test 11: WIZARD dispatches to the wizard handler and consumes no turn.
    lda #11
    sta test_case_id
    jsr reset_state
    lda #CMD_WIZARD
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_wizard_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_turn_calls
    beq *+5
    jmp test_fail

    // Test 12: level_change_generate_current reloads the dungeon overlay after
    // tier activation clobbers $E000, before monster spawning on deep levels.
    lda #12
    sta test_case_id
    jsr reset_state
    lda #49
    sta zp_player_dlvl
    lda #1
    sta test_force_overlay_tier_reset
    jsr level_change_generate_current
    lda test_tier_transition_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_overlay_load_calls
    cmp #2
    beq *+5
    jmp test_fail
    lda test_spawn_tier_seen
    cmp #4
    beq *+5
    jmp test_fail
    lda test_spawn_overlay_seen
    cmp #OVL_DUNGEON_GEN
    beq *+5
    jmp test_fail

    // Test 13: search-mode toggle sets the mode bit and consumes no turn.
    lda #13
    sta test_case_id
    jsr reset_state
    lda #CMD_SEARCH_MODE
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda player_data + PL_FLAGS
    and #PLF_SEARCHING
    bne *+5
    jmp test_fail
    lda test_turn_calls
    beq *+5
    jmp test_fail
    lda test_status_calls
    cmp #1
    beq *+5
    jmp test_fail

    // Test 14: successful movement in search mode consumes two turns and one search scan.
    lda #14
    sta test_case_id
    jsr reset_state
    lda #1
    sta test_move_ok
    sta test_move_relocated
    lda #PLF_SEARCHING
    sta player_data + PL_FLAGS
    lda #CMD_MOVE_N
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_turn_calls
    cmp #2
    beq *+5
    jmp test_fail
    lda test_search_scan_calls
    cmp #1
    beq *+5
    jmp test_fail

    // Test 15: attack-only movement disturbance clears search mode and skips extra search.
    lda #15
    sta test_case_id
    jsr reset_state
    lda #1
    sta test_move_ok
    sta test_move_disturbs_search
    lda #PLF_SEARCHING
    sta player_data + PL_FLAGS
    lda #CMD_MOVE_E
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_turn_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_search_scan_calls
    beq *+5
    jmp test_fail
    lda player_data + PL_FLAGS
    and #PLF_SEARCHING
    beq *+5
    jmp test_fail

    // Test 16: running in search mode keeps the mode active and applies the
    // same extra search-turn behavior on a one-step stop.
    lda #16
    sta test_case_id
    jsr reset_state
    lda #1
    sta test_move_ok
    lda #PLF_SEARCHING
    sta player_data + PL_FLAGS
    lda #1
    sta test_run_should_stop
    lda #CMD_RUN_E
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_player_try_move_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_last_move_cmd
    cmp #CMD_MOVE_E
    beq *+5
    jmp test_fail
    lda test_turn_calls
    cmp #2
    beq *+5
    jmp test_fail
    lda test_search_scan_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda zp_run_dir
    cmp #$ff
    beq *+5
    jmp test_fail
    lda player_data + PL_FLAGS
    and #PLF_SEARCHING
    cmp #PLF_SEARCHING
    beq *+5
    jmp test_fail

    // Test 17: load_resume_game clears transient search mode state.
    lda #17
    sta test_case_id
    jsr reset_state
    lda #PLF_SEARCHING
    sta player_data + PL_FLAGS
    lda #5
    sta zp_search_count
    lda #CMD_QUIT
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    lda #2
    sta test_cmd_budget
    jsr load_resume_game
    lda player_data + PL_FLAGS
    and #PLF_SEARCHING
    beq *+5
    jmp test_fail
    lda zp_search_count
    beq *+5
    jmp test_fail

    // Test 18: scroll + remote scene dirtiness must bypass the C128 delta path.
    lda #18
    sta test_case_id
    jsr reset_state
    lda #1
    sta test_move_ok
    sta test_scene_dirty
    sta test_scroll_delta_success
    sta test_force_view_scroll_y
    lda #CMD_MOVE_S
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_viewport_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_render_full_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_render_local_calls
    beq *+5
    jmp test_fail
    lda test_render_scroll_delta_calls
    beq *+5
    jmp test_fail
    lda test_status_calls
    cmp #1
    beq *+5
    jmp test_fail

    // Test 19: a successful CMD_SAVE in C128 one-drive flow still routes
    // through disk setup, save, and the shared game-return owner.
    lda #19
    sta test_case_id
    jsr reset_state
    lda #1
    sta test_disk_setup_success
    sta test_save_success
    sta disk_mode
    lda #CMD_SAVE
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_tramp_disk_setup_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_disk_prompt_save_calls
    beq *+5
    jmp test_fail
    lda test_save_game_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_disk_prompt_game_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_game_over_prompt_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_delete_savefile_calls
    beq *+5
    jmp test_fail

    // Test 20: a failed CMD_SAVE still routes through the shared game-return
    // owner before resuming gameplay.
    lda #20
    sta test_case_id
    jsr reset_state
    lda #1
    sta test_disk_setup_success
    sta test_move_ok
    sta disk_mode
    lda #CMD_SAVE
    sta test_cmd_script
    lda #CMD_MOVE_N
    sta test_cmd_script + 1
    lda #2
    sta test_cmd_len
    jsr run_case
    lda test_tramp_disk_setup_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_save_game_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_disk_prompt_save_calls
    beq *+5
    jmp test_fail
    lda test_disk_prompt_game_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_player_try_move_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_game_over_prompt_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_delete_savefile_calls
    beq *+5
    jmp test_fail

    // Test 21: player_died routes through the shared game-return owner after
    // death-screen disk I/O when disk setup is already complete.
    lda #21
    sta test_case_id
    jsr reset_state
    lda #1
    sta disk_setup_done
    sta disk_mode
    lda #7
    sta zp_death_source
    jsr player_died
    lda test_disk_prompt_save_calls
    beq *+5
    jmp test_fail
    lda test_tramp_game_over_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_disk_prompt_game_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_exit_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_delete_savefile_calls
    beq *+5
    jmp test_fail
    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    brk
