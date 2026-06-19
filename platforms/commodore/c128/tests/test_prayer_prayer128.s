#importonce
// test_prayer_prayer128.s — Focused C128 coverage for the Prayer prayer row

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
.const PL_WIS_CUR = 29
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
itok_detect_monsters:
    .text "Detect Monsters" ; .byte 0

#import "../../../../core/huffman_data.s"
#import "../../../../core/input_contract.s"
#import "../../../../core/zeropage.s"
#import "test_helpers128.s"
#import "../memory128.s"
#import "../config128.s"
#import "../../../../core/color.s"
#import "../../../../core/item_defs.s"
#import "../../../../core/rng.s"
#import "../../../../core/math.s"
#import "../../../../core/tables.s"
#import "../../../../core/dungeon_data.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/spell_names.s"
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../../../../core/player_magic.s"
#import "../../../../core/player_magic_feedback.s"

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

test_huff_calls: .byte 0
test_last_huff: .byte 0
test_more_calls: .byte 0
test_key_calls: .byte 0
test_msg_calls: .byte 0
test_last_msg_lo: .byte 0
test_last_msg_hi: .byte 0
test_spell_exec_calls: .byte 0
test_last_spell_idx: .byte $ff
test_progress: .byte 0
test_rng_value: .byte 0

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
.label hal_screen_clear = screen_clear
ui_help_clear_all:
viewport_update:
render_viewport:
status_draw:
input_wait_release:
.label hal_input_wait_release = input_wait_release
.label hal_input_modal_prepare = input_wait_release
input_get_key_fast:
show_inv_and_select:
tramp_spell_list_display:
monster_get_ptr:
combat_kill_message:
combat_print_winner_message:
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
combat_note_kill:
find_random_floor:
monster_find_at:
combat_apply_damage_16:
hal_sound_play:
piw_prompt_filtered_inv:
piw_pick_filtered_inv_key:
piw_print_prompt_with_count:
screen_flash_set_color:
screen_flash_reset_color:
screen_flash_at:
msg_clear:
    clc
    rts

input_get_key:
.label hal_input_get_key = input_get_key
.label hal_input_get_text_char = input_get_key
    inc test_key_calls
    clc
    rts

test_msg_show_more:
    inc test_more_calls
    clc
    rts

msg_print:
    inc test_msg_calls
    lda zp_ptr0
    sta test_last_msg_lo
    lda zp_ptr0_hi
    sta test_last_msg_hi
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

huff_print_msg:
    stx test_last_huff
    inc test_huff_calls
    rts

test_rng_range:
    lda test_rng_value
    rts

test_tramp_spell_execute_selected:
    inc test_spell_exec_calls
    lda pm_spell_idx
    sta test_last_spell_idx
    lda #48
    jsr rng_range
    clc
    adc #48
    jsr pmx_add_bless_msg
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
    lda #25
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #22
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_reset_prayer_prayer_state:
    lda #0
    sta test_huff_calls
    sta test_last_huff
    sta test_more_calls
    sta test_key_calls
    sta zp_msg_flags
    sta test_msg_calls
    sta test_last_msg_lo
    sta test_last_msg_hi
    sta test_spell_exec_calls
    sta test_rng_value
    sta zp_eff_bless
    lda #$ff
    sta test_last_spell_idx

    lda #CLASS_PRIEST
    sta player_data + PL_CLASS
    lda #SPELL_PRIEST
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_WIS_CUR
    sta player_data + PL_CON_CUR
    lda #30
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

    :PatchJump(rng_range, test_rng_range)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(tramp_spell_execute_selected, test_tramp_spell_execute_selected)
    :PatchJump(msg_show_more, test_msg_show_more)

    // Test 1: onset prints the righteous message, sets the bless timer to 48,
    // spends 22 mana, and marks Prayer worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_prayer_prayer_state
    jsr player_pray
    bcc !t1_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda test_last_spell_idx
    cmp #25
    bne !t1_fail+
    lda zp_eff_bless
    cmp #48
    bne !t1_fail+
    lda test_msg_calls
    cmp #1
    bne !t1_fail+
    lda test_last_msg_lo
    cmp #<pmx_righteous_msg
    bne !t1_fail+
    lda test_last_msg_hi
    cmp #>pmx_righteous_msg
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
    jmp test_after_onset
!t1_fail:
    jmp test_fail

    // Test 2: refresh stays silent and adds onto the existing bless timer.
test_after_onset:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_prayer_prayer_state
    lda #5
    sta zp_eff_bless
    jsr player_pray
    bcc !t2_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda test_last_spell_idx
    cmp #25
    bne !t2_fail+
    lda zp_eff_bless
    cmp #53
    bne !t2_fail+
    lda test_msg_calls
    bne !t2_fail+
    lda test_huff_calls
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
    jmp test_after_refresh
!t2_fail:
    jmp test_fail

    // Test 3: successful overcast prayer executes, then prints upstream-style
    // fatigue faint feedback, zeros mana, and applies paralysis.
test_after_refresh:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_prayer_prayer_state
    lda #1
    sta zp_player_mp
    sta player_data + PL_MANA
    sta test_rng_value
    jsr player_pray
    bcc !t3_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t3_fail+
    lda test_last_spell_idx
    cmp #25
    bne !t3_fail+
    lda test_huff_calls
    cmp #1
    bne !t3_fail+
    lda test_last_huff
    cmp #HSTR_PM_NO_MANA
    bne !t3_fail+
    lda test_more_calls
    cmp #1
    bne !t3_fail+
    lda test_key_calls
    cmp #1
    bne !t3_fail+
    lda zp_eff_paralyze
    cmp #2
    bne !t3_fail+
    lda zp_player_mp
    bne !t3_fail+
    lda player_data + PL_MANA
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$02
    beq !t3_fail+
    lda #4
    sta test_progress
    jmp test_after_overcast
!t3_fail:
    jmp test_fail

    // Test 4: cast failure spends mana, prints HSTR_PM_FAIL, does not set
    // bless, and leaves Prayer unworked.
test_after_overcast:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_prayer_prayer_state
    jsr player_pray
    bcc !t4_fail+
    lda test_spell_exec_calls
    bne !t4_fail+
    lda zp_eff_bless
    bne !t4_fail+
    lda test_huff_calls
    cmp #1
    bne !t4_fail+
    lda test_last_huff
    cmp #HSTR_PM_FAIL
    bne !t4_fail+
    lda test_msg_calls
    bne !t4_fail+
    lda zp_player_mp
    cmp #8
    bne !t4_fail+
    lda player_data + PL_MANA
    cmp #8
    bne !t4_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$02
    bne !t4_fail+
    lda #3
    sta test_progress
    jmp test_pass
!t4_fail:
    jmp test_fail

test_fail_loop:
    jmp test_fail_loop

test_pass_loop:
    jmp test_pass_loop
