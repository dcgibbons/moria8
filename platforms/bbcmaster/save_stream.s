#importonce
// save_stream.s — BBC Master 128 Acorn DFS buffered byte-stream backend &
// storage HAL implementation (< $3000) for platforms/shared/save.s and core/6502/score_io.s.
//
// Authority: docs/BBCMASTER_MEMORY_CONTRACT.md.
// Linked below $3000 so all DFS file operations route through EnterMos / ExitMos
// while preserving caller A, X, Y, and core ZP ($02-$8F).

#import "memory.s"
#import "storage.s"
#import "hal/hal_contract.s"
#import "hal/storage_policy.s"
#import "../../core/6502/storage_status.s"

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
// Storage & Stream State (< $3000)
// ============================================================
.const STREAM_DIR_NONE  = 0
.const STREAM_DIR_READ  = 1
.const STREAM_DIR_WRITE = 2

disk_command_status: .byte 0
disk_status:         .byte 0
disk_error_phase:    .byte 0
disk_error_readst:   .byte 0
disk_error_device:   .byte 8
disk_error_dos0:     .byte $30
disk_error_dos1:     .byte $30

stream_lfn:          .byte 0
stream_dev:          .byte 8
stream_sa:           .byte 0
stream_handle:       .byte 0
stream_open:         .byte 0
stream_dir:          .byte 0
stream_buf_idx:      .byte 0
stream_buf_cnt:      .byte 0
stream_eof:          .byte 0
stream_err:          .byte 0
stream_last_status:  .byte HAL_STORAGE_STATUS_WRONG_MEDIA
stream_off0:         .byte 0
stream_off1:         .byte 0
stream_off2:         .byte 0
stream_tmp_a:        .byte 0

// ============================================================
// OS / Media / Marker Services
// ============================================================
disk_kernal_enter:
disk_kernal_exit:
disk_error_clear:
disk_error_set_phase:
    clc
    rts

disk_note_program_media_current:
    lda disk_setup_done
    cmp #2
    bne !dnpmc_done+
    lda #1
    sta disk_setup_done
!dnpmc_done:
    rts

// beeb_probe_drive_ready — Check if a readable DFS disk is mounted in device A (8..11)
// Output: Carry clear = drive ready, Carry set = empty / fault
beeb_probe_drive_ready:
    sta beeb_io_device
    lda #hal_storage_marker_read_name_len
    ldx #<hal_storage_marker_read_name
    ldy #>hal_storage_marker_read_name
    jsr beeb_set_pathname
    jmp beeb_mos_osfile_path_05

// disk_program_media_present — Check if Program Disk (TITLE) is in save_device
// Output: Carry clear = program disk present, Carry set = not program disk
disk_program_media_present:
    lda save_device
disk_program_media_present_on_device:
    sta beeb_io_device
    lda #hal_storage_program_probe_name_len
    ldx #<hal_storage_program_probe_name
    ldy #>hal_storage_program_probe_name
    jsr beeb_set_pathname
    jmp beeb_dfs_file_exists

// disk_require_program_media / hal_storage_probe_media — Verify Program Disk (TITLE)
// is in program_device.
// Output: Carry clear = program media present, Carry set = absent/wrong media
hal_storage_probe_media:
disk_require_program_media:
    lda program_device
    jmp disk_program_media_present_on_device

hal_storage_init_selected_drive:
    lda disk_prompt_device
    jmp beeb_probe_drive_ready

// Resident trampolines into StorageOverlay ($A800-$BFFF) preserving caller overlay.
disk_require_save_media:
    lda #<disk_require_save_media_ovl
    ldy #>disk_require_save_media_ovl
    bra !bsc_call+

disk_marker_init:
    lda #<disk_marker_init_ovl
    ldy #>disk_marker_init_ovl
    bra !bsc_call+

disk_marker_present:
    lda #<disk_marker_present_ovl
    ldy #>disk_marker_present_ovl
!bsc_call:
    jmp storage_swap_dispatch

disk_read_command_status:
    stz disk_command_status
    clc
    rts

disk_save_media_status:
    jsr disk_require_save_media
disk_setup_status:
    lda stream_last_status
    rts

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
    phx
    phy

    lda stream_open
    beq !not_already_open+
    jsr hal_storage_close
