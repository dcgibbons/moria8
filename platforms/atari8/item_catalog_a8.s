#importonce
// item_catalog_a8.s — Atari 8-bit HAL reader for 'ITM2' ITEM.CAT
//
// Linked strictly in LowHelpers (< $4000) so:
// - Cartridge builds can bank-switch $D5xx / $A000-$BFFF via cart_read
//   without unmapping the reader or destination buffer.
// - Disk builds can call EnterSio / ExitSio (OS ROM $E459 at PORTB = $FF)
//   without unmapping the reader or 125-byte DOS 2.5 sector cache.
//
// Interface (required by core/item_catalog.s when HAL_PLATFORM_ITEM_CAT_CUSTOM):
//   hal_item_cat_read_byte:
//     Input:  item_cat_off_lo, item_cat_off_hi (in Default RAM < $C100)
//     Output: A = byte at offset
//     Clobbers: A, Y (MUST preserve X and caller core ZP / PORTB = $FE)

#if ATARI8_CARTRIDGE

// 256-byte page cache below $4000 so consecutive Huffman bit/byte reads hit
// RAM without disabling NMIs or banking the cartridge window.
icat_cache_buf:   .fill 256, 0
icat_cached_page: .byte $ff
icat_saved_x:     .byte 0

hal_item_cat_read_byte:
    // Read offset from Default RAM while PORTB = $FE (RAM visible at $A000-$BFFF).
    lda item_cat_off_hi
    cmp icat_cached_page
    bne !load_page+
!hit:
    ldy item_cat_off_lo
    lda icat_cache_buf,y
    rts
!load_page:
    stx icat_saved_x
    sta cart_offset + 1
    lda #0
    sta cart_offset
    lda #3
    sta cart_is_record
    lda #CART_ASSET_ITEM_CATALOG
    jsr cart_read
    bcs !fail+
    lda cart_offset + 1
    sta icat_cached_page
    ldx icat_saved_x
    jmp !hit-
!fail:
    ldx icat_saved_x
    lda #0
    rts

#else

// Dedicated 128-byte DOS 2.5 sector buffer below $4000 so SIO reads into
// sio_sector_buf (save_stream / monster catalog) never invalidate ITEM.CAT.
icat_sec_buf:    .fill 128, 0
icat_cached_sec: .byte $ff
icat_start_lo:   .byte 0
icat_start_hi:   .byte 0
icat_fid_mask:   .byte 0
icat_sec_idx:    .byte 0
icat_byte_idx:   .byte 0
icat_rem_lo:     .byte 0
icat_rem_hi:     .byte 0
icat_cur_lo:     .byte 0
icat_cur_hi:     .byte 0
icat_left:       .byte 0
icat_saved_x:    .byte 0
icat_fname:      .text "ITEM.CAT"

hal_item_cat_read_byte:
    // Fast integer split: offset / 125 for 0 <= offset < 7800.
    // q0 = offset >> 7; off - q0*125 = (off_lo & $7f) + 3*q0; adjust <= 2 times.
    lda item_cat_off_lo
    asl
    lda item_cat_off_hi
    rol
    sta icat_sec_idx
    asl
    clc
    adc icat_sec_idx
    sta icat_rem_lo
    lda #0
    sta icat_rem_hi
    lda item_cat_off_lo
    and #$7f
    clc
    adc icat_rem_lo
    bcc !no_c+
    inc icat_rem_hi
!no_c:
!div_chk:
    ldy icat_rem_hi
    bne !sub_125+
    cmp #125
    bcc !div_done+
!sub_125:
    sec
    sbc #125
    bcs !sub_nc+
    dec icat_rem_hi
!sub_nc:
    inc icat_sec_idx
    bne !div_chk-
!div_done:
    sta icat_byte_idx

    lda icat_sec_idx
    cmp icat_cached_sec
    bne !miss+
!hit:
    ldy icat_byte_idx
    lda icat_sec_buf,y
    rts

!miss:
    stx icat_saved_x
