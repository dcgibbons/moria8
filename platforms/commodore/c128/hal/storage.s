#importonce
// C128 storage HAL adapter.
//
// Zero-byte aliases over the current C128 storage implementation. Raw
// KERNAL-style labels expect the caller to use hal_storage_enter_os/exit_os
// when ROM visibility is required, matching the current disk runtime pattern.

#import "storage_policy.s"
#import "storage_drive.s"
#import "storage_overlay_names.s"
#import "storage_tier_names.s"
#import "storage_title_name.s"

.label hal_storage_enter_os = disk_kernal_enter
.label hal_storage_exit_os = disk_kernal_exit
.label hal_storage_require_program_media = c128_require_program_media
.label hal_storage_require_save_media = disk_require_save_media
.label hal_storage_marker_present = disk_marker_present
.label hal_storage_marker_init = disk_marker_init
.label hal_storage_save_media_status = disk_save_media_status
.label hal_storage_setup_status = disk_setup_status
.label hal_storage_save_stream_status = save_stream_status
.label hal_storage_load_stream_status = load_stream_status
.label hal_storage_setnam = KERNAL_SETNAM
.label hal_storage_setlfs = KERNAL_SETLFS
.label hal_storage_open = KERNAL_OPEN
.label hal_storage_close = KERNAL_CLOSE
.label hal_storage_chkin = KERNAL_CHKIN
.label hal_storage_chkout = KERNAL_CHKOUT
.label hal_storage_chrin = KERNAL_CHRIN
.label hal_storage_chrout = KERNAL_CHROUT
.label hal_storage_clrchn = KERNAL_CLRCHN
.label hal_storage_readst = KERNAL_READST
.label hal_storage_load = KERNAL_LOAD
.label hal_storage_read_command_status = c128_storage_read_command_status
.label hal_storage_open_cmd_channel = c128_open_cmd_channel
.label hal_storage_read_open_cmd_status = c128_read_open_cmd_status
.label hal_storage_close_cmd_channel = c128_close_cmd_channel
.label hal_storage_status_lost = c128_status_lost
.label hal_storage_command_status = disk_command_status
.label hal_storage_diag_code = disk_status
.label hal_storage_diag_phase = disk_diag_phase
.label hal_storage_diag_readst = disk_diag_readst
.label hal_storage_diag_device = disk_diag_device
.label hal_storage_diag_dos0 = disk_diag_cmd_status0
.label hal_storage_diag_dos1 = disk_diag_cmd_status1
.label hal_storage_save_record = save_game
.label hal_storage_load_record = load_game

c128_open_cmd_channel:
    ldx save_device
c128_open_cmd_channel_x:
    txa
    pha
    // Start with no channel selected, as the Plus/4 reader must (after a write
    // the drive refused, its JiffyDOS KERNAL never completed the CHKIN).
    jsr KERNAL_CLRCHN
    lda #0
    tax
    tay
    jsr KERNAL_SETNAM
    pla
    tax
    lda #hal_storage_cmd_channel
    ldy #hal_storage_cmd_channel
    jsr KERNAL_SETLFS
    jmp KERNAL_OPEN

c128_clear_cmd_status_diag:
    lda #$ff
    sta disk_diag_cmd_status0
    sta disk_diag_cmd_status1
    lda #0
    sta disk_diag_readst        // this read's, not the last one's
    sta c128_status_lost
    rts

// Keep c128_storage_read_command_status immediately above c128_read_open_cmd_status
// so playtest/moria_playtest/disk.py's [reader, +0x100) READST span includes it.
c128_storage_read_command_status:
    ldx save_device
c128_storage_read_command_status_x:
    jsr c128_clear_cmd_status_diag
    jsr c128_open_cmd_channel_x
    bcs !cs_open_fail+
    jsr c128_read_open_cmd_status_cleared
    jmp c128_close_cmd_channel
!cs_open_fail:
    rts

c128_read_open_cmd_status:
    jsr c128_clear_cmd_status_diag
