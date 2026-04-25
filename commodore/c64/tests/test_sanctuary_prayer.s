// test_sanctuary_prayer.s — Focused runtime tests for the Sanctuary prayer row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 4, $ff

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
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    brk

.pc = $0840 "Main"

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
#import "../../common/projectile.s"
#import "../../common/spell_effects.s"
#import "../../common/spell_data.s"
#import "../../common/player_magic_state.s"
#import "../../common/player_magic_state_ops.s"
#import "../../common/player_magic.s"
#import "../../common/player_magic_feedback.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
#import "../../common/ui_trampoline_stubs.s"

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

test_mon_present:    .byte 0
test_mon_x:          .byte 0
test_mon_y:          .byte 0
test_mon_data:       .fill 12, 0
test_rng_result:     .byte 0
test_spell_exec_calls: .byte 0
test_huff_calls:     .byte 0
test_last_huff_id:   .byte 0
test_msg_calls:      .byte 0
test_last_msg_lo:    .byte 0
test_last_msg_hi:    .byte 0
test_last_spell_idx: .byte $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx test_last_huff_id
    inc test_huff_calls
    rts

test_msg_print:
    inc test_msg_calls
    lda zp_ptr0
    sta test_last_msg_lo
    lda zp_ptr0_hi
    sta test_last_msg_hi
    rts

test_monster_find_at:
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

test_monster_get_ptr:
    lda #<test_mon_data
    sta zp_ptr0
    lda #>test_mon_data
    sta zp_ptr0_hi
    rts

test_rng_range:
    lda test_rng_result
    rts

test_tramp_sanctuary_execute:
    inc test_spell_exec_calls
    lda pm_spell_idx
    sta test_last_spell_idx
    jmp pmx_sleep_adjacent_msg

test_pm_select_book:
    lda #1
    sta pm_book_idx
    lda #<book_mask_5
    sta pm_book_mask_lo
    lda #>book_mask_5
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #12
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #5
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_reset_sanctuary_state:
    jsr player_init
    lda #0
    sta test_mon_present
    sta test_rng_result
    sta test_spell_exec_calls
    sta test_huff_calls
    sta test_last_huff_id
    sta test_msg_calls
    sta test_last_msg_lo
    sta test_last_msg_hi
    lda #$ff
    sta test_last_spell_idx

    lda #CLASS_PRIEST
    sta player_data + PL_CLASS
    lda #SPELL_PRIEST
    sta pm_spell_type
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_WIS_CUR
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
    lda #$10
    sta player_data + PL_SPELLS_LEARNT_1
    lda #0
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3

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

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(msg_print, test_msg_print)
    :PatchJump(test_spell_execute_selected, test_tramp_sanctuary_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(monster_get_ptr, test_monster_get_ptr)
    :PatchJump(monster_find_at, test_monster_find_at)
    :PatchJump(rng_range, test_rng_range)

    // Test 1: successful prayer on an adjacent monster shows explicit success
    // feedback, sleeps the target, spends 5 mana, and marks Sanctuary worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_sanctuary_state
    lda #1
    sta test_mon_present
    jsr player_pray
    bcc !t1_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda test_last_spell_idx
    cmp #12
    bne !t1_fail+
    lda test_huff_calls
    bne !t1_fail+
    lda test_msg_calls
    cmp #1
    bne !t1_fail+
    lda test_last_msg_lo
    cmp #<pmx_sleep_success_msg
    bne !t1_fail+
    lda test_last_msg_hi
    cmp #>pmx_sleep_success_msg
    bne !t1_fail+
    lda test_mon_data + MX_SLEEP_CUR
    cmp #20
    bne !t1_fail+
    lda test_mon_data + MX_FLAGS
    and #MF_AWAKE
    bne !t1_fail+
    lda zp_player_mp
    cmp #15
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #15
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$10
    beq !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: resistant adjacent target reports unaffected, stays awake, and
    // still consumes mana and marks the prayer worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_sanctuary_state
    lda #1
    sta test_mon_present
    lda #20
    sta cr_level
    jsr player_pray
    bcc !t2_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda test_last_spell_idx
    cmp #12
    bne !t2_fail+
    lda test_huff_calls
    bne !t2_fail+
    lda test_msg_calls
    cmp #1
    bne !t2_fail+
    lda test_last_msg_lo
    cmp #<pmx_sleep_unaffected_msg
    bne !t2_fail+
    lda test_last_msg_hi
    cmp #>pmx_sleep_unaffected_msg
    bne !t2_fail+
    lda test_mon_data + MX_SLEEP_CUR
    bne !t2_fail+
    lda test_mon_data + MX_FLAGS
    and #MF_AWAKE
    cmp #MF_AWAKE
    bne !t2_fail+
    lda zp_player_mp
    cmp #15
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #15
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$10
    beq !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: no adjacent monsters shows explicit no-target feedback and still
    // consumes mana and marks the prayer worked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_sanctuary_state
    jsr player_pray
    bcc !t3_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t3_fail+
    lda test_last_spell_idx
    cmp #12
    bne !t3_fail+
    lda test_msg_calls
    bne !t3_fail+
    lda test_huff_calls
    cmp #1
    bne !t3_fail+
    lda test_last_huff_id
    cmp #HSTR_PIQ_NOTHING
    bne !t3_fail+
    lda test_mon_data + MX_SLEEP_CUR
    bne !t3_fail+
    lda test_mon_data + MX_FLAGS
    and #MF_AWAKE
    cmp #MF_AWAKE
    bne !t3_fail+
    lda zp_player_mp
    cmp #15
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #15
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$10
    beq !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // Test 4: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Sanctuary unworked.
!t4:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_sanctuary_state
    lda #1
    sta test_mon_present
    jsr player_pray
    bcc !t4_fail+
    lda test_spell_exec_calls
    bne !t4_fail+
    lda test_msg_calls
    bne !t4_fail+
    lda test_huff_calls
    cmp #1
    bne !t4_fail+
    lda test_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t4_fail+
    lda test_mon_data + MX_SLEEP_CUR
    bne !t4_fail+
    lda test_mon_data + MX_FLAGS
    and #MF_AWAKE
    cmp #MF_AWAKE
    bne !t4_fail+
    lda zp_player_mp
    cmp #15
    bne !t4_fail+
    lda player_data + PL_MANA
    cmp #15
    bne !t4_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$10
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp test_finish
!t4_fail:
    lda #$00
    sta tc_results + 3
    jmp test_finish
