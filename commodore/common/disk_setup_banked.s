#importonce
// disk_setup_banked.s — Non-overlay FEAT-DISK coordinator
//
// C64 hosts this in the banked payload. C128 imports the same coordinator into
// resident code. In both cases the overlay remains display/input only and
// all disk transactions stay outside the live overlay frame.

.const FEAT_SETNAM = hal_storage_setnam
.const FEAT_SETLFS = hal_storage_setlfs
.const FEAT_OPEN   = hal_storage_open
.const FEAT_CLOSE  = hal_storage_close
.const FEAT_CLRCHN = hal_storage_clrchn
.const FEAT_READST = hal_storage_readst
.const FEAT_CHKOUT = hal_storage_chkout
.const FEAT_CHROUT = hal_storage_chrout

#if HAL_STORAGE_COMMAND_STATUS_FROM_DISK_DIAG
disk_diag_phase:       .byte 0
disk_diag_carry:       .byte 0
disk_diag_readst:      .byte 0
disk_diag_device:      .byte 0
disk_diag_lfn:         .byte 0
disk_diag_sec:         .byte 0
disk_diag_byte:        .byte 0
disk_diag_index:       .byte 0
disk_diag_cmd_status0: .byte 0
disk_diag_cmd_status1: .byte 0
disk_diag_init_status0:.byte 0
disk_diag_init_status1:.byte 0
disk_diag_scratch_status0:.byte 0
disk_diag_scratch_status1:.byte 0
disk_diag_write_status0:.byte 0
disk_diag_write_status1:.byte 0
#endif

disk_marker_init:
#if HAL_STORAGE_COMMAND_STATUS_FROM_DISK_DIAG
    lda #$90
    sta disk_diag_phase
    lda save_device
    sta disk_diag_device
    lda #hal_storage_marker_file_num
    sta disk_diag_lfn
    lda #hal_storage_marker_sec_write
    sta disk_diag_sec
    lda #$ff
    sta disk_diag_readst
    sta disk_diag_cmd_status0
    sta disk_diag_cmd_status1
    sta disk_diag_scratch_status0
    sta disk_diag_scratch_status1
    sta disk_diag_write_status0
    sta disk_diag_write_status1

    jsr disk_kernal_enter
    lda #hal_storage_marker_scratch_name_len
    ldx #<hal_storage_marker_scratch_name
    ldy #>hal_storage_marker_scratch_name
    jsr FEAT_SETNAM
    lda #hal_storage_cmd_channel
    ldx save_device
    ldy #hal_storage_cmd_channel
    jsr FEAT_SETLFS
    jsr FEAT_OPEN
    bcc !dmi_scratch_open_ok+
    lda #1
    sta disk_diag_carry
    lda #$97
    sta disk_diag_phase
    sta disk_status
    jmp !dmi_done+
!dmi_scratch_open_ok:
    lda #hal_storage_cmd_channel
    jsr FEAT_CLOSE
    jsr FEAT_CLRCHN
    jsr hal_storage_read_command_status
    lda disk_diag_cmd_status0
    sta disk_diag_scratch_status0
    lda disk_diag_cmd_status1
    sta disk_diag_scratch_status1
    lda disk_diag_scratch_status0
    cmp #$30
    beq !dmi_scratch_check_00_01+
    cmp #$36
    bne !dmi_scratch_fail+
    lda disk_diag_scratch_status1
    cmp #$32
    beq !dmi_create+
    jmp !dmi_scratch_fail+
!dmi_scratch_check_00_01:
    lda disk_diag_scratch_status1
    cmp #$30
    beq !dmi_create+
    cmp #$31
    beq !dmi_create+
!dmi_scratch_fail:
    lda #$97
    sta disk_diag_phase
    sta disk_status
    jmp !dmi_done+
!dmi_create:
    lda #$91
    sta disk_diag_phase
    lda #$91
    sta disk_status

    lda #hal_storage_marker_write_name_len - 1
    ldx #<(hal_storage_marker_write_name + 1)
    ldy #>(hal_storage_marker_write_name + 1)
    jsr FEAT_SETNAM
    lda #hal_storage_marker_file_num
    ldx save_device
    ldy #hal_storage_marker_sec_write
    jsr FEAT_SETLFS
    jsr FEAT_OPEN
    bcc !dmi_open_ok+
    lda #1
    sta disk_diag_carry
    lda #$92
    sta disk_diag_phase
    sta disk_status
    jmp !dmi_done+
!dmi_open_ok:
    lda #0
    sta disk_diag_carry
    jsr FEAT_READST
    sta disk_diag_readst
    beq !dmi_chkout+
    lda #$92
    sta disk_diag_phase
    sta disk_status
    jmp !dmi_close+

!dmi_chkout:
    lda #$93
    sta disk_diag_phase
    ldx #hal_storage_marker_file_num
    jsr FEAT_CHKOUT
    bcc !dmi_write_start+
    lda #1
    sta disk_diag_carry
    lda #$93
    sta disk_status
    jmp !dmi_close+

