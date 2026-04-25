// test_sleep_iii.s — Focused runtime tests for the Sleep III spell row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 3, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #2
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

test_mon0_visible:   .byte 0
test_mon1_visible:   .byte 0
test_mon0_data:      .fill 12, 0
test_mon1_data:      .fill 12, 0
test_mon_dummy:      .fill 12, 0
test_spell_exec_calls: .byte 0
test_huff_calls:     .byte 0
test_last_huff_id:   .byte 0
test_msg_calls:      .byte 0
test_last_msg_lo:    .byte 0
test_last_msg_hi:    .byte 0
test_last_spell_idx: .byte $ff
test_sleep_hits:     .byte 0
test_sleep_idx:      .byte 0

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

test_monster_get_ptr:
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

test_los_is_visible:
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
    jmp pmx_report_sleep_result

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
    jsr player_init
    lda #0
    sta test_mon0_visible
    sta test_mon1_visible
    sta test_spell_exec_calls
    sta test_huff_calls
    sta test_last_huff_id
    sta test_msg_calls
    sta test_last_msg_lo
    sta test_last_msg_hi
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
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(msg_print, test_msg_print)
    :PatchJump(test_spell_execute_selected, test_tramp_sleep_iii_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(monster_get_ptr, test_monster_get_ptr)
    :PatchJump(los_is_visible, test_los_is_visible)

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
    cmp #<pmx_sleep_success_msg
    bne !t1_fail+
    lda test_last_msg_hi
    cmp #>pmx_sleep_success_msg
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
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: with no visible eligible monsters, cast prints HSTR_PIQ_NOTHING,
    // sleeps nobody, still spends mana, and still marks worked.
!t2:
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
    lda test_last_huff_id
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
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Sleep III unworked.
!t3:
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
    lda test_last_huff_id
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
    lda #$01
    sta tc_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta tc_results + 2
    jmp test_finish
