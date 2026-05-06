// boot.s — Chain-loading bootloader for Moria8 Plus/4

.pc = $1001 "BASIC Stub"
.word basic_stub_end
.word 10
.byte $9e
.text "4110"
.byte 0
basic_stub_end:
.word 0

.pc = $100e "Boot"

.const LOGICAL_FILE    = 2
.const DEVICE_NUM      = 8
.const LOAD_USE_HEADER = 1
.const TED_BG          = $ff15
.const TED_BORDER      = $ff19

boot_entry:
    lda #0
    sta TED_BG
    sta TED_BORDER
    lda #$93
    jsr $ffd2

    jsr load_boot_art

load_main_program:
    lda #game_filename_end - game_filename
    ldx #<game_filename
    ldy #>game_filename
    jsr $ffbd
    lda #LOGICAL_FILE
    ldx #DEVICE_NUM
    ldy #LOAD_USE_HEADER
    jsr $ffba

    ldx #chain_stub_end - chain_stub - 1
!copy_stub:
    lda chain_stub,x
    sta $0340,x
    dex
    bpl !copy_stub-
    jmp $0340

load_boot_art:
    lda #art_filename_end - art_filename
    ldx #<art_filename
    ldy #>art_filename
    jsr $ffbd
    lda #LOGICAL_FILE
    ldx #DEVICE_NUM
    ldy #LOAD_USE_HEADER
    jsr $ffba
    lda #0
    jsr $ffd5
    php
    lda #LOGICAL_FILE
    jsr $ffc3
    jsr $ffcc
    plp
    rts

chain_stub:
    lda #0
    jsr $ffd5
    bcs !err+
    jmp $100e
!err:
    lda #$93
    jsr $ffd2
    ldx #0
!msg:
    lda load_error_msg,x
    beq !spin+
    jsr $ffd2
    inx
    bne !msg-
!spin:
    jmp !spin-
chain_stub_end:

art_filename:
    .byte $42,$4f,$4f,$54,$41,$52,$54,$34  // "BOOTART4"
art_filename_end:

game_filename:
    .byte $4d,$4f,$52,$49,$41,$34          // "MORIA4"
game_filename_end:

load_error_msg:
    .byte $4c,$4f,$41,$44,$20,$45,$52,$52,$4f,$52
    .byte 0
