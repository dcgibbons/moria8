// test_find_hidden_traps_doors.s — Focused runtime tests for the Find Hidden Traps/Doors spell row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 9, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    sei
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #8
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
    brk

.pc = $0840 "Main"

.segmentdef TestUnused [start=$E160, min=$E160, max=$FFF9]
.segmentdef TestCreateOverlay [start=$D000, min=$D000, max=$DFFF]
#import "../../../../core/6502/zeropage.s"
#import "../memory.s"
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
.segment TestUnused
#import "../../../../core/6502/stat_display.s"
.segment Default
.segment TestCreateOverlay
player_create:
    brk
.segment Default
#import "../../../../core/6502/sound.s"
#import "../../../../core/6502/dungeon_data.s"
#import "../../../../core/6502/huffman.s"
.macro ChestSearchSegment() {
}
.macro ChestSearchRestoreSegment() {
}
#define CHEST_ROUTING_ENABLED
#import "../../../../core/6502/dungeon_features.s"
#import "chest_summons_stubs.s"
#import "../../../../core/6502/chest_search.s"
#import "../../../../core/6502/monster.s"
#import "../../../../core/6502/tier_manager.s"
#import "../../common/overlay.s"
.segment TestUnused
#import "../../../../core/6502/monster_ai.s"
.segment Default
#import "../../../../core/6502/recall.s"
.segment TestCreateOverlay
monster_can_cast:
monster_pick_spell:
    brk
.segment Default
#import "../../../../core/6502/item.s"
.segment TestCreateOverlay
#import "../../../../core/6502/special_rooms.s"
.segment Default
.segment TestUnused
#import "../../../../core/6502/ego_items.s"
.segment Default
#import "../../../../core/6502/special_rooms_stubs.s"
#import "../../../../core/6502/player_items.s"
.segment TestUnused
#import "../../../../core/6502/projectile.s"
.segment Default
#import "../../../../core/6502/spell_effects.s"
#import "../../../../core/6502/spell_effects_overlay.s"
#import "../../../../core/6502/spell_data.s"
#import "../../../../core/6502/player_magic_state.s"
#import "../../../../core/6502/player_magic_state_ops.s"
#import "../../../../core/6502/player_magic.s"
#import "../../../../core/6502/player_magic_feedback.s"
.segment TestUnused
#import "../dungeon_render.s"
.segment Default
#import "../../../../core/6502/dungeon_los.s"
.segment TestCreateOverlay
#import "../../../../core/6502/player_move.s"
.segment Default
.segment TestUnused
#import "../../../../core/6502/combat.s"
#import "../../../../core/6502/scene_mat_tile.s"
.segment Default
.segment TestCreateOverlay
#import "../../../../core/6502/monster_attack.s"
.segment Default
.segment TestUnused
#import "../../../../core/6502/turn.s"
.segment Default
#import "../../../../core/6502/item_actions_overlay.s"
#import "../../../../core/6502/ui_trampoline_stubs.s"

store_init_all:
    rts

// Local fill_map_rock (avoids importing all of dungeon_gen.s for map setup).
fill_map_rock:
    ldx #0
!fmr_row:
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
!fmr_col:
    lda #TILE_WALL_H
    :MapWrite_ptr0_y()
    iny
    cpy #MAP_COLS
    bne !fmr_col-
    inx
    cpx #MAP_ROWS
    bne !fmr_row-
    rts

// Linker stub — special-room generation is never exercised by this suite.
random_floor_in_room:
    lda #10
    ldy #10
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
ui_char_display:
    rts
count_spells_known:
    jmp spell_mask_count_ptr

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

tfhd_spell_exec_calls: .byte 0
tfhd_huff_calls: .byte 0
tfhd_last_huff_id: .byte 0
tfhd_last_spell_idx: .byte $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tfhd_last_huff_id
    inc tfhd_huff_calls
    rts

test_tramp_find_hidden_traps_doors_execute:
    inc tfhd_spell_exec_calls
    lda pm_spell_idx
    sta tfhd_last_spell_idx
    jsr eff_find_doors
    jsr eff_find_traps
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
    lda #5
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #3
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
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

test_reset_find_hidden_state:
    jsr player_init
    lda #0
    sta tfhd_spell_exec_calls
    sta tfhd_huff_calls
    sta tfhd_last_huff_id
    sta vis_room_revealed
    lda #$ff
    sta tfhd_last_spell_idx
    sta vis_cached_room_idx

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

    lda #$20
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3

    lda #0
    sta trap_count
    rts

