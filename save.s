// save.s — Save/Load game system with RLE map compression
//
// Writes all game state to a sequential file on 1541 disk via KERNAL I/O.
// Load restores state and deletes the savefile to enforce permadeath.
// Uses 16-bit additive complement checksum for integrity.
//
// KERNAL calls: SETNAM($FFBD), SETLFS($FFBA), OPEN($FFC0), CLOSE($FFC3),
//   CHKOUT($FFC9), CHKIN($FFC6), CLRCHN($FFCC), CHROUT($FFD2),
//   CHRIN($FFCF), READST($FFB7)

// ============================================================
// Constants
// ============================================================
.const SAVE_FILE_NUM  = 2       // Logical file number for save/load data
.const CHECK_FILE_NUM = 3       // Separate file number for check_savefile_exists
.const SAVE_DEVICE    = 8       // Device 8 = first disk drive
.const SAVE_SEC_ADDR  = 2       // Secondary address for write (1541 channel 2)
.const LOAD_SEC_ADDR  = 5       // Secondary address for read (1541 channel 5)
.const CHECK_SEC_ADDR = 6       // Secondary address for existence check (1541 channel 6)
.const CMD_CHANNEL    = 15      // Command channel file number

.const SAVE_MAGIC_SIZE = 8
.const SAVE_VERSION    = $03

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

// ============================================================
// KERNAL vectors
// ============================================================
.const KERNAL_SETNAM = $ffbd
.const KERNAL_SETLFS = $ffba
.const KERNAL_OPEN   = $ffc0
.const KERNAL_CLOSE  = $ffc3
.const KERNAL_CHKOUT = $ffc9
.const KERNAL_CHKIN  = $ffc6
.const KERNAL_CLRCHN = $ffcc
.const KERNAL_CHROUT = $ffd2
.const KERNAL_CHRIN  = $ffcf
.const KERNAL_READST = $ffb7

// ============================================================
// Scratch variables (before code so BRK is last in tests)
// ============================================================
save_block_lo:  .byte 0         // Source address lo for save_write_block
save_block_hi:  .byte 0         // Source address hi
save_count_lo:  .byte 0         // Byte count lo
save_count_hi:  .byte 0         // Byte count hi
save_cksum_lo:  .byte 0         // Running checksum lo
save_cksum_hi:  .byte 0         // Running checksum hi
rle_size_lo:    .byte 0         // Compressed map size lo
rle_size_hi:    .byte 0         // Compressed map size hi
rle_run_byte:   .byte 0         // Current run byte value
rle_run_len:    .byte 0         // Current run length
rle_lit_len:    .byte 0         // Literal buffer length
save_io_error:  .byte 0         // I/O error flag
rle_work_lo:    .byte <CREATURE_BASE  // RLE workspace pointer lo (default CREATURE_BASE)
rle_work_hi:    .byte >CREATURE_BASE  // RLE workspace pointer hi

// Literal buffer for RLE (max 128 bytes)
rle_lit_buf:    .fill 128, 0

// ============================================================
// String data (PETSCII for KERNAL I/O — NOT screen codes)
// ============================================================
// Note: KERNAL SETNAM needs PETSCII filenames.
// Use raw byte values to avoid screencode encoding.
save_filename:
    .byte $40               // "@" — replace existing file prefix
    .byte $30, $3a          // "0:"
    .byte $54, $48, $45, $2e, $47, $41, $4d, $45  // "THE.GAME"
    .byte $2c, $53, $2c, $57  // ",S,W" (sequential, write)
.label save_filename_len = * - save_filename

load_filename:
    .byte $30, $3a          // "0:"
    .byte $54, $48, $45, $2e, $47, $41, $4d, $45  // "THE.GAME"
    .byte $2c, $53, $2c, $52  // ",S,R" (sequential, read)
.label load_filename_len = * - load_filename

scratch_cmd:
    .byte $53, $30, $3a     // "S0:"
    .byte $54, $48, $45, $2e, $47, $41, $4d, $45  // "THE.GAME"
.label scratch_cmd_len = * - scratch_cmd

