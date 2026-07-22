#importonce
// save_stream.s — Buffered byte-stream backend for the shared save engine.
//
// Implements the KERNAL-shaped storage primitives consumed by
// platforms/shared/save.s and core/score_io.s (SAVE_SETNAM..SAVE_READST
// aliases) on top of the ProDOS 8 MLI helpers in storage_mli.s. ProDOS files
// are byte-addressable, so the stream is a permanent, ordinary buffered
// design: one open MLI ref_num, a 256-byte staging buffer in main RAM,
// MLI READ on refill / MLI WRITE on flush.
//
// Semantics preserved from the Commodore adapters:
// - Open mode comes from the filename suffix, not the secondary address
//   (the policy sets both secondary addresses to 2, exactly like the 1541
//   data-channel usage): ",S,R" = open for read, error if missing;
//   ",S,W" = create-if-missing + truncate; a leading '@' destroys any
//   existing file first (save-with-replace).
// - A logical file number of hal_storage_cmd_channel (15), or a "S0:" name
//   prefix, is a command open: DESTROY, best-effort, always carry clear
//   (hiscore scratch semantics).
// - READST: 0 = ok, $40 = EOF (set once the buffer is drained after a short
//   MLI READ), $01 = write-side error, $02 = read-side error. save.s masks
//   $03 on both paths and tests $40/beq on the load paths; EOF mid-block is
//   caught by the save checksum, matching Commodore behavior.
// - CHRIN/CHROUT preserve A (CHROUT), X, Y, and all of zero page — callers
//   hold loop state in registers and zp_ptr0 across byte calls.
// - Only refill/flush/open/close touch the MLI, so only those paths pay the
//   save_zp/restore_zp + thunk-reinstall wrap (a2_mli_begin/a2_mli_end).
//
// Stream state lives in platform-owned ZP $94-$A3 (memory.s: the platform
// claims $90-$EF; the MLI never touches ZP >= $90, so state survives MLI
// calls without save/restore). The stream buffer is a2_ss_buf below: a
// 256-byte block in resident main RAM, refilled with 255-byte MLI READs so
// trans_count always fits one byte.

#import "hal/hal_contract.s"
#import "hal/storage_policy.s"

// ============================================================
// Stream state (platform ZP)
// ============================================================
.const a2_ss_name_lo   = $94          // stashed SETNAM name pointer
.const a2_ss_name_hi   = $95
.const a2_ss_name_len  = $96
.const a2_ss_lfn       = $97          // stashed SETLFS logical file number
.const a2_ss_sec       = $98          // stashed SETLFS secondary address
.const a2_ss_ref       = $99          // open MLI ref_num
.const a2_ss_dir       = $9a          // A2_SS_DIR_* below
.const a2_ss_idx       = $9b          // buffer cursor (read next / write next)
.const a2_ss_count     = $9c          // valid bytes in buffer (read mode)
.const a2_ss_eof       = $9d          // 1 = MLI signalled EOF; buffer drains to $40
.const a2_ss_status    = $9e          // sticky stream error ($01 write / $02 read)
.const a2_ss_open      = $9f          // 1 = stream open
.const a2_ss_fresh     = $a0          // 1 = file created by this open (no truncate)
.const a2_ss_tmp_x     = $a1          // register preserves
.const a2_ss_tmp_y     = $a2

.const A2_SS_DIR_NONE  = 0
.const A2_SS_DIR_READ  = 1
.const A2_SS_DIR_WRITE = 2

// ============================================================
// Stream buffer (resident main RAM, 256 bytes; 255 used per refill)
// ============================================================
a2_ss_buf: .fill 256, 0

// ============================================================
// hal_storage_setnam — Stash the filename (KERNAL SETNAM shape).
// Input: A = name length, X = name lo, Y = name hi.
// The name is parsed later by a2_mli_set_pathname during OPEN.
// ============================================================
hal_storage_setnam:
    sta a2_ss_name_len
    stx a2_ss_name_lo
    sty a2_ss_name_hi
    rts

// ============================================================
// hal_storage_setlfs — Stash logical file / device / secondary.
// Input: A = logical file number, X = device, Y = secondary address.
// The device number is advisory (boot volume only); it is recorded in the
// diagnostic byte. Secondary addresses carry no mode meaning here — the
// filename suffix selects the open mode, as on the 1541.
// ============================================================
hal_storage_setlfs:
    sta a2_ss_lfn
    stx hal_storage_diag_device
    sty a2_ss_sec
    rts

