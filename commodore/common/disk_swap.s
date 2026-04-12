#importonce
// disk_swap.s — Save-disk session state and validation helpers
//
// Keeps the resident disk contract intentionally small:
//   - swap prompts for one-drive mode
//   - device probing / drive init
//   - save-disk marker validation and initialization
//   - tiny shared state used by title/setup/save/load/hiscore paths
//
// The guided setup UI lives in the UI overlay so resident code stays small.

#import "bank_port_consts.s"

// ============================================================
// Data
// ============================================================
disk_mode:         .byte 0             // 0=unset, 1=one-drive swap, 2=save drive
save_device:       .byte 8             // Device# for save/score I/O
disk_setup_done:   .byte 0             // 0 until the session finishes Disk Setup
disk_ui_result:    .byte 1             // 0=success, 1=cancel/failure
disk_ui_action:    .byte 0
disk_ui_value:     .byte 0

disk_temp:         .byte 0
disk_status:       .byte 0

// PETSCII command bytes / marker file contents
disk_init_cmd:     .byte $49, $30      // "I0"
disk_marker_magic: .byte $4d, $38, $53, $41, $56, $45  // "M8SAVE"
.const DISK_MARKER_MAGIC_LEN = * - disk_marker_magic

disk_marker_read_fname:
    .byte $30, $3a                      // "0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44  // "MORIA8.ID"
    .byte $2c, $53, $2c, $52            // ",S,R"
.label disk_marker_read_fname_len = * - disk_marker_read_fname

disk_marker_write_fname:
    .byte $40                           // "@"
    .byte $30, $3a                      // "0:"
    .byte $4d, $4f, $52, $49, $41, $38, $2e, $49, $44  // "MORIA8.ID"
    .byte $2c, $53, $2c, $57            // ",S,W"
.label disk_marker_write_fname_len = * - disk_marker_write_fname

.const DS_PROMPT_COL = (SCREEN_COLS - 19) / 2
.const DS_PRESS_ANY_KEY_COL = (SCREEN_COLS - 13) / 2
.const DS_DRIVE_IND_COL = (SCREEN_COLS - 10) / 2
.const DS_TITLE_MENU_ROW = STATUS_ROW
.const DS_TITLE_PROMPT_ROW = STATUS_ROW + 1
.const DISK_MARKER_FILE_NUM = 6
.const DISK_MARKER_SEC_RD   = 2       // Match normal sequential file reads
.const DISK_MARKER_SEC_WR   = 2       // Match normal sequential file writes
.const DISK_PROGRAM_FILE_NUM = 7
.const KERNAL_ERR_DEVICE_NOT_PRESENT = 5

#if C128
.const FEAT_SETNAM = KERNAL_SETNAM
.const FEAT_SETLFS = KERNAL_SETLFS
.const FEAT_OPEN   = KERNAL_OPEN
.const FEAT_CLOSE  = KERNAL_CLOSE
.const FEAT_CLRCHN = KERNAL_CLRCHN
.const FEAT_READST = KERNAL_READST
.const FEAT_CHKIN  = KERNAL_CHKIN
.const FEAT_CHKOUT = KERNAL_CHKOUT
.const FEAT_CHRIN  = KERNAL_CHRIN
.const FEAT_CHROUT = KERNAL_CHROUT
#else
.const FEAT_SETNAM = c64_disk_setnam
.const FEAT_SETLFS = c64_disk_setlfs
.const FEAT_OPEN   = c64_disk_open
.const FEAT_CLOSE  = c64_disk_close
.const FEAT_CLRCHN = c64_disk_clrchn
.const FEAT_READST = KERNAL_READST
.const FEAT_CHKIN  = KERNAL_CHKIN
.const FEAT_CHKOUT = KERNAL_CHKOUT
.const FEAT_CHRIN  = KERNAL_CHRIN
.const FEAT_CHROUT = KERNAL_CHROUT
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
    sta save_device
    rts

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
#if C128
    // After one-drive setup validates the save disk on C128, keep runtime
    // on that media instead of re-prompting on every save/load transaction.
    lda disk_mode
    cmp #1
    bne !dps_prompt+
    lda disk_setup_done
    bne !dps_skip+
!dps_prompt:
#endif
    lda #<ds_save_str
    ldx #>ds_save_str
    jmp disk_prompt
