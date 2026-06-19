// test_light_area.s — Focused runtime tests for the Light Area spell row

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
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../../../../core/player_magic_feedback.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"
#import "../../../../core/ui_trampoline_stubs.s"

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

tla_spell_exec_calls: .byte 0
tla_huff_calls: .byte 0
tla_last_huff_id: .byte 0
tla_last_spell_idx: .byte $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tla_last_huff_id
    inc tla_huff_calls
    rts

test_input_get_key_d:
    lda #$44
    rts

test_input_get_modal_spell_a:
    lda #$41
    rts

test_tramp_light_area_execute:
    inc tla_spell_exec_calls
    lda pm_spell_idx
    sta tla_last_spell_idx
    ldx #HSTR_PIQ_LIGHT
    jmp huff_print_msg

test_pm_select_book:
    lda #0
    sta pm_book_idx
    lda #<book_mask_0
    sta pm_book_mask_lo
    lda #>book_mask_0
    sta pm_book_mask_hi
    sec
    rts

test_pm_pick_visible_spell_d:
    lda #3
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #2
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_reset_light_area_spell_state:
    jsr player_init
    lda #0
    sta tla_spell_exec_calls
    sta tla_huff_calls
    sta tla_last_huff_id
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
    lda #$08
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    rts

test_start:
    :PatchJump(input_get_key, test_input_get_key_d)
    :PatchJump(input_get_modal_dismiss_key, test_input_get_modal_spell_a)
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_light_area_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_pick_visible_spell, test_pm_pick_visible_spell_d)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: successful cast dispatches spell index 3, emits the explicit
    // light message, spends 2 mana, and marks Light Area worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_light_area_spell_state
    jsr player_cast_spell
    bcc !t1_fail+
    lda tla_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tla_last_spell_idx
    cmp #3
    bne !t1_fail+
    lda tla_huff_calls
    cmp #1
    bne !t1_fail+
    lda tla_last_huff_id
    cmp #HSTR_PIQ_LIGHT
    bne !t1_fail+
    lda zp_player_mp
    cmp #18
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #18
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$08
    beq !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Light Area unworked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_light_area_spell_state
    jsr player_cast_spell
    bcc !t2_fail+
    lda tla_spell_exec_calls
    bne !t2_fail+
    lda tla_huff_calls
    cmp #1
    bne !t2_fail+
    lda tla_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t2_fail+
    lda zp_player_mp
    cmp #18
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #18
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$08
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp test_finish
!t2_fail:
    lda #$00
    sta tc_results + 1
    jmp test_finish
