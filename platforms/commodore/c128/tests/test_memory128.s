#importonce
// test_memory128.s — C128 MMU smoke tests for C4.2

#import "../../../../core/6502/zeropage.s"
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
    lda $0314
    sta kernal_irq_vec_lo
    lda $0315
    sta kernal_irq_vec_hi
    lda #0
    sta KERNAL_NESTING_DEPTH
    sta c128_kernal_irq_tail_runtime_owned
    jsr init_common_mmu_helpers   // as boot does: common-RAM MMU helpers at $0C00
    // Test 2 runs with CLI to check IRQ-state bookkeeping, not to take IRQs:
    // silence the boot's interrupt sources. Stop the CIA timers too: this
    // PRG's load fills the KERNAL page $0A, and its NMI handler re-enabled
    // CIA 2 timer A from $0A0F on every NMI (an NMI storm).
    lda #$7f
    sta $dc0d
    sta $dd0d
    lda #0
    sta $dc0e
    sta $dc0f
    sta $dd0e
    sta $dd0f
    lda $dc0d
    lda $dd0d
    lda #0
    sta $d01a
    lda #$ff
    sta $d019

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
    // IRQs stay disabled while Bank 1 is mapped (mmu_select_bank1 saves P
    // and SEIs); the paired mmu_select_bank0 restores them.
    php
    pla
    and #$04
    beq test_fail   // Fail if I=0 (enabled) while Bank 1 is mapped

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
    jmp !test4_start+
!store_fail:
    jsr mmu_select_bank0
    jmp test_fail

    // Test 4: Huffman reads expose physical Bank 1 under top common RAM,
    // then restore the product's Bank 0/$D506=$0D invariant and IRQ state.
!test4_start:
    sei
    // Bottom-only common RAM keeps $F000 private to each bank for the setup
    // writes. 16 KB ($07), not 4 KB ($05): this code runs at $3xxx and must
    // stay visible across the raw MMU_CR switch.
    lda #$07
    sta $d506
    lda #MMU_ALL_RAM
    sta MMU_CR
    lda #$a5
    sta $f000
    lda #MMU_RAM_BANK1
    sta MMU_CR
    lda #$5a
    sta $f000
    lda #$6b
    sta $f001
    lda #MMU_ALL_RAM
    sta MMU_CR
    lda #$0d
    sta $d506

    lda #<$f000
    sta zp_ptr0
    lda #>$f000
    sta zp_ptr0_hi
    ldy #0
    cli
    jsr mmu_common_huff_read_ptr0
    cmp #$5a
    beq !ptr0_value_ok+
    jmp test_fail
!ptr0_value_ok:
    php
    pla
    and #$04
    beq !ptr0_irq_ok+
    jmp test_fail
!ptr0_irq_ok:
    lda MMU_CR
    cmp #MMU_ALL_RAM
    beq !ptr0_bank_ok+
    jmp test_fail
!ptr0_bank_ok:
    lda $d506
    cmp #$0d
    beq !ptr0_common_ok+
    jmp test_fail
!ptr0_common_ok:

    lda #<$f000
    sta zp_ptr1
    lda #>$f000
    sta zp_ptr1_hi
    ldy #1
    sei
    jsr mmu_common_huff_read_ptr1
    cmp #$6b
    beq !ptr1_value_ok+
    jmp test_fail
!ptr1_value_ok:
    php
    pla
    and #$04
    bne !ptr1_irq_ok+
    jmp test_fail
!ptr1_irq_ok:
    lda $f000                  // Top common shows the untouched Bank 0 byte.
    cmp #$a5
    beq !ptr1_common_ok+
    jmp test_fail
!ptr1_common_ok:
    jmp test5_b1_d000_spike

