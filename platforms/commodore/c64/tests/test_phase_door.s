// test_phase_door.s — Focused runtime tests for the Phase Door spell row

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
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"
#import "../../../../core/item_actions_overlay.s"
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

tpm_spell_exec_calls: .byte 0
tpm_huff_calls: .byte 0
tpm_last_huff_id: .byte 0
tpm_last_spell_idx: .byte $ff
tpd_find_random_floor_calls: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_input_get_key_c:
    lda #$43
    rts

test_input_get_modal_spell_a:
    lda #$41
    rts

test_huff_print_msg:
    stx tpm_last_huff_id
    inc tpm_huff_calls
    rts

test_tramp_spell_execute_selected:
    inc tpm_spell_exec_calls
    lda pm_spell_idx
    sta tpm_last_spell_idx
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

test_pm_pick_visible_spell_c:
    lda #2
    sta pm_spell_idx
    sec
    rts

test_pm_validate_selected_spell:
    lda #2
    sta pm_cost_tmp
    sec
    rts

test_calc_spell_failure_success:
    clc
    rts

test_calc_spell_failure_fail:
    sec
    rts

test_find_random_floor_phase_door:
    inc tpd_find_random_floor_calls
    lda tpd_find_random_floor_calls
    cmp #1
    bne !second+
    lda #25
    sta df_target_x
    lda #14
    sta df_target_y
    sec
    rts
!second:
    lda #40
    sta df_target_x
    lda #30
    sta df_target_y
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

test_setup_phase_door_room:
    jsr fill_map_rock
    lda #0
    sta vis_room_revealed
    sta tpd_find_random_floor_calls

    lda #22
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #12
    sta zp_player_y
    sta player_data + PL_MAP_Y

    lda #TILE_FLOOR | FLAG_OCCUPIED
    ldx #12
    ldy #22
    jsr test_write_tile

    lda #TILE_FLOOR
    ldx #14
    ldy #25
    jsr test_write_tile

    lda #TILE_FLOOR
    ldx #30
    ldy #40
    jsr test_write_tile
    rts

test_reset_phase_door_spell_state:
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #SPELL_MAGE
    sta player_data + PL_SPELL_TYPE
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_INT_CUR
    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    lda #20
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA
    lda #$04
    sta player_data + PL_SPELLS_LEARNT_0
    lda #0
    sta player_data + PL_SPELLS_LEARNT_1
    sta player_data + PL_SPELLS_LEARNT_2
    sta player_data + PL_SPELLS_LEARNT_3
    sta player_data + PL_SPELLS_WORKED_0
    sta player_data + PL_SPELLS_WORKED_1
    sta player_data + PL_SPELLS_WORKED_2
    sta player_data + PL_SPELLS_WORKED_3
    sta tpm_spell_exec_calls
    sta tpm_huff_calls
    lda #$ff
    sta tpm_last_spell_idx
    lda #0
    sta tpm_last_huff_id
    rts

test_start:
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    jsr msg_init
    jsr hal_sound_init

    lda #8
    sta $c6
    ldx #7
    lda #$20
!seed_keys:
    sta $0277,x
    dex
    bpl !seed_keys-

    lda #0
    sta zp_eff_poison
    sta zp_eff_blind
    sta zp_eff_confuse
    sta zp_eff_paralyze
    sta zp_eff_regen
    sta zp_game_flags

    // Test 1: Phase Door uses the validated nearby tile exactly once.
    :PatchJump(find_random_floor, test_find_random_floor_phase_door)
    jsr test_setup_phase_door_room
    jsr eff_phase_door
    lda tpd_find_random_floor_calls
    cmp #1
    bne !t1_fail+
    lda zp_player_x
    cmp #25
    bne !t1_fail+
    lda zp_player_y
    cmp #14
    bne !t1_fail+
    lda vis_room_revealed
    cmp #1
    bne !t1_fail+
    ldx #12
    ldy #22
    jsr test_read_tile
    and #FLAG_OCCUPIED
    bne !t1_fail+
    ldx #14
    ldy #25
    jsr test_read_tile
    and #FLAG_OCCUPIED
    beq !t1_fail+
    ldx #30
    ldy #40
    jsr test_read_tile
    and #FLAG_OCCUPIED
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: cast failure consumes 2 mana, prints the fail text,
    // and leaves Phase Door unworked/unexecuted.
!t2:
    :PatchJump(input_get_key, test_input_get_key_c)
    :PatchJump(input_get_modal_dismiss_key, test_input_get_modal_spell_a)
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(test_spell_execute_selected, test_tramp_spell_execute_selected)
    :PatchJump(pm_select_book, test_pm_select_book)
    :PatchJump(pm_pick_visible_spell, test_pm_pick_visible_spell_c)
    :PatchJump(pm_validate_selected_spell, test_pm_validate_selected_spell)
    :PatchJump(calc_spell_failure, test_calc_spell_failure_fail)
    jsr player_init
    jsr test_reset_phase_door_spell_state
    jsr player_cast_spell
    bcc !t2_fail+
    lda tpm_spell_exec_calls
    bne !t2_fail+
    lda tpm_huff_calls
    cmp #1
    bne !t2_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PM_FAIL
    bne !t2_fail+
    lda zp_player_mp
    cmp #18
    bne !t2_fail+
    lda player_data + PL_MANA
    cmp #18
    bne !t2_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$04
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: successful Phase Door cast stays message-light and marks
    // spell 2 worked after consuming the real 2-mana cost.
!t3:
    :PatchJump(calc_spell_failure, test_calc_spell_failure_success)
    jsr player_init
    jsr test_reset_phase_door_spell_state
    jsr player_cast_spell
    bcc !t3_fail+
    lda tpm_spell_exec_calls
    cmp #1
    bne !t3_fail+
    lda tpm_last_spell_idx
    cmp #2
    bne !t3_fail+
    lda tpm_huff_calls
    bne !t3_fail+
    lda zp_player_mp
    cmp #18
    bne !t3_fail+
    lda player_data + PL_MANA
    cmp #18
    bne !t3_fail+
    lda player_data + PL_SPELLS_WORKED_0
    and #$04
    cmp #$04
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !tests_done+
!t3_fail:
    lda #$00
    sta tc_results + 2

!tests_done:
    jmp test_finish

phase_door_test_body_end:

.assert "Phase Door test stays below MAP_BASE", phase_door_test_body_end <= MAP_BASE, true
.assert "Phase Door result buffer stays under KERNAL ROM", tc_results + 3 <= $10000, true
