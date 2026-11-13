// Commander X16 Cartridge cold boot ROM (Bank 32, $C000-$C0FF).
// x16-rom checks Bank 32 $C000-$C003 for "CX16", then calls $C004 with I=1.
// Copies MORIA8.PRG from Cart ROM Banks 32+ via a low-RAM stub at $0400,
// restores $00=0 and $01=0 (KERNAL Bank 0), flushes any buffered keys from
// boot_cartridge's Shift-check window ($A80A), enables IRQs (cli), and jumps
// to entry_bootstrap ($080D).

.cpu _65c02
#import "cartridge_contract.s"

.const BOOT_RAM_BANK_REG = $00
.const BOOT_ROM_BANK_REG = $01
.const BOOT_KBDBUF_COUNT = $a80a

.var cart_out_dir = cmdLineVars.containsKey("CART_OUT") ? cmdLineVars.get("CART_OUT") : "."

.segmentdef CartBoot [start=$c000, min=$c000, max=$c0ff]
.file [name=cart_out_dir + "/bootrom.bin", type="bin", segments="CartBoot"]

.segment CartBoot
    .byte $43, $58, $31, $36    // "CX16" cartridge autostart signature

boot_cold_start:
    sei
    cld
    ldx #$ff
    txs
    stz BOOT_RAM_BANK_REG

boot_copy_prepare:
    ldx #0
!copy_stub:
    lda boot_ram_stub_src,x
    sta CART_COPY_STUB_ADDR,x
    inx
    cpx #(boot_ram_stub_end - boot_ram_stub)
    bne !copy_stub-
    jmp boot_ram_stub

boot_ram_stub_src:
.pseudopc CART_COPY_STUB_ADDR {
boot_ram_stub:
    lda #CART_ROM_BANK_START
    sta BOOT_ROM_BANK_REG
    lda CART_DIRECTORY + CART_DESC_BANK
    sta boot_src_bank
    lda CART_DIRECTORY + CART_DESC_ROM_LO
    sta boot_src + 1
    lda CART_DIRECTORY + CART_DESC_ROM_HI
    sta boot_src + 2
    lda CART_DIRECTORY + CART_DESC_DEST_LO
    sta boot_dst + 1
    lda CART_DIRECTORY + CART_DESC_DEST_HI
    sta boot_dst + 2
    lda CART_DIRECTORY + CART_DESC_SIZE_LO
    sta boot_rem_lo
    lda CART_DIRECTORY + CART_DESC_SIZE_HI
    sta boot_rem_hi
    lda boot_src_bank
    sta BOOT_ROM_BANK_REG

boot_copy_loop:
    lda boot_rem_lo
    ora boot_rem_hi
    beq boot_copy_done
boot_src:
    lda $ffff
boot_dst:
    sta $ffff
    inc boot_src + 1
    bne !+
    inc boot_src + 2
    bne !+
    lda #>CART_ROM_WINDOW_BASE
    sta boot_src + 2
    inc BOOT_ROM_BANK_REG
!:
    inc boot_dst + 1
    bne !+
    inc boot_dst + 2
!:
    lda boot_rem_lo
    bne !+
    dec boot_rem_hi
!:
    dec boot_rem_lo
    bra boot_copy_loop

boot_copy_done:
    stz BOOT_RAM_BANK_REG
    stz BOOT_ROM_BANK_REG
    stz BOOT_KBDBUF_COUNT
    cli
    // Headless testbench trap (only active in x16emu when harness primes $07FC-$07FF = "M8TB").
    lda CART_EMU_SIG0
    cmp #$31
    bne !launch+
    lda CART_EMU_SIG1
    cmp #$36
    bne !launch+
    ldx #3
!tb_chk:
    lda CART_TB_MAGIC_ADDR,x
    cmp boot_tb_magic,x
    bne !launch+
    dex
    bpl !tb_chk-
    stz CART_TB_MAGIC_ADDR
    jmp $fffd
!launch:
    jmp CART_ENTRY

boot_src_bank: .byte 0
boot_rem_lo:   .byte 0
boot_rem_hi:   .byte 0
boot_tb_magic: .byte $4d, $38, $54, $42 // "M8TB"
boot_ram_stub_end:
}
boot_rom_end:

.assert "Boot ROM stub fits in $0400-$04FF", boot_ram_stub_end <= CART_COPY_STUB_ADDR + $0100, true
.assert "Boot ROM fits before directory at $C100", boot_rom_end <= CART_BOOT_LIMIT, true
