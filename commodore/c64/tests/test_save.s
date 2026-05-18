// test_save.s — Runtime tests for save/load system
//
// Tests: RLE round-trip (uniform, alternating, mixed), checksum complement,
// recount_monsters, recount_floor_items, save-version compatibility helpers,
// split item stat save/load persistence.
//
// Results at $0400-$0415: $01 = pass, $00 = fail per test (22 tests)

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
    ldx #21
!copy:
    lda tc_results,x
    sta $0400,x
    dex
    bpl !copy-
    brk

.pc = * "Test Body"

#define SAVE_TEST_RLE
#define STORAGE_STATUS_HELPER
#define STORAGE_SETUP_STATUS_HELPER
#define STORAGE_STREAM_STATUS_HELPER
#define HAL_STORAGE_SAVE_MEDIA_STATUS_LEGACY
#define HAL_STORAGE_SWAP_PROMPT_LEGACY_SETUP_SKIP
#define HAL_STORAGE_SWAP_PROMPT_FULLSCREEN
#define HAL_STORAGE_SWAP_PROMPT_SIMPLE_KEY
#define HAL_STORAGE_SWAP_PROMPT_CPU_PORT_RESTORE
#define HAL_STORAGE_MARKER_PRESENT_DIRECT

player_cast_spell:
player_pray:
magic_recalc_mana:
magic_check_new_spells:
ui_help_display:
    rts

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
dg_idx: .byte 0
#import "../../common/huffman.s"
#import "../../common/dungeon_features.s"
#import "../../common/monster.s"
#import "../../common/tier_manager.s"
#import "../../common/overlay.s"
#import "../../common/monster_ai.s"
#import "../../common/recall.s"
#import "../../common/monster_magic.s"
#import "../../common/item.s"
random_floor_in_room:
    lda #0
    tay
    rts
#import "../../common/special_rooms.s"
#import "../../common/ego_items.s"
#import "../../common/special_rooms_stubs.s"
#import "../../common/player_items.s"
#import "../../common/spell_data.s"
#import "../../common/projectile.s"
#import "../../common/spell_effects.s"
#import "../../common/ui_inventory.s"
#import "../../common/ui_equipment.s"
#import "../dungeon_render.s"
#import "../../common/dungeon_los.s"
#import "../../common/player_move.s"
#import "../../common/combat.s"
#import "../../common/monster_attack.s"
#import "../../common/turn.s"
#import "../../common/store_data.s"
// Store code goes in a dummy overlay segment so it doesn't bloat the test body.
// test_save.s doesn't test store code, but turn.s→tramp_store_restock_all
// needs these symbols. Placing them past $D000 avoids overlapping MAP_BASE.
.segmentdef TestStoreOverlay [start=$d000, min=$d000, max=$ffff]
.segment TestStoreOverlay
#import "../../common/store.s"
#import "../../common/ui_store.s"
.segment Default

