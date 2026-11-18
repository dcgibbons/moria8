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
    sei
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    lda tc_result
    sta $0400
    brk

.pc = $0830 "Main"

.segmentdef TestUnused [start=$E100, min=$E100, max=$FFF9]
.segmentdef TestUnusedUI [start=$E100, min=$E100, max=$FFF9]
.segmentdef TestCreateOverlay [start=$D000, min=$D000, max=$DFFF]
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
.segment TestUnusedUI
#import "../../../../core/ui_status.s"
#import "../../../../core/ui_help_clear.s"
#import "../../../../core/ui_character.s"
#import "../../../../core/stat_display.s"
.segment Default
.segment TestCreateOverlay
player_create:
    brk
.segment Default
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "dungeon_gen_stubs.s"
#import "../../../../core/huffman.s"
#import "../../../../core/dungeon_features.s"
#import "chest_summons_stubs.s"
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
.segment TestUnused
#import "../../../../core/monster_ai.s"
.segment Default
#import "../../../../core/recall.s"
.segment TestCreateOverlay
#import "../../../../core/monster_magic.s"
.segment Default
#import "../../../../core/item.s"
.segment TestCreateOverlay
#import "../../../../core/special_rooms.s"
.segment Default
.segment TestUnused
#import "../../../../core/ego_items.s"
.segment Default
#import "../../../../core/special_rooms_stubs.s"
#import "../../../../core/player_items.s"
#import "../../../../core/spell_data.s"
.segment TestUnused
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
.segment Default
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../../../../core/ui_inventory.s"
#import "../../../../core/ui_equipment.s"
.segment TestCreateOverlay
#import "../dungeon_render.s"
.segment Default
#import "../../../../core/dungeon_los.s"
.segment TestUnusedUI
#import "../../../../core/player_move.s"
.segment Default
.segment TestUnused
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
.segment Default
#import "../../../../core/monster_attack.s"
.segment TestCreateOverlay
#import "../../../../core/turn.s"
.segment Default
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

tc_result:          .byte $ff
tpm_spell_exec_calls: .byte 0
tpm_huff_calls:     .byte 0
tpm_first_huff_id:  .byte 0
tpm_second_huff_id: .byte 0
tpm_third_huff_id:  .byte 0
tpm_more_calls:     .byte 0
tpm_key_calls:      .byte 0
tpm_rng_val:        .byte 0
tpm_mhp_before_lo:  .byte 0
tpm_mhp_before_hi:  .byte 0
tpm_recalc_in_exec: .byte 0

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

test_rng_range:
    lda tpm_rng_val
    rts

test_tramp_spell_execute_prompt:
    inc tpm_spell_exec_calls
    lda tpm_recalc_in_exec
    beq !no_recalc+
    jmp magic_recalc_mana
!no_recalc:
    ldx #HSTR_PIQ_IDENTIFY_PROMPT
    jsr huff_print_msg
    rts

test_huff_print_msg:
    lda tpm_huff_calls
    beq !first+
    cmp #1
    beq !second+
    cmp #2
    bne !store_last+
    lda tpm_more_calls
    bne !store_last+            // Must print BEFORE msg_show_more!
    stx tpm_third_huff_id
    jmp !store_last+
!second:
    stx tpm_second_huff_id
    jmp !store_last+
!first:
    stx tpm_first_huff_id
!store_last:
    inc tpm_huff_calls
    rts

test_pm_validate_selected_spell_cost1:
    lda #1
    sta pm_cost_tmp
    sec
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
    :PatchJump(rng_range, test_rng_range)

    // Case 1: Mage overcast (no CON drain: rng_range=0) -> HSTR_PM_FAINT_EFFORT
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
    sta player_data + PL_CON_CUR
    sta zp_player_con
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
    sta tpm_third_huff_id
    sta tpm_more_calls
    sta tpm_key_calls
    sta tpm_rng_val
    sta tpm_recalc_in_exec

    jsr player_cast_spell
    bcc !fail_jmp+
    lda tpm_spell_exec_calls
    cmp #1
    bne !fail_jmp+
    lda tpm_huff_calls
    cmp #2
    bne !fail_jmp+
    lda tpm_first_huff_id
    cmp #HSTR_PIQ_IDENTIFY_PROMPT
    bne !fail_jmp+
    lda tpm_second_huff_id
    cmp #HSTR_PM_FAINT_EFFORT
    bne !fail_jmp+
    lda tpm_more_calls
    cmp #1
    bne !fail_jmp+
    lda tpm_key_calls
    cmp #2
    bne !fail_jmp+
    lda zp_eff_paralyze
    cmp #1
    bne !fail_jmp+
    lda zp_player_mp
    bne !fail_jmp+
    lda player_data + PL_MANA
    bne !fail_jmp+
    lda zp_player_con
    cmp #18
    beq !case2+