#if C128
!dps_skip:
    rts
#endif

disk_prompt_game:
#if C128
    // C128 runtime/overlay assets are already resident after boot, so
    // one-drive sessions never need to swap back to program media. This
    // intentionally skips the legacy prompt and its drive re-init side effect.
    lda disk_mode
    cmp #1
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
#endif
    jsr disk_init_drive

#if !C128
    lda #BANK_NO_BASIC
    sta $01
#endif

    lda #10
    jsr screen_clear_row
    lda #11
    jsr screen_clear_row
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
// disk_init_drive — Reinitialize current save drive after swap
// ============================================================
disk_init_drive:
#if C128
    lda #2
    ldx #<disk_init_cmd
    ldy #>disk_init_cmd
    jsr w_setnam
    lda #CMD_CHANNEL
    ldx save_device
    ldy #CMD_CHANNEL
    jsr w_setlfs
    jsr w_open
    bcs !did_close+
    lda #CMD_CHANNEL
    jsr w_close
!did_close:
    jsr w_clrchn
    rts
#else
    jsr disk_kernal_enter
    lda #2
    ldx #<disk_init_cmd
    ldy #>disk_init_cmd
    jsr FEAT_SETNAM
    lda #CMD_CHANNEL
    ldx save_device
    ldy #CMD_CHANNEL
    jsr FEAT_SETLFS
    jsr FEAT_OPEN
    bcs !did_close+
    lda #CMD_CHANNEL
    jsr FEAT_CLOSE
!did_close:
    jsr FEAT_CLRCHN
    jsr disk_kernal_exit
    rts
#endif

// ============================================================
// probe_device — Check whether an IEC device responds
// Input:  X = device number (8-30)
// Output: carry clear = present, carry set = absent
// ============================================================
probe_device:
#if C128
    stx disk_temp

    lda #0
    ldx #0
    ldy #0
    jsr w_setnam
    lda #CMD_CHANNEL
    ldx disk_temp
    ldy #CMD_CHANNEL
    jsr w_setlfs
    jsr w_open
    bcs !pd_absent+
!pd_close:
    lda #CMD_CHANNEL
    jsr w_close
    jsr w_clrchn
    clc
    rts
!pd_absent:
    jsr w_clrchn
    sec
    rts
#else
    stx disk_temp
    jsr disk_kernal_enter

    lda #0
    ldx #0
    ldy #0
    jsr FEAT_SETNAM
    lda #CMD_CHANNEL
    ldx disk_temp
    ldy #CMD_CHANNEL
    jsr FEAT_SETLFS
    jsr FEAT_OPEN
    bcs !pd_absent+
!pd_close:
    lda #CMD_CHANNEL
    jsr FEAT_CLOSE
    jsr FEAT_CLRCHN
    jsr disk_kernal_exit
    clc
    rts
!pd_absent:
    jsr FEAT_CLRCHN
    jsr disk_kernal_exit
    sec
    rts
#endif

// ============================================================
// disk_marker_present — Validate the configured save-disk marker file
// Output: carry clear = valid marker found, carry set = invalid/missing
// ============================================================
disk_marker_present:
#if !C128
    jsr c64_disk_marker_present
    rts
#else
    lda #1
    sta disk_status
    jsr disk_kernal_enter

    lda #disk_marker_read_fname_len
    ldx #<disk_marker_read_fname
    ldy #>disk_marker_read_fname
    jsr KERNAL_SETNAM
    lda #DISK_MARKER_FILE_NUM
    ldx save_device
    ldy #DISK_MARKER_SEC_RD
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    bcs !dmp_done+

    ldx #DISK_MARKER_FILE_NUM
    jsr KERNAL_CHKIN
    bcs !dmp_close+

    lda #0
    sta disk_temp
!dmp_read:
    jsr KERNAL_CHRIN
    ldx disk_temp
    cmp disk_marker_magic,x
    bne !dmp_fail+
    inx
    stx disk_temp
    cpx #DISK_MARKER_MAGIC_LEN
    bcc !dmp_read-
    lda #0
    sta disk_status
    jmp !dmp_close+
!dmp_fail:
    lda #1
    sta disk_status
!dmp_close:
    jsr KERNAL_CLRCHN
    lda #DISK_MARKER_FILE_NUM
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