save_magic:
    .byte $4d, $4f, $52, $49, $41, $30, $31  // "MORIA01"
    .byte SAVE_VERSION                          // Version byte
.assert "Magic is 8 bytes", * - save_magic, SAVE_MAGIC_SIZE

// Screen-code strings for status messages
.encoding "screencode_upper"
save_saving_str:
    .text "SAVING GAME..." ; .byte 0
save_done_str:
    .text "GAME SAVED." ; .byte 0
save_load_str:
    .text "LOADING GAME..." ; .byte 0
save_corrupt_str:
    .text "SAVE FILE CORRUPT!" ; .byte 0
save_ioerr_str:
    .text "DISK ERROR!" ; .byte 0
save_welcome_str:
    .text "WELCOME BACK TO MORIA!" ; .byte 0
title_menu_str:
    .text "N)EW  L)OAD  D)UAL DISK" ; .byte 0

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
// Syncs ZP→struct, writes all blocks + RLE map + checksum, closes
// Clobbers: A, X, Y, all scratch
// ============================================================
save_game:
    // Show "SAVING GAME..." message
    lda #<save_saving_str
    sta zp_ptr0
    lda #>save_saving_str
    sta zp_ptr0_hi
    jsr msg_print

    // Sync ZP fields back to player struct
    jsr player_sync_from_zp

    // Reset checksum
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    sta save_io_error

    // Compress map while we can still use CREATURE_BASE as workspace
    // (monster_table will be written before we need it)
    jsr rle_compress_map

    // Delete old save file (ignore errors)
    jsr delete_savefile

    // Open file for writing
    // SETNAM
    lda #save_filename_len
    ldx #<save_filename
    ldy #>save_filename
    jsr KERNAL_SETNAM
    // SETLFS: file#2, device 8, secondary 2
    lda #SAVE_FILE_NUM
    ldx #SAVE_DEVICE
    ldy #SAVE_SEC_ADDR
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcc !save_open_ok+
    jmp !save_error+
!save_open_ok:

    // Direct output to file
    ldx #SAVE_FILE_NUM
    jsr KERNAL_CHKOUT
    bcc !save_chkout_ok+
    jmp !save_error_close+
!save_chkout_ok:

    // --- Write blocks in order ---

    // 1. Magic header (8 bytes)
    :save_block(save_magic, SAVE_MAGIC_SIZE)

    // 2. Player data (80 bytes)
    :save_block(player_data, PL_STRUCT_SIZE)

    // 3. ZP game state $40-$5f (32 bytes)
    :save_block(ZP_STATE_START, ZP_STATE_SIZE)

    // 4. RNG state $1a-$1d (4 bytes)
    :save_block(ZP_RNG_START, ZP_RNG_SIZE)

    // 5. Inventory (5 × 30 = 150 bytes)
    :save_block(inv_item_id, TOTAL_INV_SLOTS)
    :save_block(inv_qty, TOTAL_INV_SLOTS)
    :save_block(inv_p1, TOTAL_INV_SLOTS)
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

    // 8. Store inventory (4 × 72 = 288 bytes)
    :save_block(si_item_id, STORE_TOTAL_SLOTS)
    :save_block(si_qty, STORE_TOTAL_SLOTS)
    :save_block(si_p1, STORE_TOTAL_SLOTS)
    :save_block(si_flags, STORE_TOTAL_SLOTS)

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

    // 16. Floor items (7 × 32 = 224 bytes)
    :save_block(fi_item_id, MAX_FLOOR_ITEMS)
    :save_block(fi_x, MAX_FLOOR_ITEMS)
    :save_block(fi_y, MAX_FLOOR_ITEMS)
    :save_block(fi_qty, MAX_FLOOR_ITEMS)
    :save_block(fi_p1, MAX_FLOOR_ITEMS)
    :save_block(fi_flags, MAX_FLOOR_ITEMS)
    :save_block(fi_ego, MAX_FLOOR_ITEMS)

    // 17. RLE map size (2 bytes, little-endian)
    lda rle_size_lo
    jsr save_write_byte
    lda rle_size_hi
    jsr save_write_byte

    // 18. RLE compressed map data (dynamic size — inline, not macro)
    lda rle_work_lo
    sta save_block_lo
    lda rle_work_hi
    sta save_block_hi
    lda rle_size_lo
    sta save_count_lo
    lda rle_size_hi
    sta save_count_hi
    jsr save_write_block
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
    jsr KERNAL_CLRCHN
    lda #SAVE_FILE_NUM
    jsr KERNAL_CLOSE

    // Show success
    lda #<save_done_str
    sta zp_ptr0
    lda #>save_done_str
    sta zp_ptr0_hi
    jsr msg_print
    rts

