#importonce
// disk_setup_atari.s — Atari 8-bit Disk Setup & Save Disk Media Management
// (linked in HelpOverlay $E000-$EFFF alongside save_slot_menu.s).
//
// Enforces a separate Save Disk (never saving onto the Program Disk), supports
// both 1-drive swap mode (D1:) and 2-drive mode (D2:..D4:), and initializes
// blank DOS 2.5 Save Disks with MORIA8.ID, HISCORE.DAT, and SAVE0..3.SAV.

#import "memory.s"

// ============================================================
// disk_setup_menu — Interactive Disk Setup Modal
// Output: Carry clear = save disk ready, Carry set = cancelled
// ============================================================
disk_setup_menu:
    lda save_device
    sta dsm_orig_save_dev
    lda disk_mode
    sta dsm_orig_disk_mode
!menu_redraw:
    jsr hal_screen_clear

    lda #COL_YELLOW
    sta zp_text_color
    lda #<dsm_title_str
    ldy #>dsm_title_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #2
    ldx #15
    jsr dsm_put_at

    lda #COL_WHITE
    sta zp_text_color
    lda #<dsm_prog_str
    ldy #>dsm_prog_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #5
    ldx #4
    jsr dsm_put_at

    lda #<dsm_save_str
    ldy #>dsm_save_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #6
    ldx #4
    jsr dsm_put_at
    lda save_device
    sec
    sbc #7
    ora #$30
    jsr hal_screen_put_char
    lda #$3a                // ':'
    jsr hal_screen_put_char

    lda #COL_CYAN
    sta zp_text_color
    lda #<dsm_opt1_str
    ldy #>dsm_opt1_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #9
    ldx #4
    jsr dsm_put_at

    lda #<dsm_opt2_str
    ldy #>dsm_opt2_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #11
    ldx #4
    jsr dsm_put_at

    lda #<dsm_opt3_str
    ldy #>dsm_opt3_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #13
    ldx #4
    jsr dsm_put_at

    lda #<dsm_optq_str
    ldy #>dsm_optq_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #15
    ldx #4
    jsr dsm_put_at

!wait_choice:
    jsr input_get_modal_dismiss_key
    jsr dsm_is_cancel_key
    beq !cancel+
    cmp #$31                // '1' — Same as program (D1:)
    beq !select_d1+
    cmp #$32                // '2' — Pick save drive (D1:..D4:)
    beq !pick_drive+
    cmp #$33                // '3' — Done
    beq !done_choice+
    jmp !wait_choice-

!cancel:
    lda dsm_orig_save_dev
    sta save_device
    lda dsm_orig_disk_mode
    sta disk_mode
    sec
    rts

dsm_orig_save_dev:  .byte 0
dsm_orig_disk_mode: .byte 0

!select_d1:
    lda program_device
    sta save_device
    lda #1
    sta disk_mode
!done_choice:
    jsr disk_prepare_selected_save_media
    bcc !dsm_ok+
!redraw_jmp:
    jmp !menu_redraw-
!dsm_ok:
    clc
    rts

!pick_drive:
    lda #COL_YELLOW
    sta zp_text_color
    lda #<dsm_pick_str
    ldy #>dsm_pick_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #18
    ldx #4
    jsr dsm_put_at

!wait_drv:
    jsr input_get_modal_dismiss_key
    jsr dsm_is_cancel_key
    beq !redraw_jmp-
    cmp #$31
    bcc !wait_drv-
    cmp #$35
    bcs !wait_drv-
    sec
    sbc #$31
    clc
    adc #8                  // '1'..'4' -> device 8..11 (D1:..D4:)
    sta save_device
    jmp !menu_redraw-

// ============================================================
// disk_prepare_selected_save_media — Validate/Initialize Save Disk
// Output: Carry clear = save disk ready, Carry set = cancelled
// ============================================================
disk_prepare_selected_save_media:
    lda save_device
    sta disk_prompt_device
    ldx #2
    cmp program_device
    bne !set_mode+
    ldx #1
