// test_main_loop.s — Focused dispatch tests for common/game_loop.s
//
// Verifies representative command dispatch paths using a deterministic
// harness that exits through the normal CMD_QUIT path.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(bootstrap)

.pc = $080E "Test Code"

.encoding "screencode_mixed"

.const DUNGEON_GEN_BUSY = 1

bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    ldx #12
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0830 "Main"

// Symbols normally provided by the full platform main or C128 helpers.
c128_select_tier_cache_slot:
    clc
    rts

entry_main:
    rts

exit_trampoline:
    rts

game_over_prompt:
    rts

tramp_level_generate:
    rts

generation_busy_begin:
    inc test_busy_begin_calls
    rts

generation_busy_tick:
    inc test_busy_tick_calls
    rts

generation_busy_end:
    inc test_busy_end_calls
    rts

tramp_game_over:
    rts

wizard_reset_session_state:
    rts

wizard_wall_walk_active:
    lda #0
    rts

cmd_wizard_entry:
    inc test_wizard_calls
    rts

save_game:
    rts

disk_prompt_save:
    rts

disk_prompt_game:
    rts

delete_savefile:
    rts

.label tramp_ui_char_display = ui_char_display
.label tramp_ui_inv_display = ui_inv_display
.label tramp_ui_help_display = ui_help_display
.label tramp_ui_equip_display = ui_equip_display
.label tramp_store_init_all = store_init_all
.label tramp_store_restock_all = store_restock_all
.label tramp_store_enter = store_enter
.label tramp_player_create = player_create

tramp_ui_recall:
    rts

tramp_dig_ability:
    rts

#import "../../common/zeropage.s"
#import "../memory.s"
#import "../../common/reu.s"
#import "../screen.s"
#import "../../common/color.s"
#import "../config.s"
#import "../input.s"
#import "../../common/rng.s"
#import "../../common/math.s"
#import "../../common/tables.s"
#import "../../common/item_defs.s"
#import "../../common/player.s"
#import "../../common/ui_messages.s"
#import "../../common/ui_status.s"
#import "../../common/ui_help_clear.s"
#import "../../common/ui_character.s"
#import "../../common/stat_display.s"
.segmentdef TestCreateOverlay [start=$D000]
.segment TestCreateOverlay
#import "../../common/background_data.s"
#import "../../common/player_create.s"
.segment Default
#import "../../common/sound.s"
#import "../../common/dungeon_data.s"
#import "../../common/dungeon_gen.s"
#import "../../common/huffman.s"
#import "../../common/dungeon_features.s"
#import "../../common/monster.s"
#import "../../common/tier_manager.s"
#import "../../common/overlay.s"
#import "../../common/monster_ai.s"
#import "../../common/recall.s"
#import "../../common/monster_magic.s"
#import "../../common/item.s"
#import "../../common/special_rooms.s"
#import "../../common/ego_items.s"
#import "../../common/special_rooms_stubs.s"
#import "../../common/player_items.s"
#import "../../common/spell_data.s"
#import "../../common/projectile.s"
#import "../../common/spell_effects.s"
#import "../../common/player_magic.s"
#import "../../common/ui_inventory.s"
#import "../../common/ui_recall.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/ranged_fire.s"
#import "../../common/throw.s"
#import "../../common/bash.s"
#import "../../common/tunnel.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
#import "../../common/store_data.s"
#import "../../common/store.s"
#import "../../common/ui_store.s"
#import "../../common/ui_help.s"
#import "../../common/game_loop.s"

save_welcome_str:
    .text "WELCOME BACK" ; .byte 0

tc_results: .fill 13, $ff

test_cmd_idx: .byte 0
test_cmd_len: .byte 0
test_cmd_budget: .byte 0
test_cmd_script: .fill 4, 0
test_case_idx: .byte 0

test_turn_calls: .byte 0
test_status_calls: .byte 0
test_render_local_calls: .byte 0
test_render_full_calls: .byte 0
test_viewport_calls: .byte 0
test_msg_clear_calls: .byte 0
test_do_look_calls: .byte 0
test_update_visibility_calls: .byte 0
test_screen_clear_calls: .byte 0
test_player_try_move_calls: .byte 0
test_last_move_cmd: .byte 0
test_get_dir_calls: .byte 0
test_door_open_calls: .byte 0
test_read_scroll_calls: .byte 0
test_cast_spell_calls: .byte 0
test_item_pickup_calls: .byte 0
test_wizard_calls: .byte 0
test_busy_begin_calls: .byte 0
test_busy_tick_calls: .byte 0
test_busy_end_calls: .byte 0

