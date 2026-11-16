#importonce
// catalog_fetch.s — The monster catalog on the C64 and Plus/4: whole records
// from the REU or the drive (docs/MONSTER_CATALOG_DESIGN.md, "C64 and
// Plus/4"; core/monster_catalog.s calls catalog_fetch_record).
//
// The port defines, before importing this file:
// - CATALOG_HIDDEN_BASE/END: hidden RAM for the level index and the sector
//   table (memory.s owns the span; MONSTER.IDX fills it at boot);
// - CATALOG_NAME_POOL_BASE/END: the species name pool (hidden RAM);
// - :CatalogMap() / :CatalogUnmap(): make the hidden RAM readable and
//   writable / restore the caller's banking (C64: all RAM, interrupts off);
// - :CatalogKernalIn() / :CatalogKernalOut(): the KERNAL visible for the
//   drive transaction / the caller's banking back (C64: a summon cast from an
//   overlay runs with the KERNAL banked out; Plus/4: its wrappers bank);
// - CATALOG_REU when the REU path is built (C64);
// - CATALOG_EXT_DISK_ENABLED when Phase 5 MONSTER.EXT (9 sectors, 31 x 8 B
//   per sector) is wired on the port's disk / REU path.
//
// Most species are fetched while a level is generated; a new arrival or a
// summon of a species not yet on the level fetches during play (maintainer,
// 2026-11-05: "if we need to ad-hoc load a couple of monsters during the
// gameplay on non-REU systems, I think that is OK").

#import "catalog_records.s"
.const CFR_LFN = 5              // The buffer channel (shared with ICR_LFN)
.const CATALOG_EXT_RECORD_SIZE        = 8
.const CATALOG_EXT_RECORDS_PER_SECTOR = 31
.const CATALOG_EXT_SECTORS            = 9
.const CATALOG_EXT_LOAD               = $e000

// The index the picker reads and the record sectors' places on the disk, in
// MONSTER.IDX order (tools/catalog_disk.py): labels only, the data is loaded.
.segmentdef CatalogHidden [start=CATALOG_HIDDEN_BASE, virtual]
.segment CatalogHidden
#import "../../shared/catalog/catalog_index.s"
cat_sector_track:  .fill CATALOG_RECORD_SECTORS, 0
cat_sector_number: .fill CATALOG_RECORD_SECTORS, 0
#if CATALOG_EXT_DISK_ENABLED
cat_ext_sector_track:  .fill CATALOG_EXT_SECTORS, 0
cat_ext_sector_number: .fill CATALOG_EXT_SECTORS, 0
#endif
cat_hidden_end:
.segment Default
.const CATALOG_IDX_SIZE = cat_hidden_end - cat_level_raw
.assert "Catalog index starts the hidden span", cat_level_raw, CATALOG_HIDDEN_BASE
.assert "Catalog index and sector table fit the hidden span", cat_hidden_end - 1 <= CATALOG_HIDDEN_END, true
.assert "Catalog sector table follows the index (MONSTER.IDX order)", cat_sector_track, catalog_index_end
.assert "Catalog index fits one load window", CATALOG_IDX_SIZE <= $1000, true

#if PLATFORM_CAT_RECORD_EXTERNAL
.label cat_record = PLATFORM_CAT_RECORD_BASE   // a port's free RAM (the C64: page 3)
.assert "The record buffer is the size config.s gives it", CATALOG_RECORD_SIZE, 49
#else
cat_record:   .fill CATALOG_RECORD_SIZE, 0   // The record catalog_fetch_record read
#endif
#if CATALOG_EXT_DISK_ENABLED
#if PLATFORM_CAT_EXT_RECORD_EXTERNAL
.label cat_ext_record = PLATFORM_CAT_EXT_RECORD_BASE
#else
cat_ext_record: .fill CATALOG_EXT_RECORD_SIZE, 0
#endif
#endif
cfr_group:    .byte 0                       // Record sector (id / records per sector)
cfr_offset:   .byte 0                       // Byte of the record in its sector's data
cfr_track:    .byte 0
cfr_sector:   .byte 0
cfr_idx:      .byte 0                       // Loop index across the KERNAL calls (the
                                            // Plus/4 wrappers return X = the stack)
cfr_skip_lo:  .byte 0                       // Bytes to skip in the by-name read
cfr_skip_hi:  .byte 0