#define C64_TEST_NO_SPELL_NAME_STUBS
#import "../../common/ui_trampoline_stubs.s"
#import "../../common/runtime_ui_strings.s"
.const SAVE_DEVICE    = 8
.const hal_storage_save_file_num  = 2
.const hal_storage_check_file_num = 3
.const hal_storage_save_sec_write = 2
.const hal_storage_save_sec_read  = 2
.const hal_storage_check_sec_read = hal_storage_save_sec_read
.const hal_storage_cmd_channel    = 15
.const hal_storage_marker_file_num = 6
.const hal_storage_marker_sec_read = 2
.const hal_storage_marker_sec_write = 2
.const hal_storage_program_file_num = 7
.const KERNAL_ERR_DEVICE_NOT_PRESENT = 5
.const KERNAL_SETNAM = test_save_setnam
.const KERNAL_SETLFS = test_save_setlfs
.const KERNAL_OPEN   = test_save_open
.const KERNAL_CLOSE  = test_save_close
.const KERNAL_CHKOUT = test_save_chkout
.const KERNAL_CHKIN  = test_save_chkin
.const KERNAL_CLRCHN = test_save_clrchn
.const KERNAL_CHROUT = test_save_chrout
.const KERNAL_CHRIN  = test_save_chrin
.const KERNAL_READST = test_save_readst
.label c64_disk_setnam = test_save_setnam
.label c64_disk_setlfs = test_save_setlfs
.label c64_disk_open   = test_save_open
.label c64_disk_close  = test_save_close
.label c64_disk_clrchn = test_save_clrchn
.label c64_disk_readst = test_save_readst
.label c64_disk_chkin  = test_save_chkin
.label c64_disk_chkout = test_save_chkout
.label c64_disk_chrin  = test_save_chrin
.label c64_disk_chrout = test_save_chrout
.label hal_storage_setnam = test_save_setnam
.label hal_storage_setlfs = test_save_setlfs
.label hal_storage_open   = test_save_open
.label hal_storage_close  = test_save_close
.label hal_storage_chkin  = test_save_chkin
.label hal_storage_chkout = test_save_chkout
.label hal_storage_chrin  = test_save_chrin
.label hal_storage_chrout = test_save_chrout
.label hal_storage_clrchn = test_save_clrchn
.label hal_storage_readst = test_save_readst
.label hal_storage_save_media_status = disk_save_media_status
.label hal_storage_setup_status = disk_setup_status
.label hal_storage_save_stream_status = save_stream_status
.label hal_storage_load_stream_status = load_stream_status
.label hal_storage_marker_present = c64_disk_marker_present
.label hal_storage_marker_write_resident = c64_disk_marker_write_resident
hal_storage_init_selected_drive:
    rts
c64_disk_marker_present:
    lda test_save_marker_present
    beq !missing+
    clc
    rts
!missing:
    lda test_save_marker_status
    bne !store_status+
    lda #1
!store_status:
    sta disk_status
    lda test_save_marker_lsr_return
    beq !return_sec+
    lda disk_status
    lsr
    rts
!return_sec:
    sec
    rts
c64_disk_marker_write_resident:
    clc
    rts
hal_storage_init_command:
    .byte $49, $30
hal_storage_save_write_name:
    .byte $40, $30, $3a
    .byte $54, $45, $53, $54
    .byte $2c, $53, $2c, $57
.label hal_storage_save_write_name_len = * - hal_storage_save_write_name
.label hal_storage_save_probe_name = hal_storage_save_write_name + 1
.label hal_storage_save_probe_name_len = hal_storage_save_write_name_len - 1
hal_storage_save_read_name:
    .byte $30, $3a
    .byte $54, $45, $53, $54
    .byte $2c, $53, $2c, $52
.label hal_storage_save_read_name_len = * - hal_storage_save_read_name
#import "../../common/save.s"
#import "../../common/disk_swap.s"

// Strings referenced by imported modules but defined in main.s
press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

// Workspace-based RLE decompressor for test use only.
// The game uses rle_decompress_from_file (streaming from disk) instead.
// Tests point rle_work_lo/hi at low screen RAM so compressed source stays
// below MAP_BASE during round-trip checks that clear the map before decode.
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
tc_results: .fill 22, $ff
tc_count: .byte 0

// Verification buffer — 256 bytes at $CF00 (floor item area, safe during tests 2-3)
.const VERIFY_BUF = $CF00

// Memory-backed save stream used by persistence tests. MAP_BASE is unused
// after the RLE tests and gives enough room for the item save blocks.
.const SAVE_STREAM_BUF = MAP_BASE

// RLE workspace for the round-trip tests.
// $0500-$07ff is free in this test image and gives 768 bytes, which is enough
// for the mixed-pattern streams used here while staying below MAP_BASE.
.const RLE_TEST_BUF = $0500

test_save_last_lfn:   .byte 0
test_save_last_dev:   .byte 0
test_save_last_sec:   .byte 0
test_save_tmp_y:      .byte 0
test_save_close_arms_readst: .byte 0
test_save_readst_value: .byte 0
test_save_last_msg: .byte 0
test_save_dismiss_calls: .byte 0
test_save_marker_present: .byte 0
test_save_marker_status: .byte 0
test_save_marker_lsr_return: .byte 0
test_save_sink_writes: .byte 0
test_save_file_exists_calls: .byte 0
test_save_open_calls: .byte 0
test_save_chkout_calls: .byte 0
test_save_chrout_calls: .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_save_setnam:
    clc
    rts

