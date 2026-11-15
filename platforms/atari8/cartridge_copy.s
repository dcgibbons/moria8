#importonce
#import "memory.s"
#import "cartridge_contract.s"
#import "../commodore/common/catalog_records.s"
// AtariMax MaxFlash 128 KB ROM reader.
// Owner: platforms/atari8/ low resident RAM (< $4000, imported by storage.s).
// Lifetime: session-long.
// Callers: asset HAL (cart_load_prg, cart_load_title), RuntimeBanked legal entry
// (cart_load_asset), LegalOverlay (legal_stream.s), and monster catalog
// (cartridge_catalog.s), including calls originating from $E000 overlays and
// $F000 RuntimeBanked.
//
// Because Atari XL/XE cartridge ROM overlays $A000-$BFFF with no RAM
// write-through, cart_read executes strictly below $4000, masks IRQs + NMIs,
// enforces non-overlap between post-boot destinations and $A000-$BFFF, disables
// the cartridge ($D510), syncs OS_GINTLK ($03FA) with TRIG3 ($D013), and
// restores NMIEN/IRQ state before returning. No core ZP ($02-$8F) is modified.

.const CART_RUNTIME_NAME_LEN = 9

cart_load_asset:
    ldx #0
    stx cart_offset
    stx cart_offset + 1
    stx cart_is_record
    jmp cart_read

// cart_read — Copy ROM asset/slice described by A (asset ID), cart_offset, and
// cart_is_record (0=full asset, 1=catalog 49B record, 2=256B legal page).
// Output: Carry clear = success, Carry set = bounded legal EOF/out-of-range.
// Clobbers: A, X, Y (preserves core ZP $02-$8F and caller IRQ mask)
cart_read:
    cmp #CART_ASSET_COUNT
    bcc !valid_id+
    jmp cart_invalid_asset
!valid_id:
    ldx #0
    stx cart_read_error
    asl
    asl
    asl
    tax
    php
    pla
    and #$04
    sta cart_saved_i
    sei
    lda #$00
    sta NMIEN
    lda #PORTB_GAME_RAM
    sta PORTB
    sta CART_BANK_SELECT       // Bank 0 holds CART_DIRECTORY at $A100

    lda CART_DIRECTORY + 0,x
    sta cart_bank
    lda CART_DIRECTORY + 1,x
    clc
    adc cart_offset
    sta cart_source + 1
    lda CART_DIRECTORY + 2,x
    adc #0
    sec
    sbc #>CART_WINDOW          // Express page relative to $A000 (0..$1F+)
    clc
    adc cart_offset + 1
    bcs !invalid_jmp+          // Huge/overflowing offset
!normalize:
    cmp #$20
    bcc !source_ready+
    sbc #$20                   // Carry is set
    inc cart_bank
    bne !normalize-
!invalid_jmp:
    jmp cart_invalid_asset
!source_ready:
    clc
    adc #>CART_WINDOW
    sta cart_source + 2
    lda cart_bank
    cmp #CART_ROM_BANK_COUNT
    bcs !invalid_jmp-

    lda CART_DIRECTORY + 3,x
    sta cart_destination + 1
    lda CART_DIRECTORY + 4,x
    sta cart_destination + 2
    lda CART_DIRECTORY + 5,x
    sta cart_count
    lda CART_DIRECTORY + 6,x
    sta cart_count + 1

    lda cart_is_record
    bne !not_plain+
    jmp !check_nonzero_len+
!not_plain:
    cmp #2
    beq !legal+
    cmp #3
    beq !item_cat+

    // cart_is_record == 1: 49-byte catalog record within CART_ASSET_CATALOG
    lda cart_offset
    clc
    adc #CATALOG_RECORD_SIZE
    sta cart_tmp
    lda cart_offset + 1
    adc #0
    bcs !invalid_jmp-
    cmp cart_count + 1
    bcc !record_fit_ok+
    bne !invalid_jmp-
    lda cart_count
    cmp cart_tmp
    bcc !invalid_jmp-
!record_fit_ok:
    lda #<cat_record
    sta cart_destination + 1
    lda #>cat_record
    sta cart_destination + 2
    lda #CATALOG_RECORD_SIZE
    sta cart_count
    lda #0
    sta cart_count + 1
    beq !validate_dest+

!legal:
    // Page-aligned 256-byte read bounded by legal document descriptor length
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
    sta cart_destination + 1
    lda #>legal_input_cache
    sta cart_destination + 2
    lda #0
    sta cart_count
    lda #1
    sta cart_count + 1
    jmp !check_nonzero_len+

!item_cat:
    // Page-aligned 256-byte (or tail) slice into icat_cache_buf (< $4000).
    lda cart_offset
    bne !legal_bad-
    lda cart_offset + 1
    cmp cart_count + 1
    beq !icat_tail+
    bcs !legal_bad-
    lda #0
    sta cart_count
    lda #1
    sta cart_count + 1
    bne !icat_set_dest+
!icat_tail:
    lda cart_count
    beq !legal_bad-
    lda #0
    sta cart_count + 1
!icat_set_dest:
    lda #<icat_cache_buf
    sta cart_destination + 1
    lda #>icat_cache_buf
    sta cart_destination + 2