// catalog_fetch_record — Read creature cat_id_lo/hi's record into cat_record.
// Clobbers: A, X, Y, zp_temp0-3, nf_value_2 (the drive path's digits)
// Called unmapped. The drive path reads the record's sector directly via split
// U1 -> icr_drive_ok -> B-P commands (#367 #7); a refused '#' channel or read
// error aborts before CHKIN 5 and falls back to reading MONSTER.CATn by name,
// and only when that fails too does the game ask for the program disk.
catalog_fetch_record:
    // Sector and place: id / and % CATALOG_RECORDS_PER_SECTOR (id <= 278).
    lda cat_id_lo
    sta cfr_track
    lda cat_id_hi
    sta cfr_sector
    ldx #0
!cfr_div:
    lda cfr_track
    sec
    sbc #CATALOG_RECORDS_PER_SECTOR
    tay
    lda cfr_sector
    sbc #0
    bcc !cfr_div_done+
    sta cfr_sector
    sty cfr_track
    inx
    bne !cfr_div-
!cfr_div_done:
    stx cfr_group
    ldx cfr_track               // The record within its sector
    lda cfr_record_offset,x
    sta cfr_offset
    // The KERNAL and I/O in, for the REU's registers or the drive: a pick can
    // come from code running with every ROM and I/O banked out (pits and
    // nests are placed from the C64's $F000 runtime).
    :CatalogKernalIn()
#if CATALOG_REU
    lda reu_present
    beq !cfr_disk+
    jsr cfr_from_reu
    :CatalogKernalOut()
    rts
!cfr_disk:
#endif
    :CatalogMap()
    ldx cfr_group
    lda cat_sector_track,x
    sta cfr_track
    lda cat_sector_number,x
    sta cfr_sector
    :CatalogUnmap()
!cfr_retry:
    lda cfr_track
    beq !cfr_by_name+
    jsr cfr_open_cmd_and_buf
    lda cfr_track
    sta icr_track
    lda cfr_sector
    sta icr_sector
    clc
    lda cfr_offset
    adc #2                      // Skip 2-byte T/S link in 1541 '#' buffer
    jsr icr_send_u1_bp
    bcs !cfr_u1_err+
    jsr cfr_read_record
    lda #15
    jsr hal_storage_close
    jsr cfr_check
    beq !cfr_ok+
    bne !cfr_by_name+
!cfr_u1_err:
    jsr icr_close_buf
    lda #15
    jsr hal_storage_close
!cfr_by_name:
    // By name: MONSTER.CATn, skipping to the record (s * 254 + its offset).
    lda cfr_group
    lsr
    lsr
    lsr
    lsr
    clc
    adc #$31
    sta cfr_name_digit
    lda #cfr_name_digit + 1 - cfr_name
    ldx #<cfr_name
    ldy #>cfr_name
    jsr hal_storage_setnam
    lda #CFR_LFN
    ldx program_device
    ldy #CFR_LFN
    jsr hal_storage_setlfs
    jsr hal_storage_open
    lda cfr_group
    and #CATALOG_FILE_SECTORS - 1
    sta cfr_skip_hi             // s * 256 ...
    asl
    sta cfr_skip_lo
    lda cfr_offset
    sec
    sbc cfr_skip_lo             // ... - 2s + the offset
    sta cfr_skip_lo
    lda cfr_skip_hi
    sbc #0
    sta cfr_skip_hi
    ldx #CFR_LFN
    jsr hal_storage_chkin
!cfr_skip:
    lda cfr_skip_lo
    ora cfr_skip_hi
    beq !cfr_skipped+
    jsr hal_storage_chrin
    lda cfr_skip_lo
    bne !cfr_skip_lo+
    dec cfr_skip_hi
!cfr_skip_lo:
    dec cfr_skip_lo
    jmp !cfr_skip-
!cfr_skipped:
    jsr cfr_read_record
    jsr cfr_check
    beq !cfr_ok+
    jmp !cfr_wrong+
!cfr_ok:
    :CatalogKernalOut()
    rts
!cfr_wrong:
    lda #cfr_name_end - cfr_name
    sta alr_len
    lda #<cfr_name
    sta alr_name_lo
    lda #>cfr_name
    sta alr_name_hi
    lda #0
    sta alr_left
    jsr asset_load_ask_for_disk
    // The prompt cleared the screen: redraw it all at the next render.
    lda #1
    sta vis_room_revealed
    lda #0
    sta status_cache_valid
    jmp !cfr_retry-

