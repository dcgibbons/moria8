// test_monster_magic3.s — Focused C64 runtime tests for Phase 5 Wave 5.4b:
//   - Extended monster spells (MSF2_BLINK, MSF2_TELE_SELF, MSF2_SUMMON_UNDEAD,
//     MSF2_SLOW, MSF2_DRAIN_MANA), including cr_spell_flags == 0 extended-only
//     casters and uniform pick across MSF + MSF2.
//   - cr_cdefense (CD_FROST, CD_FIRE, CD_POISON, CD_ACID, CD_LIGHT, CD_STONE,
//     CD_NO_SLEEP) across bolts, balls, light room, stone-to-mud, sleep/confuse
//     spells/items/melee-confuse, breath /4 resistance, and FT/FB/Fire-ammo egos.
//   - Summoned creatures come from levels 1 to dlvl + 2 (VMS misc.inc
//     summon_monster, mon$summon_adj = 2): the monster spell and the Staff of
//     Summoning (tests 21-22).
//   - VMS summon counts, Summon Undead's creature, summons awake beside the
//     player, poly_monster's roll and level, mass_poly's reach (tests 23-28).
//
// Results at $0400-$041B: $01 = pass, $00 = fail (28 tests).

#define C64_TEST_NAME_STREAMS_A000
#define MONSTER_MAGIC_PRODUCTION_EXTENDED

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start

test_exit_trampoline:
    sei
    :BankOutBasic()
    ldx #27
!tc_copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !tc_copy-
    brk

.pc = $0830 "Main"
.encoding "screencode_mixed"

#define COMPILE_EMBEDDED_DUNGEON_TEST_ROSTER
#define PLAYER_CHARGEN_EXTERNAL
#define TRAP_TRIGGER_EXTERNAL
#define ITEM_SPAWN_EXTERNAL
#define PICK_ITEM_TYPE_EXTERNAL

.segmentdef TestUnused [start=$E100, min=$E100, max=$FFF9]
.segmentdef TestCreateOverlay [start=$D000, min=$D000, max=$DFFF]
.segmentdef TestNameStreams [start=$E100, min=$E100, max=$FFF9]

#import "../../../../core/zeropage.s"
#import "../memory.s"
#define ITEM_ACTIONS_OVERLAY_EXTERNAL
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
.segment TestUnused
#import "../../../../core/ui_status.s"
.segment Default
#import "../../../../core/ui_help_clear.s"
#import "../../../../core/stat_display.s"
.segment TestCreateOverlay
player_create:
    brk
.segment Default
#import "../../../../core/input_contract.s"
#import "../../../../core/sound.s"
#import "../../../../core/dungeon_data.s"
#import "dungeon_gen_stubs.s"
#import "../../../../core/huffman.s"
#import "../../../../core/dungeon_features.s"
#import "chest_summons_stubs.s"
#import "../../../../core/monster.s"
#import "../../../../core/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/monster_ai.s"
#import "../../../../core/recall.s"
#import "../../../../core/monster_magic.s"
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../../../../core/item.s"
hal_item_cat_read_byte:
    lda #0
    rts
.segment TestCreateOverlay
#import "../../../../core/special_rooms.s"
.segment Default
#import "../../../../core/ego_items.s"
#import "../../../../core/special_rooms_stubs.s"
.segment TestUnused
#import "../../../../core/player_items.s"
.segment Default
#import "../../../../core/spell_data.s"
#import "../../../../core/projectile.s"
#import "../../../../core/spell_effects.s"
#import "../../../../core/player_magic_state.s"
#import "../../../../core/player_magic_state_ops.s"
#import "../../../../core/player_magic.s"
#import "../../../../core/player_magic_feedback.s"
#import "../../../../core/player_magic_ball.s"
#import "../../../../core/eff_item_p1.s"
#import "../dungeon_render.s"
#import "../../../../core/dungeon_los.s"
#import "../../../../core/player_move.s"
#import "../../../../core/combat.s"
#import "../../../../core/scene_mat_tile.s"
#import "../../../../core/monster_attack.s"
.segment TestCreateOverlay
#import "../../../../core/turn.s"
.segment TestUnused
#import "../../../../core/trap_trigger_cold.s"
#import "../../../../core/player_chargen_cold.s"
#import "../../../../core/item_spawn_cold.s"
#import "../../../../core/pick_item_type_cold.s"
.segment Default

store_init_all:
store_restock_all:
store_enter:
ui_help_show_paged:
ui_help_display:
help_draw_line:
help_draw_hborder:
ui_char_display:
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
count_spells_known:
chest_mark_found_all:
    rts
#import "../../../../core/ui_trampoline_stubs.s"

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

tc_results:     .fill 28, $ff
tc_hist:        .fill 6, 0      // runs by monsters placed (0-5+)
tc_cnt:         .byte 0
tc_seen_a:      .byte 0
tc_seen_b:      .byte 0
tst_save_mode:  .byte 0         // 0 = fail save, 1 = pass save
tst_save_orig:  .fill 3, 0
tst_dice_orig:  .fill 3, 0
tst_fixed_dice: .byte 16

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

tst_dir_east:
    lda zp_player_x
    clc
    adc #1
    sta df_target_x
    lda zp_player_y
    sta df_target_y
    sec
    rts

tst_flash_nop:
    rts

tst_always_hit:
    sec
    rts

tst_save_stub:
    lda tst_save_mode
    eor #1
    lsr                         // C=0 when saved, C=1 when failed
    rts

tst_patch_save:
    ldx #2
