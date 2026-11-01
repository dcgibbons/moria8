// test_monster_attack.s — Runtime tests for monster_attack.s
//
// Tests: mon_atk_calc_tohit, mon_atk_roll_tohit, mon_atk_ac_reduce,
//        mon_atk_apply_damage, player_death_check, poison effect,
//        paralysis effect, aggravation effect, fear, acid armour damage,
//        Protection from Evil repelling evil attackers, no-HP upstream
//        attack types in the shipped tier data (Banshee, Lich), confusion
//        and poison durations through mon_atk_effect_dispatch, the two
//        attacks the shipped rows keep, no-spell casters, the Quylthulg,
//        and full hit dice for CD_MAX_HP creatures (monster_spawn_one).
//
// Results at $0400-$042d: $01 = pass, $00 = fail per test
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
    ldx #45
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
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "../../../../core/dungeon_gen.s"
#import "../../../../core/huffman.s"
#import "../../../../core/dungeon_features.s"
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/recall.s"
viewport_update:
render_viewport:
render_single_tile:
render_local_area:
    rts
#import "../../../../core/monster_attack.s"

combat_append_str:
combat_append_monster_name:
cmb_term_and_print:
combat_msg_monster_in_way:
inv_remove_item:
inv_consume_one:
tramp_assign_special_room:
tramp_vault_seal_entrance:
tramp_spawn_special_room_monsters:
    rts
player_get_infra_range:
    lda #0
    rts
mm_los_clear_to_target:
    clc
    rts

eff_fear_timer:
    .byte 0
eff_detect_timer:
    .byte 0
vis_room_revealed:
    .byte 0
cmb_type:
    .byte 0
cmb_buf_idx:
    .byte 0
cmb_the_str:
    .text "THE " ; .byte 0
inv_qty:
    .fill 31, 0
inv_item_id:
    .fill TOTAL_INV_SLOTS, FI_EMPTY
inv_p1:
    .fill TOTAL_INV_SLOTS, 0
it_color_ac:
    .fill ITEM_TYPE_COUNT, 0
item_get_base_ac:
    lda it_color_ac,y
    and #$0f
    rts
inv_to_ac:
    .fill TOTAL_INV_SLOTS, 0
inv_to_hit:
    .fill TOTAL_INV_SLOTS, 0
inv_to_dam:
    .fill TOTAL_INV_SLOTS, 0
inv_flags:
    .fill TOTAL_INV_SLOTS, 0
inv_ego:
    .fill TOTAL_INV_SLOTS, 0
// Acid armour damage (monster_acid.s) callees outside the attack module
inv_slot_to_fi_add:
item_append_desc:
    rts
player_recalc_equipment:
    inc tc_recalcs
    rts
tc_recalcs: .byte 0

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .byte 0

// Test scratch
tc_loop:    .byte 0
tc_ok:      .byte 0
tc_results: .fill 46, $ff      // Result buffer (copied to $0400 at end)
tc_repels:  .byte 0             // " is repelled." summaries seen
tc_hurt:    .byte 0             // Rounds that did damage or poisoned
.const NA_BANSHEE = 11          // tier4.s index map: [196] DL24 Banshee
.const NA_LICH    = 36          // tier4.s index map: [239] DL34 Lich
.const NA_QUYLTHULG   = 0       // [174] DL20 Quylthulg
.const NA_GIANT_TROLL = 12      // [197] DL25 Giant Troll
.const NA_GHOST       = 28      // [227] DL31 Ghost
.const NA_IRIDESCENT  = 44      // [256] DL37 Iridescent Beetle
.const NA_ANCIENT_RED = 52      // [273] DL40 Ancient Red Dragon
.const NA_BALROG      = 56      // [278] DL100 Balrog
tc_msgs:    .byte 0             // Effect/summary messages seen (spy)
tc_rec:     .word 0             // na_row_check record pointer
tc_hp_lo:   .byte 0             // mh_spawn: the spawned HP
tc_hp_hi:   .byte 0

// Effect-message spy: counts the " is repelled." summary (zp_ptr2).
mon_atk_build_effect_msg:
    inc tc_msgs
    ldy #0
!mabm_cmp:
    lda (zp_ptr2),y
    cmp tc_repelled_text,y
    bne !mabm_other+
    iny
    cmp #0
    bne !mabm_cmp-
    inc tc_repels
!mabm_other:
    rts
tc_repelled_text: .text " is repelled." ; .byte 0
tc_fear_start: .byte 0          // fear_attempt: timer before each attempt
tc_saved:   .byte 0
tc_afraid:  .byte 0

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

    // Initialize message system
    jsr msg_init

    // Initialize sound (needed to avoid crash on sound_play)
    jsr hal_sound_init

    // Pre-stuff keyboard buffer for -more- prompts
    lda #8
    sta $c6
    lda #$20
    sta $0277
    sta $0278
    sta $0279
    sta $027a
    sta $027b
    sta $027c
    sta $027d
    sta $027e

    // ==========================================
    // Test 1: mon_atk_calc_tohit type 1 (Normal), level 2
    // Base 60 + 2*3 = 66
    // ==========================================
    lda #ATK_NORMAL
    sta mat_atk_type
    lda #0                      // Creature type 0 (White harpy, level 2)
    sta mat_type2

    jsr mon_atk_calc_tohit

    lda zp_combat_tohit
    cmp #66
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // ==========================================
    // Test 2: mon_atk_calc_tohit type 14 (Poison), level 4
    // Base 5 + 4*3 = 17
    // Creature type 12 = Giant White Rat, level 4
    // ==========================================
