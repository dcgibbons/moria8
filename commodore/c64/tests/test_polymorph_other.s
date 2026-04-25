// test_polymorph_other.s — Focused runtime tests for the Polymorph Other row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tpo_results: .fill 3, $ff

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
    lda tpo_results,x
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
tpo_spell_exec_calls: .byte 0
tpo_huff_calls: .byte 0
tpo_last_huff_id: .byte 0
tpo_last_spell_idx: .byte $ff
tpo_remove_calls: .byte 0
tpo_spawn_calls: .byte 0
tpo_work_idx: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tpo_last_huff_id
    inc tpo_huff_calls
    rts

test_eff_directional_monster:
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

test_monster_remove:
    inc tpo_remove_calls
    lda #0
    sta test_mon_present
    ldx test_mon_data + MX_Y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy test_mon_data + MX_X
    :MapRead_ptr0_y()
    and #(~FLAG_OCCUPIED & $ff)
    :MapWrite_ptr0_y()
    rts

test_pick_creature_type:
    lda #5
    sta ms_type
    rts

test_monster_spawn_one:
    inc tpo_spawn_calls
    lda #1
    sta test_mon_present
    lda ms_spawn_x
    sta test_mon_data + MX_X
    lda ms_spawn_y
    sta test_mon_data + MX_Y
    lda ms_type
    sta test_mon_data + MX_TYPE
    ldx ms_spawn_y
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy ms_spawn_x
    :MapRead_ptr0_y()
    ora #FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    sec
    rts

test_tramp_polymorph_execute:
    inc tpo_spell_exec_calls
    lda pm_spell_idx
    sta tpo_last_spell_idx
    jsr eff_directional_monster
    bcc !done+
    stx tpo_work_idx
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    sta ms_spawn_x
    ldy #MX_Y
    lda (zp_ptr0),y
    sta ms_spawn_y
    ldx tpo_work_idx
    jsr monster_remove
    jsr pick_creature_type
    jsr monster_spawn_one
    lda #1
    sta vis_room_revealed
!done:
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
    lda #19
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

test_reset_polymorph_state:
    jsr player_init
    lda #0
    sta test_mon_present
    sta tpo_spell_exec_calls
    sta tpo_huff_calls
    sta tpo_last_huff_id
    sta tpo_remove_calls
    sta tpo_spawn_calls
    sta vis_room_revealed
    lda #$ff
    sta tpo_last_spell_idx

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
    lda #$08
    sta player_data + PL_SPELLS_LEARNT_2
    lda #0
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3

    lda #12
    sta test_mon_data + MX_X
    lda #10
    sta test_mon_data + MX_Y
    lda #1
    sta test_mon_data + MX_TYPE

    lda #10
    sta zp_player_x
    sta player_data + PL_MAP_X
    sta zp_player_y
    sta player_data + PL_MAP_Y

    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #12
    lda #TILE_FLOOR | FLAG_LIT | FLAG_OCCUPIED
    :MapWrite_ptr0_y()
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_polymorph_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(eff_directional_monster, test_eff_directional_monster)
    :PatchJump(monster_get_ptr, test_monster_get_ptr)
    :PatchJump(monster_remove, test_monster_remove)
    :PatchJump(pick_creature_type, test_pick_creature_type)
    :PatchJump(monster_spawn_one, test_monster_spawn_one)

    // Test 1: successful cast silently replaces the target monster type at the
    // same coordinates, keeps occupancy valid, spends 7 mana, and marks worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_polymorph_state
    lda #1
    sta test_mon_present
    jsr player_cast_spell
    bcc !t1_fail+
    lda tpo_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tpo_last_spell_idx
    cmp #19
    bne !t1_fail+
    lda tpo_huff_calls
    bne !t1_fail+
    lda tpo_remove_calls
    cmp #1
    bne !t1_fail+
    lda tpo_spawn_calls
    cmp #1
    bne !t1_fail+
    lda test_mon_present
    cmp #1
    bne !t1_fail+
    lda test_mon_data + MX_TYPE
    cmp #5
    bne !t1_fail+
    lda test_mon_data + MX_X
    cmp #12
    bne !t1_fail+
    lda test_mon_data + MX_Y
    cmp #10
    bne !t1_fail+
    lda vis_room_revealed
    cmp #1
    bne !t1_fail+
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #12
    :MapRead_ptr0_y()
    and #FLAG_OCCUPIED
    beq !t1_fail+
    lda zp_player_mp
    cmp #13
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$08
    beq !t1_fail+
    lda #$01
    sta tpo_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tpo_results + 0

    // Test 2: no target is a silent no-effect success that still consumes mana
    // and marks the spell worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_polymorph_state
    jsr player_cast_spell
    bcc !t2_fail+
    lda tpo_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda tpo_last_spell_idx
    cmp #19
    bne !t2_fail+
    lda tpo_huff_calls
    bne !t2_fail+
    lda tpo_remove_calls
    bne !t2_fail+
    lda tpo_spawn_calls
    bne !t2_fail+
    lda test_mon_present
    bne !t2_fail+
    lda vis_room_revealed
    bne !t2_fail+
    lda zp_player_mp
    cmp #13
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$08
    beq !t2_fail+
    lda #$01
    sta tpo_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tpo_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Polymorph Other unworked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_polymorph_state
    lda #1
    sta test_mon_present
    jsr player_cast_spell
    bcc !t3_fail+
    lda tpo_spell_exec_calls
    bne !t3_fail+
    lda tpo_huff_calls
    cmp #1
    bne !t3_fail+
    lda tpo_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda tpo_remove_calls
    bne !t3_fail+
    lda tpo_spawn_calls
    bne !t3_fail+
    lda test_mon_data + MX_TYPE
    cmp #1
    bne !t3_fail+
    lda zp_player_mp
    cmp #13
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #13
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$08
    bne !t3_fail+
    lda #$01
    sta tpo_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta tpo_results + 2
    jmp test_finish
