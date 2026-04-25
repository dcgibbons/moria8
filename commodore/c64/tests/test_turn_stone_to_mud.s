// test_turn_stone_to_mud.s — Focused runtime tests for the Turn Stone to Mud spell row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
ttsm_results: .fill 3, $ff

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
    lda ttsm_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    brk

.pc = $0840 "Main"

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
#import "../../common/projectile.s"
#import "../../common/spell_effects.s"
#import "../../common/spell_data.s"
#import "../../common/player_magic_state.s"
#import "../../common/player_magic_state_ops.s"
#import "../../common/player_magic.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
#import "../../common/ui_trampoline_stubs.s"

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
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
    rts

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

ttsm_spell_exec_calls: .byte 0
ttsm_huff_calls: .byte 0
ttsm_last_huff_id: .byte 0
ttsm_last_spell_idx: .byte $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx ttsm_last_huff_id
    inc ttsm_huff_calls
    rts

test_get_direction_target_east:
    lda zp_player_x
    clc
    adc #1
    sta df_target_x
    lda zp_player_y
    sta df_target_y
    sec
    rts

test_tramp_turn_stone_to_mud_execute:
    inc ttsm_spell_exec_calls
    lda pm_spell_idx
    sta ttsm_last_spell_idx
    jsr eff_wall_to_mud
    rts

test_pm_select_book:
    lda #1
    sta pm_book_idx
    lda #<book_mask_1
    sta pm_book_mask_lo
    lda #>book_mask_1
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #15
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #7
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_write_tile:
    stx zp_ptr1
    sty zp_ptr1_hi
    pha
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_ptr1_hi
    pla
    sta (zp_ptr0),y
    rts

test_read_tile:
    stx zp_ptr1
    sty zp_ptr1_hi
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_ptr1_hi
    lda (zp_ptr0),y
    rts

test_reset_turn_stone_state:
    jsr player_init
    lda #0
    sta ttsm_spell_exec_calls
    sta ttsm_huff_calls
    sta ttsm_last_huff_id
    sta vis_room_revealed
    lda #$ff
    sta ttsm_last_spell_idx
    sta vis_cached_room_idx

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
    lda #$80
    sta player_data + PL_SPELLS_LEARNT_1
    lda #0
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3

    lda #22
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #12
    sta zp_player_y
    sta player_data + PL_MAP_Y
    lda #1
    sta zp_player_dlvl
    lda #0
    sta trap_count
    rts

test_setup_map_with_wall_east:
    jsr fill_map_rock
    lda #0
    sta vis_room_revealed

    lda #TILE_FLOOR
    ldx #11
!rows:
    cpx #14
    bcs !room_done+
    ldy #21
!cols:
    jsr test_write_tile
    iny
    cpy #25
    bcc !cols-
    inx
    jmp !rows-
!room_done:

    lda #TILE_WALL_H
    ldx #12
    ldy #23
    jsr test_write_tile
    rts

test_setup_map_with_floor_east:
    jsr fill_map_rock
    lda #0
    sta vis_room_revealed

    lda #TILE_FLOOR
    ldx #11
!rows2:
    cpx #14
    bcs !done+
    ldy #21
!cols2:
    jsr test_write_tile
    iny
    cpy #25
    bcc !cols2-
    inx
    jmp !rows2-
!done:
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(get_direction_target, test_get_direction_target_east)
    :PatchJump(test_spell_execute_selected, test_tramp_turn_stone_to_mud_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: successful cast reaches spell slot 15, converts the target wall
    // to lit/visited floor, stays message-light, spends 7 mana, and marks the
    // spell worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_turn_stone_state
    jsr test_setup_map_with_wall_east
    jsr player_cast_spell
    bcc !t1_fail+
    lda ttsm_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda ttsm_last_spell_idx
    cmp #15
    bne !t1_fail+
    lda ttsm_huff_calls
    bne !t1_fail+
    lda vis_room_revealed
    cmp #1
    bne !t1_fail+
    ldx #12
    ldy #23
    jsr test_read_tile
    cmp #(TILE_FLOOR | FLAG_VISITED | FLAG_LIT)
    bne !t1_fail+
    lda zp_player_mp
    cmp #13
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$80
    beq !t1_fail+
    lda #$01
    sta ttsm_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta ttsm_results + 0

    // Test 2: successful cast with a non-wall target stays silent/no-effect
    // while still consuming mana and marking the spell worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_turn_stone_state
    jsr test_setup_map_with_floor_east
    jsr player_cast_spell
    bcc !t2_fail+
    lda ttsm_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda ttsm_last_spell_idx
    cmp #15
    bne !t2_fail+
    lda ttsm_huff_calls
    bne !t2_fail+
    lda vis_room_revealed
    bne !t2_fail+
    ldx #12
    ldy #23
    jsr test_read_tile
    cmp #TILE_FLOOR
    bne !t2_fail+
    lda zp_player_mp
    cmp #13
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$80
    beq !t2_fail+
    lda #$01
    sta ttsm_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta ttsm_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Turn Stone to Mud unworked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_turn_stone_state
    jsr test_setup_map_with_wall_east
    jsr player_cast_spell
    bcc !t3_fail+
    lda ttsm_spell_exec_calls
    bne !t3_fail+
    lda ttsm_huff_calls
    cmp #1
    bne !t3_fail+
    lda ttsm_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    ldx #12
    ldy #23
    jsr test_read_tile
    cmp #TILE_WALL_H
    bne !t3_fail+
    lda zp_player_mp
    cmp #13
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$80
    bne !t3_fail+
    lda #$01
    sta ttsm_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta ttsm_results + 2
    jmp test_finish
