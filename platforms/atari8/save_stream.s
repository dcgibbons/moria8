#importonce
// save_stream.s — Atari 8-bit buffered DOS 2.5 sector stream & storage HAL
// implementation for platforms/shared/save.s and core/score_io.s.
//
// Linked below $4000 so all sector reads/writes route directly through
// EnterSio / ExitSio while preserving caller A, X, Y, and core ZP ($02-$8F).

#import "memory.s"
#import "storage.s"
#import "hal/hal_contract.s"
#import "hal/storage_policy.s"
#import "../../core/storage_status.s"

// ============================================================
// HAL Storage Symbol Exports
// ============================================================
.label hal_storage_enter_os              = disk_kernal_enter
.label hal_storage_exit_os               = disk_kernal_exit
.label hal_storage_require_program_media = disk_require_program_media
.label hal_storage_require_save_media    = disk_require_save_media
.label hal_storage_marker_present        = disk_marker_present
.label hal_storage_marker_init           = disk_marker_init
.label hal_storage_save_media_status     = disk_save_media_status
.label hal_storage_setup_status          = disk_setup_status
.label hal_storage_save_stream_status    = save_stream_status
.label hal_storage_load_stream_status    = load_stream_status
.label hal_storage_load                  = hal_asset_load_prg_header
.label hal_storage_read_command_status   = disk_read_command_status
.label hal_storage_command_status        = disk_command_status
.label hal_storage_diag_code             = disk_status
.label hal_storage_diag_phase            = disk_error_phase
.label hal_storage_diag_readst           = disk_error_readst
.label hal_storage_diag_device           = disk_error_device
.label hal_storage_diag_dos0             = disk_error_dos0
.label hal_storage_diag_dos1             = disk_error_dos1
.label hal_storage_save_record           = save_game
.label hal_storage_load_record           = load_game

// ============================================================
// Storage & Stream State
// ============================================================
.const STREAM_DIR_NONE  = 0
.const STREAM_DIR_READ  = 1
.const STREAM_DIR_WRITE = 2

program_device:      .byte 8
save_device:         .byte 9
disk_prompt_device:  .byte 8
disk_mode:           .byte 2
disk_setup_done:     .byte 0

disk_command_status: .byte 0
disk_status:         .byte 0
disk_error_phase:    .byte 0
disk_error_readst:   .byte 0
disk_error_device:   .byte 8
disk_error_dos0:     .byte 0
disk_error_dos1:     .byte 0

stream_nam_len:      .byte 0
stream_nam_lo:       .byte 0
stream_nam_hi:       .byte 0
stream_lfn:          .byte 0
stream_dev:          .byte 8
stream_sa:           .byte 0
stream_open:         .byte 0
stream_dir:          .byte 0
stream_buf_idx:      .byte 0
stream_buf_cnt:      .byte 0
stream_eof:          .byte 0
stream_err:          .byte 0
stream_last_status:  .byte HAL_STORAGE_STATUS_OK
stream_cur_sec_lo:   .byte 0
stream_cur_sec_hi:   .byte 0
stream_next_sec_lo:  .byte 0
stream_next_sec_hi:  .byte 0
stream_rem_sec_lo:   .byte 0
stream_rem_sec_hi:   .byte 0
stream_file_idx:     .byte 0
stream_tmp_a:        .byte 0
stream_tmp_x:        .byte 0
stream_tmp_y:        .byte 0

// ============================================================
// OS / Media / Marker Services
// ============================================================
disk_kernal_enter:
disk_kernal_exit:
disk_error_clear:
disk_error_set_phase:
    rts

disk_note_program_media_current:
    lda disk_setup_done
    cmp #2
    bne !dnpmc_done+
    lda #1
    sta disk_setup_done
!dnpmc_done:
    rts

// disk_program_media_present — Check if Program Disk (TITLE.DAT) is in save_device
// Output: Carry clear = program disk present, Carry set = not program disk
disk_program_media_present:
    lda save_device
disk_program_media_present_on_device:
    sta atari_io_device
    tax
    jsr hal_storage_probe_media
    bcs !not_prog+
    ldx #10
!cp_t:
    lda fn_83_title,x
    sta atari_fn_83,x
    dex
    bpl !cp_t-
    jmp atari_find_dir_entry
!not_prog:
    sec
    rts

// disk_require_program_media — Verify Program Disk (TITLE.DAT) is in program_device
// Output: Carry clear = program media present, Carry set = absent/wrong media
disk_require_program_media:
    lda program_device
    jmp disk_program_media_present_on_device

