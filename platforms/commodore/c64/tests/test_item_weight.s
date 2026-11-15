// test_item_weight.s — VMS Moria 4.8's weight limit (core/inv_add.s
// inv_add_carried) and the floor pickup's refusal (core/item.s item_pickup).
//
// Oracle: VMS Moria 4.8 misc.inc weight_limit (:2589-2596: cstr x
// player_weight_cap 130 + py.misc.wt, capped at 3000 tenths of a pound) and
// inven_check_weight (:2600-2611: the pack and equipment plus the new item
// must not pass it); moria.inc:2118 refuses the pickup with "You can't carry
// that much weight." Moria8's body weight (PL_WEIGHT) is 0. Every expected
// weight is written by hand from it_weight (tenths of a pound).
//
// Results at $0400-$0404: $01 = pass, $00 = fail per test (5 tests)
.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

// Bootstrap + exit trampoline at $080E (right after BASIC stub).
// MUST be in "Test Code" segment so run_tests.sh sets breakpoint here (below $A000).
.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    sei                         // Disable IRQs during copy
    :BankOutBasic()             // Ensure BASIC ROM off (tc_results in $A000+)
    ldx #5-1
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0830 "Main"

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
.segment Default
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
#import "../../../../core/monster_ai.s"
#import "../../../../core/recall.s"
.segment TestCreateOverlay
#import "../../../../core/monster_magic.s"
.segment Default
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../../../../core/item.s"
#import "item_cat_resident_helper.s"
#import "../../../../core/special_rooms.s"
#import "../../../../core/ego_items.s"
#import "../../../../core/special_rooms_stubs.s"
#import "../../../../core/player_items.s"
#import "../../../../core/item_exchange.s"
#import "../../../../core/spell_data.s"
.segment Default
#import "../../../../core/projectile.s"
.segment Default
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
.segment TestCreateOverlay
#import "../../../../core/spell_effects.s"
.segment Default
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
.segment Default
#import "../dungeon_render.s"
.segment Default
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
.segment Default
#import "../../../../core/scene_mat_tile.s"
.segment Default
eff_fear_timer: .byte 0
monster_attack_player:
player_update_hunger_state:
    sec
    rts
// The production damage entries' shape (monster_attack.s): 8-bit, or 16-bit
// with the high byte in mad_dmg_hi (breath); acid breath's armour damage
// finds no armour here.
mad_dmg_hi: .byte 0
mon_atk_acid_armour:
    clc
    rts
mon_atk_apply_damage:
    lda #0
    sta mad_dmg_hi
mon_atk_apply_damage_16:
    lda zp_player_hp_lo
    sec
    sbc zp_combat_dmg
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sbc mad_dmg_hi
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    bmi !mad_dead+
    ora zp_player_hp_lo
    beq !mad_dead+
    clc
    rts
!mad_dead:
    sec
    rts
player_death_check:
    lda zp_player_hp_hi
    bmi !pdc_dead+
    ora zp_player_hp_lo
    beq !pdc_dead+
    rts
!pdc_dead:
    lda zp_game_flags
    ora #$01
    sta zp_game_flags
    rts
#define C64_TEST_FULL_ITEMDESC_STUB
ui_help_display:
    rts
#import "../../../../core/ui_trampoline_stubs.s"

// Store modules are never executed here; item_cat_data takes the $E100 window
// (item_cat_kernal_helper.s), so only the store inventory arrays that
// ui_trampoline_stubs.s references are linked (data, parked).
.segment Default
#import "../../../../core/store_data_defs.s"
#import "../../../../core/store_inventory_data.s"
.segment Default

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test result buffer — copy to $0400 at end (msg_print clobbers $0400)
tc_results: .fill 5, $ff
tx_ok: .byte 0

// tx_begin — a test starts passing, with an empty inventory and clear message rows
tx_begin:
    lda #1
    sta tx_ok
    jsr item_init_inventory
    jsr msg_clear
    lda #0
    sta zp_msg_flags
    rts
tx_fail:
    lda #0
    sta tx_ok
    rts

// tx_field_ptr — zp_ptr0 = &inv_item_id[X] (16-bit: slot + 7 * 33 > 255)
tx_field_ptr:
    sta zp_ptr2
    sty zp_ptr2_hi
    txa
    clc
    adc #<inv_item_id
    sta zp_ptr0
    lda #>inv_item_id
    adc #0
    sta zp_ptr0_hi
    lda #0
    sta tx_field
    rts
// tx_field_next — advance zp_ptr0 to the same slot of the next array
tx_field_next:
    lda zp_ptr0
    clc
    adc #TOTAL_INV_SLOTS
    sta zp_ptr0
    bcc !done+
    inc zp_ptr0_hi
!done:
    inc tx_field
    lda tx_field
    cmp #8
    rts
tx_field: .byte 0

// tx_seed — copy the 8-field record at A/Y (id, qty, p1, to_hit, to_dam,
// to_ac, flags, ego) into inventory slot X.
tx_seed:
    jsr tx_field_ptr