!save_error_close:
    jsr KERNAL_CLRCHN
    lda #SAVE_FILE_NUM
    jsr KERNAL_CLOSE
!save_error:
    lda #<save_ioerr_str
    sta zp_ptr0
    lda #>save_ioerr_str
    sta zp_ptr0_hi
    jsr msg_print
    rts

// ============================================================
// load_game — Top-level load routine
// Opens file, verifies magic, reads all blocks, verifies checksum,
// decompresses map, syncs struct→ZP, deletes savefile.
// Output: carry set = success, carry clear = failure
// Clobbers: A, X, Y, all scratch
// ============================================================

load_game:
    // Show "LOADING GAME..." message
    lda #<save_load_str
    sta zp_ptr0
    lda #>save_load_str
    sta zp_ptr0_hi
    jsr msg_print

    // Reset checksum
    lda #0
    sta save_cksum_lo
    sta save_cksum_hi
    sta save_io_error

    // Open file for reading
    lda #load_filename_len
    ldx #<load_filename
    ldy #>load_filename
    jsr KERNAL_SETNAM
    lda #SAVE_FILE_NUM
    ldx #SAVE_DEVICE
    ldy #LOAD_SEC_ADDR
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcc !load_open_ok+
    jmp !load_fail+
!load_open_ok:

    // Direct input from file
    ldx #SAVE_FILE_NUM
    jsr KERNAL_CHKIN
    bcc !load_chkin_ok+
    jmp !load_fail_close+
!load_chkin_ok:

    // --- Read and verify magic header ---
    // Read 8 bytes to temp area and compare
    :load_block(rle_lit_buf, SAVE_MAGIC_SIZE)
    ldx #0
!check_magic:
    lda rle_lit_buf,x
    cmp save_magic,x
    beq !magic_ok+
    jmp !load_corrupt+
!magic_ok:
    inx
    cpx #SAVE_MAGIC_SIZE
    bcc !check_magic-

    // --- Read all blocks in same order as save ---

    // 2. Player data
    :load_block(player_data, PL_STRUCT_SIZE)

    // 3. ZP game state
    :load_block(ZP_STATE_START, ZP_STATE_SIZE)

    // 4. RNG state
    :load_block(ZP_RNG_START, ZP_RNG_SIZE)

    // 5. Inventory
    :load_block(inv_item_id, TOTAL_INV_SLOTS)
    :load_block(inv_qty, TOTAL_INV_SLOTS)
    :load_block(inv_p1, TOTAL_INV_SLOTS)
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
    :load_block(si_flags, STORE_TOTAL_SLOTS)

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
    :load_block(fi_item_id, MAX_FLOOR_ITEMS)
    :load_block(fi_x, MAX_FLOOR_ITEMS)
    :load_block(fi_y, MAX_FLOOR_ITEMS)
    :load_block(fi_qty, MAX_FLOOR_ITEMS)
    :load_block(fi_p1, MAX_FLOOR_ITEMS)
    :load_block(fi_flags, MAX_FLOOR_ITEMS)
    :load_block(fi_ego, MAX_FLOOR_ITEMS)

    // 17. RLE map size (2 bytes)
    jsr load_read_byte
    sta rle_size_lo
    jsr load_read_byte
    sta rle_size_hi

    // 18. Decompress RLE map directly from file → MAP_BASE
    // (Streaming decompressor avoids workspace/MAP_BASE overlap)
    jsr rle_decompress_from_file

    // 19. Read stored checksum (2 bytes, NOT accumulated)
    jsr KERNAL_CHRIN
    sta zp_temp0            // Stored checksum lo
    jsr KERNAL_CHRIN
    sta zp_temp1            // Stored checksum hi

    // Check I/O error
    lda save_io_error
    beq !load_io_ok+
    jmp !load_fail_close+