disk_require_save_media:
    lda disk_setup_done
    bne !drsm_chk+
    sec
    rts
!drsm_chk:
    jsr disk_program_media_present
    bcs !not_prog_disk+
    lda #HAL_STORAGE_STATUS_WRONG_MEDIA
    sta stream_last_status
    lda #3
    sta disk_status
    sec
    rts
!not_prog_disk:
    jsr disk_marker_present
    bcs !missing_marker+
    lda #HAL_STORAGE_STATUS_OK
    sta stream_last_status
    lda #0
    sta disk_status
    clc
    rts
!missing_marker:
    lda #HAL_STORAGE_STATUS_WRONG_MEDIA
    sta stream_last_status
    lda #2
    sta disk_status
    sec
    rts

// hal_storage_probe_media — Issue SIO Status ('S') command to device X (8..11)
// Output: Carry clear = drive present, Carry set = absent
hal_storage_probe_media:
    stx atari_io_device
    lda #'S'
    sta DCB_DCOMND
    lda #$40
    sta DCB_DSTATS
    lda #<sio_sector_buf
    sta DCB_DBUFLO
    lda #>sio_sector_buf
    sta DCB_DBUFHI
    lda #4
    sta DCB_DBYTLO
    lda #0
    sta DCB_DBYTHI
    sta DCB_DAUX1
    sta DCB_DAUX2
    jsr EnterSio
    jmp ExitSio

hal_storage_init_selected_drive:
    ldx disk_prompt_device
    jmp hal_storage_probe_media

// atari_write_sio_sector — Write 128-byte sio_sector_buf to sector X (lo) / Y (hi)
// on atari_io_device. Must reside < $4000.
// Output: Carry clear = success, Carry set = error
atari_write_sio_sector:
    stx DCB_DAUX1
    sty DCB_DAUX2
    lda #'P'
    sta DCB_DCOMND
    lda #$80
    sta DCB_DSTATS
    lda #<sio_sector_buf
    sta DCB_DBUFLO
    lda #>sio_sector_buf
    sta DCB_DBUFHI
    lda #128
    sta DCB_DBYTLO
    lda #0
    sta DCB_DBYTHI
    jsr EnterSio
    jmp ExitSio

// disk_marker_present — Verify MORIA8.ID exists and has "M8SAVE" on save_device
// Output: Carry clear = valid marker found, Carry set = invalid/missing
disk_marker_present:
    lda #hal_storage_marker_read_name_len
    ldx #<hal_storage_marker_read_name
    ldy #>hal_storage_marker_read_name
    jsr hal_storage_setnam
    lda #hal_storage_marker_file_num
    ldx save_device
    ldy #hal_storage_marker_sec_read
    jsr hal_storage_setlfs
    jsr hal_storage_open
    bcs !absent+
    ldx #0
!chk_magic:
    jsr hal_storage_chrin
    cmp hal_storage_marker_magic,x
    bne !bad_magic+
    inx
    cpx #hal_storage_marker_magic_len
    bcc !chk_magic-
    lda #hal_storage_marker_file_num
    jsr hal_storage_close
    clc
    rts
!bad_magic:
    lda #hal_storage_marker_file_num
    jsr hal_storage_close
!absent:
    sec
    rts

disk_read_command_status:
    lda #0
    sta disk_command_status
    clc
    rts

disk_save_media_status:
disk_setup_status:
    lda stream_last_status
    rts

// ============================================================
// Canonical 11-Byte DOS 2.5 8+3 Filenames for Mutable/Probe Files
// ============================================================
fn_83_title:
    .byte 'T','I','T','L','E',' ',' ',' ','D','A','T'
fn_83_marker:
    .byte 'M','O','R','I','A','8',' ',' ','I','D',' '
fn_83_hiscore:
    .byte 'H','I','S','C','O','R','E',' ','D','A','T'
fn_83_save:
    .byte 'S','A','V','E','0',' ',' ',' ','S','A','V'

// ============================================================
// KERNAL-Shaped Stream API (SETNAM, SETLFS, OPEN, CLOSE, CHRIN, CHROUT, READST)
// ============================================================

hal_storage_setnam:
    sta stream_nam_len
    stx stream_nam_lo
    sty stream_nam_hi
    rts

hal_storage_setlfs:
    sta stream_lfn
    stx stream_dev
    stx disk_error_device
    sty stream_sa
    rts