test_move_ok: .byte 0
test_dir_ok: .byte 0
test_open_ok: .byte 0
test_read_ok: .byte 0
test_cast_ok: .byte 0
test_pickup_ok: .byte 0
test_scene_dirty: .byte 0
test_stairs_tile: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

install_jump_patch:
    :PatchJump(generation_busy_begin_api, generation_busy_begin)
    :PatchJump(generation_busy_tick_api, generation_busy_tick)
    :PatchJump(generation_busy_end_api, generation_busy_end)
    :PatchJump(input_get_command, test_input_get_command)
    :PatchJump(msg_clear, test_msg_clear)
    :PatchJump(turn_post_action, test_turn_post_action)
    :PatchJump(status_draw, test_status_draw)
    :PatchJump(viewport_update, test_viewport_update)
    :PatchJump(update_visibility, test_update_visibility)
    :PatchJump(render_local_area, test_render_local_area)
    :PatchJump(render_viewport, test_render_viewport)
    :PatchJump(player_try_move, test_player_try_move)
    :PatchJump(item_read_scroll, test_item_read_scroll)
    :PatchJump(player_cast_spell, test_player_cast_spell)
    :PatchJump(trap_check_at_player, test_trap_check)
    :PatchJump(check_player_on_store_door, test_check_store_door)
    :PatchJump(check_stairs_at_player, test_check_stairs_at_player)
    :PatchJump(do_look, test_do_look)
    :PatchJump(get_direction_target, test_get_direction_target)
    :PatchJump(door_try_open, test_door_try_open)
    :PatchJump(item_pickup, test_item_pickup)
    :PatchJump(screen_clear, test_screen_clear)
    :PatchJump(screen_clear_row, test_screen_clear_row)
    :PatchJump(overlay_load, test_overlay_load)
    :PatchJump(level_change_generate_current, test_level_change_generate_current)
    rts

reset_state:
    lda #0
    sta test_cmd_idx
    sta test_cmd_len
    sta test_case_idx
    sta test_turn_calls
    sta test_status_calls
    sta test_render_local_calls
    sta test_render_full_calls
    sta test_viewport_calls
    sta test_msg_clear_calls
    sta test_do_look_calls
    sta test_update_visibility_calls
    sta test_screen_clear_calls
    sta test_player_try_move_calls
    sta test_last_move_cmd
    sta test_get_dir_calls
    sta test_door_open_calls
    sta test_read_scroll_calls
    sta test_cast_spell_calls
    sta test_item_pickup_calls
    sta test_wizard_calls
    sta test_busy_begin_calls
    sta test_busy_tick_calls
    sta test_busy_end_calls
    sta test_move_ok
    sta test_dir_ok
    sta test_open_ok
    sta test_read_ok
    sta test_cast_ok
    sta test_pickup_ok
    sta test_scene_dirty
    sta test_stairs_tile
    sta zp_game_flags
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
    lda #6
    sta test_cmd_budget
    jsr main_loop
    rts

test_input_get_command:
    dec test_cmd_budget
    bne !budget_ok+
    ldx test_case_idx
    lda #$00
    sta tc_results,x
    jmp test_finish
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

test_msg_clear:
    inc test_msg_clear_calls
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
    rts

test_update_visibility:
    inc test_update_visibility_calls
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
    lda test_move_ok
    beq !blocked+
    sec
    rts
!blocked:
    clc
    rts

test_item_pickup:
    inc test_item_pickup_calls
    lda test_pickup_ok
    beq !fail+
    sec
    rts
!fail:
    clc
    rts

test_trap_check:
    clc
    rts

test_check_store_door:
    clc
    rts

test_check_stairs_at_player:
    lda test_stairs_tile
    lsr
    lsr
    lsr
    lsr
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

test_item_read_scroll:
    inc test_read_scroll_calls
    lda test_read_ok
    beq !fail+
    sec
    rts
!fail:
    clc
    rts

test_player_cast_spell:
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

test_screen_clear_row:
    rts

test_overlay_load:
    clc
    rts