!load_io_ok:

    // Close file (map already decompressed from file stream)
    jsr KERNAL_CLRCHN
    lda #SAVE_FILE_NUM
    jsr KERNAL_CLOSE

    // Verify checksum: computed sum must match stored sum
    lda save_cksum_lo
    cmp zp_temp0
    bne !load_cksum_bad+
    lda save_cksum_hi
    cmp zp_temp1
    beq !load_cksum_ok+
!load_cksum_bad:
    jmp !load_corrupt_nocl+
!load_cksum_ok:

    // Sync struct → ZP
    jsr player_sync_to_zp

    // Recount active entities from loaded tables
    jsr recount_monsters
    jsr recount_floor_items

    // Delete savefile (permadeath)
    jsr delete_savefile

    sec                     // Success
    rts

!load_corrupt:
    jsr KERNAL_CLRCHN
    lda #SAVE_FILE_NUM
    jsr KERNAL_CLOSE
!load_corrupt_nocl:
    lda #<save_corrupt_str
    sta zp_ptr0
    lda #>save_corrupt_str
    sta zp_ptr0_hi
    jsr msg_print
    clc                     // Failure
    rts

!load_fail_close:
    jsr KERNAL_CLRCHN
    lda #SAVE_FILE_NUM
    jsr KERNAL_CLOSE
!load_fail:
    lda #<save_ioerr_str
    sta zp_ptr0
    lda #>save_ioerr_str
    sta zp_ptr0_hi
    jsr msg_print
    clc                     // Failure
    rts

// ============================================================
// save_write_block — Write N bytes from addr to file with checksum
// Input: save_block_lo/hi = source addr, save_count_lo/hi = byte count
// Clobbers: A, X, Y, zp_ptr0/hi
// ============================================================
save_write_block:
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
    jsr KERNAL_CHROUT
    // Check status
    jsr KERNAL_READST
    and #$03                // Timeout or error bits
    beq !swb_ok+
    inc save_io_error
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

// ============================================================
// save_write_byte — Write single byte (in A) with checksum
// Input: A = byte to write
// Clobbers: flags
// ============================================================
save_write_byte:
    pha
    // Accumulate checksum
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !swby_no_carry+
    inc save_cksum_hi
!swby_no_carry:
    pla
    jsr KERNAL_CHROUT
    pha
    jsr KERNAL_READST
    and #$03
    beq !swby_ok+
    inc save_io_error
!swby_ok:
    pla
    rts

// ============================================================
// save_write_byte_raw — Write byte without checksum accumulation
// Input: A = byte to write
// ============================================================
save_write_byte_raw:
    jsr KERNAL_CHROUT
    pha
    jsr KERNAL_READST
    and #$03
    beq !swbr_ok+
    inc save_io_error
!swbr_ok:
    pla
    rts

// ============================================================
// load_read_block — Read N bytes from file to addr with checksum
// Input: zp_ptr0/hi = dest addr, save_count_lo/hi = byte count
// Clobbers: A, X, Y
// ============================================================
load_read_block:
    ldy #0
!lrb_loop:
    // Check if count == 0
    lda save_count_lo
    ora save_count_hi
    beq !lrb_done+
    // Read byte from file
    jsr KERNAL_CHRIN
    // Store at destination
    sta (zp_ptr0),y
    // Accumulate checksum
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !lrb_no_carry+
    inc save_cksum_hi
!lrb_no_carry:
    // Check status (bit 6 = EOF, bits 1-0 = timeout/error)
    jsr KERNAL_READST
    and #$43
    beq !lrb_ok+
    inc save_io_error
!lrb_ok:
    // Advance pointer
    iny
    bne !lrb_no_page+
    inc zp_ptr0_hi
!lrb_no_page:
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

// ============================================================
// load_read_byte — Read single byte from file with checksum
// Output: A = byte read
// Clobbers: flags
// ============================================================
load_read_byte:
    jsr KERNAL_CHRIN
    pha
    // Accumulate checksum
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !lrby_no_carry+
    inc save_cksum_hi
