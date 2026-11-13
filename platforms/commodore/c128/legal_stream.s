#importonce

// C128 Magic Desk 128 LegalOverlay-only ROM stream ($E000-$E5FF).
// Calls cart_read in Bank 0 Default (< $6000), which bounces 256-byte chunks
// from Bank 0..15 ROM into Bank 0 legal_input_cache ($E700) via bottom-common RAM.

legal_stream_open:
    lda #0
    sta legal_cart_offset
    sta legal_cart_offset + 1
    sta legal_cart_index
    sta legal_opened
    sta legal_eof
    lda legal_document
    clc
    adc #CART_ASSET_LEGAL_NOTICE
    sta legal_cart_asset
    clc
    rts

legal_stream_read:
    lda legal_cart_index
    bne !buffered+
    lda legal_cart_offset + 1
    cmp #$80
    bcs !error+
    lda legal_cart_offset
    sta cart_offset
    lda legal_cart_offset + 1
    sta cart_offset + 1
    lda #2
    sta cart_is_legal
    lda legal_cart_asset
    jsr cart_read
    bcs !error+
    inc legal_cart_offset + 1
!buffered:
    ldx legal_cart_index
    lda legal_input_cache,x
    inc legal_cart_index
    cmp #0
    bne !read+
    lda #$40
    sta legal_eof
    sec
    rts
!read:
    clc
    rts
!error:
    sec
    rts

legal_stream_pause:
legal_stream_close:
    rts

legal_cart_offset: .word 0
legal_cart_index:  .byte 0
legal_cart_asset:  .byte 0