!c: lda player_saving_throw,x
    sta tst_save_orig,x
    dex
    bpl !c-
    :PatchJump(player_saving_throw, tst_save_stub)
    rts

tst_unpatch_save:
    ldx #2
!c: lda tst_save_orig,x
    sta player_saving_throw,x
    dex
    bpl !c-
    rts

tst_dice_stub:
    lda tst_fixed_dice
    sta zp_math_a
    lda #0
    sta zp_math_b
    rts

tst_patch_dice:
    ldx #2
!c: lda math_dice,x
    sta tst_dice_orig,x
    dex
    bpl !c-
    :PatchJump(math_dice, tst_dice_stub)
    rts

tst_unpatch_dice:
    ldx #2
!c: lda tst_dice_orig,x
    sta math_dice,x
    dex
    bpl !c-
    rts

// Build clean dark room [16..29, 9..16], player at (20, 12)
tst_setup_room:
    jsr fill_map_rock
    jsr item_init_floor
    jsr monster_init_table
    lda #0
    sta zp_msg_flags
    sta zp_game_flags
    sta zp_eff_blind
    sta zp_eff_confuse
    sta zp_eff_paralyze
    sta zp_eff_speed
    sta player_pflags
    sta vis_room_revealed
    lda #8
    sta $c6
    lda #$20
    ldx #7
!k: sta $0277,x
    dex
    bpl !k-

    lda #1
    sta room_count
    lda #16
    sta room_x
    lda #9
    sta room_y
    lda #14
    sta room_w
    lda #8
    sta room_h
    lda #0
    sta room_lit
    // Carve floor [16..29, 9..16]
    ldx #9
!tsr_row:
    jsr map_row_ptr0_x
    ldy #16
    lda #TILE_FLOOR
!tsr_col:
    sta (zp_ptr0),y
    iny
    cpy #30
    bcc !tsr_col-
    inx
    cpx #17
    bcc !tsr_row-

    lda #20
    sta zp_player_x
    sta player_data + PL_MAP_X
    lda #12
    sta zp_player_y
    sta player_data + PL_MAP_Y
    lda #3
    sta zp_player_dlvl
    lda #1
    sta current_tier
    lda #100
    sta zp_player_hp_lo
    sta player_data + PL_HP_LO
    lda #0
    sta zp_player_hp_hi
    sta player_data + PL_HP_HI

    // Clear creature type 5 test scratch flags/defenses
    ldx #5
    lda #0
    sta cr_spell_flags,x
    sta cr_spell_flags2,x
    sta cr_spell_chance,x
    sta cr_cdefense,x
    sta cr_mflags,x
    lda #10
    sta cr_level,x
    rts

// tst_tally_levels — For each live slot from X on: tc_total += 1, tc_seen_a
// += 1 when its creature level is above dlvl, tc_seen_b += 1 when above
// dlvl + 2 (the summon limit).
tst_tally_levels:
    stx tc_cnt2
!ttl_loop:
    ldx tc_cnt2
    cpx #MAX_MONSTERS
    bcs !ttl_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !ttl_next+
    inc tc_total
    tay
    lda cr_level,y
    cmp zp_player_dlvl
    beq !ttl_next+
    bcc !ttl_next+
    inc tc_seen_a
    sec
    sbc #2
    cmp zp_player_dlvl
    beq !ttl_next+
    bcc !ttl_next+
    inc tc_seen_b
!ttl_next:
    inc tc_cnt2
    bne !ttl_loop-
!ttl_done:
    rts

// tst_summon_verdict — A = $01 when something was summoned, some above dlvl
// and none above dlvl + 2, else $00.
tst_summon_verdict:
    lda tc_total
    beq !tsv_fail+
    lda tc_seen_a
    beq !tsv_fail+
    lda tc_seen_b
    bne !tsv_fail+
    lda #$01
    rts
!tsv_fail:
    lda #$00
    rts

tst_summon_reset:
    lda #0
    sta tc_total
    sta tc_seen_a
    sta tc_seen_b
    lda #24
    sta tc_loop
    rts

tc_cnt2:        .byte 0
tc_total:       .byte 0
tc_loop:        .byte 0

// tst_hist_reset — tc_hist zeroed, 40 runs (tc_loop)
tst_hist_reset:
    ldx #5
    lda #0
!thr_loop:
    sta tc_hist,x
    dex
    bpl !thr_loop-
    sta tc_seen_a
    sta tc_seen_b
    lda #40
    sta tc_loop
    rts

// tst_hist_add — tc_hist[min(zp_mon_count, 5)] += 1
tst_hist_add:
    lda zp_mon_count
    cmp #5
    bcc !tha_ok+
    lda #5
!tha_ok:
    tax
    inc tc_hist,x
    rts

// tst_slot_awake — Z = 0 when slot X is awake (MF_AWAKE)
tst_slot_awake:
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_AWAKE
    rts

// Spawn creature type 5 at (A, Y) with HP = 200 in slot X; sets zp_mon_* too.
tst_spawn_t5:
    sta ms_spawn_x
    sta zp_mon_x
    sty ms_spawn_y
    sty zp_mon_y
    lda #5
    sta zp_mon_type
    jsr monster_spawn_one
    stx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #200
    sta (zp_ptr0),y
    iny
    lda #0
    sta (zp_ptr0),y
    ldy #MX_SLEEP_CUR
    sta (zp_ptr0),y
    ldx zp_mon_idx
    rts

