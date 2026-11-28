// test_ego.s — Runtime tests for ego item system
//
// Tests: roll_ego_type (non-weapon, dlvl 0, deep weapon), ego_apply_damage
//        (slay x2, slay x3, bonus dice), ego_get_ac_bonus, pickup/drop lifecycle,
//        resistance armour (roll, worn flags, suffixes), the Lordly rings,
//        the crowns of the Magi (roll, flags, INT, suffix).
//
// Results at $0400-$0418: $01 = pass, $00 = fail per test (25 tests)
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
    ldx #24
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_mixed"

#define COMPILE_EMBEDDED_DUNGEON_TEST_ROSTER

.segmentdef TestCreateOverlay [start=$D000, min=$D000, max=$DFFF]
.segmentdef TestUnused [start=$E100, min=$E100, max=$FFF9]
#import "../../../../core/6502/zeropage.s"
#import "../memory.s"
#import "../../common/reu.s"
#import "../screen.s"
#import "../../../../core/6502/color.s"
#import "../config.s"
#import "../input.s"
#import "../../../../core/6502/rng.s"
#import "../../../../core/6502/math.s"
#import "../../../../core/6502/tables.s"
#import "../../../../core/6502/item_defs.s"
#import "../../../../core/6502/player.s"
#import "../../../../core/6502/ui_messages.s"
.segment TestCreateOverlay
#import "../../../../core/6502/ui_status.s"
.segment Default
#import "../../../../core/6502/ui_help_clear.s"
.segment Default
#import "../../../../core/6502/stat_display.s"
.segment TestCreateOverlay
ui_char_display:
player_create:
    brk
.segment Default
#import "../../../../core/6502/sound.s"
#import "../../../../core/6502/dungeon_data.s"
#import "dungeon_gen_stubs.s"
#import "../../../../core/6502/huffman.s"
#import "../../../../core/6502/dungeon_features.s"
#import "chest_summons_stubs.s"
#import "../../../../core/6502/monster.s"
#import "../../../../core/6502/tier_manager.s"
#import "../../common/overlay.s"
.segment Default
#import "../../../../core/6502/monster_ai.s"
.segment Default
#import "../../../../core/6502/recall.s"
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../../../../core/6502/item.s"
#import "item_cat_resident_helper.s"
#import "../../../../core/6502/special_rooms.s"
#import "../../../../core/6502/ego_items.s"
#import "../../../../core/6502/special_rooms_stubs.s"
#import "../../../../core/6502/player_items.s"
#import "../../../../core/6502/spell_data.s"
#import "../../../../core/6502/projectile.s"
.segment Default
#import "../../../../core/6502/spell_effects.s"
.segment Default
#import "../../../../core/6502/player_magic_state.s"
#import "../../../../core/6502/player_magic_state_ops.s"
#import "../../../../core/6502/player_magic.s"
#import "../../../../core/6502/ui_inventory.s"
#import "../../../../core/6502/ui_equipment.s"
.segment TestCreateOverlay
#import "../dungeon_render.s"
.segment Default
#import "../../../../core/6502/dungeon_los.s"
#import "../../../../core/6502/player_move.s"
.segment Default
#import "../../../../core/6502/combat.s"
#import "../../../../core/6502/scene_mat_tile.s"
.segment Default
.segment TestCreateOverlay
#import "../../../../core/6502/player_save.s"
#import "../../../../core/6502/element_resist.s"
monster_attack_player:
mon_atk_acid_armour:
mon_atk_apply_damage:
mon_atk_apply_damage_16:
player_death_check:
    brk
mad_dmg_hi: .byte 0
.segment Default
#import "../../../../core/6502/turn.s"

.segment TestCreateOverlay
#import "../../../../core/6502/ui_help.s"
.segment Default
#import "../../../../core/6502/ui_trampoline_stubs.s"
#import "../../../../core/6502/player_adjust_equipment_stat.s"
// Monster spells and the store are not exercised here: stubbed in the $D000
// test overlay so accidental execution hits BRK / parked_tripwire.
.segment TestCreateOverlay
monster_can_cast:
monster_pick_spell:
    brk
.segment Default
store_init_all:
    rts
store_restock_all:
    rts
store_enter:
    rts

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tc_results: .fill 25, $ff      // Result buffer (copied to $0400 at end)
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
    lda #ITEM_SLOT_RATION_OF_FOOD                     // Ration of food
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
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
        sta item_cur_page
    }
    lda #ITEM_SLOT_DAGGER                      // Dagger
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
    sta t_ha_count              // Count Holy Avengers (must roll fi_add_p1 in 1..4)
    sta tc_loop

