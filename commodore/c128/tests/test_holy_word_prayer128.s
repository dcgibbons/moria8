#importonce
// test_holy_word_prayer128.s — Focused C128 coverage for the Holy Word prayer row

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
.const PL_STR_BASE = 21
.const PL_INT_BASE = 22
.const PL_WIS_BASE = 23
.const PL_DEX_BASE = 24
.const PL_CON_BASE = 25
.const PL_CHR_BASE = 26
.const PL_STR_CUR = 27
.const PL_INT_CUR = 28
.const PL_WIS_CUR = 29
.const PL_DEX_CUR = 30
.const PL_CON_CUR = 31
.const PL_CHR_CUR = 32
.const PL_HP_LO = 33
.const PL_HP_HI = 34
.const PL_MHP_LO = 35
.const PL_MHP_HI = 36
.const PL_MANA = 37
.const PL_MAX_MANA = 38
.const PL_MAP_X = 49
.const PL_MAP_Y = 50
.const PL_SPELL_TYPE = 60
.const PL_SPELLS_LEARNT_0 = 61
.const PL_SPELLS_LEARNT_1 = 62
.const PL_SPELLS_LEARNT_2 = 63
.const PL_SPELLS_LEARNT_3 = 64
.const PL_SPELLS_WORKED_0 = 65
.const PL_SPELLS_WORKED_1 = 66
.const PL_SPELLS_WORKED_2 = 67
.const PL_SPELLS_WORKED_3 = 68
.const PL_NEW_SPELLS = 73
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
trap_count: .byte 0
trap_x: .fill 16, 0
trap_y: .fill 16, 0
trap_type: .fill 16, 0
cr_mflags: .fill 65, 0
cmb_kill_str:
    .text "KILL" ; .byte 0
pmx_work_idx: .byte 0
pmx_work_flag: .byte 0
pmx_work_damage: .byte 0
fi_add_x: .byte 0
fi_add_y: .byte 0
fi_add_id: .byte 0
fi_add_qty: .byte 0
fi_add_qty_hi: .byte 0
fi_add_p1: .byte 0
fi_add_flags: .byte 0
fi_add_ego: .byte 0

test_huff_calls: .byte 0
test_last_huff: .byte 0
test_spell_exec_calls: .byte 0
test_last_spell_idx: .byte $ff
test_kill_calls: .byte 0
test_progress: .byte 0
test_los_visible: .byte 1
eff_fear_timer: .byte 0
vis_room_revealed: .byte 0
vis_cached_room_idx: .byte 0
dg_room_x: .byte 0
dg_room_y: .byte 0
dg_room_w: .byte 0
dg_room_h: .byte 0

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
screen_flash_set_color:
screen_flash_reset_color:
screen_flash_at:
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
find_random_floor:
piw_prompt_filtered_inv:
piw_pick_filtered_inv_key:
piw_print_prompt_with_count:
floor_item_find_at:
floor_item_remove:
floor_item_add:
fi_add_clear_plain_meta:
    clc
    rts

combat_award_xp:
combat_check_levelup:
    rts

combat_append_monster_name:
combat_msg_monster_shudders:
combat_msg_monster_dissolves:
    rts

los_is_visible:
    lda test_los_visible
    beq !hidden+
    sec
    rts
!hidden:
    clc
    rts

monster_remove:
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #EMPTY_SLOT
    sta (zp_ptr0),y
    rts

sound_play:
    rts

tier_restore_after_overlay:
    rts

huff_print_msg:
    stx test_last_huff
    inc test_huff_calls
    rts

eff_remove_fear:
    lda #0
    sta eff_fear_timer
    rts

player_calc_stats:
    ldx #0
!pcs_loop:
    lda player_data + PL_STR_BASE,x
    sta player_data + PL_STR_CUR,x
    inx
    cpx #6
    bcc !pcs_loop-
    rts