!seed:
    ldy tx_field
    lda (zp_ptr2),y
    ldy #0
    sta (zp_ptr0),y
    jsr tx_field_next
    bne !seed-
    jmp inven_recalc_weight
// tx_slot_is — Z set when slot X holds exactly the record at A/Y
tx_slot_is:
    jsr tx_field_ptr
!cmp:
    ldy tx_field
    lda (zp_ptr2),y
    ldy #0
    cmp (zp_ptr0),y
    bne !done+
    jsr tx_field_next
    bne !cmp-
    lda #0                  // Z = 1: every field matched
!done:
    rts
// tx_row_is — Z set when message row X (0/1) starts with the string at A/Y
// and the cell after it is blank
tx_row_is:
    sta zp_ptr2
    sty zp_ptr2_hi
    lda tx_row_lo,x
    sta zp_ptr0
    lda tx_row_hi,x
    sta zp_ptr0_hi
    ldy #0
!cmp:
    lda (zp_ptr2),y
    beq !end+
    cmp (zp_ptr0),y
    bne !done+
    iny
    bne !cmp-
!end:
    lda (zp_ptr0),y
    cmp #$20
!done:
    rts
tx_row_lo: .byte <SCREEN_RAM, <(SCREEN_RAM + 40)
tx_row_hi: .byte >SCREEN_RAM, >(SCREEN_RAM + 40)

.macro EXPECT_A(value) {
    cmp #value
    beq !ok+
    jsr tx_fail
!ok:
}
.macro EXPECT_MEM(addr, value) {
    lda addr
    cmp #value
    beq !ok+
    jsr tx_fail
!ok:
}
.macro EXPECT_CS() {
    bcs !ok+
    jsr tx_fail
!ok:
}
.macro EXPECT_CC() {
    bcc !ok+
    jsr tx_fail
!ok:
}
.macro EXPECT_SLOT(slot, record) {
    lda #<record
    ldy #>record
    ldx #slot
    jsr tx_slot_is
    beq !ok+
    jsr tx_fail
!ok:
}
.macro EXPECT_ROW(row, text) {
    lda #<text
    ldy #>text
    ldx #row
    jsr tx_row_is
    beq !ok+
    jsr tx_fail
!ok:
}
.macro EXPECT_ROW_BLANK(row) {
    lda SCREEN_RAM + row * 40
    cmp #$20
    beq !ok+
    jsr tx_fail
!ok:
}
.macro SEED(slot, record) {
    lda #<record
    ldy #>record
    ldx #slot
    jsr tx_seed
}
// Combat stats from equipment alone (base stats give no adjustment).
.macro EXPECT_STATS(tohit, todam, ac) {
    :EXPECT_MEM(player_data + PL_TOHIT, tohit)
    :EXPECT_MEM(player_data + PL_TODMG, todam)
    :EXPECT_MEM(player_data + PL_AC, ac)
}
.macro END_TEST(n) {
    lda tx_ok
    sta tc_results + n
}
// Stuff the KERNAL keyboard buffer: a selection key, then SPACE for -more-.
.macro KEYS(key) {
    lda #2
    sta $c6
    lda #key
    sta $0277
    lda #$20
    sta $0278
}

// Records: id, qty, p1, to_hit, to_dam, to_ac, flags, ego
rec_empty:      .byte FI_EMPTY, 0, 0, 0, 0, 0, 0, 0
rec_swords20:   .byte 4, 20, 0, 0, 0, 0, 0, 0     // Long swords, 5.0 lb x 20 = 1000
rec_swords59:   .byte 4, 59, 0, 0, 0, 0, 0, 0     // 5.0 lb x 59 = 2950
rec_armor2:     .byte 7, 2, 0, 0, 0, 0, 0, 0      // 8.0 lb x 2 = 160
rec_chain:      .byte 8, 1, 0, 0, 0, 0, 0, 0      // Chain mail, 12.0 lb
rec_robe:       .byte 6, 1, 0, 0, 0, 0, 0, 0      // 2.0 lb
rec_potions12:  .byte 17, 12, 0, 0, 0, 0, 0, 0    // 0.4 lb x 12 = 4.8 lb
rec_potion:     .byte 17, 1, 0, 0, 0, 0, 0, 0

// Messages, as the player reads them
s_too_heavy: .text "You can't carry that much weight." ; .byte 0

test_start:
    ldx #5 - 1
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-
    lda #1
    sta zp_player_dlvl
    sta zp_light_radius
    jsr msg_init
    lda #200
    sta zp_player_hp_lo
    sta zp_player_mhp_lo
    lda #0
    sta zp_player_hp_hi
    sta zp_player_mhp_hi
    sta player_data + PL_WEIGHT
    lda #RACE_HUMAN
    sta player_data + PL_RACE
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    ldx #STAT_COUNT - 1
    lda #10
