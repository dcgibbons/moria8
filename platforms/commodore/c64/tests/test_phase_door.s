// test_phase_door.s — Focused runtime tests for the Phase Door spell row
//
// Tests 5-7 run the production eff_phase_door / find_random_floor_near
// against VMS Moria moria.inc teleport(10) (Umoria player.cpp
// playerTeleport(10)): a random map square is moved halfway toward the
// player, truncating the step, while its distance (VMS distance.mar:
// max(dy,dx) + min(dy,dx) div 2) exceeds 10, until an open floor square
// without a creature is found; it never gives up. Moria8 refuses the
// player's own square and stops after about 2,000 tries (1,793-2,048).
.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $E000 "Result Buffer"
tc_results: .fill 7, $ff

.pc = $080E "Test Code"

.encoding "screencode_mixed"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    :BankOutKernal()
    ldx #6
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
#define REU_DETECT_EXTERNAL      // not exercised here; frees room below MAP_BASE
#import "../../common/reu.s"
#import "../screen.s"
#import "../../../../core/color.s"
#import "../config.s"
// Product layout: scratch buffers in free page-2 RAM, keeping the test body
// below MAP_BASE now that items stack.
#define PLATFORM_SCRATCH_BUFS_IN_PAGE2
#import "../input.s"
#import "../../../../core/rng.s"
#import "../../../../core/math.s"
#import "../../../../core/tables.s"
#import "../../../../core/item_defs.s"
#import "../../../../core/player.s"
#import "../../../../core/ui_messages.s"
#import "../../../../core/ui_status.s"
#import "../../../../core/ui_help_clear.s"
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
#import "../../../../core/scene_mat_tile.s"
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

test_input_get_key_a:
    lda #$41
    rts

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

tpd_frfn_orig: .fill 3, 0
tpd_ok:   .byte 0
tpd_loop: .byte 0
tpd_row:  .byte 0
tpd_dx:   .byte 0
tpd_max:  .byte 0
tpd_end:  .byte 0

// tpd_floor_row — TILE_FLOOR on row Y from column A to column X
tpd_floor_row:
    sty tpd_row_arg
    stx tpd_end
    tax
!tfr_loop:
    stx tpd_dx
    txa
    tay
    ldx tpd_row_arg
    lda #TILE_FLOOR
    jsr test_write_tile
    ldx tpd_dx
    inx
    cpx tpd_end
    bcc !tfr_loop-
    beq !tfr_loop-
    rts
tpd_row_arg: .byte 0

// tpd_cast_at_22_12 — Production eff_phase_door from (22,12)
tpd_cast_at_22_12:
    lda #22
    sta zp_player_x
    lda #12
    sta zp_player_y
    lda #0
    sta vis_room_revealed
    jmp eff_phase_door

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

    lda #TILE_FLOOR                 // the player's tile: no creature flag
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
    ldx #2
!save_frfn:
    lda find_random_floor_near,x
    sta tpd_frfn_orig,x
    dex
    bpl !save_frfn-
    :PatchJump(find_random_floor_near, test_find_random_floor_phase_door)
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
    bne !t1_fail+
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
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // Test 4: the Scroll of Phase Door (item 136, VMS teleport(10)) read
    // through the real item_read_scroll dispatch moves the player to the
    // validated nearby tile, is consumed, and becomes known.
!t4:
    jsr item_init_inventory
    jsr test_setup_phase_door_room
    lda #0
    sta zp_eff_blind
    sta zp_msg_flags
    ldx #ITEM_TYPE_SCR_PHASE_DOOR
    jsr id_known_clear
    lda #ITEM_TYPE_SCR_PHASE_DOOR
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags
    :PatchJump(input_get_key, test_input_get_key_a)   // 'A': the scroll in slot 0
    jsr item_read_scroll
    bcc !t4_fail+
    lda zp_player_x
    cmp #25
    bne !t4_fail+
    lda zp_player_y
    cmp #14
    bne !t4_fail+
    lda inv_item_id
    cmp #FI_EMPTY
    bne !t4_fail+
    ldx #ITEM_TYPE_SCR_PHASE_DOOR
    jsr id_known_test
    beq !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // Tests 5-7: the production search (find_random_floor_near restored).