!lrby_no_carry:
    // Check status (bit 6 = EOF, bits 1-0 = timeout/error)
    jsr KERNAL_READST
    and #$43
    beq !lrby_ok+
    inc save_io_error
!lrby_ok:
    pla
    rts

// ============================================================
// delete_savefile — Send scratch command via command channel
// Clobbers: A, X, Y
// ============================================================
delete_savefile:
    // Open command channel — scratch command executes on OPEN
    lda #scratch_cmd_len
    ldx #<scratch_cmd
    ldy #>scratch_cmd
    jsr KERNAL_SETNAM
    lda #CMD_CHANNEL
    ldx #SAVE_DEVICE
    ldy #CMD_CHANNEL
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcs !dsf_done+          // OPEN failed — nothing to close
    lda #CMD_CHANNEL
    jsr KERNAL_CLOSE
!dsf_done:
    jsr KERNAL_CLRCHN
    rts

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
// rle_compress_map — Compress MAP_BASE → CREATURE_BASE
// Output: rle_size_lo/hi = compressed size
// Workspace: CREATURE_BASE (must be safe to write)
// Clobbers: A, X, Y, zp_ptr0/hi, zp_ptr1/hi
// ============================================================
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

    // Remaining bytes = MAP_SIZE (3840)
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

// ============================================================
// rle_decompress_from_file — Stream-decompress RLE from open file → MAP_BASE
// Reads compressed bytes via load_read_byte (accumulates checksum).
// Avoids workspace/MAP_BASE overlap by reading directly from disk.
// Input: rle_size_lo/hi = compressed data size (file must be open with CHKIN)
// Clobbers: A, Y, zp_ptr1/hi, save_count_lo/hi, rle_run_len, rle_run_byte
// ============================================================
rle_decompress_from_file:
    // Dest: MAP_BASE
    lda #<MAP_BASE
    sta zp_ptr1
    lda #>MAP_BASE
    sta zp_ptr1_hi

    // Remaining compressed bytes
    lda rle_size_lo
    sta save_count_lo
    lda rle_size_hi
    sta save_count_hi

!rdff_loop:
    // Done?
    lda save_count_lo
    ora save_count_hi
    beq !rdff_done+
    lda save_io_error
    bne !rdff_done+

    // Read header byte from file
    jsr rdff_read_byte
    cmp #$80
    bcs !rdff_repeat+

    // --- Literal run: length = header + 1 ---
    clc
    adc #1
    sta rle_run_len
!rdff_lit:
    lda rle_run_len
    beq !rdff_loop-
    jsr rdff_read_byte
    ldy #0
    sta (zp_ptr1),y
    jsr rle_d_advance_dst
    dec rle_run_len
    jmp !rdff_lit-

!rdff_repeat:
    // --- Repeat run: length = header - $7D ---
    sec
    sbc #$7d
    sta rle_run_len
    jsr rdff_read_byte
    sta rle_run_byte
!rdff_rep:
    lda rle_run_len
    beq !rdff_loop-
    lda rle_run_byte
    ldy #0
    sta (zp_ptr1),y
    jsr rle_d_advance_dst
    dec rle_run_len
    jmp !rdff_rep-

!rdff_done:
    rts

// Helper: read one RLE byte from file with checksum + count decrement
rdff_read_byte:
    jsr load_read_byte
    pha
    lda save_count_lo
    sec
    sbc #1
    sta save_count_lo
    bcs !+
    dec save_count_hi
!:  pla
    rts

// Helper: advance dest pointer by 1, check bounds
rle_d_advance_dst:
    inc zp_ptr1
    bne !rdad_no+
    inc zp_ptr1_hi
!rdad_no:
    // Bounds check: dest must not exceed MAP_END ($CEFF)
    lda zp_ptr1_hi
    cmp #>(MAP_END + 1)     // $CF = past end of map
    bcc !rdad_ok+
    inc save_io_error       // Flag overflow — corrupt compressed data
!rdad_ok:
    rts

