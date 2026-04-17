// test_utility_effects.s — Focused runtime tests for area/utility spell helpers
//
// Keeps higher-end utility coverage out of the large effects suite so the
// suite stays below the C64 scratch-buffer boundary.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"

test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_finish:
    sei
    :BankOutBasic()
    ldx #3
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0830 "Main"

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
#import "../../common/player_magic_utility.s"
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

tc_results: .fill 4, $ff

tpm_msg_calls:    .byte 0
tpm_last_msg_lo:  .byte 0
tpm_last_msg_hi:  .byte 0
tpm_huff_calls:   .byte 0
tpm_last_huff_id: .byte 0
test_mon_slot:    .byte 0
pmx_work_idx:     .byte 0
pmx_work_flag:    .byte 0
pmx_work_damage:  .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_huff_print_msg:
    stx tpm_last_huff_id
    inc tpm_huff_calls
    rts

test_msg_print:
    inc tpm_msg_calls
    lda zp_ptr0
    sta tpm_last_msg_lo
    lda zp_ptr0_hi
    sta tpm_last_msg_hi
    rts

eff_remove_fear:
    lda #0
    sta eff_fear_timer
    rts

test_combat_award_xp:
    rts

test_combat_check_levelup:
    rts

test_start:
    // Test 1: Sense Surroundings / map-area marks tiles visited.
    jsr tv_setup_dark_room
    lda #0
    sta vis_room_revealed
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #24
    lda (zp_ptr0),y
    and #~FLAG_VISITED & $ff
    sta (zp_ptr0),y
    jsr eff_map_area
    lda vis_room_revealed
    cmp #1
    bne !t1_fail+
    ldy #24
    lda (zp_ptr0),y
    and #FLAG_VISITED
    beq !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // Test 2: Glyph of Warding on an empty tile creates a glyph.
!t2:
    jsr tv_setup_dark_room
    jsr glyph_clear_all
    lda #0
    sta vis_room_revealed
    sta tpm_msg_calls
    :PatchJump(msg_print, test_msg_print)
    jsr eff_glyph_of_warding
    lda glyph_active + 0
    cmp #1
    bne !t2_fail+
    lda glyph_x + 0
    cmp zp_player_x
    bne !t2_fail+
    lda glyph_y + 0
    cmp zp_player_y
    bne !t2_fail+
    lda vis_room_revealed
    cmp #1
    bne !t2_fail+
    lda tpm_msg_calls
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // Test 3: Glyph of Warding with an object under the player reports blockage.
!t3:
    jsr tv_setup_dark_room
    jsr glyph_clear_all
    lda #0
    sta vis_room_revealed
    sta tpm_msg_calls
    sta tpm_last_msg_lo
    sta tpm_last_msg_hi
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
    bcc !t3_fail+
    jsr eff_glyph_of_warding
    lda glyph_active + 0
    bne !t3_fail+
    lda tpm_msg_calls
    cmp #1
    bne !t3_fail+
    lda tpm_last_msg_lo
    cmp #<pmx_msg_object_under
    bne !t3_fail+
    lda tpm_last_msg_hi
    cmp #>pmx_msg_object_under
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // Test 4: Holy Word heals, clears maladies, and dispels an evil monster.
!t4:
    jsr tv_setup_dark_room
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(combat_award_xp, test_combat_award_xp)
    :PatchJump(combat_check_levelup, test_combat_check_levelup)
    lda #0
    sta tpm_huff_calls
    sta tpm_last_huff_id
    lda #23
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #0
    jsr monster_spawn_one
    bcs !t4_spawn_ok+
    lda #$17
    sta tc_results + 3
    jmp test_finish
!t4_spawn_ok:
    stx test_mon_slot
    jsr monster_get_ptr
    jsr test_find_evil_type
    bcs !t4_have_evil_type+
    lda #$19
    sta tc_results + 3
    jmp test_finish
!t4_have_evil_type:
    ldy #MX_TYPE
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #1
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    lda #5
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #40
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_mhp_hi
    lda #7
    sta zp_eff_poison
    lda #8
    sta zp_eff_blind
    lda #9
    sta zp_eff_confuse
    lda #10
    sta eff_fear_timer
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    jsr eff_holy_word
    lda zp_player_hp_lo
    cmp #40
    beq !t4_hp_ok+
    lda zp_player_hp_lo
    sta tc_results + 3
    jmp test_finish
!t4_hp_ok:
    lda zp_eff_poison
    beq !t4_poison_ok+
    lda #$11
    sta tc_results + 3
    jmp test_finish
!t4_poison_ok:
    lda zp_eff_blind
    beq !t4_blind_ok+
    lda #$12
    sta tc_results + 3
    jmp test_finish
!t4_blind_ok:
    lda zp_eff_confuse
    beq !t4_confuse_ok+
    lda #$13
    sta tc_results + 3
    jmp test_finish
!t4_confuse_ok:
    lda eff_fear_timer
    beq !t4_fear_ok+
    lda #$14
    sta tc_results + 3
    jmp test_finish
!t4_fear_ok:
    lda tpm_huff_calls
    cmp #1
    beq !t4_huff_count_ok+
    lda #$15
    sta tc_results + 3
    jmp test_finish
!t4_huff_count_ok:
    lda tpm_last_huff_id
    cmp #HSTR_PIQ_MUCH_BETTER
    beq !t4_huff_id_ok+
    lda #$16
    sta tc_results + 3
    jmp test_finish
!t4_huff_id_ok:
    ldx test_mon_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !t4_monster_ok+
    lda #$18
    sta tc_results + 3
    jmp test_finish
!t4_monster_ok:
    lda #$01
    sta tc_results + 3
    jmp test_finish
tv_setup_dark_room:
    jsr fill_map_rock
    jsr item_init_floor
    jsr monster_init_table
    lda #0
    sta vis_room_revealed
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

test_find_evil_type:
    ldx #0
!tfe_loop:
    cpx #MAX_CREATURES
    bcs !tfe_none+
    lda cr_mflags,x
    and #CF_EVIL
    bne !tfe_found+
    inx
    jmp !tfe_loop-
!tfe_found:
    txa
    sec
    rts
!tfe_none:
    clc
    rts
