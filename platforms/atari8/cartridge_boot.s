#import "memory.s"
#import "cartridge_contract.s"
// AtariMax MaxFlash 128 KB native cartridge cold-boot PackBits loader.
// Owner: platforms/atari8/ Bank 0 ROM ($A000-$BFFF at reset).
// Lifetime: cold boot only (exits to resident MORIA8.RES at CART_ENTRY $0C00).
// Callers: Atari XL/XE OS reset dispatch via hardware cartridge vector $BFFA-$BFFF.
//
// Because Atari XL/XE cartridge ROM maps at $A000-$BFFF with no RAM write-through
// while RD5=1, the copier runs in SCREEN_RAM ($0800), prefetches 256-byte PackBits
// ROM pages into $0900-$09FF, immediately disables the cartridge ($D510) so all
// unpacked writes hit Main RAM ($0C00..$C0FF), and synchronizes OS_GINTLK ($03FA)
// with TRIG3 ($D013) before entering the game.

.if (!cmdLineVars.containsKey("CART_OUT")) {
    .error "CART_OUT is required; generated files belong under build/"
}
.var CART_OUT = cmdLineVars.get("CART_OUT")

.const BOOT_ZP_SRC        = $02
.const BOOT_ZP_SRC_HI     = $03
.const BOOT_ZP_DST        = $04
.const BOOT_ZP_DST_HI     = $05
.const BOOT_ZP_BANK       = $06
.const BOOT_ZP_PAGES_LEFT = $07
.const BOOT_ZP_SRC_IDX    = $08
.const BOOT_ZP_SAVED_X    = $09
.const BOOT_BOUNCE        = SCREEN_RAM + $0100

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
    ldx #7
!clr_pokey:
    sta AUDF1,x
    dex
    bpl !clr_pokey-
    lda #PORTB_GAME_RAM
    sta PORTB
    ldx #boot_copier_end - boot_copier
!copy_ram:
    lda boot_copier - 1,x
    sta SCREEN_RAM - 1,x
    dex
    bne !copy_ram-
    jmp SCREEN_RAM

boot_copier:
.pseudopc SCREEN_RAM {
    sta CART_BANK_SELECT       // Ensure Bank 0 directory is mapped at $A000
    lda CART_DIRECTORY + 0
    sta BOOT_ZP_BANK
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
    bne boot_invalid_near      // CART_ENTRY ($0C00) low byte is $00
    lda CART_DIRECTORY + 4
    sta BOOT_ZP_DST_HI
    cmp #>CART_ENTRY
    bne boot_invalid_near
    ldy CART_DIRECTORY + 6
    lda CART_DIRECTORY + 5
    beq !exact_pages+
    iny
    beq boot_invalid_near
!exact_pages:
    tya
    beq boot_invalid_near
    sta BOOT_ZP_PAGES_LEFT
    lda #0
    sta BOOT_ZP_SRC_IDX
    beq !pb_pkt+
boot_invalid_near:
    jmp boot_invalid

!pb_pkt:
    jsr next_src_byte          // A = PackBits packet header
    cmp #$80
    beq !done+                 // $80 -> EOF
    bcs !pb_run+               // $81..$FF -> repeat 257 - n times
    tax                        // $00..$7F -> copy X + 1 literal bytes
!pb_lit:
    jsr next_src_byte
    jsr put_dst_byte
    dex
    bpl !pb_lit-
    bmi !pb_pkt-
!pb_run:
    eor #$ff
    adc #1                     // C=1 on entry from bcs -> A = 257 - n (2..128)
    tax
    jsr next_src_byte          // A = repeated byte
!pb_fill:
    jsr put_dst_byte
    dex
    bne !pb_fill-
    beq !pb_pkt-

!done:
    sta CART_DISABLE
    lda CART_TRIG3
    sta CART_OS_GINTLK         // Sync OS VBI interlock while cartridge RD5=0
    jmp CART_ENTRY

next_src_byte:
    ldy BOOT_ZP_SRC_IDX
    bne !nsb_have+
    stx BOOT_ZP_SAVED_X
    lda BOOT_ZP_PAGES_LEFT
    beq boot_invalid
    dec BOOT_ZP_PAGES_LEFT
    ldx BOOT_ZP_BANK
    cpx #CART_ROM_BANK_COUNT
    bcs boot_invalid
    sta CART_BANK_SELECT,x     // Enable source ROM bank at $A000-$BFFF
!nsb_fill:
    lda (BOOT_ZP_SRC),y
    sta BOOT_BOUNCE,y
    iny
    bne !nsb_fill-
    sta CART_DISABLE           // Disable cartridge so $A000-$BFFF writes hit Main RAM
    inc BOOT_ZP_SRC_HI
    lda BOOT_ZP_SRC_HI
    cmp #>CART_WINDOW_END
    bcc !nsb_bank_ok+
    lda #>CART_WINDOW
    sta BOOT_ZP_SRC_HI
    inc BOOT_ZP_BANK
!nsb_bank_ok:
    ldx BOOT_ZP_SAVED_X
!nsb_have:
    lda BOOT_BOUNCE,y
    iny
    sty BOOT_ZP_SRC_IDX
    rts

put_dst_byte:
    ldy BOOT_ZP_DST_HI
    cpy #>MAP_BASE
    bcs boot_invalid
    ldy #0
    sta (BOOT_ZP_DST),y
    inc BOOT_ZP_DST
    bne !pdb_ok+
    inc BOOT_ZP_DST_HI
!pdb_ok:
    rts

boot_invalid:
    sta CART_DISABLE
    inc COLBK
    jmp boot_invalid

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
