#importonce
// Commander X16 Cartridge ROM asset loader and bounded reader (resident < $9B00).
// Switches CX16_ROM_BANK_REG ($01) to Cart ROM Banks 32+ and copies directly
// into fixed low RAM or banked RAM ($A000-$BFFF via $00), restoring $00, $01, and P.

#import "cartridge_contract.s"

// cart_load_asset — Load asset A (0..CART_ASSET_COUNT-1) to its descriptor
// target RAM bank and address. Returns C=0 on success, C=1 on invalid asset ID.
cart_load_asset:
    cmp #CART_ASSET_COUNT
    bcc !valid+
    sec
    rts
!valid:
    php
    sei
    ldx CX16_RAM_BANK_REG
    phx
    ldx CX16_ROM_BANK_REG
    phx
    jsr cart_read_descriptor
    lda cart_desc_tmp + CART_DESC_BANK
    sta cart_cur_bank
    lda cart_desc_tmp + CART_DESC_ROM_LO
    sta cart_copy_src + 1
    lda cart_desc_tmp + CART_DESC_ROM_HI
    sta cart_copy_src + 2
    lda cart_desc_tmp + CART_DESC_DEST_LO
    sta cart_copy_dst + 1
    lda cart_desc_tmp + CART_DESC_DEST_HI
    sta cart_copy_dst + 2
    lda cart_desc_tmp + CART_DESC_SIZE_LO
    sta cart_rem_lo
    lda cart_desc_tmp + CART_DESC_SIZE_HI
    sta cart_rem_hi
    lda cart_desc_tmp + CART_DESC_RAM_BANK
    cmp #CART_RAM_BANK_NONE
    beq !keep_ram_bank+
    sta CX16_RAM_BANK_REG
!keep_ram_bank:
    lda cart_cur_bank
    sta CX16_ROM_BANK_REG
    jsr cart_copy_loop
    plx
    stx CX16_ROM_BANK_REG
    plx
    stx CX16_RAM_BANK_REG
    plp
    clc
    rts

// cart_read — Read up to cart_count bytes from cart_asset_id at cart_offset into
// cart_dest (within caller's active RAM bank $00).
//   cart_is_record = 0: strict raw read (rejects offset+count > size with C=1)
//   cart_is_record = 2: legal chunk read (clamps to remaining size; A=0, C=1 at EOF)
// Returns A = actual byte count copied (low byte), C=0 on success, C=1 on error/EOF.
cart_read:
    lda cart_asset_id
    cmp #CART_ASSET_COUNT
    bcc !valid_id+
    lda #0
    sta cart_actual_lo
    sta cart_actual_hi
    sec
    rts
!valid_id:
    php
    sei
    ldx CX16_RAM_BANK_REG
    phx
    ldx CX16_ROM_BANK_REG
    phx
    lda cart_asset_id
    jsr cart_read_descriptor
    // Check zero-length request before touching destination.
    lda cart_count_lo
    ora cart_count_hi
    bne !nonzero_req+
    lda cart_is_record
    cmp #2
    beq !check_avail+
    lda #0
    sta cart_actual_lo
    sta cart_actual_hi
    jmp !ok_restore+
!nonzero_req:
!check_avail:
    // avail = desc_size - cart_offset
    lda cart_desc_tmp + CART_DESC_SIZE_LO
    sec
    sbc cart_offset_lo
    sta cart_avail_lo
    lda cart_desc_tmp + CART_DESC_SIZE_HI
    sbc cart_offset_hi
    sta cart_avail_hi
    bcs !+
    jmp !eof_or_oob+
!:
    lda cart_avail_lo
    ora cart_avail_hi
    bne !+
    jmp !eof_or_oob+
!:
    // Compare avail vs cart_count (if cart_count > avail, clamp or reject).
    lda cart_avail_lo
    cmp cart_count_lo
    lda cart_avail_hi
    sbc cart_count_hi
    bcs !use_requested+
    lda cart_is_record
    cmp #2
    beq !+
    jmp !eof_or_oob+
!:
    lda cart_avail_lo
    sta cart_rem_lo
    lda cart_avail_hi
    sta cart_rem_hi
    bra !have_len+
!use_requested:
    lda cart_count_lo
    sta cart_rem_lo
    lda cart_count_hi
    sta cart_rem_hi
