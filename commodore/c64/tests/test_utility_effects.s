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
    ldx #9
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
#import "../../common/player_magic_map.s"
#import "../../common/player_magic_feedback.s"
#import "../../common/player_magic_earthquake.s"
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

tc_results: .fill 10, $ff

tpm_msg_calls:    .byte 0
tpm_last_msg_lo:  .byte 0
tpm_last_msg_hi:  .byte 0
tpm_huff_calls:   .byte 0
tpm_last_huff_id: .byte 0
test_mon_slot:    .byte 0
test_expected_stat: .byte 0
test_rng_idx:     .byte 0
pmx_work_idx:     .byte 0
pmx_work_flag:    .byte 0
pmx_work_damage:  .byte 0
test_rng_script:  .fill 160, 1

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

test_rng_range:
    ldx test_rng_idx
    lda test_rng_script,x
    inc test_rng_idx
    rts

test_rng_fill_ones:
    lda #0
    sta test_rng_idx
    ldx #0
    lda #1
!trfo_loop:
    sta test_rng_script,x
    inx
    cpx #160
    bne !trfo_loop-
    rts

test_rng_fill_zeroes:
    lda #0
    sta test_rng_idx
    ldx #0
!trfz_loop:
    sta test_rng_script,x
    inx
    cpx #160
    bne !trfz_loop-
    rts

test_dispel_evil_msg:
    lda #CF_EVIL
    sta pmx_work_flag
    lda zp_player_lvl
    asl
    clc
    adc zp_player_lvl
    sta pmx_work_damage
    jsr eff_dispel_flagged
    bne !tdem_done+
    ldx #HSTR_PIQ_NOTHING
    jsr huff_print_msg
!tdem_done:
    rts

test_start:
    // Test 1: Sense Surroundings follows umoria-style map-area behavior:
    // reveal floors plus adjacent room/corridor walls, but keep untouched
    // solid rock and hidden doors unrevealed.
    jsr tv_setup_dark_room
    :PatchJump(rng_range, test_rng_range)
    jsr test_rng_fill_zeroes
    lda #0
    sta vis_room_revealed

    // Untouched solid rock well outside the mapped room/corridor.
    ldx #5
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #5
    lda (zp_ptr0),y
    and #~FLAG_VISITED & $ff
    sta (zp_ptr0),y

    // Room wall enclosing the mapped dark room.
    ldx #9
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #24
    lda (zp_ptr0),y
    and #~FLAG_VISITED & $ff
    sta (zp_ptr0),y

    // Room floor in the mapped dark room.
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #24
    lda (zp_ptr0),y
    and #~FLAG_VISITED & $ff
    sta (zp_ptr0),y

    // Hidden door on the room wall should stay hidden.
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #19
    lda #TILE_SECRET
    sta (zp_ptr0),y

    // Corridor floor and its wall should both map like umoria's area map.
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    ldx #11
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
    lda (zp_ptr0),y
    and #~FLAG_VISITED & $ff
    sta (zp_ptr0),y

    jsr eff_map_area
    lda vis_room_revealed
    cmp #1
    bne !t1_fail+

    // Solid rock stays dark.
    ldx #5
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #5
    lda (zp_ptr0),y
    and #FLAG_VISITED
    bne !t1_fail+

    // Room wall is revealed.
    ldx #9
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #24
    lda (zp_ptr0),y
    and #FLAG_VISITED
    beq !t1_fail+

    // Room floor is revealed.
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #24
    lda (zp_ptr0),y
    and #FLAG_VISITED
    beq !t1_fail+

    // Hidden door stays hidden.
    ldy #19
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_SECRET
    bne !t1_fail+
    lda (zp_ptr0),y
    and #FLAG_VISITED
    bne !t1_fail+

    // Corridor floor maps.
    ldy #10
    lda (zp_ptr0),y
    and #FLAG_VISITED
    beq !t1_fail+
    ldx #11
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #10
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
    sta tpm_huff_calls
    sta tpm_last_huff_id
    :PatchJump(huff_print_msg, test_huff_print_msg)
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
    lda tpm_huff_calls
    cmp #1
    bne !t2_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PMU_GLYPH_OK
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
    sta tpm_huff_calls
    sta tpm_last_huff_id
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
    lda tpm_huff_calls
    cmp #1
    bne !t3_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PMU_GLYPH_BLOCK
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // Test 4: Create Food replaces any item underfoot and reports success.
!t4:
    jsr tv_setup_dark_room
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(msg_print, test_msg_print)
    lda #0
    sta tpm_msg_calls
    sta tpm_last_msg_lo
    sta tpm_last_msg_hi
    sta tpm_huff_calls
    sta tpm_last_huff_id
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
    bcc !t4_fail+
    jsr pmu_create_food
    bcc !t4_fail+
    lda tpm_huff_calls
    cmp #1
    bne !t4_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PMU_CREATE_FOOD
    bne !t4_fail+
    lda zp_player_x
    ldy zp_player_y
    jsr floor_item_find_at
    bcc !t4_fail+
    lda fi_item_id,x
    cmp #15
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // Test 5: Holy Word matches umoria: full heal, remove fear/poison,
    // restore stats, grant invulnerability, and dispel an evil monster.
