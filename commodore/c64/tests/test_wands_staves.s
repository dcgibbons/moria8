// test_wands_staves.s — Runtime tests for Step 7.7
//
// Tests: Wand/Staff generation, charges, aiming, using.
//
// Results at $0400-$041f: $01 = pass, $00 = fail per test

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_bootstrap)

.pc = $080E "Test Code"
test_bootstrap:
    :BankOutBasic()
    jmp test_start
test_exit_trampoline:
    ldx #6
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
#import "../../common/ui_help.s"
#import "../../common/ui_trampoline_stubs.s"
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
#import "../../common/player_magic.s"
#import "../../common/ui_inventory.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
#import "../../common/store_data.s"
#import "../../common/store.s"
#import "../../common/ui_store.s"

// Strings referenced by imported modules checking main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Test result buffer
tc_results: .fill 32, $ff
tc_loop_ctr: .byte 0

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
    sta zp_temp0                // Wand count
    sta zp_temp1                // Staff count
    sta tc_loop_ctr             // Loop counter

!t1_loop:
    lda #10                     // Deep enough dlvl to allow all items
    sta zp_player_dlvl
    jsr pick_item_type          // Returns type in A. Clobbers X, Y!
    sta zp_temp2

    // Check wand (39-42)
    cmp #39
    bcc !t1_not_wand+
    cmp #43
    bcs !t1_not_wand+
    inc zp_temp0
!t1_not_wand:

    // Check staff (43-46)
    lda zp_temp2
    cmp #43
    bcc !t1_not_staff+
    cmp #47
    bcs !t1_not_staff+
    inc zp_temp1
!t1_not_staff:

    inc tc_loop_ctr
    bne !t1_loop-               // Loop 256 times

    // Verify we found some
    lda zp_temp0
    beq !t1_fail+
    lda zp_temp1
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
    lda #39                     // Wand of Light
    jsr roll_enchantment        // Returns charges in A
    cmp #0
    beq !t2_fail+               // Should have charges
    cmp #50
    bcs !t2_fail+               // Should be reasonable (10-15)

    lda #40                     // Wand of Lightning
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
    lda #43                     // Staff of Light
    jsr roll_enchantment
    cmp #0
    beq !t3_fail+

    lda #46                     // Staff of CLW
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
    lda #39
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
    ldx #39
    lda id_known,x
    cmp #1
    bne !t4_fail+

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
    lda #39
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
    lda #43
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
    ldx #43
    lda id_known,x
    cmp #1
    bne !t6_fail+

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
    lda #43
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
    jmp !finish+
!t7_fail:
    lda #$00
    sta tc_results + 6

!finish:
    jmp test_exit_trampoline
