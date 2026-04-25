// test_slow_poison_prayer.s — Focused runtime tests for the Slow Poison prayer row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 3, $ff

.pc = $080E "Bootstrap"

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
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    jmp test_done_break

.pc = $0840 "Test Code"

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

tspp_spell_exec_calls: .byte 0
tspp_huff_calls: .byte 0
tspp_last_huff_id: .byte 0
tspp_last_spell_idx: .byte $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tspp_last_huff_id
    inc tspp_huff_calls
    rts

test_tramp_slow_poison_prayer_execute:
    inc tspp_spell_exec_calls
    lda pm_spell_idx
    sta tspp_last_spell_idx
    jmp pmx_slow_poison_msg

test_pm_select_book:
    lda #0
    sta pm_book_idx
    lda #<book_mask_4
    sta pm_book_mask_lo
    lda #>book_mask_4
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #7
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #3
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_reset_slow_poison_prayer_state:
    jsr player_init
    lda #0
    sta tspp_spell_exec_calls
    sta tspp_huff_calls
    sta tspp_last_huff_id
    sta zp_eff_poison
    lda #$ff
    sta tspp_last_spell_idx

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

    lda #$80
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
    :PatchJump(test_spell_execute_selected, test_tramp_slow_poison_prayer_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: poisoned prayer reduces poison severity with the current
    // lsr/ora#1 rule, reports reduced poison, spends 3 mana, and marks slot 7
    // worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_slow_poison_prayer_state
    lda #10
    sta zp_eff_poison
    jsr player_pray
    bcc !t1_fail+
    lda tspp_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tspp_last_spell_idx
    cmp #7
    bne !t1_fail+
    lda tspp_huff_calls
    cmp #1
    bne !t1_fail+
    lda tspp_last_huff_id
    cmp #HSTR_EFF_POISON_END
    bne !t1_fail+
    lda zp_eff_poison
    cmp #5
    bne !t1_fail+
    lda zp_player_mp
    cmp #17
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #17
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$80
    beq !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: already-clear prayer stays silent/no-op, still spends 3 mana,
    // and marks the prayer worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_slow_poison_prayer_state
    jsr player_pray
    bcc !t2_fail+
    lda tspp_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda tspp_last_spell_idx
    cmp #7
    bne !t2_fail+
    lda tspp_huff_calls
    bne !t2_fail+
    lda zp_eff_poison
    bne !t2_fail+
    lda zp_player_mp
    cmp #17
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #17
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$80
    beq !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, preserves poison,
    // and leaves Slow Poison unworked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_slow_poison_prayer_state
    lda #10
    sta zp_eff_poison
    jsr player_pray
    bcc !t3_fail+
    lda tspp_spell_exec_calls
    bne !t3_fail+
    lda tspp_huff_calls
    cmp #1
    bne !t3_fail+
    lda tspp_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda zp_eff_poison
    cmp #10
    bne !t3_fail+
    lda zp_player_mp
    cmp #17
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #17
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$80
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta tc_results + 2
    jmp test_finish

test_done_break:
    brk
