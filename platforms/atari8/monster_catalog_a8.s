#importonce
// monster_catalog_a8.s — The Atari 8-bit monster catalog as disk records
// (docs/MONSTER_CATALOG_DESIGN.md "Atari 8-bit", core/monster_catalog.s;
// docs/ATARI8_MEMORY_CONTRACT.md owns PORTB, SIOV and the 130XE slots).
//
// MONSTER.CAT holds the 49-byte records (platforms/commodore/common/
// catalog_records.s), A8_CATALOG_RECORDS_PER_SECTOR to each 125-byte DOS 2.5
// sector: record n is in file sector n / 2, at byte (n % 2) * 49 of its data.
// The disk build writes it contiguous (tools/make_atr.py), and the game finds
// its first sector in the directory, so a record is one sector read: start +
// n / 2 (maintainer, 2026-11-05). A record that names another creature (a
// file copied by DOS, not contiguous) is read again down the sector chain
// from the start, and only then does the game ask for the program disk.
//
// A 130XE preloads every record sector at boot, 32 to a 4 KB slot at a
// 128-byte stride (A8_CATALOG_XE_SLOTS: the tiers' old slots 10-13 and the
// spare 15); a record is then a 49-byte banked copy (a8_cat_xe_copy).
//
// Linked in the low helpers (< $4000): the SIOV calls return with the OS ROM
// in, and the 130XE copy maps $4000-$7FFF to an extended bank, so cat_record
// and the copy loop must lie below $4000. The level index alone lives in
// the $F000 runtime.

#import "../commodore/common/catalog_records.s"

.const A8_CATALOG_RECORDS_PER_SECTOR = 2
.const A8_CATALOG_SECTOR_DATA        = 125   // DOS 2.5 data bytes per sector
.const A8_CATALOG_SECTORS            = 140   // ceil(279 / 2)
.const A8_CATALOG_SLOT_SECTORS       = 32    // 4 KB slot / 128-byte sectors
.const A8_CATALOG_SLOT_COUNT         = 5
.assert "Atari catalog records fit a DOS 2.5 sector", A8_CATALOG_RECORDS_PER_SECTOR * CATALOG_RECORD_SIZE <= A8_CATALOG_SECTOR_DATA, true
.assert "Atari catalog sectors fit the 130XE slots", A8_CATALOG_SLOT_COUNT * A8_CATALOG_SLOT_SECTORS >= A8_CATALOG_SECTORS, true

.const CATALOG_NAME_POOL_BASE = PLATFORM_TIER_NAME_POOL_BASE
.const CATALOG_NAME_POOL_END  = PLATFORM_TIER_NAME_POOL_END

.macro CatalogWinBegin() {
}
.macro CatalogWinEnd() {
}
.macro CatalogMap() {
}
.macro CatalogUnmap() {
}
.macro CatalogPoolWrite() {
    sta (zp_ptr1),y
}

// The level index: in the $F000 runtime (ATARI.BNK), RAM read with the game's
// banking (PORTB $FE), where the picker reads it; Default has no room.
.segment RuntimeBanked
#import "../shared/catalog/catalog_index.s"
.segment Default
.assert "Atari catalog sectors hold every record", A8_CATALOG_SECTORS * A8_CATALOG_RECORDS_PER_SECTOR >= CATALOG_COUNT, true

cat_record:     .fill CATALOG_RECORD_SIZE, 0   // The record catalog_fetch_record read
cat_start_lo:   .byte 0                        // MONSTER.CAT's first sector (0: not found)
cat_start_hi:   .byte 0
a8_cat_sec:     .byte 0                        // Record sector: id / 2
a8_cat_off:     .byte 0                        // Record in its sector: 0 or 49
a8_cat_left:    .byte 0                        // Sectors still to walk or stage
a8_cat_slot:    .byte 0                        // Preload: the catalog slot (0..4)
a8_cat_xe_slots:
    .byte 10, 11, 12, 13, 15                   // The 130XE slots, in record order
a8_cat_name:
    .text "MONSTER.CAT"
.const A8_CAT_NAME_LEN = * - a8_cat_name

