// test_item_effects_vms.s — End-to-end C64 runtime verification of VMS Moria 4.8
// consumable and device effects across all 166 active IDs (20..185 on Page 0):
//   Test 1 ($0400): All 30 Foods & Mushrooms/Molds (20..49) via production item_eat
//   Test 2 ($0401): All 6 non-contiguous Gain-Stat (#50,#53,#56,#59,#66,#77),
//                   4 Lose-Stat (#51,#54,#57,#60), & 6 Restore-Stat (#52,#55,#58,#61,#78,#79)
//                   Potions via production item_quaff
//   Test 3 ($0402): Remaining 29 VMS Potions in 50..94 (heals + piq_quaff_identify,
//                   XP/mana, timed buffs/cures, Sleep + Free Action, drinks) via item_quaff
//   Test 4 ($0403): All 42 VMS Scrolls (95..136) via production item_read_scroll
//   Test 5 ($0404): All 24 VMS Wands (137..160) via item_aim_wand &
//                   all 25 VMS Staves (161..185) via item_use_staff
//
// Results at $0400-$0404: $01 = pass, $00 = fail per test (5 tests)

#define C64_TEST_NAME_STREAMS_A000

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

.segmentdef TestCreateOverlay [start=$D100, min=$D100, max=$FFF9]
.segmentdef TestUnused2 [start=$D500, min=$D500, max=$FFF9]
.segmentdef TestUnused3 [start=$D900, min=$D900, max=$FFF9]
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
#import "../../../../core/6502/ui_help_clear.s"
#import "../../../../core/6502/ui_trampoline_stubs.s"
.segment TestCreateOverlay
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
.segment TestUnused2
#import "../../../../core/6502/monster_ai.s"
.segment Default
#import "../../../../core/6502/recall.s"
#import "../../../../core/6502/monster_magic.s"
#define ITEM_SPAWN_EXTERNAL
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../../../../core/6502/item.s"
#undef ITEM_SPAWN_EXTERNAL
#import "item_cat_resident_helper.s"
.segment TestUnused2
#import "../../../../core/6502/special_rooms.s"
.segment Default
#import "../../../../core/6502/ego_items.s"
#import "../../../../core/6502/special_rooms_stubs.s"
#define SCROLL_P3_ROUTER_ENABLED
#import "../../../../core/6502/player_items.s"
#import "../../../../core/6502/spell_data.s"
#import "../../../../core/6502/projectile.s"
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../../core/6502/spell_effects.s"
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../../../core/6502/player_magic_state.s"
#import "../../../../core/6502/player_magic_state_ops.s"
#import "../../../../core/6502/player_magic.s"
#import "../../../../core/6502/dungeon_los.s"
#import "../../../../core/6502/los_trace.s"
.segment TestUnused3
#import "../../../../core/6502/player_move.s"
.segment Default
#import "../../../../core/6502/combat.s"
#import "../../../../core/6502/scene_mat_tile.s"
.segment TestUnused3
#import "../../../../core/6502/monster_attack.s"
.segment TestCreateOverlay
#import "../dungeon_render.s"
.segment Default
#import "../../../../core/6502/turn.s"

// Spy stubs for spell/death-overlay-hosted targets reached by scroll_effects_p3.s
spy_kind:   .byte 0
spy_arg:    .byte 0
spy_arg2:   .byte 0
tpm_huff_calls:   .byte 0
tpm_last_huff_id: .byte 0
tpm_msg_calls:    .byte 0

eff_recharge_item:
    sta spy_arg
    lda #1
    sta spy_kind
    rts
eff_earthquake:
    lda #2
    sta spy_kind
    rts
chest_mark_found_all:
    rts
eff_glyph_of_warding:
    lda #3
    sta spy_kind
    rts
eff_genocide:
    lda #4
    sta spy_kind
    rts
eff_destroy_area:
    lda #5
    sta spy_kind
    rts
eff_slow_monster_dir:
    lda #6
    sta spy_kind
    rts
eff_teleport_other:
    lda #7
    sta spy_kind
    rts
eff_staff_speed:
    lda #8
    sta spy_kind
    rts
eff_ball:
    sta spy_arg
    lda #9
    sta spy_kind
    rts
ped_s28:
    lda #10
    sta spy_kind
    rts
eff_reveal_floorplan:
    lda #11
    sta spy_kind
    rts
pmx_print_inline:
    inc tpm_msg_calls
    rts

irs_p3_swap_exec:
    jsr irs_dispatch_p3_overlay
    sec
    rts

#define SCROLL_P3_EXISTING_OWNER
#define SCROLL_P3_NEW_OWNER
#define SCROLL_P3_ROUTER_ENABLED
#import "../../../../core/6502/scroll_effects_p3.s"
#undef SCROLL_P3_NEW_OWNER
#undef SCROLL_P3_EXISTING_OWNER

#define SCROLL_P3_ROUTER_ENABLED
#import "../../../../core/6502/item_actions_overlay.s"

ui_char_display:
put_stat_val:
status_draw:
status_mark_dirty:
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

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

spy_huff_print_msg:
    stx tpm_last_huff_id
    inc tpm_huff_calls
    rts

spy_msg_print:
    inc tpm_msg_calls
    rts

spy_eff_bolt:
    sta spy_arg
    stx spy_arg2
    lda #12
    sta spy_kind
    rts

spy_dir_east:
    lda zp_player_x
    clc
    adc #1
    sta df_target_x
    lda zp_player_y
    sta df_target_y
    sec
    rts