!have_len:
    lda cart_rem_lo
    sta cart_actual_lo
    lda cart_rem_hi
    sta cart_actual_hi
    ora cart_actual_lo
    beq !ok_restore+
    // Normalize ROM source (desc_bank, desc_rom) + cart_offset across 16 KB banks.
    lda cart_desc_tmp + CART_DESC_BANK
    sta cart_cur_bank
    lda cart_desc_tmp + CART_DESC_ROM_HI
    sec
    sbc #>CART_ROM_WINDOW_BASE
    sta cart_avail_hi
    lda cart_desc_tmp + CART_DESC_ROM_LO
    clc
    adc cart_offset_lo
    sta cart_copy_src + 1
    lda cart_avail_hi
    adc cart_offset_hi
    bcc !norm_bank+
    inc cart_cur_bank
    inc cart_cur_bank
    inc cart_cur_bank
    inc cart_cur_bank
!norm_bank:
    cmp #$40
    bcc !bank_ready+
    sec
    sbc #$40
    inc cart_cur_bank
    bra !norm_bank-
!bank_ready:
    clc
    adc #>CART_ROM_WINDOW_BASE
    sta cart_copy_src + 2
    lda cart_dest_lo
    sta cart_copy_dst + 1
    lda cart_dest_hi
    sta cart_copy_dst + 2
    lda cart_cur_bank
    sta CX16_ROM_BANK_REG
    jsr cart_copy_loop
!ok_restore:
    plx
    stx CX16_ROM_BANK_REG
    plx
    stx CX16_RAM_BANK_REG
    plp
    lda cart_actual_lo
    clc
    rts
!eof_or_oob:
    lda #0
    sta cart_actual_lo
    sta cart_actual_hi
    plx
    stx CX16_ROM_BANK_REG
    plx
    stx CX16_RAM_BANK_REG
    plp
    lda #0
    sec
    rts

// Reads 8-byte descriptor for asset A into cart_desc_tmp. Leaves $01 = 32.
cart_read_descriptor:
    asl
    asl
    asl
    tax
    lda #CART_ROM_BANK_START
    sta CX16_ROM_BANK_REG
    ldy #0
!rd_desc:
    lda CART_DIRECTORY,x
    sta cart_desc_tmp,y
    inx
    iny
    cpy #CART_DESCRIPTOR_SIZE
    bne !rd_desc-
    rts

cart_copy_loop:
    lda cart_rem_lo
    ora cart_rem_hi
    beq !copy_done+
cart_copy_src:
    lda $ffff
cart_copy_dst:
    sta $ffff
    inc cart_copy_src + 1
    bne !+
    inc cart_copy_src + 2
    bne !+
    lda #>CART_ROM_WINDOW_BASE
    sta cart_copy_src + 2
    inc CX16_ROM_BANK_REG
!:
    inc cart_copy_dst + 1
    bne !+
    inc cart_copy_dst + 2
!:
    lda cart_rem_lo
    bne !+
    dec cart_rem_hi
!:
    dec cart_rem_lo
    bra cart_copy_loop
!copy_done:
    rts

// cart_load_prg — Load LEGALUI PRG from Cart ROM (the only non-preloaded asset
// routed through hal_asset_load_prg_header; overlays switch via Bank 9-20).
// Input: A = filename length, X = filename lo, Y = filename hi.
// Output: C=0 on success, C=1 if unknown.
cart_load_prg:
    cmp #7
    bne !not_found+
    stx !cmp+ + 1
    sty !cmp+ + 2
    ldy #6
!cmp:
    lda $ffff,y
    cmp cart_name_legalui,y
    bne !not_found+
    dey
    bpl !cmp-
    lda #CART_ASSET_LEGALUI
    jmp cart_load_asset
!not_found:
    sec
    rts

cart_name_legalui: .byte 'L','E','G','A','L','U','I'

cart_asset_id:   .byte 0
cart_offset_lo:  .byte 0
cart_offset_hi:  .byte 0
cart_dest_lo:    .byte 0
cart_dest_hi:    .byte 0
cart_count_lo:   .byte 0
cart_count_hi:   .byte 0
cart_is_record:  .byte 0
cart_actual_lo:  .byte 0
cart_actual_hi:  .byte 0
cart_cur_bank:   .byte 0
cart_rem_lo:     .byte 0
cart_rem_hi:     .byte 0
cart_avail_lo:   .byte 0
cart_avail_hi:   .byte 0
cart_desc_tmp:   .fill CART_DESCRIPTOR_SIZE, 0
