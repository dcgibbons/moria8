#importonce
// memory_bank.s — BBC Master 128 Sideways RAM (ROMSEL $FE30), Private RAM ANDY,
// and Shadow RAM LYNNE (ACCCON $FE34) bank-switching helpers.
//
// Authority: docs/BBCMASTER_MEMORY_CONTRACT.md.
// All routines in this file are linked below $3000 in unbanked low RAM so they
// remain visible across every ACCCON ($3000-$7FFF) and ROMSEL ($8000-$BFFF)
// transition.

#import "memory.s"

// ============================================================
// EnterMos / ExitMos — Safe MOS / DFS Call Envelope (< $3000)
// ============================================================
// Saves core + platform ZP ($02-$AF), ensures main RAM is visible at $3000-$7FFF
// (ACCCON = $01: D=1, X=0), and restores MOS's filing-system ROM in ROMSEL
// ($FE30 = zp_mos_romsel_shadow) before calling into MOS/DFS.
EnterMos:
hal_memory_enter_os:
    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    jsr save_zp
    lda beeb_boot_romsel
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    clc
    rts

ExitMos:
hal_memory_exit_os:
    php
    pha
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
    lda #ROMSEL_BANK4
    sta zp_mos_romsel_shadow
    sta SHEILA_ROMSEL
    lda #ACCCON_NORMAL
    sta beeb_acccon_shadow
    sta SHEILA_ACCCON
    clc
    rts

beeb_boot_romsel: .byte $00

// ============================================================
// Huffman Corpus Readers (ANDY $8000-$8FFF via ROMSEL = $84)
// ============================================================
// Setting ROMSEL = $84 maps 4 KB ANDY at $8000-$8FFF while keeping Bank 4's
// upper 12 KB ($9000-$BFFF, including overlays at $A800-$BFFF) visible!
// Zero address arithmetic; preserves X, Y, C, I, D, V and sets N/Z from A.
mmu_safe_huff_read_ptr0:
    php
    sei
    lda #ROMSEL_ANDY
    sta SHEILA_ROMSEL
    lda (zp_ptr0),y
    sta beeb_mmu_byte
    lda #ROMSEL_BANK4
    sta SHEILA_ROMSEL
    plp
    lda beeb_mmu_byte
    rts

mmu_safe_huff_read_ptr1:
    php
    sei
    lda #ROMSEL_ANDY
    sta SHEILA_ROMSEL
    lda (zp_ptr1),y
    sta beeb_mmu_byte
    lda #ROMSEL_BANK4
    sta SHEILA_ROMSEL
    plp
    lda beeb_mmu_byte
    rts

// ============================================================
// Map & BeebAuxData Readers/Writers
// ============================================================
// Dispatches by high byte of pointer:
//   - >= $80 (bmi): Bank 5 Map ($8000-$B30B), zero address arithmetic.
//   - $60..$76 (bpl): Bank 6 BeebAuxData (virtual $6000-$76FF -> physical
//                     $8000-$96FF = virt + $2000 via dedicated beeb_aux_ptr).
// Preserves X, Y, C, I, D, V; sets N/Z from A on reads; preserves A on writes.
mmu_safe_map_read_ptr0:
    php
    sei
    lda zp_ptr0_hi
    bpl !aux0+
    lda #ROMSEL_BANK5
    sta SHEILA_ROMSEL
    lda (zp_ptr0),y
    sta beeb_mmu_byte
    lda #ROMSEL_BANK4
    sta SHEILA_ROMSEL
    plp
    lda beeb_mmu_byte
    rts
!aux0:
    cmp #>BEEB_AUXDATA_VIRT_BASE
    bcc !main0+
    clc
    adc #BEEB_AUXDATA_PHYS_OFFSET
    sta beeb_aux_ptr_hi
    lda zp_ptr0
    sta beeb_aux_ptr
    lda #ROMSEL_BANK6
    sta SHEILA_ROMSEL
    lda (beeb_aux_ptr),y
    sta beeb_mmu_byte
    lda #ROMSEL_BANK4
    sta SHEILA_ROMSEL
    plp
    lda beeb_mmu_byte
    rts