test_setup_hidden_features_map:
    jsr fill_map_rock
    lda #0
    sta vis_room_revealed

    lda #TILE_SECRET
    ldx #12
    ldy #18
    jsr test_write_tile

    lda #TILE_FLOOR
    ldx #12
    ldy #22
    jsr test_write_tile

    lda #1
    sta trap_count
    lda #22
    sta trap_x
    lda #12
    sta trap_y
    lda #0
    sta trap_type
    rts

test_setup_empty_detect_map:
    jsr fill_map_rock
    lda #0
    sta vis_room_revealed
    lda #0
    sta trap_count

    lda #TILE_FLOOR
    ldx #12
    ldy #18
    jsr test_write_tile

    lda #TILE_DOOR_CLOSED
    ldx #12
    ldy #19
    jsr test_write_tile
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_find_hidden_traps_doors_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: successful cast reveals both secret doors and tracked hidden traps,
    // stays message-light, spends 3 mana, and marks spell slot 5 worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_find_hidden_state
    jsr test_setup_hidden_features_map
    jsr player_cast_spell
    bcc !t1_fail+
    lda tfhd_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tfhd_last_spell_idx
    cmp #5
    bne !t1_fail+
    lda tfhd_huff_calls
    bne !t1_fail+
    lda zp_player_mp
    cmp #17
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #17
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$20
    beq !t1_fail+
    lda vis_room_revealed
    cmp #1
    bne !t1_fail+

    ldx #12
    ldy #18
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    bne !t1_fail+
    ldx #12
    ldy #18
    jsr test_read_tile
    and #FLAG_VISITED
    beq !t1_fail+

    ldx #12
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    bne !t1_fail+
    ldx #12
    ldy #22
    jsr test_read_tile
    and #FLAG_VISITED
    beq !t1_fail+
    lda trap_count
    cmp #1
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: no hidden traps or doors is a silent no-effect success that still
    // consumes mana and marks the spell worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_find_hidden_state
    jsr test_setup_empty_detect_map
    jsr player_cast_spell
    bcc !t2_fail+
    lda tfhd_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda tfhd_last_spell_idx
    cmp #5
    bne !t2_fail+
    lda tfhd_huff_calls
    bne !t2_fail+
    lda zp_player_mp
    cmp #17
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #17
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$20
    beq !t2_fail+
    lda vis_room_revealed
    cmp #1
    bne !t2_fail+
    lda trap_count
    bne !t2_fail+
    ldx #12
    ldy #18
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !t2_fail+
    ldx #12
    ldy #19
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, leaves hidden
    // features untouched, and does not mark the spell worked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_find_hidden_state
    jsr test_setup_hidden_features_map
    jsr player_cast_spell
    bcc !t3_fail+
    lda tfhd_spell_exec_calls
    bne !t3_fail+
    lda tfhd_huff_calls
    cmp #1
    bne !t3_fail+
    lda tfhd_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda zp_player_mp
    cmp #17
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #17
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$20
    bne !t3_fail+
    lda vis_room_revealed
    bne !t3_fail+
    ldx #12
    ldy #18
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    bne !t3_fail+
    ldx #12
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !t3_fail+
    lda trap_count
    cmp #1
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // Test 4: armed unfound chest adjacent + 100% search chance discovers
    // the trap: sets CHEST_P1_TRAP_FOUND, prints the discovery message.
!t4:
    lda #(CHEST_P1_TRAP_POISON | CHEST_P1_LOCKED)
    jsr test_setup_search_chest_map
    lda #100
    jsr search_scan_adjacent_silent
    bcc !t4_fail+
    lda fi_p1
    and #CHEST_P1_TRAP_FOUND
    beq !t4_fail+
    lda tfhd_last_huff_id
    cmp #HSTR_CHEST_FOUND_TRAP
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // Test 5: searching the same (now-found) chest again reports the find but
    // emits no message, matching VMS discovery-only behavior.
!t5:
    lda #0
    sta tfhd_huff_calls
    sta tfhd_last_huff_id
    lda #100
    jsr search_scan_adjacent_silent
    bcc !t5_fail+
    lda tfhd_huff_calls
    bne !t5_fail+
    lda fi_p1
    and #CHEST_P1_TRAP_FOUND
    beq !t5_fail+
    lda #$01
    sta tc_results + 4
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results + 4

    // Test 6: zero search chance never discovers: bit 6 stays clear, no
    // message, scan reports nothing found.
