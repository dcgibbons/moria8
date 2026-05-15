#importonce
// save.s — Save/Load game system
//
// Writes all game state to a sequential file on 1541 disk via KERNAL I/O.
// Load restores state without consuming the savefile.
// Uses 16-bit additive complement checksum for integrity.
// Map data is written raw (`MAP_SIZE` bytes). RLE compressor is kept for tests only.
//
// KERNAL calls: SETNAM($FFBD), SETLFS($FFBA), OPEN($FFC0), CLOSE($FFC3),
//   CHKOUT($FFC9), CHKIN($FFC6), CLRCHN($FFCC), CHROUT($FFD2),
//   CHRIN($FFCF), READST($FFB7)

// ============================================================
// Constants
// ============================================================
.const SAVE_MAGIC_SIZE = 8
#if C128
.const SAVE_VERSION    = $10
.const OLDEST_SAVE_VERSION = SAVE_VERSION
#elif PLUS4
.const SAVE_VERSION    = $01
.const OLDEST_SAVE_VERSION = SAVE_VERSION
#else
.const SAVE_VERSION    = $0f
.const OLDEST_SAVE_VERSION = SAVE_VERSION
#endif
.const SAVE_FLOOR42_VERSION = SAVE_VERSION
.const LOAD_RESULT_OK        = 0
.const LOAD_RESULT_NOTFOUND  = 1
.const LOAD_RESULT_CORRUPT   = 2
.const LOAD_RESULT_IOERR     = 3
.const LOAD_RESULT_UNSUPPORTED = 4

// ZP game state range to save ($40–$5f = 32 bytes)
// Coverage: player struct fields ($2B-$3F) saved via player_sync_from_zp.
//   ZP $40-$5F saved directly (turn counter, effect timers, game flags).
//   ZP $1A-$1D saved directly (RNG state).
// NOT saved (intentionally):
//   $13-$19: zp_ui_dirty/zp_msg_flags — reset by msg_init/status_draw on load.
//   $60-$8F: viewport/sound/combat scratch — recalculated or transient.
.const ZP_STATE_START = $40
.const ZP_STATE_SIZE  = 32      // $40–$5f inclusive

// RNG state ($1a–$1d = 4 bytes)
.const ZP_RNG_START   = $1a
.const ZP_RNG_SIZE    = 4

// RLE packet encoding
.const RLE_LITERAL_MAX = 128    // Max literal run length
.const RLE_REPEAT_MIN  = 3     // Minimum repeat run
.const RLE_REPEAT_MAX  = 130    // Max repeat run length

.const SAVE_SETNAM = hal_storage_setnam
.const SAVE_SETLFS = hal_storage_setlfs
.const SAVE_OPEN   = hal_storage_open
.const SAVE_CLOSE  = hal_storage_close
.const SAVE_CHKOUT = hal_storage_chkout
.const SAVE_CHKIN  = hal_storage_chkin
.const SAVE_CLRCHN = hal_storage_clrchn
.const SAVE_CHROUT = hal_storage_chrout
.const SAVE_CHRIN  = hal_storage_chrin
.const SAVE_READST = hal_storage_readst

#if C128
.const SAVE_IO_CHUNK_SIZE = 128
#endif

// ============================================================
// Scratch variables (before code so BRK is last in tests)
// ============================================================
save_block_lo:  .byte 0         // Source address lo for save_write_block
save_block_hi:  .byte 0         // Source address hi
save_count_lo:  .byte 0         // Byte count lo
save_count_hi:  .byte 0         // Byte count hi
save_cksum_lo:  .byte 0         // Running checksum lo
save_cksum_hi:  .byte 0         // Running checksum hi
save_magic_buf: .fill SAVE_MAGIC_SIZE, 0  // Load-time header scratch
#if SAVE_TEST_RLE
rle_size_lo:    .byte 0         // Compressed map size lo
rle_size_hi:    .byte 0         // Compressed map size hi
rle_run_byte:   .byte 0         // Current run byte value
rle_run_len:    .byte 0         // Current run length
rle_lit_len:    .byte 0         // Literal buffer length
#endif
save_io_error:  .byte 0         // I/O error flag
load_result:    .byte LOAD_RESULT_IOERR
load_save_version: .byte 0
load_floor_item_count: .byte 0
#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
plus4_test_file_cksum_lo: .byte 0
plus4_test_file_cksum_hi: .byte 0
plus4_test_read_count_lo: .byte 0
plus4_test_read_count_hi: .byte 0
#endif
#if C128
save_chunk_len: .byte 0
save_chunk_idx: .byte 0
save_chunk_status: .byte 0
save_stage_buf:
    .fill SAVE_IO_CHUNK_SIZE, 0
save_stage_buf_end:
#endif
#if SAVE_TEST_RLE
rle_work_lo:    .byte <CREATURE_BASE  // RLE workspace pointer lo (default CREATURE_BASE)
rle_work_hi:    .byte >CREATURE_BASE  // RLE workspace pointer hi

// Literal buffer for RLE (max 128 bytes)
rle_lit_buf:    .fill 128, 0
#endif

save_magic:
#if PLUS4
    .byte $4d, $4f, $52, $49, $41, $2b, $34  // "MORIA+4"
#else
    .byte $4d, $4f, $52, $49, $41, $30, $31  // "MORIA01"
#endif
    .byte SAVE_VERSION                          // Version byte
.assert "Magic is 8 bytes", * - save_magic, SAVE_MAGIC_SIZE

#import "storage_status.s"

#if C128 || PLUS4 || STORAGE_STREAM_STATUS_HELPER
// save_stream_status
// Output: A = HAL_STORAGE_STATUS_* for the most recent save-record stream.
save_stream_status:
    lda save_io_error
    beq !ok+
    lda #HAL_STORAGE_STATUS_UNKNOWN
    rts
!ok:
    lda #HAL_STORAGE_STATUS_OK
    rts

// load_stream_status
// Output: A = HAL_STORAGE_STATUS_* for the most recent load-record stream.
load_stream_status:
    lda load_result
    cmp #LOAD_RESULT_OK
    bne !not_ok+
    lda #HAL_STORAGE_STATUS_OK
    rts
!not_ok:
    cmp #LOAD_RESULT_NOTFOUND
    bne !unsupported+
    lda #HAL_STORAGE_STATUS_NOT_FOUND
    rts
!unsupported:
    cmp #LOAD_RESULT_UNSUPPORTED
    bne !unknown+
    lda #HAL_STORAGE_STATUS_UNSUPPORTED
    rts
!unknown:
    lda #HAL_STORAGE_STATUS_UNKNOWN
    rts

// save_stream_status_message
// Input: A = HAL_STORAGE_STATUS_*.
// Output: X = HSTR_* message id for the save stream failure.
save_stream_status_message:
    ldx #HSTR_SAVE_IOERR
    rts

// load_stream_status_message
// Input: A = HAL_STORAGE_STATUS_*.
// Output: X = HSTR_* message id for the load stream failure.
load_stream_status_message:
    cmp #HAL_STORAGE_STATUS_NOT_FOUND
    bne !unsupported+
    ldx #HSTR_SAVE_NOTFOUND
    rts
!unsupported:
    cmp #HAL_STORAGE_STATUS_UNSUPPORTED
    bne !ioerr+
    ldx #HSTR_SAVE_UNSUPPORTED
    rts