// catalog_boot_load — tier_init, each title: find MONSTER.CAT.
.label catalog_boot_load = a8_cat_find

// a8_cat_find — cat_start = MONSTER.CAT's first sector on the program
// disk; C = 1 (and cat_start 0) when the disk has none.
// Clobbers: A, X, Y
a8_cat_find:
    lda program_device
    sta atari_io_device
    lda #A8_CAT_NAME_LEN
    sta atari_io_cnt
    lda #<a8_cat_name
    sta atari_io_src
    lda #>a8_cat_name
    sta atari_io_src_hi
    jsr atari_format_83
    jsr atari_find_dir_entry
    bcs !acf_none+
    lda atari_io_sec_lo
    sta cat_start_lo
    lda atari_io_sec_hi
    sta cat_start_hi
    clc
    rts
!acf_none:
    lda #0
    sta cat_start_lo
    sta cat_start_hi
    sec
    rts

// a8_cat_read — Sector A (lo) / X (hi) of the program disk into
// sio_sector_buf. C = 1 on an SIO error.
// Clobbers: A, X, Y
a8_cat_read:
    sta DCB_DAUX1
    stx DCB_DAUX2
    lda #'R'
    sta DCB_DCOMND
    lda #$40
    sta DCB_DSTATS
    lda #<sio_sector_buf
    sta DCB_DBUFLO
    lda #>sio_sector_buf
    sta DCB_DBUFHI
    lda #128
    sta DCB_DBYTLO
    lda #0
    sta DCB_DBYTHI
    jsr EnterSio
    jmp ExitSio

// a8_cat_sector_n — A (lo) / X (hi) = cat_start + A.
// Clobbers: A, X
a8_cat_sector_n:
    clc
    adc cat_start_lo
    pha
    lda cat_start_hi
    adc #0
    tax
    pla
    rts

// catalog_fetch_record — Read creature cat_id_lo/hi's record into
// cat_record: the 130XE copy, else its sector, else the sector chain, else
// the program-disk prompt and again; it always returns the record.
// Clobbers: A, X, Y
catalog_fetch_record:
    lda cat_id_hi
    lsr
    lda cat_id_lo
    ror                         // A = id / 2, C = the odd record
    sta a8_cat_sec
    lda #0
    bcc !cfr_even+
    lda #CATALOG_RECORD_SIZE
!cfr_even:
    sta a8_cat_off
    lda xe_present
    beq !cfr_retry+
    lda a8_cat_sec
    lsr
    lsr
    lsr
    lsr
    lsr                         // The catalog slot: sector / 32
    tax
    lda a8_cat_xe_slots,x
    tax
    lda xe_slot_populated,x
    bpl !cfr_retry+
    jsr a8_cat_xe_copy
    jsr a8_cat_check
    bne !cfr_retry+
    rts
!cfr_retry:
    lda program_device
    sta atari_io_device
    lda cat_start_lo
    ora cat_start_hi
    bne !cfr_have+
    jsr a8_cat_find
    bcs !cfr_prompt+
!cfr_have:
    lda a8_cat_sec
    jsr a8_cat_sector_n
    jsr a8_cat_read
    bcs !cfr_walk+
    jsr a8_cat_take
    beq !cfr_ok+
!cfr_walk:
    // Down the chain from the first sector: a8_cat_sec links.
    lda a8_cat_sec
    sta a8_cat_left
    lda cat_start_lo
    sta atari_io_sec_lo
    lda cat_start_hi
    sta atari_io_sec_hi
!cfr_walk_read:
    lda atari_io_sec_lo
    ldx atari_io_sec_hi
    jsr a8_cat_read
    bcs !cfr_prompt+
    lda a8_cat_left
    beq !cfr_walk_take+
    dec a8_cat_left
    lda sio_sector_buf + DOS25_LINK_HI
    and #$03
    sta atari_io_sec_hi
    lda sio_sector_buf + DOS25_LINK_LO
    sta atari_io_sec_lo
    ora atari_io_sec_hi
    bne !cfr_walk_read-
    beq !cfr_prompt+            // The chain ended short
!cfr_walk_take:
    jsr a8_cat_take
    beq !cfr_ok+
