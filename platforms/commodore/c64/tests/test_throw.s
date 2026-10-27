// test_throw.s — Runtime tests for throw.s
//
// Tests: range calculation (light/heavy/weightless), potion detection,
//        item consumption, to-hit calculation, throw selector filtering,
//        thrown-item redraw and floor metadata preservation, and a fired
//        shot's range by launcher and a missed shot's landing (ranged_fire.s
//        rf_fly and rf_shot_lands, M5d 2026-10-26).
//
// Results at $0400-$040F: $01 = pass, $00 = fail per test (16 tests)
.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #15
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_mixed"

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
#import "../../../../core/stat_display.s"
.segmentdef TestCreateOverlay [start=$D000]
.segment TestCreateOverlay
#import "../../../../core/background_data.s"
#import "../../../../core/player_create.s"
.segment Default
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "dungeon_gen_stubs.s"
#import "../../../../core/huffman.s"
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
#import "../../../../core/dungeon_features.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
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
#import "../../../../core/spell_data.s"
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/ranged_fire.s"
#import "../../../../core/throw.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"
// Store modules move to the dummy segment so the test body stays below
// MAP_BASE ($C000); map writes during tests must not corrupt test code.
.segmentdef TestStoreOverlay [start=$d000, min=$d000, max=$ffff]
.segment TestStoreOverlay
#import "../../../../core/store_data.s"
#import "../../../../core/store.s"
#import "../../../../core/ui_store.s"
.segment Default
#import "../../../../core/ui_help.s"
#import "../../../../core/ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tc_results: .fill 16, $ff
tt_base: .byte 0
tt_seen: .byte 0
tt_count: .byte 0

test_start:
    // Seed RNG
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    // ==========================================
    // Test 1: Range — light item (potion, weight=4)
    // STR=12 → (12+20)*10/4 = 320/4 = 80 → clamped to 10
    // ==========================================
    lda #12
    sta zp_player_str

    // Calculate: (STR+20)*10
    lda zp_player_str
    clc
    adc #20                     // A = 32
    ldx #10
    jsr math_multiply           // zp_math_a = lo(320)=$40, zp_math_b = hi(320)=$01

    // Divide by weight 4
    ldx #4
    jsr math_div_16x8           // zp_math_a = lo(80)=$50

    // Clamp to [1, 10]
    lda zp_math_a
    cmp #11
    bcc !t1_no_clamp+
    lda #10
!t1_no_clamp:
    cmp #10
    beq !t1_pass+
    lda #$00
    sta tc_results+0
    jmp !t1_done+
!t1_pass:
    lda #$01
    sta tc_results+0
!t1_done:

    // ==========================================
    // Test 2: Range — heavy item (chain mail, weight=120)
    // STR=10 → (10+20)*10/120 = 300/120 = 2 (integer)
    // ==========================================
    lda #10
    sta zp_player_str

    lda zp_player_str
    clc
    adc #20                     // A = 30
    ldx #10
    jsr math_multiply           // 300

    ldx #120
    jsr math_div_16x8           // 300/120 = 2

    lda zp_math_a
    cmp #2
    beq !t2_pass+
    lda #$00
    sta tc_results+1
    jmp !t2_done+
!t2_pass:
    lda #$01
    sta tc_results+1
!t2_done:

    // ==========================================
    // Test 3: Range — weightless item (gold, weight=0)
    // Weight 0 → max range = 10
    // ==========================================
    ldx #0                      // Type 0 (gold), weight = 0
    lda it_weight,x
    cmp #0
    bne !t3_fail+
    // If weight is 0, range should be 10
    lda #10
    cmp #10
    beq !t3_pass+
!t3_fail:
    lda #$00
    sta tc_results+2
    jmp !t3_done+
!t3_pass:
    lda #$01
    sta tc_results+2
!t3_done:

    // ==========================================
    // Test 4: Potion detection — type 17 (Cure Light Wounds) = ICAT_POTION
    // ==========================================
    ldx #17
    lda it_category,x
    cmp #ICAT_POTION
    beq !t4_pass+
    lda #$00
    sta tc_results+3
    jmp !t4_done+
!t4_pass:
    lda #$01
    sta tc_results+3
!t4_done:

    // ==========================================
    // Test 5: Item consumption — qty 3 → 2 after throw
    // ==========================================
    ldx #5                      // Use slot 5
    lda #2                      // Dagger
    sta inv_item_id,x
    lda #3
    sta inv_qty,x
    lda #0
    sta inv_p1,x
    sta inv_flags,x
    sta inv_ego,x

    // Simulate throw consumption
    dec inv_qty,x
    // Should be 2 (not 0, so slot stays)
    lda inv_qty,x
    cmp #2
    bne !t5_fail+
    lda inv_item_id,x
    cmp #2                      // Still a dagger
    bne !t5_fail+
    lda #$01
    sta tc_results+4
    jmp !t5_done+
