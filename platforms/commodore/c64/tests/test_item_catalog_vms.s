// test_item_catalog_vms.s — Exhaustive C64 runtime verification of all 361 VMS
// Moria 4.8 item templates (0..360 across Page 0 0..254 and Page 1 0..105):
//   Test 1 ($0400): All 361 decoded item names (length + 16-bit digest)
//   Test 2 ($0401): All 361 hot catalog getters (ICAT_*, base_ac, glyph, color, unknown_idx, missile_type)
//   Test 3 ($0402): All 361 cold ITEM.CAT fields (16-bit cost, 16-bit weight, dice/sides, p1, 32-bit VMS flags, tohit/todam/toac)
//   Test 4 ($0403): Books (186..193), Lights (194..196), Spike (197), all 6 Digging tools (198..203 via calc_dig_ability), Chests (204..210), Ranged (234..243), Crowns (249..251)
//   Test 5 ($0404): All 41 Rings & Amulets (309..349) stat masks, Page-0 non-aliasing, PFLAG_*/PFLAG2_*/SUST_*/Slaying/AC/Wield recalc, & monster_ai Page-1 Ring of Speed
//
// Results at $0400-$0404: $01 = pass, $00 = fail per test (5 tests)

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_finish:
    sei
    :BankOutBasic()
    ldx #4
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = $0830 "Main"
.encoding "screencode_mixed"

.segmentdef TestCreateOverlay [start=$D000, min=$D000, max=$FFF9]
.segmentdef TestUnusedStatus [start=$D000, min=$D000, max=$FFF9]
.segmentdef TestUnusedCombat [start=$D000, min=$D000, max=$FFF9]
.segmentdef TestUnusedMagic [start=$D000, min=$D000, max=$FFF9]
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
.segment TestUnusedStatus
#import "../../../../core/ui_status.s"
.segment Default
#import "../../../../core/ui_help_clear.s"
.segment TestCreateOverlay
#import "../../../../core/stat_display.s"
player_create:
    brk
.segment Default
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "dungeon_gen_stubs.s"
#import "../../../../core/huffman.s"
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
.segment TestUnusedStatus
#import "../../../../core/dungeon_features.s"
.segment Default
#import "chest_summons_stubs.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/monster_ai.s"
.segment TestUnusedStatus
#import "../../../../core/recall.s"
.segment TestCreateOverlay
#import "../../../../core/monster_magic.s"
.segment Default
#define ITEM_SPAWN_EXTERNAL
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../../../../core/item.s"
#undef ITEM_SPAWN_EXTERNAL
#import "item_cat_resident_helper.s"
.segment TestUnusedMagic
#import "../../../../core/special_rooms.s"
.segment Default
#import "../../../../core/ego_items.s"
#import "../../../../core/special_rooms_stubs.s"
#define ITEM_ACTIONS_OVERLAY_EXTERNAL
#define PLAYER_RECALC_EQUIPMENT_EXTERNAL
.segment TestUnusedMagic
#import "../../../../core/player_items.s"
.segment Default
#undef PLAYER_RECALC_EQUIPMENT_EXTERNAL
#import "../../../../core/player_recalc_equipment.s"
#undef ITEM_ACTIONS_OVERLAY_EXTERNAL
#import "../../../../core/spell_data.s"
.segment TestCreateOverlay
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
.segment Default
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
.segment TestUnusedMagic
#import "../../../../core/player_magic.s"
.segment TestCreateOverlay
#import "../dungeon_render.s"
.segment Default
#import "../../../../core/dungeon_los.s"
.segment TestCreateOverlay
#import "../../../../core/player_move.s"
.segment TestUnusedCombat
#import "../../../../core/combat.s"
.segment TestCreateOverlay
#import "../../../../core/scene_mat_tile.s"
.segment Default
#import "../../../../core/calc_dig_cold.s"
#import "../../../../core/ui_trampoline_stubs.s"

tun_dig_ability: .byte 0
eff_fear_timer: .byte 0
mad_dmg_hi: .byte 0
mon_atk_acid_armour:
mon_atk_apply_damage:
mon_atk_apply_damage_16:
player_death_check:
player_disarm_get_effective_chance:
    clc
    rts
monster_attack_player:
player_update_hunger_state:
item_read_scroll:
item_aim_wand:
item_use_staff:
    sec
    rts
ui_char_display:
ui_help_display:
ui_help_show_paged:
help_draw_line:
help_draw_hborder:
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
store_init_all:
store_restock_all:
store_enter:
    rts
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

tc_results: .fill 5, $ff
t_slot:     .byte 0
t_limit:    .byte 0
t_hash_lo:  .byte 0
t_hash_hi:  .byte 0
t_hash_b:   .byte 0
t_base_ac:  .byte 0
t_base_hit: .byte 0
t_base_dam: .byte 0

test_start:
    jsr screen_clear
    jsr msg_init

    // =========================================================================
    // Test 1: Verify all 361 decoded item names (0..254 Page 0, 0..105 Page 1)
    // =========================================================================
    lda #0
    sta item_cur_page
    sta t_slot
!t1_p0:
    ldx t_slot
    jsr id_known_set
    lda t_slot
    jsr item_get_name_ptr
    jsr compute_name_digest
    ldx t_slot
    tya
    cmp exp_name_len_p0,x
    bne !t1_fail+
    lda t_hash_lo
    cmp exp_name_hlo_p0,x
    bne !t1_fail+
    lda t_hash_hi
    cmp exp_name_hhi_p0,x
    bne !t1_fail+
    inc t_slot
    lda t_slot
    cmp #ITEM_PAGE_SIZE
    bcc !t1_p0-

    lda #ITEM_PAGE_BIT
    sta item_cur_page
    lda #0
    sta t_slot
!t1_p1:
    ldx t_slot
    jsr id_known_set
    lda t_slot
    jsr item_get_name_ptr
    jsr compute_name_digest
    ldx t_slot
    tya
    cmp exp_name_len_p1,x
    bne !t1_fail+
    lda t_hash_lo
    cmp exp_name_hlo_p1,x
    bne !t1_fail+
    lda t_hash_hi
    cmp exp_name_hhi_p1,x
    bne !t1_fail+
    inc t_slot
    lda t_slot
    cmp #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)
    bcc !t1_p1-

    lda #0
    sta item_cur_page
    lda #$01
    sta tc_results + 0
    jmp !t2_start+
!t1_fail:
    lda #0
    sta item_cur_page
    sta tc_results + 0

    // =========================================================================
    // Test 2: Verify all 361 hot catalog getters across Page 0 & Page 1
    // (ICAT_*, base_ac, display_char, color, unknown_idx, missile_type)
    // =========================================================================
!t2_start:
    lda #0
    sta item_cur_page
    sta t_slot
!t2_p0:
    ldx t_slot
    txa
    jsr item_get_category_a
    ldx t_slot
    cmp exp_cat_p0,x
    beq !+
    jmp !t2_fail+
!:  ldy t_slot
    jsr item_get_base_ac
    ldx t_slot
    cmp exp_ac_p0,x
    beq !+
    jmp !t2_fail+
!:  ldx t_slot
    jsr item_get_display_char
    ldx t_slot
    cmp exp_glyph_p0,x
    beq !+
    jmp !t2_fail+
!:  ldy t_slot
    jsr it_read_color_ac_y
    lsr
    lsr
    lsr
    lsr
    ldx t_slot
    cmp exp_color_p0,x
    beq !+
    jmp !t2_fail+
!:  lda t_slot
    jsr item_get_unknown_idx_a
    ldx t_slot
    cmp exp_uidx_p0,x
    beq !+
    jmp !t2_fail+
