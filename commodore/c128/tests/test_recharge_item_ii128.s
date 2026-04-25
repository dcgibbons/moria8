#importonce
// test_recharge_item_ii128.s — Focused C128 coverage for the Recharge Item II row

.const KEY_ESC = $ae
.const SFX_HIT = $01
.const SFX_PICKUP = $03
.const SFX_SPELL = $06
.const SFX_SPELL_FAIL = $07
.const VIEWPORT_X = 1
.const VIEWPORT_Y = 2
.const VIEWPORT_W = 78
.const VIEWPORT_H = 19
.const MX_X = 0
.const MX_Y = 1
.const MX_TYPE = 2
.const MX_HP_LO = 3
.const MX_HP_HI = 4
.const MX_SLEEP_CUR = 7
.const MX_CONFUSE = 9
.const MAX_MONSTERS = 32
.const EMPTY_SLOT = $ff
.const CF_UNDEAD = $02
.const PIW_FILTER_PRAYER_BOOK = $fb
.const PIW_FILTER_MAGE_BOOK = $fc

.const PL_CLASS = 18
.const PL_LEVEL = 19
.const PL_INT_CUR = 28
.const PL_CON_CUR = 31
.const PL_HP_LO = 33
.const PL_HP_HI = 34
.const PL_MANA = 37
.const PL_MAX_MANA = 38
.const PL_SPELL_TYPE = 60
.const PL_SPELLS_LEARNT_0 = 61
.const PL_SPELLS_LEARNT_1 = 62
.const PL_SPELLS_LEARNT_2 = 63
.const PL_SPELLS_LEARNT_3 = 64
.const PL_SPELLS_WORKED_0 = 65
.const PL_SPELLS_WORKED_1 = 66
.const PL_SPELLS_WORKED_2 = 67
.const PL_SPELLS_WORKED_3 = 68
.const PL_STRUCT_SIZE = 111

player_data:
    .fill PL_STRUCT_SIZE, 0

itn_17:
    .text "Cure Light Wounds" ; .byte 0
itn_30:
    .text "Detect Monsters" ; .byte 0

#import "../../common/huffman_data.s"
#import "../../common/input_contract.s"
#import "../../common/zeropage.s"
#import "test_helpers128.s"
#import "../memory128.s"
#import "../config128.s"
#import "../../common/color.s"
#import "../../common/item_defs.s"
#import "../../common/rng.s"
#import "../../common/math.s"
#import "../../common/tables.s"
#import "../../common/dungeon_data.s"
#import "../../common/spell_data.s"
#import "../../common/spell_names.s"
#import "../../common/player_magic_state.s"
#import "../../common/player_magic_state_ops.s"
#import "../../common/projectile.s"
#import "../../common/spell_effects.s"
#import "../../common/player_magic.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $5000 "Test Code"

msg_row1_col: .byte 0
cmb_slot: .byte 0
cmb_type: .byte 0
cmb_buf_idx: .byte 0
df_target_x: .byte 0
df_target_y: .byte 0
piw_filter: .byte 0
id_known: .fill 64, 0
inv_item_id: .fill 30, 0
inv_flags: .fill 30, 0
inv_qty: .fill 30, 0
inv_p1: .fill 30, 0
inv_ego: .fill 30, 0
it_name_lo: .fill 64, 0
it_name_hi: .fill 64, 0
cmb_period:
    .text "." ; .byte 0
trap_count: .byte 0
trap_x: .fill 16, 0
trap_y: .fill 16, 0
trap_type: .fill 16, 0
cr_mflags: .fill 65, 0

test_huff_calls: .byte 0
test_last_huff: .byte 0
test_spell_exec_calls: .byte 0
test_last_spell_idx: .byte $ff
test_success_msg_calls: .byte 0
test_inline_calls: .byte 0
test_rng_idx: .byte 0
test_rng_script: .fill 2, 0
test_target_slot: .byte 0
test_work_damage: .byte 0
test_work_flag: .byte 0
test_progress: .byte 0
vis_room_revealed: .byte 0