!ioerr:
    ldx #HSTR_SAVE_IOERR
    rts
#endif

#if C128 || PLUS4
// save_print_storage_status
// Input: A = HAL_STORAGE_STATUS_*.
// Prints a friendly direct storage-status message when the semantic status is
// known; otherwise prints the existing compressed generic disk error.
save_print_storage_status:
    cmp #HAL_STORAGE_STATUS_WRITE_PROTECTED
    bne !disk_full+
    lda #<save_write_protected_str
    ldy #>save_write_protected_str
    jmp save_print_direct_status
!disk_full:
    cmp #HAL_STORAGE_STATUS_DISK_FULL
    bne !not_ready+
    lda #<save_disk_full_str
    ldy #>save_disk_full_str
    jmp save_print_direct_status
!not_ready:
    cmp #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    bne !generic+
    lda #<save_drive_not_ready_str
    ldy #>save_drive_not_ready_str
    jmp save_print_direct_status
!generic:
    ldx #HSTR_SAVE_IOERR
    jsr huff_print_msg
#if PLUS4
    jsr save_append_disk_detail_plus4
#endif
    rts

save_print_direct_status:
    sta zp_ptr0
    sty zp_ptr0_hi
    jmp msg_print

save_write_protected_str:
    .text "Disk is write-protected." ; .byte 0
save_disk_full_str:
    .text "Disk is full." ; .byte 0
save_drive_not_ready_str:
    .text "Drive is not ready." ; .byte 0
#endif

// ============================================================
// Macros for concise block I/O
// ============================================================

.macro save_block(addr, size) {
    lda #<addr
    sta save_block_lo
    lda #>addr
    sta save_block_hi
    lda #<size
    sta save_count_lo
    lda #>size
    sta save_count_hi
    jsr save_write_block
}

.macro load_block(addr, size) {
    lda #<addr
    sta zp_ptr0
    lda #>addr
    sta zp_ptr0_hi
    lda #<size
    sta save_count_lo
    lda #>size
    sta save_count_hi
    jsr load_read_block
}

// ============================================================
// save_game — Top-level save routine
// Syncs ZP→struct, writes all blocks + raw map + checksum, closes
// Clobbers: A, X, Y, all scratch
// ============================================================
#if C128 || PLUS4
save_confirm_overwrite:
    lda #hal_storage_save_probe_name_len
    sta save_count_lo
    lda #<hal_storage_save_probe_name
    sta save_block_lo
    lda #>hal_storage_save_probe_name
    sta save_block_hi
    jsr save_file_exists
    bcc !save_confirm_done+
    ldx #HSTR_SAVE_OVERWRITE
    jsr huff_print_msg
#if PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
plus4_test_save_overwrite_prompt:
#endif
#if C128
    jsr input_prepare_followup_key
#endif
!save_confirm_loop:
    jsr hal_input_get_key
    cmp #$59                // Y
    beq !save_confirm_yes+
    cmp #$4e                // N
    beq !save_confirm_no+
    bne !save_confirm_loop-
!save_confirm_yes:
    lda #hal_storage_save_write_name_len
    sta save_count_lo
    lda #<hal_storage_save_write_name
    sta save_block_lo
    lda #>hal_storage_save_write_name
    sta save_block_hi
!save_confirm_done:
    sec
    rts
!save_confirm_no:
    clc
    rts
#else
save_select_output_name_c64:
    jsr save_file_exists
    bcc !save_select_ok+
    ldx #HSTR_SAVE_OVERWRITE
    jsr huff_print_msg
!save_select_loop:
    jsr hal_input_get_key
    cmp #$59                // Y
    beq !save_select_yes+
    cmp #$4e                // N
    bne !save_select_loop-
    clc
    rts
!save_select_yes:
!save_select_ok:
    sec
    rts
#endif

save_game:
    jsr disk_require_save_media
    bcc !save_media_ok+
    ldx #HSTR_SAVE_NEED_SAVE
    lda disk_setup_done
    beq !save_media_fail+
!save_wrong_media:
    jsr hal_storage_save_media_status
    cmp #HAL_STORAGE_STATUS_WRONG_MEDIA
    beq !save_bad_media+
#if C128 || PLUS4
    jsr save_print_storage_status
    jmp !save_media_after_print+
#else
    ldx #HSTR_SAVE_IOERR
#endif
    jmp !save_media_fail+
!save_bad_media:
    ldx #HSTR_SAVE_BAD_SAVE
!save_media_fail:
#if PLUS4
    txa
    pha
#endif
    jsr huff_print_msg
#if PLUS4
    pla
    tax
    cpx #HSTR_SAVE_IOERR
    bne !save_media_no_detail+
    jsr save_append_disk_detail_plus4
!save_media_no_detail:
#endif
!save_media_after_print:
    jsr input_get_modal_dismiss_key
save_return_fail:
#if !C128 && !PLUS4
    clc
save_return_c64_with_carry:
    lda #BANK_NO_BASIC
    sta hal_memory_cpu_port
    rts
#else
    clc
    rts
#endif

!save_media_ok:
#if !C128 && !PLUS4
    lda #BANK_NO_BASIC
    sta hal_memory_cpu_port
#endif
#if C128 || PLUS4
    jsr save_confirm_overwrite
    bcc save_return_fail
#else
    jsr save_select_output_name_c64
    bcc save_return_fail
    jsr SAVE_SETNAM
#endif

    // Show "SAVING GAME..." message
    ldx #HSTR_SAVE_SAVING
    jsr huff_print_msg

    // Sync ZP fields back to player struct
    jsr player_sync_from_zp
    jsr player_search_clear_transient_state

    // Reset checksum
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    sta save_io_error
#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    sta plus4_test_read_count_lo
    sta plus4_test_read_count_hi
#endif
#if PLUS4
    jsr disk_error_clear
#endif

    // Open file for writing
    // SETNAM
#if C128
    lda save_count_lo
    ldx save_block_lo
    ldy save_block_hi
#else
    lda #hal_storage_save_write_name_len
    ldx #<hal_storage_save_write_name
    ldy #>hal_storage_save_write_name
#endif
    jsr SAVE_SETNAM
    // SETLFS: file#2, device 8/9, secondary 2
    lda #hal_storage_save_file_num
    ldx save_device
    ldy #hal_storage_save_sec_write
    jsr SAVE_SETLFS
    jsr SAVE_OPEN
    bcc !save_open_ok+
#if PLUS4
    pha
    lda #$a1
    jsr disk_error_set_phase
    pla
    sta disk_error_readst
#endif
    jmp !save_error+
!save_open_ok:

    // Direct output to file
    ldx #hal_storage_save_file_num
    jsr SAVE_CHKOUT
    bcc !save_chkout_ok+
#if PLUS4
    pha
    lda #$a2
    jsr disk_error_set_phase
    pla
    sta disk_error_readst
#endif
    jmp !save_error_close+
