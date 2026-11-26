// test_save.s — Runtime tests for save/load system
//
// Tests: RLE round-trip (uniform, alternating, mixed), checksum complement,
// recount_monsters, recount_floor_items, save-version compatibility helpers,
// split item stat save/load persistence, invalid item-ID load hardening.
//
// Results at $0400-$042C: $01 = pass, $00 = fail per test (45 tests)

#define C64_TEST_NAME_STREAMS_A000

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
    ldx #44
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
#define HAL_STORAGE_SAVE_CHECKS_DOS_STATUS
#define HAL_STORAGE_FRIENDLY_STATUS_MESSAGES
#define HAL_STORAGE_COMMAND_STATUS_FROM_DOS_CODE
#define HAL_STORAGE_SWAP_PROMPT_LEGACY_SETUP_SKIP
#define HAL_STORAGE_SWAP_PROMPT_FULLSCREEN
#define HAL_STORAGE_SWAP_PROMPT_SIMPLE_KEY
#define HAL_STORAGE_SWAP_PROMPT_CPU_PORT_RESTORE
#define HAL_STORAGE_MARKER_PRESENT_DIRECT
#define HAL_STORAGE_SAVE_SELECT_OUTPUT_NAME_LEGACY
#define HAL_STORAGE_LOAD_ALLOW_UNMARKED_SAVE
#define HAL_STORAGE_CPU_PORT_RESTORE_AFTER_IO
#define HAL_STORAGE_VIC_BANK_RESTORE_AFTER_SERIAL
// test_save exercises save/load formats and known-item bitsets using
// hot tables only; item_cat_data (7.5 KB) is never read here.
#define HAL_PLATFORM_ITEM_CAT_CUSTOM
hal_item_cat_read_byte:
    brk

player_cast_spell:
player_pray:
magic_recalc_mana:
magic_check_new_spells:
ui_help_display:
ui_inv_display:
ui_inv_select_display:
ui_equip_display:
    rts
// Save tests do not execute monster AI; these satisfy indirect turn/render
// links without pulling the full AI engine into the MAP_BASE-sensitive body.
monster_ai_tick:
    rts
mat_scene_dirty: .byte 0

.segmentdef TestUnused [start=$E100, min=$E100, max=$FFF9]
#define PLAYER_CHARGEN_EXTERNAL
#define TRAP_TRIGGER_EXTERNAL
#define ITEM_SPAWN_EXTERNAL
#define PICK_ITEM_TYPE_EXTERNAL
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
.segmentdef TestUnusedStatus [start=$D000, min=$D000, max=$DFFF]
.segment TestUnusedStatus
#import "../../../../core/6502/ui_status.s"
#import "../../../../core/6502/stat_display.s"
.segment Default
#import "../../../../core/6502/ui_help_clear.s"
.segmentdef TestCreateOverlay [start=$D000]
.segmentdef TestNameStreams [start=$E100]
.segmentdef TestStoreOverlay [start=$d000, min=$d000, max=$ffff]
.segment TestCreateOverlay
#import "../../../../core/6502/background_data.s"
#import "../../../../core/6502/player_create.s"
.segment Default
#import "../../../../core/6502/sound.s"
#import "../../../../core/6502/dungeon_data.s"
dg_idx: .byte 0
#import "../../../../core/6502/huffman.s"
#import "../../../../core/6502/dungeon_features.s"
#import "chest_summons_stubs.s"
#import "../../../../core/6502/monster.s"
#import "../../../../core/6502/tier_manager.s"
#import "../../common/overlay.s"
#import "../../../../core/6502/recall.s"
.segmentdef TestUnusedCombat [start=$d000, min=$d000, max=$dfff]
.segment TestUnusedCombat
#import "../../../../core/6502/monster_magic.s"
.segment Default
// Adding to the pack (inv_add.s) is not exercised here: parked out of
// reach, the runner's tripwire (tools/parked_tripwire.py) failing the
// suite if it is ever called (the VMS weight limit, 2026-11-13, took
// the body past MAP_BASE).
#define INV_ADD_EXTERNAL
#import "../../../../core/6502/item.s"
#undef INV_ADD_EXTERNAL
.segmentdef TestParkedInvAdd [start=$f200]
.segment TestParkedInvAdd
#import "../../../../core/6502/inv_add.s"
.segment TestUnusedCombat
random_floor_in_room:
    lda #0
    tay
    rts
#import "../../../../core/6502/special_rooms.s"
.segment Default
// The resistance armour and crown roll and its data are not exercised here
// (no item spawns): out of the way with the store code past $D000.
#define EGO_ARMOUR_SEGMENT_CUSTOM
.macro EgoArmourSegment() {
    .segment TestStoreOverlay
}
.macro EgoArmourRestoreSegment() {
    .segment Default
}
#define EGO_ARMOUR_DATA_SEGMENT_CUSTOM
.macro EgoArmourDataSegment() {
    .segment TestStoreOverlay
}
.macro EgoArmourDataRestoreSegment() {
    .segment Default
}
.segment TestStoreOverlay
#import "../../../../core/6502/ego_items.s"
#import "../../../../core/6502/special_rooms_stubs.s"
#import "../../../../core/6502/player_items.s"
.segment Default
#import "../../../../core/6502/spell_data.s"
.segmentdef TestUnusedPlay [start=$d000, min=$d000, max=$fff9]
.segment TestUnusedPlay
#import "../../../../core/6502/projectile.s"
#import "../../../../core/6502/dungeon_los.s"
#import "../../../../core/6502/player_move.s"
#import "../../../../core/6502/combat.s"
#import "../../../../core/6502/scene_mat_tile.s"
#import "../../../../core/6502/monster_attack.s"
#import "../../../../core/6502/turn.s"
.segment TestUnused
#import "../../../../core/6502/trap_trigger_cold.s"
#import "../../../../core/6502/player_chargen_cold.s"
#import "../../../../core/6502/item_spawn_cold.s"
#import "../../../../core/6502/pick_item_type_cold.s"
.segment Default
#import "../../../../core/6502/store_data.s"
// Store code goes in a dummy overlay segment so it doesn't bloat the test body.
// test_save.s doesn't test store code, but turn.s→tramp_store_restock_all
// needs these symbols. Placing them past $D000 avoids overlapping MAP_BASE.
.segment TestStoreOverlay
#import "../../../../core/6502/store.s"
#import "../../../../core/6502/ui_store.s"
// spell_effects.s only links here (no save test casts): 16-item stores
// grew the store arrays in the test body.
#import "../../../../core/6502/spell_effects.s"
#import "../dungeon_render.s"
.segment Default

#define C64_TEST_NO_SPELL_NAME_STUBS
#import "../../../../core/6502/ui_trampoline_stubs.s"
#import "../../../../core/6502/runtime_ui_strings.s"
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
.const hal_storage_save_version = $22
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
.label hal_storage_read_command_status = test_save_read_command_status
.label hal_storage_dos_code_status = disk_dos_code_status
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
tramp_disk_prepare_selected:
    inc test_save_prepare_selected_calls
    lda test_save_prepare_selected_result
    beq !fail+
    lda #1
    sta test_save_marker_present
    clc
    rts
!fail:
    sec
    rts
hal_storage_init_command:
    .byte $49, $30
hal_storage_save_write_name:
    .byte $40, $30, $3a
    .byte $54, $45, $53, $54
    .byte $2c, $53, $2c, $57
.label hal_storage_save_write_name_len = * - hal_storage_save_write_name
    .byte $57
.label hal_storage_save_probe_name = hal_storage_save_write_name + 1
.label hal_storage_save_probe_name_len = hal_storage_save_write_name_len - 1
hal_storage_save_read_name:
    .byte $30, $3a
    .byte $54, $45, $53, $54
    .byte $2c, $53, $2c, $52
.label hal_storage_save_read_name_len = * - hal_storage_save_read_name
    .byte $52
#import "../../../shared/save.s"
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
tc_results: .fill 45, $ff

// ui_character.s dropped to keep the test body under MAP_BASE.
ui_char_display:
    rts
count_spells_known:
    jmp spell_mask_count_ptr
tc_count: .byte 0

// Verification buffer — 256 bytes at $CF00 (floor item area, safe during tests 2-3)
.const VERIFY_BUF = $CF00

// Memory-backed save stream used by persistence tests. MAP_BASE is unused
// after the RLE tests and gives enough room for the item save blocks.
.const SAVE_STREAM_BUF = MAP_BASE
// Full save_game + load_game round-trip in Test 45 (~4.1 KB with zeroed map)
// sits between test_body_end and MAP_BASE so it never touches MAP_BASE or $D000.
.const T45_STREAM_BUF = MAP_BASE - $1100

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
test_save_prepare_selected_result: .byte 0
test_save_prepare_selected_calls: .byte 0
test_save_open_fail: .byte 0
test_save_chkin_fail: .byte 0
test_save_cmd_status: .byte 0
test_save_cmd_calls: .byte 0
test_save_magic_readst: .byte 0
test_save_eof_lo:       .byte 0
test_save_eof_hi:       .byte 0
test_save_end_lo:       .byte 0
test_save_end_hi:       .byte 0
test_save_t45_ck_active:.byte 0
test_save_t45_ck0_lo:   .byte 0
test_save_t45_ck0_hi:   .byte 0
test_save_t45_ck1_lo:   .byte 0
test_save_t45_ck1_hi:   .byte 0
test_save_t45_ck_lo:    .byte 0
test_save_t45_ck_hi:    .byte 0

.macro PatchJump(target, replacement) {
    lda #$4c
    sta target
    lda #<replacement
    sta target + 1
    lda #>replacement
    sta target + 2
}

test_save_read_command_status:
    inc test_save_cmd_calls
    lda test_save_cmd_status
    sta disk_status
    rts

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
    lda test_save_open_fail
    beq !open_ok+
    sec
    rts
!open_ok:
    clc
    rts

test_save_chkin:
    lda test_save_chkin_fail
    beq !chkin_ok+
    sec
    rts
!chkin_ok:
test_save_clrchn:
    clc
    rts

test_save_readst:
    lda test_save_magic_readst
    bne !sticky+
    lda test_save_readst_value
    pha
    lda #0
    sta test_save_readst_value
    pla
!sticky:
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
    sta (zp_ptr2),y
    inc zp_ptr2
    bne !+
    inc zp_ptr2_hi
!:  ldy test_save_tmp_y
    clc
    rts
!sink:
    pla
    clc
    rts

test_save_chrin:
    sty test_save_tmp_y
    lda test_save_eof_hi
    beq !read_next+
    lda zp_ptr2_hi
    cmp test_save_eof_hi
    bcc !read_next+
    bne !at_eof+
    lda zp_ptr2
    cmp test_save_eof_lo
    bcc !read_next+