player_sync_to_zp:
    lda player_data + PL_STR_CUR
    sta zp_player_str
    lda player_data + PL_INT_CUR
    sta zp_player_int
    lda player_data + PL_WIS_CUR
    sta zp_player_wis
    lda player_data + PL_DEX_CUR
    sta zp_player_dex
    lda player_data + PL_CON_CUR
    sta zp_player_con
    lda player_data + PL_CHR_CUR
    sta zp_player_chr
    rts

stat_bonus_index:
    rts

glyph_add_at:
    clc
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
    bcc !kill+
    pha
    ldy #MX_HP_LO
    lda zp_temp0
    sta (zp_ptr0),y
    iny
    pla
    sta (zp_ptr0),y
    clc
    rts
!kill:
    ldy #MX_HP_LO
    lda #0
    sta (zp_ptr0),y
    iny
    sta (zp_ptr0),y
    sec
    rts

combat_kill_message:
    inc test_kill_calls
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #EMPTY_SLOT
    sta (zp_ptr0),y
    rts

msg_build_action:
cmb_print_buf:
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

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_tramp_spell_execute_selected:
    inc test_spell_exec_calls
    lda pm_spell_idx
    sta test_last_spell_idx
    jsr eff_holy_word
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
    lda #30
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #38
    sta pm_cost_tmp
    sec
    rts

test_clear_monsters:
    ldx #0
!loop:
    lda #0
    sta test_mon_table,x
    inx
    cpx #(MAX_MONSTERS * MONSTER_ENTRY_SIZE)
    bcc !loop-
    lda #0
    ldx #0
!flags:
    sta cr_mflags,x
    inx
    cpx #65
    bcc !flags-
    rts

test_seed_stats:
    ldx #0
!seed:
    lda #12
    sta player_data + PL_STR_BASE,x
    sta player_data + PL_STR_CUR,x
    inx
    cpx #6
    bcc !seed-
    jsr player_sync_to_zp
    rts

test_mark_stats_drained:
    lda #3
    sta player_data + PL_STR_CUR
    sta zp_player_str
    lda #4
    sta player_data + PL_INT_CUR
    sta zp_player_int
    lda #5
    sta player_data + PL_WIS_CUR
    sta zp_player_wis
    lda #6
    sta player_data + PL_DEX_CUR
    sta zp_player_dex
    lda #7
    sta player_data + PL_CON_CUR
    sta zp_player_con
    lda #8
    sta player_data + PL_CHR_CUR
    sta zp_player_chr
    rts

test_seed_evil_monster:
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda #10
    sta (zp_ptr0),y
    iny
    lda #8
    sta (zp_ptr0),y
    iny
    lda #1
    sta (zp_ptr0),y
    iny
    lda #1
    sta (zp_ptr0),y
    iny
    lda #0
    sta (zp_ptr0),y
    lda #CF_EVIL
    sta cr_mflags + 1
    rts

test_reset_holy_word_state:
    jsr test_clear_monsters
    lda #0
    sta test_huff_calls
    sta test_last_huff
    sta test_spell_exec_calls
    sta test_kill_calls
    sta eff_fear_timer
    sta zp_eff_poison
    sta eff_invuln_timer
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
    lda #$40
    sta player_data + PL_SPELLS_LEARNT_3
    lda #0
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3

    lda #10
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #8
    sta zp_player_y
    sta player_data + PL_MAP_Y

    lda #10
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #30
    sta zp_player_mhp_lo
    sta player_data + PL_MHP_LO
    lda #0
    sta zp_player_mhp_hi
    sta player_data + PL_MHP_HI

    jsr test_seed_stats
    rts

test_expect_stats_restored:
    ldx #0
!check:
    lda player_data + PL_STR_CUR,x
    cmp #12
    bne !fail+
    inx
    cpx #6
    bcc !check-
    lda zp_player_str
    cmp #12
    bne !fail+
    lda zp_player_int
    cmp #12
    bne !fail+
    lda zp_player_wis
    cmp #12
    bne !fail+
    lda zp_player_dex
    cmp #12
    bne !fail+
    lda zp_player_con
    cmp #12
    bne !fail+
    lda zp_player_chr
    cmp #12
    beq !ok+
