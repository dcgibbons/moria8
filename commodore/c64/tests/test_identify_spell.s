// test_identify_spell.s — Focused runtime tests for the Identify spell row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tid_results: .fill 4, $ff
tid_msg_buf: .fill 42, 0
tid_expected_identify:
    .text "This is a Cure Serious Wounds potion." ; .byte 0

.pc = $080E "Bootstrap"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #3
!copy:
    lda tid_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    jmp test_done_break

.pc = $083F "Test Code"
test_done_break:
    brk

.pc = $0840 "Main"

.const PIW_FILTER_MAGE_BOOK = $fc

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

piw_filter: .byte 0

show_inv_and_select:
    lda #$41
    rts

piw_prompt_filtered_inv:
    lda inv_item_id + 1
    cmp #FI_EMPTY
    bne !have_item+
    ldx #HSTR_PIW_NOTHING
    jsr huff_print_msg
    clc
    rts
!have_item:
    sec
    rts

piw_pick_filtered_inv_key:
    cmp #$41
    bne !bad+
    ldx #1
    lda inv_item_id + 1
    sec
    rts
!bad:
    clc
    rts

piw_print_prompt_with_count:
player_recalc_equipment:
    rts

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

tid_key_idx: .byte 0
tid_key_script: .fill 4, 0
tid_spell_exec_calls: .byte 0
tid_huff_calls: .byte 0
tid_last_huff_id: .byte 0
tid_last_spell_idx: .byte $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_input_get_key_script:
    ldx tid_key_idx
    lda tid_key_script,x
    inx
    stx tid_key_idx
    rts

test_huff_print_msg:
    stx tid_last_huff_id
    inc tid_huff_calls
    rts

test_cmb_term_and_print_capture:
    :BankOutKernal()
    ldx cmb_buf_idx
    lda #0
    sta combat_msg_buf,x
    ldx #0
!copy:
    lda combat_msg_buf,x
    sta tid_msg_buf,x
    cmp #0
    beq !done+
    inx
    cpx #42
    bcc !copy-
!done:
    :BankInKernal()
    rts

test_tramp_identify_execute:
    inc tid_spell_exec_calls
    lda pm_spell_idx
    sta tid_last_spell_idx
    jsr eff_identify_prompt
    rts

test_pm_select_book:
    lda #2
    sta pm_book_idx
    lda #<book_mask_2
    sta pm_book_mask_lo
    lda #>book_mask_2
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #20
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

test_reset_identify_state:
    jsr item_init_inventory
    jsr player_init
    lda #0
    sta tid_key_idx
    sta tid_spell_exec_calls
    sta tid_huff_calls
    sta tid_last_huff_id
    lda #$ff
    sta tid_last_spell_idx
    lda #0
    sta id_known + 25
    ldx #41
    lda #0
!clr:
    sta tid_msg_buf,x
    dex
    bpl !clr-

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
    lda #$10
    sta player_data + PL_SPELLS_LEARNT_2
    lda #0
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    rts

