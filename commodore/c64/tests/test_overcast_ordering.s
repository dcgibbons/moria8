// test_overcast_ordering.s — Runtime regression for shared overcast sequencing.
//
// Ensures a successful overcast spell executes first, then emits the
// upstream faint-from-fatigue feedback after the effect/prompt work has already
// run.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    lda tc_result
    sta $0400
    brk

.pc = $0830 "Main"

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
#import "../../common/spell_data.s"
#import "../../common/projectile.s"
#import "../../common/spell_effects.s"
#import "../../common/player_magic_state.s"
#import "../../common/player_magic_state_ops.s"
#import "../../common/player_magic.s"
#import "../../common/ui_inventory.s"
#import "../../common/ui_equipment.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
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
#import "../../common/ui_trampoline_stubs.s"

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

tc_result:          .byte $ff
tpm_spell_exec_calls: .byte 0
tpm_huff_calls:     .byte 0
tpm_first_huff_id:  .byte 0
tpm_second_huff_id: .byte 0
tpm_more_calls:     .byte 0
tpm_key_calls:      .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_input_wait_release:
    rts

test_input_get_key_a:
    inc tpm_key_calls
    lda #$41
    rts

test_msg_show_more:
    inc tpm_more_calls
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

test_pm_pick_visible_spell:
    lda #0
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell_cost2:
    lda #2
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_tramp_spell_execute_prompt:
    inc tpm_spell_exec_calls
    ldx #HSTR_PIQ_IDENTIFY_PROMPT
    jsr huff_print_msg
    rts

test_huff_print_msg:
    lda tpm_huff_calls
    beq !first+
    cmp #1
    bne !store_last+
    stx tpm_second_huff_id
    jmp !store_last+
!first:
    stx tpm_first_huff_id
!store_last:
    inc tpm_huff_calls
    rts

test_start:
    :PatchJump(input_wait_release, test_input_wait_release)
    :PatchJump(input_get_key, test_input_get_key_a)
    :PatchJump(msg_show_more, test_msg_show_more)
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_spell_execute_prompt)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_pick_visible_spell, test_pm_pick_visible_spell)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell_cost2)
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)

    jsr player_init
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    lda #1
    sta zp_player_mp
    sta player_data + PL_MANA
    lda #20
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda #1
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta tpm_spell_exec_calls
    sta tpm_huff_calls
    sta tpm_first_huff_id
    sta tpm_second_huff_id
    sta tpm_more_calls
    sta tpm_key_calls

    jsr player_cast_spell
    bcc !fail+
    lda tpm_spell_exec_calls
    cmp #1
    bne !fail+
    lda tpm_huff_calls
    cmp #2
    bne !fail+
    lda tpm_first_huff_id
    cmp #HSTR_PIQ_IDENTIFY_PROMPT
    bne !fail+
    lda tpm_second_huff_id
    cmp #HSTR_PM_NO_MANA
    bne !fail+
    lda tpm_more_calls
    cmp #1
    bne !fail+
    lda tpm_key_calls
    cmp #2
    bne !fail+
    lda zp_eff_paralyze
    beq !fail+
    lda zp_player_mp
    bne !fail+
    lda player_data + PL_MANA
    bne !fail+
    lda #$01
    sta tc_result
    jmp test_finish

!fail:
    lda #$00
    sta tc_result
    jmp test_finish