spy_nop_rts:
    rts

spy_pick_creature:
    lda #1
    rts

tc_results: .fill 5, $ff
t_id:       .byte 0
t_carry:    .byte 0
t_idx:      .byte 0

// Setup a small lit room around (10, 10) for directional/area/floor effects
init_test_arena:
    jsr item_init_floor
    jsr monster_init_table
    lda #1
    sta room_count
    lda #8
    sta room_x
    sta room_y
    lda #6
    sta room_w
    sta room_h
    ldx #7
!ita_row:
    jsr map_row_ptr0_x
    ldy #7
!ita_col:
    lda #(TILE_FLOOR | FLAG_LIT)
    sta (zp_ptr0),y
    iny
    cpy #15
    bcc !ita_col-
    inx
    cpx #15
    bcc !ita_row-
    lda #10
    sta zp_player_x
    sta zp_player_y
    lda #5
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    sta player_data + PL_MAX_DLVL
    rts

reset_player_baseline:
    jsr item_init_inventory
    lda #0
    ldx #(zp_eff_see_inv - zp_eff_poison)
!rpb_eff:
    sta zp_eff_poison,x
    dex
    bpl !rpb_eff-
    sta eff_fear_timer
    sta eff_invuln_timer
    sta eff_detect_timer
    sta player_pflags
    sta player_pflags2
    sta zp_msg_flags
    sta spy_kind
    sta spy_arg
    sta spy_arg2
    sta tpm_huff_calls
    sta tpm_msg_calls
    lda #$ff
    sta tpm_last_huff_id

    lda #100
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #200
    sta zp_player_mhp_lo
    sta player_data + PL_MHP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI
    sta zp_player_mhp_hi
    sta player_data + PL_MHP_HI

    lda #<1000
    sta zp_player_food
    sta player_data + PL_FOOD_LO
    lda #>1000
    sta zp_player_food_hi
    sta player_data + PL_FOOD_HI

    lda #5
    sta zp_player_mp
    sta player_data + PL_MANA
    lda #20
    sta zp_player_mmp
    sta player_data + PL_MAX_MANA

    lda #100
    sta player_data + PL_XP_0
    lda #0
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2

    ldx #0
!rpb_stats:
    lda #0
    sta player_stat_res,x
    lda #12
    sta player_data + PL_STR_BASE,x
    sta player_data + PL_STR_CUR,x
    sta zp_player_str,x
    inx
    cpx #6
    bcc !rpb_stats-
    rts

stuff_slot_a_keys:
    lda #3
    sta $c6
    lda #$41                    // 'A' = slot 0
    sta $0277
    lda #$41                    // 'A' = shifted slot 0 (used if Identify scroll prompts after consuming slot 0)
    sta $0278
    lda #$20
    sta $0279
    rts

run_eat_a:
    sta t_id
    jsr reset_player_baseline
    lda t_id
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #0
    sta inv_ego + 0
    jsr stuff_slot_a_keys
    jsr item_eat
    lda #0
    rol
    sta t_carry
    rts

run_quaff_a:
    sta t_id
    jsr reset_player_baseline
    lda t_id
run_quaff_keep_a:
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #0
    sta inv_ego + 0
    sta zp_msg_flags
    jsr stuff_slot_a_keys
    jsr item_quaff
    lda #0
    rol
    sta t_carry
    rts

test_start:
    jsr screen_clear
    jsr msg_init

    lda #$42
    sta zp_rng_0
    lda #$13
    sta zp_rng_1
    lda #$7a
    sta zp_rng_2
    lda #$05
    sta zp_rng_3

    :PatchJump(huff_print_msg, spy_huff_print_msg)
    :PatchJump(msg_print, spy_msg_print)
    :PatchJump(eff_bolt, spy_eff_bolt)
    :PatchJump(get_direction_target, spy_dir_east)
    :PatchJump(tier_check_transition, spy_nop_rts)
    :PatchJump(pick_creature_type, spy_pick_creature)
    // The summon entry sits just before pick_creature_type and runs into it
    // (lda #2 / BIT abs): spy it too, or the summons run the patched bytes.
    :PatchJump(pick_summon_creature_type, spy_pick_creature)

    lda #2
    sta active_dungeon_count
    lda #1
    sta cr_level + 1
    lda #CF_UNDEAD
    sta cr_mflags + 1
    lda #20
    sta cr_hd_num + 1
    lda #1
    sta cr_hd_sides + 1

    jsr init_test_arena
    jsr item_init_identification

    // =========================================================================
    // Test 1: All 30 VMS Foods & Mushrooms/Molds (20..49) via item_eat
    // =========================================================================
    // 1A: Loop all 30 foods (20..49) -> every ID consumes 1 item and sets C=1
    lda #ITEM_SLOT_MUSHROOM_OF_POISON
    sta t_id
!t1_all_eat:
    lda t_id
    jsr run_eat_a
    lda t_carry
    bne !+
    jmp !t1_fail+
!:  lda inv_item_id + 0
    cmp #FI_EMPTY
    beq !+
    jmp !t1_fail+
!:  inc t_id
    lda t_id
    cmp #(ITEM_SLOT_PINT_OF_FINE_WINE + 1)
    bcc !t1_all_eat-

    // 1B: Spot-verify key VMS mushroom/mold/Waybread effects across 20..44
    // #20 Mushroom of Poison & #36 Hairy Mold of Poison -> zp_eff_poison > 0
    lda #ITEM_SLOT_MUSHROOM_OF_POISON
    jsr run_eat_a
    lda zp_eff_poison
    bne !+
    jmp !t1_fail+
