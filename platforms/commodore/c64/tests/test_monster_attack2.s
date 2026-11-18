// test_monster_attack2.s — Phase 5 Wave 5.4b unit tests for 4-attack loop,
// 19 VMS ADESC_* attack verbs, and all extended VMS ATK_* melee effects.
//
// Results at $0400-$0421 (34 tests): $01 = pass, $00 = fail per test.

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

#define COMPILE_EMBEDDED_DUNGEON_TEST_ROSTER
#define MONSTER_ATTACK_PRODUCTION_EXTENDED
#define PLAYER_CHARGEN_EXTERNAL
#define TRAP_TRIGGER_EXTERNAL
#define ITEM_SPAWN_EXTERNAL
#define PICK_ITEM_TYPE_EXTERNAL
#define HAL_PLATFORM_ITEM_CAT_CUSTOM

.segmentdef TestUnused [start=$D000, virtual]

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
#import "../../../../core/spell_data.s"
#import "../../../../core/player.s"
#import "../../../../core/ui_messages.s"
#import "../../../../core/ui_status.s"
.segment TestUnused
player_create:
    brk
#import "../../../../core/ui_help_clear.s"
#import "../../../../core/ui_character.s"
.segment Default
#import "../../../../core/stat_display.s"
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "dungeon_gen_stubs.s"
#import "../../../../core/huffman.s"
#import "../../../../core/dungeon_features.s"
#import "chest_summons_stubs.s"
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
.segment TestUnused
#import "../../../../core/monster_ai.s"
#import "../../../../core/monster_magic.s"
.segment Default
#import "../../../../core/recall.s"
#import "../../../../core/item.s"
#import "item_cat_resident_helper.s"
#import "../../../../core/special_rooms.s"
#import "../../../../core/ego_items.s"
#import "../../../../core/special_rooms_stubs.s"
.segment TestUnused
#import "../../../../core/trap_trigger_cold.s"
#import "../../../../core/player_chargen_cold.s"
#import "../../../../core/item_spawn_cold.s"
#import "../../../../core/pick_item_type_cold.s"
#import "../dungeon_render.s"
.segment Default
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/monster_attack.s"
#import "../../../../core/turn.s"

store_init_all:
store_restock_all:
store_enter:
ui_help_show_paged:
ui_help_display:
help_draw_line:
help_draw_hborder:
ui_inv_display:
ui_inv_select_display:
ui_inv_dispatch:
ui_equip_display:
magic_recalc_mana:
magic_check_new_spells:
pm_setup_active_tables:
eff_teleport_self:
eff_teleport_apply_target:
eff_kill_monster:
    rts

player_recalc_equipment:
    inc tc_recalcs
    rts

show_inv_and_select:
    lda #$20
    rts
piw_prompt_filtered_inv:
piw_pick_filtered_inv_key:
    clc
    rts

eff_detect_timer:     .byte 0
eff_detect_evil_mode: .byte 0

#import "../../../../core/ui_trampoline_stubs.s"

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

tc_recalcs: .byte 0
tc_loop:    .byte 0
tc_cnt1:    .byte 0
tc_cnt2:    .byte 0
tc_max:     .byte 0
tc_wt_lo:   .byte 0
tc_wt_hi:   .byte 0
tc_results: .fill 34, $00

// Custom test creature row 26 ("orc" name pointer)
tc_mon_name: .text "orc" ; .byte 0

tc_init_msg_keys:
    jsr msg_init
    lda #MSG_ROW
    jsr hal_screen_clear_row
    lda #MSG_ROW + 1
    jsr hal_screen_clear_row
    lda #$20
    ldx #7
!trs_kb:
    sta $0277,x
    dex
    bpl !trs_kb-
    lda #8
    sta $c6
    rts

// Reset player HP=200/200, AC=0, lvl=10, clear timers & inventory
tc_reset_state:
    jsr tc_init_msg_keys
    lda #0
    sta status_cache_valid
    sta zp_eff_poison
    sta zp_eff_blind
    sta zp_eff_confuse
    sta zp_eff_paralyze
    sta zp_eff_protect
    sta zp_eff_bless
    sta zp_eff_hero
    sta eff_fear_timer
    sta eff_invuln_timer
    sta player_pflags
    sta player_sust_mask
    sta tc_recalcs
    sta zp_player_ac
    sta zp_dirty_count
    lda #10
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #100
    sta player_data + PL_EXPFACT
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #0
    sta player_data + PL_RACE
    lda #18
    ldx #5
!trs_st:
    sta player_data + PL_STR_BASE,x
    sta player_data + PL_STR_CUR,x
    sta zp_player_str,x
    dex
    bpl !trs_st-
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    sta zp_player_mhp_lo
    sta player_data + PL_MHP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    sta zp_player_mhp_hi
    sta player_data + PL_MHP_HI
    jsr item_init_inventory

    // Configure creature row 26 defaults: level 30, 0 attacks until set
    lda #27
    sta active_dungeon_count
    lda #<tc_mon_name
    sta cr_name_lo + 26
    lda #>tc_mon_name
    sta cr_name_hi + 26
    lda #30
    sta cr_level + 26
    lda #0
    sta cr_mflags + 26
    sta cr_atk0_type + 26
    sta cr_atk0_dice + 26
    sta cr_atk0_sides + 26
    sta cr_atk1_type + 26
    sta cr_atk1_dice + 26
    sta cr_atk1_sides + 26
    sta cr_atk2_type + 26
    sta cr_atk2_dice + 26
    sta cr_atk2_sides + 26
    sta cr_atk3_type + 26
    sta cr_atk3_dice + 26
    sta cr_atk3_sides + 26

    // Active monster slot 0 -> row 26 at (10, 10) with 50 HP
    lda #0
    sta zp_mon_idx
    lda #26
    sta zp_mon_type
    sta mat_type2
    lda #10
    sta zp_mon_x
    sta zp_mon_y
    lda #MF_AWAKE | MF_VISIBLE
    sta zp_mon_flags
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda #10
    sta (zp_ptr0),y
    iny
    sta (zp_ptr0),y
    ldy #MX_TYPE
    lda #26
    sta (zp_ptr0),y
    ldy #MX_HP_LO
    lda #50
    sta (zp_ptr0),y
    iny
    lda #0
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #MF_AWAKE | MF_VISIBLE
    sta (zp_ptr0),y
    rts

// Check null-terminated screen-code string at (X=lo, Y=hi) matches hd_decode_buf
tc_match_decode_buf:
    stx zp_ptr1
    sty zp_ptr1_hi
    ldy #0
!tmdb_lp:
    lda (zp_ptr1),y
    cmp hd_decode_buf,y
    bne !tmdb_no+
    cmp #0
    beq !tmdb_yes+
    iny
    bne !tmdb_lp-
!tmdb_no:
    clc
    rts
!tmdb_yes:
    sec
    rts