!at_eof:
    lda #$40
    sta test_save_readst_value
    lda #$00
    ldy test_save_tmp_y
    clc
    rts
!read_next:
    lda test_save_t45_ck_active
    beq !read_mem+
    lda zp_ptr2_hi
    cmp test_save_t45_ck0_hi
    bne !chk_ck1+
    lda zp_ptr2
    cmp test_save_t45_ck0_lo
    bne !chk_ck1+
    lda test_save_t45_ck_lo
    jmp !got_byte+
!chk_ck1:
    lda zp_ptr2_hi
    cmp test_save_t45_ck1_hi
    bne !read_mem+
    lda zp_ptr2
    cmp test_save_t45_ck1_lo
    bne !read_mem+
    lda test_save_t45_ck_hi
    jmp !got_byte+
!read_mem:
    ldy #0
    lda (zp_ptr2),y
!got_byte:
    inc zp_ptr2
    bne !+
    inc zp_ptr2_hi
!:  pha
    lda test_save_eof_hi
    beq !no_eof+
    lda zp_ptr2_hi
    cmp test_save_eof_hi
    bcc !no_eof+
    bne !hit_eof+
    lda zp_ptr2
    cmp test_save_eof_lo
    bcc !no_eof+
!hit_eof:
    lda #$40
    sta test_save_readst_value
!no_eof:
    pla
    ldy test_save_tmp_y
    clc
    rts

test_save_file_not_exists:
    inc test_save_file_exists_calls
    clc
    rts

test_save_file_exists:
    inc test_save_file_exists_calls
    sec
    rts

test_huff_print_msg:
    stx test_save_last_msg
    rts

test_modal_dismiss_key:
    inc test_save_dismiss_calls
    rts

test_stream_reset_write:
    lda #<SAVE_STREAM_BUF
    sta zp_ptr2
    lda #>SAVE_STREAM_BUF
    sta zp_ptr2_hi
    rts

test_stream_reset_read:
    lda #<SAVE_STREAM_BUF
    sta zp_ptr2
    lda #>SAVE_STREAM_BUF
    sta zp_ptr2_hi
    rts

// Load a current-version door-state block whose count byte is A.
test_load_door_count:
    sta SAVE_STREAM_BUF
    jsr test_stream_reset_read
    jsr ts_reset_io_state
    jmp load_read_door_state

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
    sta si_meta_hi,x
    dex
    bpl !fields-
    rts

test_save_item_state_blocks:
    :save_block(inv_item_id, 8 * TOTAL_INV_SLOTS)
    :save_block(si_item_id, 8 * STORE_TOTAL_SLOTS)
    jsr save_write_floor_items
    rts

test_load_item_state_blocks:
    :load_block(inv_item_id, 8 * TOTAL_INV_SLOTS)
    jsr save_sanitize_inv_ids
    :load_block(si_item_id, 8 * STORE_TOTAL_SLOTS)
    jsr save_sanitize_store_ids
    jsr load_read_floor_items
    rts

// One sentinel byte after an inventory section (the next block's start).
test_save_sentinel_value: .byte $5a
test_load_sentinel_value: .byte 0
test_save_sentinel:
    :save_block(test_save_sentinel_value, 1)
    rts
test_load_sentinel:
    lda #0
    sta test_load_sentinel_value
    :load_block(test_load_sentinel_value, 1)
    lda test_load_sentinel_value
    cmp #$5a
    rts

// ts_fill_inventory_pattern — a distinct byte in every slot of all 8 arrays.
// Slot 2: id 2, qty $42, p1 $82, to_hit $83, to_dam $81, to_ac $04,
// flags 3, ego $41. Slot 32: id 32, qty $60, p1 $a0, ego $50.
ts_fill_inventory_pattern:
    ldx #TOTAL_INV_SLOTS - 1
!fill:
    txa
    sta inv_item_id,x
    sta inv_flags,x
    inc inv_flags,x
    ora #$40
    sta inv_qty,x
    eor #$c0
    sta inv_p1,x
    sta inv_to_hit,x
    inc inv_to_hit,x
    sta inv_to_dam,x
    dec inv_to_dam,x
    sta inv_to_ac,x
    asl inv_to_ac,x
    sta inv_ego,x
    lsr inv_ego,x
    dex
    bpl !fill-
    rts

// The pre-single-block writer: 8 per-array blocks of TOTAL_INV_SLOTS.
test_save_per_array_inventory_blocks:
    :save_block(inv_item_id, TOTAL_INV_SLOTS)
    :save_block(inv_qty, TOTAL_INV_SLOTS)
    :save_block(inv_p1, TOTAL_INV_SLOTS)
    :save_block(inv_to_hit, TOTAL_INV_SLOTS)
    :save_block(inv_to_dam, TOTAL_INV_SLOTS)
    :save_block(inv_to_ac, TOTAL_INV_SLOTS)
    :save_block(inv_flags, TOTAL_INV_SLOTS)
    :save_block(inv_ego, TOTAL_INV_SLOTS)
    rts

// The product's inventory descriptor (last pre-inventory table entry).
test_save_product_inventory_desc:
    lda #<save_block_desc_inventory
    sta zp_ptr1
    lda #>save_block_desc_inventory
    sta zp_ptr1_hi
    lda #1
    jmp save_write_block_table

.macro t13_expect(value) {
    cmp #value
    beq !ok+
    jmp t13_fail
!ok:
}

// ts_reset_io_state — Zero save checksum and error state. Clobbers: A
ts_reset_io_state:
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    sta save_io_error
    sta test_save_open_fail
    sta test_save_chkin_fail
    sta test_save_cmd_status
    sta test_save_cmd_calls
    sta test_save_magic_readst
    sta test_save_eof_hi
    rts

// ts_clear_known_bits — Zero the full known-item bitset. Clobbers: A, X
ts_clear_known_bits:
    ldx #ID_KNOWN_BYTES - 1
    lda #0
!loop:
    sta id_known_bits,x
    dex
    bpl !loop-
    rts

// ts_expect_known_range / ts_expect_unknown_range — Check id_known state for
// IDs [X, Y) on active item_cur_page. Output: carry set = all matched.
// Clobbers: A, X
ts_range_end: .byte 0
// ts_fixed_known — Carry set when paged item (item_cur_page, X) is fixed-known
// (irfk_defaults: non-flavoured category or unknown_idx == $ff).
// Clobbers: A, Y (X preserved)
ts_fixed_known:
    bit item_cur_page
    bvs !tfk_p1+
    cpx #ITEM_PAGE_SIZE
    bcs !tfk_no+
    bcc !tfk_chk+
!tfk_p1:
    cpx #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)
    bcs !tfk_no+
!tfk_chk:
    txa
    jsr item_get_category_a
    cmp #ICAT_POTION
    bcc !tfk_yes+
    cmp #ICAT_AMULET
    bcs !tfk_yes+
    cmp #ICAT_BOOK
    beq !tfk_yes+
    txa
    jsr item_get_unknown_idx_a
    cmp #$ff
    beq !tfk_yes+
!tfk_no:
    clc
    rts
!tfk_yes:
    sec
    rts

ts_expect_known_range:
    sty ts_range_end
!loop:
    jsr id_known_test
    beq !bad+
    inx
    cpx ts_range_end
    bcc !loop-
    sec
    rts
!bad:
    clc
    rts
ts_expect_unknown_range:
    sty ts_range_end
!loop:
    jsr id_known_test
    bne !bad+
    inx
    cpx ts_range_end
    bcc !loop-
    sec
    rts
!bad:
    clc
    rts

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
    ldx #44
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
    lda #ITEM_SLOT_DAGGER                      // Dagger
    sta fi_item_id + 0
    .if (ITEM_PAGE_DAGGER != 0) {
        lda #ITEM_PAGE_DAGGER
        sta fi_meta_hi + 0
    }
    lda #ITEM_SLOT_RATION_OF_FOOD                     // Food
    sta fi_item_id + 3
    lda #ITEM_SLOT_LEATHER_ARMOR                      // Leather armor
    sta fi_item_id + 10
    lda #ITEM_SLOT_GOLD_SMALL                      // Gold (small)
    sta fi_item_id + 20
    lda #ITEM_SLOT_WOODEN_TORCH                     // Torch
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
    // Test 12: Only SAVE_VERSION ($22) is accepted; legacy V1 ($17),
    // intermediate ($0f, $18, $19, $20, $21), and future ($23) versions
    // are rejected, and load_game on a $17 save returns
    // LOAD_RESULT_UNSUPPORTED without reading or mutating game RAM.
    // ============================================================
    lda #SAVE_VERSION
    jsr save_version_supported
    bcs !t12_cur_ok+
    jmp !t12_fail+
!t12_cur_ok:
    lda #$17                    // Legacy C64 Save V1
    jsr save_version_supported
    bcs !t12_fail_far+
    lda #$18
    jsr save_version_supported
    bcs !t12_fail_far+
    lda #$19
    jsr save_version_supported
    bcs !t12_fail_far+
    lda #$20
    jsr save_version_supported
    bcs !t12_fail_far+
    lda #(SAVE_VERSION - 1)     // $21 (370-item pre-VMS-renumber V2)
    jsr save_version_supported
    bcs !t12_fail_far+
    lda #(SAVE_VERSION + 1)     // $23 (future)
    jsr save_version_supported
    bcs !t12_fail_far+
    lda #$0f
    jsr save_version_supported
    bcc !t12_stream_test+
!t12_fail_far:
    jmp !t12_fail+

!t12_stream_test:
    ldx #0
