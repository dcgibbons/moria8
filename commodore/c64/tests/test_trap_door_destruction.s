// test_trap_door_destruction.s — Focused runtime tests for the Trap/Door Destruction spell row

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

ttdd_spell_exec_calls: .byte 0
ttdd_huff_calls: .byte 0
ttdd_last_huff_id: .byte 0
ttdd_last_spell_idx: .byte $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx ttdd_last_huff_id
    inc ttdd_huff_calls
    rts

test_tramp_trap_door_destruction_execute:
    inc ttdd_spell_exec_calls
    lda pm_spell_idx
    sta ttdd_last_spell_idx
    jsr eff_destroy_traps_doors
    rts

test_pm_select_book:
    lda #1
    sta pm_book_idx
    lda #<book_mask_1
    sta pm_book_mask_lo
    lda #>book_mask_1
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #9
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

test_reset_trap_door_destruction_state:
    jsr player_init
    lda #0
    sta ttdd_spell_exec_calls
    sta ttdd_huff_calls
    sta ttdd_last_huff_id
    sta vis_room_revealed
    lda #$ff
    sta ttdd_last_spell_idx
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

    lda #22
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #12
    sta zp_player_y
    sta player_data + PL_MAP_Y
    lda #1
    sta zp_player_dlvl
    lda #0
    sta trap_count
    rts

test_setup_adjacent_destruction_map:
    jsr fill_map_rock
    lda #0
    sta vis_room_revealed

    lda #TILE_FLOOR
    ldx #11
!rows:
    cpx #14
    bcs !room_done+
    ldy #21
!cols:
    jsr test_write_tile
    iny
    cpy #24
    bcc !cols-
    inx
    jmp !rows-
!room_done:

    lda #TILE_SECRET
    ldx #11
    ldy #22
    jsr test_write_tile

    lda #TILE_DOOR_CLOSED
    ldx #12
    ldy #23
    jsr test_write_tile

    lda #TILE_TRAP
    ldx #13
    ldy #22
    jsr test_write_tile

    lda #2
    sta trap_count
    lda #22
    sta trap_x
    lda #13
    sta trap_y
    lda #0
    sta trap_type
    lda #30
    sta trap_x + 1
    lda #13
    sta trap_y + 1
    lda #1
    sta trap_type + 1
    rts

test_setup_no_effect_map:
    jsr fill_map_rock
    lda #0
    sta vis_room_revealed

    lda #TILE_FLOOR
    ldx #11
!rows:
    cpx #14
    bcs !room_done+
    ldy #21
!cols:
    jsr test_write_tile
    iny
    cpy #24
    bcc !cols-
    inx
    jmp !rows-
!room_done:

    lda #TILE_DOOR_OPEN
    ldx #11
    ldy #22
    jsr test_write_tile

    lda #TILE_FLOOR
    ldx #13
    ldy #22
    jsr test_write_tile

    lda #TILE_DOOR_CLOSED
    ldx #12
    ldy #30
    jsr test_write_tile

    lda #1
    sta trap_count
    lda #30
    sta trap_x
    lda #13
    sta trap_y
    lda #0
    sta trap_type
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_trap_door_destruction_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: successful cast opens adjacent secret/closed doors, removes the
    // adjacent trap from map+table, stays message-light, spends 5 mana, and
    // marks spell slot 9 worked in byte 1.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_trap_door_destruction_state
    jsr test_setup_adjacent_destruction_map
    jsr player_cast_spell
    bcs !t1_ok0+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok0:
    lda ttdd_spell_exec_calls
    cmp #1
    beq !t1_ok1+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok1:
    lda ttdd_last_spell_idx
    cmp #9
    beq !t1_ok2+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok2:
    lda ttdd_huff_calls
    beq !t1_ok3+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok3:
    lda zp_player_mp
    cmp #15
    beq !t1_ok4+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok4:
    lda player_data + PL_MANA
    cmp #15
    beq !t1_ok5+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok5:
    lda player_data + PL_SPELLS_WORKED_1
    and #$02
    bne !t1_ok6+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok6:
    lda vis_room_revealed
    cmp #1
    beq !t1_ok7+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok7:

    ldx #11
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !t1_ok8+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok8:
    ldx #11
    ldy #22
    jsr test_read_tile
    and #FLAG_VISITED
    bne !t1_ok9+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok9:

    ldx #12
    ldy #23
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !t1_ok10+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok10:
    ldx #12
    ldy #23
    jsr test_read_tile
    and #FLAG_VISITED
    bne !t1_ok11+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok11:

    ldx #13
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !t1_ok12+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok12:
    lda trap_count
    cmp #1
    beq !t1_ok13+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok13:
    lda trap_x
    cmp #30
    beq !t1_ok14+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok14:
    lda trap_y
    cmp #13
    beq !t1_ok15+
    lda #$00
    sta tc_results + 0
    jmp !t2+
