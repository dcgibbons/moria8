#importonce
// disk_setup_banked.s — Non-overlay FEAT-DISK coordinator
//
// C64 hosts this in the banked payload. C128 imports the same coordinator into
// resident code. In both cases the overlay remains display/input only and
// all disk transactions stay outside the live overlay frame.

disk_marker_scratch_cmd:
    .byte $53, $30, $3a                 // "S0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44  // "MORIA8.ID"
.label disk_marker_scratch_cmd_len = * - disk_marker_scratch_cmd
#if !C128
.label c64_disk_marker_write_phys = c64_disk_marker_write_resident
#else
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
#if C128
    lda #$90
    sta disk_diag_phase
    lda save_device
    sta disk_diag_device
    lda #DISK_MARKER_FILE_NUM
    sta disk_diag_lfn
    lda #DISK_MARKER_SEC_WR
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
    lda #disk_marker_scratch_cmd_len
    ldx #<disk_marker_scratch_cmd
    ldy #>disk_marker_scratch_cmd
    jsr KERNAL_SETNAM
    lda #CMD_CHANNEL
    ldx save_device
    ldy #CMD_CHANNEL
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcc !dmi_scratch_open_ok+
    lda #1
    sta disk_diag_carry
    lda #$97
    sta disk_diag_phase
    sta disk_status
    jmp !dmi_done+
!dmi_scratch_open_ok:
    lda #CMD_CHANNEL
    jsr KERNAL_CLOSE
    jsr KERNAL_CLRCHN
    jsr disk_diag_read_command_status
    lda disk_diag_cmd_status0
    sta disk_diag_scratch_status0
    lda disk_diag_cmd_status1
    sta disk_diag_scratch_status1
    lda disk_diag_scratch_status0
    cmp #$30
    bne !dmi_scratch_fail+
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

    lda #disk_marker_write_fname_len - 1
    ldx #<(disk_marker_write_fname + 1)
    ldy #>(disk_marker_write_fname + 1)
    jsr KERNAL_SETNAM
    lda #DISK_MARKER_FILE_NUM
    ldx save_device
    ldy #DISK_MARKER_SEC_WR
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
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
    jsr KERNAL_READST
    sta disk_diag_readst
    beq !dmi_chkout+
    lda #$92
    sta disk_diag_phase
    sta disk_status
    jmp !dmi_close+

!dmi_chkout:
    lda #$93
    sta disk_diag_phase
    ldx #DISK_MARKER_FILE_NUM
    jsr KERNAL_CHKOUT
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
    lda disk_marker_magic,x
    jsr KERNAL_CHROUT
    jsr KERNAL_READST
    sta disk_diag_readst
    beq !dmi_write_ok+
    lda #$94
    sta disk_status
    jmp !dmi_close+
!dmi_write_ok:
    inc disk_temp
    lda disk_temp
    cmp #DISK_MARKER_MAGIC_LEN
    bcc !dmi_write-
    lda #0
    sta disk_status
!dmi_close:
    lda #$95
    sta disk_diag_phase
    jsr KERNAL_CLRCHN
    lda #DISK_MARKER_FILE_NUM
    jsr KERNAL_CLOSE
    jsr KERNAL_READST
    sta disk_diag_readst
    jsr disk_diag_read_command_status
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
    sec
    rts
!dmi_ok:
    clc
    rts

disk_diag_read_command_status:
    lda #$ff
    sta disk_diag_cmd_status0
    sta disk_diag_cmd_status1
    lda #0
    ldx #0
    ldy #0
    jsr KERNAL_SETNAM
    lda #CMD_CHANNEL
    ldx save_device
    ldy #CMD_CHANNEL
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcs !ddrcs_done+
    ldx #CMD_CHANNEL
    jsr KERNAL_CHKIN
    bcs !ddrcs_close+
    jsr KERNAL_CHRIN
    sta disk_diag_cmd_status0
    jsr KERNAL_READST
    sta disk_diag_readst
    jsr KERNAL_CHRIN
    sta disk_diag_cmd_status1
    jsr KERNAL_READST
    sta disk_diag_readst
!ddrcs_close:
    jsr KERNAL_CLRCHN
    lda #CMD_CHANNEL
    jsr KERNAL_CLOSE
!ddrcs_done:
    rts

