#importonce
#import "../../shared/legal_entry.s"
// Resident entry, session-long; called by title or the Help controller.
tramp_ui_sysinfo_display:
    lda #1
    .byte $2c                   // BIT abs — skip lda #0
tramp_ui_legal_display:
    lda #0
    sta legal_entry_mode
    jsr disk_prompt_game_required
    :LegalSnapshot()
    lda #$36
    sta $01
    cli
    lda #0
    sta current_overlay
    lda #7
    ldx #<legal_ui_filename
    ldy #>legal_ui_filename
    jsr asset_load_required
    sei
    jsr c64_install_ram_irq_vectors
    dec $01                    // Required loader returns $36; expose RAM + I/O ($35).
    jsr legal_viewer
!done:
    jmp tramp_sr_epilogue

legal_entry_mode: .byte 0
legal_ui_filename: .byte 'L','E','G','A','L','U','I'
.label legal_os_setlfs = hal_storage_setlfs
.label legal_os_open = hal_storage_open
.label legal_os_chkin = hal_storage_chkin
.label legal_os_chrin = hal_storage_chrin
.label legal_os_readst = hal_storage_readst
.label legal_os_clrchn = hal_storage_clrchn

#if !C64_CARTRIDGE
.segment LegalOverlay
legal_os_read_open_status:
    ldx program_device
    jsr c64_storage_read_command_status_x
    lda hal_storage_status_lost
    cmp #1                      // C=1 only when the status byte was lost.
    lda disk_status
    rts
.segment Default

.segment LegalOverlay
legal_notice_filename: .byte 'L','I','C','E','N','S','E',',','S',',','R'
.label legal_notice_filename_len = * - legal_notice_filename
legal_offer_filename: .byte 'S','O','U','R','C','E','-','O','F','F','E','R',',','S',',','R'
.label legal_offer_filename_len = * - legal_offer_filename
legal_filename_lo: .byte <legal_notice_filename, <legal_offer_filename
legal_filename_hi: .byte >legal_notice_filename, >legal_offer_filename
legal_filename_len: .byte legal_notice_filename_len, legal_offer_filename_len
// KERNAL OPEN cannot read E000 while ROM is mapped, nor $D700 hidden RAM while
// $01=$36 exposes I/O. Preserve only the BASIC-buffer bytes used by this
// filename in LegalOverlay; no read past its length.
legal_os_setnam:
    sta legal_saved_length
    stx zp_ptr0
    sty zp_ptr0_hi
    tay
    dey
!stage:
    lda PLATFORM_LEGAL_NAME_STAGE_BASE,y
    sta legal_saved_filename,y
    lda (zp_ptr0),y
    sta PLATFORM_LEGAL_NAME_STAGE_BASE,y
    dey
    bpl !stage-
    lda legal_saved_length
    ldx #<PLATFORM_LEGAL_NAME_STAGE_BASE
    ldy #>PLATFORM_LEGAL_NAME_STAGE_BASE
    jmp hal_storage_setnam
legal_os_close:
    jsr hal_storage_close
    ldy legal_saved_length
    dey
!restore:
    lda legal_saved_filename,y
    sta PLATFORM_LEGAL_NAME_STAGE_BASE,y
    dey
    bpl !restore-
    rts
legal_saved_length: .byte 0
legal_saved_filename: .fill 16, 0
.segment Default

.label legal_os_fill_cache = legal_stream_fill_bytes
#endif
