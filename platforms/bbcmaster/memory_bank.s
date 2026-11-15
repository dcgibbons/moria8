#importonce
// memory_bank.s — BBC Master 128 Sideways RAM (ROMSEL $FE30), Private RAM ANDY,
// and Shadow RAM LYNNE (ACCCON $FE34) bank-switching helpers.
//
// Authority: docs/BBCMASTER_MEMORY_CONTRACT.md.
// All routines in this file are linked below $3000 in unbanked low RAM so they
// remain visible across every ACCCON ($3000-$7FFF) and ROMSEL ($8000-$BFFF)
// transition.

#import "memory.s"
#import "cache_layout.s"

// ============================================================
// EnterMos / ExitMos — Safe MOS / DFS Call Envelope (< $3000)
// ============================================================
// Saves core + platform ZP ($02-$AF), ensures main RAM is visible at $3000-$7FFF
// (ACCCON = $01: D=1, X=0), and restores MOS's filing-system ROM in ROMSEL
// ($FE30 = zp_mos_romsel_shadow) before calling into MOS/DFS.
EnterMos:
hal_memory_enter_os:
    php
    sei
    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    jsr save_zp
    lda beeb_boot_romsel
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    plp
    clc
    rts

ExitMos:
hal_memory_exit_os:
    php
    pha
    sei
    lda #ROMSEL_BANK4
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    jsr restore_zp
    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    pla
    plp
    rts

hal_memory_restore_runtime:
    php
    sei
    lda #ROMSEL_BANK4
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    plp
    clc
    rts

beeb_boot_romsel: .byte $00

// ============================================================
// Huffman Corpus Readers (ANDY $8000-$8FFF via ROMSEL = $84)
// ============================================================
// Setting ROMSEL = $84 maps 4 KB ANDY at $8000-$8FFF while keeping Bank 4's
// upper 12 KB ($9000-$BFFF, including overlays at $A800-$BFFF) visible!
// A pointer at BEEB_HUFFDATA_LIMIT ($9000) and up reads sideways Bank 6
// instead: the monster catalog's fields and Huffman names (cache_layout.s,
// 2026-11-05), whose name decode shares these readers with the corpus.
// Zero address arithmetic; preserves X, Y, C, I, D, V and sets N/Z from A.
mmu_safe_huff_read_ptr0:
    php
    sei
    lda zp_ptr0_hi
    cmp #>BEEB_HUFFDATA_LIMIT
    lda #ROMSEL_ANDY
    bcc !hr0+
    lda #ROMSEL_BANK6
!hr0:
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda (zp_ptr0),y
    bra mmu_romsel_store_exit

mmu_safe_huff_read_ptr1:
    php
    sei
    lda zp_ptr1_hi
    cmp #>BEEB_HUFFDATA_LIMIT
    lda #ROMSEL_ANDY
    bcc !hr1+
    lda #ROMSEL_BANK6
!hr1:
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda (zp_ptr1),y
    bra mmu_romsel_store_exit

// ============================================================
// Map & BeebAuxData Readers/Writers
// ============================================================
// Dispatches by virtual address:
//   - >= $8000 (bmi): Bank 5 Map ($8000-$B30B), zero address arithmetic.
//   - $6000-$7FFF:    Bank 6 BeebAuxData (virtual $6000-$72FF -> physical
//                     $8000-$92FF = virt + $2000 via dedicated beeb_aux_ptr).
//   - otherwise:      Main RAM.
// Preserves X, Y, C, I, D, V; sets N/Z from A on reads; preserves A on writes.
mmu_safe_map_read_ptr0:
    php
    sei
    lda zp_ptr0_hi
    bpl !cold_r0+
    lda #ROMSEL_BANK5
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda (zp_ptr0),y
mmu_romsel_store_exit:
    sta beeb_mmu_byte
mmu_romsel_exit:
    lda #ROMSEL_BANK4
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    plp
    lda beeb_mmu_byte
    rts
!cold_r0:
    sta beeb_aux_ptr_hi
    lda zp_ptr0
mmu_cold_read:
    sta beeb_aux_ptr
    lda beeb_aux_ptr_hi
    cmp #>BEEB_AUXDATA_VIRT_BASE
    bcc !main_read+
    clc
    adc #BEEB_AUXDATA_PHYS_OFFSET
    sta beeb_aux_ptr_hi
    lda #ROMSEL_BANK6
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda (beeb_aux_ptr),y
    bra mmu_romsel_store_exit
