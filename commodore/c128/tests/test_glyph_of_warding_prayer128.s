#importonce
// test_glyph_of_warding_prayer128.s — Focused C128 coverage for the Glyph of Warding prayer row

.const KEY_ESC = $ae
.const SFX_HIT = $01
.const SFX_PICKUP = $03
.const SFX_SPELL = $06
.const SFX_SPELL_FAIL = $07
.const VIEWPORT_X = 1
.const VIEWPORT_Y = 2
.const VIEWPORT_W = 78
.const VIEWPORT_H = 19
.const MX_X = 0
.const MX_Y = 1
.const MX_TYPE = 2
.const MX_HP_LO = 3
.const MX_HP_HI = 4
.const MX_SLEEP_CUR = 7
.const MX_CONFUSE = 9
.const MAX_MONSTERS = 32
.const EMPTY_SLOT = $ff
.const CF_UNDEAD = $02
.const CF_EVIL = $04
.const PIW_FILTER_PRAYER_BOOK = $fb
.const PIW_FILTER_MAGE_BOOK = $fc

.const PL_CLASS = 18
.const PL_LEVEL = 19
.const PL_WIS_CUR = 29
.const PL_CON_CUR = 31
.const PL_HP_LO = 33
.const PL_HP_HI = 34
.const PL_MANA = 37
.const PL_MAX_MANA = 38
.const PL_MAP_X = 39
.const PL_MAP_Y = 40
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
cmb_kill_str:
    .text "KILL" ; .byte 0
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
cr_level: .fill 65, 0

fi_x: .fill MAX_FLOOR_ITEMS, 0
fi_y: .fill MAX_FLOOR_ITEMS, 0
fi_item_id: .fill MAX_FLOOR_ITEMS, 0
fi_qty: .fill MAX_FLOOR_ITEMS, 0
fi_add_x: .byte 0
fi_add_y: .byte 0
fi_add_id: .byte 0
fi_add_qty: .byte 0
fi_add_qty_hi: .byte 0
fi_add_p1: .byte 0
fi_add_flags: .byte 0
fi_add_ego: .byte 0
pmx_work_idx: .byte 0
pmx_work_flag: .byte 0
pmx_work_damage: .byte 0

glyph_x: .fill MAX_GLYPHS, 0
glyph_y: .fill MAX_GLYPHS, 0
glyph_active: .fill MAX_GLYPHS, 0

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
input_get_key:
input_get_key_fast:
show_inv_and_select:
tramp_spell_list_display:
monster_get_ptr:
combat_kill_message:
combat_msg_monster_shudders:
combat_msg_monster_dissolves:
combat_msg_monster_runs_frantically:
combat_msg_monster_unaffected:
los_is_visible:
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
msg_build_action:
cmb_print_buf:
piw_prompt_filtered_inv:
piw_pick_filtered_inv_key:
piw_print_prompt_with_count:
screen_flash_set_color:
screen_flash_reset_color:
screen_flash_at:
    clc
    rts

eff_remove_fear:
    rts

player_calc_stats:
    rts

player_sync_to_zp:
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

calc_spell_failure:
    clc
    rts

tramp_spell_execute_selected:
    rts

huff_print_msg:
    stx test_last_huff
    inc test_huff_calls
    rts

fi_add_clear_plain_meta:
    lda #0
    sta fi_add_qty_hi
    sta fi_add_p1
    sta fi_add_flags
    sta fi_add_ego
    rts

floor_item_find_at:
    stx zp_temp0
    sty zp_temp1
    ldx #0
!find:
    cpx #MAX_FLOOR_ITEMS
    bcs !miss+
    lda fi_item_id,x
    beq !next+
    lda fi_x,x
    cmp zp_temp0
    bne !next+
    lda fi_y,x
    cmp zp_temp1
    bne !next+
    sec
    rts
!next:
    inx
    jmp !find-
!miss:
    clc
    rts

floor_item_remove:
    lda #0
    sta fi_item_id,x
    sta fi_qty,x
    sta fi_x,x
    sta fi_y,x
    rts

floor_item_add:
    ldx #0
!slot:
    cpx #MAX_FLOOR_ITEMS
    bcs !fail+
    lda fi_item_id,x
    beq !use+
    inx
    jmp !slot-
!use:
    lda fi_add_x
    sta fi_x,x
    lda fi_add_y
    sta fi_y,x
    lda fi_add_id
    sta fi_item_id,x
    lda fi_add_qty
    sta fi_qty,x
    sec
    rts
!fail:
    clc
    rts

glyph_clear_all:
    ldx #MAX_GLYPHS - 1
    lda #0
!loop:
    sta glyph_active,x
    dex
    bpl !loop-
    rts

glyph_find_at:
    sta fi_add_x
    stx zp_temp0
    ldx #0