c128_read_open_cmd_status_cleared:
    ldx #hal_storage_cmd_channel
    jsr KERNAL_CHKIN
    bcs !cs_done+
    jsr KERNAL_READST
    bne !cs_done+
    jsr KERNAL_CHRIN
    sta disk_diag_cmd_status0
    jsr KERNAL_READST
    sta disk_diag_readst
    bne !cs_check_lost+
    jsr KERNAL_CHRIN
    sta disk_diag_cmd_status1
    jsr KERNAL_READST
    sta disk_diag_readst
    and #$02
    beq !cs_done+
    lda #$ff
    sta disk_diag_cmd_status1
    inc c128_status_lost
!cs_check_lost:
    // A read that timed out (ST bit 1) before any digit came lost its byte
    // on the bus: c128_status_lost says so, for a caller that can ask again
    // with a fresh OPEN (reading this channel again goes on mid-message).
    lda c128_status_lost
    bne !cs_done+
    lda disk_diag_readst
    and #$02                    // read timeout
    beq !cs_done+
    lda disk_diag_cmd_status0
    eor #$30
    cmp #10                     // a digit: the drive answered
    bcc !cs_done+
    inc c128_status_lost
!cs_done:
    jmp KERNAL_CLRCHN

c128_close_cmd_channel:
    jsr KERNAL_CLRCHN
    lda #hal_storage_cmd_channel
    jmp KERNAL_CLOSE

c128_status_lost: .byte 0       // nonzero: the last status read lost its byte

// Platform-owned save-disk marker filenames and marker bytes. PETSCII bytes
// for KERNAL SETNAM / sequential marker contents.
hal_storage_init_command:
    .byte $49, $30                              // "I0"

hal_storage_marker_magic:
    .byte $4d, $38, $53, $41, $56, $45          // "M8SAVE"
.label hal_storage_marker_magic_len = * - hal_storage_marker_magic

hal_storage_marker_read_name:
    .byte $30, $3a                              // "0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44 // "MORIA8.ID"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_marker_read_name_len = * - hal_storage_marker_read_name

hal_storage_marker_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44 // "MORIA8.ID"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_marker_write_name_len = * - hal_storage_marker_write_name

hal_storage_marker_scratch_name:
    .byte $53, $30, $3a                         // "S0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44 // "MORIA8.ID"
.label hal_storage_marker_scratch_name_len = * - hal_storage_marker_scratch_name

// Platform-owned save-record filenames. PETSCII bytes for KERNAL SETNAM.
hal_storage_save_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $54, $48, $45, $2e, $47, $41, $4d, $45 // "THE.GAME"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_save_write_name_len = * - hal_storage_save_write_name
    .byte $57                                   // spare suffix byte for "THE.GAME2"
.label hal_storage_save_probe_name = hal_storage_save_write_name + 1
.label hal_storage_save_probe_name_len = hal_storage_save_write_name_len - 1

hal_storage_save_read_name:
    .byte $30, $3a                              // "0:"
    .byte $54, $48, $45, $2e, $47, $41, $4d, $45 // "THE.GAME"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_save_read_name_len = * - hal_storage_save_read_name
    .byte $52                                   // spare suffix byte for "THE.GAME2"

// Platform-owned high-score filenames. PETSCII bytes for KERNAL SETNAM.
hal_storage_score_read_name:
    .byte $30, $3a                              // "0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45 // "HALL.OF.FAME"
    .byte $2c, $53, $2c, $52                    // ",S,R"
.label hal_storage_score_read_name_len = * - hal_storage_score_read_name

hal_storage_score_write_name:
    .byte $40, $30, $3a                         // "@0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45 // "HALL.OF.FAME"
    .byte $2c, $53, $2c, $57                    // ",S,W"
.label hal_storage_score_write_name_len = * - hal_storage_score_write_name

hal_storage_score_scratch_name:
    .byte $53, $30, $3a                         // "S0:"
    .byte $48, $41, $4c, $4c, $2e, $4f, $46, $2e, $46, $41, $4d, $45 // "HALL.OF.FAME"
.label hal_storage_score_scratch_name_len = * - hal_storage_score_scratch_name
