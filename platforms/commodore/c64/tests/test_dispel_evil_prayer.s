// test_dispel_evil_prayer.s — Focused runtime tests for the Dispel Evil prayer row

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
test_done_break:
    brk

.pc = $0840 "Main"

#import "../../../../core/zeropage.s"
#import "../memory.s"
#import "../../common/reu.s"
#import "../screen.s"
#import "../../../../core/color.s"
#import "../config.s"
#import "../input.s"
#import "../../../../core/rng.s"
#import "../../../../core/math.s"
#import "../../../../core/tables.s"
#import "../../../../core/item_defs.s"
#import "../../../../core/player.s"
#import "../../../../core/ui_messages.s"
#import "../../../../core/ui_status.s"
#import "../../../../core/ui_help_clear.s"
#import "../../../../core/ui_character.s"
#import "../../../../core/stat_display.s"
.segmentdef TestCreateOverlay [start=$D000]
.segment TestCreateOverlay
#import "../../../../core/background_data.s"
#import "../../../../core/player_create.s"
.segment Default
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "../../../../core/dungeon_gen.s"
#import "../../../../core/huffman.s"
#import "../../../../core/dungeon_features.s"
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/monster_ai.s"
#import "../../../../core/recall.s"
#import "../../../../core/monster_magic.s"
#import "../../../../core/item.s"
#import "../../../../core/special_rooms.s"
#import "../../../../core/ego_items.s"
#import "../../../../core/special_rooms_stubs.s"
#import "../../../../core/player_items.s"
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../../../../core/player_magic_utility.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"
#import "../../../../core/ui_trampoline_stubs.s"

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

tdep_spell_exec_calls: .byte 0
tdep_huff_calls: .byte 0
tdep_last_huff_id: .byte 0
tdep_last_spell_idx: .byte $ff
tdep_kill_calls: .byte 0
tdep_rng_value: .byte 0
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
    stx tdep_last_huff_id
    inc tdep_huff_calls
    rts

eff_remove_fear:
    rts

test_rng_range:
    lda tdep_rng_value
    rts

test_monster_get_ptr:
    lda test_mon_ptr_lo,x
    sta zp_ptr0
    lda test_mon_ptr_hi,x
    sta zp_ptr0_hi
    rts

test_combat_kill_message:
    inc tdep_kill_calls
    jsr monster_remove
    inc zp_dirty_count
    rts

test_tramp_dispel_evil_prayer_execute:
    inc tdep_spell_exec_calls
    lda pm_spell_idx
    sta tdep_last_spell_idx
    lda #CF_EVIL
    sta pmx_work_flag
    lda zp_player_lvl
    asl
    clc
    adc zp_player_lvl
    sta pmx_work_damage
    jsr eff_dispel_flagged
    bne !done+
    ldx #HSTR_PIQ_NOTHING
    jsr huff_print_msg
!done:
    rts

test_pm_select_book:
    lda #3
    sta pm_book_idx
    lda #<book_mask_7
    sta pm_book_mask_lo
    lda #>book_mask_7
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #28
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #32
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

test_reset_dispel_evil_prayer_state:
    jsr player_init
    jsr test_clear_monsters
    lda #0
    sta tdep_spell_exec_calls
    sta tdep_huff_calls
    sta tdep_last_huff_id
    sta tdep_kill_calls
    sta tdep_rng_value
    lda #$ff
    sta tdep_last_spell_idx

    lda #0
    ldx #0
!clr_flags:
    sta cr_mflags,x
    inx
    cpx #65
    bcc !clr_flags-

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
    lda #40
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA

    lda #0
    sta player_data + PL_SPELLS_LEARNT_0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    lda #$10
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
    :PatchJump(monster_get_ptr, test_monster_get_ptr)
    :PatchJump(combat_kill_message, test_combat_kill_message)
    :PatchJump(test_spell_execute_selected, test_tramp_dispel_evil_prayer_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: Dispel Evil damages visible eligible evil targets through the
    // shared flagged-dispel owner, kills a 1 HP evil target, leaves non-evil
    // untouched, spends 32 mana, and marks slot 28 worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_dispel_evil_prayer_state
    lda #CF_EVIL
    sta cr_mflags + 1
    lda #1
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_TYPE
    lda #20
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_X
    sta zp_player_x
    lda #12
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_Y
    sta zp_player_y
    ldx #12
    lda map_row_lo,x
    sta zp_ptr1
    lda map_row_hi,x
    sta zp_ptr1_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED | FLAG_OCCUPIED
    :MapWrite_ptr1_y()
    lda #1
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_HP_LO
    lda #2
    sta test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_TYPE
    lda #5
    sta test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_HP_LO
    lda #1
    sta tdep_rng_value
    lda #$02
    sta tc_results + 0
    jsr player_pray
    bcc !t1_fail+
    lda #$03
    sta tc_results + 0
    lda tdep_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda #$04
    sta tc_results + 0
    lda tdep_last_spell_idx
    cmp #28
    bne !t1_fail+
    lda #$05
    sta tc_results + 0
    lda test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_TYPE
    cmp #EMPTY_SLOT
    bne !t1_fail+
    lda #$06
    sta tc_results + 0
    lda test_mon_table + (1 * MONSTER_ENTRY_SIZE) + MX_HP_LO
    cmp #5
    bne !t1_fail+
    lda #$07
    sta tc_results + 0
    lda tdep_huff_calls
    bne !t1_fail+
    lda #$08
    sta tc_results + 0
    lda zp_player_mp
    cmp #8
    bne !t1_fail+
    lda #$09
    sta tc_results + 0
    lda player_data + PL_MANA
    cmp #8
    bne !t1_fail+
    lda #$0a
    sta tc_results + 0
    lda player_data + PL_SPELLS_WORKED_3
    and #$10
    beq !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    // Test 2: no evil prints HSTR_PIQ_NOTHING, spends mana, and still marks
    // the prayer worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_dispel_evil_prayer_state
    lda #2
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_TYPE
    lda #5
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_HP_LO
    lda #0
    sta tdep_rng_value
    jsr player_pray
    bcc !t2_fail+
    lda tdep_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda tdep_last_spell_idx
    cmp #28
    bne !t2_fail+
    lda tdep_kill_calls
    bne !t2_fail+
    lda tdep_huff_calls
    cmp #1
    bne !t2_fail+
    lda tdep_last_huff_id
    cmp #HSTR_PIQ_NOTHING
    bne !t2_fail+
    lda zp_player_mp
    cmp #8
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #8
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$10
    beq !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not execute
    // the dispel path, and leaves the prayer unworked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_dispel_evil_prayer_state
    lda #CF_EVIL
    sta cr_mflags + 1
    lda #1
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_TYPE
    lda #1
    sta test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_HP_LO
    jsr player_pray
    bcc !t3_fail+
    lda tdep_spell_exec_calls
    bne !t3_fail+
    lda tdep_kill_calls
    bne !t3_fail+
    lda test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_TYPE
    cmp #1
    bne !t3_fail+
    lda test_mon_table + (0 * MONSTER_ENTRY_SIZE) + MX_HP_LO
    cmp #1
    bne !t3_fail+
    lda tdep_huff_calls
    cmp #1
    bne !t3_fail+
    lda tdep_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda zp_player_mp
    cmp #8
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #8
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$10
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta tc_results + 2
    jmp test_finish