// Check screen row at zp_ptr2 exactly equals null-terminated string (X=lo, Y=hi)
// followed by a space ($20).
tc_match_row0_exact:
    lda #$00
    sta zp_ptr2
    lda #$04
    sta zp_ptr2_hi
    bne tc_match_row_exact
tc_match_row1_exact:
    lda #$28
    sta zp_ptr2
    lda #$04
    sta zp_ptr2_hi
tc_match_row_exact:
    stx zp_ptr1
    sty zp_ptr1_hi
    ldy #0
!tmre_lp:
    lda (zp_ptr1),y
    beq !tmre_end+
    cmp (zp_ptr2),y
    bne !tmr0_no+
    iny
    cpy #40
    bcc !tmre_lp-
    bcs !tmr0_no+
!tmre_end:
    lda (zp_ptr2),y
    cmp #$20
    bne !tmr0_no+
    sec
    rts

// Check screen row 0 ($0400..$0427) starts with null-terminated string (X=lo, Y=hi)
tc_match_row0_prefix:
    stx zp_ptr1
    sty zp_ptr1_hi
    ldy #0
!tmr0_lp:
    lda (zp_ptr1),y
    beq !tmr0_yes+
    cmp $0400,y
    bne !tmr0_no+
    iny
    cpy #40
    bcc !tmr0_lp-
!tmr0_no:
    clc
    rts
!tmr0_yes:
    sec
    rts

test_start:
    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$f1
    sta zp_rng_3

    jsr msg_init
    jsr hal_sound_init

    // =========================================================
    // Test 0: 4-attack loop — all 4 slots (atk0..atk3) fire and accumulate
    // =========================================================
    jsr tc_reset_state
    lda #60
    sta cr_level + 26           // tohit = 240 vs AC 0
    lda #ATK_NORMAL
    sta cr_atk0_type + 26
    sta cr_atk1_type + 26
    sta cr_atk2_type + 26
    sta cr_atk3_type + 26
    lda #1
    sta cr_atk0_dice + 26
    sta cr_atk0_sides + 26
    sta cr_atk1_dice + 26
    sta cr_atk1_sides + 26
    sta cr_atk2_dice + 26
    sta cr_atk2_sides + 26
    sta cr_atk3_dice + 26
    sta cr_atk3_sides + 26
    lda #0
    sta tc_max
    lda #8
    sta tc_loop
!t0_lp:
    jsr msg_init
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    jsr monster_attack_player
    lda #200
    sec
    sbc zp_player_hp_lo
    cmp tc_max
    bcc !t0_nx+
    sta tc_max
!t0_nx:
    dec tc_loop
    bne !t0_lp-
    lda tc_max
    cmp #4
    bne !t1+
    inc tc_results + 0

    // =========================================================
    // Test 1: ATK_NONE (0) in slot 2 stops loop before slot 3
    // =========================================================
!t1:
    jsr tc_reset_state
    lda #60
    sta cr_level + 26
    lda #ATK_NORMAL
    sta cr_atk0_type + 26
    sta cr_atk1_type + 26
    sta cr_atk3_type + 26       // Slot 2 stays ATK_NONE (0)
    lda #1
    sta cr_atk0_dice + 26
    sta cr_atk0_sides + 26
    sta cr_atk1_dice + 26
    sta cr_atk1_sides + 26
    lda #20
    sta cr_atk3_dice + 26
    lda #1
    sta cr_atk3_sides + 26
    lda #0
    sta tc_max
    lda #8
    sta tc_loop
!t1_lp:
    jsr msg_init
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    jsr monster_attack_player
    lda #200
    sec
    sbc zp_player_hp_lo
    cmp tc_max
    bcc !t1_nx+
    sta tc_max
!t1_nx:
    dec tc_loop
    bne !t1_lp-
    lda tc_max
    cmp #2
    bne !t2+
    inc tc_results + 1

    // =========================================================
    // Test 2: ATK_BLANK (99) in slot 1 is skipped; slots 0, 2, 3 fire
    // =========================================================
!t2:
    jsr tc_reset_state
    lda #60
    sta cr_level + 26
    lda #ATK_NORMAL
    sta cr_atk0_type + 26
    sta cr_atk2_type + 26
    sta cr_atk3_type + 26
    lda #ATK_BLANK
    sta cr_atk1_type + 26
    lda #1
    sta cr_atk0_dice + 26
    sta cr_atk0_sides + 26
    sta cr_atk2_dice + 26
    sta cr_atk2_sides + 26
    sta cr_atk3_dice + 26
    sta cr_atk3_sides + 26
    lda #20
    sta cr_atk1_dice + 26
    sta cr_atk1_sides + 26
    lda #0
    sta tc_max
    lda #8
    sta tc_loop
!t2_lp:
    jsr msg_init
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    jsr monster_attack_player
    lda #200
    sec
    sbc zp_player_hp_lo
    cmp tc_max
    bcc !t2_nx+
    sta tc_max
!t2_nx:
    dec tc_loop
    bne !t2_lp-
    lda tc_max
    cmp #3
    bne !t3+
    inc tc_results + 2

    // =========================================================
    // Test 3: Signed BTH for ATK_LOSE_STR (2): -3 + lvl*3 clamped [0, 255]
    // =========================================================
!t3:
    jsr tc_reset_state
    lda #ATK_LOSE_STR
    sta mat_atk_type
    lda #0
    sta cr_level + 26
    jsr mon_atk_calc_tohit
    lda zp_combat_tohit
    bne !t4+
    lda #1
    sta cr_level + 26
    jsr mon_atk_calc_tohit
    lda zp_combat_tohit
    bne !t4+
    lda #2
    sta cr_level + 26
    jsr mon_atk_calc_tohit
    lda zp_combat_tohit
    cmp #3
    bne !t4+
    lda #10
    sta cr_level + 26
    jsr mon_atk_calc_tohit
    lda zp_combat_tohit
    cmp #27
    bne !t4+
    lda #100
    sta cr_level + 26
    jsr mon_atk_calc_tohit
    lda zp_combat_tohit
    cmp #255
    bne !t4+
    inc tc_results + 3

    // =========================================================
    // Test 4: 0-HP status blow sets mat_any_hit != 0 (never "misses you.")
    // =========================================================
!t4:
    jsr tc_reset_state
    lda #60
    sta cr_level + 26
    // Pack ADESC_TOUCHES (5): verb[4:1]=2 ($20 in sides), verb[0]=1 ($80 in type)
    lda #$80 | ATK_EAT_FOOD
    sta cr_atk0_type + 26
    lda #$20
    sta cr_atk0_sides + 26
    lda #16
    sta tc_loop
!t4_lp:
    jsr msg_init
    jsr monster_attack_player
    lda mat_any_hit
    bne !t4_hit+
    dec tc_loop
    bne !t4_lp-
    jmp !t5+
!t4_hit:
    ldx #<tc_str_orc_touches
    ldy #>tc_str_orc_touches
    jsr tc_match_row0_prefix
    bcc !t5+
    inc tc_results + 4

    // =========================================================
    // Test 5: ADESC_NONE (0) and ADESC_HITS (1) preserve "The orc hits you."
    // =========================================================
