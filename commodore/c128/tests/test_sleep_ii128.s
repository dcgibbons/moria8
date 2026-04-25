#importonce
// test_sleep_ii128.s — Focused C128 coverage for the Sleep II row

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
.const MF_AWAKE = $01
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
it_name_lo: .fill 64, 0
it_name_hi: .fill 64, 0
cmb_period:
    .text "." ; .byte 0
trap_count: .byte 0
trap_x: .fill 16, 0
trap_y: .fill 16, 0
trap_type: .fill 16, 0
cr_level: .byte 0
cr_mflags: .fill 65, 0

test_mon_present: .byte 0
test_mon_x: .byte 0
test_mon_y: .byte 0
test_mon_data: .fill 12, 0
test_huff_calls: .byte 0
test_last_huff: .byte 0
test_msg_calls: .byte 0
test_last_msg_lo: .byte 0
test_last_msg_hi: .byte 0
test_rng_result: .byte 0
test_spell_exec_calls: .byte 0
test_last_spell_idx: .byte $ff
test_progress: .byte 0
vis_room_revealed: .byte 0
test_sleep_hits: .byte 0
test_sleep_seen: .byte 0
test_dir_idx: .byte 0
test_feedback_x: .byte 0
test_feedback_y: .byte 0
test_mon_slot: .byte 0

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
input_wait_release:
input_get_key:
input_get_key_fast:
show_inv_and_select:
tramp_spell_list_display:
combat_kill_message:
monster_wake:
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

monster_find_at:
    cmp test_mon_x
    bne !miss+
    cpy test_mon_y
    bne !miss+
    lda test_mon_present
    beq !miss+
    ldx #0
    sec
    rts
!miss:
    clc
    rts

monster_get_ptr:
    lda #<test_mon_data
    sta zp_ptr0
    lda #>test_mon_data
    sta zp_ptr0_hi
    rts

test_pmx_print_inline:
    sta zp_ptr0
    sty zp_ptr0_hi
    jmp msg_print

test_pmx_sleep_adjacent_msg:
    lda #0
    sta test_sleep_hits
    sta test_sleep_seen
    sta test_dir_idx
!scan:
    ldx test_dir_idx
    cpx #8
    bcs !done_scan+
    lda zp_player_x
    clc
    adc dir_dx,x
    sta test_feedback_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta test_feedback_y
    lda test_feedback_x
    ldy test_feedback_y
    jsr monster_find_at
    bcc !next+
    inc test_sleep_seen
    stx test_mon_slot
    jsr test_pmx_try_sleep_monster
    bcc !next+
    inc test_sleep_hits
!next:
    inc test_dir_idx
    jmp !scan-
!done_scan:
    lda test_sleep_hits
    bne !any+
    lda test_sleep_seen
    bne !unaffected+
    ldx #HSTR_PIQ_NOTHING
    jmp huff_print_msg
!any:
    lda #<test_pmx_sleep_success_msg
    ldy #>test_pmx_sleep_success_msg
    jmp test_pmx_print_inline
!unaffected:
    lda #<test_pmx_sleep_unaffected_msg
    ldy #>test_pmx_sleep_unaffected_msg
    jmp test_pmx_print_inline

test_pmx_try_sleep_monster:
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda #40
    jsr test_rng_range
    cmp cr_level,x
    bcc !resist+
    ldx test_mon_slot
    lda #20
    jsr monster_apply_sleep
    sec
    rts
!resist:
    clc
    rts

test_pmx_sleep_success_msg:
    .text "A monster falls asleep." ; .byte 0
test_pmx_sleep_unaffected_msg:
    .text "The monster is unaffected." ; .byte 0

test_rng_range:
    lda test_rng_result
    rts

test_tramp_sleep_ii_execute:
    inc test_spell_exec_calls
    lda pm_spell_idx
    sta test_last_spell_idx
    jmp test_pmx_sleep_adjacent_msg

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
    lda #18
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