test_start:
    lda #FI_EMPTY
    sta inv_item_id + EQUIP_WEAPON
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
    :PatchJump(get_direction_target, tst_dir_east)
    :PatchJump(screen_flash_at, tst_flash_nop)
    :PatchJump(msg_print, tst_flash_nop)

    // ========================================================
    // Test 1: Extended-only caster (cr_spell_flags == 0,
    // cr_spell_flags2 = MSF2_BLINK) passes monster_can_cast;
    // CM2_PHASE alone ($20, non-spell bit) does NOT cast.
    // ========================================================
    jsr tst_setup_room
    lda #22
    ldy #12
    jsr tst_spawn_t5
    lda #1
    sta cr_spell_chance + 5
    lda #MSF2_BLINK
    sta cr_spell_flags2 + 5
    jsr monster_can_cast
    bcc !t1_fail+
    lda #CM2_PHASE
    sta cr_spell_flags2 + 5
    jsr monster_can_cast
    bcs !t1_fail+
    lda #$01
    bne !t1_store+
!t1_fail:
    lda #$00
!t1_store:
    sta tc_results + 0

    // ========================================================
    // Test 2: Uniform pick across MSF_BLIND + MSF2_SLOW hits
    // both handlers and records recall_spells safely.
    // ========================================================
    jsr tst_setup_room
    jsr tst_patch_save
    lda #0
    sta tst_save_mode
    sta tc_seen_a
    sta tc_seen_b
    sta recall_spells + 5
    lda #22
    ldy #12
    jsr tst_spawn_t5
    lda #MSF_BLIND
    sta cr_spell_flags + 5
    lda #MSF2_SLOW
    sta cr_spell_flags2 + 5
    lda #1
    sta cr_spell_chance + 5
    lda #24
    sta tc_cnt
!t2_loop:
    lda #0
    sta zp_eff_blind
    sta zp_eff_speed
    sta zp_msg_flags
    lda #8
    sta $c6
    jsr monster_pick_spell
    lda zp_eff_blind
    beq !t2_chk_slow+
    inc tc_seen_a
!t2_chk_slow:
    lda zp_eff_speed
    bpl !t2_next+
    inc tc_seen_b
!t2_next:
    dec tc_cnt
    bne !t2_loop-
    jsr tst_unpatch_save
    lda tc_seen_a
    beq !t2_fail+
    lda tc_seen_b
    beq !t2_fail+
    lda recall_spells + 5
    beq !t2_fail+
    lda #$01
    bne !t2_store+
!t2_fail:
    lda #$00
!t2_store:
    sta tc_results + 1

    // ========================================================
    // Test 3: MSF2_BLINK ($01) short self-teleports <= 10 tiles,
    // updates MX_X/MX_Y and FLAG_OCCUPIED on old & new tiles.
    // ========================================================
    jsr tst_setup_room
    lda #23
    ldy #12
    jsr tst_spawn_t5
    lda #MSF2_BLINK
    sta cr_spell_flags2 + 5
    lda #1
    sta cr_spell_chance + 5
    jsr monster_pick_spell
    // Old tile (23, 12) must no longer have FLAG_OCCUPIED
    ldx #12
    jsr map_row_ptr0_x
    ldy #23
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    bne !t3_fail+
    // Monster moved off (23, 12) and not on player (20, 12)
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_X
    lda (zp_ptr0),y
    cmp zp_mon_x
    bne !t3_fail+
    iny
    lda (zp_ptr0),y
    cmp zp_mon_y
    bne !t3_fail+
    lda zp_mon_x
    cmp #23
    bne !t3_moved+
    lda zp_mon_y
    cmp #12
    beq !t3_fail+
!t3_moved:
    // New tile must have FLAG_OCCUPIED and |dx| <= 10, |dy| <= 10
    ldx zp_mon_y
    jsr map_row_ptr0_x
    ldy zp_mon_x
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    beq !t3_fail+
    lda zp_mon_x
    sec
    sbc #23
    bcs !t3_dx_pos+
    eor #$ff
    adc #1
!t3_dx_pos:
    cmp #11
    bcs !t3_fail+
    lda #$01
    bne !t3_store+
!t3_fail:
    lda #$00
!t3_store:
    sta tc_results + 2

    // ========================================================
    // Test 4: MSF2_TELE_SELF ($02) long self-teleport reaches
    // a distant floor room [53..57, 28..32] (> 35 tiles away).
    // ========================================================
    jsr fill_map_rock
    jsr monster_init_table
    lda #10
    sta zp_player_x
    sta zp_player_y
    // Place caster on isolated floor at (12, 10) and destination 5x5 room [53..57, 28..32]
    ldx #10
    jsr map_row_ptr0_x
    ldy #12
    lda #TILE_FLOOR
    sta (zp_ptr0),y
    ldx #28
!t4_row:
    jsr map_row_ptr0_x
    ldy #53
    lda #TILE_FLOOR
!t4_col:
    sta (zp_ptr0),y
    iny
    cpy #58
    bcc !t4_col-
    inx
    cpx #33
    bcc !t4_row-
    lda #12
    ldy #10
    jsr tst_spawn_t5
    lda #0
    sta cr_spell_flags + 5
    lda #MSF2_TELE_SELF
    sta cr_spell_flags2 + 5
    lda #1
    sta cr_spell_chance + 5
    jsr monster_pick_spell
    lda zp_mon_x
    cmp #53
    bcc !t4_fail+
    cmp #58
    bcs !t4_fail+
    lda zp_mon_y
    cmp #28
    bcc !t4_fail+
    cmp #33
    bcs !t4_fail+
    ldx zp_mon_y
    jsr map_row_ptr0_x
    ldy zp_mon_x
    lda (zp_ptr0),y
    and #FLAG_OCCUPIED
    beq !t4_fail+
    lda #$01
    bne !t4_store+
