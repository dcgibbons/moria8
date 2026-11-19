#importonce
#import "cartridge_contract.s"
#import "../common/catalog_records.s"
// Plus/4 c264 magic cart ROM reader. Owner: Plus/4 cartridge low resident RAM (< $8000).
// Called by asset HAL and catalog fetch, including from $E000 overlays and $F000
// runtime. Restores BASIC+KERNAL slot, bank 0, and RAM visibility ($FF3F) before
// returning. All runtime destinations live outside $8000-$BFFF and >= $FC00 (checked
// by tools/make_plus4_magic.py), so writes go directly to RAM beneath ROM.
// No ZP is borrowed. Non-reentrant, IRQs masked.
// Directory: bank 0, $8100, CART_ASSET_COUNT 8-byte descriptors.

cart_reader_start:
.assert "Cartridge reader starts in low resident RAM", cart_reader_start >= $1001, true

cart_load_asset:
    ldx #0
    stx cart_offset
    stx cart_offset + 1
    stx cart_is_record
    jmp cart_read

cart_read:
    ldx #0
    stx cart_read_error
    asl
    asl
    asl
    tax
    php
    sei
    lda #0
    sta CART_REG_BANK
    sta CART_REG_C1LO_KERNAL
    sta PLUS4_ROM_ENABLE
    lda CART_DIRECTORY,x
    sta cart_bank
    lda CART_DIRECTORY + 1,x
    clc
    adc cart_offset
    sta cart_source + 1
    lda CART_DIRECTORY + 2,x
    adc cart_offset + 1
!normalize:
    cmp #>CART_ROM_WINDOW_END
    bcc !source_ready+
    sbc #(CART_ROM_WINDOW_END - CART_ROM_WINDOW_BASE) / $100
    inc cart_bank
    bne !normalize-
!source_ready:
    sta cart_source + 2
    lda CART_DIRECTORY + 3,x
    sta cart_destination + 1
    lda CART_DIRECTORY + 4,x
    sta cart_destination + 2
    lda CART_DIRECTORY + 5,x
    sta cart_count
    lda CART_DIRECTORY + 6,x
    sta cart_count + 1
    lda cart_is_record
    beq !copy+
    cmp #2
    beq !legal+
    cmp #3
    beq !cat_ext+
    lda #<cat_record
    sta cart_destination + 1
    lda #>cat_record
    sta cart_destination + 2
    lda #CATALOG_RECORD_SIZE
    sta cart_count
    lda #0
    sta cart_count + 1
    beq !copy+
!cat_ext:
    lda #<cat_ext_record
    sta cart_destination + 1
    lda #>cat_ext_record
    sta cart_destination + 2
    lda #8
    sta cart_count
    lda #0
    sta cart_count + 1
    beq !copy+
!legal:
    // ROM documents are page-padded, but each request must still fit its
    // descriptor. A missing terminator cannot read the following asset.
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
    jmp !loop+
!legal_ok:
    lda #<legal_input_cache
    sta cart_destination + 1
    lda #>legal_input_cache
    sta cart_destination + 2
    lda #0
    sta cart_count
    lda #1
    sta cart_count + 1
!copy:
    lda cart_bank
    sta CART_REG_BANK
!loop:
    // A chunk ends at the source page boundary, hence never crosses a
    // 16 KB C1LO bank. X=0 means 256 bytes; the final chunk may be shorter.
    ldx cart_source + 1
    beq !capacity+
    txa
    eor #$ff
    clc
    adc #1
    tax
!capacity:
    lda cart_count + 1
    bne !chunk+
    lda cart_count
    beq !done+
    cpx #0
    beq !tail+
    cpx cart_count
    bcc !chunk+
!tail:
    ldx cart_count
!chunk:
    ldy #0
cart_source:
    lda $8000,y
cart_destination:
    sta $ffff,y
    iny
    dex
    bne cart_source
    tya
    bne !partial+
    inc cart_destination + 2
    dec cart_count + 1
    jmp !source+
!partial:
    sty cart_chunk
    clc
    adc cart_destination + 1
    sta cart_destination + 1
    bcc !subtract+
    inc cart_destination + 2