!:  lda #ITEM_SLOT_HAIRY_MOLD_OF_POISON
    jsr run_eat_a
    lda zp_eff_poison
    bne !+
    jmp !t1_fail+

    // #21 Blindness -> zp_eff_blind, #22 Paranoia -> eff_fear_timer, #23 Confusion -> zp_eff_confuse
!:  lda #ITEM_SLOT_MUSHROOM_OF_BLINDNESS
    jsr run_eat_a
    lda zp_eff_blind
    bne !+
    jmp !t1_fail+
!:  lda #ITEM_SLOT_MUSHROOM_OF_PARANOIA
    jsr run_eat_a
    lda eff_fear_timer
    bne !+
    jmp !t1_fail+
!:  lda #ITEM_SLOT_MUSHROOM_OF_CONFUSION
    jsr run_eat_a
    lda zp_eff_confuse
    bne !+
    jmp !t1_fail+

    // #29 Weakness drains STR (< 12), #30 Unhealth drains CON (< 12)
!:  lda #ITEM_SLOT_MUSHROOM_OF_WEAKNESS
    jsr run_eat_a
    lda player_data + PL_STR_CUR
    cmp #12
    bcc !+
    jmp !t1_fail+
!:  lda #ITEM_SLOT_MUSHROOM_OF_UNHEALTH
    jsr run_eat_a
    lda player_data + PL_CON_CUR
    cmp #12
    bcc !+
    jmp !t1_fail+

    // #35 Mushroom of Restoring restores all 6 drained stats (8 -> 12)
!:  jsr reset_player_baseline
    lda #8
    ldx #0
!t1_drain6:
    sta player_data + PL_STR_CUR,x
    sta zp_player_str,x
    inx
    cpx #6
    bcc !t1_drain6-
    lda #ITEM_SLOT_MUSHROOM_OF_RESTORING
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_eat
    ldx #0
!t1_chk6:
    lda player_data + PL_STR_CUR,x
    cmp #12
    beq !+
    jmp !t1_fail+
!:  inx
    cpx #6
    bcc !t1_chk6-

    // #43 & #44 Elvish Waybread saturate food to FOOD_MAX (4000) and heal HP
    lda #ITEM_SLOT_PIECE_OF_ELVISH_WAYBREAD_L6
    jsr run_eat_a
    lda zp_player_food
    cmp #FOOD_MAX_LO
    beq !+
    jmp !t1_fail+
!:  lda zp_player_food_hi
    cmp #FOOD_MAX_HI
    beq !+
    jmp !t1_fail+
!:  lda zp_player_hp_lo
    cmp #101
    bcs !+
    jmp !t1_fail+
!:  lda #ITEM_SLOT_PIECE_OF_ELVISH_WAYBREAD_L20
    jsr run_eat_a
    lda zp_player_food
    cmp #FOOD_MAX_LO
    beq !+
    jmp !t1_fail+
!:  lda zp_player_hp_lo
    cmp #101
    bcs !t1_pass+
    jmp !t1_fail+

!t1_pass:
    lda #$01
    sta tc_results + 0
    jmp !t2_start+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // =========================================================================
    // Test 2: All 6 Non-Contiguous Gain-Stat, 4 Lose-Stat & 6 Restore-Stat
    // Potions via production item_quaff
    // =========================================================================
!t2_start:
    // 2A: 6 non-contiguous Gain-Stat potions (#50,#53,#56,#59,#66,#77)
    // Verify each raises ONLY its exact stat (12 -> 13) and leaves other 5 at 12!
    ldy #0
!t2_gain_loop:
    sty t_idx
    lda gain_pot_ids,y
    jsr run_quaff_a
    lda t_carry
    bne !+
    jmp !t2_fail+
!:  ldy t_idx
    ldx #0
!t2_gain_chk:
    txa
    cmp gain_pot_stat_idx,y
    beq !t2_gain_expect13+
    lda player_data + PL_STR_BASE,x
    cmp #12
    beq !t2_gain_next_s+
    jmp !t2_fail+
!t2_gain_expect13:
    lda player_data + PL_STR_BASE,x
    cmp #13
    beq !+
    jmp !t2_fail+
!:  lda player_data + PL_STR_CUR,x
    cmp #13
    beq !t2_gain_next_s+
    jmp !t2_fail+
!t2_gain_next_s:
    inx
    cpx #6
    bcc !t2_gain_chk-
    iny
    cpy #6
    bcc !t2_gain_loop-

    // 2B: 4 Lose-Stat potions (#51 STR, #54 INT, #57 WIS, #60 CHR) -> target 11, others 12
    ldy #0
!t2_lose_loop:
    sty t_idx
    lda lose_pot_ids,y
    jsr run_quaff_a
    ldy t_idx
    ldx #0
!t2_lose_chk:
    txa
    cmp lose_pot_stat_idx,y
    beq !t2_lose_expect11+
    lda player_data + PL_STR_CUR,x
    cmp #12
    beq !t2_lose_next_s+
    jmp !t2_fail+
!t2_lose_expect11:
    lda player_data + PL_STR_CUR,x
    cmp #11
    beq !t2_lose_next_s+
    jmp !t2_fail+