hal_storage_open:
    stx stream_tmp_x
    sty stream_tmp_y

    lda #0
    sta stream_open
    sta stream_dir
    sta stream_buf_idx
    sta stream_buf_cnt
    sta stream_eof
    sta stream_err
    sta disk_error_readst
    lda #HAL_STORAGE_STATUS_OK
    sta stream_last_status

    // Channel 15 command opens ("S0:..." scratch or "I0") succeed as no-ops so
    // pre-allocated HISCORE.DAT / SAVE0..3.SAV slots remain intact.
    lda stream_lfn
    cmp #hal_storage_cmd_channel
    bne !parse_name+
    clc
    jmp !open_ret+

!parse_name:
    lda stream_nam_lo
    sta atari_io_src
    lda stream_nam_hi
    sta atari_io_src_hi

    ldy #0
    lda (atari_io_src),y
    cmp #'S'
    bne !not_scratch+
    iny
    lda (atari_io_src),y
    cmp #'0'
    bne !not_scratch_y0+
    iny
    lda (atari_io_src),y
    cmp #':'
    bne !not_scratch_y0+
    clc
    jmp !open_ret+
!not_scratch_y0:
    ldy #0
!not_scratch:
    // Detect write mode from leading '@' or trailing 'W' or stream_sa == 1
    lda #STREAM_DIR_READ
    sta stream_dir
    lda stream_sa
    cmp #hal_storage_save_sec_write
    bne !chk_at+
    lda #STREAM_DIR_WRITE
    sta stream_dir
!chk_at:
    lda (atari_io_src),y
    cmp #'@'
    bne !chk_prefix+
    lda #STREAM_DIR_WRITE
    sta stream_dir
    iny
!chk_prefix:
    // Skip optional "0:" prefix
    lda (atari_io_src),y
    cmp #'0'
    bne !check_trailing_w+
    iny
    lda (atari_io_src),y
    cmp #':'
    bne !rewind_one+
    iny
    jmp !check_trailing_w+
!rewind_one:
    dey

!check_trailing_w:
    sty atari_io_cnt        // Save start offset of base filename
    ldy stream_nam_len
    beq !map_filename+
    dey
    lda (atari_io_src),y
    cmp #'W'
    bne !map_filename+
    lda #STREAM_DIR_WRITE
    sta stream_dir

!map_filename:
    ldy atari_io_cnt
    lda (atari_io_src),y
    cmp #'M'
    bne !chk_hall+
    ldx #10
!cp_m:
    lda fn_83_marker,x
    sta atari_fn_83,x
    dex
    bpl !cp_m-
    jmp !lookup_dir+

!chk_hall:
    cmp #'H'
    bne !chk_save+
    ldx #10
!cp_h:
    lda fn_83_hiscore,x
    sta atari_fn_83,x
    dex
    bpl !cp_h-
    jmp !lookup_dir+

!chk_save:
    ldx #10
!cp_s:
    lda fn_83_save,x
    sta atari_fn_83,x
    dex
    bpl !cp_s-
    // Check character immediately after "THE.GAME" (offset + 8) for '2'..'4'
    tya
    clc
    adc #8
    tay
    cpy stream_nam_len
    bcs !lookup_dir+
    lda (atari_io_src),y
    cmp #'2'
    bcc !lookup_dir+
    cmp #'5'
    bcs !lookup_dir+
    sec
    sbc #1                  // '2' -> '1', '3' -> '2', '4' -> '3'
    sta atari_fn_83 + 4

!lookup_dir:
    lda stream_dev
    cmp #8
    bcs !dev_ok+
    lda save_device
!dev_ok:
    sta atari_io_device
    jsr atari_find_dir_entry
    bcc !dir_found+
    lda #HAL_STORAGE_STATUS_NOT_FOUND
    sta stream_last_status
    lda #$02
    sta stream_err
    lda #1
    sta stream_eof
    sec
    jmp !open_ret+

!dir_found:
    lda atari_io_sec_lo
    sta stream_cur_sec_lo
    lda atari_io_sec_hi
    sta stream_cur_sec_hi
    lda atari_dir_count_lo
    sta stream_rem_sec_lo
    lda atari_dir_count_hi
    sta stream_rem_sec_hi
    lda atari_file_idx
    sta stream_file_idx

    lda stream_dir
    cmp #STREAM_DIR_WRITE
    beq !open_write+

    // READ mode: read first sector and check $7D byte count for empty slot (0)
    jsr stream_read_cur_sector
    bcs !open_io_err+
    lda sio_sector_buf + DOS25_LINK_BYTES
    bne !read_non_empty+
    // Pre-allocated slot has 0 bytes -> report NOT_FOUND
    lda #HAL_STORAGE_STATUS_NOT_FOUND
    sta stream_last_status
    lda #$02
    sta stream_err
    lda #1
    sta stream_eof
    sec
    jmp !open_ret+