// ============================================================
// hal_storage_open — Translate the stashed name into an MLI open.
// Read mode: OPEN, error (carry set) if the file is missing.
// Write mode: optional DESTROY ('@' replace), CREATE (duplicate tolerated),
//             OPEN, SET_EOF 0 truncate when the file pre-existed.
// Command mode (lfn 15 or "S0:" name): best-effort DESTROY, always success.
// Output: carry clear = open; carry set with A = HAL_STATUS_*, X = raw
//         ProDOS code, Y = HAL_STORAGE_PHASE_* (diag bytes updated).
// ============================================================
hal_storage_open:
    lda a2_ss_open
    beq !fresh+
    lda a2_ss_lfn                   // defensive: never two streams at once
    jsr hal_storage_close
!fresh:
    lda #0
    sta a2_ss_dir
    sta a2_ss_idx
    sta a2_ss_count
    sta a2_ss_eof
    sta a2_ss_status
    sta a2_ss_fresh
    lda a2_ss_name_len
    ldx a2_ss_name_lo
    ldy a2_ss_name_hi
    jsr a2_mli_set_pathname
    lda a2_ss_lfn
    cmp #hal_storage_cmd_channel
    beq !command+
    lda a2_name_scratch
    beq !data+
!command:
    // "S0:name" = scratch: DESTROY, missing file is not an error.
    jsr a2_mli_begin
    lda #HAL_STORAGE_PHASE_COMMAND
    sta hal_storage_diag_phase
    jsr a2i_destroy
    jsr a2_mli_end
    clc
    rts
!data:
    lda a2_name_write
    bne !write_mode+
    // ---- open for read ----
    jsr a2_mli_begin
    lda #HAL_STORAGE_PHASE_OPEN
    sta hal_storage_diag_phase
    jsr a2i_open
    jsr a2_mli_end
    bcs !fail+
    lda a2_open_ref
    sta a2_ss_ref
    lda #A2_SS_DIR_READ
    sta a2_ss_dir
    lda #1
    sta a2_ss_open
    clc
    rts
!fail:
    jsr a2_map_error
    rts                             // carry set by a2_map_error
!write_mode:
    // ---- open for write ----
    jsr a2_mli_begin
    lda #HAL_STORAGE_PHASE_OPEN
    sta hal_storage_diag_phase
    lda a2_name_replace
    beq !create+
    jsr a2i_destroy
    bcc !create+
    cmp #A2ERR_NOT_FOUND
    beq !create+
    jmp !fail_end+
!create:
    jsr a2i_create
    bcc !created+
    cmp #A2ERR_DUPLICATE
    bne !fail_end+
    jmp !open_write+                // exists already: open + truncate
!created:
    lda #1
    sta a2_ss_fresh
!open_write:
    jsr a2i_open
    bcc !truncate+
!fail_end:
    jsr a2_mli_end
    jsr a2_map_error
    rts                             // carry set
!truncate:
    lda a2_ss_fresh
    bne !opened+
    // Pre-existing file opened without replace: rewind EOF to 0 so stale
    // tail bytes can never survive a shorter rewrite.
    lda a2_open_ref
    sta a2_eof_ref
    jsr a2i_set_eof0
    bcs !close_fail+
!opened:
    jsr a2_mli_end
    lda a2_open_ref
    sta a2_ss_ref
    lda #A2_SS_DIR_WRITE
    sta a2_ss_dir
    lda #1
    sta a2_ss_open
    clc
    rts
!close_fail:
    pha
    jsr a2i_close_open_ref
    pla
    jmp !fail_end-

// ============================================================
// hal_storage_close — Flush (write mode) and close the MLI ref_num.
// Input: A = logical file number (advisory; one stream policy).
// Closing an unopened stream is a harmless success, matching the way
// save.s/score_io.s clean up after failed opens.
// ============================================================
hal_storage_close:
    ldx a2_ss_open
    bne !open+
    clc
    rts
!open:
    lda a2_ss_dir
    cmp #A2_SS_DIR_WRITE
    bne !no_flush+
    lda a2_ss_idx
    beq !no_flush+
    jsr a2_ss_flush                 // sticky status on error; close regardless
!no_flush:
    lda a2_ss_ref
    sta a2_close_ref
    jsr a2_mli_begin
    lda #HAL_STORAGE_PHASE_CLOSE
    sta hal_storage_diag_phase
    jsr a2i_close
    jsr a2_mli_end
    php
    lda #0
    sta a2_ss_open
    sta a2_ss_dir
    sta a2_ss_idx
    sta a2_ss_count
    sta a2_ss_eof
    plp
    bcc !ok+
    jsr a2_map_error
    lda #A2_SS_ERR_WRITE
    sta a2_ss_status                // post-close READST still reports the failure
    rts                             // carry set
!ok:
    clc
    rts

