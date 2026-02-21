// test_ego.s — Runtime tests for ego item system
//
// Tests: roll_ego_type (non-weapon, dlvl 0, deep weapon), ego_apply_damage
//        (slay x2, slay x3, bonus dice), ego_get_ac_bonus, pickup/drop lifecycle.
//
// Results at $0400-$0409: $01 = pass, $00 = fail per test (10 tests)
// NOTE: msg_print writes to screen row 0 ($0400+), so we store results
// in tc_results[] and copy to $0400 at the very end.

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

// Exit trampoline at $080E — banks out BASIC, copies results, breaks.
// MUST be in "Test Code" segment so run_tests.sh sets breakpoint here (below $A000).
.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #9
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_mixed"

#import "../zeropage.s"
#import "../memory.s"
#import "../reu.s"
#import "../screen.s"
#import "../color.s"
#import "../config.s"
#import "../input.s"
#import "../rng.s"
#import "../math.s"
#import "../tables.s"
#import "../item_defs.s"
#import "../player.s"
#import "../ui_messages.s"
#import "../ui_status.s"
#import "../ui_help_clear.s"
#import "../ui_character.s"
#import "../stat_display.s"
#import "../player_create.s"
#import "../sound.s"
#import "../dungeon_data.s"
#import "../dungeon_gen.s"
#import "../huffman.s"
#import "../dungeon_features.s"
#import "../monster.s"
#import "../tier_manager.s"
#import "../overlay.s"
#import "../monster_ai.s"
#import "../recall.s"
#import "../monster_magic.s"
#import "../item.s"
#import "../special_rooms.s"
#import "../ego_items.s"
#import "../special_rooms_stubs.s"
#import "../player_items.s"
#import "../spell_data.s"
#import "../projectile.s"
#import "../spell_effects.s"
#import "../player_magic.s"
#import "../ui_inventory.s"
#import "../dungeon_render.s"
#import "../dungeon_los.s"
#import "../player_move.s"
#import "../combat.s"
#import "../monster_attack.s"
#import "../turn.s"
#import "../store_data.s"
#import "../store.s"
#import "../ui_store.s"
#import "../ui_help.s"
#import "../ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tc_results: .fill 10, $ff      // Result buffer (copied to $0400 at end)
tc_loop:    .byte 0
tc_count:   .byte 0

test_start:
    // Seed RNG deterministically
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    // Initialize message system and sound
    jsr msg_init
    jsr sound_init

    // ============================================================
    // Test 1: roll_ego_type returns 0 for non-weapons
    // Item type 15 = Ration of Food (ICAT_FOOD), should never get ego.
    // ============================================================
    lda #20                     // dlvl 20 (high chance)
    sta zp_player_dlvl
    lda #15                     // Ration of food
    jsr roll_ego_type
    cmp #EGO_NONE
    beq !t1_pass+
    lda #$00
    jmp !t1_store+
!t1_pass:
    lda #$01
!t1_store:
    sta tc_results + 0

    // ============================================================
    // Test 2: roll_ego_type returns 0 at dlvl 0
    // Chance = min(0*2, 40) = 0 out of 100, always zero.
    // Item type 2 = Dagger (ICAT_WEAPON, melee).
    // ============================================================
    lda #0
    sta zp_player_dlvl
    lda #2                      // Dagger
    jsr roll_ego_type
    cmp #EGO_NONE
    beq !t2_pass+
    lda #$00
    jmp !t2_store+
!t2_pass:
    lda #$01
!t2_store:
    sta tc_results + 1

    // ============================================================
    // Test 3: roll_ego_type produces ego for melee weapon at deep dlvl
    // At dlvl 20, chance = 40/100 = 40%. Run 200 trials; at least
    // one should produce a non-zero ego (P(all zero) = 0.6^200 ≈ 0).
    // ============================================================
    lda #20
    sta zp_player_dlvl
    lda #0
    sta tc_count                // Count non-zero egos
    sta tc_loop

!t3_loop:
    lda #2                      // Dagger
    jsr roll_ego_type
    cmp #EGO_NONE
    beq !t3_next+
    inc tc_count
!t3_next:
    inc tc_loop
    lda tc_loop
    cmp #200
    bne !t3_loop-

    lda tc_count
    beq !t3_fail+               // If 0 egos in 200 tries, fail
    lda #$01
    jmp !t3_store+
!t3_fail:
    lda #$00
!t3_store:
    sta tc_results + 2

    // ============================================================
    // Test 4: ego_apply_damage — Slay Animal x2
    // Set cmb_damage=10, cmb_type to an animal creature, ego=SLAY_ANIMAL.
    // Expected: 10*2 = 20.
    // ============================================================
    lda #10
    sta cmb_damage
    // Use creature index 1 (Giant White Mouse, CF_ANIMAL)
    lda #1
    sta cmb_type
    lda #EGO_SLAY_ANIMAL
    jsr ego_apply_damage
    lda cmb_damage
    cmp #20
    beq !t4_pass+
    lda #$00
    jmp !t4_store+