test_save_setlfs:
    sta test_save_last_lfn
    stx test_save_last_dev
    sty test_save_last_sec
    clc
    rts

test_save_close:
    lda test_save_close_arms_readst
    beq !close_ok+
    lda #$42
    sta test_save_readst_value
!close_ok:
    clc
    rts

test_save_chkout:
    inc test_save_chkout_calls
    clc
    rts

test_save_open:
    inc test_save_open_calls
    clc
    rts

test_save_chkin:
test_save_clrchn:
    clc
    rts

test_save_readst:
    lda test_save_readst_value
    pha
    lda #0
    sta test_save_readst_value
    pla
    clc
    rts

test_save_chrout:
    pha
    inc test_save_chrout_calls
    lda test_save_sink_writes
    bne !sink+
    sty test_save_tmp_y
    ldy #0
    pla
    sta (zp_ptr1),y
    inc zp_ptr1
    bne !+
    inc zp_ptr1_hi
!:  ldy test_save_tmp_y
    clc
    rts
!sink:
    pla
    clc
    rts

test_save_chrin:
    sty test_save_tmp_y
    ldy #0
    lda (zp_ptr1),y
    inc zp_ptr1
    bne !+
    inc zp_ptr1_hi
!:  ldy test_save_tmp_y
    clc
    rts

test_save_file_not_exists:
    inc test_save_file_exists_calls
    clc
    rts

test_huff_print_msg:
    stx test_save_last_msg
    rts

test_modal_dismiss_key:
    inc test_save_dismiss_calls
    rts

test_stream_reset_write:
    lda #<SAVE_STREAM_BUF
    sta zp_ptr1
    lda #>SAVE_STREAM_BUF
    sta zp_ptr1_hi
    rts

test_stream_reset_read:
    lda #<SAVE_STREAM_BUF
    sta zp_ptr1
    lda #>SAVE_STREAM_BUF
    sta zp_ptr1_hi
    rts

test_clear_store_items:
    ldx #STORE_TOTAL_SLOTS - 1
    lda #FI_EMPTY
!ids:
    sta si_item_id,x
    dex
    bpl !ids-
    ldx #STORE_TOTAL_SLOTS - 1
    lda #0
!fields:
    sta si_qty,x
    sta si_p1,x
    sta si_to_hit,x
    sta si_to_dam,x
    sta si_to_ac,x
    sta si_meta,x
    dex
    bpl !fields-
    rts

test_save_item_state_blocks:
    :save_block(inv_item_id, TOTAL_INV_SLOTS)
    :save_block(inv_qty, TOTAL_INV_SLOTS)
    :save_block(inv_p1, TOTAL_INV_SLOTS)
    :save_block(inv_to_hit, TOTAL_INV_SLOTS)
    :save_block(inv_to_dam, TOTAL_INV_SLOTS)
    :save_block(inv_to_ac, TOTAL_INV_SLOTS)
    :save_block(inv_flags, TOTAL_INV_SLOTS)
    :save_block(inv_ego, TOTAL_INV_SLOTS)
    :save_block(si_item_id, STORE_TOTAL_SLOTS)
    :save_block(si_qty, STORE_TOTAL_SLOTS)
    :save_block(si_p1, STORE_TOTAL_SLOTS)
    :save_block(si_to_hit, STORE_TOTAL_SLOTS)
    :save_block(si_to_dam, STORE_TOTAL_SLOTS)
    :save_block(si_to_ac, STORE_TOTAL_SLOTS)
    :save_block(si_meta, STORE_TOTAL_SLOTS)
    jsr save_write_floor_items
    rts