test_start:
    :PatchJump(input_get_key, test_input_get_key_script)
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(cmb_term_and_print, test_cmb_term_and_print_capture)
    :PatchJump(test_spell_execute_selected, test_tramp_identify_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: success identifies the selected item, prints the exact built
    // identify message, spends 7 mana, and marks the spell worked in byte 2.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_identify_state
    lda #$41
    sta tid_key_script + 0
    lda #0
    sta tid_key_script + 1
    lda #25
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1
    sta inv_to_ac + 1
    lda #$fe
    sta inv_to_hit + 1
    lda #6
    sta inv_to_dam + 1
    lda #0
    sta inv_ego + 1
    jsr player_cast_spell
    bcc !t1_fail_pre+
    lda tid_spell_exec_calls
    cmp #1
    bne !t1_fail_pre+
    lda tid_last_spell_idx
    cmp #20
    bne !t1_fail_pre+
    lda tid_huff_calls
    bne !t1_fail_pre+
    lda id_known + 25
    cmp #1
    bne !t1_fail_pre+
    lda inv_flags + 1
    and #IF_IDENTIFIED
    beq !t1_fail_pre+
    lda inv_to_hit + 1
    cmp #$fe
    bne !t1_fail_pre+
    lda inv_to_dam + 1
    cmp #6
    bne !t1_fail_pre+
    lda inv_to_ac + 1
    bne !t1_fail_pre+
    lda #<tid_expected_identify
    sta zp_ptr0
    lda #>tid_expected_identify
    sta zp_ptr0_hi
    lda #<tid_msg_buf
    sta zp_ptr1
    lda #>tid_msg_buf
    sta zp_ptr1_hi
    :BankOutKernal()
    ldy #0
!cmp1:
    lda (zp_ptr0),y
    cmp (zp_ptr1),y
    bne !t1_fail_bank+
    cmp #0
    beq !t1_pass+
    iny
    cpy #42
    bcc !cmp1-
    bcs !t1_fail_bank+
!t1_fail_pre:
    jmp !t1_fail+
!t1_pass:
    :BankInKernal()
    lda zp_player_mp
    cmp #13
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$10
    beq !t1_fail+
    lda #$01
    sta tid_results + 0
    jmp !t2+
!t1_fail_bank:
    :BankInKernal()
!t1_fail:
    lda #$00
    sta tid_results + 0

    // Test 2: cancel after the prompt prints HSTR_PIQ_NOTHING, identifies
    // nothing, still spends mana, and still marks the spell worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_identify_state
    lda #$20
    sta tid_key_script + 0
    lda #0
    sta tid_key_script + 1
    lda #25
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1
    jsr player_cast_spell
    bcc !t2_fail+
    lda tid_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda tid_last_spell_idx
    cmp #20
    bne !t2_fail+
    lda tid_huff_calls
    cmp #1
    bne !t2_fail+
    lda tid_last_huff_id
    cmp #HSTR_PIQ_NOTHING
    bne !t2_fail+
    lda id_known + 25
    bne !t2_fail+
    lda inv_flags + 1
    and #IF_IDENTIFIED
    bne !t2_fail+
    lda zp_player_mp
    cmp #13
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$10
    beq !t2_fail+
    lda #$01
    sta tid_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tid_results + 1

    // Test 3: no eligible items prints HSTR_PIW_NOTHING, never reaches item
    // selection, still spends mana, and still marks the spell worked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_identify_state
    jsr player_cast_spell
    bcc !t3_fail+
    lda tid_spell_exec_calls
    cmp #1
    bne !t3_fail+
    lda tid_last_spell_idx
    cmp #20
    bne !t3_fail+
    lda tid_huff_calls
    cmp #1
    bne !t3_fail+
    lda tid_last_huff_id
    cmp #HSTR_PIW_NOTHING
    bne !t3_fail+
    lda id_known + 25
    bne !t3_fail+
    lda zp_player_mp
    cmp #13
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$10
    beq !t3_fail+
    lda #$01
    sta tid_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tid_results + 2

    // Test 4: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Identify unworked.
!t4:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_identify_state
    lda #25
    sta inv_item_id + 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1
    jsr player_cast_spell
    bcc !t4_fail+
    lda tid_spell_exec_calls
    bne !t4_fail+
    lda tid_huff_calls
    cmp #1
    bne !t4_fail+
    lda tid_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t4_fail+
    lda id_known + 25
    bne !t4_fail+
    lda inv_flags + 1
    and #IF_IDENTIFIED
    bne !t4_fail+
    lda zp_player_mp
    cmp #13
    bne !t4_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t4_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$10
    bne !t4_fail+
    lda #$01
    sta tid_results + 3
    jmp test_finish
!t4_fail:
    lda #$00
    sta tid_results + 3
    jmp test_finish
