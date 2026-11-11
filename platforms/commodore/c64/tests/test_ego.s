// test_ego.s — Runtime tests for ego item system
//
// Tests: roll_ego_type (non-weapon, dlvl 0, deep weapon), ego_apply_damage
//        (slay x2, slay x3, bonus dice), ego_get_ac_bonus, pickup/drop lifecycle,
//        resistance armour (roll, worn flags, suffixes).
//
// Results at $0400-$0412: $01 = pass, $00 = fail per test (19 tests)
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
    ldx #18
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_mixed"

#define COMPILE_EMBEDDED_DUNGEON_TEST_ROSTER

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
#import "dungeon_gen_stubs.s"
#import "../../../../core/huffman.s"
#import "../../../../core/dungeon_features.s"
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/monster_ai.s"
#import "../../../../core/recall.s"
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
#import "../../../../core/ui_inventory.s"
#import "../../../../core/ui_equipment.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"
#import "../../../../core/ui_help.s"
#import "../../../../core/ui_trampoline_stubs.s"
// Monster spells and the store are not exercised here: out of the way above
// the I/O hole (resistance armour, 2026-11-11, took the body into the create
// overlay at $D000).
.segmentdef TestUnused [start=$e000]
.segment TestUnused
#import "../../../../core/monster_magic.s"
#import "../../../../core/store_data.s"
#import "../../../../core/store.s"
#import "../../../../core/ui_store.s"
.segment Default

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tc_results: .fill 19, $ff      // Result buffer (copied to $0400 at end)
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
    jsr hal_sound_init

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
    lda #EGO_SLAY_EVIL
    sta fi_meta
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

    // ============================================================
    // Test 11: ego_apply_damage — Slay Dragon x4 vs CF_DRAGON (VMS tot_dam,
    // moria.inc: tdam*4), capped at 255; nothing against a non-dragon.
    // Creature 20 is flagged a dragon here.
    // ============================================================
    lda #CF_DRAGON
    sta cr_mflags + 20
    lda #10
    sta cmb_damage
    lda #20
    sta cmb_type
    lda #EGO_SLAY_DRAGON
    jsr ego_apply_damage
    lda cmb_damage
    cmp #40
    bne !t11_fail+
    lda #100
    sta cmb_damage
    lda #EGO_SLAY_DRAGON
    jsr ego_apply_damage
    lda cmb_damage
    cmp #255
    bne !t11_fail+
    lda #0
    sta cr_mflags + 20
    lda #10
    sta cmb_damage
    lda #EGO_SLAY_DRAGON
    jsr ego_apply_damage
    lda cmb_damage
    cmp #10
    bne !t11_fail+
    lda #$01
    bne !t11_store+
!t11_fail:
    lda #$00
!t11_store:
    sta tc_results + 10

    // ============================================================
    // Test 12: a floor item keeps ego 8 (bit 3 packed in fi_meta bit 7) and
    // its flags through the real floor_item_add pack.
    // ============================================================
    ldx #0
    lda #FI_EMPTY
!t12_clr:
    sta fi_item_id,x
    inx
    cpx #MAX_FLOOR_ITEMS
    bne !t12_clr-
    lda #0
    sta zp_item_count
    lda #2                      // Dagger
    sta fi_add_id
    lda #6
    sta fi_add_x
    sta fi_add_y
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    sta fi_add_to_hit
    sta fi_add_to_dam
    sta fi_add_to_ac
    lda #IF_IDENTIFIED
    sta fi_add_flags
    lda #EGO_SLAY_DRAGON
    sta fi_add_ego
    jsr floor_item_add
    bcc !t12_fail+
    stx t12_slot
    jsr floor_item_get_ego_x
    cmp #EGO_SLAY_DRAGON
    bne !t12_fail+
    ldx t12_slot
    jsr floor_item_get_flags_x
    cmp #IF_IDENTIFIED
    bne !t12_fail+
    lda #$01
    bne !t12_store+
!t12_fail:
    lda #$00
!t12_store:
    sta tc_results + 11

    // ============================================================
    // Tests 13-19: resistance armour (2026-11-11; VMS magic_treasure,
    // misc.inc): body armour and shields that rolled a magic bonus get a
    // resistance with magik(trunc(min(15 + dlvl, 70) / 6)), then randint(9):
    // 1 (R) +5 AC, 2 (RA), 3-4 (RF), 5-6 (RC), 7-9 (RL).
    // ============================================================
    lda #50
    sta zp_player_dlvl

    // Test 13: Chain mail with no magic bonus (to-AC 0) never gets one
    lda #0
    sta fi_add_to_ac
    lda #8
    jsr t_armour_trials
    lda tc_count
    jsr t_store_zero
    sta tc_results + 12

    // Test 14: a cursed Small shield (to-AC -2) never gets one
    lda #$fe
    sta fi_add_to_ac
    lda #9
    jsr t_armour_trials
    lda tc_count
    jsr t_store_zero
    sta tc_results + 13

    // Test 15: magic Chain mail on DL50: special = 65 / 6 = 10%, so 200
    // trials give 8-35 resistances; each one of the five, and (R) +5 AC
    lda #3
    sta fi_add_to_ac
    lda #8
    jsr t_armour_trials
    lda t_bad
    bne !t15_fail+
    lda tc_count
    cmp #8
    bcc !t15_fail+
    cmp #36
    bcs !t15_fail+
    lda #$01
    .byte $2c
