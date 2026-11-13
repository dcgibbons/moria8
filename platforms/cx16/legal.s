#importonce
#import "../shared/legal_entry.s"
.const CX16_BANK_LEGAL = 23
.assert "Legal bank follows catalog and fits RAM", CX16_BANK_LEGAL > CX16_BANK_CATALOG && CX16_BANK_LEGAL < 64, true
// Resident entry; Bank 23 is temporary for one modal, never boot-preloaded.
tramp_ui_legal_display:
    lda CX16_RAM_BANK_REG
    pha
    lda #CX16_BANK_LEGAL
    sta CX16_RAM_BANK_REG
    :LegalSnapshot()
    lda #7
    ldx #<legal_ui_filename
    ldy #>legal_ui_filename
    jsr asset_load_required
    jsr legal_viewer
!done:
    pla
    sta CX16_RAM_BANK_REG
    rts

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

// One Bank 0 interval per chunk, rather than two bank flips per byte.
// The existing row stage is idle during this modal; cache belongs to Bank 23.
legal_os_fill_cache:
    lda CX16_ROM_BANK_REG
    pha
    lda CX16_RAM_BANK_REG
    pha
    stz CX16_RAM_BANK_REG
    stz CX16_ROM_BANK_REG
    stz legal_chunk_count
!read:
legal_fill_read:
    jsr KERNAL_CHRIN
    pha
legal_fill_status:
    jsr KERNAL_READST
    sta legal_chunk_status
    and #$bf
    bne !failed+
    pla
    ldx legal_chunk_count
    sta CX16_ROW_STAGE_BASE,x
    inc legal_chunk_count
    lda legal_chunk_status
    bne !done+
    lda legal_chunk_count
    cmp #128
    bcc !read-
    beq !done+
!failed:
    pla                         // Discard failed data; return its status.
!done:
    pla
    sta CX16_RAM_BANK_REG
    ldx #0
    lda legal_chunk_count
    beq !copied+
!copy:
    lda CX16_ROW_STAGE_BASE,x
    sta legal_input_cache,x
    inx
    cpx legal_chunk_count
    bcc !copy-
!copied:
    pla
    sta CX16_ROM_BANK_REG
    lda legal_chunk_status
    rts
legal_chunk_count: .byte 0
legal_chunk_status: .byte 0
.assert "Legal burst reader stays outside banked RAM", legal_os_fill_cache < $9b00, true
