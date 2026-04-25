#importonce
// test_identify128.s — Focused C128 coverage for the Identify spell row

.const KEY_ESC = $ae
.const SFX_HIT = $01
.const SFX_PICKUP = $03
.const SFX_SPELL = $06
.const SFX_SPELL_FAIL = $07
.const VIEWPORT_X = 1
.const VIEWPORT_Y = 2
.const VIEWPORT_W = 78
.const VIEWPORT_H = 19
.const MX_CONFUSE = 9
.const MX_SLEEP_CUR = 7
.const MX_TYPE = 2
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

tid_msg_buf: .fill 42, 0
tid_expected_identify:
    .text "This is a Cure Serious Wounds potion." ; .byte 0
combat_msg_buf: .fill 42, 0
tid_this_is_str:
    .text "This is a " ; .byte 0

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
cr_level: .fill 65, 0
vis_room_revealed: .byte 0

tid_key_idx: .byte 0
tid_key_script: .fill 4, 0
tid_huff_calls: .byte 0
tid_last_huff: .byte 0
tid_spell_exec_calls: .byte 0
tid_last_spell_idx: .byte $ff
test_progress: .byte 0

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
screen_flash_set_color:
screen_flash_reset_color:
screen_flash_at:
input_wait_release:
input_get_key_fast:
show_inv_and_select:
tramp_spell_list_display:
combat_kill_message:
monster_wake:
monster_apply_sleep:
projectile_msg_suffix:
player_calc_hp:
light_room_x:
player_search_mode_off:
tunnel_spawn_gold:
monster_get_ptr:
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
    clc
    rts

calc_spell_failure:
    clc
    rts

tramp_spell_execute_selected:
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

input_get_key:
    ldx tid_key_idx
    lda tid_key_script,x
    inx
    stx tid_key_idx
    rts

huff_print_msg:
    stx tid_last_huff
    inc tid_huff_calls
    rts

combat_append_str:
    sta zp_ptr0
    sty zp_ptr0_hi
    ldx cmb_buf_idx
    ldy #0
!copy:
    lda (zp_ptr0),y
    beq !done+
    sta combat_msg_buf,x
    inx
    iny
    cpx #41
    bcc !copy-
!done:
    stx cmb_buf_idx
    lda #0
    sta combat_msg_buf + 41
    rts

huff_append_combat:
    cpx #HSTR_PIQ_THISIS
    bne !done+
    lda #<tid_this_is_str
    ldy #>tid_this_is_str
    jsr combat_append_str
!done:
    rts

msg_print:
    rts

cmb_term_and_print:
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
    lda #0
    sta tid_key_idx
    sta tid_huff_calls
    sta tid_last_huff
    sta tid_spell_exec_calls
    lda #$ff
    sta tid_last_spell_idx
    sta id_known + 25
    ldx #29
    lda #0
!clr_inv:
    sta inv_item_id,x
    sta inv_flags,x
    sta inv_qty,x
    sta inv_p1,x
    sta inv_ego,x
    dex
    bpl !clr_inv-
    ldx #41
    lda #0
!clr_msg:
    sta tid_msg_buf,x
    dex
    bpl !clr_msg-

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
    lda #$10
    sta player_data + PL_SPELLS_LEARNT_2
    lda #0
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
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
    :PatchJump(tramp_spell_execute_selected, test_tramp_identify_execute)

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
    sta inv_ego + 1
    jsr player_cast_spell
    bcc !t1_fail+
    lda tid_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tid_last_spell_idx
    cmp #20
    bne !t1_fail+
    lda tid_huff_calls
    bne !t1_fail+
    lda id_known + 25
    cmp #1
    bne !t1_fail+
    lda inv_flags + 1
    and #IF_IDENTIFIED
    beq !t1_fail+
    lda #<tid_expected_identify
    sta zp_ptr0
    lda #>tid_expected_identify
    sta zp_ptr0_hi
    lda #<tid_msg_buf
    sta zp_ptr1
    lda #>tid_msg_buf
    sta zp_ptr1_hi
    ldy #0
!cmp1:
    lda (zp_ptr0),y
    cmp (zp_ptr1),y
    bne !t1_fail+
    cmp #0
    beq !t1_msg_ok+
    iny
    cpy #42
    bcc !cmp1-
    bcs !t1_fail+
!t1_msg_ok:
    lda zp_player_mp
    cmp #13
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$10
    beq !t1_fail+
    lda #1
    sta test_progress
    jmp test_after_success
!t1_fail:
    jmp test_fail

    // Test 2: cancel after the prompt prints HSTR_PIQ_NOTHING and still marks
    // the spell worked after spending mana.
test_after_success:
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
    lda tid_last_huff
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
    lda #2
    sta test_progress
    jmp test_after_cancel
!t2_fail:
    jmp test_fail

    // Test 3: no eligible items prints HSTR_PIW_NOTHING and still marks the
    // spell worked after spending mana.
test_after_cancel:
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
    lda tid_last_huff
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
    lda #3
    sta test_progress
    jmp test_after_no_item
!t3_fail:
    jmp test_fail

    // Test 4: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Identify unworked.
test_after_no_item:
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
    lda tid_last_huff
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
    lda #4
    sta test_progress
    jmp test_pass
!t4_fail:
    jmp test_fail

test_fail_loop:
    jmp test_fail_loop

test_pass_loop:
    jmp test_pass_loop
