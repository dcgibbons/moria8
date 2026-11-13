#importonce
#import "../shared/legal_entry.s"
// Low resident (< $3000), session-long. No cached Sideways bank is borrowed.
// C=1: optional load cancelled; the caller must not reload a cold owner.
// C=0: viewer completed. The overlay window is invalidated in both cases.
tramp_ui_legal_display:
    :LegalSnapshot()
    lda #0
    sta current_overlay
!load:
    lda #7
    ldx #<legal_ui_filename
    ldy #>legal_ui_filename
    jsr asset_load_retry
    bcc !loaded+
    jsr asset_load_ask_for_disk
    jsr input_is_modal_escape_key
    bne !load-
legal_cancel_restore:
    :LegalRestore()
    sec
legal_cancel_return:
    rts
!loaded:
    jmp legal_viewer

legal_ui_filename: .byte 'L','E','G','A','L','U','I'
legal_notice_filename: .byte 'L','I','C','E','N','S','E',',','S',',','R'
.label legal_notice_filename_len = * - legal_notice_filename
legal_offer_filename: .byte 'S','R','C','O','F','F','R',',','S',',','R'
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

.label legal_os_fill_cache = legal_stream_fill_bytes