!t5:
    jsr tv_setup_dark_room
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(msg_print, test_msg_print)
    :PatchJump(combat_award_xp, test_combat_award_xp)
    :PatchJump(combat_check_levelup, test_combat_check_levelup)
    lda #0
    sta tpm_msg_calls
    sta tpm_last_msg_lo
    sta tpm_last_msg_hi
    sta tpm_huff_calls
    sta tpm_last_huff_id
    lda #23
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #0
    jsr monster_spawn_one
    bcs !t5_spawn_ok+
    lda #$17
    sta tc_results + 4
    jmp test_finish
!t5_spawn_ok:
    stx test_mon_slot
    jsr monster_get_ptr
    jsr test_find_evil_type
    bcs !t5_have_evil_type+
    lda #$19
    sta tc_results + 4
    jmp test_finish
!t5_have_evil_type:
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
    lda #$2c
    sta zp_player_mhp_lo
    sta player_data + PL_MHP_LO
    lda #1
    sta zp_player_mhp_hi
    sta player_data + PL_MHP_HI
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
    lda #0
    sta player_data + PL_RACE
    sta player_data + PL_CLASS
    ldx #0
!t5_seed_stats:
    lda #12
    sta player_data + PL_STR_BASE,x
    inx
    cpx #6
    bcc !t5_seed_stats-
    jsr player_calc_stats
    lda player_data + PL_STR_CUR
    sta test_expected_stat
    lda #3
    sta player_data + PL_STR_CUR
    sta zp_player_str
    jsr eff_holy_word
    lda zp_player_hp_lo
    cmp #$2c
    bne !t5_hp_fail+
    lda zp_player_hp_hi
    cmp #1
    beq !t5_hp_ok+
!t5_hp_fail:
    lda zp_player_hp_hi
    sta tc_results + 4
    jmp test_finish
!t5_hp_ok:
    lda zp_eff_poison
    beq !t5_poison_ok+
    lda #$11
    sta tc_results + 4
    jmp test_finish
!t5_poison_ok:
    lda zp_eff_blind
    cmp #8
    beq !t5_blind_ok+
    lda #$12
    sta tc_results + 4
    jmp test_finish
!t5_blind_ok:
    lda zp_eff_confuse
    cmp #9
    beq !t5_confuse_ok+
    lda #$13
    sta tc_results + 4
    jmp test_finish
!t5_confuse_ok:
    lda eff_fear_timer
    beq !t5_fear_ok+
    lda #$14
    sta tc_results + 4
    jmp test_finish
!t5_fear_ok:
    lda player_data + PL_STR_CUR
    cmp test_expected_stat
    beq !t5_stat_ok+
    lda #$1b
    sta tc_results + 4
    jmp test_finish
!t5_stat_ok:
    lda eff_invuln_timer
    cmp #3
    beq !t5_invuln_ok+
    lda #$1c
    sta tc_results + 4
    jmp test_finish
!t5_invuln_ok:
    lda tpm_huff_calls
    cmp #1
    bne !t5_huff_fail+
    lda tpm_msg_calls
    cmp #1
    beq !t5_huff_count_ok+
    lda #$15
    sta tc_results + 4
    jmp test_finish
!t5_huff_count_ok:
    lda tpm_last_huff_id
    cmp #HSTR_PIQ_VERY_GOOD
    beq !t5_huff_id_ok+
!t5_huff_fail:
    lda #$16
    sta tc_results + 4
    jmp test_finish
!t5_huff_id_ok:
    lda tpm_last_msg_lo
    cmp #<combat_msg_buf
    bne !t5_msg_fail+
    lda tpm_last_msg_hi
    cmp #>combat_msg_buf
    beq !t5_msg_ok+
!t5_msg_fail:
    lda #$1a
    sta tc_results + 4
    jmp test_finish
!t5_msg_ok:
    ldx test_mon_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !t5_monster_ok+
    lda #$18
    sta tc_results + 4
    jmp test_finish
!t5_monster_ok:
    lda #$01
    sta tc_results + 4
    jmp !t6+

    // Test 6: Earthquake full effect marks redraw and can open a wall tile.
