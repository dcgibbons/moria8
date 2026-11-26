// test_remove_fear_prayer.s — Focused runtime tests for the Remove Fear prayer row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    ldx #2
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
test_done_break:
    brk

.pc = $0840 "Main"

.const PIW_FILTER_MAGE_BOOK = $fc

.segmentdef TestUnused [start=$E100, min=$E100, max=$FFF9]
#import "../../../../core/6502/zeropage.s"
#import "../memory.s"
#import "../../common/reu.s"
#import "../screen.s"
#import "../../../../core/6502/color.s"
#import "../config.s"
#import "../input.s"
#import "../../../../core/6502/rng.s"
#import "../../../../core/6502/math.s"
#import "../../../../core/6502/tables.s"
#import "../../../../core/6502/item_defs.s"
#import "../../../../core/6502/player.s"
#import "../../../../core/6502/ui_messages.s"
#import "../../../../core/6502/ui_status.s"
#import "../../../../core/6502/ui_help_clear.s"
.segment TestUnused
#import "../../../../core/6502/ui_character.s"
#import "../../../../core/6502/stat_display.s"
.segment Default
.segmentdef TestCreateOverlay [start=$D000]
.segment TestCreateOverlay
#import "../../../../core/6502/background_data.s"
#import "../../../../core/6502/player_create.s"
.segment Default
#import "../../../../core/6502/sound.s"
#import "../../../../core/6502/dungeon_data.s"
#import "dungeon_gen_stubs.s"
#import "../../../../core/6502/huffman.s"
#import "../../../../core/6502/dungeon_features.s"
#import "chest_summons_stubs.s"
#import "../../../../core/6502/monster.s"
#import "../../../../core/6502/tier_manager.s"
#import "../../common/overlay.s"
.segment TestUnused
#import "../../../../core/6502/monster_ai.s"
.segment Default
#import "../../../../core/6502/recall.s"
#import "../../../../core/6502/monster_magic.s"
#import "../../../../core/6502/item.s"
#import "../../../../core/6502/special_rooms.s"
.segment TestUnused
#import "../../../../core/6502/ego_items.s"
.segment Default
#import "../../../../core/6502/special_rooms_stubs.s"
.segment TestUnused
#import "../../../../core/6502/projectile.s"
#import "../../../../core/6502/spell_effects.s"
.segment Default
#import "../../../../core/6502/spell_data.s"
#import "../../../../core/6502/player_magic_state.s"
#import "../../../../core/6502/player_magic_state_ops.s"
#import "../../../../core/6502/player_magic.s"
#import "../dungeon_render.s"
#import "../../../../core/6502/dungeon_los.s"
#import "../../../../core/6502/player_move.s"
.segment TestUnused
#import "../../../../core/6502/combat.s"
#import "../../../../core/6502/scene_mat_tile.s"
.segment Default
#import "../../../../core/6502/monster_attack.s"
#import "../../../../core/6502/turn.s"
#import "../../../../core/6502/ui_trampoline_stubs.s"

piw_filter: .byte 0

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

show_inv_and_select:
piw_prompt_filtered_inv:
piw_pick_filtered_inv_key:
piw_print_prompt_with_count:
player_recalc_equipment:
    rts

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

tc_results: .fill 3, $ff
trfp_spell_exec_calls: .byte 0
trfp_huff_calls: .byte 0
trfp_last_huff_id: .byte 0
trfp_last_spell_idx: .byte $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx trfp_last_huff_id
    inc trfp_huff_calls
    rts

test_eff_remove_fear:
    lda eff_fear_timer
    beq !done+
    lda #0
    sta eff_fear_timer
    ldx #HSTR_EFF_FEAR_END
    jsr huff_print_msg
!done:
    rts

test_tramp_remove_fear_prayer_execute:
    inc trfp_spell_exec_calls
    lda pm_spell_idx
    sta trfp_last_spell_idx
    jsr test_eff_remove_fear
    rts

test_pm_select_book:
    lda #0
    sta pm_book_idx
    lda #<book_mask_0
    sta pm_book_mask_lo
    lda #>book_mask_0
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
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

test_reset_remove_fear_prayer_state:
    jsr player_init
    lda #0
    sta trfp_spell_exec_calls
    sta trfp_huff_calls
    sta trfp_last_huff_id
    sta eff_fear_timer
    lda #$ff
    sta trfp_last_spell_idx

    lda #CLASS_PRIEST
    sta player_data + PL_CLASS
    lda #SPELL_PRIEST
    sta pm_spell_type
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_WIS_CUR
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
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_remove_fear_prayer_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: afraid prayer clears fear, reports the fear-end text, spends 2
    // mana, and marks Remove Fear worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_remove_fear_prayer_state
    lda #7
    sta eff_fear_timer
    jsr player_pray
    bcc !t1_fail+
    lda trfp_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda trfp_last_spell_idx
    cmp #3
    bne !t1_fail+
    lda eff_fear_timer
    bne !t1_fail+
    lda trfp_huff_calls
    cmp #1
    bne !t1_fail+
    lda trfp_last_huff_id
    cmp #HSTR_EFF_FEAR_END
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

    // Test 2: not-afraid prayer stays silent/no-op, still spends 2 mana, and
    // marks Remove Fear worked through the normal success path.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_remove_fear_prayer_state
    jsr player_pray
    bcc !t2_fail+
    lda trfp_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda trfp_last_spell_idx
    cmp #3
    bne !t2_fail+
    lda eff_fear_timer
    bne !t2_fail+
    lda trfp_huff_calls
    bne !t2_fail+
    lda zp_player_mp
    cmp #18
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #18
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$08
    beq !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not clear
    // fear, and leaves Remove Fear unworked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_remove_fear_prayer_state
    lda #7
    sta eff_fear_timer
    jsr player_pray
    bcc !t3_fail+
    lda trfp_spell_exec_calls
    bne !t3_fail+
    lda eff_fear_timer
    cmp #7
    bne !t3_fail+
    lda trfp_huff_calls
    cmp #1
    bne !t3_fail+
    lda trfp_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda zp_player_mp
    cmp #18
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #18
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$08
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta tc_results + 2
    jmp test_finish