!t2_lose_next_s:
    inx
    cpx #6
    bcc !t2_lose_chk-
    iny
    cpy #4
    bcc !t2_lose_loop-

    // 2C: 6 Restore-Stat potions (#52,#55,#58,#61,#78,#79): all 6 drained to 8 (base 12)
    // Verify each restores ONLY its exact stat to 12 while other 5 remain 8!
    ldy #0
!t2_rest_loop:
    sty t_idx
    jsr reset_player_baseline
    lda #8
    ldx #0
!t2_rest_drain:
    sta player_data + PL_STR_CUR,x
    sta zp_player_str,x
    inx
    cpx #6
    bcc !t2_rest_drain-
    ldy t_idx
    lda rest_pot_ids,y
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_quaff
    bcs !+
    jmp !t2_fail+
!:  ldy t_idx
    ldx #0
!t2_rest_chk:
    txa
    cmp rest_pot_stat_idx,y
    beq !t2_rest_expect12+
    lda player_data + PL_STR_CUR,x
    cmp #8
    beq !t2_rest_next_s+
    jmp !t2_fail+
!t2_rest_expect12:
    lda player_data + PL_STR_CUR,x
    cmp #12
    beq !t2_rest_next_s+
    jmp !t2_fail+
!t2_rest_next_s:
    inx
    cpx #6
    bcc !t2_rest_chk-
    iny
    cpy #6
    bcc !t2_rest_loop-

    lda #$01
    sta tc_results + 1
    jmp !t3_start+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // =========================================================================
    // Test 3: All 45 VMS Potions (50..94) consume & return C=1 + key effects
    // =========================================================================
!t3_start:
    jsr item_init_identification
    // 3A: Quaff every potion 50..94 below max HP -> all 45 return C=1 and identify!
    lda #ITEM_SLOT_POTION_OF_GAIN_STRENGTH
    sta t_id
!t3_all_pot:
    lda t_id
    jsr run_quaff_a
    lda t_carry
    bne !+
    jmp !t3_fail+
!:  lda #0
    sta item_cur_page
    ldx t_id
    jsr id_known_test
    bne !+
    jmp !t3_fail+
!:  inc t_id
    lda t_id
    cmp #(ITEM_SLOT_POTION_OF_INFRAVISION + 1)
    bcc !t3_all_pot-

    // 3B: Heal potions (#62..#65) at FULL HP are a silent no-op (VMS hp_player: no message, HP unchanged)
    jsr reset_player_baseline
    lda #200
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #ITEM_SLOT_POTION_OF_HEALING
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_quaff
    lda tpm_huff_calls
    beq !+
    jmp !t3_fail+
!:  lda zp_player_hp_lo
    cmp #200
    beq !+
    jmp !t3_fail+

    // 3C: Spot-check Speed (#72), Resist Heat (#88), Resist Cold (#89),
    // Detect Invisible (#90), Restore Mana (#93), Infravision (#94), Sleep (#68)
!:  lda #ITEM_SLOT_POTION_OF_SPEED
    jsr run_quaff_a
    lda zp_eff_speed
    bpl !+
    jmp !t3_fail+
!:  bne !+
    jmp !t3_fail+
!:  lda #ITEM_SLOT_POTION_OF_RESIST_HEAT
    jsr run_quaff_a
    lda zp_eff_resist
    bne !+
    jmp !t3_fail+
!:  lda #ITEM_SLOT_POTION_OF_RESIST_COLD
    jsr run_quaff_a
    lda eff_resist_cold_timer
    bne !+
    jmp !t3_fail+
!:  lda #ITEM_SLOT_POTION_OF_DETECT_INVISIBLE
    jsr run_quaff_a
    lda zp_eff_see_inv
    cmp #13
    bcs !+
    jmp !t3_fail+
!:  cmp #25
    bcc !+
    jmp !t3_fail+
!:  lda zp_eff_invis
    beq !+
    jmp !t3_fail+
    // H1: Temporary See-Invisible ticks down to 0 via turn_tick_effects
!:  lda #2
    sta zp_eff_see_inv
    jsr turn_tick_effects
    lda zp_eff_see_inv
    cmp #1
    beq !+
    jmp !t3_fail+
!:  jsr turn_tick_effects
    lda zp_eff_see_inv
    beq !+
    jmp !t3_fail+
!:  lda #ITEM_SLOT_POTION_OF_RESTORE_MANA
    jsr run_quaff_a
    lda zp_player_mp
    cmp #20
    beq !+
    jmp !t3_fail+
!:  lda #ITEM_SLOT_POTION_OF_INFRAVISION
    jsr run_quaff_a
    lda zp_eff_infra
    bne !+
    jmp !t3_fail+
!:  lda #ITEM_SLOT_POTION_OF_SLEEP
    jsr run_quaff_a
    lda zp_eff_paralyze
    bne !+
    jmp !t3_fail+

    // 3D: H7 Potion of Lose Memories (#81) drops XP & level while preserving
    // PL_MAX_XP, and Potion of Restore Life Levels (#87) restores XP & level
!:  jsr reset_player_baseline
    lda #RACE_HUMAN
    sta player_data + PL_RACE
    lda #CLASS_WARRIOR
    sta player_data + PL_CLASS
    lda #100
    sta player_data + PL_EXPFACT
    lda #3
    sta player_data + PL_LEVEL
    sta zp_player_lvl
    lda #28                             // Level 3 threshold is 25 XP; 28 - 7 = 21 -> Level 2
    sta player_data + PL_XP_0
    sta player_data + PL_MAX_XP_0
    lda #0
    sta player_data + PL_XP_1
    sta player_data + PL_XP_2
    sta player_data + PL_MAX_XP_1
    sta player_data + PL_MAX_XP_2
    lda #ITEM_SLOT_POTION_OF_LOSE_MEMORIES
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_quaff
    lda player_data + PL_XP_0
    cmp #21
    beq !+
    jmp !t3_fail+
