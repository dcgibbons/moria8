// test_fire_ball.s — Focused runtime tests for the Fire Ball spell row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tfb_results: .fill 3, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #2
!copy:
    lda tfb_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    brk

.pc = $0840 "Main"

#import "../../../../core/zeropage.s"
#import "../memory.s"
#import "../../common/reu.s"
#import "../screen.s"
#import "../../../../core/color.s"
#import "../config.s"
#import "../input.s"
#import "../../../../core/rng.s"
#import "../../../../core/math.s"
#import "../../../../core/tables.s"
#import "../../../../core/item_defs.s"
#import "../../../../core/player.s"
#import "../../../../core/ui_messages.s"
#import "../../../../core/ui_status.s"
#import "../../../../core/ui_help_clear.s"
#import "../../../../core/ui_character.s"
#import "../../../../core/stat_display.s"
.segmentdef TestCreateOverlay [start=$D000]
.segment TestCreateOverlay
#import "../../../../core/background_data.s"
#import "../../../../core/player_create.s"
.segment Default
#import "../../../../core/input_contract.s"
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "../../../../core/dungeon_gen.s"
#import "../../../../core/huffman.s"
#import "../../../../core/dungeon_features.s"
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/monster_ai.s"
#import "../../../../core/recall.s"
#import "../../../../core/monster_magic.s"
#import "../../../../core/item.s"
#import "../../../../core/special_rooms.s"
#import "../../../../core/ego_items.s"
#import "../../../../core/special_rooms_stubs.s"
#import "../../../../core/player_items.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../../../../core/player_magic_ball.s"
#import "../../../../core/ui_inventory.s"
#import "../../../../core/ui_equipment.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"

store_init_all:
    rts

store_restock_all:
    rts

store_enter:
    rts

ui_help_show_paged:
ui_help_display:
help_draw_line:
help_draw_hborder:
    rts
#import "../../../../core/ui_trampoline_stubs.s"

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

tfb_spell_exec_calls: .byte 0
tfb_huff_calls: .byte 0
tfb_last_huff_id: .byte 0
tfb_last_spell_idx: .byte $ff
tfb_kill_calls: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_get_direction_target_east:
    lda zp_player_x
    clc
    adc #1
    sta df_target_x
    lda zp_player_y
    sta df_target_y
    sec
    rts

test_huff_print_msg:
    stx tfb_last_huff_id
    inc tfb_huff_calls
    rts

test_combat_kill_message:
    inc tfb_kill_calls
    jsr monster_remove
    inc zp_dirty_count
    rts

test_tramp_fire_ball_execute:
    inc tfb_spell_exec_calls
    lda pm_spell_idx
    sta tfb_last_spell_idx
    lda #49
    jsr eff_ball
    rts

test_pm_select_book:
    lda #3
    sta pm_book_idx
    lda #<book_mask_3
    sta pm_book_mask_lo
    lda #>book_mask_3
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #28
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #18
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_reset_fire_ball_state:
    jsr player_init
    lda #0
    sta tfb_spell_exec_calls
    sta tfb_huff_calls
    sta tfb_last_huff_id
    sta tfb_kill_calls
    lda #$ff
    sta tfb_last_spell_idx

    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta pm_spell_type
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA

    lda #0
    sta player_data + PL_SPELLS_LEARNT_0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    lda #$10
    sta player_data + PL_SPELLS_LEARNT_3
    lda #0
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    rts

tv_setup_dark_room:
    jsr fill_map_rock
    jsr item_init_floor
    jsr monster_init_table
    lda #0
    sta vis_room_revealed
    lda #$ff
    sta vis_cached_room_idx
    lda #0
    sta room_count

    lda #1
    sta room_count
    lda #20
    sta room_x
    sta dg_room_x
    lda #10
    sta room_y
    sta dg_room_y
    lda #10
    sta room_w
    sta dg_room_w
    lda #6
    sta room_h
    sta dg_room_h
    lda #0
    sta room_lit
    jsr draw_dungeon_room
    jsr darken_rooms

    lda #22
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #12
    sta zp_player_y
    sta player_data + PL_MAP_Y
    lda #1
    sta zp_player_dlvl
    lda #0
    sta zp_eff_blind
    lda #1
    sta zp_light_radius
    sta player_data + PL_LIGHT_RAD
    lda #COL_BLACK
    sta zp_text_color
    jsr screen_clear
    jsr update_visibility
    jsr viewport_update
    jsr render_viewport
    rts

test_start:
    :PatchJump(get_direction_target, test_get_direction_target_east)
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(combat_kill_message, test_combat_kill_message)
    :PatchJump(test_spell_execute_selected, test_tramp_fire_ball_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: successful cast reaches spell slot 28, remains message-light,
    // kills a monster in the target area, spends 18 mana, and marks worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_fire_ball_state
    jsr tv_setup_dark_room
    lda #23
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #10
    jsr monster_spawn_one
    bcc !t1_fail+
    lda #23
    ldy #12
    jsr monster_find_at
    bcc !t1_fail+
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #8
    sta (zp_ptr0),y
    iny
    lda #0
    sta (zp_ptr0),y

    jsr player_cast_spell
    bcc !t1_fail+
    lda tfb_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tfb_last_spell_idx
    cmp #28
    bne !t1_fail+
    lda tfb_huff_calls
    bne !t1_fail+
    lda tfb_kill_calls
    cmp #1
    bne !t1_fail+
    lda #23
    ldy #12
    jsr monster_find_at
    bcs !t1_fail+
    lda zp_player_mp
    cmp #2
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #2
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$10
    beq !t1_fail+
    lda #$01
    sta tfb_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tfb_results + 0

    // Test 2: successful cast with no target area stays silent/no-effect
    // while still consuming mana and marking the spell worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_fire_ball_state
    jsr tv_setup_dark_room
    jsr player_cast_spell
    bcc !t2_fail+
    lda tfb_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda tfb_last_spell_idx
    cmp #28
    bne !t2_fail+
    lda tfb_huff_calls
    bne !t2_fail+
    lda tfb_kill_calls
    bne !t2_fail+
    lda zp_player_mp
    cmp #2
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #2
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$10
    beq !t2_fail+
    lda #$01
    sta tfb_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tfb_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not
    // execute, and leaves Fire Ball unworked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_fire_ball_state
    jsr tv_setup_dark_room
    lda #23
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #10
    jsr monster_spawn_one
    bcc !t3_fail+
    jsr player_cast_spell
    bcc !t3_fail+
    lda tfb_spell_exec_calls
    bne !t3_fail+
    lda tfb_huff_calls
    cmp #1
    bne !t3_fail+
    lda tfb_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda tfb_kill_calls
    bne !t3_fail+
    lda #23
    ldy #12
    jsr monster_find_at
    bcc !t3_fail+
    lda zp_player_mp
    cmp #2
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #2
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$10
    bne !t3_fail+
    lda #$01
    sta tfb_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta tfb_results + 2
    jmp test_finish