// cfr_open_cmd_and_buf — OPEN 15,dev,15 and OPEN 5,dev,5,"#" (with cfr_hash < $8000).
// Clobbers: A, X, Y
cfr_open_cmd_and_buf:
    lda #0
    jsr hal_storage_setnam
    lda #15
    ldx program_device
    ldy #15
    jsr hal_storage_setlfs
    jsr hal_storage_open
    lda #1
    ldx #<cfr_hash
    ldy #>cfr_hash
    jsr hal_storage_setnam
    lda #CFR_LFN
    ldx program_device
    ldy #CFR_LFN
    jsr hal_storage_setlfs
    jmp hal_storage_open

// cfr_read_record — CATALOG_RECORD_SIZE bytes from the buffer channel (its
// input already selected for the by-name read) into cat_record; close it.
// Clobbers: A, X
cfr_read_record:
    ldx #CFR_LFN
    jsr hal_storage_chkin
    lda #0
    sta cfr_idx
!crr_read:
    jsr hal_storage_chrin
    ldx cfr_idx
    sta cat_record,x
    inx
    stx cfr_idx
    cpx #CATALOG_RECORD_SIZE
    bne !crr_read-
    jmp icr_close_buf

// cfr_check — Z = 1 when cat_record is creature cat_id's record.
// Clobbers: A
cfr_check:
    lda cat_record
    cmp cat_id_lo
    bne !cc_done+
    lda cat_record + 1
    cmp cat_id_hi
!cc_done:
    rts

#if CATALOG_REU
// cfr_from_reu — The record from the REU copy of MONSTER.CAT1-4: file
// group / CATALOG_FILE_SECTORS at $1000 per file, then as loaded at $E000
// (the 2-byte header gone): sector s at s * 254, the record at its offset - 2.
cfr_from_reu:
    lda cfr_group
    and #CATALOG_FILE_SECTORS - 1
    sta cfr_track               // s
    asl
    sta cfr_sector              // 2s
    lda cfr_offset
    sec
    sbc #CATALOG_SECTOR_HEADER
    sec
    sbc cfr_sector              // s * 254 = s * 256 - 2s
    sta REU_REULO
    lda cfr_track
    sbc #0
    sta cfr_sector
    lda cfr_group
    and #$ff - (CATALOG_FILE_SECTORS - 1)   // The file's $1000 step
    clc
    adc cfr_sector
    sta REU_REUHI
    lda #0
    sta REU_BANK
    sta REU_LENHI
    sta REU_CONTROL
    lda #<cat_record
    sta REU_C64LO
    lda #>cat_record
    sta REU_C64HI
    lda #CATALOG_RECORD_SIZE
    sta REU_LENLO
    lda #REU_CMD_FETCH
    sta REU_COMMAND             // The DMA completes before the next instruction
    rts
.assert "Catalog files are 16 sectors, $1000 apart in the REU", CATALOG_FILE_SECTORS, 16
#endif

#if CATALOG_EXT_DISK_ENABLED
#if !CATALOG_EXT_REU_CUSTOM
.const CATALOG_EXT_REU_BANK = 1
.const CATALOG_EXT_REU_BASE = $2000
#endif

// catalog_fetch_ext — Read creature cat_id_lo/hi's 8 extended Phase 5 bytes
// into cat_ext_record from REU Bank 1 ($2000) or 9-sector MONSTER.EXT.
// Clobbers: A, X, Y, zp_temp0-3, nf_value_2
catalog_fetch_ext:
    lda cat_id_lo
    sta cfr_track
    lda cat_id_hi
    sta cfr_sector
    ldx #0
!cfe_div:
    lda cfr_track
    sec
    sbc #CATALOG_EXT_RECORDS_PER_SECTOR
    tay
    lda cfr_sector
    sbc #0
    bcc !cfe_div_done+
    sta cfr_sector
    sty cfr_track
    inx
    bne !cfe_div-
!cfe_div_done:
    stx cfr_group               // s = id / 31 (0..8)
    lda cfr_track               // r = id % 31 (0..30)
    asl
    asl
    asl                         // r * 8 (0..240)
    clc
    adc #CATALOG_SECTOR_HEADER  // 2 + r * 8 (2..242)
    sta cfr_offset
    :CatalogKernalIn()
#if CATALOG_REU
    lda reu_present
    beq !cfe_disk+
    jsr cfr_ext_from_reu
    :CatalogKernalOut()
    rts
!cfe_disk:
#endif
    :CatalogMap()
    ldx cfr_group
    lda cat_ext_sector_track,x
    sta cfr_track
    lda cat_ext_sector_number,x
    sta cfr_sector
    :CatalogUnmap()
