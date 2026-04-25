// test_call_light_prayer.s — Focused runtime tests for the Call Light prayer row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 2, $ff

.pc = $080E "Bootstrap"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #1
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    jmp test_done_break

.pc = $0840 "Test Code"

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

tclp_spell_exec_calls: .byte 0
tclp_huff_calls: .byte 0
tclp_last_huff_id: .byte 0
tclp_last_spell_idx: .byte $ff
tclp_light_room_calls: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tclp_last_huff_id
    inc tclp_huff_calls
    rts

test_light_room_x:
    inc tclp_light_room_calls
    lda #1
    sta vis_room_revealed
    rts

test_tramp_call_light_prayer_execute:
    inc tclp_spell_exec_calls
    lda pm_spell_idx
    sta tclp_last_spell_idx
    jsr eff_light_room
    ldx #HSTR_PIQ_LIGHT
    jsr huff_print_msg
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
    lda #4
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

test_reset_call_light_prayer_state:
    jsr player_init
    lda #0
    sta tclp_spell_exec_calls
    sta tclp_huff_calls
    sta tclp_last_huff_id
    sta tclp_light_room_calls
    sta vis_room_revealed
    lda #$ff
    sta tclp_last_spell_idx

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

    lda #$10
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3

    lda #1
    sta room_count
    lda #10
    sta room_x + 0
    lda #8
    sta room_y + 0
    lda #4
    sta room_w + 0
    lda #3
    sta room_h + 0
    lda #12
    sta zp_player_x
    lda #10
    sta zp_player_y
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_call_light_prayer_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(light_room_x, test_light_room_x)

    // Test 1: successful prayer dispatches prayer index 4, exercises the
    // shared room-light seam, emits the explicit light message, spends 2 mana,
    // and marks Call Light worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_call_light_prayer_state
    jsr player_pray
    bcc !t1_fail+
    lda tclp_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tclp_last_spell_idx
    cmp #4
    bne !t1_fail+
    lda tclp_light_room_calls
    cmp #1
    bne !t1_fail+
    lda vis_room_revealed
    cmp #1
    bne !t1_fail+
    lda tclp_huff_calls
    cmp #1
    bne !t1_fail+
    lda tclp_last_huff_id
    cmp #HSTR_PIQ_LIGHT
    bne !t1_fail+
    lda zp_player_mp
    cmp #18
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #18
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$10
    beq !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: cast failure spends mana, prints HSTR_PM_FAIL, does not execute
    // the light effect, and leaves Call Light unworked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_call_light_prayer_state
    jsr player_pray
    bcc !t2_fail+
    lda tclp_spell_exec_calls
    bne !t2_fail+
    lda tclp_light_room_calls
    bne !t2_fail+
    lda vis_room_revealed
    bne !t2_fail+
    lda tclp_huff_calls
    cmp #1
    bne !t2_fail+
    lda tclp_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t2_fail+
    lda zp_player_mp
    cmp #18
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #18
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$10
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp test_finish
!t2_fail:
    lda #$00
    sta tc_results + 1
    jmp test_finish

test_done_break:
    brk