!read_non_empty:
    sta stream_buf_cnt
    lda #0
    sta stream_buf_idx
    lda #1
    sta stream_open
    clc
    jmp !open_ret+

!open_io_err:
    lda #HAL_STORAGE_STATUS_UNKNOWN
    sta stream_last_status
    lda #$02
    sta stream_err
    lda #1
    sta stream_eof
    sec
    jmp !open_ret+

!open_write:
    lda #0
    sta stream_buf_idx
    lda #1
    sta stream_open
    clc

!open_ret:
    ldx stream_tmp_x
    ldy stream_tmp_y
    rts

// ============================================================
// hal_storage_chkin / chkout / clrchn / readst
// ============================================================
hal_storage_chkin:
    lda stream_open
    beq !bad+
    lda stream_dir
    cmp #STREAM_DIR_READ
    bne !bad+
    clc
    rts
!bad:
    sec
    rts

hal_storage_chkout:
    lda stream_open
    beq !bad+
    lda stream_dir
    cmp #STREAM_DIR_WRITE
    bne !bad+
    clc
    rts
!bad:
    sec
    rts

hal_storage_clrchn:
    clc
    rts

hal_storage_readst:
    lda stream_err
    bne !done+
    lda stream_dir
    cmp #STREAM_DIR_READ
    bne !ok+
    lda stream_buf_idx
    cmp stream_buf_cnt
    bcc !ok+
    lda stream_eof
    beq !ok+
    lda #$40                // EOF
    jmp !done+
!ok:
    lda #0
!done:
    sta disk_error_readst
    rts

// ============================================================
// hal_storage_chrin — Read next byte from open stream (preserves X, Y, ZP)
// ============================================================
hal_storage_chrin:
    stx stream_tmp_x
    sty stream_tmp_y
    lda stream_err
    bne !ret_zero+
    ldx stream_buf_idx
    cpx stream_buf_cnt
    bcc !have_byte+
    lda stream_eof
    bne !ret_zero+

    // Advance to next sector in chain
    lda stream_next_sec_lo
    sta stream_cur_sec_lo
    lda stream_next_sec_hi
    sta stream_cur_sec_hi
    jsr stream_read_cur_sector
    bcs !read_err+
    lda sio_sector_buf + DOS25_LINK_BYTES
    beq !at_eof+
    sta stream_buf_cnt
    ldx #0
    stx stream_buf_idx
!have_byte:
    lda sio_sector_buf,x
    inc stream_buf_idx
    ldx stream_tmp_x
    ldy stream_tmp_y
    clc
    rts

!read_err:
    lda #$02
    sta stream_err
    lda #HAL_STORAGE_STATUS_UNKNOWN
    sta stream_last_status
!at_eof:
    lda #1
    sta stream_eof
!ret_zero:
    lda #0
    ldx stream_tmp_x
    ldy stream_tmp_y
    rts

// stream_read_cur_sector — Read stream_cur_sec_lo/hi into sio_sector_buf
// and unpack 10-bit next link into stream_next_sec_lo/hi.
stream_read_cur_sector:
    lda #'R'
    sta DCB_DCOMND
    lda #$40
    sta DCB_DSTATS
    lda #<sio_sector_buf
    sta DCB_DBUFLO
    lda #>sio_sector_buf
    sta DCB_DBUFHI
    lda #128
    sta DCB_DBYTLO
    lda #0
    sta DCB_DBYTHI
    lda stream_cur_sec_lo
    sta DCB_DAUX1
    lda stream_cur_sec_hi
    sta DCB_DAUX2
    jsr EnterSio
    jsr ExitSio
    bcs !fail+
    lda sio_sector_buf + DOS25_LINK_HI
    and #$03
    sta stream_next_sec_hi
    lda sio_sector_buf + DOS25_LINK_LO
    sta stream_next_sec_lo
    ora stream_next_sec_hi
    bne !more+
    lda #1
    sta stream_eof
!more:
    clc
!fail:
    rts

