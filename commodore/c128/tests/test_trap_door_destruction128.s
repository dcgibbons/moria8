#importonce
// test_trap_door_destruction128.s — Focused C128 coverage for the Trap/Door Destruction row

.const KEY_ESC = $ae
.const SFX_HIT = $01
.const SFX_PICKUP = $03
.const SFX_SPELL = $06
.const SFX_SPELL_FAIL = $07
.const VIEWPORT_X = 1
.const VIEWPORT_Y = 2
.const VIEWPORT_W = 78
.const VIEWPORT_H = 19
.const MX_CONFUSE = 9
.const MX_SLEEP_CUR = 7
.const MX_TYPE = 2
.const MAX_MONSTERS = 32
.const EMPTY_SLOT = $ff
.const CF_UNDEAD = $02
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
trap_count: .byte 0
trap_x: .fill 16, 0
trap_y: .fill 16, 0
trap_type: .fill 16, 0
cr_mflags: .fill 65, 0

test_huff_calls: .byte 0
test_last_huff: .byte 0
test_spell_exec_calls: .byte 0
test_last_spell_idx: .byte $ff
test_progress: .byte 0
vis_room_revealed: .byte 0

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
.label hal_screen_clear = screen_clear
ui_help_clear_all:
viewport_update:
render_viewport:
status_draw:
msg_clear:
msg_print:
input_wait_release:
.label hal_input_wait_release = input_wait_release
.label hal_input_modal_prepare = input_wait_release
input_get_key:
.label hal_input_get_key = input_get_key
.label hal_input_get_text_char = input_get_key
input_get_key_fast:
show_inv_and_select:
tramp_spell_list_display:
monster_get_ptr:
combat_kill_message:
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
monster_remove:
combat_award_xp:
combat_check_levelup:
find_random_floor:
monster_find_at:
combat_apply_damage_16:
hal_sound_play:
piw_prompt_filtered_inv:
piw_pick_filtered_inv_key:
piw_print_prompt_with_count:
screen_flash_set_color:
screen_flash_reset_color:
screen_flash_at:
    clc
    rts

calc_spell_failure:
    clc
    rts

tramp_spell_execute_selected:
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

test_tramp_spell_execute_selected:
    inc test_spell_exec_calls
    lda pm_spell_idx
    sta test_last_spell_idx
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

test_reset_trap_door_destruction_state:
    lda #0
    sta test_huff_calls
    sta test_last_huff
    sta test_spell_exec_calls
    sta vis_room_revealed
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
    lda #12
    sta zp_player_y
    lda #0
    sta trap_count
    rts

test_setup_adjacent_destruction_map:
    jsr fill_map_rock_test
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
    jsr fill_map_rock_test
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

    // Test 1: successful cast opens adjacent secret/closed doors, removes the
    // adjacent trap from map+table, stays message-light, spends 5 mana, and
    // marks spell slot 9 worked in byte 1.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_trap_door_destruction_state
    jsr test_setup_adjacent_destruction_map
    jsr player_cast_spell
    bcs !t1_ok0+
    jmp test_fail
!t1_ok0:
    lda test_spell_exec_calls
    cmp #1
    beq !t1_ok1+
    jmp test_fail
!t1_ok1:
    lda test_last_spell_idx
    cmp #9
    beq !t1_ok2+
    jmp test_fail
!t1_ok2:
    lda test_huff_calls
    beq !t1_ok3+
    jmp test_fail
!t1_ok3:
    lda zp_player_mp
    cmp #15
    beq !t1_ok4+
    jmp test_fail
!t1_ok4:
    lda player_data + PL_MANA
    cmp #15
    beq !t1_ok5+
    jmp test_fail
!t1_ok5:
    lda player_data + PL_SPELLS_WORKED_1
    and #$02
    bne !t1_ok6+
    jmp test_fail
!t1_ok6:
    lda vis_room_revealed
    cmp #1
    beq !t1_ok7+
    jmp test_fail
!t1_ok7:
    ldx #11
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !t1_ok8+
    jmp test_fail
!t1_ok8:
    ldx #11
    ldy #22
    jsr test_read_tile
    and #FLAG_VISITED
    bne !t1_ok9+
    jmp test_fail
!t1_ok9:
    ldx #12
    ldy #23
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !t1_ok10+
    jmp test_fail