!:  lda zp_player_lvl
    cmp #2
    beq !+
    jmp !t3_fail+
!:  lda player_data + PL_MAX_XP_0
    cmp #28
    beq !+
    jmp !t3_fail+
!:  lda #0
    sta zp_msg_flags
    lda #ITEM_SLOT_POTION_OF_RESTORE_LIFE_LEVELS
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_quaff
    lda player_data + PL_XP_0
    cmp #28
    beq !+
    jmp !t3_fail+
!:  lda zp_player_lvl
    cmp #3
    beq !+
    jmp !t3_fail+

    // 3E: 18/100 (118) positive player_stat_res drain + single-stat restore
    // preserves drained residual on non-target stats and restores target residual
!:  jsr reset_player_baseline
    lda #117
    sta player_data + PL_STR_BASE
    sta player_data + PL_INT_BASE
    lda #ITEM_SLOT_RING_OF_STRENGTH
    sta inv_item_id + EQUIP_RING
    lda #ITEM_PAGE_RING_OF_STRENGTH
    sta inv_ego + EQUIP_RING
    lda #4
    sta inv_p1 + EQUIP_RING
    lda #1
    sta inv_qty + EQUIP_RING
    lda #ITEM_SLOT_RING_OF_GAIN_INTELLIGENCE
    sta inv_item_id + EQUIP_RING2
    lda #ITEM_PAGE_RING_OF_GAIN_INTELLIGENCE
    sta inv_ego + EQUIP_RING2
    lda #4
    sta inv_p1 + EQUIP_RING2
    lda #1
    sta inv_qty + EQUIP_RING2
    jsr player_calc_stats               // Both 117 + 4*10 -> cur=118, res=+39
    lda #ITEM_SLOT_POTION_OF_WEAKNESS
    jsr run_quaff_keep_a
    lda #ITEM_SLOT_POTION_OF_LOSE_INTELLIGENCE
    jsr run_quaff_keep_a
    // Restore ONLY Intelligence: INT residual returns to +39, STR stays drained (+36..+38)
    lda #ITEM_SLOT_POTION_OF_RESTORE_INTELLIGENCE
    jsr run_quaff_keep_a
    lda player_data + PL_INT_CUR
    cmp #118
    beq !+
    jmp !t3_fail+
!:  lda player_stat_res + 1
    cmp #39
    beq !+
    jmp !t3_fail+
!:  lda player_stat_res + 0
    cmp #36
    bcc !t3_fail_3e+
    cmp #39
    bcc !+
!t3_fail_3e:
    jmp !t3_fail+
!:  pha                             // keep drained STR residual across unequip
    lda #EQUIP_RING
    sta piw_equip
    tax
    clc
    jsr player_adjust_equipment_stat    // Unequip +4 STR ring: 118 + res - 40 = 78 + res
    pla
    clc
    adc #78
    cmp player_data + PL_STR_CUR
    beq !+
    jmp !t3_fail+
!:  lda #EQUIP_RING
    sta piw_equip
    tax
    sec
    jsr player_adjust_equipment_stat    // Re-equip +4 STR ring and restore STR
    lda #ITEM_SLOT_POTION_OF_RESTORE_STRENGTH
    jsr run_quaff_keep_a
    lda #EQUIP_RING
    sta piw_equip
    tax
    clc
    jsr player_adjust_equipment_stat
    lda player_data + PL_STR_CUR
    cmp #117
    beq !+
    jmp !t3_fail+

    // 3F: MON-044 Gain Strength with worn stat-modifying rings preserves 18/xx
    // stepping across thresholds and preserves existing drains.
!:  jsr reset_player_baseline
    lda #16
    sta player_data + PL_STR_BASE
    lda #ITEM_SLOT_RING_OF_STRENGTH
    sta inv_item_id + EQUIP_RING
    lda #ITEM_PAGE_RING_OF_STRENGTH
    sta inv_ego + EQUIP_RING
    lda #3
    sta inv_p1 + EQUIP_RING
    lda #1
    sta inv_qty + EQUIP_RING
    jsr player_calc_stats               // healthy = 28 (18/10)
    lda #ITEM_SLOT_POTION_OF_GAIN_STRENGTH
    jsr run_quaff_keep_a
    lda player_data + PL_STR_BASE
    cmp #17
    bne !t3_fail_3f_mid+
    lda player_data + PL_STR_CUR
    cmp #38
    bne !t3_fail_3f_mid+
    lda player_stat_res + 0
    bne !t3_fail_3f_mid+

    // Drained base=16 +3 ring (healthy 28, cur 22) -> cur=32 (drain -6 kept)
    lda #16
    sta player_data + PL_STR_BASE
    lda #22
    sta player_data + PL_STR_CUR
    sta zp_player_str
    lda #0
    sta player_stat_res + 0
    lda #ITEM_SLOT_POTION_OF_GAIN_STRENGTH
    jsr run_quaff_keep_a
    lda player_data + PL_STR_BASE
    cmp #17
    bne !t3_fail_3f_mid+
    lda player_data + PL_STR_CUR
    cmp #32
    bne !t3_fail_3f_mid+
    lda player_stat_res + 0
    bne !t3_fail_3f_mid+

    // Base=17 +12 ring (healthy 118, res +10) -> base=18, cur=118, res=+20
    lda #12
    sta inv_p1 + EQUIP_RING
    jsr player_calc_stats
    lda #ITEM_SLOT_POTION_OF_GAIN_STRENGTH
    jsr run_quaff_keep_a
    lda player_data + PL_STR_BASE
    cmp #18
    bne !t3_fail_3f_mid+
    lda player_data + PL_STR_CUR
    cmp #118
    bne !t3_fail_3f_mid+
    lda player_stat_res + 0
    cmp #20
    beq !+