!t5:
    jsr tc_reset_state
    lda #60
    sta cr_level + 26
    lda #ATK_NORMAL
    sta cr_atk0_type + 26
    lda #1
    sta cr_atk0_dice + 26
    sta cr_atk0_sides + 26
    lda #16
    sta tc_loop
!t5_lp0:
    jsr msg_init
    jsr monster_attack_player
    lda mat_any_hit
    bne !t5_chk0+
    dec tc_loop
    bne !t5_lp0-
    jmp !t6+
!t5_chk0:
    ldx #<tc_str_orc_hits
    ldy #>tc_str_orc_hits
    jsr tc_match_row0_prefix
    bcc !t6+
    // Now ADESC_HITS (1): type bit 7 = 1 ($81), sides high nibble = 0
    lda #$80 | ATK_NORMAL
    sta cr_atk0_type + 26
    lda #16
    sta tc_loop
!t5_lp1:
    jsr msg_init
    jsr monster_attack_player
    lda mat_any_hit
    bne !t5_chk1+
    dec tc_loop
    bne !t5_lp1-
    jmp !t6+
!t5_chk1:
    ldx #<tc_str_orc_hits
    ldy #>tc_str_orc_hits
    jsr tc_match_row0_prefix
    bcc !t6+
    inc tc_results + 5

    // =========================================================
    // Test 6: All 18 VMS verb phrases (ADESC 2..19) decode byte-for-byte
    // =========================================================
!t6:
    lda #0
    sta tc_loop                 // 0..17 -> verb 2..19
!t6_lp:
    ldx tc_loop
    txa
    clc
    adc #2
    jsr mon_atk_verb_to_ptr2
    ldx tc_loop
    ldy tc_verb_hi,x
    lda tc_verb_lo,x
    tax
    jsr tc_match_decode_buf
    bcc !t7+
    inc tc_loop
    lda tc_loop
    cmp #18
    bcc !t6_lp-
    inc tc_results + 6

    // =========================================================
    // Test 7: 5-bit verb unpack through monster_attack_player (13 & 18)
    // =========================================================
!t7:
    jsr tc_reset_state
    lda #60
    sta cr_level + 26
    // ADESC_SPORES (13 = %01101): sides=(6<<4)|1=$61, type=(1<<7)|ATK_NORMAL=$81
    lda #$81
    sta cr_atk0_type + 26
    lda #1
    sta cr_atk0_dice + 26
    lda #$61
    sta cr_atk0_sides + 26
    lda #16
    sta tc_loop
!t7_lp1:
    jsr msg_init
    jsr monster_attack_player
    lda mat_any_hit
    bne !t7_c1+
    dec tc_loop
    bne !t7_lp1-
    jmp !t8+
!t7_c1:
    lda mat_hit_verb
    cmp #ADESC_SPORES
    bne !t8+
    ldx #<tc_str_orc_spores
    ldy #>tc_str_orc_spores
    jsr tc_match_row0_prefix
    bcc !t8+
    // ADESC_DROOLS (18 = %10010): sides=(9<<4)|1=$91, type=$01
    lda #$01
    sta cr_atk0_type + 26
    lda #$91
    sta cr_atk0_sides + 26
    lda #16
    sta tc_loop
!t7_lp2:
    jsr msg_init
    jsr monster_attack_player
    lda mat_any_hit
    bne !t7_c2+
    dec tc_loop
    bne !t7_lp2-
    jmp !t8+
!t7_c2:
    lda mat_hit_verb
    cmp #ADESC_DROOLS
    bne !t8+
    inc tc_results + 7

    // =========================================================
    // Test 8: ATK_CORRODE (9) corrodes worn boots, keeps full dice, recalcs
    // =========================================================
!t8:
    jsr tc_reset_state
    lda #ITEM_SLOT_LEATHER_BOOTS                     // Leather Boots (base AC > 0)
    sta inv_item_id + EQUIP_FEET
    lda #0
    sta inv_to_ac + EQUIP_FEET
    lda #ATK_CORRODE
    sta mat_atk_type
    lda #10
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda zp_combat_dmg
    cmp #10                     // Not halved (unlike acid) and no +1d8 when piece took it
    bne !t9+
    lda inv_to_ac + EQUIP_FEET
    cmp #$ff
    bne !t9+
    lda tc_recalcs
    cmp #1
    bne !t9+
    inc tc_results + 8

    // =========================================================
    // Test 9: ATK_CORRODE (9) naked adds +1..8 extra HP damage
    // =========================================================
!t9:
    jsr tc_reset_state
    lda #ATK_CORRODE
    sta mat_atk_type
    lda #10
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda zp_combat_dmg
    cmp #11
    bcc !t10+
    cmp #19
    bcs !t10+
    inc tc_results + 9

    // =========================================================
    // Test 10: ATK_BLIND (10) AC-reduces HP damage + sets 10+randint(lvl)
    // =========================================================
!t10:
    jsr tc_reset_state
    lda #100
    sta zp_player_ac            // 50% AC reduction: 20 -> 10
    lda #4
    sta cr_level + 26
    lda #ATK_BLIND
    sta mat_atk_type
    lda #20
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda zp_combat_dmg
    cmp #10
    bne !t11+
    lda zp_eff_blind
    cmp #11
    bcc !t11+
    cmp #15
    bcs !t11+
    inc tc_results + 10

    // =========================================================
    // Test 11: ATK_BLIND (10) stacks +5 and saturates at 255
    // =========================================================
!t11:
    jsr tc_reset_state
    lda #20
    sta zp_eff_blind
    lda #ATK_BLIND
    sta mat_atk_type
    lda #4
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda zp_eff_blind
    cmp #25
    bne !t12+
    lda #253
    sta zp_eff_blind
    jsr mon_atk_effect_dispatch
    lda zp_eff_blind
    cmp #255
    bne !t12+
    inc tc_results + 11

    // =========================================================
    // Test 12: ATK_STEAL_GOLD (12) rolls to-hit vs zp_player_lvl, NOT AC
    // =========================================================
!t12:
    jsr tc_reset_state
    lda #250
    sta zp_player_ac            // Impossible vs AC, trivial vs lvl=1
    lda #1
    sta zp_player_lvl
    lda #25
    sta cr_level + 26           // tohit = 80
    lda #ATK_STEAL_GOLD
    sta mat_atk_type
    lda #0
    sta tc_cnt1
    lda #20
    sta tc_loop
!t12_lp:
    jsr mon_atk_calc_tohit
    bcc !t12_nx+
    inc tc_cnt1
!t12_nx:
    dec tc_loop
    bne !t12_lp-
    lda tc_cnt1
    cmp #10                     // Hits most of the 20 rolls despite AC=250
    bcc !t13+
    inc tc_results + 12

    // =========================================================
    // Test 13: ATK_STEAL_GOLD (12) 0 HP, steals au/10 + randint(25), floors 0
    // =========================================================