!main0:
    plp
    lda (zp_ptr0),y
    rts

mmu_safe_map_read_ptr1:
    php
    sei
    lda zp_ptr1_hi
    bpl !aux1+
    lda #ROMSEL_BANK5
    sta SHEILA_ROMSEL
    lda (zp_ptr1),y
    sta beeb_mmu_byte
    lda #ROMSEL_BANK4
    sta SHEILA_ROMSEL
    plp
    lda beeb_mmu_byte
    rts
!aux1:
    cmp #>BEEB_AUXDATA_VIRT_BASE
    bcc !main1+
    clc
    adc #BEEB_AUXDATA_PHYS_OFFSET
    sta beeb_aux_ptr_hi
    lda zp_ptr1
    sta beeb_aux_ptr
    lda #ROMSEL_BANK6
    sta SHEILA_ROMSEL
    lda (beeb_aux_ptr),y
    sta beeb_mmu_byte
    lda #ROMSEL_BANK4
    sta SHEILA_ROMSEL
    plp
    lda beeb_mmu_byte
    rts
!main1:
    plp
    lda (zp_ptr1),y
    rts

mmu_safe_map_write_ptr0:
    php
    sei
    sta beeb_mmu_byte
    lda zp_ptr0_hi
    bpl !aux_w0+
    lda #ROMSEL_BANK5
    sta SHEILA_ROMSEL
    lda beeb_mmu_byte
    sta (zp_ptr0),y
    lda #ROMSEL_BANK4
    sta SHEILA_ROMSEL
    plp
    lda beeb_mmu_byte
    rts
!aux_w0:
    cmp #>BEEB_AUXDATA_VIRT_BASE
    bcc !main_w0+
    clc
    adc #BEEB_AUXDATA_PHYS_OFFSET
    sta beeb_aux_ptr_hi
    lda zp_ptr0
    sta beeb_aux_ptr
    lda #ROMSEL_BANK6
    sta SHEILA_ROMSEL
    lda beeb_mmu_byte
    sta (beeb_aux_ptr),y
    lda #ROMSEL_BANK4
    sta SHEILA_ROMSEL
    plp
    lda beeb_mmu_byte
    rts
!main_w0:
    plp
    lda beeb_mmu_byte
    sta (zp_ptr0),y
    rts

mmu_safe_map_write_ptr1:
    php
    sei
    sta beeb_mmu_byte
    lda zp_ptr1_hi
    bpl !aux_w1+
    lda #ROMSEL_BANK5
    sta SHEILA_ROMSEL
    lda beeb_mmu_byte
    sta (zp_ptr1),y
    lda #ROMSEL_BANK4
    sta SHEILA_ROMSEL
    plp
    lda beeb_mmu_byte
    rts
!aux_w1:
    cmp #>BEEB_AUXDATA_VIRT_BASE
    bcc !main_w1+
    clc
    adc #BEEB_AUXDATA_PHYS_OFFSET
    sta beeb_aux_ptr_hi
    lda zp_ptr1
    sta beeb_aux_ptr
    lda #ROMSEL_BANK6
    sta SHEILA_ROMSEL
    lda beeb_mmu_byte
    sta (beeb_aux_ptr),y
    lda #ROMSEL_BANK4
    sta SHEILA_ROMSEL
    plp
    lda beeb_mmu_byte
    rts
!main_w1:
    plp
    lda beeb_mmu_byte
    sta (zp_ptr1),y
    rts

// mmu_safe_map_read_block — Burst-copy X bytes from Bank 5 Map (zp_ptr0),y
// to low main RAM (zp_ptr1),y. Clobbers A, X, Y.
mmu_safe_map_read_block:
    php
    sei
    lda #ROMSEL_BANK5
    sta SHEILA_ROMSEL
!loop:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    dex
    bne !loop-
    lda #ROMSEL_BANK4
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
    sta SHEILA_ROMSEL
!rd_page:
    lda (zp_ptr0),y
    sta beeb_ss_buf,y
    iny
    bne !rd_page-
    lda #ROMSEL_BANK4
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
