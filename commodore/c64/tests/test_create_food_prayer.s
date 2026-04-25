// test_create_food_prayer.s — Focused runtime tests for the Create Food prayer row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tcf_results: .fill 3, $ff

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
    lda tcf_results,x
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

tcf_spell_exec_calls: .byte 0
tcf_huff_calls: .byte 0
tcf_last_huff_id: .byte 0
tcf_last_spell_idx: .byte $ff

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tcf_last_huff_id
    inc tcf_huff_calls
    rts

test_pmu_create_food:
    lda zp_player_x
    ldy zp_player_y
    jsr floor_item_find_at
    bcc !free+
    jsr floor_item_remove
!free:
    lda zp_player_x
    sta fi_add_x
    lda zp_player_y
    sta fi_add_y
    lda #15
    sta fi_add_id
    lda #0
    sta fi_add_qty_hi
    sta fi_add_p1
    sta fi_add_flags
    sta fi_add_ego
    lda #1
    sta fi_add_qty
    jsr floor_item_add
    bcc !fail+
    lda #1
    sta vis_room_revealed
    ldx #HSTR_PMU_CREATE_FOOD
    jsr huff_print_msg
    sec
    rts
!fail:
    clc
    rts

test_tramp_create_food_execute:
    inc tcf_spell_exec_calls
    lda pm_spell_idx
    sta tcf_last_spell_idx
    jsr test_pmu_create_food
    bcs !ok+
    ldx #HSTR_PMU_GLYPH_BLOCK
    jsr huff_print_msg
!ok:
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

test_pm_prompt_visible_spell_choice:
    lda #13
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

test_reset_create_food_state:
    jsr item_init_floor
    jsr player_init
    lda #0
    sta tcf_spell_exec_calls
    sta tcf_huff_calls
    sta tcf_last_huff_id
    sta vis_room_revealed
    lda #$ff
    sta tcf_last_spell_idx
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

    lda #0
    sta player_data + PL_SPELLS_LEARNT_0
    lda #$20
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
    rts

test_setup_open_floor:
    jsr fill_map_rock
    lda #0
    sta vis_room_revealed
    lda #TILE_FLOOR
    ldx #11
!rows:
    cpx #14
    bcs !done+
    ldy #21
!cols:
    jsr test_write_tile
    iny
    cpy #24
    bcc !cols-
    inx
    jmp !rows-
!done:
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

test_seed_underfoot_item:
    lda zp_player_x
    sta fi_add_x
    lda zp_player_y
    sta fi_add_y
    lda #17
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_qty_hi
    sta fi_add_p1
    sta fi_add_flags
    sta fi_add_ego
    jsr floor_item_add
    rts

test_fill_floor_items_elsewhere:
    ldx #0
!loop:
    cpx #MAX_FLOOR_ITEMS
    bcs !done+
    txa
    clc
    adc #1
    sta fi_item_id,x
    lda #1
    sta fi_qty,x
    lda #1
    sta fi_x,x
    txa
    clc
    adc #1
    sta fi_y,x
    inx
    jmp !loop-
!done:
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_create_food_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: successful prayer reaches slot 13, replaces any item under
    // the player with a ration, prints CREATE_FOOD, spends 5 mana, and marks
    // the prayer worked in byte 1.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_create_food_state
    jsr test_setup_open_floor
    jsr test_seed_underfoot_item
    bcc !t1_fail+
    jsr player_pray
    bcc !t1_fail+
    lda tcf_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tcf_last_spell_idx
    cmp #13
    bne !t1_fail+
    lda tcf_huff_calls
    cmp #1
    bne !t1_fail+
    lda tcf_last_huff_id
    cmp #HSTR_PMU_CREATE_FOOD
    bne !t1_fail+
    lda zp_player_x
    ldy zp_player_y
    jsr floor_item_find_at
    bcc !t1_fail+
    lda fi_item_id,x
    cmp #15
    bne !t1_fail+
    lda vis_room_revealed
    cmp #1
    bne !t1_fail+
    lda zp_player_mp
    cmp #15
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #15
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$20
    beq !t1_fail+
    lda #$01
    sta tcf_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tcf_results + 0

    // Test 2: with no free floor-item slot, prayer stays explicit on failure,
    // leaves no ration underfoot, still spends mana, and marks the prayer
    // worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_create_food_state
    jsr test_setup_open_floor
    jsr test_fill_floor_items_elsewhere
    jsr player_pray
    bcc !t2_fail+
    lda tcf_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda tcf_last_spell_idx
    cmp #13
    bne !t2_fail+
    lda tcf_huff_calls
    cmp #1
    bne !t2_fail+
    lda tcf_last_huff_id
    cmp #HSTR_PMU_GLYPH_BLOCK
    bne !t2_fail+
    lda zp_player_x
    ldy zp_player_y
    jsr floor_item_find_at
    bcs !t2_fail+
    lda vis_room_revealed
    bne !t2_fail+
    lda zp_player_mp
    cmp #15
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #15
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$20
    beq !t2_fail+
    lda #$01
    sta tcf_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tcf_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Create Food unworked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_create_food_state
    jsr test_setup_open_floor
    jsr player_pray
    bcc !t3_fail+
    lda tcf_spell_exec_calls
    bne !t3_fail+
    lda tcf_huff_calls
    cmp #1
    bne !t3_fail+
    lda tcf_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda zp_player_x
    ldy zp_player_y
    jsr floor_item_find_at
    bcs !t3_fail+
    lda zp_player_mp
    cmp #15
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #15
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_1
    and #$20
    bne !t3_fail+
    lda #$01
    sta tcf_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta tcf_results + 2
    jmp test_finish