!t3_loop:
    lda #0
    sta fi_add_p1
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
        sta item_cur_page
    }
    lda #ITEM_SLOT_DAGGER                      // Dagger
    jsr roll_ego_type
    cmp #EGO_NONE
    beq !t3_chk_zero+
    inc tc_count
    cmp #EGO_HOLY_AVENGER
    bne !t3_chk_zero+
    inc t_ha_count
    lda fi_add_p1
    beq !t3_fail+
    cmp #5
    bcs !t3_fail+
    bcc !t3_next+
!t3_chk_zero:
    lda fi_add_p1
    bne !t3_fail+
!t3_next:
    inc tc_loop
    lda tc_loop
    cmp #200
    bne !t3_loop-
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #0
        sta item_cur_page
    }

    lda tc_count
    beq !t3_fail+               // If 0 egos in 200 tries, fail
    lda t_ha_count
    beq !t3_fail+               // Must observe Holy Avenger with p1 in 1..4
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
    lda #ITEM_SLOT_DAGGER                      // Dagger
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
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
        sta fi_meta_hi
    }
    lda #1
    sta zp_item_count

    // Clear inventory slot 0
    lda #FI_EMPTY
    sta inv_item_id

    // Set up fi_add scratch for inv_add_item
    lda #ITEM_SLOT_DAGGER
    sta fi_add_id
    lda #1
    sta fi_add_qty
    lda #0
    sta fi_add_p1
    sta fi_add_flags
    lda #(EGO_SLAY_EVIL | ITEM_PAGE_DAGGER)
    sta fi_add_ego

    jsr inv_add_item

    // Check inv_ego at slot where item was placed
    // inv_add_item finds first empty carried slot (0-21)
    lda inv_ego
    cmp #(EGO_SLAY_EVIL | ITEM_PAGE_DAGGER)
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
    lda #ITEM_SLOT_SHORT_BOW                     // Short Bow
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
    lda #ITEM_SLOT_DAGGER                      // Dagger
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
    lda #(EGO_SLAY_DRAGON | ITEM_PAGE_DAGGER)
    sta fi_add_ego
    jsr floor_item_add
    bcc !t12_fail+
    stx t12_slot
    jsr floor_item_get_ego_x
    cmp #(EGO_SLAY_DRAGON | ITEM_PAGE_DAGGER)
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
    lda #ITEM_SLOT_CHAIN_MAIL
    jsr t_armour_trials
    lda tc_count
    jsr t_store_zero
    sta tc_results + 12

    // Test 14: a cursed Small shield (to-AC -2) never gets one
    lda #$fe
    sta fi_add_to_ac
    .if (ITEM_PAGE_SMALL_SHIELD != 0) {
        lda #ITEM_PAGE_SMALL_SHIELD
        sta item_cur_page
    }
    lda #ITEM_SLOT_SMALL_SHIELD
    jsr t_armour_trials
    .if (ITEM_PAGE_SMALL_SHIELD != 0) {
        lda #0
        sta item_cur_page
    }
    lda tc_count
    jsr t_store_zero
    sta tc_results + 13

    // Test 15: magic Chain mail on DL50: special = 65 / 6 = 10%, so 200
    // trials give 8-35 resistances; each one of the five, and (R) +5 AC
    lda #3
    sta fi_add_to_ac
    lda #ITEM_SLOT_CHAIN_MAIL
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

    // Test 16: Leather gloves never roll body/shield resistance egos: plain
    // gloves get none, magic gloves roll only Free Action or Slaying
    lda #0
    sta fi_add_to_ac
    .if (ITEM_PAGE_LEATHER_GLOVES != 0) {
        lda #ITEM_PAGE_LEATHER_GLOVES
        sta item_cur_page
    }
    lda #ITEM_SLOT_LEATHER_GLOVES
    jsr t_armour_trials
    lda tc_count
    bne !t16_fail+
    lda #3
    sta fi_add_to_ac
    lda #0
    sta tc_count
    sta tc_loop
!t16_loop:
    .if (ITEM_PAGE_LEATHER_GLOVES != 0) {
        lda #ITEM_PAGE_LEATHER_GLOVES
        sta item_cur_page
    }
    lda #ITEM_SLOT_LEATHER_GLOVES
    jsr roll_ego_type
    beq !t16_next+
    inc tc_count
    cmp #EGO_FREE_ACTION
    bcc !t16_fail+
    cmp #EGO_SLAYING + 1
    bcs !t16_fail+