!t1_ok10:
    ldx #12
    ldy #23
    jsr test_read_tile
    and #FLAG_VISITED
    bne !t1_ok11+
    jmp test_fail
!t1_ok11:
    ldx #13
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    beq !t1_ok12+
    jmp test_fail
!t1_ok12:
    lda trap_count
    cmp #1
    beq !t1_ok13+
    jmp test_fail
!t1_ok13:
    lda trap_x
    cmp #30
    beq !t1_ok14+
    jmp test_fail
!t1_ok14:
    lda trap_y
    cmp #13
    beq !t1_ok15+
    jmp test_fail
!t1_ok15:
    lda #1
    sta test_progress
    jmp test_after_success

    // Test 2: no adjacent eligible traps/doors is a silent no-effect success
    // that still consumes mana and marks the spell worked.
test_after_success:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_trap_door_destruction_state
    jsr test_setup_no_effect_map
    jsr player_cast_spell
    bcs !t2_ok0+
    jmp test_fail
!t2_ok0:
    lda test_spell_exec_calls
    cmp #1
    beq !t2_ok1+
    jmp test_fail
!t2_ok1:
    lda test_last_spell_idx
    cmp #9
    beq !t2_ok2+
    jmp test_fail
!t2_ok2:
    lda test_huff_calls
    beq !t2_ok3+
    jmp test_fail
!t2_ok3:
    lda zp_player_mp
    cmp #15
    beq !t2_ok4+
    jmp test_fail
!t2_ok4:
    lda player_data + PL_MANA
    cmp #15
    beq !t2_ok5+
    jmp test_fail
!t2_ok5:
    lda player_data + PL_SPELLS_WORKED_1
    and #$02
    bne !t2_ok6+
    jmp test_fail
!t2_ok6:
    lda vis_room_revealed
    cmp #1
    beq !t2_ok7+
    jmp test_fail
!t2_ok7:
    lda trap_count
    cmp #1
    beq !t2_ok8+
    jmp test_fail
!t2_ok8:
    lda trap_x
    cmp #30
    beq !t2_ok9+
    jmp test_fail
!t2_ok9:
    lda trap_y
    cmp #13
    beq !t2_ok10+
    jmp test_fail
!t2_ok10:
    ldx #11
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_OPEN
    beq !t2_ok11+
    jmp test_fail
!t2_ok11:
    ldx #12
    ldy #30
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    beq !t2_ok12+
    jmp test_fail
!t2_ok12:
    lda #2
    sta test_progress
    jmp test_after_no_effect

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, leaves adjacent
    // traps/doors untouched, and does not mark the spell worked.
test_after_no_effect:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_trap_door_destruction_state
    jsr test_setup_adjacent_destruction_map
    jsr player_cast_spell
    bcs !t3_ok0+
    jmp test_fail
!t3_ok0:
    lda test_spell_exec_calls
    beq !t3_ok1+
    jmp test_fail
!t3_ok1:
    lda test_huff_calls
    cmp #1
    beq !t3_ok2+
    jmp test_fail
!t3_ok2:
    lda test_last_huff
    cmp #HSTR_PM_FAIL
    beq !t3_ok3+
    jmp test_fail
!t3_ok3:
    lda zp_player_mp
    cmp #15
    beq !t3_ok4+
    jmp test_fail
!t3_ok4:
    lda player_data + PL_MANA
    cmp #15
    beq !t3_ok5+
    jmp test_fail
!t3_ok5:
    lda player_data + PL_SPELLS_WORKED_1
    and #$02
    beq !t3_ok6+
    jmp test_fail
!t3_ok6:
    lda vis_room_revealed
    beq !t3_ok7+
    jmp test_fail
!t3_ok7:
    ldx #11
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    beq !t3_ok8+
    jmp test_fail
!t3_ok8:
    ldx #12
    ldy #23
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    beq !t3_ok9+
    jmp test_fail
!t3_ok9:
    ldx #13
    ldy #22
    jsr test_read_tile
    and #TILE_TYPE_MASK
    cmp #TILE_TRAP
    beq !t3_ok10+
    jmp test_fail
!t3_ok10:
    lda trap_count
    cmp #2
    beq !t3_ok11+
    jmp test_fail
!t3_ok11:
    lda #3
    sta test_progress
    jmp test_pass

test_fail_loop:
    jmp test_fail_loop

test_pass_loop:
    jmp test_pass_loop