!t4_fail:
    lda #$00
!t4_store:
    sta tc_results + 3

    // ========================================================
    // Test 5: MSF2_SUMMON_UNDEAD ($04) spawns an adjacent
    // undead monster (cr_mflags & CF_UNDEAD != 0).
    // ========================================================
    jsr tst_setup_room
    // Ensure creature type 6 is marked CF_UNDEAD in embedded test roster
    lda cr_mflags + 6
    sta tc_cnt
    ora #CF_UNDEAD
    sta cr_mflags + 6
    lda #23
    ldy #12
    jsr tst_spawn_t5
    lda #MSF2_SUMMON_UNDEAD
    sta cr_spell_flags2 + 5
    lda #1
    sta cr_spell_chance + 5
    jsr monster_pick_spell
    // Slot 1 must now hold an active undead creature adjacent to (23, 12)
    ldx #1
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !t5_fail+
    tay
    lda cr_mflags,y
    and #CF_UNDEAD
    beq !t5_fail+
    lda tc_cnt
    sta cr_mflags + 6
    lda #$01
    bne !t5_store+
!t5_fail:
    lda tc_cnt
    sta cr_mflags + 6
    lda #$00
!t5_store:
    sta tc_results + 4

    // ========================================================
    // Test 6: MSF2_SLOW ($08) blocked by PFLAG_FREE_ACT and
    // resisted on successful player saving throw.
    // ========================================================
    jsr tst_setup_room
    jsr tst_patch_save
    lda #23
    ldy #12
    jsr tst_spawn_t5
    lda #PFLAG_FREE_ACT
    sta player_pflags
    lda #0
    sta tst_save_mode           // Would fail save if reached
    jsr monster_cast_slow
    lda zp_eff_speed
    bne !t6_fail+
    lda #0
    sta player_pflags
    lda #1
    sta tst_save_mode           // Pass save
    jsr monster_cast_slow
    lda zp_eff_speed
    bne !t6_fail+
    jsr tst_unpatch_save
    lda #$01
    bne !t6_store+
!t6_fail:
    jsr tst_unpatch_save
    lda #$00
!t6_store:
    sta tc_results + 5

    // ========================================================
    // Test 7: MSF2_SLOW ($08) on failed save sets zp_eff_speed
    // in [-8, -4] ($f8..$fc) and extends active slow by -2.
    // ========================================================
    jsr tst_setup_room
    jsr tst_patch_save
    lda #0
    sta tst_save_mode           // Fail save
    lda #23
    ldy #12
    jsr tst_spawn_t5
    jsr monster_cast_slow
    lda zp_eff_speed
    cmp #$f8                    // -8
    bcc !t7_fail+
    cmp #$fd                    // <= -4 ($fc)
    bcs !t7_fail+
    lda #$fb                    // -5
    sta zp_eff_speed
    jsr monster_cast_slow
    jsr tst_unpatch_save
    lda zp_eff_speed
    cmp #$f9                    // -5 - 2 = -7
    bne !t7_fail_unpatched+
    lda #$01
    bne !t7_store+
!t7_fail:
    jsr tst_unpatch_save
!t7_fail_unpatched:
    lda #$00
!t7_store:
    sta tc_results + 6

    // ========================================================
    // Test 8: MSF2_DRAIN_MANA ($10) is no-op at 0 MP; with MP>0
    // drains r1 = randint(lev)/2 + 1 and heals caster 6*r1 HP.
    // ========================================================
    jsr tst_setup_room
    lda #23
    ldy #12
    jsr tst_spawn_t5
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #50
    sta (zp_ptr0),y
    lda #0
    sta zp_player_mp
    sta player_data + PL_MANA
    jsr monster_cast_drain_mana
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #50
    bne !t8_fail+

    lda #20
    sta zp_player_mp
    sta player_data + PL_MANA
    lda #10
    sta cr_level + 5
    jsr monster_cast_drain_mana
    // r1 = 20 - zp_player_mp must be in 1..6, PL_MANA synced, HP == 50 + 6*r1
    lda zp_player_mp
    cmp player_data + PL_MANA
    bne !t8_fail+
    lda #20
    sec
    sbc zp_player_mp
    beq !t8_fail+
    cmp #7
    bcs !t8_fail+
    ldx #6
    jsr math_multiply
    lda zp_math_a
    clc
    adc #50
    sta tc_cnt
    ldx zp_mon_idx
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp tc_cnt
    bne !t8_fail+
    lda #$01
    bne !t8_store+
!t8_fail:
    lda #$00
!t8_store:
    sta tc_results + 7

    // ========================================================
    // Test 9: CD_FROST ($01) Frost Bolt (4d8) deals 2x on
    // vulnerable, 1x neutral, and /4 on Frost breather.
    // ========================================================
    jsr tst_patch_dice
    lda #16
    sta tst_fixed_dice
    // Vulnerable: 16 * 2 = 32 -> HP 200 - 32 = 168
    jsr tst_setup_room
    lda #22
    ldy #12
    jsr tst_spawn_t5
    lda #CD_FROST
    sta cr_cdefense + 5
    lda #4
    ldx #8
    ldy #1
    jsr eff_bolt
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #168
    bne !t9_fail+
    // Resistant (breathes frost): 16 / 4 = 4 -> HP 200 - 4 = 196
    jsr tst_setup_room
    lda #22
    ldy #12
    jsr tst_spawn_t5
    lda #MSF_BREATH
    sta cr_spell_flags + 5
    lda #(MS_BREATH_FROST << MS_BREATH_SHIFT)
    sta cr_spell_chance + 5
    lda #4
    ldx #8
    ldy #1
    jsr eff_bolt
    jsr tst_unpatch_dice
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #196
    bne !t9_fail_unp+
    lda #$01
    bne !t9_store+
