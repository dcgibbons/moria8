// test_recharge_item_i.s — Focused runtime tests for the Recharge Item I spell row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tri_results: .fill 4, $ff

.pc = $080E "Test Code"

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
    lda tri_results,x
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

tri_spell_exec_calls: .byte 0
tri_huff_calls: .byte 0
tri_last_huff_id: .byte 0
tri_last_spell_idx: .byte $ff
tri_success_msg_calls: .byte 0
tri_inline_calls: .byte 0
tri_rng_idx: .byte 0
tri_rng_script: .fill 2, 0
tri_target_slot: .byte 0
tri_work_damage: .byte 0
tri_work_flag: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tri_last_huff_id
    inc tri_huff_calls
    rts

test_rng_range_scripted:
    ldx tri_rng_idx
    lda tri_rng_script,x
    inx
    stx tri_rng_idx
    rts

pmx_pick_recharge_item:
    lda #0
    clc
    rts

test_pick_recharge_item_success:
    ldx #0
    lda inv_item_id,x
    sec
    rts

test_pick_recharge_item_none:
    lda #$ff
    clc
    rts

test_print_recharged_item:
    inc tri_success_msg_calls
    rts

test_print_inline:
    inc tri_inline_calls
    rts

test_remove_inventory_item:
    lda #FI_EMPTY
    sta inv_item_id,x
    lda #0
    sta inv_qty,x
    sta inv_p1,x
    sta inv_flags,x
    sta inv_ego,x
    rts

test_force_recharge_backfire:
    lda #<tri_msg_bright_flash
    ldy #>tri_msg_bright_flash
    jsr test_print_inline
    ldx #0
    jsr test_remove_inventory_item
    sec
    rts

test_eff_recharge_item:
    sta tri_work_damage
    jsr pmx_pick_recharge_item
    bcs !found+
    cmp #$ff
    beq !none+
    rts
!found:
    stx tri_target_slot
    lda inv_p1,x
    sta tri_work_flag
    lda tri_work_damage
    lsr
    lsr
    lsr
    clc
    adc #2
    sta zp_temp0
    lda tri_work_flag
    cmp zp_temp0
    bcc !recharge+
    lda #4
    jsr rng_range
    bne !recharge+
    lda #<tri_msg_bright_flash
    ldy #>tri_msg_bright_flash
    jsr test_print_inline
    ldx tri_target_slot
    jsr test_remove_inventory_item
    jmp !done+
!recharge:
    lda tri_work_damage
    lsr
    lsr
    lsr
    clc
    adc #1
    jsr rng_range
    clc
    adc #2
    ldx tri_target_slot
    clc
    adc inv_p1,x
    sta inv_p1,x
    jsr test_print_recharged_item
!done:
    rts
!none:
    ldx #HSTR_PIW_NOTHING
    jmp huff_print_msg

tri_msg_bright_flash:
    .text "There is a bright flash of light." ; .byte 0

test_tramp_recharge_execute:
    inc tri_spell_exec_calls
    lda pm_spell_idx
    sta tri_last_spell_idx
    lda #20
    jsr test_eff_recharge_item
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
    lda #17
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

test_reset_recharge_state:
    jsr item_init_inventory
    jsr player_init
    lda #0
    sta tri_spell_exec_calls
    sta tri_huff_calls
    sta tri_last_huff_id
    sta tri_success_msg_calls
    sta tri_inline_calls
    sta tri_rng_idx
    lda #$ff
    sta tri_last_spell_idx

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
    lda #$02
    sta player_data + PL_SPELLS_LEARNT_2
    lda #0
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    rts

