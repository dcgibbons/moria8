// boot.s — Chain-loading bootloader for Moria8 C64
//
// Standalone assembly unit. Loads a bitmap boot-art asset, displays it,
// then chain-loads the game binary (MORIA64) from disk.
//
// Disk layout in the current dual-entry disk:
//   "moria8"    = this directory-entry bootloader on C64
//   "boot64"    = debug/explicit child entry alias to this same bootloader
//   "bootart64" = bitmap boot-art asset staged at $A000
//   "moria64"   = game binary (loaded by this bootloader)

#import "hal/memory_bank_consts.s"
#import "../common/bank_port_consts.s"

// ============================================================
// BASIC stub — SYS 2062 ($080E)
// ============================================================
.pc = $0801 "BASIC Stub"
:BasicUpstart2(boot_entry)

// ============================================================
// Bootloader entry / constants
// ============================================================
.const VIC_BANK3_SELECT = %11111100
.const VIC_BANK0_SELECT = %00000011

.const ART_STAGE        = $A000
.const ART_SCREEN_STAGE = $BF40
.const ART_COLOR_STAGE  = $C328
.const ART_BITMAP_DEST  = $E000
.const ART_SCREEN_DEST  = $DC00
.const ART_COLOR_DEST   = $D800
.const ART_BITMAP_PAGES = $1F
.const ART_BITMAP_TAIL  = $40
.const ART_ATTR_PAGES   = $03
.const ART_ATTR_TAIL    = $E8

.const BITMAP_D011      = $3B
.const BITMAP_D016      = $18
.const BITMAP_D018      = $78
.const TEXT_D011        = $1B
.const TEXT_D016        = $08
.const TEXT_D018        = $14

.const LOGICAL_FILE     = 2
.const DEVICE_NUM       = 8
.const LOAD_USE_HEADER  = 1

.const CHAIN_STUB_ADDR  = $0340
.const CHAIN_STUB_MAX   = $c0

.const ZP_SRC_LO        = $FB
.const ZP_SRC_HI        = $FC
.const ZP_DST_LO        = $FD
.const ZP_DST_HI        = $FE

.pc = $080E "Boot"
boot_entry:
    jsr capture_boot_device
    lda #$93
    jsr $ffd2               // Clear screen
    lda #0
    sta $d020
    sta $d021

    jsr load_boot_art
    bcs load_main_program
    jsr display_boot_art

load_main_program:
    lda #game_filename_end - game_filename
    ldx #<game_filename
    ldy #>game_filename
    jsr $ffbd               // KERNAL SETNAM

    lda #LOGICAL_FILE
    ldx boot_device
    ldy #LOAD_USE_HEADER
    jsr $ffba               // KERNAL SETLFS

    ldx #0
!copy_stub:
    lda chain_stub,x
    sta CHAIN_STUB_ADDR,x
    inx
    cpx #chain_stub_end - chain_stub
    bne !copy_stub-

    lda boot_device
    sta chain_boot_device
    jmp chain_entry

// ============================================================
// Art load / display
// ============================================================
load_boot_art:
    lda #art_filename_end - art_filename
    ldx #<art_filename
    ldy #>art_filename
    jsr $ffbd               // KERNAL SETNAM

    lda #LOGICAL_FILE
    ldx boot_device
    ldy #LOAD_USE_HEADER
    jsr $ffba               // KERNAL SETLFS

    lda #0
    jsr $ffd5               // KERNAL LOAD
    php

    lda #LOGICAL_FILE
    jsr $ffc3               // CLOSE file — LOAD leaves it in the file table
    jsr $ffcc               // CLRCHN

    plp
    rts

capture_boot_device:
    lda $ba                 // KERNAL current device from LOAD/RUN path
    cmp #8
    bcc !done+
    cmp #31
    bcs !done+
    sta boot_device
!done:
    rts

display_boot_art:
    sei
    jsr copy_bitmap_to_vic_ram
    jsr copy_screen_to_vic_ram
    jsr copy_color_to_vic_ram

    lda $dd00
    and #VIC_BANK3_SELECT
    sta $dd00               // VIC bank 3 ($C000-$FFFF)

    lda #BITMAP_D018
    sta $d018               // Screen $DC00, bitmap $E000
    lda #BITMAP_D016
    sta $d016               // Multicolor bitmap mode
    lda #BITMAP_D011
    sta $d011               // Bitmap mode + screen on
    lda #0
    sta $d020
    sta $d021
    cli
    rts

copy_bitmap_to_vic_ram:
    lda #BANK_ALL_RAM
    sta $01

    lda #<ART_STAGE
    sta ZP_SRC_LO
    lda #>ART_STAGE
    sta ZP_SRC_HI
    lda #<ART_BITMAP_DEST
    sta ZP_DST_LO
    lda #>ART_BITMAP_DEST
    sta ZP_DST_HI

    ldx #ART_BITMAP_PAGES
!page_loop:
    ldy #0
!byte_loop:
    lda (ZP_SRC_LO),y
    sta (ZP_DST_LO),y
    iny
    bne !byte_loop-
    inc ZP_SRC_HI
    inc ZP_DST_HI
    dex
    bne !page_loop-

    ldy #0
