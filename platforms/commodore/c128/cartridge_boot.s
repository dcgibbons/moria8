// Commodore 128 Magic Desk 128 cold boot stub at External Function ROM $8000.
// Built standalone with :CART_OUT=<out> into rom0.bin ($8000-$80FF).
#import "cartridge_contract.s"

.var cart_out = cmdLineVars.get("CART_OUT")
.file [name=cart_out + "/rom0.bin", type="bin", segments="RomBoot"]
.segmentdef RomBoot [start=$8000, min=$8000, max=$80ff]
.segment RomBoot

.label boot_zp_src = $fb
.label boot_zp_dst = $fd
.const BOOT_COPIER_RAM = $1800

    jmp cold_start
    jmp cold_start
    .byte $01                       // C128 External Function ROM autostart ID
    .byte $43, $42, $4d             // "CBM" ($8007-$8009)

cold_start:
    sei
    cld
    ldx #$ff
    txs
    ldx #0
!copy_stub:
    lda boot_copier,x
    sta BOOT_COPIER_RAM,x
    inx
    cpx #boot_copier_end - boot_copier
    bne !copy_stub-
    jmp BOOT_COPIER_RAM

boot_copier:
.pseudopc BOOT_COPIER_RAM {
    // Cartridge autostart ID $01 runs before C128 KERNAL completes RAMTAS,
    // RESTOR, and CINT; run them from RAM under Bank 15 so $0314-$0333 IEC/IRQ
    // vectors and editor tables are valid before Drive 8/9 KERNAL I/O runs.
    lda #$00
    sta $ff00
    jsr $ff84                       // IOINIT
    jsr $ff87                       // RAMTAS
    jsr $ff8a                       // RESTOR
    jsr $ff81                       // CINT
    sei
    cld
    ldx #$ff
    txs
    lda #$05                        // 4KB bottom common; Bank 0 RAM everywhere below $8000
    sta $d506
    lda #MMU_EXT_ROM_IO             // $3A: Bank 0 RAM, Ext Function ROM ($8000-$BFFF), I/O
    sta $ff00
    lda #0
    sta CART_REG_BANK               // Directory lives in Bank 0 at $8100

    lda CART_DIRECTORY + (CART_ASSET_RESIDENT * CART_DESCRIPTOR_SIZE) + 0
    sta boot_bank
    lda CART_DIRECTORY + (CART_ASSET_RESIDENT * CART_DESCRIPTOR_SIZE) + 1
    sta boot_zp_src
    lda CART_DIRECTORY + (CART_ASSET_RESIDENT * CART_DESCRIPTOR_SIZE) + 2
    sta boot_zp_src + 1
    lda CART_DIRECTORY + (CART_ASSET_RESIDENT * CART_DESCRIPTOR_SIZE) + 3
    sta boot_zp_dst
    lda CART_DIRECTORY + (CART_ASSET_RESIDENT * CART_DESCRIPTOR_SIZE) + 4
    sta boot_zp_dst + 1
    lda CART_DIRECTORY + (CART_ASSET_RESIDENT * CART_DESCRIPTOR_SIZE) + 5
    sta boot_len
    lda CART_DIRECTORY + (CART_ASSET_RESIDENT * CART_DESCRIPTOR_SIZE) + 6
    sta boot_len + 1

    lda boot_bank
    sta CART_REG_BANK
    ldy #0
!copy_loop:
    lda boot_len
    bne !take_byte+
    lda boot_len + 1
    beq !done+
    dec boot_len + 1
!take_byte:
    dec boot_len
    lda (boot_zp_src),y
    sta (boot_zp_dst),y
    inc boot_zp_src
    bne !src_ok+
    inc boot_zp_src + 1
    lda boot_zp_src + 1
    cmp #$c0
    bne !src_ok+
    lda #$80
    sta boot_zp_src + 1
    inc boot_bank
    lda boot_bank
    sta CART_REG_BANK
!src_ok:
    inc boot_zp_dst
    bne !copy_loop-
    inc boot_zp_dst + 1
    jmp !copy_loop-

!done:
    lda #0
    sta CART_REG_BANK
    lda #$0e                        // MMU_NORMAL: Bank 0 RAM, KERNAL ROM, I/O
    sta $ff00
    lda #$36
    sta $01
    jmp CART_ENTRY                  // $1c0e -> entry_real

boot_bank: .byte 0
boot_len:  .word 0
}
boot_copier_end:
.assert "C128 cartridge boot fits before directory at $8100", * <= CART_DIRECTORY, true