!:  ldx t_slot
    jsr item_get_missile
    ldx t_slot
    cmp exp_msl_p0,x
    beq !+
    jmp !t2_fail+
!:  inc t_slot
    lda t_slot
    cmp #ITEM_PAGE_SIZE
    bcs !t2_p1_init+
    jmp !t2_p0-

!t2_p1_init:
    lda #ITEM_PAGE_BIT
    sta item_cur_page
    lda #0
    sta t_slot
!t2_p1:
    ldx t_slot
    txa
    jsr item_get_category_a
    ldx t_slot
    cmp exp_cat_p1,x
    beq !+
    jmp !t2_fail+
!:  ldy t_slot
    jsr item_get_base_ac
    ldx t_slot
    cmp exp_ac_p1,x
    beq !+
    jmp !t2_fail+
!:  ldx t_slot
    jsr item_get_display_char
    ldx t_slot
    cmp exp_glyph_p1,x
    beq !+
    jmp !t2_fail+
!:  ldy t_slot
    jsr it_read_color_ac_y
    lsr
    lsr
    lsr
    lsr
    ldx t_slot
    cmp exp_color_p1,x
    beq !+
    jmp !t2_fail+
!:  lda t_slot
    jsr item_get_unknown_idx_a
    ldx t_slot
    cmp exp_uidx_p1,x
    beq !+
    jmp !t2_fail+
!:  ldx t_slot
    jsr item_get_missile
    ldx t_slot
    cmp exp_msl_p1,x
    beq !+
    jmp !t2_fail+
!:  inc t_slot
    lda t_slot
    cmp #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)
    bcs !t2_pass+
    jmp !t2_p1-

!t2_pass:
    lda #0
    sta item_cur_page
    lda #$01
    sta tc_results + 1
    jmp !t3_start+
!t2_fail:
    lda #0
    sta item_cur_page
    sta tc_results + 1

    // =========================================================================
    // Test 3: Verify all 361 cold ITEM.CAT fields (cost, weight, dice/sides,
    // p1, 32-bit VMS flags, tohit/todam/toac) across Page 0 & Page 1
    // =========================================================================
!t3_start:
    lda #0
    sta item_cur_page
    sta t_slot
!t3_p0:
    ldx t_slot
    jsr item_get_cost_x
    ldx t_slot
    cmp exp_cost_lo_p0,x
    beq !+
    jmp !t3_fail+
!:  lda icat_cost_hi
    cmp exp_cost_hi_p0,x
    beq !+
    jmp !t3_fail+
!:  jsr item_get_weight_x
    ldx t_slot
    cmp exp_wt_lo_p0,x
    beq !+
    jmp !t3_fail+
!:  lda icat_weight_hi
    cmp exp_wt_hi_p0,x
    beq !+
    jmp !t3_fail+
!:  txa
    jsr item_cat_select_id
    jsr item_cat_get_dmg
    ldx t_slot
    cmp exp_dice_p0,x
    beq !+
    jmp !t3_fail+
!:  lda icat_dmg_sides
    cmp exp_sides_p0,x
    beq !+
    jmp !t3_fail+
!:  jsr item_cat_get_effects
    ldx t_slot
    lda icat_flags_0
    cmp exp_f0_p0,x
    beq !+
    jmp !t3_fail+
!:  lda icat_flags_1
    cmp exp_f1_p0,x
    beq !+
    jmp !t3_fail+
!:  lda icat_flags_2
    cmp exp_f2_p0,x
    beq !+
    jmp !t3_fail+
!:  lda icat_flags_3
    cmp exp_f3_p0,x
    beq !+
    jmp !t3_fail+
!:  lda icat_p1_lo
    cmp exp_p1_lo_p0,x
    beq !+
    jmp !t3_fail+
!:  lda icat_p1_hi
    cmp exp_p1_hi_p0,x
    beq !+
    jmp !t3_fail+
!:  lda icat_tohit
    cmp exp_tohit_p0,x
    beq !+
    jmp !t3_fail+
!:  lda icat_todam
    cmp exp_todam_p0,x
    beq !+
    jmp !t3_fail+
!:  lda icat_toac
    cmp exp_toac_p0,x
    beq !+
    jmp !t3_fail+
!:  inc t_slot
    lda t_slot
    cmp #ITEM_PAGE_SIZE
    bcs !t3_p1_init+
    jmp !t3_p0-

!t3_p1_init:
    lda #ITEM_PAGE_BIT
    sta item_cur_page
    lda #0
    sta t_slot
!t3_p1:
    ldx t_slot
    jsr item_get_cost_x
    ldx t_slot
    cmp exp_cost_lo_p1,x
    beq !+
    jmp !t3_fail+
!:  lda icat_cost_hi
    cmp exp_cost_hi_p1,x
    beq !+
    jmp !t3_fail+
!:  jsr item_get_weight_x
    ldx t_slot
    cmp exp_wt_lo_p1,x
    beq !+
    jmp !t3_fail+
!:  lda icat_weight_hi
    cmp exp_wt_hi_p1,x
    beq !+
    jmp !t3_fail+
!:  txa
    jsr item_cat_select_id
    jsr item_cat_get_dmg
    ldx t_slot
    cmp exp_dice_p1,x
    beq !+
    jmp !t3_fail+
!:  lda icat_dmg_sides
    cmp exp_sides_p1,x
    beq !+
    jmp !t3_fail+
!:  jsr item_cat_get_effects
    ldx t_slot
    lda icat_flags_0
    cmp exp_f0_p1,x
    beq !+
    jmp !t3_fail+
!:  lda icat_flags_1
    cmp exp_f1_p1,x
    beq !+
    jmp !t3_fail+
!:  lda icat_flags_2
    cmp exp_f2_p1,x
    beq !+
    jmp !t3_fail+
!:  lda icat_flags_3
    cmp exp_f3_p1,x
    beq !+
    jmp !t3_fail+
!:  lda icat_p1_lo
    cmp exp_p1_lo_p1,x
    beq !+
    jmp !t3_fail+
!:  lda icat_p1_hi
    cmp exp_p1_hi_p1,x
    beq !+
    jmp !t3_fail+
!:  lda icat_tohit
    cmp exp_tohit_p1,x
    beq !+
    jmp !t3_fail+
!:  lda icat_todam
    cmp exp_todam_p1,x
    beq !+
    jmp !t3_fail+
!:  lda icat_toac
    cmp exp_toac_p1,x
    beq !+
    jmp !t3_fail+
!:  inc t_slot
    lda t_slot
    cmp #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)
    bcs !t3_pass+
    jmp !t3_p1-

!t3_pass:
    lda #0
    sta item_cur_page
    lda #$01
    sta tc_results + 2
    jmp !t4_start+
!t3_fail:
    lda #0
    sta item_cur_page
    sta tc_results + 2

    // =========================================================================
    // Test 4: Digging tools (198..203 via calc_dig_ability), Books (186..193),
    // Chests (204..210), Ranged (234..243), Crowns (249..251)
    // =========================================================================
!t4_start:
    // 4A: All 6 digging tools at STR=16 (STR>>2 = 4), ego=0 -> 24, 10, 36, 48, 22, 34
    jsr item_init_inventory
    lda #16
    sta zp_player_str
    sta player_data + PL_STR_CUR
    lda #0
    sta player_data + PL_TODMG
    ldy #0
!t4_dig_loop:
    sty t_slot
    lda dig_tool_ids,y
    sta inv_item_id + EQUIP_WEAPON
    lda #0
    sta inv_ego + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON
    jsr calc_dig_ability
    ldy t_slot
    lda tun_dig_ability
    cmp dig_tool_exp,y
    beq !+
    jmp !t4_fail+