!t2:
    lda #ATK_POISON
    sta mat_atk_type
    lda #12                     // Giant White Rat (level 4)
    sta mat_type2

    jsr mon_atk_calc_tohit

    lda zp_combat_tohit
    cmp #17
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // ==========================================
    // Test 3: mon_atk_roll_tohit high tohit vs AC 0 — high hit rate
    // tohit=60, AC=0 → should hit most of the time (>80%)
    // Run 20 trials, count hits
    // ==========================================
!t3:
    lda #60
    sta zp_combat_tohit
    lda #0
    sta zp_player_ac
    lda #20
    sta tc_loop
    lda #0
    sta tc_ok                   // Hit counter

!t3_loop:
    jsr mon_atk_roll_tohit
    bcc !t3_miss+
    inc tc_ok
!t3_miss:
    dec tc_loop
    bne !t3_loop-

    // Expect at least 16 hits out of 20 (80%)
    lda tc_ok
    cmp #16
    bcc !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // ==========================================
    // Test 4: mon_atk_ac_reduce AC=100, damage=10
    // Reduction = (100*10)/200 = 5, result = 5
    // ==========================================
!t4:
    lda #100
    sta zp_player_ac
    lda #10
    sta zp_combat_dmg

    jsr mon_atk_ac_reduce

    lda zp_combat_dmg
    cmp #5
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // ==========================================
    // Test 5: mon_atk_ac_reduce AC=10, damage=8
    // Reduction = (10*8)/200 = 0, result = 8 (no change)
    // ==========================================
!t5:
    lda #10
    sta zp_player_ac
    lda #8
    sta zp_combat_dmg

    jsr mon_atk_ac_reduce

    lda zp_combat_dmg
    cmp #8
    bne !t5_fail+
    lda #$01
    sta tc_results + 4
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results + 4

    // ==========================================
    // Test 6: mon_atk_apply_damage HP 20→15
    // Set player HP to 20, damage 5, verify HP=15
    // ==========================================
!t6:
    lda #20
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #5
    sta zp_combat_dmg

    jsr mon_atk_apply_damage
    bcs !t6_fail+               // Should not be dead

    lda zp_player_hp_lo
    cmp #15
    bne !t6_fail+
    lda #$01
    sta tc_results + 5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 5

    // ==========================================
    // Test 7: mon_atk_apply_damage HP→0 triggers death
    // Set HP to 3, damage 3, verify game_flags bit 0 set
    // ==========================================
!t7:
    lda #0
    sta zp_game_flags           // Clear game flags
    lda #3
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #3
    sta zp_combat_dmg

    jsr mon_atk_apply_damage
    bcc !t7_fail+               // Should be dead (carry set)

    jsr player_death_check
    lda zp_game_flags
    and #$01
    beq !t7_fail+               // Bit 0 should be set
    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // ==========================================
    // Test 8: Poison effect sets timer
    // Use creature type 2 (White Worm Mass, level 1, ATK_POISON)
    // ==========================================
!t8:
    lda #0
    sta zp_game_flags           // Reset game flags
    sta zp_eff_poison           // Clear existing poison

    lda #2                      // White Worm Mass
    sta mat_type2

    jsr mon_atk_effect_poison

    lda zp_eff_poison
    beq !t8_fail+               // Should be > 0
    lda #$01
    sta tc_results + 7
    jmp !t9+
!t8_fail:
    lda #$00
    sta tc_results + 7

    // ==========================================
    // Test 9: Paralysis effect sets timer (force fail)
    // Use creature type 8 (Floating Eye, level 2)
    // Warrior: save = race save + 18 + con_adj (VMS player_saves(con_adj),
    // MON-011), well under 100, so repeated attempts must paralyze
    // Run multiple attempts until paralyzed (save roll is random)
    // ==========================================
!t9:
    lda #0
    sta zp_eff_paralyze
    sta player_data + PL_FLAGS  // No free action
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #8                      // Floating Eye
    sta mat_type2

    lda #20
    sta tc_loop
!t9_loop:
    lda #0
    sta zp_eff_paralyze         // Reset each attempt
    jsr mon_atk_effect_paralyze
    lda zp_eff_paralyze
    bne !t9_pass+               // Got paralyzed
    dec tc_loop
    bne !t9_loop-
    // 20 attempts all resisted — unlikely but possible, fail
    lda #$00
    sta tc_results + 8
    jmp !t10+
!t9_pass:
    lda #$01
    sta tc_results + 8

    // ==========================================
    // Test 10: Aggravation wakes sleeping monsters
    // Spawn 3 monsters (asleep), call mon_atk_effect_aggravate,
    // check all have MF_AWAKE set
    // ==========================================
!t10:
    lda #0
    sta zp_game_flags
    jsr monster_init_table

    // Place player at (5,5) so spawn positions don't conflict
    lda #5
    sta zp_player_x
    sta zp_player_y

    // Manually create 3 monsters (asleep)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #4                      // Kobold
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0                      // Asleep
    sta (zp_ptr0),y
    ldy #MX_X
    lda #10
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #10
    sta (zp_ptr0),y

    ldx #1
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #9                      // Jackal
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0                      // Asleep
    sta (zp_ptr0),y
    ldy #MX_X
    lda #20
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #20
    sta (zp_ptr0),y

    ldx #2
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #1                      // Giant White Mouse
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0                      // Asleep
    sta (zp_ptr0),y
    ldy #MX_X
    lda #30
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #30
    sta (zp_ptr0),y

    ldx #2
!t10_seed_sleep:
    jsr monster_get_ptr
    ldy #MX_SLEEP_CUR
    lda #9
    sta (zp_ptr0),y
    dex
    bpl !t10_seed_sleep-

    jsr mon_atk_effect_aggravate

    // Check all 3 have MF_AWAKE
    lda #1
    sta tc_ok

    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    bne !t10_c1+
    lda #0
    sta tc_ok