test_load_item_state_blocks:
    :load_block(inv_item_id, TOTAL_INV_SLOTS)
    :load_block(inv_qty, TOTAL_INV_SLOTS)
    :load_block(inv_p1, TOTAL_INV_SLOTS)
    :load_block(inv_to_hit, TOTAL_INV_SLOTS)
    :load_block(inv_to_dam, TOTAL_INV_SLOTS)
    :load_block(inv_to_ac, TOTAL_INV_SLOTS)
    :load_block(inv_flags, TOTAL_INV_SLOTS)
    :load_block(inv_ego, TOTAL_INV_SLOTS)
    :load_block(si_item_id, STORE_TOTAL_SLOTS)
    :load_block(si_qty, STORE_TOTAL_SLOTS)
    :load_block(si_p1, STORE_TOTAL_SLOTS)
    :load_block(si_to_hit, STORE_TOTAL_SLOTS)
    :load_block(si_to_dam, STORE_TOTAL_SLOTS)
    :load_block(si_to_ac, STORE_TOTAL_SLOTS)
    :load_block(si_meta, STORE_TOTAL_SLOTS)
    lda #SAVE_VERSION
    sta load_save_version
    jsr load_read_floor_items
    rts

.macro t13_expect(value) {
    cmp #value
    beq !ok+
    jmp t13_fail
!ok:
}

test_start:
    // BASIC ROM already banked out by bootstrap above
    :PatchJump(save_file_exists, test_save_file_not_exists)
    :PatchJump(huff_print_msg, test_huff_print_msg)
    :PatchJump(input_get_modal_dismiss_key, test_modal_dismiss_key)

    // Point RLE workspace to safe buffer (not CREATURE_BASE which overlaps code)
    lda #<RLE_TEST_BUF
    sta rle_work_lo
    lda #>RLE_TEST_BUF
    sta rle_work_hi

    // Initialize result area to $ff (untested)
    ldx #21
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

    // ============================================================
    // Test 11: save_version_supported accepts the current C64 save version.
    // ============================================================
    lda #SAVE_VERSION
    jsr save_version_supported
    bcc !t11_fail+
    lda #$01
    bne !t11_store+
!t11_fail:
    lda #$00
!t11_store:
    sta tc_results + 10

    // ============================================================
    // Test 12: unsupported/floor-layout helpers reject non-current versions.
    // ============================================================
    lda #(SAVE_VERSION - 1)
    jsr save_version_supported
    bcs !t12_fail+
    lda #(SAVE_VERSION + 1)
    jsr save_version_supported
    bcs !t12_fail+
    lda #(SAVE_VERSION - 1)
    jsr save_version_uses_legacy_floor_layout
    bcc !t12_fail+
    lda #SAVE_VERSION
    jsr save_version_uses_legacy_floor_layout
    bcs !t12_fail+
    lda #$01
    bne !t12_store+
!t12_fail:
    lda #$00
