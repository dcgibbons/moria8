// test_combat.s — Runtime tests for combat.s
//
// Tests: combat_calc_tohit, combat_calc_blows, combat_roll_damage,
//        combat_apply_damage, combat_award_xp, combat_check_levelup,
//        msg_build_combat.
//
// Results at $0400-$0409: $01 = pass, $00 = fail per test
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
    ldx #33
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0828 "Main"

.encoding "screencode_mixed"

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
#import "../../common/spell_data.s"
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

ui_inv_display:
ui_inv_select_display:
ui_inv_dispatch:
    rts

ui_equip_display:
    rts

show_inv_and_select:
    lda #$20
    rts

piw_prompt_filtered_inv:
    clc
    rts

piw_pick_filtered_inv_key:
    clc
    rts

magic_recalc_mana:
    rts

magic_check_new_spells:
    rts

pm_setup_active_tables:
    rts

eff_teleport_self:
    rts

eff_kill_monster:
    rts

eff_detect_timer:
    .byte 0

#import "../../common/ui_trampoline_stubs.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test scratch
tc_loop:    .byte 0
tc_ok:      .byte 0
tc_results: .fill 34, $ff      // Result buffer (copied to $0400 at end)

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

    // Default to an equipped dagger so generic melee to-hit tests do not
    // include the bare-hand penalty unless a test explicitly clears weapon.
    lda #2
    sta inv_item_id + EQUIP_WEAPON

    // ==========================================
    // Test 1: combat_calc_tohit for Warrior level 1, TOHIT=0
    // Expected: class_bth(70) + TOHIT*3(0) + level*bth_per_level(1*4) = 74
    // ==========================================
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #0
    sta player_data + PL_TOHIT

    jsr combat_calc_tohit

    lda zp_combat_tohit
    cmp #74
    bne !t1_fail+
    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // ==========================================
    // Test 2: combat_calc_tohit with PL_TOHIT=2
    // Expected: 70 + 2*3(6) + 1*4 = 80
    // ==========================================
!t2:
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #2
    sta player_data + PL_TOHIT

    jsr combat_calc_tohit

    lda zp_combat_tohit
    cmp #80
    bne !t2_fail+
    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // ==========================================
    // Test 3: combat_calc_blows with DEX 12 (unarmed)
    // Umoria bare hands get exactly 2 blows.
    // ==========================================
!t3:
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_WEAPON
    lda #12
    sta player_data + PL_DEX_CUR

    jsr combat_calc_blows

    lda zp_combat_blows
    cmp #2
    bne !t3_fail+
    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // ==========================================
    // Test 4: combat_calc_blows with DEX 18 (unarmed)
    // Umoria bare hands get exactly 2 blows.
    // ==========================================
!t4:
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_WEAPON
    lda #18
    sta player_data + PL_DEX_CUR

    jsr combat_calc_blows

    lda zp_combat_blows
    cmp #2
    bne !t4_fail+
    lda #$01
    sta tc_results + 3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // ==========================================
    // Test 5: combat_roll_damage returns values in [1,2] range
    // Run 20 times, all must be in range
    // ==========================================
!t5:
    lda #0
    sta player_data + PL_TODMG  // No damage bonus
    lda #20
    sta tc_loop
    lda #1
    sta tc_ok

!t5_loop:
    jsr combat_roll_damage
    lda cmb_damage
    cmp #1
    bcc !t5_bad+                // < 1
    cmp #3
    bcs !t5_bad+                // >= 3
    jmp !t5_next+
!t5_bad:
    lda #0
    sta tc_ok
!t5_next:
    dec tc_loop
    bne !t5_loop-

    lda tc_ok
    sta tc_results + 4

    // ==========================================
    // Test 6: combat_apply_damage kills at HP=0
    // Set monster HP to 3, apply 3 damage → dead (carry set)
    // ==========================================
!t6:
    jsr monster_init_table

    // Manually create a monster in slot 0
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #4                      // Kobold
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #3
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y

    ldx #0
    lda #3                      // 3 damage
    jsr combat_apply_damage
    bcs !t6_pass+
    lda #$00
    sta tc_results + 5
    jmp !t7+
!t6_pass:
    lda #$01
    sta tc_results + 5

    // ==========================================
    // Test 7: combat_apply_damage alive when HP > 0
    // Set monster HP to 5, apply 2 damage → alive (carry clear), HP = 3
    // ==========================================