!save_chkout_ok:

    // --- Write blocks in order ---

    // 1. Magic header (8 bytes)
    :save_block(save_magic, SAVE_MAGIC_SIZE)

    // 2. Player data (80 bytes)
    :save_block(player_data, PL_STRUCT_SIZE)

    // 2b. Player background text (160 bytes)
    :save_block(player_background, 160)

    // 3. ZP game state $40-$5f (32 bytes)
    :save_block(ZP_STATE_START, ZP_STATE_SIZE)

    // 3b. Static effect timers
    :save_block(eff_fear_timer, 1)

    // 4. RNG state $1a-$1d (4 bytes)
    :save_block(ZP_RNG_START, ZP_RNG_SIZE)

    // 5. Inventory (5 × 30 = 150 bytes)
    :save_block(inv_item_id, TOTAL_INV_SLOTS)
    :save_block(inv_qty, TOTAL_INV_SLOTS)
    :save_block(inv_p1, TOTAL_INV_SLOTS)
    :save_block(inv_to_hit, TOTAL_INV_SLOTS)
    :save_block(inv_to_dam, TOTAL_INV_SLOTS)
    :save_block(inv_to_ac, TOTAL_INV_SLOTS)
    :save_block(inv_flags, TOTAL_INV_SLOTS)
    :save_block(inv_ego, TOTAL_INV_SLOTS)

    // 6. id_known (49 bytes)
    :save_block(id_known, ITEM_TYPE_COUNT)

    // 7. Shuffle tables (12+12+4+5+5 = 38 bytes)
    :save_block(potion_shuffle, 12)
    :save_block(scroll_shuffle, 12)
    :save_block(ring_shuffle, 4)
    :save_block(wand_shuffle, 5)
    :save_block(staff_shuffle, 5)

    // 8. Store inventory
    :save_block(si_item_id, STORE_TOTAL_SLOTS)
    :save_block(si_qty, STORE_TOTAL_SLOTS)
    :save_block(si_p1, STORE_TOTAL_SLOTS)
    :save_block(si_to_hit, STORE_TOTAL_SLOTS)
    :save_block(si_to_dam, STORE_TOTAL_SLOTS)
    :save_block(si_to_ac, STORE_TOTAL_SLOTS)
    :save_block(si_meta, STORE_TOTAL_SLOTS)

    // 9. Stairs (6 bytes)
    :save_block(stairs_up_x, 6)

    // 10. Level entry dir (1 byte)
    :save_block(level_entry_dir, 1)

    // 11. Room count (1 byte)
    :save_block(room_count, 1)

    // 12. Room arrays (5 × 8 = 40 bytes)
    :save_block(room_x, MAX_ROOMS)
    :save_block(room_y, MAX_ROOMS)
    :save_block(room_w, MAX_ROOMS)
    :save_block(room_h, MAX_ROOMS)
    :save_block(room_lit, MAX_ROOMS)
    :save_block(room_type, MAX_ROOMS)

    // 13. Trap count (1 byte)
    :save_block(trap_count, 1)

    // 14. Trap arrays (3 × 16 = 48 bytes)
    :save_block(trap_x, MAX_TRAPS)
    :save_block(trap_y, MAX_TRAPS)
    :save_block(trap_type, MAX_TRAPS)

    // 15. Monster table (32 × 12 = 384 bytes)
    :save_block(monster_table, MAX_MONSTERS * MONSTER_ENTRY_SIZE)

    // 16. Floor items (logical 8-field layout, serialized from packed RAM)
    jsr save_write_floor_items

    // 16b. Recall data (4 x MAX_CREATURES = 260 bytes)
    :save_block(recall_data_start, RECALL_DATA_SIZE)

    // 17. Map data (`MAP_SIZE` bytes raw)
#if C128
    jsr save_write_map_c128
#else
    :save_block(MAP_BASE, MAP_SIZE)
#endif

    // Check for I/O errors
    lda save_io_error
    beq !save_io_ok+
    jmp !save_error_close+
!save_io_ok:

    // 19. Write checksum (2 bytes, not accumulated)
    lda save_cksum_lo
    jsr save_write_byte_raw
    lda save_cksum_hi
    jsr save_write_byte_raw

    // Close and clean up
    jsr save_restore_channels
    lda #hal_storage_save_file_num
    jsr SAVE_CLOSE
#if !C128 && !PLUS4
    jsr SAVE_READST
    and #$83
    bne !save_error+
#endif
#if !C128 && !PLUS4
    jsr c64_restore_vic_bank0_after_serial
#endif

    // Show success
    ldx #HSTR_SAVE_DONE
    jsr huff_print_msg
#if !C128 && !PLUS4
    lda #BANK_NO_BASIC
    sta hal_memory_cpu_port
#endif
    sec
    rts

!save_error_close:
    jsr save_restore_channels
    lda #hal_storage_save_file_num
    jsr SAVE_CLOSE
#if !C128 && !PLUS4
    jsr c64_restore_vic_bank0_after_serial
#endif
!save_error:
#if C128 || PLUS4
    jsr hal_storage_save_stream_status
    jsr save_print_storage_status
    jmp !save_error_after_print+
#else
    ldx #HSTR_SAVE_IOERR
#endif
#if PLUS4
    txa
    pha
#endif
    jsr huff_print_msg
#if PLUS4
    pla
    tax
    cpx #HSTR_SAVE_IOERR
    bne !save_error_no_detail+
    jsr save_append_disk_detail_plus4
!save_error_no_detail:
#endif
!save_error_after_print:
    jsr input_get_modal_dismiss_key
    jmp save_return_fail

// ============================================================
// load_game — Top-level load routine
// Opens file, verifies magic, reads all blocks + raw map,
// verifies checksum, syncs struct→ZP.
// Output: load_result = LOAD_RESULT_* status code.
//         carry set = success, carry clear = failure where preserved by platform exit path.
// Clobbers: A, X, Y, all scratch
// ============================================================

load_game:
    lda #LOAD_RESULT_IOERR
    sta load_result
    jsr disk_require_save_media
    bcc !load_media_ok+
    ldx #HSTR_SAVE_NEED_SAVE
    lda disk_setup_done
    beq !load_media_fail+
!load_wrong_media:
    jsr hal_storage_save_media_status
    cmp #HAL_STORAGE_STATUS_WRONG_MEDIA
    beq !load_bad_media+
#if C128 || PLUS4
    jsr save_print_storage_status
    jmp !load_media_after_print+
#else
    ldx #HSTR_SAVE_IOERR
#endif
    jmp !load_media_fail+
!load_bad_media:
    ldx #HSTR_SAVE_BAD_SAVE
!load_media_fail:
#if PLUS4_TEST_SCRIPTED_LOAD_WRONG_MEDIA_PRODUCT
plus4_test_load_media_fail:
#endif
    jsr huff_print_msg
!load_media_after_print:
    clc
    rts
!load_media_ok:
#if !C128 && !PLUS4
    lda #BANK_NO_BASIC
    sta hal_memory_cpu_port
#endif

    // Show "LOADING GAME..." message
    ldx #HSTR_SAVE_LOADING
    jsr huff_print_msg

    // Reset checksum
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    sta save_io_error

#if PLUS4
    jsr SAVE_CLRCHN
    lda #hal_storage_save_file_num
    jsr SAVE_CLOSE
#endif

    // Open save file for sequential read via CHKIN/CHRIN
    lda #hal_storage_save_read_name_len
    ldx #<hal_storage_save_read_name
    ldy #>hal_storage_save_read_name
    jsr SAVE_SETNAM
    lda #hal_storage_save_file_num
    ldx save_device
    ldy #hal_storage_save_sec_read
    jsr SAVE_SETLFS
    jsr SAVE_OPEN
    bcc !load_open_ok+
    // OPEN failed — file not found is the most common cause
