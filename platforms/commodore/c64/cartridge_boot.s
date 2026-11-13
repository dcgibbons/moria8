#import "cartridge_contract.s"
// EasyFlash native reset ROM. Owner: bank-0 ROMH ($E000 at reset), plus
// bank-0 ROML ($8000 in normal mode). The reset bridge uses $0200 before
// RAMTAS; the main copier uses cassette-buffer $033C-$03FB, dead at entry.
// Generation later owns this cassette scratch (memory.s door-scan buffer).
// Keep the KERNAL keyboard/editor variables at $0277-$02FF intact.
.const CART_BOOT_COPY_BASE = $033c
.const CART_BOOT_COPY_END = $03fc
.if (!cmdLineVars.containsKey("CART_OUT")) {
    .error "CART_OUT is required; generated files belong under build/"
}
.var CART_OUT = cmdLineVars.get("CART_OUT")
.segmentdef RomL [outBin=CART_OUT + "/roml.bin", start=$8000, min=$8000, max=$80ff]
.segmentdef RomH [outBin=CART_OUT + "/romh.bin", start=$e000, min=$e000, max=$ffff]
.segment RomH
reset:
    sei
    cld
    ldx #$ff
    txs
    lda #$37
    sta $01
    lda #$2f
    sta $00
    ldx #bridge_end - bridge - 1
!bridge:
    lda bridge,x
    sta $0200,x
    dex
    bpl !bridge-
    jmp $0200
bridge:
.pseudopc $0200 {
    lda #$07                 // Normal 16 KB cart, system KERNAL visible
    sta $de02
    jmp ($fffc)                // KERNAL reset detects our CBM80 entry
}
bridge_end:
.pc = $fffa
    .word reset, reset, reset

.segment RomL
    .word cold, cold
    .byte $c3,$c2,$cd,$38,$30  // CBM80
cold:
    sei
    jsr $ff84                // IOINIT
    jsr $ff87                // RAMTAS (before copying the RAM boot routine)
    jsr $ff8a                // RESTOR
    jsr $ff81                // CINT
    sei
boot_copy_prepare:
    ldx #copy_end - copy - 1
!copy:
    lda copy,x
    sta CART_BOOT_COPY_BASE,x
    dex
    cpx #$ff
    bne !copy-
    jmp CART_BOOT_COPY_BASE
copy:
.pseudopc CART_BOOT_COPY_BASE {
    lda #<boot_nmi
    sta $0318
    lda #>boot_nmi
    sta $0319
    lda #$06
    sta $de02
    lda CART_DIRECTORY + 0
    sta boot_bank
    lda CART_DIRECTORY + 1
    sta boot_source + 1
    lda CART_DIRECTORY + 2
    sta boot_source + 2
    lda CART_DIRECTORY + 3
    sta boot_destination + 1
    lda CART_DIRECTORY + 4
    sta boot_destination + 2
    lda CART_DIRECTORY + 5
    sta boot_count
    lda CART_DIRECTORY + 6
    sta boot_count + 1
    lda boot_bank
    sta $de00
!loop:
    // Resident source begins at a ROM page boundary (checked by packer).
    // X=0 copies a whole page; otherwise this is the final partial page.
    ldx boot_count + 1
    beq !tail+
    ldx #0
    beq !chunk+
!tail:
    ldx boot_count
    beq !done+
!chunk:
    ldy #0
boot_source:
    lda $8000,y
boot_destination:
    sta $0801,y
    iny
    dex
    bne boot_source
    tya
    bne !done+
    inc boot_source + 2
    inc boot_destination + 2
    lda boot_source + 2
    cmp #$a0
    bne !count+
    lda #$80
    sta boot_source + 2
    inc boot_bank
    lda boot_bank
    sta $de00
!count:
    dec boot_count + 1
    jmp !loop-
!done:
    lda #$04
    sta $de02
    jsr $ff8a                // Restore KERNAL vectors after boot NMI guard
    jmp CART_ENTRY
boot_nmi:
    pha
    lda $dd0d
    pla
    rti
boot_count: .word 0
boot_bank: .byte 0
}
copy_end:
.assert "Boot copier fits cassette scratch below screen", CART_BOOT_COPY_BASE + copy_end - copy <= CART_BOOT_COPY_END, true
.assert "Boot copier avoids KERNAL vectors and keyboard workspace", CART_BOOT_COPY_BASE >= $033c && CART_BOOT_COPY_END <= $0400, true
.assert "Boot ROML leaves directory at $8100", * <= $8100, true
