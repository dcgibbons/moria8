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

.const SWAP_SETNAM = hal_storage_setnam
.const SWAP_SETLFS = hal_storage_setlfs
.const SWAP_OPEN   = hal_storage_open
.const SWAP_CLOSE  = hal_storage_close
.const SWAP_CHKIN  = hal_storage_chkin
.const SWAP_CHRIN  = hal_storage_chrin
.const SWAP_CLRCHN = hal_storage_clrchn
.const SWAP_READST = hal_storage_readst

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
#if HAL_STORAGE_EXTENDED_DISK_DIAG
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
#if HAL_STORAGE_COMMAND_STATUS_FROM_DISK_DIAG || HAL_STORAGE_COMMAND_STATUS_FROM_ERROR_DIAG
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
#if HAL_STORAGE_EXTENDED_DISK_DIAG
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
#if HAL_STORAGE_MEDIA_STATE_TRACKING
    lda #C128_MEDIA_UNKNOWN
    sta c128_media_state
#endif
    rts

#if HAL_STORAGE_EXTENDED_DISK_DIAG
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

#if HAL_STORAGE_COMMAND_STATUS_FROM_DISK_DIAG || HAL_STORAGE_COMMAND_STATUS_FROM_ERROR_DIAG
// disk_command_status
// Output: A = HAL_STORAGE_STATUS_* for the most recently captured DOS command
// channel status. Raw diagnostic bytes remain platform-owned.
disk_command_status:
#if HAL_STORAGE_COMMAND_STATUS_FROM_DISK_DIAG
    lda disk_diag_cmd_status0
    ldx disk_diag_cmd_status1
    jmp storage_status_from_dos_digits
#elif HAL_STORAGE_COMMAND_STATUS_FROM_ERROR_DIAG
    lda disk_error_dos0
    bne !digits+
    ldx disk_error_dos1
    bne !digits+
    lda #HAL_STORAGE_STATUS_OK
    rts
!digits:
    ldx disk_error_dos1
    jmp storage_status_from_dos_digits
#endif
#endif

// disk_save_media_status
// Output: A = HAL_STORAGE_STATUS_* for the most recent save-media failure.
//         Raw platform diagnostics remain in disk_status/disk_error_*.
disk_save_media_status:
#if HAL_STORAGE_SAVE_MEDIA_STATUS_LEGACY
    lda disk_status
    cmp #2                      // 0/1 = wrong media; >=2 = I/O/device.
    bcs !ioerr+
    lda #HAL_STORAGE_STATUS_WRONG_MEDIA
    rts
!ioerr:
    lda #HAL_STORAGE_STATUS_UNKNOWN
    rts
#elif HAL_STORAGE_SAVE_MEDIA_STATUS_ERROR_DIAG
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
    jsr hal_storage_command_status
    cmp #HAL_STORAGE_STATUS_NOT_FOUND
    bne !unknown+
!wrong:
    lda #HAL_STORAGE_STATUS_WRONG_MEDIA
    rts
!unknown:
    lda #HAL_STORAGE_STATUS_UNKNOWN
    rts
#elif HAL_STORAGE_SAVE_MEDIA_STATUS_MARKER_DOS
    lda disk_status
    cmp #$83                    // Marker bytes read, but contents mismatch.
    beq !wrong+
    cmp #$84                    // Marker READ failed; READST alone is ambiguous.
    bne !ioerr+
!check_dos:
    jsr disk_kernal_enter
    jsr hal_storage_read_command_status
    jsr disk_kernal_exit
    jsr hal_storage_command_status
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

#if HAL_STORAGE_COMMAND_STATUS_FROM_DISK_DIAG || HAL_STORAGE_COMMAND_STATUS_FROM_ERROR_DIAG || STORAGE_SETUP_STATUS_HELPER
// disk_setup_status
// Output: A = HAL_STORAGE_STATUS_* for the most recent Disk Setup init failure.
//         Raw platform diagnostics remain in disk_status/disk_error_*.
disk_setup_status:
#if HAL_STORAGE_SETUP_STATUS_COMMAND_FIRST
    jsr hal_storage_command_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    bne !done+
    jmp disk_setup_status_from_raw
!done:
    rts
#elif HAL_STORAGE_SETUP_STATUS_ERROR_FIRST
    lda disk_error_dos0
    beq !raw+
    jsr hal_storage_command_status
    cmp #HAL_STORAGE_STATUS_UNKNOWN
    bne !done+
!raw:
    jsr disk_setup_status_from_raw
!done:
    rts
#elif STORAGE_SETUP_STATUS_HELPER
    jmp disk_setup_status_from_raw
#endif

disk_setup_status_from_raw:
    lda disk_status
    cmp #26
    bne !check_full+
    lda #HAL_STORAGE_STATUS_WRITE_PROTECTED
    rts
!check_full:
    cmp #72
    bne !check_ready+
    lda #HAL_STORAGE_STATUS_DISK_FULL
    rts
!check_ready:
    cmp #74
    bne !unknown+
    lda #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    rts
!unknown:
    lda #HAL_STORAGE_STATUS_UNKNOWN
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
#if HAL_STORAGE_MEDIA_STATE_TRACKING
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
    bcc !dps_save_ready+
    lda #C128_MEDIA_UNKNOWN
    sta c128_media_state
    sec
    rts