#if !C128 && !PLUS4
    jsr c64_restore_vic_bank0_after_serial
#endif
    jmp !load_notfound+
!load_open_ok:
    ldx #hal_storage_save_file_num
    jsr SAVE_CHKIN
    bcc !load_chkin_ok+
    // CHKIN failed — close and bail
    lda #hal_storage_save_file_num
    jsr SAVE_CLOSE
#if !C128 && !PLUS4
    jsr c64_restore_vic_bank0_after_serial
#endif
    jmp !load_fail+
!load_chkin_ok:

    // --- Read and verify magic header ---
    // Read 8 bytes to temp area and compare
    :load_block(save_magic_buf, SAVE_MAGIC_SIZE)
#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
plus4_test_after_load_magic:
#endif
    // Check STATUS after reading magic: file-not-found on 1541 causes OPEN to
    // succeed but first CHRINs return immediate EOF/timeout (STATUS = $42).
    // Any non-zero STATUS this early means the file doesn't exist.
    jsr SAVE_READST
#if PLUS4
    and #$fe                // Plus/4 KERNAL may leave write-timeout bit set after CHRIN
#endif
    beq !load_magic_check+
    jmp !load_close_notfound+   // STATUS non-zero → file not found
!load_magic_check:
    ldx #0
!check_magic:
    lda save_magic_buf,x
    cmp save_magic,x
    beq !magic_ok+
    jmp !load_corrupt+
!magic_ok:
    inx
    cpx #SAVE_MAGIC_SIZE - 1
    bcc !check_magic-

    lda save_magic_buf + SAVE_MAGIC_SIZE - 1
    jsr save_version_supported
    bcs !load_version_ok+
    jmp !load_unsupported+
!load_version_ok:
    lda save_magic_buf + SAVE_MAGIC_SIZE - 1
    sta load_save_version

    // --- Read all blocks in same order as save ---

    // 2. Player data
    :load_block(player_data, PL_STRUCT_SIZE)

    // 2b. Player background text (160 bytes)
    :load_block(player_background, 160)

    // 3. ZP game state
    :load_block(ZP_STATE_START, ZP_STATE_SIZE)

    // 3b. Static effect timers
    :load_block(eff_fear_timer, 1)

    // 4. RNG state
    :load_block(ZP_RNG_START, ZP_RNG_SIZE)

    // 5. Inventory
    :load_block(inv_item_id, TOTAL_INV_SLOTS)
    :load_block(inv_qty, TOTAL_INV_SLOTS)
    :load_block(inv_p1, TOTAL_INV_SLOTS)
    :load_block(inv_to_hit, TOTAL_INV_SLOTS)
    :load_block(inv_to_dam, TOTAL_INV_SLOTS)
    :load_block(inv_to_ac, TOTAL_INV_SLOTS)
    :load_block(inv_flags, TOTAL_INV_SLOTS)
    :load_block(inv_ego, TOTAL_INV_SLOTS)

    // 6. id_known
    :load_block(id_known, ITEM_TYPE_COUNT)

    // 7. Shuffle tables
    :load_block(potion_shuffle, 12)
    :load_block(scroll_shuffle, 12)
    :load_block(ring_shuffle, 4)
    :load_block(wand_shuffle, 5)
    :load_block(staff_shuffle, 5)

    // 8. Store inventory
    :load_block(si_item_id, STORE_TOTAL_SLOTS)
    :load_block(si_qty, STORE_TOTAL_SLOTS)
    :load_block(si_p1, STORE_TOTAL_SLOTS)
    :load_block(si_to_hit, STORE_TOTAL_SLOTS)
    :load_block(si_to_dam, STORE_TOTAL_SLOTS)
    :load_block(si_to_ac, STORE_TOTAL_SLOTS)
    :load_block(si_meta, STORE_TOTAL_SLOTS)

    // 9. Stairs
    :load_block(stairs_up_x, 6)

    // 10. Level entry dir
    :load_block(level_entry_dir, 1)

    // 11. Room count
    :load_block(room_count, 1)

    // 12. Room arrays
    :load_block(room_x, MAX_ROOMS)
    :load_block(room_y, MAX_ROOMS)
    :load_block(room_w, MAX_ROOMS)
    :load_block(room_h, MAX_ROOMS)
    :load_block(room_lit, MAX_ROOMS)
    :load_block(room_type, MAX_ROOMS)

    // 13. Trap count
    :load_block(trap_count, 1)

    // 14. Trap arrays
    :load_block(trap_x, MAX_TRAPS)
    :load_block(trap_y, MAX_TRAPS)
    :load_block(trap_type, MAX_TRAPS)

    // 15. Monster table
    :load_block(monster_table, MAX_MONSTERS * MONSTER_ENTRY_SIZE)

    // 16. Floor items
    jsr load_read_floor_items

    // 16b. Recall data (4 x MAX_CREATURES = 260 bytes)
    :load_block(recall_data_start, RECALL_DATA_SIZE)

    // 17. Map data (`MAP_SIZE` bytes raw)
#if C128
    jsr load_read_map_c128
#else
    :load_block(MAP_BASE, MAP_SIZE)
#endif
    lda save_io_error
    beq !load_read_checksum+
    jmp !load_corrupt_nocl+

    // 19. Read stored checksum (2 bytes, NOT accumulated into save_cksum)
!load_read_checksum:
#if C128
    jsr SAVE_CHRIN        // Stored checksum lo (not accumulated)
    sta zp_temp0
    jsr SAVE_READST
    beq !load_checksum_hi+
    jmp !load_corrupt_nocl+
!load_checksum_hi:
    jsr SAVE_CHRIN        // Stored checksum hi (not accumulated)
    sta zp_temp1
    jsr SAVE_READST
    beq !load_checksum_status_ok+
    cmp #$40                // EOI after final expected byte is valid
    beq !load_checksum_status_ok+
    jmp !load_corrupt_nocl+
!load_checksum_status_ok:
#else
    jsr SAVE_READST
#if PLUS4
    sta disk_error_readst
    and #$fe
#endif
    beq !load_checksum_lo+
    jmp !load_corrupt_nocl+
!load_checksum_lo:
    jsr SAVE_CHRIN        // Stored checksum lo (not accumulated)
    sta zp_temp0
#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    sta plus4_test_file_cksum_lo
#endif
    jsr SAVE_READST
#if PLUS4
    sta disk_error_readst
    and #$fe
#endif
    beq !load_checksum_hi+
    jmp !load_corrupt_nocl+
!load_checksum_hi:
    jsr SAVE_CHRIN        // Stored checksum hi (not accumulated)
    sta zp_temp1
#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    sta plus4_test_file_cksum_hi
#endif
#endif

    // Check for I/O errors during read
    lda save_io_error
    beq !load_io_ok+
    jmp !load_corrupt_nocl+
!load_io_ok:

    // Verify checksum
    lda save_cksum_lo
    cmp zp_temp0
    bne !load_cksum_bad+
    lda save_cksum_hi
    cmp zp_temp1
    beq !load_cksum_ok+
!load_cksum_bad:
    jmp !load_corrupt_nocl+