!main_read:
    plp
    lda (beeb_aux_ptr),y
    rts

mmu_safe_map_read_ptr1:
    php
    sei
    lda zp_ptr1_hi
    bpl !cold_r1+
    lda #ROMSEL_BANK5
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda (zp_ptr1),y
    bra mmu_romsel_store_exit
!cold_r1:
    sta beeb_aux_ptr_hi
    lda zp_ptr1
    bra mmu_cold_read

mmu_safe_map_write_ptr0:
    php
    sei
    sta beeb_mmu_byte
    lda zp_ptr0_hi
    bpl !cold_w0+
    lda #ROMSEL_BANK5
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda beeb_mmu_byte
    sta (zp_ptr0),y
    bra mmu_romsel_exit
!cold_w0:
    sta beeb_aux_ptr_hi
    lda zp_ptr0
mmu_cold_write:
    sta beeb_aux_ptr
    lda beeb_aux_ptr_hi
    cmp #>BEEB_AUXDATA_VIRT_BASE
    bcc !main_write+
    clc
    adc #BEEB_AUXDATA_PHYS_OFFSET
    sta beeb_aux_ptr_hi
    lda #ROMSEL_BANK6
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda beeb_mmu_byte
    sta (beeb_aux_ptr),y
    bra mmu_romsel_exit
!main_write:
    plp
    lda beeb_mmu_byte
    sta (beeb_aux_ptr),y
    rts

mmu_safe_map_write_ptr1:
    php
    sei
    sta beeb_mmu_byte
    lda zp_ptr1_hi
    bpl !cold_w1+
    lda #ROMSEL_BANK5
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda beeb_mmu_byte
    sta (zp_ptr1),y
    jmp mmu_romsel_exit
!cold_w1:
    sta beeb_aux_ptr_hi
    lda zp_ptr1
    bra mmu_cold_write

// mmu_safe_map_read_block — Burst-copy X bytes from Bank 5 Map (zp_ptr0),y
// to low main RAM (zp_ptr1),y. Clobbers A, X, Y.
mmu_safe_map_read_block:
    php
    sei
    lda #ROMSEL_BANK5
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
!loop:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    dex
    bne !loop-
    lda #ROMSEL_BANK4
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    plp
    rts

// ============================================================
// Sideways RAM Cache -> Bank 4 Window Bounce Copy (< $3000)
// ============================================================
// Copies X pages (256 B each) from Sideways Bank A at (zp_ptr0) into
// Bank 4 at (zp_ptr1) using the 256-byte low-RAM bounce buffer beeb_ss_buf.
// Input: A = source bank ($05, $06, or $07), X = page count,
//        zp_ptr0 = source address in Bank A, zp_ptr1 = dest address in Bank 4.
// Output: C = 0, ROMSEL = $04.
beeb_swr_copy_to_window:
    sta swr_src_bank
    ldy #0
!page_loop:
    php
    sei
    lda swr_src_bank
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
!rd_page:
    lda (zp_ptr0),y
    sta beeb_ss_buf,y
    iny
    bne !rd_page-
    lda #ROMSEL_BANK4
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    plp

!wr_page:
    lda beeb_ss_buf,y
    sta (zp_ptr1),y
    iny
    bne !wr_page-

    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dex
    bne !page_loop-
    clc
    rts

swr_src_bank: .byte 0

// ============================================================
// BANKED_DATA window & HAL memory helpers (Bank 4 is active during gameplay)
// ============================================================
mmu_safe_db_read_ptr0:
    lda (zp_ptr0),y
    rts

mmu_safe_db_write_ptr0:
    sta (zp_ptr0),y
    rts

mmu_safe_db_read_ptr1:
    lda (zp_ptr1),y
    rts

mmu_safe_db_write_ptr1:
    sta (zp_ptr1),y
    rts

db_bulk_enter:
    rts

db_bulk_exit:
    rts

plus4_bank_ram:
    rts

hal_memory_copy:
    ldy #0
    ldx zp_temp1
    beq !partial+
!page:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    bne !page-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dex
    bne !page-
!partial:
    ldx zp_temp0
    beq !done+
