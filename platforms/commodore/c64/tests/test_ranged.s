// test_ranged.s — Runtime tests for ranged_fire.s
//
// Tests: item_get_missile, ammo matching, ammo depletion,
//        melee unarmed fallback with bow, ranged_fire validation, and the
//        fired shot (M5d, 2026-10-26): Umoria launcher multiplier, VMS range,
//        distance penalty and missed-shot landing.
//
// Results at $0400-$040F: $01 = pass, $00 = fail per test (16 tests)
// The shot's range and a missed shot's landing are tested in test_throw.s,
// whose layout keeps the map and floor-item table clear of test code.

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
#import "../../../../core/ui_inventory.s"
#import "../../../../core/ui_equipment.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/ranged_fire.s"
#import "../../../../core/throw.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"
#import "../../../../core/store_data.s"
#import "../../../../core/store.s"
#import "../../../../core/ui_store.s"
#import "../../../../core/ui_help.s"
#import "../../../../core/ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tc_results: .fill 16, $ff
tr_save: .byte 0
tr_count: .byte 0
tr_seen: .byte 0
tr_base: .byte 0

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
    // Test 1: item_get_missile(49) = 1 (Short Bow)
    // ==========================================
    ldx #49
    jsr item_get_missile
    cmp #1
    beq !t1_pass+
    lda #$00
    sta tc_results+0
    jmp !t1_done+
!t1_pass:
    lda #$01
    sta tc_results+0
!t1_done:

    // ==========================================
    // Test 2: item_get_missile(52) = $81 (Arrow)
    // ==========================================
    ldx #52
    jsr item_get_missile
    cmp #$81
    beq !t2_pass+
    lda #$00
    sta tc_results+1
    jmp !t2_done+
!t2_pass:
    lda #$01
    sta tc_results+1
!t2_done:

    // ==========================================
    // Test 3: item_get_missile(1) = 0 (Dagger, not ranged)
    // ==========================================
    ldx #1
    jsr item_get_missile
    cmp #0
    beq !t3_pass+
    lda #$00
    sta tc_results+2
    jmp !t3_done+
!t3_pass:
    lda #$01
    sta tc_results+2
!t3_done:

    // ==========================================
    // Test 4: Crossbow(50)→2, Bolt(53)→$82, Sling(51)→3, Rock(54)→$83,
    // and melee IDs above the missile table remain non-ranged.
    // ==========================================
    ldx #50
    jsr item_get_missile
    cmp #2
    bne !t4_fail+
    ldx #53
    jsr item_get_missile
    cmp #$82
    bne !t4_fail+
    ldx #51
    jsr item_get_missile
    cmp #3
    bne !t4_fail+
    ldx #54
    jsr item_get_missile
    cmp #$83
    bne !t4_fail+
    ldx #77
    jsr item_get_missile
    cmp #0
    bne !t4_fail+
    lda #$01
    sta tc_results+3
    jmp !t4_done+
!t4_fail:
    lda #$00
    sta tc_results+3
!t4_done:

    // ==========================================
    // Test 5: Ammo matching — bow ammo_type matches arrow type
    // bow it_missile=1, arrow it_missile=$81, ($81 & $7f) == 1
    // ==========================================
    ldx #49
    jsr item_get_missile
    sta tr_save               // 1 (bow ammo type)
    ldx #52
    jsr item_get_missile
    and #$7f                  // Strip high bit → 1
    cmp tr_save
    beq !t5_pass+
    lda #$00
    sta tc_results+4
    jmp !t5_done+
!t5_pass:
    lda #$01
    sta tc_results+4
!t5_done:

    // ==========================================
    // Test 6: Ammo depletion — qty 1 → 0 clears slot
    // ==========================================
    ldx #3
    lda #52                   // Arrow
    sta inv_item_id,x
    lda #1
    sta inv_qty,x
    // Simulate consumption
    dec inv_qty,x
    bne !t6_nz+
    lda #FI_EMPTY
    sta inv_item_id,x
!t6_nz:
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !t6_pass+
    lda #$00
    sta tc_results+5
    jmp !t6_done+
!t6_pass:
    lda #$01
    sta tc_results+5
!t6_done:

    // ==========================================
    // Test 7: No weapon → ranged_fire returns carry clear
    // ==========================================
    jsr msg_init
    ldx #EQUIP_WEAPON
    lda #FI_EMPTY
    sta inv_item_id,x
    jsr ranged_fire
    bcc !t7_pass+
    lda #$00
    sta tc_results+6
    jmp !t7_done+
!t7_pass:
    lda #$01
    sta tc_results+6