!t7:
    jsr monster_init_table

    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #4                      // Kobold
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #5
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y

    ldx #0
    lda #2                      // 2 damage
    jsr combat_apply_damage
    bcc !t7_alive+
    lda #$00
    sta tc_results + 6
    jmp !t8+
!t7_alive:
    // Check HP = 3
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #3
    bne !t7_fail+
    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // ==========================================
    // Test 8: combat_award_xp adds correct XP
    // Kobold (type 4): cr_xp=5, cr_level=1, player_level=1
    // XP = (5*1)/1 = 5
    // ==========================================
!t8:
    // Clear player XP
    lda #0
    sta player_data + PL_XP_0
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2

    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #4                      // Kobold
    sta cmb_type

    jsr combat_award_xp

    lda player_data + PL_XP_0
    cmp #5
    bne !t8_fail+
    lda player_data + PL_XP_1
    bne !t8_fail+               // Should be 0
    lda #$01
    sta tc_results + 7
    jmp !t9+
!t8_fail:
    lda #$00
    sta tc_results + 7

    // ==========================================
    // Test 9: combat_award_xp with 16-bit XP
    // Set cr_xp_lo[4]=$E8, cr_xp_hi[4]=$03 → xp=1000
    // cr_level[4]=1, player_level=1
    // Expected: (1000*1)/1 = 1000 = $03E8
    // ==========================================
!t9:
    // Clear player XP
    lda #0
    sta player_data + PL_XP_0
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2

    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #4                      // Creature slot 4
    sta cmb_type

    // Set 16-bit XP: $03E8 = 1000
    lda #$e8
    sta cr_xp_lo + 4
    lda #$03
    sta cr_xp_hi + 4
    // Set creature level = 1
    lda #1
    sta cr_level + 4

    jsr combat_award_xp

    lda player_data + PL_XP_0
    cmp #$e8
    bne !t9_fail+
    lda player_data + PL_XP_1
    cmp #$03
    bne !t9_fail+
    lda player_data + PL_XP_2
    bne !t9_fail+               // Should be 0
    lda player_data + PL_XP_FRAC_LO
    bne !t9_fail+
    lda player_data + PL_XP_FRAC_HI
    bne !t9_fail+
    lda #$01
    sta tc_results + 8
    jmp !t10+
!t9_fail:
    lda #$00
    sta tc_results + 8

    // ==========================================
    // Test 10: combat_check_levelup triggers at threshold
    // XP threshold for level 1→2 is 10. Set XP=10, level=1.
    // ==========================================
!t10:
    // Pre-stuff keyboard buffer for -more- prompt from levelup message
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

    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #100                    // Human Warrior = 100+0 = 100
    sta player_data + PL_EXPFACT
    // Set base stats for HP calc
    lda #12
    sta player_data + PL_STR_CUR
    sta player_data + PL_DEX_CUR
    sta player_data + PL_CON_CUR

    lda #10
    sta player_data + PL_XP_0
    lda #0
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2

    jsr combat_check_levelup

    lda zp_player_lvl
    cmp #2
    bne !t10_fail+
    lda #$01
    sta tc_results + 9
    jmp !t11+
!t10_fail:
    lda #$00
    sta tc_results + 9

    // ==========================================
    // Test 11: msg_build_hit produces correct string
    // msg_build_hit with cmb_type=4 (Kobold)
    // Expected: "YOU HIT THE KOBOLD."
    // ==========================================
