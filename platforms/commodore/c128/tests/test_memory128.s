#importonce
// test_memory128.s — C128 MMU smoke tests for C4.2

#import "../../../../core/zeropage.s"
#import "test_helpers128.s"
#define C128_TEST_MAP_ROW_STORE_HELPER
#import "../memory128.s"
#undef C128_TEST_MAP_ROW_STORE_HELPER

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

c128_restore_runtime_state:
    rts

test_start:
    sei
    cld
    ldx #$ff
    txs

    // Test 0: Common-RAM IRQ/NMI entries must clear Decimal Mode first.
    lda mmu_common_irq
    cmp #$d8                    // CLD opcode
    beq !irq_cld_ok+
    jmp test_fail
!irq_cld_ok:
    lda mmu_common_irq + 1
    cmp #$48                    // PHA remains second opcode
    beq !irq_pha_ok+
    jmp test_fail
!irq_pha_ok:
    lda mmu_common_nmi
    cmp #$d8                    // CLD opcode
    beq !nmi_cld_ok+
    jmp test_fail
!nmi_cld_ok:
    lda mmu_common_nmi + 1
    cmp #$48                    // PHA remains second opcode
    beq !nmi_pha_ok+
    jmp test_fail
!nmi_pha_ok:

    // Test 1: mmu_select_bank1/0 isolation at $4000
    // (Note: $4000 is RAM in both banks)
    
    jsr mmu_select_bank0
    lda #$a5
    sta $4000

    jsr mmu_select_bank1
    lda #$5a
    sta $4000
    lda $4000
    cmp #$5a
    bne test_fail

    jsr mmu_select_bank0
    lda $4000
    cmp #$a5
    bne test_fail

    // Test 2: mmu_select_bank1 preserves caller IRQ state
    
    // Case A: Call from CLI state
    cli
    jsr mmu_select_bank1
    // (IRQ should be disabled INSIDE, but restored OUTSIDE)
    php
    pla
    and #$04
    bne test_fail   // Fail if I=1 (disabled) outside

    jsr mmu_select_bank0 // Balanced restore
    php
    pla
    and #$04
    bne test_fail   // Still should be enabled

    // Case B: Call from SEI state
    sei
    jsr mmu_select_bank1
    php
    pla
    and #$04
    beq test_fail   // Fail if I=0 (enabled) outside

    jsr mmu_select_bank0
    php
    pla
    and #$04
    beq test_fail   // Still should be disabled

    // Test 3: mmu_common_copy_map_row isolation and boundary checks
    jmp !test3_start+
test_fail:
    jmp test_fail
!test3_start:

    // Setup dummy data in Bank 1 at $4000
    jsr mmu_select_bank1
    ldx #0
!setup_src:
    txa
    sta $4000,x
    inx
    cpx #MMU_COPY_MAP_ROW_LEN
    bne !setup_src-
    jsr mmu_select_bank0

    // Setup sentinels at $03FF and SCREEN_RAM + len
    lda #$ff
    sta $03ff
    sta SCREEN_RAM + MMU_COPY_MAP_ROW_LEN
    
    // Clear destination $0400-$0400+len-1
    lda #0
    ldx #0
!clr_dest:
    sta $0400,x
    inx
    cpx #MMU_COPY_MAP_ROW_LEN
    bne !clr_dest-

    // Call the copy routine
    lda #<$4000
    sta zp_ptr0
    lda #>$4000
    sta zp_ptr0_hi
    lda #MMU_COPY_MAP_ROW_LEN
    jsr mmu_common_copy_map_row

    // Verify boundaries to prove no clobbering
    lda $03ff
    cmp #$ff
    bne test_fail
    lda SCREEN_RAM + MMU_COPY_MAP_ROW_LEN
    cmp #$ff
    bne test_fail

    // Verify copied content
    ldx #0
!chk_dest:
    txa
    cmp SCREEN_RAM,x
    bne test_fail
    inx
    cpx #MMU_COPY_MAP_ROW_LEN
    bne !chk_dest-

    // The generation path copies all 198 map columns with the same primitive.
    jsr mmu_select_bank1
    ldx #0
!setup_full_src:
    txa
    eor #$a5
    sta $4000,x
    inx
    cpx #C128_FUTURE_MAP_COLS
    bne !setup_full_src-
    jsr mmu_select_bank0

    lda #$ff
    sta SCREEN_RAM + C128_FUTURE_MAP_COLS
    lda #0
    ldx #0
!clr_full_dest:
    sta SCREEN_RAM,x
    inx
    cpx #C128_FUTURE_MAP_COLS
    bne !clr_full_dest-

    lda #C128_FUTURE_MAP_COLS
    jsr mmu_common_copy_map_row

    lda SCREEN_RAM + C128_FUTURE_MAP_COLS
    cmp #$ff
    bne test_fail
    ldx #0
!chk_full_dest:
    txa
    eor #$a5
    cmp SCREEN_RAM,x
    beq !full_byte_ok+
    jmp test_fail
!full_byte_ok:
    inx
    cpx #C128_FUTURE_MAP_COLS
    bne !chk_full_dest-

    // Store the same full row back to Bank 1 and preserve the next byte.
    jsr mmu_select_bank1
    lda #0
    ldx #0
!clr_full_store:
    sta $4000,x
    inx
    cpx #C128_FUTURE_MAP_COLS
    bne !clr_full_store-
    lda #$ff
    sta $4000 + C128_FUTURE_MAP_COLS
    jsr mmu_select_bank0

    lda #C128_FUTURE_MAP_COLS
    jsr mmu_common_store_map_row

    jsr mmu_select_bank1
    lda $4000 + C128_FUTURE_MAP_COLS
    cmp #$ff
    bne !store_fail+
    ldx #0
!chk_full_store:
    txa
    eor #$a5
    cmp $4000,x
    bne !store_fail+
    inx
    cpx #C128_FUTURE_MAP_COLS
    bne !chk_full_store-
    jsr mmu_select_bank0
    jmp test_pass
!store_fail:
    jsr mmu_select_bank0
    jmp test_fail

test_pass:
    jmp test_pass
