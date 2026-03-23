// test_save.s — Runtime tests for save/load system
//
// Tests: RLE round-trip (uniform, alternating, mixed), checksum complement,
// recount_monsters, recount_floor_items.
//
// Results at $0400-$0409: $01 = pass, $00 = fail per test (10 tests)

.pc = $0801 "BASIC Stub"
:BasicUpstart2(bootstrap)

.pc = $0810 "Test Code"

.encoding "screencode_mixed"

// Bootstrap — must be before imports so it's in RAM below $A000.
// Banks out BASIC ROM then jumps to test_start (which may be above $A000).
bootstrap:
    lda $01
    and #%11111110          // Clear bit 0 → bank out BASIC ROM
    sta $01
    jmp test_start

// test_finish — Copy results to $0400 and halt.
// Must be in low memory (before imports) so BRK address is below $A000.
// VICE breakpoint on $A000+ can false-trigger during BASIC ROM execution.
test_finish:
    ldx #9
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = * "Test Body"

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
#import "../../common/player_magic.s"
#import "../../common/ui_inventory.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
#import "../../common/store_data.s"
#import "../../common/ui_help.s"

// Store code goes in a dummy overlay segment so it doesn't bloat the test body.
// test_save.s doesn't test store code, but turn.s→tramp_store_restock_all
// needs these symbols. Placing them past $D000 avoids overlapping MAP_BASE.
.segmentdef TestStoreOverlay [start=$d000, min=$d000, max=$ffff]
.segment TestStoreOverlay
#import "../../common/store.s"
#import "../../common/ui_store.s"
.segment Default

#import "../../common/ui_trampoline_stubs.s"
#import "../../common/runtime_ui_strings.s"
#import "../../common/io_kernal_consts.s"
#import "../../common/save.s"
#import "../../common/disk_swap.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Workspace-based RLE decompressor for test use only.
// The game uses rle_decompress_from_file (streaming from disk) instead.
// Tests set rle_work_lo/hi to $B0A0 so there's no workspace/MAP_BASE overlap.
rle_decompress_map:
    lda rle_work_lo
    sta zp_ptr0
    lda rle_work_hi
    sta zp_ptr0_hi
    lda #<MAP_BASE
    sta zp_ptr1
    lda #>MAP_BASE
    sta zp_ptr1_hi
    lda #0
    sta save_io_error
    lda rle_size_lo
    sta save_count_lo
    lda rle_size_hi
    sta save_count_hi
!rle_d_loop:
    lda save_count_lo
    ora save_count_hi
    beq !rle_d_done+
    lda save_io_error
    bne !rle_d_done+
    ldy #0
    lda (zp_ptr0),y
    pha
    jsr !rle_d_adv_src+
    pla
    cmp #$80
    bcs !rle_d_repeat+
    clc
    adc #1
    sta rle_run_len
!rle_d_lit:
    lda rle_run_len
    beq !rle_d_loop-
    ldy #0
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    jsr !rle_d_adv_src+
    jsr rle_d_advance_dst
    dec rle_run_len
    jmp !rle_d_lit-
!rle_d_repeat:
    sec
    sbc #$7d
    sta rle_run_len
    ldy #0
    lda (zp_ptr0),y
    sta rle_run_byte
    jsr !rle_d_adv_src+
!rle_d_rep:
    lda rle_run_len
    beq !rle_d_loop-
    lda rle_run_byte
    ldy #0
    sta (zp_ptr1),y
    jsr rle_d_advance_dst
    dec rle_run_len
    jmp !rle_d_rep-
!rle_d_done:
    rts
!rle_d_adv_src:
    inc zp_ptr0
    bne !+
    inc zp_ptr0_hi
!:  lda save_count_lo
    sec
    sbc #1
    sta save_count_lo
    bcs !+
    dec save_count_hi
!:  rts

// Test result buffer — copy to $0400 at end (msg_print clobbers $0400)
tc_results: .fill 12, $ff
tc_count: .byte 0