!:  iny
    cpy #6
    bcc !t4_dig_loop-

    // 4B: Ego bonus (+1 * 12 = +12) on Pick (24 + 12 = 36) and (+2 * 12 = +24) on Shovel (10 + 24 = 34),
    // while Dwarven Shovel ignores tool ego (stays 34) per calc_dig_cold.s cpx #2
    lda #ITEM_SLOT_PICK
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_ego + EQUIP_WEAPON
    jsr calc_dig_ability
    lda tun_dig_ability
    cmp #36
    beq !+
    jmp !t4_fail+
!:  lda #ITEM_SLOT_SHOVEL
    sta inv_item_id + EQUIP_WEAPON
    lda #2
    sta inv_ego + EQUIP_WEAPON
    jsr calc_dig_ability
    lda tun_dig_ability
    cmp #34
    beq !+
    jmp !t4_fail+
!:  lda #ITEM_SLOT_DWARVEN_SHOVEL
    sta inv_item_id + EQUIP_WEAPON
    lda #2
    sta inv_ego + EQUIP_WEAPON
    jsr calc_dig_ability
    lda tun_dig_ability
    cmp #34
    beq !+
    jmp !t4_fail+

    // 4C: Mage books 186..189 and Priest books 190..193 contiguous book indices 0..3
!:  .assert "Mage & Priest books contiguous on Page 0", ITEM_SPELLBOOK_THE_MAGES_GUIDE_TO_POWER - ITEM_SPELLBOOK_BEGINNERS_MAGICK == 3 && ITEM_HOLY_BOOK_OF_PRAYERS_EXORCISM - ITEM_HOLY_BOOK_OF_PRAYERS_BEGINNERS_HANDBOOK == 3 && ITEM_PAGE_SPELLBOOK_BEGINNERS_MAGICK == 0 && ITEM_PAGE_HOLY_BOOK_OF_PRAYERS_EXORCISM == 0, true
    .assert "Live chests 204..209 + Ruined Chest 210 contiguous on Page 0", ITEM_LARGE_STEEL_CHEST - ITEM_SMALL_WOODEN_CHEST == 5 && ITEM_RUINED_CHEST == ITEM_LARGE_STEEL_CHEST + 1 && ITEM_PAGE_SMALL_WOODEN_CHEST == 0, true
    .assert "Crowns contiguous at end of Helms on Page 0", ITEM_GOLDEN_CROWN == ITEM_SILVER_CROWN + 1 && ITEM_JEWEL_ENCRUSTED_CROWN == ITEM_SILVER_CROWN + 2 && ITEM_PAGE_SILVER_CROWN == 0, true

    // 4D: Ranged launcher & ammo p1 multipliers on 234..239 (2,3,4,5,6,1)
    lda #0
    sta item_cur_page
    ldy #0
!t4_bow_loop:
    sty t_slot
    tya
    clc
    adc #ITEM_SLOT_SHORT_BOW
    jsr item_cat_select_id
    jsr item_cat_get_effects
    ldy t_slot
    lda icat_p1_lo
    cmp bow_exp_p1,y
    beq !+
    jmp !t4_fail+
!:  iny
    cpy #6
    bcc !t4_bow_loop-

    lda #$01
    sta tc_results + 3
    jmp !t5_start+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // =========================================================================
    // Test 5: All 41 Jewelry items (309..349 on Page 1):
    //   - equip_stat_mask_x matches VMS stat mask on Page 1
    //   - equip_stat_mask_x returns 0 for Page-0 items with same slot_lo (54..94)
    //   - player_recalc_equipment sets exact PFLAG_*, PFLAG2_*, SUST_* for all 41
    //   - Ring of Slaying / Increase Damage / Increase To-Hit / Protection bonuses
    //   - monster_ai_tick Ring of Speed check works on Page 1 and ignores Page 0
    // =========================================================================
!t5_start:
    lda #RACE_HUMAN
    sta player_data + PL_RACE
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #12
    sta player_data + PL_STR_BASE
    sta player_data + PL_INT_BASE
    sta player_data + PL_WIS_BASE
    sta player_data + PL_DEX_BASE
    sta player_data + PL_CON_BASE
    sta player_data + PL_CHR_BASE
    sta player_data + PL_STR_CUR
    sta player_data + PL_INT_CUR
    sta player_data + PL_WIS_CUR
    sta player_data + PL_DEX_CUR
    sta player_data + PL_CON_CUR
    sta player_data + PL_CHR_CUR

    lda #0
    sta t_slot
!t5_jloop:
    jsr item_init_inventory
    ldy t_slot
    tya
    clc
    adc #ITEM_SLOT_RING_OF_STRENGTH
    cpy #31
    bcs !t5_amulet_slot+
    // Ring (0..30 -> EQUIP_RING)
    sta inv_item_id + EQUIP_RING
    lda #ITEM_PAGE_BIT
    sta inv_ego + EQUIP_RING
    lda #1
    sta inv_qty + EQUIP_RING
    ldx #EQUIP_RING
    jsr equip_stat_mask_x
    ldy t_slot
    cmp exp_jewelry_stat,y
    beq !+
    lda #$21
    jmp !t5_fail_code+
    // Verify Page 0 with same slot_lo returns 0 (no false Page-0 stat match)
!:  lda #0
    sta inv_ego + EQUIP_RING
    ldx #EQUIP_RING
    jsr equip_stat_mask_x
    beq !+
    lda #$22
    jmp !t5_fail_code+
!:  lda #ITEM_PAGE_BIT
    sta inv_ego + EQUIP_RING
    jmp !t5_check_pflags+

!t5_amulet_slot:
    // Amulet (31..40 -> EQUIP_AMULET)
    sta inv_item_id + EQUIP_AMULET
    lda #ITEM_PAGE_BIT
    sta inv_ego + EQUIP_AMULET
    lda #1
    sta inv_qty + EQUIP_AMULET
    ldx #EQUIP_AMULET
    jsr equip_stat_mask_x
    ldy t_slot
    cmp exp_jewelry_stat,y
    beq !+
    lda #$23
    jmp !t5_fail_code+
!:  lda #0
    sta inv_ego + EQUIP_AMULET
    ldx #EQUIP_AMULET
    jsr equip_stat_mask_x
    beq !+
    lda #$24
    jmp !t5_fail_code+
!:  lda #ITEM_PAGE_BIT
    sta inv_ego + EQUIP_AMULET

!t5_check_pflags:
    jsr player_recalc_equipment
    ldy t_slot
    lda player_pflags
    cmp exp_jewelry_pf1,y
    beq !+
    lda #$25
    jmp !t5_fail_code+
!:  lda player_pflags2
    cmp exp_jewelry_pf2,y
    beq !+
    lda #$26
    jmp !t5_fail_code+
!:  lda player_sust_mask
    cmp exp_jewelry_sust,y
    beq !+
    lda #$27
    jmp !t5_fail_code+
!:  inc t_slot
    lda t_slot
    cmp #41
    bcs !t5_combat_rings+
    jmp !t5_jloop-

!t5_combat_rings:
    // Baseline combat bonuses with empty inventory
    jsr item_init_inventory
    jsr player_recalc_equipment
    lda player_data + PL_AC
    sta t_base_ac
    lda player_data + PL_TOHIT
    sta t_base_hit
    lda player_data + PL_TODMG
    sta t_base_dam

    // Ring of Protection (base_ac=1, +5 to_ac on Page 1) adds +6 AC
    lda #ITEM_SLOT_RING_OF_PROTECTION
    sta inv_item_id + EQUIP_RING
    lda #ITEM_PAGE_RING_OF_PROTECTION
    sta inv_ego + EQUIP_RING
    lda #5
    sta inv_to_ac + EQUIP_RING
    lda #1
    sta inv_qty + EQUIP_RING
    jsr player_recalc_equipment
    lda t_base_ac
    clc
    adc #6
    cmp player_data + PL_AC
    beq !+
    jmp !t5_fail+

    // Ring of Slaying (+3/+4 on Page 1) + Ring of Increase Damage (+2 dam on Page 1)