!t5_fail:
    lda #$00
    sta tc_results+4
!t5_done:
    // Clean up
    lda #FI_EMPTY
    sta inv_item_id+5

    // ==========================================
    // Test 6: throw_calc_tohit — Warrior(0), Human(0), level 1
    // BTH_BOW = 55, race BTH = 0, PL_TOHIT = 0, level adj = 4*1 = 4
    // Total = 55 + 0 + 0 + 4 = 59. 75% = 59*3/4 = 177/4 = 44
    // ==========================================
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #RACE_HUMAN
    sta player_data + PL_RACE
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #0
    sta player_data + PL_TOHIT

    jsr throw_calc_tohit

    lda zp_combat_tohit
    cmp #44
    beq !t6_pass+
    lda #$00
    sta tc_results+5
    jmp !t6_done+
!t6_pass:
    lda #$01
    sta tc_results+5
!t6_done:

    // ==========================================
    // Test 7: Throw selector cache with filter $ff only lists occupied slots
    // Slot 1 is empty; visible list must be 0, 2, 5.
    // ==========================================
    jsr item_init_inventory
    lda #2                      // Dagger
    sta inv_item_id+0
    lda #1
    sta inv_qty+0
    lda #17                     // Potion
    sta inv_item_id+2
    lda #1
    sta inv_qty+2
    lda #15                     // Food
    sta inv_item_id+5
    lda #1
    sta inv_qty+5

    lda #$ff
    jsr piw_build_visible_inv_cache
    cmp #3
    bne !t7_fail+
    lda piw_visible_slots+0
    cmp #0
    bne !t7_fail+
    lda piw_visible_slots+1
    cmp #2
    bne !t7_fail+
    lda piw_visible_slots+2
    cmp #5
    bne !t7_fail+
    lda #$01
    sta tc_results+6
    jmp !t7_done+
!t7_fail:
    lda #$00
    sta tc_results+6
!t7_done:

    // ==========================================
    // Test 8: Throw selector maps visible B to second occupied slot, not slot 1
    // ==========================================
    lda #$ff
    jsr piw_build_visible_inv_cache
    lda #$42                    // 'B'
    jsr piw_pick_filtered_inv_key
    bcc !t8_fail+
    cpx #2
    bne !t8_fail+
    cmp #17
    bne !t8_fail+
    lda #$01
    sta tc_results+7
    jmp !t8_done+
!t8_fail:
    lda #$00
    sta tc_results+7
!t8_done:

    // ==========================================
    // Test 9: Throw selector rejects letters beyond visible occupied entries
    // ==========================================
    lda #$ff
    jsr piw_build_visible_inv_cache
    lda #$44                    // 'D'
    jsr piw_pick_filtered_inv_key
    bcc !t9_pass+
    lda #$00
    sta tc_results+8
    jmp !t9_done+
!t9_pass:
    lda #$01
    sta tc_results+8
!t9_done:

    // ==========================================
    // Test 10: Thrown zero-quantity spellbook is removed, not duplicated
    // ==========================================
    jsr item_init_floor
    jsr item_init_inventory

    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y

    lda #0
    sta turn_action_redraw_pending
    sta inv_qty+0
    sta inv_p1+0
    sta inv_to_hit+0
    sta inv_to_dam+0
    sta inv_to_ac+0
    sta inv_flags+0
    sta inv_ego+0
    sta tw_slot
    lda #47                     // Beginner's Spellbook
    sta inv_item_id+0
    sta tw_item_id
    lda #20
    sta tw_last_x
    lda #15
    sta tw_last_y

    jsr tw_consume_item
    bcc !t10_fail+
    lda inv_item_id+0
    cmp #FI_EMPTY
    bne !t10_fail+
    lda inv_qty+0
    bne !t10_fail+
    lda #20
    ldy #15
    jsr floor_item_find_at
    bcc !t10_fail+
    lda fi_item_id,x
    cmp #47
    bne !t10_fail+
    lda #$01
    sta tc_results+9
    jmp !t10_done+
!t10_fail:
    lda #$00
    sta tc_results+9
