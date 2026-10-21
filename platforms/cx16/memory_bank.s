#importonce
// memory_bank.s — Commander X16 banked-RAM ($A000-$BFFF) mechanics.
//
// Virtual address space $2000-$9FFF maps to 8 KB RAM banks 1..4 at $A000-$BFFF:
//   $2000-$3FFF -> Bank 1 ($A000-$BFFF): live map low half (8,192 B)
//   $4000-$530B -> Bank 2 ($A000-$B30B): live map high half (4,876 B)
//   $6000-$7FFF -> Bank 3 ($A000-$BFFF): Cx16AuxData
//   $8000-$9FFF -> Bank 4 ($A000-$BFFF): Cx16HuffData
//
// Because switching ZP $00 on CX16 only affects $A000-$BFFF and never banks
// out fixed low RAM ($0000-$9EFF), these resident routines switch $00, access
// $A000-$BFFF, and restore $00 directly without zero-page execution thunks.

// ============================================================
// Virtual-to-Banked Byte Accessors (core-facing, via mmu_macros.s)
// ============================================================

// mmu_safe_map_read_ptr0 — Read byte at virtual (zp_ptr0),y -> A.
// Preserves: X, Y, C, V. Sets N/Z from A. Restores CX16_RAM_BANK_REG ($00).
mmu_safe_map_read_ptr0:
    php
    sei
    lda CX16_RAM_BANK_REG
    pha
    tya
    clc
    adc zp_ptr0
    sta !sm_read0+ + 1
    lda zp_ptr0_hi
    adc #0
    pha
    and #$1f
    ora #$a0
    sta !sm_read0+ + 2
    pla
    lsr
    lsr
    lsr
    lsr
    lsr
    sta CX16_RAM_BANK_REG
!sm_read0:
    lda $a000
    sta cx16_zp_scratch
    pla
    sta CX16_RAM_BANK_REG
    plp
    lda cx16_zp_scratch
    rts

// mmu_safe_map_read_ptr1 — Read byte at virtual (zp_ptr1),y -> A.
// Preserves: X, Y, C, V. Sets N/Z from A. Restores CX16_RAM_BANK_REG ($00).
mmu_safe_huff_read_ptr1:
mmu_safe_map_read_ptr1:
    php
    sei
    lda CX16_RAM_BANK_REG
    pha
    tya
    clc
    adc zp_ptr1
    sta !sm_read1+ + 1
    lda zp_ptr1_hi
    adc #0
    pha
    and #$1f
    ora #$a0
    sta !sm_read1+ + 2
    pla
    lsr
    lsr
    lsr
    lsr
    lsr
    sta CX16_RAM_BANK_REG
!sm_read1:
    lda $a000
    sta cx16_zp_scratch
    pla
    sta CX16_RAM_BANK_REG
    plp
    lda cx16_zp_scratch
    rts

// mmu_safe_map_write_ptr0 — Write A to virtual (zp_ptr0),y.
// Preserves: A, X, Y, C, V. Restores CX16_RAM_BANK_REG ($00).
mmu_safe_map_write_ptr0:
    php
    sei
    sta cx16_zp_scratch
    lda CX16_RAM_BANK_REG
    pha
    tya
    clc
    adc zp_ptr0
    sta !sm_write0+ + 1
    lda zp_ptr0_hi
    adc #0
    pha
    and #$1f
    ora #$a0
    sta !sm_write0+ + 2
    pla
    lsr
    lsr
    lsr
    lsr
    lsr
    sta CX16_RAM_BANK_REG
    lda cx16_zp_scratch
!sm_write0:
    sta $a000
    pla
    sta CX16_RAM_BANK_REG
    lda cx16_zp_scratch
    plp
    rts

// mmu_safe_map_write_ptr1 — Write A to virtual (zp_ptr1),y.
// Preserves: A, X, Y, C, V. Restores CX16_RAM_BANK_REG ($00).
mmu_safe_map_write_ptr1:
    php
    sei
    sta cx16_zp_scratch
    lda CX16_RAM_BANK_REG
    pha
    tya
    clc
    adc zp_ptr1
    sta !sm_write1+ + 1
    lda zp_ptr1_hi
    adc #0
    pha
    and #$1f
    ora #$a0
    sta !sm_write1+ + 2
    pla
    lsr
    lsr
    lsr
    lsr
    lsr
    sta CX16_RAM_BANK_REG
    lda cx16_zp_scratch
!sm_write1:
    sta $a000
    pla
    sta CX16_RAM_BANK_REG
    lda cx16_zp_scratch
    plp
    rts

// mmu_safe_map_read_block — Copy X bytes from virtual (zp_ptr0),y to fixed RAM
// (zp_ptr1),y. Y = starting offset, X = count (0 = 256). Clobbers A, X, Y.
// Fast path: when zp_ptr0_hi != $3F, the slice cannot cross the Bank 1/2
// boundary ($3FFF/$4000), so we switch $00 once for the entire row.
mmu_safe_map_read_block:
    lda zp_ptr0_hi
    cmp #$3f
    beq !slow_block+
    php
    sei
    lda CX16_RAM_BANK_REG
    pha
    lda zp_ptr0_hi
    pha
    lsr
    lsr
    lsr
    lsr
    lsr
    sta CX16_RAM_BANK_REG
    lda zp_ptr0_hi
    and #$1f
    ora #$a0
    sta zp_ptr0_hi
!fast_loop:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    dex
    bne !fast_loop-
    pla
    sta zp_ptr0_hi
    pla
    sta CX16_RAM_BANK_REG
    plp
    rts
!slow_block:
    jsr mmu_safe_map_read_ptr0
    sta (zp_ptr1),y
    iny
    dex
    bne !slow_block-
    rts

// ============================================================
// BANKED_DATA window access ($A000-$BFFF in currently selected bank)
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

// ============================================================
// hal_memory_* contract exports
// ============================================================
hal_memory_enter_os:
    clc
    rts

hal_memory_exit_os:
    clc
    rts

hal_memory_restore_runtime:
    clc
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