!cfr_prompt:
    lda #A8_CAT_NAME_LEN
    sta alr_len
    lda #<a8_cat_name
    sta alr_name_lo
    lda #>a8_cat_name
    sta alr_name_hi
    lda #0
    sta alr_left
    jsr asset_load_ask_for_disk
    // The prompt cleared the screen: redraw it all at the next render.
    lda #1
    sta vis_room_revealed
    lda #0
    sta status_cache_valid
    sta cat_start_lo            // Find the file again on the disk now in
    sta cat_start_hi
    jmp !cfr_retry-
!cfr_ok:
    rts

// a8_cat_take — The record at a8_cat_off of sio_sector_buf into
// cat_record; Z = 1 when it is creature cat_id's.
// Clobbers: A, X, Y
a8_cat_take:
    ldx a8_cat_off
    ldy #0
!act_copy:
    lda sio_sector_buf,x
    sta cat_record,y
    inx
    iny
    cpy #CATALOG_RECORD_SIZE
    bne !act_copy-
                                // fall through
// a8_cat_check — Z = 1 when cat_record is creature cat_id's record.
// Clobbers: A
a8_cat_check:
    lda cat_record
    cmp cat_id_lo
    bne !acc_done+
    lda cat_record + 1
    cmp cat_id_hi
!acc_done:
    rts

// a8_cat_xe_copy — The record from 130XE slot X: its window + (sector %
// 32) * 128 + a8_cat_off, with interrupts and NMIs off while the bank is
// in (ATARI8_MEMORY_CONTRACT.md, 130XE Cache Execution Rules).
// Clobbers: A, Y
a8_cat_xe_copy:
    lda a8_cat_sec
    lsr                         // C = an odd sector: its upper half page
    lda #0
    ror
    ora a8_cat_off
    sta atari_io_src
    lda a8_cat_sec
    and #A8_CATALOG_SLOT_SECTORS - 1
    lsr
    clc
    adc xe_slot_win_hi,x
    sta atari_io_src_hi
    php
    sei
    lda #$00
    sta NMIEN
    lda xe_slot_portb,x
    sta PORTB
    ldy #CATALOG_RECORD_SIZE - 1
!axc_copy:
    lda (atari_io_src),y
    sta cat_record,y
    dey
    bpl !axc_copy-
    lda #PORTB_GAME_RAM
    sta PORTB
    sta NMIRES
    lda #$c0
    sta NMIEN
    plp
    rts

// a8_catalog_xe_preload — At boot on a 130XE: every record sector, 32 to a
// slot, staged through the $E000 window and stashed (the caller reloads the
// overlays after). An SIO error stops it; those records read from the disk.
// Clobbers: A, X, Y
a8_catalog_xe_preload:
    jsr a8_cat_find
    bcs !axp_done+
    lda #0
    sta a8_cat_sec
    sta a8_cat_slot
!axp_slot:
    jsr xe_show_progress
    lda #<BANKED_DATA_BASE
    sta atari_io_dst
    lda #>BANKED_DATA_BASE
    sta atari_io_dst_hi
    lda #A8_CATALOG_SLOT_SECTORS
    sta a8_cat_left
!axp_sector:
    lda a8_cat_sec
    cmp #A8_CATALOG_SECTORS
    bcs !axp_stash+
    jsr a8_cat_sector_n
    jsr a8_cat_read
    bcs !axp_done+
    ldy #127
!axp_copy:
    lda sio_sector_buf,y
    sta (atari_io_dst),y
    dey
    bpl !axp_copy-
    lda atari_io_dst
    eor #$80                    // The next 128 bytes
    sta atari_io_dst
    bmi !axp_next+
    inc atari_io_dst_hi
!axp_next:
    inc a8_cat_sec
    dec a8_cat_left
    bne !axp_sector-
!axp_stash:
    ldx a8_cat_slot
    lda a8_cat_xe_slots,x
    tax
    jsr xe_cache_stash
    inc a8_cat_slot
    lda a8_cat_slot
    cmp #A8_CATALOG_SLOT_COUNT
    bcc !axp_slot-
!axp_done:
    rts