!t1_ok15:
    lda #$01
    sta tc_results + 0
    jmp !t2+

    // Test 2: no adjacent eligible traps/doors is a silent no-effect success
    // that still consumes mana and marks the spell worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_trap_door_destruction_state
    jsr test_setup_no_effect_map
    jsr player_cast_spell
    bcs !t2_ok0+
    lda #$00
    sta tc_results + 1
    jmp !t3+
!t2_ok0:
    lda ttdd_spell_exec_calls
    cmp #1
    beq !t2_ok1+
    lda #$00
    sta tc_results + 1
    jmp !t3+
!t2_ok1:
    lda ttdd_last_spell_idx
    cmp #9
    beq !t2_ok2+
    lda #$00
    sta tc_results + 1
    jmp !t3+
!t2_ok2:
    lda ttdd_huff_calls
    beq !t2_ok3+
    lda #$00
    sta tc_results + 1
    jmp !t3+
!t2_ok3:
    lda zp_player_mp
    cmp #15
    beq !t2_ok4+
    lda #$00
    sta tc_results + 1
    jmp !t3+
!t2_ok4:
    lda player_data + PL_MANA
    cmp #15
    beq !t2_ok5+
    lda #$00
    sta tc_results + 1
    jmp !t3+
!t2_ok5:
    lda player_data + PL_SPELLS_WORKED_1
    and #$02
    bne !t2_ok6+
    lda #$00
    sta tc_results + 1
    jmp !t3+
!t2_ok6:
    lda vis_room_revealed
    cmp #1
    beq !t2_ok7+
    lda #$00
    sta tc_results + 1
    jmp !t3+
!t2_ok7:
    lda trap_count
    cmp #1
    beq !t2_ok8+
    lda #$00
    sta tc_results + 1
    jmp !t3+
!t2_ok8:
    lda trap_x
    cmp #30
    beq !t2_ok9+
    lda #$00
    sta tc_results + 1
    jmp !t3+
!t2_ok9:
    lda trap_y
    cmp #13
    beq !t2_ok10+
    lda #$00
    sta tc_results + 1
    jmp !t3+
!t2_ok10:
    ldx #11
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !t2_ok11+
    lda #$00
    sta tc_results + 1
    jmp !t3+
!t2_ok11:
    ldx #12
    ldy #30
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    beq !t2_ok12+
    lda #$00
    sta tc_results + 1
    jmp !t3+
!t2_ok12:
    lda #$01
    sta tc_results + 1
    jmp !t3+

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, leaves adjacent
    // traps/doors untouched, and does not mark the spell worked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_trap_door_destruction_state
    jsr test_setup_adjacent_destruction_map
    jsr player_cast_spell
    bcs !t3_ok0+
    lda #$00
    sta tc_results + 2
    jmp test_finish
!t3_ok0:
    lda ttdd_spell_exec_calls
    beq !t3_ok1+
    lda #$00
    sta tc_results + 2
    jmp test_finish
!t3_ok1:
    lda ttdd_huff_calls
    cmp #1
    beq !t3_ok2+
    lda #$00
    sta tc_results + 2
    jmp test_finish
!t3_ok2:
    lda ttdd_last_huff_id
    cmp #HSTR_PM_FAIL
    beq !t3_ok3+
    lda #$00
    sta tc_results + 2
    jmp test_finish
!t3_ok3:
    lda zp_player_mp
    cmp #15
    beq !t3_ok4+
    lda #$00
    sta tc_results + 2
    jmp test_finish
!t3_ok4:
    lda player_data + PL_MANA
    cmp #15
    beq !t3_ok5+
    lda #$00
    sta tc_results + 2
    jmp test_finish
!t3_ok5:
    lda player_data + PL_SPELLS_WORKED_1
    and #$02
    beq !t3_ok6+
    lda #$00
    sta tc_results + 2
    jmp test_finish
!t3_ok6:
    lda vis_room_revealed
    beq !t3_ok7+
    lda #$00
    sta tc_results + 2
    jmp test_finish
!t3_ok7:
    ldx #11
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    beq !t3_ok8+
    lda #$00
    sta tc_results + 2
    jmp test_finish
!t3_ok8:
    ldx #12
    ldy #23
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    beq !t3_ok9+
    lda #$00
    sta tc_results + 2
    jmp test_finish
!t3_ok9:
    ldx #13
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    beq !t3_ok10+
    lda #$00
    sta tc_results + 2
    jmp test_finish
!t3_ok10:
    lda trap_count
    cmp #2
    beq !t3_ok11+
    lda #$00
    sta tc_results + 2
    jmp test_finish
!t3_ok11:
    lda #$01
    sta tc_results + 2
    jmp test_finish