// ============================================================
// Test 5: C128M-002 Spike — Bank 1 $D000-$DFFF via SEI + $7F common bounce
// Proves common-RAM-bounced reads/writes into Bank 1 $D000-$DFFF under
// MMU_RAM_BANK1_NOIO ($7F) preserve VIC $D020, VDC VRAM/regs, CIA1/2 timers,
// IRQ state + real CIA1 IRQ servicing, and EnterKernal/ExitKernal transitions.
// ============================================================
.const SPIKE_MMU_RAM_BANK1_NOIO = $7f
.const SPIKE_MMU_ALL_RAM_NOIO   = $3f
.const SPIKE_COMMON_BASE        = $0f00
.const SPIKE_VDC_ADDR           = $d600
.const SPIKE_VDC_DATA           = $d601
.const SPIKE_TBL_LEN            = 12

test5_b1_d000_spike:
    sei
    lda #CPU_PORT_DDR_DEFAULT
    sta $00
    lda #BANK_NO_BASIC
    sta $01
    lda #$0d
    sta $d506
    lda #MMU_ALL_RAM
    sta MMU_CR

    // Install common-RAM spike routines at $0F00 (< $0FB0 cartridge slot)
    ldx #0
!copy_spike:
    lda spike_common_blob,x
    sta SPIKE_COMMON_BASE,x
    inx
    cpx #spike_common_blob_end - spike_common_blob
    bne !copy_spike-

    // Install Top Common hardware vectors ($FFFA/$FFFE) as in production
    lda #<mmu_common_nmi
    sta $fffa
    lda #>mmu_common_nmi
    sta $fffb
    lda #<spike_common_irq_stub
    sta $fffe
    lda #>spike_common_irq_stub
    sta $ffff

    // 5A. Establish live I/O baselines under MMU_ALL_RAM ($3E)
    lda #$03
    sta $d020
    lda $d020
    and #$0f
    cmp #$03
    beq !vic_init_ok+
    jmp test_fail
!vic_init_ok:

    // VDC VRAM sentinel $5D at $07FF (safe scratch byte past 80x25 screen)
    lda #$07
    ldy #$ff
    ldx #18
    jsr spike_vdc_write
    tya
    ldx #19
    jsr spike_vdc_write
    lda #$5d
    ldx #31
    jsr spike_vdc_write
    jsr spike_vdc_read_07ff
    cmp #$5d
    beq !vdc_init_ok+
    jmp test_fail
!vdc_init_ok:

    // CIA1 & CIA2 stopped Timer A latches
    lda #$34
    sta $dc04
    lda #$12
    sta $dc05
    lda #$78
    sta $dd04
    lda #$56
    sta $dd05
    lda $dc04
    cmp #$34
    bne !cia_init_fail+
    lda $dc05
    cmp #$12
    bne !cia_init_fail+
    lda $dd04
    cmp #$78
    bne !cia_init_fail+
    lda $dd05
    cmp #$56
    beq !cia_init_ok+
!cia_init_fail:
    jmp test_fail
!cia_init_ok:

    // 5B. Write distinct Bank 0 RAM sentinel $12 at $D020 via $3F bounce
    lda #<$d020
    sta zp_ptr0
    lda #>$d020
    sta zp_ptr0_hi
    ldy #0
    lda #$12
    jsr spike_b0_d000_write

    // 5C. Write 12 test sentinels across Bank 1 $D000-$DFFF via $7F bounce
    // First test explicit CLI and SEI preservation on $D000 and $D500
    lda #<$d000
    sta zp_ptr0
    lda #>$d000
    sta zp_ptr0_hi
    ldy #0
    lda #$5a
    cli
    jsr spike_b1_d000_write
    php
    pla
    and #$04
    beq !cli_wr_ok+
    jmp test_fail
!cli_wr_ok:
    sei
    lda MMU_CR
    cmp #MMU_ALL_RAM
    beq !cli_mmu_ok+
    jmp test_fail
!cli_mmu_ok:

    // Write remaining table entries with mixed CLI/SEI
    ldx #0