// Verification buffer — 256 bytes at $CF00 (floor item area, safe during tests 2-3)
.const VERIFY_BUF = $CF00

// RLE workspace — must be past test body end (currently ~$BD9F after imports).
// Worst case: 3840 alternating bytes → 3870 compressed → extends to ~$CB1E
// BASIC ROM is banked out, so $A000-$BFFF is RAM. Overlap with map area
// at $C000+ is fine since map is being compressed from it during test.
.const RLE_TEST_BUF = $BE00

test_start:
    // BASIC ROM already banked out by bootstrap above

    // Point RLE workspace to safe buffer (not CREATURE_BASE which overlaps code)
    lda #<RLE_TEST_BUF
    sta rle_work_lo
    lda #>RLE_TEST_BUF
    sta rle_work_hi

    // Initialize result area to $ff (untested)
    ldx #11
    lda #$ff
!clr:
    sta tc_results,x
    dex
    bpl !clr-

    // ============================================================
    // Test 1: RLE round-trip — uniform map (all same tile)
    // Fill MAP_BASE with $0C (floor+lit+visited), compress,
    // verify small output, decompress, compare
    // ============================================================

    // Fill MAP_BASE with $0C
    lda #$0C
    ldx #0
!t1_fill0:
    sta MAP_BASE,x
    sta MAP_BASE + $100,x
    sta MAP_BASE + $200,x
    sta MAP_BASE + $300,x
    sta MAP_BASE + $400,x
    sta MAP_BASE + $500,x
    sta MAP_BASE + $600,x
    sta MAP_BASE + $700,x
    sta MAP_BASE + $800,x
    sta MAP_BASE + $900,x
    sta MAP_BASE + $a00,x
    sta MAP_BASE + $b00,x
    sta MAP_BASE + $c00,x
    sta MAP_BASE + $d00,x
    sta MAP_BASE + $e00,x
    inx
    bne !t1_fill0-

    jsr rle_compress_map

    // Compressed size should be small (< 100 bytes for 3840 uniform)
    // 3840 / 130 = 29.5 → ~30 repeat packets × 2 bytes = 60 bytes
    lda rle_size_hi
    bne !t1_fail+           // Should be < 256
    lda rle_size_lo
    cmp #100
    bcs !t1_fail+           // Should be < 100

    // Now clear MAP_BASE
    lda #$00
    ldx #0
!t1_clear:
    sta MAP_BASE,x
    sta MAP_BASE + $100,x
    sta MAP_BASE + $200,x
    sta MAP_BASE + $300,x
    sta MAP_BASE + $400,x
    sta MAP_BASE + $500,x
    sta MAP_BASE + $600,x
    sta MAP_BASE + $700,x
    sta MAP_BASE + $800,x
    sta MAP_BASE + $900,x
    sta MAP_BASE + $a00,x
    sta MAP_BASE + $b00,x
    sta MAP_BASE + $c00,x
    sta MAP_BASE + $d00,x
    sta MAP_BASE + $e00,x
    inx
    bne !t1_clear-

    // Decompress back to MAP_BASE
    jsr rle_decompress_map

    // Verify all bytes are $0C
    ldx #0
!t1_verify:
    lda MAP_BASE,x
    cmp #$0C
    bne !t1_fail+
    lda MAP_BASE + $100,x
    cmp #$0C
    bne !t1_fail+
    lda MAP_BASE + $200,x
    cmp #$0C
    bne !t1_fail+
    lda MAP_BASE + $300,x
    cmp #$0C
    bne !t1_fail+
    lda MAP_BASE + $e00,x  // Spot check last full page
    cmp #$0C
    bne !t1_fail+
    inx
    bne !t1_verify-
    lda #$01
    jmp !t1_store+
!t1_fail:
    lda #$00
!t1_store:
    sta tc_results + 0

    // ============================================================
    // Test 2: RLE round-trip — mixed pattern (alternating + uniform)
    // First page alternating $0C/$10, rest uniform $10.
    // Compressed output stays below MAP_BASE (avoids decompressor
    // overwriting its own source when workspace extends past $C000).
    // ============================================================

    // Fill all pages with uniform wall ($10) first
    lda #$10
    ldx #0