// ============================================================
// hal_storage_chkin / hal_storage_chkout — Select stream direction.
// Input: X = logical file number (advisory).
// Output: carry clear = stream open in the requested direction.
// ============================================================
hal_storage_chkin:
    lda a2_ss_open
    beq !bad+
    lda a2_ss_dir
    cmp #A2_SS_DIR_READ
    bne !bad+
    clc
    rts
!bad:
    sec
    rts

hal_storage_chkout:
    lda a2_ss_open
    beq !bad+
    lda a2_ss_dir
    cmp #A2_SS_DIR_WRITE
    bne !bad+
    clc
    rts
!bad:
    sec
    rts

// ============================================================
// hal_storage_clrchn — No channels to restore on ProDOS. No-op.
// ============================================================
hal_storage_clrchn:
    clc
    rts

// ============================================================
// hal_storage_chrin — Next buffered byte from the read stream.
// Output: A = byte (0 after EOF). Preserves X, Y, and zero page.
// ============================================================
hal_storage_chrin:
    stx a2_ss_tmp_x
    ldx a2_ss_idx
    cpx a2_ss_count
    bcc !have+
    jsr a2_ss_refill
    bcs !empty+
    ldx a2_ss_idx                   // refill resets the cursor to 0
!have:
    lda a2_ss_buf,x
    inc a2_ss_idx
    ldx a2_ss_tmp_x
    rts
!empty:
    lda #0
    ldx a2_ss_tmp_x
    rts

// a2_ss_refill — MLI READ the next 255 bytes into the stream buffer.
// 255 (not 256) so trans_count always fits one byte. A short transfer marks
// EOF: it only happens at end of file (TRM 4.5.3). Preserves Y.
// Output: carry clear = buffer holds a2_ss_count > 0 bytes; carry set = no
//         data (EOF or error, recorded in a2_ss_status).
a2_ss_refill:
    lda a2_ss_eof
    beq !go+
    sec
    rts
!go:
    tya
    pha
    lda a2_ss_ref
    sta a2_rw_ref
    lda #<a2_ss_buf
    sta a2_rw_buf
    lda #>a2_ss_buf
    sta a2_rw_buf + 1
    lda #255
    sta a2_rw_req
    lda #0
    sta a2_rw_req + 1
    jsr a2_mli_begin
    jsr a2i_read
    jsr a2_mli_end
    bcs !err+
    pla
    tay
    lda a2_rw_trans + 1
    bne !bad+                       // defensive: 255-byte request caps trans
    lda a2_rw_trans
    beq !bad+                       // defensive: clear carry implies data
    sta a2_ss_count
    lda #0
    sta a2_ss_idx
    lda a2_ss_count
    cmp #255
    bcs !full+
    lda #1
    sta a2_ss_eof                   // short read = EOF once the buffer drains
!full:
    clc
    rts
!bad:
    lda #HAL_STORAGE_PHASE_READ
    sta hal_storage_diag_phase
    lda #A2ERR_IO
    jsr a2_map_error
    lda #A2_SS_ERR_READ
    sta a2_ss_status
    lda #1
    sta a2_ss_eof
    sec
    rts
!err:
    pha
    lda #HAL_STORAGE_PHASE_READ
    sta hal_storage_diag_phase
    pla
    cmp #A2ERR_EOF
    beq !eof+
    jsr a2_map_error
    lda #A2_SS_ERR_READ
    sta a2_ss_status
!eof:
    lda #1
    sta a2_ss_eof
    pla
    tay
    sec
    rts

// ============================================================
// hal_storage_chrout — Buffer one byte for the write stream; flush at 256.
// Input: A = byte. Preserves A, X, Y, and zero page.
// Errors surface in a2_ss_status (observed via hal_storage_readst).
// ============================================================
hal_storage_chrout:
    stx a2_ss_tmp_x
    sty a2_ss_tmp_y
    ldx a2_ss_idx
    sta a2_ss_buf,x
    inx
    stx a2_ss_idx
    bne !done+
    pha
    jsr a2_ss_flush                 // full 256-byte block
    pla
!done:
    ldx a2_ss_tmp_x
    ldy a2_ss_tmp_y
    rts

// a2_ss_flush — MLI WRITE the pending buffer bytes (a2_ss_idx; 0 = 256).
// Preserves Y. On error: sticky a2_ss_status, diag bytes mapped, buffer
// dropped so the stream keeps accepting bytes (the failure is latched).
a2_ss_flush:
    tya
    pha
    lda a2_ss_ref
    sta a2_rw_ref
    lda #<a2_ss_buf
    sta a2_rw_buf
    lda #>a2_ss_buf
    sta a2_rw_buf + 1
    lda a2_ss_idx
    sta a2_rw_req
    lda #0
    sta a2_rw_req + 1
    ldx a2_ss_idx
    bne !len_ok+
    inc a2_rw_req + 1               // cursor wrapped: 256 bytes pending