!t11:
    lda #4
    sta cmb_type

    lda #<cmb_hit_str
    ldy #>cmb_hit_str
    jsr msg_build_action

    // Check: "You hit the Kobold."
    // Y(59) o(0f) u(15) ' '(20) h(08) i(09) t(14) ' '(20) t(14) h(08) e(05) ' '(20)
    // K(4b) o(0f) b(02) o(0f) l(0c) d(04) .(2e) null(00)
    // (screencode_mixed: uppercase A-Z=$41-$5A, lowercase a-z=$01-$1A)
    lda combat_msg_buf + 0
    cmp #$59                    // 'Y'
    bne !t11_fail+
    lda combat_msg_buf + 1
    cmp #$0f                    // 'o' (lowercase)
    bne !t11_fail+
    lda combat_msg_buf + 2
    cmp #$15                    // 'u' (lowercase)
    bne !t11_fail+
    lda combat_msg_buf + 3
    cmp #$20                    // ' '
    bne !t11_fail+
    lda combat_msg_buf + 4
    cmp #$08                    // 'h' (lowercase)
    bne !t11_fail+
    lda combat_msg_buf + 5
    cmp #$09                    // 'i' (lowercase)
    bne !t11_fail+
    lda combat_msg_buf + 6
    cmp #$14                    // 't' (lowercase)
    bne !t11_fail+
    // Check "Kobold." at offset 12
    lda combat_msg_buf + 12
    cmp #$4b                    // 'K'
    bne !t11_fail+
    lda combat_msg_buf + 18
    cmp #$2e                    // '.'
    bne !t11_fail+
    lda combat_msg_buf + 19
    cmp #$00                    // null
    bne !t11_fail+

    lda #$01
    sta tc_results + 10
    jmp !t12+

!t11_fail:
    lda #$00
    sta tc_results + 10

    // ==========================================
    // Test 12: combat_critical_blow — unarmed = no crit
    // Set no weapon, known damage, verify unchanged
    // ==========================================
!t12:
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_WEAPON
    lda #7
    sta cmb_damage

    jsr combat_critical_blow

    lda cmb_damage
    cmp #7                      // Should be unchanged
    bne !t12_fail+
    lda #$01
    sta tc_results + 11
    jmp !t13+
!t12_fail:
    lda #$00
    sta tc_results + 11

    // ==========================================
    // Test 13: combat_critical_blow — high plus-to-hit can crit
    // Equip heavy weapon (type 8, weight=120), high tohit (255),
    // high level (50). Chance = 120 + 5*100 + 4*50 = 820.
    // rng_range_word(5000) returns [0,4999], so ~16% chance per call.
    // Run 20 iterations — at least one should produce damage > base.
    // ==========================================
!t13:
    // Equip weapon type 8 (Two-Handed Sword, weight=120)
    lda #8
    sta inv_item_id + EQUIP_WEAPON
    lda #0
    sta inv_ego + EQUIP_WEAPON

    lda #255
    sta zp_combat_tohit
    lda #100
    sta player_data + PL_TOHIT
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS

    lda #20
    sta tc_loop
    lda #0
    sta tc_ok                   // Will set to 1 if any crit seen
!t13_loop:
    lda #5
    sta cmb_damage              // Base damage = 5

    jsr combat_critical_blow

    lda cmb_damage
    cmp #6                      // Any value > 5 means crit happened
    bcc !t13_next+
    lda #1
    sta tc_ok
!t13_next:
    dec tc_loop
    bne !t13_loop-

    lda tc_ok
    sta tc_results + 12

    // ==========================================
    // Test 14: combat_calc_blows — STR too weak for weapon
    // STR 3, Long Sword (type 4, weight=50), DEX 18
    // STR*15 = 45 < 50 → too heavy → force 1 blow
    // ==========================================
!t14:
    lda #3
    sta player_data + PL_STR_CUR
    lda #18
    sta player_data + PL_DEX_CUR
    lda #4                      // Long Sword (weight=50)
    sta inv_item_id + EQUIP_WEAPON

    jsr combat_calc_blows

    lda zp_combat_blows
    cmp #1
    bne !t14_fail+
    lda #$01
    sta tc_results + 13
    jmp !t15+
!t14_fail:
    lda #$00
    sta tc_results + 13

    // ==========================================
    // Test 15: combat_calc_blows — STR 18 with light weapon
    // STR 18, Dagger (type 2, weight=12), DEX 18
    // adj_weight = (18*10)/12 = 15 → row 6 (>=9)
    // DEX 18 is still the <19 bucket, so this is 2 blows.
    // ==========================================
!t15:
    lda #18
    sta player_data + PL_STR_CUR
    lda #18
    sta player_data + PL_DEX_CUR
    lda #2                      // Dagger (weight=12)
    sta inv_item_id + EQUIP_WEAPON

    jsr combat_calc_blows

    lda zp_combat_blows
    cmp #2
    bne !t15_fail+
    lda #$01
    sta tc_results + 14
    jmp !t16+