!retry:
    lda icat_start_lo
    ora icat_start_hi
    bne !have_start+

    lda program_device
    sta atari_io_device
    lda #8
    sta atari_io_cnt
    lda #<icat_fname
    sta atari_io_src
    lda #>icat_fname
    sta atari_io_src_hi
    jsr atari_format_83
    jsr atari_find_dir_entry
    bcc !dir_ok+
    jmp !prompt_disk+
!dir_ok:
    lda atari_io_sec_lo
    sta icat_start_lo
    lda atari_io_sec_hi
    sta icat_start_hi
    lda atari_file_idx
    and #$3f
    asl
    asl
    sta icat_fid_mask

!have_start:
    // Fast contiguous read at icat_start + icat_sec_idx.
    lda icat_start_lo
    clc
    adc icat_sec_idx
    tay
    lda icat_start_hi
    adc #0
    tax
    tya
    jsr icat_read_sector
    bcs !chain_walk+
    jsr icat_verify_buf
    beq !cache_ok+

!chain_walk:
    // Non-contiguous fallback: follow DOS 2.5 10-bit sector links from start.
    lda icat_start_lo
    sta icat_cur_lo
    lda icat_start_hi
    sta icat_cur_hi
    lda icat_sec_idx
    sta icat_left
!cw_loop:
    lda icat_cur_lo
    ora icat_cur_hi
    beq !prompt_disk+
    lda icat_cur_lo
    ldx icat_cur_hi
    jsr icat_read_sector
    bcs !prompt_disk+
    lda icat_sec_buf + DOS25_LINK_HI
    and #$fc
    cmp icat_fid_mask
    bne !prompt_disk+
    lda icat_left
    beq !cw_last+
    dec icat_left
    lda icat_sec_buf + DOS25_LINK_HI
    and #$03
    sta icat_cur_hi
    lda icat_sec_buf + DOS25_LINK_LO
    sta icat_cur_lo
    jmp !cw_loop-
!cw_last:
    lda icat_byte_idx
    cmp icat_sec_buf + DOS25_LINK_BYTES
    bcs !prompt_disk+

!cache_ok:
    lda icat_sec_idx
    sta icat_cached_sec
    ldx icat_saved_x
    jmp !hit-

!prompt_disk:
    lda #0
    sta icat_start_lo
    sta icat_start_hi
    lda #$ff
    sta icat_cached_sec
    lda #8
    sta alr_len
    lda #<icat_fname
    sta alr_name_lo
    lda #>icat_fname
    sta alr_name_hi
    lda #0
    sta alr_left
    jsr asset_load_ask_for_disk
    lda #1
    sta vis_room_revealed
    lda #0
    sta status_cache_valid
    jmp !retry-

// icat_read_sector — Read DOS 2.5 sector A (lo) / X (hi) from program_device
// into icat_sec_buf. Output: C = 1 on SIO error. Clobbers: A, X, Y.
icat_read_sector:
    sta DCB_DAUX1
    stx DCB_DAUX2
    lda program_device
    sta atari_io_device
    lda #'R'
    sta DCB_DCOMND
    lda #$40
    sta DCB_DSTATS
    lda #<icat_sec_buf
    sta DCB_DBUFLO
    lda #>icat_sec_buf
    sta DCB_DBUFHI
    lda #128
    sta DCB_DBYTLO
    lda #0
    sta DCB_DBYTHI
    jsr EnterSio
    jmp ExitSio

// icat_verify_buf — Z = 1 iff icat_sec_buf matches expected DOS 2.5 file ID
// and contains at least icat_byte_idx + 1 payload bytes.
icat_verify_buf:
    lda icat_sec_buf + DOS25_LINK_HI
    and #$fc
    cmp icat_fid_mask
    bne !bad+
    lda icat_byte_idx
    cmp icat_sec_buf + DOS25_LINK_BYTES
    bcs !bad+
    lda #0
    rts
!bad:
    lda #1
    rts

#endif