!t2_base:
    sta MAP_BASE,x
    sta MAP_BASE + $100,x
    sta MAP_BASE + $200,x
    sta MAP_BASE + $300,x
    sta MAP_BASE + $400,x
    sta MAP_BASE + $500,x
    sta MAP_BASE + $600,x
    sta MAP_BASE + $700,x
    sta MAP_BASE + $800,x
    sta MAP_BASE + $900,x
    sta MAP_BASE + $a00,x
    sta MAP_BASE + $b00,x
    sta MAP_BASE + $c00,x
    sta MAP_BASE + $d00,x
    sta MAP_BASE + $e00,x
    inx
    bne !t2_base-

    // Overwrite first page with alternating $0C/$10
    ldx #0
    ldy #0
!t2_fill:
    tya
    and #$01
    beq !t2_even+
    lda #$10
    jmp !t2_store_byte+
!t2_even:
    lda #$0C
!t2_store_byte:
    sta MAP_BASE,x
    iny
    inx
    bne !t2_fill-

    // Save first 256 bytes for verification
    ldx #0
!t2_save:
    lda MAP_BASE,x
    sta VERIFY_BUF,x
    inx
    bne !t2_save-

    jsr rle_compress_map

    // Clear MAP_BASE
    lda #$00
    ldx #0
!t2_clear:
    sta MAP_BASE,x
    sta MAP_BASE + $100,x
    sta MAP_BASE + $200,x
    sta MAP_BASE + $300,x
    sta MAP_BASE + $400,x
    sta MAP_BASE + $500,x
    sta MAP_BASE + $600,x
    sta MAP_BASE + $700,x
    sta MAP_BASE + $800,x
    sta MAP_BASE + $900,x
    sta MAP_BASE + $a00,x
    sta MAP_BASE + $b00,x
    sta MAP_BASE + $c00,x
    sta MAP_BASE + $d00,x
    sta MAP_BASE + $e00,x
    inx
    bne !t2_clear-

    jsr rle_decompress_map

    // Verify first 256 bytes match saved pattern
    ldx #0
!t2_verify:
    lda MAP_BASE,x
    cmp VERIFY_BUF,x
    bne !t2_fail+
    inx
    bne !t2_verify-
    lda #$01
    jmp !t2_store_res+
!t2_fail:
    lda #$00
!t2_store_res:
    sta tc_results + 1

    // ============================================================
    // Test 3: RLE round-trip — mixed data (rooms + corridors)
    // Create a pattern with some repeated areas and some varied
    // ============================================================

    // Fill with wall ($10) as base
    lda #$10
    ldx #0
!t3_base:
    sta MAP_BASE,x
    sta MAP_BASE + $100,x
    sta MAP_BASE + $200,x
    sta MAP_BASE + $300,x
    sta MAP_BASE + $400,x
    sta MAP_BASE + $500,x
    sta MAP_BASE + $600,x
    sta MAP_BASE + $700,x
    sta MAP_BASE + $800,x
    sta MAP_BASE + $900,x
    sta MAP_BASE + $a00,x
    sta MAP_BASE + $b00,x
    sta MAP_BASE + $c00,x
    sta MAP_BASE + $d00,x
    sta MAP_BASE + $e00,x
    inx
    bne !t3_base-

    // Add a "room" at offset 100: 20 bytes of floor ($0C)
    ldx #0
!t3_room:
    cpx #20
    bcs !t3_room_done+
    lda #$0C
    sta MAP_BASE + 100,x
    inx
    jmp !t3_room-
!t3_room_done:

    // Add a corridor: alternating floor/wall for 10 bytes at offset 200
    lda #$0C
    sta MAP_BASE + 200
    lda #$10
    sta MAP_BASE + 201
    lda #$0C
    sta MAP_BASE + 202
    lda #$10
    sta MAP_BASE + 203
    lda #$0C
    sta MAP_BASE + 204
    lda #$10
    sta MAP_BASE + 205
    lda #$0C
    sta MAP_BASE + 206
    lda #$10
    sta MAP_BASE + 207
    lda #$0C
    sta MAP_BASE + 208
    lda #$10
    sta MAP_BASE + 209

    // Save first 256 bytes for verification
    ldx #0