!len_ok:
    jsr a2_mli_begin
    jsr a2i_write
    jsr a2_mli_end
    bcs !err+
    lda a2_rw_trans
    cmp a2_rw_req
    bne !short+
    lda a2_rw_trans + 1
    cmp a2_rw_req + 1
    bne !short+
    pla
    tay
    lda #0
    sta a2_ss_idx
    rts
!short:
    pla
    tay
    lda #A2ERR_IO
    jmp !map+
!err:
    tax
    pla
    tay
    txa
!map:
    pha
    lda #HAL_STORAGE_PHASE_WRITE
    sta hal_storage_diag_phase
    pla
    jsr a2_map_error
    lda #A2_SS_ERR_WRITE
    sta a2_ss_status
    lda #0
    sta a2_ss_idx
    rts

// ============================================================
// hal_storage_readst — Stream status byte (KERNAL READST shape).
// 0 = ok; $40 = EOF (buffer drained after a short MLI READ); $01 = write
// error; $02 = read error. save.s masks $03 on the byte paths and tests
// beq/$40 on the load framing paths. Also refreshed into the diagnostic
// byte for hal_storage_diag_readst.
// ============================================================
hal_storage_readst:
    lda a2_ss_status
    bne !done+                      // sticky error dominates
    lda a2_ss_dir
    cmp #A2_SS_DIR_READ
    bne !ok+
    lda a2_ss_idx
    cmp a2_ss_count
    bcc !ok+                        // buffered bytes remain
    lda a2_ss_eof
    beq !ok+
    lda #A2_SS_EOF
    jmp !done+
!ok:
    lda #0
!done:
    sta hal_storage_diag_readst
    rts

// ============================================================
// a2_save_block_mode — Set a2_save_aux_mode_flag when the current save/load
// block descriptor is aux-resident (store inventory, recall data). Called
// at the head of save_write_block / load_read_block (#if APPLE2 branch).
// Map blocks do not flow through here: they stream via save_write_map_c128
// and load_read_map_c128 below (HAL_STORAGE_MAP_BANKED).
// Clobbers: A
// ============================================================
a2_save_block_mode:
    lda #0
    sta a2_save_aux_mode_flag

    // All seven store arrays form one contiguous aux-only block.
    lda zp_ptr0_hi
    cmp #>si_item_id
    bcc !try_recall+
    bne !store_check_end+
    lda zp_ptr0
    cmp #<si_item_id
    bcc !try_recall+
!store_check_end:
    lda zp_ptr0_hi
    cmp #>store_inventory_data_end
    bcc !aux+
    bne !try_recall+
    lda zp_ptr0
    cmp #<store_inventory_data_end
    bcc !aux+
!try_recall:
    lda zp_ptr0_hi
    cmp #>recall_data_start
    bne !done+
    lda zp_ptr0
    cmp #<recall_data_start
    bne !done+
!aux:
    lda #$80
    sta a2_save_aux_mode_flag
!done:
    rts

// ============================================================
// Apple II map I/O helpers (HAL_STORAGE_MAP_BANKED). The map lives in aux
// at MAP_BASE; save streams it out through the p0 aux thunk, load streams
// it back through the p0 aux write wrapper. Mirrors the C128 contract from
// platforms/shared/save.s.
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
    ldy #0
!swm_loop:
    lda save_count_lo
    ora save_count_hi
    beq !swm_done+
    jsr mmu_safe_map_read_ptr0
    sta a2_zp_scratch
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !swm_no_carry+
    inc save_cksum_hi
!swm_no_carry:
    lda a2_zp_scratch
    jsr hal_storage_chrout
    jsr hal_storage_readst
    beq !swm_advance+
    sec
    rts
!swm_advance:
    inc zp_ptr0
    bne !swm_no_hi+
    inc zp_ptr0_hi
!swm_no_hi:
    lda save_count_lo
    sec
    sbc #1
    sta save_count_lo
    bcs !swm_loop-
    dec save_count_hi
    jmp !swm_loop-
!swm_done:
    clc
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
    ldy #0
!lrm_loop:
    lda save_io_error
    bne !lrm_done+
    lda save_count_lo
    ora save_count_hi
    beq !lrm_done+
    jsr load_read_byte
    jsr mmu_safe_map_write_ptr0
    inc zp_ptr0
    bne !lrm_no_hi+
    inc zp_ptr0_hi
!lrm_no_hi:
    lda save_count_lo
    sec
    sbc #1
    sta save_count_lo
    bcs !lrm_loop-
    dec save_count_hi
    jmp !lrm_loop-
!lrm_done:
    rts
