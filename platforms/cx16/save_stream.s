#importonce
// save_stream.s — Commander X16 KERNAL byte-stream backend for the shared
// save engine (platforms/shared/save.s, save_slot_menu.s, and core/score_io.s).
//
// All entry points reside in fixed low RAM ($0801-$9AFF) and save/restore
// CX16_RAM_BANK_REG ($00) while selecting RAM Bank 0 (KVARSB0) and ROM Bank 0
// (KERNAL) for the underlying CX16 KERNAL call, so callers executing inside
// $A000-$BFFF overlays (OVL.STORAGE, OVL.DEATH) can invoke SAVE_* / SCORE_*
// directly.

#import "hal/hal_contract.s"
#import "hal/storage_policy.s"

.const KERNAL_READST = $ffb7
.const KERNAL_SETNAM = $ffbd
.const KERNAL_SETLFS = $ffba
.const KERNAL_OPEN   = $ffc0
.const KERNAL_CLOSE  = $ffc3
.const KERNAL_CHKIN  = $ffc6
.const KERNAL_CHKOUT = $ffc9
.const KERNAL_CLRCHN = $ffcc
.const KERNAL_CHRIN  = $ffcf
.const KERNAL_CHROUT = $ffd2
.const KERNAL_LOAD   = $ffd5

// ============================================================
// hal_storage_setnam — KERNAL SETNAM wrapper.
// Input: A = name length, X = name lo, Y = name hi.
// ============================================================
hal_storage_setnam:
    pha
    lda CX16_RAM_BANK_REG
    sta cx16_ss_saved_bank
    stz CX16_RAM_BANK_REG
    stz CX16_ROM_BANK_REG
    pla
    jsr KERNAL_SETNAM
    bra cx16_ss_restore_bank

// ============================================================
// hal_storage_setlfs — KERNAL SETLFS wrapper.
// Input: A = logical file number, X = device, Y = secondary address.
// ============================================================
hal_storage_setlfs:
    stx hal_storage_diag_device
    pha
    lda CX16_RAM_BANK_REG
    sta cx16_ss_saved_bank
    stz CX16_RAM_BANK_REG
    stz CX16_ROM_BANK_REG
    pla
    jsr KERNAL_SETLFS
    bra cx16_ss_restore_bank

// ============================================================
// hal_storage_open — KERNAL OPEN wrapper.
// ============================================================
hal_storage_open:
    lda CX16_RAM_BANK_REG
    sta cx16_ss_saved_bank
    stz CX16_RAM_BANK_REG
    stz CX16_ROM_BANK_REG
    jsr KERNAL_OPEN
    php
    sta hal_storage_diag_code
    lda cx16_ss_saved_bank
    sta CX16_RAM_BANK_REG
    lda hal_storage_diag_code
    plp
    rts

// ============================================================
// hal_storage_close — KERNAL CLOSE wrapper.
// Input: A = logical file number.
// ============================================================
hal_storage_close:
    pha
    lda CX16_RAM_BANK_REG
    sta cx16_ss_saved_bank
    stz CX16_RAM_BANK_REG
    stz CX16_ROM_BANK_REG
    pla
    jsr KERNAL_CLOSE
    bra cx16_ss_restore_bank

// ============================================================
// hal_storage_chkin / hal_storage_chkout / hal_storage_clrchn
// ============================================================
hal_storage_chkin:
    lda CX16_RAM_BANK_REG
    sta cx16_ss_saved_bank
    stz CX16_RAM_BANK_REG
    stz CX16_ROM_BANK_REG
    jsr KERNAL_CHKIN
    bra cx16_ss_restore_bank

hal_storage_chkout:
    lda CX16_RAM_BANK_REG
    sta cx16_ss_saved_bank
    stz CX16_RAM_BANK_REG
    stz CX16_ROM_BANK_REG
    jsr KERNAL_CHKOUT
cx16_ss_restore_bank:
    php
    pha
    lda cx16_ss_saved_bank
    sta CX16_RAM_BANK_REG
    pla
    plp
    rts

cx16_ss_saved_bank: .byte 0

hal_storage_clrchn:
    lda CX16_RAM_BANK_REG
    pha
    stz CX16_RAM_BANK_REG
    stz CX16_ROM_BANK_REG
    jsr KERNAL_CLRCHN
    pla
    sta CX16_RAM_BANK_REG
    clc
    rts