!t12_copy_hdr:
    lda save_magic,x
    sta SAVE_STREAM_BUF,x
    inx
    cpx #SAVE_MAGIC_SIZE - 1
    bcc !t12_copy_hdr-
    lda #$17
    sta SAVE_STREAM_BUF + SAVE_MAGIC_SIZE - 1
    lda #$aa
    sta SAVE_STREAM_BUF + SAVE_MAGIC_SIZE
    sta SAVE_STREAM_BUF + SAVE_MAGIC_SIZE + 1

    lda #$77
    sta player_data + PL_LEVEL
    jsr item_init_inventory
    jsr test_clear_store_items

    jsr ts_reset_io_state
    sta test_save_last_msg
    sta test_save_readst_value
    sta test_save_close_arms_readst
    sta test_save_sink_writes
    lda #1
    sta test_save_marker_present
    sta disk_setup_done
    lda #2
    sta disk_mode
    lda #8
    sta save_device
    jsr test_stream_reset_read
    jsr load_game
    php
    lda #0
    sta test_save_marker_present
    plp
    bcs !t12_fail+
    lda load_result
    cmp #LOAD_RESULT_UNSUPPORTED
    bne !t12_fail+
    lda test_save_last_msg
    cmp #HSTR_SAVE_UNSUPPORTED
    bne !t12_fail+
    lda zp_ptr2
    cmp #<(SAVE_STREAM_BUF + SAVE_MAGIC_SIZE)
    bne !t12_fail+
    lda zp_ptr2_hi
    cmp #>(SAVE_STREAM_BUF + SAVE_MAGIC_SIZE)
    bne !t12_fail+
    lda player_data + PL_LEVEL
    cmp #$77
    bne !t12_fail+
    lda inv_item_id
    cmp #FI_EMPTY
    bne !t12_fail+
    lda si_item_id
    cmp #FI_EMPTY
    bne !t12_fail+
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
    jsr ts_reset_io_state
    sta test_save_sink_writes

    jsr item_init_inventory
    jsr item_init_floor
    jsr test_clear_store_items

    // Inventory slot 2: weapon-like item with split combat stats.
    lda #ITEM_SLOT_DAGGER
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
    lda #(EGO_FLAME_TONGUE | ITEM_PAGE_DAGGER)
    sta inv_ego + 2

    // Equipment body slot: armor AC must persist independently.
    lda #ITEM_SLOT_LEATHER_ARMOR
    sta inv_item_id + EQUIP_BODY
    lda #1
    sta inv_qty + EQUIP_BODY
    lda #5
    sta inv_to_ac + EQUIP_BODY
    lda #IF_IDENTIFIED
    sta inv_flags + EQUIP_BODY

    // New V3 amulet slot: save/load must preserve the 31st slot.
    lda #ITEM_SLOT_RING_OF_STRENGTH
    sta inv_item_id + EQUIP_AMULET
    .if (ITEM_PAGE_RING_OF_STRENGTH != 0) {
        lda #ITEM_PAGE_RING_OF_STRENGTH
        sta inv_ego + EQUIP_AMULET
    }
    lda #1
    sta inv_qty + EQUIP_AMULET
    lda #$7f
    sta inv_p1 + EQUIP_AMULET
    lda #IF_IDENTIFIED
    sta inv_flags + EQUIP_AMULET

    // Boundary IDs: first appended (96) and last appended (127) must persist.
    lda #ITEM_SLOT_POTION_OF_HEALING
    sta inv_item_id + 3
    lda #1
    sta inv_qty + 3
    lda #12
    sta inv_p1 + 3
    lda #IF_IDENTIFIED
    sta inv_flags + 3
    lda #ITEM_SLOT_STAFF_OF_REMOVE_CURSE
    sta inv_item_id + 4
    lda #1
    sta inv_qty + 4
    lda #9
    sta inv_p1 + 4
    lda #IF_TRIED
    sta inv_flags + 4

    // Store/home slot 10: packed flags+ego plus split stat sidecars.
    lda #ITEM_SLOT_GOLD_LARGE
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
    lda #(IF_IDENTIFIED | IF_SENSED)
    sta si_meta + 10
    lda #EGO_DEFENDER
    sta si_meta_hi + 10

    // Floor slot 3: V2 stores raw fi_meta flags and fi_meta_hi ego/page.
    lda #ITEM_SLOT_DAGGER
    sta fi_item_id + 3
    lda #11
    sta fi_x + 3
    lda #12
    sta fi_y + 3
    lda #2
    sta fi_qty + 3
    lda #$55
    sta fi_p1 + 3
    lda #(IF_IDENTIFIED | IF_CURSED)
    sta fi_meta + 3
    lda #(EGO_FROST_BRAND | ITEM_PAGE_DAGGER)
    sta fi_meta_hi + 3
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
    jsr ts_reset_io_state
    jsr test_load_item_state_blocks

    lda inv_item_id + 2
    :t13_expect(ITEM_SLOT_DAGGER)
    lda inv_p1 + 2
    :t13_expect($44)
    lda inv_to_hit + 2
    :t13_expect($fb)
    lda inv_to_dam + 2
    :t13_expect(7)
    lda inv_flags + 2
    :t13_expect(IF_IDENTIFIED | IF_CURSED)
    lda inv_ego + 2
    :t13_expect(EGO_FLAME_TONGUE | ITEM_PAGE_DAGGER)

    lda inv_item_id + EQUIP_BODY
    :t13_expect(ITEM_SLOT_LEATHER_ARMOR)
    lda inv_to_ac + EQUIP_BODY
    :t13_expect(5)
    lda inv_flags + EQUIP_BODY
    :t13_expect(IF_IDENTIFIED)

    lda inv_item_id + EQUIP_AMULET
    :t13_expect(ITEM_SLOT_RING_OF_STRENGTH)
    .if (ITEM_PAGE_RING_OF_STRENGTH != 0) {
        lda inv_ego + EQUIP_AMULET
        :t13_expect(ITEM_PAGE_RING_OF_STRENGTH)
    }
    lda inv_qty + EQUIP_AMULET
    :t13_expect(1)
    lda inv_p1 + EQUIP_AMULET
    :t13_expect($7f)
    lda inv_flags + EQUIP_AMULET
    :t13_expect(IF_IDENTIFIED)

    lda inv_item_id + 3
    :t13_expect(ITEM_SLOT_POTION_OF_HEALING)
    lda inv_qty + 3
    :t13_expect(1)
    lda inv_p1 + 3
    :t13_expect(12)
    lda inv_flags + 3
    :t13_expect(IF_IDENTIFIED)
    lda inv_item_id + 4
    :t13_expect(ITEM_SLOT_STAFF_OF_REMOVE_CURSE)
    lda inv_qty + 4
    :t13_expect(1)
    lda inv_p1 + 4
    :t13_expect(9)
    lda inv_flags + 4
    :t13_expect(IF_TRIED)

    lda si_item_id + 10
    :t13_expect(ITEM_SLOT_GOLD_LARGE)
    lda si_p1 + 10
    :t13_expect($33)
    lda si_to_hit + 10
    :t13_expect(3)
    lda si_to_dam + 10
    :t13_expect($fe)
    lda si_to_ac + 10
    :t13_expect(6)
    lda si_meta + 10
    :t13_expect(IF_IDENTIFIED | IF_SENSED)
    lda si_meta_hi + 10
    :t13_expect(EGO_DEFENDER)

    lda fi_item_id + 3
    :t13_expect(ITEM_SLOT_DAGGER)
    lda fi_x + 3
    :t13_expect(11)
    lda fi_y + 3
    :t13_expect(12)
    lda fi_qty + 3
    :t13_expect(2)
    lda fi_p1 + 3
    :t13_expect($55)
    lda fi_meta + 3
    :t13_expect(IF_IDENTIFIED | IF_CURSED)
    lda fi_meta_hi + 3
    :t13_expect(EGO_FROST_BRAND | ITEM_PAGE_DAGGER)
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
    jsr ts_reset_io_state
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
    // Test 15: saving to a configured non-save disk enters the selected-disk
    // prepare/init flow instead of reporting "Wrong Save Disk" directly.
    // ============================================================
    jsr ts_reset_io_state
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
    sta test_save_prepare_selected_result
    sta test_save_prepare_selected_calls
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
    lda test_save_prepare_selected_calls
    cmp #1
    beq !t15_prepare_ok+
    lda #3
    jmp t15_fail_code
!t15_prepare_ok:
    lda test_save_last_msg
    beq !t15_msg_ok+
    lda #4
    jmp t15_fail_code
!t15_msg_ok:
    lda #0
    sta test_save_marker_present
    sta test_save_marker_status
    sta test_save_marker_lsr_return
    sta test_save_sink_writes
    sta test_save_prepare_selected_calls
    lda #$01
    bne !t15_store+
t15_fail_code:
    pha
    sta test_save_marker_present
    sta test_save_marker_status
    sta test_save_marker_lsr_return
    sta test_save_sink_writes
    sta test_save_prepare_selected_calls
    pla
!t15_store:
    sta tc_results + 14

    // ============================================================
    // Test 16: C64 save-media I/O failures report Disk error!,
    // not Wrong Save Disk. disk_status=1 means marker mismatch;
    // other nonzero values are hardware/media I/O status.
    // ============================================================
    jsr ts_reset_io_state
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
    jsr ts_reset_io_state
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
    lda #$30                    // 01 FILES SCRATCHED: informational
    ldx #$31
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_OK
    beq !t19_ok_01+
    lda #8
    jmp t19_fail_code
!t19_ok_01:
    lda #$31                    // 19: the top of the informational range
    ldx #$39
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_OK
    beq !t19_ok_19+
    lda #9
    jmp t19_fail_code
!t19_ok_19:
    lda #$37                    // 73: the DOS banner after a reset
    ldx #$33
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_OK
    beq !t19_ok_73+
    lda #10
    jmp t19_fail_code
!t19_ok_73:
    lda #$32                    // 20: the first error code
    ldx #$30
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq !t19_ok_20+
    lda #11
    jmp t19_fail_code
!t19_ok_20:
    lda #$30                    // a first digit with no second one read
    ldx #$0d
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq !t19_ok_nodigit+
    lda #12
    jmp t19_fail_code
!t19_ok_nodigit:
    lda #$30                    // the $ff "never read" seed as the second digit
    ldx #$ff
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq !t19_ok_seed2+
    lda #13
    jmp t19_fail_code
!t19_ok_seed2:
    lda #$31                    // ':' just past '9'
    ldx #$3a
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq !t19_ok_colon+
    lda #14
    jmp t19_fail_code
!t19_ok_colon:
    lda #$ff                    // the seed as the first digit
    ldx #$ff
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq !t19_ok_seed1+
    lda #15
    jmp t19_fail_code
!t19_ok_seed1:
    lda #$2f                    // just below '0' as the first digit
    ldx #$30
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq !t19_ok_low1+
    lda #16
    jmp t19_fail_code
!t19_ok_low1:
    lda #$30                    // ...and as the second
    ldx #$2f
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    beq !t19_ok_low2+
    lda #17
    jmp t19_fail_code
!t19_ok_low2:
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

    // ============================================================
    // Test 23: V2 known-item round-trip writes ID_KNOWN_BYTES (47 B),
    // preserves Page 0 and Page 1 known bits, refreshes fixed-known
    // items, and keeps spare capacity bits (361-375) clear.
    // ============================================================
    jsr ts_reset_io_state
    sta test_save_sink_writes
    jsr ts_clear_known_bits
    lda #0
    sta item_cur_page
    ldx #0
!t23_seed_p0:
    txa
    and #1
    beq !t23_skip_p0+
    jsr id_known_set
!t23_skip_p0:
    inx
    cpx #ITEM_PAGE_SIZE
    bcc !t23_seed_p0-
    lda #ITEM_PAGE_BIT
    sta item_cur_page
    ldx #0
!t23_seed_p1:
    txa
    and #1
    beq !t23_skip_p1+
    jsr id_known_set