!t3_fail_3f_mid:
    jmp !t3_fail+

    // Base=18 + cursed -2 ring -> matches healthy(new_base, -2) from player_calc_stats
!:  lda #(-2) & $ff
    sta inv_p1 + EQUIP_RING
    jsr player_calc_stats
    lda #ITEM_SLOT_POTION_OF_GAIN_STRENGTH
    jsr run_quaff_keep_a
    lda player_data + PL_STR_BASE
    cmp #19
    bcc !t3_fail_3f+
    lda player_data + PL_STR_CUR
    pha
    lda player_stat_res + 0
    pha
    jsr player_calc_stats
    pla
    cmp player_stat_res + 0
    bne !t3_fail_3f_pop+
    pla
    cmp player_data + PL_STR_CUR
    bne !t3_fail_3f+

    // Saturated gear (+17 STR ring already equipped on Page 1), base=100,
    // drained cur=90, res=0 -> must apply full (new_base - 100) delta
    lda #17
    sta inv_p1 + EQUIP_RING
    lda #100
    sta player_data + PL_STR_BASE
    lda #90
    sta player_data + PL_STR_CUR
    sta zp_player_str
    lda #0
    sta player_stat_res + 0
    lda #ITEM_SLOT_POTION_OF_GAIN_STRENGTH
    jsr run_quaff_keep_a
    lda player_data + PL_STR_BASE
    sec
    sbc #100
    beq !t3_fail_3f+
    cmp #11
    bcs !t3_fail_3f+
    clc
    adc #90
    cmp player_data + PL_STR_CUR
    bne !t3_fail_3f+
    lda player_stat_res + 0
    beq !t3_pass+
!t3_fail_3f_pop:
    pla
!t3_fail_3f:
    jmp !t3_fail+

!t3_pass:
    lda #$01
    sta tc_results + 2
    jmp !t4_start+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // =========================================================================
    // Test 4: All 42 VMS Scrolls (95..136) via production item_read_scroll
    // =========================================================================
!t4_start:
    jsr item_init_identification
    lda #ITEM_SLOT_SCROLL_OF_ENCHANT_WEAPON_TO_HIT
    sta t_id
!t4_scroll_loop:
    jsr init_test_arena
    jsr reset_player_baseline
    // Place scroll in slot 0 and a targetable item in slot 1 (for Identify)
    lda t_id
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #0
    sta inv_ego + 0

    lda #ITEM_SLOT_RING_OF_PROTECTION
    sta inv_item_id + 1
    lda #ITEM_PAGE_RING_OF_PROTECTION
    sta inv_ego + 1
    lda #1
    sta inv_qty + 1

    // Equip weapon & body armor so enchant/curse scrolls have valid targets
    lda #ITEM_SLOT_DAGGER
    sta inv_item_id + EQUIP_WEAPON
    lda #ITEM_PAGE_DAGGER
    sta inv_ego + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON

    lda #ITEM_SLOT_LEATHER_ARMOR
    sta inv_item_id + EQUIP_BODY
    lda #0
    sta inv_ego + EQUIP_BODY
    lda #1
    sta inv_qty + EQUIP_BODY

    jsr stuff_slot_a_keys
    jsr item_read_scroll
    bcs !+
    jmp !t4_fail+
!:  // 2 carried items -> 1 carried item after scroll consumption (slot 1 now empty)
    lda inv_item_id + 1
    cmp #FI_EMPTY
    beq !+
    jmp !t4_fail+
!:  // Scroll ID must be marked known on Page 0
    lda #0
    sta item_cur_page
    ldx t_id
    jsr id_known_test
    bne !+
    jmp !t4_fail+
!:  inc t_id
    lda t_id
    cmp #(ITEM_SLOT_SCROLL_OF_STAR_DESTRUCTION + 1)
    bcs !t4_spot+
    jmp !t4_scroll_loop-

!t4_spot:
    // Spot-verify key scroll handlers: Recharging (spy 1, arg 50), Genocide (spy 4),
    // *Destruction* (spy 5), Magic Mapping (spy 11), Blessing (zp_eff_bless > 0),
    // Word of Recall (zp_eff_word_recall > 0), & Enchant Weapon To-Hit vs To-Dam
    jsr reset_player_baseline
    lda #ITEM_SLOT_SCROLL_OF_RECHARGING
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_read_scroll
    lda spy_kind
    cmp #1
    beq !+
    jmp !t4_fail+
!:  lda spy_arg
    cmp #50
    beq !+
    jmp !t4_fail+

!:  jsr reset_player_baseline
    lda #ITEM_SLOT_SCROLL_OF_GENOCIDE
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_read_scroll
    lda spy_kind
    cmp #4
    beq !+
    jmp !t4_fail+