disk_setup_capture_init_status:
    lda #$ff
    sta disk_diag_init_status0
    sta disk_diag_init_status1
    jsr disk_kernal_enter
    jsr disk_diag_read_command_status
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
    lda #disk_marker_scratch_cmd_len
    ldx #<disk_marker_scratch_cmd
    ldy #>disk_marker_scratch_cmd
    jsr FEAT_SETNAM
    lda #CMD_CHANNEL
    ldx save_device
    ldy #CMD_CHANNEL
    jsr FEAT_SETLFS
    jsr FEAT_OPEN
    bcs !dmi_create+
    lda #CMD_CHANNEL
    jsr FEAT_CLOSE
    jsr FEAT_CLRCHN
!dmi_create:
    jsr c64_disk_marker_write_phys
!dmi_done:
    jsr disk_kernal_exit
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
#if C128
    sta disk_ui_action
    jsr tramp_disk_setup_ui_action
    rts
#else
    sta disk_ui_action
    inc $01
    jsr ui_disk_setup_dispatch
    dec $01
    rts
#endif

disk_setup_commit_ready:
#if C128
    lda #1
    sta disk_setup_done
#else
    lda #2
    sta disk_setup_done
#endif
    clc
    rts

disk_setup_commit_initialized:
#if C128
    lda #1
    sta disk_setup_done
    lda #DISK_UI_RES_OK
    sta disk_ui_result
#else
    lda #2
    sta disk_setup_done
#endif
    clc
    rts

disk_setup_prepare_selected:
!retry:
    lda #DISK_UI_ACT_INSERT_DISK
    jsr disk_setup_call_ui
    jsr disk_init_drive
#if C128
    jsr disk_setup_capture_init_status
#endif
    jsr disk_marker_present
    bcc disk_setup_commit_ready
    lda #DISK_UI_ACT_INIT_PROMPT
    jsr disk_setup_call_ui
    lda disk_ui_result
    cmp #DISK_UI_RES_YES
    bne !fail+
    jsr disk_marker_init
    bcc disk_setup_commit_initialized
    lda #DISK_UI_ACT_SHOW_INIT_FAIL
    jsr disk_setup_call_ui
!fail:
    sec
    rts

disk_setup_use_drive9:
    lda #9
    sta save_device
    lda #2
    sta disk_mode
    jmp disk_setup_prepare_selected

disk_setup_run:
    lda disk_setup_done
    bne !menu+
#if C128
    ldx #9
    jsr probe_device
#else
    ldx #9
    jsr probe_device
#endif
    bcs !menu+
    lda #DISK_UI_ACT_CONFIRM_DRIVE9
    jsr disk_setup_call_ui
    lda disk_ui_result
    cmp #DISK_UI_RES_YES
    bne !menu+
    jsr disk_setup_use_drive9
    bcc !done+

!menu:
    lda #DISK_UI_ACT_MENU
    jsr disk_setup_call_ui
    lda disk_ui_result
#if C128
    cmp #DISK_UI_RES_OTHER_DRIVE
    beq !other_drive+
#endif
    cmp #DISK_UI_RES_TWO_DRIVE
    beq !two_drive+
    cmp #DISK_UI_RES_ONE_DRIVE
    bne !fail+
    lda #8
    sta save_device
    lda #1
    sta disk_mode
    jsr disk_setup_prepare_selected
    bcs !menu-
!done:
    clc
    rts

!two_drive:
    ldx #9
    jsr probe_device
    bcc !drive9_present+
    lda #DISK_UI_ACT_SHOW_NO_DRIVE9
    jsr disk_setup_call_ui
    jmp !menu-
!drive9_present:
    jsr disk_setup_use_drive9
    bcs !menu-
    clc
    rts

#if C128
!other_drive:
    lda #DISK_UI_ACT_ENTER_DEVICE
    jsr disk_setup_call_ui
    lda disk_ui_result
    cmp #DISK_UI_RES_OK
    bne !menu-
    ldx disk_ui_value
    jsr probe_device
    bcc !other_probe_ok+
    lda #DISK_UI_ACT_SHOW_NO_DEVICE
    jsr disk_setup_call_ui
    jmp !menu-
!other_probe_ok:
    lda disk_ui_value
    sta save_device
    cmp #8
    bne !other_two_drive+
    lda #1
    bne !other_mode_set+
!other_two_drive:
    lda #2
!other_mode_set:
    sta disk_mode
    jsr disk_setup_prepare_selected
    bcs !menu-
    clc
    rts
#endif

!fail:
    sec
    rts