!t10_c1:
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    bne !t10_bad+
    ldx #1
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    bne !t10_c2+
    lda #0
    sta tc_ok
!t10_c2:
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    bne !t10_bad+
    ldx #2
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    bne !t10_c3+
    lda #0
    sta tc_ok
!t10_c3:
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    bne !t10_bad+
    jmp !t10_store+
!t10_bad:
    lda #0
    sta tc_ok
!t10_store:
    lda tc_ok
    sta tc_results + 9

    // ==========================================
    // Test 11: Fear attack, failed save (MON-012; VMS creature.inc /
    // Umoria monster.cpp): a new fear lasts 3 + randint(level). White
    // Harpy (level 2): 4-5. Half-Troll Warrior, WIS 3: save 10 (-8 + 18 +
    // wis_adj 0), so an attempt soon fails.
    // ==========================================
!t11:
    lda #7                      // Half-Troll
    sta player_data + PL_RACE
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #3
    sta player_data + PL_WIS_CUR
    lda #0                      // White Harpy (level 2)
    sta mat_type2
    lda #0
    jsr fear_until_afraid
    bcc !t11_fail+
    cmp #4
    bcc !t11_fail+
    cmp #6
    bcs !t11_fail+
    lda #$01
    sta tc_results + 10
    jmp !t13+
!t11_fail:
    lda #$00
    sta tc_results + 10
    jmp !t13+

    // ==========================================
    // Test 12: Holy Word invulnerability blocks melee damage
    // ==========================================
!t13:
    lda #50
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #3
    sta eff_invuln_timer
    lda #10
    sta zp_combat_dmg
    jsr mon_atk_apply_damage
    bcs !t13_fail+
    lda zp_player_hp_lo
    cmp #50
    bne !t13_fail+
    lda zp_player_hp_hi
    beq !t13_ok+
!t13_fail:
    lda #$00
    sta tc_results + 11
    jmp !t14+
!t13_ok:
    lda #$01
    sta tc_results + 11

    // ==========================================
    // Test 13: bless contributes +2 effective AC for monster damage reduction.
    // AC 98 + bless 2, damage 10: reduction 5, result 5.
    // ==========================================
!t14:
    lda #98
    sta zp_player_ac
    lda #1
    sta zp_eff_bless
    lda #10
    sta zp_combat_dmg

    jsr mon_atk_ac_reduce

    lda #0
    sta zp_eff_bless
    lda zp_combat_dmg
    cmp #5
    bne !t14_fail+
    lda #$01
    sta tc_results + 12
    jmp !t15+
!t14_fail:
    lda #$00
    sta tc_results + 12

    // ==========================================
    // Test 14: heroism blocks new fear from monster attacks.
    // ==========================================
!t15:
    lda #0
    sta eff_fear_timer
    lda #5
    sta zp_eff_hero
    lda #0                      // White Harpy
    sta mat_type2

    jsr mon_atk_effect_fear

    lda #0
    sta zp_eff_hero
    lda eff_fear_timer
    bne !t15_fail+
    lda #$01
    sta tc_results + 13
    jmp !t16+
!t15_fail:
    lda #$00
    sta tc_results + 13

    // ==========================================
    // Test 15: a failed save while afraid adds 3 (VMS afraid := afraid + 3)
    // ==========================================
!t16:
    lda #10
    jsr fear_until_afraid
    bcc !t16_fail+
    cmp #13
    bne !t16_fail+
    lda #$01
    sta tc_results + 14
    jmp !t17+
!t16_fail:
    lda #$00
    sta tc_results + 14

    // ==========================================
    // Test 16: the fear timer saturates at 255
    // ==========================================
!t17:
    lda #254
    jsr fear_until_afraid
    bcc !t17_fail+
    cmp #$ff
    bne !t17_fail+
    lda #$01
    sta tc_results + 15
    jmp !t18+
!t17_fail:
    lda #$00
    sta tc_results + 15

    // ==========================================
    // Test 17: the save resists. Halfling Mage, WIS 18/100: save 61 (18 +
    // 36 + wis_adj 7). Of 30 attempts from no fear, some must resist (timer
    // stays 0) and some must not.
    // ==========================================
!t18:
    lda #3                      // Halfling
    sta player_data + PL_RACE
    lda #CLASS_MAGE
    sta player_data + PL_CLASS
    lda #118
    sta player_data + PL_WIS_CUR
    lda #0
    sta tc_saved
    sta tc_afraid
    lda #30
    sta tc_loop
!t18_loop:
    lda #0
    sta eff_fear_timer
    jsr mon_atk_effect_fear
    lda eff_fear_timer
    bne !t18_afraid+
    inc tc_saved
    bne !t18_next+              // Always taken
!t18_afraid:
    inc tc_afraid
!t18_next:
    dec tc_loop
    bne !t18_loop-
    lda tc_saved
    beq !t18_fail+
    lda tc_afraid
    beq !t18_fail+
    lda #$01
    sta tc_results + 16
    jmp !t19+
!t18_fail:
    lda #$00
    sta tc_results + 16

    // ==========================================
    // Tests 18-22: acid (MON-015; pinned VMS moria.inc acid_dam/minus_ac).
    // Base AC from the item table: Leather armor 4, Small shield 2,
    // Leather gloves 1.
    // ==========================================
!t19:
    lda #4
    sta it_color_ac + 7
    lda #2
    sta it_color_ac + 9
    lda #1
    sta it_color_ac + 11

    // Test 18: body armour only, AC 4 + 0: damage 7 -> 3 (div 2), to-AC -1,
    // equipment recalculated
    jsr acid_clear_armour
    lda #7
    sta inv_item_id + EQUIP_BODY
    lda #7
    jsr acid_hit
    cmp #3
    bne !t19_fail+
    lda inv_to_ac + EQUIP_BODY
    cmp #$ff
    bne !t19_fail+
    lda tc_recalcs
    cmp #1
    bne !t19_fail+
    lda #$01
    sta tc_results + 17
    jmp !t20+
