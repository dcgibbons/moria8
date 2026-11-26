// test_wands_staves.s — Runtime tests for Step 7.7
//
// Tests: Wand/Staff generation, charges, aiming, using, Wand of Lightning
// bolt dice.
//
// Results at $0400-$041f: $01 = pass, $00 = fail per test

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

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

.segmentdef TestUnused [start=$E100, min=$E100, max=$FFF9]
.segmentdef TestCreateOverlay [start=$D000, min=$D000, max=$DFFF]
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
.segment TestUnused
#import "../../../../core/6502/ui_status.s"
.segment Default
#import "../../../../core/6502/ui_help_clear.s"
#import "../../../../core/6502/ui_character.s"
.segment TestUnused
#import "../../../../core/6502/ui_help.s"
.segment Default
#import "../../../../core/6502/ui_trampoline_stubs.s"
#import "../../../../core/6502/stat_display.s"
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
.segment TestUnused
#import "../../../../core/6502/monster_ai.s"
.segment Default
#import "../../../../core/6502/recall.s"
.segment TestCreateOverlay
#import "../../../../core/6502/monster_magic.s"
.segment Default
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
#import "../../../../core/6502/item.s"
#import "item_cat_resident_helper.s"
#import "../../../../core/6502/special_rooms.s"
#import "../../../../core/6502/ego_items.s"
#import "../../../../core/6502/special_rooms_stubs.s"
#import "../../../../core/6502/player_items.s"
#import "../../../../core/6502/spell_data.s"
#import "../../../../core/6502/projectile.s"
#import "../../../../core/6502/spell_effects.s"
#import "../../../../core/6502/player_magic_state.s"
#import "../../../../core/6502/player_magic_state_ops.s"
#import "../../../../core/6502/player_magic.s"
#import "../../../../core/6502/ui_inventory.s"
#import "../../../../core/6502/ui_equipment.s"
#import "../../../../core/6502/dungeon_los.s"
#import "../../../../core/6502/player_move.s"
#import "../../../../core/6502/combat.s"
.segment TestUnused
#import "../../../../core/6502/scene_mat_tile.s"
.segment Default
#import "../../../../core/6502/monster_attack.s"
.segment TestCreateOverlay
#import "../../../../core/6502/turn.s"
.segment Default
#import "../../../../core/6502/store_data.s"
.segment TestCreateOverlay
#import "../../../../core/6502/store.s"
.segment Default
.segment TestUnused
#import "../../../../core/6502/ui_store.s"
.segment Default

// Strings referenced by imported modules checking main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test result buffer
tc_results: .fill 32, $ff
tc_loop_ctr: .byte 0
tws_wand_count: .byte 0
tws_staff_count: .byte 0

// Captured eff_bolt arguments for Test 8.
tws_bolt_calls: .byte 0
tws_bolt_dice:  .byte 0
tws_bolt_sides: .byte 0
tws_bolt_bonus: .byte 0

// test_eff_bolt_capture — replaces eff_bolt for Test 8: records the
// A=dice, X=sides, Y=bonus arguments without prompting for a direction.
test_eff_bolt_capture:
    sta tws_bolt_dice
    stx tws_bolt_sides
    sty tws_bolt_bonus
    inc tws_bolt_calls
    rts

test_start:
    // Initialize result area
    ldx #31
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    // Seed RNG
    lda #$12
    sta zp_rng_0
    lda #$34
    sta zp_rng_1
    lda #$56
    sta zp_rng_2
    lda #$78
    sta zp_rng_3

    // Init systems
    jsr msg_init
    jsr item_init_identification

    // ==========================================
    // Test 1: pick_item_type generates wands/staves
    // ==========================================
    // Run loop 256 times (enough to find both)
    lda #0
    sta tws_wand_count          // pick_item_type uses zp_temp0-3 as scratch
    sta tws_staff_count
    sta tc_loop_ctr             // Loop counter

!t1_loop:
    lda #10                     // Deep enough dlvl to allow all items
    sta zp_player_dlvl
    jsr pick_item_type          // Returns slot in A (page in item_cur_page). Clobbers X, Y!
    jsr item_get_category_a     // Paged catalog: wands/staves are found by category
    cmp #ICAT_WAND
    bne !t1_not_wand+
    inc tws_wand_count
    jmp !t1_next+
!t1_not_wand:
    cmp #ICAT_STAFF
    bne !t1_next+
    inc tws_staff_count
!t1_next:

    inc tc_loop_ctr
    bne !t1_loop-               // Loop 256 times

    // Verify we found some
    lda tws_wand_count
    beq !t1_fail+
    lda tws_staff_count
    beq !t1_fail+

    lda #$01
    sta tc_results + 0
    jmp !t2+
!t1_fail:
    lda #$00
    sta tc_results + 0

    // ==========================================
    // Test 2: roll_enchantment gives charges for wands
    // ==========================================
!t2:
    lda #ITEM_SLOT_WAND_OF_LIGHT                     // Wand of Light
    jsr roll_enchantment        // Returns charges in A
    cmp #0
    beq !t2_fail+               // Should have charges
    cmp #50
    bcs !t2_fail+               // Should be reasonable (10-15)

    lda #ITEM_SLOT_WAND_OF_LIGHTNING                     // Wand of Lightning
    jsr roll_enchantment
    cmp #0
    beq !t2_fail+

    lda #$01
    sta tc_results + 1
    jmp !t3+
!t2_fail:
    lda #$00
    sta tc_results + 1

    // ==========================================
    // Test 3: roll_enchantment gives charges for staves
    // ==========================================
