#importonce
#import "../../shared/legal_entry.s"
// Bank 0 resident below $6000; all code survives the KERNAL transition.
tramp_ui_sysinfo_display:
    lda #1
    bne !store+
tramp_ui_legal_display:
    lda #0
!store:
    sta legal_entry_mode
#if !C128_CARTRIDGE
    beq !prompt_disk+
    lda c128_bank2_flags
    and #C128_BANK2_LEGALUI_BIT
    bne !load+
!prompt_disk:
    jsr disk_prompt_game
    bcc !load+
    rts
#endif
!load:
    :LegalSnapshot()
    lda #0
    sta current_overlay
#if !C128_CARTRIDGE
    lda c128_bank2_flags
    and #C128_BANK2_LEGALUI_BIT
    beq !disk_load+
    lda #>$e000
    ldx #>BANK2_LEGALUI_BASE
    ldy #BANK2_LEGALUI_PAGES
    jsr c128_copy_from_bank2
    bcc !enter+
!disk_load:
#endif
    lda #7
    ldx #<legal_ui_filename
    ldy #>legal_ui_filename
    jsr asset_load_required
!enter:
    jsr tramp_ui_enter
    jsr legal_viewer
!done:
    jmp tramp_ui_exit

// Reuse the resident wrappers which already restore MMU/common RAM/ZP/I.
#if !C128_CARTRIDGE
.label legal_os_setnam = w_setnam
.label legal_os_setlfs = w_setlfs
.label legal_os_open = w_open
.label legal_os_close = w_close
.label legal_os_chkin = w_chkin
.label legal_os_chrin = w_chrin
.label legal_os_readst = w_readst
.label legal_os_clrchn = w_clrchn
#endif

legal_entry_mode: .byte 0
legal_ui_filename: .byte 'L','E','G','A','L','U','I'
#if !C128_CARTRIDGE
legal_notice_filename: .byte 'L','I','C','E','N','S','E',',','S',',','R'
.label legal_notice_filename_len = * - legal_notice_filename
legal_offer_filename: .byte 'S','O','U','R','C','E','-','O','F','F','E','R',',','S',',','R'
.label legal_offer_filename_len = * - legal_offer_filename

.segment LegalOverlay
legal_filename_lo: .byte <legal_notice_filename, <legal_offer_filename
legal_filename_hi: .byte >legal_notice_filename, >legal_offer_filename
legal_filename_len: .byte legal_notice_filename_len, legal_offer_filename_len
legal_os_read_open_status:
    jsr c128_program_read_command_status
    lda c128_program_status_lost
    bne !lost+
    lda disk_diag_readst
    and #$02
    beq !answered+
    lda disk_diag_cmd_status0
    eor #$30
    cmp #10                     // Timeout before the first digit: reopen/retry.
    bcc !answered+
!lost:
    sec
    rts
!answered:
    jsr disk_command_status
    clc
    rts
legal_os_prompt_program_media:
    lda legal_entry_mode
    beq !ok+
    jmp disk_prompt_game
!ok:
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
.assert "Legal burst reader stays below $8000 ExtROM/KERNAL window", legal_os_fill_cache < $8000, true
#endif
