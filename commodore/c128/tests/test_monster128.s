// test_monster128.s — C128-specific regression test for monster kill memory preservation
//
// Tests: monster_remove regression (Bug R4) where FLAG_OCCUPIED clear
// clobbered map bytes by directly reading from Bank 0.

#import "../../common/zeropage.s"
#import "../config128.s"
#import "../memory128.s"
#import "../../common/mmu_macros.s"
#import "../../common/dungeon_data.s"

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

// Put the dummy map row somewhere safe
test_map_row:
    .fill 80, 0

.pc = $3000 "Test Code"
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
    // Verify results
    // ==========================================
    // The monster count should decrease
    lda zp_mon_count
    bne test_fail

    lda map_row_lo+5
    sta zp_ptr0
    lda map_row_hi+5
    sta zp_ptr0_hi
    ldy #10
    :MapRead_ptr0_y()
    
    cmp #$08
    bne test_fail

    jmp test_pass

test_fail:
    lda #$00
    sta $0400
    jmp test_fail

test_pass:
    lda #$01
    sta $0400
    jmp test_pass

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
sound_play: rts
msg_build_action: rts
cmb_print_buf: rts

// Required variables
current_tier: .byte 0
tier_count_table: .fill 5, 0
dir_dx: .fill 8, 0
dir_dy: .fill 8, 0
