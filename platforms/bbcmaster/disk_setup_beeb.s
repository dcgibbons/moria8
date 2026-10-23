#importonce
// disk_setup_beeb.s — BBC Master 128 Disk Setup & Save Disk Media Management
// (linked in StorageOverlay $A800-$BFFF alongside save.s and save_slot_menu.s).
//
// Enforces a separate Save Disk (never saving onto the Program Disk), supports
// both 1-drive swap mode (:0) and 2-drive mode (:0..:3), and initializes
// blank Acorn DFS Save Disks with MORIAID ("M8SAVE").

#import "memory.s"

// ============================================================
// beeb_disk_setup_run / disk_setup_menu — Interactive Disk Setup Modal
// Output: Carry clear = save disk ready, Carry set = cancelled
// ============================================================
beeb_disk_setup_run:
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
    ldx #35
    jsr dsm_put_at

    lda #COL_WHITE
    sta zp_text_color
    lda #<dsm_prog_str
    ldy #>dsm_prog_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #5
    ldx #28
    jsr dsm_put_at

    lda #<dsm_save_str
    ldy #>dsm_save_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #6
    ldx #28
    jsr dsm_put_at
    lda save_device
    sec
    sbc #8
    and #$03
    ora #$30
    jsr hal_screen_put_char

    lda #COL_CYAN
    sta zp_text_color
    lda #<dsm_opt1_str
    ldy #>dsm_opt1_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #9
    ldx #28
    jsr dsm_put_at

    lda #<dsm_opt2_str
    ldy #>dsm_opt2_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #11
    ldx #28
    jsr dsm_put_at

    lda #<dsm_opt3_str
    ldy #>dsm_opt3_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #13
    ldx #28
    jsr dsm_put_at

    lda #<dsm_optq_str
    ldy #>dsm_optq_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #15
    ldx #28
    jsr dsm_put_at

!wait_choice:
    jsr input_get_modal_dismiss_key
    jsr dsm_is_cancel_key
    beq !cancel+
    cmp #$31                // '1' — Same as program (:0 swap)
    beq !select_d0+
    cmp #$32                // '2' — Pick save drive (:0..:3)
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

dsm_orig_save_dev:  .byte 8
dsm_orig_disk_mode: .byte 1

!select_d0:
    lda program_device
    sta save_device
    lda #1
    sta disk_mode
!done_choice:
    jsr beeb_disk_prepare_selected
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
    ldx #28
    jsr dsm_put_at

!wait_drv:
    jsr input_get_modal_dismiss_key
    jsr dsm_is_cancel_key
    beq !redraw_jmp-
    cmp #$30                // '0'..'3' -> :0..:3 (device 8..11)
    bcc !wait_drv-
    cmp #$34
    bcs !wait_drv-
    sec
    sbc #$30
    clc
    adc #8
    sta save_device
    jmp !menu_redraw-

// ============================================================
// beeb_disk_prepare_selected — Validate/Initialize Save Disk
// Output: Carry clear = save disk ready, Carry set = cancelled
// ============================================================
beeb_disk_prepare_selected:
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
    beq !prompt_insert+     // 1-drive swap mode always prompts to swap first

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
    ldx #26
    jsr dsm_put_at
    jsr dsm_wait_any_key
    jsr dsm_is_cancel_key
    beq !prep_cancel+

!check_media:
    lda save_device
    jsr beeb_probe_drive_ready
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
    ldx #27
    jsr dsm_put_at

    lda #<dsm_init_ask_str
    ldy #>dsm_init_ask_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #12
    ldx #26
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
// disk_prompt_save_impl / disk_prompt_game_impl — 1-drive swap prompts
// ============================================================
disk_prompt_save_impl:
    lda disk_mode
    cmp #1
    beq !dps_check+
    clc
    rts
!dps_check:
    jsr disk_require_save_media
    bcs !dps_prompt+
    clc
    rts
!dps_prompt:
    jsr ui_clear_full_screen_safe
    jsr msg_init
    lda #COL_WHITE
    sta zp_text_color
    lda #10
    ldx #32
    lda #<ds_save_str
    ldy #>ds_save_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #10
    jsr dsm_put_at
    jsr dsm_wait_any_key
    jmp !dps_check-

disk_prompt_game_impl:
    lda disk_mode
    cmp #1
    bne !dpg_ok+
!dpg_check:
    jsr disk_require_program_media
    bcc !dpg_ok+
    jsr ui_clear_full_screen_safe
    jsr msg_init
    lda #COL_WHITE
    sta zp_text_color
    lda #<ds_game_str
    ldy #>ds_game_str
    sta zp_ptr0
    sty zp_ptr0_hi
    lda #10
    ldx #30
    jsr dsm_put_at
    jsr dsm_wait_any_key
    jmp !dpg_check-
!dpg_ok:
    clc
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
    ldx #24
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
    ldx #33
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
// Strings
// ============================================================
dsm_title_str:         .text "DISK SETUP" ; .byte 0
dsm_prog_str:          .text "Program: :0" ; .byte 0
dsm_save_str:          .text "Save:    :" ; .byte 0
dsm_opt1_str:          .text "1) Same as program" ; .byte 0
dsm_opt2_str:          .text "2) Pick save drive" ; .byte 0
dsm_opt3_str:          .text "3) Done" ; .byte 0
dsm_optq_str:          .text "Q) Back" ; .byte 0
dsm_pick_str:          .text "Save drive (0-3): " ; .byte 0
dsm_insert_save_str:   .text "Insert a separate Save Disk" ; .byte 0
dsm_prog_disk_err_str: .text "Program disk cannot hold saves." ; .byte 0
dsm_no_marker_str:     .text "No Save Disk marker found." ; .byte 0
dsm_init_ask_str:      .text "Initialize this disk? (Y/N)" ; .byte 0
dsm_init_err_str:      .text "Disk error." ; .byte 0

// ============================================================
// StorageOverlay Helpers for BeebAuxData (Bank 6) & Map (Bank 5) Save/Load
// ============================================================
hal_storage_save_block_mode:
    lda #0
    sta beeb_save_aux_mode_flag

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
    sta beeb_save_aux_mode_flag
!done:
    rts

save_write_map_c128:
save_write_map_banked:
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
    sta beeb_zp_scratch
    clc
    adc save_cksum_lo
    sta save_cksum_lo
    bcc !swm_no_carry+
    inc save_cksum_hi
!swm_no_carry:
    lda beeb_zp_scratch
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
load_read_map_banked:
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
