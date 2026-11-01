// test_item_exchange.s — SHIFT+X weapon exchange (core/item_exchange.s) and
// the `w` cursed-target refusal (core/player_item_commands.s item_wear).
//
// Oracle: VMS Moria 4.8 moria.inc switch_weapon (:616-648), inven_command
// 'x' (:699-706) and wear (:539-552); docs/X_WEAPON_SWAP_DESIGN.md §4, §11.
// Every expected record, stat and message below is written by hand; the
// stats derive from a Human Warrior with every stat 10 (no STR/DEX
// adjustment), so to-hit, to-dam and AC come from the equipment alone.
//
// Results at $0400-$040d: $01 = pass, $00 = fail per test (14 tests)
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
    ldx #14-1
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0830 "Main"

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
#import "../../../../core/item_exchange.s"
#import "../../../../core/spell_data.s"
#import "../../../../core/projectile.s"
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../../core/spell_effects.s"
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
eff_fear_timer: .byte 0
monster_attack_player:
player_update_hunger_state:
    sec
    rts
mon_atk_apply_damage:
    lda zp_player_hp_lo
    sec
    sbc zp_combat_dmg
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda zp_player_hp_hi
    sbc #0
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

// Store/huffman imports in dummy segment to avoid MAP_BASE ($C000) overlap
.segmentdef TestStoreOverlay [start=$d000, min=$d000, max=$ffff]
.segment TestStoreOverlay
#import "../../../../core/store_data.s"
#import "../../../../core/store.s"
#import "../../../../core/ui_store.s"
.segment Default

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test result buffer — copy to $0400 at end (msg_print clobbers $0400)
tc_results: .fill 14, $ff
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
    rts
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
rec_empty:         .byte FI_EMPTY, 0, 0, 0, 0, 0, 0, 0
rec_mace:          .byte 5, 1, 0, 1, 0, 0, IF_IDENTIFIED, 0
rec_mace_cursed:   .byte 5, 1, 0, 1, 0, 0, IF_IDENTIFIED | IF_CURSED, 0
rec_dagger:        .byte 2, 1, 0, 3, 4, 0, IF_IDENTIFIED, EGO_DEFENDER
rec_dagger_cursed: .byte 2, 1, 0, 3, 4, 0, IF_IDENTIFIED | IF_CURSED, EGO_DEFENDER
rec_dagger_ac:     .byte 2, 1, 0, 3, 4, 7, IF_IDENTIFIED | IF_CURSED, EGO_DEFENDER
rec_dagger_ac_uncursed: .byte 2, 1, 0, 3, 4, 7, IF_IDENTIFIED, EGO_DEFENDER
rec_potion:        .byte 17, 1, 0, 0, 0, 0, 0, 0
rec_armor:         .byte 7, 1, 0, 0, 0, 2, IF_IDENTIFIED, 0
rec_armor_cursed:  .byte 7, 1, 0, 0, 0, 2, IF_IDENTIFIED | IF_CURSED, 0
rec_robe:          .byte 6, 1, 0, 0, 0, 0, 0, 0
rec_torch_cursed:  .byte ITEM_TYPE_WOODEN_TORCH, 1, 100, 0, 0, 0, IF_CURSED, 0
rec_torches:       .byte ITEM_TYPE_WOODEN_TORCH, 2, 200, 0, 0, 0, 0, 0
rec_torch_one:     .byte ITEM_TYPE_WOODEN_TORCH, 1, 200, 0, 0, 0, 0, 0
rec_torch_old:     .byte ITEM_TYPE_WOODEN_TORCH, 1, 100, 0, 0, 0, 0, 0

// Messages, as the player reads them
s_no_weapons: .text "No weapons to exchange." ; .byte 0
s_cursed:     .text "You cannot remove it, it is cursed!" ; .byte 0
s_pri_mace:   .text "Primary: Mace (+1,+0)" ; .byte 0
s_pri_dagger: .text "Primary: Dagger (Defender) (+3,+4)" ; .byte 0
s_sec_mace:   .text "Secondary: Mace (+1,+0)" ; .byte 0
s_sec_dagger: .text "Secondary: Dagger (Defender) (+3,+4)" ; .byte 0