!check_nonzero_len:
    lda cart_count
    ora cart_count + 1
    beq !invalid_mid+

!validate_dest:
    // Reject any post-boot destination overlapping the $A000-$BFFF cart window.
    lda cart_count
    sec
    sbc #1
    sta cart_tmp
    lda cart_count + 1
    sbc #0
    tay
    lda cart_destination + 1
    clc
    adc cart_tmp
    tya
    adc cart_destination + 2
    bcs !invalid_mid+
    cmp #>CART_WINDOW
    bcc !dest_ok+
    lda cart_destination + 2
    cmp #>CART_WINDOW_END
    bcs !dest_ok+
!invalid_mid:
    jmp cart_invalid_asset

!dest_ok:
    ldx cart_bank
    cpx #CART_ROM_BANK_COUNT
    bcs !invalid_mid-
    sta CART_BANK_SELECT,x

!loop:
    // Cap chunk at remaining bytes in current source page so a copy never
    // reads across $BFFF -> $C000. X=0 means 256 bytes.
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
    lda $a000,y
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
    cmp #>CART_WINDOW_END
    bcc !loop-
    lda #>CART_WINDOW
    sta cart_source + 2
    inc cart_bank
    lda cart_count
    ora cart_count + 1
    beq !done+
    ldx cart_bank
    cpx #CART_ROM_BANK_COUNT
    bcs !invalid_jmp2+
    sta CART_BANK_SELECT,x
    jmp !loop-

!invalid_jmp2:
    jmp cart_invalid_asset

!done:
    sta CART_DISABLE
    lda CART_TRIG3
    sta CART_OS_GINTLK
    sta NMIRES
    lda atari_nmi_enabled
    sta NMIEN
    lda cart_saved_i
    bne !keep_sei+
    cli
!keep_sei:
    lda cart_read_error
    beq !ok+
    sec
    rts
!ok:
    clc
    rts

// cart_load_prg — Resolve Atari PRG asset filename while cartridge is disabled.
// Input: A = filename length, X/Y = filename pointer lo/hi.
// Output: Carry clear = loaded, Carry set = error (invalid asset halts).
cart_load_prg:
    stx cart_name_cmp + 1
    sty cart_name_cmp + 2
    sta cart_name_len

    // 1. Overlays OVL.STA..OVL.CHS
    ldx #0
!ovl_loop:
    lda hal_storage_overlay_name_len,x
    cmp cart_name_len
    bne !ovl_next+
    lda hal_storage_overlay_name_lo,x
    ldy hal_storage_overlay_name_hi,x
    jsr cart_match_name
    bne !ovl_next+
    txa
    clc
    adc #CART_ASSET_STARTUP
    jmp cart_load_asset
!ovl_next:
    inx
    cpx #CART_OVERLAY_COUNT
    bcc !ovl_loop-

    // 2. RuntimeBanked payload ("ATARI.BNK")
    lda cart_name_len
    cmp #CART_RUNTIME_NAME_LEN
    bne !chk_title+
    lda #<atari_banked_fname
    ldy #>atari_banked_fname
    jsr cart_match_name
    bne !chk_title+
    lda #CART_ASSET_RUNTIME
    jmp cart_load_asset

!chk_title:
    // 3. Title artwork ("TITLE.DAT")
    lda cart_name_len
    cmp #hal_storage_title_name_len
    bne !chk_legal+
    lda #<hal_storage_title_name
    ldy #>hal_storage_title_name
    jsr cart_match_name
    bne !chk_legal+
    lda #CART_ASSET_TITLE
    jmp cart_load_asset

!chk_legal:
    // 4. Legal UI overlay ("LEGALUI")
    lda cart_name_len
    cmp #7
    bne cart_invalid_asset
    lda #<legal_ui_filename
    ldy #>legal_ui_filename
    jsr cart_match_name
    bne cart_invalid_asset
    lda #CART_ASSET_LEGAL_UI
    jmp cart_load_asset

// Compare cart_name_len bytes between (cart_name_cmp+1) and (A/Y).
// Preserves X; returns Z=1 on exact match.
cart_match_name:
    sta cart_expected + 1
    sty cart_expected + 2
    ldy #0
!cmp_loop:
cart_name_cmp:
    lda $ffff,y
cart_expected:
    cmp $ffff,y
    bne !mismatch+
    iny
    cpy cart_name_len
    bcc !cmp_loop-
    lda #0
!mismatch:
    rts

cart_load_title:
    lda #CART_ASSET_TITLE
    jmp cart_load_asset

cart_invalid_asset:
    sei
    lda #0
    sta NMIEN
    sta IRQEN
    sta CART_DISABLE
!halt:
    inc COLBK
    jmp !halt-

atari_nmi_enabled: .byte 0
cart_saved_i:      .byte 0
cart_read_error:   .byte 0
cart_bank:         .byte 0
cart_count:        .word 0
cart_chunk:        .byte 0
cart_tmp:          .byte 0
cart_offset:       .word 0
cart_is_record:    .byte 0
cart_name_len:     .byte 0
cart_reader_end:
.assert "Atari cartridge reader stays below $4000", cart_reader_end <= $4000, true