!load_cksum_ok:
#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
plus4_test_load_success:
#endif
    // Close file after successful read
    jsr load_close_file_restore

    // Sync struct → ZP
    jsr player_search_clear_transient_state
    jsr player_sync_to_zp

    // Recount active entities from loaded tables
    jsr recount_monsters
    jsr recount_floor_items

    lda #LOAD_RESULT_OK
    sta load_result
#if C128
    sec
    rts
#else
    jmp !load_return_ok+
#endif

!load_corrupt:
!load_corrupt_nocl:
#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
plus4_test_load_corrupt:
#endif
    lda #LOAD_RESULT_CORRUPT
    sta load_result
    // Close file (may still be open if corruption detected mid-read)
    jsr load_close_file_restore
    ldx #HSTR_SAVE_CORRUPT
    jsr huff_print_msg
#if C128
    clc
    rts
#else
    jmp !load_return_fail+
#endif

!load_unsupported:
#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
plus4_test_load_unsupported:
#endif
    lda #LOAD_RESULT_UNSUPPORTED
    sta load_result
    jsr load_close_file_restore
#if C128 || PLUS4
    jsr hal_storage_load_stream_status
    jsr load_stream_status_message
#else
    ldx #HSTR_SAVE_UNSUPPORTED
#endif
    jsr huff_print_msg
#if C128
    clc
    rts
#else
    jmp !load_return_fail+
#endif

!load_close_notfound:
    // File was opened but returned no data — close before showing message
    jsr load_close_file_restore
!load_notfound:
#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
plus4_test_load_notfound:
#endif
    // OPEN-fail path also jumps here (file was never opened, no close needed)
    lda #LOAD_RESULT_NOTFOUND
    sta load_result
#if C128 || PLUS4
    jsr hal_storage_load_stream_status
    jsr load_stream_status_message
#else
    ldx #HSTR_SAVE_NOTFOUND
#endif
    jsr huff_print_msg
#if C128
    clc
    rts
#else
    jmp !load_return_fail+
#endif

!load_fail:
#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
plus4_test_load_ioerr:
#endif
    lda #LOAD_RESULT_IOERR
    sta load_result
#if C128 || PLUS4
    jsr hal_storage_load_stream_status
    jsr save_print_storage_status
    jmp !load_fail_after_print+
#else
    ldx #HSTR_SAVE_IOERR
#endif
    jsr huff_print_msg
!load_fail_after_print:
#if C128
    clc
    rts
#else
!load_return_fail:
#if !PLUS4
    jmp save_return_fail
!load_return_ok:
    sec
    jmp save_return_c64_with_carry
#else
    clc                     // Failure
    bcc !load_return_done+
!load_return_ok:
    sec                     // Success
!load_return_done:
    rts
#endif
#endif

// ============================================================
// save_write_block — Write N bytes from addr to file with checksum
// Input: save_block_lo/hi = source addr, save_count_lo/hi = byte count
// Clobbers: A, X, Y, zp_ptr0/hi
// ============================================================
load_close_file_restore:
    jsr save_restore_channels
    lda #hal_storage_save_file_num
    jsr SAVE_CLOSE
#if !C128 && !PLUS4
    jsr c64_restore_vic_bank0_after_serial
#endif
    rts

#if !C128 && !PLUS4
c64_restore_vic_bank0_after_serial:
    lda hal_memory_vic_bank_select
    ora #hal_memory_vic_bank0_mask
    sta hal_memory_vic_bank_select
    rts
#endif

save_write_block:
#if C128
    lda save_block_lo
    sta zp_ptr0
    lda save_block_hi
    sta zp_ptr0_hi
!swb_c128_loop:
    lda save_count_lo
    ora save_count_hi
    beq !swb_c128_done+
    jsr save_prepare_chunk_len_c128
    jsr save_stage_from_ptr0_c128
    jsr c128_save_stream_chunk
    jmp !swb_c128_loop-
!swb_c128_done:
    rts
#else
    lda save_block_lo
    sta zp_ptr0
    lda save_block_hi
    sta zp_ptr0_hi
    ldy #0
!swb_loop:
    // Check if count == 0
    lda save_count_lo
    ora save_count_hi
    beq !swb_done+
    // Read byte from source
    lda (zp_ptr0),y
    // Accumulate checksum
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !swb_no_carry+
    inc save_cksum_hi
!swb_no_carry:
    // Write byte
    lda (zp_ptr0),y
    jsr SAVE_CHROUT
    // Check status
    jsr SAVE_READST
    sta zp_temp0
    and #$03                // Timeout or error bits
    beq !swb_ok+
    inc save_io_error
#if PLUS4
    lda #$a3
    jsr disk_error_set_phase
    lda zp_temp0
    sta disk_error_readst
#endif
!swb_ok:
    // Advance pointer
    iny
    bne !swb_no_page+
    inc zp_ptr0_hi
!swb_no_page:
    // Decrement count
    lda save_count_lo
    sec
    sbc #1
    sta save_count_lo
    bcs !swb_loop-
    dec save_count_hi
    jmp !swb_loop-
!swb_done:
    rts
#endif

// ============================================================
// save_write_byte — Write single byte (in A) with checksum
// Input: A = byte to write
// Clobbers: flags
// ============================================================
save_write_byte:
#if C128
    sta zp_temp0
    txa
    pha
    lda zp_temp0
#else
    pha
#endif
    // Accumulate checksum
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !swby_no_carry+
    inc save_cksum_hi
!swby_no_carry:
#if C128
    lda zp_temp0
#else
    pla
#endif
    jsr SAVE_CHROUT
    pha
    jsr SAVE_READST
    sta zp_temp0
    and #$03
    beq !swby_ok+
    inc save_io_error
#if PLUS4
    lda #$a3
    jsr disk_error_set_phase
    lda zp_temp0
    sta disk_error_readst
#endif
!swby_ok:
    pla
#if C128
    sta zp_temp0
    pla
    tax
    lda zp_temp0
#endif
    rts

// ============================================================
// save_write_byte_raw — Write byte without checksum accumulation
// Input: A = byte to write
// ============================================================
save_write_byte_raw:
#if C128
    sta zp_temp0
    txa
    pha
    lda zp_temp0
#endif
    jsr SAVE_CHROUT
    pha
    jsr SAVE_READST
    sta zp_temp0
    and #$03
    beq !swbr_ok+
    inc save_io_error
#if PLUS4
    lda #$a3
    jsr disk_error_set_phase
    lda zp_temp0
    sta disk_error_readst
#endif
!swbr_ok:
    pla
#if C128
    sta zp_temp0
    pla
    tax
    lda zp_temp0
#endif
    rts

// ============================================================
// save_write_floor_items — Serialize packed floor-item RAM as the legacy
// logical field layout:
//   id, x, y, qty, qty_hi, p1, flags, ego
// This preserves item semantics while allowing a denser in-RAM layout.
// ============================================================
save_write_floor_items:
    :save_block(fi_item_id, MAX_FLOOR_ITEMS)
    :save_block(fi_x, MAX_FLOOR_ITEMS)
    :save_block(fi_y, MAX_FLOOR_ITEMS)
    :save_block(fi_qty, MAX_FLOOR_ITEMS)

    ldx #0
!swfi_qty_hi:
    cpx #MAX_FLOOR_ITEMS
    bcs !swfi_p1_start+
    jsr floor_item_get_qty_hi_x
    jsr save_write_byte
    inx
    jmp !swfi_qty_hi-