!t5:
    ldx #2
!restore_frfn:
    lda tpd_frfn_orig,x
    sta find_random_floor_near,x
    dex
    bpl !restore_frfn-

    // Test 5: the west end of an east-west corridor (floor x 22-60 on row
    // 12, rock elsewhere). Every one of 30 casts moves the player along the
    // corridor, 1-10 squares east. Before the fix 20 whole-map tries mostly
    // found nothing and the player stayed.
    jsr fill_map_rock
    lda #22
    ldx #60
    ldy #12
    jsr tpd_floor_row
    lda #1
    sta tpd_ok
    lda #30
    sta tpd_loop
!t5_loop:
    jsr tpd_cast_at_22_12
    lda zp_player_y
    cmp #12
    bne !t5_bad+
    lda zp_player_x
    cmp #23
    bcc !t5_bad+
    cmp #33
    bcc !t5_next+
!t5_bad:
    lda #0
    sta tpd_ok
!t5_next:
    dec tpd_loop
    bne !t5_loop-
    lda tpd_ok
    sta tc_results + 4

    // Test 6: open floor x 10-34, rows 2-22 around the player at (22,12).
    // Over 40 casts every landing is 1-10 by VMS distance (the old
    // Chebyshev <= 10 test also allowed e.g. (8,8): VMS distance 12).
    jsr fill_map_rock
    lda #2
    sta tpd_row
!t6_rows:
    lda #10
    ldx #34
    ldy tpd_row
    jsr tpd_floor_row
    inc tpd_row
    lda tpd_row
    cmp #23
    bne !t6_rows-
    lda #1
    sta tpd_ok
    lda #40
    sta tpd_loop
!t6_loop:
    jsr tpd_cast_at_22_12
    lda zp_player_x
    sec
    sbc #22
    bcs !t6_dx+
    eor #$ff
    adc #1
!t6_dx:
    sta tpd_dx
    lda zp_player_y
    sec
    sbc #12
    bcs !t6_dy+
    eor #$ff
    adc #1
!t6_dy:
    // VMS distance: (2 * max + min) div 2
    cmp tpd_dx
    bcs !t6_dy_max+
    ldx tpd_dx                  // max = |dx|, min = |dy| (A)
    stx tpd_max
    bcc !t6_dist+               // Always
!t6_dy_max:
    sta tpd_max                 // max = |dy|, min = |dx|
    lda tpd_dx
!t6_dist:
    lsr
    clc
    adc tpd_max
    beq !t6_bad+                // Did not move
    cmp #11
    bcc !t6_next+
!t6_bad:
    lda #0
    sta tpd_ok
!t6_next:
    dec tpd_loop
    bne !t6_loop-
    lda tpd_ok
    sta tc_results + 5

    // Test 7: the only other floor squares in reach hold creatures: the
    // search ends (about 2,000 tries) and the player stays put.
    jsr fill_map_rock
    lda #22
    ldx #24
    ldy #12
    jsr tpd_floor_row
    lda #TILE_FLOOR | FLAG_OCCUPIED
    ldx #12
    ldy #23
    jsr test_write_tile
    lda #TILE_FLOOR | FLAG_OCCUPIED
    ldx #12
    ldy #24
    jsr test_write_tile
    jsr tpd_cast_at_22_12
    lda #$00
    sta tc_results + 6
    lda zp_player_x
    cmp #22
    bne !tests_done+
    lda zp_player_y
    cmp #12
    bne !tests_done+
    lda vis_room_revealed
    bne !tests_done+
    lda #$01
    sta tc_results + 6

!tests_done:
    jmp test_finish

phase_door_test_body_end:

.assert "Phase Door test stays below MAP_BASE", phase_door_test_body_end <= MAP_BASE, true
.assert "Phase Door result buffer stays under KERNAL ROM", tc_results + 4 <= $10000, true
// Dropped the ui_character.s import to keep the test body under MAP_BASE
// (map-overlap boundary); stubs satisfy the trampoline references.
ui_char_display:
    rts
count_spells_known:
    jmp spell_mask_count_ptr