!t23_skip_p1:
    inx
    cpx #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)
    bcc !t23_seed_p1-

    jsr test_stream_reset_write
    jsr save_write_known_items
    lda zp_ptr2
    cmp #<(SAVE_STREAM_BUF + ID_KNOWN_BYTES)
    beq !t23_len_lo_ok+
    lda #2
    jmp t23_fail_code
!t23_len_lo_ok:
    lda zp_ptr2_hi
    cmp #>(SAVE_STREAM_BUF + ID_KNOWN_BYTES)
    beq !t23_len_hi_ok+
    lda #2
    jmp t23_fail_code
!t23_len_hi_ok:

    jsr ts_clear_known_bits
    jsr test_stream_reset_read
    jsr load_read_known_items

    lda #0
    sta item_cur_page
    ldx #0
!t23_chk_p0:
    txa
    and #1
    bne !t23_p0_need_known+
    jsr ts_fixed_known
    bcs !t23_p0_need_known+
    jsr id_known_test
    beq !t23_p0_next+
    lda #3
    jmp t23_fail_code
!t23_p0_need_known:
    jsr id_known_test
    bne !t23_p0_next+
    lda #3
    jmp t23_fail_code
!t23_p0_next:
    inx
    cpx #ITEM_PAGE_SIZE
    bcc !t23_chk_p0-

    lda #ITEM_PAGE_BIT
    sta item_cur_page
    ldx #0
!t23_chk_p1:
    txa
    and #1
    bne !t23_p1_need_known+
    jsr ts_fixed_known
    bcs !t23_p1_need_known+
    jsr id_known_test
    beq !t23_p1_next+
    lda #4
    jmp t23_fail_code
!t23_p1_need_known:
    jsr id_known_test
    bne !t23_p1_next+
    lda #4
    jmp t23_fail_code
!t23_p1_next:
    inx
    cpx #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)
    bcc !t23_chk_p1-

    .assert "361 occupies bit 0 of byte 45 (second-to-last known byte)", (ITEM_TYPE_COUNT >> 3) == (ID_KNOWN_BYTES - 2) && (ITEM_TYPE_COUNT & 7) == 1, true
    lda id_known_bits + ID_KNOWN_BYTES - 2
    and #$fe
    ora id_known_bits + ID_KNOWN_BYTES - 1
    beq !t23_spare_ok+
    lda #5
    jmp t23_fail_code
!t23_spare_ok:
    lda #0
    sta item_cur_page
    lda save_io_error
    beq !t23_ok+
    lda #6
    jmp t23_fail_code
!t23_ok:
    lda #$01
    bne !t23_store+
t23_fail_code:
!t23_store:
    sta tc_results + 22

    // ============================================================
    // Test 24: V2 34-slot inventory preserves EQUIP_CLOAK (32),
    // EQUIP_SECONDARY (33), and Page-1 ITEM_PAGE_BIT entries.
    // ============================================================
    jsr ts_reset_io_state
    sta test_save_sink_writes
    jsr item_init_inventory
    lda #ITEM_SLOT_CLEAR_POTION_OF_WATER
    sta inv_item_id + 1
    lda #3
    sta inv_qty + 1
    lda #IF_IDENTIFIED
    sta inv_flags + 1
    lda #ITEM_PAGE_CLEAR_POTION_OF_WATER
    sta inv_ego + 1

    lda #ITEM_SLOT_CLOAK
    sta inv_item_id + EQUIP_CLOAK
    lda #1
    sta inv_qty + EQUIP_CLOAK
    lda #$03
    sta inv_p1 + EQUIP_CLOAK
    lda #4
    sta inv_to_ac + EQUIP_CLOAK
    lda #IF_IDENTIFIED
    sta inv_flags + EQUIP_CLOAK
    lda #(ITEM_PAGE_CLOAK | EGO_STEALTH)
    sta inv_ego + EQUIP_CLOAK

    lda #ITEM_SLOT_DAGGER
    sta inv_item_id + EQUIP_SECONDARY
    lda #1
    sta inv_qty + EQUIP_SECONDARY
    lda #2
    sta inv_to_hit + EQUIP_SECONDARY
    lda #3
    sta inv_to_dam + EQUIP_SECONDARY
    lda #(IF_IDENTIFIED | IF_CURSED)
    sta inv_flags + EQUIP_SECONDARY
    lda #(ITEM_PAGE_DAGGER | EGO_SLAY_EVIL)
    sta inv_ego + EQUIP_SECONDARY

    jsr test_stream_reset_write
    :save_block(inv_item_id, 8 * TOTAL_INV_SLOTS)
    jsr test_save_sentinel

    jsr item_init_inventory
    jsr test_stream_reset_read
    jsr ts_reset_io_state
    :load_block(inv_item_id, 8 * TOTAL_INV_SLOTS)
    jsr save_sanitize_inv_ids

    lda inv_item_id + 1
    cmp #ITEM_SLOT_CLEAR_POTION_OF_WATER
    beq !t24_p1_id_ok+
    lda #2
    jmp t24_fail_code
!t24_p1_id_ok:
    lda inv_ego + 1
    cmp #ITEM_PAGE_CLEAR_POTION_OF_WATER
    beq !t24_p1_bit_ok+
    lda #3
    jmp t24_fail_code
!t24_p1_bit_ok:
    lda inv_item_id + EQUIP_CLOAK
    cmp #ITEM_SLOT_CLOAK
    beq !t24_clk_id_ok+
    lda #4
    jmp t24_fail_code
!t24_clk_id_ok:
    lda inv_to_ac + EQUIP_CLOAK
    cmp #4
    beq !t24_clk_ac_ok+
    lda #5
    jmp t24_fail_code
!t24_clk_ac_ok:
    lda inv_ego + EQUIP_CLOAK
    cmp #(ITEM_PAGE_CLOAK | EGO_STEALTH)
    beq !t24_clk_ego_ok+
    lda #6
    jmp t24_fail_code
!t24_clk_ego_ok:
    lda inv_item_id + EQUIP_SECONDARY
    cmp #ITEM_SLOT_DAGGER
    beq !t24_sec_id_ok+
    lda #7
    jmp t24_fail_code
!t24_sec_id_ok:
    lda inv_ego + EQUIP_SECONDARY
    cmp #(ITEM_PAGE_DAGGER | EGO_SLAY_EVIL)
    beq !t24_sec_ego_ok+
    lda #8
    jmp t24_fail_code
!t24_sec_ego_ok:
    jsr test_load_sentinel
    beq !t24_sentinel_ok+
    lda #9
    jmp t24_fail_code
!t24_sentinel_ok:
    lda #$01
    bne !t24_store+
t24_fail_code:
!t24_store:
    sta tc_results + 23

    // ============================================================
    // Test 25: load_game accepts a markerless configured disk when
    // the save file itself exists. This guards the C128 single-drive
    // path where Disk Setup accepts THE.GAME but the load precheck
    // used to reject the same disk on marker-only validation.
    // ============================================================
    :PatchJump(save_file_exists, test_save_file_exists)
    lda #0
    sta test_save_last_msg
    sta test_save_dismiss_calls
    sta test_save_readst_value
    sta test_save_close_arms_readst
    sta test_save_sink_writes
    sta test_save_marker_present
    sta test_save_file_exists_calls
    sta test_save_open_calls
    lda #1
    sta disk_setup_done
    lda #2
    sta disk_mode
    lda #8
    sta save_device
    lda #9
    sta program_device
    jsr test_stream_reset_read
    jsr load_game
    lda test_save_file_exists_calls
    cmp #1
    beq !t25_exists_ok+
    lda #2
    jmp t25_fail_code
!t25_exists_ok:
    lda test_save_open_calls
    cmp #1
    beq !t25_open_ok+
    lda #3
    jmp t25_fail_code
!t25_open_ok:
    lda test_save_last_msg
    cmp #HSTR_SAVE_NEED_SAVE
    bne !t25_msg_ok+
    lda #4
    jmp t25_fail_code
!t25_msg_ok:
    lda #$01
    bne !t25_store+
t25_fail_code:
!t25_store:
    sta tc_results + 24

    // ============================================================
    // Test 26: V2 floor-item p1 vs gold qty_hi honors ITEM_PAGE_BIT:
    // Page-0 slot 0/1 reads qty_hi -> fi_p1; Page-1 slot 0/1 keeps fi_p1.
    // ============================================================
    jsr ts_reset_io_state
    sta test_save_sink_writes
    jsr item_init_floor
    lda #ITEM_SLOT_GOLD_SMALL                      // Page 0 gold (slot_lo = 0)
    sta fi_item_id + 0
    sta fi_meta_hi + 0
    lda #$34
    sta fi_qty + 0
    lda #$12
    sta fi_p1 + 0
    lda #4
    sta fi_x + 0
    lda #5
    sta fi_y + 0

    lda #0                      // Page 1 logical 255 (slot_lo = 0)
    sta fi_item_id + 1          // raw-id-ok: synthetic boundary test
    lda #(ITEM_PAGE_BIT | EGO_RESIST)
    sta fi_meta_hi + 1
    lda #2
    sta fi_qty + 1
    lda #$7a
    sta fi_p1 + 1
    lda #6
    sta fi_x + 1
    lda #7
    sta fi_y + 1
    lda #IF_IDENTIFIED
    sta fi_meta + 1

    lda #1                      // Page 1 logical 256 (slot_lo = 1)
    sta fi_item_id + 2          // raw-id-ok: synthetic boundary test
    lda #ITEM_PAGE_BIT
    sta fi_meta_hi + 2
    lda #$5b
    sta fi_p1 + 2
    lda #8
    sta fi_x + 2
    lda #9
    sta fi_y + 2

    jsr test_stream_reset_write
    jsr save_write_floor_items

    jsr item_init_floor
    jsr test_stream_reset_read
    jsr ts_reset_io_state
    jsr load_read_floor_items

    lda fi_item_id + 0
    beq !t26_g0_id+
    lda #2
    jmp t26_fail_code
!t26_g0_id:
    lda fi_qty + 0
    cmp #$34
    bne !t26_g0_fail+
    lda fi_p1 + 0
    cmp #$12
    beq !t26_p1_chk+
!t26_g0_fail:
    lda #3
    jmp t26_fail_code
!t26_p1_chk:
    lda fi_item_id + 1
    bne !t26_p1_fail+
    lda fi_meta_hi + 1
    cmp #(ITEM_PAGE_BIT | EGO_RESIST)
    bne !t26_p1_fail+
    lda fi_p1 + 1
    cmp #$7a
    beq !t26_p2_chk+
!t26_p1_fail:
    lda #4
    jmp t26_fail_code
!t26_p2_chk:
    lda fi_item_id + 2
    cmp #1 // raw-id-ok: synthetic boundary test
    bne !t26_p2_fail+
    lda fi_meta_hi + 2
    cmp #ITEM_PAGE_BIT
    bne !t26_p2_fail+
    lda fi_p1 + 2
    cmp #$5b
    beq !t26_ok+