!wr_tbl:
    lda spike_addr_lo,x
    sta zp_ptr0
    lda spike_addr_hi,x
    sta zp_ptr0_hi
    lda spike_expected_val,x
    ldy #0
    cli
    jsr spike_b1_d000_write
    php
    sei
    pla
    and #$04
    beq !wr_cli_ok+
    jmp test_fail
!wr_cli_ok:
    lda MMU_CR
    cmp #MMU_ALL_RAM
    beq !wr_mmu_ok+
    jmp test_fail
!wr_mmu_ok:
    lda $d506
    cmp #$0d
    beq !wr_d506_ok+
    jmp test_fail
!wr_d506_ok:
    inx
    cpx #SPIKE_TBL_LEN
    bne !wr_tbl-

    // Explicit SEI read test on $D500
    lda #<$d500
    sta zp_ptr0
    lda #>$d500
    sta zp_ptr0_hi
    ldy #0
    sei
    jsr spike_b1_d000_read
    cmp #$3c
    beq !sei_rd_val_ok+
    jmp test_fail
!sei_rd_val_ok:
    php
    pla
    and #$04
    bne !sei_rd_i_ok+
    jmp test_fail
!sei_rd_i_ok:

    // 5D. Verify all I/O, Bank 0 RAM, VDC, CIA, and Bank 1 RAM $D000-$DFFF
    jsr spike_verify_all_state

    // Additional post-$7F VDC write/read proof at $07FE
    lda #$07
    ldx #18
    jsr spike_vdc_write
    lda #$fe
    ldx #19
    jsr spike_vdc_write
    lda #$6c
    ldx #31
    jsr spike_vdc_write
    lda #$07
    ldx #18
    jsr spike_vdc_write
    lda #$fe
    ldx #19
    jsr spike_vdc_write
    ldx #31
    jsr spike_vdc_read
    cmp #$6c
    beq !vdc_post_ok+
    jmp test_fail
!vdc_post_ok:

    // 5E. Trigger a real CIA1 Timer A IRQ after $7F bounces and confirm clean RTI
    sei
    lda #0
    sta spike_irq_count
    lda #$7f
    sta $dc0d
    lda $dc0d                   // Clear any pending CIA1 flags
    lda #$40
    sta $dc04
    lda #$00
    sta $dc05
    lda #$81
    sta $dc0d                   // Enable CIA1 Timer A IRQ
    lda #$19
    sta $dc0e                   // Start one-shot with forced latch load
    cli
    ldx #0
    ldy #0
!wait_irq:
    lda spike_irq_count
    bne !irq_fired+
    inx
    bne !wait_irq-
    iny
    bne !wait_irq-
    sei
    jmp test_fail
!irq_fired:
    sei
    lda #$7f
    sta $dc0d
    lda #0
    sta $dc0e
    lda $dc0d
    // Restore CIA1 baseline latch values since Timer A latch was reused
    lda #$34
    sta $dc04
    lda #$12
    sta $dc05
    jsr spike_verify_all_state

    // 5F. Verify EnterKernal / ExitKernal, Bank 1 map select, and Huffman read
    // keep Bank 1 $D000-$DFFF and Top Common $F000 untouched.
    lda #0
    sta KERNAL_NESTING_DEPTH
    :EnterKernal()
    lda #2
    ldx #8
    ldy #1
    jsr $ffba                   // Safe SETLFS under KERNAL ROM
    :ExitKernal()

    lda KERNAL_NESTING_DEPTH
    beq !ek_depth_ok+
    jmp test_fail
!ek_depth_ok:
    lda MMU_CR
    cmp #MMU_ALL_RAM
    beq !ek_mmu_ok+
    jmp test_fail
!ek_mmu_ok:
    lda $d506
    cmp #$0d
    beq !ek_d506_ok+
    jmp test_fail
