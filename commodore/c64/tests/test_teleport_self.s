// test_teleport_self.s — Focused runtime tests for the Teleport Self spell row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 2, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #1
!copy:
    lda tc_results,x
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
#import "../../common/player_magic_feedback.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
#import "../../common/item_actions_overlay.s"
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

tts_spell_exec_calls: .byte 0
tts_huff_calls: .byte 0
tts_last_huff_id: .byte 0
tts_last_spell_idx: .byte $ff
tts_find_random_floor_calls: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tts_last_huff_id
    inc tts_huff_calls
    rts

test_tramp_spell_execute_selected:
    inc tts_spell_exec_calls
    lda pm_spell_idx
    sta tts_last_spell_idx
    jsr eff_teleport_self
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

test_pm_pick_visible_spell_e:
    lda #12
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #6
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_find_random_floor_teleport_self:
    inc tts_find_random_floor_calls
    lda #40
    sta df_target_x
    lda #30
    sta df_target_y
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

test_setup_teleport_self_room:
    jsr fill_map_rock
    lda #0
    sta vis_room_revealed
    sta tts_find_random_floor_calls

    lda #22
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #12
    sta zp_player_y
    sta player_data + PL_MAP_Y

    lda #TILE_FLOOR | FLAG_OCCUPIED
    ldx #12
    ldy #22
    jsr test_write_tile

    lda #TILE_FLOOR
    ldx #30
    ldy #40
    jsr test_write_tile
    rts

test_reset_teleport_self_spell_state:
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    lda #20
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda #0
    sta player_data + PL_SPELLS_LEARNT_0
    lda #$10
    sta player_data + PL_SPELLS_LEARNT_1
    lda #0
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    lda #0
    sta tts_spell_exec_calls
    sta tts_huff_calls
    sta tts_last_huff_id
    lda #$ff
    sta tts_last_spell_idx
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_spell_execute_selected)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_pick_visible_spell_e)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(find_random_floor, test_find_random_floor_teleport_self)

    // Test 1: successful cast relocates to the random floor target, updates
    // occupancy + redraw state, stays message-light, spends 6 mana, and marks
    // spell slot 12 worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_teleport_self_spell_state
    jsr test_setup_teleport_self_room
    jsr player_cast_spell
    bcc !t1_fail+
    lda tts_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tts_last_spell_idx
    cmp #12
    bne !t1_fail+
    lda tts_find_random_floor_calls
    cmp #1
    bne !t1_fail+
    lda zp_player_x
    cmp #40
    bne !t1_fail+
    lda zp_player_y
    cmp #30
    bne !t1_fail+
    lda tts_huff_calls
    bne !t1_fail+
    lda vis_room_revealed
    cmp #1
    bne !t1_fail+
    ldx #12
    ldy #22
    jsr test_read_tile
    and #FLAG_OCCUPIED
    bne !t1_fail+
    ldx #30
    ldy #40
    jsr test_read_tile
    and #FLAG_OCCUPIED
    beq !t1_fail+
    lda zp_player_mp
    cmp #14
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #14
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$10
    beq !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Teleport Self unworked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_teleport_self_spell_state
    jsr test_setup_teleport_self_room
    jsr player_cast_spell
    bcc !t2_fail+
    lda tts_spell_exec_calls
    bne !t2_fail+
    lda tts_find_random_floor_calls
    bne !t2_fail+
    lda zp_player_x
    cmp #22
    bne !t2_fail+
    lda zp_player_y
    cmp #12
    bne !t2_fail+
    lda tts_huff_calls
    cmp #1
    bne !t2_fail+
    lda tts_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t2_fail+
    lda vis_room_revealed
    bne !t2_fail+
    ldx #12
    ldy #22
    jsr test_read_tile
    and #FLAG_OCCUPIED
    beq !t2_fail+
    ldx #30
    ldy #40
    jsr test_read_tile
    and #FLAG_OCCUPIED
    bne !t2_fail+
    lda zp_player_mp
    cmp #14
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #14
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$10
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp test_finish
!t2_fail:
    lda #$00
    sta tc_results + 1
    jmp test_finish