!t9_fail:
    jsr tst_unpatch_dice
!t9_fail_unp:
    lda #$00
!t9_store:
    sta tc_results + 8

    // ========================================================
    // Test 10: CD_FIRE ($02) Fire Bolt (6d8) deals 2x on CD_FIRE
    // and /4 on Multi-Hued breather (MS_BREATH_ALL).
    // ========================================================
    jsr tst_patch_dice
    lda #20
    sta tst_fixed_dice
    jsr tst_setup_room
    lda #22
    ldy #12
    jsr tst_spawn_t5
    lda #CD_FIRE
    sta cr_cdefense + 5
    lda #6
    ldx #8
    ldy #1
    jsr eff_bolt
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #160                    // 200 - 40
    bne !t10_fail+
    jsr tst_setup_room
    lda #22
    ldy #12
    jsr tst_spawn_t5
    lda #MSF_BREATH
    sta cr_spell_flags + 5
    lda #(MS_BREATH_ALL << MS_BREATH_SHIFT)
    sta cr_spell_chance + 5
    lda #6
    ldx #8
    ldy #1
    jsr eff_bolt
    jsr tst_unpatch_dice
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #195                    // 200 - (20 / 4)
    bne !t10_fail_unp+
    lda #$01
    bne !t10_store+
!t10_fail:
    jsr tst_unpatch_dice
!t10_fail_unp:
    lda #$00
!t10_store:
    sta tc_results + 9

    // ========================================================
    // Test 11: CD_POISON ($04) Stinking Cloud (eff_ball 9)
    // deals 18 on CD_POISON and 2 (9/4) on Gas breather.
    // ========================================================
    jsr tst_setup_room
    lda #21
    ldy #12
    jsr tst_spawn_t5
    lda #CD_POISON
    sta cr_cdefense + 5
    lda #9
    jsr eff_ball
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #182                    // 200 - 18
    bne !t11_fail+
    jsr tst_setup_room
    lda #21
    ldy #12
    jsr tst_spawn_t5
    lda #MSF_BREATH
    sta cr_spell_flags + 5
    lda #(MS_BREATH_GAS << MS_BREATH_SHIFT)
    sta cr_spell_chance + 5
    lda #9
    jsr eff_ball
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #198                    // 200 - 2
    bne !t11_fail+
    lda #$01
    bne !t11_store+
!t11_fail:
    lda #$00
!t11_store:
    sta tc_results + 10

    // ========================================================
    // Test 12: CD_ACID ($08) Acid Ball (eff_ball 40) deals 80
    // on CD_ACID and 10 (40/4) on Acid breather.
    // ========================================================
    jsr tst_setup_room
    lda #21
    ldy #12
    jsr tst_spawn_t5
    lda #CD_ACID
    sta cr_cdefense + 5
    lda #40
    jsr eff_ball
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #120                    // 200 - 80
    bne !t12_fail+
    jsr tst_setup_room
    lda #21
    ldy #12
    jsr tst_spawn_t5
    lda #MSF_BREATH
    sta cr_spell_flags + 5
    lda #(MS_BREATH_ACID << MS_BREATH_SHIFT)
    sta cr_spell_chance + 5
    lda #40
    jsr eff_ball
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #190                    // 200 - 10
    bne !t12_fail+
    lda #$01
    bne !t12_store+
!t12_fail:
    lda #$00
!t12_store:
    sta tc_results + 11

    // ========================================================
    // Test 13: CD_LIGHT ($10) Lightning Ball (eff_ball 24)
    // deals 48 on CD_LIGHT and 6 (24/4) on Lightning breather.
    // ========================================================
    jsr tst_setup_room
    lda #21
    ldy #12
    jsr tst_spawn_t5
    lda #CD_LIGHT
    sta cr_cdefense + 5
    lda #24
    jsr eff_ball
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #152                    // 200 - 48
    bne !t13_fail+
    jsr tst_setup_room
    lda #21
    ldy #12
    jsr tst_spawn_t5
    lda #MSF_BREATH
    sta cr_spell_flags + 5
    lda #(MS_BREATH_LIGHTNING << MS_BREATH_SHIFT)
    sta cr_spell_chance + 5
    lda #24
    jsr eff_ball
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #194                    // 200 - 6
    bne !t13_fail+
    lda #$01
    bne !t13_store+
!t13_fail:
    lda #$00
