// test_word_of_destruction.s — Focused runtime tests for the Word of Destruction spell row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
twd_results: .fill 2, $ff

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
    lda twd_results,x
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

twd_spell_exec_calls: .byte 0
twd_huff_calls: .byte 0
twd_last_huff_id: .byte 0
twd_last_spell_idx: .byte $ff
pmx_work_idx: .byte 0
pmx_work_flag: .byte 0
pmx_work_damage: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx twd_last_huff_id
    inc twd_huff_calls
    rts

eff_remove_fear:
    lda #0
    sta eff_fear_timer
    rts

test_tramp_word_of_destruction_execute:
    inc twd_spell_exec_calls
    lda pm_spell_idx
    sta twd_last_spell_idx
    jsr eff_destroy_area
    rts

test_pm_select_book:
    lda #3
    sta pm_book_idx
    lda #<book_mask_3
    sta pm_book_mask_lo
    lda #>book_mask_3
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #29
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

test_reset_word_of_destruction_state:
    jsr player_init
    lda #0
    sta twd_spell_exec_calls
    sta twd_huff_calls
    sta twd_last_huff_id
    sta vis_room_revealed
    sta trap_count
    sta zp_dirty_count
    lda #$ff
    sta twd_last_spell_idx
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
    lda #23
    sta zp_player_mp
    sta player_data + PL_MANA
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA

    lda #0
    sta player_data + PL_SPELLS_LEARNT_0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    lda #$20
    sta player_data + PL_SPELLS_LEARNT_3
    lda #0
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

test_setup_destruction_map:
    jsr fill_map_rock
    jsr item_init_floor
    jsr monster_init_table
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

    lda #TILE_TRAP
    ldx #13
    ldy #22
    jsr test_write_tile

    lda #1
    sta trap_count
    lda #22
    sta trap_x
    lda #13
    sta trap_y
    lda #0
    sta trap_type

    lda #23
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #10
    jsr monster_spawn_one
    bcc !spawn_fail+
    lda #23
    ldy #12
    jsr monster_find_at
    bcc !spawn_fail+
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #8
    sta (zp_ptr0),y
    iny
    lda #0
    sta (zp_ptr0),y
!spawn_fail:
    rts

test_start:
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_word_of_destruction_execute)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: successful cast reaches spell slot 29, kills an adjacent
    // monster, destroys adjacent trap/door fixtures, sets redraw state, spends
    // 21 mana, and marks worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_word_of_destruction_state
    jsr test_setup_destruction_map
    jsr player_cast_spell
    bcc !t1_fail+
    lda twd_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda twd_last_spell_idx
    cmp #29
    bne !t1_fail+
    lda zp_dirty_count
    cmp #1
    bne !t1_fail+
    lda vis_room_revealed
    cmp #1
    bne !t1_fail+
    lda #23
    ldy #12
    jsr monster_find_at
    bcs !t1_fail+
    ldx #11
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    bne !t1_fail+
    ldx #13
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !t1_fail+
    lda trap_count
    bne !t1_fail+
    lda zp_player_mp
    cmp #2
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #2
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$20
    beq !t1_fail+
    lda #$01
    sta twd_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta twd_results + 0

    // Test 2: cast failure spends mana, prints HSTR_PM_FAIL, does not
    // execute, and leaves the area unchanged and unworked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_word_of_destruction_state
    jsr test_setup_destruction_map
    jsr player_cast_spell
    bcc !t2_fail+
    lda twd_spell_exec_calls
    bne !t2_fail+
    lda twd_huff_calls
    cmp #1
    bne !t2_fail+
    lda twd_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t2_fail+
    lda zp_dirty_count
    bne !t2_fail+
    lda vis_room_revealed
    bne !t2_fail+
    lda #23
    ldy #12
    jsr monster_find_at
    bcc !t2_fail+
    ldx #11
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    bne !t2_fail+
    ldx #13
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    bne !t2_fail+
    lda trap_count
    cmp #1
    bne !t2_fail+
    lda zp_player_mp
    cmp #2
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #2
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$20
    bne !t2_fail+
    lda #$01
    sta twd_results + 1
    jmp test_finish
!t2_fail:
    lda #$00
    sta twd_results + 1
    jmp test_finish
