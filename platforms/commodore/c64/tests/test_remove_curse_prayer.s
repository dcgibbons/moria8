// test_remove_curse_prayer.s — Focused runtime tests for the Remove Curse prayer row

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
    ldx #2
!copy:
    lda tc_results,x
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

trc_spell_exec_calls: .byte 0
trc_huff_calls: .byte 0
trc_last_huff_id: .byte 0
trc_last_spell_idx: .byte $ff
tc_results: .fill 3, $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx trc_last_huff_id
    inc trc_huff_calls
    rts

test_tramp_remove_curse_prayer_execute:
    inc trc_spell_exec_calls
    lda pm_spell_idx
    sta trc_last_spell_idx
    jsr test_eff_remove_curse_all
    ldx #HSTR_PIQ_CLEANSED
    jsr huff_print_msg
    rts

test_eff_remove_curse_all:
    ldx #0
!loop:
    cpx #TOTAL_INV_SLOTS
    bcs !done+
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !next+
    lda inv_flags,x
    and #~IF_CURSED & $ff
    sta inv_flags,x
!next:
    inx
    jmp !loop-
!done:
    rts

test_pm_select_book:
    lda #1
    sta pm_book_idx
    lda #<book_mask_5
    sta pm_book_mask_lo
    lda #>book_mask_5
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #14
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

test_reset_remove_curse_state:
    jsr item_init_inventory
    jsr player_init

    lda #0
    sta trc_spell_exec_calls
    sta trc_huff_calls
    sta trc_last_huff_id
    lda #$ff
    sta trc_last_spell_idx

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

    lda #0
    sta player_data + PL_SPELLS_LEARNT_0
    lda #$40
    sta player_data + PL_SPELLS_LEARNT_1
    lda #0
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    rts

test_seed_equipped_and_carried_curses:
    lda #2
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #IF_CURSED
    sta inv_flags + EQUIP_WEAPON

    lda #7
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #IF_CURSED
    sta inv_flags
    rts

test_seed_uncursed_equipment_and_carried_item:
    lda #2
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #0
    sta inv_flags + EQUIP_WEAPON

    lda #7
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_flags
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_remove_curse_prayer_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: successful prayer clears both equipped and carried curses,
    // prints CLEANSED, spends 6 mana, and marks prayer slot 14 worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_remove_curse_state
    jsr test_seed_equipped_and_carried_curses
    jsr player_pray
    bcc !t1_fail+
    lda trc_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda trc_last_spell_idx
    cmp #14
    bne !t1_fail+
    lda inv_flags + EQUIP_WEAPON
    and #IF_CURSED
    bne !t1_fail+
    lda inv_flags
    and #IF_CURSED
    bne !t1_fail+
    lda trc_huff_calls
    cmp #1
    bne !t1_fail+
    lda trc_last_huff_id
    cmp #HSTR_PIQ_CLEANSED
    bne !t1_fail+
    lda zp_player_mp
    cmp #14
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #14
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$40
    beq !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: with no cursed carried/equipped items, the current success path
    // still prints CLEANSED, leaves inventory state unchanged, spends mana,
    // and marks the prayer worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_remove_curse_state
    jsr test_seed_uncursed_equipment_and_carried_item
    jsr player_pray
    bcc !t2_fail+
    lda trc_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda trc_last_spell_idx
    cmp #14
    bne !t2_fail+
    lda inv_flags + EQUIP_WEAPON
    and #IF_CURSED
    bne !t2_fail+
    lda inv_flags
    and #IF_CURSED
    bne !t2_fail+
    lda trc_huff_calls
    cmp #1
    bne !t2_fail+
    lda trc_last_huff_id
    cmp #HSTR_PIQ_CLEANSED
    bne !t2_fail+
    lda zp_player_mp
    cmp #14
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #14
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$40
    beq !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not clear
    // any curse flags, and leaves Remove Curse unworked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_remove_curse_state
    jsr test_seed_equipped_and_carried_curses
    jsr player_pray
    bcc !t3_fail+
    lda trc_spell_exec_calls
    bne !t3_fail+
    lda inv_flags + EQUIP_WEAPON
    and #IF_CURSED
    beq !t3_fail+
    lda inv_flags
    and #IF_CURSED
    beq !t3_fail+
    lda trc_huff_calls
    cmp #1
    bne !t3_fail+
    lda trc_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda zp_player_mp
    cmp #14
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #14
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$40
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta tc_results + 2
    jmp test_finish

// Keep the monitor stop address away from BASIC ROM execution reached during
// autostart before the test program banks BASIC out.
.fill $22, $ea
test_done_break:
    brk