// ============================================================
// hal_storage_chrin — Read next byte from open stream.
// Output: A = byte. Preserves X, Y (stack-reentrant).
// ============================================================
hal_storage_chrin:
    phx
    phy
    lda CX16_RAM_BANK_REG
    pha
    stz CX16_RAM_BANK_REG
    stz CX16_ROM_BANK_REG
    jsr KERNAL_CHRIN
    tax
    pla
    sta CX16_RAM_BANK_REG
    txa
    ply
    plx
    rts

// ============================================================
// hal_storage_chrout — Write byte in A to open stream.
// Input: A = byte. Preserves A, X, Y (stack-reentrant).
// ============================================================
hal_storage_chrout:
    phx
    phy
    tax
    lda CX16_RAM_BANK_REG
    pha
    stz CX16_RAM_BANK_REG
    stz CX16_ROM_BANK_REG
    txa
    pha
    jsr KERNAL_CHROUT
    pla
    tax
    pla
    sta CX16_RAM_BANK_REG
    txa
    ply
    plx
    rts

// ============================================================
// hal_storage_readst — Return KERNAL status byte in A (Z/N set).
// Preserves X, Y (stack-reentrant).
// ============================================================
hal_storage_readst:
    phx
    phy
    lda CX16_RAM_BANK_REG
    pha
    stz CX16_RAM_BANK_REG
    stz CX16_ROM_BANK_REG
    jsr KERNAL_READST
    sta hal_storage_diag_readst
    pla
    sta CX16_RAM_BANK_REG
    ply
    plx
    lda hal_storage_diag_readst
    rts

// ============================================================
// cx16_save_block_mode — Set cx16_save_aux_mode_flag ($80) when the current
// save/load block descriptor lives in Bank 3 (Cx16AuxData: store inventory
// or monster recall data).
// ============================================================
cx16_save_block_mode:
hal_storage_save_block_mode:
    stz cx16_save_aux_mode_flag

    lda zp_ptr0_hi
    cmp #>si_item_id
    bcc !try_recall+
    bne !store_check_end+
    lda zp_ptr0
    cmp #<si_item_id
    bcc !try_recall+
!store_check_end:
    lda zp_ptr0_hi
    cmp #>store_inventory_data_end
    bcc !aux+
    bne !try_recall+
    lda zp_ptr0
    cmp #<store_inventory_data_end
    bcc !aux+
!try_recall:
    lda zp_ptr0_hi
    cmp #>recall_data_start
    bne !done+
    lda zp_ptr0
    cmp #<recall_data_start
    bne !done+
!aux:
    lda #$80
    sta cx16_save_aux_mode_flag
!done:
    rts

// ============================================================
// Banked map I/O helpers (HAL_STORAGE_MAP_BANKED).
// Streams MAP_BASE ($2000-$530B in RAM Banks 1-2) in page bursts via
// CX16_ROW_STAGE_BASE ($0700) to avoid per-byte bank toggling.
// Because save_cksum_*, save_count_*, and save_io_error reside in OVL.STORAGE
// (Bank 19 at $A000-$BFFF), the page loop keeps its working counters and
// running checksum in fixed low RAM (cx16_map_*) while $00 is switched to
// Bank 0/1/2, then writes the final checksum/error back after restoring $00.
// ============================================================
cx16_map_pages_left: .byte 0
cx16_map_cksum_lo:   .byte 0
cx16_map_cksum_hi:   .byte 0

save_write_map_banked:
    lda CX16_RAM_BANK_REG
    pha
    lda save_cksum_lo
    sta cx16_map_cksum_lo
    lda save_cksum_hi
    sta cx16_map_cksum_hi
    stz CX16_ROM_BANK_REG
    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi
    lda #>MAP_SIZE
    sta cx16_map_pages_left
!swm_page_loop:
    lda cx16_map_pages_left
    bne !swm_full_page+
    ldx #<MAP_SIZE
    bra !swm_stage+
!swm_full_page:
    ldx #0                          // 0 = 256 bytes
!swm_stage:
    stx cx16_zp_scratch
    // Map the active 8 KB map bank (Bank 1 or Bank 2) once for this page
    lda zp_ptr0_hi
    lsr
    lsr
    lsr
    lsr
    lsr
    sta CX16_RAM_BANK_REG
    lda zp_ptr0_hi
    and #$1f
    ora #$a0
    sta zp_ptr1_hi
    lda zp_ptr0
    sta zp_ptr1
    ldy #0