!fail_jmp:
    jmp !fail+

    // Case 2: Priest overcast (no CON drain: rng_range=0) -> HSTR_PM_NO_MANA
!case2:
    lda #CLASS_PRIEST
    sta player_data + PL_CLASS
    lda #SPELL_PRIEST
    sta player_data + PL_SPELL_TYPE
    lda #1
    sta zp_player_mp
    sta player_data + PL_MANA
    lda #0
    sta zp_eff_paralyze
    sta tpm_huff_calls
    sta tpm_second_huff_id
    sta tpm_more_calls
    jsr player_pray
    bcc !fail_jmp-
    lda tpm_huff_calls
    cmp #2
    bne !fail_jmp-
    lda tpm_second_huff_id
    cmp #HSTR_PM_NO_MANA
    bne !fail_jmp-
    lda tpm_more_calls
    cmp #1
    bne !fail_jmp-

    // Case 3 (Bug B): Overcast 1/3 CON drain (rng_range=1) prints
    // HSTR_PM_HEALTH_DAMAGED before -MORE-, lowers CON + zp_player_con,
    // recomputes PL_MHP + zp_player_mhp, and clamps HP <= MHP.
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #18
    sta player_data + PL_CON_CUR
    sta zp_player_con
    jsr player_calc_hp
    lda zp_player_mhp_lo
    sta tpm_mhp_before_lo
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_mhp_hi
    sta tpm_mhp_before_hi
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #1
    sta zp_player_mp
    sta player_data + PL_MANA
    sta tpm_rng_val
    lda #0
    sta zp_eff_paralyze
    sta tpm_huff_calls
    sta tpm_second_huff_id
    sta tpm_third_huff_id
    sta tpm_more_calls
    jsr player_cast_spell
    bcc !fail_jmp2+
    lda tpm_huff_calls
    cmp #3
    bne !fail_jmp2+
    lda tpm_second_huff_id
    cmp #HSTR_PM_FAINT_EFFORT
    bne !fail_jmp2+
    lda tpm_third_huff_id
    cmp #HSTR_PM_HEALTH_DAMAGED
    bne !fail_jmp2+
    lda tpm_more_calls
    cmp #1
    bne !fail_jmp2+
    lda player_data + PL_CON_CUR
    cmp #17
    bne !fail_jmp2+
    lda zp_player_con
    cmp #17
    beq !case3_mhp+
!fail_jmp2:
    jmp !fail+
!case3_mhp:
    // At level 50, CON 18 (+2) -> 17 (+1) lowers MHP by 49
    lda tpm_mhp_before_lo
    sec
    sbc #49
    cmp zp_player_mhp_lo
    bne !fail_jmp2-
    cmp player_data + PL_MHP_LO
    bne !fail_jmp2-
    cmp zp_player_hp_lo
    bne !fail_jmp2-
    cmp player_data + PL_HP_LO
    bne !fail_jmp2-
    lda tpm_mhp_before_hi
    sbc #0
    cmp zp_player_mhp_hi
    bne !fail_jmp2-
    cmp player_data + PL_MHP_HI
    bne !fail_jmp2-
    cmp zp_player_hp_hi
    bne !fail_jmp2-
    cmp player_data + PL_HP_HI
    bne !fail_jmp2-

    // Case 4 (Bug A): Ranger (min spell level 3) casting a 1-MP spell with 2 MP
    // when magic_recalc_mana runs mid-cast must spend 1 MP and NEVER faint.
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell_cost1)
    lda #CLASS_RANGER
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #5
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    lda #2
    sta zp_player_mp
    sta player_data + PL_MANA
    lda #1
    sta tpm_recalc_in_exec
    lda #0
    sta zp_eff_paralyze
    sta tpm_huff_calls
    sta tpm_more_calls
    jsr player_cast_spell
    bcc !fail+
    lda zp_eff_paralyze
    bne !fail+
    lda tpm_huff_calls
    bne !fail+
    lda tpm_more_calls
    bne !fail+
    lda zp_player_mp
    cmp #1
    bne !fail+
    lda player_data + PL_MANA
    cmp #1
    bne !fail+

    lda #$01
    sta tc_result
    jmp test_finish

!fail:
    lda #$00
    sta tc_result
    jmp test_finish