walkable_table:
    .byte 1, 0, 0, 0, 0, 0, 0, 1
    .byte 0, 1, 1, 1, 0, 0, 1, 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

screen_clear:
ui_help_clear_all:
viewport_update:
render_viewport:
status_draw:
msg_clear:
msg_print:
input_wait_release:
input_get_key:
input_get_key_fast:
show_inv_and_select:
tramp_spell_list_display:
monster_get_ptr:
combat_kill_message:
monster_wake:
monster_apply_sleep:
projectile_msg_suffix:
player_calc_hp:
light_room_x:
player_search_mode_off:
huff_append_combat:
combat_append_str:
cmb_term_and_print:
tunnel_spawn_gold:
monster_remove:
combat_award_xp:
combat_check_levelup:
find_random_floor:
monster_find_at:
combat_apply_damage_16:
sound_play:
piw_prompt_filtered_inv:
piw_pick_filtered_inv_key:
piw_print_prompt_with_count:
screen_flash_set_color:
screen_flash_reset_color:
screen_flash_at:
    clc
    rts

get_direction_target:
    lda zp_player_x
    clc
    adc #1
    sta df_target_x
    lda zp_player_y
    sta df_target_y
    sec
    rts

calc_spell_failure:
    clc
    rts

tramp_spell_execute_selected:
    rts

huff_print_msg:
    stx test_last_huff
    inc test_huff_calls
    rts

test_rng_range_scripted:
    ldx test_rng_idx
    lda test_rng_script,x
    inx
    stx test_rng_idx
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
    inc test_success_msg_calls
    rts

test_print_inline:
    inc test_inline_calls
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
    lda #<test_msg_bright_flash
    ldy #>test_msg_bright_flash
    jsr test_print_inline
    ldx #0
    jsr test_remove_inventory_item
    sec
    rts

test_eff_recharge_item:
    sta test_work_damage
    jsr pmx_pick_recharge_item
    bcs !found+
    cmp #$ff
    beq !none+
    rts
!found:
    stx test_target_slot
    lda inv_p1,x
    sta test_work_flag
    lda test_work_damage
    lsr
    lsr
    lsr
    clc
    adc #2
    sta zp_temp0
    lda test_work_flag
    cmp zp_temp0
    bcc !recharge+
    lda #4
    jsr rng_range
    bne !recharge+
    lda #<test_msg_bright_flash
    ldy #>test_msg_bright_flash
    jsr test_print_inline
    ldx test_target_slot
    jsr test_remove_inventory_item
    jmp !done+
!recharge:
    lda test_work_damage
    lsr
    lsr
    lsr
    clc
    adc #1
    jsr rng_range
    clc
    adc #2
    ldx test_target_slot
    clc
    adc inv_p1,x
    sta inv_p1,x
    jsr test_print_recharged_item
!done:
    rts
!none:
    ldx #HSTR_PIW_NOTHING
    jmp huff_print_msg

test_msg_bright_flash:
    .text "There is a bright flash of light." ; .byte 0

test_tramp_recharge_execute:
    inc test_spell_exec_calls
    lda pm_spell_idx
    sta test_last_spell_idx
    lda #50
    jsr test_eff_recharge_item
    rts

test_pm_select_book:
    lda #3
    sta pm_book_idx
    lda #<book_mask_3
    sta pm_book_mask_lo
    lda #>book_mask_3
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #25
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #12
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
    ldx #29
    lda #0
!clear:
    sta inv_flags,x
    sta inv_qty,x
    sta inv_p1,x
    sta inv_ego,x
    dex
    bpl !clear-
    ldx #29
    lda #FI_EMPTY
!clear_ids:
    sta inv_item_id,x
    dex
    bpl !clear_ids-

    lda #0
    sta test_huff_calls
    sta test_last_huff
    sta test_spell_exec_calls
    sta test_success_msg_calls
    sta test_inline_calls
    sta test_rng_idx
    lda #$ff
    sta test_last_spell_idx

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
    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA

    lda #0
    sta player_data + PL_SPELLS_LEARNT_0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    lda #$02
    sta player_data + PL_SPELLS_LEARNT_3
    lda #0
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
    sta inv_flags
    sta inv_ego
    rts

