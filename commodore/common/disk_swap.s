#importonce
// disk_swap.s — Save-disk session state and validation helpers
//
// Keeps the resident disk contract intentionally small:
//   - swap prompts for one-drive mode
//   - swap/init state for platform-owned device probing / drive init
//   - save-disk marker validation and initialization
//   - tiny shared state used by title/setup/save/load/hiscore paths
//
// The guided setup UI lives in the UI overlay so resident code stays small.

#import "bank_port_consts.s"
#import "storage_status.s"

// ============================================================
// Data
// ============================================================
disk_mode:         .byte 0             // 0=unset, 1=one-drive swap, 2=save drive
program_device:    .byte 8             // Device# for program/runtime PRG I/O
save_device:       .byte 8             // Device# for save/score I/O
disk_setup_done:   .byte 0             // 0 until the session finishes Disk Setup
disk_ui_result:    .byte 1             // 0=success, 1=cancel/failure
disk_ui_action:    .byte 0
disk_ui_value:     .byte 0

disk_temp:         .byte 0
disk_status:       .byte 0
disk_prompt_device:.byte 8
#if PLUS4
disk_error_phase:  .byte 0
disk_error_readst: .byte 0
disk_error_dos0:   .byte 0
disk_error_dos1:   .byte 0
disk_error_device: .byte 8
disk_error_actual: .byte 0
disk_error_expect: .byte 0
disk_error_index:  .byte 0
#endif

.const DS_PROMPT_COL = (SCREEN_COLS - 19) / 2
.const DS_PRESS_ANY_KEY_COL = (SCREEN_COLS - 13) / 2
.const DS_DRIVE_IND_COL = (SCREEN_COLS - 10) / 2
.const DS_TITLE_MENU_ROW = STATUS_ROW
.const DS_TITLE_PROMPT_ROW = STATUS_ROW + 1
#if C128 || PLUS4
.const DISK_ERR_NONE              = $00
.const DISK_ERR_MARKER_OPEN       = $81
.const DISK_ERR_MARKER_CHKIN      = $82
.const DISK_ERR_MARKER_READ       = $83
.const DISK_ERR_SCRATCH           = $97
.const DISK_ERR_MARKER_WRITE_OPEN = $92
.const DISK_ERR_MARKER_CHKOUT     = $93
.const DISK_ERR_MARKER_WRITE      = $94
.const DISK_ERR_MARKER_CLOSE      = $95
.const DISK_ERR_MARKER_DOS        = $96
.const DISK_ERR_SAVE_OPEN         = $a1
.const DISK_ERR_SAVE_CHKOUT       = $a2
.const DISK_ERR_SAVE_WRITE        = $a3
.const DISK_ERR_LOAD_OPEN         = $b1
.const DISK_ERR_LOAD_CHKIN        = $b2
.const DISK_ERR_LOAD_READ         = $b3
.const DISK_ERR_HISCORE_LOAD      = $c1
.const DISK_ERR_HISCORE_SAVE      = $c2
#endif

.const DISK_UI_ACT_MENU            = 0
.const DISK_UI_ACT_CONFIRM_DRIVE9  = 1
.const DISK_UI_ACT_INSERT_DISK     = 2
.const DISK_UI_ACT_INIT_PROMPT     = 3
.const DISK_UI_ACT_SHOW_NO_DRIVE9  = 4
.const DISK_UI_ACT_SHOW_NO_DEVICE  = 5
.const DISK_UI_ACT_SHOW_PROGRAM    = 6
.const DISK_UI_ACT_SHOW_INIT_FAIL  = 7
.const DISK_UI_ACT_ENTER_DEVICE    = 8

.const DISK_UI_RES_OK          = 0
.const DISK_UI_RES_CANCEL      = 1
.const DISK_UI_RES_ONE_DRIVE   = 2
.const DISK_UI_RES_TWO_DRIVE   = 3
.const DISK_UI_RES_OTHER_DRIVE = 4
.const DISK_UI_RES_YES         = 5
.const DISK_UI_RES_NO          = 6

// ============================================================
// Session helpers
// ============================================================
disk_reset_session_state:
    lda #0
    sta disk_mode
    sta disk_setup_done
    lda #1
    sta disk_ui_result
    lda #8
    sta program_device
    sta save_device
#if PLUS4
    sta disk_error_device
    lda #0
    sta disk_error_phase
    sta disk_error_readst
    sta disk_error_dos0
    sta disk_error_dos1
    sta disk_error_actual
    sta disk_error_expect
    sta disk_error_index
#endif
#if C128
    lda #C128_MEDIA_UNKNOWN
    sta c128_media_state
#endif
    rts