!t13:
    jsr tc_reset_state
    lda #3
    sta zp_player_dex
    lda #1
    sta zp_eff_paralyze         // Guarantee no anti-theft block
    lda #200
    sta player_data + PL_GOLD_0
    lda #0
    sta player_data + PL_GOLD_1
    sta player_data + PL_GOLD_2
    lda #ATK_STEAL_GOLD
    sta mat_atk_type
    lda #30
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda zp_combat_dmg
    bne !t14+                   // Must zero HP damage
    lda player_data + PL_GOLD_0
    cmp #155                    // 200 - (20 + 25) = 155
    bcc !t14+
    cmp #180                    // 200 - (20 + 1) = 179
    bcs !t14+
    // Small gold (5) clamps cleanly to 0 without underflow
    lda #5
    sta player_data + PL_GOLD_0
    jsr mon_atk_effect_dispatch
    lda player_data + PL_GOLD_0
    ora player_data + PL_GOLD_1
    ora player_data + PL_GOLD_2
    bne !t14+
    inc tc_results + 13

    // =========================================================
    // Test 14: DEX=118 anti-theft protects most attempts; paralysis overrides
    // =========================================================
!t14:
    jsr tc_reset_state
    lda #118                    // 18/100 DEX: protects when randint(124) in 1..117
    sta zp_player_dex
    lda #0
    sta zp_eff_paralyze
    sta tc_cnt1                 // Protected count
    lda #ATK_STEAL_GOLD
    sta mat_atk_type
    lda #24
    sta tc_loop
!t14_lp:
    jsr tc_init_msg_keys
    lda #100
    sta player_data + PL_GOLD_0
    jsr mon_atk_effect_dispatch
    lda player_data + PL_GOLD_0
    cmp #100
    bne !t14_nx+
    inc tc_cnt1
!t14_nx:
    dec tc_loop
    bne !t14_lp-
    lda tc_cnt1
    cmp #15                     // Expected ~22.6/24 protected
    bcc !t15+
    // Paralyzed overrides DEX=118
    lda #4
    sta zp_eff_paralyze
    lda #100
    sta player_data + PL_GOLD_0
    jsr mon_atk_effect_dispatch
    lda player_data + PL_GOLD_0
    cmp #100
    beq !t15+
    inc tc_results + 14

    // =========================================================
    // Test 15: ATK_STEAL_ITEM (13) steals 1 unit, updates weight, empty-safe
    // =========================================================
!t15:
    jsr tc_reset_state
    lda #1
    sta zp_eff_paralyze
    lda #ITEM_SLOT_RATION_OF_FOOD                     // Ration of Food
    sta inv_item_id + 0
    lda #2
    sta inv_qty + 0
    lda #0
    sta inv_ego + 0
    jsr inven_recalc_weight
    lda inven_weight_lo
    sta tc_wt_lo
    lda inven_weight_hi
    sta tc_wt_hi
    lda #ATK_STEAL_ITEM
    sta mat_atk_type
    lda #15
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda zp_combat_dmg
    bne !t16+
    lda inv_qty + 0
    cmp #1
    bne !t16+
    // Weight must have decreased
    lda inven_weight_lo
    cmp tc_wt_lo
    lda inven_weight_hi
    sbc tc_wt_hi
    bcs !t16+
    // Second steal removes last unit -> FI_EMPTY, weight == 0
    jsr mon_atk_effect_dispatch
    lda inv_item_id + 0
    cmp #FI_EMPTY
    bne !t16+
    lda inven_weight_lo
    ora inven_weight_hi
    bne !t16+
    // Third steal on empty pack is a clean no-op
    jsr mon_atk_effect_dispatch
    lda inven_weight_lo
    ora inven_weight_hi
    bne !t16+
    inc tc_results + 15

    // =========================================================
    // Test 16: Thief blink updates MX_X/Y, zp_mon_x/y, FLAG_OCCUPIED, MF_VISIBLE
    // =========================================================
!t16:
    jsr tc_reset_state
    // Clear map to wall, then carve a 6x6 floor room at rows 8..13, cols 8..13
    ldx #0
!t16_wall:
    jsr map_row_ptr0_x
    ldy #0
    lda #TILE_WALL_H
!t16_wc:
    sta (zp_ptr0),y
    iny
    cpy #MAP_COLS
    bcc !t16_wc-
    inx
    cpx #MAP_ROWS
    bcc !t16_wall-

    ldx #8
!t16_flr:
    jsr map_row_ptr0_x
    ldy #8
    lda #TILE_FLOOR
!t16_fc:
    sta (zp_ptr0),y
    iny
    cpy #14
    bcc !t16_fc-
    inx
    cpx #14
    bcc !t16_flr-

    // Mark player at (8, 8) and monster at (10, 10) occupied
    lda #8
    sta zp_player_x
    sta zp_player_y
    ldx #10
    jsr map_row_ptr0_x
    ldy #10
    lda #TILE_FLOOR | FLAG_OCCUPIED
    sta (zp_ptr0),y

    lda #1
    sta zp_eff_paralyze
    lda #ATK_STEAL_GOLD
    sta mat_atk_type
    lda #16
    sta tc_loop
!t16_lp:
    jsr tc_init_msg_keys
    jsr mon_atk_effect_dispatch
    lda zp_mon_x
    cmp #10
    bne !t16_moved+
    lda zp_mon_y
    cmp #10
    bne !t16_moved+
    dec tc_loop
    bne !t16_lp-
    jmp !t17+
!t16_moved:
    // Old tile (10,10) must have FLAG_OCCUPIED cleared
    ldx #10
    jsr map_row_ptr0_x
    ldy #10
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    bne !t17+
    // New tile (zp_mon_x, zp_mon_y) must have FLAG_OCCUPIED set
    ldx zp_mon_y
    jsr map_row_ptr0_x
    ldy zp_mon_x
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    beq !t17+
    // MX_X, MX_Y, MX_FLAGS must match zp_mon_x, zp_mon_y, and clear MF_VISIBLE
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp zp_mon_x
    bne !t17+
    ldy #MX_Y
    lda (zp_ptr0),y
    cmp zp_mon_y
    bne !t17+
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_VISIBLE
    bne !t17+
    lda zp_dirty_count
    beq !t17+
    inc tc_results + 16

    // =========================================================
    // Test 17: ATK_LOSE_STR (2) AC-reduces HP + drains STR when unsustained
    // =========================================================
!t17:
    jsr tc_reset_state
    lda #100
    sta zp_player_ac
    lda #ATK_LOSE_STR
    sta mat_atk_type
    lda #16
    sta tc_loop
!t17_lp:
    jsr msg_init
    lda #20
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda zp_combat_dmg
    cmp #10
    bne !t18+
    lda player_data + PL_STR_CUR
    cmp #18
    bcc !t17_ok+
    dec tc_loop
    bne !t17_lp-
    jmp !t18+