!tail:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    dex
    bne !tail-
!done:
    clc
    rts

hal_memory_read_byte:
    lda (zp_ptr0),y
    clc
    rts

hal_memory_write_byte:
    sta (zp_ptr0),y
    clc
    rts

// ============================================================
// Monster Recall Shadow-RAM Accessors (< $3000, LYNNE $3F80-$43DB)
// ============================================================
// Preserves X and all zero-page slots (restores beeb_acccon_shadow).
hal_recall_read_byte:
    clc
    lda recall_off_lo
    adc #<BEEB_LYNNE_AUX_BASE
    sta hrrb_lda + 1
    lda recall_off_hi
    adc #>BEEB_LYNNE_AUX_BASE
    sta hrrb_lda + 2
    php
    sei
    ldy beeb_acccon_shadow
    lda #ACCCON_LYNNE
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
hrrb_lda:
    lda BEEB_LYNNE_AUX_BASE
!recall_exit:
    sty beeb_acccon_shadow
    sty SHEILA_ACCCON
    plp
    rts

hal_recall_write_byte:
    sta hrwb_val + 1
    clc
    lda recall_off_lo
    adc #<BEEB_LYNNE_AUX_BASE
    sta hrwb_sta + 1
    lda recall_off_hi
    adc #>BEEB_LYNNE_AUX_BASE
    sta hrwb_sta + 2
    php
    sei
    ldy beeb_acccon_shadow
    lda #ACCCON_LYNNE
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
hrwb_val:
    lda #$00
hrwb_sta:
    sta BEEB_LYNNE_AUX_BASE
    bra !recall_exit-

// ============================================================
// ITEMCAT DFS On-Demand 10-Slot Page Cache (< $3000)
//   Slots 0,1,4 (LYNNE $3400-$35FF, B6 $9300): pages  0..5  (RECORDS, mod 3)
//   Slot  2     (LYNNE  $3600):                pages 14..21 (item base names)
//   Slot  3     (LYNNE  $3700):                pages 22..26 (ego & flavour names)
//   Slot  5     (Bank 6 $9400):                pages  6..9  (costs/wds/flags/bonuses)
//   Slot  6     (Bank 7 $BC00):                pages 10..11 (effects & egos)
//   Slot  7     (Bank 7 $BD00):                pages 27..29 ($80+ token strings)
//   Slot  8     (Bank 7 $BE00):                page   12    (BLK_INDEX + CANON — pinned)
//   Slot  9     (Bank 7 $BF00):                page   13    (CANON_SYMS + names — pinned)
// ============================================================
beeb_icat_inv_lynne:
    lda #$ff
    ldy #3
!inv_lp:
    sta beeb_icat_slot_page,y
    dey
    bpl !inv_lp-
    rts

// Input:  item_cat_off_lo/hi = 16-bit offset into ITEMCAT.
// Output: A = byte. Clobbers: A, Y (preserves X and all ZP).
hal_item_cat_read_byte:
    phx
    ldy item_cat_off_hi
    ldx beeb_icat_page_slot,y
    tya
    cmp beeb_icat_slot_page,x
    beq !hic_hit+
    jsr beeb_icat_load_page
!hic_hit:
    lda beeb_icat_slot_hi,x
    ldy item_cat_off_lo
    php
    sei
    cpx #4
    bcc !hic_lynne+
    sta hic_lda + 2
    cpx #6
    lda #ROMSEL_BANK6
    adc #0                  // $06 for Slots 4..5 (C=0), $07 for Slots 6..9 (C=1)
    ldx zp_mos_romsel_shadow
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
hic_lda:
    lda BEEB_ICAT_B6_ADDR,y
    stx zp_mos_romsel_shadow
    stx SHEILA_ROMSEL
    plp
    plx
    rts
!hic_lynne:
    sta hic_lyn_lda + 2
    ldx beeb_acccon_shadow
    lda #ACCCON_LYNNE
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
hic_lyn_lda:
    lda DUNGEON_GEN_SCAN_SCRATCH_BASE,y
    stx beeb_acccon_shadow
    stx SHEILA_ACCCON
    plp
    plx
    rts

