#importonce
#import "../../shared/legal_entry.s"
// Bank 0 resident below $6000; all code survives the KERNAL transition.
tramp_ui_legal_display:
    jsr disk_prompt_game
    bcc !load+
    rts
!load:
    :LegalSnapshot()
    lda #0
    sta current_overlay
    lda #7
    ldx #<legal_ui_filename
    ldy #>legal_ui_filename
    jsr asset_load_required
    jsr tramp_ui_enter
    jsr legal_viewer
!done:
    jmp tramp_ui_exit

// Reuse the resident wrappers which already restore MMU/common RAM/ZP/I.
.label legal_os_setnam = w_setnam
.label legal_os_setlfs = w_setlfs
.label legal_os_open = w_open
.label legal_os_close = w_close
.label legal_os_chkin = w_chkin
.label legal_os_chrin = w_chrin
.label legal_os_readst = w_readst
.label legal_os_clrchn = w_clrchn

legal_ui_filename: .byte 'L','E','G','A','L','U','I'
legal_notice_filename: .byte 'L','I','C','E','N','S','E',',','S',',','R'
.label legal_notice_filename_len = * - legal_notice_filename
legal_offer_filename: .byte 'S','O','U','R','C','E','-','O','F','F','E','R',',','S',',','R'
.label legal_offer_filename_len = * - legal_offer_filename
legal_filename_lo: .byte <legal_notice_filename, <legal_offer_filename
legal_filename_hi: .byte >legal_notice_filename, >legal_offer_filename
legal_filename_len: .byte legal_notice_filename_len, legal_offer_filename_len

.segment LegalOverlay
legal_os_read_open_status:
    jsr c128_program_read_command_status
    lda disk_diag_readst
    and #$02
    beq !answered+
    lda disk_diag_cmd_status0
    eor #$30
    cmp #10                     // Timeout before the first digit: reopen/retry.
    bcc !answered+
    sec
    rts
!answered:
    jsr disk_command_status
    clc
    rts
.segment Default

// Low resident code remains executable with KERNAL visible. Writes pass
// through ROM to Bank 0 E700; no overlay instruction executes in OS mode.
legal_os_fill_cache:
    php
    :EnterKernal()
    lda #0
    sta legal_chunk_count
!read:
legal_fill_read:
    jsr $ffcf
    pha
legal_fill_status:
    jsr $ffb7
    sta legal_chunk_status
    and #$bf
    bne !failed+
    pla
    ldx legal_chunk_count
    sta legal_input_cache,x
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
    :ExitKernal()
    plp
    ldx legal_chunk_count
    lda legal_chunk_status
    rts
legal_chunk_count: .byte 0
legal_chunk_status: .byte 0
.assert "Legal burst reader stays visible under KERNAL", legal_os_fill_cache < $6000, true
