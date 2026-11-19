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

#import "../../../../core/zeropage.s"
#import "../memory.s"
#define C64_TEST_HIDDEN_MAP
#import "../config.s"

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

    // --------------------------------------------------------
    // Test 3 ($0403): $D700-$DEFF hidden read/write helpers
    // Keep $DF00-$DFFF untouched; verify Color RAM ($D800) != DRAM ($D800)
    // --------------------------------------------------------
    sei
    lda #$36
    sta $01
    lda #$05
    sta $d800               // Color RAM canary (low 4 bits = 5)
    lda #$06
    sta $d810               // Color RAM canary for inc test (low 4 bits = 6)
    cli

    // Write $A5 -> $D700 via ptr0 (Y=0, X=$42, cli)
    lda #$00
    sta zp_ptr0
    lda #$d7
    sta zp_ptr0_hi
    ldy #$00
    ldx #$42
    lda #$a5
    jsr c64_hidden_write_ptr0
    cmp #$a5
    beq !+
    jmp !t4_fail+
!:
    cpx #$42
    beq !+
    jmp !t4_fail+
!:
    cpy #$00
    beq !+
    jmp !t4_fail+
!:
    lda $01
    cmp #$36
    beq !+
    jmp !t4_fail+
!:
    php
    pla
    and #$04                // I flag must still be clear
    beq !+
    jmp !t4_fail+
!:

    // Write $5A -> $D800 via ptr1 (Y=0, X=$77) and verify Color RAM untouched
    lda #$00
    sta zp_ptr1
    lda #$d8
    sta zp_ptr1_hi
    ldy #$00
    ldx #$77
    lda #$5a
    jsr c64_hidden_write_ptr1
    cmp #$5a
    beq !+
    jmp !t4_fail+
!:
    cpx #$77
    beq !+
    jmp !t4_fail+
!:
    cpy #$00
    beq !+
    jmp !t4_fail+
!:
    lda $01
    cmp #$36
    beq !+
    jmp !t4_fail+
!:
    lda $d800
    and #$0f
    cmp #$05
    beq !+
    jmp !t4_fail+
!:

    // Write $81 -> $DEFF via ptr0 (Y=$FF)
    lda #$00
    sta zp_ptr0
    lda #$de
    sta zp_ptr0_hi
    ldy #$ff
    lda #$81
    jsr c64_hidden_write_ptr0

    // Verify I=1 preservation while writing $3C -> $D78D via ptr1 (Y=$8D)
    sei
    lda #$00
    sta zp_ptr1
    lda #$d7
    sta zp_ptr1_hi
    ldy #$8d
    lda #$3c
    jsr c64_hidden_write_ptr1
    php
    pla
    and #$04
    bne !+
    cli
    jmp !t4_fail+
!:
    cli

    // Write $00 -> $D701 via ptr0 for Z-flag read check
    lda #$00
    sta zp_ptr0
    lda #$d7
    sta zp_ptr0_hi
    ldy #$01
    lda #$00
    jsr c64_hidden_write_ptr0

    // Read back $D700 (N=1, Z=0)
    ldy #$00
    ldx #$19
    jsr c64_hidden_read_ptr0
    bmi !+
    jmp !t4_fail+
!:
    bne !+
    jmp !t4_fail+
!:
    cmp #$a5
    beq !+
    jmp !t4_fail+
!:
    cpx #$19
    beq !+
    jmp !t4_fail+
!:
    cpy #$00
    beq !+
    jmp !t4_fail+
!:
    lda $01
    cmp #$36
    beq !+
    jmp !t4_fail+
!:

    // Read back $D701 (N=0, Z=1)
    ldy #$01
    jsr c64_hidden_read_ptr0
    beq !+
    jmp !t4_fail+
!:
    bpl !+
    jmp !t4_fail+
!:

    // Read back $D800 via ptr1 ($5A) and verify Color RAM still $05
    lda #$00
    sta zp_ptr1
    lda #$d8
    sta zp_ptr1_hi
    ldy #$00
    ldx #$2a
    jsr c64_hidden_read_ptr1
    cmp #$5a
    beq !+
    jmp !t4_fail+
!:
    cpx #$2a
    beq !+
    jmp !t4_fail+
!:
    cpy #$00
    beq !+
    jmp !t4_fail+
!:
    lda $d800
    and #$0f
    cmp #$05
    beq !+
    jmp !t4_fail+
!:

    // Read back $DEFF via ptr0 ($81) and $D78D via ptr1 ($3C)
    lda #$de
    sta zp_ptr0_hi
    ldy #$ff
    jsr c64_hidden_read_ptr0
    cmp #$81
    beq !+
    jmp !t4_fail+
!:
    lda #$d7
    sta zp_ptr1_hi
    ldy #$8d
    jsr c64_hidden_read_ptr1
    cmp #$3c
    beq !+
    jmp !t4_fail+
!:

    lda #$01
    sta $0403
    jmp !t4_done+
!t4_fail:
    lda #$00
    sta $0403
!t4_done:

    // --------------------------------------------------------
    // Test 4 ($0404): c64_hidden_inc_ptr0 ($FE -> $FF -> $00)
    // --------------------------------------------------------
    lda #$00
    sta zp_ptr0
    lda #$d8
    sta zp_ptr0_hi
    ldy #$10
    lda #$fe
    jsr c64_hidden_write_ptr0

    ldx #$33
    jsr c64_hidden_inc_ptr0
    bmi !+
    jmp !t5_fail+