test_level_change_generate_current:
    jsr generation_busy_begin
    jsr generation_busy_tick
    jsr generation_busy_tick
    jsr generation_busy_tick
    jsr generation_busy_tick
    lda #$ff
    sta zp_run_dir
    jsr test_screen_clear
    jsr test_viewport_update
    jsr test_render_viewport
    jsr generation_busy_end
    jsr test_status_draw
    rts

test_start:
    sei
    cld
    ldx #$ff
    txs

    ldx #12
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    jsr install_jump_patch

    // Test 1: REST consumes one turn and redraws status.
    jsr reset_state
    lda #0
    sta test_case_idx
    lda #CMD_REST
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_turn_calls
    cmp #1
    bne !t1_fail+
    lda test_status_calls
    cmp #1
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t1_done+
!t1_fail:
    lda #$00
    sta tc_results + 0
!t1_done:

    // Test 2: LOOK dispatches helper and consumes no turn.
    jsr reset_state
    lda #1
    sta test_case_idx
    lda #CMD_LOOK
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_do_look_calls
    cmp #1
    bne !t2_fail+
    lda test_turn_calls
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t2_done+
!t2_fail:
    lda #$00
    sta tc_results + 1
!t2_done:

    // Test 3: MOVE_N routes through player_try_move and consumes a turn on success.
    jsr reset_state
    lda #2
    sta test_case_idx
    lda #1
    sta test_move_ok
    lda #CMD_MOVE_N
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_player_try_move_calls
    cmp #1
    bne !t3_fail+
    lda test_last_move_cmd
    cmp #CMD_MOVE_N
    bne !t3_fail+
    lda test_turn_calls
    cmp #1
    bne !t3_fail+
    lda test_render_local_calls
    cmp #1
    bne !t3_fail+
    lda test_status_calls
    cmp #1
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t3_done+
!t3_fail:
    lda #$00
    sta tc_results + 2
!t3_done:

    // Test 4: OPEN with invalid direction consumes no turn and skips door handler.
    jsr reset_state
    lda #3
    sta test_case_idx
    lda #CMD_OPEN
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_get_dir_calls
    cmp #1
    bne !t4_fail+
    lda test_door_open_calls
    bne !t4_fail+
    lda test_turn_calls
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !t4_done+
!t4_fail:
    lda #$00
    sta tc_results + 3
!t4_done:

    // Test 5: OPEN success consumes a turn and reaches redraw tail.
    jsr reset_state
    lda #4
    sta test_case_idx
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
    bne !t5_fail+
    lda test_door_open_calls
    cmp #1
    bne !t5_fail+
    lda test_turn_calls
    cmp #1
    bne !t5_fail+
    lda test_viewport_calls
    cmp #1
    bne !t5_fail+
    lda test_render_full_calls
    cmp #1
    bne !t5_fail+
    lda test_status_calls
    cmp #1
    bne !t5_fail+
    lda #$01
    sta tc_results + 4
    jmp !t5_done+
!t5_fail:
    lda #$00
    sta tc_results + 4
!t5_done:

    // Test 6: READ success consumes a turn, updates visibility, and uses
    // local redraw when the scene is otherwise clean.
    jsr reset_state
    lda #5
    sta test_case_idx
    lda #1
    sta test_read_ok
    lda #CMD_READ
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_read_scroll_calls
    cmp #1
    bne !t6_fail+
    lda test_turn_calls
    cmp #1
    bne !t6_fail+
    lda test_update_visibility_calls
    cmp #1
    bne !t6_fail+
    lda test_viewport_calls
    cmp #1
    bne !t6_fail+
    lda test_render_local_calls
    cmp #1
    bne !t6_fail+
    lda test_render_full_calls
    bne !t6_fail+
    lda test_status_calls
    cmp #1
    bne !t6_fail+
    lda #$01
    sta tc_results + 5
    jmp !t6_done+
!t6_fail:
    lda #$00
    sta tc_results + 5
!t6_done:

    // Test 7: CAST no-turn restores the gameplay view without consuming a turn.
    jsr reset_state
    lda #6
    sta test_case_idx
    lda #CMD_CAST
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_cast_spell_calls
    cmp #1
    bne !t7_fail+
    lda test_turn_calls
    bne !t7_fail+
    lda test_screen_clear_calls
    cmp #1
    bne !t7_fail+
    lda test_viewport_calls
    cmp #1
    bne !t7_fail+
    lda test_render_full_calls
    cmp #1
    bne !t7_fail+
    lda test_status_calls
    cmp #1
    bne !t7_fail+
    lda #$01
    sta tc_results + 6
    jmp !t7_done+