!ek_d506_ok:

    // Re-check Huffman read ($F000 Bank 1 = $5A, Bank 0 = $A5)
    lda #<$f000
    sta zp_ptr0
    lda #>$f000
    sta zp_ptr0_hi
    ldy #0
    jsr mmu_common_huff_read_ptr0
    cmp #$5a
    beq !huff_still_ok+
    jmp test_fail
!huff_still_ok:
    lda $f000
    cmp #$a5
    beq !top_still_ok+
    jmp test_fail
!top_still_ok:
    jsr spike_verify_all_state
    jsr test_production_b1_noio_and_catalog_ext

    jmp test_pass

// Helper: verify VIC $D020, Bank 0 RAM $D020, VDC $07FF, CIA1/2 latches,
// and all 12 Bank 1 $D000-$DFFF bytes.
spike_verify_all_state:
    lda $d020
    and #$0f
    cmp #$03
    beq !chk_b0_ram+
    jmp test_fail
!chk_b0_ram:
    lda #<$d020
    sta zp_ptr0
    lda #>$d020
    sta zp_ptr0_hi
    ldy #0
    jsr spike_b0_d000_read
    cmp #$12
    beq !chk_vdc+
    jmp test_fail
!chk_vdc:
    jsr spike_vdc_read_07ff
    cmp #$5d
    beq !chk_cia+
    jmp test_fail
!chk_cia:
    lda $dc04
    cmp #$34
    bne !cia_chk_fail+
    lda $dc05
    cmp #$12
    bne !cia_chk_fail+
    lda $dd04
    cmp #$78
    bne !cia_chk_fail+
    lda $dd05
    cmp #$56
    beq !chk_b1_tbl+
!cia_chk_fail:
    jmp test_fail
!chk_b1_tbl:
    ldx #0
!rd_tbl:
    lda spike_addr_lo,x
    sta zp_ptr0
    lda spike_addr_hi,x
    sta zp_ptr0_hi
    ldy #0
    cli
    jsr spike_b1_d000_read
    php
    sei
    cmp spike_expected_val,x
    beq !rd_val_ok+
    pla
    jmp test_fail
!rd_val_ok:
    pla
    and #$04
    beq !rd_cli_ok+
    jmp test_fail
!rd_cli_ok:
    lda MMU_CR
    cmp #MMU_ALL_RAM
    beq !rd_mmu_ok+
    jmp test_fail
!rd_mmu_ok:
    lda $d506
    cmp #$0d
    beq !rd_d506_ok+
    jmp test_fail
!rd_d506_ok:
    inx
    cpx #SPIKE_TBL_LEN
    bne !rd_tbl-
    rts

spike_vdc_wait:
    bit SPIKE_VDC_ADDR
    bpl spike_vdc_wait
    rts

spike_vdc_write:
    pha
    jsr spike_vdc_wait
    stx SPIKE_VDC_ADDR
    jsr spike_vdc_wait
    pla
    sta SPIKE_VDC_DATA
    rts

spike_vdc_read:
    jsr spike_vdc_wait
    stx SPIKE_VDC_ADDR
    jsr spike_vdc_wait
    lda SPIKE_VDC_DATA
    rts

spike_vdc_read_07ff:
    lda #$07
    ldx #18
    jsr spike_vdc_write
    lda #$ff
    ldx #19
    jsr spike_vdc_write
    ldx #31
    jmp spike_vdc_read

spike_addr_lo:
    .byte <$d000, <$d020, <$d500, <$d600, <$d601, <$d800
    .byte <$dc04, <$dc05, <$dd04, <$dd05, <$de00, <$dfff
spike_addr_hi:
    .byte >$d000, >$d020, >$d500, >$d600, >$d601, >$d800
    .byte >$dc04, >$dc05, >$dd04, >$dd05, >$de00, >$dfff
spike_expected_val:
    .byte $5a, $a5, $3c, $91, $82, $f7
    .byte $aa, $bb, $cc, $dd, $6e, $4b