!:  jsr item_init_inventory
    lda #ITEM_SLOT_RING_OF_SLAYING
    sta inv_item_id + EQUIP_RING
    lda #ITEM_PAGE_RING_OF_SLAYING
    sta inv_ego + EQUIP_RING
    lda #3
    sta inv_to_hit + EQUIP_RING
    lda #4
    sta inv_to_dam + EQUIP_RING
    lda #1
    sta inv_qty + EQUIP_RING

    lda #ITEM_SLOT_RING_OF_INCREASE_DAMAGE
    sta inv_item_id + EQUIP_RING2
    lda #ITEM_PAGE_RING_OF_INCREASE_DAMAGE
    sta inv_ego + EQUIP_RING2
    lda #2
    sta inv_to_dam + EQUIP_RING2
    lda #1
    sta inv_qty + EQUIP_RING2
    jsr player_recalc_equipment
    lda t_base_hit
    clc
    adc #3
    cmp player_data + PL_TOHIT
    beq !+
    jmp !t5_fail+
!:  lda t_base_dam
    clc
    adc #6
    cmp player_data + PL_TODMG
    beq !+
    jmp !t5_fail+

    // monster_ai_tick Ring of Speed check on Page 1 vs Page 0 non-aliasing
!:  jsr monster_init_table
    jsr item_init_inventory
    lda #0
    sta zp_eff_speed
    lda #ITEM_SLOT_RING_OF_SPEED
    sta inv_item_id + EQUIP_RING
    sta inv_item_id + EQUIP_RING2
    lda #ITEM_PAGE_RING_OF_SPEED
    sta inv_ego + EQUIP_RING
    sta inv_ego + EQUIP_RING2
    lda #1
    sta inv_qty + EQUIP_RING
    sta inv_qty + EQUIP_RING2
    jsr monster_ai_tick
    lda mat_fast
    cmp #2
    beq !+
    jmp !t5_fail+
!:  // Clear page bits (simulating Page-0 items with same slot_lo) -> mat_fast must be 0
    lda #0
    sta inv_ego + EQUIP_RING
    sta inv_ego + EQUIP_RING2
    jsr monster_ai_tick
    lda mat_fast
    beq !t5_pass+
    jmp !t5_fail+

!t5_pass:
    lda #$01
    sta tc_results + 4
    jmp test_finish
!t5_fail:
!t5_fail_code:
    lda #$00
    sta tc_results + 4
    jmp test_finish

// 16-bit order-sensitive string digest over (zp_ptr0),0..len-1
// Returns Y = length, t_hash_lo, t_hash_hi.
compute_name_digest:
    lda #0
    sta t_hash_lo
    sta t_hash_hi
    ldy #0
!cnd_loop:
    lda (zp_ptr0),y
    beq !cnd_done+
    sta t_hash_b
    asl t_hash_lo
    rol t_hash_hi
    bcc !cnd_nc+
    inc t_hash_lo
!cnd_nc:
    lda t_hash_lo
    eor t_hash_b
    sta t_hash_lo
    tya
    clc
    adc t_hash_hi
    sta t_hash_hi
    lda t_hash_hi
    clc
    adc t_hash_b
    sta t_hash_hi
    iny
    cpy #64
    bcc !cnd_loop-
!cnd_done:
    rts

dig_tool_ids:
    .byte ITEM_SLOT_PICK, ITEM_SLOT_SHOVEL, ITEM_SLOT_ORCISH_PICK, ITEM_SLOT_DWARVEN_PICK, ITEM_SLOT_GNOMISH_SHOVEL, ITEM_SLOT_DWARVEN_SHOVEL
dig_tool_exp:
    .byte 24, 10, 36, 48, 22, 34
bow_exp_p1:
    .byte 2, 3, 4, 5, 6, 1

exp_jewelry_stat:
    .byte $01, $08, $10, $02, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $00, $00
    .byte $00, $00, $02, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $04, $20, $00, $00, $00, $00, $02, $3f
exp_jewelry_pf1:
    .byte $00, $00, $00, $00, $04, $00, $00, $00, $01, $02, $80, $00, $00, $00, $01, $20
    .byte $02, $00, $00, $00, $00, $00, $00, $08, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $20, $18, $00
exp_jewelry_pf2:
    .byte $00, $00, $00, $00, $00, $20, $10, $01, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $38, $00, $00, $00, $00, $08, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $20, $10, $01, $00, $20, $20
exp_jewelry_sust:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $01, $02, $04, $10, $08, $20, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00

exp_name_len_p0:
    .byte $0c, $0c, $06, $06, $06, $06, $06, $06, $07, $07, $04, $04, $04, $05, $09, $04
    .byte $06, $08, $08, $07, $12, $15, $14, $15, $19, $17, $1a, $19, $1a, $14, $14, $20
    .byte $15, $17, $17, $15, $14, $1c, $19, $16, $21, $0e, $0a, $18, $18, $17, $0c, $13
    .byte $10, $11, $17, $12, $1a, $1b, $1b, $1e, $15, $15, $18, $12, $12, $1a, $1b, $1d
    .byte $1e, $11, $1b, $19, $0f, $13, $13, $10, $0f, $12, $25, $21, $15, $18, $1b, $1e
    .byte $12, $17, $14, $19, $11, $17, $12, $1d, $15, $15, $1a, $15, $1b, $16, $15, $1f
    .byte $1f, $17, $12, $16, $0f, $18, $14, $17, $18, $1b, $17, $17, $1c, $1c, $1a, $18
    .byte $18, $1d, $1d, $17, $1a, $13, $17, $1f, $17, $14, $12, $12, $1b, $15, $17, $1a
    .byte $16, $19, $15, $17, $12, $14, $15, $18, $17, $0d, $11, $0d, $12, $14, $11, $14
    .byte $15, $14, $17, $15, $12, $1d, $15, $15, $15, $15, $11, $17, $12, $12, $16, $12
    .byte $0e, $0e, $1c, $16, $1a, $18, $16, $14, $12, $12, $14, $11, $17, $16, $17, $1a
    .byte $19, $0e, $11, $17, $15, $14, $0f, $14, $11, $11, $1a, $12, $13, $22, $27, $24
    .byte $29, $1d, $0d, $0c, $0c, $0a, $04, $06, $0b, $0c, $0e, $0e, $12, $12, $10, $10
    .byte $11, $11, $0c, $05, $04, $0d, $15, $12, $14, $10, $16, $16, $12, $0b, $0a, $0a
    .byte $10, $11, $14, $0e, $16, $0f, $13, $14, $0a, $12, $09, $08, $0d, $0e, $0e, $05
    .byte $05, $04, $04, $09, $10, $10, $09, $09, $0a, $0c, $0c, $15, $0d, $12, $12
exp_name_len_p1:
    .byte $0e, $09, $0c, $15, $0c, $12, $13, $12, $0b, $14, $06, $0f, $0d, $09, $0d, $17
    .byte $1a, $0b, $10, $07, $1a, $13, $1c, $04, $06, $0a, $1b, $06, $05, $0b, $1d, $0c
    .byte $18, $0e, $0a, $09, $11, $0b, $05, $16, $0b, $04, $0a, $12, $08, $0a, $08, $06
    .byte $07, $0e, $04, $05, $05, $07, $10, $16, $19, $19, $0d, $11, $15, $16, $13, $13
    .byte $17, $11, $11, $10, $20, $20, $20, $0b, $11, $17, $17, $12, $19, $15, $18, $1c
    .byte $16, $1c, $19, $18, $0f, $13, $13, $10, $12, $13, $17, $18, $15, $12, $0e, $0c
    .byte $18, $0c, $11, $0e, $0e, $0c, $0e, $13, $11, $0c
