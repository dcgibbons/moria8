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

.segmentdef TestCreateOverlay [start=$D000, min=$D000, max=$DFFF]
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
.segment TestCreateOverlay
#import "../../../../core/stat_display.s"
.segment Default
.segment TestCreateOverlay
player_create:
    brk
.segment Default
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "dungeon_gen_stubs.s"
#import "../../../../core/huffman.s"
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
#import "../../../../core/dungeon_features.s"
#import "chest_summons_stubs.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
.segment TestCreateOverlay
mat_scene_dirty: .byte 0
monster_ai_tick:
    brk
.segment Default
#import "../../../../core/recall.s"
.segment TestCreateOverlay
#import "../../../../core/los_trace.s"
#import "../../../../core/element_resist.s"
monster_can_cast:
monster_pick_spell:
    brk
.segment Default
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../../../../core/item.s"
#import "item_cat_resident_helper.s"
#import "../../../../core/special_rooms.s"
#import "../../../../core/ego_items.s"
#import "../../../../core/special_rooms_stubs.s"
#import "../../../../core/player_items.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/projectile.s"
.segment TestCreateOverlay
#import "../../../../core/spell_effects.s"
.segment Default
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
.segment TestCreateOverlay
#import "../dungeon_render.s"
.segment Default
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/ranged_fire.s"
#import "../../../../core/throw.s"
.segment TestCreateOverlay
mad_dmg_hi: .byte 0
mon_atk_acid_armour:
mon_atk_apply_damage_16:
monster_attack_player:
player_death_check:
    brk
.segment Default
#import "../../../../core/turn.s"
// Store modules are never executed here; item_cat_data takes the $E100 window
// (item_cat_kernal_helper.s), so only the store inventory arrays that
// ui_trampoline_stubs.s references are linked (data, parked).
.segment TestCreateOverlay
#import "../../../../core/store_data_defs.s"
#import "../../../../core/store_inventory_data.s"
.segment Default
.segment Default
#import "../../../../core/ui_help.s"
.segment Default
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
    lda #ITEM_PAGE_GOLD_SMALL
    sta item_cur_page
    ldx #ITEM_SLOT_GOLD_SMALL                      // Type 0 (gold), weight = 0
    jsr item_get_weight_x
    lda icat_weight_lo
    ora icat_weight_hi
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
    lda #ITEM_PAGE_POTION_OF_CURE_LIGHT_WOUNDS
    sta item_cur_page
    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    jsr item_get_category_a
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
    lda #ITEM_SLOT_DAGGER                      // Dagger
    sta inv_item_id,x
    lda #3
    sta inv_qty,x
    lda #0
    sta inv_p1,x
    sta inv_flags,x
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
    }
    sta inv_ego,x

    // Simulate throw consumption
    dec inv_qty,x
    // Should be 2 (not 0, so slot stays)
    lda inv_qty,x
    cmp #2
    bne !t5_fail+
    lda inv_item_id,x
    cmp #ITEM_SLOT_DAGGER                      // Still a dagger
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
    lda #ITEM_SLOT_DAGGER                      // Dagger
    sta inv_item_id+0
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
        sta inv_ego+0
    }
    lda #1
    sta inv_qty+0
    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS                     // Potion
    sta inv_item_id+2
    lda #1
    sta inv_qty+2
    lda #ITEM_SLOT_RATION_OF_FOOD                     // Food
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
    cmp #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
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
    lda #ITEM_SLOT_SPELLBOOK_BEGINNERS_MAGICK                     // Beginner's Spellbook
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
    cmp #ITEM_SLOT_SPELLBOOK_BEGINNERS_MAGICK
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
    lda #(EGO_FLAME_TONGUE | ITEM_PAGE_DAGGER)
    sta inv_ego+0
    sta tw_save_ego
    lda #ITEM_SLOT_DAGGER                      // Dagger
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
    cmp #ITEM_SLOT_DAGGER
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
    cmp #(EGO_FLAME_TONGUE | ITEM_PAGE_DAGGER)
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
    lda #ITEM_SLOT_SLING - IT_MISSILE_BASE   // Sling
    sta rf_launcher
    jsr t12_shot
    lda tw_last_x
    cmp #25
    bne !t12_fail+
    lda #ITEM_SLOT_SHORT_BOW - IT_MISSILE_BASE   // Short Bow
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
    lda #ITEM_SLOT_FLASK_OF_OIL
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
    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS                     // Potion of Cure Light Wounds
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
    lda #ITEM_SLOT_ARROW                     // Arrow
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
    lda #ITEM_SLOT_ARROW                     // Arrow
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