!:  jsr reset_player_baseline
    lda #ITEM_SLOT_SCROLL_OF_STAR_DESTRUCTION
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_read_scroll
    lda spy_kind
    cmp #5
    beq !+
    jmp !t4_fail+

!:  jsr reset_player_baseline
    lda #ITEM_SLOT_SCROLL_OF_MAGIC_MAPPING
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_read_scroll
    lda spy_kind
    cmp #11
    beq !+
    jmp !t4_fail+

!:  jsr reset_player_baseline
    lda #ITEM_SLOT_SCROLL_OF_BLESSING
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_read_scroll
    lda zp_eff_bless
    bne !+
    jmp !t4_fail+

!:  jsr reset_player_baseline
    lda #ITEM_SLOT_SCROLL_OF_WORD_OF_RECALL
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_read_scroll
    lda zp_eff_word_recall
    bne !+
    jmp !t4_fail+

    // Spot-verify Enchant Weapon To-Hit (+1 to_hit, 0 to_dam) vs To-Dam (0 to_hit, +1 to_dam)
!:  jsr reset_player_baseline
    lda #ITEM_SLOT_DAGGER
    sta inv_item_id + EQUIP_WEAPON
    lda #ITEM_PAGE_DAGGER
    sta inv_ego + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #ITEM_SLOT_SCROLL_OF_ENCHANT_WEAPON_TO_HIT
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_read_scroll
    lda inv_to_hit + EQUIP_WEAPON
    cmp #1
    beq !+
    jmp !t4_fail+
!:  lda inv_to_dam + EQUIP_WEAPON
    beq !+
    jmp !t4_fail+

!:  lda #0
    sta zp_msg_flags
    lda #ITEM_SLOT_SCROLL_OF_ENCHANT_WEAPON_TO_DAM
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_read_scroll
    lda inv_to_hit + EQUIP_WEAPON
    cmp #1
    beq !+
    jmp !t4_fail+
!:  lda inv_to_dam + EQUIP_WEAPON
    cmp #1
    beq !+
    jmp !t4_fail+

    // C1: Scroll of Summon Monster seeds fae_cx/fae_cy from zp_player_x/y
    // even when prior fae_cx/fae_cy holds OOB $ff
!:  jsr init_test_arena
    jsr reset_player_baseline
    lda #$ff
    sta fae_cx
    sta fae_cy
    lda #ITEM_SLOT_SCROLL_OF_SUMMON_MONSTER
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_read_scroll
    lda zp_mon_count
    bne !+
    jmp !t4_fail+
!:  ldx #0
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    sec
    sbc #9                              // adjacent to zp_player_x=10 -> 9..11
    cmp #3
    bcc !+
    jmp !t4_fail+
!:  ldy #MX_Y
    lda (zp_ptr0),y
    sec
    sbc #9                              // adjacent to zp_player_y=10 -> 9..11
    cmp #3
    bcc !+
    jmp !t4_fail+

    // Scroll of Curse Armor reverses Crown of Might (+3) STR/DEX/CON & zeroes p1,
    // and recalculates weight when stripping EGO_GREAT_MASS from worn boots
!:  jsr reset_player_baseline
    lda #ITEM_SLOT_GOLDEN_CROWN
    sta inv_item_id + EQUIP_HEAD
    lda #EGO_MIGHT
    sta inv_ego + EQUIP_HEAD
    lda #3
    sta inv_p1 + EQUIP_HEAD
    lda #1
    sta inv_qty + EQUIP_HEAD
    jsr player_calc_stats               // STR/DEX/CON: 12 -> 15
    lda #ITEM_SLOT_SCROLL_OF_CURSE_ARMOR
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr stuff_slot_a_keys
    jsr item_read_scroll
    lda inv_ego + EQUIP_HEAD
    ora inv_p1 + EQUIP_HEAD
    beq !+
    jmp !t4_fail+
!:  lda player_data + PL_STR_CUR
    cmp #12
    beq !+
    jmp !t4_fail+
!:  lda player_data + PL_DEX_CUR
    cmp #12
    beq !+
    jmp !t4_fail+
!:  lda player_data + PL_CON_CUR
    cmp #12
    beq !+
    jmp !t4_fail+

!:  jsr reset_player_baseline
    lda #ITEM_SLOT_HARD_LEATHER_BOOTS
    sta inv_item_id + EQUIP_FEET
    lda #(ITEM_PAGE_HARD_LEATHER_BOOTS | EGO_GREAT_MASS)
    sta inv_ego + EQUIP_FEET
    lda #1
    sta inv_qty + EQUIP_FEET
    jsr inven_recalc_weight
    lda inven_weight_lo
    cmp #40
    beq !+
    jmp !t4_fail+
!:  lda #ITEM_SLOT_SCROLL_OF_CURSE_ARMOR
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    jsr inven_recalc_weight
    jsr stuff_slot_a_keys
    jsr item_read_scroll
    lda inv_ego + EQUIP_FEET
    cmp #ITEM_PAGE_HARD_LEATHER_BOOTS
    beq !+
    jmp !t4_fail+
!:  lda inven_weight_lo
    cmp #20
    beq !t4_pass+
    jmp !t4_fail+

!t4_pass:
    lda #$01
    sta tc_results + 3
    jmp !t5_start+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // =========================================================================
    // Test 5: All 24 VMS Wands (137..160) via item_aim_wand &
    //         All 25 VMS Staves (161..185) via item_use_staff
    // =========================================================================
