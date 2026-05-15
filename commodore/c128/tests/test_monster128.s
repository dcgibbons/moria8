#importonce
// test_monster128.s — C128-specific regression test for monster kill memory preservation
//
// Tests: monster_remove regression (Bug R4) where FLAG_OCCUPIED clear
// clobbered map bytes by directly reading from Bank 0.

#import "../../common/zeropage.s"
#import "../config128.s"
#import "test_helpers128.s"
#import "../memory128.s"
#import "../../common/mmu_macros.s"
#import "../../common/dungeon_data.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

// Put the dummy map row somewhere safe
test_map_row:
    .fill 80, 0

.pc = $3000 "Test Code"
.const TEST_NAME_LO_TABLE  = $8100
.const TEST_NAME_HI_TABLE  = $8120
.const TEST_NAME_STR       = $8200
.const TEST_NAME_PTR       = $e200
.const TEST_TIER2_BASE     = $8400
.const TEST2_NAME_LO_TABLE = TEST_TIER2_BASE + $0100
.const TEST2_NAME_HI_TABLE = TEST_TIER2_BASE + $0120
.const TEST2_NAME_STR      = TEST_TIER2_BASE + $0200
.const TEST2_NAME_PTR      = $e200

c128_restore_runtime_state:
    rts

tier_check_transition:
    rts

#import "../../common/monster.s"
test_start:
    sei
    cld
    ldx #$ff
    txs

    // Set MMU to Bank 1 context
    lda #MMU_ALL_RAM
    sta $ff00

    // Initialize result to fail
    lda #$00
    sta $0400

    // ==========================================
    // Setup test state
    // ==========================================
    jsr monster_init_table

    lda map_row_lo+5
    sta zp_ptr0
    lda map_row_hi+5
    sta zp_ptr0_hi
    ldy #10
    
    // Poison bank 0 
    lda #$FF                // Poison byte
    sta (zp_ptr0),y

    // Write correct byte to Bank 1 map
    lda #($08 | $01)        // FLAG_LIT | FLAG_OCCUPIED
    :MapWrite_ptr0_y()      // Properly writes to Bank 1 map array

    // Create a dummy monster in slot 0 to remove
    jsr monster_get_ptr     // Gets ptr for X=0
    ldy #MX_TYPE
    lda #1                  // Not empty
    sta (zp_ptr0),y
    ldy #MX_X
    lda #10
    sta (zp_ptr0),y
    ldy #MX_Y
    lda #5
    sta (zp_ptr0),y
    inc zp_mon_count

    // ==========================================
    // Run the routine
    // ==========================================
    ldx #0
    jsr monster_remove

    // ==========================================
    // Verify monster_remove results
    // ==========================================
    // The monster count should decrease
    lda zp_mon_count
    beq *+5
    jmp !fail+

    lda map_row_lo+5
    sta zp_ptr0
    lda map_row_hi+5
    sta zp_ptr0_hi
    ldy #10
    :MapRead_ptr0_y()
    
    cmp #$08
    beq *+5
    jmp !fail+

    // ==========================================
    // C128 creature_get_name Bank1 tier path
    // ==========================================
    // Stage tier name pointer tables and target string in Bank 1.
    jsr mmu_select_bank1
    // Tier cache encodes historical $E0xx payload pointers; C128 runtime
    // must translate these to the reclaimed high Bank 1 cache window before copy.
    lda #<TEST_NAME_PTR
    sta TEST_NAME_LO_TABLE
    lda #>TEST_NAME_PTR
    sta TEST_NAME_HI_TABLE
    lda #18   // 'R' screen code
    sta TEST_NAME_STR + 0
    lda #15   // 'o' screen code
    sta TEST_NAME_STR + 1
    lda #7    // 'g' screen code
    sta TEST_NAME_STR + 2
    lda #21   // 'u' screen code
    sta TEST_NAME_STR + 3
    lda #5    // 'e' screen code
    sta TEST_NAME_STR + 4
    lda #0
    sta TEST_NAME_STR + 5
    jsr mmu_select_bank0

    lda #1
    sta current_tier
    lda #1
    sta active_dungeon_count
    lda #<TEST_NAME_LO_TABLE
    sta tier_name_lo_addr
    lda #>TEST_NAME_LO_TABLE
    sta tier_name_lo_addr+1
    lda #<TEST_NAME_HI_TABLE
    sta tier_name_hi_addr
    lda #>TEST_NAME_HI_TABLE
    sta tier_name_hi_addr+1

    ldx #0
    jsr creature_get_name
    cmp #<creature_name_buf
    bne !fail+
    cpy #>creature_name_buf
    bne !fail+

    ldx #0