!set_mode:
    stx disk_mode
    cpx #1
    beq !prompt_insert+     // 1-drive mode always prompts to swap first

    // 2-drive mode: check if an initialized Save Disk is already in save_device
    jmp !check_media+

!prompt_insert:
    jsr hal_screen_clear
    lda #COL_WHITE
    sta zp_text_color
    lda #<dsm_insert_save_str
    ldy #>dsm_insert_save_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #10
    ldx #6
    jsr dsm_put_at
    jsr dsm_wait_any_key
    jsr dsm_is_cancel_key
    beq !prep_cancel+

!check_media:
    ldx save_device
    jsr hal_storage_probe_media
    bcc !check_not_prog+
    lda #<save_drive_not_ready_str
    ldy #>save_drive_not_ready_str
    jsr dsm_show_error
    beq !prep_cancel+
    jmp !prompt_insert-

!check_not_prog:
    jsr disk_program_media_present
    bcs !check_marker+
    // Program Disk detected! Reject saving onto the Program Disk.
    lda #<dsm_prog_disk_err_str
    ldy #>dsm_prog_disk_err_str
    jsr dsm_show_error
    beq !prep_cancel+
    jmp !prompt_insert-

!check_marker:
    jsr disk_marker_present
    bcc !media_ready+

    // Unmarked disk: prompt to initialize it as a Save Disk
    jsr hal_screen_clear
    lda #COL_WHITE
    sta zp_text_color
    lda #<dsm_no_marker_str
    ldy #>dsm_no_marker_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #10
    ldx #7
    jsr dsm_put_at

    lda #<dsm_init_ask_str
    ldy #>dsm_init_ask_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #12
    ldx #6
    jsr dsm_put_at

!wait_yn:
    jsr input_get_modal_dismiss_key
    cmp #$59                // 'Y'
    beq !do_init+
    cmp #$4e                // 'N'
    beq !prep_cancel+
    jsr dsm_is_cancel_key
    beq !prep_cancel+
    jmp !wait_yn-

!do_init:
    lda save_device
    sta disk_prompt_device
    jsr disk_marker_init
    bcc !media_ready+
    lda #<dsm_init_err_str
    ldy #>dsm_init_err_str
    jsr dsm_show_error
!prep_cancel:
    sec
    rts

!media_ready:
    ldx #1
    lda disk_mode
    cmp #1
    bne !store_done+
    ldx #2
!store_done:
    stx disk_setup_done
    jsr hal_screen_clear
    clc
    rts

// ============================================================
// disk_marker_init — Format/Initialize DOS 2.5 Save Disk on disk_prompt_device
// Refuses to touch any disk containing TITLE.DAT.
// Output: Carry clear = ready, Carry set = error
// ============================================================
disk_marker_init:
    ldx disk_prompt_device
    jsr hal_storage_probe_media
    bcs !init_fail+
    lda disk_prompt_device
    jsr disk_program_media_present_on_device
    bcc !init_fail+         // Refuse to overwrite Program Disk!

    lda disk_prompt_device
    sta atari_io_device

    // 1. Zero sio_sector_buf and write empty start sectors + Dir sector 362
    jsr dsm_zero_sio_buf
    ldy #5
!empty_loop:
    sty stream_tmp_y
    ldx init_empty_sec_lo,y
    lda init_empty_sec_hi,y
    tay
    jsr atari_write_sio_sector
    bcs !init_fail+
    ldy stream_tmp_y
    dey
    bpl !empty_loop-

    // 2. Write Sector 4 (MORIA8.ID = "M8SAVE", $7D = 6)
    ldx #hal_storage_marker_magic_len - 1
!cp_magic:
    lda hal_storage_marker_magic,x
    sta sio_sector_buf,x
    dex
    bpl !cp_magic-
    lda #hal_storage_marker_magic_len
    sta sio_sector_buf + DOS25_LINK_BYTES
    ldx #4
    ldy #0
    jsr atari_write_sio_sector
    bcs !init_fail+

    // 3. Write Sector 360 ($0168, DOS 2.5 VTOC)
    jsr dsm_zero_sio_buf
    ldx #4