!t19_fail:
    lda #$00
    sta tc_results + 17

    // Test 19: worn out (AC 4, to-AC -4): full damage, nothing changes
!t20:
    jsr acid_clear_armour
    lda #7
    sta inv_item_id + EQUIP_BODY
    lda #$fc
    sta inv_to_ac + EQUIP_BODY
    lda #8
    jsr acid_hit
    cmp #8
    bne !t20_fail+
    lda inv_to_ac + EQUIP_BODY
    cmp #$fc
    bne !t20_fail+
    lda tc_recalcs
    bne !t20_fail+
    lda #$01
    sta tc_results + 18
    jmp !t21+
!t20_fail:
    lda #$00
    sta tc_results + 18

    // Test 20: no armour worn: full damage
!t21:
    jsr acid_clear_armour
    lda #8
    jsr acid_hit
    cmp #8
    bne !t21_fail+
    lda tc_recalcs
    bne !t21_fail+
    lda #$01
    sta tc_results + 19
    jmp !t22+
!t21_fail:
    lda #$00
    sta tc_results + 19

    // Test 21: the last slot (gloves only) is found and damaged
!t22:
    jsr acid_clear_armour
    lda #11
    sta inv_item_id + EQUIP_HANDS
    lda #8
    jsr acid_hit
    cmp #4
    bne !t22_fail+
    lda inv_to_ac + EQUIP_HANDS
    cmp #$ff
    bne !t22_fail+
    lda #$01
    sta tc_results + 20
    jmp !t23+
!t22_fail:
    lda #$00
    sta tc_results + 20

    // Test 22: body armour (AC 4) and a worn-out shield (2, -2): the piece is
    // chosen at random among those worn, so over 40 hits both outcomes occur
!t23:
    lda #0
    sta tc_saved
    sta tc_afraid
    lda #40
    sta tc_loop
!t23_loop:
    jsr acid_clear_armour
    lda #7
    sta inv_item_id + EQUIP_BODY
    lda #9
    sta inv_item_id + EQUIP_SHIELD
    lda #$fe
    sta inv_to_ac + EQUIP_SHIELD
    lda #8
    jsr acid_hit
    cmp #4
    bne !t23_full+
    inc tc_saved                // body chosen: halved
    bne !t23_next+              // Always taken
!t23_full:
    inc tc_afraid               // shield chosen: full damage
!t23_next:
    dec tc_loop
    bne !t23_loop-
    lda tc_saved
    beq !t23_fail+
    lda tc_afraid
    beq !t23_fail+
    lda #$01
    sta tc_results + 21
    jmp !t24+
!t23_fail:
    lda #$00
    sta tc_results + 21

    // ==========================================
    // Tests 23-26: Protection from Evil through production
    // monster_attack_player. VMS Moria creature.inc make_attack: while
    // protevil > 0, an attack of a creature with the evil defence bit whose
    // level satisfies (py.misc.lev + 1) > level becomes type 99, which
    // always "hits" and only prints "<name> is repelled." (no damage, no
    // effect); Umoria monster.cpp monsterAttackPlayer is identical. Test
    // creature (row 26): 4d4 normal hit, then 1d1 poison; player level 5,
    // AC 0, so an unprotected round almost always hurts.
    // ==========================================
!t24:
    lda #ATK_NORMAL
    sta cr_atk0_type + 26
    lda #4
    sta cr_atk0_dice + 26
    sta cr_atk0_sides + 26
    lda #ATK_POISON
    sta cr_atk1_type + 26
    lda #1
    sta cr_atk1_dice + 26
    sta cr_atk1_sides + 26
    lda #5
    sta zp_player_lvl
    lda #0
    sta zp_player_ac
    sta zp_eff_bless
    sta eff_invuln_timer

    // Test 23: evil, creature level 5 = player level 5 (the boundary),
    // protected: 12 rounds, every one repelled, none hurts, the timer is
    // not consumed by the repel.
    lda #CF_EVIL
    ldx #5
    ldy #9
    jsr rp_rounds
    lda tc_hurt
    bne !t24_fail+
    lda tc_repels
    cmp #12
    bne !t24_fail+
    lda zp_eff_protect
    cmp #9
    bne !t24_fail+
    lda #$01
    sta tc_results + 22
    jmp !t25+
!t24_fail:
    lda #$00
    sta tc_results + 22

    // Test 24: evil but level 6 > player level 5: not repelled
