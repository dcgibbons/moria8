#importonce
// item_catalog_records.s — Shared Commodore sector-cached reader for ITEM.CAT / item.idx
//
// Implements hal_item_cat_read_byte for C64, C128, and Plus/4:
//   - Cartridge builds (#if ITEM_CATALOG_CART): delegates to ROML/cart bank reader
//     (:ItemCatCartRead() macro if ITEM_CATALOG_CART_MACRO, else hal_item_cat_cart_read_byte).
//   - REU / Disk builds (#else): keeps one cached window of up to ICR_WINDOW bytes
//     (item_cat_sec_buf) from the byte a miss asked for to at most its sector's end.
//     Sector 0 holds ITEM.CAT[0..251] (after the 2-byte PRG load header); sectors 1..N-1
//     hold 254 bytes starting at sec*254 - 2. Uses item.idx track/sector table with
//     U1 / B-P 5 <n> direct sector reads, falling back to sequential "ITEM.CAT" open and
//     asset_load_ask_for_disk if a wrong disk is inserted.
//
// Platform port hooks (all optional):
//   ITEM_CAT_IDX_EXTERNAL     — port supplies item_cat_idx_data / track / number tables
//   ITEM_CAT_BUF_EXTERNAL     — port supplies ITEM_CAT_BUF_BASE (ICR_WINDOW B buffer)
//   ITEM_CAT_MAP_CUSTOM       — port defines :ItemCatMap() / :ItemCatUnmap()
//                               :ItemCatKernalIn() / :ItemCatKernalOut()
//   ITEM_CATALOG_REU          — REU holds headerless ITEM.CAT at ITEM_CAT_REU_BANK /
//                               ITEM_CAT_REU_ADDR_HI / ITEM_CAT_REU_ADDR_LO

#import "../../shared/item_catalog/item_cat_layout.s"

.const ITMCAT_SECTOR_PAYLOAD = 254
.const ITMCAT_SECTOR_COUNT   = floor((ITMCAT_TOTAL_SIZE + 2 + ITMCAT_SECTOR_PAYLOAD - 1) / ITMCAT_SECTOR_PAYLOAD)
.const ITMCAT_IDX_BODY_SIZE  = 3 + 2 * ITMCAT_SECTOR_COUNT
.const ICR_LFN               = 5
.const ICR_WINDOW            = 64   // Bytes a miss reads from the one asked for: the buffer's size
.assert "ICR_WINDOW fits a sector's payload and holds the 'ITM2' magic", ICR_WINDOW >= 4 && ICR_WINDOW <= ITMCAT_SECTOR_PAYLOAD, true

#if !ITEM_CAT_MAP_CUSTOM
.macro ItemCatMap() {
    :CatalogMap()
}
.macro ItemCatUnmap() {
    :CatalogUnmap()
}
.macro ItemCatKernalIn() {
    :CatalogKernalIn()
}
.macro ItemCatKernalOut() {
    :CatalogKernalOut()
}
#endif

#if !ITEM_CATALOG_CART

#if !ITEM_CAT_IDX_EXTERNAL
item_cat_idx_data:
item_cat_idx_size_lo:   .byte <ITMCAT_TOTAL_SIZE
item_cat_idx_size_hi:   .byte >ITMCAT_TOTAL_SIZE
item_cat_idx_sec_count: .byte ITMCAT_SECTOR_COUNT
item_cat_sec_track:     .fill ITMCAT_SECTOR_COUNT, 0
item_cat_sec_number:    .fill ITMCAT_SECTOR_COUNT, 0
item_cat_idx_end:
.assert "item.idx runtime table size matches catalog_disk.py", item_cat_idx_end - item_cat_idx_data, ITMCAT_IDX_BODY_SIZE
#endif

#if ITEM_CAT_BUF_EXTERNAL
.label item_cat_sec_buf = ITEM_CAT_BUF_BASE
#else
item_cat_sec_buf:   .fill ICR_WINDOW, 0
#endif

