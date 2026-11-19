#import "cartridge_contract.s"
// Plus/4 c264 magic cart native autostart ROM (Bank 0 C1LO at $8000).
// KERNAL reset ($FFF6 -> $F2A4) runs IOINIT, RAMTAS, RESTOR, and CINT before
// jumping to $8000. The copier runs in cassette/door-scan scratch ($033C-$03FB)
// and bounces chunks through $0400-$04FF (unused until dungeon generation)
// because moria4.prg ($1001..~$C7xx) overlaps the $8000-$BFFF C1LO window.
.const CART_BOOT_COPY_BASE = $033c
.const CART_BOOT_COPY_END = $03fc
.const CART_BOOT_BOUNCE = $0400
.const CART_BOOT_ROM_ENABLE = $ff3e
.const CART_BOOT_RAM_ENABLE = $ff3f

.if (!cmdLineVars.containsKey("CART_OUT")) {
    .error "CART_OUT is required; generated files belong under build/"
}
.var CART_OUT = cmdLineVars.get("CART_OUT")
.segmentdef BootRom [outBin=CART_OUT + "/bootrom.bin", start=$8000, min=$8000, max=$80ff]

.segment BootRom
    jmp cold
    jmp cold
    .byte $01                   // Autostart cartridge ID >= 1
    .byte $43, $42, $4d         // "CBM" signature

.const CART_KERNAL_CINT   = $ff81
.const CART_KERNAL_IOINIT = $ff84
.const CART_KERNAL_RAMTAS = $ff87
.const CART_KERNAL_RESTOR = $ff8a
.const CART_TED_CURSOR_HI = $ff0c
.const CART_TED_CURSOR_LO = $ff0d

cold:
    sei
    cld
    ldx #$ff
    txs
    lda #0
    sta CART_REG_BANK
    sta CART_REG_C1LO_KERNAL
    sta CART_BOOT_ROM_ENABLE
    // Plus/4 autostart ID $01 runs inside $FC4E before IOINIT/RAMTAS/RESTOR/CINT.
    // Initialize KERNAL, vectors ($0312-$0331), and keyboard tables before copying.
    jsr CART_KERNAL_IOINIT
    jsr CART_KERNAL_RAMTAS
    jsr CART_KERNAL_RESTOR
    jsr CART_KERNAL_CINT
    sei
    // CINT homes the TED hardware cursor to cell 0 (top-left); park it off-screen ($03FF).
    lda #$ff
    sta CART_TED_CURSOR_HI
    sta CART_TED_CURSOR_LO
    lda #0
    sta CART_REG_BANK
    sta CART_REG_C1LO_KERNAL
    sta CART_BOOT_ROM_ENABLE
boot_copy_prepare:
    ldx #copy_end - copy
!copy:
    lda copy - 1,x
    sta CART_BOOT_COPY_BASE - 1,x
    dex
    bne !copy-
    jmp CART_BOOT_COPY_BASE

copy:
.pseudopc CART_BOOT_COPY_BASE {
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
!loop:
    // Resident source begins at a ROM page boundary (checked by packer).
    // boot_chunk_count = 0 copies 256 bytes; 1..255 is the final partial page.
    lda boot_count + 1
    beq !tail+
    lda #0
    beq !chunk+
!tail:
    lda boot_count
    beq !done+
!chunk:
    sta boot_chunk_count
    tax
    lda boot_bank
    sta CART_REG_BANK
    sta CART_REG_C1LO_KERNAL
    sta CART_BOOT_ROM_ENABLE
    ldy #0
boot_source:
    lda $8000,y
    sta CART_BOOT_BOUNCE,y
    iny
    dex
    bne boot_source
    lda #0
    sta CART_REG_BANK
    sta CART_REG_BASIC_KERNAL
    sta CART_BOOT_RAM_ENABLE
    ldx boot_chunk_count
    ldy #0
!write_bounce:
    lda CART_BOOT_BOUNCE,y
boot_destination:
    sta $1001,y
    iny
    dex
    bne !write_bounce-
    tya
    bne !done+
    inc boot_source + 2
    inc boot_destination + 2
    lda boot_source + 2
    cmp #>CART_ROM_WINDOW_END
    bne !count+
    lda #>CART_ROM_WINDOW_BASE
    sta boot_source + 2
    inc boot_bank
!count:
    dec boot_count + 1
    jmp !loop-
!done:
    lda #0
    sta CART_REG_BANK
    sta CART_REG_BASIC_KERNAL
    sta CART_BOOT_ROM_ENABLE    // KERNAL visible for entry's KERNAL_SETMSG call
    jmp CART_ENTRY
boot_count:       .word 0
boot_bank:        .byte 0
boot_chunk_count: .byte 0
}
copy_end:
.assert "Boot copier fits cassette scratch below bounce buffer", CART_BOOT_COPY_BASE + copy_end - copy <= CART_BOOT_COPY_END, true
.assert "Boot copier avoids KERNAL vectors and bounce buffer", CART_BOOT_COPY_BASE >= $033c && CART_BOOT_COPY_END <= CART_BOOT_BOUNCE, true
.assert "Boot ROM leaves directory at $8100", * <= CART_DIRECTORY, true