test_start:
    ldx #14 - 1
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
    jsr player_calc_stats

    // ==========================================================
    // Test 1: neither weapon slot occupied: refused, no turn, nothing
    // moves, "No weapons to exchange."
    // ==========================================================
    jsr tx_begin
    jsr item_exchange
    :EXPECT_CC()
    :EXPECT_SLOT(EQUIP_WEAPON, rec_empty)
    :EXPECT_SLOT(EQUIP_CLOAK, rec_empty)
    :EXPECT_SLOT(EQUIP_SECONDARY, rec_empty)
    :EXPECT_ROW(0, s_no_weapons)
    :END_TEST(0)

    // ==========================================================
    // Test 2: a cursed primary is refused (VMS checks the primary only):
    // no turn, both records and the combat stats unchanged.
    // ==========================================================
    jsr tx_begin
    :SEED(EQUIP_WEAPON, rec_mace_cursed)
    :SEED(EQUIP_SECONDARY, rec_dagger)
    jsr player_recalc_equipment
    :EXPECT_STATS(1, 0, 0)
    jsr item_exchange
    :EXPECT_CC()
    :EXPECT_SLOT(EQUIP_WEAPON, rec_mace_cursed)
    :EXPECT_SLOT(EQUIP_SECONDARY, rec_dagger)
    :EXPECT_STATS(1, 0, 0)
    :EXPECT_ROW(0, s_cursed)
    :END_TEST(1)

    // ==========================================================
    // Test 3: bonus transfer. Dagger (+3,+4) (Defender: +5 AC) wielded,
    // Mace (+1,+0) secondary: to-hit 3, to-dam 4, AC 5. After X: one turn,
    // all 8 fields exchanged, to-hit 1, to-dam 0, AC 0 (the secondary's
    // bonuses count for nothing), and both report lines.
    // ==========================================================
    jsr tx_begin
    jsr player_recalc_equipment
    :EXPECT_STATS(0, 0, 0)              // the fixture's base
    :SEED(EQUIP_WEAPON, rec_dagger)
    :SEED(EQUIP_SECONDARY, rec_mace)
    jsr player_recalc_equipment
    :EXPECT_STATS(3, 4, 5)
    jsr msg_clear
    jsr item_exchange
    :EXPECT_CS()
    :EXPECT_SLOT(EQUIP_WEAPON, rec_mace)
    :EXPECT_SLOT(EQUIP_SECONDARY, rec_dagger)
    :EXPECT_STATS(1, 0, 0)
    :EXPECT_ROW(0, s_pri_mace)
    :EXPECT_ROW(1, s_sec_dagger)
    :END_TEST(2)

    // ==========================================================
    // Test 4: only a primary: it becomes the secondary, to-hit/to-dam
    // drop to the base, and only the Secondary line prints.
    // ==========================================================
    jsr tx_begin
    :SEED(EQUIP_WEAPON, rec_dagger)
    jsr player_recalc_equipment
    jsr msg_clear
    jsr item_exchange
    :EXPECT_CS()
    :EXPECT_SLOT(EQUIP_WEAPON, rec_empty)
    :EXPECT_SLOT(EQUIP_SECONDARY, rec_dagger)
    :EXPECT_STATS(0, 0, 0)
    :EXPECT_ROW(0, s_sec_dagger)
    :EXPECT_ROW_BLANK(1)
    :END_TEST(3)

    // ==========================================================
    // Test 5: only a secondary: it becomes the primary; only the Primary
    // line prints.
    // ==========================================================
    jsr tx_begin
    :SEED(EQUIP_SECONDARY, rec_dagger)
    jsr player_recalc_equipment
    :EXPECT_STATS(0, 0, 0)
    jsr item_exchange
    :EXPECT_CS()
    :EXPECT_SLOT(EQUIP_WEAPON, rec_dagger)
    :EXPECT_SLOT(EQUIP_SECONDARY, rec_empty)
    :EXPECT_STATS(3, 4, 5)
    :EXPECT_ROW(0, s_pri_dagger)
    :EXPECT_ROW_BLANK(1)
    :END_TEST(4)

    // ==========================================================
    // Test 6: a cursed secondary may be swapped in (VMS); the next X is
    // then refused because the primary is cursed.
    // ==========================================================
    jsr tx_begin
    :SEED(EQUIP_WEAPON, rec_mace)
    :SEED(EQUIP_SECONDARY, rec_dagger_cursed)
    jsr item_exchange
    :EXPECT_CS()
    :EXPECT_SLOT(EQUIP_WEAPON, rec_dagger_cursed)
    :EXPECT_SLOT(EQUIP_SECONDARY, rec_mace)
    jsr msg_clear
    jsr item_exchange
    :EXPECT_CC()
    :EXPECT_SLOT(EQUIP_WEAPON, rec_dagger_cursed)
    :EXPECT_SLOT(EQUIP_SECONDARY, rec_mace)
    :EXPECT_ROW(0, s_cursed)
    :END_TEST(5)

    // ==========================================================
    // Test 7: X twice restores both records and the derived stats.
    // ==========================================================
    jsr tx_begin
    :SEED(EQUIP_WEAPON, rec_dagger)
    :SEED(EQUIP_SECONDARY, rec_mace)
    jsr player_recalc_equipment
    jsr item_exchange
    :EXPECT_CS()
    jsr msg_clear
    jsr item_exchange
    :EXPECT_CS()
    :EXPECT_SLOT(EQUIP_WEAPON, rec_dagger)
    :EXPECT_SLOT(EQUIP_SECONDARY, rec_mace)
    :EXPECT_STATS(3, 4, 5)
    :END_TEST(6)

    // ==========================================================
    // Test 8: the secondary is outside the AC range and the ego bonus
    // (VMS py_bonuses skip it): a Defender with +7 AC as the secondary
    // leaves AC at the armour's (Leather Armour [4,+2] = 6) and
    // player_pflags unchanged. Remove Curse covers it (VMS magic.inc:61).
    // ==========================================================
    jsr tx_begin
    :SEED(EQUIP_BODY, rec_armor)
    jsr player_recalc_equipment
    :EXPECT_STATS(0, 0, 6)
    lda player_pflags
    pha
    :SEED(EQUIP_SECONDARY, rec_dagger_ac)
    jsr player_recalc_equipment
    :EXPECT_STATS(0, 0, 6)
    pla
    cmp player_pflags
    beq !t8_pflags_ok+
    jsr tx_fail