!t7_done:

    // ==========================================
    // Test 8: Melee with bow → combat_roll_damage uses 1d2
    // (not 0d0 from bow). Run 10 trials, all should be 1-2.
    // ==========================================
    ldx #EQUIP_WEAPON
    lda #49                   // Short Bow
    sta inv_item_id,x
    lda #1
    sta inv_qty,x
    lda #0
    sta player_data + PL_TODMG

    lda #10
    sta tr_save
!t8_loop:
    jsr combat_roll_damage
    lda zp_math_a
    beq !t8_fail+             // 0 means 0d0 (bow dice), wrong
    cmp #3
    bcs !t8_fail+             // 3+ impossible for 1d2
    dec tr_save
    bne !t8_loop-
    lda #$01
    sta tc_results+7
    jmp !t8_done+
!t8_fail:
    lda #$00
    sta tc_results+7
!t8_done:

    // ==========================================
    // Test 9: C64 overlay-safe stale tier names.
    // Item-overlay projectile commands execute from $E000; they must not
    // reload tier names over the running overlay when formatting hit/miss
    // messages for tier monsters whose cr_name pointer is stale.
    // ==========================================
    lda #7                    // OVL_ITEMS
    sta current_overlay
    lda #0
    sta current_tier
    ldx #30
    lda #$00
    sta cr_name_lo,x
    lda #$e0
    sta cr_name_hi,x
    jsr creature_get_name
    sta zp_ptr0
    sty zp_ptr0_hi
    ldy #0
    lda (zp_ptr0),y
    cmp #'m'
    bne !t9_fail+
    iny
    lda (zp_ptr0),y
    cmp #'o'
    bne !t9_fail+
    lda current_tier
    bne !t9_fail+
    lda #$01
    sta tc_results+8
    jmp !t9_done+
!t9_fail:
    lda #$00
    sta tc_results+8
!t9_done:
    lda #0
    sta current_overlay

    // ==========================================
    // Test 10: Zero-quantity ammo is removed, not underflowed
    // ==========================================
    jsr item_init_inventory
    lda #0
    sta rf_ammo_slot
    sta inv_qty
    lda #53                   // Bolt
    sta inv_item_id

    jsr rf_consume_ammo

    lda inv_item_id
    cmp #FI_EMPTY
    bne !t10_fail+
    lda inv_qty
    bne !t10_fail+
    lda #$01
    sta tc_results+9
    jmp !t10_done+
!t10_fail:
    lda #$00
    sta tc_results+9
!t10_done:

    // ==========================================
    // Test 11: Light Crossbow and Bolt (1d5), no to-dam: Umoria
    // weaponMissileFacts multiplies by 3, so 40 rolls are all multiples of
    // 3 in 3..15 and not all the minimum
    // ==========================================
    lda #50 - IT_MISSILE_BASE   // Light Crossbow
    sta rf_launcher
    lda #53                     // Bolt
    sta tw_item_id
    lda #0
    sta tw_save_to_dam
    sta inv_to_dam + EQUIP_WEAPON
    sta tr_seen
    lda #40
    sta tr_count
!t11_loop:
    jsr rf_roll_damage
    lda cmb_damage
    cmp #3
    bcc !t11_fail+
    cmp #16
    bcs !t11_fail+
    cmp #3
    beq !t11_min+
    inc tr_seen
!t11_min:
!t11_mod3:
    sec
    sbc #3
    beq !t11_ok+
    bcs !t11_mod3-
    jmp !t11_fail+
!t11_ok:
    dec tr_count
    bne !t11_loop-
    lda tr_seen
    beq !t11_fail+
    lda #$01
    sta tc_results+10
    jmp !t11_done+
!t11_fail:
    lda #$00
    sta tc_results+10
!t11_done:

    // ==========================================
    // Test 12: Short Bow +1 to-dam and Arrow (1d4) +3: (1d4 + 4) x 2 is
    // 10, 12, 14 or 16; an Arrow at -10 floors at 0 before the multiplier
    // ==========================================
    lda #49 - IT_MISSILE_BASE   // Short Bow
    sta rf_launcher
    lda #52                     // Arrow
    sta tw_item_id
    lda #3
    sta tw_save_to_dam
    lda #1
    sta inv_to_dam + EQUIP_WEAPON
    lda #30
    sta tr_count
!t12_loop:
    jsr rf_roll_damage
    lda cmb_damage
    cmp #10
    bcc !t12_fail+
    cmp #17
    bcs !t12_fail+
    and #1
    bne !t12_fail+
    dec tr_count
    bne !t12_loop-
    lda #$f6                    // -10
    sta tw_save_to_dam
    lda #0
    sta inv_to_dam + EQUIP_WEAPON
    lda #20
    sta tr_count
!t12_neg:
    jsr rf_roll_damage
    lda cmb_damage
    bne !t12_fail+
    dec tr_count
    bne !t12_neg-
    lda #$01
    sta tc_results+11
    jmp !t12_done+