!fail:
    clc
    rts
!ok:
    sec
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

    :PatchJump(tramp_spell_execute_selected, test_tramp_spell_execute_selected)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    // Test 1: Holy Word heals to full, clears poison/fear, restores stats,
    // grants 3 turns of invulnerability, dispels evil, and marks the prayer worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_holy_word_state
    lda #9
    sta zp_eff_poison
    lda #7
    sta eff_fear_timer
    jsr test_mark_stats_drained
    jsr test_seed_evil_monster
    jsr player_pray
    bcc !t1_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda test_last_spell_idx
    cmp #30
    bne !t1_fail+
    lda zp_player_hp_lo
    cmp #30
    bne !t1_fail+
    lda player_data + PL_HP_LO
    cmp #30
    bne !t1_fail+
    lda zp_eff_poison
    bne !t1_fail+
    lda eff_fear_timer
    bne !t1_fail+
    jsr test_expect_stats_restored
    bcc !t1_fail+
    lda eff_invuln_timer
    cmp #3
    bne !t1_fail+
    lda test_huff_calls
    cmp #1
    bne !t1_fail+
    lda test_last_huff
    cmp #HSTR_PIQ_VERY_GOOD
    bne !t1_fail+
    lda test_kill_calls
    cmp #1
    bne !t1_fail+
    lda test_mon_table + MX_TYPE
    cmp #EMPTY_SLOT
    bne !t1_fail+
    lda zp_player_mp
    cmp #2
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #2
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$40
    beq !t1_fail+
    lda #1
    sta test_progress
    jmp test_after_full
!t1_fail:
    jmp test_fail

    // Test 2: with no evil targets and already-clean/full state, Holy Word
    // still succeeds, stays on the current explicit heal message, and grants invulnerability.
test_after_full:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_holy_word_state
    jsr player_pray
    bcc !t2_fail+
    lda test_spell_exec_calls
    cmp #1
    bne !t2_fail+
    lda test_last_spell_idx
    cmp #30
    bne !t2_fail+
    lda zp_player_hp_lo
    cmp #30
    bne !t2_fail+
    lda zp_eff_poison
    bne !t2_fail+
    lda eff_fear_timer
    bne !t2_fail+
    lda eff_invuln_timer
    cmp #3
    bne !t2_fail+
    lda test_huff_calls
    cmp #1
    bne !t2_fail+
    lda test_last_huff
    cmp #HSTR_PIQ_VERY_GOOD
    bne !t2_fail+
    lda test_kill_calls
    bne !t2_fail+
    lda zp_player_mp
    cmp #2
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #2
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$40
    beq !t2_fail+
    lda #2
    sta test_progress
    jmp test_after_fail
!t2_fail:
    jmp test_fail

    // Test 3: cast failure spends mana, prints HSTR_PM_FAIL, does not execute
    // Holy Word, and leaves the prayer unworked.
test_after_fail:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_holy_word_state
    lda #9
    sta zp_eff_poison
    lda #7
    sta eff_fear_timer
    jsr test_mark_stats_drained
    jsr test_seed_evil_monster
    jsr player_pray
    bcc !t3_fail+
    lda test_spell_exec_calls
    bne !t3_fail+
    lda zp_player_hp_lo
    cmp #10
    bne !t3_fail+
    lda player_data + PL_HP_LO
    cmp #10
    bne !t3_fail+
    lda zp_eff_poison
    cmp #9
    bne !t3_fail+
    lda eff_fear_timer
    cmp #7
    bne !t3_fail+
    lda eff_invuln_timer
    bne !t3_fail+
    lda test_huff_calls
    cmp #1
    bne !t3_fail+
    lda test_last_huff
    cmp #HSTR_PM_FAIL
    bne !t3_fail+
    lda test_kill_calls
    bne !t3_fail+
    lda zp_player_mp
    cmp #2
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #2
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$40
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