icr_cache_valid:    .byte 0
icr_cache_start_lo: .byte 0
icr_cache_start_hi: .byte 0
icr_cache_len:      .byte 0
icr_sec_idx:        .byte 0
icr_end_lo:         .byte 0
icr_end_hi:         .byte 0
icr_track:          .byte 0
icr_sector:         .byte 0
icr_bp_off:         .byte 0
icr_save_x:         .byte 0
icr_idx:            .byte 0
icr_skip_lo:        .byte 0
icr_skip_hi:        .byte 0
icr_bp_pos:         .byte 0

#endif

// hal_item_cat_read_byte — Input: item_cat_off_lo/hi. Output: A = byte.
// Clobbers: A, Y (preserves X and caller zero-page).
hal_item_cat_read_byte:
#if ITEM_CATALOG_CART
#if ITEM_CATALOG_CART_MACRO
    :ItemCatCartRead()
    rts
#else
    jmp hal_item_cat_cart_read_byte
#endif
#else
    lda icr_cache_valid
    beq !icr_miss+
    sec
    lda item_cat_off_lo
    sbc icr_cache_start_lo
    tay
    lda item_cat_off_hi
    sbc icr_cache_start_hi
    bcc !icr_miss+
    bne !icr_miss+
    cpy icr_cache_len
    bcs !icr_miss+
    lda item_cat_sec_buf,y
    rts

!icr_miss:
    stx icr_save_x
    lda zp_temp0
    pha
    lda zp_temp1
    pha
    lda zp_temp2
    pha
    lda zp_temp3
    pha

    // Map byte offset (item_cat_off_lo/hi) to its sector: icr_cache_start =
    // the file offset at the sector's buffer byte 2, icr_end = its end. Sector
    // 0 starts at -2 (its 2-byte PRG load header) and covers [0, 252);
    // sectors 1..N-1 cover 254 bytes.
    lda #0
    sta icr_sec_idx
    sta icr_end_hi
    lda #<-2
    sta icr_cache_start_lo
    lda #>-2
    sta icr_cache_start_hi
    lda #ITMCAT_SECTOR_PAYLOAD - 2
    sta icr_end_lo
!icr_find_sec:
    lda item_cat_off_hi
    cmp icr_end_hi
    bcc !icr_found_sec+
    bne !icr_step_sec+
    lda item_cat_off_lo
    cmp icr_end_lo
    bcc !icr_found_sec+
!icr_step_sec:
    inc icr_sec_idx
    lda icr_end_lo
    sta icr_cache_start_lo
    lda icr_end_hi
    sta icr_cache_start_hi
    clc
    lda icr_end_lo
    adc #ITMCAT_SECTOR_PAYLOAD
    sta icr_end_lo
    bcc !icr_find_sec-
    inc icr_end_hi
    bcs !icr_find_sec-          // Always (C = 1 from the adc)

!icr_found_sec:
    // Only a window from the byte asked for, ICR_WINDOW bytes at most: one
    // lookup wants 1-4 bytes, and the whole 254 over the serial bus cost a
    // stock 1541 most of each miss (53 misses entering the game, 2026-11-20).
    sec
    lda item_cat_off_lo
    sbc icr_cache_start_lo
    clc
    adc #2                      // Past the sector's two link bytes
    sta icr_bp_pos
    sec
    lda icr_end_lo
    sbc item_cat_off_lo         // What is left of the sector (1..254)
    cmp #ICR_WINDOW
    bcc !+
    lda #ICR_WINDOW
!:  sta icr_cache_len
    lda item_cat_off_lo
    sta icr_cache_start_lo
    lda item_cat_off_hi
    sta icr_cache_start_hi
    :ItemCatKernalIn()
#if ITEM_CATALOG_REU
    lda reu_present
    beq !icr_disk+
    jsr icr_from_reu
    jmp !icr_loaded+