!t16_next:
    inc tc_loop
    lda tc_loop
    cmp #200
    bne !t16_loop-
    lda tc_count
    cmp #8
    bcc !t16_fail+
    cmp #36
    bcs !t16_fail+
    lda #$01
    .byte $2c
!t16_fail:
    lda #$00
    sta tc_results + 15
    .if (ITEM_PAGE_LEATHER_GLOVES != 0) {
        lda #0
        sta item_cur_page
    }

    // Test 17: the flags from what is worn: (Resist) body armour and a
    // (Resist Acid) shield give the four resistances; a Defender adds Free
    // Action, See Invisible and Feather Falling; a digging tool's ego gives none
    lda #ITEM_SLOT_PICK                     // Pick (ICAT_DIGGING): inv_ego is a tool prefix
    sta inv_item_id + EQUIP_WEAPON
    lda #ITEM_SLOT_CHAIN_MAIL
    sta inv_item_id + EQUIP_BODY
    lda #ITEM_SLOT_SMALL_SHIELD
    sta inv_item_id + EQUIP_SHIELD
    lda #EGO_RESIST
    sta inv_ego + EQUIP_BODY
    lda #(ITEM_PAGE_SMALL_SHIELD | EGO_RESIST_ACID)
    sta inv_ego + EQUIP_SHIELD
    lda #2                      // a tool ego (Dwarven): no flags
    sta inv_ego + EQUIP_WEAPON
    jsr player_recalc_pflags_equipment
    lda player_pflags
    cmp #PFLAG_RESIST_FIRE | PFLAG_RESIST_COLD | PFLAG_RESIST_ACID | PFLAG_RESIST_LIGHT
    bne !t17_fail+
    lda #ITEM_SLOT_DAGGER
    sta inv_item_id + EQUIP_WEAPON
    lda #(ITEM_PAGE_DAGGER | EGO_DEFENDER)
    sta inv_ego + EQUIP_WEAPON
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_BODY
    sta inv_item_id + EQUIP_SHIELD
    lda #0
    sta inv_ego + EQUIP_BODY
    sta inv_ego + EQUIP_SHIELD
    jsr player_recalc_pflags_equipment
    lda player_pflags
    cmp #PFLAG_RESIST_FIRE | PFLAG_RESIST_COLD | PFLAG_RESIST_ACID | PFLAG_RESIST_LIGHT | PFLAG_FREE_ACT | PFLAG_SEE_INVIS | PFLAG_FFALL
    bne !t17_fail+
    lda #$01
    .byte $2c
!t17_fail:
    lda #$00
    sta tc_results + 16
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_WEAPON
    sta inv_item_id + EQUIP_BODY
    sta inv_item_id + EQUIP_SHIELD
    lda #0
    sta inv_ego + EQUIP_WEAPON
    sta inv_ego + EQUIP_BODY
    sta inv_ego + EQUIP_SHIELD
    jsr player_recalc_pflags_equipment

    // Test 18: one (Resist Lightning) body armour gives only that
    lda #ITEM_SLOT_CHAIN_MAIL
    sta inv_item_id + EQUIP_BODY
    lda #EGO_RESIST_LIGHT
    sta inv_ego + EQUIP_BODY
    jsr player_recalc_pflags_equipment
    lda player_pflags
    cmp #PFLAG_RESIST_LIGHT
    jsr t_store_eq
    sta tc_results + 17
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_BODY
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

    // Test 20: the rings of Lordly Protection and the Amulet of Resist Acid
    // (MON-029; VMS values.inc): Fire on the right hand and Cold on the left
    // give those two; the amulet acid; a Lordly ring adds its 5 base AC
    lda #ITEM_SLOT_RING_OF_LORDLY_PROTECTION_FIRE
    sta inv_item_id + EQUIP_RING
    .if (ITEM_PAGE_RING_OF_LORDLY_PROTECTION_FIRE != 0) {
        lda #ITEM_PAGE_RING_OF_LORDLY_PROTECTION_FIRE
        sta inv_ego + EQUIP_RING
    }
    lda #ITEM_SLOT_RING_OF_LORDLY_PROTECTION_COLD
    sta inv_item_id + EQUIP_RING2
    .if (ITEM_PAGE_RING_OF_LORDLY_PROTECTION_COLD != 0) {
        lda #ITEM_PAGE_RING_OF_LORDLY_PROTECTION_COLD
        sta inv_ego + EQUIP_RING2
    }
    lda #ITEM_SLOT_AMULET_OF_RESIST_ACID
    sta inv_item_id + EQUIP_AMULET
    .if (ITEM_PAGE_AMULET_OF_RESIST_ACID != 0) {
        lda #ITEM_PAGE_AMULET_OF_RESIST_ACID
        sta inv_ego + EQUIP_AMULET
    }
    jsr player_recalc_pflags_equipment
    lda player_pflags
    cmp #PFLAG_RESIST_FIRE | PFLAG_RESIST_COLD | PFLAG_RESIST_ACID
    bne !t20_fail+
    lda player_data + PL_AC
    sta t_to_ac                 // AC with both rings (5 each)
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_RING2
    jsr player_recalc_pflags_equipment
    lda player_pflags
    cmp #PFLAG_RESIST_FIRE | PFLAG_RESIST_ACID
    bne !t20_fail+
    lda t_to_ac
    sec
    sbc player_data + PL_AC
    cmp #5
    bne !t20_fail+
    lda #$01
    .byte $2c
