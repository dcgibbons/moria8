#import "memory.s"
#import "cartridge_contract.s"
// AtariMax MaxFlash 128 KB native cartridge cold-boot loader.
// Owner: platforms/atari8/ Bank 0 ROM ($A000-$BFFF at reset).
// Lifetime: cold boot only (exits to resident MORIA8.RES at CART_ENTRY $0C00).
// Callers: Atari XL/XE OS reset dispatch via hardware cartridge vector $BFFA-$BFFF.
//
// Because Atari XL/XE cartridge ROM maps at $A000-$BFFF with no RAM write-through
// while RD5=1, the copier runs in SCREEN_RAM ($0800) and bounces each chunk
// through $0900-$09FF with the cartridge temporarily disabled ($D510), then
// synchronizes OS_GINTLK ($03FA) with TRIG3 ($D013) before entering the game.

.if (!cmdLineVars.containsKey("CART_OUT")) {
    .error "CART_OUT is required; generated files belong under build/"
}
.var CART_OUT = cmdLineVars.get("CART_OUT")

.const BOOT_ZP_SRC     = $02
.const BOOT_ZP_SRC_HI  = $03
.const BOOT_ZP_DST     = $04
.const BOOT_ZP_DST_HI  = $05
.const BOOT_ZP_CNT     = $06
.const BOOT_ZP_CNT_HI  = $07
.const BOOT_BOUNCE     = SCREEN_RAM + $0100

.segmentdef Bank0 [outBin=CART_OUT + "/bank0.bin", start=$a000, min=$a000, max=$bfff, fill, fillByte=$ff]
.segment Bank0

.pc = $a000 "Bank 0 Boot Stub"
cart_init:
    rts

cart_start:
    sei
    cld
    ldx #$ff
    txs
    lda #$00
    sta NMIEN
    sta IRQEN
    sta DMACTL
    sta AUDC1
    sta AUDC2
    sta AUDC3
    sta AUDC4
    lda #PORTB_GAME_RAM
    sta PORTB
    ldx #boot_copier_end - boot_copier - 1
!copy_ram:
    lda boot_copier,x
    sta SCREEN_RAM,x
    dex
    cpx #$ff
    bne !copy_ram-
    jmp SCREEN_RAM

boot_copier:
.pseudopc SCREEN_RAM {
    sta CART_BANK_SELECT       // Ensure Bank 0 directory is mapped at $A000
    lda CART_DIRECTORY + 0
    sta boot_bank
    cmp #CART_ROM_BANK_COUNT
    bcs boot_invalid_near
    lda CART_DIRECTORY + 1
    sta BOOT_ZP_SRC
    bne boot_invalid_near      // Boot copier requires page-aligned resident source
    lda CART_DIRECTORY + 2
    sta BOOT_ZP_SRC_HI
    cmp #>CART_WINDOW
    bcc boot_invalid_near
    cmp #>CART_WINDOW_END
    bcs boot_invalid_near
    lda CART_DIRECTORY + 3
    sta BOOT_ZP_DST
    cmp #<CART_ENTRY
    bne boot_invalid_near
    lda CART_DIRECTORY + 4
    sta BOOT_ZP_DST_HI
    cmp #>CART_ENTRY
    bne boot_invalid_near
    lda CART_DIRECTORY + 5
    sta BOOT_ZP_CNT
    lda CART_DIRECTORY + 6
    sta BOOT_ZP_CNT_HI
    ora BOOT_ZP_CNT
    bne !loop+
boot_invalid_near:
    jmp boot_invalid

!loop:
    lda BOOT_ZP_CNT
    ora BOOT_ZP_CNT_HI
    beq !done+
    ldx #0                     // X=0 -> 256-byte full page
    lda BOOT_ZP_CNT_HI
    bne !chunk_ready+
    ldx BOOT_ZP_CNT
!chunk_ready:
    stx boot_chunk
    ldx boot_bank
    sta CART_BANK_SELECT,x     // Enable source ROM bank at $A000-$BFFF
    ldy #0
    ldx boot_chunk
!read_rom:
    lda (BOOT_ZP_SRC),y
    sta BOOT_BOUNCE,y
    iny
    dex
    bne !read_rom-

    sta CART_DISABLE           // Disable cartridge so $A000-$BFFF writes hit Main RAM
    ldy #0
    ldx boot_chunk
!write_ram:
    lda BOOT_BOUNCE,y
    sta (BOOT_ZP_DST),y
    iny
    dex
    bne !write_ram-

    lda boot_chunk
    bne !done+                 // Final partial page completes transfer
    dec BOOT_ZP_CNT_HI
    inc BOOT_ZP_DST_HI
    inc BOOT_ZP_SRC_HI
    lda BOOT_ZP_SRC_HI
    cmp #>CART_WINDOW_END
    bcc !loop-
    lda #>CART_WINDOW
    sta BOOT_ZP_SRC_HI
    inc boot_bank
    lda boot_bank
    cmp #CART_ROM_BANK_COUNT
    bcc !loop-

boot_invalid:
    inc COLBK
    jmp boot_invalid

!done:
    sta CART_DISABLE
    lda CART_TRIG3
    sta CART_OS_GINTLK         // Sync OS VBI interlock while cartridge RD5=0
    jmp CART_ENTRY

boot_bank:  .byte 0
boot_chunk: .byte 0
boot_copier_ram_end:
}
boot_copier_end:
boot_rom_end:

.assert "Boot stub fits below Bank 0 directory ($A100)", boot_rom_end <= CART_DIRECTORY, true
.assert "RAM boot copier stays below bounce buffer ($0900)", boot_copier_ram_end <= BOOT_BOUNCE, true
.assert "RAM boot copier fits in 256-byte init loop", boot_copier_end - boot_copier <= 256, true

.pc = $bffa "Atari Cartridge Header"
    .word cart_start
    .byte $00                  // $00 = cartridge present
    .byte $04                  // Bit 2 = run cart; Bit 0 = 0 (no disk boot); Bit 7 = 0 (normal init)
    .word cart_init
