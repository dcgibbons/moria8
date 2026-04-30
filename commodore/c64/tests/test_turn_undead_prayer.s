// test_turn_undead_prayer.s — Focused runtime tests for the Turn Undead prayer row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $0838 "Result Buffer"
tc_results: .fill 3, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    ldx #2
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    jmp test_done_break

test_done_break:
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
#import "../../common/player_magic_utility.s"
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

ttup_spell_exec_calls: .byte 0
ttup_huff_calls: .byte 0
ttup_last_huff_id: .byte 0
ttup_last_spell_idx: .byte $ff
ttup_frantic_calls: .byte 0
ttup_unaffected_calls: .byte 0
ttup_rng_value: .byte 0
pmx_work_idx: .byte 0
pmx_work_flag: .byte 0
pmx_work_damage: .byte 0

test_mon_table: .fill MAX_MONSTERS * MONSTER_ENTRY_SIZE, 0
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

test_huff_print_msg:
    stx ttup_last_huff_id
    inc ttup_huff_calls
    rts

test_rng_range:
    lda ttup_rng_value
    rts

test_combat_msg_monster_runs_frantically:
    inc ttup_frantic_calls
    rts

test_combat_msg_monster_unaffected:
    inc ttup_unaffected_calls
    rts

eff_remove_fear:
    rts

test_monster_get_ptr:
    lda test_mon_ptr_lo,x
    sta zp_ptr0
    lda test_mon_ptr_hi,x
    sta zp_ptr0_hi
    rts

test_tramp_turn_undead_prayer_execute:
    inc ttup_spell_exec_calls
    lda pm_spell_idx
    sta ttup_last_spell_idx
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
    jsr player_init
    jsr test_clear_monsters
    lda #0
    sta ttup_spell_exec_calls
    sta ttup_huff_calls
    sta ttup_last_huff_id
    sta ttup_frantic_calls
    sta ttup_unaffected_calls
    sta ttup_rng_value
    sta cr_mflags + 0
    sta cr_mflags + 1
    sta cr_mflags + 2
    sta cr_mflags + 3
    lda #$ff
    sta ttup_last_spell_idx

    lda #CLASS_PRIEST
    sta player_data + PL_CLASS
    lda #SPELL_PRIEST
    sta pm_spell_type
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #1
    sta zp_light_radius
    sta player_data + PL_LIGHT_RAD
    lda #18
    sta player_data + PL_WIS_CUR
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

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(rng_range, test_rng_range)
    :PatchJump(combat_msg_monster_runs_frantically, test_combat_msg_monster_runs_frantically)
    :PatchJump(combat_msg_monster_unaffected, test_combat_msg_monster_unaffected)
    :PatchJump(test_spell_execute_selected, test_tramp_turn_undead_prayer_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(monster_get_ptr, test_monster_get_ptr)

    // Test 1: Turn Undead affects only visible undead. Low-level visible
    // undead turn and report frantically, high-level visible undead resist and
    // report unaffected, hidden undead and non-undead stay unchanged.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_turn_undead_prayer_state
    lda #CF_UNDEAD
    sta cr_mflags + 1
    sta cr_mflags + 3
    lda #20
    sta zp_player_x
    lda #12
    sta zp_player_y
    ldx #12
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED | FLAG_OCCUPIED
    :MapWrite_ptr1_y()
    ldy #21
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED | FLAG_OCCUPIED
    :MapWrite_ptr1_y()
    ldy #25
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_OCCUPIED
    :MapWrite_ptr1_y()
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
    sta ttup_rng_value
    jsr player_pray
    bcc !t1_fail+
    lda ttup_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda ttup_last_spell_idx
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
    lda ttup_frantic_calls
    cmp #1
    bne !t1_fail+
    lda ttup_unaffected_calls
    cmp #1
    bne !t1_fail+
    lda ttup_huff_calls
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
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: no visible undead prints HSTR_PIQ_NOTHING, spends mana, and
    // marks the prayer worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_turn_undead_prayer_state
    lda #2
    sta test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_TYPE
    lda #9
    sta test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    jsr player_pray
    bcc !t2_fail+
    lda ttup_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda ttup_last_spell_idx
    cmp #24
    bne !t2_fail+
    lda test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_CONFUSE
    bne !t2_fail+
    lda test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    cmp #9
    bne !t2_fail+
    lda ttup_huff_calls
    cmp #1
    bne !t2_fail+
    lda ttup_last_huff_id
    cmp #HSTR_PIQ_NOTHING
    bne !t2_fail+
    lda ttup_frantic_calls
    bne !t2_fail+
    lda ttup_unaffected_calls
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
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not execute
    // Turn Undead, and leaves the prayer unworked.
!t3:
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
    lda ttup_spell_exec_calls
    bne !t3_fail+
    lda test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_CONFUSE
    bne !t3_fail+
    lda test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_SLEEP_CUR
    cmp #7
    bne !t3_fail+
    lda ttup_huff_calls
    cmp #1
    bne !t3_fail+
    lda ttup_last_huff_id
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
    lda #$01
    sta tc_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta tc_results + 2
    jmp test_finish