!t17_ok:
    cmp zp_player_str
    bne !t18+
    inc tc_results + 17

    // =========================================================
    // Test 18: ATK_LOSE_STR (2) blocked by SUST_STR
    // =========================================================
!t18:
    jsr tc_reset_state
    lda #SUST_STR
    sta player_sust_mask
    lda #100
    sta zp_player_ac
    lda #ATK_LOSE_STR
    sta mat_atk_type
    lda #16
    sta tc_loop
!t18_lp:
    jsr msg_init
    lda #20
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda zp_combat_dmg
    cmp #10
    bne !t19+
    dec tc_loop
    bne !t18_lp-
    lda player_data + PL_STR_CUR
    cmp #18
    bne !t19+
    inc tc_results + 18

    // =========================================================
    // Test 19: ATK_LOSE_DEX/INT/WIS (15, 17, 18) drain & matching SUST_* block
    // =========================================================
!t19:
    jsr tc_reset_state
    // Sustain DEX blocks DEX drain, while non-matching SUST_STR does not
    lda #SUST_DEX
    sta player_sust_mask
    lda #ATK_LOSE_DEX
    sta mat_atk_type
    jsr mon_atk_effect_dispatch
    lda player_data + PL_DEX_CUR
    cmp #18
    bne !t20+
    lda #SUST_STR
    sta player_sust_mask
    jsr mon_atk_effect_dispatch
    lda player_data + PL_DEX_CUR
    cmp #17
    bne !t20+
    // INT (17) & WIS (18)
    lda #SUST_INT
    sta player_sust_mask
    lda #ATK_LOSE_INT
    sta mat_atk_type
    jsr mon_atk_effect_dispatch
    lda player_data + PL_INT_CUR
    cmp #18
    bne !t20+
    lda #0
    sta player_sust_mask
    jsr mon_atk_effect_dispatch
    lda player_data + PL_INT_CUR
    cmp #17
    bne !t20+
    lda #ATK_LOSE_WIS
    sta mat_atk_type
    jsr mon_atk_effect_dispatch
    lda player_data + PL_WIS_CUR
    cmp #17
    bne !t20+
    inc tc_results + 19

    // =========================================================
    // Test 20: ATK_LOSE_CON (16) lowers MHP & clamps HP; SUST_CON blocks
    // =========================================================
!t20:
    jsr tc_reset_state
    lda #118                    // 18/100 CON -> high CON HP bonus
    sta player_data + PL_CON_CUR
    sta zp_player_con
    jsr player_calc_hp
    lda player_data + PL_MHP_LO
    sta zp_player_mhp_lo
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    sta tc_max                  // Initial MHP lo
    lda #SUST_CON
    sta player_sust_mask
    lda #ATK_LOSE_CON
    sta mat_atk_type
    lda #0
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda player_data + PL_CON_CUR
    cmp #118
    bne !t21+
    // Remove SUST_CON and drain twice so CON bonus tier drops
    lda #0
    sta player_sust_mask
    jsr mon_atk_effect_dispatch
    jsr mon_atk_effect_dispatch
    jsr mon_atk_effect_dispatch
    lda player_data + PL_CON_CUR
    cmp #118
    bcs !t21+
    lda zp_player_mhp_lo
    cmp tc_max
    bcs !t21+
    cmp zp_player_hp_lo         // HP clamped down to new MHP
    bne !t21+
    inc tc_results + 20

    // =========================================================
    // Test 21: ATK_LOSE_EXP (19) 0 HP even on 52d8 + drains rolled + 2*(xp/100)
    // =========================================================
!t21:
    jsr tc_reset_state
    lda #<1000
    sta player_data + PL_XP_0
    lda #>1000
    sta player_data + PL_XP_1
    lda #0
    sta player_data + PL_XP_2
    lda #ATK_LOSE_EXP
    sta mat_atk_type
    lda #8                      // sides = 8
    ldy #52                     // dice = 52 (Nether Wraith 52d8: 52..416 > 255!)
    jsr mon_atk_hit
    bcs !t22+                   // Must NOT kill player!
    lda zp_player_hp_lo
    cmp #200                    // 0 HP damage!
    bne !t22+
    // Remaining XP in 1000 - (416 + 20) .. 1000 - (52 + 20) = [564, 928]
    lda player_data + PL_XP_0
    cmp #<564
    lda player_data + PL_XP_1
    sbc #>564
    bcc !t22+
    lda player_data + PL_XP_0
    cmp #<929
    lda player_data + PL_XP_1
    sbc #>929
    bcs !t22+
    inc tc_results + 21

    // =========================================================
    // Test 22: ATK_LOSE_EXP (19) drops player level & floors XP/frac at 0
    // =========================================================
!t22:
    jsr tc_reset_state
    lda #3
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #30                     // Lvl 2 threshold=10, Lvl 3 threshold=25 (expfact=100)
    sta player_data + PL_XP_0
    lda #0
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2
    lda #$55
    sta player_data + PL_XP_FRAC_LO
    sta player_data + PL_XP_FRAC_HI
    lda #ATK_LOSE_EXP
    sta mat_atk_type
    lda #25
    sta zp_combat_dmg
    lda #0
    sta mad_dmg_hi
    jsr mon_atk_effect_dispatch // 30 - 25 = 5 XP (< 10) -> drops from lvl 3 to lvl 1!
    lda zp_player_lvl
    cmp #1
    bne !t23+
    lda player_data + PL_LEVEL
    cmp #1
    bne !t23+
    // Drain 50 more XP -> clamps XP & XP_FRAC to 0, stays level 1
    lda #50
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda player_data + PL_XP_0
    ora player_data + PL_XP_1
    ora player_data + PL_XP_2
    ora player_data + PL_XP_FRAC_LO
    ora player_data + PL_XP_FRAC_HI
    bne !t23+
    lda zp_player_lvl
    cmp #1
    bne !t23+
    inc tc_results + 22

    // =========================================================
    // Test 23: ATK_DISENCHANT (21) lowers +bonuses >= 0, keeps cursed & rings
    // =========================================================
!t23:
    jsr tc_reset_state
    lda #ITEM_SLOT_DAGGER                      // Dagger (+1/+1)
    sta inv_item_id + EQUIP_WEAPON
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
        sta inv_ego + EQUIP_WEAPON
    }
    lda #1
    sta inv_to_hit + EQUIP_WEAPON
    sta inv_to_dam + EQUIP_WEAPON
    lda #ITEM_SLOT_LEATHER_ARMOR                      // Leather Armor (+3 AC)
    sta inv_item_id + EQUIP_BODY
    lda #3
    sta inv_to_ac + EQUIP_BODY
    lda #ITEM_SLOT_CLOAK        // Cursed Cloak (-2 AC)
    sta inv_item_id + EQUIP_CLOAK
    lda #<-2
    sta inv_to_ac + EQUIP_CLOAK
    lda #ITEM_SLOT_RING_OF_SLAYING // Ring (+4/+4, immune to VMS disenchant!)
    sta inv_item_id + EQUIP_RING
    .if (ITEM_PAGE_RING_OF_SLAYING != 0) {
        lda #ITEM_PAGE_RING_OF_SLAYING
        sta inv_ego + EQUIP_RING
    }
    lda #4
    sta inv_to_hit + EQUIP_RING
    sta inv_to_dam + EQUIP_RING

    lda #ATK_DISENCHANT
    sta mat_atk_type
    lda #48
    sta tc_loop