!t6:
    jsr tv_setup_dark_room
    :PatchJump(rng_range, test_rng_range)
    :PatchJump(msg_print, test_msg_print)
    jsr test_rng_fill_ones
    lda #0
    sta tpm_msg_calls
    lda #0
    sta vis_room_revealed
    sta turn_scene_dirty
    lda #28
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #18
    sta zp_player_y
    sta player_data + PL_MAP_Y
    lda #0
    sta test_rng_script + 0
    jsr eff_earthquake
    lda vis_room_revealed
    cmp #1
    bne !t6_fail+
    lda turn_scene_dirty
    cmp #1
    bne !t6_fail+
    lda tpm_msg_calls
    cmp #1
    bne !t6_fail+
    lda tpm_last_msg_lo
    cmp #<eq_cast_msg
    bne !t6_fail+
    lda tpm_last_msg_hi
    cmp #>eq_cast_msg
    bne !t6_fail+
    ldx #10
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_FLOOR
    bne !t6_fail+
    lda #$01
    sta tc_results + 5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 5

    // Test 7: Earthquake tile helper removes a floor item and makes a wall.
!t7:
    jsr tv_setup_dark_room
    :PatchJump(rng_range, test_rng_range)
    jsr test_rng_fill_ones
    lda #21
    sta fi_add_x
    lda #11
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
    bcc !t7_fail+
    lda #21
    sta eq_cur_x
    lda #11
    sta eq_cur_y
    lda #0
    sta eq_changed
    lda #9
    sta test_rng_script + 0
    jsr eq_process_tile
    lda eq_changed
    cmp #1
    bne !t7_fail+
    lda #21
    ldy #11
    jsr floor_item_find_at
    bcs !t7_fail+
    ldx #11
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #21
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_WALL_H
    bne !t7_fail+
    lda (zp_ptr0),y
    and #FLAG_HAS_ITEM
    bne !t7_fail+
    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // Test 8: Earthquake tile helper kills an attack-only monster cleanly.
!t8:
    jsr tv_setup_dark_room
    :PatchJump(rng_range, test_rng_range)
    jsr test_rng_fill_ones
    lda #21
    sta ms_spawn_x
    lda #11
    sta ms_spawn_y
    lda #0
    jsr monster_spawn_one
    bcs !t8_spawn_ok+
    jmp !t8_fail+
!t8_spawn_ok:
    stx test_mon_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #6                      // CF_ATTACK_ONLY
    sta (zp_ptr0),y
    lda #21
    sta eq_cur_x
    lda #11
    sta eq_cur_y
    lda #0
    sta eq_changed
    lda #9
    sta test_rng_script + 0
    jsr eq_process_tile
    lda eq_changed
    cmp #1
    bne !t8_fail+
    ldx test_mon_slot
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    bne !t8_fail+
    ldx #11
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #21
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    bne !t8_fail+
    lda #$01
    sta tc_results + 7
    jmp !t9+
!t8_fail:
    lda #$00
    sta tc_results + 7
    jmp test_finish

    // Test 9: Dispel Evil reports no-effect when no evil targets remain.
!t9:
    jsr tv_setup_dark_room
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(msg_print, test_msg_print)
    lda #0
    sta tpm_msg_calls
    sta tpm_last_msg_lo
    sta tpm_last_msg_hi
    sta tpm_huff_calls
    sta tpm_last_huff_id
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    jsr test_dispel_evil_msg
    lda tpm_huff_calls
    cmp #1
    bne !t9_fail+
    lda tpm_last_huff_id
    cmp #HSTR_PIQ_NOTHING
    bne !t9_fail+
    lda tpm_msg_calls
    bne !t9_fail+
    lda #$01
    sta tc_results + 8
    jmp !t10+
!t9_fail:
    lda #$00
    sta tc_results + 8
    jmp !t10+

    // Test 10: Find Doors reveals all secret doors on the map.
!t10:
    jsr tv_setup_dark_room
    lda #0
    sta vis_room_revealed

    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #18
    lda #TILE_SECRET
    sta (zp_ptr0),y

    ldy #19
    lda #TILE_SECRET
    sta (zp_ptr0),y

    jsr eff_find_doors

    lda vis_room_revealed
    cmp #1
    bne !t10_fail+

    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #18
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    bne !t10_fail+
    lda (zp_ptr0),y
    and #FLAG_VISITED
    beq !t10_fail+

    ldy #19
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    cmp #TILE_DOOR_CLOSED
    bne !t10_fail+

    lda #$01
    sta tc_results + 9
    jmp test_finish
!t10_fail:
    lda #$00
    sta tc_results + 9
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
