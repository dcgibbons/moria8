#importonce
#import "cartridge_contract.s"
#import "../common/catalog_records.s"
// EasyFlash ROM reader. Owner: C64 cartridge low resident RAM, session-long.
// Called by asset HAL and catalog fetch, including from the $E000 overlays
// and $F000 runtime. It switches ROM off before returning to those callers.
// No ZP or $DF00 cartridge RAM is borrowed. Non-reentrant, IRQs masked.
// Directory: bank 0, $8100, CART_ASSET_COUNT 8-byte descriptors (bank, source word,
// destination word, length word, reserved). tools/make_easyflash.py owns it.

// Installed once during startup. During transfers only the single-byte
// active flag changes: NMI must never observe a half-replaced vector.
cart_install_nmi:
    php
    sei
    lda $0318
    sta cart_original_nmi
    lda $0319
    sta cart_original_nmi + 1
    lda #<cart_nmi
    sta $0318
    lda #>cart_nmi
    sta $0319
    plp
    rts

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
    lda #1
    sta cart_copy_active
    lda $01
    pha
    lda #$37                // ROML reads need HIRAM; KERNAL NMI vector is active
    sta $01
    lda #0
    sta $de00
    lda #$06                 // 8 KB ROML; writes still reach the RAM beneath ROM
    sta $de02
    lda CART_DIRECTORY,x
    sta cart_bank
    lda CART_DIRECTORY + 1,x
    clc
    adc cart_offset
    sta cart_source + 1
    lda CART_DIRECTORY + 2,x
    adc cart_offset + 1
!normalize:
    cmp #$a0
    bcc !source_ready+
    sbc #$20                 // C=1 from CMP
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
    lda #<cat_record
    sta cart_destination + 1
    lda #>cat_record
    sta cart_destination + 2
    lda #CATALOG_RECORD_SIZE
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
    sta $de00
!loop:
    // A chunk ends at the source page boundary, hence never crosses a
    // ROM bank. X=0 means 256 bytes; the final chunk may be shorter.
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
    cmp #$a0
    bne !loop-
    lda #$80
    sta cart_source + 2
    inc cart_bank
    lda cart_bank
    sta $de00
    jmp !loop-
!done:
    lda #$04                 // Disable cartridge before restoring caller
    sta $de02
    pla
    sta $01
    lda #0
    sta cart_copy_active
    plp
    lda cart_read_error
    beq !ok+
    sec
    rts
!ok:
    clc
    rts

// PRG HAL adapter: resolve the existing platform-owned overlay file names
// while ROM is disabled (a caller's filename can itself live above $8000).
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
    lda #CART_ASSET_TITLE
    jmp cart_load_asset

cart_invalid_asset:
    sei
    lda #$35
    sta $01
    lda #2
    sta $d020
    jmp cart_invalid_asset

// KERNAL NMI entry jumps through $0318 before pushing any general registers.
// Preserve ordinary NMI handling outside transfers, including RESTORE.
cart_nmi:
    pha
    lda cart_copy_active
    beq !ordinary+
    lda $dd0d
    pla
    rti
!ordinary:
    pla
    jmp (cart_original_nmi)

cart_original_nmi: .word 0
cart_read_error: .byte 0
cart_copy_active: .byte 0
cart_bank:      .byte 0
cart_count:     .word 0
cart_chunk:     .byte 0
cart_offset:    .word 0
cart_is_record: .byte 0
cart_name_len:  .byte 0
cart_reader_end:
.assert "Cartridge reader stays visible beneath ROML", cart_reader_end <= $8000, true