!t5_start:
    jsr item_init_identification
    // 5A: All 24 Wands (137..160)
    lda #ITEM_SLOT_WAND_OF_LIGHT
    sta t_id
!t5_wand_loop:
    jsr init_test_arena
    jsr reset_player_baseline
    lda t_id
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #3
    sta inv_p1 + 0
    lda #0
    sta inv_ego + 0
    jsr stuff_slot_a_keys
    jsr item_aim_wand
    bcs !+
    jmp !t5_fail+
!:  lda inv_p1 + 0
    cmp #2
    beq !+
    jmp !t5_fail+
!:  lda #0
    sta item_cur_page
    ldx t_id
    jsr id_known_test
    bne !+
    jmp !t5_fail+
!:  inc t_id
    lda t_id
    cmp #(ITEM_SLOT_WAND_OF_WONDER + 1)
    bcc !t5_wand_loop-

    // 5B: All 25 Staves (161..185)
    lda #ITEM_SLOT_STAFF_OF_LIGHT
    sta t_id
!t5_staff_loop:
    jsr init_test_arena
    jsr reset_player_baseline
    lda t_id
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #3
    sta inv_p1 + 0
    lda #0
    sta inv_ego + 0
    jsr stuff_slot_a_keys
    jsr item_use_staff
    bcs !+
    jmp !t5_fail+
!:  lda inv_p1 + 0
    cmp #2
    beq !+
    jmp !t5_fail+
!:  lda #0
    sta item_cur_page
    ldx t_id
    jsr id_known_test
    bne !+
    jmp !t5_fail+
!:  inc t_id
    lda t_id
    cmp #(ITEM_SLOT_STAFF_OF_DARKNESS_L5 + 1)
    bcc !t5_staff_loop-

    // 5C: Spot-check Staff of Earthquakes (#167 -> spy_kind 2), Staff of Speed (#177 -> spy_kind 8),
    // Wand of Fire Balls (#157 -> spy_kind 9, arg 49), Wand of Acid Balls (#159 -> spy_kind 9, arg 40)
    jsr init_test_arena
    jsr reset_player_baseline
    lda #ITEM_SLOT_STAFF_OF_EARTHQUAKES
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #2
    sta inv_p1 + 0
    jsr stuff_slot_a_keys
    jsr item_use_staff
    lda spy_kind
    cmp #2
    beq !+
    jmp !t5_fail+

!:  jsr reset_player_baseline
    lda #ITEM_SLOT_STAFF_OF_SPEED
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #2
    sta inv_p1 + 0
    jsr stuff_slot_a_keys
    jsr item_use_staff
    lda spy_kind
    cmp #8
    beq !+
    jmp !t5_fail+

!:  jsr reset_player_baseline
    lda #ITEM_SLOT_WAND_OF_FIRE_BALLS
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #2
    sta inv_p1 + 0
    jsr stuff_slot_a_keys
    jsr item_aim_wand
    lda spy_kind
    cmp #9
    beq !+
    jmp !t5_fail+
!:  lda spy_arg
    cmp #49
    beq !+
    jmp !t5_fail+

!:  jsr reset_player_baseline
    lda #ITEM_SLOT_WAND_OF_ACID_BALLS
    sta inv_item_id + 0
    lda #1
    sta inv_qty + 0
    lda #2
    sta inv_p1 + 0
    jsr stuff_slot_a_keys
    jsr item_aim_wand
    lda spy_kind
    cmp #9
    beq !+
    jmp !t5_fail+
!:  lda spy_arg
    cmp #40
    beq !t5_pass+
    jmp !t5_fail+

!t5_pass:
    lda #$01
    sta tc_results + 4
    jmp test_finish
!t5_fail:
    lda #$00
    sta tc_results + 4
    jmp test_finish

gain_pot_ids:
    .byte ITEM_SLOT_POTION_OF_GAIN_STRENGTH
    .byte ITEM_SLOT_POTION_OF_GAIN_INTELLIGENCE
    .byte ITEM_SLOT_POTION_OF_GAIN_WISDOM
    .byte ITEM_SLOT_POTION_OF_CHARISMA
    .byte ITEM_SLOT_POTION_OF_GAIN_CONSTITUTION
    .byte ITEM_SLOT_POTION_OF_GAIN_DEXTERITY
gain_pot_stat_idx:
    .byte 0, 1, 2, 5, 4, 3

lose_pot_ids:
    .byte ITEM_SLOT_POTION_OF_WEAKNESS
    .byte ITEM_SLOT_POTION_OF_LOSE_INTELLIGENCE
    .byte ITEM_SLOT_POTION_OF_LOSE_WISDOM
    .byte ITEM_SLOT_POTION_OF_UGLINESS
lose_pot_stat_idx:
    .byte 0, 1, 2, 5

rest_pot_ids:
    .byte ITEM_SLOT_POTION_OF_RESTORE_STRENGTH
    .byte ITEM_SLOT_POTION_OF_RESTORE_INTELLIGENCE
    .byte ITEM_SLOT_POTION_OF_RESTORE_WISDOM
    .byte ITEM_SLOT_POTION_OF_RESTORE_CHARISMA
    .byte ITEM_SLOT_POTION_OF_RESTORE_DEXTERITY
    .byte ITEM_SLOT_POTION_OF_RESTORE_CONSTITUTION
rest_pot_stat_idx:
    .byte 0, 1, 2, 5, 3, 4

effects_vms_test_end:
.assert "Effects VMS test stays below MAP_BASE", effects_vms_test_end <= MAP_BASE, true
