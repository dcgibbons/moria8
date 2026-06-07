// test_detect_doors_stairs_prayer.s — Focused runtime tests for the Detect Doors/Stairs prayer row

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
#import "../../common/item_actions_overlay.s"
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

tddsp_spell_exec_calls: .byte 0
tddsp_huff_calls: .byte 0
tddsp_last_huff_id: .byte 0
tddsp_last_spell_idx: .byte $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tddsp_last_huff_id
    inc tddsp_huff_calls
    rts

test_tramp_detect_doors_stairs_prayer_execute:
    inc tddsp_spell_exec_calls
    lda pm_spell_idx
    sta tddsp_last_spell_idx
    jsr eff_find_doors
    jsr test_eff_find_stairs
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
    lda #6
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

test_mark_stairs_at:
    sta zp_ptr1
    sty zp_ptr1_hi
    cpy #MAP_ROWS
    bcs !done+
    lda zp_ptr1
    cmp #MAP_COLS
    bcs !done+
    ldx zp_ptr1_hi
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy zp_ptr1
    :MapRead_ptr0_y()
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_DN
    beq !mark+
    cmp #TILE_STAIRS_UP
    bne !done+
!mark:
    :MapRead_ptr0_y()
    ora #FLAG_VISITED
    :MapWrite_ptr0_y()
!done:
    rts

test_eff_find_stairs:
    lda stairs_up_x
    ldy stairs_up_y
    jsr test_mark_stairs_at
    lda stairs_dn1_x
    ldy stairs_dn1_y
    jsr test_mark_stairs_at
    lda stairs_dn2_x
    ldy stairs_dn2_y
    jsr test_mark_stairs_at
    lda #1
    sta vis_room_revealed
    rts

test_reset_detect_doors_stairs_state:
    jsr player_init
    lda #0
    sta tddsp_spell_exec_calls
    sta tddsp_huff_calls
    sta tddsp_last_huff_id
    sta vis_room_revealed
    lda #$ff
    sta tddsp_last_spell_idx
    sta vis_cached_room_idx

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

    lda #$40
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3

    lda #$ff
    sta stairs_up_x
    sta stairs_up_y
    sta stairs_dn1_x
    sta stairs_dn1_y
    sta stairs_dn2_x
    sta stairs_dn2_y
    rts

test_setup_hidden_door_stairs_map:
    jsr fill_map_rock
    lda #0
    sta vis_room_revealed

    lda #TILE_SECRET
    ldx #12
    ldy #18
    jsr test_write_tile

    lda #TILE_STAIRS_UP
    ldx #12
    ldy #22
    jsr test_write_tile
    lda #22
    sta stairs_up_x
    lda #12
    sta stairs_up_y
    rts

test_setup_empty_detect_map:
    jsr fill_map_rock
    lda #0
    sta vis_room_revealed

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
    :PatchJump(test_spell_execute_selected, test_tramp_detect_doors_stairs_prayer_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: successful prayer reveals secret doors and tracked stairs,
    // stays message-light, spends 3 mana, and marks prayer slot 6 worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_detect_doors_stairs_state
    jsr test_setup_hidden_door_stairs_map
    jsr player_pray
    bcc !t1_fail+
    lda tddsp_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tddsp_last_spell_idx
    cmp #6
    bne !t1_fail+
    lda tddsp_huff_calls
    bne !t1_fail+
    lda zp_player_mp
    cmp #17
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #17
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$40
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
    and #FLAG_VISITED
    beq !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: no eligible doors or stairs is a silent no-effect success that
    // still consumes mana and marks the prayer worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_detect_doors_stairs_state
    jsr test_setup_empty_detect_map
    jsr player_pray
    bcc !t2_fail+
    lda tddsp_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda tddsp_last_spell_idx
    cmp #6
    bne !t2_fail+
    lda tddsp_huff_calls
    bne !t2_fail+
    lda zp_player_mp
    cmp #17
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #17
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$40
    beq !t2_fail+
    lda vis_room_revealed
    cmp #1
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

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, leaves doors and
    // stairs untouched, and does not mark the prayer worked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_detect_doors_stairs_state
    jsr test_setup_hidden_door_stairs_map
    jsr player_pray
    bcc !t3_fail+
    lda tddsp_spell_exec_calls
    bne !t3_fail+
    lda tddsp_huff_calls
    cmp #1
    bne !t3_fail+
    lda tddsp_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda zp_player_mp
    cmp #17
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #17
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$40
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
    and #FLAG_VISITED
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta tc_results + 2
    jmp test_finish