!not_already_open:
    .assert "stream_open..stream_off2 contiguous (10 B)", stream_off2 - stream_open, 9
    ldx #9
!clr_stream_state:
    stz stream_open,x
    dex
    bpl !clr_stream_state-
    stz disk_error_readst
    lda #HAL_STORAGE_STATUS_OK
    sta stream_last_status

    // Channel 15 command opens ("S0:..." scratch or "I0") succeed as no-ops so
    // pre-allocated HISCORE / SAVE0..3 slots remain intact in-place.
    lda stream_lfn
    cmp #hal_storage_cmd_channel
    bne !parse_name+
    clc
    jmp !open_ret+

!parse_name:
    lda stream_dev
    cmp #8
    bcs !dev_ok+
    lda save_device
!dev_ok:
    sta beeb_io_device
    lda stream_nam_len
    ldx stream_nam_lo
    ldy stream_nam_hi
    jsr beeb_set_pathname

    lda beeb_name_scratch
    beq !not_scratch+
    clc
    jmp !open_ret+

!not_scratch:
    lda beeb_name_write
    bne !open_write+
    lda stream_sa
    cmp #hal_storage_save_sec_write
    beq !open_write+

    // ---- READ MODE ----
    jsr EnterMos
    lda #$40                // OSFIND A=$40: Open for input
    jsr beeb_call_osfind
    jsr ExitMos
    bcs !open_not_found+
    cmp #$00
    beq !open_not_found+
    sta stream_handle
    lda #STREAM_DIR_READ
    sta stream_dir
    lda #1
    sta stream_open

    // Refill first buffer and check first byte for unwritten pre-allocated slot ($00)
    jsr beeb_stream_refill
    bcs !close_not_found+
    lda beeb_ss_buf
    beq !close_not_found+
    clc
    jmp !open_ret+

!close_not_found:
    jsr EnterMos
    ldy stream_handle
    jsr beeb_call_osfind_close
    jsr ExitMos
    stz stream_open
    stz stream_dir
!open_not_found:
    lda #HAL_STORAGE_STATUS_NOT_FOUND
    sta stream_last_status
    lda #$02
    sta stream_err
    lda #1
    sta stream_eof
    sec
    jmp !open_ret+

!open_write:
    // ---- WRITE MODE ----
    // Never allow opening a write stream on a disk containing TITLE (Program Disk)!
    lda beeb_io_device
    jsr disk_program_media_present_on_device
    bcc !open_write_wrong_media+
    // Re-populate BEEB_OS_PATH_BASE for the target write file
    lda stream_nam_len
    ldx stream_nam_lo
    ldy stream_nam_hi
    jsr beeb_set_pathname

    // Try opening existing file in-place via OSFIND A=$C0 first so overwriting
    // SAVE0..3 or HISCORE reuses its existing contiguous sectors without fragmenting DFS.
    jsr EnterMos
    lda #$c0
    jsr beeb_call_osfind
    bcs !open_write_err+
    cmp #$00
    bne !got_write_handle+

    // File does not exist yet: create and open it via OSFIND A=$80
    lda #$80
    jsr beeb_call_osfind
    bcs !open_write_err+
    cmp #$00
    beq !open_write_err+

!got_write_handle:
    sta stream_handle
    jsr ExitMos
    lda #STREAM_DIR_WRITE
    sta stream_dir
    stz stream_buf_idx
    lda #1
    sta stream_open
    clc
    jmp !open_ret+

!open_write_wrong_media:
    lda #HAL_STORAGE_STATUS_WRONG_MEDIA
    sta stream_last_status
    lda #3
    sta disk_status
    lda #$01
    sta stream_err
    sec
    jmp !open_ret+

!open_write_err:
    jsr ExitMos
    lda #HAL_STORAGE_STATUS_UNKNOWN
    sta stream_last_status
    lda #$01
    sta stream_err
    sec

!open_ret:
    ply
    plx
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
    phx
    phy
    lda stream_err
    bne !ret_zero+
    ldx stream_buf_idx
    cpx stream_buf_cnt
    bcc !have_byte+
    lda stream_eof
    bne !ret_zero+
    jsr beeb_stream_refill
    bcs !ret_zero+
    ldx #0
!have_byte:
    lda beeb_ss_buf,x
    inc stream_buf_idx
    ply
    plx
    clc
    rts