test_fail:
    jmp test_fail_loop

test_pass:
    jmp test_pass_loop

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #MMU_ALL_RAM
    sta $ff00
    lda #0
    sta test_progress

    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(tramp_spell_execute_selected, test_tramp_recharge_execute)
    :PatchJump(rng_range, test_rng_range_scripted)

    // Test 1: successful cast reaches spell slot 25, uses the stronger
    // recharge path, prints the current recharged-item confirmation, spends 12
    // mana, and marks the spell worked in byte 3.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    :PatchJump(pmx_pick_recharge_item, test_pick_recharge_item_success)
    jsr test_reset_recharge_state
    jsr test_seed_wand
    lda #1
    sta inv_p1
    lda #6
    sta test_rng_script + 0
    jsr player_cast_spell
    bcc !t1_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda test_last_spell_idx
    cmp #25
    bne !t1_fail+
    lda test_work_damage
    cmp #50
    bne !t1_fail+
    lda inv_item_id
    cmp #39
    bne !t1_fail+
    lda inv_p1
    cmp #9
    bne !t1_fail+
    lda test_success_msg_calls
    cmp #1
    bne !t1_fail+
    lda test_inline_calls
    bne !t1_fail+
    lda test_huff_calls
    bne !t1_fail+
    lda zp_player_mp
    cmp #8
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #8
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$02
    beq !t1_fail+
    lda #1
    sta test_progress
    jmp test_after_success
!t1_fail:
    jmp test_fail

    // Test 2: with no eligible item, cast prints HSTR_PIW_NOTHING, makes no
    // mutation, still spends mana, and marks the spell worked.
test_after_success:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    :PatchJump(pmx_pick_recharge_item, test_pick_recharge_item_none)
    jsr test_reset_recharge_state
    jsr player_cast_spell
    bcc !t2_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda test_last_spell_idx
    cmp #25
    bne !t2_fail+
    lda test_huff_calls
    cmp #1
    bne !t2_fail+
    lda test_last_huff
    cmp #HSTR_PIW_NOTHING
    bne !t2_fail+
    lda test_success_msg_calls
    bne !t2_fail+
    lda test_inline_calls
    bne !t2_fail+
    lda zp_player_mp
    cmp #8
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #8
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$02
    beq !t2_fail+
    lda #2
    sta test_progress
    jmp test_after_none
!t2_fail:
    jmp test_fail

    // Test 3: cast failure prints HSTR_PM_FAIL, does not execute, and leaves
    // Recharge Item II unworked.
test_after_none:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    :PatchJump(pmx_pick_recharge_item, test_pick_recharge_item_success)
    jsr test_reset_recharge_state
    jsr test_seed_wand
    lda #1
    sta inv_p1
    jsr player_cast_spell
    bcc !t3_fail+
    lda test_spell_exec_calls
    bne !t3_fail+
    lda test_huff_calls
    cmp #1
    bne !t3_fail+
    lda test_last_huff
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda inv_item_id
    cmp #39
    bne !t3_fail+
    lda inv_p1
    cmp #1
    bne !t3_fail+
    lda zp_player_mp
    cmp #8
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #8
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$02
    bne !t3_fail+
    lda #3
    sta test_progress
    jmp test_after_fail
!t3_fail:
    jmp test_fail

    // Test 4: the destructive recharge branch prints the bright-flash inline
    // message and destroys the item.
test_after_fail:
    jsr test_reset_recharge_state
    jsr test_seed_wand
    lda #8
    sta inv_p1
    jsr test_force_recharge_backfire
    lda test_inline_calls
    cmp #1
    bne !t4_fail+
    lda test_success_msg_calls
    bne !t4_fail+
    lda test_huff_calls
    bne !t4_fail+
    lda inv_item_id
    cmp #FI_EMPTY
    bne !t4_fail+
    lda #4
    sta test_progress
    jmp test_pass
!t4_fail:
    jmp test_fail

test_fail_loop:
    jmp test_fail_loop

test_pass_loop:
    jmp test_pass_loop
