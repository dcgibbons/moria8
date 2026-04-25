// test_genocide.s — Focused runtime tests for the Genocide spell row

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tg_results: .fill 2, $ff

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
    lda tg_results,x
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
#import "../../common/input_contract.s"
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
#import "../../common/spell_data.s"
#import "../../common/projectile.s"
#import "../../common/spell_effects.s"
#import "../../common/player_magic_state.s"
#import "../../common/player_magic_state_ops.s"
#import "../../common/player_magic.s"
#import "../../common/player_magic_feedback.s"
#import "../../common/player_magic_execute_overlay.s"
#import "../../common/ui_inventory.s"
#import "../../common/ui_equipment.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"

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
    rts
#import "../../common/ui_trampoline_stubs.s"

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

tg_huff_calls: .byte 0
tg_last_huff_id: .byte 0
tg_spell_exec_calls: .byte 0
tg_last_spell_idx: .byte $ff

recall_query_sc: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tg_last_huff_id
    inc tg_huff_calls
    rts

test_input_get_key_w:
    lda #$57
    rts

test_tramp_spell_execute_selected:
    inc tg_spell_exec_calls
    lda pm_spell_idx
    sta tg_last_spell_idx
    jsr eff_genocide
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
    lda #30
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #25
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

recall_key_to_screen_code:
    cmp #$41
    bcc !try_shifted+
    cmp #$5b
    bcs !try_shifted+
    sec
    sbc #$40
    sta recall_query_sc
    sec
    rts
!try_shifted:
    cmp #$c1
    bcc !invalid+
    cmp #$db
    bcs !invalid+
    and #$3f
    clc
    adc #$40
    sta recall_query_sc
    sec
    rts
!invalid:
    clc
    rts

test_setup_room:
    jsr fill_map_rock
    jsr item_init_floor
    jsr monster_init_table
    lda #0
    sta vis_room_revealed
    sta zp_dirty_count
    lda #$ff
    sta vis_cached_room_idx
    lda #0
    sta room_count

    lda #1
    sta room_count
    lda #20
    sta room_x
    sta dg_room_x
    lda #10
    sta room_y
    sta dg_room_y
    lda #10
    sta room_w
    sta dg_room_w
    lda #6
    sta room_h
    sta dg_room_h
    lda #0
    sta room_lit
    jsr draw_dungeon_room
    jsr darken_rooms

    lda #22
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #12
    sta zp_player_y
    sta player_data + PL_MAP_Y
    lda #1
    sta zp_player_dlvl
    lda #0
    sta zp_eff_blind
    lda #1
    sta zp_light_radius
    sta player_data + PL_LIGHT_RAD
    lda #COL_BLACK
    sta zp_text_color
    jsr screen_clear
    jsr update_visibility
    jsr viewport_update
    jsr render_viewport
    rts

test_spawn_genocide_targets:
    lda #23
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #2                      // 'W'
    jsr monster_spawn_one
    bcc !done+

    lda #24
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #10                     // also 'W'
    jsr monster_spawn_one
    bcc !done+

    lda #25
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #1                      // non-matching glyph
    jsr monster_spawn_one
!done:
    rts

test_reset_genocide_spell_state:
    jsr player_init
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
    lda #30
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
    sta tg_huff_calls
    sta tg_last_huff_id
    sta tg_spell_exec_calls
    sta vis_room_revealed
    sta zp_dirty_count
    lda #$ff
    sta tg_last_spell_idx
    rts

test_start:
    :PatchJump(input_get_key, test_input_get_key_w)
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_spell_execute_selected)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_prompt_visible_spell_choice, test_pm_prompt_visible_spell_choice)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)

    jsr msg_init
    jsr sound_init

    // Test 1: successful cast reaches spell slot 30, prompts for a glyph,
    // removes all matching monsters, leaves nonmatches alive, spends 25 mana,
    // and marks Genocide worked.
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr test_reset_genocide_spell_state
    jsr test_setup_room
    jsr test_spawn_genocide_targets
    jsr player_cast_spell
    bcc !t1_fail+
    lda tg_spell_exec_calls
    cmp #1
    bne !t1_fail+
    lda tg_last_spell_idx
    cmp #30
    bne !t1_fail+
    lda tg_huff_calls
    cmp #1
    bne !t1_fail+
    lda tg_last_huff_id
    cmp #HSTR_PM_TITLE_PRAY
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
    ldx #1
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !t1_fail+
    ldx #2
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #1
    bne !t1_fail+
    lda zp_mon_count
    cmp #1
    bne !t1_fail+
    lda zp_player_mp
    cmp #5
    bne !t1_fail+
    lda player_data + PL_MANA
    cmp #5
    bne !t1_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$40
    beq !t1_fail+
    lda #$01
    sta tg_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tg_results + 0

    // Test 2: cast failure spends mana, prints HSTR_PM_FAIL, does not prompt
    // or execute, leaves monsters unchanged, and does not mark worked.
!t2:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr test_reset_genocide_spell_state
    jsr test_setup_room
    jsr test_spawn_genocide_targets
    jsr player_cast_spell
    bcc !t2_fail+
    lda tg_spell_exec_calls
    bne !t2_fail+
    lda tg_huff_calls
    cmp #1
    bne !t2_fail+
    lda tg_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t2_fail+
    lda vis_room_revealed
    bne !t2_fail+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #2
    bne !t2_fail+
    ldx #1
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #10
    bne !t2_fail+
    ldx #2
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #1
    bne !t2_fail+
    lda zp_mon_count
    cmp #3
    bne !t2_fail+
    lda zp_player_mp
    cmp #5
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #5
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_3
    and #$40
    bne !t2_fail+
    lda #$01
    sta tg_results + 1
    jmp test_finish
!t2_fail:
    lda #$00
    sta tg_results + 1
    jmp test_finish