!t26_p2_fail:
    lda #5
    jmp t26_fail_code
!t26_ok:
    lda #$01
    bne !t26_store+
t26_fail_code:
!t26_store:
    sta tc_results + 25

    // ============================================================
    // Test 27: invalid item IDs in an inventory save stream wipe to
    // empty on load (save_sanitize_inv_ids); valid Page-0/Page-1 IDs
    // survive.
    // ============================================================
    jsr ts_reset_io_state
    sta test_save_sink_writes
    jsr item_init_inventory
    lda #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)  // Invalid Page 1 ID (=361)
    sta inv_item_id + 2
    lda #ITEM_PAGE_BIT
    sta inv_ego + 2
    lda #ITEM_SLOT_SMALL_WOODEN_CHEST
    sta inv_item_id + 3
    lda #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE - 1) // Max valid Page 1 (=360)
    sta inv_item_id + 4
    lda #ITEM_PAGE_BIT
    sta inv_ego + 4
    jsr test_stream_reset_write
    :save_block(inv_item_id, 8 * TOTAL_INV_SLOTS)

    jsr item_init_inventory
    jsr test_stream_reset_read
    jsr ts_reset_io_state
    :load_block(inv_item_id, 8 * TOTAL_INV_SLOTS)
    jsr save_sanitize_inv_ids

    lda inv_item_id + 2
    cmp #FI_EMPTY
    beq !t27_bad_ok+
    lda #2
    jmp t27_fail_code
!t27_bad_ok:
    lda inv_item_id + 3
    cmp #ITEM_SLOT_SMALL_WOODEN_CHEST
    beq !t27_good_ok+
    lda #3
    jmp t27_fail_code
!t27_good_ok:
    lda inv_item_id + 4
    cmp #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE - 1)
    beq !t27_p1_ok+
    lda #4
    jmp t27_fail_code
!t27_p1_ok:
    lda #$01
    bne !t27_store+
t27_fail_code:
!t27_store:
    sta tc_results + 26

    // ============================================================
    // Test 28: invalid Page-1 item IDs in a floor-item save stream
    // wipe to empty on load; valid chest & Page-1 IDs survive.
    // ============================================================
    jsr ts_reset_io_state
    sta test_save_sink_writes
    jsr item_init_floor
    lda #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)  // Invalid Page 1 ID (=361)
    sta fi_item_id + 1
    lda #ITEM_PAGE_BIT
    sta fi_meta_hi + 1
    lda #10
    sta fi_x + 1
    lda #12
    sta fi_y + 1
    lda #ITEM_SLOT_LARGE_STEEL_CHEST
    sta fi_item_id + 5
    lda #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE - 1) // Max valid Page 1 (=360)
    sta fi_item_id + 6
    lda #ITEM_PAGE_BIT
    sta fi_meta_hi + 6
    jsr test_stream_reset_write
    jsr save_write_floor_items

    jsr item_init_floor
    jsr test_stream_reset_read
    jsr ts_reset_io_state
    jsr load_read_floor_items

    lda fi_item_id + 1
    cmp #FI_EMPTY
    beq !t28_bad_ok+
    lda #2
    jmp t28_fail_code
!t28_bad_ok:
    lda fi_item_id + 5
    cmp #ITEM_SLOT_LARGE_STEEL_CHEST
    beq !t28_good_ok+
    lda #3
    jmp t28_fail_code
!t28_good_ok:
    lda fi_item_id + 6
    cmp #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE - 1)
    beq !t28_p1_ok+
    lda #4
    jmp t28_fail_code
!t28_p1_ok:
    lda #$01
    bne !t28_store+
t28_fail_code:
!t28_store:
    sta tc_results + 27

    // ============================================================
    // Test 29: save_sanitize_store_ids wipes invalid Page-1 store IDs
    // and keeps valid chest and Page-1 IDs.
    // ============================================================
    jsr test_clear_store_items
    lda #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)  // Invalid Page 1 ID (=361)
    sta si_item_id + 1
    lda #ITEM_PAGE_BIT
    sta si_meta_hi + 1
    lda #ITEM_SLOT_RUINED_CHEST
    sta si_item_id + 7
    lda #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE - 1) // Max valid Page 1 (=360)
    sta si_item_id + 8
    lda #ITEM_PAGE_BIT
    sta si_meta_hi + 8
    jsr save_sanitize_store_ids

    lda si_item_id + 1
    cmp #FI_EMPTY
    beq !t29_bad_ok+
    lda #2
    jmp t29_fail_code
!t29_bad_ok:
    lda si_item_id + 7
    cmp #ITEM_SLOT_RUINED_CHEST
    beq !t29_good_ok+
    lda #3
    jmp t29_fail_code
!t29_good_ok:
    lda si_item_id + 8
    cmp #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE - 1)
    beq !t29_p1_ok+
    lda #4
    jmp t29_fail_code
!t29_p1_ok:
    lda #$01
    bne !t29_store+
t29_fail_code:
!t29_store:
    sta tc_results + 28

    // ============================================================
    // Test 30: door-state table round-trips at the current save version.
    // ============================================================
    lda #2
    sta door_state_count
    lda #10
    sta door_state_x
    lda #20
    sta door_state_y
    lda #15                     // locked, difficulty 15
    sta door_state_val
    lda #11
    sta door_state_x + 1
    lda #21
    sta door_state_y + 1
    lda #$94                    // stuck, magnitude 20
    sta door_state_val + 1

    jsr test_stream_reset_write
    jsr save_write_door_state

    lda #0
    sta door_state_count
    sta door_state_x
    sta door_state_y
    sta door_state_val
    sta door_state_x + 1
    sta door_state_y + 1
    sta door_state_val + 1

    jsr test_stream_reset_read
    jsr ts_reset_io_state
    jsr load_read_door_state

    lda door_state_count
    cmp #2
    bne !t30_fail+
    lda door_state_x
    cmp #10
    bne !t30_fail+
    lda door_state_y
    cmp #20
    bne !t30_fail+
    lda door_state_val
    cmp #15
    bne !t30_fail+
    lda door_state_x + 1
    cmp #11
    bne !t30_fail+
    lda door_state_y + 1
    cmp #21
    bne !t30_fail+
    lda door_state_val + 1
    cmp #$94
    bne !t30_fail+
    lda save_io_error
    bne !t30_fail+
    lda #$01
    bne !t30_store+
!t30_fail:
    lda #$00
!t30_store:
    sta tc_results + 29

    // ============================================================
    // Test 31: V2 store block writes/reads all 8*STORE_TOTAL_SLOTS
    // (1024 B) including si_meta_hi Page-1 & ego persistence + sentinel.
    // ============================================================
    jsr ts_reset_io_state
    sta test_save_sink_writes
    jsr test_clear_store_items
    lda #ITEM_SLOT_DAGGER
    sta si_item_id + 0
    lda #IF_IDENTIFIED
    sta si_meta + 0
    lda #(ITEM_PAGE_DAGGER | EGO_FLAME_TONGUE)
    sta si_meta_hi + 0
    lda #ITEM_SLOT_CLEAR_POTION_OF_WATER
    sta si_item_id + (STORE_TOTAL_SLOTS - 1)
    lda #IF_SENSED
    sta si_meta + (STORE_TOTAL_SLOTS - 1)
    lda #(ITEM_PAGE_CLEAR_POTION_OF_WATER | EGO_MAGI)
    sta si_meta_hi + (STORE_TOTAL_SLOTS - 1)

    jsr test_stream_reset_write
    :save_block(si_item_id, 8 * STORE_TOTAL_SLOTS)
    jsr test_save_sentinel
    lda zp_ptr2
    cmp #<(SAVE_STREAM_BUF + 8 * STORE_TOTAL_SLOTS + 1)
    bne !t31_fail_far+
    lda zp_ptr2_hi
    cmp #>(SAVE_STREAM_BUF + 8 * STORE_TOTAL_SLOTS + 1)
    beq !t31_len_ok+
!t31_fail_far:
    jmp !t31_fail+
!t31_len_ok:
    jsr test_clear_store_items
    jsr test_stream_reset_read
    jsr ts_reset_io_state
    :load_block(si_item_id, 8 * STORE_TOTAL_SLOTS)
    jsr save_sanitize_store_ids

    lda save_io_error
    bne !t31_fail+
    lda si_item_id + 0
    cmp #ITEM_SLOT_DAGGER
    bne !t31_fail+
    lda si_meta_hi + 0
    cmp #(ITEM_PAGE_DAGGER | EGO_FLAME_TONGUE)
    bne !t31_fail+
    lda si_item_id + (STORE_TOTAL_SLOTS - 1)
    cmp #ITEM_SLOT_CLEAR_POTION_OF_WATER
    bne !t31_fail+
    lda si_meta + (STORE_TOTAL_SLOTS - 1)
    cmp #IF_SENSED
    bne !t31_fail+
    lda si_meta_hi + (STORE_TOTAL_SLOTS - 1)
    cmp #(ITEM_PAGE_CLEAR_POTION_OF_WATER | EGO_MAGI)
    bne !t31_fail+
    jsr test_load_sentinel
    bne !t31_fail+
    lda #$01
    bne !t31_store+
!t31_fail:
    lda #$00
!t31_store:
    sta tc_results + 30

    // ============================================================
    // Test 32: maximum representable door-state count is accepted.
    // ============================================================
    lda #MAX_DOOR_STATES
    jsr test_load_door_count
    lda save_io_error
    bne !t32_fail+
    lda door_state_count
    cmp #MAX_DOOR_STATES
    bne !t32_fail+
    lda #$01
    bne !t32_store+
!t32_fail:
    lda #$00
!t32_store:
    sta tc_results + 31

    // ============================================================
    // Test 33: count 17 is rejected before runtime table access.
    // ============================================================
    lda #MAX_DOOR_STATES + 1
    jsr test_load_door_count
    lda save_io_error
    beq !t33_fail+
    lda door_state_count
    bne !t33_fail+
    lda #$01
    bne !t33_store+
!t33_fail:
    lda #$00
!t33_store:
    sta tc_results + 32

    // ============================================================
    // Test 34: count 255 is rejected before runtime table access.
    // ============================================================
    lda #$ff
    jsr test_load_door_count
    lda save_io_error
    beq !t34_fail+
    lda door_state_count
    bne !t34_fail+
    lda #$01
    bne !t34_store+
!t34_fail:
    lda #$00