!swfi_p1_start:
    ldx #0
!swfi_p1:
    cpx #MAX_FLOOR_ITEMS
    bcs !swfi_flags_start+
    jsr floor_item_get_p1_x
    jsr save_write_byte
    inx
    jmp !swfi_p1-

!swfi_flags_start:
    ldx #0
!swfi_flags:
    cpx #MAX_FLOOR_ITEMS
    bcs !swfi_ego_start+
    jsr floor_item_get_flags_x
    jsr save_write_byte
    inx
    jmp !swfi_flags-

!swfi_ego_start:
    ldx #0
!swfi_ego:
    cpx #MAX_FLOOR_ITEMS
    bcs !swfi_to_hit_start+
    jsr floor_item_get_ego_x
    jsr save_write_byte
    inx
    jmp !swfi_ego-

!swfi_to_hit_start:
    :save_block(fi_to_hit, MAX_FLOOR_ITEMS)
    :save_block(fi_to_dam, MAX_FLOOR_ITEMS)
    :save_block(fi_to_ac, MAX_FLOOR_ITEMS)
!swfi_done:
    rts

// ============================================================
// load_read_block — Read N bytes from open sequential file to dest (zp_ptr0)
// Accumulates checksum. Advances zp_ptr0.
// Input: zp_ptr0/hi = dest addr, save_count_lo/hi = byte count
// Clobbers: A, X, Y
// ============================================================
load_read_block:
#if C128
!lrb_c128_loop:
    lda save_io_error
    bne !lrb_c128_done+
    lda save_count_lo
    ora save_count_hi
    beq !lrb_c128_done+
    jsr save_prepare_chunk_len_c128
    jsr c128_load_stream_chunk
    jsr load_unstage_to_ptr0_c128
    jmp !lrb_c128_loop-
!lrb_c128_done:
    rts
#else
!lrb_loop:
    lda save_io_error
    bne !lrb_done+
    // Check if count == 0
    lda save_count_lo
    ora save_count_hi
    beq !lrb_done+
    // Read byte from file (accumulates checksum)
    jsr load_read_byte
    // Store at destination
    ldy #0
    sta (zp_ptr0),y
    // Advance dest pointer
    inc zp_ptr0
    bne !lrb_no_hi+
    inc zp_ptr0_hi
!lrb_no_hi:
    // Decrement count
    lda save_count_lo
    sec
    sbc #1
    sta save_count_lo
    bcs !lrb_loop-
    dec save_count_hi
    jmp !lrb_loop-
!lrb_done:
    rts
#endif

// ============================================================
// load_read_byte — Read single byte from open sequential file with checksum
// Output: A = byte read.
// Clobbers: A, flags
// ============================================================
load_read_byte:
#if C128
    txa
    pha
#endif
    jsr SAVE_CHRIN        // Read next byte from open sequential file
    pha
#if PLUS4_TEST_SCRIPTED_LOAD_RESUME_PRODUCT || PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT
    inc plus4_test_read_count_lo
    bne !lrby_count_ok+
    inc plus4_test_read_count_hi
!lrby_count_ok:
#endif
    jsr SAVE_READST
#if C128
    beq !lrby_status_ok+
    inc save_io_error
    jmp !lrby_status_done+
#else
#if PLUS4
    sta disk_error_readst
    and #$02
#else
    and #$03
#endif
    beq !lrby_status_ok+
    inc save_io_error
#endif
!lrby_status_ok:
!lrby_status_done:
    pla
    pha
    // Accumulate checksum
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !lrby_no_carry+
    inc save_cksum_hi
!lrby_no_carry:
    pla                     // A = original byte
#if C128
    sta zp_temp0
    pla
    tax
    lda zp_temp0
#endif
    rts

#if C128
// ============================================================
// C128 chunk staging helpers — keep game zero page out of open KERNAL windows.
// The low-memory streaming helpers enter KERNAL once per staged chunk.
// ============================================================
save_prepare_chunk_len_c128:
    lda save_count_hi
    bne !full+
    lda save_count_lo
    cmp #SAVE_IO_CHUNK_SIZE
    bcs !full+
    sta save_chunk_len
    rts
!full:
    lda #SAVE_IO_CHUNK_SIZE
    sta save_chunk_len
    rts

save_stage_from_ptr0_c128:
    ldy #0
    ldx #0
!stage_loop:
    cpx save_chunk_len
    bcs !stage_done+
    lda (zp_ptr0),y
    sta save_stage_buf,x
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !no_carry+
    inc save_cksum_hi
!no_carry:
    inc zp_ptr0
    bne !ptr_ok+
    inc zp_ptr0_hi
!ptr_ok:
    lda save_count_lo
    sec
    sbc #1
    sta save_count_lo
    bcs !count_ok+
    dec save_count_hi
!count_ok:
    inx
    jmp !stage_loop-
!stage_done:
    rts

load_unstage_to_ptr0_c128:
    ldy #0
    ldx #0
!unstage_loop:
    cpx save_chunk_len
    bcs !unstage_done+
    lda save_stage_buf,x
    sta (zp_ptr0),y
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !no_carry+
    inc save_cksum_hi
!no_carry:
    inc zp_ptr0
    bne !ptr_ok+
    inc zp_ptr0_hi
!ptr_ok:
    lda save_count_lo
    sec
    sbc #1
    sta save_count_lo
    bcs !count_ok+
    dec save_count_hi
!count_ok:
    inx
    jmp !unstage_loop-
!unstage_done:
    rts
#endif

// ============================================================
// load_read_floor_items — Read floor items from savefile into the packed
// in-RAM floor table. Supports both the prior 32-slot save layout and the
// new 42-slot layout via the version byte already validated in load_game.
// ============================================================
load_read_floor_items:
    lda #MAX_FLOOR_ITEMS
    sta load_floor_item_count
    lda load_save_version
    jsr save_version_uses_legacy_floor_layout
    bcc !lrfi_count_ready+
    lda #32
    sta load_floor_item_count
!lrfi_count_ready:
    jsr item_init_floor

    lda #<fi_item_id
    sta zp_ptr0
    lda #>fi_item_id
    sta zp_ptr0_hi
    lda load_floor_item_count
    sta save_count_lo
    lda #0
    sta save_count_hi
    jsr load_read_block

    lda #<fi_x
    sta zp_ptr0
    lda #>fi_x
    sta zp_ptr0_hi
    lda load_floor_item_count
    sta save_count_lo
    lda #0
    sta save_count_hi
    jsr load_read_block

    lda #<fi_y
    sta zp_ptr0
    lda #>fi_y
    sta zp_ptr0_hi
    lda load_floor_item_count
    sta save_count_lo
    lda #0
    sta save_count_hi
    jsr load_read_block

    lda #<fi_qty
    sta zp_ptr0
    lda #>fi_qty
    sta zp_ptr0_hi
    lda load_floor_item_count
    sta save_count_lo
    lda #0
    sta save_count_hi
    jsr load_read_block

    ldx #0
!lrfi_qty_hi:
    cpx load_floor_item_count
    bcs !lrfi_p1_start+
    jsr load_read_byte
    pha
    lda fi_item_id,x
    cmp #2
    bcs !lrfi_qty_hi_skip+
    pla
    sta fi_p1,x
    jmp !lrfi_qty_hi_next+
!lrfi_qty_hi_skip:
    pla