!t13_store:
    sta tc_results + 12

    // ========================================================
    // Test 14: CD_LIGHT ($10) eff_light_room deals 2d8 (2..16)
    // and wakes sleeping CD_LIGHT monster, leaving non-CD_LIGHT
    // monster unharmed and asleep.
    // ========================================================
    jsr tst_setup_room
    // Slot 0: type 5 with CD_LIGHT at (24, 12), sleeping
    lda #24
    ldy #12
    jsr tst_spawn_t5
    lda #CD_LIGHT
    sta cr_cdefense + 5
    lda #20
    ldx #0
    jsr monster_apply_sleep
    // Slot 1: type 4 without CD_LIGHT at (25, 12), HP=50, sleeping
    lda #0
    sta cr_cdefense + 4
    lda #25
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #4
    jsr monster_spawn_one
    ldx #1
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #50
    sta (zp_ptr0),y
    iny
    lda #0
    sta (zp_ptr0),y
    lda #20
    ldx #1
    jsr monster_apply_sleep

    jsr eff_light_room

    // Slot 0 took 2..16 dmg (HP in [184..198]) and woke up (MX_SLEEP_CUR == 0)
    ldx #0
    jsr monster_get_ptr
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    bne !t14_fail+
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #184
    bcc !t14_fail+
    cmp #199
    bcs !t14_fail+
    // Slot 1 still HP 50 and asleep
    ldx #1
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #50
    bne !t14_fail+
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    beq !t14_fail+
    lda #$01
    bne !t14_store+
!t14_fail:
    lda #$00
!t14_store:
    sta tc_results + 13

    // ========================================================
    // Test 15: CD_STONE ($20) eff_wall_to_mud along open ray
    // deals 100 damage + wakes CD_STONE monster; non-CD_STONE
    // monster takes 0 damage.
    // ========================================================
    jsr tst_setup_room
    lda #23
    ldy #12
    jsr tst_spawn_t5
    lda #CD_STONE
    sta cr_cdefense + 5
    lda #15
    ldx #0
    jsr monster_apply_sleep
    jsr eff_wall_to_mud
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #100                    // 200 - 100
    bne !t15_fail+
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    bne !t15_fail+
    // Non-CD_STONE monster takes 0 damage
    lda #0
    sta cr_cdefense + 5
    jsr eff_wall_to_mud
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    cmp #100
    bne !t15_fail+
    lda #$01
    bne !t15_store+
!t15_fail:
    lda #$00
!t15_store:
    sta tc_results + 14

    // ========================================================
    // Test 16: CD_STONE ($20) phased monster inside adjacent
    // wall tile: wall dug to floor AND monster killed (HP 80).
    // ========================================================
    jsr tst_setup_room
    lda #21
    ldy #12
    jsr tst_spawn_t5
    lda #CD_STONE
    sta cr_cdefense + 5
    ldx #0
    jsr monster_get_ptr
    ldy #MX_HP_LO
    lda #80
    sta (zp_ptr0),y
    // Put a wall at (21, 12) where the phased CD_STONE monster stands
    ldx #12
    jsr map_row_ptr0_x
    ldy #21
    lda #TILE_WALL_V | FLAG_OCCUPIED
    sta (zp_ptr0),y
    jsr eff_wall_to_mud
    // Wall became floor and monster was slain
    ldx #12
    jsr map_row_ptr0_x
    ldy #21
    lda (zp_ptr0),y
    and #TILE_TYPE_MASK
    bne !t16_fail+
    lda #21
    ldy #12
    jsr monster_find_at
    bcs !t16_fail+
    lda #$01
    bne !t16_store+
!t16_fail:
    lda #$00
!t16_store:
    sta tc_results + 15

    // ========================================================
    // Test 17: CD_NO_SLEEP ($40) immune to pmx_try_sleep_monster
    // even at cr_level = 1 (where non-immune always sleeps).
    // ========================================================
    jsr tst_setup_room
    lda #22
    ldy #12
    jsr tst_spawn_t5
    lda #1
    sta cr_level + 5
    lda #CD_NO_SLEEP
    sta cr_cdefense + 5
    ldx #0
    jsr pmx_try_sleep_monster
    bcs !t17_fail+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    bne !t17_fail+
    // Clear CD_NO_SLEEP -> now sleeps
    lda #0
    sta cr_cdefense + 5
    ldx #0
    jsr pmx_try_sleep_monster
    bcc !t17_fail+
    lda #$01
    bne !t17_store+
!t17_fail:
    lda #$00
!t17_store:
    sta tc_results + 16

    // ========================================================
    // Test 18: CD_NO_SLEEP ($40) immune to Confuse spell
    // (pmx_confuse_monster_dir_msg), Page 1 sleep (ep1_sleep_slot),
    // and Page 1 Wand of Confuse Monster (ep1_wand_confuse).
    // ========================================================
    jsr tst_setup_room
    lda #22
    ldy #12
    jsr tst_spawn_t5
    lda #CD_NO_SLEEP
    sta cr_cdefense + 5
    jsr pmx_confuse_monster_dir_msg
    ldx #0
    jsr ep1_sleep_slot
    jsr ep1_wand_confuse
    ldx #0
    jsr monster_get_ptr
    ldy #MX_CONFUSE
    lda (zp_ptr0),y
    bne !t18_fail+
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    bne !t18_fail+
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    and #MF_CONFUSED
    bne !t18_fail+
    lda #$01
    bne !t18_store+
!t18_fail:
    lda #$00
!t18_store:
    sta tc_results + 17

    // ========================================================
    // Test 19: CD_NO_SLEEP ($40) immune to Monster Confusion
    // scroll melee hit (zp_confuse_melee cleared, MX_CONFUSE=0).
    // ========================================================
    jsr tst_setup_room
    lda #21
    ldy #12
    jsr tst_spawn_t5
    lda #CD_NO_SLEEP
    sta cr_cdefense + 5
    :PatchJump(combat_roll_tohit, tst_always_hit)
    lda #1
    sta zp_confuse_melee
    lda #21
    ldy #12
    jsr player_attack_monster
    lda zp_confuse_melee
    bne !t19_fail+
    ldx #0
    jsr monster_get_ptr
    ldy #MX_CONFUSE
    lda (zp_ptr0),y
    bne !t19_fail+
    lda #$01
    bne !t19_store+