!icr_disk:
#endif
!icr_retry:
    :ItemCatMap()
    ldx icr_sec_idx
    lda item_cat_sec_track,x
    sta icr_track
    lda item_cat_sec_number,x
    sta icr_sector
    :ItemCatUnmap()
    lda icr_track
    bne !icr_direct+
    jmp !icr_by_name+
!icr_direct:

    // Direct sector read: OPEN 15,dev,15 / OPEN 5,dev,5,"#" / U1 5 0 t s / B-P 5 <pos>
    jsr icr_open_cmd
    lda #1
    ldx #<icr_hash
    ldy #>icr_hash
    jsr hal_storage_setnam
    lda #ICR_LFN
    ldx program_device
    ldy #ICR_LFN
    jsr hal_storage_setlfs
    jsr hal_storage_open

    // Any sector-0 miss (not just file offset 0) must still verify 'ITM2' so a
    // wrong disk with a readable t/s fails before returning item records.
    // Sector 0 ends at offset 252, so icr_cache_start_hi is guaranteed 0 here.
    lda icr_sec_idx
    bne !icr_u1_window+
    lda icr_cache_start_lo
    beq !icr_u1_window+
    lda #4
    jsr icr_send_u1_bp
    bcs !icr_cmd_failed+
    jsr icr_chkin_ok
    bcs !icr_cmd_failed+
    lda #4
    jsr icr_read_buf_n
    jsr hal_storage_clrchn
    jsr icr_verify_magic
    bcs !icr_cmd_failed+
    lda icr_bp_pos
    jsr icr_send_bp
    bcs !icr_cmd_failed+
    bcc !icr_u1_read+           // Always (C = 0 from icr_send_bp)

!icr_u1_window:
    lda icr_bp_pos
    jsr icr_send_u1_bp
    bcs !icr_cmd_failed+

!icr_u1_read:
    jsr icr_chkin_ok
    bcs !icr_cmd_failed+
    jsr icr_read_sector_buf
    lda #15
    jsr hal_storage_close
    jsr icr_verify_sector
    bcs !icr_by_name+
    jmp !icr_loaded+

!icr_cmd_failed:
    jsr icr_close_all
!icr_by_name:
    jsr icr_open_cmd
    lda #icr_name_end - icr_name
    ldx #<icr_name
    ldy #>icr_name
    jsr hal_storage_setnam
    lda #ICR_LFN
    ldx program_device
    ldy #ICR_LFN
    jsr hal_storage_setlfs
    jsr hal_storage_open
    bcs !icr_wrong_disk+
    jsr icr_drive_ok
    bcs !icr_wrong_disk+
    jsr icr_chkin_ok
    bcs !icr_wrong_disk+
    // Skip 2-byte PRG header + icr_cache_start_lo/hi payload bytes.
    jsr hal_storage_chrin
    jsr hal_storage_chrin
    lda icr_cache_start_lo
    sta icr_skip_lo
    lda icr_cache_start_hi
    sta icr_skip_hi
!icr_skip:
    lda icr_skip_lo
    ora icr_skip_hi
    beq !icr_read_named+
    jsr hal_storage_chrin
    jsr hal_storage_readst
    and #$bf
    bne !icr_wrong_disk+
    lda icr_skip_lo
    bne !+
    dec icr_skip_hi
!:  dec icr_skip_lo
    jmp !icr_skip-
!icr_read_named:
    jsr icr_read_sector_buf
    lda #15
    jsr hal_storage_close
    jsr icr_verify_sector
    bcc !icr_loaded+

!icr_wrong_disk:
    jsr icr_close_all
    lda #icr_name_end - icr_name
    sta alr_len
    lda #<icr_name
    sta alr_name_lo
    lda #>icr_name
    sta alr_name_hi
    lda #0
    sta alr_left
    jsr asset_load_ask_for_disk
    lda #1
    sta vis_room_revealed
    lda #0
    sta status_cache_valid
    jmp !icr_retry-

