// test_portal_prayer.s — Focused runtime tests for the Portal prayer row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 2, $ff

.pc = $080E "Test Code"

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
    brk

.pc = $0840 "Main"

.segmentdef TestCreateOverlay [start=$D000, min=$D000, max=$DFFF]
#import "../../../../core/6502/zeropage.s"
#import "../memory.s"
#define REU_DETECT_EXTERNAL      // not exercised here; frees room below MAP_BASE
#import "../../common/reu.s"
#import "../screen.s"
#import "../../../../core/6502/color.s"
#import "../config.s"
#import "../input.s"
#import "../../../../core/6502/rng.s"
#import "../../../../core/6502/math.s"
#import "../../../../core/6502/tables.s"
#import "../../../../core/6502/item_defs.s"
#import "../../../../core/6502/player.s"
#import "../../../../core/6502/ui_messages.s"
#import "../../../../core/6502/ui_status.s"
#import "../../../../core/6502/ui_help_clear.s"
#import "../../../../core/6502/stat_display.s"
.segment TestCreateOverlay
player_create:
    brk
.segment Default
#import "../../../../core/6502/sound.s"
#import "../../../../core/6502/dungeon_data.s"
#import "dungeon_gen_stubs.s"
#import "../../../../core/6502/huffman.s"
#import "../../../../core/6502/dungeon_features.s"
#import "chest_summons_stubs.s"
#import "../../../../core/6502/monster.s"
#import "../../../../core/6502/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/6502/monster_ai.s"
#import "../../../../core/6502/recall.s"
.segment TestCreateOverlay
#import "../../../../core/6502/monster_magic.s"
.segment Default
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../../../../core/6502/item.s"
#import "item_cat_resident_helper.s"
.segment TestCreateOverlay
#import "../../../../core/6502/special_rooms.s"
.segment Default
#import "../../../../core/6502/ego_items.s"
#import "../../../../core/6502/special_rooms_stubs.s"
#import "../../../../core/6502/player_items.s"
#import "../../../../core/6502/projectile.s"
#import "../../../../core/6502/spell_effects.s"
#import "../../../../core/6502/spell_data.s"
#import "../../../../core/6502/player_magic_state.s"
#import "../../../../core/6502/player_magic_state_ops.s"
#import "../../../../core/6502/player_magic.s"
#import "../../../../core/6502/player_magic_feedback.s"
.segment TestCreateOverlay
#import "../dungeon_render.s"
.segment Default
#import "../../../../core/6502/dungeon_los.s"
#import "../../../../core/6502/player_move.s"
#import "../../../../core/6502/combat.s"
#import "../../../../core/6502/scene_mat_tile.s"
#import "../../../../core/6502/monster_attack.s"
#import "../../../../core/6502/turn.s"
#import "../../../../core/6502/item_actions_overlay.s"
#import "../../../../core/6502/ui_trampoline_stubs.s"

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

tpp_spell_exec_calls: .byte 0
tpp_huff_calls: .byte 0
tpp_last_huff_id: .byte 0
tpp_last_spell_idx: .byte $ff
tpp_find_random_floor_calls: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tpp_last_huff_id
    inc tpp_huff_calls
    rts

test_tramp_portal_prayer_execute:
    inc tpp_spell_exec_calls
    lda pm_spell_idx
    sta tpp_last_spell_idx
    jsr eff_teleport_self
    rts

test_pm_select_book:
    lda #1
    sta pm_book_idx
    lda #<book_mask_5
    sta pm_book_mask_lo
    lda #>book_mask_5
    sta pm_book_mask_hi
    sec
    rts

test_pm_pick_visible_prayer:
    lda #9
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_prayer:
    lda #4
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_find_random_floor_portal:
    inc tpp_find_random_floor_calls
    lda #40
    sta df_target_x
    lda #30
    sta df_target_y
    sec
    rts

test_write_tile:
    stx zp_ptr1
    sty zp_ptr1_hi
    pha
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_ptr1_hi
    pla
    sta (zp_ptr0),y
    rts

test_read_tile:
    stx zp_ptr1
    sty zp_ptr1_hi
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_ptr1_hi
    lda (zp_ptr0),y
    rts

test_setup_portal_room:
    jsr fill_map_rock
    lda #0
    sta vis_room_revealed
    sta tpp_find_random_floor_calls

    lda #22
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #12
    sta zp_player_y
    sta player_data + PL_MAP_Y

    lda #TILE_FLOOR                 // the player's tile: no creature flag
    ldx #12
    ldy #22
    jsr test_write_tile

    lda #TILE_FLOOR
    ldx #30
    ldy #40
    jsr test_write_tile
    rts

test_reset_portal_prayer_state:
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
    lda #20
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda #0
    sta player_data + PL_SPELLS_LEARNT_0
    lda #$02
    sta player_data + PL_SPELLS_LEARNT_1
    lda #0
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    lda #0
    sta tpp_spell_exec_calls
    sta tpp_huff_calls
    sta tpp_last_huff_id
    lda #$ff
    sta tpp_last_spell_idx
    rts

// Dropped ui_* imports to stay under the map-overlap boundary.
ui_char_display:
    rts
count_spells_known:
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_portal_prayer_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_pick_visible_prayer)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_prayer)
    :PatchJump(find_random_floor_near, test_find_random_floor_portal)  // eff_teleport_self's search entry

    // Test 1: successful prayer relocates to the random floor target, updates
    // occupancy + redraw state, stays message-light, spends 4 mana, and marks
    // prayer slot 9 worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_portal_prayer_state
    jsr test_setup_portal_room
    jsr player_pray
    bcc !t1_fail+
    lda tpp_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tpp_last_spell_idx
    cmp #9
    bne !t1_fail+
    lda tpp_find_random_floor_calls
    cmp #1
    bne !t1_fail+
    lda zp_player_x
    cmp #40
    bne !t1_fail+
    lda zp_player_y
    cmp #30
    bne !t1_fail+
    lda tpp_huff_calls
    bne !t1_fail+
    lda vis_room_revealed
    cmp #1
    bne !t1_fail+
    ldx #12
    ldy #22
    jsr test_read_tile
    and #FLAG_OCCUPIED
    bne !t1_fail+
    ldx #30
    ldy #40
    jsr test_read_tile
    and #FLAG_OCCUPIED
    bne !t1_fail+
    lda zp_player_mp
    cmp #16
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #16
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$02
    beq !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: prayer failure spends mana, prints HSTR_PM_FAIL, does not
    // execute, and leaves Portal unworked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_portal_prayer_state
    jsr test_setup_portal_room
    jsr player_pray
    bcc !t2_fail+
    lda tpp_spell_exec_calls
    bne !t2_fail+
    lda tpp_find_random_floor_calls
    bne !t2_fail+
    lda zp_player_x
    cmp #22
    bne !t2_fail+
    lda zp_player_y
    cmp #12
    bne !t2_fail+
    lda tpp_huff_calls
    cmp #1
    bne !t2_fail+
    lda tpp_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t2_fail+
    lda vis_room_revealed
    bne !t2_fail+
    ldx #12
    ldy #22
    jsr test_read_tile
    and #FLAG_OCCUPIED
    bne !t2_fail+
    ldx #30
    ldy #40
    jsr test_read_tile
    and #FLAG_OCCUPIED
    bne !t2_fail+
    lda zp_player_mp
    cmp #16
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #16
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$02
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp test_finish
!t2_fail:
    lda #$00
    sta tc_results + 1
    jmp test_finish