!ret_zero:
    lda #0
    ply
    plx
    rts

// beeb_stream_osgbpb — Execute OSGBPB at stream_off0..2 via beeb_ss_buf
// Input: A = OSGBPB op ($01 write, $03 read), X = byte count (1..128)
// Output: Carry clear = success (stream_off0..2 updated), Carry set = MOS error
beeb_stream_osgbpb:
    sta bso_op+1
    phx
    lda stream_handle
    jsr beeb_prep_ss_osgbpb
    pla
    sta BEEB_OS_CTRL_BASE + 5
    lda stream_off0
    sta BEEB_OS_CTRL_BASE + 9
    lda stream_off1
    sta BEEB_OS_CTRL_BASE + 10
    lda stream_off2
    sta BEEB_OS_CTRL_BASE + 11

    jsr EnterMos
bso_op:
    lda #$00
    jsr beeb_call_osgbpb
    jsr ExitMos
    bcs !bso_done+

    // Save updated file offset returned in BEEB_OS_CTRL_BASE + 9..11
    lda BEEB_OS_CTRL_BASE + 9
    sta stream_off0
    lda BEEB_OS_CTRL_BASE + 10
    sta stream_off1
    lda BEEB_OS_CTRL_BASE + 11
    sta stream_off2
    clc
!bso_done:
    rts

// beeb_stream_refill — Read up to 128 bytes (half-sector aligned) into beeb_ss_buf at stream_off0..2
beeb_stream_refill:
    lda #$03                // OSGBPB A=$03: Read bytes at specified offset
    ldx #128                // Request 128 bytes (never crosses a 256-byte sector boundary)
    jsr beeb_stream_osgbpb
    bcs !refill_err+

    // Transferred = 128 - residual (BEEB_OS_CTRL_BASE + 5)
    lda #128
    sec
    sbc BEEB_OS_CTRL_BASE + 5
    beq !at_eof+
    sta stream_buf_cnt
    stz stream_buf_idx
    lda BEEB_OS_CTRL_BASE + 5
    beq !refill_ok+
    lda #1
    sta stream_eof
!refill_ok:
    clc
    rts

!refill_err:
    lda #$02
    sta stream_err
    lda #HAL_STORAGE_STATUS_UNKNOWN
    sta stream_last_status
!at_eof:
    lda #1
    sta stream_eof
    sec
    rts

// ============================================================
// hal_storage_chrout — Buffer one byte for write stream (preserves A, X, Y, ZP)
// ============================================================
hal_storage_chrout:
    sta stream_tmp_a
    phx
    phy
    lda stream_err
    bne !done+

    ldx stream_buf_idx
    lda stream_tmp_a
    sta beeb_ss_buf,x
    inx
    stx stream_buf_idx
    cpx #128
    bcc !done+
    jsr beeb_stream_flush
!done:
    ply
    plx
    lda stream_tmp_a
    clc
    rts

// beeb_stream_flush — Write stream_buf_idx bytes (1..128) from beeb_ss_buf at stream_off0..2
beeb_stream_flush:
    ldx stream_buf_idx
    beq !flush_ok+
    lda #$01                // OSGBPB A=$01: Write bytes at specified offset
    jsr beeb_stream_osgbpb
    bcs !flush_err+
    lda BEEB_OS_CTRL_BASE + 5
    bne !flush_err+         // Residual != 0 -> short write

    stz stream_buf_idx
!flush_ok:
    clc
    rts

!flush_err:
    lda #$01
    sta stream_err
    lda #HAL_STORAGE_STATUS_UNKNOWN
    sta stream_last_status
    stz stream_buf_idx
    sec
    rts

// ============================================================
// hal_storage_close — Flush remaining bytes and close DFS file handle
// ============================================================
hal_storage_close:
    phx
    phy
    lda stream_open
    beq !closed_ok+
    lda stream_dir
    cmp #STREAM_DIR_WRITE
    bne !close_handle+
    lda stream_err
    bne !close_handle+
    jsr beeb_stream_flush

!close_handle:
    jsr EnterMos
    ldy stream_handle
    jsr beeb_call_osfind_close
    jsr ExitMos
    stz stream_open
    stz stream_dir
    lda stream_err
    beq !closed_ok+
    sec
    jmp !close_ret+
!closed_ok:
    clc
!close_ret:
    ply
    plx
    rts