!lrfi_qty_hi_next:
    inx
    jmp !lrfi_qty_hi-

!lrfi_p1_start:
    ldx #0
!lrfi_p1:
    cpx load_floor_item_count
    bcs !lrfi_flags_start+
    jsr load_read_byte
    pha
    lda fi_item_id,x
    cmp #2
    bcc !lrfi_p1_skip+
    pla
    sta fi_p1,x
    jmp !lrfi_p1_next+
!lrfi_p1_skip:
    pla
!lrfi_p1_next:
    inx
    jmp !lrfi_p1-

!lrfi_flags_start:
    ldx #0
!lrfi_flags:
    cpx load_floor_item_count
    bcs !lrfi_ego_start+
    jsr load_read_byte
    asl
    asl
    asl
    sta fi_meta,x
    inx
    jmp !lrfi_flags-

!lrfi_ego_start:
    ldx #0
!lrfi_ego:
    cpx load_floor_item_count
    bcs !lrfi_stats+
    jsr load_read_byte
    and #FI_META_EGO_MASK
    ora fi_meta,x
    sta fi_meta,x
    inx
    jmp !lrfi_ego-
!lrfi_stats:
    lda #<fi_to_hit
    sta zp_ptr0
    lda #>fi_to_hit
    sta zp_ptr0_hi
    lda load_floor_item_count
    sta save_count_lo
    lda #0
    sta save_count_hi
    jsr load_read_block

    lda #<fi_to_dam
    sta zp_ptr0
    lda #>fi_to_dam
    sta zp_ptr0_hi
    lda load_floor_item_count
    sta save_count_lo
    lda #0
    sta save_count_hi
    jsr load_read_block

    lda #<fi_to_ac
    sta zp_ptr0
    lda #>fi_to_ac
    sta zp_ptr0_hi
    lda load_floor_item_count
    sta save_count_lo
    lda #0
    sta save_count_hi
    jsr load_read_block
!lrfi_done:
    rts

// ============================================================
// save_version_supported — Accept any historical save version this tree
// has emitted on the current platform.
// Input: A = save version byte
// Output: carry set = supported, carry clear = unsupported
// ============================================================
save_version_supported:
    cmp #OLDEST_SAVE_VERSION
    bcc !svs_unsupported+
    cmp #(SAVE_VERSION + 1)
    bcs !svs_unsupported+
    sec
    rts
!svs_unsupported:
    clc
    rts

// ============================================================
// save_version_uses_legacy_floor_layout — Older supported saves still carry
// the pre-expanded 32-slot floor-item layout.
// Input: A = save version byte
// Output: carry set = legacy 32-slot floor layout, carry clear = current layout
// ============================================================
save_version_uses_legacy_floor_layout:
    cmp #SAVE_FLOOR42_VERSION
    bcc !svl_legacy+
    clc
    rts
!svl_legacy:
    sec
    rts

#if C128
// ============================================================
// C128 map I/O helpers — MAP_BASE is in Bank 1 RAM on C128.
// Save/load all non-map blocks through normal bank0 pointers; map bytes
// must be read/written through explicit MMU bank switching.
// ============================================================
save_write_map_c128:
    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi
    lda #<MAP_SIZE
    sta save_count_lo
    lda #>MAP_SIZE
    sta save_count_hi
!swm_loop:
    lda save_count_lo
    ora save_count_hi
    beq !swm_done+
    jsr save_prepare_chunk_len_c128
    jsr save_stage_map_c128
    jsr c128_save_stream_chunk
    jmp !swm_loop-
!swm_done:
    rts

load_read_map_c128:
    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi
    lda #<MAP_SIZE
    sta save_count_lo
    lda #>MAP_SIZE
    sta save_count_hi
!lrm_loop:
    lda save_io_error
    bne !lrm_done+
    lda save_count_lo
    ora save_count_hi
    beq !lrm_done+
    jsr save_prepare_chunk_len_c128
    jsr c128_load_stream_chunk
    jsr load_unstage_map_c128
    jmp !lrm_loop-
!lrm_done:
    rts

save_stage_map_c128:
    ldy #0
    ldx #0
!stage_loop:
    cpx save_chunk_len
    bcs !stage_done+
    jsr mmu_safe_map_read_ptr0
    sta save_stage_buf,x
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !no_carry+
    inc save_cksum_hi
!no_carry:
    inc zp_ptr0
    bne !ptr_ok+
    inc zp_ptr0_hi
!ptr_ok:
    lda save_count_lo
    sec
    sbc #1
    sta save_count_lo
    bcs !count_ok+
    dec save_count_hi
!count_ok:
    inx
    jmp !stage_loop-
!stage_done:
    rts

load_unstage_map_c128:
    ldy #0
    ldx #0
!unstage_loop:
    cpx save_chunk_len
    bcs !unstage_done+
    lda save_stage_buf,x
    jsr mmu_safe_map_write_ptr0
    lda save_stage_buf,x
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !no_carry+
    inc save_cksum_hi
!no_carry:
    inc zp_ptr0
    bne !ptr_ok+
    inc zp_ptr0_hi
!ptr_ok:
    lda save_count_lo
    sec
    sbc #1
    sta save_count_lo
    bcs !count_ok+
    dec save_count_hi
!count_ok:
    inx
    jmp !unstage_loop-
!unstage_done:
    rts
#endif

// ============================================================
// save_file_exists — Probe whether the platform save record exists.
// Output: carry set = file exists, carry clear = file not present
// Clobbers: A, X, Y
// ============================================================
save_file_exists:
    lda #hal_storage_save_read_name_len
    ldx #<hal_storage_save_read_name
    ldy #>hal_storage_save_read_name
    jsr SAVE_SETNAM
    lda #hal_storage_check_file_num
    ldx save_device
    ldy #hal_storage_check_sec_read
    jsr SAVE_SETLFS
    jsr SAVE_OPEN
#if !C128 && !PLUS4
    bcc !sfe_exists+
    clc
    rts
!sfe_exists:
    lda #hal_storage_check_file_num
    jsr SAVE_CLOSE
    sec
    rts
#else
    bcc !sfe_open_ok+
    clc
    bcc !sfe_cleanup+
!sfe_open_ok:
    ldx #hal_storage_check_file_num
    jsr SAVE_CHKIN
    bcs !sfe_cleanup+
!sfe_chkin_ok:
    jsr SAVE_CHRIN
    jsr SAVE_READST
    cmp #$42                // LOAD-missing status on 1541 path
    beq !sfe_missing+
    sec
    bcs !sfe_close+
!sfe_missing:
    clc
!sfe_close:
!sfe_cleanup:
    php
    lda #hal_storage_check_file_num
    jsr SAVE_CLOSE
    jsr save_restore_channels
#if C128
    lda hal_memory_vic_bank_select
    ora #hal_memory_vic_bank0_mask
    sta hal_memory_vic_bank_select
#endif
    plp
    rts
#endif

// ============================================================
// save_restore_channels — restore default KERNAL channels
// C128 workaround: avoid CLRCHN vector path; use explicit CHKIN/CHKOUT.
// C64 path keeps CLRCHN behavior.
// ============================================================
save_restore_channels:
#if C128
    // Restore default channels through the resident C128 KERNAL wrapper before
    // returning to runtime/program-file LOADs.
    jmp w_clrchn