test_reset_sleep_ii_state:
    lda #0
    sta test_mon_present
    sta test_huff_calls
    sta test_last_huff
    sta test_msg_calls
    sta test_last_msg_lo
    sta test_last_msg_hi
    sta test_rng_result
    sta test_spell_exec_calls
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
    lda #$04
    sta player_data + PL_SPELLS_LEARNT_2
    lda #0
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3

    lda #10
    sta zp_player_x
    lda #10
    sta zp_player_y
    lda #11
    sta test_mon_x
    lda #10
    sta test_mon_y
    lda #0
    sta cr_level
    sta test_mon_data + MX_TYPE
    lda #MF_AWAKE
    sta test_mon_data + MX_FLAGS
    lda #0
    sta test_mon_data + MX_SLEEP_CUR
    rts

monster_apply_sleep:
    pha
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #<~MF_AWAKE
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    pla
    sta (zp_ptr0),y
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
    :PatchJump(tramp_spell_execute_selected, test_tramp_sleep_ii_execute)

    // Test 1: successful cast on an adjacent monster shows explicit success
    // feedback, sleeps the target, spends 7 mana, and marks worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_sleep_ii_state
    lda #1
    sta test_mon_present
    jsr player_cast_spell
    bcc !t1_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda test_last_spell_idx
    cmp #18
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
    lda test_mon_data + MX_SLEEP_CUR
    cmp #20
    bne !t1_fail+
    lda test_mon_data + MX_FLAGS
    and #MF_AWAKE
    bne !t1_fail+
    lda zp_player_mp
    cmp #13
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$04
    beq !t1_fail+
    lda #1
    sta test_progress
    jmp test_after_success
!t1_fail:
    jmp test_fail

    // Test 2: resistant adjacent target reports unaffected, stays awake, and
    // still consumes mana and marks the spell worked.
test_after_success:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_sleep_ii_state
    lda #1
    sta test_mon_present
    lda #20
    sta cr_level
    jsr player_cast_spell
    bcc !t2_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda test_last_spell_idx
    cmp #18
    bne !t2_fail+
    lda test_huff_calls
    bne !t2_fail+
    lda test_msg_calls
    cmp #1
    bne !t2_fail+
    lda test_last_msg_lo
    cmp #<test_pmx_sleep_unaffected_msg
    bne !t2_fail+
    lda test_last_msg_hi
    cmp #>test_pmx_sleep_unaffected_msg
    bne !t2_fail+
    lda test_mon_data + MX_SLEEP_CUR
    bne !t2_fail+
    lda test_mon_data + MX_FLAGS
    and #MF_AWAKE
    cmp #MF_AWAKE
    bne !t2_fail+
    lda zp_player_mp
    cmp #13
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$04
    beq !t2_fail+
    lda #2
    sta test_progress
    jmp test_after_unaffected
!t2_fail:
    jmp test_fail

    // Test 3: no adjacent monsters shows explicit no-target feedback and still
    // consumes mana and marks the spell worked.
test_after_unaffected:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_sleep_ii_state
    jsr player_cast_spell
    bcc !t3_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t3_fail+
    lda test_last_spell_idx
    cmp #18
    bne !t3_fail+
    lda test_msg_calls
    bne !t3_fail+
    lda test_huff_calls
    cmp #1
    bne !t3_fail+
    lda test_last_huff
    cmp #HSTR_PIQ_NOTHING
    bne !t3_fail+
    lda test_mon_data + MX_SLEEP_CUR
    bne !t3_fail+
    lda test_mon_data + MX_FLAGS
    and #MF_AWAKE
    cmp #MF_AWAKE
    bne !t3_fail+
    lda zp_player_mp
    cmp #13
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$04
    beq !t3_fail+
    lda #3
    sta test_progress
    jmp test_after_no_target
!t3_fail:
    jmp test_fail

    // Test 4: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Sleep II unworked.
test_after_no_target:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_sleep_ii_state
    lda #1
    sta test_mon_present
    jsr player_cast_spell
    bcc !t4_fail+
    lda test_spell_exec_calls
    bne !t4_fail+
    lda test_msg_calls
    bne !t4_fail+
    lda test_huff_calls
    cmp #1
    bne !t4_fail+
    lda test_last_huff
    cmp #HSTR_PM_FAIL
    bne !t4_fail+
    lda test_mon_data + MX_SLEEP_CUR
    bne !t4_fail+
    lda test_mon_data + MX_FLAGS
    and #MF_AWAKE
    cmp #MF_AWAKE
    bne !t4_fail+
    lda zp_player_mp
    cmp #13
    bne !t4_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t4_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$04
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
