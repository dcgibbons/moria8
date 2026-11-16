#importonce
#import "cartridge_contract.s"

// Magic Desk 128 ROM reader (Default RAM < $8000, Bank 0).
// Descriptor table at Bank 0 $8100 (CART_DIRECTORY) holds 8-byte entries:
//   [0] bank (0..15), [1..2] source ($8000-$BFFF), [3..4] dest, [5..6] length, [7] dest_flags
// All ROM reads and Bank 0 / Bank 1 / $F000-$FFFB RAM writes bounce through
// bottom-common mmu_common_cart_copy_chunk ($0C06+) so caller/destination code
// in $8000-$FFFF or Bank 1 never disappears mid-transfer.

cart_reader_start:
cart_load_asset:
    ldx #0
    stx cart_offset
    stx cart_offset + 1
    stx cart_is_legal
    jmp cart_read

cart_load_title:
    lda #CART_ASSET_TITLE
    jmp cart_load_asset

cart_read:
    tay
    ldx #0
    stx cart_read_error
    // Preserve zp_ptr0 / zp_ptr1 across transfer
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha
    lda zp_ptr1
    pha
    lda zp_ptr1_hi
    pha

    tya
    asl
    asl
    asl
    tax

    // Fetch 8-byte descriptor from Bank 0 $8100 under $FF00 = $3A (Default < $8000 stays visible)
    php
    sei
    lda MMU_CR
    pha
    lda #MMU_EXT_ROM_IO
    sta MMU_CR
    lda #0
    sta CART_REG_BANK
    ldy #0
!desc:
    lda CART_DIRECTORY,x
    sta cart_desc_buf,y
    inx
    iny
    cpy #CART_DESCRIPTOR_SIZE
    bne !desc-
    pla
    sta MMU_CR
    plp

    lda cart_desc_buf + 0
    sta cart_bank
    lda cart_desc_buf + 1
    clc
    adc cart_offset
    sta zp_ptr0
    lda cart_desc_buf + 2
    and #$3f                        // 0-based page ($00..$3F) within 16 KB bank; preserves C
    adc cart_offset + 1
    bcc !norm+
    // Sum wrapped past $FF pages ($100 pages = 4 x 16 KB banks); A is in $00..$3F.
    ldx cart_bank
    inx
    inx
    inx
    inx
    stx cart_bank
    clc
!norm:
    cmp #$40
    bcc !src_ok+
    sbc #$40                        // C=1 from cmp; advance 16 KB ROM bank
    inc cart_bank
    bcs !norm-                      // C stays 1 across inc; loops at most 3 times
!src_ok:
    clc
    adc #$80                        // restore $8000-$BFFF External Function ROM base
    sta zp_ptr0_hi
    lda cart_desc_buf + 3
    sta zp_ptr1
    lda cart_desc_buf + 4
    sta zp_ptr1_hi
    lda cart_desc_buf + 5
    sta cart_count
    lda cart_desc_buf + 6
    sta cart_count + 1

    // Map descriptor flag byte -> (dst_mmu, dst_d506)
    lda #$0d
    ldy #MMU_ALL_RAM
    ldx cart_desc_buf + 7
    beq !flags_set+
    ldy #MMU_RAM_BANK1
    cpx #CART_DEST_BANK1
    beq !flags_set+
    ldy #MMU_RAM_BANK1_NOIO
    cpx #CART_DEST_BANK1_NOIO
    beq !flags_set+
    ldy #MMU_RAM_BANK1
    lda #$05                        // CART_DEST_BANK1_TOP_OFF: expose physical Bank 1 $F000-$FFFB
!flags_set:
    sta mmu_common_cart_dst_d506
    sty mmu_common_cart_dst_mmu

    lda cart_is_legal
    beq !copy_prep+
    // Document reads are page-aligned into legal_input_cache ($E700, Bank 0)
    lda cart_offset
    bne !legal_bad+
    lda cart_count
    bne !legal_bad+
    lda cart_offset + 1
    cmp cart_count + 1
    bcc !legal_ok+
!legal_bad:
    inc cart_read_error
    lda #0
    sta cart_count
    sta cart_count + 1
    jmp !done+
!legal_ok:
    lda #<legal_input_cache
    sta zp_ptr1
    lda #>legal_input_cache
    sta zp_ptr1_hi
    lda #0
    sta cart_count
    lda #1
    sta cart_count + 1
    lda #$0d
    sta mmu_common_cart_dst_d506
    lda #MMU_ALL_RAM
    sta mmu_common_cart_dst_mmu

!copy_prep:
    lda cart_bank
    sta mmu_common_cart_bank

!chunk_loop:
    lda cart_count + 1
    bne !full_chunk+
    lda cart_count
    bne !partial_chunk+
    jmp !done+
!partial_chunk:
    cmp #MMU_COMMON_CART_CHUNK_MAX
    bcs !full_chunk+
    tax
    bne !clamp_page+
!full_chunk:
    ldx #MMU_COMMON_CART_CHUNK_MAX
!clamp_page:
    // Clamp chunk so zp_ptr0 never crosses a page boundary inside common helper
    lda zp_ptr0
    cmp #$100 - MMU_COMMON_CART_CHUNK_MAX + 1
    bcc !do_chunk+
    eor #$ff
    clc
    adc #1                          // bytes remaining in current page (1..15)
    sta cart_chunk_tmp
    txa
    cmp cart_chunk_tmp
    bcc !do_chunk+
    ldx cart_chunk_tmp
