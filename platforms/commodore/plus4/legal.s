#importonce
#import "../../shared/legal_entry.s"
// Resident entry. LegalOverlay remains cold; cached Help is not modified.
tramp_ui_legal_display:
    jsr disk_prompt_game_required
    :LegalSnapshot()
    lda #0
    sta current_overlay
    lda #7
    ldx #<legal_ui_filename
    ldy #>legal_ui_filename
    jsr asset_load_required
    sei
    jsr plus4_install_ram_irq_vectors
    jsr plus4_bank_ram
    jsr legal_viewer
!done:
    jmp tramp_sr_epilogue

legal_ui_filename: .byte 'L','E','G','A','L','U','I'
legal_notice_filename: .byte 'L','I','C','E','N','S','E',',','S',',','R'
.label legal_notice_filename_len = * - legal_notice_filename
legal_offer_filename: .byte 'S','O','U','R','C','E','-','O','F','F','E','R',',','S',',','R'
.label legal_offer_filename_len = * - legal_offer_filename
legal_filename_lo: .byte <legal_notice_filename, <legal_offer_filename
legal_filename_hi: .byte >legal_notice_filename, >legal_offer_filename
legal_filename_len: .byte legal_notice_filename_len, legal_offer_filename_len
.label legal_os_setnam = hal_storage_setnam
.label legal_os_setlfs = hal_storage_setlfs
.label legal_os_open = hal_storage_open
.label legal_os_close = hal_storage_close
.label legal_os_chkin = hal_storage_chkin
.label legal_os_chrin = hal_storage_chrin
.label legal_os_readst = hal_storage_readst
.label legal_os_clrchn = hal_storage_clrchn

.segment LegalOverlay
legal_os_read_open_status:
    lda program_device
    sta disk_prompt_device
    jsr hal_storage_read_command_status
    lda hal_storage_status_lost
    cmp #1                      // C=1 only when the status byte was lost.
    lda disk_status
    rts
.segment Default

.label legal_os_fill_cache = legal_stream_fill_bytes
