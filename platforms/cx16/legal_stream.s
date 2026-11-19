#importonce
// Commander X16 Cartridge legal document stream (Bank 23 LegalOverlay).
// Reads 128-byte chunks directly from Cart ROM via cart_read into legal_input_cache.

.const LEGAL_ROM_CHUNK = 128

legal_stream_open:
    ldx legal_document
    cpx #2
    bcc !valid+
    sec
    rts
!valid:
    lda legal_rom_assets,x
    sta legal_rom_asset
    lda #0
    sta legal_rom_off_lo
    sta legal_rom_off_hi
    sta legal_cache_index
    sta legal_cache_count
    sta legal_eof
    lda #1
    sta legal_opened
    clc
    rts

legal_stream_read:
    ldx legal_cache_index
    cpx legal_cache_count
    bcc !cached+
    lda legal_rom_asset
    sta cart_asset_id
    lda legal_rom_off_lo
    sta cart_offset_lo
    lda legal_rom_off_hi
    sta cart_offset_hi
    lda #<legal_input_cache
    sta cart_dest_lo
    lda #>legal_input_cache
    sta cart_dest_hi
    lda #LEGAL_ROM_CHUNK
    sta cart_count_lo
    lda #0
    sta cart_count_hi
    lda #2
    sta cart_is_record
    jsr cart_read
    bcs !eof+
    cmp #0
    beq !eof+
    sta legal_cache_count
    lda #0
    sta legal_cache_index
    lda legal_rom_off_lo
    clc
    adc legal_cache_count
    sta legal_rom_off_lo
    bcc !cached+
    inc legal_rom_off_hi
!cached:
    ldx legal_cache_index
    lda legal_input_cache,x
    inc legal_cache_index
    clc
    rts
!eof:
    lda #$40
    sta legal_eof
    sec
    rts

legal_stream_pause:
    rts

legal_stream_close:
    lda #0
    sta legal_opened
    sta legal_cache_index
    sta legal_cache_count
    clc
    rts

legal_rom_assets:
    .byte CART_ASSET_LICENSE, CART_ASSET_SOURCE_OFFER
legal_rom_asset:   .byte 0
legal_rom_off_lo:  .byte 0
legal_rom_off_hi:  .byte 0
legal_cache_index: .byte 0
legal_cache_count: .byte 0