!t3:
    lda #ITEM_SLOT_STAFF_OF_LIGHT                     // Staff of Light
    jsr roll_enchantment
    cmp #0
    beq !t3_fail+

    lda #ITEM_SLOT_STAFF_OF_CURE_LIGHT_WOUNDS                     // Staff of CLW
    jsr roll_enchantment
    cmp #0
    beq !t3_fail+

    lda #$01
    sta tc_results + 2
    jmp !t4+
!t3_fail:
    lda #$00
    sta tc_results + 2

    // ==========================================
    // Test 4: item_aim_wand (Wand of Light)
    // ==========================================
!t4:
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags

    // Add Wand of Light (39) to slot 0 with 5 charges
    lda #ITEM_SLOT_WAND_OF_LIGHT
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #5
    sta inv_p1                  // 5 charges
    lda #0
    sta inv_flags

    // Stuff input: 'A' ($41) + space for -more- after effect message
    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_aim_wand
    bcc !t4_fail+               // Should consume turn

    // Check charges decremented to 4
    lda inv_p1
    cmp #4
    bne !t4_fail+

    // Check id_known set
    ldx #ITEM_SLOT_WAND_OF_LIGHT
    jsr id_known_test
    beq !t4_fail+

    lda #$01
    sta tc_results + 3
    jmp !t5+
!t4_fail:
    lda #$00
    sta tc_results + 3

    // ==========================================
    // Test 5: item_aim_wand empty
    // ==========================================
!t5:
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags

    // Wand of Light with 0 charges
    lda #ITEM_SLOT_WAND_OF_LIGHT
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1                  // 0 charges

    // Stuff input: 'A' + space for -more- after "NO CHARGES" message
    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_aim_wand
    bcs !t5_fail+               // Should NOT consume turn

    // Check message "NO CHARGES LEFT" (implicit check via logic flow)
    // Effectively if carry clear, it worked as expected for empty wand

    lda #$01
    sta tc_results + 4
    jmp !t6+
!t5_fail:
    lda #$00
    sta tc_results + 4

    // ==========================================
    // Test 6: item_use_staff (Staff of Light)
    // ==========================================
!t6:
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags

    // Add Staff of Light (43) to slot 0 with 5 charges
    lda #ITEM_SLOT_STAFF_OF_LIGHT
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #5
    sta inv_p1
    lda #0
    sta inv_flags

    // Stuff input: 'A' + space for -more- after effect message
    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_use_staff
    bcc !t6_fail+               // Should consume turn

    // Check charges decremented to 4
    lda inv_p1
    cmp #4
    bne !t6_fail+

    // Check id_known
    ldx #ITEM_SLOT_STAFF_OF_LIGHT
    jsr id_known_test
    beq !t6_fail+

    lda #$01
    sta tc_results + 5
    jmp !t7+
!t6_fail:
    lda #$00
    sta tc_results + 5

    // ==========================================
    // Test 7: item_use_staff empty
    // ==========================================
!t7:
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags

    // Staff with 0 charges
    lda #ITEM_SLOT_STAFF_OF_LIGHT
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1

    // Stuff input: 'A' + space for -more- after "NO CHARGES" message
    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_use_staff
    bcs !t7_fail+               // Should NOT consume turn

    lda #$01
    sta tc_results + 6
    jmp !t8+
!t7_fail:
    lda #$00
    sta tc_results + 6

    // ==========================================
    // Test 8: item_aim_wand (Wand of Lightning) fires a 3d8 bolt
    // ==========================================
    // Oracle: VMS Moria wands.inc (rev adce6c88) Lightning Bolt wand
    // fire_bolt(..., damroll('3d8'), ...). eff_bolt is replaced with a
    // capture stub so the production item_aim_wand dispatch is checked
    // without a direction prompt.
!t8:
    jsr item_init_inventory
    lda #0
    sta zp_msg_flags
    sta tws_bolt_calls
    sta tws_bolt_dice
    sta tws_bolt_sides
    lda #$ff
    sta tws_bolt_bonus

    lda #$4c                    // JMP test_eff_bolt_capture
    sta eff_bolt
    lda #<test_eff_bolt_capture
    sta eff_bolt + 1
    lda #>test_eff_bolt_capture
    sta eff_bolt + 2

    // Wand of Lightning (40) in slot 0 with 5 charges
    lda #ITEM_SLOT_WAND_OF_LIGHTNING
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #5
    sta inv_p1
    lda #0
    sta inv_flags

    // Stuff input: 'A' + space for -more- after effect message
    lda #2
    sta $c6
    lda #$41
    sta $0277
    lda #$20
    sta $0278

    jsr item_aim_wand
    bcc !t8_fail+               // Should consume turn

    lda tws_bolt_calls
    cmp #1
    bne !t8_fail+
    lda tws_bolt_dice
    cmp #3
    bne !t8_fail+
    lda tws_bolt_sides
    cmp #8
    bne !t8_fail+
    lda tws_bolt_bonus
    bne !t8_fail+

    // Charges decremented to 4
    lda inv_p1
    cmp #4
    bne !t8_fail+

    lda #$01
    sta tc_results + 7
    jmp !finish+
!t8_fail:
    lda #$00
    sta tc_results + 7

!finish:
    jmp test_exit_trampoline

// dungeon_render.s lives in TestCreateOverlay ($D000+) so the test body stays
// below MAP_BASE; it must come after dungeon_data.s defines MAP_COLS.
.segment TestCreateOverlay
#import "../dungeon_render.s"
.segment Default