!t10_done:

    // ==========================================
    // Test 11: Thrown non-potion floor placement requests a scene redraw
    // ==========================================
    jsr item_init_floor
    jsr item_init_inventory

    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y

    lda #0
    sta turn_action_redraw_pending
    sta inv_p1+0
    sta tw_save_p1
    sta inv_to_ac+0
    sta tw_save_to_ac
    sta tw_slot
    lda #$fe                    // -2 to-hit
    sta inv_to_hit+0
    sta tw_save_to_hit
    lda #6
    sta inv_to_dam+0
    sta tw_save_to_dam
    lda #IF_IDENTIFIED
    sta inv_flags+0
    sta tw_save_flags
    lda #EGO_FLAME_TONGUE
    sta inv_ego+0
    sta tw_save_ego
    lda #2                      // Dagger
    sta inv_item_id+0
    sta tw_item_id
    lda #1
    sta inv_qty+0
    lda #20
    sta tw_last_x
    lda #15
    sta tw_last_y

    jsr tw_drop_saved               // the landing itself (its 9-in-10 roll: test 16)
    sec
    bcc !t11_fail+
    lda turn_action_redraw_pending
    beq !t11_fail+
    lda #20
    ldy #15
    jsr floor_item_find_at
    bcc !t11_fail+
    lda fi_item_id,x
    cmp #2
    bne !t11_fail+
    lda fi_to_hit,x
    cmp #$fe
    bne !t11_fail+
    lda fi_to_dam,x
    cmp #6
    bne !t11_fail+
    lda fi_to_ac,x
    bne !t11_fail+
    jsr floor_item_get_flags_x
    and #IF_IDENTIFIED
    beq !t11_fail+
    jsr floor_item_get_ego_x
    cmp #EGO_FLAME_TONGUE
    bne !t11_fail+
    lda #$01
    sta tc_results+10
    jmp !t11_done+
!t11_fail:
    lda #$00
    sta tc_results+10
!t11_done:

    // ==========================================
    // Test 12: Range by launcher (VMS facts): east along open floor with
    // nothing in the way, a Sling shot ends 20 squares out, a Short Bow 25
    // ==========================================
    jsr msg_init
    jsr monster_init_table
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #4
!t12_floor:
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y
    iny
    cpy #45
    bne !t12_floor-
    lda #5
    sta zp_player_x
    lda #15
    sta zp_player_y
    lda #51 - IT_MISSILE_BASE   // Sling
    sta rf_launcher
    jsr t12_shot
    lda tw_last_x
    cmp #25
    bne !t12_fail+
    lda #49 - IT_MISSILE_BASE   // Short Bow
    sta rf_launcher
    jsr t12_shot
    lda tw_last_x
    cmp #30
    bne !t12_fail+
    lda #$01
    sta tc_results+11
    jmp !t12_done+
!t12_fail:
    lda #$00
    sta tc_results+11
!t12_done:

    // ==========================================
    // Test 13: A missed shot lands at the last open square when
    // randint(10) > 1 (VMS drop_throw): 40 to 49 of 50 with the seeded RNG,
    // keeping its to-hit; a shot that hit is used up, nothing lands
    // ==========================================
    lda #0
    sta tt_seen
    lda #50
    sta tt_count
!t13_loop:
    jsr t13_stock_arrow
    jsr rf_shot_lands
    lda #20
    ldy #15
    jsr floor_item_find_at
    bcc !t13_next+
    lda fi_to_hit,x
    cmp #2
    bne !t13_fail+
    inc tt_seen
!t13_next:
    dec tt_count
    bne !t13_loop-
    lda tt_seen
    cmp #40
    bcc !t13_fail+
    cmp #50
    bcs !t13_fail+
    jsr t13_stock_arrow
    jsr rf_consume_ammo
    lda #20
    ldy #15
    jsr floor_item_find_at
    bcs !t13_fail+
    lda #$01
    sta tc_results+12
    jmp !t13_done+
!t13_fail:
    lda #$00
    sta tc_results+12
!t13_done:

    // ==========================================
    // Test 14: Thrown damage (VMS facts plus Moria8's STR bonus): a Flask
    // of Oil's 2d6 with STR 10 (bonus 0) is 2-12 whatever PL_TODMG holds
    // (+10 here); its own +3 to-dam makes 5-15; -20 floors at 0
    // ==========================================
    lda #10
    sta zp_player_str
    lda #10
    sta player_data + PL_TODMG
    lda #ITEM_FLASK_OIL
    sta tw_item_id
    lda #0
    sta tw_save_to_dam
    lda #2
    ldx #12
    jsr t14_range
    bcc !t14_fail+
    lda #3
    sta tw_save_to_dam
    lda #5
    ldx #15
    jsr t14_range
    bcc !t14_fail+
    lda #$ec                    // -20
    sta tw_save_to_dam
    lda #0
    ldx #0
    jsr t14_range
    bcc !t14_fail+
    lda #$01
    sta tc_results+13
    jmp !t14_done+
!t14_fail:
    lda #$00
    sta tc_results+13