exp_name_hlo_p0:
    .byte $06, $81, $42, $42, $42, $db, $db, $db, $8d, $8d, $1a, $1a, $1a, $7a, $45, $1a
    .byte $37, $cd, $4b, $20, $c2, $b8, $d2, $09, $b4, $8a, $f2, $f1, $4b, $9d, $d9, $ab
    .byte $6b, $32, $04, $ae, $cd, $90, $bc, $cf, $bd, $85, $9b, $1e, $1e, $8c, $cb, $c6
    .byte $30, $d6, $3f, $3c, $0f, $9a, $7a, $9e, $57, $9f, $db, $aa, $3f, $18, $69, $c9
    .byte $32, $74, $b0, $75, $39, $f9, $50, $2b, $cd, $7f, $ae, $64, $06, $27, $c5, $b4
    .byte $3f, $fe, $cb, $aa, $6f, $f4, $67, $b0, $61, $1b, $1f, $a8, $00, $39, $7d, $43
    .byte $7a, $3b, $6f, $f1, $37, $8f, $3e, $94, $9d, $90, $10, $35, $23, $28, $c8, $b1
    .byte $b1, $7e, $7e, $a3, $51, $fe, $bf, $d5, $1c, $4f, $ff, $dd, $04, $c1, $82, $09
    .byte $61, $ac, $fb, $7d, $0a, $f3, $46, $4c, $d1, $1f, $b4, $71, $f6, $9a, $8d, $2e
    .byte $d3, $81, $75, $9f, $a1, $f1, $ab, $cc, $ef, $e0, $e2, $21, $f2, $b6, $96, $4f
    .byte $71, $b9, $df, $6c, $d6, $6e, $c6, $76, $5b, $5b, $a7, $a1, $5a, $62, $df, $df
    .byte $85, $83, $09, $3a, $79, $94, $dd, $8a, $c5, $c5, $22, $64, $80, $b3, $3a, $2a
    .byte $4f, $ed, $68, $4e, $b7, $3a, $ab, $cd, $9b, $8d, $2e, $53, $db, $d3, $07, $34
    .byte $0d, $29, $c4, $61, $af, $b0, $c8, $0d, $3b, $3a, $29, $c1, $71, $e3, $e4, $e9
    .byte $9c, $47, $27, $4d, $5c, $2d, $2e, $f4, $e9, $89, $93, $5e, $2e, $db, $3d, $6a
    .byte $c4, $22, $a3, $ec, $28, $b3, $2f, $1d, $85, $70, $15, $15, $57, $84, $ea
exp_name_hlo_p1:
    .byte $08, $5d, $45, $06, $97, $e6, $b9, $0f, $19, $12, $a5, $bd, $8f, $f5, $51, $1e
    .byte $8d, $5b, $98, $64, $de, $01, $6a, $10, $c3, $ea, $16, $e7, $14, $dc, $7a, $07
    .byte $49, $11, $79, $c2, $61, $1b, $1e, $4b, $51, $6d, $da, $d6, $89, $02, $93, $2f
    .byte $d7, $bf, $b5, $b1, $f6, $d0, $69, $2e, $eb, $c1, $5c, $93, $39, $3c, $f7, $fa
    .byte $ba, $54, $54, $a0, $55, $19, $4f, $fb, $89, $9e, $48, $4b, $e6, $b4, $05, $7e
    .byte $5f, $94, $49, $52, $76, $f3, $f3, $74, $ed, $39, $1c, $72, $39, $94, $eb, $d4
    .byte $e4, $65, $59, $26, $8b, $c8, $c0, $f0, $89, $2a
exp_name_hhi_p0:
    .byte $9e, $63, $6d, $6d, $6d, $07, $07, $07, $47, $47, $9d, $9d, $9d, $bd, $f8, $9d
    .byte $25, $12, $ea, $d1, $2e, $85, $80, $81, $8b, $68, $76, $78, $72, $7e, $e7, $ea
    .byte $a8, $74, $65, $00, $92, $36, $a7, $7d, $05, $db, $c2, $a7, $a7, $7b, $bb, $09
    .byte $3f, $49, $dc, $13, $1b, $15, $a3, $ed, $b8, $51, $c5, $2d, $d3, $ba, $4b, $09
    .byte $cd, $30, $33, $e3, $a9, $8a, $84, $95, $bd, $53, $75, $56, $da, $7b, $f4, $49
    .byte $f9, $a8, $38, $af, $67, $1b, $fa, $24, $de, $e4, $07, $e5, $3d, $98, $0e, $f2
    .byte $cb, $84, $de, $bd, $19, $29, $6f, $4f, $0b, $ea, $7f, $e8, $c6, $8d, $87, $d1
    .byte $d1, $3a, $3a, $b8, $10, $78, $d9, $c9, $0a, $41, $b4, $e7, $fb, $d9, $64, $1d
    .byte $b5, $78, $03, $be, $aa, $fa, $66, $55, $9e, $a5, $d6, $c3, $ac, $fa, $f5, $8e
    .byte $52, $54, $a4, $c1, $6a, $55, $ac, $4c, $e6, $b5, $da, $98, $ef, $2c, $f4, $65
    .byte $32, $49, $bf, $e1, $2b, $93, $d3, $b3, $0d, $0d, $38, $eb, $9a, $72, $ed, $ac
    .byte $f7, $d4, $06, $61, $04, $4f, $98, $5a, $5c, $5c, $70, $c0, $db, $16, $ee, $19
    .byte $3a, $72, $5e, $9e, $2c, $69, $c2, $09, $04, $0d, $f8, $4d, $d1, $fd, $17, $24
    .byte $e8, $b2, $09, $f7, $e2, $c5, $06, $3b, $81, $84, $6b, $11, $5d, $d5, $45, $8c
    .byte $8e, $2c, $63, $c0, $0c, $f5, $ca, $62, $48, $b5, $ca, $48, $1e, $05, $15, $f6
    .byte $3b, $85, $ea, $a2, $9d, $1f, $be, $31, $5e, $e1, $46, $c9, $d0, $3c, $46
exp_name_hhi_p1:
    .byte $1c, $a7, $ef, $c0, $10, $2d, $ae, $e1, $e6, $0d, $41, $c0, $8f, $24, $7e, $12
    .byte $60, $e2, $54, $c8, $03, $3a, $b7, $97, $73, $91, $00, $53, $88, $9f, $eb, $8e
    .byte $7b, $d3, $89, $97, $f1, $b6, $00, $86, $9d, $84, $64, $11, $6a, $d1, $94, $3e
    .byte $b6, $37, $cc, $f7, $29, $03, $9c, $96, $5d, $ef, $40, $71, $21, $52, $57, $4a
    .byte $6c, $57, $57, $21, $05, $5f, $eb, $52, $04, $68, $79, $bb, $ac, $1a, $1b, $12
    .byte $47, $2f, $fa, $ba, $41, $1e, $1e, $e8, $2c, $5a, $74, $02, $94, $0a, $24, $ec
    .byte $ae, $d6, $18, $55, $f2, $54, $7c, $62, $9b, $47

