#importonce
// test_sleep_iii128.s — Focused C128 coverage for the Sleep III row

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
.const MX_FLAGS = 5
.const MX_X = 3
.const MX_Y = 4
.const MF_AWAKE = $01
.const MAX_MONSTERS = 32
.const EMPTY_SLOT = $ff
.const CF_UNDEAD = $02
.const PIW_FILTER_PRAYER_BOOK = $fb
.const PIW_FILTER_MAGE_BOOK = $fc

.const PL_CLASS = 18
.const PL_LEVEL = 19
.const PL_INT_CUR = 28
.const PL_WIS_CUR = 29
.const PL_CON_CUR = 31
.const PL_HP_LO = 33
.const PL_HP_HI = 34
.const PL_MANA = 37
.const PL_MAX_MANA = 38
.const PL_MAP_X = 49
.const PL_MAP_Y = 50
.const PL_SPELL_TYPE = 60
.const PL_SPELLS_LEARNT_0 = 61
.const PL_SPELLS_LEARNT_1 = 62
.const PL_SPELLS_LEARNT_2 = 63
.const PL_SPELLS_LEARNT_3 = 64
.const PL_SPELLS_WORKED_0 = 65
.const PL_SPELLS_WORKED_1 = 66
.const PL_SPELLS_WORKED_2 = 67
.const PL_SPELLS_WORKED_3 = 68
.const PL_NEW_SPELLS = 69
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
it_name_lo: .fill 64, 0
it_name_hi: .fill 64, 0
cmb_period:
    .text "." ; .byte 0
trap_count: .byte 0
trap_x: .fill 16, 0
trap_y: .fill 16, 0
trap_type: .fill 16, 0
cr_level: .fill 65, 0
cr_mflags: .fill 65, 0
vis_room_revealed: .byte 0

test_mon0_visible: .byte 0
test_mon1_visible: .byte 0
test_mon0_data: .fill 12, 0
test_mon1_data: .fill 12, 0
test_mon_dummy: .fill 12, 0
test_huff_calls: .byte 0
test_last_huff: .byte 0
test_msg_calls: .byte 0
test_last_msg_lo: .byte 0
test_last_msg_hi: .byte 0
test_spell_exec_calls: .byte 0
test_last_spell_idx: .byte $ff
test_progress: .byte 0
test_sleep_hits: .byte 0
test_sleep_idx: .byte 0
test_pmx_sleep_success_msg:
    .text "A monster falls asleep." ; .byte 0

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
input_get_key:
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
    clc
    rts

tier_restore_after_overlay:
stat_bonus_index:
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

msg_print:
    inc test_msg_calls
    lda zp_ptr0
    sta test_last_msg_lo
    lda zp_ptr0_hi
    sta test_last_msg_hi
    rts

monster_get_ptr:
    cpx #0
    beq !mon0+
    cpx #1
    beq !mon1+
    lda #<test_mon_dummy
    sta zp_ptr0
    lda #>test_mon_dummy
    sta zp_ptr0_hi
    rts
!mon0:
    lda #<test_mon0_data
    sta zp_ptr0
    lda #>test_mon0_data
    sta zp_ptr0_hi
    rts
!mon1:
    lda #<test_mon1_data
    sta zp_ptr0
    lda #>test_mon1_data
    sta zp_ptr0_hi
    rts

los_is_visible:
    cpx test_mon0_data + MX_X
    bne !check1+
    cpy test_mon0_data + MX_Y
    bne !check1+
    lda test_mon0_visible
    bne !visible+
    clc
    rts
!check1:
    cpx test_mon1_data + MX_X
    bne !miss+
    cpy test_mon1_data + MX_Y
    bne !miss+
    lda test_mon1_visible
    bne !visible+
!miss:
    clc
    rts
!visible:
    sec
    rts

test_pmx_print_inline:
    sta zp_ptr0
    sty zp_ptr0_hi
    jmp msg_print

test_pmx_report_sleep_result:
    cmp #0
    bne !any+
    ldx #HSTR_PIQ_NOTHING
    jmp huff_print_msg
!any:
    lda #<test_pmx_sleep_success_msg
    ldy #>test_pmx_sleep_success_msg
    jmp test_pmx_print_inline

test_eff_sleep_all:
    lda #0
    sta test_sleep_idx
    sta test_sleep_hits
!loop:
    ldx test_sleep_idx
    cpx #MAX_MONSTERS
    bcs !done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !next+
    ldy #MX_X
    lda (zp_ptr0),y
    tax
    ldy #MX_Y
    lda (zp_ptr0),y
    tay
    jsr los_is_visible
    bcc !next+
    ldx test_sleep_idx
    lda #25
    jsr monster_apply_sleep
    inc test_sleep_hits
!next:
    inc test_sleep_idx
    jmp !loop-
!done:
    lda test_sleep_hits
    jmp test_pmx_report_sleep_result