#if PLUS4
disk_error_clear:
    lda #0
    sta disk_error_phase
    sta disk_error_readst
    sta disk_error_dos0
    sta disk_error_dos1
    sta disk_error_actual
    sta disk_error_expect
    sta disk_error_index
    lda save_device
    sta disk_error_device
    rts

disk_error_set_phase:
    sta disk_error_phase
    lda save_device
    sta disk_error_device
    lda #0
    sta disk_error_readst
    sta disk_error_dos0
    sta disk_error_dos1
    sta disk_error_actual
    sta disk_error_expect
    sta disk_error_index
    rts

disk_error_set_readst:
    sta disk_error_readst
    lda save_device
    sta disk_error_device
    rts

disk_error_set_dos_status:
    sta disk_error_dos0
    stx disk_error_dos1
    lda save_device
    sta disk_error_device
    rts
#endif

// disk_save_media_status
// Output: A = HAL_STORAGE_STATUS_* for the most recent save-media failure.
//         Raw platform diagnostics remain in disk_status/disk_error_*.
disk_save_media_status:
#if !C128 && !PLUS4
    lda disk_status
    cmp #2                      // 0/1 = wrong media; >=2 = I/O/device.
    bcs !ioerr+
    lda #HAL_STORAGE_STATUS_WRONG_MEDIA
    rts
!ioerr:
    lda #HAL_STORAGE_STATUS_UNKNOWN
    rts
#elif PLUS4
    lda disk_status
    cmp #74
    bne !check_readst+
    lda #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    rts
!check_readst:
    lda disk_error_readst
    bne !unknown+
    lda disk_error_dos0
    beq !wrong+
    lda disk_error_dos0
    ldx disk_error_dos1
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_NOT_FOUND
    bne !unknown+
!wrong:
    lda #HAL_STORAGE_STATUS_WRONG_MEDIA
    rts
!unknown:
    lda #HAL_STORAGE_STATUS_UNKNOWN
    rts
#elif C128
    lda disk_status
    cmp #$83                    // Marker bytes read, but contents mismatch.
    beq !wrong+
    cmp #$84                    // Marker READ failed; READST alone is ambiguous.
    bne !ioerr+
!check_dos:
    jsr disk_kernal_enter
    jsr hal_storage_read_command_status
    jsr disk_kernal_exit
    lda disk_diag_cmd_status0
    ldx disk_diag_cmd_status1
    jsr storage_status_from_dos_digits
    cmp #HAL_STORAGE_STATUS_NOT_FOUND
    bne !ioerr+
    jmp !wrong+
!ioerr:
    lda #HAL_STORAGE_STATUS_UNKNOWN
    rts
!wrong:
    lda #HAL_STORAGE_STATUS_WRONG_MEDIA
    rts
#endif

disk_require_save_media:
    lda disk_setup_done
    bne !drsm_check+
    sec
    rts
!drsm_check:
    lda disk_mode
    bne !drsm_marker+
    sec
    rts
!drsm_marker:
    jsr disk_marker_present
    rts

// ============================================================
// Swap prompts
// ============================================================
disk_prompt_save:
    lda save_device
    sta disk_prompt_device
#if C128
    // In one-drive mode, setup completion does not prove which disk is
    // currently mounted. Prompt only when the media-state owner says save
    // media is not already current.
    lda disk_mode
    cmp #1
    bne !dps_prompt+
    lda c128_media_state
    cmp #C128_MEDIA_SAVE
    bne !dps_prompt+
    jsr input_prepare_modal_dismiss_key
    jsr disk_init_drive
    rts
!dps_prompt:
#else
    // On C64, the first one-drive save/load transaction after Disk Setup
    // already has the save disk mounted from the setup UI. Consume that
    // fresh-setup state once so the player is not asked to press a second key
    // for the same media swap.
    lda disk_mode
    cmp #1
    bne !dps_prompt+
    lda disk_setup_done
    cmp #2
    bne !dps_prompt+
    dec disk_setup_done
    rts
#endif
#if !C128
!dps_prompt:
#endif
    lda #<ds_save_str
    ldx #>ds_save_str
    jmp disk_prompt

disk_prompt_game:
    lda program_device
    sta disk_prompt_device
#if C128
    lda disk_mode
    cmp #1
    bne !dpg_prompt+
    lda c128_media_state
    cmp #C128_MEDIA_PROGRAM
    bne !dpg_prompt+
    rts
!dpg_prompt:
#endif
    lda #<ds_game_str
    ldx #>ds_game_str
    jmp disk_prompt

disk_prompt:
    sta zp_ptr0
    stx zp_ptr0_hi
    lda disk_mode
    cmp #1
    beq !dp_show+
    rts
!dp_show:
#if !C128
    jsr ui_clear_full_screen_safe
    jsr msg_init
