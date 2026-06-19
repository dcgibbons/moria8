// test_earthquake_prayer.s — Focused runtime tests for the Earthquake prayer row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tep_results: .fill 3, $ff

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
    lda tep_results,x
    sta $0400,x
    dex
    bpl !copy-
    :BankInKernal()
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
#import "../../../../core/player_magic_feedback.s"
#import "../../../../core/player_magic_earthquake.s"
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

tep_spell_exec_calls: .byte 0
tep_huff_calls: .byte 0
tep_last_huff_id: .byte 0
tep_msg_calls: .byte 0
tep_last_msg_lo: .byte 0
tep_last_msg_hi: .byte 0
tep_last_spell_idx: .byte $ff
tep_rng_idx: .byte 0
test_rng_script: .fill 255, 1

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tep_last_huff_id
    inc tep_huff_calls
    rts

test_msg_print:
    inc tep_msg_calls
    lda zp_ptr0
    sta tep_last_msg_lo
    lda zp_ptr0_hi
    sta tep_last_msg_hi
    rts

test_rng_range:
    ldx tep_rng_idx
    lda test_rng_script,x
    inc tep_rng_idx
    rts

test_rng_fill_ones:
    lda #0
    sta tep_rng_idx
    ldx #0
    lda #1
!loop:
    sta test_rng_script,x
    inx
    cpx #255
    bne !loop-
    rts

test_rng_fill_zeroes:
    lda #0
    sta tep_rng_idx
    ldx #0
!loop:
    sta test_rng_script,x
    inx
    cpx #255
    bne !loop-
    rts

test_tramp_earthquake_prayer_execute:
    inc tep_spell_exec_calls
    lda pm_spell_idx
    sta tep_last_spell_idx
    jsr eff_earthquake
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
    lda #21
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #9
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
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

test_fill_map_stairs:
    ldx #0
!row_loop:
    cpx #MAP_ROWS
    bcs !done+
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
    lda #TILE_STAIRS_UP
!col_loop:
    sta (zp_ptr0),y
    iny
    cpy #MAP_COLS
    bcc !col_loop-
    inx
    jmp !row_loop-
!done:
    rts

test_reset_earthquake_prayer_state:
    jsr player_init
    jsr fill_map_rock
    jsr item_init_floor
    jsr monster_init_table

    lda #0
    sta tep_spell_exec_calls
    sta tep_huff_calls
    sta tep_last_huff_id
    sta tep_msg_calls
    sta tep_last_msg_lo
    sta tep_last_msg_hi
    sta vis_room_revealed
    sta turn_scene_dirty
    lda #$ff
    sta tep_last_spell_idx

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
    sta player_data + PL_SPELLS_LEARNT_1
    lda #$20
    sta player_data + PL_SPELLS_LEARNT_2
    lda #0
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3

    lda #28
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #18
    sta zp_player_y
    sta player_data + PL_MAP_Y
    lda #1
    sta zp_player_dlvl
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(msg_print, test_msg_print)
    :PatchJump(rng_range, test_rng_range)
    :PatchJump(test_spell_execute_selected, test_tramp_earthquake_prayer_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: successful prayer reaches slot 21, prints the earthquake cast
    // text, mutates the first scripted wall tile, sets redraw state, spends 9
    // mana, and marks worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_earthquake_prayer_state
    jsr test_rng_fill_zeroes
    jsr test_fill_map_stairs
    lda #TILE_FLOOR | FLAG_OCCUPIED
    ldx #18
    ldy #28
    jsr test_write_tile
    jsr player_pray
    bcc !t1_fail+
    lda tep_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tep_last_spell_idx
    cmp #21
    bne !t1_fail+
    lda tep_msg_calls
    cmp #1
    bne !t1_fail+
    lda tep_last_msg_lo
    cmp #<eq_cast_msg
    bne !t1_fail+
    lda tep_last_msg_hi
    cmp #>eq_cast_msg
    bne !t1_fail+
    lda zp_player_mp
    cmp #11
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #11
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$20
    beq !t1_fail+
    lda #$01
    sta tep_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tep_results + 0

    // Test 2: low-impact pass prints the cast text but leaves terrain and
    // redraw state unchanged when the nearby area contains only inert tiles.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_earthquake_prayer_state
    jsr test_rng_fill_ones
    jsr test_fill_map_stairs
    lda #TILE_FLOOR | FLAG_OCCUPIED
    ldx #18
    ldy #28
    jsr test_write_tile
    jsr player_pray
    bcc !t2_fail+
    lda tep_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda tep_last_spell_idx
    cmp #21
    bne !t2_fail+
    lda tep_msg_calls
    cmp #1
    bne !t2_fail+
    lda tep_last_msg_lo
    cmp #<eq_cast_msg
    bne !t2_fail+
    lda tep_last_msg_hi
    cmp #>eq_cast_msg
    bne !t2_fail+
    lda vis_room_revealed
    bne !t2_fail+
    lda turn_scene_dirty
    bne !t2_fail+
    ldx #12
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_STAIRS_UP
    bne !t2_fail+
    lda zp_player_mp
    cmp #11
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #11
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$20
    beq !t2_fail+
    lda #$01
    sta tep_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tep_results + 1

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves terrain/reveal state unchanged and unworked.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_earthquake_prayer_state
    jsr test_rng_fill_ones
    jsr player_pray
    bcc !t3_fail+
    lda tep_spell_exec_calls
    bne !t3_fail+
    lda tep_huff_calls
    cmp #1
    bne !t3_fail+
    lda tep_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda tep_msg_calls
    bne !t3_fail+
    lda vis_room_revealed
    bne !t3_fail+
    lda turn_scene_dirty
    bne !t3_fail+
    ldx #10
    ldy #20
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_WALL_H
    bne !t3_fail+
    lda zp_player_mp
    cmp #11
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #11
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_2
    and #$20
    bne !t3_fail+
    lda #$01
    sta tep_results + 2
    jmp test_finish
!t3_fail:
    lda #$00
    sta tep_results + 2
    jmp test_finish