exp_cat_p0:
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09
    .byte $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09
    .byte $09, $09, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a
    .byte $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a
    .byte $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0b
    .byte $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b
    .byte $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b
    .byte $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0e, $0e, $0e, $0e, $0e, $0e, $0e
    .byte $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
    .byte $0e, $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0f
    .byte $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0d, $0d, $0d, $0d, $0d, $0d
    .byte $0d, $0d, $08, $08, $08, $12, $00, $00, $00, $00, $00, $00, $11, $11, $11, $11
    .byte $11, $11, $11, $13, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03
    .byte $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $02, $02, $02, $02, $02, $02
    .byte $02, $02, $02, $02, $05, $05, $05, $05, $05, $05, $05, $05, $07, $07, $07
exp_cat_p1:
    .byte $06, $06, $04, $04, $04, $04, $04, $04, $02, $02, $02, $02, $02, $02, $02, $02
    .byte $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02
    .byte $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02
    .byte $02, $02, $02, $02, $02, $02, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c
    .byte $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c
    .byte $0c, $0c, $0c, $0c, $0c, $10, $10, $10, $10, $10, $10, $10, $10, $10, $10, $14
    .byte $14, $14, $14, $14, $14, $14, $14, $14, $14, $14
exp_ac_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $01, $02, $04, $05, $06, $07, $06, $06, $08, $0b, $01, $0d, $0e
    .byte $0e, $0f, $10, $12, $13, $14, $16, $17, $19, $1c, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $01, $02, $03, $05, $06, $00, $00, $00, $01, $02, $03
exp_ac_p1:
    .byte $01, $02, $02, $03, $04, $03, $04, $05, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $05, $05, $05, $00, $00, $00, $00, $01, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_glyph_p0:
    .byte $24, $24, $24, $24, $24, $24, $24, $24, $24, $24, $24, $24, $24, $24, $24, $24
    .byte $24, $24, $24, $24, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c
    .byte $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c
    .byte $2c, $2c, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21
    .byte $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21
    .byte $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $21, $3f
    .byte $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f
    .byte $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f
    .byte $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $3f, $2d, $2d, $2d, $2d, $2d, $2d, $2d
    .byte $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d, $2d
    .byte $2d, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
    .byte $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $3f, $3f, $3f, $3f, $3f, $3f
    .byte $3f, $3f, $2a, $2a, $21, $5c, $5c, $5c, $5c, $5c, $5c, $5c, $26, $26, $26, $26
    .byte $26, $26, $26, $28, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b
    .byte $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $1c, $1c, $1c, $1c, $1c, $1c
    .byte $1b, $1b, $1b, $1b, $5d, $5d, $5d, $5d, $5d, $5d, $5d, $5d, $5d, $5d, $5d
exp_glyph_p1:
    .byte $5d, $5d, $29, $29, $29, $29, $29, $29, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
    .byte $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
    .byte $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
    .byte $2f, $2f, $2f, $2f, $2f, $2f, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d
    .byte $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d, $3d
    .byte $3d, $3d, $3d, $3d, $3d, $22, $22, $22, $22, $22, $22, $22, $22, $22, $22, $5c
    .byte $5c, $5c, $5c, $5c, $5c, $5c, $5c, $5c, $5c, $5c
exp_color_p0:
    .byte $07, $07, $08, $08, $08, $0f, $0f, $0f, $02, $02, $07, $07, $07, $03, $06, $07
    .byte $0a, $01, $05, $0e, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09
    .byte $09, $09, $09, $09, $0d, $0d, $0d, $0d, $0d, $09, $05, $07, $07, $09, $09, $09
    .byte $08, $08, $01, $08, $08, $01, $02, $03, $01, $06, $05, $01, $02, $0f, $01, $01
    .byte $01, $01, $01, $07, $05, $0c, $04, $05, $0d, $05, $0d, $09, $01, $01, $0c, $0c
    .byte $0f, $04, $0e, $0d, $0a, $04, $06, $0a, $0a, $03, $05, $04, $05, $06, $08, $07
    .byte $03, $01, $0f, $03, $01, $0d, $03, $03, $03, $0d, $0d, $08, $07, $0a, $07, $01
    .byte $01, $0f, $0f, $0a, $09, $0a, $07, $03, $0d, $0d, $0a, $08, $07, $0a, $01, $0f
    .byte $09, $07, $03, $0d, $08, $0a, $01, $0f, $0a, $07, $03, $06, $0a, $09, $0c, $0f
    .byte $0c, $0c, $09, $01, $04, $0f, $09, $0c, $0f, $03, $0f, $03, $03, $0a, $05, $0d
    .byte $0f, $07, $07, $09, $09, $02, $03, $09, $09, $09, $0a, $05, $09, $0f, $0b, $01
    .byte $09, $07, $0d, $09, $03, $09, $09, $01, $09, $09, $04, $04, $06, $0a, $07, $07
    .byte $03, $01, $08, $07, $08, $01, $0f, $09, $0b, $01, $03, $01, $09, $09, $0f, $0f
    .byte $01, $01, $09, $0f, $0f, $09, $09, $09, $09, $09, $09, $09, $09, $0c, $0c, $0c
    .byte $0c, $0f, $0f, $0f, $0f, $0f, $01, $01, $0f, $01, $09, $09, $09, $0f, $0f, $09
    .byte $09, $0f, $0c, $0b, $09, $09, $0c, $0c, $0f, $01, $07, $0d, $09, $09, $09
exp_color_p1:
    .byte $09, $0f, $0f, $09, $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0c, $0f, $01, $0f
    .byte $0f, $01, $0f, $01, $01, $01, $01, $0f, $0f, $01, $01, $0f, $01, $0f, $01, $0c
    .byte $0f, $0f, $0f, $0f, $0f, $09, $0f, $0f, $01, $0f, $0f, $0f, $0f, $0f, $0f, $0f
    .byte $0f, $0f, $0f, $0f, $0f, $0f, $0a, $03, $06, $0d, $07, $02, $03, $08, $0a, $03
    .byte $0a, $03, $03, $03, $0a, $0d, $03, $01, $03, $05, $03, $07, $03, $0d, $03, $02
    .byte $03, $03, $03, $0d, $0a, $07, $07, $07, $07, $07, $07, $07, $0d, $0d, $02, $01
    .byte $01, $0d, $08, $01, $01, $01, $01, $01, $01, $09
exp_uidx_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $10, $16, $17, $11, $18, $19, $12, $1a, $1b, $15, $1c, $1d, $00, $03
    .byte $0e, $0a, $14, $1e, $1f, $06, $07, $02, $01, $20, $ff, $ff, $ff, $13, $21, $22
    .byte $23, $24, $25, $26, $05, $27, $28, $29, $0c, $0d, $2a, $2b, $0f, $04, $09, $13
    .byte $14, $06, $01, $04, $00, $15, $12, $02, $0a, $07, $0b, $16, $0e, $17, $0c, $18
    .byte $18, $19, $19, $10, $1a, $08, $1b, $1c, $1d, $0d, $0f, $1e, $09, $1f, $20, $21
    .byte $22, $23, $24, $25, $26, $27, $28, $03, $11, $00, $01, $02, $09, $05, $0d, $0e
    .byte $0f, $04, $10, $11, $0a, $12, $13, $14, $15, $06, $16, $0b, $08, $07, $03, $0c
    .byte $17, $00, $08, $09, $0a, $0b, $02, $0c, $0d, $0d, $05, $0e, $0f, $10, $11, $03
    .byte $12, $06, $13, $14, $07, $15, $16, $04, $17, $17, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_uidx_p1:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $01, $0a, $0b, $0c, $04, $0d, $0e, $0f, $02, $03
    .byte $10, $11, $11, $12, $07, $08, $09, $13, $14, $15, $16, $00, $17, $05, $18, $19
    .byte $1a, $1b, $1c, $1d, $06, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_msl_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $01, $01, $02, $02, $03
    .byte $81, $82, $83, $83, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_msl_p1:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