!t23_lp:
    jsr msg_init
    lda #12
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda zp_combat_dmg
    bne !t24+
    dec tc_loop
    bne !t23_lp-
    // Dagger (+1/+1) and Armor (+3) must be reduced to 0 (never negative!)
    lda inv_to_hit + EQUIP_WEAPON
    ora inv_to_dam + EQUIP_WEAPON
    ora inv_to_ac + EQUIP_BODY
    bne !t24+
    // Cursed cloak (-2) and Ring (+4/+4) untouched
    lda inv_to_ac + EQUIP_CLOAK
    cmp #<-2
    bne !t24+
    lda inv_to_hit + EQUIP_RING
    cmp #4
    bne !t24+
    lda tc_recalcs
    beq !t24+
    inc tc_results + 23

    // =========================================================
    // Test 24: ATK_EAT_FOOD (22) consumes only ICAT_FOOD & updates weight
    // =========================================================
!t24:
    jsr tc_reset_state
    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS                     // Potion in slot 0 (not food)
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #ITEM_SLOT_RATION_OF_FOOD                     // Ration of Food in slot 1 (qty 2)
    sta inv_item_id + 1
    lda #2
    sta inv_qty + 1
    jsr inven_recalc_weight
    lda inven_weight_lo
    sta tc_wt_lo
    lda inven_weight_hi
    sta tc_wt_hi
    lda #ATK_EAT_FOOD
    sta mat_atk_type
    lda #10
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda zp_combat_dmg
    bne !t25+
    lda inv_qty + 1
    cmp #1
    bne !t25+
    lda inven_weight_lo
    cmp tc_wt_lo
    lda inven_weight_hi
    sbc tc_wt_hi
    bcs !t25+
    jsr mon_atk_effect_dispatch // Eats 2nd ration -> compacts slot 1
    jsr mon_atk_effect_dispatch // No food left -> Potion in slot 0 untouched!
    lda inv_item_id + 0
    cmp #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS
    bne !t25+
    lda inv_item_id + 1
    cmp #FI_EMPTY
    bne !t25+
    inc tc_results + 24

    // =========================================================
    // Test 25: ATK_EAT_LIGHT (23) drains 8..16 charges, floors at 1, ignores 0
    // =========================================================
!t25:
    jsr tc_reset_state
    lda #ITEM_SLOT_BRASS_LANTERN                     // Brass Lantern
    sta inv_item_id + EQUIP_LIGHT
    lda #30
    sta inv_p1 + EQUIP_LIGHT
    lda #ATK_EAT_LIGHT
    sta mat_atk_type
    lda #10
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda zp_combat_dmg
    bne !t26+
    lda inv_p1 + EQUIP_LIGHT
    cmp #14                     // 30 - 16 = 14
    bcc !t26+
    cmp #23                     // 30 - 8 = 22
    bcs !t26+
    // Drain from 5 -> floored at 1
    lda #5
    sta inv_p1 + EQUIP_LIGHT
    jsr mon_atk_effect_dispatch
    lda inv_p1 + EQUIP_LIGHT
    cmp #1
    bne !t26+
    // Fuel 0 stays 0
    lda #0
    sta inv_p1 + EQUIP_LIGHT
    jsr mon_atk_effect_dispatch
    lda inv_p1 + EQUIP_LIGHT
    bne !t26+
    inc tc_results + 25

    // =========================================================
    // Test 26: ATK_EAT_CHARGES (24) zeroes wand/staff p1 & heals monster (cap $7FFF)
    // =========================================================
!t26:
    jsr tc_reset_state
    lda #ITEM_SLOT_WAND_OF_LIGHT                     // Wand of Light (0 charges: skipped)
    sta inv_item_id + 0
    lda #0
    sta inv_p1 + 0
    lda #1
    sta inv_qty + 0
    lda #ITEM_SLOT_POTION_OF_CURE_LIGHT_WOUNDS                     // Potion with p1=9 (not wand/staff: skipped)
    sta inv_item_id + 1
    lda #9
    sta inv_p1 + 1
    lda #1
    sta inv_qty + 1
    lda #ITEM_SLOT_STAFF_OF_LIGHT                     // Staff of Light (6 charges)
    sta inv_item_id + 2
    lda #6
    sta inv_p1 + 2
    lda #1
    sta inv_qty + 2
    lda #10
    sta cr_level + 26           // Heal = 10 * 6 = 60 -> 50 + 60 = 110
    lda #ATK_EAT_CHARGES
    sta mat_atk_type
    lda #10
    sta zp_combat_dmg
    jsr mon_atk_effect_dispatch
    lda zp_combat_dmg
    bne !t27+
    lda inv_p1 + 2
    bne !t27+
    lda inv_p1 + 1
    cmp #9
    bne !t27+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #110
    bne !t27+
    // Test 15-bit monster HP saturation at $7FFF
    lda #$f0
    sta (zp_ptr0),y
    iny
    lda #$7f
    sta (zp_ptr0),y
    lda #10
    sta inv_p1 + 0
    jsr mon_atk_effect_dispatch
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #$ff
    bne !t27+
    iny
    lda (zp_ptr0),y
    cmp #$7f
    bne !t27+
    inc tc_results + 26

    // =========================================================
    // Test 27: Gold stolen message ("Your purse feels lighter.") & status AU: refresh
    // =========================================================
!t27:
    jsr tc_reset_state
    lda #1
    sta zp_eff_paralyze
    lda #200
    sta player_data + PL_GOLD_0
    lda #0
    sta player_data + PL_GOLD_1
    sta player_data + PL_GOLD_2
    jsr status_mark_dirty
    jsr status_draw
    lda $0400 + 23 * SCREEN_COLS + STS_ROW23_AU_COL + 3
    cmp #'2'
    bne !t28+
    jsr tc_init_msg_keys
    lda #ATK_STEAL_GOLD
    sta mat_atk_type
    jsr mon_atk_effect_dispatch
    ldx #<tc_str_stl_gold
    ldy #>tc_str_stl_gold
    jsr tc_match_row0_exact
    bcc !t28+
    // status_draw refreshed AU: from 200 to 155..179 ('1'..) and updated cache
    lda $0400 + 23 * SCREEN_COLS + STS_ROW23_AU_COL + 3
    cmp #'1'
    bne !t28+
    lda status_prev_gold_lo
    cmp player_data + PL_GOLD_0
    bne !t28+
    // Also exercise through full monster_attack_player (1 gold -> 0 -> '0')
    lda #1
    sta player_data + PL_GOLD_0
    jsr status_mark_dirty
    jsr status_draw
    lda #60
    sta cr_level + 26
    lda #$80 | ATK_STEAL_GOLD
    sta cr_atk0_type + 26
    lda #$20                    // ADESC_TOUCHES (5)
    sta cr_atk0_sides + 26
    lda #16
    sta tc_loop