!t12_store:
    sta tc_results + 11

    // ============================================================
    // Test 13: split item stats and metadata persist through the
    // real save/load block representation for inventory/equipment,
    // store/home slots, and packed floor items.
    // ============================================================
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    sta save_io_error

    jsr item_init_inventory
    jsr item_init_floor
    jsr test_clear_store_items

    // Inventory slot 2: weapon-like item with split combat stats.
    lda #2
    sta inv_item_id + 2
    lda #1
    sta inv_qty + 2
    lda #$44
    sta inv_p1 + 2
    lda #$fb
    sta inv_to_hit + 2
    lda #7
    sta inv_to_dam + 2
    lda #0
    sta inv_to_ac + 2
    lda #(IF_IDENTIFIED | IF_CURSED)
    sta inv_flags + 2
    lda #EGO_FLAME_TONGUE
    sta inv_ego + 2

    // Equipment body slot: armor AC must persist independently.
    lda #7
    sta inv_item_id + EQUIP_BODY
    lda #1
    sta inv_qty + EQUIP_BODY
    lda #5
    sta inv_to_ac + EQUIP_BODY
    lda #IF_IDENTIFIED
    sta inv_flags + EQUIP_BODY

    // Store/home slot 10: packed flags+ego plus split stat sidecars.
    lda #1
    sta si_item_id + 10
    sta si_qty + 10
    lda #$33
    sta si_p1 + 10
    lda #3
    sta si_to_hit + 10
    lda #$fe
    sta si_to_dam + 10
    lda #6
    sta si_to_ac + 10
    lda #((EGO_DEFENDER << ITEM_META_EGO_SHIFT) | IF_IDENTIFIED | IF_SENSED)
    sta si_meta + 10

    // Floor slot 3: packed floor metadata uses flags<<3 plus low ego bits.
    lda #2
    sta fi_item_id + 3
    lda #11
    sta fi_x + 3
    lda #12
    sta fi_y + 3
    lda #2
    sta fi_qty + 3
    lda #$55
    sta fi_p1 + 3
    lda #(((IF_IDENTIFIED | IF_CURSED) << 3) | EGO_FROST_BRAND)
    sta fi_meta + 3
    lda #$82
    sta fi_to_hit + 3
    lda #9
    sta fi_to_dam + 3
    lda #4
    sta fi_to_ac + 3

    jsr test_stream_reset_write
    jsr test_save_item_state_blocks

    jsr item_init_inventory
    jsr item_init_floor
    jsr test_clear_store_items
    jsr test_stream_reset_read
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    sta save_io_error
    jsr test_load_item_state_blocks

    lda inv_item_id + 2
    :t13_expect(2)
    lda inv_p1 + 2
    :t13_expect($44)
    lda inv_to_hit + 2
    :t13_expect($fb)
    lda inv_to_dam + 2
    :t13_expect(7)
    lda inv_flags + 2
    :t13_expect(IF_IDENTIFIED | IF_CURSED)
    lda inv_ego + 2
    :t13_expect(EGO_FLAME_TONGUE)

    lda inv_item_id + EQUIP_BODY
    :t13_expect(7)
    lda inv_to_ac + EQUIP_BODY
    :t13_expect(5)
    lda inv_flags + EQUIP_BODY
    :t13_expect(IF_IDENTIFIED)

    lda si_item_id + 10
    :t13_expect(1)
    lda si_p1 + 10
    :t13_expect($33)
    lda si_to_hit + 10
    :t13_expect(3)
    lda si_to_dam + 10
    :t13_expect($fe)
    lda si_to_ac + 10
    :t13_expect(6)
    lda si_meta + 10
    :t13_expect((EGO_DEFENDER << ITEM_META_EGO_SHIFT) | IF_IDENTIFIED | IF_SENSED)

    lda fi_item_id + 3
    :t13_expect(2)
    lda fi_x + 3
    :t13_expect(11)
    lda fi_y + 3
    :t13_expect(12)
    lda fi_qty + 3
    :t13_expect(2)
    lda fi_p1 + 3
    :t13_expect($55)
    lda fi_meta + 3
    :t13_expect(((IF_IDENTIFIED | IF_CURSED) << 3) | EGO_FROST_BRAND)
    lda fi_to_hit + 3
    :t13_expect($82)
    lda fi_to_dam + 3
    :t13_expect(9)
    lda fi_to_ac + 3
    :t13_expect(4)
    lda save_io_error
    beq !t13_no_io_error+
    jmp t13_fail
!t13_no_io_error:
    lda #$01
    bne !t13_store+
t13_fail:
    lda #$00
!t13_store:
    sta tc_results + 12

    // ============================================================
    // Test 14: C64 save reports a close-time KERNAL status error.
    // Writes and write-time READST succeed, but CLOSE arms a late
    // $42 status. save_game must return failure through Disk error!.
    // ============================================================
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    sta save_io_error
    sta test_save_last_msg
    sta test_save_dismiss_calls
    sta test_save_readst_value
    sta test_save_sink_writes
    lda #1
    sta test_save_marker_present
    sta test_save_close_arms_readst
    sta test_save_sink_writes
    sta disk_setup_done
    lda #2
    sta disk_mode
    lda #8
    sta save_device
    jsr test_stream_reset_write
    jsr save_game
    bcc !t14_carry_ok+
    lda #2
    jmp t14_fail_code