!t8_pflags_ok:
    jsr eff_remove_curse
    :EXPECT_SLOT(EQUIP_SECONDARY, rec_dagger_ac_uncursed)
    :END_TEST(7)

    // ==========================================================
    // Test 9: a non-weapon in the secondary slot (only a corrupt save
    // can put one there) is refused like an empty pair, and `t` recovers
    // it to the pack.
    // ==========================================================
    jsr tx_begin
    :SEED(EQUIP_WEAPON, rec_mace)
    :SEED(EQUIP_SECONDARY, rec_potion)
    jsr item_exchange
    :EXPECT_CC()
    :EXPECT_SLOT(EQUIP_WEAPON, rec_mace)
    :EXPECT_SLOT(EQUIP_SECONDARY, rec_potion)
    :EXPECT_ROW(0, s_no_weapons)
    :SEED(EQUIP_WEAPON, rec_empty)
    jsr msg_clear
    :KEYS($41)                          // A = the only occupied slot
    jsr item_takeoff
    :EXPECT_CS()
    :EXPECT_SLOT(EQUIP_SECONDARY, rec_empty)
    :EXPECT_MEM(inv_item_id + 0, 17)
    :END_TEST(8)

    // ==========================================================
    // Test 10: the reserved cloak slot stays empty and is never offered;
    // the take-off cache lists the secondary last.
    // ==========================================================
    jsr tx_begin
    :SEED(EQUIP_WEAPON, rec_mace)
    :SEED(EQUIP_BODY, rec_armor)
    :SEED(EQUIP_SECONDARY, rec_dagger)
    jsr item_exchange
    :EXPECT_SLOT(EQUIP_CLOAK, rec_empty)
    jsr piw_build_visible_equip_cache
    :EXPECT_A(3)
    :EXPECT_MEM(piw_visible_slots + 0, 22)
    :EXPECT_MEM(piw_visible_slots + 1, 23)
    :EXPECT_MEM(piw_visible_slots + 2, 32)
    :END_TEST(9)

    // ==========================================================
    // Test 11: `w` will not replace a cursed weapon (VMS wear,
    // moria.inc:539-552): refused, no turn, nothing moves.
    // ==========================================================
    jsr tx_begin
    :SEED(EQUIP_WEAPON, rec_mace_cursed)
    :SEED(0, rec_dagger)
    :KEYS($41)
    jsr item_wear
    :EXPECT_CC()
    :EXPECT_SLOT(EQUIP_WEAPON, rec_mace_cursed)
    :EXPECT_SLOT(0, rec_dagger)
    :EXPECT_ROW(1, s_cursed)              // under the wear prompt on row 0
    :END_TEST(10)

    // ==========================================================
    // Test 12: nor cursed body armour.
    // ==========================================================
    jsr tx_begin
    :SEED(EQUIP_BODY, rec_armor_cursed)
    :SEED(0, rec_robe)
    :KEYS($41)
    jsr item_wear
    :EXPECT_CC()
    :EXPECT_SLOT(EQUIP_BODY, rec_armor_cursed)
    :EXPECT_SLOT(0, rec_robe)
    :EXPECT_ROW(1, s_cursed)              // under the wear prompt on row 0
    :END_TEST(11)

    // ==========================================================
    // Test 13: nor a cursed light, from a stack of torches (the stack
    // path): the stack keeps both torches.
    // ==========================================================
    jsr tx_begin
    :SEED(EQUIP_LIGHT, rec_torch_cursed)
    :SEED(0, rec_torches)
    :KEYS($41)
    jsr item_wear
    :EXPECT_CC()
    :EXPECT_SLOT(EQUIP_LIGHT, rec_torch_cursed)
    :EXPECT_SLOT(0, rec_torches)
    :END_TEST(12)

    // ==========================================================
    // Test 14: an uncursed light is still replaced from the stack (one
    // torch on, one left, the old one to the pack).
    // ==========================================================
    jsr tx_begin
    :SEED(EQUIP_LIGHT, rec_torch_old)
    :SEED(0, rec_torches)
    :KEYS($41)
    jsr item_wear
    :EXPECT_CS()
    :EXPECT_SLOT(EQUIP_LIGHT, rec_torch_one)
    :EXPECT_SLOT(0, rec_torch_one)
    :EXPECT_SLOT(1, rec_torch_old)
    :END_TEST(13)

    jmp test_exit_trampoline

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

item_exchange_test_body_end:
.assert "Item exchange test stays below MAP_BASE", item_exchange_test_body_end <= MAP_BASE, true