!cfe_retry:
    lda cfr_track
    beq !cfe_by_name+
    jsr cfr_open_cmd_and_buf
    lda cfr_track
    sta icr_track
    lda cfr_sector
    sta icr_sector
    clc
    lda cfr_offset
    adc #2                      // Skip 2-byte T/S link in '#' buffer
    jsr icr_send_u1_bp
    bcs !cfe_u1_err+
    jsr cfr_read_ext_record
    lda #15
    jsr hal_storage_close
    jmp !cfe_ok+
!cfe_u1_err:
    jsr icr_close_buf
    lda #15
    jsr hal_storage_close
!cfe_by_name:
    lda #cfr_ext_name_end - cfr_ext_name
    ldx #<cfr_ext_name
    ldy #>cfr_ext_name
    jsr hal_storage_setnam
    lda #CFR_LFN
    ldx program_device
    ldy #CFR_LFN
    jsr hal_storage_setlfs
    jsr hal_storage_open
    lda cfr_group
    sta cfr_skip_hi             // s * 256 ...
    asl
    sta cfr_skip_lo
    lda cfr_offset
    sec
    sbc cfr_skip_lo             // ... - 2s + cfr_offset
    sta cfr_skip_lo
    lda cfr_skip_hi
    sbc #0
    sta cfr_skip_hi
    ldx #CFR_LFN
    jsr hal_storage_chkin
    jsr hal_storage_readst
    and #$bf
    bne !cfe_by_name_err+
!cfe_skip:
    lda cfr_skip_lo
    ora cfr_skip_hi
    beq !cfe_skipped+
    jsr hal_storage_chrin
    jsr hal_storage_readst
    and #$bf
    bne !cfe_by_name_err+
    lda cfr_skip_lo
    bne !cfe_skip_lo+
    dec cfr_skip_hi
!cfe_skip_lo:
    dec cfr_skip_lo
    jmp !cfe_skip-
!cfe_skipped:
    jsr cfr_read_ext_record
!cfe_ok:
    :CatalogKernalOut()
    rts
!cfe_by_name_err:
    jsr icr_close_buf
    lda #cfr_ext_name_end - cfr_ext_name
    sta alr_len
    lda #<cfr_ext_name
    sta alr_name_lo
    lda #>cfr_ext_name
    sta alr_name_hi
    lda #0
    sta alr_left
    jsr asset_load_ask_for_disk
    lda #1
    sta vis_room_revealed
    lda #0
    sta status_cache_valid
    jmp !cfe_retry-

cfr_read_ext_record:
    ldx #CFR_LFN
    jsr hal_storage_chkin
    lda #0
    sta cfr_idx
!crer_read:
    jsr hal_storage_chrin
    ldx cfr_idx
    sta cat_ext_record,x
    inx
    stx cfr_idx
    cpx #CATALOG_EXT_RECORD_SIZE
    bne !crer_read-
    jmp icr_close_buf

#if CATALOG_REU
// cfr_ext_from_reu — Fetch 8 bytes from REU Bank 1 ($2000 + s * 254 + r * 8).
cfr_ext_from_reu:
    lda cfr_group
    sta cfr_track               // s (0..8)
    asl
    sta cfr_sector              // 2s
    lda cfr_offset
    sec
    sbc #CATALOG_SECTOR_HEADER
    sec
    sbc cfr_sector              // lo(s * 254 + r * 8); C = 0 on borrow
    tay
    lda cfr_track
    sbc #0                      // hi(s * 254 + r * 8)
    tax
    tya
    clc
    adc #<CATALOG_EXT_REU_BASE
    sta REU_REULO
    txa
    adc #>CATALOG_EXT_REU_BASE
    sta REU_REUHI
    lda #CATALOG_EXT_REU_BANK
    sta REU_BANK
    lda #0
    sta REU_LENHI
    sta REU_CONTROL
    lda #<cat_ext_record
    sta REU_C64LO
    lda #>cat_ext_record
    sta REU_C64HI
    lda #CATALOG_EXT_RECORD_SIZE
    sta REU_LENLO
    lda #REU_CMD_FETCH
    sta REU_COMMAND
    rts
#endif

cfr_ext_name: .text "MONSTER.EXT"
cfr_ext_name_end:
#endif

// Buffer channel's '#' filename and MONSTER.CAT1-4 filename (< $8000 on Plus/4).
cfr_hash: .text "#"
cfr_name: .text "MONSTER.CAT"
cfr_name_end:
cfr_name_digit: .text "1"                   // The by-name read's file
cfr_record_offset:
    .fill CATALOG_RECORDS_PER_SECTOR, CATALOG_SECTOR_HEADER + i * CATALOG_RECORD_SIZE
.assert "Catalog drive commands name the buffer channel", CFR_LFN, 5
