#importonce
// Store A bytes from Bank 0 SCREEN_RAM into the Bank 1 row at zp_ptr0.
// This routine must execute from common RAM while Bank 1 is selected.
// Input: A = byte count (1-255), zp_ptr0 = Bank 1 destination row.
// Preserves: X. Clobbers: A, Y and caller flags.
mmu_common_store_map_row:
#if C128_TEST_COUNT_MAP_ROW_STORES
    inc c128_test_row_store_count_lo
    bne !store_counted+
    inc c128_test_row_store_count_hi
!store_counted:
#endif
    sta mmu_common_row_end
    php
    sei
    lda #MMU_RAM_BANK1
    sta MMU_CR
    ldy #0
!store:
    lda SCREEN_RAM,y
    sta (zp_ptr0),y
    iny
    cpy mmu_common_row_end
    bne !store-
    lda #MMU_ALL_RAM
    sta MMU_CR
    plp
    rts

// Apply mmu_common_row_mask to an inclusive Bank 1 map-row span.
// Input: A = final column, Y = first column, zp_ptr0 = Bank 1 row.
// Preserves: X. Clobbers: A, Y and caller flags.
mmu_common_and_map_span:
    clc
    adc #1
    sta mmu_common_row_end
    php
    sei
    lda #MMU_RAM_BANK1
    sta MMU_CR
!and_span:
    lda (zp_ptr0),y
    and mmu_common_row_mask
    sta (zp_ptr0),y
    iny
    cpy mmu_common_row_end
    bne !and_span-
    lda #MMU_ALL_RAM
    sta MMU_CR
    plp
    rts