!t19_fail:
    lda #$00
!t19_store:
    sta tc_results + 18

    // ========================================================
    // Test 20: Flame Tongue (FT), Frost Brand (FB), and Fire
    // Ammo ego 1.5x slay against CD_FIRE / CD_FROST (+ 2d4).
    // ========================================================
    jsr tst_patch_dice
    lda #5
    sta tst_fixed_dice
    lda #5
    sta cmb_type
    // FT vs neutral: 20 + 5 = 25
    lda #0
    sta cr_cdefense + 5
    lda #20
    sta cmb_damage
    lda #EGO_FLAME_TONGUE
    jsr ego_apply_damage
    lda cmb_damage
    cmp #25
    bne !t20_fail+
    // FT vs CD_FIRE: trunc(20 * 1.5) + 5 = 35
    lda #CD_FIRE
    sta cr_cdefense + 5
    lda #20
    sta cmb_damage
    lda #EGO_FLAME_TONGUE
    jsr ego_apply_damage
    lda cmb_damage
    cmp #35
    bne !t20_fail+
    // EGO_AMMO_FIRE vs CD_FIRE: 35
    lda #20
    sta cmb_damage
    lda #EGO_AMMO_FIRE
    jsr ego_apply_damage
    lda cmb_damage
    cmp #35
    bne !t20_fail+
    // FB vs CD_FIRE (wrong element): 25; FB vs CD_FROST: 35
    lda #20
    sta cmb_damage
    lda #EGO_FROST_BRAND
    jsr ego_apply_damage
    lda cmb_damage
    cmp #25
    bne !t20_fail+
    lda #CD_FROST
    sta cr_cdefense + 5
    lda #20
    sta cmb_damage
    lda #EGO_FROST_BRAND
    jsr ego_apply_damage
    jsr tst_unpatch_dice
    lda cmb_damage
    cmp #35
    bne !t20_fail_unp+
    lda #$01
    bne !t20_store+
!t20_fail:
    jsr tst_unpatch_dice
!t20_fail_unp:
    lda #$00
!t20_store:
    sta tc_results + 19

    // ========================================================
    // Test 21: MSF_SUMMON at DL2 summons from levels 1-4 (VMS summon_monster:
    // dun_level + mon$summon_adj). The embedded roster has 14 creatures of
    // levels 1-2, 10 of levels 3-4 and 2 of level 5: 24 casts must summon
    // some of levels 3-4 and none of level 5. Before the fix the summons
    // came from levels 1-2 only.
    // ========================================================
    jsr tst_summon_reset
!t21_loop:
    jsr tst_setup_room          // a clean room (no FLAG_OCCUPIED left)
    lda #2
    sta zp_player_dlvl
    lda #23
    ldy #12
    jsr tst_spawn_t5            // the caster in slot 0 (level 10)
    lda #MSF_SUMMON
    sta cr_spell_flags + 5
    lda #1
    sta cr_spell_chance + 5
    jsr monster_pick_spell
    ldx #1                      // the summoned creature
    jsr tst_tally_levels
    dec tc_loop
    bne !t21_loop-
    jsr tst_summon_verdict
    sta tc_results + 20

    // ========================================================
    // Test 22: the Staff of Summoning (ep1_summon_many) at DL2 also summons
    // from levels 1-4, 24 uses.
    // ========================================================
    jsr tst_summon_reset
!t22_loop:
    jsr tst_setup_room
    lda #2
    sta zp_player_dlvl
    jsr ep1_summon_many
    ldx #0
    jsr tst_tally_levels
    dec tc_loop
    bne !t22_loop-
    jsr tst_summon_verdict
    sta tc_results + 21

    // ========================================================
    // Test 23: Scroll of Summon Monster summons randint(3) = 1-3 (VMS
    // scrolls.inc 7); 40 reads see one and more, never 0 or 4+. Before the
    // fix it summoned exactly one.
    // ========================================================
    jsr tst_hist_reset
!t23_loop:
    jsr tst_setup_room
    jsr ep1_summon_one
    jsr tst_hist_add
    dec tc_loop
    bne !t23_loop-
    lda tc_hist + 0
    ora tc_hist + 4
    ora tc_hist + 5
    bne !t23_fail+
    lda tc_hist + 1
    beq !t23_fail+
    lda tc_hist + 2
    ora tc_hist + 3
    beq !t23_fail+
    lda #$01
    .byte $2c
!t23_fail:
    lda #$00
    sta tc_results + 22

    // ========================================================
    // Test 24: Staff of Summoning summons randint(4) = 1-4 (VMS staffs.inc
    // 8); 40 uses see one and four, never 0 or 5. Before: 2-4.
    // ========================================================
    jsr tst_hist_reset
!t24_loop:
    jsr tst_setup_room
    jsr ep1_summon_many
    jsr tst_hist_add
    dec tc_loop
    bne !t24_loop-
    lda tc_hist + 0
    ora tc_hist + 5
    bne !t24_fail+
    lda tc_hist + 1
    beq !t24_fail+
    lda tc_hist + 4
    beq !t24_fail+
    lda #$01
    .byte $2c
