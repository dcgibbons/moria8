#importonce
// item_cat_vdc128.s — Native C128 16 KB VDC RAM preload & reader for ITEM.CAT
//
// Module ownership:
//   owner: Bank 0 Default resident (< $4000, imported by main.s before input128.s);
//     imported directly by tests/test_item_desc128.s for unit coverage.
//   lifetime: permanent session lifetime (populated once at boot in
//     c128_load_core_residents after any $FF62 JDLCHR font restore; survives
//     all dungeon generation, overlay swaps, and game_restart cycles).
//   callers: c128_load_core_residents (c128_load_item_cat_vdc) and
//     core/6502/item_catalog.s (hal_item_cat_read_byte).
//
// Cartridge builds (#if C128_CARTRIDGE):
//   - Delegate hal_item_cat_read_byte to hal_item_cat_cart_read_byte in
//     cartridge_copy.s (< $8000), reading directly from MD128 External
//     Function ROM with zero disk access.
//
// Disk builds (#else):
//   - At startup (c128_load_core_residents, after any JDLCHR font restore),
//     c128_load_item_cat_vdc loads "ITEM.CAT" (7,478 B payload) into Bank 1
//     MAP_BASE ($4000-$5D35) at full KERNAL/Burst speed (SA=0), verifies the
//     'ITM2' header, and streams all 7,478 bytes into unused 16 KB VDC RAM:
//       * ITEM.CAT[0..3839]    ($0000-$0EFF) -> VDC $1100-$1FFF (3,840 B)
//       * ITEM.CAT[3840..7477] ($0F00-$1D35) -> VDC $2008-$3C6D (bytes 8..15
//         of 455 16-byte character cells in $2000-$3FFF; 80x25 8-scanline text
//         mode uses only bytes 0..7 of each cell for Set 0 and Set 1 glyphs).
//   - Gameplay hal_item_cat_read_byte reads directly from VDC RAM via $D600/$D601
//     in ~95 cycles with zero floppy disk access, zero new ZP bytes, and full
//     preservation of Set 0 ($2000) and Set 1 ($3000) glyph rasters.

#import "../../shared/item_catalog/item_cat_layout.s"

.const ITEM_CAT_FILE_NUM = 14

#if C128_CARTRIDGE

hal_item_cat_read_byte:
    jmp hal_item_cat_cart_read_byte

#else

icv_tmp:     .byte 0
icv_addr_lo: .byte 0
icv_save_x:  .byte 0
icv_save_y:  .byte 0

// vdc_item_cat_map_addr — Map 16-bit ITEM.CAT offset (item_cat_off_lo/hi,
// 0..ITMCAT_TOTAL_SIZE-1) to physical 16 KB VDC RAM address (A = hi, Y = lo).
// Clobbers: A, Y. Preserves: X, ZP.
vdc_item_cat_map_addr:
    ldy item_cat_off_lo
    lda item_cat_off_hi
    cmp #>VDC_ITEM_CAT_LO_SIZE
    bcs !icv_hi_span+
    clc
    adc #>VDC_ITEM_CAT_LO_BASE
    rts
!icv_hi_span:
    // Carry set: rel = off - $0F00 ($0000..$0E35); slot S = rel >> 3, B = rel & 7.
    sbc #>VDC_ITEM_CAT_LO_SIZE
    sta icv_tmp
    tya
    and #$07
    ora #VDC_ITEM_CAT_CELL_OFFSET
    sta icv_addr_lo
    lda item_cat_off_lo
    and #$f8
    asl                             // C = bit 4 of S; A = (S & $0F) << 4
    ora icv_addr_lo                 // ORA/TAY/LDA preserve C for ROL below
    tay
    lda icv_tmp
    rol                             // A = (rel_hi << 1) | C ($00..$1C)
    ora #>VDC_CHARSET_BASE          // $20..$3C
    rts

// hal_item_cat_read_byte — Input: item_cat_off_lo/hi. Output: A = byte.
// Clobbers: A, Y. Preserves: X, ZP, MMU state, and caller I flag.
hal_item_cat_read_byte:
    php
    sei
    stx icv_save_x
    jsr vdc_item_cat_map_addr
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_read_reg
    ldx icv_save_x
    plp
    rts

icv_magic:
    .byte $49, $54, $4d, $32        // "ITM2"

item_cat_filename:
    .text "ITEM.CAT"
item_cat_filename_end:
.const ITEM_CAT_FILENAME_LEN = item_cat_filename_end - item_cat_filename

// c128_load_item_cat_vdc — Preload "ITEM.CAT" into 16 KB VDC RAM via Bank 1
// MAP_BASE ($4000-$5D35) before title/gameplay maps use MAP_BASE.
// Output: carry clear = success, carry set = load or magic failure.
c128_load_item_cat_vdc:
    lda #ITEM_CAT_FILE_NUM
    sta disk_temp
    lda #ITEM_CAT_FILENAME_LEN
    sta disk_status
    lda #<item_cat_filename
    sta zp_ptr0
    lda #>item_cat_filename
    sta zp_ptr0_hi
    lda #<MAP_BASE
    sta zp_ptr1
    lda #>MAP_BASE
    sta zp_ptr1_hi
    lda #1
    sta c128_runtime_load_bank
    lda #0
    sta crl_sa
    jsr c128_load_runtime_prg
    bcc !icv_loaded+
    rts
!icv_loaded:
    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi
    ldy #3
!icv_chk_magic:
    jsr mmu_safe_map_read_ptr0
    cmp icv_magic,y
    bne !icv_bad_magic+
    dey
    bpl !icv_chk_magic-

    php
    sei
    lda #0
    sta item_cat_off_lo
    sta item_cat_off_hi
    ldy #0
!icv_copy_loop:
    // Reseed VDC update pointer + Reg 31 at $1100 start (off == 0) and at each
    // 8-byte cell boundary in $2000-$3FFF (off_hi >= $0F && (off_lo & 7) == 0).
    lda item_cat_off_hi
    cmp #>VDC_ITEM_CAT_LO_SIZE
    bcc !icv_chk_zero+
    lda item_cat_off_lo
    and #$07
    beq !icv_reseed+
    bne !icv_stream_byte+
!icv_chk_zero:
    ora item_cat_off_lo
    bne !icv_stream_byte+
!icv_reseed:
    sty icv_save_y
    jsr vdc_item_cat_map_addr
    jsr vdc_set_update_addr
    ldx #31
    jsr vdc_select_reg
    ldy icv_save_y
!icv_stream_byte:
    jsr mmu_safe_map_read_ptr0
    jsr vdc_wait
    sta VDC_DATA_REG
    iny
    bne !icv_no_page+
    inc zp_ptr0_hi
!icv_no_page:
    inc item_cat_off_lo
    bne !icv_chk_end+
    inc item_cat_off_hi
!icv_chk_end:
    lda item_cat_off_hi
    cmp #>ITMCAT_TOTAL_SIZE
    bcc !icv_copy_loop-
    lda item_cat_off_lo
    cmp #<ITMCAT_TOTAL_SIZE
    bcc !icv_copy_loop-
    plp
    clc
    rts

!icv_bad_magic:
    sec
    rts

#endif
