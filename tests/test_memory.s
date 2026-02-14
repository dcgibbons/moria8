// test_memory.s — Runtime tests for memory.s bank switching
//
// Tests:
// 1. Write to $A000 (RAM under BASIC ROM), bank out BASIC, read back
// 2. Write to $E000 (RAM under KERNAL ROM), bank out KERNAL, read back
// 3. ZP save/restore round-trip
//
// Results at $0400: $01 = pass per test

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $0810 "Test Code"

#import "../zeropage.s"
#import "../memory.s"

test_start:
    // Init results
    ldx #7
    lda #$ff
!clr:
    sta $0400,x
    dex
    bpl !clr-

    // ==========================================
    // Test 1: Write $A5 to $A000, read back with BASIC banked out
    // CPU writes always go to RAM, so write should work even
    // with BASIC ROM visible. But read requires banking out.
    // ==========================================
    lda #$a5
    sta $a000               // Write goes to RAM
    // Now bank out BASIC and read back
    :BankOutBasic()
    lda $a000
    cmp #$a5
    bne !t1_fail+
    :BankInBasic()
    lda #$01
    sta $0400
    jmp !t1_done+
!t1_fail:
    :BankInBasic()
    lda #$00
    sta $0400
!t1_done:

    // ==========================================
    // Test 2: Write $5A to $E000, read back with KERNAL banked out
    // ==========================================
    lda #$5a
    sta $e000               // Write goes to RAM
    // Bank out KERNAL (with SEI)
    sei
    :BankOutKernal()
    lda $e000
    cmp #$5a
    bne !t2_fail+
    :BankInKernal()
    cli
    lda #$01
    sta $0401
    jmp !t2_done+
!t2_fail:
    :BankInKernal()
    cli
    lda #$00
    sta $0401
!t2_done:

    // ==========================================
    // Test 3: ZP save/restore round-trip (full range $02–$8F)
    // Write recognizable pattern to all 142 ZP bytes, save,
    // overwrite with zeros, restore, verify all match.
    // ==========================================
    // Write test pattern: each byte = index XOR $A5
    ldx #0
!t3_write:
    txa
    eor #$a5
    sta $02,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !t3_write-

    // Save ZP
    jsr save_zp

    // Overwrite all with zeros
    ldx #0
    lda #$00
!t3_zero:
    sta $02,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !t3_zero-

    // Restore ZP
    jsr restore_zp

    // Verify all 142 bytes match expected pattern
    ldx #0
!t3_verify:
    txa
    eor #$a5
    cmp $02,x
    bne !t3_fail+
    inx
    cpx #ZP_SAVE_SIZE
    bne !t3_verify-

    lda #$01
    sta $0402
    jmp !t3_done+
!t3_fail:
    lda #$00
    sta $0402
!t3_done:

    brk
