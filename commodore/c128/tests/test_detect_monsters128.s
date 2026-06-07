#importonce
// test_detect_monsters128.s — Focused C128 coverage for the Detect Monsters row

.const KEY_ESC = $ae
.const SFX_SPELL = $06
.const SFX_SPELL_FAIL = $07
.const MAX_MONSTERS = 32
.const MONSTER_ENTRY_SIZE = 12
.const EMPTY_SLOT = $ff
.const CF_EVIL = $04
.const MX_TYPE = 2
.const PIW_FILTER_PRAYER_BOOK = $fb
.const PIW_FILTER_MAGE_BOOK = $fc

.const PL_CLASS = 18
.const PL_LEVEL = 19
.const PL_INT_CUR = 28
.const PL_CON_CUR = 31
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
#import "../../common/player_magic_detect.s"
#import "../../common/player_magic.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $5000 "Test Code"

msg_row1_col: .byte 0
cmb_slot: .byte 0
cmb_type: .byte 0
cmb_buf_idx: .byte 0
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

test_detect_calls: .byte 0
test_msg_calls: .byte 0
test_last_msg_lo: .byte 0
test_last_msg_hi: .byte 0
test_huff_calls: .byte 0
test_last_huff: .byte 0
test_spell_exec_calls: .byte 0
test_progress: .byte 0
vis_room_revealed: .byte 0

test_mon_table:
    .fill MAX_MONSTERS * MONSTER_ENTRY_SIZE, 0

test_mon_ptr_lo:
    .fill MAX_MONSTERS, <(test_mon_table + i * MONSTER_ENTRY_SIZE)
test_mon_ptr_hi:
    .fill MAX_MONSTERS, >(test_mon_table + i * MONSTER_ENTRY_SIZE)

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
msg_clear:
input_wait_release:
.label hal_input_wait_release = input_wait_release
.label hal_input_modal_prepare = input_wait_release
input_get_key:
.label hal_input_get_key = input_get_key
.label hal_input_get_text_char = input_get_key
input_get_key_fast:
show_inv_and_select:
tramp_spell_list_display:
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
    clc
    rts

calc_spell_failure:
    clc
    rts

tramp_spell_execute_selected:
    rts

eff_detect_monsters:
    inc test_detect_calls
    rts

eff_detect_evil_only:
    inc test_detect_calls
    ldx #0
!edeo_loop:
    cpx #MAX_MONSTERS
    bcs !edeo_none+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !edeo_next+
    tay
    lda cr_mflags,y
    and #CF_EVIL
    bne !edeo_found+
!edeo_next:
    inx
    jmp !edeo_loop-
!edeo_found:
    lda #1
    rts
!edeo_none:
    lda #0
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
    lda test_mon_ptr_lo,x
    sta zp_ptr0
    lda test_mon_ptr_hi,x
    sta zp_ptr0_hi
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

test_pm_prompt_visible_spell_choice:
    lda #1
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #1
    sta pm_cost_tmp
    sec
    rts

test_tramp_spell_execute_selected:
    inc test_spell_exec_calls
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_clear_monsters:
    ldx #MAX_MONSTERS * MONSTER_ENTRY_SIZE - 1
    lda #0
!clear_loop:
    sta test_mon_table,x
    dex
    bpl !clear_loop-

    ldx #0
    lda #EMPTY_SLOT
!empty_loop:
    sta test_mon_table + MX_TYPE,x
    txa
    clc
    adc #MONSTER_ENTRY_SIZE
    tax
    cpx #MAX_MONSTERS * MONSTER_ENTRY_SIZE
    bcc !empty_loop-
    rts

test_reset_detect_state:
    lda #0
    sta test_detect_calls
    sta test_msg_calls
    sta test_huff_calls
    sta test_last_huff
    sta test_spell_exec_calls

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

    lda #$02
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
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
    :PatchJump(tramp_spell_execute_selected, test_tramp_spell_execute_selected)
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)

    // Test 1: no active monsters uses the explicit no-creatures message.
    jsr test_clear_monsters
    jsr test_reset_detect_state
    jsr pmx_detect_monsters_msg
    lda test_detect_calls
    cmp #1
    bne !t1_fail+
    lda test_msg_calls
    cmp #1
    bne !t1_fail+
    lda test_last_msg_lo
    cmp #<pmx_msg_no_creatures
    bne !t1_fail+
    lda test_last_msg_hi
    cmp #>pmx_msg_no_creatures
    bne !t1_fail+
    lda test_huff_calls
    bne !t1_fail+
    lda #1
    sta test_progress
    jmp test_after_none
!t1_fail:
    jmp test_fail

    // Test 2: an active monster uses the detect-present huffman feedback.
test_after_none:
    jsr test_clear_monsters
    jsr test_reset_detect_state
    lda #0
    sta test_mon_table + MX_TYPE
    jsr pmx_detect_monsters_msg
    lda test_detect_calls
    cmp #1
    bne !t2_fail+
    lda test_huff_calls
    cmp #1
    bne !t2_fail+
    lda test_last_huff
    cmp #HSTR_PIQ_SENSE
    bne !t2_fail+
    lda test_msg_calls
    bne !t2_fail+
    lda #2
    sta test_progress
    jmp test_after_present
!t2_fail:
    jmp test_fail

    // Test 3: cast failure consumes mana, prints HSTR_PM_FAIL, and leaves
    // Detect Monsters unworked/unexecuted.
test_after_present:
    jsr test_clear_monsters
    jsr test_reset_detect_state
    jsr player_cast_spell
    bcc !t3_fail+
    lda test_huff_calls
    cmp #1
    bne !t3_fail+
    lda test_last_huff
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda test_spell_exec_calls
    bne !t3_fail+
    lda test_detect_calls
    bne !t3_fail+
    lda zp_player_mp
    cmp #19
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #19
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$02
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
