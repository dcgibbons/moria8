// test_holy_word_prayer.s — Focused runtime tests for the Holy Word prayer row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Bootstrap"

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
    lda thw_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    jmp test_done_break

.pc = $0840 "Test Code"

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

thw_spell_exec_calls: .byte 0
thw_huff_calls: .byte 0
thw_last_huff_id: .byte 0
thw_last_spell_idx: .byte $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx thw_last_huff_id
    inc thw_huff_calls
    rts

eff_remove_fear:
    rts

test_tramp_holy_word_execute:
    inc thw_spell_exec_calls
    lda pm_spell_idx
    sta thw_last_spell_idx
    rts

test_pm_select_book:
    lda #3
    sta pm_book_idx
    lda #<book_mask_7
    sta pm_book_mask_lo
    lda #>book_mask_7
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #30
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #38
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_reset_holy_word_state:
    jsr player_init
    lda #0
    sta thw_spell_exec_calls
    sta thw_huff_calls
    sta thw_last_huff_id
    sta eff_invuln_timer
    lda #$ff
    sta thw_last_spell_idx

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
    lda #40
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA

    lda #0
    sta player_data + PL_SPELLS_LEARNT_0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    lda #$40
    sta player_data + PL_SPELLS_LEARNT_3
    lda #0
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_holy_word_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: successful prayer reaches slot 30, spends 38 mana, and marks
    // the prayer worked. The shared Holy Word seam remains covered by
    // test_utility_effects on C64.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_holy_word_state
    jsr player_pray
    bcc !t1_fail+
    lda thw_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda thw_last_spell_idx
    cmp #30
    bne !t1_fail+
    lda thw_huff_calls
    bne !t1_fail+
    lda eff_invuln_timer
    bne !t1_fail+
    lda zp_player_mp
    cmp #2
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #2
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$40
    beq !t1_fail+
    lda #$01
    sta thw_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta thw_results + 0

    // Test 2: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Holy Word unworked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_holy_word_state
    jsr player_pray
    bcc !t2_fail+
    lda thw_spell_exec_calls
    bne !t2_fail+
    lda thw_huff_calls
    cmp #1
    bne !t2_fail+
    lda thw_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t2_fail+
    lda eff_invuln_timer
    bne !t2_fail+
    lda zp_player_mp
    cmp #2
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #2
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$40
    bne !t2_fail+
    lda #$01
    sta thw_results + 1
    jmp test_finish
!t2_fail:
    lda #$00
    sta thw_results + 1
    jmp test_finish

thw_results: .fill 2, $ff

test_done_break:
    brk