spike_common_blob:
.pseudopc SPIKE_COMMON_BASE {
spike_b1_d000_read:
    php
    sei
    lda #SPIKE_MMU_RAM_BANK1_NOIO
    sta MMU_CR
    lda (zp_ptr0),y
    sta spike_tmp_val
    lda #MMU_ALL_RAM
    sta MMU_CR
    plp
    lda spike_tmp_val
    rts

spike_b1_d000_write:
    sta spike_tmp_val
    php
    sei
    lda #SPIKE_MMU_RAM_BANK1_NOIO
    sta MMU_CR
    lda spike_tmp_val
    sta (zp_ptr0),y
    lda #MMU_ALL_RAM
    sta MMU_CR
    plp
    rts

spike_b0_d000_read:
    php
    sei
    lda #SPIKE_MMU_ALL_RAM_NOIO
    sta MMU_CR
    lda (zp_ptr0),y
    sta spike_tmp_val
    lda #MMU_ALL_RAM
    sta MMU_CR
    plp
    lda spike_tmp_val
    rts

spike_b0_d000_write:
    sta spike_tmp_val
    php
    sei
    lda #SPIKE_MMU_ALL_RAM_NOIO
    sta MMU_CR
    lda spike_tmp_val
    sta (zp_ptr0),y
    lda #MMU_ALL_RAM
    sta MMU_CR
    plp
    rts

spike_common_irq_stub:
    cld
    inc spike_irq_count
    jmp mmu_common_irq

spike_tmp_val:   .byte 0
spike_irq_count: .byte 0
}
spike_common_blob_end:
.assert "Spike common stub fits below $0FB0", spike_common_blob_end - spike_common_blob <= $0fb0 - SPIKE_COMMON_BASE, true

cat_id_lo: .byte 0
cat_id_hi: .byte 0
#import "../catalog_ext_fetch128.s"

.const TEST_CEX_CASE_COUNT = 5
test_cex_ids_lo:
    .byte <0, <1, <255, <256, <278
test_cex_ids_hi:
    .byte >0, >1, >255, >256, >278
test_cex_seeds:
    .byte $11, $37, $7e, $a4, $e9
test_cex_idx:
    .byte 0

// Test 12: Production mmu_common_b1_noio_read/write_ptr0 + catalog_fetch_ext
// across Bank 1 $D000-$D8B7 and msg_history $DCB8-$DF37, preserving VIC/VDC/CIA
// I/O registers, X, zp_ptr0, MMU_CR, $D506, and caller CLI/SEI state.
test_production_b1_noio_and_catalog_ext:
    lda #0
    sta test_cex_idx
!seed_case:
    ldx test_cex_idx
    lda test_cex_ids_hi,x
    sta zp_ptr0_hi
    lda test_cex_ids_lo,x
    asl
    rol zp_ptr0_hi
    asl
    rol zp_ptr0_hi
    asl
    rol zp_ptr0_hi
    sta zp_ptr0
    lda zp_ptr0_hi
    clc
    adc #>BANK1_CATALOG_EXT_BASE
    sta zp_ptr0_hi

    ldy #0
!seed_byte:
    tya
    asl
    clc
    adc test_cex_seeds,x
    eor #$5c
    jsr mmu_common_b1_noio_write_ptr0
    iny
    cpy #CATALOG_EXT_RECORD_SIZE
    bcc !seed_byte-

    inc test_cex_idx
    lda test_cex_idx
    cmp #TEST_CEX_CASE_COUNT
    bcc !seed_case-

    // Verify all 5 boundary records via production catalog_fetch_ext under CLI & SEI
    lda #0
    sta test_cex_idx
!verify_case:
    ldx test_cex_idx
    lda test_cex_ids_lo,x
    sta cat_id_lo
    lda test_cex_ids_hi,x
    sta cat_id_hi

    lda #$fe
    sta zp_ptr0
    lda #$ca
    sta zp_ptr0_hi
    ldx #$5a

    lda test_cex_idx
    and #$01
    bne !call_sei+
    cli
    jsr catalog_fetch_ext
    php
    sei
    pla
    and #$04
    beq !irq_mode_ok+
    jmp test_fail