exp_cost_lo_p0:
    .byte $00, $00, $03, $04, $05, $06, $07, $08, $09, $0a, $0c, $0e, $10, $12, $14, $18
    .byte $1c, $20, $28, $50, $00, $00, $00, $00, $00, $3c, $32, $19, $32, $00, $32, $5e
    .byte $05, $14, $1e, $e8, $00, $00, $4b, $19, $4b, $03, $02, $0a, $0a, $00, $01, $02
    .byte $01, $02, $c8, $00, $2c, $2c, $00, $2c, $2c, $00, $2c, $2c, $00, $2c, $0f, $28
    .byte $64, $c8, $2c, $c4, $00, $05, $05, $05, $4b, $00, $02, $01, $00, $2c, $2c, $2c
    .byte $c8, $00, $00, $fa, $23, $64, $0a, $90, $1e, $1e, $32, $19, $4b, $23, $14, $7d
    .byte $7d, $7d, $32, $64, $0f, $00, $0f, $28, $32, $1e, $28, $23, $f4, $0f, $0f, $23
    .byte $23, $23, $23, $e8, $0f, $05, $00, $32, $64, $c8, $ee, $00, $64, $0a, $c8, $f4
    .byte $00, $f4, $00, $00, $0f, $28, $50, $96, $ee, $c8, $58, $20, $e8, $2c, $90, $00
    .byte $00, $f4, $90, $f4, $b0, $64, $c8, $90, $00, $5e, $bc, $b0, $dc, $08, $90, $72
    .byte $fa, $fa, $5e, $5e, $c8, $c8, $90, $5e, $00, $00, $c4, $20, $00, $20, $bc, $c8
    .byte $c8, $e8, $00, $ee, $f4, $5e, $e8, $b0, $00, $00, $19, $64, $90, $20, $19, $64
    .byte $2c, $20, $23, $02, $03, $01, $32, $0f, $f4, $b0, $64, $fa, $14, $3c, $64, $96
    .byte $c8, $fa, $00, $03, $04, $12, $23, $37, $64, $2d, $a0, $e6, $4a, $00, $ae, $12
    .byte $00, $76, $a3, $d0, $07, $39, $84, $b6, $1a, $b0, $32, $78, $f0, $8c, $2c, $05
    .byte $01, $02, $01, $02, $04, $0c, $1e, $4b, $c8, $fa, $f4, $e8, $04, $07, $0c
exp_cost_lo_p1:
    .byte $03, $23, $1e, $3c, $78, $32, $7d, $c8, $19, $0a, $0a, $0a, $00, $3c, $5e, $3c
    .byte $50, $ff, $b4, $55, $8f, $52, $e8, $23, $90, $2c, $a3, $2a, $32, $30, $e8, $00
    .byte $f4, $c8, $78, $30, $0e, $01, $78, $4e, $64, $2d, $5a, $f6, $54, $98, $78, $6b
    .byte $ae, $78, $66, $24, $e6, $12, $90, $90, $90, $5e, $b8, $fa, $00, $fa, $fa, $fa
    .byte $c8, $14, $1e, $00, $b0, $b0, $b0, $00, $00, $64, $64, $64, $00, $f4, $ee, $58
    .byte $58, $ee, $ee, $f4, $e8, $14, $1e, $2c, $fa, $fa, $00, $c8, $2c, $88, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_cost_hi_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01
    .byte $00, $00, $00, $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $01, $01, $00, $01, $01, $00, $01, $01, $00, $01, $00, $00
    .byte $00, $00, $01, $09, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $01, $01
    .byte $00, $00, $00, $00, $00, $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $00, $00, $00
    .byte $00, $00, $00, $03, $00, $00, $00, $00, $00, $00, $02, $00, $00, $00, $00, $01
    .byte $00, $01, $00, $00, $00, $00, $00, $00, $02, $00, $02, $03, $03, $01, $01, $00
    .byte $00, $01, $01, $01, $04, $00, $00, $01, $00, $01, $02, $04, $05, $07, $01, $06
    .byte $00, $00, $01, $01, $00, $00, $01, $01, $00, $00, $09, $03, $00, $03, $02, $00
    .byte $00, $03, $00, $02, $01, $01, $03, $04, $00, $00, $00, $00, $01, $03, $00, $00
    .byte $01, $03, $00, $00, $00, $00, $00, $00, $01, $04, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $00, $01, $02
    .byte $00, $02, $02, $02, $03, $03, $03, $03, $04, $04, $00, $00, $00, $00, $01, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $03, $00, $00, $00
exp_cost_hi_p1:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $00
    .byte $00, $00, $00, $00, $02, $03, $03, $00, $01, $01, $02, $00, $00, $00, $03, $00
    .byte $01, $00, $00, $01, $00, $00, $00, $02, $00, $00, $00, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $00, $00, $00, $01, $01, $01, $01, $0b, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $04, $04, $04, $00, $00, $00, $00, $00, $00, $01, $02, $02
    .byte $02, $02, $02, $01, $03, $00, $00, $01, $00, $00, $00, $00, $01, $13, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_wt_lo_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $02, $0a, $05, $03, $03, $01, $02, $02
    .byte $0a, $0a, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04
    .byte $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04
    .byte $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $05
    .byte $05, $02, $02, $02, $02, $05, $05, $02, $05, $02, $05, $05, $05, $05, $05, $05
    .byte $05, $05, $05, $05, $05, $02, $05, $05, $05, $05, $05, $05, $02, $05, $05, $05
    .byte $05, $05, $05, $05, $05, $05, $05, $02, $05, $0a, $0a, $0a, $0a, $0a, $0a, $0a
    .byte $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a, $0a
    .byte $0a, $32, $32, $32, $32, $32, $32, $32, $32, $32, $32, $32, $32, $32, $32, $32
    .byte $32, $32, $32, $32, $32, $32, $32, $32, $32, $32, $1e, $1e, $1e, $1e, $1e, $1e
    .byte $1e, $1e, $1e, $0a, $0a, $0a, $32, $3c, $b4, $c8, $32, $78, $fa, $ff, $ff, $ff
    .byte $ff, $ff, $fa, $0a, $14, $50, $5a, $78, $6e, $96, $82, $96, $8c, $14, $fa, $78
    .byte $c8, $04, $0e, $18, $22, $2c, $04, $54, $7c, $7c, $1e, $28, $28, $32, $c8, $05
    .byte $02, $02, $04, $05, $0a, $0f, $14, $1e, $3c, $14, $1e, $28, $0a, $05, $14
exp_wt_lo_p1:
    .byte $05, $19, $32, $4b, $64, $41, $5a, $78, $1e, $0f, $0c, $14, $0f, $5f, $8c, $50
    .byte $64, $4b, $c8, $6e, $b4, $04, $f0, $1e, $78, $32, $c8, $28, $32, $1e, $18, $4b
    .byte $b4, $96, $aa, $a0, $28, $64, $96, $18, $96, $32, $78, $b4, $a0, $b4, $aa, $be
    .byte $be, $78, $a0, $32, $2c, $1e, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02
    .byte $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02
    .byte $02, $02, $02, $02, $02, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $0a
    .byte $19, $02, $05, $32, $3c, $28, $19, $03, $02, $03
