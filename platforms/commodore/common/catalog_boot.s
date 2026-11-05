#importonce
// catalog_boot.s — Boot-time loads for the monster catalog on the C64 and
// Plus/4 (catalog_fetch.s): once, before the title screen. The C64 places
// it in the init-only tail.

// catalog_boot_load — MONSTER.IDX (the level index and the record sectors'
// places on this disk) into the hidden span, through a buffer in the map:
// the $E000 window holds the overlay the title menus use, and a game loaded
// from a save disk left in the drive must not need the program disk again.
// Clobbers: A, X, Y
catalog_boot_load:
    lda #cbl_idx_name_end - cbl_idx_name
    ldx #<cbl_idx_name
    ldy #>cbl_idx_name
    jsr asset_load_required     // PRG at CATALOG_IDX_LOAD (memory.s)
    :CatalogMap()
    ldx #0
!cbl_copy:
    lda CATALOG_IDX_LOAD,x
    sta cat_level_raw,x
    inx
    cpx #CATALOG_IDX_SIZE
    bne !cbl_copy-
    :CatalogUnmap()
    rts

#if CATALOG_REU
// catalog_reu_preload — With an REU (tier_init's loading screen up),
// MONSTER.CAT1-4 into it at $0000-$3FFF; the overlays stash after them.
// Clobbers: A, X, Y, zp_ptr0
catalog_reu_preload:
    jsr overlay_invalidate      // The loads replace whatever overlay $E000 held
    lda #$31                    // "1"
    sta cbl_cat_digit
!cbl_file:
    lda #<cbl_cat_name
    sta zp_ptr0
    lda #>cbl_cat_name
    sta zp_ptr0_hi
    jsr reu_show_file
    lda #cbl_cat_name_end - cbl_cat_name
    ldx #<cbl_cat_name
    ldy #>cbl_cat_name
    jsr asset_load_required     // PRG at CATALOG_RECORDS_LOAD
    // The REU copy: file n at (n - 1) * $1000, as loaded.
    sei
    lda hal_memory_cpu_port
    pha
    lda #BANK_NO_KERNAL         // The DMA reads RAM at $E000
    sta hal_memory_cpu_port
    lda #<CATALOG_RECORDS_LOAD
    sta REU_C64LO
    lda #>CATALOG_RECORDS_LOAD
    sta REU_C64HI
    lda #0
    sta REU_REULO
    sta REU_BANK
    sta REU_CONTROL
    lda cbl_cat_digit
    sec
    sbc #$31
    asl
    asl
    asl
    asl
    sta REU_REUHI
    lda #<(CATALOG_FILE_SECTORS * 254 - CATALOG_SECTOR_HEADER)
    sta REU_LENLO
    lda #>(CATALOG_FILE_SECTORS * 254 - CATALOG_SECTOR_HEADER)
    sta REU_LENHI
    lda #REU_CMD_STASH
    sta REU_COMMAND
    pla
    sta hal_memory_cpu_port
    cli
    jsr reu_show_status
    inc cbl_cat_digit
    lda cbl_cat_digit
    cmp #$31 + CATALOG_RECORD_FILES
    bne !cbl_file-
    // The overlays stash after the catalog.
    lda #0
    sta reu_tier_offset_lo
    lda #>(CATALOG_RECORD_FILES * $1000)
    sta reu_tier_offset_hi
    rts
#endif
.assert "The catalog's REU copy fits below the 64 KB of bank 0", CATALOG_RECORD_FILES * $1000 <= $10000, true

// File names: PETSCII capitals, digits and '.' share the screen codes.
cbl_idx_name: .text "MONSTER.IDX"
cbl_idx_name_end:
cbl_cat_name: .text "MONSTER.CAT"
cbl_cat_digit: .text "1"
cbl_cat_name_end:
    .byte 0                     // reu_show_file reads a 0-terminated name
