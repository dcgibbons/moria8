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

.const ZP_SRC_LO        = $FB
.const ZP_SRC_HI        = $FC
.const ZP_DST_LO        = $FD
.const ZP_DST_HI        = $FE

.pc = $080E "Boot"
boot_entry:
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
    ldx #DEVICE_NUM
    ldy #LOAD_USE_HEADER
    jsr $ffba               // KERNAL SETLFS

    ldx #chain_stub_end - chain_stub - 1
!copy_stub:
    lda chain_stub,x
    sta $0340,x
    dex
    bpl !copy_stub-

    jmp $0340

// ============================================================
// Art load / display
// ============================================================
load_boot_art:
    lda #art_filename_end - art_filename
    ldx #<art_filename
    ldy #>art_filename
    jsr $ffbd               // KERNAL SETNAM

    lda #LOGICAL_FILE
    ldx #DEVICE_NUM
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
// ============================================================
chain_stub:
    lda #0
    jsr $ffd5               // KERNAL LOAD
    bcs !err+

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
    lda #0
    sta $d020
    sta $d021
    jmp $080E               // Jump to game entry point

!err:
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
    jmp ($A002)             // BASIC warm start on error
chain_stub_end:

// ============================================================
// Data
// ============================================================
art_filename:
    .byte $42, $4F, $4F, $54, $41, $52, $54, $36, $34   // "BOOTART64"
art_filename_end:

game_filename:
    .byte $4D, $4F, $52, $49, $41, $36, $34             // "MORIA64"
game_filename_end:
