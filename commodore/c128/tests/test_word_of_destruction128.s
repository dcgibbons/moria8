#importonce
// test_word_of_destruction128.s — Focused C128 coverage for the Word of Destruction row

.const KEY_ESC = $ae
.const SFX_HIT = $01
.const SFX_PICKUP = $03
.const SFX_SPELL = $06
.const SFX_SPELL_FAIL = $07
.const VIEWPORT_X = 1
.const VIEWPORT_Y = 2
.const VIEWPORT_W = 78
.const VIEWPORT_H = 19
.const MONSTER_ENTRY_SIZE = 12
.const MX_X = 0
.const MX_Y = 1
.const MX_HP_LO = 3
.const MX_HP_HI = 4
.const MX_CONFUSE = 9
.const MX_SLEEP_CUR = 7
.const MX_TYPE = 2
.const MAX_MONSTERS = 32
.const EMPTY_SLOT = $ff
.const CF_UNDEAD = $02
.const CF_EVIL = $04
.const PIW_FILTER_PRAYER_BOOK = $fb
.const PIW_FILTER_MAGE_BOOK = $fc

.const PL_CLASS = 18
.const PL_LEVEL = 19
.const PL_INT_CUR = 28
.const PL_CON_CUR = 31
.const PL_HP_LO = 33
.const PL_HP_HI = 34
.const PL_MANA = 37
.const PL_MAX_MANA = 38
.const PL_SPELL_TYPE = 60
.const PL_SPELLS_LEARNT_0 = 61
.const PL_SPELLS_LEARNT_1 = 62
.const PL_SPELLS_LEARNT_2 = 63
.const PL_SPELLS_LEARNT_3 = 64
.const PL_SPELLS_WORKED_0 = 65
.const PL_SPELLS_WORKED_1 = 66
.const PL_SPELLS_WORKED_2 = 67
.const PL_SPELLS_WORKED_3 = 68
.const PL_STRUCT_SIZE = 111

player_data:
    .fill PL_STRUCT_SIZE, 0

itn_17:
    .text "Cure Light Wounds" ; .byte 0
itn_30:
    .text "Detect Monsters" ; .byte 0

#import "../../common/huffman_data.s"
#import "../../common/input_contract.s"
#import "../../common/zeropage.s"
#import "test_helpers128.s"
#import "../memory128.s"
#import "../config128.s"
#import "../../common/color.s"
#import "../../common/item_defs.s"
#import "../../common/rng.s"
#import "../../common/math.s"
#import "../../common/tables.s"
#import "../../common/dungeon_data.s"
#import "../../common/spell_data.s"
#import "../../common/spell_names.s"
#import "../../common/player_magic_state.s"
#import "../../common/player_magic_state_ops.s"
#import "../../common/projectile.s"
#import "../../common/spell_effects.s"
#import "../../common/player_magic.s"
#import "../../common/player_magic_utility.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $5000 "Test Code"

msg_row1_col: .byte 0
cmb_slot: .byte 0
cmb_type: .byte 0
cmb_buf_idx: .byte 0
df_target_x: .byte 0
df_target_y: .byte 0
piw_filter: .byte 0
id_known: .fill 64, 0
inv_item_id: .fill 30, 0
inv_flags: .fill 30, 0
it_name_lo: .fill 64, 0
it_name_hi: .fill 64, 0
cmb_period:
    .text "." ; .byte 0
cmb_kill_str:
    .text "have slain" ; .byte 0
trap_count: .byte 0
trap_x: .fill 16, 0
trap_y: .fill 16, 0
trap_type: .fill 16, 0
cr_mflags: .fill 65, 0
fi_add_x: .byte 0
fi_add_y: .byte 0
fi_add_id: .byte 0
fi_add_qty: .byte 0

test_huff_calls: .byte 0
test_last_huff: .byte 0
test_spell_exec_calls: .byte 0
test_last_spell_idx: .byte $ff
pmx_work_idx: .byte 0
pmx_work_flag: .byte 0
pmx_work_damage: .byte 0
test_progress: .byte 0
vis_room_revealed: .byte 0
eff_fear_timer: .byte 0

test_mon_table:
    .fill MAX_MONSTERS * MONSTER_ENTRY_SIZE, 0

test_mon_ptr_lo:
    .fill MAX_MONSTERS, <(test_mon_table + i * MONSTER_ENTRY_SIZE)
test_mon_ptr_hi:
    .fill MAX_MONSTERS, >(test_mon_table + i * MONSTER_ENTRY_SIZE)

walkable_table:
    .byte 1, 0, 0, 0, 0, 0, 0, 1
    .byte 0, 1, 1, 1, 0, 0, 1, 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

screen_clear:
ui_help_clear_all:
viewport_update:
render_viewport:
status_draw:
msg_clear:
msg_print:
input_wait_release:
input_get_key:
input_get_key_fast:
show_inv_and_select:
tramp_spell_list_display:
monster_wake:
monster_apply_sleep:
projectile_msg_suffix:
player_calc_hp:
light_room_x:
player_search_mode_off:
huff_append_combat:
combat_append_str:
cmb_term_and_print:
tunnel_spawn_gold:
combat_award_xp:
combat_check_levelup:
find_random_floor:
sound_play:
piw_prompt_filtered_inv:
piw_pick_filtered_inv_key:
piw_print_prompt_with_count:
screen_flash_set_color:
screen_flash_reset_color:
screen_flash_at:
combat_msg_monster_shudders:
combat_msg_monster_dissolves:
los_is_visible:
    clc
    rts

floor_item_find_at:
    clc
    rts

floor_item_remove:
    rts

fi_add_clear_plain_meta:
    rts

floor_item_add:
    sec
    rts

glyph_add_at:
    sec
    rts

msg_build_action:
    rts

cmb_print_buf:
    rts

player_calc_stats:
    rts

player_sync_to_zp:
    rts

calc_spell_failure:
    clc
    rts

tramp_spell_execute_selected:
    rts

monster_get_ptr:
    lda test_mon_ptr_lo,x
    sta zp_ptr0
    lda test_mon_ptr_hi,x
    sta zp_ptr0_hi
    rts

monster_find_at:
    stx zp_temp0
    sty zp_temp1
    ldx #0
!mfa_loop:
    cpx #MAX_MONSTERS
    bcs !mfa_none+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !mfa_next+
    ldy #MX_X
    lda (zp_ptr0),y
    cmp zp_temp0
    bne !mfa_next+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp zp_temp1
    bne !mfa_next+
    sec
    rts
!mfa_next:
    inx
    jmp !mfa_loop-
!mfa_none:
    clc
    rts

monster_remove:
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #EMPTY_SLOT
    sta (zp_ptr0),y
    rts

combat_apply_damage_16:
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sec
    sbc zp_math_a
    sta zp_temp0
    iny
    lda (zp_ptr0),y
    sbc zp_math_b
    bcc !cad_kill+
    pha
    ldy #MX_HP_LO
    lda zp_temp0
    sta (zp_ptr0),y
    iny
    pla
    sta (zp_ptr0),y
    clc
    rts
!cad_kill:
    ldy #MX_HP_LO
    lda #0
    sta (zp_ptr0),y
    iny
    sta (zp_ptr0),y
    sec
    rts

get_direction_target:
    lda zp_player_x
    clc
    adc #1
    sta df_target_x
    lda zp_player_y
    sta df_target_y
    sec
    rts

huff_print_msg:
    stx test_last_huff
    inc test_huff_calls
    rts

eff_remove_fear:
    lda #0
    sta eff_fear_timer
    rts

combat_kill_message:
    jsr monster_remove
    inc zp_dirty_count
    rts

test_tramp_spell_execute_selected:
    inc test_spell_exec_calls
    lda pm_spell_idx
    sta test_last_spell_idx
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

fill_map_rock_test:
    ldx #0
!row_loop:
    cpx #MAP_ROWS
    bcs !done+
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #0
    lda #TILE_WALL_H
!col_loop:
    sta (zp_ptr0),y
    iny
    cpy #MAP_COLS
    bcc !col_loop-
    inx
    jmp !row_loop-
!done:
    rts

test_clear_monsters:
    ldx #MAX_MONSTERS * MONSTER_ENTRY_SIZE - 1
    lda #0
!clear_loop:
    sta test_mon_table,x
    dex
    bpl !clear_loop-
    ldx #0
!mark_empty:
    cpx #MAX_MONSTERS
    bcs !done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #EMPTY_SLOT
    sta (zp_ptr0),y
    inx
    jmp !mark_empty-
!done:
    rts

test_place_target_monster:
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #10
    sta (zp_ptr0),y
    iny
    lda #23
    sta (zp_ptr0),y
    iny
    lda #12
    sta (zp_ptr0),y
    iny
    lda #8
    sta (zp_ptr0),y
    iny
    lda #0
    sta (zp_ptr0),y
    rts

test_reset_word_of_destruction_state:
    lda #0
    sta test_huff_calls
    sta test_last_huff
    sta test_spell_exec_calls
    sta vis_room_revealed
    sta trap_count
    sta zp_dirty_count
    lda #$ff
    sta test_last_spell_idx

    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    sta player_data + PL_CON_CUR
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
    lda #12
    sta zp_player_y
    rts

test_setup_destruction_map:
    jsr fill_map_rock_test
    jsr test_clear_monsters
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

    jsr test_place_target_monster
    rts

test_fail:
    jmp test_fail_loop

test_pass:
    jmp test_pass_loop

test_start:
    sei
    cld
    ldx #$ff
    txs

    lda #MMU_ALL_RAM
    sta $ff00
    lda #0
    sta test_progress

    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(tramp_spell_execute_selected, test_tramp_spell_execute_selected)

    // Test 1: successful cast reaches spell slot 29, kills an adjacent
    // monster, destroys adjacent trap/door fixtures, sets redraw state, spends
    // 21 mana, and marks worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_word_of_destruction_state
    jsr test_setup_destruction_map
    jsr player_cast_spell
    bcc !t1_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda test_last_spell_idx
    cmp #29
    bne !t1_fail+
    lda zp_dirty_count
    cmp #1
    bne !t1_fail+
    lda vis_room_revealed
    cmp #1
    bne !t1_fail+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !t1_fail+
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
    lda #1
    sta test_progress
    jmp test_after_success
!t1_fail:
    jmp test_fail

    // Test 2: cast failure spends mana, prints HSTR_PM_FAIL, does not
    // execute, and leaves the area unchanged and unworked.
test_after_success:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_word_of_destruction_state
    jsr test_setup_destruction_map
    jsr player_cast_spell
    bcc !t2_fail+
    lda test_spell_exec_calls
    bne !t2_fail+
    lda test_huff_calls
    cmp #1
    bne !t2_fail+
    lda test_last_huff
    cmp #HSTR_PM_FAIL
    bne !t2_fail+
    lda zp_dirty_count
    bne !t2_fail+
    lda vis_room_revealed
    bne !t2_fail+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #10
    bne !t2_fail+
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
    lda #2
    sta test_progress
    jmp test_pass
!t2_fail:
    jmp test_fail

test_fail_loop:
    jmp test_fail_loop

test_pass_loop:
    jmp test_pass_loop