#else
    jsr SAVE_CLRCHN
    rts
#endif

// ============================================================
// recount_monsters — Scan monster_table, set zp_mon_count
// Clobbers: A, X
// ============================================================
recount_monsters:
    lda #0
    sta zp_mon_count
    ldx #0
!rcm_loop:
    cpx #MAX_MONSTERS
    bcs !rcm_done+
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp #EMPTY_SLOT
    beq !rcm_next+
    inc zp_mon_count
!rcm_next:
    inx
    jmp !rcm_loop-
!rcm_done:
    rts

// ============================================================
// recount_floor_items — Scan fi_item_id, set zp_item_count
// Clobbers: A, X
// ============================================================
recount_floor_items:
    lda #0
    sta zp_item_count
    ldx #0
!rcfi_loop:
    cpx #MAX_FLOOR_ITEMS
    bcs !rcfi_done+
    lda fi_item_id,x
    cmp #FI_EMPTY
    beq !rcfi_next+
    inc zp_item_count
!rcfi_next:
    inx
    jmp !rcfi_loop-
!rcfi_done:
    rts

// ============================================================
// Test-only map compressor retained for save round-trip coverage.
// Production save/load writes the map raw.
// ============================================================
#if SAVE_TEST_RLE
rle_compress_map:
    // Source pointer: MAP_BASE
    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi

    // Dest pointer: CREATURE_BASE
    lda rle_work_lo
    sta zp_ptr1
    lda rle_work_hi
    sta zp_ptr1_hi

    // Remaining bytes = MAP_SIZE
    lda #<MAP_SIZE
    sta save_count_lo
    lda #>MAP_SIZE
    sta save_count_hi

    // Output size = 0
    lda #0
    sta rle_size_lo
    sta rle_size_hi
    sta rle_lit_len

!rle_c_loop:
    // Check if done
    lda save_count_lo
    ora save_count_hi
    bne !rle_c_not_done+
    jmp !rle_c_flush_lit+
!rle_c_not_done:

    // Read current byte
    ldy #0
    lda (zp_ptr0),y
    sta rle_run_byte
    lda #1
    sta rle_run_len

    // Count run of same bytes
!rle_c_count:
    // Check if we've hit max repeat or end of input
    lda rle_run_len
    cmp #RLE_REPEAT_MAX
    bcs !rle_c_emit+

    // More input?
    // remaining - run_len > 0?
    lda save_count_lo
    sec
    sbc rle_run_len
    sta zp_temp0
    lda save_count_hi
    sbc #0
    ora zp_temp0
    beq !rle_c_emit+       // Exactly run_len bytes left

    // Check next byte
    ldy rle_run_len
    lda (zp_ptr0),y
    cmp rle_run_byte
    bne !rle_c_emit+
    inc rle_run_len
    jmp !rle_c_count-

!rle_c_emit:
    // If run >= 3, emit repeat packet
    lda rle_run_len
    cmp #RLE_REPEAT_MIN
    bcs !rle_c_repeat+

    // Run < 3: add to literal buffer
    ldy #0
!rle_c_add_lit:
    cpy rle_run_len
    bcs !rle_c_lit_added+
    ldx rle_lit_len
    lda rle_run_byte
    sta rle_lit_buf,x
    inc rle_lit_len
    // Flush literal buffer if full (128)
    lda rle_lit_len
    cmp #RLE_LITERAL_MAX
    bcc !rle_c_no_flush+
    jsr rle_flush_literals
!rle_c_no_flush:
    iny
    jmp !rle_c_add_lit-
!rle_c_lit_added:
    jmp !rle_c_advance+

!rle_c_repeat:
    // Flush any pending literals first
    lda rle_lit_len
    beq !rle_c_no_lit+
    jsr rle_flush_literals
!rle_c_no_lit:
    // Emit repeat packet: header = run_len + $7D, then the byte
    lda rle_run_len
    clc
    adc #$7d                // len + $7D (3→$80, 130→$FF)
    ldy #0
    sta (zp_ptr1),y
    iny
    lda rle_run_byte
    sta (zp_ptr1),y
    // Advance dest by 2
    lda zp_ptr1
    clc
    adc #2
    sta zp_ptr1
    bcc !rle_c_no_dp+
    inc zp_ptr1_hi
!rle_c_no_dp:
    // Update output size
    lda rle_size_lo
    clc
    adc #2
    sta rle_size_lo
    bcc !rle_c_advance+
    inc rle_size_hi

!rle_c_advance:
    // Advance source by run_len
    lda zp_ptr0
    clc
    adc rle_run_len
    sta zp_ptr0
    bcc !rle_c_no_sp+
    inc zp_ptr0_hi
!rle_c_no_sp:
    // Decrease remaining by run_len
    lda save_count_lo
    sec
    sbc rle_run_len
    sta save_count_lo
    bcs !rle_c_no_borrow+
    dec save_count_hi
!rle_c_no_borrow:
    jmp !rle_c_loop-

!rle_c_flush_lit:
    // Flush remaining literals
    lda rle_lit_len
    beq !rle_c_done+
    jsr rle_flush_literals
!rle_c_done:
    rts

// rle_flush_literals — Write literal packet from rle_lit_buf
// Packet: header byte = (len-1), then len data bytes
// Clobbers: A, X, Y
rle_flush_literals:
    lda rle_lit_len
    beq !rfl_done+
    // Header: len - 1
    sec
    sbc #1
    ldy #0
    sta (zp_ptr1),y
    iny
    // Copy literal bytes
    ldx #0
!rfl_copy:
    cpx rle_lit_len
    bcs !rfl_copied+
    lda rle_lit_buf,x
    sta (zp_ptr1),y
    inx
    iny
    // Handle dest page crossing (Y wrap from $FF→$00)
    // Currently dead code: max literal is 128, Y starts at 1, max Y=129.
    bne !rfl_copy-
    inc zp_ptr1_hi
    jmp !rfl_copy-
!rfl_copied:
    // Advance dest pointer: already at ptr1 + Y
    tya
    clc
    adc zp_ptr1
    sta zp_ptr1
    bcc !rfl_no_dp+
    inc zp_ptr1_hi
!rfl_no_dp:
    // Update output size: header(1) + data(lit_len)
    lda rle_size_lo
    clc
    adc rle_lit_len
    sta rle_size_lo
    bcc !rfl_no_c1+
    inc rle_size_hi
!rfl_no_c1:
    inc rle_size_lo         // +1 for header byte
    bne !rfl_no_c2+
    inc rle_size_hi
!rfl_no_c2:
    // Reset literal buffer
    lda #0
    sta rle_lit_len
!rfl_done:
    rts

// Helper: advance dest pointer by 1, check bounds (used by test decompressor)
rle_d_advance_dst:
    inc zp_ptr1
    bne !rdad_no+
    inc zp_ptr1_hi
!rdad_no:
    // Bounds check: dest must not exceed MAP_END.
    // After writing the final byte at MAP_END, ptr1 may advance to MAP_END+1.
    // That is still valid — only the I/O area and beyond is a true overflow.
    lda zp_ptr1_hi
    cmp #>(MAP_END + 1) + 1 // $D0 = into I/O area, truly past map
    bcc !rdad_ok+
    inc save_io_error       // Flag overflow — corrupt compressed data
!rdad_ok:
    rts
#endif