test_tramp_sleep_iii_execute:
    inc test_spell_exec_calls
    lda pm_spell_idx
    sta test_last_spell_idx
    jmp test_eff_sleep_all

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
    lda #21
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

test_reset_sleep_iii_state:
    lda #0
    sta test_mon0_visible
    sta test_mon1_visible
    sta test_huff_calls
    sta test_last_huff
    sta test_msg_calls
    sta test_last_msg_lo
    sta test_last_msg_hi
    sta test_spell_exec_calls
    sta test_sleep_hits
    sta test_sleep_idx
    lda #$ff
    sta test_last_spell_idx
    sta test_mon_dummy + MX_TYPE

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

    lda #10
    sta zp_player_x
    sta player_data + PL_MAP_X
    sta zp_player_y
    sta player_data + PL_MAP_Y

    lda #0
    sta player_data + PL_SPELLS_LEARNT_0
    sta player_data + PL_SPELLS_LEARNT_1
    lda #$20
    sta player_data + PL_SPELLS_LEARNT_2
    lda #0
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3

    lda #EMPTY_SLOT
    sta test_mon0_data + MX_TYPE
    sta test_mon1_data + MX_TYPE
    lda #11
    sta test_mon0_data + MX_X
    lda #10
    sta test_mon0_data + MX_Y
    lda #12
    sta test_mon1_data + MX_X
    lda #10
    sta test_mon1_data + MX_Y
    lda #MF_AWAKE
    sta test_mon0_data + MX_FLAGS
    sta test_mon1_data + MX_FLAGS
    lda #0
    sta test_mon0_data + MX_SLEEP_CUR
    sta test_mon1_data + MX_SLEEP_CUR
    rts

test_start:
    sei
    ldx #$ff
    txs

    lda #MMU_ALL_RAM
    sta $ff00
    lda #0
    sta test_progress

    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(tramp_spell_execute_selected, test_tramp_sleep_iii_execute)

    // Test 1: success sleeps visible monsters, leaves hidden monsters alone,
    // prints explicit success feedback, spends 7 mana, and marks worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_sleep_iii_state
    lda #0
    sta test_mon0_data + MX_TYPE
    sta test_mon1_data + MX_TYPE
    lda #1
    sta test_mon0_visible
    jsr player_cast_spell
    bcc !t1_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda test_last_spell_idx
    cmp #21
    bne !t1_fail+
    lda test_huff_calls
    bne !t1_fail+
    lda test_msg_calls
    cmp #1
    bne !t1_fail+
    lda test_last_msg_lo
    cmp #<test_pmx_sleep_success_msg
    bne !t1_fail+
    lda test_last_msg_hi
    cmp #>test_pmx_sleep_success_msg
    bne !t1_fail+
    lda test_mon0_data + MX_SLEEP_CUR
    cmp #25
    bne !t1_fail+
    lda test_mon0_data + MX_FLAGS
    and #MF_AWAKE
    bne !t1_fail+
    lda test_mon1_data + MX_SLEEP_CUR
    bne !t1_fail+
    lda test_mon1_data + MX_FLAGS
    and #MF_AWAKE
    beq !t1_fail+
    lda zp_player_mp
    cmp #13
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$20
    beq !t1_fail+
    lda #1
    sta test_progress
    jmp test_after_success
!t1_fail:
    jmp test_fail

    // Test 2: with no visible eligible monsters, cast prints HSTR_PIQ_NOTHING,
    // sleeps nobody, still spends mana, and still marks worked.
test_after_success:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_sleep_iii_state
    lda #0
    sta test_mon0_data + MX_TYPE
    jsr player_cast_spell
    bcc !t2_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda test_last_spell_idx
    cmp #21
    bne !t2_fail+
    lda test_huff_calls
    cmp #1
    bne !t2_fail+
    lda test_last_huff
    cmp #HSTR_PIQ_NOTHING
    bne !t2_fail+
    lda test_msg_calls
    bne !t2_fail+
    lda test_mon0_data + MX_SLEEP_CUR
    bne !t2_fail+
    lda zp_player_mp
    cmp #13
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$20
    beq !t2_fail+
    lda #2
    sta test_progress
    jmp test_after_none
!t2_fail:
    jmp test_fail

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Sleep III unworked.
test_after_none:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_sleep_iii_state
    lda #0
    sta test_mon0_data + MX_TYPE
    lda #1
    sta test_mon0_visible
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
    lda test_msg_calls
    bne !t3_fail+
    lda test_mon0_data + MX_SLEEP_CUR
    bne !t3_fail+
    lda zp_player_mp
    cmp #13
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$20
    bne !t3_fail+
    lda #3
    sta test_progress
    jmp test_pass
!t3_fail:
    jmp test_fail

test_fail:
    lda #$ff
    sta $d7ff
    jmp test_fail_loop

test_pass:
    lda #$00
    sta $d7ff
    jmp test_pass_loop

test_fail_loop:
    jmp test_fail_loop

test_pass_loop:
    jmp test_pass_loop
