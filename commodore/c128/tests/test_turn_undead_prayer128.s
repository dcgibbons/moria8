#importonce
// test_turn_undead_prayer128.s — Focused C128 coverage for the Turn Undead prayer row

.const KEY_ESC = $ae
.const SFX_HIT = $01
.const SFX_PICKUP = $03
.const SFX_SPELL = $06
.const SFX_SPELL_FAIL = $07
.const VIEWPORT_X = 1
.const VIEWPORT_Y = 2
.const VIEWPORT_W = 78
.const VIEWPORT_H = 19
.const MONSTER_ENTRY_SIZE = 12
.const MX_X = 0
.const MX_Y = 1
.const MX_TYPE = 2
.const MX_SLEEP_CUR = 7
.const MX_CONFUSE = 9
.const MAX_MONSTERS = 32
.const EMPTY_SLOT = $ff
.const CF_UNDEAD = $02
.const CF_EVIL = $04
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
#import "../../common/player_magic_feedback.s"
#import "../../common/player_magic_utility.s"

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
cmb_kill_str:
    .text "KILL" ; .byte 0
fi_add_x: .byte 0
fi_add_y: .byte 0
fi_add_id: .byte 0
fi_add_qty: .byte 0
fi_add_qty_hi: .byte 0
fi_add_p1: .byte 0
fi_add_flags: .byte 0
fi_add_ego: .byte 0

test_huff_calls: .byte 0
test_last_huff: .byte 0
test_spell_exec_calls: .byte 0
test_last_spell_idx: .byte $ff
test_progress: .byte 0
test_frantic_calls: .byte 0
test_unaffected_calls: .byte 0
test_rng_value: .byte 0
pmx_work_idx: .byte 0
pmx_work_flag: .byte 0
pmx_work_damage: .byte 0
vis_room_revealed: .byte 0
vis_cached_room_idx: .byte 0
dg_room_x: .byte 0
dg_room_y: .byte 0
dg_room_w: .byte 0
dg_room_h: .byte 0

test_mon_table:
    .fill MAX_MONSTERS * MONSTER_ENTRY_SIZE, 0

test_mon_ptr_lo:
    .fill MAX_MONSTERS, <(test_mon_table + i * MONSTER_ENTRY_SIZE)
test_mon_ptr_hi:
    .fill MAX_MONSTERS, >(test_mon_table + i * MONSTER_ENTRY_SIZE)

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
hal_sound_play:
piw_prompt_filtered_inv:
piw_pick_filtered_inv_key:
piw_print_prompt_with_count:
screen_flash_set_color:
screen_flash_reset_color:
screen_flash_at:
combat_kill_message:
floor_item_find_at:
floor_item_remove:
floor_item_add:
fi_add_clear_plain_meta:
    clc
    rts

combat_msg_monster_shudders:
combat_msg_monster_dissolves:
    rts

combat_msg_monster_runs_frantically:
    inc test_frantic_calls
    rts

combat_msg_monster_unaffected:
    inc test_unaffected_calls
    rts

los_is_visible:
    cpx #25
    beq !hidden+
    sec
    rts
!hidden:
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

huff_print_msg:
    stx test_last_huff
    inc test_huff_calls
    rts

test_rng_range:
    lda test_rng_value
    rts

msg_build_action:
    rts

cmb_print_buf:
    rts

eff_remove_fear:
    rts

player_calc_stats:
    rts

player_sync_to_zp:
    rts

glyph_add_at:
    clc
    rts

monster_get_ptr:
    lda test_mon_ptr_lo,x
    sta zp_ptr0
    lda test_mon_ptr_hi,x
    sta zp_ptr0_hi
    rts

test_tramp_turn_undead_prayer_execute:
    inc test_spell_exec_calls
    lda pm_spell_idx
    sta test_last_spell_idx
    jsr eff_turn_undead
    rts

test_pm_select_book:
    lda #2
    sta pm_book_idx
    lda #<book_mask_6
    sta pm_book_mask_lo
    lda #>book_mask_6
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #24
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #21
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_clear_monsters:
    ldx #0
!loop:
    lda #0
    sta test_mon_table,x
    inx
    cpx #(MAX_MONSTERS * MONSTER_ENTRY_SIZE)
    bcc !loop-
    rts