!cp_vtoc:
    lda init_vtoc_head,x
    sta sio_sector_buf,x
    dex
    bpl !cp_vtoc-
    ldx #<360
    ldy #>360
    jsr atari_write_sio_sector
    bcs !init_fail+

    // 4. Write Sector 361 ($0169, DOS 2.5 Directory with 6 entries)
    jsr dsm_zero_sio_buf
    ldx #95
!cp_dir:
    lda save_disk_dir_table,x
    sta sio_sector_buf,x
    dex
    bpl !cp_dir-
    ldx #<361
    ldy #>361
    jsr atari_write_sio_sector
    bcs !init_fail+

    lda #HAL_STORAGE_STATUS_OK
    sta stream_last_status
    lda #0
    sta disk_status
    clc
    rts

!init_fail:
    lda #HAL_STORAGE_STATUS_UNKNOWN
    sta stream_last_status
    sec
    rts

dsm_zero_sio_buf:
    ldx #127
    lda #0
!zloop:
    sta sio_sector_buf,x
    dex
    bpl !zloop-
    rts

// ============================================================
// UI Helpers
// ============================================================
dsm_put_at:
    sta zp_cursor_row
    stx zp_cursor_col
    jmp hal_screen_put_string

dsm_show_error:
    sta zp_ptr0
    sty zp_ptr0_hi
    jsr hal_screen_clear
    lda #COL_LRED
    sta zp_text_color
    lda #10
    ldx #4
    jsr dsm_put_at
    jsr dsm_wait_any_key
    jmp dsm_is_cancel_key

dsm_wait_any_key:
    lda #COL_WHITE
    sta zp_text_color
    lda #<press_key_str
    ldy #>press_key_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #12
    ldx #13
    jsr dsm_put_at
    jmp input_get_modal_dismiss_key

dsm_is_cancel_key:
    cmp #$51                // 'Q'
    beq !yes+
    cmp #$1b                // ESC
    beq !yes+
    cmp #$03                // RUN/STOP
!yes:
    rts

// ============================================================
// Save Disk Format Tables & Strings
// ============================================================
init_empty_sec_lo:
    .byte 5, 7, 63, 119, 175, <362
init_empty_sec_hi:
    .byte 0, 0, 0, 0, 0, >362

init_vtoc_head:
    .byte $02, <707, >707, <480, >480

save_disk_dir_table:
    .byte $42, 1,  0, 4,   0, 'M','O','R','I','A','8',' ',' ','I','D',' '
    .byte $42, 2,  0, 5,   0, 'H','I','S','C','O','R','E',' ','D','A','T'
    .byte $42, 56, 0, 7,   0, 'S','A','V','E','0',' ',' ',' ','S','A','V'
    .byte $42, 56, 0, 63,  0, 'S','A','V','E','1',' ',' ',' ','S','A','V'
    .byte $42, 56, 0, 119, 0, 'S','A','V','E','2',' ',' ',' ','S','A','V'
    .byte $42, 56, 0, 175, 0, 'S','A','V','E','3',' ',' ',' ','S','A','V'

dsm_title_str:         .text "DISK SETUP" ; .byte 0
dsm_prog_str:          .text "Program: D1:" ; .byte 0
dsm_save_str:          .text "Save:    D" ; .byte 0
dsm_opt1_str:          .text "1) Same as program" ; .byte 0
dsm_opt2_str:          .text "2) Pick save drive" ; .byte 0
dsm_opt3_str:          .text "3) Done" ; .byte 0
dsm_optq_str:          .text "Q) Back" ; .byte 0
dsm_pick_str:          .text "Save drive (1-4): " ; .byte 0
dsm_insert_save_str:   .text "Insert a separate Save Disk" ; .byte 0
dsm_prog_disk_err_str: .text "Program disk cannot hold saves." ; .byte 0
dsm_no_marker_str:     .text "No Save Disk marker found." ; .byte 0
dsm_init_ask_str:      .text "Initialize this disk? (Y/N)" ; .byte 0
dsm_init_err_str:      .text "Disk error." ; .byte 0