!dps_save_ready:
    lda #C128_MEDIA_SAVE
    sta c128_media_state
    clc
    rts
!dps_prompt:
#elif HAL_STORAGE_SWAP_PROMPT_LEGACY_SETUP_SKIP
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
#if HAL_STORAGE_SWAP_PROMPT_FULLSCREEN || HAL_STORAGE_MEDIA_STATE_TRACKING
!dps_prompt:
#endif
    lda #<ds_save_str
    ldx #>ds_save_str
    jmp disk_prompt

disk_prompt_game:
    lda program_device
    sta disk_prompt_device
#if HAL_STORAGE_MEDIA_STATE_TRACKING
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
#if HAL_STORAGE_SWAP_PROMPT_FULLSCREEN
    jsr ui_clear_full_screen_safe
    jsr msg_init
#endif
    lda #COL_WHITE
    sta zp_text_color
    lda #10
    sta zp_cursor_row
    lda #DS_PROMPT_COL
    sta zp_cursor_col
    jsr hal_screen_put_string

    lda #11
    sta zp_cursor_row
    lda #DS_PRESS_ANY_KEY_COL
    sta zp_cursor_col
    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
    sta zp_ptr0_hi
    jsr hal_screen_put_string

#if HAL_STORAGE_SWAP_PROMPT_MODAL_DISMISS
    jsr input_get_modal_dismiss_key
#elif HAL_STORAGE_SWAP_PROMPT_SIMPLE_KEY
    jsr hal_input_get_key
    jsr ui_clear_full_screen_safe
    jsr msg_init
#endif
    jsr hal_storage_init_selected_drive

#if HAL_STORAGE_SWAP_PROMPT_CPU_PORT_RESTORE
    lda #BANK_NO_BASIC
    sta hal_memory_cpu_port
    rts
#elif HAL_STORAGE_SWAP_PROMPT_RETURN_AFTER_INIT
    rts
#elif HAL_STORAGE_SWAP_PROMPT_CLEAR_ROWS_AND_TRACK_MEDIA
    php
    lda #10
    jsr hal_screen_clear_row
    lda #11
    jsr hal_screen_clear_row
    plp
    bcc !dp_init_ok+
    lda #C128_MEDIA_UNKNOWN
    sta c128_media_state
    sec
    rts
!dp_init_ok:
    lda disk_prompt_device
    cmp program_device
    bne !dp_not_program+
    lda #C128_MEDIA_PROGRAM
    sta c128_media_state
    clc
    rts
!dp_not_program:
    cmp save_device
    bne !dp_media_unknown+
    lda #C128_MEDIA_SAVE
    sta c128_media_state
    clc
    rts
!dp_media_unknown:
    lda #C128_MEDIA_UNKNOWN
    sta c128_media_state
    clc
#endif
    rts

#if HAL_STORAGE_DIR_READ_FNAME
disk_dir_read_fname:
    .byte $24                           // "$"
.label disk_dir_read_fname_len = * - disk_dir_read_fname
#endif

// ============================================================
// KERNAL access wrappers
// ============================================================
disk_kernal_enter:
#if HAL_STORAGE_KERNAL_ENTER_REQUIRED
    :EnterKernal()
#endif
    rts

disk_kernal_exit:
#if HAL_STORAGE_KERNAL_ENTER_REQUIRED
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
#if HAL_STORAGE_MARKER_PRESENT_DIRECT
    jsr hal_storage_marker_present
    rts
#elif HAL_STORAGE_MARKER_PRESENT_INLINE
    lda #$81
    sta disk_status
    sta disk_diag_phase
    lda save_device
    sta disk_diag_device
    lda #hal_storage_marker_file_num
    sta disk_diag_lfn
    lda #hal_storage_marker_sec_read
    sta disk_diag_sec
#if C128_TEST_SCRIPTED_SAVE_MEDIA_FAIL_PRODUCT
    lda c128_test_input_idx
    cmp #3
    bcc !dmp_test_normal+
    lda #74
    sta disk_status
    lda #$81
    sta disk_diag_phase
    lda #$37
    sta disk_diag_cmd_status0
    lda #$34
    sta disk_diag_cmd_status1
    sec
    rts
!dmp_test_normal:
#endif
    jsr disk_kernal_enter

    lda #hal_storage_marker_read_name_len
    ldx #<hal_storage_marker_read_name
    ldy #>hal_storage_marker_read_name
    jsr SWAP_SETNAM
    lda #hal_storage_marker_file_num
    ldx save_device
    ldy #hal_storage_marker_sec_read
    jsr SWAP_SETLFS
    jsr SWAP_OPEN
    bcc !dmp_open_ok+
    lda #1
    sta disk_diag_carry
    lda #$81
    sta disk_status
    jmp !dmp_done+
!dmp_open_ok:
    lda #0
    sta disk_diag_carry
    jsr SWAP_READST
    sta disk_diag_readst
    beq !dmp_chkin+
    lda #$81
    sta disk_status
    jmp !dmp_close+

!dmp_chkin:
    lda #$82
    sta disk_diag_phase
    ldx #hal_storage_marker_file_num
    jsr SWAP_CHKIN
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
    jsr SWAP_CHRIN
    sta disk_diag_byte
    jsr SWAP_READST
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
    jsr SWAP_CLRCHN
    lda #hal_storage_marker_file_num
    jsr SWAP_CLOSE
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