test_seed_wand:
    lda #39
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_to_ac
    lda #$fe
    sta inv_to_hit
    lda #6
    sta inv_to_dam
    lda #IF_IDENTIFIED
    sta inv_flags
    lda #EGO_FLAME_TONGUE
    sta inv_ego
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_recharge_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(rng_range, test_rng_range_scripted)

    // Test 1: successful cast reaches spell slot 17, recharges a wand,
    // prints the current recharged-item confirmation, spends 7 mana, and marks
    // the spell worked in byte 2.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    :PatchJump(pmx_pick_recharge_item, test_pick_recharge_item_success)
    jsr test_reset_recharge_state
    jsr test_seed_wand
    lda #1
    sta inv_p1
    lda #2
    sta tri_rng_script + 0       // +4 charges total
    jsr player_cast_spell
    bcc !t1_fail+
    lda tri_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tri_last_spell_idx
    cmp #17
    bne !t1_fail+
    lda inv_item_id
    cmp #39
    bne !t1_fail+
    lda inv_p1
    cmp #5
    bne !t1_fail+
    lda inv_to_hit
    cmp #$fe
    bne !t1_fail+
    lda inv_to_dam
    cmp #6
    bne !t1_fail+
    lda inv_to_ac
    bne !t1_fail+
    lda inv_flags
    cmp #IF_IDENTIFIED
    bne !t1_fail+
    lda inv_ego
    cmp #EGO_FLAME_TONGUE
    bne !t1_fail+
    lda tri_success_msg_calls
    cmp #1
    bne !t1_fail+
    lda tri_inline_calls
    bne !t1_fail+
    lda tri_huff_calls
    bne !t1_fail+
    lda zp_player_mp
    cmp #13
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$02
    beq !t1_fail+
    lda #$01
    sta tri_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tri_results + 0

    // Test 2: with no eligible item, cast prints HSTR_PIW_NOTHING, makes no
    // mutation, still spends mana, and marks the spell worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    :PatchJump(pmx_pick_recharge_item, test_pick_recharge_item_none)
    jsr test_reset_recharge_state
    jsr player_cast_spell
    bcc !t2_fail+
    lda tri_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda tri_last_spell_idx
    cmp #17
    bne !t2_fail+
    lda tri_huff_calls
    cmp #1
    bne !t2_fail+
    lda tri_last_huff_id
    cmp #HSTR_PIW_NOTHING
    bne !t2_fail+
    lda tri_success_msg_calls
    bne !t2_fail+
    lda tri_inline_calls
    bne !t2_fail+
    lda zp_player_mp
    cmp #13
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$02
    beq !t2_fail+
    lda #$01
    sta tri_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tri_results + 1

    // Test 3: cast failure prints HSTR_PM_FAIL, does not execute, and leaves
    // Recharge Item I unworked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    :PatchJump(pmx_pick_recharge_item, test_pick_recharge_item_success)
    jsr test_reset_recharge_state
    jsr test_seed_wand
    lda #1
    sta inv_p1
    jsr player_cast_spell
    bcc !t3_fail+
    lda tri_spell_exec_calls
    bne !t3_fail+
    lda tri_huff_calls
    cmp #1
    bne !t3_fail+
    lda tri_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda inv_item_id
    cmp #39
    bne !t3_fail+
    lda inv_p1
    cmp #1
    bne !t3_fail+
    lda zp_player_mp
    cmp #13
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$02
    bne !t3_fail+
    lda #$01
    sta tri_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tri_results + 2

    // Test 4: the shared recharge seam backfires on a high-charge item,
    // prints the bright-flash inline message, and destroys the item.
!t4:
    jsr test_reset_recharge_state
    jsr test_seed_wand
    lda #4
    sta inv_p1
    jsr test_force_recharge_backfire
    lda tri_inline_calls
    cmp #1
    bne !t4_fail+
    lda tri_success_msg_calls
    bne !t4_fail+
    lda tri_huff_calls
    bne !t4_fail+
    lda inv_item_id
    cmp #FI_EMPTY
    bne !t4_fail+
    lda #$01
    sta tri_results + 3
    jmp test_finish
!t4_fail:
    lda #$00
    sta tri_results + 3
    jmp test_finish