!t15_fail:
    lda #$00
    sta tc_results + 14

    // ==========================================
    // Test 16: combat_calc_blows — weak STR with medium weapon
    // STR 10, Long Sword (type 4, weight=50), DEX 12
    // STR*15 = 150 >= 50 → ok
    // adj_weight = (10*10)/50 = 2 → bracket 0 (<3)
    // Row 0, Col 1 (DEX 10-14) = 1 blow
    // ==========================================
!t16:
    lda #10
    sta player_data + PL_STR_CUR
    lda #12
    sta player_data + PL_DEX_CUR
    lda #4                      // Long Sword (weight=50)
    sta inv_item_id + EQUIP_WEAPON

    jsr combat_calc_blows

    lda zp_combat_blows
    cmp #1
    bne !t16_fail+
    lda #$01
    sta tc_results + 15
    jmp !t17+
!t16_fail:
    lda #$00
    sta tc_results + 15

    // ==========================================
    // Test 17: combat_calc_blows — moderate STR/DEX
    // STR 14, Short Sword (type 3, weight=30), DEX 15
    // STR*15 = 210 >= 30 → ok
    // adj_weight = (14*10)/30 = 4 → bracket 1 (3-4)
    // Umoria row 3 (<5), col 1 (<19) = 1 blow
    // ==========================================
!t17:
    lda #14
    sta player_data + PL_STR_CUR
    lda #15
    sta player_data + PL_DEX_CUR
    lda #3                      // Short Sword (weight=30)
    sta inv_item_id + EQUIP_WEAPON

    jsr combat_calc_blows

    lda zp_combat_blows
    cmp #1
    bne !t17_fail+
    lda #$01
    sta tc_results + 16
    jmp !t18+
!t17_fail:
    lda #$00
    sta tc_results + 16

    // ==========================================
    // Test 18: AC from DEX only (no equipment)
    // DEX 18 -> Umoria AC adjustment 2.
    // No armor equipped -> AC = 2
    // ==========================================
!t18:
    // Clear all equipment slots
    lda #FI_EMPTY
    ldx #EQUIP_BODY
!t18_clr:
    sta inv_item_id,x
    inx
    cpx #EQUIP_RING + 1
    bne !t18_clr-

    lda #18
    sta player_data + PL_DEX_CUR
    lda #12
    sta player_data + PL_STR_CUR

    jsr player_calc_combat

    lda player_data + PL_AC
    cmp #2
    bne !t18_fail+
    lda #$01
    sta tc_results + 17
    jmp !t19+
!t18_fail:
    lda #$00
    sta tc_results + 17

    // ==========================================
    // Test 19: AC from DEX + one armor piece
    // DEX 12 → dex_ac_bonus index 9 = 0
    // Leather armor (type 7, base_ac=4) in EQUIP_BODY, p1=0
    // AC = 0 + 4 = 4
    // ==========================================
!t19:
    // Clear all equipment slots
    lda #FI_EMPTY
    ldx #EQUIP_BODY
!t19_clr:
    sta inv_item_id,x
    inx
    cpx #EQUIP_RING + 1
    bne !t19_clr-

    lda #12
    sta player_data + PL_DEX_CUR
    lda #7                      // Leather armor
    sta inv_item_id + EQUIP_BODY
    lda #0
    sta inv_to_ac + EQUIP_BODY

    jsr player_calc_combat

    lda player_data + PL_AC
    cmp #4
    bne !t19_fail+
    lda #$01
    sta tc_results + 18
    jmp !t20+
!t19_fail:
    lda #$00
    sta tc_results + 18

    // ==========================================
    // Test 20: AC from DEX + multiple armor + enchantment
    // DEX 18 -> bonus 2
    // Chain mail (type 8, base_ac=6) in EQUIP_BODY, p1=+2
    // Iron helm (type 10, base_ac=1) in EQUIP_HEAD, p1=0
    // AC = 2 + 6 + 2 + 1 = 11
    // ==========================================
!t20:
    // Clear all equipment slots
    lda #FI_EMPTY
    ldx #EQUIP_BODY
!t20_clr:
    sta inv_item_id,x
    inx
    cpx #EQUIP_RING + 1
    bne !t20_clr-

    lda #18
    sta player_data + PL_DEX_CUR
    lda #8                      // Chain mail
    sta inv_item_id + EQUIP_BODY
    lda #2                      // +2 enchantment
    sta inv_to_ac + EQUIP_BODY
    lda #10                     // Iron helm
    sta inv_item_id + EQUIP_HEAD
    lda #0
    sta inv_to_ac + EQUIP_HEAD

    jsr player_calc_combat

    lda player_data + PL_AC
    cmp #11
    bne !t20_fail+
    lda #$01
    sta tc_results + 19
    jmp !t21+