!do_chunk:
    stx cart_chunk_tmp
    jsr mmu_common_cart_copy_chunk

    // Advance cart_count -= chunk
    lda cart_count
    sec
    sbc cart_chunk_tmp
    sta cart_count
    bcs !adv_dst+
    dec cart_count + 1
!adv_dst:
    lda zp_ptr1
    clc
    adc cart_chunk_tmp
    sta zp_ptr1
    bcc !adv_src+
    inc zp_ptr1_hi
!adv_src:
    lda zp_ptr0
    clc
    adc cart_chunk_tmp
    sta zp_ptr0
    bne !chunk_loop-
    inc zp_ptr0_hi
    lda zp_ptr0_hi
    cmp #$c0
    bne !chunk_loop-
    lda #$80
    sta zp_ptr0_hi
    inc mmu_common_cart_bank
    bne !chunk_loop-

!done:
    pla
    sta zp_ptr1_hi
    pla
    sta zp_ptr1
    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    lda cart_read_error
    beq !ok+
    sec
    rts
!ok:
    clc
    rts

// PRG HAL adapter: resolve LEGALUI and ovl.* filenames from caller (even above $8000)
// Input: A = filename len, X = lo, Y = hi
cart_load_prg:
    stx cart_legal_name_read + 1
    sty cart_legal_name_read + 2
    stx cart_name_read + 1
    sty cart_name_read + 2
    sta cart_name_len
    cmp #7
    bne !overlays+
    ldy #0
!legal_name:
cart_legal_name_read:
    lda $ffff,y
    cmp legal_ui_filename,y
    bne !overlays+
    iny
    cpy #7
    bne !legal_name-
    lda #CART_ASSET_LEGAL_UI
    jmp cart_load_asset
!overlays:
    ldx #0
!asset:
    lda hal_storage_overlay_name_len,x
    cmp cart_name_len
    bne !next+
    lda hal_storage_overlay_name_lo,x
    sta cart_expected + 1
    lda hal_storage_overlay_name_hi,x
    sta cart_expected + 2
    ldy #0
!char:
cart_name_read:
    lda $ffff,y
cart_expected:
    cmp $ffff,y
    bne !next+
    iny
    cpy cart_name_len
    bne !char-
    txa
    clc
    adc #CART_ASSET_OVL_BASE
    jmp cart_load_asset
!next:
    inx
    cpx #CART_OVERLAY_COUNT
    bne !asset-

cart_invalid_asset:
    sei
    lda #$0e
    sta MMU_CR
    lda #2
    sta $d020
    jmp cart_invalid_asset

// hal_item_cat_cart_read_byte — Read one byte from CART_ASSET_ITEM_CATALOG.
// Input: item_cat_off_lo/hi (Default RAM, may be >= $8000).
// Output: A = byte. Clobbers: A, Y. Preserves: X, zp_ptr0/hi, MMU_CR, P(I).
hal_item_cat_cart_read_byte:
    // Read 16-bit byte offset BEFORE MMU_EXT_ROM_IO shadows $8000-$BFFF
    lda item_cat_off_lo
    sta cart_icat_off_lo
    lda item_cat_off_hi
    sta cart_icat_off_hi

    php
    sei
    lda MMU_CR
    pha
    lda #MMU_EXT_ROM_IO
    sta MMU_CR
    lda #0
    sta CART_REG_BANK
    lda CART_DIRECTORY + CART_ASSET_ITEM_CATALOG * CART_DESCRIPTOR_SIZE + 0
    sta cart_icat_bank
    lda CART_DIRECTORY + CART_ASSET_ITEM_CATALOG * CART_DESCRIPTOR_SIZE + 1
    clc
    adc cart_icat_off_lo
    sta cart_icat_ptr + 1
    lda CART_DIRECTORY + CART_ASSET_ITEM_CATALOG * CART_DESCRIPTOR_SIZE + 2
    and #$3f
    adc cart_icat_off_hi
!norm:
    cmp #$40
    bcc !bank_ok+
    sbc #$40                        // C=1 from cmp; advance 16 KB ROM bank
    inc cart_icat_bank
    bcs !norm-                      // C stays 1 across inc
!bank_ok:
    ora #$80
    sta cart_icat_ptr + 2
    lda cart_icat_bank
    sta CART_REG_BANK
cart_icat_ptr:
    lda $ffff
    tay
    lda #0
    sta CART_REG_BANK
    pla
    sta MMU_CR
    plp
    tya
    rts

cart_desc_buf:   .fill CART_DESCRIPTOR_SIZE, 0
cart_bank:       .byte 0
cart_icat_bank:  .byte 0
cart_icat_off_lo: .byte 0
cart_icat_off_hi: .byte 0
cart_count:      .word 0
cart_offset:     .word 0
cart_chunk_tmp:  .byte 0
cart_read_error: .byte 0
cart_is_legal:   .byte 0
cart_name_len:   .byte 0
cart_reader_end:
.assert "Cartridge reader code stays below $8000 (MMU $3A Ext Function ROM)", cart_read < $8000, true
.assert "Cartridge descriptor buffer stays below $8000 (MMU $3A Ext Function ROM)", cart_desc_buf + CART_DESCRIPTOR_SIZE <= $8000, true
.assert "Cartridge reader module stays in Bank 0 Default below $8000", cart_reader_end <= $8000, true