!t24_fail:
    lda #$00
    sta tc_results + 23

    // ========================================================
    // Test 25: Scroll of Summon Undead summons randint(3) = 1-3 undead of any
    // level (VMS scrolls.inc 36, misc.inc summon_undead). At DL1 with two
    // undead in the roster, type 1 (level 1) and type 13 (level 3), 40 reads
    // see one and three summoned and the level-3 undead. Before: always two,
    // picked from DL1's mix (type 1 only).
    // ========================================================
    lda cr_mflags + 1
    pha
    ora #CF_UNDEAD
    sta cr_mflags + 1
    jsr tst_hist_reset
!t25_loop:
    jsr tst_setup_room
    lda #1
    sta zp_player_dlvl
    jsr ep1_summon_undead
    jsr tst_hist_add
    ldx #MAX_MONSTERS - 1
!t25_scan:
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #13
    bne !t25_next+
    inc tc_seen_a
!t25_next:
    dex
    bpl !t25_scan-
    dec tc_loop
    bne !t25_loop-
    pla
    sta cr_mflags + 1
    lda tc_hist + 0
    ora tc_hist + 4
    ora tc_hist + 5
    bne !t25_fail+
    lda tc_hist + 1
    beq !t25_fail+
    lda tc_hist + 3
    beq !t25_fail+
    lda tc_seen_a
    beq !t25_fail+
    lda #$01
    .byte $2c
!t25_fail:
    lda #$00
    sta tc_results + 24

    // ========================================================
    // Test 26: a monster's summons land beside the player, awake (VMS
    // creature.inc 14: summon_monster(char_row, char_col, false)); a scroll's
    // are awake too. The caster stands three squares east of the player.
    // Before: beside the caster, asleep.
    // ========================================================
    jsr tst_setup_room
    lda #23
    ldy #12
    jsr tst_spawn_t5
    lda #MSF_SUMMON
    sta cr_spell_flags + 5
    lda #1
    sta cr_spell_chance + 5
    jsr monster_pick_spell
    ldx #1
    jsr tst_slot_awake
    beq !t26_fail+
    ldy #MX_SLEEP_CUR
    lda (zp_ptr0),y
    bne !t26_fail+
    ldy #MX_X
    lda (zp_ptr0),y
    sec
    sbc zp_player_x
    clc
    adc #1
    cmp #3                      // |dx| <= 1
    bcs !t26_fail+
    ldy #MX_Y
    lda (zp_ptr0),y
    sec
    sbc zp_player_y
    clc
    adc #1
    cmp #3                      // |dy| <= 1
    bcs !t26_fail+
    jsr tst_setup_room
    jsr ep1_summon_one
    ldx #0
    jsr tst_slot_awake
    beq !t26_fail+
    lda #$01
    .byte $2c
!t26_fail:
    lda #$00
    sta tc_results + 25

    // ========================================================
    // Test 27: Wand of Polymorph (VMS spells.inc poly_monster): a level-10
    // creature changes when randint(40) > 10 (about 30 of 40 zaps) into an
    // awake creature of any level, and is otherwise unaffected. Before: it
    // always changed, asleep, into a creature of at most the depth (3).
    // ========================================================
    jsr tst_hist_reset
!t27_loop:
    jsr tst_setup_room
    lda #21                     // east of the player (tst_dir_east)
    ldy #12
    jsr tst_spawn_t5
    jsr ep1_wand_polymorph
    ldx #0
    jsr tst_slot_awake
    beq !t27_same+
    inc tc_hist + 1             // changed
    ldy #MX_TYPE
    lda (zp_ptr0),y
    tax
    lda cr_level,x
    cmp #4
    bcc !t27_next+
    inc tc_seen_a               // deeper than the level
    bne !t27_next+
!t27_same:
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #5
    bne !t27_next+
    inc tc_hist + 0             // unaffected
!t27_next:
    dec tc_loop
    bne !t27_loop-
    lda tc_hist + 0
    beq !t27_fail+
    lda tc_hist + 1
    cmp #20
    bcc !t27_fail+
    lda tc_seen_a
    beq !t27_fail+
    lda #$01
    .byte $2c
!t27_fail:
    lda #$00
    sta tc_results + 26

    // ========================================================
    // Test 28: Staff of Mass Polymorph (VMS spells.inc mass_poly): every
    // creature nearer than max_sight changes, seen or not, except a win
    // creature; one 25 squares off stays. Slot 0: unseen at distance 5;
    // slot 1: level 100 at distance 2; slot 2: seen at distance 25.
    // Before: only the seen one changed.
    // ========================================================
    jsr tst_setup_room
    lda cr_level + 6
    pha
    lda #100
    sta cr_level + 6
    lda #25
    ldy #12
    jsr tst_spawn_t5
    lda #22
    sta ms_spawn_x
    lda #12
    sta ms_spawn_y
    lda #6
    jsr monster_spawn_one
    lda #45
    ldy #12
    jsr tst_spawn_t5
    ldy #MX_FLAGS
    lda #MF_VISIBLE
    sta (zp_ptr0),y
    jsr ep1_mass_polymorph
    pla
    sta cr_level + 6
    ldx #0
    jsr tst_slot_awake
    beq !t28_fail+              // the unseen one changed
    ldx #1
    jsr tst_slot_awake
    bne !t28_fail+
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #6
    bne !t28_fail+              // the win creature stayed
    ldx #2
    jsr tst_slot_awake
    bne !t28_fail+
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #5
    bne !t28_fail+              // the far one stayed
    lda #$01
    .byte $2c
!t28_fail:
    lda #$00
    sta tc_results + 27

    jmp test_exit_trampoline

.assert "Test body fits below MAP_BASE", * <= MAP_BASE, true
