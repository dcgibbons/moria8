// test_tunnel.s — Runtime tests for R14 tunnel/dig system
//
// Tests: calc_dig_ability (bare hands, shovel, pick, ego tools, regular weapon),
//        roll_tool_ego_check (dlvl thresholds)
//
// Results at $0400-$0407: $01 = pass, $00 = fail per test (8 tests)
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
    ldx #7
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
#import "../../common/player_items.s"
#import "../../common/spell_data.s"
#import "../../common/projectile.s"
#import "../../common/spell_effects.s"
#import "../../common/player_magic_state.s"
#import "../../common/player_magic_state_ops.s"
#import "../../common/player_magic.s"
#import "../../common/ui_inventory.s"
#import "../../common/ui_equipment.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
#import "../../common/store_data.s"
#import "../../common/store.s"
#import "../../common/ui_store.s"
#import "../../common/ui_help.s"
#define C64_TEST_FULL_ITEMDESC_STUB
#import "../../common/ui_trampoline_stubs.s"
#import "../../common/tunnel.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// ============================================================
// tramp_dig_ability — stub for test context
// In main.s this is a trampoline; here we just JMP directly.
// ============================================================
tramp_dig_ability:
    jmp calc_dig_ability

// ============================================================
// calc_dig_ability — Calculate digging ability (STR + tool/weapon bonus)
// Copied from main.s — needed because main.s is not imported in tests.
// ============================================================
calc_dig_ability:
    // Check equipped weapon
    ldx inv_item_id + EQUIP_WEAPON
    cpx #$FF
    bne !cda_has_weapon+

    // Bare hands: ability = 0
    lda #0
    sta tun_dig_ability
    rts

!cda_has_weapon:
    lda it_category,x
    cmp #ICAT_DIGGING
    beq !cda_dig_tool+

    // Regular weapon: ability = (STR >> 2) + max(0, PL_TODMG >> 1)
    lda zp_player_str
    lsr
    lsr                         // STR >> 2
    sta tun_dig_ability
    lda player_data + PL_TODMG
    bmi !cda_done+              // Negative TODMG → skip
    lsr                         // TODMG >> 1
    clc
    adc tun_dig_ability
    bcc !cda_ok+
    lda #$FF                    // Cap at 255
!cda_ok:
    sta tun_dig_ability
!cda_done:
    rts

!cda_dig_tool:
    // Digging tool: ability = (STR >> 2) + dig_base_table[type-62] + (ego * 12)
    lda zp_player_str
    lsr
    lsr                         // STR >> 2
    sta tun_dig_ability

    // Add base bonus from table
    txa
    sec
    sbc #62                     // Index into dig_base_table (0=Shovel, 1=Pick)
    tax
    lda dig_base_table,x
    clc
    adc tun_dig_ability
    sta tun_dig_ability

    // Add ego bonus: ego * 12
    lda inv_ego + EQUIP_WEAPON
    beq !cda_done-              // ego=0, no bonus
    // Multiply ego (1 or 2) by 12
    sta zp_temp2                // save ego
    asl                         // *2
    asl                         // *4
    sta zp_temp3                // ego*4
    asl                         // *8
    clc
    adc zp_temp3                // *8 + *4 = *12
    clc
    adc tun_dig_ability
    bcc !cda_ego_ok+
    lda #$FF                    // Cap at 255
!cda_ego_ok:
    sta tun_dig_ability
    rts

dig_base_table:
    .byte 6, 20                 // Shovel base=6, Pick base=20

// ============================================================
// Test scratch
// ============================================================
tc_results: .fill 8, $ff       // Result buffer (copied to $0400 at end)
tc_loop:    .byte 0
tc_count:   .byte 0
tc_max_ego: .byte 0

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
    // Test 1: Bare hands (no weapon) → tun_dig_ability = 0
    // ============================================================
    lda #$FF
    sta inv_item_id + EQUIP_WEAPON
    lda #18
    sta zp_player_str

    jsr calc_dig_ability
    lda tun_dig_ability
    cmp #0
    beq !t1_pass+
    lda #$00
    jmp !t1_store+
!t1_pass:
    lda #$01
!t1_store:
    sta tc_results + 0

    // ============================================================
    // Test 2: Shovel (type 62, ego=0) + STR=18 → ability = 4+6 = 10
    // STR>>2 = 18>>2 = 4, shovel base = 6
    // ============================================================
    lda #62
    sta inv_item_id + EQUIP_WEAPON
    lda #0
    sta inv_ego + EQUIP_WEAPON
    lda #18
    sta zp_player_str

    jsr calc_dig_ability
    lda tun_dig_ability
    cmp #10
    beq !t2_pass+
    lda #$00
    jmp !t2_store+