!t20_fail:
    lda #$00
    sta tc_results + 19
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_RING
    sta inv_item_id + EQUIP_RING2
    sta inv_item_id + EQUIP_AMULET
    .if (ITEM_PAGE_RING_OF_LORDLY_PROTECTION_FIRE != 0 || ITEM_PAGE_RING_OF_LORDLY_PROTECTION_COLD != 0 || ITEM_PAGE_AMULET_OF_RESIST_ACID != 0) {
        lda #0
        sta inv_ego + EQUIP_RING
        sta inv_ego + EQUIP_RING2
        sta inv_ego + EQUIP_AMULET
    }
    jsr player_recalc_pflags_equipment

    // Test 21: crown vs regular-helm egos (VMS magic_treasure): on DL50 a
    // magic Silver Crown picks from the 6 crown egos (Magi, Might..Regen;
    // Magi/Might..Seeing p1 1-3, Regen p1 0), rolling Magi at least once;
    // a magic Iron Helm rolls only helm egos (Intelligence/Wisdom/Infra-Vision,
    // never crown egos); an unenchanted crown never rolls an ego.
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3
    lda #0
    sta item_cur_page
    sta tc_count
    sta tc_loop
    sta t_bad
!t21_loop:
    lda #3
    sta fi_add_to_ac
    lda #0
    sta fi_add_p1
    lda #ITEM_SLOT_SILVER_CROWN
    jsr roll_ego_type
    cmp #EGO_NONE
    beq !t21_none+
    cmp #EGO_REGENERATION
    beq !t21_none+              // Regen leaves fi_add_p1 = 0
    cmp #EGO_MAGI
    bne !t21_chk_crown_range+
    inc tc_count
    jmp !t21_chk_p1+
!t21_chk_crown_range:
    cmp #EGO_MIGHT
    bcc !t21_bad+
    cmp #EGO_SEEING + 1
    bcs !t21_bad+
!t21_chk_p1:
    lda fi_add_p1
    beq !t21_bad+
    cmp #4
    bcc !t21_next+
!t21_bad:
    inc t_bad
    jmp !t21_next+
!t21_none:
    lda fi_add_p1               // a plain or Regen crown keeps p1 0
    bne !t21_bad-
!t21_next:
    inc tc_loop
    lda tc_loop
    cmp #250
    bne !t21_loop-
    lda t_bad
    bne !t21_fail+
    lda tc_count
    beq !t21_fail+
    cmp #16
    bcs !t21_fail+
    lda #3
    sta fi_add_to_ac
    lda #0
    sta tc_count
    sta tc_loop
!t21_helm_loop:
    lda #ITEM_SLOT_IRON_HELM                     // Iron Helm: helm egos 25..27 only
    jsr roll_ego_type
    beq !t21_helm_next+
    inc tc_count
    cmp #EGO_INTELLIGENCE
    bcc !t21_fail+
    cmp #EGO_INFRA_VISION + 1
    bcs !t21_fail+
!t21_helm_next:
    inc tc_loop
    lda tc_loop
    cmp #200
    bne !t21_helm_loop-
    lda tc_count
    beq !t21_fail+
    lda #0
    sta fi_add_to_ac
    lda #ITEM_SLOT_JEWEL_ENCRUSTED_CROWN
    jsr t_armour_trials
    lda tc_count
    bne !t21_fail+
    lda #$01
    .byte $2c