!t25:
    lda #CF_EVIL
    ldx #6
    ldy #9
    jsr rp_rounds
    jsr rp_expect_hurt
    sta tc_results + 23

    // Test 25: not evil (animal), level 5: not repelled
    lda #CF_ANIMAL
    ldx #5
    ldy #9
    jsr rp_rounds
    jsr rp_expect_hurt
    sta tc_results + 24

    // Test 26: evil, level 5, protection 0: not repelled
    lda #CF_EVIL
    ldx #5
    ldy #0
    jsr rp_rounds
    jsr rp_expect_hurt
    sta tc_results + 25

    // ==========================================
    // Tests 27-30: upstream attack types that deal no HP damage, in the
    // shipped tier data (tools/parse_creatures.py -> tier4.s) and through
    // production monster_attack_player. Pinned VMS Moria creature.inc
    // make_attack: types 12, 13 and 19-24 never call take_hit (Lose
    // experience, 19, feeds its dice to lose_exp as experience); Umoria
    // monster.cpp executeAttackOnPlayer is identical (no playerTakesHit).
    // Moria8 has no such effects, so the generator keeps the attack as a 0d0
    // ATK_NORMAL touch.
    // Banshee: VMS values.inc:2514-2515 '4 10 0d0|19 5 14d8' (Umoria
    // data_creatures.cpp:342 attacks 99, 188 = {4,10,{0,0}}, {19,5,{14,8}}).
    // Lich: VMS values.inc:2605-2606 '15 5 2d8|19 5 30d8|24 5 0d0' (Umoria
    // identical); its Lose DEX 2d8 does hurt (take_hit), Moria8 poison.
    // ==========================================

    // Test 27: tier4 #11 is the Banshee: fear 0d0, then a 0d0 touch
    ldx #NA_BANSHEE
    lda #<tc_banshee_name
    ldy #>tc_banshee_name
    jsr na_name_is
    bne !t27_fail+
    lda #<tc_banshee_atks
    ldy #>tc_banshee_atks
    jsr na_atks_are
    bne !t27_fail+
    lda #$01
    sta tc_results + 26
    jmp !t28+
!t27_fail:
    lda #$00
    sta tc_results + 26

    // Test 28: tier4 #36 is the Lich: 2d8 poison (Lose DEX), then a 0d0 touch
!t28:
    ldx #NA_LICH
    lda #<tc_lich_name
    ldy #>tc_lich_name
    jsr na_name_is
    bne !t28_fail+
    lda #<tc_lich_atks
    ldy #>tc_lich_atks
    jsr na_atks_are
    bne !t28_fail+
    lda #$01
    sta tc_results + 27
    jmp !t29+
!t28_fail:
    lda #$00
    sta tc_results + 27

    // Test 29: 12 production rounds by the shipped Banshee cost no HP
    // (before the fix its 14d8 touch took 14-112 a hit)
!t29:
    ldx #NA_BANSHEE
    jsr na_rounds
    lda tc_hurt
    ora tc_big
    bne !t29_fail+
    lda #$01
    sta tc_results + 28
    jmp !t30+
!t29_fail:
    lda #$00
    sta tc_results + 28

    // Test 30: 12 production rounds by the shipped Lich: some cost HP (its
    // 2d8), none more than 16 (its 30d8 touch is gone)
!t30:
    ldx #NA_LICH
    jsr na_rounds
    lda tc_big
    bne !t30_fail+
    lda tc_hurt
    beq !t30_fail+
    lda tc_maxloss
    cmp #16 + 1
    bcs !t30_fail+
    lda #$01
    sta tc_results + 29
    jmp !t31+
!t30_fail:
    lda #$00
    sta tc_results + 29

    // ==========================================
    // Tests 31-35: confusion and poison durations, 128 production
    // mon_atk_effect_dispatch calls each (eff_sweep). randint(N) is 1..N
    // (VMS source/macro/randint.mar; Umoria game.cpp randomNumber).
    // Confusion (VMS creature.inc:404-417; Umoria monster.cpp:1563-1576):
    // 50% (randint(2) = 1); if not confused, confused += randint(level);
    // then confused += 3. Poison (VMS creature.inc:521-527; Umoria
    // monster.cpp:1665-1669): poisoned += randint(level) + 5.
    // ==========================================

    // Test 31: a new confusion by a level-4 creature lasts 4-7 turns, and
    // both ends occur (randint(4) + 3)
!t31:
    lda #ATK_CONFUSE
    ldx #0
    ldy #4
    jsr eff_sweep
    lda #4
    ldx #7
    jsr eff_range_is
    sta tc_results + 30

    // Test 32: an existing confusion gains exactly 3 (10 -> 13)
    lda #ATK_CONFUSE
    ldx #10
    ldy #4
    jsr eff_sweep
    lda #13
    ldx #13
    jsr eff_range_is
    sta tc_results + 31

    // Test 33: a level-4 poisoning from none lasts 6-9 turns, and both ends
    // occur (randint(4) + 5)
    lda #ATK_POISON
    ldx #0
    ldy #4
    jsr eff_sweep
    lda #6
    ldx #9
    jsr eff_range_is
    sta tc_results + 32

    // Test 34: poison stacks: from 20, a level-4 poisoning gives 26-29
    lda #ATK_POISON
    ldx #20
    ldy #4
    jsr eff_sweep
    lda #26
    ldx #29
    jsr eff_range_is
    sta tc_results + 33

    // Test 35: level 1 (randint(1) = 1): a new confusion lasts exactly 4
    // and a new poisoning exactly 6
    lda #ATK_CONFUSE
    ldx #0
    ldy #1
    jsr eff_sweep
    lda #4
    ldx #4
    jsr eff_range_is
    sta tc_ok
    lda #ATK_POISON
    ldx #0
    ldy #1
    jsr eff_sweep
    lda #6
    ldx #6
    jsr eff_range_is
    and tc_ok
    sta tc_results + 34

    // ==========================================
    // Tests 36-40: which two of up to four upstream attacks the shipped tier4
    // rows keep (tools/parse_creatures.py select_attack_slots: paralysis
    // first, then expected damage, then a Moria8 effect, then the earlier
    // slot; kept in upstream order). Rows from pinned VMS values.inc c_list
    // (Umoria data_creatures.cpp identical), type mapping as the generator's
    // table: fire/cold/blind/lose INT -> ATK_NORMAL, no-HP types -> 0d0.
    // Before 2026-11-01 the first two were kept.
    // ==========================================

    // Test 36: Ancient Red Dragon, values.inc:2671 '1 3 1d10|1 3 1d10|1 2
    // 2d14': its 2d14 bite (was 1d10, 1d10)
    ldx #NA_ANCIENT_RED
    lda #<tc_ard_row
    ldy #>tc_ard_row
    jsr na_row_check
    sta tc_results + 35

    // Test 37: Giant Troll, values.inc:2516 '1 1 1d6|1 1 1d6|1 2 3d4': its
    // 3d4 bite (was 1d6, 1d6)
    ldx #NA_GIANT_TROLL
    lda #<tc_gtroll_row
    ldy #>tc_gtroll_row
    jsr na_row_check
    sta tc_results + 36

    // Test 38: Ghost, values.inc:2579 '4 7 0d0|19 5 22d8|17 3 1d10': the
    // fear wail and the 1d10 lose-INT claw (ATK_NORMAL), not the 0d0
    // drain-experience touch (was FEAR 0d0, NORMAL 0d0)
    ldx #NA_GHOST
    lda #<tc_ghost_row
    ldy #>tc_ghost_row
    jsr na_row_check
    sta tc_results + 37

    // Test 39: Iridescent Beetle, values.inc:2639 '1 2 4d6|1 1 1d12|11 7
    // 0d0': the 4d6 bite and the paralysing gaze (was 4d6, 1d12)
    ldx #NA_IRIDESCENT
    lda #<tc_irid_row
    ldy #>tc_irid_row
    jsr na_row_check
    sta tc_results + 38

    // Test 40: 12 production monster_attack_player rounds by the shipped
    // Ancient Red Dragon: some round costs more than 20 HP (two 1d10 blows
    // could not), none more than 38 (1d10 + 2d14)
    ldx #NA_ANCIENT_RED
    jsr na_rounds
    lda tc_big
    bne !t40_fail+
    lda tc_maxloss
    cmp #20 + 1
    bcc !t40_fail+
    cmp #38 + 1
    bcs !t40_fail+
    lda #$01
    .byte $2c