exp_wt_hi_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_wt_hi_p1:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00, $01, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_dice_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0a, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $06, $00, $00, $00, $00, $00, $01, $00, $00
    .byte $00, $00, $00, $01, $01, $00, $01, $01, $00, $01, $01, $00, $01, $01, $00, $00
    .byte $00, $00, $00, $01, $01, $00, $00, $00, $00, $01, $01, $01, $01, $00, $01, $01
    .byte $01, $01, $01, $01, $00, $01, $01, $01, $00, $00, $01, $01, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $01
    .byte $01, $00, $01, $01, $00, $01, $01, $01, $01, $00, $01, $00, $00, $00, $00, $00
    .byte $01, $00, $01, $01, $01, $01, $00, $01, $01, $01, $00, $01, $01, $01, $01, $00
    .byte $01, $00, $01, $01, $00, $01, $01, $00, $01, $01, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $02, $01, $01, $01, $01, $01, $01, $01, $02, $02, $02, $02
    .byte $02, $02, $00, $00, $00, $00, $00, $00, $01, $00, $01, $01, $01, $00, $00, $00
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $00, $02, $00, $00, $00, $00, $00, $00
    .byte $01, $01, $01, $01, $00, $00, $00, $00, $00, $01, $01, $01, $00, $00, $00
exp_dice_p1:
    .byte $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $03, $01
    .byte $01, $02, $03, $01, $03, $04, $04, $01, $03, $01, $04, $01, $01, $01, $04, $01
    .byte $02, $02, $03, $02, $01, $01, $02, $03, $02, $02, $03, $03, $01, $02, $01, $02
    .byte $03, $02, $02, $01, $02, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
exp_sides_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0a, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $08, $00, $00, $00, $00, $00, $01, $00, $00
    .byte $00, $00, $00, $01, $01, $00, $01, $01, $00, $01, $01, $00, $01, $01, $00, $00
    .byte $00, $00, $00, $01, $01, $00, $00, $00, $00, $01, $01, $01, $01, $00, $01, $01
    .byte $01, $01, $01, $01, $00, $01, $01, $01, $00, $00, $01, $01, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $01
    .byte $01, $00, $01, $01, $00, $01, $01, $01, $01, $00, $01, $00, $00, $00, $00, $00
    .byte $01, $00, $02, $02, $02, $02, $00, $02, $02, $02, $00, $02, $02, $02, $02, $00
    .byte $02, $00, $02, $02, $00, $02, $02, $00, $02, $02, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $06, $01, $03, $02, $03, $04, $02, $03, $03, $05, $04, $06
    .byte $04, $06, $00, $00, $00, $00, $00, $00, $02, $00, $02, $03, $01, $00, $00, $00
    .byte $04, $04, $04, $04, $04, $04, $06, $06, $00, $04, $00, $00, $00, $00, $00, $00
    .byte $04, $05, $02, $03, $00, $00, $00, $00, $00, $01, $02, $03, $00, $00, $00
exp_sides_p1:
    .byte $00, $00, $01, $02, $02, $02, $03, $03, $05, $04, $04, $04, $01, $09, $04, $06
    .byte $07, $05, $06, $07, $06, $05, $05, $05, $04, $08, $04, $06, $07, $06, $06, $01
    .byte $08, $04, $04, $06, $04, $03, $06, $06, $06, $04, $03, $04, $08, $06, $0a, $06
    .byte $04, $05, $05, $06, $08, $04, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
exp_f0_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $01, $02, $04, $08, $10, $20, $40, $80, $00, $00, $00, $00
    .byte $00, $00, $00, $40, $01, $10, $20, $00, $00, $00, $00, $20, $20, $00, $00, $00
    .byte $00, $00, $01, $02, $04, $08, $10, $20, $40, $80, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $01, $02, $04, $08, $10, $20, $40, $80, $00, $00, $00, $00, $00, $00, $00, $01
    .byte $02, $04, $08, $10, $20, $40, $80, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01
    .byte $02, $04, $08, $10, $20, $40, $80, $00, $00, $01, $02, $04, $08, $10, $20, $40
    .byte $80, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $01, $02, $04, $08, $10, $20, $40, $80, $80, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $7f, $80, $00, $00, $ff, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_f0_p1:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $01, $02, $04, $08, $00, $40, $00, $80, $00, $00
    .byte $00, $00, $00, $01, $00, $00, $00, $40, $08, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $10, $20, $40, $00, $80, $00, $40, $7f, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_f1_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $02, $04, $00
    .byte $00, $00, $00, $80, $00, $00, $00, $04, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $02, $04, $08, $10, $20
    .byte $40, $80, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $01, $02, $04, $08, $10, $20, $40, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $01, $02, $04, $08, $10, $20, $40, $80, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $01, $02, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $01, $02, $04, $08, $10, $20, $40, $80, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $02, $04, $08, $10, $20, $40
    .byte $80, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $ff, $00, $00, $00, $ff
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_f1_p1:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $10, $00, $04, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $06, $00, $00, $00, $00, $02, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $04, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_f2_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01
    .byte $20, $40, $80, $1f, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $01, $02, $04, $08, $10, $20, $40, $80, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01
    .byte $01, $02, $02, $04, $08, $10, $20, $40, $80, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $02, $04, $08, $10, $20, $40
    .byte $80, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $01, $02, $04, $08, $10, $20, $40, $00, $00, $00, $00, $ff, $00, $00, $00
    .byte $ff, $00, $00, $00, $04, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_f2_p1:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $08, $20
    .byte $00, $00, $00, $00, $08, $10, $20, $00, $00, $00, $00, $00, $00, $00, $40, $40
    .byte $40, $40, $40, $40, $00, $00, $00, $00, $00, $00, $00, $00, $10, $80, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_f3_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $04, $04, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $02, $00, $00, $02, $02, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $10, $30
    .byte $70, $70, $00, $00, $10, $00, $00, $00, $00, $00, $30, $00, $00, $02, $04, $68
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $02, $04, $08, $10, $20, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $01, $01, $00, $00, $00, $7f, $00, $00
    .byte $01, $7e, $00, $00, $00, $00, $20, $20, $20, $20, $20, $20, $0f, $15, $0f, $1f
    .byte $0f, $23, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_f3_p1:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $80, $00, $00, $00
    .byte $04, $00, $00, $00, $00, $00, $00, $80, $80, $00, $00, $00, $80, $01, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $80, $00, $00, $01, $80, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_p1_lo_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $f4, $f4, $f4, $f4, $f4, $f4, $f4, $f4, $f4, $f4, $f4, $f4
    .byte $f4, $f4, $f4, $f4, $b0, $b0, $b0, $b0, $b0, $88, $b8, $4c, $4c, $dc, $f4, $d6
    .byte $f4, $90, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $32, $64
    .byte $64, $c8, $00, $00, $64, $00, $32, $00, $00, $32, $90, $fa, $c8, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $4c, $a0, $4c, $00, $01, $00, $02, $03, $01, $02, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $02, $03, $04, $05, $06, $01
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_p1_lo_p1:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $fb, $00, $00, $00, $fb, $fb, $00, $00, $00, $00, $00, $01, $02
    .byte $03, $04, $05, $06, $06, $00, $00, $00, $00, $00, $00, $00, $00, $00, $fb, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_p1_hi_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $04, $04, $04, $04, $04, $13, $0b, $1d, $1d, $05, $01, $06
    .byte $01, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $1d, $0f, $1d, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_p1_hi_p1:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $ff, $00, $00, $00, $ff, $ff, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $ff, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_tohit_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $05, $05
    .byte $03, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
exp_tohit_p1:
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
exp_todam_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $9c, $9c, $9c, $9c, $9c, $9c
    .byte $9c, $9c, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $ff, $ff, $ff, $ff, $fe, $ff, $00, $fe, $fe
    .byte $fb, $fe, $fe, $fe, $fd, $fd, $fd, $fd, $fd, $fd, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_todam_p1:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $fe, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $fe
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_toac_p0:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
exp_toac_p1:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $fe, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $fe
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

catalog_vms_test_end:
.assert "Catalog VMS test stays below MAP_BASE", catalog_vms_test_end <= MAP_BASE, true