!t21_fail:
    lda #$00
    sta tc_results + 20

    // Test 22: worn, a crown of the Magi gives See Invisible and fire, acid
    // and cold resistance (VMS %X'01380008': no lightning); its p1 raises
    // INT on wearing and lowers it on taking off, as the Amulet of the Magi
    lda #ITEM_SLOT_GOLDEN_CROWN
    sta inv_item_id + EQUIP_HEAD
    lda #EGO_MAGI
    sta inv_ego + EQUIP_HEAD
    lda #2
    sta inv_p1 + EQUIP_HEAD
    jsr player_recalc_pflags_equipment
    lda player_pflags
    cmp #PFLAG_SEE_INVIS | PFLAG_RESIST_FIRE | PFLAG_RESIST_ACID | PFLAG_RESIST_COLD
    bne !t22_fail_jmp+
    ldx #EQUIP_HEAD
    jsr equip_stat_index
    bcc !t22_fail_jmp+
    cpy #PL_INT_CUR - PL_STR_CUR
    bne !t22_fail_jmp+
    lda #12
    sta player_data + PL_INT_CUR
    sta zp_player_int
    sta t_to_ac
    lda #EQUIP_HEAD
    sta piw_equip
    sec
    jsr player_adjust_equipment_stat
    lda player_data + PL_INT_CUR
    sec
    sbc t_to_ac
    cmp #2
    bne !t22_fail_jmp+
    lda #EQUIP_HEAD
    sta piw_equip
    clc
    jsr player_adjust_equipment_stat
    lda player_data + PL_INT_CUR
    cmp t_to_ac
    beq !t22_plain+
!t22_fail_jmp:
    jmp !t22_fail+
!t22_plain:
    lda #0                      // a plain crown: no stat
    sta inv_ego + EQUIP_HEAD
    ldx #EQUIP_HEAD
    jsr equip_stat_index
    bcs !t22_fail+
    // Ring of Gain Constitution (+2) at level 5 (CON 16 -> 18) updates zp_player_con
    // and zp_player_mhp on equip, and clamps zp_player_hp down on unequip
    lda #5
    sta player_data + PL_LEVEL
    lda #16
    sta player_data + PL_CON_CUR
    sta zp_player_con
    jsr player_calc_hp
    lda zp_player_mhp_lo
    sta t_to_ac
    lda #ITEM_SLOT_RING_OF_GAIN_CONSTITUTION
    sta inv_item_id + EQUIP_RING
    lda #ITEM_PAGE_RING_OF_GAIN_CONSTITUTION
    sta inv_ego + EQUIP_RING
    lda #2
    sta inv_p1 + EQUIP_RING
    lda #EQUIP_RING
    sta piw_equip
    sec
    jsr player_adjust_equipment_stat
    lda zp_player_con
    cmp #18
    bne !t22_fail+
    lda zp_player_mhp_lo
    sec
    sbc t_to_ac
    cmp #8                      // +2 CON bonus/lvl * 4 levels = +8 MHP
    bne !t22_fail+
    lda zp_player_mhp_lo
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    clc
    jsr player_adjust_equipment_stat
    lda zp_player_con
    cmp #16
    bne !t22_fail+
    lda zp_player_mhp_lo
    cmp t_to_ac
    bne !t22_fail+
    lda zp_player_hp_lo
    cmp t_to_ac
    bne !t22_fail+
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_RING
    lda #0
    sta inv_ego + EQUIP_RING
    sta inv_p1 + EQUIP_RING
    lda #$01
    .byte $2c
!t22_fail:
    lda #$00
    sta tc_results + 21
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_HEAD
    lda #0
    sta inv_ego + EQUIP_HEAD
    sta inv_p1 + EQUIP_HEAD
    jsr player_recalc_pflags_equipment

    // Test 23: the suffix
    lda #EGO_MAGI
    jsr ego_get_suffix_ptr
    ldy #t23_magi_end - t23_magi - 1
!t23_cmp:
    lda (zp_ptr0),y
    cmp t23_magi,y
    bne !t23_fail+
    dey
    bpl !t23_cmp-
    lda #$01
    .byte $2c