// ============================================================
// hal_storage_chrout — Buffer one byte for write stream (preserves A, X, Y, ZP)
// ============================================================
// Flushes full 125-byte sectors lazily when byte #126 arrives so the final
// sector of any file (even exact multiples of 125 B) is flushed on close with
// a 0 next-sector link.
hal_storage_chrout:
    sta stream_tmp_a
    stx stream_tmp_x
    sty stream_tmp_y
    lda stream_err
    bne !done+

    ldx stream_buf_idx
    cpx #ATARI_SAVE_SECTOR_DATA_BYTES
    bcc !store_byte+

    // Buffer holds 125 bytes and a 126th byte is arriving: flush current sector
    // linked to stream_cur_sec + 1.
    lda stream_cur_sec_lo
    clc
    adc #1
    sta stream_next_sec_lo
    lda stream_cur_sec_hi
    adc #0
    sta stream_next_sec_hi
    jsr stream_write_cur_sector
    bcs !done+

    // Advance stream_cur_sec to stream_next_sec
    lda stream_next_sec_lo
    sta stream_cur_sec_lo
    lda stream_next_sec_hi
    sta stream_cur_sec_hi
    ldx #0
    stx stream_buf_idx

!store_byte:
    lda stream_tmp_a
    sta sio_sector_buf,x
    inc stream_buf_idx

!done:
    lda stream_tmp_a
    ldx stream_tmp_x
    ldy stream_tmp_y
    clc
    rts

// ============================================================
// hal_storage_close — Flush final sector (with 0 link) and close stream
// ============================================================
hal_storage_close:
    stx stream_tmp_x
    sty stream_tmp_y
    lda stream_open
    beq !closed_ok+
    lda stream_dir
    cmp #STREAM_DIR_WRITE
    bne !close_cleanup+
    lda stream_err
    bne !close_cleanup+

    // Flush final sector with next_sector = 0
    lda #0
    sta stream_next_sec_lo
    sta stream_next_sec_hi
    jsr stream_write_cur_sector

!close_cleanup:
    lda #0
    sta stream_open
    sta stream_dir
    lda stream_err
    beq !closed_ok+
    sec
    jmp !close_ret+
!closed_ok:
    clc
!close_ret:
    ldx stream_tmp_x
    ldy stream_tmp_y
    rts

// stream_write_cur_sector — Stamp 3-byte DOS 2.5 trailer and write sio_sector_buf
stream_write_cur_sector:
    // Check remaining pre-allocated sector budget
    lda stream_rem_sec_lo
    ora stream_rem_sec_hi
    bne !have_budget+
    lda #$01
    sta stream_err
    lda #HAL_STORAGE_STATUS_DISK_FULL
    sta stream_last_status
    sec
    rts

!have_budget:
    // Decrement remaining sector budget
    lda stream_rem_sec_lo
    sec
    sbc #1
    sta stream_rem_sec_lo
    bcs !no_borrow+
    dec stream_rem_sec_hi
!no_borrow:
    // Zero-pad any unused bytes in sio_sector_buf[stream_buf_idx..124]
    ldx stream_buf_idx
    lda #0
!pad_loop:
    cpx #ATARI_SAVE_SECTOR_DATA_BYTES
    bcs !pad_done+
    sta sio_sector_buf,x
    inx
    jmp !pad_loop-
!pad_done:
    // Stamp canonical DOS 2.5 3-byte trailer ($7D..$7F)
    lda stream_buf_idx
    sta sio_sector_buf + DOS25_LINK_BYTES
    lda stream_file_idx
    asl
    asl
    ora stream_next_sec_hi
    sta sio_sector_buf + DOS25_LINK_HI
    lda stream_next_sec_lo
    sta sio_sector_buf + DOS25_LINK_LO

    lda #'P'                // Put sector
    sta DCB_DCOMND
    lda #$80
    sta DCB_DSTATS
    lda #<sio_sector_buf
    sta DCB_DBUFLO
    lda #>sio_sector_buf
    sta DCB_DBUFHI
    lda #128
    sta DCB_DBYTLO
    lda #0
    sta DCB_DBYTHI
    lda stream_cur_sec_lo
    sta DCB_DAUX1
    lda stream_cur_sec_hi
    sta DCB_DAUX2
    jsr EnterSio
    jsr ExitSio
    bcc !write_ok+
    lda #$01
    sta stream_err
    lda #HAL_STORAGE_STATUS_UNKNOWN
    sta stream_last_status
    sec
    rts
!write_ok:
    clc
    rts