!t34_store:
    sta tc_results + 33

    // ============================================================
    // Test 35: the product inventory descriptor writes exactly the
    // stream the old writer did: 8 per-array blocks of TOTAL_INV_SLOTS,
    // inv_item_id first and inv_ego last.
    // ============================================================
    jsr ts_reset_io_state
    sta test_save_sink_writes
    jsr ts_fill_inventory_pattern
    lda #<(SAVE_STREAM_BUF + $200)
    sta zp_ptr2
    lda #>(SAVE_STREAM_BUF + $200)
    sta zp_ptr2_hi
    jsr test_save_per_array_inventory_blocks
    jsr test_stream_reset_write
    jsr test_save_product_inventory_desc
    lda zp_ptr2                     // stream length is exactly 8 * T
    cmp #<(SAVE_STREAM_BUF + 8 * TOTAL_INV_SLOTS)
    bne !t35_fail+
    lda zp_ptr2_hi
    cmp #>(SAVE_STREAM_BUF + 8 * TOTAL_INV_SLOTS)
    bne !t35_fail+
    ldx #0
!t35_cmp:                           // first min(8 * T, 256) bytes
    lda SAVE_STREAM_BUF,x
    cmp SAVE_STREAM_BUF + $200,x
    bne !t35_fail+
    inx
    cpx #<min(8 * TOTAL_INV_SLOTS, 256)
    bne !t35_cmp-
.if (8 * TOTAL_INV_SLOTS > 256) {
    ldx #0
!t35_cmp_hi:                        // the rest of the 8 * T bytes
    lda SAVE_STREAM_BUF + $100,x
    cmp SAVE_STREAM_BUF + $300,x
    bne !t35_fail+
    inx
    cpx #8 * TOTAL_INV_SLOTS - 256
    bne !t35_cmp_hi-
}
    lda SAVE_STREAM_BUF + 2                         // inv_item_id[2]
    cmp #2 // raw-id-ok: synthetic boundary test
    bne !t35_fail+
    lda SAVE_STREAM_BUF + TOTAL_INV_SLOTS + 2       // inv_qty[2]
    cmp #$42
    bne !t35_fail+
    lda SAVE_STREAM_BUF + 7 * TOTAL_INV_SLOTS + 2   // inv_ego[2] = ($42 ^ $c0) >> 1
    cmp #$41
    bne !t35_fail+
    lda SAVE_STREAM_BUF + EQUIP_CLOAK               // inv_item_id[32], the cloak
    cmp #EQUIP_CLOAK
    bne !t35_fail+
    lda SAVE_STREAM_BUF + EQUIP_SECONDARY           // inv_item_id[33], the secondary
    cmp #EQUIP_SECONDARY
    bne !t35_fail+
    lda SAVE_STREAM_BUF + (8 * TOTAL_INV_SLOTS - 1) // inv_ego[33], byte 271
    cmp #$50
    bne !t35_fail+
    lda save_io_error
    bne !t35_fail+
    lda #$01
    bne !t35_store+
!t35_fail:
    lda #$00
!t35_store:
    sta tc_results + 34

    // ============================================================
    // Test 36: a V2 inventory section round-trips all
    // 8 x 34 = 272 bytes (slots EQUIP_CLOAK=32, EQUIP_SECONDARY=33
    // populated) and reads back exactly 272 bytes.
    // ============================================================
    jsr ts_reset_io_state
    sta test_save_sink_writes
    jsr ts_fill_inventory_pattern
    .const T36_TAIL = 8 * TOTAL_INV_SLOTS - 256
    ldx #0
!t36_snap:
    lda inv_item_id,x
    sta SAVE_STREAM_BUF + $200,x
    lda inv_item_id + T36_TAIL,x
    sta SAVE_STREAM_BUF + $200 + T36_TAIL,x
    inx
    bne !t36_snap-
    jsr test_stream_reset_write
    jsr test_save_product_inventory_desc
    jsr item_init_inventory
    jsr test_stream_reset_read
    jsr ts_reset_io_state
    :load_block(inv_item_id, 8 * TOTAL_INV_SLOTS)
    lda zp_ptr2
    cmp #<(SAVE_STREAM_BUF + 8 * TOTAL_INV_SLOTS)
    bne !t36_fail+
    lda zp_ptr2_hi
    cmp #>(SAVE_STREAM_BUF + 8 * TOTAL_INV_SLOTS)
    bne !t36_fail+
    ldx #0
!t36_cmp:
    lda inv_item_id,x
    cmp SAVE_STREAM_BUF + $200,x
    bne !t36_fail+
    lda inv_item_id + T36_TAIL,x
    cmp SAVE_STREAM_BUF + $200 + T36_TAIL,x
    bne !t36_fail+
    inx
    bne !t36_cmp-
    lda inv_item_id + EQUIP_CLOAK
    cmp #EQUIP_CLOAK
    bne !t36_fail+
    lda inv_p1 + EQUIP_CLOAK
    cmp #$a0
    bne !t36_fail+
    lda inv_item_id + EQUIP_SECONDARY
    cmp #EQUIP_SECONDARY
    bne !t36_fail+
    lda inv_p1 + EQUIP_SECONDARY
    cmp #$a1
    bne !t36_fail+
    lda inv_ego + EQUIP_SECONDARY
    cmp #$50
    bne !t36_fail+
    lda save_io_error
    bne !t36_fail+
    lda #$01
    bne !t36_store+
!t36_fail:
    lda #$00
!t36_store:
    sta tc_results + 35

    // ============================================================
    // Test 37: 9-bit paged ID sanitization boundary edges across
    // Page 0 (0..254 valid, 255=empty) and Page 1 (255..360 valid,
    // 361+ wiped to FI_EMPTY) for inventory and floor tables.
    // ============================================================
    jsr item_init_inventory
    lda #(ITEM_PAGE_SIZE - 1)               // 254 (max Page 0)
    sta inv_item_id + 0                     // raw-id-ok: synthetic boundary test
    lda #0
    sta inv_ego + 0
    lda #FI_EMPTY                           // 255 (empty Page 0)
    sta inv_item_id + 1
    lda #0                                  // logical 255 (min Page 1)
    sta inv_item_id + 2                     // raw-id-ok: synthetic boundary test
    lda #ITEM_PAGE_BIT
    sta inv_ego + 2
    lda #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE - 1) // 105 (logical 360, max valid)
    sta inv_item_id + 3
    lda #(ITEM_PAGE_BIT | EGO_DEFENDER)
    sta inv_ego + 3
    lda #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE) // 106 (logical 361, invalid)
    sta inv_item_id + 4
    lda #ITEM_PAGE_BIT
    sta inv_ego + 4
    lda #(ITEM_PAGE_SIZE - 1)               // 254 on Page 1 (invalid)
    sta inv_item_id + 5                     // raw-id-ok: synthetic boundary test
    lda #ITEM_PAGE_BIT
    sta inv_ego + 5
    jsr save_sanitize_inv_ids

    lda inv_item_id + 0
    cmp #(ITEM_PAGE_SIZE - 1)               // raw-id-ok: synthetic boundary test
    bne !t37_fail+
    lda inv_item_id + 1
    cmp #FI_EMPTY
    bne !t37_fail+
    lda inv_item_id + 2
    bne !t37_fail+
    lda inv_ego + 2
    cmp #ITEM_PAGE_BIT
    bne !t37_fail+
    lda inv_item_id + 3
    cmp #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE - 1)
    bne !t37_fail+
    lda inv_ego + 3
    cmp #(ITEM_PAGE_BIT | EGO_DEFENDER)
    bne !t37_fail+
    lda inv_item_id + 4
    cmp #FI_EMPTY
    bne !t37_fail+
    lda inv_item_id + 5
    cmp #FI_EMPTY
    bne !t37_fail+

    jsr item_init_floor
    lda #(ITEM_PAGE_SIZE - 1)
    sta fi_item_id + 0                      // raw-id-ok: synthetic boundary test
    lda #0
    sta fi_meta_hi + 0
    lda #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE - 1)
    sta fi_item_id + 1
    lda #ITEM_PAGE_BIT
    sta fi_meta_hi + 1
    lda #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE)
    sta fi_item_id + 2
    lda #ITEM_PAGE_BIT
    sta fi_meta_hi + 2
    jsr save_sanitize_floor_ids
    lda fi_item_id + 0
    cmp #(ITEM_PAGE_SIZE - 1)               // raw-id-ok: synthetic boundary test
    bne !t37_fail+
    lda fi_item_id + 1
    cmp #(ITEM_TYPE_COUNT - ITEM_PAGE_SIZE - 1)
    bne !t37_fail+
    lda fi_item_id + 2
    cmp #FI_EMPTY
    bne !t37_fail+
    lda #$01
    bne !t37_store+
!t37_fail:
    lda #$00
!t37_store:
    sta tc_results + 36

    // ============================================================
    // Test 38: V2 post-known descriptor table streams FLAVOUR_COUNT
    // (174 B) shuffles, 8*STORE_TOTAL_SLOTS (1024 B) stores, and
    // level arrays cleanly with exact stream alignment.
    // ============================================================
    .const T38_BYTES = FLAVOUR_COUNT + (8 * STORE_TOTAL_SLOTS) + 7 + 1 + (MAX_ROOMS * 6) + (1 + MAX_TRAPS * 3) + (MAX_MONSTERS * MONSTER_ENTRY_SIZE)
    .assert "Test 38 post-known stream fits in MAP_BASE", T38_BYTES + 1 <= MAP_SIZE, true
    jsr ts_reset_io_state
    sta test_save_sink_writes
    jsr test_clear_store_items
    lda #$11
    sta potion_shuffle
    lda #$22
    sta staff_shuffle + FLAVOUR_STAFF_COUNT - 1
    lda #ITEM_SLOT_DAGGER
    sta si_item_id + STORE_TOTAL_SLOTS - 1
    lda #(ITEM_PAGE_DAGGER | EGO_SLAY_DRAGON)
    sta si_meta_hi + STORE_TOTAL_SLOTS - 1
    lda #$03
    sta level_entry_dir
    lda #$44
    sta monster_table
    jsr test_stream_reset_write
    lda #<save_block_table_post_known
    sta zp_ptr1
    lda #>save_block_table_post_known
    sta zp_ptr1_hi
    lda #SAVE_BLOCK_POST_KNOWN_COUNT
    jsr save_write_block_table
    jsr test_save_sentinel
    lda zp_ptr2
    cmp #<(SAVE_STREAM_BUF + T38_BYTES + 1)
    bne !t38_fail+
    lda zp_ptr2_hi
    cmp #>(SAVE_STREAM_BUF + T38_BYTES + 1)
    bne !t38_fail+

    lda #$77
    sta potion_shuffle
    sta staff_shuffle + FLAVOUR_STAFF_COUNT - 1
    sta si_meta_hi + STORE_TOTAL_SLOTS - 1
    sta level_entry_dir
    sta monster_table
    jsr test_stream_reset_read
    jsr ts_reset_io_state
    lda #<save_block_table_post_known
    sta zp_ptr1
    lda #>save_block_table_post_known
    sta zp_ptr1_hi
    lda #SAVE_BLOCK_POST_KNOWN_COUNT
    jsr load_read_block_table
    jsr test_load_sentinel
    bne !t38_fail+
    lda save_io_error
    bne !t38_fail+
    lda potion_shuffle
    cmp #$11
    bne !t38_fail+
    lda staff_shuffle + FLAVOUR_STAFF_COUNT - 1
    cmp #$22
    bne !t38_fail+
    lda si_meta_hi + STORE_TOTAL_SLOTS - 1
    cmp #(ITEM_PAGE_DAGGER | EGO_SLAY_DRAGON)
    bne !t38_fail+
    lda level_entry_dir
    cmp #$03
    bne !t38_fail+
    lda monster_table
    cmp #$44
    bne !t38_fail+
    lda #$01
    bne !t38_store+