test_reset_turn_undead_prayer_state:
    jsr test_clear_monsters
    lda #0
    sta test_huff_calls
    sta test_last_huff
    sta test_spell_exec_calls
    sta test_frantic_calls
    sta test_unaffected_calls
    sta test_rng_value
    sta cr_mflags + 0
    sta cr_mflags + 1
    sta cr_mflags + 2
    sta cr_mflags + 3
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
    lda #$01
    sta player_data + PL_SPELLS_LEARNT_3
    lda #0
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
    :PatchJump(tramp_spell_execute_selected, test_tramp_turn_undead_prayer_execute)
    :PatchJump(rng_range, test_rng_range)

    // Test 1: Turn Undead affects only visible undead. Low-level visible
    // undead turn and report frantically, high-level visible undead resist and
    // report unaffected, hidden undead and non-undead stay unchanged.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_turn_undead_prayer_state
    lda #CF_UNDEAD
    sta cr_mflags + 1
    sta cr_mflags + 3
    lda #1
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_TYPE
    lda #20
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_X
    lda #12
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_Y
    lda #7
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    lda #2
    sta test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_TYPE
    lda #9
    sta test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    lda #3
    sta test_mon_table + (2 * MONSTER_ENTRY_SIZE) + MX_TYPE
    lda #21
    sta test_mon_table + (2 * MONSTER_ENTRY_SIZE) + MX_X
    lda #12
    sta test_mon_table + (2 * MONSTER_ENTRY_SIZE) + MX_Y
    lda #5
    sta test_mon_table + (2 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    lda #4
    sta test_mon_table + (2 * MONSTER_ENTRY_SIZE) + MX_CONFUSE
    lda #3
    sta test_mon_table + (3 * MONSTER_ENTRY_SIZE) + MX_TYPE
    lda #25
    sta test_mon_table + (3 * MONSTER_ENTRY_SIZE) + MX_X
    lda #12
    sta test_mon_table + (3 * MONSTER_ENTRY_SIZE) + MX_Y
    lda #6
    sta test_mon_table + (3 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    lda #8
    sta test_mon_table + (3 * MONSTER_ENTRY_SIZE) + MX_CONFUSE
    lda #1
    sta cr_level + 1
    lda #10
    sta cr_level + 3
    lda #5
    sta test_rng_value
    jsr player_pray
    bcc !t1_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda test_last_spell_idx
    cmp #24
    bne !t1_fail+
    lda test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_CONFUSE
    cmp #50
    bne !t1_fail+
    lda test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    bne !t1_fail+
    lda test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_CONFUSE
    bne !t1_fail+
    lda test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    cmp #9
    bne !t1_fail+
    lda test_mon_table + (2 * MONSTER_ENTRY_SIZE) + MX_CONFUSE
    cmp #4
    bne !t1_fail+
    lda test_mon_table + (2 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    cmp #5
    bne !t1_fail+
    lda test_mon_table + (3 * MONSTER_ENTRY_SIZE) + MX_CONFUSE
    cmp #8
    bne !t1_fail+
    lda test_mon_table + (3 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    cmp #6
    bne !t1_fail+
    lda test_frantic_calls
    cmp #1
    bne !t1_fail+
    lda test_unaffected_calls
    cmp #1
    bne !t1_fail+
    lda test_huff_calls
    bne !t1_fail+
    lda zp_player_mp
    cmp #9
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #9
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$01
    beq !t1_fail+
    lda #1
    sta test_progress
    jmp test_after_success
!t1_fail:
    jmp test_fail

    // Test 2: no visible undead prints HSTR_PIQ_NOTHING, spends mana, and
    // marks the prayer worked.
test_after_success:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_turn_undead_prayer_state
    lda #2
    sta test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_TYPE
    lda #9
    sta test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    jsr player_pray
    bcc !t2_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda test_last_spell_idx
    cmp #24
    bne !t2_fail+
    lda test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_CONFUSE
    bne !t2_fail+
    lda test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    cmp #9
    bne !t2_fail+
    lda test_huff_calls
    cmp #1
    bne !t2_fail+
    lda test_last_huff
    cmp #HSTR_PIQ_NOTHING
    bne !t2_fail+
    lda test_frantic_calls
    bne !t2_fail+
    lda test_unaffected_calls
    bne !t2_fail+
    lda zp_player_mp
    cmp #9
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #9
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$01
    beq !t2_fail+
    lda #2
    sta test_progress
    jmp test_after_no_undead
!t2_fail:
    jmp test_fail

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not execute
    // Turn Undead, and leaves the prayer unworked.
test_after_no_undead:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_turn_undead_prayer_state
    lda #CF_UNDEAD
    sta cr_mflags + 1
    lda #1
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_TYPE
    lda #7
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    jsr player_pray
    bcc !t3_fail+
    lda test_spell_exec_calls
    bne !t3_fail+
    lda test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_CONFUSE
    bne !t3_fail+
    lda test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    cmp #7
    bne !t3_fail+
    lda test_huff_calls
    cmp #1
    bne !t3_fail+
    lda test_last_huff
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda zp_player_mp
    cmp #9
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #9
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$01
    bne !t3_fail+
    lda #3
    sta test_progress
    jmp test_pass
!t3_fail:
    jmp test_fail

test_fail_loop:
    jmp test_fail_loop

test_pass_loop:
    jmp test_pass_loop