!t40_fail:
    lda #$00
    sta tc_results + 39

    // Test 41: no shipped tier4 creature has a spell chance without a spell
    // (tools/parse_creatures.py map_spells: none of the upstream spells maps,
    // e.g. the Banshee and Ghost, VMS spells %X'0001002F' = teleport self and
    // drain mana, so chance 0; monster_can_cast then never spends a turn)
    ldx #tier4_cr_spell_flags - tier4_cr_spell_chance - 1   // TIER_COUNT - 1
!t41_loop:
    lda tier4_cr_spell_chance,x
    beq !t41_next+
    lda tier4_cr_spell_flags,x
    beq !t41_fail+
!t41_next:
    dex
    bpl !t41_loop-
    lda tier4_cr_spell_chance + NA_GHOST
    ora tier4_cr_spell_chance + NA_BANSHEE
    bne !t41_fail+
    lda #$01
    .byte $2c
!t41_fail:
    lda #$00
    sta tc_results + 40

    // Test 42: the Quylthulg (Umoria data_creatures.cpp:320: CMOVE
    // $00010004, CM_ONLY_MAGIC; attacks {0,0,0,0}; not in VMS) never moves
    // upstream (Umoria monster.cpp monsterMove moves only with
    // CM_MOVE_NORMAL or a random bit): CF_ATTACK_ONLY, no attack slot
    ldx #NA_QUYLTHULG
    lda tier4_cr_mflags,x
    and #CF_ATTACK_ONLY
    beq !t42_fail+
    lda tier4_cr_atk0_type,x
    ora tier4_cr_atk1_type,x
    bne !t42_fail+
    lda #$01
    .byte $2c
!t42_fail:
    lda #$00
    sta tc_results + 41

    // Test 43: 12 production rounds by the shipped Quylthulg next to the
    // player: no physical attack, so no HP lost, no hit/miss line and no
    // recall attack count (before: 12 "misses you." lines and counts)
    lda #0
    sta tc_msgs
    lda recall_attacks + 26
    sta tc_ok
    ldx #NA_QUYLTHULG
    jsr na_rounds
    lda tc_hurt
    ora tc_big
    ora tc_msgs
    bne !t43_fail+
    lda recall_attacks + 26
    cmp tc_ok
    bne !t43_fail+
    lda #$01
    .byte $2c
!t43_fail:
    lda #$00
    sta tc_results + 42

    // Test 44: CD_MAX_HP (Umoria cdefense $4000, VMS %X'4000') lands in
    // cr_speed bit 7: set for the Balrog (VMS values.inc:2685 %X'5004') and
    // Quylthulg (Umoria :320 $5000), clear for the Giant Troll (VMS :2516
    // %X'2026')
    lda tier4_cr_speed + NA_BALROG
    and tier4_cr_speed + NA_QUYLTHULG
    bpl !t44_fail+
    lda tier4_cr_speed + NA_GIANT_TROLL
    bmi !t44_fail+
    lda #$01
    .byte $2c
!t44_fail:
    lda #$00
    sta tc_results + 43

    // Test 45: production monster_spawn_one gives the shipped Balrog its full
    // hit dice every time: VMS misc.inc place_monster (cdefense $4000 ->
    // max_hp('375d8') = 3000; Umoria 75d40 = 3000), 4 spawns (was a roll,
    // about 1537)
    lda #4
    sta tc_loop
!t45_loop:
    ldx #NA_BALROG
    jsr mh_spawn
    lda tc_hp_lo
    cmp #<3000
    bne !t45_fail+
    lda tc_hp_hi
    cmp #>3000
    bne !t45_fail+
    dec tc_loop
    bne !t45_loop-
    lda #$01
    .byte $2c
!t45_fail:
    lda #$00
    sta tc_results + 44

    // Test 46: a creature without CD_MAX_HP still rolls: 8 shipped Giant
    // Trolls (19d8) each have 19-152 HP and not all 152
    lda #8
    sta tc_loop
    lda #0
    sta tc_ok