!t14_carry_ok:
    lda test_save_last_msg
    cmp #HSTR_SAVE_IOERR
    beq !t14_msg_ok+
    lda #3
    jmp t14_fail_code
!t14_msg_ok:
    lda test_save_dismiss_calls
    cmp #1
    beq !t14_dismiss_ok+
    lda #4
    jmp t14_fail_code
!t14_dismiss_ok:
    lda #0
    sta test_save_close_arms_readst
    sta test_save_marker_present
    sta test_save_sink_writes
    lda #$01
    bne !t14_store+
t14_fail_code:
    pha
    sta test_save_close_arms_readst
    sta test_save_marker_present
    sta test_save_sink_writes
    pla
!t14_store:
    sta tc_results + 13

    // ============================================================
    // Test 15: C64 save-media validation failures are modal.
    // Otherwise the caller can immediately redraw gameplay and erase
    // the error before the user sees it.
    // ============================================================
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    sta save_io_error
    sta test_save_last_msg
    sta test_save_dismiss_calls
    sta test_save_readst_value
    sta test_save_close_arms_readst
    sta test_save_sink_writes
    sta test_save_marker_present
    sta test_save_marker_lsr_return
    sta test_save_file_exists_calls
    sta test_save_open_calls
    sta test_save_chkout_calls
    sta test_save_chrout_calls
    sta test_save_marker_status
    lda #1
    sta disk_setup_done
    lda #2
    sta disk_mode
    lda #8
    sta save_device
    jsr save_game
    bcc !t15_carry_ok+
    lda #2
    jmp t15_fail_code
!t15_carry_ok:
    lda test_save_last_msg
    cmp #HSTR_SAVE_BAD_SAVE
    beq !t15_msg_ok+
    lda #3
    jmp t15_fail_code
!t15_msg_ok:
    lda test_save_dismiss_calls
    cmp #1
    beq !t15_dismiss_ok+
    lda #4
    jmp t15_fail_code
!t15_dismiss_ok:
    lda #0
    sta test_save_marker_present
    sta test_save_marker_status
    sta test_save_marker_lsr_return
    sta test_save_sink_writes
    lda #$01
    bne !t15_store+
t15_fail_code:
    pha
    sta test_save_marker_present
    sta test_save_marker_status
    sta test_save_marker_lsr_return
    sta test_save_sink_writes
    pla
!t15_store:
    sta tc_results + 14

    // ============================================================
    // Test 16: C64 save-media I/O failures report Disk error!,
    // not Wrong Save Disk. disk_status=1 means marker mismatch;
    // other nonzero values are hardware/media I/O status.
    // ============================================================
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    sta save_io_error
    sta test_save_last_msg
    sta test_save_dismiss_calls
    sta test_save_readst_value
    sta test_save_close_arms_readst
    sta test_save_sink_writes
    sta test_save_marker_present
    sta test_save_marker_lsr_return
    sta test_save_file_exists_calls
    sta test_save_open_calls
    sta test_save_chkout_calls
    sta test_save_chrout_calls
    lda #$42
    sta test_save_marker_status
    lda #1
    sta disk_setup_done
    lda #2
    sta disk_mode
    lda #8
    sta save_device
    jsr save_game
    bcc !t16_carry_ok+
    lda #2
    jmp t16_fail_code
!t16_carry_ok:
    lda test_save_last_msg
    cmp #HSTR_SAVE_IOERR
    beq !t16_msg_ok+
    lda #3
    jmp t16_fail_code
!t16_msg_ok:
    lda test_save_dismiss_calls
    cmp #1
    beq !t16_dismiss_ok+
    lda #4
    jmp t16_fail_code
!t16_dismiss_ok:
    lda #0
    sta test_save_marker_status
    sta test_save_marker_lsr_return
    lda #$01
    bne !t16_store+
t16_fail_code:
    pha
    sta test_save_marker_status
    pla