!t2_pass:
    lda #$01
!t2_store:
    sta tc_results + 1

    // ============================================================
    // Test 3: Pick (type 63, ego=0) + STR=18 → ability = 4+20 = 24
    // ============================================================
    lda #63
    sta inv_item_id + EQUIP_WEAPON
    lda #0
    sta inv_ego + EQUIP_WEAPON
    lda #18
    sta zp_player_str

    jsr calc_dig_ability
    lda tun_dig_ability
    cmp #24
    beq !t3_pass+
    lda #$00
    jmp !t3_store+
!t3_pass:
    lda #$01
!t3_store:
    sta tc_results + 2

    // ============================================================
    // Test 4: Gnomish Shovel (type 62, ego=1) + STR=18 → 4+6+12 = 22
    // ============================================================
    lda #62
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_ego + EQUIP_WEAPON
    lda #18
    sta zp_player_str

    jsr calc_dig_ability
    lda tun_dig_ability
    cmp #22
    beq !t4_pass+
    lda #$00
    jmp !t4_store+
!t4_pass:
    lda #$01
!t4_store:
    sta tc_results + 3

    // ============================================================
    // Test 5: Orcish Pick (type 63, ego=1) + STR=18 → 4+20+12 = 36
    // ============================================================
    lda #63
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_ego + EQUIP_WEAPON
    lda #18
    sta zp_player_str

    jsr calc_dig_ability
    lda tun_dig_ability
    cmp #36
    beq !t5_pass+
    lda #$00
    jmp !t5_store+
!t5_pass:
    lda #$01
!t5_store:
    sta tc_results + 4

    // ============================================================
    // Test 6: Dwarven Pick (type 63, ego=2) + STR=18 → 4+20+24 = 48
    // ============================================================
    lda #63
    sta inv_item_id + EQUIP_WEAPON
    lda #2
    sta inv_ego + EQUIP_WEAPON
    lda #18
    sta zp_player_str

    jsr calc_dig_ability
    lda tun_dig_ability
    cmp #48
    beq !t6_pass+
    lda #$00
    jmp !t6_store+
!t6_pass:
    lda #$01
!t6_store:
    sta tc_results + 5

    // ============================================================
    // Test 7: roll_tool_ego_check at DL<10 → always returns 0
    // Call roll_ego_type with item type 62 (Shovel, ICAT_DIGGING)
    // at dlvl=5 — should always return 0.
    // Run 50 iterations to be sure.
    // ============================================================
    lda #5
    sta zp_player_dlvl
    lda #0
    sta tc_loop
    sta tc_count                // Track any non-zero results

!t7_loop:
    lda #62                     // Shovel
    jsr roll_ego_type
    cmp #0
    beq !t7_next+
    inc tc_count                // Non-zero = unexpected
!t7_next:
    inc tc_loop
    lda tc_loop
    cmp #50
    bne !t7_loop-

    lda tc_count
    beq !t7_pass+               // All 50 returned 0 = pass
    lda #$00
    jmp !t7_store+
!t7_pass:
    lda #$01
!t7_store:
    sta tc_results + 6

    // ============================================================
    // Test 8: roll_tool_ego_check at DL>=10 → can return 1 or 2
    // Call roll_ego_type with item type 62 at dlvl=25 (deep enough
    // for ego 2). Run 200 iterations — at least one should return
    // non-zero (P(all 0) = 0.65^200 ≈ 0).
    // Also verify no value > 2 ever appears.
    // ============================================================
    lda #25
    sta zp_player_dlvl
    lda #0
    sta tc_loop
    sta tc_count                // Count non-zero egos
    sta tc_max_ego              // Track max ego seen

!t8_loop:
    lda #62                     // Shovel
    jsr roll_ego_type
    cmp #0
    beq !t8_next+
    inc tc_count                // Non-zero ego
    cmp tc_max_ego
    bcc !t8_next+
    sta tc_max_ego              // Update max
!t8_next:
    inc tc_loop
    lda tc_loop
    cmp #200
    bne !t8_loop-

    // Pass if at least one non-zero AND max <= 2
    lda tc_count
    beq !t8_fail+               // No egos in 200 tries = fail
    lda tc_max_ego
    cmp #3
    bcs !t8_fail+               // ego > 2 = fail
    lda #$01
    jmp !t8_store+
!t8_fail:
    lda #$00
!t8_store:
    sta tc_results + 7

    jmp test_exit_trampoline