!subtract:
    lda cart_count
    sec
    sbc cart_chunk
    sta cart_count
    bcs !source+
    dec cart_count + 1
!source:
    tya
    clc
    adc cart_source + 1
    sta cart_source + 1
    bne !loop-
    inc cart_source + 2
    lda cart_source + 2
    cmp #>CART_ROM_WINDOW_END
    bne !loop-
    lda #>CART_ROM_WINDOW_BASE
    sta cart_source + 2
    inc cart_bank
    lda cart_bank
    sta CART_REG_BANK
    jmp !loop-
!done:
    lda #0
    sta CART_REG_BANK
    sta CART_REG_BASIC_KERNAL
    sta PLUS4_RAM_ENABLE
    plp
    lda cart_read_error
    beq !ok+
    sec
    rts
!ok:
    clc
    rts

// PRG HAL adapter: resolve the existing platform-owned overlay file names
// while RAM is visible (a caller's filename can itself live above $8000).
cart_load_prg:
    stx cart_legal_name_read + 1
    sty cart_legal_name_read + 2
    stx cart_name_read + 1
    stx cart_index_char + 1
    sty cart_name_read + 2
    sty cart_index_char + 2
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
    adc #CART_ASSET_STARTUP
    jmp cart_load_asset
!next:
    inx
    cpx #CART_OVERLAY_COUNT
    bne !asset-
    // The only other PRG-header HAL request is the catalog boot index.
    lda cart_name_len
    cmp #cbl_idx_name_end - cbl_idx_name
    bne cart_invalid_asset
    ldy #0
!index_char:
cart_index_char:
    lda $ffff,y
    cmp cbl_idx_name,y
    bne cart_invalid_asset
    iny
    cpy cart_name_len
    bne !index_char-
    lda #CART_ASSET_INDEX
    jmp cart_load_asset

cart_load_title:
    lda #CART_ASSET_TITLE_ART
    jmp cart_load_asset

// hal_item_cat_cart_read_byte — Read one byte from CART_ASSET_ITEM_CATALOG.
// Input: item_cat_off_lo/hi (16-bit byte offset). Output: A = byte (N/Z updated).
// Preserves: X, caller zero-page, IRQ flag; restores CART_REG_BANK=0 & $FF3F.
hal_item_cat_cart_read_byte:
    stx icr_cart_save_x
    php
    sei
    lda #0
    sta CART_REG_BANK
    sta CART_REG_C1LO_KERNAL
    sta PLUS4_ROM_ENABLE
    ldx #CART_ASSET_ITEM_CATALOG * CART_DESCRIPTOR_SIZE
    lda CART_DIRECTORY,x
    sta cart_bank
    lda CART_DIRECTORY + 1,x
    clc
    adc item_cat_off_lo
    sta icr_cart_lda + 1
    lda CART_DIRECTORY + 2,x
    adc item_cat_off_hi
!icr_norm:
    cmp #>CART_ROM_WINDOW_END
    bcc !icr_ready+
    sbc #(CART_ROM_WINDOW_END - CART_ROM_WINDOW_BASE) / $100
    inc cart_bank
    bne !icr_norm-
!icr_ready:
    sta icr_cart_lda + 2
    lda cart_bank
    sta CART_REG_BANK
icr_cart_lda:
    ldy $8000
    lda #0
    sta CART_REG_BANK
    sta CART_REG_BASIC_KERNAL
    sta PLUS4_RAM_ENABLE
    plp
    ldx icr_cart_save_x
    tya
    rts

cart_invalid_asset:
    sei
    lda #0
    sta CART_REG_BANK
    sta CART_REG_BASIC_KERNAL
    sta PLUS4_RAM_ENABLE
    lda #$22                    // Dark red border on TED
    sta TED_BORDER
    jmp cart_invalid_asset

cart_read_error: .byte 0
cart_bank:      .byte 0
cart_count:     .word 0
cart_chunk:     .byte 0
cart_offset:    .word 0
cart_is_record: .byte 0
cart_name_len:  .byte 0
icr_cart_save_x: .byte 0
cart_reader_end:
.assert "Cartridge reader stays visible beneath C1LO ROM", cart_reader_end <= CART_ROM_WINDOW_BASE, true