!t27_lp:
    jsr tc_init_msg_keys
    jsr monster_attack_player
    lda mat_any_hit
    bne !t27_hit+
    dec tc_loop
    bne !t27_lp-
    jmp !t28+
!t27_hit:
    lda $0400 + 23 * SCREEN_COLS + STS_ROW23_AU_COL + 3
    cmp #'0'
    bne !t28+
    inc tc_results + 27

    // =========================================================
    // Test 28: Gold theft dodged message ("You quickly protect your money pouch!")
    // =========================================================
!t28:
    jsr tc_reset_state
    lda #125                    // randint(124) in 1..124 is always < 125
    sta zp_player_dex
    lda #100
    sta player_data + PL_GOLD_0
    lda #ATK_STEAL_GOLD
    sta mat_atk_type
    jsr mon_atk_effect_dispatch
    lda player_data + PL_GOLD_0
    cmp #100
    bne !t29+
    ldx #<tc_str_prot_gold
    ldy #>tc_str_prot_gold
    jsr tc_match_row0_exact
    bcc !t29+
    inc tc_results + 28

    // =========================================================
    // Test 29: Item stolen message ("Your backpack feels lighter.") & VMS subval>=512 rule
    // =========================================================
!t29:
    jsr tc_reset_state
    lda #1
    sta zp_eff_paralyze
    // VMS subval >= 512: Arrow stack (qty 12) loses entire slot in 1 theft
    lda #ITEM_SLOT_ARROW
    sta inv_item_id + 0
    lda #12
    sta inv_qty + 0
    lda #0
    sta inv_ego + 0
    jsr inven_recalc_weight
    lda #ATK_STEAL_ITEM
    sta mat_atk_type
    jsr mon_atk_effect_dispatch
    lda inv_item_id + 0
    cmp #FI_EMPTY
    bne !t30+
    lda inven_weight_lo
    ora inven_weight_hi
    bne !t30+
    ldx #<tc_str_stl_item
    ldy #>tc_str_stl_item
    jsr tc_match_row0_exact
    bcc !t30+
    // VMS subval >= 512: Iron Spike stack (qty 5) also loses entire slot
    jsr tc_init_msg_keys
    lda #ITEM_SLOT_IRON_SPIKE
    sta inv_item_id + 0
    lda #5
    sta inv_qty + 0
    jsr inven_recalc_weight
    jsr mon_atk_effect_dispatch
    lda inv_item_id + 0
    cmp #FI_EMPTY
    bne !t30+
    // Empty pack does NOT print "Your backpack feels lighter."
    jsr tc_init_msg_keys
    jsr mon_atk_effect_dispatch
    ldx #<tc_str_stl_item
    ldy #>tc_str_stl_item
    jsr tc_match_row0_exact
    bcs !t30+
    inc tc_results + 29

    // =========================================================
    // Test 30: Item theft dodged message ("You grab hold of your backpack!")
    // =========================================================
!t30:
    jsr tc_reset_state
    lda #125
    sta zp_player_dex
    lda #ITEM_SLOT_RATION_OF_FOOD
    sta inv_item_id + 0
    lda #2
    sta inv_qty + 0
    lda #ATK_STEAL_ITEM
    sta mat_atk_type
    jsr mon_atk_effect_dispatch
    lda inv_qty + 0
    cmp #2
    bne !t31+
    ldx #<tc_str_prot_item
    ldy #>tc_str_prot_item
    jsr tc_match_row0_exact
    bcc !t31+
    inc tc_results + 30

    // =========================================================
    // Test 31: Thief blink smoke message ("There is a puff of smoke!") on Row 1
    // =========================================================
!t31:
    jsr tc_reset_state
    // Carve small floor box at rows 8..12, cols 8..12 around thief (10,10)
    ldx #8
!t31_flr:
    jsr map_row_ptr0_x
    ldy #8
    lda #TILE_FLOOR
!t31_fc:
    sta (zp_ptr0),y
    iny
    cpy #13
    bcc !t31_fc-
    inx
    cpx #13
    bcc !t31_flr-
    lda #8
    sta zp_player_x
    sta zp_player_y
    ldx #10
    jsr map_row_ptr0_x
    ldy #10
    lda #TILE_FLOOR | FLAG_OCCUPIED
    sta (zp_ptr0),y
    lda #125
    sta zp_player_dex           // Dodge on Row 0; smoke on Row 1 when 50% blink triggers
    lda #ATK_STEAL_GOLD
    sta mat_atk_type
    lda #24
    sta tc_loop
!t31_lp:
    jsr tc_init_msg_keys
    jsr mon_atk_effect_dispatch
    lda zp_mon_x
    cmp #10
    bne !t31_smoke+
    lda zp_mon_y
    cmp #10
    bne !t31_smoke+
    // Did not blink -> only 1 message printed (Row 1 unused)
    lda zp_msg_flags
    cmp #MSG_PENDING
    bne !t32+
    dec tc_loop
    bne !t31_lp-
    jmp !t32+
!t31_smoke:
    ldx #<tc_str_prot_gold
    ldy #>tc_str_prot_gold
    jsr tc_match_row0_exact
    bcc !t32+
    ldx #<tc_str_smoke
    ldy #>tc_str_smoke
    jsr tc_match_row1_exact
    bcc !t32+
    inc tc_results + 31

    // =========================================================
    // Test 32: VMS teleport_away(monptr, max_sight=20) — thief always lands within +-20
    // =========================================================
!t32:
    jsr tc_reset_state
    // Open the entire interior (rows 1..64, cols 1..196 = 12,544 floor tiles) so an
    // unconstrained random-floor picker would land outside +-20 >86% of the time.
    ldx #1
!t32_flr:
    jsr map_row_ptr0_x
    ldy #1
    lda #TILE_FLOOR
!t32_fc:
    sta (zp_ptr0),y
    iny
    cpy #MAP_COLS - 1
    bcc !t32_fc-
    inx
    cpx #MAP_ROWS - 1
    bcc !t32_flr-

    lda #30
    sta zp_player_x
    lda #29
    sta zp_player_y
    lda #1
    sta zp_eff_paralyze
    lda #60
    sta cr_level + 26
    lda #ATK_STEAL_GOLD
    sta cr_atk0_type + 26
    lda #0
    sta tc_cnt1                 // Blink count across 32 rounds
    lda #32
    sta tc_loop