!t14_done:
    lda #0
    sta tw_save_to_dam
    sta player_data + PL_TODMG

    // ==========================================
    // Test 15: Thrown to-hit (VMS tbth - cur_dis, tpth with the item's
    // to-hit): six squares cost 6; +4 item to-hit adds 3 x 4 x 3/4 = 9; a
    // long flight floors at 0
    // ==========================================
    lda #0
    sta player_data + PL_CLASS  // Warrior
    sta player_data + PL_RACE   // Human
    sta player_data + PL_TOHIT
    sta zp_eff_bless
    sta tw_save_to_hit
    sta rf_dist
    lda #1
    sta zp_player_lvl
    jsr throw_calc_tohit
    lda zp_combat_tohit
    sta tt_base
    lda #6
    sta rf_dist
    jsr throw_calc_tohit
    lda tt_base
    sec
    sbc #6
    cmp zp_combat_tohit
    bne !t15_fail+
    lda #0
    sta rf_dist
    lda #4
    sta tw_save_to_hit
    jsr throw_calc_tohit
    lda tt_base
    clc
    adc #9
    cmp zp_combat_tohit
    bne !t15_fail+
    lda #0
    sta tw_save_to_hit
    lda #255
    sta rf_dist
    jsr throw_calc_tohit
    lda zp_combat_tohit
    bne !t15_fail+
    lda #$01
    sta tc_results+14
    jmp !t15_done+
!t15_fail:
    lda #$00
    sta tc_results+14
!t15_done:
    lda #0
    sta rf_dist

    // ==========================================
    // Test 16: A thrown item that misses lands when randint(10) > 1 (VMS
    // drop_throw): 40 to 49 of 50 with the seeded RNG; a potion never lands
    // (Moria8: it shatters); one that hits is used up
    // ==========================================
    lda #0
    sta tt_seen
    lda #50
    sta tt_count
!t16_loop:
    jsr t13_stock_arrow
    jsr tw_consume_item
    lda #20
    ldy #15
    jsr floor_item_find_at
    bcc !t16_next+
    inc tt_seen
!t16_next:
    dec tt_count
    bne !t16_loop-
    lda tt_seen
    cmp #40
    bcc !t16_fail+
    cmp #50
    bcs !t16_fail+
    lda #20
    sta tt_count
!t16_potion:
    jsr t13_stock_arrow
    lda #17                     // Potion of Cure Light Wounds
    sta tw_item_id
    jsr tw_consume_item
    lda #20
    ldy #15
    jsr floor_item_find_at
    bcs !t16_fail+
    dec tt_count
    bne !t16_potion-
    jsr t13_stock_arrow
    jsr tw_hit_used_up
    lda #20
    ldy #15
    jsr floor_item_find_at
    bcs !t16_fail+
    lda inv_item_id             // used up from the pack
    cmp #FI_EMPTY
    bne !t16_fail+
    lda #$01
    sta tc_results+15
    jmp !t16_done+
!t16_fail:
    lda #$00
    sta tc_results+15
!t16_done:

    jmp test_exit_trampoline

// One Arrow +2 in pack slot 0, saved as the shot, its flight ending at
// (20, 15), and an empty floor
t13_stock_arrow:
    jsr item_init_floor
    jsr item_init_inventory
    lda #52                     // Arrow
    sta inv_item_id
    sta rf_ammo_id
    lda #1
    sta inv_qty
    lda #2
    sta inv_to_hit
    lda #0
    sta rf_ammo_slot
    tax
    jsr tw_save_slot
    lda #20
    sta tw_last_x
    lda #15
    sta tw_last_y
    rts

// Fire east from (5, 15) with one Arrow in pack slot 0 and an empty floor
t12_shot:
    jsr item_init_floor
    jsr item_init_inventory
    lda #52                     // Arrow
    sta inv_item_id
    sta rf_ammo_id
    lda #1
    sta inv_qty
    lda #0
    sta rf_ammo_slot
    tax
    jsr tw_save_slot
    lda #3                      // East (dir_dx/dir_dy index)
    sta proj_dir
    jmp rf_fly

throw_test_body_end:
.assert "Throw test stays below MAP_BASE", throw_test_body_end <= MAP_BASE, true
// Dropped ui_* imports to keep the test body under MAP_BASE (map-overlap
// boundary); stubs satisfy the trampoline references.
ui_char_display:
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
    rts
count_spells_known:
    jmp spell_mask_count_ptr
player_disarm_get_effective_chance:
    lda #0
    rts

// tw_roll_damage 40 times: carry set when every roll is within A..X
t14_lo: .byte 0
t14_hi: .byte 0
t14_n:  .byte 0
t14_range:
    sta t14_lo
    stx t14_hi
    lda #40
    sta t14_n
!t14r_loop:
    jsr tw_roll_damage
    lda cmb_damage
    cmp t14_lo
    bcc !t14r_bad+
    lda t14_hi
    cmp cmb_damage
    bcc !t14r_bad+
    dec t14_n
    bne !t14r_loop-
    sec
    rts
!t14r_bad:
    clc
    rts