!icr_loaded:
    :ItemCatKernalOut()
    lda #1
    sta icr_cache_valid
    pla
    sta zp_temp3
    pla
    sta zp_temp2
    pla
    sta zp_temp1
    pla
    sta zp_temp0
    ldx icr_save_x
    sec
    lda item_cat_off_lo
    sbc icr_cache_start_lo
    tay
    lda item_cat_sec_buf,y
    rts

icr_chkin_ok:
    ldx #ICR_LFN
    jsr hal_storage_chkin
    bcs !ico_err+
    jsr hal_storage_readst
    and #$bf
    beq !ico_ok+
!ico_err:
    sec
    rts
!ico_ok:
    clc
    rts

// icr_read_sector_buf — Read icr_cache_len bytes from active channel ICR_LFN into item_cat_sec_buf; close ICR_LFN.
icr_read_sector_buf:
    lda icr_cache_len
    jsr icr_read_buf_n
icr_close_buf:
    jsr hal_storage_clrchn
    lda #ICR_LFN
    jmp hal_storage_close

icr_open_cmd:
    lda #0
    jsr hal_storage_setnam
    lda #15
    ldx program_device
    ldy #15
    jsr hal_storage_setlfs
    jmp hal_storage_open

icr_close_all:
    jsr icr_close_buf
    lda #15
    jmp hal_storage_close

// icr_read_buf_n — Read A bytes (1..ICR_WINDOW) from active channel ICR_LFN into item_cat_sec_buf.
// Uses icr_skip_lo as loop limit (dead on !icr_direct and after !icr_skip finishes).
icr_read_buf_n:
    sta icr_skip_lo
    lda #0
    sta icr_idx
!irsb_loop:
    jsr hal_storage_chrin
    ldx icr_idx
    sta item_cat_sec_buf,x
    inx
    stx icr_idx
    cpx icr_skip_lo
    bne !irsb_loop-
    rts

// icr_verify_sector — C = 0 if the buffer looks valid: one read from the
// file's start (icr_cache_start = 0) must begin with 'ITM2'.
icr_verify_sector:
    lda icr_cache_start_lo
    ora icr_cache_start_hi
    bne !ivs_ok+
icr_verify_magic:
    ldx #3
!ivm_loop:
    lda item_cat_sec_buf,x
    cmp icr_magic,x
    bne !ivs_bad+
    dex
    bpl !ivm_loop-
!ivs_ok:
    clc
    rts
!ivs_bad:
    sec
    rts

#if ITEM_CATALOG_REU
icr_from_reu:
    clc
    lda #<ITEM_CAT_REU_BASE
    adc icr_cache_start_lo
    sta REU_REULO
    lda #>ITEM_CAT_REU_BASE
    adc icr_cache_start_hi
    sta REU_REUHI
    lda #ITEM_CAT_REU_BANK
    adc #0
    sta REU_BANK
    lda #0
    sta REU_LENHI
    sta REU_CONTROL
    lda #<item_cat_sec_buf
    sta REU_C64LO
    lda #>item_cat_sec_buf
    sta REU_C64HI
    lda icr_cache_len
    sta REU_LENLO
    lda #REU_CMD_FETCH
    sta REU_COMMAND
    rts
#endif

.const ICR_BP_OFFSET = 8

