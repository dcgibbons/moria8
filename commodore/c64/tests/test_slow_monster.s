// test_slow_monster.s — Focused runtime tests for the Slow Monster spell row

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
#import "../../common/player_magic_slow_runtime.s"
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

test_mon_present: .byte 0
test_mon_data: .fill 12, 0
tsm_spell_exec_calls: .byte 0
tsm_huff_calls: .byte 0
tsm_last_huff_id: .byte 0
tsm_msg_calls: .byte 0
tsm_last_msg_lo: .byte 0
tsm_last_msg_hi: .byte 0
tsm_last_spell_idx: .byte $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tsm_last_huff_id
    inc tsm_huff_calls
    rts

test_msg_print:
    lda zp_ptr0
    sta tsm_last_msg_lo
    lda zp_ptr0_hi
    sta tsm_last_msg_hi
    inc tsm_msg_calls
    rts

test_eff_directional_monster:
    lda test_mon_present
    beq !miss+
    lda #<test_mon_data
    sta zp_ptr0
    lda #>test_mon_data
    sta zp_ptr0_hi
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

test_eff_slow_monster_dir:
    jsr eff_directional_monster
    bcc !done+
    ldy #MX_SPEED_CNT
    lda #$ff
    sta (zp_ptr0),y
    iny
    lda #0
    sta (zp_ptr0),y
    lda #<pmx_slow_monster_msg
    sta zp_ptr0
    lda #>pmx_slow_monster_msg
    sta zp_ptr0_hi
    jsr msg_print
!done:
    rts

test_tramp_slow_monster_execute:
    inc tsm_spell_exec_calls
    lda pm_spell_idx
    sta tsm_last_spell_idx
    jsr test_eff_slow_monster_dir
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
    lda #23
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #9
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_reset_slow_monster_state:
    jsr player_init
    lda #0
    sta test_mon_present
    sta tsm_spell_exec_calls
    sta tsm_huff_calls
    sta tsm_last_huff_id
    sta tsm_msg_calls
    sta tsm_last_msg_lo
    sta tsm_last_msg_hi
    lda #$ff
    sta tsm_last_spell_idx

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
    lda #$80
    sta player_data + PL_SPELLS_LEARNT_2
    lda #0
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3

    lda #0
    sta test_mon_data + MX_SPEED_CNT
    lda #7
    sta test_mon_data + MX_SLEEP_CUR
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(msg_print, test_msg_print)
    :PatchJump(test_spell_execute_selected, test_tramp_slow_monster_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(eff_directional_monster, test_eff_directional_monster)
    :PatchJump(monster_get_ptr, test_monster_get_ptr)

    // Test 1: successful cast on a valid target slows it, clears sleep,
    // prints the slowed-target message, spends 9 mana, and marks worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_slow_monster_state
    lda #1
    sta test_mon_present
    jsr player_cast_spell
    bcc !t1_fail+
    lda tsm_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tsm_last_spell_idx
    cmp #23
    bne !t1_fail+
    lda test_mon_data + MX_SPEED_CNT
    cmp #$ff
    bne !t1_fail+
    lda test_mon_data + MX_SLEEP_CUR
    bne !t1_fail+
    lda tsm_huff_calls
    bne !t1_fail+
    lda tsm_msg_calls
    cmp #1
    bne !t1_fail+
    lda tsm_last_msg_lo
    cmp #<pmx_slow_monster_msg
    bne !t1_fail+
    lda tsm_last_msg_hi
    cmp #>pmx_slow_monster_msg
    bne !t1_fail+
    lda zp_player_mp
    cmp #11
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #11
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$80
    beq !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: with no valid target, cast stays silent/no-effect while still
    // consuming mana and marking the spell worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_slow_monster_state
    jsr player_cast_spell
    bcc !t2_fail+
    lda tsm_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda tsm_last_spell_idx
    cmp #23
    bne !t2_fail+
    lda tsm_huff_calls
    bne !t2_fail+
    lda tsm_msg_calls
    bne !t2_fail+
    lda test_mon_data + MX_SPEED_CNT
    bne !t2_fail+
    lda test_mon_data + MX_SLEEP_CUR
    cmp #7
    bne !t2_fail+
    lda zp_player_mp
    cmp #11
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #11
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$80
    beq !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not
    // execute, and leaves Slow Monster unworked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_slow_monster_state
    lda #1
    sta test_mon_present
    jsr player_cast_spell
    bcc !t3_fail+
    lda tsm_spell_exec_calls
    bne !t3_fail+
    lda tsm_huff_calls
    cmp #1
    bne !t3_fail+
    lda tsm_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda tsm_msg_calls
    bne !t3_fail+
    lda test_mon_data + MX_SPEED_CNT
    bne !t3_fail+
    lda test_mon_data + MX_SLEEP_CUR
    cmp #7
    bne !t3_fail+
    lda zp_player_mp
    cmp #11
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #11
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$80
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta tc_results + 2
    jmp test_finish