!t46_loop:
    ldx #NA_GIANT_TROLL
    jsr mh_spawn
    lda tc_hp_hi
    bne !t46_fail+
    lda tc_hp_lo
    cmp #19
    bcc !t46_fail+
    cmp #152 + 1
    bcs !t46_fail+
    cmp #152
    beq !t46_next+
    inc tc_ok
!t46_next:
    dec tc_loop
    bne !t46_loop-
    lda tc_ok
    beq !t46_fail+
    lda #$01
    .byte $2c
!t46_fail:
    lda #$00
    sta tc_results + 45

!tests_done:
    jmp test_exit_trampoline

// na_row_check — A = $01 when tier4 creature X has the six attack bytes
// and then the zero-terminated name at A/Y (lo/hi), else $00.
na_row_check:
    sta tc_rec
    sty tc_rec + 1
    jsr na_atks_are             // Preserves X
    bne !nrc_fail+
    lda tc_rec
    clc
    adc #6
    pha
    lda tc_rec + 1
    adc #0
    tay
    pla
    jsr na_name_is
    bne !nrc_fail+
    lda #$01
    rts
!nrc_fail:
    lda #$00
    rts

// mh_spawn — Copy tier4 creature X's hit dice, cr_speed and sleep into
// roster row 26 and spawn one through production monster_spawn_one at
// (10,10) on an empty table. Output: tc_hp_lo/hi = its HP.
mh_spawn:
    lda tier4_cr_hd_num,x
    sta cr_hd_num + 26
    lda tier4_cr_hd_sides,x
    sta cr_hd_sides + 26
    lda tier4_cr_speed,x
    sta cr_speed + 26
    lda tier4_cr_sleep,x
    sta cr_sleep + 26
    jsr monster_init_table
    lda #10
    sta ms_spawn_x
    sta ms_spawn_y
    lda #26
    jsr monster_spawn_one
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sta tc_hp_lo
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    sta tc_hp_hi
    rts

// acid_clear_armour — Empty the body..hands slots and zero their to-AC.
acid_clear_armour:
    ldx #EQUIP_BODY
!aca_loop:
    lda #FI_EMPTY
    sta inv_item_id,x
    lda #0
    sta inv_to_ac,x
    inx
    cpx #EQUIP_HANDS + 1
    bne !aca_loop-
    lda #0
    sta tc_recalcs
    rts

// acid_hit — Production acid effect on damage A. Output: A = damage dealt.
acid_hit:
    sta zp_combat_dmg
    lda #0
    sta mat_type2
    jsr mon_atk_effect_acid
    lda zp_combat_dmg
    rts

// eff_sweep — 128 production mon_atk_effect_dispatch calls with attack type
// A by roster row 26 at level Y, each from timer X (zp_eff_confuse for
// ATK_CONFUSE, else zp_eff_poison). Output: tc_min/tc_max = smallest and
// largest timer that changed ($ff/$00 when none did).
eff_sweep:
    sta mat_atk_type
    stx tc_eff_start
    sty cr_level + 26
    lda #26
    sta mat_type2
    lda #$ff
    sta tc_min
    lda #0
    sta tc_max
    lda #128
    sta tc_loop
!es_loop:
    lda tc_eff_start
    sta zp_eff_confuse
    sta zp_eff_poison
    lda #0
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda zp_eff_poison
    ldx mat_atk_type
    cpx #ATK_CONFUSE
    bne !es_got+
    lda zp_eff_confuse
!es_got:
    cmp tc_eff_start
    beq !es_next+
    cmp tc_min
    bcs !es_not_min+
    sta tc_min
!es_not_min:
    cmp tc_max
    bcc !es_next+
    sta tc_max
!es_next:
    dec tc_loop
    bne !es_loop-
    lda #0
    sta zp_eff_confuse
    sta zp_eff_poison
    rts

// eff_range_is — A = $01 when tc_min = A and tc_max = X, else $00.
eff_range_is:
    cmp tc_min
    bne !eri_fail+
    cpx tc_max
    bne !eri_fail+
    lda #$01
    rts
!eri_fail:
    lda #$00
    rts

tc_eff_start: .byte 0
tc_min:     .byte 0
tc_max:     .byte 0

// fear_until_afraid — Attack with fear (mat_type2) from fear timer A until
// a save fails (the timer changes), at most 30 tries.
// Output: carry set and A = new timer, or carry clear if every try resisted.
fear_until_afraid:
    sta tc_fear_start
    lda #30
    sta tc_loop
!fua_loop:
    lda tc_fear_start
    sta eff_fear_timer
    jsr mon_atk_effect_fear
    lda eff_fear_timer
    cmp tc_fear_start
    bne !fua_changed+
    dec tc_loop
    bne !fua_loop-
    clc
    rts
!fua_changed:
    sec
    rts

// rp_rounds — 12 rounds of production monster_attack_player by row 26 with
// cr_mflags A, cr_level X and protection timer Y, each from 100 HP and no
// poison. Output: tc_hurt = rounds that cost HP or poisoned, tc_repels =
// " is repelled." summaries.
rp_rounds:
    sta cr_mflags + 26
    stx cr_level + 26
    sty zp_eff_protect
    lda #0
    sta tc_hurt
    sta tc_repels
    lda #12
    sta tc_loop
!rpr_loop:
    lda #100
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    sta zp_eff_poison
    sta zp_game_flags
    lda #26
    sta zp_mon_type
    lda #0
    sta zp_mon_idx
    jsr monster_attack_player
    lda zp_player_hp_lo
    cmp #100
    bne !rpr_hurt+
    lda zp_eff_poison
    beq !rpr_next+
!rpr_hurt:
    inc tc_hurt