!tail_loop:
    lda (ZP_SRC_LO),y
    sta (ZP_DST_LO),y
    iny
    cpy #ART_BITMAP_TAIL
    bne !tail_loop-

    lda #BANK_ALL_ROM
    sta $01
    rts

copy_screen_to_vic_ram:
    lda #BANK_ALL_RAM
    sta $01

    lda #<ART_SCREEN_STAGE
    sta ZP_SRC_LO
    lda #>ART_SCREEN_STAGE
    sta ZP_SRC_HI
    lda #<ART_SCREEN_DEST
    sta ZP_DST_LO
    lda #>ART_SCREEN_DEST
    sta ZP_DST_HI

    ldx #ART_ATTR_PAGES
!page_loop:
    ldy #0
!byte_loop:
    lda (ZP_SRC_LO),y
    sta (ZP_DST_LO),y
    iny
    bne !byte_loop-
    inc ZP_SRC_HI
    inc ZP_DST_HI
    dex
    bne !page_loop-

    ldy #0
!tail_loop:
    lda (ZP_SRC_LO),y
    sta (ZP_DST_LO),y
    iny
    cpy #ART_ATTR_TAIL
    bne !tail_loop-

    lda #BANK_ALL_ROM
    sta $01
    rts

copy_color_to_vic_ram:
    lda #BANK_NO_KERNAL
    sta $01

    lda #<ART_COLOR_STAGE
    sta ZP_SRC_LO
    lda #>ART_COLOR_STAGE
    sta ZP_SRC_HI
    lda #<ART_COLOR_DEST
    sta ZP_DST_LO
    lda #>ART_COLOR_DEST
    sta ZP_DST_HI

    ldx #ART_ATTR_PAGES
!page_loop:
    ldy #0
!byte_loop:
    lda (ZP_SRC_LO),y
    sta (ZP_DST_LO),y
    iny
    bne !byte_loop-
    inc ZP_SRC_HI
    inc ZP_DST_HI
    dex
    bne !page_loop-

    ldy #0
!tail_loop:
    lda (ZP_SRC_LO),y
    sta (ZP_DST_LO),y
    iny
    cpy #ART_ATTR_TAIL
    bne !tail_loop-

    lda #BANK_ALL_ROM
    sta $01
    rts

// ============================================================
// Chain-load stub (copied to $0340 before main LOAD)
// Everything read by !err: lives inside $0340-$03FF so a partial
// MORIA64 load over $0801+ cannot clobber error reporting.
// ============================================================
.encoding "ascii"
chain_stub:
.pseudopc CHAIN_STUB_ADDR {
chain_entry:
    lda #0
    jsr $ffd5               // KERNAL LOAD

    lda #$37
    sta $01
    lda $dd00
    ora #VIC_BANK0_SELECT
    sta $dd00
    lda #TEXT_D018
    sta $d018
    lda #TEXT_D016
    sta $d016
    lda #TEXT_D011
    sta $d011
    bcs !err+

    lda #0
    sta $d020
    sta $d021
    jmp $080E               // Jump to game entry point

!err:
    lda #$0e
    sta $d020
    sta $0286               // Light-blue text on blue background
    lda #$06
    sta $d021
    lda #LOGICAL_FILE
    jsr $ffc3               // CLOSE file after failed LOAD
    jsr $ffcc               // CLRCHN before printing/returning to BASIC
    cld
    cli

    ldx #0
!msg_loop:
    lda chain_err_msg,x
    beq !msg_done+
    cmp #1
    beq !print_dev+
    jsr $ffd2
!msg_next:
    inx
    bne !msg_loop-

!print_dev:
    lda chain_boot_device
    ldy #$2f                // '0' - 1
!tens:
    iny
    sec
    sbc #10
    bcs !tens-
    adc #10 + $30           // remainder -> PETSCII '0'..'9' (C=0)
    pha
    tya
    cmp #$30                // suppress leading '0' for devices 8..9
    beq !ones+
    jsr $ffd2
!ones:
    pla
    jsr $ffd2
    jmp !msg_next-

!msg_done:
    ldx #$ff
    txs
    jmp ($A002)             // BASIC warm start on error

chain_boot_device:
    .byte DEVICE_NUM

chain_err_msg:
    .byte $93               // CLR/HOME
    .text "?LOAD ERROR: MORIA64 (DEV "
    .byte 1                 // print decimal chain_boot_device
    .text ")"
    .byte $0d
    .text "CHECK BOOT DISK ON DRIVE "
    .byte 1                 // print decimal chain_boot_device
    .text "."
    .byte $0d, 0
}
chain_stub_end:

.assert "C64 boot chain stub fits in $0340-$03FF", chain_stub_end - chain_stub <= CHAIN_STUB_MAX, true

// ============================================================
// Data
// ============================================================
art_filename:
    .byte $42, $4F, $4F, $54, $41, $52, $54, $36, $34   // "BOOTART64"
art_filename_end:

game_filename:
    .byte $4D, $4F, $52, $49, $41, $36, $34             // "MORIA64"
game_filename_end:

boot_device:
    .byte DEVICE_NUM