!t20_fail:
    lda #$00
    sta tc_results + 19

    // ==========================================
    // Test 21: combat_compute_level_threshold uses full 24-bit late table
    // Level 30 threshold should be 100000 at expfact 100.
    // ==========================================
!t21:
    lda #30
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #100
    sta player_data + PL_EXPFACT

    jsr combat_compute_level_threshold

    lda ccl_adj_0
    cmp #$a0
    bne !t21_fail+
    lda ccl_adj_1
    cmp #$86
    bne !t21_fail+
    lda ccl_adj_2
    cmp #$01
    bne !t21_fail+
    lda #$01
    sta tc_results + 20
    jmp !t22+
!t21_fail:
    lda #$00
    sta tc_results + 20

    // ==========================================
    // Test 22: non-100 expfact scales late threshold correctly
    // Level 30 threshold 100000 * 150 / 100 = 150000 = $0249F0.
    // ==========================================
!t22:
    lda #30
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #150
    sta player_data + PL_EXPFACT

    jsr combat_compute_level_threshold

    lda ccl_adj_0
    cmp #$f0
    bne !t22_fail+
    lda ccl_adj_1
    cmp #$49
    bne !t22_fail+
    lda ccl_adj_2
    cmp #$02
    bne !t22_fail+
    lda #$01
    sta tc_results + 21
    jmp !t23+
!t22_fail:
    lda #$00
    sta tc_results + 21

    // ==========================================
    // Test 23: combat_check_levelup applies Umoria's excess-halving loop
    // across repeated gains.
    // Level 1, XP=100, expfact=100:
    //   threshold 10 -> level 2, XP becomes 55
    //   threshold 25 -> level 3, XP becomes 40
    //   threshold 45 -> stop
    // Final: level 3 with XP retained at 40.
    // ==========================================
!t23:
    // Pre-stuff keyboard buffer for repeated levelup messages
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

    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #100
    sta player_data + PL_EXPFACT
    lda #12
    sta player_data + PL_STR_CUR
    sta player_data + PL_DEX_CUR
    sta player_data + PL_CON_CUR
    lda #100
    sta player_data + PL_XP_0
    lda #0
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2
    sta player_data + PL_XP_FRAC_LO
    sta player_data + PL_XP_FRAC_HI

    jsr combat_check_levelup

    lda zp_player_lvl
    cmp #3
    bne !t23_fail+
    lda player_data + PL_XP_0
    cmp #40
    bne !t23_fail+
    lda player_data + PL_XP_1
    bne !t23_fail+
    lda player_data + PL_XP_2
    bne !t23_fail+
    lda player_data + PL_XP_FRAC_LO
    bne !t23_fail+
    lda player_data + PL_XP_FRAC_HI
    bne !t23_fail+
    lda #$01
    sta tc_results + 22
    jmp !t24+
!t23_fail:
    lda #$00
    sta tc_results + 22
    jmp !t24+

    // ==========================================
    // Test 24: combat_calc_tohit saturates large positive PL_TOHIT
    // Warrior level 1, TOHIT=100:
    // 70 + 300 + 4 would exceed 255, so result must cap at 255.
    // ==========================================
!t24:
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #100
    sta player_data + PL_TOHIT

    jsr combat_calc_tohit

    lda zp_combat_tohit
    cmp #255
    bne !t24_fail+
    lda #$01
    sta tc_results + 23
    jmp !t25+
!t24_fail:
    lda #$00
    sta tc_results + 23

    // ==========================================
    // Test 25: combat_calc_tohit floors large negative PL_TOHIT before
    // the per-level class bonus is added back.
    // Warrior level 1, TOHIT=-100:
    // 70 - 300 floors to 0, then +4 level bonus = 4.
    // ==========================================
!t25:
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #1
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #$9c                    // -100 signed
    sta player_data + PL_TOHIT

    jsr combat_calc_tohit

    lda zp_combat_tohit
    cmp #4
    bne !t25_fail+
    lda #$01
    sta tc_results + 24
    jmp !t26+