!t38_fail:
    lda #$00
!t38_store:
    sta tc_results + 37

    // ============================================================
    // Test 39: V2 unconditional door-state block round-trips an
    // empty table (door_state_count = 0) with sentinel alignment.
    // ============================================================
    jsr ts_reset_io_state
    sta test_save_sink_writes
    lda #0
    sta door_state_count
    sta door_state_x
    jsr test_stream_reset_write
    jsr save_write_door_state
    jsr test_save_sentinel

    lda #5
    sta door_state_count
    lda #$77
    sta door_state_x
    jsr test_stream_reset_read
    jsr ts_reset_io_state
    jsr load_read_door_state
    jsr test_load_sentinel
    bne !t39_fail+
    lda save_io_error
    bne !t39_fail+
    lda door_state_count
    bne !t39_fail+
    lda door_state_x
    bne !t39_fail+
    lda #$01
    bne !t39_store+
!t39_fail:
    lda #$00
!t39_store:
    sta tc_results + 38

    // ============================================================
    // Test 40: a current save made before an item was added carries a
    // clear bit for it. After the load the fixed-description items are
    // known as in a new game (Page-0 crowns, Leather Armour, Water potion;
    // Page-1 Amulet of Resist Acid, Dagger) and flavoured ones stay unknown
    // (Page-0 Gain Stat potion, Staff of Earthquakes; Page-1 Lordly rings).
    // ============================================================
    jsr ts_reset_io_state
    sta test_save_sink_writes
    jsr ts_clear_known_bits
    jsr test_stream_reset_write
    jsr save_write_known_items
    jsr ts_clear_known_bits
    jsr test_stream_reset_read
    jsr load_read_known_items
    lda #0
    sta item_cur_page
    .assert "t40 Page-0 known/unknown items live on Page 0", ITEM_JEWEL_ENCRUSTED_CROWN == ITEM_SILVER_CROWN + 2 && ITEM_GOLDEN_CROWN == ITEM_SILVER_CROWN + 1 && ITEM_PAGE_SILVER_CROWN == 0 && ITEM_PAGE_JEWEL_ENCRUSTED_CROWN == 0 && ITEM_PAGE_LEATHER_ARMOR == 0 && ITEM_PAGE_POTION_OF_GAIN_STRENGTH == 0 && ITEM_PAGE_CLEAR_POTION_OF_WATER == 0 && ITEM_PAGE_STAFF_OF_EARTHQUAKES == 0, true
    .assert "t40 Page-1 known/unknown items live on Page 1", ITEM_RING_OF_LORDLY_PROTECTION_COLD == ITEM_RING_OF_LORDLY_PROTECTION_FIRE + 2 && ITEM_RING_OF_LORDLY_PROTECTION_ACID == ITEM_RING_OF_LORDLY_PROTECTION_FIRE + 1 && ITEM_PAGE_RING_OF_LORDLY_PROTECTION_FIRE == ITEM_PAGE_BIT && ITEM_PAGE_RING_OF_LORDLY_PROTECTION_COLD == ITEM_PAGE_BIT && ITEM_PAGE_AMULET_OF_RESIST_ACID == ITEM_PAGE_BIT && ITEM_PAGE_DAGGER == ITEM_PAGE_BIT, true
    ldx #ITEM_SLOT_SILVER_CROWN
    ldy #ITEM_SLOT_JEWEL_ENCRUSTED_CROWN + 1
    jsr ts_expect_known_range
    bcc !t40_fail+
    ldx #ITEM_SLOT_LEATHER_ARMOR                          // Leather Armour
    ldy #ITEM_SLOT_LEATHER_ARMOR + 1
    jsr ts_expect_known_range
    bcc !t40_fail+
    ldx #ITEM_SLOT_CLEAR_POTION_OF_WATER
    jsr id_known_test
    beq !t40_fail+
    ldx #ITEM_SLOT_POTION_OF_GAIN_STRENGTH
    ldy #ITEM_SLOT_POTION_OF_GAIN_STRENGTH + 1
    jsr ts_expect_unknown_range
    bcc !t40_fail+
    ldx #ITEM_SLOT_STAFF_OF_EARTHQUAKES
    jsr id_known_test
    bne !t40_fail+
    lda #ITEM_PAGE_BIT
    sta item_cur_page
    ldx #ITEM_SLOT_AMULET_OF_RESIST_ACID
    jsr id_known_test
    beq !t40_fail+
    ldx #ITEM_SLOT_DAGGER
    jsr id_known_test
    beq !t40_fail+
    ldx #ITEM_SLOT_RING_OF_LORDLY_PROTECTION_FIRE
    ldy #ITEM_SLOT_RING_OF_LORDLY_PROTECTION_COLD + 1
    jsr ts_expect_unknown_range
    bcc !t40_fail+
    lda #0
    sta item_cur_page
    lda #$01
    .byte $2c
!t40_fail:
    lda #$00
    sta tc_results + 39

    // ============================================================
    // Test 41: C64 disk_save_media_status classifies concrete DOS codes
    // (0/1 -> WRONG_MEDIA, 26 -> WRITE_PROTECTED, 72 -> DISK_FULL,
    // 74 -> DEVICE_NOT_READY, 2/unmapped -> UNKNOWN) and preserves raw
    // disk_status.
    // ============================================================
    lda #0
    sta disk_status
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_WRONG_MEDIA
    bne !t41_fail+
    lda disk_status
    bne !t41_fail+

    lda #1
    sta disk_status
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_WRONG_MEDIA
    bne !t41_fail+
    lda disk_status
    cmp #1
    bne !t41_fail+

    lda #26
    sta disk_status
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_WRITE_PROTECTED
    bne !t41_fail+
    lda disk_status
    cmp #26
    bne !t41_fail+

    lda #72
    sta disk_status
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_DISK_FULL
    bne !t41_fail+
    lda disk_status
    cmp #72
    bne !t41_fail+

    lda #74
    sta disk_status
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    bne !t41_fail+
    lda disk_status
    cmp #74
    bne !t41_fail+

    lda #2
    sta disk_status
    jsr disk_save_media_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    bne !t41_fail+
    lda disk_status
    cmp #2
    bne !t41_fail+
    lda #$01
    .byte $2c
!t41_fail:
    lda #$00
    sta tc_results + 40

    // ============================================================
    // Test 42: C64 disk_dos_code_status (c64_storage_dos_code_status)
    // maps 0 -> OK (Z=1), 1 and 62 -> NOT_FOUND (Z=0), 26/72/74 ->
    // friendly codes (Z=0), else UNKNOWN (Z=0), preserving disk_status.
    // ============================================================
    lda #0
    sta disk_status
    jsr disk_dos_code_status
    bne !t42_fail+
    cmp #HAL_STORAGE_STATUS_OK
    bne !t42_fail+

    lda #1
    sta disk_status
    jsr disk_dos_code_status
    beq !t42_fail+
    cmp #HAL_STORAGE_STATUS_NOT_FOUND
    bne !t42_fail+
    lda disk_status
    cmp #1
    bne !t42_fail+

    lda #62
    sta disk_status
    jsr disk_dos_code_status
    beq !t42_fail+
    cmp #HAL_STORAGE_STATUS_NOT_FOUND
    bne !t42_fail+
    lda disk_status
    cmp #62
    bne !t42_fail+

    lda #26
    sta disk_status
    jsr disk_dos_code_status
    beq !t42_fail+
    cmp #HAL_STORAGE_STATUS_WRITE_PROTECTED
    bne !t42_fail+

    lda #72
    sta disk_status
    jsr disk_dos_code_status
    beq !t42_fail+
    cmp #HAL_STORAGE_STATUS_DISK_FULL
    bne !t42_fail+

    lda #74
    sta disk_status
    jsr disk_dos_code_status
    beq !t42_fail+
    cmp #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    bne !t42_fail+
    lda disk_status
    cmp #74
    bne !t42_fail+

    lda #2
    sta disk_status
    jsr disk_dos_code_status
    beq !t42_fail+
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    bne !t42_fail+
    lda #$01
    .byte $2c
!t42_fail:
    lda #$00
    sta tc_results + 41

    // ============================================================
    // Test 43: load_game classifies command-channel status on early
    // READST, OPEN failure, and CHKIN failure (62/1/0 -> NOTFOUND,
    // 74 -> NOT_READY, 26 -> WRITE_PROTECTED, 2/unmapped -> IOERR),
    // preserving raw disk_status diagnostics.
    // ============================================================
    // 43a: Early READST ($42) + DOS 62 (stored as 1 by C64 cmd reader) -> NOTFOUND
    jsr ts_reset_io_state
    sta test_save_last_msg
    sta test_save_readst_value
    sta test_save_close_arms_readst
    lda #1
    sta test_save_marker_present
    sta disk_setup_done
    sta test_save_cmd_status
    lda #2
    sta disk_mode
    lda #8
    sta save_device
    lda #$42
    sta test_save_magic_readst
    jsr test_stream_reset_read
    jsr load_game
    bcs !t43_fail_top+
    lda load_result
    cmp #LOAD_RESULT_NOTFOUND
    bne !t43_fail_top+
    lda test_save_last_msg
    cmp #HSTR_SAVE_NOTFOUND
    bne !t43_fail_top+
    lda disk_status
    cmp #1
    bne !t43_fail_top+

    // 43b: Early READST ($42) + raw DOS 62 -> NOTFOUND
    jsr ts_reset_io_state
    sta test_save_last_msg
    lda #62
    sta test_save_cmd_status
    lda #$42
    sta test_save_magic_readst
    jsr test_stream_reset_read
    jsr load_game
    bcs !t43_fail_top+
    lda load_result
    cmp #LOAD_RESULT_NOTFOUND
    bne !t43_fail_top+
    lda test_save_last_msg
    cmp #HSTR_SAVE_NOTFOUND
    bne !t43_fail_top+
    lda disk_status
    cmp #62
    beq !t43_c+