!t3_save:
    lda MAP_BASE,x
    sta VERIFY_BUF,x
    inx
    bne !t3_save-

    jsr rle_compress_map

    // Clear MAP_BASE
    lda #$00
    ldx #0
!t3_clear:
    sta MAP_BASE,x
    sta MAP_BASE + $100,x
    sta MAP_BASE + $200,x
    sta MAP_BASE + $300,x
    sta MAP_BASE + $400,x
    sta MAP_BASE + $500,x
    sta MAP_BASE + $600,x
    sta MAP_BASE + $700,x
    sta MAP_BASE + $800,x
    sta MAP_BASE + $900,x
    sta MAP_BASE + $a00,x
    sta MAP_BASE + $b00,x
    sta MAP_BASE + $c00,x
    sta MAP_BASE + $d00,x
    sta MAP_BASE + $e00,x
    inx
    bne !t3_clear-

    jsr rle_decompress_map

    // Verify first 256 bytes match saved pattern
    ldx #0
!t3_verify:
    lda MAP_BASE,x
    cmp VERIFY_BUF,x
    bne !t3_fail+
    inx
    bne !t3_verify-
    lda #$01
    jmp !t3_store_res+
!t3_fail:
    lda #$00
!t3_store_res:
    sta tc_results + 2

    // ============================================================
    // Test 4: RLE compression ratio — uniform should be < 2% of input
    // Re-do uniform test and check ratio
    // ============================================================
    lda #$0C
    ldx #0
!t4_fill:
    sta MAP_BASE,x
    sta MAP_BASE + $100,x
    sta MAP_BASE + $200,x
    sta MAP_BASE + $300,x
    sta MAP_BASE + $400,x
    sta MAP_BASE + $500,x
    sta MAP_BASE + $600,x
    sta MAP_BASE + $700,x
    sta MAP_BASE + $800,x
    sta MAP_BASE + $900,x
    sta MAP_BASE + $a00,x
    sta MAP_BASE + $b00,x
    sta MAP_BASE + $c00,x
    sta MAP_BASE + $d00,x
    sta MAP_BASE + $e00,x
    inx
    bne !t4_fill-

    jsr rle_compress_map

    // 3840 bytes uniform: 3840/130=29.5 → 30 packets × 2 = 60 bytes
    // Allow up to 80 bytes
    lda rle_size_hi
    bne !t4_fail+
    lda rle_size_lo
    cmp #80
    bcs !t4_fail+
    lda #$01
    jmp !t4_store+
!t4_fail:
    lda #$00
!t4_store:
    sta tc_results + 3

    // ============================================================
    // Test 5: Checksum — accumulate known data, verify sum value
    // Bytes $01, $02, $03 → sum = $0006 (cksum_lo=$06, cksum_hi=$00)
    // ============================================================
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi

    // Accumulate $01
    lda #$01
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !t5_nc1+
    inc save_cksum_hi
!t5_nc1:
    // Accumulate $02
    lda #$02
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !t5_nc2+
    inc save_cksum_hi
!t5_nc2:
    // Accumulate $03
    lda #$03
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !t5_nc3+
    inc save_cksum_hi
!t5_nc3:

    // Verify: cksum_lo should be $06, cksum_hi should be $00
    lda save_cksum_lo
    cmp #$06
    bne !t5_fail+
    lda save_cksum_hi
    cmp #$00
    bne !t5_fail+
    lda #$01
    jmp !t5_store+
!t5_fail:
    lda #$00
!t5_store:
    sta tc_results + 4

    // ============================================================
    // Test 6: Checksum with overflow — $FF + $FF = $01FE
    // ============================================================
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi

    lda #$ff
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !t6_nc1+
    inc save_cksum_hi
!t6_nc1:
    lda #$ff
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !t6_nc2+
    inc save_cksum_hi