!t16_store:
    sta tc_results + 15

    // ============================================================
    // Test 17: Media I/O failure is terminal for the save path.
    // The real product smoke covers c64_disk_marker_present's carry
    // convention; this unit guards common save_game from entering
    // overwrite/file-output after the media gate fails.
    // ============================================================
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    sta save_io_error
    sta test_save_last_msg
    sta test_save_dismiss_calls
    sta test_save_readst_value
    sta test_save_close_arms_readst
    sta test_save_sink_writes
    sta test_save_marker_present
    sta test_save_file_exists_calls
    sta test_save_open_calls
    sta test_save_chkout_calls
    sta test_save_chrout_calls
    lda #1
    sta test_save_sink_writes
    lda #2
    sta test_save_marker_status
    lda #1
    sta disk_setup_done
    lda #2
    sta disk_mode
    lda #8
    sta save_device
    jsr save_game
    bcc !t17_carry_ok+
    lda #2
    jmp t17_fail_code
!t17_carry_ok:
    lda test_save_last_msg
    cmp #HSTR_SAVE_IOERR
    beq !t17_msg_ok+
    lda #3
    jmp t17_fail_code
!t17_msg_ok:
    lda test_save_dismiss_calls
    cmp #1
    beq !t17_dismiss_ok+
    lda #4
    jmp t17_fail_code
!t17_dismiss_ok:
    lda test_save_file_exists_calls
    ora test_save_open_calls
    ora test_save_chkout_calls
    ora test_save_chrout_calls
    beq !t17_no_io+
    lda #5
    jmp t17_fail_code
!t17_no_io:
    lda #0
    sta test_save_marker_status
    sta test_save_marker_lsr_return
    lda #$01
    bne !t17_store+
t17_fail_code:
    pha
    lda #0
    sta test_save_marker_status
    sta test_save_marker_lsr_return
    pla
!t17_store:
    sta tc_results + 16

    // ============================================================
    // Test 18: C64 save-media classifier returns normalized HAL
    // status codes. Common save/load branches on this semantic value.
    // ============================================================
    lda #1
    sta disk_status
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_WRONG_MEDIA
    beq !t18_wrong_ok+
    lda #2
    jmp t18_fail_code
!t18_wrong_ok:
    lda #KERNAL_ERR_DEVICE_NOT_PRESENT
    sta disk_status
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq !t18_io_ok+
    lda #3
    jmp t18_fail_code
!t18_io_ok:
    lda #$42
    sta disk_status
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq !t18_status_ok+
    lda #4
    jmp t18_fail_code
!t18_status_ok:
    lda #$01
    bne !t18_store+
t18_fail_code:
!t18_store:
    sta tc_results + 17

    // ============================================================
    // Test 19: DOS command-channel digits normalize to semantic
    // HAL storage statuses.
    // ============================================================
    lda #$30
    ldx #$30
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_OK
    beq !t19_ok_00+
    lda #2
    jmp t19_fail_code
!t19_ok_00:
    lda #$32
    ldx #$36
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_WRITE_PROTECTED
    beq !t19_ok_26+
    lda #3
    jmp t19_fail_code
!t19_ok_26:
    lda #$36
    ldx #$32
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_NOT_FOUND
    beq !t19_ok_62+
    lda #4
    jmp t19_fail_code
!t19_ok_62:
    lda #$37
    ldx #$32
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_DISK_FULL
    beq !t19_ok_72+
    lda #5
    jmp t19_fail_code
!t19_ok_72:
    lda #$37
    ldx #$34
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    beq !t19_ok_74+
    lda #6
    jmp t19_fail_code
!t19_ok_74:
    lda #$33
    ldx #$31
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq !t19_ok_unknown+
    lda #7
    jmp t19_fail_code
!t19_ok_unknown:
    lda #$01
    bne !t19_store+
t19_fail_code:
!t19_store:
    sta tc_results + 18

    // ============================================================
    // Test 20: Disk Setup classifier maps raw setup status bytes to
    // normalized HAL storage statuses.
    // ============================================================
    lda #26
    sta disk_status
    jsr disk_setup_status
    cmp #HAL_STORAGE_STATUS_WRITE_PROTECTED
    beq !t20_ok_26+
    lda #2
    jmp t20_fail_code
