// test_main_loop128.s — Focused dispatch tests for common/game_loop.s on C128

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

.encoding "screencode_mixed"

c128_restore_runtime_vectors:
    rts

c128_restore_runtime_guards:
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

tramp_game_over:
    rts

save_game:
    rts

disk_prompt_save:
    rts

disk_prompt_game:
    rts

delete_savefile:
    rts

tramp_ui_help_display:
    inc test_help_calls
    rts

tramp_ui_inv_display:
    inc test_inventory_calls
    rts

tramp_ui_char_display:
    rts

tramp_ui_equip_display:
    rts

tramp_store_init_all:
    rts

tramp_store_restock_all:
    rts

tramp_store_enter:
    rts

tramp_player_create:
    rts

tramp_ui_recall:
    rts

c128_preload_fn_len: .byte 0
c128_kernal_return_mmu: .byte 0
kernal_irq_vec_lo: .byte 0
kernal_irq_vec_hi: .byte 0
c128_preload_status: .byte 0
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
    .byte 0, %00000001, %00000010, %00000100, %00001000

#import "../../common/zeropage.s"
#import "../memory128.s"
#import "../../common/reu.s"
#import "../screen_vdc.s"
#import "../../common/color.s"
#import "../config128.s"
#import "../input128.s"
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
#import "../dungeon_render_vdc.s"
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

test_cmd_idx: .byte 0
test_cmd_len: .byte 0
test_cmd_budget: .byte 0
test_cmd_script: .fill 4, 0
test_turn_calls: .byte 0
test_status_calls: .byte 0
test_render_local_calls: .byte 0
test_render_full_calls: .byte 0
test_viewport_calls: .byte 0
test_do_look_calls: .byte 0
test_player_try_move_calls: .byte 0
test_last_move_cmd: .byte 0
test_get_dir_calls: .byte 0
test_door_open_calls: .byte 0
test_move_ok: .byte 0
test_dir_ok: .byte 0
test_open_ok: .byte 0
test_wait_release_calls: .byte 0
test_get_key_calls: .byte 0
test_help_calls: .byte 0
test_inventory_calls: .byte 0
test_screen_clear_calls: .byte 0
test_help_clear_calls: .byte 0
test_game_over_prompt_calls: .byte 0
test_exit_calls: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

install_jump_patch:
    :PatchJump(input_get_command, test_input_get_command)
    :PatchJump(turn_post_action, test_turn_post_action)
    :PatchJump(status_draw, test_status_draw)
    :PatchJump(viewport_update, test_viewport_update)
    :PatchJump(update_visibility, test_update_visibility)
    :PatchJump(render_local_area, test_render_local_area)
    :PatchJump(render_viewport, test_render_viewport)
    :PatchJump(player_try_move, test_player_try_move)
    :PatchJump(trap_check_at_player, test_trap_check)
    :PatchJump(check_player_on_store_door, test_check_store_door)
    :PatchJump(do_look, test_do_look)
    :PatchJump(get_direction_target, test_get_direction_target)
    :PatchJump(door_try_open, test_door_try_open)
    :PatchJump(input_wait_release, test_input_wait_release)
    :PatchJump(input_get_key, test_input_get_key)
    :PatchJump(screen_clear, test_screen_clear)
    :PatchJump(ui_help_clear_all, test_ui_help_clear_all)
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
    sta test_screen_clear_calls
    sta test_help_clear_calls
    sta test_game_over_prompt_calls
    sta test_exit_calls
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

test_turn_post_action:
    inc test_turn_calls
    rts

test_status_draw:
    inc test_status_calls
    rts

test_viewport_update:
    inc test_viewport_calls
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
    lda test_move_ok
    beq !blocked+
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
    lda #$20
    rts

test_screen_clear:
    inc test_screen_clear_calls
    rts

test_ui_help_clear_all:
    inc test_help_clear_calls
    rts

test_start:
    sei
    cld
    ldx #$ff
    txs
    lda #MMU_ALL_RAM
    sta $ff00
    jsr install_jump_patch

    // Test 1: MOVE_N routes through player_try_move and consumes a turn.
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

    // Test 2: LOOK dispatches helper and consumes no turn.
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

    // Test 3: OPEN success consumes a turn and redraws.
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

    // Test 4: HELP waits for key release and redraws via help clear.
    jsr reset_state
    lda #CMD_HELP
    sta test_cmd_script
    lda #1
    sta test_cmd_len
    jsr run_case
    lda test_help_calls
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

    // Test 5: INVENTORY uses dismiss gating and explicit screen clear.
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
    lda test_screen_clear_calls
    cmp #1
    beq *+5
    jmp test_fail
    lda test_status_calls
    cmp #1
    beq *+5
    jmp test_fail
    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