!t23_fail:
    lda #$00
    sta tc_results + 22

    // Test 24: player_calc_stats rebuilds the stats from base through the
    // equipment, head to left hand: a crown of the Magi (INT +2), an Amulet
    // of Wisdom (WIS +1) and a Ring of Strength on the left hand (STR +3)
    lda #10
    sta player_data + PL_STR_BASE
    sta player_data + PL_INT_BASE
    sta player_data + PL_WIS_BASE
    lda #ITEM_SLOT_SILVER_CROWN
    sta inv_item_id + EQUIP_HEAD
    lda #EGO_MAGI
    sta inv_ego + EQUIP_HEAD
    lda #2
    sta inv_p1 + EQUIP_HEAD
    lda #ITEM_SLOT_AMULET_OF_WISDOM
    sta inv_item_id + EQUIP_AMULET
    .if (ITEM_PAGE_AMULET_OF_WISDOM != 0) {
        lda #ITEM_PAGE_AMULET_OF_WISDOM
        sta inv_ego + EQUIP_AMULET
    }
    lda #1
    sta inv_p1 + EQUIP_AMULET
    lda #ITEM_SLOT_RING_OF_STRENGTH
    sta inv_item_id + EQUIP_RING2
    .if (ITEM_PAGE_RING_OF_STRENGTH != 0) {
        lda #ITEM_PAGE_RING_OF_STRENGTH
        sta inv_ego + EQUIP_RING2
    }
    lda #3
    sta inv_p1 + EQUIP_RING2
    jsr player_calc_stats
    lda player_data + PL_INT_CUR
    cmp #12
    bne !t24_fail+
    lda player_data + PL_WIS_CUR
    cmp #11
    bne !t24_fail+
    lda player_data + PL_STR_CUR
    cmp #13
    bne !t24_fail+
    lda #$01
    .byte $2c
!t24_fail:
    lda #$00
    sta tc_results + 23
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_HEAD
    sta inv_item_id + EQUIP_AMULET
    sta inv_item_id + EQUIP_RING2
    lda #0
    sta inv_ego + EQUIP_HEAD
    .if (ITEM_PAGE_AMULET_OF_WISDOM != 0) {
        sta inv_ego + EQUIP_AMULET
    }
    .if (ITEM_PAGE_RING_OF_STRENGTH != 0) {
        sta inv_ego + EQUIP_RING2
    }
    sta inv_p1 + EQUIP_HEAD
    sta inv_p1 + EQUIP_AMULET
    sta inv_p1 + EQUIP_RING2

    // Test 25: empty equipment slots (FI_EMPTY) with stale inv_ego bits must
    // yield 0 passive flags (regression guard for player_pflags_cold.s).
    ldx #EQUIP_WEAPON
    lda #FI_EMPTY
!t25_clr:
    sta inv_item_id,x
    inx
    cpx #EQUIP_END
    bne !t25_clr-
    lda #(ITEM_PAGE_BIT | EGO_DEFENDER)
    sta inv_ego + EQUIP_WEAPON
    lda #EGO_RESIST
    sta inv_ego + EQUIP_BODY
    lda #EGO_MAGI
    sta inv_ego + EQUIP_HEAD
    lda #EGO_SPEED
    sta inv_ego + EQUIP_FEET
    lda #(ITEM_PAGE_BIT | EGO_RESIST_ACID)
    sta inv_ego + EQUIP_SHIELD
    jsr player_recalc_pflags_equipment
    lda player_pflags
    ora player_pflags2
    ora player_sust_mask
    ora wield_flags_0
    ora wield_flags_1
    ora wield_flags_2
    ora wield_flags_3
    jsr t_store_zero
    sta tc_results + 24
    lda #0
    sta inv_ego + EQUIP_WEAPON
    sta inv_ego + EQUIP_BODY
    sta inv_ego + EQUIP_HEAD
    sta inv_ego + EQUIP_FEET
    sta inv_ego + EQUIP_SHIELD
    jsr player_recalc_pflags_equipment

    jmp test_exit_trampoline
t12_slot:   .byte 0
t_bad:      .byte 0
t_item:     .byte 0
t_to_ac:    .byte 0
t_ha_count: .byte 0
t19_light:  .text " (Resist Lightning)" ; .byte 0
t19_light_end:
t19_resist: .text " (Resist)" ; .byte 0
t19_resist_end:
t23_magi:   .text " of the Magi" ; .byte 0
t23_magi_end:

// t_armour_trials — 200 roll_ego_type calls for item A with fi_add_to_ac as
// set (restored each time). tc_count = resistances given; t_bad set when one
// is not a resistance ego, or (Resist) did not add 5 to-AC (the others none).
t_armour_trials:
    sta t_item
    lda fi_add_to_ac
    sta t_to_ac
    lda #0
    sta item_cur_page
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
.assert "Ego test body stays below MAP_BASE ($C000)", ego_test_body_end <= MAP_BASE, true