// icr_send_u1_bp — Shared direct-sector seek helper for item_catalog_records.s
// and catalog_fetch.s (#367 #7):
//   1) Send "U1 5 0 <icr_track> <icr_sector>\r" on channel 15, CLRCHN
//   2) Check drive status via icr_drive_ok; if C=1, abort BEFORE CHKIN 5
//      so a refused "#" buffer ("70, NO CHANNEL") can never hang serial talk
//   3) Send "B-P 5 <A>\r" on channel 15, CLRCHN, return C=0.
// A CHKOUT 15 that fails returns C=1 at once: its output went to the screen.
// Unchecked, a Plus/4 disk game printed "B-P 5" and a sector offset onto the
// map, read the buffer from the wrong place and named a Gold (large) "Gold
// (larelar" (build queue and playtest gate, 2026-11-17); the caller falls
// back to the by-name read.
// Input: A = buffer byte offset (2..255), icr_track, icr_sector
// Output: C = 0 on OK, C = 1 on drive error
// Clobbers: A, X, Y, zp_temp0, zp_temp1, zp_temp3, nf_value_2
icr_send_u1_bp:
    sta icr_bp_off
    ldx #15
    jsr hal_storage_chkout
    bcs !isub_failed+
    lda #0
    jsr icr_put_text
    lda icr_track
    jsr icr_put_num
    lda #$20
    jsr hal_storage_chrout
    lda icr_sector
    jsr icr_put_num
    lda #$0d
    jsr hal_storage_chrout
    jsr hal_storage_clrchn
    jsr icr_drive_ok
    bcs !isub_done+
    bcc !isub_bp+
icr_send_bp:
    sta icr_bp_off
!isub_bp:
    ldx #15
    jsr hal_storage_chkout
    bcs !isub_failed+
    lda #ICR_BP_OFFSET
    jsr icr_put_text
    lda icr_bp_off
    jsr icr_put_num
    lda #$0d
    jsr hal_storage_chrout
    jsr hal_storage_clrchn
    jmp icr_drive_ok
!isub_failed:
    jsr hal_storage_clrchn
!isub_err:
    sec
!isub_done:
    rts

// icr_drive_ok — After a command on the command channel (LFN 15, open): the
// first digit of the drive's status, carry clear for "0x" with clean READST,
// set for any serial/status error (the next command resets the message, so the
// rest is left unread). A buffer channel the drive refused ("70, NO CHANNEL")
// got a CHKIN anyway, and the KERNAL's talk turnaround waits for a talker that
// never comes: the Plus/4 hung buying in a store (playtest gate, 2026-11-15,
// once in about 2,200 sector reads). Shared with catalog_fetch.s via icr_send_u1_bp.
// Clobbers: A, X, Y
icr_drive_ok:
    ldx #15
    jsr hal_storage_chkin
    bcs !isub_failed-
    jsr hal_storage_chrin
    eor #$30                    // '0' ($30) -> $00; any other status byte -> != $00
    sta icr_idx
    jsr hal_storage_readst
    and #$bf                    // non-EOF serial error bits ($00 when clean)
    ora icr_idx
    pha
    jsr hal_storage_clrchn
    pla
    cmp #1                      // C = 0 iff first char == '0' and READST clean
    rts

icr_put_text:
    sta icr_idx
!ipt_send:
    ldx icr_idx
    lda icr_u1,x
    beq !ipt_done+
    jsr hal_storage_chrout
    inc icr_idx
    bne !ipt_send-
!ipt_done:
    rts

icr_put_num:
    jsr numeric_format_u8
    lda #0
    sta icr_idx
!ipn_send:
    ldx icr_idx
    lda nf_digit_buf,x
    jsr hal_storage_chrout
    inc icr_idx
    lda icr_idx
    cmp zp_temp2
    bne !ipn_send-
    rts

icr_u1:   .text "U1 5 0 " ; .byte 0
icr_bp:   .text "B-P 5 " ; .byte 0
.assert "icr_bp offset matches ICR_BP_OFFSET", icr_bp - icr_u1, ICR_BP_OFFSET
icr_hash:  .text "#"
icr_magic: .text "ITM2"
icr_name:  .text "ITEM.CAT"
icr_name_end:
#endif

#if HAL_PLATFORM_ITEM_PICKUP_CACHE
#import "item_pickup_cache.s"
#endif
