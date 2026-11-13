#importonce
// LegalOverlay owns one 128-byte disk cache. The platform owns names,
// OS bindings, OPEN validation and any low-resident burst reader.
.const LEGAL_DISK_CHUNK = 128
legal_stream_open:
    lda #0
    sta legal_eof
    sta legal_selected
    sta legal_cache_index
    sta legal_cache_count
#if HAL_STORAGE_LEGAL_COMMAND_STATUS
    lda #3
    sta legal_open_tries
!retry:
#endif
    jsr legal_stream_open_file
    bcs !done+
#if HAL_STORAGE_LEGAL_COMMAND_STATUS
legal_open_status:
    jsr legal_os_read_open_status // C=1: first DOS status byte was lost.
    bcc !answered+
    jsr legal_stream_close
    dec legal_open_tries
    bne !retry-
    sec
    rts
!answered:
    cmp #0
    bne !failed+
    // Closing command channel 15 closes data channels too. Reopen only
    // after a validated status, never CHKIN a file the drive refused.
    jsr legal_stream_close
    jmp legal_stream_open_file
!failed:
    sec
#endif
!done:
    rts

legal_stream_open_file:
    ldx legal_document
    lda legal_filename_len,x
    ldy legal_filename_hi,x
    pha
    lda legal_filename_lo,x
    tax
    pla
    jsr legal_os_setnam
    lda #LEGAL_LFN
    ldx program_device
    ldy #0
    jsr legal_os_setlfs
    lda #1
    sta legal_opened
    jmp legal_os_open

legal_stream_read:
    lda legal_eof
    and #$bf                    // Fatal status is sticky until close/reopen.
    bne !error+
    ldx legal_cache_index
    cpx legal_cache_count
    bcc !cached+
    lda legal_eof
    bne !error+
    ldx #LEGAL_LFN
    jsr legal_os_chkin
    bcs !error+
    inc legal_selected
    jsr legal_os_fill_cache
    sta legal_eof
    stx legal_cache_count
    lda #0
    sta legal_cache_index
    jsr legal_stream_pause
    lda legal_eof
    and #$bf                    // EOI alone is a valid final byte.
    bne !error+                 // Reject the entire failed refill immediately.
    ldx #0
    cpx legal_cache_count
    beq !error+
!cached:
    lda legal_input_cache,x
    inc legal_cache_index
    clc
    rts
!error:
    sec
    rts

#if !HAL_STORAGE_LEGAL_BURST_READ
legal_stream_fill_bytes:
    lda #0
    sta legal_cache_count
!read:
legal_fill_read:
    jsr legal_os_chrin
    pha
legal_fill_status:
    jsr legal_os_readst
    sta legal_eof
    and #$bf
    bne !failed+
    pla
    ldx legal_cache_count
    sta legal_input_cache,x
    inc legal_cache_count
    lda legal_eof
    bne !done+
    ldx legal_cache_count
    cpx #LEGAL_DISK_CHUNK
    bcc !read-
    beq !done+
!failed:
    pla                         // The failed CHRIN byte is never committed.
!done:
    ldx legal_cache_count
    lda legal_eof
    rts
#endif

legal_stream_close:
    lda legal_opened
    beq legal_stream_ok
    jsr legal_os_clrchn
    lda #LEGAL_LFN
    jsr legal_os_close
    lda #0
    sta legal_opened
    sta legal_selected
    sta legal_cache_count
    sta legal_cache_index
legal_stream_ok:
    clc
    rts

// Rendering and keyboard input never run with the file selected as stdin.
legal_stream_pause:
    lda legal_selected
    beq legal_stream_ok
    jsr legal_os_clrchn
    lda #0
    sta legal_selected
    rts
legal_cache_index: .byte 0
legal_cache_count: .byte 0
#if HAL_STORAGE_LEGAL_COMMAND_STATUS
legal_open_tries: .byte 0
#endif