!t25_fail:
    lda #$00
    sta tc_results + 24

    // ==========================================
    // Test 26: combat_append_decimal preserves embedded zero digits
    // Value 105 should append "105" and advance the buffer index to 3.
    // ==========================================
!t26:
    lda #0
    sta cmb_buf_idx
    lda #0
    sta combat_msg_buf + 0
    sta combat_msg_buf + 1
    sta combat_msg_buf + 2
    lda #105
    jsr combat_append_decimal

    lda cmb_buf_idx
    cmp #3
    bne !t26_fail+
    lda combat_msg_buf + 0
    cmp #$31
    bne !t26_fail+
    lda combat_msg_buf + 1
    cmp #$30
    bne !t26_fail+
    lda combat_msg_buf + 2
    cmp #$35
    bne !t26_fail+
    lda #$01
    sta tc_results + 25
    jmp !t27+
!t26_fail:
    lda #$00
    sta tc_results + 25

    // ==========================================
    // Test 27: combat_append_decimal_16 preserves interior zeros
    // Value 10005 ($2715) should append "10005" and advance to 5.
    // ==========================================
!t27:
    lda #0
    sta cmb_buf_idx
    lda #0
    sta combat_msg_buf + 0
    sta combat_msg_buf + 1
    sta combat_msg_buf + 2
    sta combat_msg_buf + 3
    sta combat_msg_buf + 4
    lda #$15
    sta zp_temp0
    lda #$27
    sta zp_temp1
    jsr combat_append_decimal_16

    lda cmb_buf_idx
    cmp #5
    bne !t27_fail+
    lda combat_msg_buf + 0
    cmp #$31
    bne !t27_fail+
    lda combat_msg_buf + 1
    cmp #$30
    bne !t27_fail+
    lda combat_msg_buf + 2
    cmp #$30
    bne !t27_fail+
    lda combat_msg_buf + 3
    cmp #$30
    bne !t27_fail+
    lda combat_msg_buf + 4
    cmp #$35
    bne !t27_fail+
    lda #$01
    sta tc_results + 26
    jmp !t28+
!t27_fail:
    lda #$00
    sta tc_results + 26

    // ==========================================
    // Test 28: player_attack_monster preserves target coordinates while
    // clearing search mode, so bump-to-attack still finds the monster.
    // ==========================================
!t28:
    jsr monster_init_table
    lda #PLF_SEARCHING
    sta player_data + PL_FLAGS
    lda #$ff
    sta zp_run_dir
    lda #0
    sta eff_fear_timer

    // Place a floor tile with an occupied monster at (20,15).
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    :MapWrite_ptr0_y()

    // Populate slot 0 at the same coordinates with clear flags.
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda #20
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #15
    sta (zp_ptr0),y
    ldy #MX_TYPE
    lda #4
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y

    lda #20
    ldy #15
    jsr player_attack_monster

    ldx #0
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE | MF_PROVOKED
    cmp #MF_AWAKE | MF_PROVOKED
    bne !t28_fail+
    lda player_data + PL_FLAGS
    and #PLF_SEARCHING
    bne !t28_fail+
    lda #$01
    sta tc_results + 27
    jmp !t29+
!t28_fail:
    lda #$00
    sta tc_results + 27

    // ==========================================
    // Test 29: combat message appends must keep slot 41 reserved for
    // the null terminator instead of scribbling into the next symbol.
    // ==========================================
!t29:
    lda #41
    sta cmb_buf_idx
    lda #0
    sta combat_msg_buf + 41
    lda #'Y'
    sta cmb_you_str

    lda #<tc_one_char_z
    ldy #>tc_one_char_z
    jsr combat_append_str
    lda #<tc_one_char_dot
    ldy #>tc_one_char_dot
    jsr combat_append_str

    lda cmb_buf_idx
    cmp #41
    bne !t29_fail+
    lda combat_msg_buf + 41
    bne !t29_fail+
    lda cmb_you_str
    cmp #'Y'
    bne !t29_fail+
    lda #$01
    sta tc_results + 28
    jmp !t30+
!t29_fail:
    lda #$00
    sta tc_results + 28

    // ==========================================
    // Test 30: melee kill marks the scene dirty for redraw.
    // ==========================================