!t15_fail:
    lda #$00
    sta tc_results + 14

    // Test 16: magic Leather gloves (and helms, boots) never get one
    lda #3
    sta fi_add_to_ac
    lda #11
    jsr t_armour_trials
    lda tc_count
    jsr t_store_zero
    sta tc_results + 15

    // Test 17: the flags from what is worn: (Resist) body armour and a
    // (Resist Acid) shield give the four resistances; a Defender adds Free
    // Action and See Invisible; a digging tool's ego gives none
    lda #EGO_RESIST
    sta inv_ego + EQUIP_BODY
    lda #EGO_RESIST_ACID
    sta inv_ego + EQUIP_SHIELD
    lda #2                      // a tool ego (Dwarven): no flags
    sta inv_ego + EQUIP_WEAPON
    jsr player_recalc_pflags_equipment
    lda player_pflags
    cmp #PFLAG_RESIST_FIRE | PFLAG_RESIST_COLD | PFLAG_RESIST_ACID | PFLAG_RESIST_LIGHT
    bne !t17_fail+
    lda #EGO_DEFENDER
    sta inv_ego + EQUIP_WEAPON
    lda #0
    sta inv_ego + EQUIP_BODY
    sta inv_ego + EQUIP_SHIELD
    jsr player_recalc_pflags_equipment
    lda player_pflags
    cmp #PFLAG_RESIST_FIRE | PFLAG_RESIST_COLD | PFLAG_RESIST_ACID | PFLAG_RESIST_LIGHT | PFLAG_FREE_ACT | PFLAG_SEE_INVIS
    bne !t17_fail+
    lda #$01
    .byte $2c
!t17_fail:
    lda #$00
    sta tc_results + 16
    lda #0
    sta inv_ego + EQUIP_WEAPON
    sta inv_ego + EQUIP_BODY
    sta inv_ego + EQUIP_SHIELD
    jsr player_recalc_pflags_equipment

    // Test 18: one (Resist Lightning) body armour gives only that
    lda #EGO_RESIST_LIGHT
    sta inv_ego + EQUIP_BODY
    jsr player_recalc_pflags_equipment
    lda player_pflags
    cmp #PFLAG_RESIST_LIGHT
    jsr t_store_eq
    sta tc_results + 17
    lda #0
    sta inv_ego + EQUIP_BODY
    jsr player_recalc_pflags_equipment

    // Test 19: the suffixes, spelled out as the weapon egos are
    lda #EGO_RESIST_LIGHT
    jsr ego_get_suffix_ptr
    ldy #t19_light_end - t19_light - 1
!t19_cmp:
    lda (zp_ptr0),y
    cmp t19_light,y
    bne !t19_fail+
    dey
    bpl !t19_cmp-
    lda #EGO_RESIST
    jsr ego_get_suffix_ptr
    ldy #t19_resist_end - t19_resist - 1
!t19_cmp2:
    lda (zp_ptr0),y
    cmp t19_resist,y
    bne !t19_fail+
    dey
    bpl !t19_cmp2-
    lda #$01
    .byte $2c
!t19_fail:
    lda #$00
    sta tc_results + 18

    jmp test_exit_trampoline
t12_slot: .byte 0
t_bad:    .byte 0
t_item:   .byte 0
t_to_ac:  .byte 0
t19_light:  .text " (Resist Lightning)" ; .byte 0
t19_light_end:
t19_resist: .text " (Resist)" ; .byte 0
t19_resist_end:

// t_armour_trials — 200 roll_ego_type calls for item A with fi_add_to_ac as
// set (restored each time). tc_count = resistances given; t_bad set when one
// is not a resistance ego, or (Resist) did not add 5 to-AC (the others none).
t_armour_trials:
    sta t_item
    lda fi_add_to_ac
    sta t_to_ac
    lda #0
    sta tc_count
    sta tc_loop
    sta t_bad
!tat_loop:
    lda t_to_ac
    sta fi_add_to_ac
    lda t_item
    jsr roll_ego_type
    cmp #EGO_NONE
    beq !tat_none+
    inc tc_count
    cmp #EGO_RESIST
    bcc !tat_bad+
    cmp #EGO_RESIST_LIGHT + 1
    bcs !tat_bad+
    ldx #5
    cmp #EGO_RESIST
    beq !tat_ac+
    ldx #0
!tat_ac:
    txa
    clc
    adc t_to_ac
    cmp fi_add_to_ac
    beq !tat_next+
!tat_bad:
    inc t_bad
    jmp !tat_next+
!tat_none:
    lda fi_add_to_ac
    cmp t_to_ac
    bne !tat_bad-
!tat_next:
    inc tc_loop
    lda tc_loop
    cmp #200
    bne !tat_loop-
    lda t_to_ac
    sta fi_add_to_ac
    rts

// t_store_zero — A = $01 when A is 0, else $00.
t_store_zero:
    cmp #0
t_store_eq:
    beq !tsz_yes+
    lda #$00
    rts
!tsz_yes:
    lda #$01
    rts

ego_test_body_end:
.assert "Ego test body stays below the create overlay ($D000)", ego_test_body_end <= $d000, true