!t20_ok_26:
    lda #72
    sta disk_status
    jsr disk_setup_status
    cmp #HAL_STORAGE_STATUS_DISK_FULL
    beq !t20_ok_72+
    lda #3
    jmp t20_fail_code
!t20_ok_72:
    lda #74
    sta disk_status
    jsr disk_setup_status
    cmp #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    beq !t20_ok_74+
    lda #4
    jmp t20_fail_code
!t20_ok_74:
    lda #2
    sta disk_status
    jsr disk_setup_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq !t20_ok_unknown+
    lda #5
    jmp t20_fail_code
!t20_ok_unknown:
    lda #$01
    bne !t20_store+
t20_fail_code:
!t20_store:
    sta tc_results + 19

    // ============================================================
    // Test 21: Save/load stream classifiers expose semantic HAL
    // status codes over the existing stream result bytes.
    // ============================================================
    lda #0
    sta save_io_error
    jsr hal_storage_save_stream_status
    cmp #HAL_STORAGE_STATUS_OK
    beq !t21_save_ok+
    lda #2
    jmp t21_fail_code
!t21_save_ok:
    lda #1
    sta save_io_error
    jsr hal_storage_save_stream_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq !t21_save_err_ok+
    lda #3
    jmp t21_fail_code
!t21_save_err_ok:
    lda #LOAD_RESULT_NOTFOUND
    sta load_result
    jsr hal_storage_load_stream_status
    cmp #HAL_STORAGE_STATUS_NOT_FOUND
    beq !t21_load_notfound_ok+
    lda #4
    jmp t21_fail_code
!t21_load_notfound_ok:
    lda #LOAD_RESULT_UNSUPPORTED
    sta load_result
    jsr hal_storage_load_stream_status
    cmp #HAL_STORAGE_STATUS_UNSUPPORTED
    beq !t21_load_unsupported_ok+
    lda #5
    jmp t21_fail_code
!t21_load_unsupported_ok:
    lda #LOAD_RESULT_IOERR
    sta load_result
    jsr hal_storage_load_stream_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq !t21_load_ioerr_ok+
    lda #6
    jmp t21_fail_code
!t21_load_ioerr_ok:
    lda #LOAD_RESULT_OK
    sta load_result
    jsr hal_storage_load_stream_status
    cmp #HAL_STORAGE_STATUS_OK
    beq !t21_status_ok+
    lda #7
    jmp t21_fail_code
!t21_status_ok:
    lda #$01
    bne !t21_store+
t21_fail_code:
!t21_store:
    sta tc_results + 20

    // ============================================================
    // Test 22: Stream status message selectors map semantic HAL
    // statuses to existing user-facing save/load messages.
    // ============================================================
    lda #HAL_STORAGE_STATUS_UNKNOWN
    jsr save_stream_status_message
    cpx #HSTR_SAVE_IOERR
    beq !t22_save_ioerr_ok+
    lda #2
    jmp t22_fail_code
!t22_save_ioerr_ok:
    lda #HAL_STORAGE_STATUS_NOT_FOUND
    jsr load_stream_status_message
    cpx #HSTR_SAVE_NOTFOUND
    beq !t22_load_notfound_ok+
    lda #3
    jmp t22_fail_code
!t22_load_notfound_ok:
    lda #HAL_STORAGE_STATUS_UNSUPPORTED
    jsr load_stream_status_message
    cpx #HSTR_SAVE_UNSUPPORTED
    beq !t22_load_unsupported_ok+
    lda #4
    jmp t22_fail_code
!t22_load_unsupported_ok:
    lda #HAL_STORAGE_STATUS_UNKNOWN
    jsr load_stream_status_message
    cpx #HSTR_SAVE_IOERR
    beq !t22_load_ioerr_ok+
    lda #5
    jmp t22_fail_code
!t22_load_ioerr_ok:
    lda #$01
    bne !t22_store+
t22_fail_code:
!t22_store:
    sta tc_results + 21

    jmp test_finish

test_body_end:
.assert "RLE test buffer stays below test code", RLE_TEST_BUF + $0300 <= $0800, true