!call_sei:
    sei
    jsr catalog_fetch_ext
    php
    pla
    and #$04
    bne !irq_mode_ok+
    jmp test_fail
!irq_mode_ok:
    cpx #$5a
    beq !x_preserved+
    jmp test_fail
!x_preserved:
    lda zp_ptr0
    cmp #$fe
    bne !ptr_fail+
    lda zp_ptr0_hi
    cmp #$ca
    beq !ptr_preserved+
!ptr_fail:
    jmp test_fail
!ptr_preserved:
    lda MMU_CR
    cmp #MMU_ALL_RAM
    beq !mmu_preserved+
    jmp test_fail
!mmu_preserved:
    lda $d506
    cmp #$0d
    beq !d506_preserved+
    jmp test_fail
!d506_preserved:
    ldx test_cex_idx
    ldy #0
!chk_ext_byte:
    tya
    asl
    clc
    adc test_cex_seeds,x
    eor #$5c
    cmp cat_ext_record,y
    beq !ext_byte_ok+
    jmp test_fail
!ext_byte_ok:
    iny
    cpy #CATALOG_EXT_RECORD_SIZE
    bcc !chk_ext_byte-

    inc test_cex_idx
    lda test_cex_idx
    cmp #TEST_CEX_CASE_COUNT
    bcs !verify_done+
    jmp !verify_case-
!verify_done:

    // Verify Bank 1 msg_history ($DCB8..$DF37) writes/reads via map thunks without CIA corruption
    lda #<BANK1_MSG_HISTORY_BASE
    sta zp_ptr1
    lda #>BANK1_MSG_HISTORY_BASE
    sta zp_ptr1_hi
    ldy #0
    lda #$73
    jsr mmu_common_map_write_ptr1
    lda #<BANK1_MSG_HISTORY_END
    sta zp_ptr1
    lda #>BANK1_MSG_HISTORY_END
    sta zp_ptr1_hi
    lda #$37
    jsr mmu_common_map_write_ptr1

    lda #<BANK1_MSG_HISTORY_BASE
    sta zp_ptr0
    lda #>BANK1_MSG_HISTORY_BASE
    sta zp_ptr0_hi
    jsr mmu_common_map_read_ptr0
    cmp #$73
    beq !mh_lo_ok+
    jmp test_fail
!mh_lo_ok:
    lda #<BANK1_MSG_HISTORY_END
    sta zp_ptr0
    lda #>BANK1_MSG_HISTORY_END
    sta zp_ptr0_hi
    jsr mmu_common_map_read_ptr0
    cmp #$37
    beq !mh_hi_ok+
    jmp test_fail
!mh_hi_ok:

    // Confirm VIC $D020, Bank 0 RAM $D020, VDC $07FF, and CIA1/2 latches stayed intact
    lda $d020
    and #$0f
    cmp #$03
    beq !io_vic_ok+
    jmp test_fail
!io_vic_ok:
    lda #<$d020
    sta zp_ptr0
    lda #>$d020
    sta zp_ptr0_hi
    ldy #0
    jsr spike_b0_d000_read
    cmp #$12
    beq !io_b0_ok+
    jmp test_fail
!io_b0_ok:
    jsr spike_vdc_read_07ff
    cmp #$5d
    beq !io_vdc_ok+
    jmp test_fail
!io_vdc_ok:
    lda $dc04
    cmp #$34
    bne !io_cia_fail+
    lda $dc05
    cmp #$12
    bne !io_cia_fail+
    lda $dd04
    cmp #$78
    bne !io_cia_fail+
    lda $dd05
    cmp #$56
    beq !io_all_ok+
!io_cia_fail:
    jmp test_fail
!io_all_ok:
    rts

test_pass:
    jmp test_pass
