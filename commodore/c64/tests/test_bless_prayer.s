// test_bless_prayer.s — Focused runtime tests for the Bless prayer row

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

.pc = $0840 "Test Body"

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

tbp_spell_exec_calls: .byte 0
tbp_huff_calls: .byte 0
tbp_last_huff_id: .byte 0
tbp_msg_calls: .byte 0
tbp_last_msg_lo: .byte 0
tbp_last_msg_hi: .byte 0
tbp_last_spell_idx: .byte $ff
tbp_rng_value: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tbp_last_huff_id
    inc tbp_huff_calls
    rts

test_msg_print_capture:
    inc tbp_msg_calls
    lda zp_ptr0
    sta tbp_last_msg_lo
    lda zp_ptr0_hi
    sta tbp_last_msg_hi
    rts

test_rng_range:
    lda tbp_rng_value
    rts

test_tramp_bless_prayer_execute:
    inc tbp_spell_exec_calls
    lda pm_spell_idx
    sta tbp_last_spell_idx
    lda #12
    jsr rng_range
    clc
    adc #12
    jsr pmx_add_bless_msg
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
    lda #2
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #2
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_reset_bless_prayer_state:
    jsr player_init
    lda #0
    sta tbp_spell_exec_calls
    sta tbp_huff_calls
    sta tbp_last_huff_id
    sta tbp_msg_calls
    sta tbp_last_msg_lo
    sta tbp_last_msg_hi
    sta zp_eff_bless
    sta tbp_rng_value
    lda #$ff
    sta tbp_last_spell_idx

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

    lda #$04
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

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(msg_print, test_msg_print_capture)
    :PatchJump(rng_range, test_rng_range)
    :PatchJump(test_spell_execute_selected, test_tramp_bless_prayer_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: onset prints the righteous message, sets the bless timer to 12,
    // spends 2 mana, and marks Bless worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_bless_prayer_state
    lda #0
    sta tbp_rng_value
    jsr player_pray
    bcc !t1_fail+
    lda tbp_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tbp_last_spell_idx
    cmp #2
    bne !t1_fail+
    lda zp_eff_bless
    cmp #12
    bne !t1_fail+
    lda tbp_msg_calls
    cmp #1
    bne !t1_fail+
    lda tbp_last_msg_lo
    cmp #<pmx_righteous_msg
    bne !t1_fail+
    lda tbp_last_msg_hi
    cmp #>pmx_righteous_msg
    bne !t1_fail+
    lda tbp_huff_calls
    bne !t1_fail+
    lda zp_player_mp
    cmp #18
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #18
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$04
    beq !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: refresh stays silent and adds onto the existing bless timer.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_bless_prayer_state
    lda #5
    sta zp_eff_bless
    lda #0
    sta tbp_rng_value
    jsr player_pray
    bcc !t2_fail+
    lda tbp_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda tbp_last_spell_idx
    cmp #2
    bne !t2_fail+
    lda zp_eff_bless
    cmp #17
    bne !t2_fail+
    lda tbp_msg_calls
    bne !t2_fail+
    lda tbp_huff_calls
    bne !t2_fail+
    lda zp_player_mp
    cmp #18
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #18
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$04
    beq !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not set
    // bless, and leaves Bless unworked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_bless_prayer_state
    jsr player_pray
    bcc !t3_fail+
    lda tbp_spell_exec_calls
    bne !t3_fail+
    lda zp_eff_bless
    bne !t3_fail+
    lda tbp_huff_calls
    cmp #1
    bne !t3_fail+
    lda tbp_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda tbp_msg_calls
    bne !t3_fail+
    lda zp_player_mp
    cmp #18
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #18
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$04
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta tc_results + 2
    jmp test_finish