!t6_nc2:

    // Verify: cksum_lo should be $FE, cksum_hi should be $01
    lda save_cksum_lo
    cmp #$fe
    bne !t6_fail+
    lda save_cksum_hi
    cmp #$01
    bne !t6_fail+
    lda #$01
    jmp !t6_store+
!t6_fail:
    lda #$00
!t6_store:
    sta tc_results + 5

    // ============================================================
    // Test 7: recount_monsters — 3 active monsters
    // ============================================================
    // Clear monster table
    ldx #0
    lda #EMPTY_SLOT
!t7_clr:
    sta monster_table,x
    inx
    cpx #MAX_MONSTERS * MONSTER_ENTRY_SIZE
    bne !t7_clr-

    // Set up 3 monsters at slots 0, 5, 31
    // Slot 0: type = 4 (Kobold)
    jsr t7_set_slot0
    // Slot 5: type = 9 (Jackal)
    jsr t7_set_slot5
    // Slot 31: type = 1 (Mouse)
    jsr t7_set_slot31

    lda #0
    sta zp_mon_count
    jsr recount_monsters

    lda zp_mon_count
    cmp #3
    beq !t7_pass+
    lda #$00
    jmp !t7_store+
!t7_pass:
    lda #$01
!t7_store:
    sta tc_results + 6

    jmp !t8_start+

// Helper subroutines for monster slot setup (avoid inlining overhead)
t7_set_slot0:
    ldx #0
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #4
    sta (zp_ptr0),y
    rts
t7_set_slot5:
    ldx #5
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #9
    sta (zp_ptr0),y
    rts
t7_set_slot31:
    ldx #31
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #1
    sta (zp_ptr0),y
    rts

!t8_start:
    // ============================================================
    // Test 8: recount_monsters — 0 active (all empty)
    // ============================================================
    // Clear all 32 monster slots using ptr-based access
    // (can't use cpx #384 because X is 8-bit)
    ldx #0
!t8_clr:
    cpx #MAX_MONSTERS
    bcs !t8_clr_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda #EMPTY_SLOT
    sta (zp_ptr0),y
    inx
    jmp !t8_clr-
!t8_clr_done:

    lda #99                     // Set to wrong value first
    sta zp_mon_count
    jsr recount_monsters

    lda zp_mon_count
    cmp #0
    beq !t8_pass+
    lda #$00
    jmp !t8_store+
!t8_pass:
    lda #$01
!t8_store:
    sta tc_results + 7

    // ============================================================
    // Test 9: recount_floor_items — 5 items
    // ============================================================
    // Clear floor items
    ldx #0
    lda #FI_EMPTY
!t9_clr:
    sta fi_item_id,x
    inx
    cpx #MAX_FLOOR_ITEMS
    bne !t9_clr-

    // Place 5 items at various slots
    lda #2                      // Dagger
    sta fi_item_id + 0
    lda #15                     // Food
    sta fi_item_id + 3
    lda #7                      // Leather armor
    sta fi_item_id + 10
    lda #0                      // Gold (small)
    sta fi_item_id + 20
    lda #13                     // Torch
    sta fi_item_id + 31

    lda #0
    sta zp_item_count
    jsr recount_floor_items

    lda zp_item_count
    cmp #5
    beq !t9_pass+
    lda #$00
    jmp !t9_store+
!t9_pass:
    lda #$01
!t9_store:
    sta tc_results + 8

    // ============================================================
    // Test 10: recount_floor_items — 0 items (all empty)
    // ============================================================
    ldx #0
    lda #FI_EMPTY
!t10_clr:
    sta fi_item_id,x
    inx
    cpx #MAX_FLOOR_ITEMS
    bne !t10_clr-

    lda #99
    sta zp_item_count
    jsr recount_floor_items

    lda zp_item_count
    cmp #0
    beq !t10_pass+
    lda #$00
    jmp !t10_store+
!t10_pass:
    lda #$01
!t10_store:
    sta tc_results + 9

    jmp test_finish