#endif
    lda #COL_WHITE
    sta zp_text_color
    lda #10
    sta zp_cursor_row
    lda #DS_PROMPT_COL
    sta zp_cursor_col
    jsr screen_put_string

    lda #11
    sta zp_cursor_row
    lda #DS_PRESS_ANY_KEY_COL
    sta zp_cursor_col
    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
    sta zp_ptr0_hi
    jsr screen_put_string

#if C128
    jsr input_get_modal_dismiss_key
#else
    jsr input_get_key
    jsr ui_clear_full_screen_safe
    jsr msg_init
#endif
    jsr hal_storage_init_selected_drive

#if !C128
    lda #BANK_NO_BASIC
    sta $01
    rts
#else
    lda #10
    jsr screen_clear_row
    lda #11
    jsr screen_clear_row
    lda disk_prompt_device
    cmp program_device
    bne !dp_not_program+
    lda #C128_MEDIA_PROGRAM
    sta c128_media_state
    rts
!dp_not_program:
    cmp save_device
    bne !dp_media_unknown+
    lda #C128_MEDIA_SAVE
    sta c128_media_state
    rts
!dp_media_unknown:
    lda #C128_MEDIA_UNKNOWN
    sta c128_media_state
#endif
    rts

#if C128
disk_dir_read_fname:
    .byte $24                           // "$"
.label disk_dir_read_fname_len = * - disk_dir_read_fname
#endif

// ============================================================
// KERNAL access wrappers
// ============================================================
disk_kernal_enter:
#if C128
    :EnterKernal()
#endif
    rts

disk_kernal_exit:
#if C128
    :ExitKernal()
#else
    sei
#endif
    rts

// ============================================================
// disk_init_drive — Reinitialize current save drive
// ============================================================
disk_init_drive:
    lda save_device
    sta disk_prompt_device
    jmp hal_storage_init_selected_drive

// ============================================================
// disk_marker_present — Validate the configured save-disk marker file
// Output: carry clear = valid marker found, carry set = invalid/missing
// ============================================================
disk_marker_present:
#if !C128
    jsr hal_storage_marker_present
    rts
#else
    lda #$81
    sta disk_status
    sta disk_diag_phase
    lda save_device
    sta disk_diag_device
    lda #hal_storage_marker_file_num
    sta disk_diag_lfn
    lda #hal_storage_marker_sec_read
    sta disk_diag_sec
    jsr disk_kernal_enter

    lda #hal_storage_marker_read_name_len
    ldx #<hal_storage_marker_read_name
    ldy #>hal_storage_marker_read_name
    jsr KERNAL_SETNAM
    lda #hal_storage_marker_file_num
    ldx save_device
    ldy #hal_storage_marker_sec_read
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcc !dmp_open_ok+
    lda #1
    sta disk_diag_carry
    lda #$81
    sta disk_status
    jmp !dmp_done+
!dmp_open_ok:
    lda #0
    sta disk_diag_carry
    jsr KERNAL_READST
    sta disk_diag_readst
    beq !dmp_chkin+
    lda #$81
    sta disk_status
    jmp !dmp_close+

!dmp_chkin:
    lda #$82
    sta disk_diag_phase
    ldx #hal_storage_marker_file_num
    jsr KERNAL_CHKIN
    bcc !dmp_read_start+
    lda #1
    sta disk_diag_carry
    lda #$82
    sta disk_status
    jmp !dmp_close+

!dmp_read_start:
    lda #0
    sta disk_diag_carry
    lda #0
    sta disk_temp
!dmp_read:
    lda #$83
    sta disk_diag_phase
    lda disk_temp
    sta disk_diag_index
    jsr KERNAL_CHRIN
    sta disk_diag_byte
    jsr KERNAL_READST
    sta disk_diag_readst
    beq !dmp_cmp+
    cmp #$40
    bne !dmp_read_status_fail+
    lda disk_temp
    cmp #hal_storage_marker_magic_len - 1
    beq !dmp_cmp+
!dmp_read_status_fail:
    lda #$84
    sta disk_status
    jmp !dmp_close+
!dmp_cmp:
    ldx disk_temp
    lda disk_diag_byte
    cmp hal_storage_marker_magic,x
    bne !dmp_fail+
    inx
    stx disk_temp
    cpx #hal_storage_marker_magic_len
    bcc !dmp_read-
    lda #0
    sta disk_status
    jmp !dmp_close+
!dmp_fail:
    sta disk_temp
    lda #$83
    sta disk_status
!dmp_close:
    jsr KERNAL_CLRCHN
    lda #hal_storage_marker_file_num
    jsr KERNAL_CLOSE
!dmp_done:
    jsr disk_kernal_exit
    lda disk_status
    beq !dmp_ok+
    sec
    rts
!dmp_ok:
    clc
    rts
#endif