!dmi_write_start:
    lda #0
    sta disk_diag_carry
    lda #0
    sta disk_temp
!dmi_write:
    lda #$94
    sta disk_diag_phase
    ldx disk_temp
    stx disk_diag_index
    lda hal_storage_marker_magic,x
    jsr FEAT_CHROUT
    jsr FEAT_READST
    sta disk_diag_readst
    beq !dmi_write_ok+
    lda #$94
    sta disk_status
    jmp !dmi_close+
!dmi_write_ok:
    inc disk_temp
    lda disk_temp
    cmp #hal_storage_marker_magic_len
    bcc !dmi_write-
    lda #0
    sta disk_status
!dmi_close:
    lda #$95
    sta disk_diag_phase
    jsr FEAT_CLRCHN
    lda #hal_storage_marker_file_num
    jsr FEAT_CLOSE
    jsr FEAT_READST
    sta disk_diag_readst
    jsr hal_storage_read_command_status
    lda disk_diag_cmd_status0
    sta disk_diag_write_status0
    lda disk_diag_cmd_status1
    sta disk_diag_write_status1
    lda disk_diag_write_status0
    cmp #$30
    bne !dmi_cmd_fail+
    lda disk_diag_write_status1
    cmp #$30
    beq !dmi_done+
!dmi_cmd_fail:
    lda #$96
    sta disk_diag_phase
    sta disk_status
!dmi_done:
    jsr disk_kernal_exit
    lda disk_status
    bne !dmi_fail+
    jsr disk_marker_present
    bcc !dmi_ok+
!dmi_fail:
    jsr disk_error_capture_c128
    sec
    rts
!dmi_ok:
    clc
    rts

disk_error_capture_c128:
    jsr hal_storage_command_status
    cmp #HAL_STORAGE_STATUS_WRITE_PROTECTED
    bne !check_72+
    lda #26
    sta disk_status
    rts
!check_72:
    cmp #HAL_STORAGE_STATUS_DISK_FULL
    bne !check_74+
    lda #72
    sta disk_status
    rts
!check_74:
    cmp #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    bne !done+
    lda #74
    sta disk_status
!done:
    rts

disk_setup_capture_init_status:
    lda #$ff
    sta disk_diag_init_status0
    sta disk_diag_init_status1
    jsr disk_kernal_enter
    jsr hal_storage_read_command_status
    lda disk_diag_cmd_status0
    sta disk_diag_init_status0
    lda disk_diag_cmd_status1
    sta disk_diag_init_status1
    jsr disk_kernal_exit
    rts
#else
    lda #2
    sta disk_status
    lda #0
    sta disk_ui_value
    lda #hal_storage_marker_scratch_name_len
    ldx #<hal_storage_marker_scratch_name
    ldy #>hal_storage_marker_scratch_name
    jsr FEAT_SETNAM
    lda #hal_storage_cmd_channel
    ldx save_device
    ldy #hal_storage_cmd_channel
    jsr FEAT_SETLFS
    jsr FEAT_OPEN
    bcs !dmi_create+
    lda #hal_storage_cmd_channel
    jsr FEAT_CLOSE
    jsr FEAT_CLRCHN
!dmi_create:
    jsr hal_storage_marker_write_resident
!dmi_done:
    jsr disk_kernal_exit
#if HAL_STORAGE_DISK_SETUP_MARKER_WRITE_STATUS_REQUIRED
    lda disk_status
    bne !dmi_fail+
#endif
    jsr disk_marker_present
    bcs !dmi_fail+
!dmi_ok:
    clc
    rts
!dmi_fail:
    sec
    rts
#endif

disk_setup_call_ui:
#if HAL_STORAGE_DISK_SETUP_UI_TRAMPOLINE
    sta disk_ui_action
    jsr tramp_disk_setup_ui_action
    rts
#elif HAL_STORAGE_DISK_SETUP_UI_PLUS4_BANK_RAM
    sta disk_ui_action
    jsr plus4_bank_ram
    jsr ui_disk_setup_dispatch
    rts
#else
    sta disk_ui_action
    inc hal_memory_cpu_port
    jsr ui_disk_setup_dispatch
    dec hal_memory_cpu_port
    rts
#endif

disk_setup_commit_ready:
    lda #hal_storage_disk_setup_done_value
    sta disk_setup_done
#if HAL_STORAGE_MEDIA_STATE_TRACKING
    lda #C128_MEDIA_SAVE
    sta c128_media_state
#endif
    clc
    rts

disk_setup_commit_initialized:
#if HAL_STORAGE_DISK_SETUP_COMMIT_SETS_UI_OK
    lda #DISK_UI_RES_OK
    sta disk_ui_result
#endif
    jmp disk_setup_commit_ready