!t6:
    lda #(CHEST_P1_TRAP_POISON | CHEST_P1_LOCKED)
    jsr test_setup_search_chest_map
    lda #0
    jsr search_scan_adjacent_silent
    bcs !t6_fail+
    lda fi_p1
    and #CHEST_P1_TRAP_FOUND
    bne !t6_fail+
    lda tfhd_huff_calls
    bne !t6_fail+
    lda #$01
    sta tc_results + 5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 5

    // Test 7: an unarmed chest (locked, no trap bits) reveals nothing even
    // at 100% chance.
!t7:
    lda #CHEST_P1_LOCKED
    jsr test_setup_search_chest_map
    lda #100
    jsr search_scan_adjacent_silent
    bcs !t7_fail+
    lda tfhd_huff_calls
    bne !t7_fail+
    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // Test 8: eff_find_traps marks every armed floor chest found and
    // leaves unarmed chests unchanged.
!t8:
    jsr fill_map_rock
    jsr item_init_floor
    // Slot 0: armed chest
    lda #10
    sta fi_add_x
    sta fi_add_y
    lda #ITEM_SLOT_SMALL_IRON_CHEST
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #(CHEST_P1_TRAP_SUMMON | CHEST_P1_LOCKED)
    sta fi_add_p1
    lda #25
    sta fi_add_to_hit
    lda #0
    sta fi_add_to_dam
    sta fi_add_to_ac
    sta fi_add_flags
    sta fi_add_ego
    jsr floor_item_add
    // Slot 1: unarmed chest
    lda #12
    sta fi_add_x
    sta fi_add_y
    lda #ITEM_SLOT_LARGE_STEEL_CHEST
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #CHEST_P1_LOCKED
    sta fi_add_p1
    lda #50
    sta fi_add_to_hit
    lda #0
    sta fi_add_to_dam
    sta fi_add_to_ac
    sta fi_add_flags
    sta fi_add_ego
    jsr floor_item_add

    jsr eff_find_traps

    lda fi_p1
    and #CHEST_P1_TRAP_FOUND
    beq !t8_fail+
    lda fi_p1 + 1
    and #CHEST_P1_TRAP_FOUND
    bne !t8_fail+
    lda #$01
    sta tc_results + 7
    jmp !t9+
!t8_fail:
    lda #$00
    sta tc_results + 7

    // Test 9: an automatic re-search of a known trapped chest must not replace
    // a full direction-prompt + command-result message pair. VMS has no repeat
    // message, so the scan simply reports the chest as found.
!t9:
    lda #(CHEST_P1_TRAP_POISON | CHEST_P1_TRAP_FOUND | CHEST_P1_LOCKED)
    jsr test_setup_search_chest_map
    lda #MSG_PENDING | MSG_FULL
    sta zp_msg_flags
    lda #100
    jsr search_scan_adjacent_silent
    bcc !t9_fail+
    lda tfhd_huff_calls
    bne !t9_fail+
    lda zp_msg_flags
    cmp #MSG_PENDING | MSG_FULL
    bne !t9_fail+
    lda fi_p1
    and #CHEST_P1_TRAP_FOUND | CHEST_P1_TRAP_POISON
    cmp #CHEST_P1_TRAP_FOUND | CHEST_P1_TRAP_POISON
    bne !t9_fail+
    lda #$01
    sta tc_results + 8
    jmp test_finish
!t9_fail:
    lda #$00
    sta tc_results + 8
    jmp test_finish

// test_setup_search_chest_map — Rock map, player at (20,20), floor tile at
// (21,20), and one chest there via floor_item_add (sets FLAG_HAS_ITEM).
// Input: A = chest p1 (trap state). Result: chest in floor slot 0.
test_setup_search_chest_map:
    sta tscc_p1
    jsr fill_map_rock
    jsr item_init_floor
    lda #20
    sta zp_player_x
    sta player_data + PL_MAP_X
    sta zp_player_y
    sta player_data + PL_MAP_Y
    lda #TILE_FLOOR
    ldx #20
    ldy #21
    jsr test_write_tile
    lda #21
    sta fi_add_x
    lda #20
    sta fi_add_y
    lda #ITEM_SLOT_SMALL_WOODEN_CHEST
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda tscc_p1
    sta fi_add_p1
    lda #7
    sta fi_add_to_hit
    lda #0
    sta fi_add_to_dam
    sta fi_add_to_ac
    sta fi_add_flags
    sta fi_add_ego
    jsr floor_item_add
    lda #0
    sta tfhd_huff_calls
    sta tfhd_last_huff_id
    rts
tscc_p1: .byte 0

test_body_end:
.assert "Test code stays below MAP_BASE (map writes during tests)", test_body_end <= MAP_BASE, true
    jmp test_finish