!:
    cmp #$ff
    beq !+
    jmp !t5_fail+
!:
    cpx #$33
    beq !+
    jmp !t5_fail+
!:
    cpy #$10
    beq !+
    jmp !t5_fail+
!:
    lda $01
    cmp #$36
    beq !+
    jmp !t5_fail+
!:

    jsr c64_hidden_inc_ptr0
    beq !+
    jmp !t5_fail+
!:
    bpl !+
    jmp !t5_fail+
!:
    jsr c64_hidden_read_ptr0
    cmp #$00
    beq !+
    jmp !t5_fail+
!:
    lda $d810
    and #$0f
    cmp #$06
    beq !+
    jmp !t5_fail+
!:

    lda #$01
    sta $0404
    jmp !t5_done+
!t5_fail:
    lda #$00
    sta $0404
!t5_done:

    // --------------------------------------------------------
    // Test 5 ($0405): c64_hidden_copy (160B cross-page round-trip)
    // $3000..$309F -> $D8CE..$D96D -> $3100..$319F
    // --------------------------------------------------------
    ldx #$00
!fill_src:
    txa
    eor #$a5
    clc
    adc #$01
    sta $3000,x
    lda #$00
    sta $3100,x
    inx
    cpx #160
    bne !fill_src-

    lda #$00
    sta zp_ptr0
    lda #$30
    sta zp_ptr0_hi
    lda #$ce
    sta zp_ptr1
    lda #$d8
    sta zp_ptr1_hi
    ldx #160
    jsr c64_hidden_copy

    lda $01
    cmp #$36
    beq !+
    jmp !t6_fail+
!:
    lda zp_ptr0
    bne !t6_fail+
    lda zp_ptr0_hi
    cmp #$30
    bne !t6_fail+
    lda zp_ptr1
    cmp #$ce
    bne !t6_fail+
    lda zp_ptr1_hi
    cmp #$d8
    bne !t6_fail+

    lda #$ce
    sta zp_ptr0
    lda #$d8
    sta zp_ptr0_hi
    lda #$00
    sta zp_ptr1
    lda #$31
    sta zp_ptr1_hi
    ldx #160
    jsr c64_hidden_copy

    ldx #$00
!cmp_copy:
    lda $3100,x
    cmp $3000,x
    bne !t6_fail+
    inx
    cpx #160
    bne !cmp_copy-

    lda #$01
    sta $0405
    jmp !t6_done+
!t6_fail:
    lda #$00
    sta $0405
!t6_done:

    // --------------------------------------------------------
    // Test 6 ($0406): mmu_safe_map_{read,write}_ptr{0,1}
    // Normal RAM ($C000-$C001) + hidden aux ($D78E, $D800, $DEFF)
    // --------------------------------------------------------
    lda #$00
    sta $c000
    sta $c001
    sta zp_ptr0
    sta zp_ptr1
    lda #$c0
    sta zp_ptr0_hi
    sta zp_ptr1_hi

    ldy #$00
    lda #$4b
    jsr mmu_safe_map_write_ptr0
    lda #$00
    jsr mmu_safe_map_read_ptr0
    cmp #$4b
    beq !+
    jmp !t7_fail+
!:
    lda $c000
    cmp #$4b
    beq !+
    jmp !t7_fail+
!:

    ldy #$01
    lda #$93
    jsr mmu_safe_map_write_ptr1
    lda #$00
    jsr mmu_safe_map_read_ptr1
    cmp #$93
    beq !+
    jmp !t7_fail+
!:
    lda $c001
    cmp #$93
    beq !+
    jmp !t7_fail+
!:

    // Hidden $D78E via ptr1
    lda #$8e
    sta zp_ptr1
    lda #$d7
    sta zp_ptr1_hi
    ldy #$00
    lda #$7e
    jsr mmu_safe_map_write_ptr1
    lda #$00
    jsr mmu_safe_map_read_ptr1
    cmp #$7e
    beq !+
    jmp !t7_fail+
!:

    // Hidden $D800 via ptr0 (Color RAM must stay $05)
    lda #$00
    sta zp_ptr0
    lda #$d8
    sta zp_ptr0_hi
    ldy #$00
    lda #$c3
    jsr mmu_safe_map_write_ptr0
    lda #$00
    jsr mmu_safe_map_read_ptr0
    cmp #$c3
    bne !t7_fail+
    lda $d800
    and #$0f
    cmp #$05
    bne !t7_fail+

    // Hidden $DEFF via ptr1
    lda #$00
    sta zp_ptr1
    lda #$de
    sta zp_ptr1_hi
    ldy #$ff
    lda #$2d
    jsr mmu_safe_map_write_ptr1
    lda #$00
    jsr mmu_safe_map_read_ptr1
    cmp #$2d
    bne !t7_fail+

    lda $01
    cmp #$36
    bne !t7_fail+
    php
    pla
    and #$04
    bne !t7_fail+

    lda #$01
    sta $0406
    jmp !t7_done+
!t7_fail:
    lda #$00
    sta $0406
!t7_done:

    lda #$37
    sta $01
    brk