!name_cmp:
    lda creature_name_buf,x
    cmp test_expected_name,x
    bne !fail+
    cmp #0
    beq !name_ok+
    inx
    cpx #16
    bne !name_cmp-
!fail:
    jmp test_fail
!name_ok:

    // ==========================================
    // C128 creature_get_name Tier-2 cache-slot translation
    // ==========================================
    jsr mmu_select_bank1
    lda #<TEST2_NAME_PTR
    sta TEST2_NAME_LO_TABLE
    lda #>TEST2_NAME_PTR
    sta TEST2_NAME_HI_TABLE
    lda #4    // 'd'
    sta TEST2_NAME_STR + 0
    lda #18   // 'r'
    sta TEST2_NAME_STR + 1
    lda #1    // 'a'
    sta TEST2_NAME_STR + 2
    lda #7    // 'g'
    sta TEST2_NAME_STR + 3
    lda #15   // 'o'
    sta TEST2_NAME_STR + 4
    lda #14   // 'n'
    sta TEST2_NAME_STR + 5
    lda #0
    sta TEST2_NAME_STR + 6
    jsr mmu_select_bank0

    lda #2
    sta current_tier
    lda #1
    sta active_dungeon_count
    lda #<TEST2_NAME_LO_TABLE
    sta tier_name_lo_addr
    lda #>TEST2_NAME_LO_TABLE
    sta tier_name_lo_addr+1
    lda #<TEST2_NAME_HI_TABLE
    sta tier_name_hi_addr
    lda #>TEST2_NAME_HI_TABLE
    sta tier_name_hi_addr+1

    ldx #0
    jsr creature_get_name
    cmp #<creature_name_buf
    bne test_fail
    cpy #>creature_name_buf
    bne test_fail

    ldx #0
!name2_cmp:
    lda creature_name_buf,x
    cmp test_expected_name2,x
    bne test_fail
    cmp #0
    beq !name2_ok+
    inx
    cpx #16
    bne !name2_cmp-
!name2_ok:

    jmp test_pass

test_fail:
    lda #$00
    sta $0400
    jmp test_fail

test_pass:
    lda #$01
    sta $0400
    jmp test_pass

test_expected_name:
    .byte 18, 15, 7, 21, 5, 0

test_expected_name2:
    .byte 4, 18, 1, 7, 15, 14, 0

// Dummy stubs needed by monster.s that aren't imported
.pc = $4000 "Stubs"
rng_range: rts
rng_range_word: rts
math_dice: rts
math_multiply: rts
math_div_16x8: rts
ccl_div_24x8: rts
tramp_spawn_special_room_monsters: rts
tramp_ego_apply_damage: rts
tier_load: rts
item_get_missile: rts
floor_item_find_at: rts
hal_sound_play: rts
msg_build_action: rts
cmb_print_buf: rts

// Required variables
current_tier: .byte 0
tier_silent_restore: .byte 0
tier_count_table: .fill 5, 0
c128_tier_cache_slot_lo:
    .byte 0, <BANK1_TIER_CACHE_BASE, <TEST_TIER2_BASE, 0, 0
c128_tier_cache_slot_hi:
    .byte 0, >BANK1_TIER_CACHE_BASE, >TEST_TIER2_BASE, 0, 0
dir_dx: .fill 8, 0
dir_dy: .fill 8, 0