!t7_fail:
    lda #$00
    sta tc_results + 6
!t7_done:

    // Test 8: REST redraws viewport when the turn changed the scene.
    jsr reset_state
    lda #7
    sta test_case_idx
    lda #1
    sta test_scene_dirty
    lda #CMD_REST
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_turn_calls
    cmp #1
    bne !t8_fail+
    lda test_viewport_calls
    cmp #1
    bne !t8_fail+
    lda test_render_full_calls
    cmp #1
    bne !t8_fail+
    lda test_status_calls
    cmp #1
    bne !t8_fail+
    lda #$01
    sta tc_results + 7
    jmp !t8_done+
!t8_fail:
    lda #$00
    sta tc_results + 7
!t8_done:

    // Test 9: MOVE with remote scene change falls back to full redraw.
    jsr reset_state
    lda #8
    sta test_case_idx
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
    bne !t9_fail+
    lda test_render_local_calls
    beq !t9_chk_full+
    jmp !t9_fail+
!t9_chk_full:
    lda test_viewport_calls
    cmp #1
    bne !t9_fail+
    lda test_render_full_calls
    cmp #1
    bne !t9_fail+
    lda test_status_calls
    cmp #1
    bne !t9_fail+
    lda #$01
    sta tc_results + 8
    jmp !t10+
!t9_fail:
    lda #$00
    sta tc_results + 8
    jmp !t10+

    // Test 10: PICKUP success consumes a turn and stays on the status-only tail
    // when the scene is otherwise clean.
!t10:
    jsr reset_state
    lda #9
    sta test_case_idx
    lda #1
    sta test_pickup_ok
    lda #CMD_PICKUP
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_item_pickup_calls
    cmp #1
    bne !t10_fail+
    lda test_turn_calls
    cmp #1
    bne !t10_fail+
    lda test_render_full_calls
    bne !t10_fail+
    lda test_viewport_calls
    bne !t10_fail+
    lda test_status_calls
    cmp #1
    bne !t10_fail+
    lda #$01
    sta tc_results + 9
    jmp !t11+
!t10_fail:
    lda #$00
    sta tc_results + 9
    jmp !t11+

    // Test 11: READ still falls back to full redraw when a room reveal is pending.
!t11:
    jsr reset_state
    lda #10
    sta test_case_idx
    lda #1
    sta test_read_ok
    sta vis_room_revealed
    lda #CMD_READ
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_update_visibility_calls
    cmp #1
    bne !t11_fail+
    lda test_viewport_calls
    cmp #1
    bne !t11_fail+
    lda test_render_local_calls
    bne !t11_fail+
    lda test_render_full_calls
    cmp #1
    bne !t11_fail+
    lda test_status_calls
    cmp #1
    bne !t11_fail+
    lda #$01
    sta tc_results + 10
    jmp !t12+
!t11_fail:
    lda #$00
    sta tc_results + 10
!t12:
    jsr reset_state
    lda #11
    sta test_case_idx
    lda #TILE_STAIRS_DN
    sta test_stairs_tile
    lda #CMD_STAIRS_DN
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_busy_begin_calls
    cmp #1
    bne !t12_fail+
    lda test_busy_end_calls
    cmp #1
    bne !t12_fail+
    lda test_busy_tick_calls
    beq !t12_fail+
    lda test_render_full_calls
    cmp #1
    bne !t12_fail+
    lda test_status_calls
    cmp #1
    bne !t12_fail+
    lda #$01
    sta tc_results + 11
    jmp !t13+
!t12_fail:
    lda #$00
    sta tc_results + 11
    jmp !t13+

    // Test 13: WIZARD dispatches to the wizard entry handler and consumes no turn.
!t13:
    jsr reset_state
    lda #12
    sta test_case_idx
    lda #CMD_WIZARD
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_wizard_calls
    cmp #1
    bne !t13_fail+
    lda test_turn_calls
    bne !t13_fail+
    lda #$01
    sta tc_results + 12
    jmp test_finish
!t13_fail:
    lda #$00
    sta tc_results + 12
    jmp test_finish