!rpr_next:
    dec tc_loop
    bne !rpr_loop-
    rts

// rp_expect_hurt — A = $01 when no round was repelled and at least one hurt
rp_expect_hurt:
    lda tc_repels
    bne !rpe_fail+
    lda tc_hurt
    beq !rpe_fail+
    lda #$01
    rts
!rpe_fail:
    lda #$00
    rts

// ============================================================
// No-HP attack types (tests 27-30): the shipped tier4 data
// ============================================================
tc_maxloss: .byte 0             // Largest HP loss in one round
tc_big:     .byte 0             // Nonzero: a round lost 256 HP or more
tc_banshee_name: .text "Banshee" ; .byte 0
tc_lich_name:    .text "Lich" ; .byte 0
// atk0 type/dice/sides, atk1 type/dice/sides
tc_banshee_atks: .byte ATK_FEAR, 0, 0, ATK_NORMAL, 0, 0
tc_lich_atks:    .byte ATK_POISON, 2, 8, ATK_NORMAL, 0, 0
// Tests 36-39: atk0 type/dice/sides, atk1 type/dice/sides, then the name
tc_ard_row:    .byte ATK_NORMAL, 1, 10, ATK_NORMAL, 2, 14
               .text "Ancient Red Dragon" ; .byte 0
tc_gtroll_row: .byte ATK_NORMAL, 1, 6, ATK_NORMAL, 3, 4
               .text "Giant Troll" ; .byte 0
tc_ghost_row:  .byte ATK_FEAR, 0, 0, ATK_NORMAL, 1, 10
               .text "Ghost" ; .byte 0
tc_irid_row:   .byte ATK_NORMAL, 4, 6, ATK_PARALYZE, 0, 0
               .text "Iridescent Beetle" ; .byte 0

// na_name_is — Z set when tier4 creature X is named as the zero-terminated
// string at A/Y (lo/hi). Preserves X.
na_name_is:
    sta zp_ptr1
    sty zp_ptr1 + 1
    lda tier4_cr_name_lo,x
    sta zp_ptr2
    lda tier4_cr_name_hi,x
    sta zp_ptr2 + 1
    ldy #0
!nni_loop:
    lda (zp_ptr2),y
    cmp (zp_ptr1),y
    bne !nni_done+
    iny
    cmp #0
    bne !nni_loop-
!nni_done:
    rts

// na_atks_are — Z set when tier4 creature X's two attacks match the six
// bytes at A/Y (lo/hi): atk0 type, dice, sides, atk1 type, dice, sides.
na_atks_are:
    sta zp_ptr1
    sty zp_ptr1 + 1
    ldy #0
    lda tier4_cr_atk0_type,x
    cmp (zp_ptr1),y
    bne !naa_done+
    iny
    lda tier4_cr_atk0_dice,x
    cmp (zp_ptr1),y
    bne !naa_done+
    iny
    lda tier4_cr_atk0_sides,x
    cmp (zp_ptr1),y
    bne !naa_done+
    iny
    lda tier4_cr_atk1_type,x
    cmp (zp_ptr1),y
    bne !naa_done+
    iny
    lda tier4_cr_atk1_dice,x
    cmp (zp_ptr1),y
    bne !naa_done+
    iny
    lda tier4_cr_atk1_sides,x
    cmp (zp_ptr1),y
!naa_done:
    rts

// na_rounds — Copy tier4 creature X's attacks, level and flags into roster
// row 26, then run 12 rounds of production monster_attack_player, each from
// 512 HP (player level 5, AC 0, no protection, bless or heroism).
// Output: tc_hurt = rounds that cost HP, tc_maxloss = largest loss below
// 256, tc_big = nonzero if a round cost 256 or more.
na_rounds:
    lda tier4_cr_atk0_type,x
    sta cr_atk0_type + 26
    lda tier4_cr_atk0_dice,x
    sta cr_atk0_dice + 26
    lda tier4_cr_atk0_sides,x
    sta cr_atk0_sides + 26
    lda tier4_cr_atk1_type,x
    sta cr_atk1_type + 26
    lda tier4_cr_atk1_dice,x
    sta cr_atk1_dice + 26
    lda tier4_cr_atk1_sides,x
    sta cr_atk1_sides + 26
    lda tier4_cr_level,x
    sta cr_level + 26
    lda tier4_cr_mflags,x
    sta cr_mflags + 26
    lda #5
    sta zp_player_lvl
    lda #0
    sta zp_player_ac
    sta zp_eff_bless
    sta zp_eff_protect
    sta zp_eff_hero
    sta eff_invuln_timer
    sta tc_hurt
    sta tc_maxloss
    sta tc_big
    lda #12
    sta tc_loop
!nar_loop:
    lda #0
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    sta zp_eff_poison
    sta zp_eff_paralyze
    sta zp_eff_confuse
    sta eff_fear_timer
    sta zp_game_flags
    lda #2
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    lda #26
    sta zp_mon_type
    lda #0
    sta zp_mon_idx
    jsr monster_attack_player
    // loss = $0200 - HP
    sec
    lda #0
    sbc zp_player_hp_lo
    tax
    lda #2
    sbc zp_player_hp_hi
    beq !nar_small+
    inc tc_big
    bne !nar_hurt+              // Always taken
!nar_small:
    txa
    beq !nar_next+
    cmp tc_maxloss
    bcc !nar_hurt+
    sta tc_maxloss
!nar_hurt:
    inc tc_hurt
!nar_next:
    dec tc_loop
    bne !nar_loop-
    rts

#import "../creature_data/tier4.s"

monster_attack_test_end:
.assert "Monster attack test stays below MAP_BASE", monster_attack_test_end <= MAP_BASE, true