!t30:
    jsr monster_init_table
    lda #0
    sta zp_dirty_count
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #50
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #18
    sta player_data + PL_STR_CUR
    lda #118
    sta player_data + PL_DEX_CUR
    lda #127
    sta player_data + PL_TOHIT
    lda #10
    sta player_data + PL_TODMG
    lda #2
    sta inv_item_id + EQUIP_WEAPON

    // Place a floor tile with an occupied monster at (20,15).
    ldx #15
    lda map_row_lo,x
    sta zp_ptr0
    lda map_row_hi,x
    sta zp_ptr0_hi
    ldy #20
    lda #((TILE_FLOOR << 4) | FLAG_OCCUPIED)
    :MapWrite_ptr0_y()

    // Populate slot 0 as a one-hit kill target.
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda #20
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #15
    sta (zp_ptr0),y
    ldy #MX_TYPE
    lda #4
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #1
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #0
    sta (zp_ptr0),y

    lda #20
    ldy #15
    jsr player_attack_monster

    lda zp_dirty_count
    cmp #1
    bne !t30_fail+
    lda #$01
    sta tc_results + 29
    jmp !t31+
!t30_fail:
    lda #$00
    sta tc_results + 29

    // ==========================================
    // Test 31: reported gnome rogue case uses Umoria blow buckets.
    // STR 16, DEX 18/36 (54), dagger weight 12:
    // adj_weight=13 -> row 6, DEX<68 -> col 2, so 3 blows.
    // ==========================================
!t31:
    lda #16
    sta player_data + PL_STR_CUR
    lda #54
    sta player_data + PL_DEX_CUR
    lda #2
    sta inv_item_id + EQUIP_WEAPON

    jsr combat_calc_blows

    lda zp_combat_blows
    cmp #3
    bne !t31_fail+
    jsr player_calc_combat
    lda player_data + PL_TODMG
    cmp #1                      // STR 16 -> Umoria damage adjustment +1.
    bne !t31_fail+
    lda #$01
    sta tc_results + 30
    jmp !t32+
!t31_fail:
    lda #$00
    sta tc_results + 30

    // ==========================================
    // Test 32: maximum exceptional DEX reaches Umoria top bucket.
    // STR 16, DEX 18/100 (118), dagger -> row 6, col 5 = 4 blows.
    // ==========================================
!t32:
    lda #16
    sta player_data + PL_STR_CUR
    lda #118
    sta player_data + PL_DEX_CUR
    lda #2
    sta inv_item_id + EQUIP_WEAPON

    jsr combat_calc_blows

    lda zp_combat_blows
    cmp #4
    bne !t32_fail+
    lda #$01
    sta tc_results + 31
    jmp !t33+
!t32_fail:
    lda #$00
    sta tc_results + 31

    // ==========================================
    // Test 33: ranged launcher used in melee is forced to one blow.
    // ==========================================
!t33:
    lda #18
    sta player_data + PL_STR_CUR
    lda #118
    sta player_data + PL_DEX_CUR
    lda #49                     // Short Bow
    sta inv_item_id + EQUIP_WEAPON

    jsr combat_calc_blows

    lda zp_combat_blows
    cmp #1
    bne !t33_fail+
    lda #$01
    sta tc_results + 32
    jmp !t34+
!t33_fail:
    lda #$00
    sta tc_results + 32

    // ==========================================
    // Test 34: critical chance uses PL_TOHIT, not full zp_combat_tohit.
    // Dagger + rogue level 3 + PL_TOHIT 0 -> chance 12 + 0 + 9 = 21.
    // ==========================================
!t34:
    lda #2
    sta inv_item_id + EQUIP_WEAPON
    lda #0
    sta inv_ego + EQUIP_WEAPON
    sta player_data + PL_TOHIT
    lda #255
    sta zp_combat_tohit
    lda #3
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #CLASS_ROGUE
    sta player_data + PL_CLASS
    lda #5
    sta cmb_damage

    jsr combat_critical_blow

    lda ccb_chance_lo
    cmp #21
    bne !t34_fail+
    lda ccb_chance_hi
    bne !t34_fail+
    lda #$01
    sta tc_results + 33
    jmp !tests_done+
!t34_fail:
    lda #$00
    sta tc_results + 33

!tests_done:
    jmp test_exit_trampoline

tc_one_char_z:   .text "Z" ; .byte 0
tc_one_char_dot: .text "." ; .byte 0