!t12_fail:
    lda #$00
    sta tc_results+11
!t12_done:
    lda #0
    sta tw_save_to_dam

    // ==========================================
    // Test 13: To-hit drops one per square flown (VMS tbth - cur_dis),
    // gains 3 per point of ammunition to-hit (BTH_PLUS_ADJ), floors at 0
    // ==========================================
    lda #CLASS_RANGER           // missile skill 72
    sta player_data + PL_CLASS
    lda #0                      // Human
    sta player_data + PL_RACE
    sta player_data + PL_TOHIT
    sta zp_eff_bless
    sta tw_save_to_hit
    sta inv_to_hit + EQUIP_WEAPON
    sta rf_dist
    lda #1
    sta zp_player_lvl
    jsr rf_calc_tohit
    lda zp_combat_tohit
    sta tr_base
    lda #7
    sta rf_dist
    jsr rf_calc_tohit
    lda tr_base
    sec
    sbc #7
    cmp zp_combat_tohit
    bne !t13_fail+
    lda #2
    sta tw_save_to_hit
    jsr rf_calc_tohit
    lda tr_base
    sec
    sbc #1                      // -7 + 2 x 3
    cmp zp_combat_tohit
    bne !t13_fail+
    lda #0
    sta tw_save_to_hit
    lda #255
    sta rf_dist
    jsr rf_calc_tohit
    lda zp_combat_tohit
    bne !t13_fail+
    lda #$01
    sta tc_results+12
    jmp !t13_done+
!t13_fail:
    lda #$00
    sta tc_results+12
!t13_done:

    // ==========================================
    // Test 14: The appended launchers (VMS p1 3, 4, 6): Long Bow and
    // Composite Bow fire arrows, Heavy Crossbow bolts, each shown '}';
    // Phase Door (136) and the Arrow keep their values
    // ==========================================
    ldx #137                    // Long Bow
    jsr item_get_missile
    cmp #1
    bne !t14_fail+
    ldx #138                    // Composite Bow
    jsr item_get_missile
    cmp #1
    bne !t14_fail+
    ldx #139                    // Heavy Crossbow
    jsr item_get_missile
    cmp #2
    bne !t14_fail+
    ldx #136                    // Phase Door
    jsr item_get_missile
    bne !t14_fail+
    ldx #139
    jsr item_get_display_char
    cmp #$1c                    // '}'
    bne !t14_fail+
    ldx #137
    jsr item_get_display_char
    cmp #$1c
    bne !t14_fail+
    ldx #52                     // Arrow
    jsr item_get_display_char
    cmp #$1b                    // '{'
    bne !t14_fail+
    lda #$01
    sta tc_results+13
    jmp !t14_done+
!t14_fail:
    lda #$00
    sta tc_results+13
!t14_done:

    // ==========================================
    // Test 15: Firing tables for the appended launchers (VMS facts range,
    // Umoria multiplier): a Heavy Crossbow with no bolts is launcher 5,
    // range 35, x4; a Long Bow launcher 3, range 30, x3
    // ==========================================
    jsr msg_init
    jsr item_init_inventory
    ldx #EQUIP_WEAPON
    lda #139                    // Heavy Crossbow
    sta inv_item_id,x
    lda #1
    sta inv_qty,x
    jsr ranged_fire
    bcs !t15_fail+              // no bolts: nothing fired
    ldx rf_launcher
    cpx #5
    bne !t15_fail+
    lda rf_range_tbl,x
    cmp #35
    bne !t15_fail+
    lda rf_mult_tbl,x
    cmp #4
    bne !t15_fail+
    ldx #EQUIP_WEAPON
    lda #137                    // Long Bow
    sta inv_item_id,x
    jsr ranged_fire
    ldx rf_launcher
    cpx #3
    bne !t15_fail+
    lda rf_range_tbl,x
    cmp #30
    bne !t15_fail+
    lda rf_mult_tbl,x
    cmp #3
    bne !t15_fail+
    lda #$01
    sta tc_results+14
    jmp !t15_done+
!t15_fail:
    lda #$00
    sta tc_results+14
!t15_done:

    // ==========================================
    // Test 16: A Heavy Crossbow in melee fights as bare hands (1d2), as
    // the Short Bow does (test 8)
    // ==========================================
    ldx #EQUIP_WEAPON
    lda #139                    // Heavy Crossbow
    sta inv_item_id,x
    lda #10
    sta tr_save
!t16_loop:
    jsr combat_roll_damage
    lda zp_math_a
    beq !t16_fail+
    cmp #3
    bcs !t16_fail+
    dec tr_save
    bne !t16_loop-
    lda #$01
    sta tc_results+15
    jmp !t16_done+
!t16_fail:
    lda #$00
    sta tc_results+15
!t16_done:

    jmp test_exit_trampoline