!find:
    cpx #MAX_GLYPHS
    bcs !miss+
    lda glyph_active,x
    beq !next+
    lda glyph_x,x
    cmp fi_add_x
    bne !next+
    lda zp_temp0
    cmp glyph_y,x
    bne !next+
    sec
    rts
!next:
    inx
    jmp !find-
!miss:
    clc
    rts

glyph_add_at:
    sty fi_add_y
    jsr glyph_find_at
    bcs !ok+
    ldx #0
!slot:
    cpx #MAX_GLYPHS
    bcs !fail+
    lda glyph_active,x
    beq !use+
    inx
    jmp !slot-
!use:
    lda fi_add_x
    sta glyph_x,x
    lda fi_add_y
    sta glyph_y,x
    lda #1
    sta glyph_active,x
!ok:
    sec
    rts
!fail:
    clc
    rts

test_tramp_glyph_of_warding_execute:
    inc test_spell_exec_calls
    lda pm_spell_idx
    sta test_last_spell_idx
    jsr eff_glyph_of_warding
    rts

test_pm_select_book:
    lda #3
    sta pm_book_idx
    lda #<book_mask_7
    sta pm_book_mask_lo
    lda #>book_mask_7
    sta pm_book_mask_hi
    sec
    rts

test_pm_prompt_visible_spell_choice:
    lda #29
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #36
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_reset_glyph_state:
    ldx #MAX_FLOOR_ITEMS - 1
    lda #0
!clear_items:
    sta fi_x,x
    sta fi_y,x
    sta fi_item_id,x
    sta fi_qty,x
    dex
    bpl !clear_items-
    jsr glyph_clear_all

    lda #0
    sta test_huff_calls
    sta test_last_huff
    sta test_spell_exec_calls
    sta vis_room_revealed
    lda #$ff
    sta test_last_spell_idx

    lda #CLASS_PRIEST
    sta player_data + PL_CLASS
    lda #SPELL_PRIEST
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_WIS_CUR
    lda #18
    sta player_data + PL_CON_CUR
    lda #40
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
    jsr fi_add_clear_plain_meta
    jsr floor_item_add
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
    :PatchJump(tramp_spell_execute_selected, test_tramp_glyph_of_warding_execute)

    // Test 1: successful prayer reaches slot 29, creates a glyph at the
    // player tile, prints GLYPH_OK, spends 36 mana, and marks the prayer
    // worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_glyph_state
    jsr player_pray
    bcc !t1_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda test_last_spell_idx
    cmp #29
    bne !t1_fail+
    lda glyph_active + 0
    cmp #1
    bne !t1_fail+
    lda glyph_x + 0
    cmp zp_player_x
    bne !t1_fail+
    lda glyph_y + 0
    cmp zp_player_y
    bne !t1_fail+
    lda test_huff_calls
    cmp #1
    bne !t1_fail+
    lda test_last_huff
    cmp #HSTR_PMU_GLYPH_OK
    bne !t1_fail+
    lda vis_room_revealed
    cmp #1
    bne !t1_fail+
    lda zp_player_mp
    cmp #4
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #4
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$20
    beq !t1_fail+
    lda #1
    sta test_progress
    jmp test_after_success
!t1_fail:
    jmp test_fail

    // Test 2: blocked by an item under the player prints GLYPH_BLOCK,
    // creates no glyph, still spends mana, and marks the prayer worked.
test_after_success:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_glyph_state
    jsr test_seed_underfoot_item
    bcc !t2_fail+
    jsr player_pray
    bcc !t2_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda test_last_spell_idx
    cmp #29
    bne !t2_fail+
    lda glyph_active + 0
    bne !t2_fail+
    lda test_huff_calls
    cmp #1
    bne !t2_fail+
    lda test_last_huff
    cmp #HSTR_PMU_GLYPH_BLOCK
    bne !t2_fail+
    lda vis_room_revealed
    bne !t2_fail+
    lda zp_player_mp
    cmp #4
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #4
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$20
    beq !t2_fail+
    lda #2
    sta test_progress
    jmp test_after_blocked
!t2_fail:
    jmp test_fail

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not execute,
    // and leaves Glyph of Warding unworked.
test_after_blocked:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_glyph_state
    jsr player_pray
    bcc !t3_fail+
    lda test_spell_exec_calls
    bne !t3_fail+
    lda glyph_active + 0
    bne !t3_fail+
    lda test_huff_calls
    cmp #1
    bne !t3_fail+
    lda test_last_huff
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda zp_player_mp
    cmp #4
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #4
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$20
    bne !t3_fail+
    lda #3
    sta test_progress
    jmp test_pass
!t3_fail:
    jmp test_fail

test_fail_loop:
    jmp test_fail_loop

test_pass_loop:
    jmp test_pass_loop