!t43_fail_top:
    jmp !t43_fail+

!t43_c:
    // 43c: Early READST ($42) + DOS 74 -> IOERR + "Drive is not ready."
    jsr ts_reset_io_state
    sta test_save_last_msg
    lda #74
    sta test_save_cmd_status
    lda #$42
    sta test_save_magic_readst
    jsr test_stream_reset_read
    jsr load_game
    bcs !t43_fail_far+
    lda load_result
    cmp #LOAD_RESULT_IOERR
    bne !t43_fail_far+
    lda test_save_last_msg
    cmp #HSTR_SAVE_NOT_READY
    bne !t43_fail_far+
    lda disk_status
    cmp #74
    bne !t43_fail_far+

    // 43d: Early READST ($42) + unmapped (2) -> IOERR + "Disk error!"
    jsr ts_reset_io_state
    sta test_save_last_msg
    lda #2
    sta test_save_cmd_status
    lda #$42
    sta test_save_magic_readst
    jsr test_stream_reset_read
    jsr load_game
    bcs !t43_fail_far+
    lda load_result
    cmp #LOAD_RESULT_IOERR
    bne !t43_fail_far+
    lda test_save_last_msg
    cmp #HSTR_SAVE_IOERR
    bne !t43_fail_far+
    lda disk_status
    cmp #2
    beq !t43_open+
!t43_fail_far:
    jmp !t43_fail+

!t43_open:
    // 43e: OPEN fail + DOS 74 -> IOERR + "Drive is not ready."
    jsr ts_reset_io_state
    sta test_save_last_msg
    lda #1
    sta test_save_open_fail
    lda #74
    sta test_save_cmd_status
    jsr load_game
    bcs !t43_fail+
    lda load_result
    cmp #LOAD_RESULT_IOERR
    bne !t43_fail+
    lda test_save_last_msg
    cmp #HSTR_SAVE_NOT_READY
    bne !t43_fail+

    // 43f: OPEN fail + detached/unmapped (2) -> IOERR + "Disk error!"
    jsr ts_reset_io_state
    sta test_save_last_msg
    lda #1
    sta test_save_open_fail
    lda #2
    sta test_save_cmd_status
    jsr load_game
    bcs !t43_fail+
    lda load_result
    cmp #LOAD_RESULT_IOERR
    bne !t43_fail+
    lda test_save_last_msg
    cmp #HSTR_SAVE_IOERR
    bne !t43_fail+

    // 43g: CHKIN fail + DOS 74 -> IOERR + "Drive is not ready."
    jsr ts_reset_io_state
    sta test_save_last_msg
    lda #1
    sta test_save_chkin_fail
    lda #74
    sta test_save_cmd_status
    jsr load_game
    bcs !t43_fail+
    lda load_result
    cmp #LOAD_RESULT_IOERR
    bne !t43_fail+
    lda test_save_last_msg
    cmp #HSTR_SAVE_NOT_READY
    bne !t43_fail+

    // 43h: CHKIN fail + unmapped (2) -> IOERR + "Disk error!"
    jsr ts_reset_io_state
    sta test_save_last_msg
    lda #1
    sta test_save_chkin_fail
    lda #2
    sta test_save_cmd_status
    jsr load_game
    bcs !t43_fail+
    lda load_result
    cmp #LOAD_RESULT_IOERR
    bne !t43_fail+
    lda test_save_last_msg
    cmp #HSTR_SAVE_IOERR
    bne !t43_fail+
    lda #0
    sta test_save_marker_present
    lda #$01
    .byte $2c
!t43_fail:
    lda #$00
    sta tc_results + 42

    // ============================================================
    // Test 44: save_game and load_game media-check failure paths
    // report friendly messages for 74/26/72 while keeping 2 -> IOERR.
    // ============================================================
    jsr ts_reset_io_state
    sta test_save_last_msg
    sta test_save_dismiss_calls
    sta test_save_marker_present
    sta test_save_marker_lsr_return
    lda #1
    sta disk_setup_done
    lda #2
    sta disk_mode
    lda #8
    sta program_device
    lda #9
    sta save_device

    lda #74
    sta test_save_marker_status
    jsr save_game
    bcs !t44_fail+
    lda test_save_last_msg
    cmp #HSTR_SAVE_NOT_READY
    bne !t44_fail+
    lda disk_status
    cmp #74
    bne !t44_fail+

    lda #26
    sta test_save_marker_status
    jsr save_game
    bcs !t44_fail+
    lda test_save_last_msg
    cmp #HSTR_SAVE_WRITE_PROTECTED
    bne !t44_fail+

    lda #72
    sta test_save_marker_status
    jsr save_game
    bcs !t44_fail+
    lda test_save_last_msg
    cmp #HSTR_SAVE_DISK_FULL
    bne !t44_fail+

    lda #74
    sta test_save_marker_status
    jsr load_game
    bcs !t44_fail+
    lda load_result
    cmp #LOAD_RESULT_IOERR
    bne !t44_fail+
    lda test_save_last_msg
    cmp #HSTR_SAVE_NOT_READY
    bne !t44_fail+
    lda #0
    sta test_save_marker_status
    lda #$01
    .byte $2c
!t44_fail:
    lda #$00
    sta tc_results + 43

    // ============================================================
    // Test 45: non-chunked $40 EOF during load_read_byte flags
    // save_io_error and aborts truncated load_game cleanly with
    // LOAD_RESULT_CORRUPT, while clean $40 EOI on the final checksum
    // byte succeeds with LOAD_RESULT_OK.
    // ============================================================
    :PatchJump(save_file_exists, test_save_file_not_exists)
    jsr ts_reset_io_state
    sta test_save_last_msg
    sta test_save_dismiss_calls
    sta test_save_readst_value
    sta test_save_close_arms_readst
    sta test_save_sink_writes
    lda #1
    sta test_save_marker_present
    sta disk_setup_done
    lda #2
    sta disk_mode
    lda #8
    sta save_device

    // 45a: direct load_read_byte accepts READST == 0 and flags READST == $40.
    lda #$11
    sta T45_STREAM_BUF
    lda #$22
    sta T45_STREAM_BUF + 1
    lda #<T45_STREAM_BUF
    sta zp_ptr2
    lda #>T45_STREAM_BUF
    sta zp_ptr2_hi
    jsr load_read_byte
    cmp #$11
    bne !t45_fail_top+
    lda save_io_error
    bne !t45_fail_top+
    lda #$40
    sta test_save_readst_value
    jsr load_read_byte
    cmp #$22
    bne !t45_fail_top+
    lda save_io_error
    cmp #1
    beq !t45_clr_setup+
!t45_fail_top:
    jmp !t45_fail+
!t45_clr_setup:

    // Zero MAP_BASE so RLE compresses cleanly inside T45_STREAM_BUF..MAP_BASE.
    lda #0
    ldx #0
!t45_clr_map:
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
    bne !t45_clr_map-

    jsr item_init_inventory
    jsr ts_reset_io_state
    lda #$25
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #<T45_STREAM_BUF
    sta zp_ptr2
    lda #>T45_STREAM_BUF
    sta zp_ptr2_hi
    jsr save_game
    bcc !t45_fail_jmp+
    lda zp_ptr2
    sta test_save_end_lo
    lda zp_ptr2_hi
    sta test_save_end_hi

    // Preserve the 2 tail checksum bytes before load_game restores MAP_BASE
    // over the upper part of T45_STREAM_BUF ($C000-$CEFF).
    lda zp_ptr2
    sec
    sbc #1
    sta test_save_t45_ck1_lo
    sta zp_ptr0
    lda zp_ptr2_hi
    sbc #0
    sta test_save_t45_ck1_hi
    sta zp_ptr0_hi
    ldy #0
    lda (zp_ptr0),y
    sta test_save_t45_ck_hi
    lda zp_ptr2
    sec
    sbc #2
    sta test_save_t45_ck0_lo
    sta zp_ptr0
    lda zp_ptr2_hi
    sbc #0
    sta test_save_t45_ck0_hi
    sta zp_ptr0_hi
    lda (zp_ptr0),y
    sta test_save_t45_ck_lo

    // 45b: Valid complete stream with $40 EOI on the final byte (cksum_hi) -> OK
    jsr ts_reset_io_state
    sta test_save_readst_value
    sta zp_player_lvl
    sta player_data + PL_LEVEL
    lda #1
    sta test_save_t45_ck_active
    lda test_save_end_lo
    sta test_save_eof_lo
    lda test_save_end_hi
    sta test_save_eof_hi
    lda #<T45_STREAM_BUF
    sta zp_ptr2
    lda #>T45_STREAM_BUF
    sta zp_ptr2_hi
    jsr load_game
    lda #0
    sta test_save_t45_ck_active
    bcc !t45_fail_jmp+
    lda load_result
    cmp #LOAD_RESULT_OK
    bne !t45_fail_jmp+
    lda save_io_error
    bne !t45_fail_jmp+
    lda player_data + PL_LEVEL
    cmp #$25
    beq !t45_trunc+
!t45_fail_jmp:
    jmp !t45_fail+

!t45_trunc:
    // 45c: Stream truncated mid-payload ($40 at magic + 20 B) -> CORRUPT
    // and halts reading at the EOF boundary rather than advancing past it.
    jsr ts_reset_io_state
    sta test_save_readst_value
    lda #$99
    sta player_data + PL_LEVEL
    lda #<(T45_STREAM_BUF + SAVE_MAGIC_SIZE + 20)
    sta test_save_eof_lo
    lda #>(T45_STREAM_BUF + SAVE_MAGIC_SIZE + 20)
    sta test_save_eof_hi
    lda #<T45_STREAM_BUF
    sta zp_ptr2
    lda #>T45_STREAM_BUF
    sta zp_ptr2_hi
    jsr load_game
    bcs !t45_fail+
    lda load_result
    cmp #LOAD_RESULT_CORRUPT
    bne !t45_fail+
    lda save_io_error
    beq !t45_fail+
    lda zp_ptr2
    cmp test_save_eof_lo
    bne !t45_fail+
    lda zp_ptr2_hi
    cmp test_save_eof_hi
    bne !t45_fail+
    lda #$01
    .byte $2c
!t45_fail:
    lda #$00
    sta tc_results + 44
    lda #0
    sta test_save_t45_ck_active
    sta test_save_eof_hi
    sta test_save_readst_value
    sta test_save_marker_present

    jmp test_finish

test_body_end:
.assert "RLE test buffer stays below test code", RLE_TEST_BUF + $0300 <= $0800, true
.assert "Test 45 stream buffer stays between test body and MAP_BASE", test_body_end <= T45_STREAM_BUF, true
.assert "Save test code stays below MAP_BASE (RLE tests overwrite MAP_BASE)", test_body_end <= MAP_BASE, true