!swm_copy_from_bank:
    lda (zp_ptr1),y
    sta CX16_ROW_STAGE_BASE,y
    iny
    dex
    bne !swm_copy_from_bank-
    // Switch to KERNAL RAM Bank 0 once and stream the staged page
    stz CX16_RAM_BANK_REG
    ldx cx16_zp_scratch
    ldy #0
!swm_stream_page:
    lda CX16_ROW_STAGE_BASE,y
    clc
    adc cx16_map_cksum_lo
    sta cx16_map_cksum_lo
    bcc !swm_no_carry+
    inc cx16_map_cksum_hi
!swm_no_carry:
    lda CX16_ROW_STAGE_BASE,y
    phy
    phx
    jsr KERNAL_CHROUT
    jsr KERNAL_READST
    plx
    ply
    and #$03
    beq !swm_next_byte+
    pla
    sta CX16_RAM_BANK_REG
    lda cx16_map_cksum_lo
    sta save_cksum_lo
    lda cx16_map_cksum_hi
    sta save_cksum_hi
    inc save_io_error
    sec
    rts
!swm_next_byte:
    iny
    dex
    bne !swm_stream_page-
    inc zp_ptr0_hi
    lda cx16_map_pages_left
    beq !swm_done+
    dec cx16_map_pages_left
    bra !swm_page_loop-
!swm_done:
    pla
    sta CX16_RAM_BANK_REG
    lda cx16_map_cksum_lo
    sta save_cksum_lo
    lda cx16_map_cksum_hi
    sta save_cksum_hi
    clc
    rts

load_read_map_banked:
    lda save_io_error
    beq !lrm_begin+
    rts
!lrm_begin:
    lda CX16_RAM_BANK_REG
    pha
    lda save_cksum_lo
    sta cx16_map_cksum_lo
    lda save_cksum_hi
    sta cx16_map_cksum_hi
    lda #<MAP_BASE
    sta zp_ptr0
    lda #>MAP_BASE
    sta zp_ptr0_hi
    lda #>MAP_SIZE
    sta cx16_map_pages_left
!lrm_page_loop:
    lda cx16_map_pages_left
    bne !lrm_full_page+
    ldx #<MAP_SIZE
    bra !lrm_read_page+
!lrm_full_page:
    ldx #0                          // 0 = 256 bytes
!lrm_read_page:
    stx cx16_zp_scratch
    stz CX16_RAM_BANK_REG
    stz CX16_ROM_BANK_REG
    ldy #0
!lrm_read_byte_loop:
    phy
    phx
    jsr KERNAL_CHRIN
    pha
    jsr KERNAL_READST
    and #$02
    beq !lrm_status_ok+
    pla
    plx
    ply
    pla
    sta CX16_RAM_BANK_REG
    lda cx16_map_cksum_lo
    sta save_cksum_lo
    lda cx16_map_cksum_hi
    sta save_cksum_hi
    inc save_io_error
    rts
!lrm_status_ok:
    pla
    plx
    ply
    sta CX16_ROW_STAGE_BASE,y
    clc
    adc cx16_map_cksum_lo
    sta cx16_map_cksum_lo
    bcc !lrm_no_carry+
    inc cx16_map_cksum_hi
!lrm_no_carry:
    iny
    dex
    bne !lrm_read_byte_loop-
    // Copy the staged page into Bank 1 or Bank 2 in a single bank switch
    lda zp_ptr0_hi
    lsr
    lsr
    lsr
    lsr
    lsr
    sta CX16_RAM_BANK_REG
    lda zp_ptr0_hi
    and #$1f
    ora #$a0
    sta zp_ptr1_hi
    lda zp_ptr0
    sta zp_ptr1
    ldx cx16_zp_scratch
    ldy #0
!lrm_write_bank_loop:
    lda CX16_ROW_STAGE_BASE,y
    sta (zp_ptr1),y
    iny
    dex
    bne !lrm_write_bank_loop-
    inc zp_ptr0_hi
    lda cx16_map_pages_left
    beq !lrm_done+
    dec cx16_map_pages_left
    bra !lrm_page_loop-
!lrm_done:
    pla
    sta CX16_RAM_BANK_REG
    lda cx16_map_cksum_lo
    sta save_cksum_lo
    lda cx16_map_cksum_hi
    sta save_cksum_hi
    rts