!t4_pass:
    lda #$01
!t4_store:
    sta tc_results + 3

    // ============================================================
    // Test 5: ego_apply_damage — Slay Undead x3
    // Set cmb_damage=10, cmb_type to undead creature, ego=SLAY_UNDEAD.
    // Creature 13 = Poltergeist (CF_UNDEAD|CF_EVIL).
    // Expected: 10*3 = 30.
    // ============================================================
    lda #10
    sta cmb_damage
    lda #13
    sta cmb_type
    lda #EGO_SLAY_UNDEAD
    jsr ego_apply_damage
    lda cmb_damage
    cmp #30
    beq !t5_pass+
    lda #$00
    jmp !t5_store+
!t5_pass:
    lda #$01
!t5_store:
    sta tc_results + 4

    // ============================================================
    // Test 6: ego_apply_damage — Slay Animal on non-animal = no change
    // Set cmb_damage=10, cmb_type to a non-animal (creature 0 = White Harpy, CF_EVIL).
    // Expected: 10 (unchanged, no bonus dice on slay animal).
    // ============================================================
    lda #10
    sta cmb_damage
    lda #0                      // White Harpy = CF_EVIL only
    sta cmb_type
    lda #EGO_SLAY_ANIMAL
    jsr ego_apply_damage
    lda cmb_damage
    cmp #10
    beq !t6_pass+
    lda #$00
    jmp !t6_store+
!t6_pass:
    lda #$01
!t6_store:
    sta tc_results + 5

    // ============================================================
    // Test 7: ego_apply_damage — Flame Tongue bonus dice
    // cmb_damage=10, any creature, ego=FLAME_TONGUE → +2d4 (range 2-8).
    // Reseed RNG for determinism, then verify damage > 10 and <= 18.
    // ============================================================
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    lda #10
    sta cmb_damage
    lda #0
    sta cmb_type
    lda #EGO_FLAME_TONGUE
    jsr ego_apply_damage
    lda cmb_damage
    cmp #11                     // Must be > 10 (at least +1 from 2d4 min=2... wait, 2d4 min=2)
    bcc !t7_fail+               // < 11 = fail
    cmp #19                     // Must be <= 18
    bcs !t7_fail+               // >= 19 = fail
    lda #$01
    jmp !t7_store+
!t7_fail:
    lda #$00
!t7_store:
    sta tc_results + 6

    // ============================================================
    // Test 8: ego_get_ac_bonus — Defender = 5, Holy Avenger = 3, None = 0
    // ============================================================
    lda #EGO_DEFENDER
    jsr ego_get_ac_bonus
    cmp #5
    bne !t8_fail+
    lda #EGO_HOLY_AVENGER
    jsr ego_get_ac_bonus
    cmp #3
    bne !t8_fail+
    lda #EGO_NONE
    jsr ego_get_ac_bonus
    cmp #0
    bne !t8_fail+
    lda #$01
    jmp !t8_store+
!t8_fail:
    lda #$00
!t8_store:
    sta tc_results + 7

    // ============================================================
    // Test 9: Ego survives pickup cycle (floor → inventory)
    // Place an item with ego on the floor, pick it up, verify inv_ego.
    // ============================================================
    // Clear floor items
    ldx #0
    lda #FI_EMPTY
!t9_clr:
    sta fi_item_id,x
    inx
    cpx #MAX_FLOOR_ITEMS
    bne !t9_clr-

    // Place a dagger with slay evil at floor slot 0
    lda #2                      // Dagger
    sta fi_item_id
    lda #5                      // x=5
    sta fi_x
    lda #5                      // y=5
    sta fi_y
    lda #1
    sta fi_qty
    lda #0
    sta fi_p1
    sta fi_flags
    lda #EGO_SLAY_EVIL
    sta fi_ego
    lda #1
    sta zp_item_count

    // Clear inventory slot 0
    lda #FI_EMPTY
    sta inv_item_id

    // Set up fi_add scratch for inv_add_item
    lda #2
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    sta fi_add_flags
    lda #EGO_SLAY_EVIL
    sta fi_add_ego

    jsr inv_add_item

    // Check inv_ego at slot where item was placed
    // inv_add_item finds first empty carried slot (0-21)
    lda inv_ego
    cmp #EGO_SLAY_EVIL
    beq !t9_pass+
    lda #$00
    jmp !t9_store+
!t9_pass:
    lda #$01
!t9_store:
    sta tc_results + 8

    // ============================================================
    // Test 10: roll_ego_type returns 0 for ranged weapons (bows)
    // Item type 49 = Short Bow (ICAT_WEAPON but ranged), should get no ego.
    // ============================================================
    lda #20
    sta zp_player_dlvl
    lda #49                     // Short Bow
    jsr roll_ego_type
    cmp #EGO_NONE
    beq !t10_pass+
    lda #$00
    jmp !t10_store+
!t10_pass:
    lda #$01
!t10_store:
    sta tc_results + 9

    jmp test_exit_trampoline