!set_base_stats:
    sta player_data + PL_STR_BASE,x
    dex
    bpl !set_base_stats-
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    jsr player_calc_stats               // STR 10: the limit is 1300

    // ==========================================================
    // Test 1: STR 10, 128.0 lb carried (pack 116.0, chain mail worn 12.0):
    // a 3.0 lb item (131.0 > 130.0) is refused with X = the refusal, and
    // nothing moves.
    // ==========================================================
    jsr tw_seed_1280
    lda #10                             // Soft leather armor, 3.0 lb
    ldx #1
    jsr tw_add
    :EXPECT_CC()
    cpx #HSTR_UIS_TOO_HEAVY
    beq !ok+
    jsr tx_fail
!ok:
    :EXPECT_SLOT(2, rec_empty)
    :END_TEST(0)

    // ==========================================================
    // Test 2: the limit itself is allowed: a 2.0 lb item makes exactly
    // 130.0 lb and goes to the first empty slot.
    // ==========================================================
    jsr tw_seed_1280
    lda #6                              // Robe, 2.0 lb
    ldx #1
    jsr tw_add
    :EXPECT_CS()
    :EXPECT_SLOT(2, rec_robe)
    :END_TEST(1)

    // ==========================================================
    // Test 3: picking up a 3.0 lb item at 128.0 lb of 130.0: no turn, the
    // item stays where it lies, the pack is unchanged, and the player reads
    // "You can't carry that much weight."
    // ==========================================================
    jsr tw_seed_1280
    jsr item_init_floor
    ldx #12
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #TILE_FLOOR | FLAG_LIT | FLAG_VISITED
    sta (zp_ptr0),y
    lda #20
    sta zp_player_x
    sta fi_add_x
    lda #12
    sta zp_player_y
    sta fi_add_y
    lda #10
    ldx #1
    jsr tw_fields
    jsr floor_item_add
    :KEYS($20)
    jsr item_pickup
    :EXPECT_CC()
    :EXPECT_MEM(fi_item_id, 10)
    :EXPECT_SLOT(2, rec_empty)
    :EXPECT_ROW(0, s_too_heavy)
    :END_TEST(2)

    // ==========================================================
    // Test 4: STR 18/100 caps at 3000, not 118 x 130 = 15340: at 295.0 lb,
    // 13 potions (5.2 lb: 300.2) are refused and 12 (4.8 lb: 299.8) taken.
    // ==========================================================
    jsr tx_begin
    lda #118
    sta player_data + PL_STR_CUR
    :SEED(0, rec_swords59)
    lda #17
    ldx #13
    jsr tw_add
    :EXPECT_CC()
    cpx #HSTR_UIS_TOO_HEAVY
    beq !ok+
    jsr tx_fail
!ok:
    lda #17
    ldx #12
    jsr tw_add
    :EXPECT_CS()
    :EXPECT_SLOT(1, rec_potions12)
    :END_TEST(3)

    // ==========================================================
    // Test 5: a full pack light enough still refuses as before, with the
    // pack-full message (VMS inven_check_num), and a stacking item still
    // joins its stack there.
    // ==========================================================
    jsr tx_begin
    :SEED(0, rec_potion)
    ldx #MAX_INV_SLOTS - 1              // slots 1-21: a dagger each
!fill:
    lda #2
    sta inv_item_id,x
    lda #1
    sta inv_qty,x
    dex
    bne !fill-
    lda #6                              // a robe: no slot
    ldx #1
    jsr tw_add
    :EXPECT_CC()
    cpx #HSTR_UIS_PACK_FULL
    beq !ok+
    jsr tx_fail
!ok:
    lda #17                             // a potion: onto slot 0's
    ldx #1
    jsr tw_add
    :EXPECT_CS()
    :EXPECT_MEM(inv_qty, 2)
    :END_TEST(4)

    jmp test_exit_trampoline

// tw_seed_1280 — a passing test with STR 10 and 128.0 lb carried: long
// swords and two armours in slots 0-1, chain mail worn.
tw_seed_1280:
    jsr tx_begin
    lda #10
    sta player_data + PL_STR_CUR
    :SEED(0, rec_swords20)
    :SEED(1, rec_armor2)
    :SEED(EQUIP_BODY, rec_chain)
    rts

// tw_fields — fi_add_id = A, fi_add_qty = X, no enchantment, flags or ego.
tw_fields:
    sta fi_add_id
    stx fi_add_qty
    lda #0
    sta fi_add_p1
    sta fi_add_to_hit
    sta fi_add_to_dam
    sta fi_add_to_ac
    sta fi_add_flags
    sta fi_add_ego
    rts
// tw_add — inv_add_carried of A x X.
tw_add:
    jsr tw_fields
    jmp inv_add_carried

// Link-satisfaction stubs, as in test_item.s (never called here).
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

item_weight_test_body_end:
.assert "Item weight test stays below MAP_BASE", item_weight_test_body_end <= MAP_BASE, true