!t32_lp:
    // Place thief at (30, 30) with FLAG_OCCUPIED
    lda #30
    sta zp_mon_x
    sta zp_mon_y
    ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda #30
    sta (zp_ptr0),y
    iny
    sta (zp_ptr0),y
    ldy #MX_FLAGS
    lda #MF_AWAKE | MF_VISIBLE
    sta zp_mon_flags
    sta (zp_ptr0),y
    ldx #30
    jsr map_row_ptr0_x
    ldy #30
    lda #TILE_FLOOR | FLAG_OCCUPIED
    sta (zp_ptr0),y

    jsr tc_init_msg_keys
    jsr monster_attack_player
    lda zp_mon_x
    cmp #30
    bne !t32_chk+
    lda zp_mon_y
    cmp #30
    beq !t32_nx+
!t32_chk:
    inc tc_cnt1
    // Must land within [30-20, 30+20] = [10, 50] on both axes
    lda zp_mon_x
    cmp #10
    bcc !t33+
    cmp #51
    bcs !t33+
    lda zp_mon_y
    cmp #10
    bcc !t33+
    cmp #51
    bcs !t33+
    // Must never land on player at (30, 29)
    lda zp_mon_x
    cmp #30
    bne !t32_clr+
    lda zp_mon_y
    cmp #29
    beq !t33+
!t32_clr:
    // Clear new tile occupancy before resetting thief to (30, 30)
    ldx zp_mon_y
    jsr map_row_ptr0_x
    ldy zp_mon_x
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    beq !t33+
    lda #TILE_FLOOR
    sta (zp_ptr0),y
!t32_nx:
    dec tc_loop
    bne !t32_lp-
    lda tc_cnt1
    cmp #6                      // Expected ~16 blinks out of 32 hits
    bcc !t33+
    inc tc_results + 32

    // =========================================================
    // Test 33: All 6 VMS monster stat/XP drain messages (STR, DEX, CON, INT, WIS, EXP)
    // =========================================================
!t33:
    jsr tc_reset_state
    lda #0
    sta player_sust_mask
    // 1. ATK_LOSE_STR (50% roll -> loop up to 32 tries until drained)
    lda #32
    sta tc_loop
!t33_str_lp:
    jsr tc_init_msg_keys
    lda #ATK_LOSE_STR
    sta mat_atk_type
    jsr mon_atk_effect_dispatch
    lda player_data + PL_STR_CUR
    cmp #18
    bcc !t33_str_hit+
    dec tc_loop
    bne !t33_str_lp-
    jmp !done+
!t33_str_hit:
    ldx #<tc_str_drn_str
    ldy #>tc_str_drn_str
    jsr tc_match_row0_exact
    bcc !done+

    // 2..5: DEX (15), CON (16), INT (17), WIS (18)
    ldx #0
!t33_stat_lp:
    stx tc_loop
    jsr tc_init_msg_keys
    ldx tc_loop
    lda tc_drn_atk,x
    sta mat_atk_type
    jsr mon_atk_effect_dispatch
    ldy tc_loop
    ldx tc_drn_msg_lo,y
    lda tc_drn_msg_hi,y
    tay
    jsr tc_match_row0_exact
    bcc !done+
    ldx tc_loop
    inx
    cpx #4
    bcc !t33_stat_lp-

    // 6. ATK_LOSE_EXP (19) via mon_atk_hit (row 0 = XP drain message)
    jsr tc_init_msg_keys
    lda #ATK_LOSE_EXP
    sta mat_atk_type
    lda #8
    ldy #1
    jsr mon_atk_hit
    ldx #<tc_str_drn_exp
    ldy #>tc_str_drn_exp
    jsr tc_match_row0_exact
    bcc !done+
    inc tc_results + 33

!done:
    jmp test_exit_trampoline

// Expected strings for screen row 0 & all 18 verb phrases (2..19)
tc_str_orc_hits:    .text "the orc hits you." ; .byte 0
tc_str_orc_touches: .text "the orc touches you." ; .byte 0
tc_str_orc_spores:  .text "the orc releases a cloud of spores." ; .byte 0
tc_str_stl_gold:    .text "Your purse feels lighter." ; .byte 0
tc_str_prot_gold:   .text "You quickly protect your money pouch!" ; .byte 0
tc_str_stl_item:    .text "Your backpack feels lighter." ; .byte 0
tc_str_prot_item:   .text "You grab hold of your backpack!" ; .byte 0
tc_str_smoke:       .text "There is a puff of smoke!" ; .byte 0
tc_str_drn_str:     .text "You feel weaker." ; .byte 0
tc_str_drn_dex:     .text "You feel more clumsy." ; .byte 0
tc_str_drn_con:     .text "Your health is damaged!" ; .byte 0
tc_str_drn_int:     .text "You feel your memories fading..." ; .byte 0
tc_str_drn_wis:     .text "Your wisdom is drained." ; .byte 0
tc_str_drn_exp:     .text "You feel your life draining away!" ; .byte 0

tc_drn_atk:    .byte ATK_LOSE_DEX, ATK_LOSE_CON, ATK_LOSE_INT, ATK_LOSE_WIS
tc_drn_msg_lo: .byte <tc_str_drn_dex, <tc_str_drn_con, <tc_str_drn_int, <tc_str_drn_wis
tc_drn_msg_hi: .byte >tc_str_drn_dex, >tc_str_drn_con, >tc_str_drn_int, >tc_str_drn_wis

tv_02: .text " bites you." ; .byte 0
tv_03: .text " claws you." ; .byte 0
tv_04: .text " stings you." ; .byte 0
tv_05: .text " touches you." ; .byte 0
tv_06: .text " kicks you." ; .byte 0
tv_07: .text " gazes at you." ; .byte 0
tv_08: .text " breathes on you." ; .byte 0
tv_09: .text " spits on you." ; .byte 0
tv_10: .text " makes a horrible wail." ; .byte 0
tv_11: .text " embraces you." ; .byte 0
tv_12: .text " crawls on you." ; .byte 0
tv_13: .text " releases a cloud of spores." ; .byte 0
tv_14: .text " begs you for money." ; .byte 0
tv_15: .text " slimes you." ; .byte 0
tv_16: .text " crushes you." ; .byte 0
tv_17: .text " tramples you." ; .byte 0
tv_18: .text " drools on you." ; .byte 0
tv_19: .text " insults you." ; .byte 0

tc_verb_lo:
    .byte <tv_02, <tv_03, <tv_04, <tv_05, <tv_06, <tv_07, <tv_08, <tv_09, <tv_10
    .byte <tv_11, <tv_12, <tv_13, <tv_14, <tv_15, <tv_16, <tv_17, <tv_18, <tv_19
tc_verb_hi:
    .byte >tv_02, >tv_03, >tv_04, >tv_05, >tv_06, >tv_07, >tv_08, >tv_09, >tv_10
    .byte >tv_11, >tv_12, >tv_13, >tv_14, >tv_15, >tv_16, >tv_17, >tv_18, >tv_19

monster_attack2_test_end:
.assert "Monster attack2 test stays below MAP_BASE", monster_attack2_test_end <= MAP_BASE, true