disk_setup_prepare_selected:
!retry:
    lda #DISK_UI_ACT_INSERT_DISK
    jsr disk_setup_call_ui
    jsr disk_init_drive
#if HAL_STORAGE_SAVE_MEDIA_STATUS_LEGACY
    bcs !show_marker_probe_fail+
#endif
#if HAL_STORAGE_COMMAND_STATUS_FROM_DISK_DIAG
    jsr disk_setup_capture_init_status
#endif
    jsr disk_program_media_present
    bcs !not_program_media+
    lda #DISK_UI_ACT_SHOW_PROGRAM
    jsr disk_setup_call_ui
    jmp !retry-
!not_program_media:
    jsr disk_marker_present
    bcc disk_setup_commit_ready
#if HAL_STORAGE_DISK_SETUP_ACCEPT_SAVE_FILE
    jsr disk_kernal_enter
    jsr save_file_exists
    jsr disk_kernal_exit
    bcs disk_setup_commit_ready
#endif
#if HAL_STORAGE_DISK_SETUP_MARKER_PROBE_DOS
    jsr disk_setup_plus4_marker_missing
    bcs !show_marker_probe_fail+
#endif
    lda #DISK_UI_ACT_INIT_PROMPT
    jsr disk_setup_call_ui
    lda disk_ui_result
    cmp #DISK_UI_RES_YES
    bne !fail+
    jsr disk_marker_init
    bcc disk_setup_commit_initialized
!show_marker_probe_fail:
    lda #DISK_UI_ACT_SHOW_INIT_FAIL
    jsr disk_setup_call_ui
!fail:
    sec
    rts

#if !HAL_STORAGE_PROGRAM_MEDIA_PRESENT_EXTERNAL
// Detect program media on the selected save drive.
// Output: carry clear = program media present, carry set = not program media
disk_program_media_present:
#if HAL_STORAGE_KERNAL_ENTER_REQUIRED
    jsr disk_kernal_enter
#endif
    lda #hal_storage_title_name_len
    ldx #<hal_storage_title_name
    ldy #>hal_storage_title_name
    jsr FEAT_SETNAM
    lda #hal_storage_program_file_num
    ldx save_device
    ldy #0
    jsr FEAT_SETLFS
    jsr FEAT_OPEN
    bcc !dpmp_open_ok+
    jsr FEAT_CLRCHN
#if HAL_STORAGE_KERNAL_ENTER_REQUIRED
    jsr disk_kernal_exit
#endif
    sec
    rts
!dpmp_open_ok:
    jsr hal_storage_read_command_status
#if HAL_STORAGE_COMMAND_STATUS_FROM_DISK_DIAG || HAL_STORAGE_COMMAND_STATUS_FROM_ERROR_DIAG
    jsr hal_storage_command_status
#else
    lda disk_status
#endif
    pha
    lda #hal_storage_program_file_num
    jsr FEAT_CLOSE
    jsr FEAT_CLRCHN
    jsr disk_kernal_exit
    pla
    cmp #1
    rts
#endif

#if HAL_STORAGE_DISK_SETUP_MARKER_PROBE_DOS
disk_setup_plus4_marker_missing:
    lda disk_error_dos0
    cmp #$36                    // 62,FILE NOT FOUND.
    bne !not_missing+
    lda disk_error_dos1
    cmp #$32
    bne !not_missing+
    clc
    rts
!not_missing:
    sec
    rts
#endif

disk_setup_run:
!menu:
    lda #DISK_UI_ACT_MENU
    jsr disk_setup_call_ui
    lda disk_ui_result
    cmp #DISK_UI_RES_TWO_DRIVE
    beq !pick_drive+
    cmp #DISK_UI_RES_ONE_DRIVE
    beq !same_drive+
    cmp #DISK_UI_RES_OK
    beq !prepare+
    bne !fail+

!same_drive:
    lda program_device
    sta save_device
    bne !prepare+

#if HAL_STORAGE_DISK_SETUP_OTHER_DRIVE
!pick_drive:
    lda #DISK_UI_ACT_ENTER_DEVICE
    jsr disk_setup_call_ui
    lda disk_ui_result
    cmp #DISK_UI_RES_OK
    bne !menu-
    ldx disk_ui_value
    jsr hal_storage_probe_media
    bcc !other_probe_ok+
    lda #DISK_UI_ACT_SHOW_NO_DEVICE
    jsr disk_setup_call_ui
    jmp !menu-
!other_probe_ok:
    lda disk_ui_value
    sta save_device
    jmp !menu-
#endif

!prepare:
#if HAL_STORAGE_SHARED_PROGRAM_SAVE_NO_SWAP
    lda #2
#else
    lda #1
#endif
    ldx save_device
    cpx program_device
    beq !mode_set+
    lda #2
!mode_set:
    sta disk_mode
    jsr disk_setup_prepare_selected
    bcs !menu-
    clc
    rts

!fail:
    sec
    rts