beeb_icat_load_page:
    sta beeb_icat_req_page
    stx beeb_icat_req_slot
    jsr EnterMos
    lda beeb_icat_handle
    bne !hilp_have_h+
    lda program_device
    sta beeb_io_device
    lda #hal_storage_item_cat_name_len
    ldx #<hal_storage_item_cat_name
    ldy #>hal_storage_item_cat_name
    jsr beeb_set_pathname
    lda #$40
    jsr beeb_call_osfind_keep_icat
    bcs !hilp_fail_mos+
    cmp #$00
    beq !hilp_fail_mos+
    sta beeb_icat_handle
!hilp_have_h:
    jsr beeb_prep_ss_osgbpb
    lda #$01
    sta BEEB_OS_CTRL_BASE + 6
    lda beeb_icat_req_page
    sta BEEB_OS_CTRL_BASE + 10
    lda #$03
    jsr beeb_call_osgbpb
    // Partial final page (page 29) triggers EOF Carry=1 after transferring
    // 149 bytes, clearing BEEB_OS_CTRL_BASE+6 to 0; 0-byte faults leave it 1.
    lda BEEB_OS_CTRL_BASE + 6
    bne !hilp_fail_mos+
    jsr ExitMos
    ldx beeb_icat_req_slot
    lda beeb_icat_slot_hi,x
    sta hilp_sta + 2
    php
    sei
    cpx #4
    bcc !hilp_lynne+
    cpx #6
    lda #ROMSEL_BANK6
    adc #0
    ldy zp_mos_romsel_shadow
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    jsr !hilp_copy+
    sty zp_mos_romsel_shadow
    sty SHEILA_ROMSEL
    bra !hilp_done+
!hilp_lynne:
    ldy beeb_acccon_shadow
    lda #ACCCON_LYNNE
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    jsr !hilp_copy+
    sty beeb_acccon_shadow
    sty SHEILA_ACCCON
!hilp_done:
    plp
    ldx beeb_icat_req_slot
    lda beeb_icat_req_page
    sta beeb_icat_slot_page,x
    rts
!hilp_copy:
    ldx #0
!hilp_clp:
    lda beeb_ss_buf,x
hilp_sta:
    sta DUNGEON_GEN_SCAN_SCRATCH_BASE,x
    inx
    bne !hilp_clp-
    rts
!hilp_fail_mos:
    jsr beeb_close_icat_in_mos
    jsr ExitMos
    lda #$fc
    jmp hal_platform_panic

beeb_icat_slot_page: .fill 10, $ff
beeb_icat_page_slot:
    .byte 0, 1, 4, 0, 1, 4              // pages  0..5  -> Slots 0, 1, 4 (RECORDS)
    .byte 5, 5, 5, 5                    // pages  6..9  -> Slot 5 (costs/wds/flags/bonuses)
    .byte 6, 6                          // pages 10..11 -> Slot 6 (effects & egos)
    .byte 8, 9                          // pages 12..13 -> Slots 8, 9 (BLK_INDEX & CANON — pinned)
    .byte 2, 2, 2, 2, 2, 2, 2, 2        // pages 14..21 -> Slot 2 (item base names)
    .byte 3, 3, 3, 3, 3                 // pages 22..26 -> Slot 3 (ego & flavour names)
    .byte 7, 7, 7                       // pages 27..29 -> Slot 7 ($80+ tokens)
beeb_icat_slot_hi:
    .assert "beeb_icat_page_slot covers 30 ITEMCAT pages", beeb_icat_slot_hi - beeb_icat_page_slot, 30
    .byte >DUNGEON_GEN_SCAN_SCRATCH_BASE, >(DUNGEON_GEN_SCAN_SCRATCH_BASE + $100)
    .byte >(DUNGEON_GEN_SCAN_SCRATCH_BASE + $200), >(DUNGEON_GEN_SCAN_SCRATCH_BASE + $300)
    .byte >BEEB_ICAT_B6_ADDR, >(BEEB_ICAT_B6_ADDR + $100)
    .byte >BEEB_ICAT_CACHE_ADDR, >(BEEB_ICAT_CACHE_ADDR + $100)
    .byte >(BEEB_ICAT_CACHE_ADDR + $200), >(BEEB_ICAT_CACHE_ADDR + $300)
beeb_icat_req_page:  .byte 0
beeb_icat_req_slot:  .byte 0
beeb_icat_handle:    .byte 0
